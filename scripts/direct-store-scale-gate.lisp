;;;; Direct RocksDB provider bounded-RSS/restart acceptance gate.
;;;;
;;;; Run only inside the memory-limited Docker target in the Makefile.  SEED
;;;; streams an incompressible logical database larger than the container's
;;;; RAM without retaining the records in Lisp.  OPEN starts a fresh SBCL,
;;;; constructs the production provider, and rejects startup RSS/time that
;;;; scale with the database.

(defparameter *scale-gate-process-start*
  (get-internal-real-time))

(defparameter *scale-gate-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defparameter *scale-gate-account-address*
  "0x0000000000000000000000000000000000000042")

(defparameter *scale-gate-storage-slot*
  "0x0000000000000000000000000000000000000000000000000000000000000009")

(defparameter *scale-gate-account-code*
  #(#x60 #x09 #x60 #x00 #x55))

(require :asdf)
(asdf:load-asd (merge-pathnames "ethereum-lisp.asd" *scale-gate-root*))
(asdf:load-system :ethereum-lisp)

(defun scale-gate-positive-integer (text label)
  (let ((value (parse-integer text :junk-allowed nil)))
    (unless (plusp value)
      (error "~A must be positive" label))
    value))

(defun scale-gate-process-rss-bytes ()
  (with-open-file (input "/proc/self/status")
    (loop for line = (read-line input nil nil)
          while line
          when (and (<= 6 (length line))
                    (string= "VmRSS:" line :end2 6))
            do (return
                 (* 1024
                    (parse-integer line :start 6 :junk-allowed t)))
          finally (error "Linux /proc/self/status has no VmRSS field"))))

(defun scale-gate-elapsed-seconds ()
  (/ (- (get-internal-real-time) *scale-gate-process-start*)
     (coerce internal-time-units-per-second 'double-float)))

(defun scale-gate-random-value (size)
  "Build one deterministic incompressible value; records reuse it serially."
  (let ((value (ethereum-lisp.bytes:make-byte-vector size))
        (word #x9e3779b9))
    (dotimes (index size value)
      ;; xorshift32, masked explicitly because Common Lisp integers do not
      ;; overflow.  This is test data, not cryptographic randomness.
      (setf word (logand #xffffffff (logxor word (ash word 13)))
            word (logand #xffffffff (logxor word (ash word -17)))
            word (logand #xffffffff (logxor word (ash word 5)))
            (aref value index) (logand word #xff)))))

(defun scale-gate-seed-canonical-state (database)
  "Write a real canonical head whose state can be point-read after restart."
  (let* ((store (ethereum-lisp:make-engine-payload-memory-store))
         (state (ethereum-lisp:make-state-db))
         (address
           (ethereum-lisp:address-from-hex *scale-gate-account-address*))
         (slot (ethereum-lisp:hash32-from-hex *scale-gate-storage-slot*)))
    (ethereum-lisp:state-db-set-account
     state address
     (ethereum-lisp:make-state-account :nonce 7 :balance 12345))
    (ethereum-lisp:state-db-set-code
     state address *scale-gate-account-code*)
    (ethereum-lisp:state-db-set-storage state address slot 987654)
    (let* ((root (ethereum-lisp:state-db-root state))
           (block
             (ethereum-lisp:make-block
              :header
              (ethereum-lisp:make-block-header
               :number 0
               :parent-hash (ethereum-lisp:zero-hash32)
               :state-root root
               :timestamp 0
               :gas-limit 30000000))))
      (ethereum-lisp:chain-store-put-block
       store block :state-available-p t)
      (ethereum-lisp:commit-state-db-to-chain-store
       store (ethereum-lisp:block-hash block) state)
      (ethereum-lisp:chain-store-update-forkchoice-checkpoints
       store
       (ethereum-lisp:make-forkchoice-state
        :head-block-hash (ethereum-lisp:block-hash block)
        :safe-block-hash (ethereum-lisp:block-hash block)
        :finalized-block-hash (ethereum-lisp:block-hash block)))
      (ethereum-lisp:node-store-export-to-kv store database))))

(defun scale-gate-seed (path record-count value-size memory-limit)
  (let ((logical-size (* record-count value-size)))
    (unless (> logical-size memory-limit)
      (error "Logical dataset ~D is not larger than RAM limit ~D"
             logical-size memory-limit))
    (let ((database
            (ethereum-lisp.database:make-rocksdb-key-value-database path))
          (value (scale-gate-random-value value-size)))
      (unwind-protect
           (progn
             ;; A checkpointed block makes the measured restart take the real
             ;; production startup branch.  Without it, an implementation that
             ;; hydrates only when a durable head exists could pass this gate by
             ;; opening an effectively empty chain around the large namespace.
             (scale-gate-seed-canonical-state database)
             ;; Use a real schema namespace rather than arbitrary unknown keys.
             ;; Each 16 KiB body is within the deployed-code size limit and is
             ;; filed under its Keccak content address.  Bounded seed batches
             ;; avoid one WAL sync per record without retaining the 512 MiB
             ;; logical dataset in Lisp.
             (loop for first from 0 below record-count by 128
                   for batch = (ethereum-lisp.database:make-kv-write-batch)
                   do (loop for index from first
                              below (min record-count (+ first 128))
                            do
                               ;; Make every record distinct without allocating
                               ;; another value-sized vector. Snappy still sees
                               ;; pseudo-random, incompressible record bodies.
                               (dotimes (offset (min 8 value-size))
                                 (setf (aref value offset)
                                       (ldb (byte 8 (* 8 offset)) index)))
                               (ethereum-lisp.database:kv-batch-put-chain-record
                                batch
                                :code
                                (ethereum-lisp.types:hash32-bytes
                                 (ethereum-lisp.crypto:keccak-256-hash value))
                                value))
                      (ethereum-lisp.database:kv-apply-batch database batch))
             (format t
                     "SEEDED logical_bytes=~D ram_limit_bytes=~D bulk_code_records=~D canonical_blocks=1~%"
                     logical-size memory-limit record-count))
        (ethereum-lisp.database:close-rocksdb-key-value-database database)))))

(defun scale-gate-open (path maximum-rss maximum-seconds)
  (let ((provider-start (get-internal-real-time))
        (database nil))
    (unwind-protect
         (progn
           (setf database
                 (ethereum-lisp.database:make-rocksdb-key-value-database
                  path :create-if-missing-p nil))
           (let* ((store
                    (ethereum-lisp.node-store.persistence:make-database-engine-payload-store
                     database))
                  (block (ethereum-lisp:chain-store-block-by-number store 0))
                  (address
                    (ethereum-lisp:address-from-hex
                     *scale-gate-account-address*))
                  (slot
                    (ethereum-lisp:hash32-from-hex
                     *scale-gate-storage-slot*))
                  (state
                    (and block
                         (ethereum-lisp:chain-store-state-db
                          store (ethereum-lisp:block-hash block)))))
             (unless
                 (ethereum-lisp.node-store.persistence:database-engine-payload-store-p
                  store)
               (error "Scale gate did not construct the direct provider"))
             (unless (and block
                          (= 0 (ethereum-lisp:chain-store-head-number store)))
               (error "Scale gate did not open its persisted canonical head"))
             (unless state
               (error "Scale gate did not open its persisted account trie"))
             (let ((account (ethereum-lisp:state-db-get-account state address)))
               (unless (and account
                            (= 7 (ethereum-lisp:state-account-nonce account))
                            (= 12345
                               (ethereum-lisp:state-account-balance account)))
                 (error "Scale gate account point read returned wrong state")))
             (unless (ethereum-lisp:bytes=
                      *scale-gate-account-code*
                      (ethereum-lisp:state-db-get-code state address))
               (error "Scale gate code point read returned wrong state"))
             (unless (= 987654
                        (ethereum-lisp:state-db-get-storage
                         state address slot))
               (error "Scale gate storage point read returned wrong state"))
             ;; Measure only after the real persisted account/code/storage
             ;; reads. A provider that defers whole-state hydration until the
             ;; first account access must fail the same RSS/time bounds.
             (let ((provider-seconds
                     (/ (- (get-internal-real-time) provider-start)
                        (coerce internal-time-units-per-second 'double-float)))
                   (process-seconds (scale-gate-elapsed-seconds))
                   (rss (scale-gate-process-rss-bytes)))
               (when (>= rss maximum-rss)
                 (error "Restart RSS ~D exceeds bound ~D" rss maximum-rss))
               (when (>= process-seconds maximum-seconds)
                 (error "Restart time ~,3Fs exceeds bound ~,3Fs"
                        process-seconds maximum-seconds))
               (format t
                       "OPEN_OK rss_bytes=~D process_seconds=~,3F provider_seconds=~,3F~%"
                       rss process-seconds provider-seconds))))
      (when database
        (ethereum-lisp.database:close-rocksdb-key-value-database database)))))

(let ((arguments (cdr sb-ext:*posix-argv*)))
  (unless arguments
    (error "usage: direct-store-scale-gate.lisp seed|open ..."))
  (cond
    ((string= (first arguments) "seed")
     (unless (= 5 (length arguments))
       (error "usage: ... seed PATH RECORD-COUNT VALUE-SIZE MEMORY-LIMIT"))
     (scale-gate-seed
      (second arguments)
      (scale-gate-positive-integer (third arguments) "record count")
      (scale-gate-positive-integer (fourth arguments) "value size")
      (scale-gate-positive-integer (fifth arguments) "memory limit")))
    ((string= (first arguments) "open")
     (unless (= 4 (length arguments))
       (error "usage: ... open PATH MAXIMUM-RSS MAXIMUM-SECONDS"))
     (scale-gate-open
      (second arguments)
      (scale-gate-positive-integer (third arguments) "maximum RSS")
      (scale-gate-positive-integer (fourth arguments) "maximum seconds")))
    (t
     (error "Unknown direct-store scale gate mode: ~A" (first arguments)))))
