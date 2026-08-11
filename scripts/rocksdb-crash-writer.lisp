;;;; RocksDB crash-injection helper.
;;;;
;;;; Each mode writes WAL-synced data into the requested RocksDB directory,
;;;; publishes a readable marker only after the final commit returns, and then
;;;; blocks forever.  It deliberately never closes the database: the parent
;;;; test SIGKILLs this process so reopening exercises crash recovery rather
;;;; than a clean shutdown.  See the crash tests in tests/database-tests.lisp.

(defparameter *root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(require :asdf)
(asdf:load-asd (merge-pathnames "ethereum-lisp.asd" *root*))
(asdf:load-system :ethereum-lisp)

(defun rocksdb-crash-writer-publish-marker (marker value)
  (with-open-file (out marker :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
    (let ((*print-readably* t))
      (write value :stream out)
      (terpri out)
      (finish-output out)))
  value)

(defun rocksdb-crash-writer-raw-batch (database marker)
  (let ((batch (ethereum-lisp.database:make-kv-write-batch)))
    (dotimes (i 16)
      (ethereum-lisp.database:kv-batch-put
       batch (vector i) (vector (+ 100 i))))
    ;; RocksDB write-options use sync=1, so returning proves the whole batch is
    ;; durable in the WAL before the marker becomes visible.
    (ethereum-lisp.database:kv-apply-batch database batch)
    (rocksdb-crash-writer-publish-marker
     marker '(:mode :raw-batch :count 16))))

(defun rocksdb-crash-writer-peer-id ()
  (let ((peer-id (ethereum-lisp:make-byte-vector 64)))
    (dotimes (index (length peer-id) peer-id)
      (setf (aref peer-id index) (mod (+ 41 index) 256)))))

(defun rocksdb-crash-writer-empty-child (parent parent-state config)
  (let ((state (ethereum-lisp:state-db-copy parent-state)))
    (values
     (ethereum-lisp:execute-signed-block
      state '()
      :expected-chain-id 1
      :header
      (ethereum-lisp:make-block-header
       :parent-hash (ethereum-lisp:block-hash parent)
       :beneficiary (ethereum-lisp:zero-address)
       :mix-hash (ethereum-lisp:zero-hash32)
       :number
       (1+ (ethereum-lisp:block-header-number
            (ethereum-lisp:block-header parent)))
       :gas-limit 30000000
       :timestamp
       (1+ (ethereum-lisp:block-header-timestamp
            (ethereum-lisp:block-header parent)))
       :base-fee-per-gas
       (ethereum-lisp:expected-base-fee-per-gas
        (ethereum-lisp:block-header parent)))
      :chain-config config
      :withdrawals '())
     state)))

(defun rocksdb-crash-writer-peer-sync-candidates (database marker)
  (let* ((chain-id 1)
         (balance 424242)
         (account
           (ethereum-lisp:address-from-hex
            "0x00000000000000000000000000000000000000cc"))
         (authority-id
           (ethereum-lisp:make-hash32
            (ethereum-lisp:make-byte-vector 32 :initial-element 77)))
         (peer-id (rocksdb-crash-writer-peer-id))
         (config
           (ethereum-lisp:make-chain-config
            :chain-id chain-id
            :byzantium-block 0
            :constantinople-block 0
            :petersburg-block 0
            :berlin-block 0
            :london-block 0
            :shanghai-time 0))
         (genesis-state (ethereum-lisp:make-state-db)))
    (ethereum-lisp:state-db-set-account
     genesis-state account
     (ethereum-lisp:make-state-account :nonce 0 :balance balance))
    (let* ((genesis
             (ethereum-lisp:make-block
              :header
              (ethereum-lisp:make-block-header
               :parent-hash (ethereum-lisp:zero-hash32)
               :beneficiary (ethereum-lisp:zero-address)
               :state-root (ethereum-lisp:state-db-root genesis-state)
               :mix-hash (ethereum-lisp:zero-hash32)
               :number 0
               :gas-limit 30000000
               :timestamp 0
               :base-fee-per-gas 1000000000)
              :withdrawals '()))
           (store (ethereum-lisp:make-engine-payload-memory-store)))
      (multiple-value-bind (parent parent-state)
          (rocksdb-crash-writer-empty-child genesis genesis-state config)
        (multiple-value-bind (first-candidate first-candidate-state)
            (rocksdb-crash-writer-empty-child parent parent-state config)
          (multiple-value-bind (last-candidate last-candidate-state)
              (rocksdb-crash-writer-empty-child
               first-candidate first-candidate-state config)
            (declare (ignore last-candidate-state))
            (ethereum-lisp:engine-payload-store-put-block
             store genesis :state-available-p t)
            (ethereum-lisp:commit-state-db-to-chain-store
             store (ethereum-lisp:block-hash genesis) genesis-state)
            (ethereum-lisp:engine-payload-store-put-block
             store parent :state-available-p t)
            (ethereum-lisp:commit-state-db-to-chain-store
             store (ethereum-lisp:block-hash parent) parent-state)
            (ethereum-lisp:chain-store-set-canonical-head
             store (ethereum-lisp:block-hash parent)
             :expected-chain-id chain-id
             :chain-config config)
            (ethereum-lisp:chain-store-update-forkchoice-checkpoints
             store
             (ethereum-lisp:make-forkchoice-state
              :head-block-hash (ethereum-lisp:block-hash parent)
              :safe-block-hash (ethereum-lisp:block-hash genesis)
              :finalized-block-hash (ethereum-lisp:block-hash genesis)))
            (ethereum-lisp.node-store.persistence:node-store-export-to-kv
             store database
             :persistence-metadata
             (ethereum-lisp.node-store.persistence:make-node-store-persistence-metadata
              :role :database
              :generation 0
              :base-chain-generation 0
              :chain-id chain-id
              :genesis-hash (ethereum-lisp:block-hash genesis)
              :authority-id authority-id))
            (labels
                ((progress-for (block)
                   (ethereum-lisp.node-store.persistence:make-node-store-peer-sync-progress
                    :peer-id peer-id
                    :authority-id authority-id
                    :chain-id chain-id
                    :genesis-hash (ethereum-lisp:block-hash genesis)
                    :last-number
                    (ethereum-lisp:block-header-number
                     (ethereum-lisp:block-header block))
                    :last-hash (ethereum-lisp:block-hash block)))
                 (import-and-persist (block)
                   (let ((progress (progress-for block)))
                     (multiple-value-bind (status candidate)
                         (ethereum-lisp:import-p2p-block-candidate
                          store block config
                          :progress progress
                          :durability-function
                          (lambda (candidate-store durable-candidate
                                   &key source candidate-kind payload-status
                                        progress)
                            (declare (ignore payload-status))
                            (unless (and (eq source :p2p)
                                         (eq candidate-kind :executed))
                              (error
                               "Peer-sync candidate durability callback lost its import provenance"))
                            (ethereum-lisp.node-store.persistence:node-store-export-payload-candidate-to-kv
                             candidate-store durable-candidate database
                             :peer-sync-progress progress)))
                       (unless (and candidate
                                    (string=
                                     ethereum-lisp:+payload-status-valid+
                                     (ethereum-lisp:payload-status-status
                                      status)))
                         (error
                          "Peer-sync crash candidate did not pass the production P2P import boundary"))))))
              (import-and-persist first-candidate)
              ;; Prove that the first exporter invocation committed its cursor
              ;; before advancing to the second candidate.
              (multiple-value-bind (first-progress present-p)
                  (ethereum-lisp.node-store.persistence:node-store-read-peer-sync-progress
                   database peer-id)
                (unless (and present-p
                             (ethereum-lisp:hash32=
                              (ethereum-lisp:block-hash first-candidate)
                              (ethereum-lisp.node-store.persistence:node-store-peer-sync-progress-last-hash
                               first-progress)))
                  (error "First peer-sync candidate cursor was not durable")))
              (import-and-persist last-candidate))
            ;; This marker is published only after the second candidate and its
            ;; cursor returned from the exporter's single WAL-synced batch.
            (rocksdb-crash-writer-publish-marker
             marker
             (list
              :mode :peer-sync-candidates
              :peer-id (ethereum-lisp:bytes-to-hex peer-id)
              :genesis-hash
              (ethereum-lisp:hash32-to-hex
               (ethereum-lisp:block-hash genesis))
              :parent-hash
              (ethereum-lisp:hash32-to-hex
               (ethereum-lisp:block-hash parent))
              :parent-number
              (ethereum-lisp:block-header-number
               (ethereum-lisp:block-header parent))
              :first-candidate-hash
              (ethereum-lisp:hash32-to-hex
               (ethereum-lisp:block-hash first-candidate))
              :last-candidate-hash
              (ethereum-lisp:hash32-to-hex
               (ethereum-lisp:block-hash last-candidate))
              :last-candidate-number
              (ethereum-lisp:block-header-number
               (ethereum-lisp:block-header last-candidate))
              :account (ethereum-lisp:address-to-hex account)
              :balance balance))))))))

(defun rocksdb-crash-writer-arguments ()
  (let ((args (cdr sb-ext:*posix-argv*)))
    (unless (= 3 (length args))
      (error
       "usage: rocksdb-crash-writer.lisp MODE DIRECTORY MARKER"))
    (values (first args) (second args) (third args))))

(multiple-value-bind (mode path marker)
    (rocksdb-crash-writer-arguments)
  (let ((database
          (ethereum-lisp.database:make-rocksdb-key-value-database path)))
    (cond
      ((string= mode "raw-batch")
       (rocksdb-crash-writer-raw-batch database marker))
      ((string= mode "peer-sync-candidates")
       (rocksdb-crash-writer-peer-sync-candidates database marker))
      (t
       (error "Unknown RocksDB crash-writer mode ~S" mode)))
    ;; Keep the open handle live while the parent prepares SIGKILL.  No unwind
    ;; cleanup closes it, because a crash does not get a graceful shutdown.
    (loop
      (sleep 3600)
      (unless database
        (error "RocksDB crash-writer database disappeared")))))
