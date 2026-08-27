(in-package #:ethereum-lisp.test)

(defvar *snap-test-buffered-apply-p* nil)

(defclass snap-failing-test-database (memory-key-value-database)
  ((fail-next-apply-p
    :initform nil
    :accessor snap-failing-test-database-fail-next-apply-p)
   (fail-next-buffered-apply-p
    :initform nil
    :accessor snap-failing-test-database-fail-next-buffered-apply-p)))

(defmethod kv-apply-batch :around
    ((database snap-failing-test-database) (batch kv-write-batch))
  (if (and (not *snap-test-buffered-apply-p*)
           (snap-failing-test-database-fail-next-apply-p database))
      (progn
        (setf (snap-failing-test-database-fail-next-apply-p database) nil)
        (error "Simulated snap progress batch failure"))
      (call-next-method)))

(defmethod kv-apply-batch-buffered :around
    ((database snap-failing-test-database) (batch kv-write-batch))
  (if (snap-failing-test-database-fail-next-buffered-apply-p database)
      (progn
        (setf
         (snap-failing-test-database-fail-next-buffered-apply-p database)
         nil)
        (error "Simulated snap buffered batch failure"))
      ;; The memory backend implements buffered writes through KV-APPLY-BATCH.
      ;; Preserve that oracle's atomic visibility without consuming a failure
      ;; that production RocksDB would encounter only at the later synchronous
      ;; seam.
      (let ((*snap-test-buffered-apply-p* t))
        (call-next-method))))

(defclass snap-counting-test-database (memory-key-value-database)
  ((apply-count :initform 0 :accessor snap-counting-test-database-apply-count)
   (buffered-apply-count
    :initform 0
    :accessor snap-counting-test-database-buffered-apply-count)
   (buffered-batch-sizes
    :initform '()
    :accessor snap-counting-test-database-buffered-batch-sizes)
   (batch-sizes :initform '()
                :accessor snap-counting-test-database-batch-sizes)
   (batch-prefixes :initform '()
                   :accessor snap-counting-test-database-batch-prefixes)))

(defmethod kv-apply-batch :around
    ((database snap-counting-test-database) (batch kv-write-batch))
  (incf (snap-counting-test-database-apply-count database))
  (push (length (ethereum-lisp.database::kv-write-batch-operations batch))
        (snap-counting-test-database-batch-sizes database))
  (push
   (mapcar
    (lambda (operation) (aref (second operation) 0))
    (reverse
     (ethereum-lisp.database::kv-write-batch-operations batch)))
   (snap-counting-test-database-batch-prefixes database))
  (call-next-method))

(defmethod kv-apply-batch-buffered :around
    ((database snap-counting-test-database) (batch kv-write-batch))
  (incf (snap-counting-test-database-buffered-apply-count database))
  (push (length (ethereum-lisp.database::kv-write-batch-operations batch))
        (snap-counting-test-database-buffered-batch-sizes database))
  (call-next-method))

(defun snap-test-hash (byte)
  (make-array 32 :element-type '(unsigned-byte 8) :initial-element byte))

(defun snap-test-index-hash (index)
  (let ((hash (make-byte-vector 32)))
    (dotimes (offset 4 hash)
      (setf (aref hash (- 31 offset))
            (ldb (byte 8 (* 8 offset)) index)))))

(defun snap-test-install-persistence-metadata
    (database chain-id genesis-hash authority-id)
  (let ((batch (make-kv-write-batch)))
    (ethereum-lisp.node-store.persistence::node-store-populate-persistence-metadata-batch
     batch
     (ethereum-lisp.node-store.persistence:make-node-store-persistence-metadata
      :role :database :generation 1 :chain-id chain-id
      :genesis-hash genesis-hash :authority-id authority-id
      :base-chain-generation 1))
    (kv-apply-batch database batch))
  database)

(deftest snap-verified-range-records-write-without-database-reads
  (:layer :unit :module :p2p)
  (let* ((database (make-memory-key-value-database))
         (count (1+ ethereum-lisp.database:+kv-get-many-max-keys+))
         (records
           (loop for index below count
                 for encoded = (rlp-encode index)
                 collect (cons (keccak-256 encoded) encoded)))
         (code (hex-to-bytes "60006000f3"))
         (codes (list (cons (keccak-256 code) code)))
         (real-get-many
           (fdefinition 'ethereum-lisp.database:kv-get-chain-records))
         (real-get
           (fdefinition 'ethereum-lisp.database:kv-get-chain-record))
         (get-many-calls 0)
         (get-calls 0)
         (batch (make-kv-write-batch)))
    ;; A state-root-authenticated record is authoritative for its content hash.
    ;; Plant a corrupt local value so the test proves both the no-read hot path
    ;; and its repair semantics, not merely insertion into an empty store.
    (kv-put-chain-record
     database :trie-node (caar records) (rlp-encode "corrupt"))
    (kv-put-chain-record database :code (caar codes) #(255))
    (unwind-protect
         (progn
           (setf
            (fdefinition 'ethereum-lisp.database:kv-get-chain-records)
            (lambda (candidate kind identifiers &optional default)
              (declare (ignore candidate kind identifiers default))
              (incf get-many-calls)
              (error "Verified SNAP range performed a database MultiGet")))
           (setf
            (fdefinition 'ethereum-lisp.database:kv-get-chain-record)
            (lambda (candidate kind identifier &optional default)
              (declare (ignore candidate kind identifier default))
              (incf get-calls)
              (error "Verified SNAP range performed a database point Get")))
           (ethereum-lisp.snap-sync::snap-sync-populate-verified-trie-records-batch
            database batch records)
           (ethereum-lisp.snap-sync::snap-sync-populate-code-batch
            database batch codes)
           (kv-apply-batch database batch))
      (setf (fdefinition 'ethereum-lisp.database:kv-get-chain-records)
            real-get-many)
      (setf (fdefinition 'ethereum-lisp.database:kv-get-chain-record)
            real-get))
    (is (zerop get-many-calls))
    (is (zerop get-calls))
    (multiple-value-bind (value present-p)
        (kv-get-chain-record database :code (caar codes))
      (is present-p)
      (is (bytes= value code)))
    (signals error
      (ethereum-lisp.snap-sync::snap-sync-populate-code-batch
       database (make-kv-write-batch)
       (list (cons (make-byte-vector 32) code))))
    (dolist (index (list 0 (1- count)))
      (multiple-value-bind (value present-p)
          (kv-get-chain-record database :trie-node (car (nth index records)))
        (is present-p)
        (is (bytes= value (cdr (nth index records))))))))

(defun snap-test-address-from-integer (value)
  (let* ((minimal (integer-to-minimal-bytes value))
         (bytes (make-byte-vector 20)))
    (replace bytes minimal :start1 (- 20 (length minimal)))
    (make-address bytes)))

(defun snap-test-partitioned-state ()
  "Return a state with at least one account in every high-nibble hash range."
  (let ((state (make-state-db))
        (seen (make-array 16 :initial-element nil))
        (addresses '())
        (found 0))
    (loop for candidate from 1
          until (= found 16)
          do (let* ((address (snap-test-address-from-integer candidate))
                    (hash (keccak-256 (address-bytes address)))
                    (partition (ash (aref hash 0) -4)))
               (unless (aref seen partition)
                 (setf (aref seen partition) t)
                 (incf found)
                 (push address addresses)
                 (state-db-set-account
                  state address
                  (make-state-account
                   :nonce candidate :balance (+ 1000 candidate))))))
    (values state (nreverse addresses))))

(defun snap-test-source-with-account-callback (base-source callback)
  (ethereum-lisp.snap-sync:make-snap-sync-source
   :account-range callback
   :storage-ranges
   (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges base-source)
   :bytecodes (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base-source)
   :trie-nodes
   (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes base-source)))

(defun snap-test-round-trip (message-id packet)
  (ethereum-lisp.snap:decode-snap-message
   message-id
   (ethereum-lisp.snap:encode-snap-message message-id packet)))

(defun snap-test-call-backend (backend message-id request)
  (multiple-value-bind (response-id encoded)
      (ethereum-lisp.snap:snap-serve-request
       backend message-id
       (ethereum-lisp.snap:encode-snap-message message-id request))
    (ethereum-lisp.snap:decode-snap-message response-id encoded)))

(defun snap-test-source (backend)
  (ethereum-lisp.snap-sync:make-snap-sync-source
   :account-range
   (lambda (request)
     (snap-test-call-backend
      backend ethereum-lisp.snap:+snap-message-get-account-range+ request))
   :storage-ranges
   (lambda (request)
     (snap-test-call-backend
      backend ethereum-lisp.snap:+snap-message-get-storage-ranges+ request))
   :bytecodes
   (lambda (request)
     (snap-test-call-backend
      backend ethereum-lisp.snap:+snap-message-get-bytecodes+ request))
   :trie-nodes
   (lambda (request)
     (snap-test-call-backend
      backend ethereum-lisp.snap:+snap-message-get-trie-nodes+ request))))

(deftest snap-bytecode-requests-use-geth-sized-hash-batches
  (:layer :unit :module :p2p)
  (let* ((codes
           (loop for index below 170
                 collect (snap-test-index-hash index)))
         (hashes (mapcar #'keccak-256 codes))
         (codes-by-hash (make-hash-table :test #'equalp))
         (request-sizes '())
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :bytecodes
            (lambda (request)
              (let ((requested
                      (ethereum-lisp.snap:snap-get-bytecodes-hashes request)))
                (push (length requested) request-sizes)
                (ethereum-lisp.snap:make-snap-bytecodes
                 1
                 (mapcar
                  (lambda (hash) (copy-seq (gethash hash codes-by-hash)))
                  requested)))))))
    (loop for code in codes
          for hash in hashes
          do (setf (gethash hash codes-by-hash) code))
    (let ((fetched
            (ethereum-lisp.snap-sync::snap-sync-fetch-codes
             source hashes (* 512 1024))))
      (is (equal '(84 84 2) (nreverse request-sizes)))
      (is (= 170 (length fetched)))
      (is (every
           (lambda (entry)
             (bytes= (car entry) (keccak-256 (cdr entry))))
           fetched)))))

(deftest snap-empty-bytecode-response-is-state-unavailable
  (:layer :unit :module :p2p)
  (let* ((code #(96 0 96 0))
         (hash (keccak-256 code))
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :bytecodes
            (lambda (request)
              (ethereum-lisp.snap:make-snap-bytecodes
               (ethereum-lisp.snap:snap-get-bytecodes-id request) '())))))
    ;; An empty response is geth's stateless-peer signal, not an ordinary
    ;; transport failure that may re-enter the dependency pool after cooldown.
    (signals ethereum-lisp.snap-sync:snap-sync-state-unavailable
      (ethereum-lisp.snap-sync::snap-sync-fetch-codes
       source (list hash) (* 512 1024)))))

(deftest snap-multi-code-flight-deduplicates-pending-pages
  (:layer :unit :module :p2p)
  #+sbcl
  (let* ((database (make-memory-key-value-database))
         (runtime
           (ethereum-lisp.snap-sync::make-snap-sync-multi-runtime nil 0 nil))
         (code (snap-test-index-hash 5))
         (hash (keccak-256 code))
         (entered (sb-thread:make-semaphore :count 0))
         (release (sb-thread:make-semaphore :count 0))
         (lock (sb-thread:make-mutex :name "snap-test-code-flight"))
         (calls 0)
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :bytecodes
            (lambda (request)
              (sb-thread:with-mutex (lock) (incf calls))
              (sb-thread:signal-semaphore entered)
              (sb-thread:wait-on-semaphore release :timeout 5)
              (ethereum-lisp.snap:make-snap-bytecodes
               (ethereum-lisp.snap:snap-get-bytecodes-id request)
               (list code)))))
         (first-thread nil)
         (second-thread nil))
    (flet ((fetch ()
             (ethereum-lisp.snap-sync::snap-sync-multi-fetch-page-codes
              runtime database source (list hash) (* 512 1024))))
      (unwind-protect
           (progn
             (setf first-thread
                   (sb-thread:make-thread
                    #'fetch :name "snap-test-code-flight-owner"))
             (is (sb-thread:wait-on-semaphore entered :timeout 5))
             (setf second-thread
                   (sb-thread:make-thread
                    #'fetch :name "snap-test-code-flight-waiter"))
             (is (eq :blocked
                     (sb-thread:join-thread
                      second-thread :timeout 0.1 :default :blocked)))
             (sb-thread:signal-semaphore release)
             (is (not (eq :timeout
                          (sb-thread:join-thread
                           first-thread :timeout 5 :default :timeout))))
             (setf first-thread nil)
             (is (not (eq :timeout
                          (sb-thread:join-thread
                           second-thread :timeout 5 :default :timeout))))
             (setf second-thread nil)
             (is (= 1 calls))
             (multiple-value-bind (stored present-p)
                 (kv-get-chain-record database :code hash)
               (is present-p)
               (is (bytes= code stored))))
        (sb-thread:signal-semaphore release)
        (when first-thread
          (ignore-errors
            (sb-thread:join-thread first-thread :timeout 5 :default nil)))
        (when second-thread
          (ignore-errors
            (sb-thread:join-thread second-thread :timeout 5 :default nil))))))
  #-sbcl
  (is t))

#+sbcl
(deftest snap-multi-bytecodes-use-one-fixed-global-worker-pool
  (:layer :unit :module :p2p)
  (is (= 32 ethereum-lisp.snap-sync::+snap-sync-global-code-workers+))
  (let* ((database (make-memory-key-value-database))
         (runtime
           (ethereum-lisp.snap-sync::make-snap-sync-multi-runtime nil 0 nil))
         (codes
           (loop for index below 340
                 collect (snap-test-index-hash (+ 4000 index))))
         (hashes (mapcar #'keccak-256 codes))
         (codes-by-hash (make-hash-table :test #'equalp))
         (lock (sb-thread:make-mutex :name "snap-global-code-test"))
         (active 0)
         (maximum-active 0)
         (calls 0)
         (workers '())
         (page-threads '())
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :bytecodes
            (lambda (request)
              (sb-thread:with-mutex (lock)
                (incf calls)
                (incf active)
                (setf maximum-active (max maximum-active active)))
              (sleep 0.05)
              (prog1
                  (ethereum-lisp.snap:make-snap-bytecodes
                   (ethereum-lisp.snap:snap-get-bytecodes-id request)
                   (mapcar
                    (lambda (hash) (copy-seq (gethash hash codes-by-hash)))
                    (ethereum-lisp.snap:snap-get-bytecodes-hashes request)))
                (sb-thread:with-mutex (lock) (decf active)))))))
    (loop for code in codes
          for hash in hashes
          do (setf (gethash hash codes-by-hash) code))
    (setf (ethereum-lisp.snap-sync::snap-sync-multi-runtime-code-worker-count
           runtime)
          2)
    (unwind-protect
         (progn
           (dotimes (index 2)
             (declare (ignore index))
             (push
              (sb-thread:make-thread
               (lambda ()
                 (ethereum-lisp.snap-sync::snap-sync-multi-code-worker
                  runtime database))
               :name "snap-test-global-code-worker")
              workers))
           (dolist (slice (list (subseq hashes 0 170)
                                (subseq hashes 170)))
             (let ((requested slice))
               (push
                (sb-thread:make-thread
                 (lambda ()
                   (ethereum-lisp.snap-sync::snap-sync-multi-fetch-page-codes
                    runtime database source requested (* 512 1024)))
                 :name "snap-test-global-code-page")
                page-threads)))
           (dolist (thread page-threads)
             (is (not (eq :timeout
                          (sb-thread:join-thread
                           thread :timeout 10 :default :timeout)))))
           (setf page-threads nil)
           (is (= 6 calls))
           (is (= 2 maximum-active))
           (dolist (hash (list (first hashes) (car (last hashes))))
             (is (nth-value
                  1 (kv-get-chain-record database :code hash)))))
      (sb-thread:with-mutex
          ((ethereum-lisp.snap-sync::snap-sync-multi-runtime-lock runtime))
        (setf
         (ethereum-lisp.snap-sync::snap-sync-multi-runtime-stopped-p runtime)
         t)
        (ethereum-lisp.snap-sync::snap-sync-multi-notify runtime))
      (dolist (thread page-threads)
        (ignore-errors
          (sb-thread:join-thread thread :timeout 5 :default nil)))
      (dolist (thread workers)
        (ignore-errors
          (sb-thread:join-thread thread :timeout 5 :default nil))))))

#+sbcl
(deftest snap-multi-code-flight-publishes-each-finished-batch
  (:layer :unit :module :p2p)
  (let* ((database (make-memory-key-value-database))
         (runtime
           (ethereum-lisp.snap-sync::make-snap-sync-multi-runtime nil 0 nil))
         (codes
           (loop for index below 85
                 collect (snap-test-index-hash (+ 1000 index))))
         (hashes (mapcar #'keccak-256 codes))
         (codes-by-hash (make-hash-table :test #'equalp))
         (large-returned (sb-thread:make-semaphore :count 0))
         (singleton-entered (sb-thread:make-semaphore :count 0))
         (release-singleton (sb-thread:make-semaphore :count 0))
         (calls-lock
           (sb-thread:make-mutex :name "snap-test-stream-code-calls"))
         (calls 0)
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :bytecodes
            (lambda (request)
              (let ((requested
                      (ethereum-lisp.snap:snap-get-bytecodes-hashes request)))
                (sb-thread:with-mutex (calls-lock) (incf calls))
                (if (= 1 (length requested))
                    (progn
                      (sb-thread:signal-semaphore singleton-entered)
                      (sb-thread:wait-on-semaphore
                       release-singleton :timeout 5))
                    (sb-thread:signal-semaphore large-returned))
                (ethereum-lisp.snap:make-snap-bytecodes
                 (ethereum-lisp.snap:snap-get-bytecodes-id request)
                 (mapcar
                  (lambda (hash)
                    (copy-seq (gethash hash codes-by-hash)))
                  requested))))))
         (owner-thread nil)
         (waiter-thread nil))
    (loop for code in codes
          for hash in hashes
          do (setf (gethash hash codes-by-hash) code))
    (flet ((fetch (requested)
             (ethereum-lisp.snap-sync::snap-sync-multi-fetch-page-codes
              runtime database source requested (* 512 1024))))
      (unwind-protect
           (progn
             (setf owner-thread
                   (sb-thread:make-thread
                    (lambda () (fetch hashes))
                    :name "snap-test-stream-code-owner"))
             (is (sb-thread:wait-on-semaphore large-returned :timeout 5))
             (is (sb-thread:wait-on-semaphore singleton-entered :timeout 5))
             ;; The singleton request is still blocked. A page sharing a hash
             ;; from the completed 84-item response must nevertheless observe
             ;; that response and finish without issuing another request.
             (setf waiter-thread
                   (sb-thread:make-thread
                    (lambda () (fetch (list (first hashes))))
                    :name "snap-test-stream-code-waiter"))
             (let ((joined
                     (sb-thread:join-thread
                      waiter-thread :timeout 5 :default :blocked)))
               (is (not (eq :blocked joined)))
               (unless (eq :blocked joined)
                 (setf waiter-thread nil)))
             (multiple-value-bind (stored present-p)
                 (kv-get-chain-record database :code (first hashes))
               (is present-p)
               (when present-p
                 (is (bytes= (first codes) stored))))
             (is (= 2 calls))
             (sb-thread:signal-semaphore release-singleton)
             (is (not (eq :timeout
                          (sb-thread:join-thread
                           owner-thread :timeout 5 :default :timeout))))
             (setf owner-thread nil))
        (sb-thread:signal-semaphore release-singleton)
        (when owner-thread
          (ignore-errors
            (sb-thread:join-thread owner-thread :timeout 5 :default nil)))
        (when waiter-thread
          (ignore-errors
            (sb-thread:join-thread waiter-thread :timeout 5 :default nil)))))))

#+sbcl
(deftest snap-bytecode-batches-use-bounded-concurrent-workers
  (:layer :unit :module :p2p)
  (let ((real
          (fdefinition
           'ethereum-lisp.snap-sync::snap-sync-fetch-code-hash-batch)))
    (unwind-protect
         (progn
           (setf
            (fdefinition
             'ethereum-lisp.snap-sync::snap-sync-fetch-code-hash-batch)
            (lambda (source hashes byte-limit)
              (declare (ignore source byte-limit))
              (sleep 0.2)
              (copy-list hashes)))
           (let* ((started-at (get-internal-real-time))
                  (result
                    (ethereum-lisp.snap-sync::snap-sync-fetch-code-batches-concurrently
                     nil '((:first) (:second)) 1))
                  (elapsed
                    (ethereum-lisp.snap-sync::snap-sync-elapsed-milliseconds
                     started-at (get-internal-real-time))))
             (is (equal '(:first :second) result))
             (is (< elapsed 380))))
      (setf
       (fdefinition
        'ethereum-lisp.snap-sync::snap-sync-fetch-code-hash-batch)
       real))))

(deftest snap-account-page-overlaps-storage-and-bytecode-dependencies
  (:layer :integration :module :p2p)
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-memory-key-value-database))
         (address
           (address-from-hex
            "0x0000000000000000000000000000000000000042"))
         (slot (make-hash32 (snap-test-hash 41)))
         (code #(96 0 96 0)))
    (state-db-set-account
     source-state address (make-state-account :nonce 1 :balance 42))
    (state-db-set-storage source-state address slot 256)
    (state-db-set-code source-state address code)
    (let* ((root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base (snap-test-source backend))
           (source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (ethereum-lisp.snap-sync:snap-sync-source-account-range base)
              :storage-ranges
              (lambda (request)
                (sleep 0.2)
                (funcall
                 (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges base)
                 request))
              :bytecodes
              (lambda (request)
                (sleep 0.2)
                (funcall
                 (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base)
                 request))
              :trie-nodes
              (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes base)))
           (task
             (first
              (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
               :count 1)))
           (result
             (ethereum-lisp.snap-sync::snap-sync-prepare-account-page
              target-database source root 0 task (* 512 1024)))
           (profile
             (ethereum-lisp.snap-sync::snap-sync-page-result-profile result))
           (storage-ms
             (ethereum-lisp.snap-sync:snap-sync-page-profile-storage-ms
              profile))
           (code-ms
             (ethereum-lisp.snap-sync:snap-sync-page-profile-code-ms profile))
           (total-ms
             (ethereum-lisp.snap-sync:snap-sync-page-profile-total-ms profile)))
      (is (>= storage-ms 150))
      (is (>= code-ms 150))
      ;; If the two 200ms delays were serial, TOTAL-MS would be at least their
      ;; sum. The account proof and memory persistence are deliberately tiny.
      (is (< total-ms (+ storage-ms code-ms)))
      (multiple-value-bind (persisted present-p)
          (kv-get-chain-record target-database :code (keccak-256 code))
        (is present-p)
        (is (bytes= code persisted))))))

(deftest snap-state-root-probe-verifies-a-small-range-and-classifies-pruning
  (:layer :unit :module :p2p)
  (let* ((database (make-memory-key-value-database))
         (state (make-state-db))
         (address
           (address-from-hex
            "0x0000000000000000000000000000000000000042")))
    (state-db-set-account state address (make-state-account :balance 7))
    (let* ((root (state-db-root state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              database state))
           (source (snap-test-source backend))
           (pruned
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (lambda (request)
                (ethereum-lisp.snap:make-snap-account-range
                 (ethereum-lisp.snap:snap-get-account-range-id request)
                 '() '())))))
      (is (ethereum-lisp.snap-sync:snap-sync-probe-state-root source root))
      (signals ethereum-lisp.snap-sync:snap-sync-state-unavailable
        (ethereum-lisp.snap-sync:snap-sync-probe-state-root pruned root)))))

(deftest snap-state-import-classifies-an-empty-account-response-as-unavailable
  (:layer :unit :module :p2p)
  (let* ((database (make-memory-key-value-database))
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range
            (lambda (request)
              (ethereum-lisp.snap:make-snap-account-range
               (ethereum-lisp.snap:snap-get-account-range-id request)
               '() '()))
            :storage-ranges (lambda (request) (declare (ignore request)))
            :bytecodes (lambda (request) (declare (ignore request)))
            :trie-nodes (lambda (request) (declare (ignore request))))))
    (signals ethereum-lisp.snap-sync:snap-sync-state-unavailable
      (ethereum-lisp.snap-sync:snap-sync-import-state
       database source
       :pivot-hash (make-hash32 (snap-test-hash 111)) :pivot-number 42
       :state-root (make-hash32 (snap-test-hash 112))
       :target-hash (make-hash32 (snap-test-hash 113))
       :chain-id 560048
       :genesis-hash (make-hash32 (snap-test-hash 114))
       :authority-id (make-hash32 (snap-test-hash 115))))
    (is (not (nth-value 1
                        (ethereum-lisp.snap-sync:snap-sync-read-progress
                         database))))))

(deftest snap-state-import-starts-storage-with-geth-full-range-bounds
  (:layer :integration :module :p2p)
  ;; Pinned geth 1.17.4 sends nil Origin/Limit for an initial complete storage
  ;; request.  A hash-scheme server may have the pivot snapshot but no longer
  ;; retain the historical trie nodes needed to prove an explicit zero/max
  ;; subrange.  Model that exact availability boundary: only the canonical
  ;; empty-bound request is served.  The storage callback count is the positive
  ;; witness that this test actually crossed the affected wire boundary.
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-memory-key-value-database))
         (address
           (address-from-hex
            "0x0000000000000000000000000000000000000042"))
         (slot (make-hash32 (make-byte-vector 32 :initial-element 7)))
         (storage-calls 0)
         (observed-origin-length nil)
         (observed-limit-length nil)
         (observed-byte-limit nil))
    (state-db-set-storage source-state address slot 256)
    (let* ((root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base-source (snap-test-source backend))
           (source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (ethereum-lisp.snap-sync:snap-sync-source-account-range
               base-source)
              :storage-ranges
              (lambda (request)
                (incf storage-calls)
                (setf observed-origin-length
                      (length
                       (ethereum-lisp.snap:snap-get-storage-ranges-origin
                        request))
                      observed-limit-length
                      (length
                       (ethereum-lisp.snap:snap-get-storage-ranges-limit
                        request))
                      observed-byte-limit
                      (ethereum-lisp.snap:snap-get-storage-ranges-bytes
                       request))
                (if (and (zerop observed-origin-length)
                         (zerop observed-limit-length))
                    (snap-test-call-backend
                     backend ethereum-lisp.snap:+snap-message-get-storage-ranges+
                     request)
                    (ethereum-lisp.snap:make-snap-storage-ranges
                     (ethereum-lisp.snap:snap-get-storage-ranges-id request)
                     '() '())))
              :bytecodes
              (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base-source)
              :trie-nodes
              (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
               base-source)))
           (progress
             (ethereum-lisp.snap-sync:snap-sync-import-state
              target-database source
              :pivot-hash (make-hash32 (snap-test-hash 116))
              :pivot-number 42 :state-root root
              :target-hash (make-hash32 (snap-test-hash 117))
              :chain-id 560048
              :genesis-hash (make-hash32 (snap-test-hash 118))
              :authority-id (make-hash32 (snap-test-hash 119)))))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p progress))
      (is (= 1 storage-calls))
      (is (zerop observed-origin-length))
      (is (zerop observed-limit-length))
      (is (= (* 512 1024) observed-byte-limit)))))

(deftest snap-state-import-batches-complete-storage-tries
  (:layer :integration :module :p2p)
  ;; snap/1 GetStorageRanges accepts a list of account hashes. Geth returns a
  ;; prefix of complete storage tries, reserving a proof for only the final
  ;; byte-capped trie. Small contracts on one account page must therefore be
  ;; fetched together instead of serializing one network round trip each.
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-instance 'snap-counting-test-database))
         (addresses
           (loop for suffix from 1 to 4
                 collect
                 (address-from-hex
                  (format nil "0x00000000000000000000000000000000000000~2,'0x"
                          suffix))))
         (storage-calls 0)
         (largest-request 0))
    (loop for address in addresses
          for byte from 1
          do (state-db-set-storage
              source-state address
              (make-hash32 (make-byte-vector 32 :initial-element byte))
              (+ 100 byte)))
    (let* ((root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base-source (snap-test-source backend))
           (source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (ethereum-lisp.snap-sync:snap-sync-source-account-range
               base-source)
              :storage-ranges
              (lambda (request)
                (incf storage-calls)
                (setf largest-request
                      (max largest-request
                           (length
                            (ethereum-lisp.snap:snap-get-storage-ranges-accounts
                             request))))
                (snap-test-call-backend
                 backend ethereum-lisp.snap:+snap-message-get-storage-ranges+
                 request))
              :bytecodes
              (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base-source)
              :trie-nodes
              (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
               base-source)))
           (progress
             (ethereum-lisp.snap-sync:snap-sync-import-state
              target-database source
              :pivot-hash (make-hash32 (snap-test-hash 120))
              :pivot-number 42 :state-root root
              :target-hash (make-hash32 (snap-test-hash 121))
              :chain-id 560048
              :genesis-hash (make-hash32 (snap-test-hash 122))
              :authority-id (make-hash32 (snap-test-hash 123)))))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p progress))
      (is (= 1 storage-calls))
      (is (= (length addresses) largest-request))
      ;; One initial synchronous batch installs the complete-node scheme. Each
      ;; of the two account pages then prebuffers its authenticated trie nodes,
      ;; buffers storage/closure metadata, and publishes a separate cursor
      ;; batch. The final traversal alone writes completion.
      (let* ((apply-count
               (snap-counting-test-database-apply-count target-database))
             (batch-sizes
               (reverse
                (copy-list
                 (snap-counting-test-database-batch-sizes target-database))))
             (batch-prefixes
               (reverse
                (copy-list
                 (snap-counting-test-database-batch-prefixes
                  target-database)))))
        (unless (= 9 apply-count)
          (error "Expected nine scheme/prebuffer/content/cursor/completion batches, got ~D (~S)"
                 apply-count (list batch-sizes batch-prefixes)))
        (is (= 9 apply-count))
        ;; The account-record WAL batches precede their metadata-only cursor
        ;; publications. #x19 is :TRIE-NODE and #x0d is :METADATA.
        (is (every (lambda (prefix) (= #x19 prefix))
                   (second batch-prefixes)))
        (is (every (lambda (prefix) (= #x0d prefix))
                   (fifth batch-prefixes)))
        (is (every (lambda (prefix) (= #x19 prefix))
                   (sixth batch-prefixes)))
        (is (every (lambda (prefix) (= #x0d prefix))
                   (eighth batch-prefixes))))
      (is (= 5
             (snap-counting-test-database-buffered-apply-count
              target-database)))
      (is (every #'plusp
                 (snap-counting-test-database-buffered-batch-sizes
                  target-database)))
      (dolist (address addresses)
        (multiple-value-bind (node present-p)
            (ethereum-lisp.trie:trie-node-store-get
             target-database
             (state-db-get-storage-root source-state address))
          (is present-p)
          (is (plusp (length node))))
        (multiple-value-bind (account present-p)
            (ethereum-lisp.trie:mpt-get
             (ethereum-lisp.trie:make-persisted-mpt
              root
              (lambda (hash)
                (ethereum-lisp.trie:trie-node-store-get
                 target-database hash)))
             (ethereum-lisp.crypto:keccak-256 (address-bytes address)))
          (declare (ignore account))
          (is present-p))))))

(deftest snap-state-import-publishes-proved-range-subtrees
  (:layer :integration :module :p2p)
  ;; Range verification reconstructs every interior node. Once the same page's
  ;; external dependencies are durable, publish coarse subtree proofs with the
  ;; atomic cursor batch so a later pivot heals only changed/boundary regions.
  (multiple-value-bind (source-state addresses)
      (snap-test-partitioned-state)
    (declare (ignore addresses))
    (let* ((source-database (make-memory-key-value-database))
           (target-database (make-memory-key-value-database))
           (root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (source (snap-test-source backend))
           (published 0)
           (real-populate
             (fdefinition
              'ethereum-lisp.snap-sync::snap-sync-populate-healed-subtree-batch))
           (progress nil))
      (let ((ethereum-lisp.snap-sync::*snap-sync-healed-subtree-prefix-nibbles*
              1)
            (ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles*
              1)
            (ethereum-lisp.snap-sync::*snap-sync-range-nested-subtree-prefix-nibbles*
              1))
        (unwind-protect
             (progn
               (setf
                (fdefinition
                 'ethereum-lisp.snap-sync::snap-sync-populate-healed-subtree-batch)
                (lambda (batch reference &optional (kind :account))
                  (incf published)
                  (funcall real-populate batch reference kind)))
               (setf
                progress
                (ethereum-lisp.snap-sync:snap-sync-import-state
                 target-database source
                 :pivot-hash (make-hash32 (snap-test-hash 241))
                 :pivot-number 42 :state-root root
                 :target-hash (make-hash32 (snap-test-hash 242))
                 :chain-id 560048
                 :genesis-hash (make-hash32 (snap-test-hash 243))
                 :authority-id (make-hash32 (snap-test-hash 244)))))
          (setf
           (fdefinition
            'ethereum-lisp.snap-sync::snap-sync-populate-healed-subtree-batch)
           real-populate)))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p progress))
      (is
       (ethereum-lisp.snap-sync::snap-sync-progress-complete-node-scheme-p
        progress))
      (is (plusp published))
      ;; The root and page-edge proof nodes are authenticated content, but
      ;; they do not by themselves prove descendant closure. Fresh imports
      ;; record that distinction so a later moving pivot cannot mistake mere
      ;; hash presence for geth's complete-subtree invariant.
      (is
       (plusp
        (hash-table-count
         (ethereum-lisp.snap-sync::snap-sync-load-incomplete-nodes
          target-database))))
      (let ((ethereum-lisp.snap-sync::*snap-sync-healed-subtree-prefix-nibbles*
              1)
            (ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles*
              1)
            (ethereum-lisp.snap-sync::*snap-sync-range-nested-subtree-prefix-nibbles*
              1))
        (is
         (plusp
          (ethereum-lisp.snap-sync::snap-sync-promote-complete-range-plan
           target-database root)))
        (is
         (ethereum-lisp.snap-sync::snap-sync-range-plan-promoted-p
          target-database root))
        (is
         (zerop
          (ethereum-lisp.snap-sync::snap-sync-promote-complete-range-plan
           target-database root)))))))

(deftest snap-proved-range-subtrees-publish-coarse-and-nested-layers
  (:layer :unit :module :p2p)
  (let ((trie (make-mpt)))
    ;; Populate every two-nibble bucket with a hashed leaf. The full proved
    ;; interval must expose both the public coarse layer and its nested reuse
    ;; layer, rather than replacing one with the other.
    (dotimes (index 256)
      (let ((key (make-byte-vector 32)))
        (setf (aref key 0) index)
        (mpt-put
         trie key
         (make-byte-vector 64 :initial-element (1+ (mod index 255))))))
    (let ((ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles*
            1)
          (ethereum-lisp.snap-sync::*snap-sync-range-nested-subtree-prefix-nibbles*
            2))
      (multiple-value-bind (subtrees groups)
          (ethereum-lisp.snap-sync::snap-sync-proved-range-subtrees
           trie (make-byte-vector 32)
           (make-byte-vector 32 :initial-element #xff))
        (is (plusp (count 1 subtrees :key (lambda (entry) (length (car entry))))))
        (is (plusp (count 2 subtrees :key (lambda (entry) (length (car entry))))))
        (is (= (length subtrees) (length groups)))
        (is
         (every
          (lambda (group)
            (and (= 3 (length group))
                 (every (lambda (reference) (= 32 (length reference)))
                        (third group))))
          groups))))))

(deftest snap-range-plan-promotion-excludes-incomplete-storage-bucket
  (:layer :unit :module :p2p)
  (let* ((database (make-memory-key-value-database))
         (trie (make-mpt))
         (unsafe-account (snap-test-hash 246))
         (commitment
           (cons unsafe-account
                 (make-hash32 (snap-test-hash 247))))
         (batch (make-kv-write-batch)))
    ;; Give every first-nibble bucket a hashed child so the test can prove
    ;; that one incomplete storage dependency excludes only its own bucket.
    (dotimes (nibble 16)
      (let ((key (make-byte-vector 32 :initial-element nibble)))
        (setf (aref key 0) (logior (ash nibble 4) nibble))
        (mpt-put trie key (make-byte-vector 64 :initial-element (1+ nibble)))))
    (let ((state-root (mpt-persist database trie)))
      (ethereum-lisp.snap-sync::snap-sync-populate-deferred-storage-batch
       batch state-root commitment)
      (ethereum-lisp.snap-sync::snap-sync-populate-deferred-storage-plan-batch
       batch state-root)
      (kv-apply-batch database batch)
      (is
       (not
        (ethereum-lisp.snap-sync::snap-sync-range-plan-fully-durable-p
         database state-root)))
      (let* ((ethereum-lisp.snap-sync::*snap-sync-healed-subtree-prefix-nibbles*
               1)
             (ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles*
               1)
             (ethereum-lisp.snap-sync::*snap-sync-range-nested-subtree-prefix-nibbles*
               1)
             (references
               (mpt-hashed-subtrees-with-prefix-at-depth
                (make-persisted-mpt
                 state-root
                 (lambda (hash) (trie-node-store-get database hash)))
                1))
             (unsafe-prefix
               (ethereum-lisp.snap-sync::snap-sync-account-prefix-bucket
                unsafe-account))
             (unsafe-reference
               (cdr (find unsafe-prefix references :key #'car :test #'equalp)))
             (safe-reference
               (cdr
                (find-if
                 (lambda (entry) (not (equalp unsafe-prefix (car entry))))
                 references))))
        (is (plusp (length references)))
        (is
         (plusp
          (ethereum-lisp.snap-sync::snap-sync-promote-complete-range-plan
           database state-root)))
        (is
         (ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p
          database safe-reference :account))
        (is
         (not
          (ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p
           database unsafe-reference :account)))
        ;; Partial promotion must retry after this storage cursor set finishes.
        (is
         (not
          (ethereum-lisp.snap-sync::snap-sync-range-plan-promoted-p
           database state-root)))))))

(deftest snap-account-range-subtree-proofs-carry-bounded-storage-gaps
  (:layer :unit :module :p2p)
  (let* ((account-hash (make-byte-vector 32))
         (storage-root (make-hash32 (snap-test-hash 249)))
         (dependency (cons account-hash storage-root))
         (dependent-reference (snap-test-hash 250))
         (safe-reference (snap-test-hash 251))
         (dependent-records
           (list dependent-reference (snap-test-hash 252)))
         (safe-records
           (list safe-reference (snap-test-hash 253)))
         (wide-reference (snap-test-hash 254))
         (wide-records
           (list wide-reference (snap-test-hash 255)))
         (nested-reference (snap-test-index-hash 998))
         (nested-records
           (list nested-reference (snap-test-index-hash 999)))
         (wide-dependencies
           (loop for index from 0
                 repeat
                 (1+
                  ethereum-lisp.snap-sync::+snap-sync-account-subtree-dependencies-max+)
                 collect
                 (let ((hash (make-byte-vector 32)))
                   ;; All entries share coarse prefix 3, but distributing the
                   ;; second nibble keeps each nested prefix independently
                   ;; within the dependency-proof bound.
                   (setf (aref hash 0) (logior #x30 (mod index 16))
                         (aref hash 31) index)
                   (cons hash
                         (make-hash32 (snap-test-index-hash (+ 1000 index))))))))
    (setf (aref account-hash 0) #x10)
    (let ((ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles*
            1))
      (multiple-value-bind (safe dependency-subtrees complete-references)
          (ethereum-lisp.snap-sync::snap-sync-classify-account-range-subtrees
           (list (list #(1) dependent-reference dependent-records)
                 (list #(2) safe-reference safe-records)
                 (list #(3) wide-reference wide-records)
                 (list #(3 0) nested-reference nested-records))
           (cons dependency wide-dependencies))
        (is (= 1 (length safe)))
        (is (bytes= safe-reference (first safe)))
        (is (= 2 (length dependency-subtrees)))
        (is
         (find dependent-reference dependency-subtrees
               :key #'car :test #'bytes=))
        (is
         (find nested-reference dependency-subtrees
               :key #'car :test #'bytes=))
        ;; Bounded dependency metadata replaces an account-tree walk but not
        ;; the exact storage work it names.  Its reconstructed account nodes
        ;; are therefore complete. The over-limit coarse group remains
        ;; fail-closed while its independently bounded nested child closes.
        (is (= 6 (length complete-references)))
        (is (every
             (lambda (reference)
               (find reference complete-references :test #'bytes=))
             (append dependent-records safe-records nested-records)))
        (is (notany
             (lambda (reference)
               (find reference complete-references :test #'bytes=))
             wide-records))
        (let* ((all-records
                 (mapcar
                  (lambda (reference) (cons reference #(1)))
                  (append dependent-records safe-records wide-records)))
               (incomplete
                 (ethereum-lisp.snap-sync::snap-sync-incomplete-record-hashes
                  all-records complete-references)))
          (is (= 2 (length incomplete)))
          (is (every
               (lambda (reference)
                 (find reference incomplete :test #'bytes=))
               wide-records)))
        (let* ((dependent-entry
                 (find dependent-reference dependency-subtrees
                       :key #'car :test #'bytes=))
               (encoded
                 (ethereum-lisp.snap-sync::snap-sync-account-subtree-dependencies-value
                  (cdr dependent-entry)))
               (decoded
                 (ethereum-lisp.snap-sync::snap-sync-account-subtree-dependencies-from-value
                  encoded)))
          (is (= 1 (length decoded)))
          (is (bytes= account-hash (caar decoded)))
          (is (hash32= storage-root (cdar decoded))))))
    (signals
     ethereum-lisp.validation:storage-error
     (ethereum-lisp.snap-sync::snap-sync-account-subtree-dependencies-from-value
      #(1 2 3)))
    (signals
     error
     (ethereum-lisp.snap-sync::snap-sync-account-subtree-dependencies-value
      (list dependency dependency)))
    (let ((empty-root-value (make-byte-vector 65)))
      (setf (aref empty-root-value 0)
            ethereum-lisp.snap-sync::+snap-sync-account-subtree-dependencies-version+)
      (replace empty-root-value (hash32-bytes +empty-trie-hash+) :start1 33)
      (signals
       ethereum-lisp.validation:storage-error
       (ethereum-lisp.snap-sync::snap-sync-account-subtree-dependencies-from-value
        empty-root-value)))
    (let ((oversized
            (make-byte-vector
             (+ 1
                (* 64
                   (1+
                    ethereum-lisp.snap-sync::+snap-sync-account-subtree-dependencies-max+))))))
      (setf (aref oversized 0)
            ethereum-lisp.snap-sync::+snap-sync-account-subtree-dependencies-version+)
      (signals
       ethereum-lisp.validation:storage-error
       (ethereum-lisp.snap-sync::snap-sync-account-subtree-dependencies-from-value
        oversized)))))

(deftest snap-range-proofs-clear-stale-incomplete-markers
  (:layer :unit :module :p2p)
  ;; A node can first appear on an open page boundary and later fall inside a
  ;; proved-complete subtree.  The later durable page must revoke the earlier
  ;; negative marker; merely declining to write a duplicate leaves millions of
  ;; already-proved nodes for the final healer to revisit.
  (let* ((database (make-memory-key-value-database))
         (account-complete (snap-test-index-hash 1800))
         (account-open (snap-test-index-hash 1801))
         (storage-complete (snap-test-index-hash 1802))
         (storage-open (snap-test-index-hash 1803))
         (initial (make-kv-write-batch)))
    (dolist (reference
             (list account-complete account-open storage-complete storage-open))
      (ethereum-lisp.snap-sync::snap-sync-populate-incomplete-node-batch
       initial reference))
    (kv-apply-batch database initial)
    (let ((result
            (ethereum-lisp.snap-sync::make-snap-sync-page-result
             :account-records
             (list
              (cons account-complete (make-byte-vector 1 :initial-element 1))
              (cons account-open (make-byte-vector 1 :initial-element 2)))
             :complete-node-hashes (list account-complete)
             :incomplete-node-hashes (list account-open))))
      (ethereum-lisp.snap-sync::snap-sync-buffer-account-page-content
       database (make-hash32 (snap-test-index-hash 1804)) result)
      ;; Once the authenticated metadata is buffered, the coordinator needs
      ;; only cursor-ordering fields.  Neither side of the closure set may keep
      ;; the page's hash graph alive until the next coarse full collection.
      (is (null
           (ethereum-lisp.snap-sync::snap-sync-page-result-account-records
            result)))
      (is (null
           (ethereum-lisp.snap-sync::snap-sync-page-result-complete-node-hashes
            result)))
      (is (null
           (ethereum-lisp.snap-sync::snap-sync-page-result-incomplete-node-hashes
            result))))
    (let* ((origin (make-byte-vector 32))
           (limit (make-byte-vector 32 :initial-element #xff))
           (task
             (ethereum-lisp.snap-sync::snap-sync-account-task
              :start origin :limit limit :next-origin origin
              :completed-p nil)))
      (ethereum-lisp.snap-sync::snap-sync-commit-storage-page
       database (make-hash32 (snap-test-index-hash 1805))
       (snap-test-index-hash 1806)
       (make-hash32 (snap-test-index-hash 1807))
       (list task)
       (ethereum-lisp.snap-sync::make-snap-sync-storage-page-result
        :task-index 0 :origin origin
        :records
        (list
         (cons storage-complete (make-byte-vector 1 :initial-element 3))
         (cons storage-open (make-byte-vector 1 :initial-element 4)))
        :complete-node-hashes (list storage-complete)
        :incomplete-node-hashes (list storage-open)
        :completed-p t)))
    (let ((markers
            (ethereum-lisp.snap-sync::snap-sync-load-incomplete-nodes
             database)))
      (is (= 2 (hash-table-count markers)))
      (is (not (nth-value 1 (gethash account-complete markers))))
      (is (nth-value 1 (gethash account-open markers)))
      (is (not (nth-value 1 (gethash storage-complete markers))))
      (is (nth-value 1 (gethash storage-open markers))))))

(deftest snap-state-import-finishes-byte-capped-storage-before-account-cursor
  (:layer :integration :module :p2p)
  ;; Match geth's account-task pending boundary: persist the authenticated
  ;; prefix, finish the trie through restart-safe partitioned StorageRanges,
  ;; and publish its range-derived subtree proofs before the account cursor
  ;; advances. The final bounded closure walk remains fail closed.
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-memory-key-value-database))
         (address
           (address-from-hex
            "0x0000000000000000000000000000000000000043"))
         (account-hash
           (ethereum-lisp.crypto:keccak-256 (address-bytes address)))
         (storage-lock
           (sb-thread:make-mutex :name "snap-test-account-storage-lanes"))
         (storage-changed
           (sb-thread:make-waitqueue :name "snap-test-account-storage-lanes"))
         (partition-active 0)
         (partition-max-active 0)
         (partition-starts 0)
         (deferred-call-count 0)
         (deferred-call-max-source-count 0)
         (deferred-call-saw-global-workers-p nil)
         (storage-calls 0)
         (trie-node-requests 0)
         (heal-progress-events '())
         (saw-byte-capped-storage-p nil)
         (initial-storage-prefix-last nil)
         (initial-storage-task-count nil)
         (partition-origin-values '())
         (replayed-initial-storage-prefix-p nil)
         (smallest-explicit-storage-origin nil)
         (storage-ready-before-account-cursor-p nil)
         (saw-account-heal-path-p nil))
    (loop for byte from 1 to 96
          do (state-db-set-storage
              source-state address
              (make-hash32 (make-byte-vector 32 :initial-element byte))
              (+ 1000 byte)))
    (let* ((root (state-db-root source-state))
           (storage-root (state-db-get-storage-root source-state address))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base-source (snap-test-source backend))
           (storage-range-function
             (lambda (request)
               (let* ((origin
                        (ethereum-lisp.snap:snap-get-storage-ranges-origin
                         request))
                      (partition-p (plusp (length origin))))
                 (sb-thread:with-mutex (storage-lock)
                   (incf storage-calls)
                   (when partition-p
                     (push
                      (ethereum-lisp.snap-sync::bytes-to-integer origin)
                      partition-origin-values)
                     (when (and initial-storage-prefix-last
                                (not
                                 (ethereum-lisp.validation:byte-vector-lexicographic<
                                  initial-storage-prefix-last origin)))
                       (setf replayed-initial-storage-prefix-p t))
                     (when (or (null smallest-explicit-storage-origin)
                               (ethereum-lisp.validation:byte-vector-lexicographic<
                                origin smallest-explicit-storage-origin))
                       (setf smallest-explicit-storage-origin
                             (copy-seq origin)))
                     (incf partition-active)
                     (setf partition-max-active
                           (max partition-max-active partition-active))
                     (when (< partition-starts
                              (min 2 initial-storage-task-count))
                       (incf partition-starts)
                       (sb-thread:condition-broadcast storage-changed))
                     ;; When density selects multiple chunks, the first waits
                     ;; for a second production lane. A one-chunk plan must not
                     ;; manufacture concurrency by timing out and retrying the
                     ;; same cursor through another source.
                     (loop repeat 20
                           while (< partition-starts
                                    (min 2 initial-storage-task-count))
                           do (sb-thread:condition-wait
                               storage-changed storage-lock :timeout 1/10))))
                 (unwind-protect
                      (let ((response
                              ;; Model the public hash-scheme boundary observed
                              ;; on Hoodi: the canonical nil-bound request is
                              ;; serviceable, but replaying its authenticated
                              ;; prefix with explicit bounds is rejected. Geth
                              ;; seeds the large-contract cursor from the first
                              ;; response and never makes this replay.
                              (if replayed-initial-storage-prefix-p
                                  (ethereum-lisp.snap:make-snap-storage-ranges
                                   (ethereum-lisp.snap:snap-get-storage-ranges-id
                                    request)
                                   '() '())
                                  (snap-test-call-backend
                                   backend
                                   ethereum-lisp.snap:+snap-message-get-storage-ranges+
                                   request))))
                        (sb-thread:with-mutex (storage-lock)
                          (setf saw-byte-capped-storage-p
                                (or saw-byte-capped-storage-p
                                    (not
                                     (null
                                      (ethereum-lisp.snap:snap-storage-ranges-proof
                                       response)))))
                          (when (and
                                 (not partition-p)
                                 (ethereum-lisp.snap:snap-storage-ranges-proof
                                  response))
                            (let* ((groups
                                     (ethereum-lisp.snap:snap-storage-ranges-slots
                                      response))
                                   (last-group (car (last groups)))
                                   (last-slot (and last-group
                                                   (car (last last-group)))))
                              (when last-slot
                                (let ((last-key
                                        (ethereum-lisp.snap:snap-storage-data-hash
                                         last-slot)))
                                  (setf
                                   initial-storage-prefix-last
                                   (copy-seq last-key)
                                   initial-storage-task-count
                                   (ethereum-lisp.snap-sync::snap-sync-adaptive-storage-task-count
                                    (length last-group) last-key)))))))
                        response)
                   (when partition-p
                     (sb-thread:with-mutex (storage-lock)
                       (decf partition-active)))))))
           (source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (ethereum-lisp.snap-sync:snap-sync-source-account-range
               base-source)
              :storage-ranges storage-range-function
              :bytecodes
              (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base-source)
              :trie-nodes
              (lambda (request)
                (incf trie-node-requests)
                (when
                    (some
                     (lambda (path-set) (= 1 (length path-set)))
                     (ethereum-lisp.snap:snap-get-trie-nodes-paths request))
                  (setf saw-account-heal-path-p t))
                (funcall
                 (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
                  base-source)
                 request))))
           (source-two
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (ethereum-lisp.snap-sync:snap-sync-source-account-range
               base-source)
              :storage-ranges storage-range-function
              :bytecodes
              (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base-source)
              :trie-nodes
              (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
               base-source)))
           (progress
             (let* ((symbol
                      'ethereum-lisp.snap-sync::snap-sync-multi-complete-deferred-storage-roots)
                    (original (symbol-function symbol)))
               (unwind-protect
                    (progn
                      ;; Observe the shipped multi-import call site, not a
                      ;; private reconstruction of its scheduler wiring.
                      (setf
                       (symbol-function symbol)
                       (lambda (&rest arguments)
                         (let ((runtime (first arguments)))
                           (sb-thread:with-mutex
                               ((ethereum-lisp.snap-sync::snap-sync-multi-runtime-lock
                                 runtime))
                             (incf deferred-call-count)
                             (setf
                              deferred-call-max-source-count
                              (max
                               deferred-call-max-source-count
                               (length
                                (ethereum-lisp.snap-sync::snap-sync-multi-runtime-storage-sources
                                 runtime)))
                              deferred-call-saw-global-workers-p
                              (or
                               deferred-call-saw-global-workers-p
                               (plusp
                                (ethereum-lisp.snap-sync::snap-sync-multi-runtime-storage-worker-count
                                 runtime))))))
                         (apply original arguments)))
                      (let ((ethereum-lisp.snap-sync::*snap-sync-heal-progress-node-interval*
                              1))
                        (ethereum-lisp.snap-sync:snap-sync-import-state-multi
                         target-database (list source source-two)
                         :pivot-hash (make-hash32 (snap-test-hash 124))
                         :pivot-number 42 :state-root root
                         :target-hash (make-hash32 (snap-test-hash 125))
                         :chain-id 560048
                         :genesis-hash (make-hash32 (snap-test-hash 126))
                         :authority-id (make-hash32 (snap-test-hash 127))
                         :byte-limit 350
                         :on-progress
                         (lambda (range-progress progress-source task-index)
                           (declare
                            (ignore range-progress progress-source task-index))
                           (setf storage-ready-before-account-cursor-p
                                 (ethereum-lisp.snap-sync::snap-sync-storage-range-tasks-completed-p
                                  target-database root account-hash storage-root)))
                         :on-heal-progress
                         (lambda (heal-progress)
                           (push heal-progress heal-progress-events)))))
                 (setf (symbol-function symbol) original)))))
      (is saw-byte-capped-storage-p)
      (is initial-storage-prefix-last)
      (is smallest-explicit-storage-origin)
      (is
       (ethereum-lisp.validation:byte-vector-lexicographic<
        initial-storage-prefix-last smallest-explicit-storage-origin))
      (is (not replayed-initial-storage-prefix-p))
      (is (> storage-calls 1))
      (is (plusp deferred-call-count))
      (is (>= deferred-call-max-source-count 2))
      (is deferred-call-saw-global-workers-p)
      (is initial-storage-task-count)
      (is (= (min 2 initial-storage-task-count) partition-max-active))
      (is (= (length partition-origin-values)
             (length (remove-duplicates partition-origin-values))))
      (is storage-ready-before-account-cursor-p)
      ;; The adaptive active partitions plus completed sentinels in the
      ;; sixteen-record restart plan retain all authenticated nodes before the
      ;; cursor. The final closure walk should need only a small boundary
      ;; repair, never the account trie or a full storage scan.
      (is (< trie-node-requests 16))
      ;; The final account-page batch published a complete dependency plan.
      ;; Healing starts directly at the deferred storage root; a one-item path
      ;; set would prove that production fell back to the account trie root.
      (is (not saw-account-heal-path-p))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p progress))
      (is (plusp (length heal-progress-events)))
      (let ((final (first heal-progress-events)))
        (is (ethereum-lisp.snap-sync:snap-sync-heal-progress-completed-p final))
        (dolist (value
                 (list
                  (ethereum-lisp.snap-sync:snap-sync-heal-progress-frontier-works
                   final)
                  (ethereum-lisp.snap-sync:snap-sync-heal-progress-deferred-storage-works
                   final)
                  (ethereum-lisp.snap-sync:snap-sync-heal-progress-remote-works
                   final)))
          (is (zerop value))))
      (is
       (ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p
        target-database (hash32-bytes storage-root) :storage-root))
      (multiple-value-bind (node present-p)
          (ethereum-lisp.trie:trie-node-store-get
           target-database storage-root)
        (is present-p)
        (is (plusp (length node)))))))

(deftest snap-large-storage-ranges-resume-durable-partition-cursors
  (:layer :integration :module :p2p)
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-memory-key-value-database))
         (address
           (address-from-hex
            "0x0000000000000000000000000000000000000044"))
         (account-hash
           (ethereum-lisp.crypto:keccak-256 (address-bytes address)))
         (storage-calls 0))
    (loop for byte from 1 to 128
          do (state-db-set-storage
              source-state address
              (make-hash32 (make-byte-vector 32 :initial-element byte))
              (+ 2000 byte)))
    (let* ((root (state-db-root source-state))
           (storage-root (state-db-get-storage-root source-state address))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base-source (snap-test-source backend))
           (flaky-source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (ethereum-lisp.snap-sync:snap-sync-source-account-range
               base-source)
              :storage-ranges
              (lambda (request)
                (incf storage-calls)
                (when (> storage-calls 1)
                  (ethereum-lisp.snap-sync:snap-sync-state-unavailable
                   "storage-range"))
                (funcall
                 (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
                  base-source)
                 request))
              :bytecodes
              (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base-source)
              :trie-nodes
              (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
               base-source))))
      (is (not
           (ethereum-lisp.snap-sync::snap-sync-fill-storage-root
            target-database (list flaky-source) root account-hash storage-root
            350)))
      (let* ((after-failure
               (ethereum-lisp.snap-sync::snap-sync-load-or-create-storage-tasks
                target-database root account-hash storage-root))
             (first-task (first after-failure)))
        (is (not
             (bytes=
              (ethereum-lisp.snap-sync::snap-sync-account-task-start first-task)
              (ethereum-lisp.snap-sync::snap-sync-account-task-next-origin
               first-task)))))
      (is
       (not
        (ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p
         target-database (hash32-bytes storage-root) :storage-root)))
      ;; A fresh source resumes the exact durable cursor instead of replaying
      ;; the already authenticated prefix.
      (is (ethereum-lisp.snap-sync::snap-sync-fill-storage-root
           target-database (list base-source) root account-hash storage-root
           350))
      (is (every
           #'ethereum-lisp.snap-sync::snap-sync-account-task-completed-p
           (ethereum-lisp.snap-sync::snap-sync-load-or-create-storage-tasks
            target-database root account-hash storage-root)))
      (is
       (not
        (ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p
         target-database (hash32-bytes storage-root) :storage-root)))
      (multiple-value-bind (node present-p)
          (ethereum-lisp.trie:trie-node-store-get
           target-database storage-root)
        (is present-p)
        (is (plusp (length node)))))))

(deftest snap-large-storage-chunks-follow-geth-density-estimate
  (:layer :unit :module :p2p)
  (let* ((space (ash 1 256))
         (maximum (1- space))
         (last (floor space 4))
         (last-key
           (ethereum-lisp.snap-sync::snap-sync-integer-to-hash-bytes last))
         (next
           (ethereum-lisp.snap-sync::snap-sync-integer-to-hash-bytes
            (1+ last)))
         (tasks
           (ethereum-lisp.snap-sync::snap-sync-make-seeded-storage-tasks
            next last-key 8192))
         (step (ceiling (- space last) 2))
         (first (first tasks))
         (second (second tasks)))
    ;; At one quarter of the hash space, 8,192 uniformly distributed slots
    ;; estimate roughly 24K remaining. Geth v1.17.4 therefore uses two chunks,
    ;; not the fixed sixteen-way fallback.
    (is (= 2
           (ethereum-lisp.snap-sync::snap-sync-adaptive-storage-task-count
            8192 last-key)))
    (is (= ethereum-lisp.snap-sync::+snap-sync-storage-task-count+
           (length tasks)))
    (is (= 2
           (count-if-not
            #'ethereum-lisp.snap-sync::snap-sync-account-task-completed-p
            tasks)))
    (is (bytes= (make-byte-vector 32)
                (ethereum-lisp.snap-sync::snap-sync-account-task-start first)))
    (is (bytes= next
                (ethereum-lisp.snap-sync::snap-sync-account-task-next-origin
                 first)))
    (is (bytes=
         (ethereum-lisp.snap-sync::snap-sync-integer-to-hash-bytes
          (1- (+ last step)))
         (ethereum-lisp.snap-sync::snap-sync-account-task-limit first)))
    (is (bytes=
         (ethereum-lisp.snap-sync::snap-sync-integer-to-hash-bytes
          (+ last step))
         (ethereum-lisp.snap-sync::snap-sync-account-task-start second)))
    (is (bytes=
         (ethereum-lisp.snap-sync::snap-sync-integer-to-hash-bytes maximum)
         (ethereum-lisp.snap-sync::snap-sync-account-task-limit second)))
    (is (every
         #'ethereum-lisp.snap-sync::snap-sync-account-task-completed-p
         (nthcdr 2 tasks)))
    ;; A denser half-space prefix needs one continuation. Zero or an estimate
    ;; wider than uint64 follows geth's error path and retains the conservative
    ;; maximum.
    (is (= 1
           (ethereum-lisp.snap-sync::snap-sync-adaptive-storage-task-count
            8192
            (ethereum-lisp.snap-sync::snap-sync-integer-to-hash-bytes
             (floor space 2)))))
    (is (= ethereum-lisp.snap-sync::+snap-sync-storage-task-count+
           (ethereum-lisp.snap-sync::snap-sync-adaptive-storage-task-count
            1 (make-byte-vector 32))))
    (is (= ethereum-lisp.snap-sync::+snap-sync-storage-task-count+
           (ethereum-lisp.snap-sync::snap-sync-adaptive-storage-task-count
            1
            (ethereum-lisp.snap-sync::snap-sync-integer-to-hash-bytes 1))))))

(deftest snap-byte-capped-storage-response-seeds-adaptive-durable-tasks
  (:layer :integration :module :p2p)
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-memory-key-value-database))
         (address
           (address-from-hex
            "0x0000000000000000000000000000000000000045"))
         (account-hash
           (ethereum-lisp.crypto:keccak-256 (address-bytes address))))
    (loop for byte from 1 to 128
          do (state-db-set-storage
              source-state address
              (make-hash32 (make-byte-vector 32 :initial-element byte))
              (+ 3000 byte)))
    (let* ((state-root (state-db-root source-state))
           (storage-root (state-db-get-storage-root source-state address))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base-source (snap-test-source backend))
           (response nil)
           (source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (ethereum-lisp.snap-sync:snap-sync-source-account-range
               base-source)
              :storage-ranges
              (lambda (request)
                (setf response
                      (funcall
                       (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
                        base-source)
                       request)))
              :bytecodes
              (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base-source)
              :trie-nodes
              (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
               base-source))))
      (multiple-value-bind (received open)
          (ethereum-lisp.snap-sync::snap-sync-fetch-storage-commitment-request
           target-database source state-root
           (list (cons account-hash storage-root)) 350)
        (is (= 1 received))
        (is (not (null open))))
      (is (not (null response)))
      (when response
        (let* ((groups
                 (ethereum-lisp.snap:snap-storage-ranges-slots response))
               (prefix (car (last groups)))
               (last-slot (car (last prefix)))
               (expected
                 (ethereum-lisp.snap-sync::snap-sync-adaptive-storage-task-count
                  (length prefix)
                  (ethereum-lisp.snap:snap-storage-data-hash last-slot)))
               (tasks
                 (ethereum-lisp.snap-sync::snap-sync-load-or-create-storage-tasks
                  target-database state-root account-hash storage-root)))
          ;; Drive the shipped nil-bound request and buffered persistence seam.
          ;; A fixed sixteen-way implementation makes both witnesses fail.
          (is (< expected
                 ethereum-lisp.snap-sync::+snap-sync-storage-task-count+))
          (is (= expected
                 (count-if-not
                  #'ethereum-lisp.snap-sync::snap-sync-account-task-completed-p
                  tasks))))))))

(deftest snap-storage-range-page-publishes-proved-subtrees
  (:layer :integration :module :p2p)
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-memory-key-value-database))
         (address
           (address-from-hex
            "0x0000000000000000000000000000000000000046"))
         (account-hash
           (ethereum-lisp.crypto:keccak-256 (address-bytes address))))
    (loop for byte from 1 to 128
          do (state-db-set-storage
              source-state address
              (make-hash32 (make-byte-vector 32 :initial-element byte))
              (+ 4000 byte)))
    (let* ((state-root (state-db-root source-state))
           (storage-root (state-db-get-storage-root source-state address))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (source (snap-test-source backend))
           (origin (make-byte-vector 32))
           (limit (make-byte-vector 32 :initial-element #xff))
           (task
             (ethereum-lisp.snap-sync::snap-sync-account-task
              :start origin :limit limit :next-origin origin
              :completed-p nil)))
      (let* ((ethereum-lisp.snap-sync::*snap-sync-healed-subtree-prefix-nibbles*
               1)
             (ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles*
               1)
             (ethereum-lisp.snap-sync::*snap-sync-range-nested-subtree-prefix-nibbles*
               1)
             (result
               (ethereum-lisp.snap-sync::snap-sync-prepare-storage-page
                source state-root account-hash storage-root 0 task
                (* 512 1024))))
        (is
         (ethereum-lisp.snap-sync::snap-sync-storage-page-result-next-origin
          result))
        (is
         (plusp
          (length
           (ethereum-lisp.snap-sync::snap-sync-storage-page-result-healed-subtrees
            result))))
        (ethereum-lisp.snap-sync::snap-sync-commit-storage-page
         target-database state-root account-hash storage-root
         (list task) result)
        (is
         (every
          (lambda (reference)
            (ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p
             target-database reference :storage))
          (ethereum-lisp.snap-sync::snap-sync-storage-page-result-healed-subtrees
           result)))))))

(deftest snap-legacy-storage-cursors-never-promote-root-closure
  (:layer :unit :module :p2p)
  (let* ((state (make-state-db))
         (database (make-memory-key-value-database))
         (address
           (address-from-hex
            "0x0000000000000000000000000000000000000047"))
         (account-hash
           (ethereum-lisp.crypto:keccak-256 (address-bytes address))))
    (loop for byte from 1 to 128
          do (state-db-set-storage
              state address
              (make-hash32 (make-byte-vector 32 :initial-element byte))
              (+ 5000 byte)))
    (let* ((state-root
             (progn
               (state-db-root state)
               (mpt-persist
                database (ethereum-lisp.state::state-db-state-trie state))))
           (object (ethereum-lisp.state::state-db-get-object state address))
           (storage-root
             (mpt-persist
              database
              (ethereum-lisp.state::state-object-storage-trie object)))
           (commitment (cons account-hash storage-root))
           (tasks
             (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
              :count ethereum-lisp.snap-sync::+snap-sync-storage-task-count+
              :completed-p t))
           (batch (make-kv-write-batch)))
      (ethereum-lisp.snap-sync::snap-sync-populate-deferred-storage-batch
       batch state-root commitment)
      (ethereum-lisp.snap-sync::snap-sync-populate-deferred-storage-plan-batch
       batch state-root)
      (loop for task in tasks
            for task-index from 0
            do (ethereum-lisp.snap-sync::snap-sync-populate-storage-task-batch
                batch state-root account-hash storage-root task-index task))
      ;; Simulate the short-lived v4 deployment that published a root-shaped
      ;; ordinary storage proof from cursor completion alone.
      (ethereum-lisp.snap-sync::snap-sync-populate-healed-subtree-batch
       batch (hash32-bytes storage-root) :storage)
      (kv-apply-batch database batch)
      (let ((ethereum-lisp.snap-sync::*snap-sync-healed-subtree-prefix-nibbles*
              1)
            (ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles*
              1)
            (ethereum-lisp.snap-sync::*snap-sync-range-nested-subtree-prefix-nibbles*
              1))
        (let ((references
                (mpt-hashed-subtrees-at-prefix-depth
                 (make-persisted-mpt
                  storage-root
                  (lambda (hash) (trie-node-store-get database hash)))
                 1)))
          (is (plusp (length references)))
          (is
           (zerop
            (ethereum-lisp.snap-sync::snap-sync-promote-complete-range-plan
             database state-root)))
          (is
           (not
            (ethereum-lisp.snap-sync::snap-sync-storage-plan-promoted-p
             database storage-root)))
          (is
           (not
            (ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p
             database (hash32-bytes storage-root) :storage)))
          (is
           (not
            (ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p
             database (hash32-bytes storage-root) :storage-root)))
          (is
           (notany
            (lambda (reference)
              (ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p
               database reference :storage))
            references)))))))

#+sbcl
(deftest snap-large-storage-range-verifies-before-source-release-and-materializes-after
  (:layer :integration :module :p2p)
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (address
           (address-from-hex
            "0x0000000000000000000000000000000000000048"))
         (account-hash
           (ethereum-lisp.crypto:keccak-256 (address-bytes address)))
         (direct-calls 0)
         (verified-calls 0)
         (verified-before-release-p nil))
    (loop for byte from 1 to 128
          do (state-db-set-storage
              source-state address
              (make-hash32 (make-byte-vector 32 :initial-element byte))
              (+ 6000 byte)))
    (let* ((state-root (state-db-root source-state))
           (storage-root (state-db-get-storage-root source-state address))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base-source (snap-test-source backend))
           (source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (ethereum-lisp.snap-sync:snap-sync-source-account-range
               base-source)
              ;; The pre-fix partition path called this callback and therefore
              ;; released a production pool reservation before proof checking.
              :storage-ranges
              (lambda (request)
                (declare (ignore request))
                (incf direct-calls)
                (error "Unverified large-storage callback was used"))
              :storage-ranges-verified
              (lambda (request verifier)
                (incf verified-calls)
                (let ((result
                        (funcall
                         verifier
                         (funcall
                          (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
                           base-source)
                          request))))
                  ;; This assignment occurs before the callback returns, which
                  ;; is the source-pool reservation boundary in production.
                  ;; Only the authenticated carrier may exist here; expanding
                  ;; it into trie records and subtree metadata happens after
                  ;; this callback returns the peer to the idle pool.
                  (setf verified-before-release-p
                        (typep
                         result
                         'ethereum-lisp.snap-sync::snap-sync-verified-storage-page))
                  result))
              :bytecodes
              (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base-source)
              :trie-nodes
              (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
               base-source)))
           (origin (make-byte-vector 32))
           (task
             (ethereum-lisp.snap-sync::snap-sync-account-task
              :start origin
              :limit (make-byte-vector 32 :initial-element #xff)
              :next-origin origin :completed-p nil))
           (result
             (ethereum-lisp.snap-sync::snap-sync-prepare-storage-page
              source state-root account-hash storage-root 0 task 350)))
      (is (= 0 direct-calls))
      (is (= 1 verified-calls))
      (is verified-before-release-p)
      (is
       (typep
        result
        'ethereum-lisp.snap-sync::snap-sync-storage-page-result))
      (is
       (ethereum-lisp.snap-sync::snap-sync-storage-page-result-next-origin
        result)))))

#+sbcl
(deftest snap-large-storage-ranges-use-live-sources-concurrently
  (:layer :integration :module :p2p)
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-memory-key-value-database))
         (address
           (address-from-hex
            "0x0000000000000000000000000000000000000045"))
         (account-hash
           (ethereum-lisp.crypto:keccak-256 (address-bytes address)))
         (lock (sb-thread:make-mutex :name "snap-test-storage-sources"))
         (changed
           (sb-thread:make-waitqueue :name "snap-test-storage-sources"))
         (active 0)
         (max-active 0)
         (fast-calls 0)
         (fast-reused-before-slow-release-p nil))
    (loop for byte from 1 to 128
          do (state-db-set-storage
              source-state address
              (make-hash32 (make-byte-vector 32 :initial-element byte))
              (+ 3000 byte)))
    (let* ((root (state-db-root source-state))
           (storage-root (state-db-get-storage-root source-state address))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base-source (snap-test-source backend))
           (slow-first-p t)
           (slow-source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (ethereum-lisp.snap-sync:snap-sync-source-account-range
               base-source)
              :storage-ranges
              (lambda (request)
                (let ((wait-p slow-first-p))
                  (when wait-p
                    (setf slow-first-p nil))
                  (sb-thread:with-mutex (lock)
                    (incf active)
                    (setf max-active (max max-active active))
                    (when (and wait-p (< fast-calls 2))
                      ;; The fast source broadcasts after every call.  Its
                      ;; first call is not the witness: re-check the predicate
                      ;; after every wakeup so suite load cannot let a valid
                      ;; early broadcast release this synthetic slow peer.
                      (loop repeat 20
                            while (< fast-calls 2)
                            do (sb-thread:condition-wait
                                changed lock :timeout 1/4)))
                    (when wait-p
                      (setf fast-reused-before-slow-release-p
                            (>= fast-calls 2))))
                  (unwind-protect
                       (funcall
                        (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
                         base-source)
                        request)
                    (sb-thread:with-mutex (lock)
                      (decf active)))))
              :bytecodes
              (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base-source)
              :trie-nodes
              (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
               base-source)))
           (fast-source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (ethereum-lisp.snap-sync:snap-sync-source-account-range
               base-source)
              :storage-ranges
              (lambda (request)
                (sb-thread:with-mutex (lock)
                  (incf fast-calls)
                  (incf active)
                  (setf max-active (max max-active active))
                  (when (>= fast-calls 2)
                    (sb-thread:condition-broadcast changed)))
                (unwind-protect
                     (funcall
                      (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
                       base-source)
                      request)
                  (sb-thread:with-mutex (lock)
                    (decf active))))
              :bytecodes
              (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base-source)
              :trie-nodes
              (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
               base-source)))
           (sources (list slow-source fast-source)))
      (is (ethereum-lisp.snap-sync::snap-sync-fill-storage-root
           target-database sources root account-hash storage-root
           (* 512 1024)))
      (is (= 2 max-active))
      (is fast-reused-before-slow-release-p))))

#+sbcl
(deftest snap-global-storage-lanes-rotate-across-large-roots
  (:layer :integration :module :p2p)
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-memory-key-value-database))
         (address-a
           (address-from-hex
            "0x0000000000000000000000000000000000000046"))
         (address-b
           (address-from-hex
            "0x0000000000000000000000000000000000000047"))
         (account-a
           (ethereum-lisp.crypto:keccak-256 (address-bytes address-a)))
         (account-b
           (ethereum-lisp.crypto:keccak-256 (address-bytes address-b)))
         (lock (sb-thread:make-mutex :name "snap-test-global-storage"))
         (changed
           (sb-thread:make-waitqueue :name "snap-test-global-storage"))
         (active 0)
         (max-active 0)
         (slow-a-active-p nil)
         (slow-a-used-p nil)
         (slow-a-saw-b-before-timeout-p nil)
         (b-calls 0)
         (b-overlapped-a-p nil)
         (result-a nil)
         (result-b nil)
         (condition-a nil)
         (condition-b nil))
    (loop for byte from 1 to 64
          do
             (let ((slot
                     (make-hash32
                      (make-byte-vector 32 :initial-element byte))))
               (state-db-set-storage
                source-state address-a slot (+ 4000 byte))
               (state-db-set-storage
                source-state address-b slot (+ 5000 byte))))
    (let* ((state-root (state-db-root source-state))
           (storage-a (state-db-get-storage-root source-state address-a))
           (storage-b (state-db-get-storage-root source-state address-b))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base-source (snap-test-source backend))
           (storage-function
             (lambda (request)
               (let* ((requested
                        (first
                         (ethereum-lisp.snap:snap-get-storage-ranges-accounts
                          request)))
                      (a-p (bytes= requested account-a))
                      (slow-p nil))
                 (sb-thread:with-mutex (lock)
                   (incf active)
                   (setf max-active (max max-active active))
                   (cond
                     ((and a-p (not slow-a-used-p))
                      (setf slow-a-used-p t
                            slow-a-active-p t
                            slow-p t)
                      (sb-thread:condition-broadcast changed))
                     ((bytes= requested account-b)
                      (incf b-calls)
                      (when slow-a-active-p
                        (setf b-overlapped-a-p t))
                      (sb-thread:condition-broadcast changed))))
                 (when slow-p
                   ;; The bound keeps a deliberately serial mutation red
                   ;; without hanging the complete cold integration suite.
                   (sb-thread:with-mutex (lock)
                     (loop repeat 40
                           while (zerop b-calls)
                           do (sb-thread:condition-wait
                               changed lock :timeout 1/20))
                     (setf slow-a-saw-b-before-timeout-p
                           (plusp b-calls))))
                 (unwind-protect
                      (funcall
                       (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
                        base-source)
                       request)
                   (sb-thread:with-mutex (lock)
                     (when slow-p (setf slow-a-active-p nil))
                     (decf active)
                     (sb-thread:condition-broadcast changed))))))
           (make-source
             (lambda ()
               (ethereum-lisp.snap-sync:make-snap-sync-source
                :account-range
                (ethereum-lisp.snap-sync:snap-sync-source-account-range
                 base-source)
                :storage-ranges storage-function
                :bytecodes
                (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base-source)
                :trie-nodes
                (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
                 base-source))))
           (sources (list (funcall make-source) (funcall make-source)))
           (runtime
             (ethereum-lisp.snap-sync::make-snap-sync-multi-runtime
              nil 0 nil))
           (workers '())
           (caller-a nil)
           (caller-b nil))
      (unwind-protect
           (progn
             (sb-thread:with-mutex
                 ((ethereum-lisp.snap-sync::snap-sync-multi-runtime-lock
                   runtime))
               (setf
                (ethereum-lisp.snap-sync::snap-sync-multi-runtime-storage-sources
                 runtime)
                sources
                (ethereum-lisp.snap-sync::snap-sync-multi-runtime-storage-worker-count
                 runtime)
                (length sources)))
             (dolist (source sources)
               (let ((worker-source source))
                 (push
                  (sb-thread:make-thread
                   (lambda ()
                     (ethereum-lisp.snap-sync::snap-sync-multi-storage-worker
                      runtime target-database worker-source state-root 350))
                   :name "snap-test-global-storage-worker")
                  workers)))
             (setf
              caller-a
              (sb-thread:make-thread
               (lambda ()
                 (handler-case
                     (setf result-a
                           (ethereum-lisp.snap-sync::snap-sync-multi-fill-storage-root
                            runtime target-database state-root account-a
                            storage-a))
                   (serious-condition (condition)
                     (setf condition-a condition))))
               :name "snap-test-global-storage-root-a"))
             (sb-thread:with-mutex (lock)
               (loop repeat 40
                     until slow-a-active-p
                     do (sb-thread:condition-wait
                         changed lock :timeout 1/20)))
             (setf
              caller-b
              (sb-thread:make-thread
               (lambda ()
                 (handler-case
                     (setf result-b
                           (ethereum-lisp.snap-sync::snap-sync-multi-fill-storage-root
                            runtime target-database state-root account-b
                            storage-b))
                   (serious-condition (condition)
                     (setf condition-b condition))))
               :name "snap-test-global-storage-root-b"))
             (sb-thread:join-thread caller-a)
             (setf caller-a nil)
             (sb-thread:join-thread caller-b)
             (setf caller-b nil))
        (sb-thread:with-mutex
            ((ethereum-lisp.snap-sync::snap-sync-multi-runtime-lock runtime))
          (setf
           (ethereum-lisp.snap-sync::snap-sync-multi-runtime-stopped-p runtime)
           t)
          (ethereum-lisp.snap-sync::snap-sync-multi-notify runtime))
        (when caller-a (ignore-errors (sb-thread:join-thread caller-a)))
        (when caller-b (ignore-errors (sb-thread:join-thread caller-b)))
        (dolist (worker workers)
          (sb-thread:join-thread worker)))
      (is (null condition-a))
      (is (null condition-b))
      (is result-a)
      (is result-b)
      (is (= 2 max-active))
      (is b-overlapped-a-p)
      (is slow-a-saw-b-before-timeout-p)
      (is (plusp b-calls))
      (is
       (ethereum-lisp.snap-sync::snap-sync-storage-range-tasks-completed-p
        target-database state-root account-a storage-a))
      (is
       (ethereum-lisp.snap-sync::snap-sync-storage-range-tasks-completed-p
        target-database state-root account-b storage-b)))))

#+sbcl
(deftest snap-global-storage-cursors-share-one-buffered-batch
  (:layer :integration :module :p2p)
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-instance 'snap-counting-test-database))
         (address-a
           (address-from-hex
            "0x0000000000000000000000000000000000000050"))
         (address-b
           (address-from-hex
            "0x0000000000000000000000000000000000000051"))
         (account-a
           (ethereum-lisp.crypto:keccak-256 (address-bytes address-a)))
         (account-b
           (ethereum-lisp.crypto:keccak-256 (address-bytes address-b))))
    (state-db-set-storage
     source-state address-a
     (make-hash32 (make-byte-vector 32 :initial-element 17)) 8001)
    (state-db-set-storage
     source-state address-b
     (make-hash32 (make-byte-vector 32 :initial-element 18)) 8002)
    (let* ((state-root (state-db-root source-state))
           (storage-a (state-db-get-storage-root source-state address-a))
           (storage-b (state-db-get-storage-root source-state address-b))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (source (snap-test-source backend))
           (tasks-a
             (ethereum-lisp.snap-sync::snap-sync-load-or-create-storage-tasks
              target-database state-root account-a storage-a))
           (tasks-b
             (ethereum-lisp.snap-sync::snap-sync-load-or-create-storage-tasks
              target-database state-root account-b storage-b))
           (job-a
             (ethereum-lisp.snap-sync::make-snap-sync-global-storage-job
              account-a storage-a tasks-a))
           (job-b
             (ethereum-lisp.snap-sync::make-snap-sync-global-storage-job
              account-b storage-b tasks-b))
           (result-a
             (ethereum-lisp.snap-sync::snap-sync-prepare-storage-page
              source state-root account-a storage-a 0 (first tasks-a) 4096))
           (result-b
             (ethereum-lisp.snap-sync::snap-sync-prepare-storage-page
              source state-root account-b storage-b 0 (first tasks-b) 4096))
           (runtime
             (ethereum-lisp.snap-sync::make-snap-sync-multi-runtime
              nil 0 nil))
           (thread-a nil)
           (thread-b nil)
           (condition-a nil)
           (condition-b nil))
      (setf
       (gethash
        0
        (ethereum-lisp.snap-sync::snap-sync-global-storage-job-claims job-a))
       source
       (gethash
        0
        (ethereum-lisp.snap-sync::snap-sync-global-storage-job-claims job-b))
       source
       (snap-counting-test-database-apply-count target-database) 0
       (snap-counting-test-database-batch-sizes target-database) '()
       (snap-counting-test-database-batch-prefixes target-database) '())
      ;; Hold the coordinator while both independently verified responses enter
      ;; its queue. Releasing it must buffer both cursor/content pairs through
      ;; one atomic KV batch. The owning account cursor supplies the later
      ;; durability seam, so storage delivery itself must not force an fsync.
      (sb-thread:with-mutex
          ((ethereum-lisp.snap-sync::snap-sync-multi-runtime-storage-write-lock
            runtime))
        (setf
         thread-a
         (sb-thread:make-thread
          (lambda ()
            (handler-case
                (ethereum-lisp.snap-sync::snap-sync-multi-commit-storage-page
                 runtime target-database state-root job-a 0 source result-a)
              (serious-condition (condition)
                (setf condition-a condition))))
          :name "snap-test-storage-batch-a")
         thread-b
         (sb-thread:make-thread
          (lambda ()
            (handler-case
                (ethereum-lisp.snap-sync::snap-sync-multi-commit-storage-page
                 runtime target-database state-root job-b 0 source result-b)
              (serious-condition (condition)
                (setf condition-b condition))))
          :name "snap-test-storage-batch-b"))
        (sb-thread:with-mutex
            ((ethereum-lisp.snap-sync::snap-sync-multi-runtime-lock runtime))
          (loop repeat 40
                while
                  (< (length
                      (ethereum-lisp.snap-sync::snap-sync-multi-runtime-storage-results
                       runtime))
                     2)
                do (sb-thread:condition-wait
                    (ethereum-lisp.snap-sync::snap-sync-multi-runtime-changed
                     runtime)
                    (ethereum-lisp.snap-sync::snap-sync-multi-runtime-lock
                     runtime)
                    :timeout 1/20))
          (is
           (= 2
              (length
               (ethereum-lisp.snap-sync::snap-sync-multi-runtime-storage-results
                runtime))))))
      (sb-thread:join-thread thread-a)
      (sb-thread:join-thread thread-b)
      (is (null condition-a))
      (is (null condition-b))
      (is (= 1 (snap-counting-test-database-apply-count target-database)))
      (is (= 1
             (snap-counting-test-database-buffered-apply-count
              target-database)))
      (is
       (ethereum-lisp.snap-sync::snap-sync-account-task-completed-p
        (first
         (ethereum-lisp.snap-sync::snap-sync-global-storage-job-tasks job-a))))
      (is
       (ethereum-lisp.snap-sync::snap-sync-account-task-completed-p
        (first
         (ethereum-lisp.snap-sync::snap-sync-global-storage-job-tasks
          job-b)))))))

#+sbcl
(deftest snap-global-storage-lane-requeues-a-failed-partition
  (:layer :integration :module :p2p)
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-memory-key-value-database))
         (address
           (address-from-hex
            "0x0000000000000000000000000000000000000048"))
         (account-hash
           (ethereum-lisp.crypto:keccak-256 (address-bytes address)))
         (lock (sb-thread:make-mutex :name "snap-test-storage-failover"))
         (changed
           (sb-thread:make-waitqueue :name "snap-test-storage-failover"))
         (failed-calls 0)
         (healthy-calls 0)
         (result nil)
         (caller-condition nil))
    (loop for byte from 1 to 64
          do (state-db-set-storage
              source-state address
              (make-hash32 (make-byte-vector 32 :initial-element byte))
              (+ 6000 byte)))
    (let* ((state-root (state-db-root source-state))
           (storage-root (state-db-get-storage-root source-state address))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base-source (snap-test-source backend))
           (failing-source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (ethereum-lisp.snap-sync:snap-sync-source-account-range
               base-source)
              :storage-ranges
              (lambda (request)
                (declare (ignore request))
                (sb-thread:with-mutex (lock)
                  (incf failed-calls)
                  (sb-thread:condition-broadcast changed))
                (error "synthetic StorageRanges transport failure"))
              :bytecodes
              (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base-source)
              :trie-nodes
              (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
               base-source)))
           (healthy-source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (ethereum-lisp.snap-sync:snap-sync-source-account-range
               base-source)
              :storage-ranges
              (lambda (request)
                (incf healthy-calls)
                (funcall
                 (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
                  base-source)
                 request))
              :bytecodes
              (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base-source)
              :trie-nodes
              (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
               base-source)))
           (runtime
             (ethereum-lisp.snap-sync::make-snap-sync-multi-runtime
              nil 0 nil))
           (failing-worker nil)
           (healthy-worker nil)
           (caller nil))
      (unwind-protect
           (progn
             ;; Count the deliberately late healthy lane up front. The waiter
             ;; must not classify the finite source set as exhausted between
             ;; the failed claim's release and the positive failover control.
             (setf
              (ethereum-lisp.snap-sync::snap-sync-multi-runtime-storage-worker-count
               runtime)
              2)
             (setf
              failing-worker
              (sb-thread:make-thread
               (lambda ()
                 (ethereum-lisp.snap-sync::snap-sync-multi-storage-worker
                  runtime target-database failing-source state-root 350))
               :name "snap-test-failing-storage-lane")
              caller
              (sb-thread:make-thread
               (lambda ()
                 (handler-case
                     (setf result
                           (ethereum-lisp.snap-sync::snap-sync-multi-fill-storage-root
                            runtime target-database state-root account-hash
                            storage-root))
                   (serious-condition (condition)
                     (setf caller-condition condition))))
               :name "snap-test-storage-failover-caller"))
             (sb-thread:with-mutex (lock)
               (loop repeat 40
                     while (zerop failed-calls)
                     do (sb-thread:condition-wait
                         changed lock :timeout 1/20)))
             (setf
              healthy-worker
              (sb-thread:make-thread
               (lambda ()
                 (ethereum-lisp.snap-sync::snap-sync-multi-storage-worker
                  runtime target-database healthy-source state-root 350))
               :name "snap-test-healthy-storage-lane"))
             (sb-thread:join-thread caller)
             (setf caller nil))
        (sb-thread:with-mutex
            ((ethereum-lisp.snap-sync::snap-sync-multi-runtime-lock runtime))
          (setf
           (ethereum-lisp.snap-sync::snap-sync-multi-runtime-stopped-p runtime)
           t)
          (ethereum-lisp.snap-sync::snap-sync-multi-notify runtime))
        (when caller (ignore-errors (sb-thread:join-thread caller)))
        (when failing-worker (sb-thread:join-thread failing-worker))
        (when healthy-worker (sb-thread:join-thread healthy-worker)))
      (is (= 1 failed-calls))
      (is (plusp healthy-calls))
      (is (null caller-condition))
      (is result)
      (is
       (ethereum-lisp.snap-sync::snap-sync-storage-range-tasks-completed-p
        target-database state-root account-hash storage-root)))))

#+sbcl
(deftest snap-global-storage-local-commit-failure-is-fatal
  (:layer :integration :module :p2p)
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-instance 'snap-failing-test-database))
         (address
           (address-from-hex
            "0x0000000000000000000000000000000000000049"))
         (account-hash
           (ethereum-lisp.crypto:keccak-256 (address-bytes address))))
    (loop for byte from 1 to 32
          do (state-db-set-storage
              source-state address
              (make-hash32 (make-byte-vector 32 :initial-element byte))
              (+ 7000 byte)))
    (let* ((state-root (state-db-root source-state))
           (storage-root (state-db-get-storage-root source-state address))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (source (snap-test-source backend))
           (runtime
             (ethereum-lisp.snap-sync::make-snap-sync-multi-runtime
              nil 0 nil))
           (worker nil)
           (failure nil))
      ;; Initialize the durable cursors before arming the failure so the
      ;; injected generic database error occurs only after a verified page.
      (ethereum-lisp.snap-sync::snap-sync-load-or-create-storage-tasks
       target-database state-root account-hash storage-root)
      (setf
       (snap-failing-test-database-fail-next-buffered-apply-p
        target-database)
       t
       (ethereum-lisp.snap-sync::snap-sync-multi-runtime-storage-worker-count
        runtime)
       1
       worker
       (sb-thread:make-thread
        (lambda ()
          (ethereum-lisp.snap-sync::snap-sync-multi-storage-worker
           runtime target-database source state-root 350))
        :name "snap-test-storage-local-commit-failure"))
      (unwind-protect
           (setf failure
                 (handler-case
                     (progn
                       (ethereum-lisp.snap-sync::snap-sync-multi-fill-storage-root
                        runtime target-database state-root account-hash
                        storage-root)
                       nil)
                   (serious-condition (condition) condition)))
        (sb-thread:with-mutex
            ((ethereum-lisp.snap-sync::snap-sync-multi-runtime-lock runtime))
          (setf
           (ethereum-lisp.snap-sync::snap-sync-multi-runtime-stopped-p runtime)
           t)
          (ethereum-lisp.snap-sync::snap-sync-multi-notify runtime))
        (when worker (sb-thread:join-thread worker)))
      (is failure)
      (when failure
        (is (search "Simulated snap buffered batch failure"
                    (princ-to-string failure)))
        (is (not
             (typep
              failure
              'ethereum-lisp.snap-sync:snap-sync-sources-exhausted)))))))

#+sbcl
(deftest snap-multi-account-pages-apply-memory-backpressure
  (:layer :unit :module :p2p)
  ;; Match geth's accountConcurrency while retaining a hard bound below the
  ;; sixty-four durable scheduling partitions.
  (is (= 16 ethereum-lisp.snap-sync::+snap-sync-account-inflight-pages+))
  (let* ((progress
           (ethereum-lisp.snap-sync::snap-sync-make-progress
            :pivot-hash (make-hash32 (snap-test-hash 231))
            :pivot-number 1
            :state-root (make-hash32 (snap-test-hash 232))
            :partial-root +empty-trie-hash+
            :target-hash (make-hash32 (snap-test-hash 233))
            :chain-id 560048
            :genesis-hash (make-hash32 (snap-test-hash 234))
            :authority-id (make-hash32 (snap-test-hash 235))
            :completed-p nil :complete-node-scheme-p t
            :tasks
            (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
             :count 64)))
         (runtime
           (ethereum-lisp.snap-sync::make-snap-sync-multi-runtime
            progress 1 nil))
         (source (list :source))
         (waiter nil)
         (claimed-index nil)
         (claimed-task nil))
    (unwind-protect
         (progn
           (dotimes
               (expected
                ethereum-lisp.snap-sync::+snap-sync-account-inflight-pages+)
             (multiple-value-bind (index task)
                 (ethereum-lisp.snap-sync::snap-sync-multi-claim-task
                  runtime source)
               (is (= expected index))
               (is task)))
           (setf waiter
                 (sb-thread:make-thread
                  (lambda ()
                    (multiple-value-setq (claimed-index claimed-task)
                      (ethereum-lisp.snap-sync::snap-sync-multi-claim-task
                       runtime source)))
                  :name "snap-test-account-backpressure"))
           (is (eq :blocked
                   (sb-thread:join-thread
                    waiter :timeout 0.1 :default :blocked)))
           (ethereum-lisp.snap-sync::snap-sync-multi-release-claim
            runtime 0 source)
           (is (not (eq :timeout
                        (sb-thread:join-thread
                         waiter :timeout 5 :default :timeout))))
           (setf waiter nil)
           (is (= 0 claimed-index))
           (is claimed-task)
           (is (= ethereum-lisp.snap-sync::+snap-sync-account-inflight-pages+
                  (hash-table-count
                   (ethereum-lisp.snap-sync::snap-sync-multi-runtime-claims
                    runtime)))))
      (sb-thread:with-mutex
          ((ethereum-lisp.snap-sync::snap-sync-multi-runtime-lock runtime))
        (setf
         (ethereum-lisp.snap-sync::snap-sync-multi-runtime-stopped-p runtime)
         t)
        (ethereum-lisp.snap-sync::snap-sync-multi-notify runtime))
      (when waiter
        (ignore-errors
          (sb-thread:join-thread waiter :timeout 5 :default nil))))))

#+sbcl
(deftest snap-multi-range-gc-is-disabled-between-phase-boundaries
  (:layer :unit :module :p2p)
  (is (null ethereum-lisp.snap-sync::*snap-sync-range-full-gc-pages*))
  (let ((runtime
          (ethereum-lisp.snap-sync::make-snap-sync-multi-runtime nil 0 nil)))
    (setf (ethereum-lisp.snap-sync::snap-sync-multi-runtime-pages runtime)
          1000000)
    (is (not (ethereum-lisp.snap-sync::snap-sync-multi-range-gc-due-p
              runtime)))
    (is (zerop
           (ethereum-lisp.snap-sync::snap-sync-multi-runtime-last-full-gc-pages
            runtime)))))

(deftest snap-sync-progress-v5-round-trips-and-migrates-v2-v4
  (:layer :unit :module :p2p)
  (let* ((pivot (make-hash32 (snap-test-hash 131)))
         (state-root (make-hash32 (snap-test-hash 132)))
         (target (make-hash32 (snap-test-hash 133)))
         (genesis (make-hash32 (snap-test-hash 134)))
         (authority (make-hash32 (snap-test-hash 135)))
         (tasks
           (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
            :count 16))
         (progress
           (ethereum-lisp.snap-sync::snap-sync-make-progress
            :pivot-hash pivot :pivot-number 42 :state-root state-root
            :partial-root +empty-trie-hash+ :target-hash target
            :chain-id 560048 :genesis-hash genesis :authority-id authority
            :completed-p nil :complete-node-scheme-p t :tasks tasks))
         (record
           (ethereum-lisp.snap-sync::snap-sync-progress-record progress))
         (round-tripped
           (ethereum-lisp.snap-sync::snap-sync-progress-from-record record))
         (healing-progress
           (ethereum-lisp.snap-sync::snap-sync-make-progress
            :pivot-hash pivot :pivot-number 43 :state-root state-root
            :partial-root +empty-trie-hash+ :target-hash target
            :chain-id 560048 :genesis-hash genesis :authority-id authority
            :completed-p nil :complete-node-scheme-p t
            :tasks
            (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
             :count 16 :completed-p t)))
         (healing-round-tripped
           (ethereum-lisp.snap-sync::snap-sync-progress-from-record
            (ethereum-lisp.snap-sync::snap-sync-progress-record
             healing-progress)))
         (legacy-cursor
           (let ((bytes (make-byte-vector 32)))
             (setf (aref bytes 0) #x20)
             bytes))
         (legacy-record
           (rlp-encode
            (make-rlp-list
             2 (hash32-bytes pivot) 42 (hash32-bytes state-root)
             legacy-cursor (hash32-bytes +empty-trie-hash+)
             (hash32-bytes target) 560048 (hash32-bytes genesis)
             (hash32-bytes authority) 0)))
         (legacy
           (ethereum-lisp.snap-sync::snap-sync-progress-from-record
            legacy-record))
         (v4-record
           (let* ((fields
                    (copy-list
                     (rlp-list-items (rlp-decode-one record))))
                  (v4-fields
                    (append (subseq fields 0 11)
                            (list (nth 12 fields)))))
             (setf (first v4-fields) 4)
             (rlp-encode (apply #'make-rlp-list v4-fields))))
         (v4
           (ethereum-lisp.snap-sync::snap-sync-progress-from-record
            v4-record))
         (migrated
           (ethereum-lisp.snap-sync::snap-sync-progress-with-task-count
            legacy
            ethereum-lisp.snap-sync::+snap-sync-account-task-count+)))
    (is (= 16
           (length
            (ethereum-lisp.snap-sync:snap-sync-progress-tasks
             round-tripped))))
    (is
     (ethereum-lisp.snap-sync::snap-sync-progress-complete-node-scheme-p
      round-tripped))
    (is
     (not
      (ethereum-lisp.snap-sync::snap-sync-progress-complete-node-scheme-p
       legacy)))
    (is (= 16
           (length
            (ethereum-lisp.snap-sync:snap-sync-progress-tasks v4))))
    (is
     (not
      (ethereum-lisp.snap-sync::snap-sync-progress-complete-node-scheme-p
       v4)))
    (is (eq round-tripped
            (ethereum-lisp.snap-sync::snap-sync-progress-with-task-count
             round-tripped
             ethereum-lisp.snap-sync::+snap-sync-account-task-count+)))
    ;; Completed flat ranges are not a publishable pivot until trie healing
    ;; reaches the exact consensus-authorized state root.  Preserve that
    ;; explicit incomplete flag both in memory and across durable round-trip.
    (is (not (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
              healing-progress)))
    (is (not (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
              healing-round-tripped)))
    (is (every
         #'ethereum-lisp.snap-sync:snap-sync-account-task-completed-p
         (ethereum-lisp.snap-sync:snap-sync-progress-tasks
          healing-round-tripped)))
    (is (bytes= (make-byte-vector 32)
                (ethereum-lisp.snap-sync:snap-sync-progress-next-origin
                 round-tripped)))
    (is (= 1
           (length
            (ethereum-lisp.snap-sync:snap-sync-progress-tasks legacy))))
    (is (= 64
           (length
            (ethereum-lisp.snap-sync:snap-sync-progress-tasks migrated))))
    (is
     (every #'ethereum-lisp.snap-sync:snap-sync-account-task-completed-p
            (subseq
             (ethereum-lisp.snap-sync:snap-sync-progress-tasks migrated)
             0 2)))
    (is (bytes= legacy-cursor
                (ethereum-lisp.snap-sync:snap-sync-progress-next-origin
                 migrated)))
    ;; Mutate one encoded task start so the record no longer covers a
    ;; contiguous keyspace. A round trip alone would not exercise this check.
    (let* ((fields
             (copy-list
              (rlp-list-items (rlp-decode-one record))))
           (task-objects
             (copy-list (rlp-list-items (nth 12 fields))))
           (second-fields
             (copy-list (rlp-list-items (second task-objects)))))
      (setf (first second-fields) (make-byte-vector 32)
            (second task-objects) (apply #'make-rlp-list second-fields)
            (nth 12 fields) (apply #'make-rlp-list task-objects))
      (signals error
        (ethereum-lisp.snap-sync::snap-sync-progress-from-record
         (rlp-encode (apply #'make-rlp-list fields)))))))

(deftest snap-complete-node-scheme-never-trusts-a-legacy-trie-store
  (:layer :unit :module :p2p)
  (let ((fresh (make-memory-key-value-database))
        (legacy (make-memory-key-value-database))
        (legacy-epoch (make-memory-key-value-database))
        (malformed (make-memory-key-value-database)))
    (is
     (ethereum-lisp.snap-sync::snap-sync-enable-complete-node-scheme-p
      fresh))
    (is
     (ethereum-lisp.snap-sync::snap-sync-complete-node-scheme-present-p
      fresh))
    (let ((batch (make-kv-write-batch)))
      (ethereum-lisp.database:kv-batch-put-chain-record
       batch :trie-node (snap-test-hash 136) #(1 2 3))
      (kv-apply-batch legacy batch))
    (is
     (not
      (ethereum-lisp.snap-sync::snap-sync-enable-complete-node-scheme-p
       legacy)))
    (is
     (not
      (ethereum-lisp.snap-sync::snap-sync-complete-node-scheme-present-p
       legacy)))
    (let ((batch (make-kv-write-batch)))
      (ethereum-lisp.database:kv-batch-put-chain-record
       batch :metadata
       ethereum-lisp.snap-sync::+snap-sync-complete-node-scheme-identifier+
       ethereum-lisp.snap-sync::+snap-sync-legacy-complete-node-scheme-value+)
      (ethereum-lisp.database:kv-batch-put-chain-record
       batch :trie-node (snap-test-hash 137) #(1 2 3))
      (kv-apply-batch legacy-epoch batch))
    ;; Epoch one is recognized so an upgrade can preserve its content, but its
    ;; absent negative markers no longer authorize a subtree skip.
    (is
     (not
      (ethereum-lisp.snap-sync::snap-sync-complete-node-scheme-present-p
       legacy-epoch)))
    (is
     (not
      (ethereum-lisp.snap-sync::snap-sync-enable-complete-node-scheme-p
       legacy-epoch)))
    (let ((batch (make-kv-write-batch)))
      (ethereum-lisp.database:kv-batch-put-chain-record
       batch :metadata
       ethereum-lisp.snap-sync::+snap-sync-complete-node-scheme-identifier+
       #(3))
      (kv-apply-batch malformed batch))
    (signals ethereum-lisp.validation:storage-error
      (ethereum-lisp.snap-sync::snap-sync-enable-complete-node-scheme-p
       malformed))
    (ethereum-lisp.snap-sync::snap-sync-disable-complete-node-scheme fresh)
    (is
     (not
      (ethereum-lisp.snap-sync::snap-sync-complete-node-scheme-present-p
       fresh)))))

(deftest snap-state-healer-invalidates-pre-closure-safe-fast-paths
  (:layer :integration :module :p2p)
  ;; The live Hoodi upgrade exposed a persisted v1 range plan and negative-node
  ;; marker that could reduce a non-empty state to one skipped storage root,
  ;; publish completion, and fail later when execution opened a missing child.
  ;; Preserve all content, but prove that every old completion namespace is a
  ;; cache miss and the authorized account root is traversed again.
  (let* ((database (make-memory-key-value-database))
         (account-value
           (state-account-rlp (make-state-account :nonce 1 :balance 42)))
         (leaf-object
           (make-rlp-list
            (ethereum-lisp.trie.encoding:hex-prefix-encode
             (make-byte-vector 63) :terminator t)
            account-value))
         (leaf-encoded (rlp-encode leaf-object))
         (leaf-reference (keccak-256 leaf-encoded))
         (branch-object
           (apply
            #'make-rlp-list
            (append
             (list leaf-reference)
             (loop repeat 15 collect (make-byte-vector 0))
             (list (make-byte-vector 0)))))
         (branch-encoded (rlp-encode branch-object))
         (root-reference (keccak-256 branch-encoded))
         (pivot (make-hash32 (snap-test-hash 138)))
         (progress
           (ethereum-lisp.snap-sync::snap-sync-make-progress
            :pivot-hash pivot :pivot-number 44
            :state-root (make-hash32 root-reference)
            :partial-root +empty-trie-hash+
            :target-hash (make-hash32 (snap-test-hash 139))
            :chain-id 560048
            :genesis-hash (make-hash32 (snap-test-hash 140))
            :authority-id (make-hash32 (snap-test-hash 141))
            :completed-p nil :complete-node-scheme-p t
            :tasks
            (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
             :count 1 :completed-p t)))
         (trie-calls 0)
         (fetched nil)
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) (declare (ignore request)))
            :storage-ranges (lambda (request) (declare (ignore request)))
            :bytecodes (lambda (request) (declare (ignore request)))
            :trie-nodes
            (lambda (request)
              (declare (ignore request))
              (incf trie-calls)
              (ethereum-lisp.snap:make-snap-trie-nodes
               1 (list leaf-encoded))))))
    (let ((batch (make-kv-write-batch)))
      (kv-batch-put-chain-record
       batch :trie-node root-reference branch-encoded)
      (kv-batch-put-chain-record
       batch :metadata
       ethereum-lisp.snap-sync::+snap-sync-complete-node-scheme-identifier+
       ethereum-lisp.snap-sync::+snap-sync-legacy-complete-node-scheme-value+)
      (kv-batch-put-chain-record
       batch :metadata
       (concatenate
        'vector (ascii-to-bytes "snap-deferred-storage-plan-v1:")
        root-reference)
       #(1))
      (kv-batch-put-chain-record
       batch :metadata
       (concatenate
        'vector (ascii-to-bytes "snap-healed-subtree-v1:") leaf-reference)
       #(1))
      (kv-apply-batch database batch))
    (is
     (not
      (ethereum-lisp.snap-sync::snap-sync-deferred-storage-plan-present-p
       database (make-hash32 root-reference))))
    (let ((ethereum-lisp.snap-sync::*snap-sync-healed-subtree-prefix-nibbles*
            1)
          (ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles*
            1)
          (ethereum-lisp.snap-sync::*snap-sync-range-nested-subtree-prefix-nibbles*
            1))
      (let ((completed
              (ethereum-lisp.snap-sync::snap-sync-heal-state
               database (list source) progress 350
               :on-heal-progress
               (lambda (snapshot)
                 (when
                     (ethereum-lisp.snap-sync:snap-sync-heal-progress-completed-p
                      snapshot)
                   (setf fetched
                         (ethereum-lisp.snap-sync:snap-sync-heal-progress-fetched-nodes
                          snapshot)))))))
        (is
         (ethereum-lisp.snap-sync:snap-sync-progress-completed-p completed))))
    (is (= 1 trie-calls))
    (is (= 1 fetched))
    (multiple-value-bind (encoded present-p)
        (ethereum-lisp.trie:trie-node-store-get database leaf-reference)
      (is present-p)
      (is (bytes= encoded leaf-encoded)))
    (multiple-value-bind (state-root present-p)
        (kv-get-chain-record database :state-history (hash32-bytes pivot))
      (is present-p)
      (is (bytes= state-root root-reference)))))

(deftest snap-sync-progress-expands-thirty-two-durable-cursors-to-sixty-four
  (:layer :unit :module :p2p)
  (let* ((old
           (ethereum-lisp.snap-sync::snap-sync-make-account-tasks :count 32))
         (new-boundaries
           (ethereum-lisp.snap-sync::snap-sync-task-boundaries 64))
         (cursor (car (nth 3 new-boundaries)))
         (tasks
           (append
            (list
             (ethereum-lisp.snap-sync::snap-sync-account-task
              :start
              (ethereum-lisp.snap-sync:snap-sync-account-task-start
               (first old))
              :limit
              (ethereum-lisp.snap-sync:snap-sync-account-task-limit
               (first old))
              :completed-p t)
             (ethereum-lisp.snap-sync::snap-sync-account-task
              :start
              (ethereum-lisp.snap-sync:snap-sync-account-task-start
               (second old))
              :limit
              (ethereum-lisp.snap-sync:snap-sync-account-task-limit
               (second old))
              :next-origin cursor))
            (cddr old)))
         (progress
           (ethereum-lisp.snap-sync::snap-sync-make-progress
            :pivot-hash (make-hash32 (snap-test-hash 141))
            :pivot-number 42
            :state-root (make-hash32 (snap-test-hash 142))
            :partial-root +empty-trie-hash+
            :target-hash (make-hash32 (snap-test-hash 143))
            :chain-id 560048
            :genesis-hash (make-hash32 (snap-test-hash 144))
            :authority-id (make-hash32 (snap-test-hash 145))
            :completed-p nil :tasks tasks))
         (migrated
           (ethereum-lisp.snap-sync::snap-sync-progress-with-task-count
            progress 64))
         (expanded
           (ethereum-lisp.snap-sync:snap-sync-progress-tasks migrated))
         (round-tripped
           (ethereum-lisp.snap-sync::snap-sync-progress-from-record
            (ethereum-lisp.snap-sync::snap-sync-progress-record migrated))))
    (is (= 64 (length expanded)))
    (is (every
         #'ethereum-lisp.snap-sync:snap-sync-account-task-completed-p
         (subseq expanded 0 3)))
    (is (bytes= cursor
                (ethereum-lisp.snap-sync:snap-sync-account-task-next-origin
                 (fourth expanded))))
    (is (= 64
           (length
            (ethereum-lisp.snap-sync:snap-sync-progress-tasks
             round-tripped))))))

(deftest snap-account-cursors-share-one-durable-publication-batch
  (:layer :unit :module :p2p)
  (let* ((database (make-instance 'snap-counting-test-database))
         (tasks
           (ethereum-lisp.snap-sync::snap-sync-make-account-tasks :count 16))
         (state-root (make-hash32 (snap-test-hash 151)))
         (progress
           (ethereum-lisp.snap-sync::snap-sync-make-progress
            :pivot-hash (make-hash32 (snap-test-hash 150))
            :pivot-number 77 :state-root state-root
            :partial-root +empty-trie-hash+
            :target-hash (make-hash32 (snap-test-hash 152))
            :chain-id 560048
            :genesis-hash (make-hash32 (snap-test-hash 153))
            :authority-id (make-hash32 (snap-test-hash 154))
            :completed-p nil :tasks tasks))
         (results
           (loop for task in tasks
                 for index from 0
                 collect
                 (ethereum-lisp.snap-sync::make-snap-sync-page-result
                  :task-index index
                  :origin
                  (copy-seq
                   (ethereum-lisp.snap-sync:snap-sync-account-task-next-origin
                    task))
                  :completed-p t))))
    (multiple-value-bind (next snapshots)
        (ethereum-lisp.snap-sync::snap-sync-commit-account-pages
         database progress results)
      (is (= 1 (snap-counting-test-database-apply-count database)))
      (is (= 16 (length snapshots)))
      (is
       (every #'ethereum-lisp.snap-sync:snap-sync-account-task-completed-p
              (ethereum-lisp.snap-sync:snap-sync-progress-tasks next)))
      (multiple-value-bind (durable present-p)
          (ethereum-lisp.snap-sync:snap-sync-read-progress database)
        (is present-p)
        (is
         (every #'ethereum-lisp.snap-sync:snap-sync-account-task-completed-p
                (ethereum-lisp.snap-sync:snap-sync-progress-tasks durable)))))))

#+sbcl
(deftest snap-account-range-buffers-records-before-dependencies
  (:layer :integration :module :p2p)
  (multiple-value-bind (source-state addresses)
      (snap-test-partitioned-state)
    (declare (ignore addresses))
    (let* ((source-database (make-memory-key-value-database))
           (target-database (make-memory-key-value-database))
           (root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (source (snap-test-source backend))
           (task
             (first
              (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
               :count 64)))
           (work
             (ethereum-lisp.snap-sync::snap-sync-prepare-account-page-range
              target-database source root 0 task (* 512 1024)))
           (references
             (ethereum-lisp.snap-sync::snap-sync-account-page-work-account-record-hashes
              work)))
      (is (plusp (length references)))
      (is
       (every
        (lambda (reference)
          (nth-value 1 (trie-node-store-get target-database reference)))
        references))
      ;; The cursor is intentionally still absent. The buffered records are
      ;; harmless idempotent content until dependency completion publishes it.
      (is (not (nth-value
                1
                (ethereum-lisp.snap-sync:snap-sync-read-progress
                 target-database)))))))

#+sbcl
(deftest snap-state-import-multi-keeps-three-account-peers-busy-across-sixty-four-ranges
  (:layer :integration :module :p2p)
  (multiple-value-bind (source-state addresses)
      (snap-test-partitioned-state)
    (let* ((source-database (make-memory-key-value-database))
           (target-database (make-memory-key-value-database))
           (root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base-source (snap-test-source backend))
           (lock (sb-thread:make-mutex :name "snap-test-three-source"))
           (changed (sb-thread:make-waitqueue
                     :name "snap-test-three-source"))
           (arrived 0)
           (released-p nil)
           (active 0)
           (max-active 0)
           (byte-limits '())
           (sources
             (loop repeat 3
                   collect
                   (let ((source-calls 0))
                     (snap-test-source-with-account-callback
                      base-source
                      (lambda (request)
                        (let ((barrier-p
                                (sb-thread:with-mutex (lock)
                                  (= (incf source-calls) 1))))
                          (when barrier-p
                            (sb-thread:with-mutex (lock)
                              (incf arrived)
                              (incf active)
                              (setf max-active (max max-active active))
                              (push
                               (ethereum-lisp.snap:snap-get-account-range-bytes
                                request)
                               byte-limits)
                              (when (= arrived 3)
                                (setf released-p t)
                                (sb-thread:condition-broadcast changed))
                              (loop until released-p
                                    do (sb-thread:condition-wait changed lock))))
                          (unwind-protect
                               (funcall
                                (ethereum-lisp.snap-sync:snap-sync-source-account-range
                                 base-source)
                                request)
                            (when barrier-p
                              (sb-thread:with-mutex (lock)
                                (decf active))))))))))
           (progress
             (ethereum-lisp.snap-sync:snap-sync-import-state-multi
              target-database sources
              :pivot-hash (make-hash32 (snap-test-hash 136))
              :pivot-number 900 :state-root root
              :target-hash (make-hash32 (snap-test-hash 137))
              :chain-id 560048
              :genesis-hash (make-hash32 (snap-test-hash 138))
              :authority-id (make-hash32 (snap-test-hash 139)))))
      (is (= 3 max-active))
      (is (= 3 (length byte-limits)))
      (is (every (lambda (limit) (= limit (* 512 1024))) byte-limits))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p progress))
      (is (= 64
             (length
              (ethereum-lisp.snap-sync:snap-sync-progress-tasks progress))))
      (is
       (every #'ethereum-lisp.snap-sync:snap-sync-account-task-completed-p
              (ethereum-lisp.snap-sync:snap-sync-progress-tasks progress)))
      (let ((trie
              (make-persisted-mpt
               root
               (lambda (hash)
                 (trie-node-store-get target-database hash)))))
        (dolist (address addresses)
          (is (nth-value
               1 (mpt-get trie (keccak-256 (address-bytes address))))))))))

#+sbcl
(deftest snap-state-import-multi-admits-new-range-sources
  (:layer :integration :module :p2p)
  (multiple-value-bind (source-state addresses)
      (snap-test-partitioned-state)
    (declare (ignore addresses))
    (let* ((source-database (make-memory-key-value-database))
           (target-database (make-memory-key-value-database))
           (root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base-source (snap-test-source backend))
           (lock (sb-thread:make-mutex :name "snap-test-live-range-sources"))
           (calls (make-array 3 :initial-element 0))
           (sources
             (loop for index below 3
                   collect
                   (let ((worker-index index))
                     (snap-test-source-with-account-callback
                      base-source
                      (lambda (request)
                        (sb-thread:with-mutex (lock)
                          (incf (aref calls worker-index)))
                        (funcall
                         (ethereum-lisp.snap-sync:snap-sync-source-account-range
                          base-source)
                         request))))))
           (provider-calls 0)
           (progress
             (ethereum-lisp.snap-sync:snap-sync-import-state-multi
              target-database (list (first sources))
              :pivot-hash (make-hash32 (snap-test-hash 229))
              :pivot-number 906 :state-root root
              :target-hash (make-hash32 (snap-test-hash 230))
              :chain-id 560048
              :genesis-hash (make-hash32 (snap-test-hash 231))
              :authority-id (make-hash32 (snap-test-hash 232))
              :heal-source-provider
              (lambda ()
                (incf provider-calls)
                sources))))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p progress))
      (is (plusp provider-calls))
      (is (plusp (aref calls 0)))
      ;; Account callbacks distinguish range work from the later healer.
      (is (plusp (aref calls 1)))
      (is (plusp (aref calls 2))))))

#+sbcl
(deftest snap-state-import-multi-resumes-tasks-without-replaying-completed-ranges
  (:layer :integration :module :p2p)
  (multiple-value-bind (source-state addresses)
      (snap-test-partitioned-state)
    (declare (ignore addresses))
    (let* ((source-database (make-memory-key-value-database))
           (target-database (make-memory-key-value-database))
           (root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base-source (snap-test-source backend))
           (sources
             (loop repeat 3
                   collect
                   (snap-test-source-with-account-callback
                    base-source
                    (ethereum-lisp.snap-sync:snap-sync-source-account-range
                     base-source))))
           (arguments
             (list
              :pivot-hash (make-hash32 (snap-test-hash 140))
              :pivot-number 901 :state-root root
              :target-hash (make-hash32 (snap-test-hash 141))
              :chain-id 560048
              :genesis-hash (make-hash32 (snap-test-hash 142))
              :authority-id (make-hash32 (snap-test-hash 143))))
           (first
             (apply #'ethereum-lisp.snap-sync:snap-sync-import-state-multi
                    target-database sources :max-pages 3 arguments))
           (completed-starts
             (loop for task in
                     (ethereum-lisp.snap-sync:snap-sync-progress-tasks first)
                   when
                     (ethereum-lisp.snap-sync:snap-sync-account-task-completed-p
                      task)
                     collect
                     (ethereum-lisp.snap-sync:snap-sync-account-task-start
                      task)))
           (request-lock
             (sb-thread:make-mutex :name "snap-test-resume-origins"))
           (resume-origins '())
           (resume-sources
             (loop repeat 3
                   collect
                   (snap-test-source-with-account-callback
                    base-source
                    (lambda (request)
                      (sb-thread:with-mutex (request-lock)
                        (push
                         (copy-seq
                          (ethereum-lisp.snap:snap-get-account-range-origin
                           request))
                         resume-origins))
                      (funcall
                       (ethereum-lisp.snap-sync:snap-sync-source-account-range
                        base-source)
                       request)))))
           (completed
             (apply #'ethereum-lisp.snap-sync:snap-sync-import-state-multi
                    target-database resume-sources arguments)))
      (is (not (ethereum-lisp.snap-sync:snap-sync-progress-completed-p first)))
      (is (= 3 (length completed-starts)))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p completed))
      (dolist (origin resume-origins)
        (is (not (find origin completed-starts :test #'bytes=)))))))

#+sbcl
(deftest snap-state-import-multi-refreshes-sources-after-exhaustion
  (:layer :integration :module :p2p)
  (multiple-value-bind (source-state addresses)
      (snap-test-partitioned-state)
    (declare (ignore addresses))
    (let* ((source-database (make-memory-key-value-database))
           (target-database (make-memory-key-value-database))
           (root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base-source (snap-test-source backend))
           (lock (sb-thread:make-mutex :name "snap-test-source-refresh"))
           (first-generation-requests 0)
           (first-generation-progress 0)
           (first-generation-profiles '())
           (first-generation-errors 0)
           (retired-source
             (snap-test-source-with-account-callback
              base-source
              (lambda (request)
                (let ((request-number
                        (sb-thread:with-mutex (lock)
                          (incf first-generation-requests))))
                  (if (= request-number 1)
                      (funcall
                       (ethereum-lisp.snap-sync:snap-sync-source-account-range
                        base-source)
                       request)
                      (error "First snap source generation retired"))))))
           (arguments
             (list
              :pivot-hash (make-hash32 (snap-test-hash 157))
              :pivot-number 905 :state-root root
              :target-hash (make-hash32 (snap-test-hash 158))
              :chain-id 560048
              :genesis-hash (make-hash32 (snap-test-hash 159))
              :authority-id (make-hash32 (snap-test-hash 160))))
           (exhaustion
             (handler-case
                 (progn
                   (apply
                    #'ethereum-lisp.snap-sync:snap-sync-import-state-multi
                    target-database (list retired-source)
                    :on-progress
                    (lambda (progress source task-index)
                      (declare (ignore progress source task-index))
                      (incf first-generation-progress))
                    :on-page-profile
                    (lambda (profile source task-index)
                      (declare (ignore source task-index))
                      (push profile first-generation-profiles))
                    :on-source-error
                    (lambda (source condition)
                      (declare (ignore source condition))
                      (incf first-generation-errors))
                    arguments)
                   nil)
               (ethereum-lisp.snap-sync:snap-sync-sources-exhausted
                   (condition)
                 condition))))
      (is (not (null exhaustion)))
      (when exhaustion
        (is (eq :account-ranges
                (ethereum-lisp.snap-sync:snap-sync-sources-exhausted-phase
                 exhaustion)))
        (is (= 1
               (length
                (ethereum-lisp.snap-sync:snap-sync-sources-exhausted-failures
                 exhaustion)))))
      ;; Positive witnesses: one verified page committed, then the same source
      ;; really failed on its next claim and reached the aggregate boundary.
      (is (= 2 first-generation-requests))
      (is (= 1 first-generation-progress))
      (is (= 1 (length first-generation-profiles)))
      (when first-generation-profiles
        (let ((profile (first first-generation-profiles)))
          (is (typep profile
                     'ethereum-lisp.snap-sync:snap-sync-page-profile))
          (is (plusp
               (ethereum-lisp.snap-sync:snap-sync-page-profile-account-count
                profile)))
          (is (plusp
               (ethereum-lisp.snap-sync:snap-sync-page-profile-trie-record-count
                profile)))
          (is (<=
               (ethereum-lisp.snap-sync:snap-sync-page-profile-incomplete-node-count
                profile)
               (ethereum-lisp.snap-sync:snap-sync-page-profile-trie-record-count
                profile)))
          (is (>=
               (ethereum-lisp.snap-sync:snap-sync-page-profile-total-ms
                profile)
               (ethereum-lisp.snap-sync:snap-sync-page-profile-account-request-ms
                profile)))
          (is (not
               (minusp
                (ethereum-lisp.snap-sync:snap-sync-page-profile-buffer-ms
                 profile))))))
      (is (= 1 first-generation-errors))
      (multiple-value-bind (persisted present-p)
          (ethereum-lisp.snap-sync:snap-sync-read-progress target-database)
        (is present-p)
        (when present-p
          (let* ((completed-starts
                   (loop for task in
                           (ethereum-lisp.snap-sync:snap-sync-progress-tasks
                            persisted)
                         when
                           (ethereum-lisp.snap-sync:snap-sync-account-task-completed-p
                            task)
                           collect
                           (ethereum-lisp.snap-sync:snap-sync-account-task-start
                            task)))
                 (resume-origins '())
                 (replacement-source
                   (snap-test-source-with-account-callback
                    base-source
                    (lambda (request)
                      (sb-thread:with-mutex (lock)
                        (push
                         (copy-seq
                          (ethereum-lisp.snap:snap-get-account-range-origin
                           request))
                         resume-origins))
                      (funcall
                       (ethereum-lisp.snap-sync:snap-sync-source-account-range
                        base-source)
                       request))))
                 (completed
                   (apply
                    #'ethereum-lisp.snap-sync:snap-sync-import-state-multi
                    target-database (list replacement-source) arguments)))
            (is (= 1 (length completed-starts)))
            (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
                 completed))
            (is (plusp (length resume-origins)))
            (dolist (start completed-starts)
              (is (not (find start resume-origins :test #'bytes=))))))))))

#+sbcl
(deftest snap-state-import-multi-batch-failure-keeps-all-task-cursors-behind
  (:layer :integration :module :p2p)
  (multiple-value-bind (source-state addresses)
      (snap-test-partitioned-state)
    (declare (ignore addresses))
    (let* ((source-database (make-memory-key-value-database))
           (target-database (make-instance 'snap-failing-test-database))
           (root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base-source (snap-test-source backend))
           (sources
             (loop repeat 3
                   collect
                   (snap-test-source-with-account-callback
                    base-source
                    (ethereum-lisp.snap-sync:snap-sync-source-account-range
                     base-source))))
           (arguments
             (list
              :pivot-hash (make-hash32 (snap-test-hash 144))
              :pivot-number 902 :state-root root
              :target-hash (make-hash32 (snap-test-hash 145))
              :chain-id 560048
              :genesis-hash (make-hash32 (snap-test-hash 146))
              :authority-id (make-hash32 (snap-test-hash 147)))))
      (is
       (ethereum-lisp.snap-sync::snap-sync-enable-complete-node-scheme-p
        target-database))
      (setf (snap-failing-test-database-fail-next-apply-p target-database) t)
      (let ((failure
              (handler-case
                  (progn
                    (apply #'ethereum-lisp.snap-sync:snap-sync-import-state-multi
                           target-database sources arguments)
                    nil)
                (serious-condition (condition) condition))))
        (is (not (null failure)))
        ;; A local commit/merge fault must reach the caller unchanged.  If this
        ;; becomes source exhaustion, the production coordinator would loop on
        ;; a corrupt or unwritable database instead of failing closed.
        (when failure
          (is (not
               (typep
                failure
                'ethereum-lisp.snap-sync:snap-sync-sources-exhausted)))))
      (is (not (nth-value
                1
                (ethereum-lisp.snap-sync:snap-sync-read-progress
                 target-database))))
      (let ((completed
              (apply #'ethereum-lisp.snap-sync:snap-sync-import-state-multi
                     target-database sources arguments)))
        (is
         (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
          completed))))))

#+sbcl
(deftest snap-state-import-multi-requeues-a-failed-sources-task
  (:layer :integration :module :p2p)
  (multiple-value-bind (source-state addresses)
      (snap-test-partitioned-state)
    (declare (ignore addresses))
    (let* ((source-database (make-memory-key-value-database))
           (target-database (make-memory-key-value-database))
           (root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base-source (snap-test-source backend))
           (lock (sb-thread:make-mutex :name "snap-test-source-failover"))
           (failed-origin nil)
           (healthy-origins '())
           (source-errors 0)
           (failing-source
             (snap-test-source-with-account-callback
              base-source
              (lambda (request)
                (sb-thread:with-mutex (lock)
                  (setf failed-origin
                        (copy-seq
                         (ethereum-lisp.snap:snap-get-account-range-origin
                          request))))
                (error "Simulated snap peer failure"))))
           (healthy-sources
             (loop repeat 2
                   collect
                   (snap-test-source-with-account-callback
                    base-source
                    (lambda (request)
                      (sb-thread:with-mutex (lock)
                        (push
                         (copy-seq
                          (ethereum-lisp.snap:snap-get-account-range-origin
                           request))
                         healthy-origins))
                      (funcall
                       (ethereum-lisp.snap-sync:snap-sync-source-account-range
                        base-source)
                       request)))))
           (progress
             (ethereum-lisp.snap-sync:snap-sync-import-state-multi
              target-database
              (cons failing-source healthy-sources)
              :pivot-hash (make-hash32 (snap-test-hash 148))
              :pivot-number 903 :state-root root
              :target-hash (make-hash32 (snap-test-hash 149))
              :chain-id 560048
              :genesis-hash (make-hash32 (snap-test-hash 150))
              :authority-id (make-hash32 (snap-test-hash 151))
              :on-source-error
              (lambda (source condition)
                (declare (ignore source condition))
                (sb-thread:with-mutex (lock)
                  (incf source-errors))))))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p progress))
      (is (= 1 source-errors))
      (is failed-origin)
      ;; The failed source's durable claim was released before the callback;
      ;; a healthy worker then fetched the exact same task origin.
      (is (find failed-origin healthy-origins :test #'bytes=)))))

#+sbcl
(deftest snap-state-import-multi-retries-a-request-timeout-on-the-same-source
  (:layer :integration :module :p2p)
  (multiple-value-bind (source-state addresses)
      (snap-test-partitioned-state)
    (declare (ignore addresses))
    (let* ((source-database (make-memory-key-value-database))
           (target-database (make-memory-key-value-database))
           (root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base-source (snap-test-source backend))
           (calls 0)
           (source-errors 0)
           (source
             (snap-test-source-with-account-callback
              base-source
              (lambda (request)
                (if (= 1 (incf calls))
                    (error
                     'ethereum-lisp.snap-sync:snap-sync-request-timeout)
                    (funcall
                     (ethereum-lisp.snap-sync:snap-sync-source-account-range
                      base-source)
                     request)))))
           (progress
             (ethereum-lisp.snap-sync:snap-sync-import-state-multi
              target-database (list source)
              :pivot-hash (make-hash32 (snap-test-hash 248))
              :pivot-number 913 :state-root root
              :target-hash (make-hash32 (snap-test-hash 249))
              :chain-id 560048
              :genesis-hash (make-hash32 (snap-test-hash 250))
              :authority-id (make-hash32 (snap-test-hash 251))
              :on-source-error
              (lambda (failed condition)
                (declare (ignore failed condition))
                (incf source-errors)))))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p progress))
      (is (< 1 calls))
      ;; A request expiry is not a source/session verdict and must not consume
      ;; the source-error callback or the source identity for this import.
      (is (zerop source-errors)))))

#+sbcl
(deftest snap-state-import-multi-preserves-all-source-state-unavailability
  (:layer :integration :module :p2p)
  (let* ((database (make-memory-key-value-database))
         (requests 0)
         (callbacks 0)
         (lock (sb-thread:make-mutex :name "snap-test-pruned-pivot"))
         (sources
           (loop repeat 3
                 collect
                 (ethereum-lisp.snap-sync:make-snap-sync-source
                  :account-range
                  (lambda (request)
                    (declare (ignore request))
                    (sb-thread:with-mutex (lock)
                      (incf requests))
                    (ethereum-lisp.snap-sync:snap-sync-state-unavailable
                     "account-range"))
                  :storage-ranges (lambda (request) (declare (ignore request)))
                  :bytecodes (lambda (request) (declare (ignore request)))
                  :trie-nodes (lambda (request) (declare (ignore request)))))))
    (signals ethereum-lisp.snap-sync:snap-sync-state-unavailable
      (ethereum-lisp.snap-sync:snap-sync-import-state-multi
       database sources
       :pivot-hash (make-hash32 (snap-test-hash 152))
       :pivot-number 904
       :state-root (make-hash32 (snap-test-hash 153))
       :target-hash (make-hash32 (snap-test-hash 154))
       :chain-id 560048
       :genesis-hash (make-hash32 (snap-test-hash 155))
       :authority-id (make-hash32 (snap-test-hash 156))
       :on-source-error
       (lambda (source condition)
         (declare (ignore source))
         (is (typep condition
                    'ethereum-lisp.snap-sync:snap-sync-state-unavailable))
         (incf callbacks))))
    ;; Positive witnesses: every worker reached its source and every error was
    ;; observed by the coordinator before the aggregate type was re-signalled.
    (is (= 3 requests))
    (is (= 3 callbacks))))

#+sbcl
(deftest snap-state-import-multi-yields-a-stale-range-pivot-after-durability
  (:layer :integration :module :p2p)
  (multiple-value-bind (source-state addresses)
      (snap-test-partitioned-state)
    (declare (ignore addresses))
    (let* ((source-database (make-memory-key-value-database))
           (target-database (make-memory-key-value-database))
           (root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (source (snap-test-source backend))
           (yield-calls 0)
           (release-calls 0)
           (release-name
             'ethereum-lisp.snap-sync::snap-sync-release-range-phase-memory)
           (real-release (fdefinition release-name)))
      (unwind-protect
           (progn
             (setf (fdefinition release-name)
                   (lambda () (incf release-calls)))
             (signals ethereum-lisp.snap-sync:snap-sync-heal-yielded
               (ethereum-lisp.snap-sync:snap-sync-import-state-multi
                target-database (list source)
                :pivot-hash (make-hash32 (snap-test-hash 233))
                :pivot-number 907 :state-root root
                :target-hash (make-hash32 (snap-test-hash 234))
                :chain-id 560048
                :genesis-hash (make-hash32 (snap-test-hash 235))
                :authority-id (make-hash32 (snap-test-hash 236))
                :range-yield-p (lambda () (incf yield-calls) t)))
             (is (= 1 yield-calls))
             (is (= 1 release-calls))
             (multiple-value-bind (progress present-p)
                 (ethereum-lisp.snap-sync:snap-sync-read-progress
                  target-database)
               (is present-p)
               (when present-p
                 (is (not
                      (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
                       progress)))
                 ;; The coordinator durably commits the contiguous result
                 ;; prefix already queued when it observes the first event.
                 ;; Concurrent range/dependency workers may therefore publish
                 ;; more than one cursor at this boundary, but never zero or a
                 ;; falsely complete pivot.
                 (let* ((tasks
                          (ethereum-lisp.snap-sync:snap-sync-progress-tasks
                           progress))
                        (completed
                          (count-if
                           #'ethereum-lisp.snap-sync:snap-sync-account-task-completed-p
                           tasks)))
                   (is (plusp completed))
                   (is (< completed (length tasks)))))))
        (setf (fdefinition release-name) real-release)))))

(deftest snap-state-healing-reports-a-typed-source-generation-exhaustion
  (:layer :integration :module :p2p)
  (let* ((database (make-memory-key-value-database))
         (pivot (make-hash32 (snap-test-hash 161)))
         (root (make-hash32 (snap-test-hash 162)))
         (target (make-hash32 (snap-test-hash 163)))
         (genesis (make-hash32 (snap-test-hash 164)))
         (authority (make-hash32 (snap-test-hash 165)))
         (requests 0)
         (callbacks 0)
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) (declare (ignore request)))
            :storage-ranges (lambda (request) (declare (ignore request)))
            :bytecodes (lambda (request) (declare (ignore request)))
            :trie-nodes
            (lambda (request)
              (declare (ignore request))
              (incf requests)
              (error "Healing source disconnected"))))
         (progress
           (ethereum-lisp.snap-sync::snap-sync-make-progress
            :pivot-hash pivot :pivot-number 906 :state-root root
            :partial-root +empty-trie-hash+ :target-hash target
            :chain-id 560048 :genesis-hash genesis :authority-id authority
            :completed-p nil
            :tasks
            (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
             :count 1 :completed-p t)))
         (exhaustion
           (handler-case
               (progn
                 (ethereum-lisp.snap-sync::snap-sync-heal-state
                  database (list source) progress (* 2 1024 1024)
                  :on-source-error
                  (lambda (failed-source condition)
                    (declare (ignore failed-source condition))
                    (incf callbacks)))
                 nil)
             (ethereum-lisp.snap-sync:snap-sync-sources-exhausted (condition)
               condition))))
    (is (not (null exhaustion)))
    (when exhaustion
      (is (eq :healing
              (ethereum-lisp.snap-sync:snap-sync-sources-exhausted-phase
               exhaustion)))
      (is (= 1
             (length
              (ethereum-lisp.snap-sync:snap-sync-sources-exhausted-failures
               exhaustion)))))
    (is (= 1 requests))
    (is (= 1 callbacks))))

(deftest snap-one-wire-messages-round-trip
  (:layer :unit :module :p2p)
  (let* ((root (snap-test-hash 1))
         (origin (snap-test-hash 2))
         (limit (snap-test-hash 3))
         (account (ethereum-lisp.snap:make-snap-account-data
                   (snap-test-hash 4)
                   (make-rlp-list
                    (ensure-byte-vector #(1))
                    (ensure-byte-vector #(2))
                    (ensure-byte-vector #(3))
                    (ensure-byte-vector #(4)))))
         (slot (ethereum-lisp.snap:make-snap-storage-data
                (snap-test-hash 5) #(6 7))))
    (let ((decoded
            (snap-test-round-trip
             ethereum-lisp.snap:+snap-message-get-account-range+
             (ethereum-lisp.snap:make-snap-get-account-range
              11 root origin limit 1024))))
      (is (= 11 (ethereum-lisp.snap:snap-get-account-range-id decoded)))
      (is (bytes= root
                  (ethereum-lisp.snap:snap-get-account-range-root decoded))))
    (let ((decoded
            (snap-test-round-trip
             ethereum-lisp.snap:+snap-message-account-range+
             (ethereum-lisp.snap:make-snap-account-range
              11 (list account) (list #(8 9))))))
      (is (= 1 (length
                (ethereum-lisp.snap:snap-account-range-accounts decoded))))
      (is (= 1 (length
                (ethereum-lisp.snap:snap-account-range-proof decoded)))))
    (let ((decoded
            (snap-test-round-trip
             ethereum-lisp.snap:+snap-message-get-storage-ranges+
             (ethereum-lisp.snap:make-snap-get-storage-ranges
              12 root (list (snap-test-hash 4)) #(1) #(2) 2048))))
      (is (= 12
             (ethereum-lisp.snap:snap-get-storage-ranges-id decoded)))
      (is (= 1
             (length
              (ethereum-lisp.snap:snap-get-storage-ranges-accounts decoded)))))
    (let ((decoded
            (snap-test-round-trip
             ethereum-lisp.snap:+snap-message-storage-ranges+
             (ethereum-lisp.snap:make-snap-storage-ranges
              12 (list (list slot)) (list #(10))))))
      (is (= 1 (length
                (first
                 (ethereum-lisp.snap:snap-storage-ranges-slots decoded))))))
    (let ((decoded
            (snap-test-round-trip
             ethereum-lisp.snap:+snap-message-get-bytecodes+
             (ethereum-lisp.snap:make-snap-get-bytecodes
              13 (list (snap-test-hash 6)) 4096))))
      (is (= 13 (ethereum-lisp.snap:snap-get-bytecodes-id decoded))))
    (let ((decoded
            (snap-test-round-trip
             ethereum-lisp.snap:+snap-message-bytecodes+
             (ethereum-lisp.snap:make-snap-bytecodes
              13 (list #(1 2 3) #(4 5))))))
      (is (= 2 (length (ethereum-lisp.snap:snap-bytecodes-codes decoded)))))
    (let ((decoded
            (snap-test-round-trip
             ethereum-lisp.snap:+snap-message-get-trie-nodes+
             (ethereum-lisp.snap:make-snap-get-trie-nodes
              14 root (list (list #(1 2) #(3))) 8192))))
      (is (= 2
             (length
              (first
               (ethereum-lisp.snap:snap-get-trie-nodes-paths decoded))))))
    (let ((decoded
            (snap-test-round-trip
             ethereum-lisp.snap:+snap-message-trie-nodes+
             (ethereum-lisp.snap:make-snap-trie-nodes
              14 (list #(1 2 3))))))
      (is (= 1
             (length (ethereum-lisp.snap:snap-trie-nodes-nodes decoded)))))))

(deftest snap-state-backend-is-an-injected-boundary
  (:layer :unit :module :p2p)
  (let* ((root (snap-test-hash 1))
         (backend
           (ethereum-lisp.snap:make-snap-state-backend
            :account-range
            (lambda (request)
              (ethereum-lisp.snap:make-snap-account-range
               (ethereum-lisp.snap:snap-get-account-range-id request)
               '() '()))))
         (payload
           (ethereum-lisp.snap:encode-snap-message
            ethereum-lisp.snap:+snap-message-get-account-range+
            (ethereum-lisp.snap:make-snap-get-account-range
             99 root (snap-test-hash 0) (snap-test-hash 255) 1024))))
    (multiple-value-bind (message-id response)
        (ethereum-lisp.snap:snap-serve-request
         backend ethereum-lisp.snap:+snap-message-get-account-range+ payload)
      (is (= ethereum-lisp.snap:+snap-message-account-range+ message-id))
      (is (= 99
             (ethereum-lisp.snap:snap-account-range-id
              (ethereum-lisp.snap:decode-snap-message
               message-id response)))))
    (signals error
      (ethereum-lisp.snap:snap-serve-request
       backend
       ethereum-lisp.snap:+snap-message-get-bytecodes+
       (ethereum-lisp.snap:encode-snap-message
        ethereum-lisp.snap:+snap-message-get-bytecodes+
        (ethereum-lisp.snap:make-snap-get-bytecodes 1 '() 1024))))))

(deftest snap-wire-rejects-unbounded-or-malformed-fields
  (:layer :unit :module :p2p)
  (signals rlp-error
    (ethereum-lisp.snap:decode-snap-message
     ethereum-lisp.snap:+snap-message-bytecodes+
     (rlp-encode
      (make-rlp-list
       (integer-to-minimal-bytes 1)
       (apply #'make-rlp-list
              (loop repeat
                    (1+ ethereum-lisp.snap:+snap-max-list-items+)
                    collect (make-byte-vector 0)))))))
  (signals error
    (ethereum-lisp.snap:decode-snap-message
     ethereum-lisp.snap:+snap-message-get-account-range+
     (rlp-encode
      (make-rlp-list
       (integer-to-minimal-bytes 1)
       (make-byte-vector 33)
       (snap-test-hash 0)
       (snap-test-hash 255)
       (integer-to-minimal-bytes 1024))))))

(deftest snap-wire-accepts-two-mib-account-pages-over-the-old-item-cap
  (:layer :unit :module :p2p)
  ;; AccountRange is governed by the request's byte budget.  Real Hoodi peers
  ;; can exceed the old 16384-item ceiling in a geth-compatible two-MiB page,
  ;; so the account response needs its own frame-bounded count policy.
  (let* ((body
           (make-rlp-list
            (make-byte-vector 0) (make-byte-vector 0)
            (make-byte-vector 0) (make-byte-vector 0)))
         (accounts
           (loop for index below 16385
                 collect
                 (ethereum-lisp.snap:make-snap-account-data
                  (let ((hash (make-byte-vector 32)))
                    (setf (aref hash 30) (ldb (byte 8 8) index)
                          (aref hash 31) (ldb (byte 8 0) index))
                    hash)
                  body)))
         (encoded
           (ethereum-lisp.snap:encode-snap-message
            ethereum-lisp.snap:+snap-message-account-range+
            (ethereum-lisp.snap:make-snap-account-range 17 accounts '())))
         (decoded
           (ethereum-lisp.snap:decode-snap-message
            ethereum-lisp.snap:+snap-message-account-range+ encoded)))
    (is (= 16385
           (length
            (ethereum-lisp.snap:snap-account-range-accounts decoded))))))

(deftest snap-wire-accepts-geth-storage-range-slack-over-the-old-cap
  (:layer :unit :module :p2p)
  ;; Pinned geth 1.17.4 allows a storage response to exceed the requested byte
  ;; budget by 10 percent to avoid splitting a contract. Minimally sized slots
  ;; can consequently exceed the old 32768 ceiling even though the response is
  ;; a valid, frame-bounded answer to our two-MiB request.
  (let* ((count 32769)
         (slot
           (ethereum-lisp.snap:make-snap-storage-data
            (make-byte-vector 32) (rlp-encode 1)))
         (encoded
           (ethereum-lisp.snap:encode-snap-message
            ethereum-lisp.snap:+snap-message-storage-ranges+
            (ethereum-lisp.snap:make-snap-storage-ranges
             18 (list (loop repeat count collect slot)) '())))
         (decoded
           (ethereum-lisp.snap:decode-snap-message
            ethereum-lisp.snap:+snap-message-storage-ranges+ encoded)))
    (is (= count
           (length
            (first
             (ethereum-lisp.snap:snap-storage-ranges-slots decoded)))))
    (is (< count ethereum-lisp.snap:+snap-max-storage-slots-per-range+))))

(deftest snap-backend-serves-and-persists-runtime-state
  (:layer :integration :module :p2p)
  (let* ((state (make-state-db))
         (database (make-memory-key-value-database))
         (address-a
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (address-b
           (address-from-hex "0x0000000000000000000000000000000000000002")))
    (state-db-set-account state address-a
                          (make-state-account :nonce 1 :balance 100))
    (state-db-set-account state address-b
                          (make-state-account :nonce 2 :balance 200))
    (let* ((root (hash32-bytes (state-db-root state)))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              database state))
           (request
             (ethereum-lisp.snap:make-snap-get-account-range
              77 root (make-byte-vector 32)
              (make-byte-vector 32 :initial-element #xff) 100000)))
      (multiple-value-bind (message-id encoded)
          (ethereum-lisp.snap:snap-serve-request
           backend ethereum-lisp.snap:+snap-message-get-account-range+
           (ethereum-lisp.snap:encode-snap-message
            ethereum-lisp.snap:+snap-message-get-account-range+ request))
        (let ((response
                (ethereum-lisp.snap:decode-snap-message message-id encoded)))
          (is (= 2 (length
                    (ethereum-lisp.snap:snap-account-range-accounts response))))
          (is (plusp
               (length
                (ethereum-lisp.snap:snap-account-range-proof response))))))
      (multiple-value-bind (root-node present-p)
          (ethereum-lisp.trie:trie-node-store-get database root)
        (is present-p)
        (is (plusp (length root-node))))
      (let ((trie-request
              (ethereum-lisp.snap:make-snap-get-trie-nodes
               ;; snap trie-node paths use compact hex-prefix encoding. #(0)
               ;; is the account trie root path; a content hash is not a path.
               78 root (list (list #(0))) 100000)))
        (multiple-value-bind (message-id encoded)
            (ethereum-lisp.snap:snap-serve-request
             backend ethereum-lisp.snap:+snap-message-get-trie-nodes+
             (ethereum-lisp.snap:encode-snap-message
              ethereum-lisp.snap:+snap-message-get-trie-nodes+ trie-request))
          (let ((response
                  (ethereum-lisp.snap:decode-snap-message message-id encoded)))
            (is (= 1
                   (length
                    (ethereum-lisp.snap:snap-trie-nodes-nodes response))))))))))

(deftest snap-trie-node-server-caps-disk-lookups
  (:layer :integration :module :p2p)
  (multiple-value-bind (state addresses)
      (snap-test-partitioned-state)
    (declare (ignore addresses))
    (let* ((database (make-memory-key-value-database))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              database state))
           (limit
             ethereum-lisp.snap-sync::+snap-sync-trie-node-lookups-per-request+)
           (request
             (ethereum-lisp.snap:make-snap-get-trie-nodes
              79 (hash32-bytes (state-db-root state))
              (loop repeat (+ limit 17) collect (list #(0)))
              (* 8 1024 1024)))
           (response
             (snap-test-call-backend
              backend ethereum-lisp.snap:+snap-message-get-trie-nodes+
              request)))
      ;; The decoder permits a structurally bounded larger list, but serving it
      ;; must stop at pinned geth's disk-lookup boundary.
      (is (= 1024 limit))
      (is (= limit
             (length
              (ethereum-lisp.snap:snap-trie-nodes-nodes response)))))))

(deftest snap-backend-keeps-the-session-for-an-unavailable-state-root
  (:layer :integration :module :p2p)
  ;; Pinned geth treats a state root that this snap server does not retain as
  ;; an availability miss: it sends the matching empty response rather than
  ;; disconnecting the shared eth+snap session. A syncing peer legitimately
  ;; asks every advertised snap source before it knows which one has its pivot.
  (let* ((state (make-state-db))
         (database (make-memory-key-value-database))
         (backend
           (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
            database state))
         (unavailable-root (snap-test-hash 254)))
    (let ((response
            (snap-test-call-backend
             backend ethereum-lisp.snap:+snap-message-get-account-range+
             (ethereum-lisp.snap:make-snap-get-account-range
              31 unavailable-root (make-byte-vector 32)
              (make-byte-vector 32 :initial-element #xff) 100000))))
      (is (= 31 (ethereum-lisp.snap:snap-account-range-id response)))
      (is (null (ethereum-lisp.snap:snap-account-range-accounts response)))
      (is (null (ethereum-lisp.snap:snap-account-range-proof response))))
    (let ((response
            (snap-test-call-backend
             backend ethereum-lisp.snap:+snap-message-get-storage-ranges+
             (ethereum-lisp.snap:make-snap-get-storage-ranges
              32 unavailable-root (list (snap-test-hash 1))
              (make-byte-vector 0) (make-byte-vector 0) 100000))))
      (is (= 32 (ethereum-lisp.snap:snap-storage-ranges-id response)))
      (is (null (ethereum-lisp.snap:snap-storage-ranges-slots response)))
      (is (null (ethereum-lisp.snap:snap-storage-ranges-proof response))))
    (let ((response
            (snap-test-call-backend
             backend ethereum-lisp.snap:+snap-message-get-trie-nodes+
             (ethereum-lisp.snap:make-snap-get-trie-nodes
              33 unavailable-root (list (list #(0))) 100000))))
      (is (= 33 (ethereum-lisp.snap:snap-trie-nodes-id response)))
      (is (null (ethereum-lisp.snap:snap-trie-nodes-nodes response))))))

(deftest snap-storage-range-preserves-geth-canonical-trie-values
  (:layer :integration :module :p2p)
  ;; Pinned geth 3827178 sends StorageIterator.Slot() directly as
  ;; StorageData.Body and passes the received body directly to
  ;; trie.VerifyRangeProof. The bytes are already RLP(minimal uint256); they
  ;; must be neither decoded by the server nor re-encoded by the client.
  (let* ((state (make-state-db))
         (database (make-memory-key-value-database))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000042"))
         (slot (make-hash32 (make-byte-vector 32 :initial-element 7)))
         (expected-value (rlp-encode 256)))
    (state-db-set-storage state address slot 256)
    (let* ((state-root (state-db-root state))
           (storage-root (state-db-get-storage-root state address))
           (account-hash (keccak-256 (address-bytes address)))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              database state))
           (response
             (snap-test-call-backend
              backend ethereum-lisp.snap:+snap-message-get-storage-ranges+
              (ethereum-lisp.snap:make-snap-get-storage-ranges
               17 (hash32-bytes state-root) (list account-hash)
               (make-byte-vector 0) (make-byte-vector 0) 100000)))
           (groups (ethereum-lisp.snap:snap-storage-ranges-slots response))
           (wire-slot (and (first groups) (first (first groups)))))
      (is (= 1 (length groups)))
      (is (= 1 (length (first groups))))
      (when wire-slot
        (is (bytes= expected-value
                    (ethereum-lisp.snap:snap-storage-data-body wire-slot)))
        (let ((entries
                (ethereum-lisp.snap-sync::snap-sync-storage-entries
                 (list wire-slot))))
          (is (bytes= expected-value (cdar entries)))
          (is (mpt-verify-range-proof storage-root entries nil
                                      :start (make-byte-vector 32)))
          ;; This is the pre-fix client mutation: an extra RLP string wrapper
          ;; changes the committed root and must be detected.
          (signals error
            (mpt-verify-range-proof
             storage-root
             (list (cons (caar entries) (rlp-encode (cdar entries))))
             nil :start (make-byte-vector 32))))))))

(deftest snap-storage-range-rejects-noncanonical-trie-values
  (:layer :unit :module :p2p)
  (let ((hash (make-byte-vector 32)))
    (dolist (body
              (list
               ;; An unset slot cannot appear in a storage range.
               (rlp-encode 0)
               ;; Long form for a one-byte value is non-canonical RLP.
               (ensure-byte-vector #(#x81 #x01))
               ;; Storage leaves are byte strings, never lists.
               (ensure-byte-vector #(#xc0))
               ;; uint256 is at most 32 decoded bytes.
               (rlp-encode (make-byte-vector 33 :initial-element 1))))
      (signals error
        (ethereum-lisp.snap-sync::snap-sync-storage-entries
         (list (ethereum-lisp.snap:make-snap-storage-data hash body)))))))

(deftest snap-account-range-carries-a-verifiable-compact-boundary-proof
  (:layer :integration :module :p2p)
  (let ((state (make-state-db))
        (database (make-memory-key-value-database)))
    (dotimes (index 40)
      (let ((address (make-address
                      (concatenate
                       'vector (make-byte-vector 19) (vector (1+ index))))))
        (state-db-set-account
         state address (make-state-account :nonce index :balance (1+ index)))))
    (let* ((root (state-db-root state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              database state))
           (origin (make-byte-vector 32))
           (response
             (snap-test-call-backend
              backend ethereum-lisp.snap:+snap-message-get-account-range+
              (ethereum-lisp.snap:make-snap-get-account-range
               1 (hash32-bytes root) origin
               (make-byte-vector 32 :initial-element #xff) 300)))
           (entries
             (mapcar
              (lambda (account)
                (cons
                 (ethereum-lisp.snap:snap-account-data-hash account)
                 (ethereum-lisp.snap-sync::snap-sync-account-full-rlp account)))
              (ethereum-lisp.snap:snap-account-range-accounts response))))
      (is (plusp (length entries)))
      (is (< (length entries) 40))
      (is (plusp
           (length (ethereum-lisp.snap:snap-account-range-proof response))))
      (is (mpt-verify-range-proof
           root entries
           (ethereum-lisp.snap:snap-account-range-proof response)
           :start origin))
      (signals error
        (mpt-verify-range-proof
         root (rest entries)
         (ethereum-lisp.snap:snap-account-range-proof response)
         :start origin)))))

(deftest snap-account-range-full-page-reconstructs-without-a-proof
  (:layer :integration :module :p2p)
  (let ((state (make-state-db))
        (database (make-memory-key-value-database)))
    (dotimes (index 40)
      (let ((address (make-address
                      (concatenate
                       'vector (make-byte-vector 19) (vector (1+ index))))))
        (state-db-set-account
         state address (make-state-account :nonce index :balance (1+ index)))))
    (let* ((root (state-db-root state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              database state))
           (origin (make-byte-vector 32))
           (response
             (snap-test-call-backend
              backend ethereum-lisp.snap:+snap-message-get-account-range+
              (ethereum-lisp.snap:make-snap-get-account-range
               1 (hash32-bytes root) origin
               (make-byte-vector 32 :initial-element #xff) (* 1024 1024))))
           (entries
             (mapcar
              (lambda (account)
                (cons
                 (ethereum-lisp.snap:snap-account-data-hash account)
                 (ethereum-lisp.snap-sync::snap-sync-account-full-rlp account)))
              (ethereum-lisp.snap:snap-account-range-accounts response))))
      (is (= 40 (length entries)))
      ;; A proof is redundant when the page contains the complete trie. Public
      ;; snap peers may therefore return an empty proof for a small state.
      (is (mpt-verify-range-proof root entries nil :start origin)))))

(deftest snap-account-range-includes-the-requested-limit-boundary
  (:layer :unit :module :p2p)
  (let ((state (make-state-db))
        (database (make-memory-key-value-database)))
    (dolist (hex '("0x0000000000000000000000000000000000000001"
                   "0x0000000000000000000000000000000000000002"))
      (state-db-set-account
       state (address-from-hex hex) (make-state-account :balance 1)))
    (let* ((entries
             (sort (copy-list (state-db-account-range state))
                   #'ethereum-lisp.validation:byte-vector-lexicographic<
                   :key #'state-account-range-entry-proof-key))
           (limit (state-account-range-entry-proof-key (first entries)))
           (root (state-db-root state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              database state))
           (response
             (snap-test-call-backend
              backend ethereum-lisp.snap:+snap-message-get-account-range+
              (ethereum-lisp.snap:make-snap-get-account-range
               5 (hash32-bytes root) (make-byte-vector 32) limit 100000)))
           (accounts
             (ethereum-lisp.snap:snap-account-range-accounts response)))
      (is (= 1 (length accounts)))
      (is (bytes= limit
                  (ethereum-lisp.snap:snap-account-data-hash
                   (first accounts)))))))

(deftest snap-state-import-resumes-and-installs-a-verified-pivot
  (:layer :integration :module :p2p)
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-memory-key-value-database))
         (addresses
           (loop for index from 1 to 6
                 collect
                 (make-address
                  (concatenate 'vector (make-byte-vector 19) (vector index)))))
         (slot (make-hash32 (make-byte-vector 32 :initial-element 7)))
         (code #(96 0 96 0)))
    (loop for address in addresses
          for index from 1
          do (state-db-set-account
              source-state address
              (make-state-account :nonce index :balance (* index 100)))
             (when (= index 2)
               (state-db-set-code source-state address code))
             (when (= index 3)
               (state-db-set-storage source-state address slot 256)))
    (let* ((root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base-source (snap-test-source backend))
           (trie-node-requests 0)
           (heal-events '())
           (source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (ethereum-lisp.snap-sync:snap-sync-source-account-range
               base-source)
              :storage-ranges
              (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
               base-source)
              :bytecodes
              (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base-source)
              :trie-nodes
              (lambda (request)
                (incf trie-node-requests)
                (funcall
                 (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
                  base-source)
                 request))))
           (pivot-hash (make-hash32 (snap-test-hash 91)))
           (genesis-hash (make-hash32 (snap-test-hash 92)))
           (authority-id (make-hash32 (snap-test-hash 93)))
           (first
             (ethereum-lisp.snap-sync:snap-sync-import-state
              target-database source
              :pivot-hash pivot-hash :pivot-number 1234 :state-root root
              :chain-id 560048 :genesis-hash genesis-hash
              :authority-id authority-id :byte-limit 180 :max-pages 1)))
      (is (not (ethereum-lisp.snap-sync:snap-sync-progress-completed-p first)))
      (is (not (hash32= +empty-trie-hash+
                        (ethereum-lisp.snap-sync:snap-sync-progress-partial-root
                         first))))
      (is (not (nth-value
                1 (kv-get-chain-record target-database :state-history
                                       (hash32-bytes pivot-hash)))))
      (let ((completed
              (ethereum-lisp.snap-sync:snap-sync-import-state
               target-database source
               :pivot-hash pivot-hash :pivot-number 1234 :state-root root
               :chain-id 560048 :genesis-hash genesis-hash
               :authority-id authority-id :byte-limit 180
               :on-heal-progress
               (lambda (event) (push event heal-events)))))
        (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p completed))
        ;; Complete same-root range, code, and storage proofs are already the
        ;; trust boundary; do not re-read the whole authenticated trie.
        (is (zerop trie-node-requests))
        (is (= 1 (length heal-events)))
        (is
         (ethereum-lisp.snap-sync:snap-sync-heal-progress-completed-p
          (first heal-events)))
        (is
         (zerop
          (ethereum-lisp.snap-sync:snap-sync-heal-progress-processed-nodes
           (first heal-events))))
        (multiple-value-bind (persisted-root present-p)
            (kv-get-chain-record target-database :state-history
                                 (hash32-bytes pivot-hash))
          (is present-p)
          (is (bytes= persisted-root (hash32-bytes root))))
        (let ((trie
                (make-persisted-mpt
                 root
                 (lambda (hash)
                   (trie-node-store-get target-database hash)))))
          (dolist (address addresses)
            (multiple-value-bind (record present-p)
                (mpt-get trie (keccak-256 (address-bytes address)))
              (is present-p)
              (is (= (* 100 (1+ (position address addresses)))
                     (state-account-balance
                      (ethereum-lisp.state:decode-state-account-rlp record)))))))
        (multiple-value-bind (persisted-code present-p)
            (kv-get-chain-record target-database :code (keccak-256 code))
          (is present-p)
          (is (bytes= code persisted-code)))
        (signals error
          (ethereum-lisp.snap-sync:snap-sync-import-state
           target-database source
           :pivot-hash pivot-hash :pivot-number 1234 :state-root root
           :chain-id 1 :genesis-hash genesis-hash
           :authority-id authority-id :byte-limit 180))
        (signals error
          (ethereum-lisp.snap-sync:snap-sync-import-state
           target-database source
           :pivot-hash pivot-hash :pivot-number 1234 :state-root root
           :target-hash (make-hash32 (snap-test-hash 94))
           :chain-id 560048 :genesis-hash genesis-hash
           :authority-id authority-id :byte-limit 180))))))

(deftest snap-state-import-rebases-ranges-and-heals-the-new-pivot-root
  (:layer :integration :module :p2p)
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-memory-key-value-database))
         (addresses
           (loop for index from 1 to 160
                 collect (snap-test-address-from-integer index)))
         (pivot-a (make-hash32 (snap-test-hash 201)))
         (pivot-b (make-hash32 (snap-test-hash 202)))
         (target-a (make-hash32 (snap-test-hash 203)))
         (target-b (make-hash32 (snap-test-hash 204)))
         (genesis (make-hash32 (snap-test-hash 205)))
         (authority (make-hash32 (snap-test-hash 206)))
         (code #(96 1 96 0))
         (slot (make-hash32 (snap-test-hash 207))))
    (loop for address in addresses
          for index from 1
          do (state-db-set-account
              source-state address
              (make-state-account :nonce index :balance (+ 1000 index))))
    (let* ((root-a (state-db-root source-state))
           (backend-a
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (first
             (ethereum-lisp.snap-sync:snap-sync-import-state
              target-database (snap-test-source backend-a)
              :pivot-hash pivot-a :pivot-number 1000 :state-root root-a
              :target-hash target-a :chain-id 560048
              :genesis-hash genesis :authority-id authority
              :byte-limit 350 :max-pages 1))
           (cursor
             (ethereum-lisp.snap-sync:snap-sync-progress-next-origin first))
           (downloaded-entry
             (find-if
              (lambda (entry)
                (ethereum-lisp.validation:byte-vector-lexicographic<
                 (state-account-range-entry-proof-key entry) cursor))
              (state-db-account-range source-state)))
           (changed-address
             (and downloaded-entry
                  (state-account-range-entry-address downloaded-entry))))
      (is (not (null cursor)))
      (is (not (null changed-address)))
      (when changed-address
        ;; Change an account that is strictly before the durable cursor.  The
        ;; rebased downloader must not request that flat range again; only the
        ;; TrieNodes healing phase can make the new root executable.
        (state-db-set-account
         source-state changed-address
         (make-state-account :nonce 999 :balance 424242))
        (state-db-set-code source-state changed-address code)
        (state-db-set-storage source-state changed-address slot 777))
      (let* ((root-b (state-db-root source-state))
             (backend-b
               (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
                source-database source-state))
             (base-source (snap-test-source backend-b))
             (origins '())
             (trie-node-requests 0)
             (source
               (ethereum-lisp.snap-sync:make-snap-sync-source
                :account-range
                (lambda (request)
                  (push
                   (copy-seq
                    (ethereum-lisp.snap:snap-get-account-range-origin request))
                   origins)
                  (funcall
                   (ethereum-lisp.snap-sync:snap-sync-source-account-range
                    base-source)
                   request))
                :storage-ranges
                (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
                 base-source)
                :bytecodes
                (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base-source)
                :trie-nodes
                (lambda (request)
                  (incf trie-node-requests)
                  (funcall
                   (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
                    base-source)
                   request)))))
        (is (not (hash32= root-a root-b)))
        (ethereum-lisp.snap-sync:snap-sync-rebase-progress
         target-database
         :pivot-hash pivot-b :pivot-number 1010 :state-root root-b
         :target-hash target-b :chain-id 560048
         :genesis-hash genesis :authority-id authority)
        (let ((completed
                (ethereum-lisp.snap-sync:snap-sync-import-state
                 target-database source
                 :pivot-hash pivot-b :pivot-number 1010 :state-root root-b
                 :target-hash target-b :chain-id 560048
                 :genesis-hash genesis :authority-id authority
                 :byte-limit 350)))
          (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
               completed))
          ;; The exact page mix may already generate all changed ancestors;
          ;; the dedicated healer regression below forces a missing-root fetch.
          (is (not (minusp trie-node-requests)))
          (is (every
               (lambda (origin) (not (bytes= origin (make-byte-vector 32))))
               origins))
          (multiple-value-bind (persisted-root state-history-present-p)
              (kv-get-chain-record
               target-database :state-history (hash32-bytes pivot-b))
            (is state-history-present-p)
            (is (bytes= persisted-root (hash32-bytes root-b))))
          (when changed-address
            (let ((trie
                    (make-persisted-mpt
                     root-b
                     (lambda (hash)
                       (trie-node-store-get target-database hash)))))
              (multiple-value-bind (record changed-account-present-p)
                  (mpt-get trie (keccak-256 (address-bytes changed-address)))
                (is changed-account-present-p)
                (when changed-account-present-p
                  (let ((account
                          (ethereum-lisp.state:decode-state-account-rlp
                           record)))
                    (is (= 424242 (state-account-balance account)))
                    (multiple-value-bind (storage-node storage-present-p)
                        (trie-node-store-get
                         target-database
                         (state-account-storage-root account))
                      (is storage-present-p)
                      (is (plusp (length storage-node))))))))
            (multiple-value-bind (persisted-code code-present-p)
                (kv-get-chain-record target-database :code (keccak-256 code))
              (is code-present-p)
              (is (bytes= code persisted-code)))))))))

(deftest snap-skeleton-and-state-rebase-commit-as-one-durable-batch
  (:layer :integration :module :p2p)
  (let* ((database (make-instance 'snap-failing-test-database))
         (chain-id 560048)
         (genesis (make-hash32 (snap-test-hash 216)))
         (authority (make-hash32 (snap-test-hash 217)))
         (old-target (make-hash32 (snap-test-hash 218)))
         (old-pivot (make-hash32 (snap-test-hash 219)))
         (old-anchor (make-hash32 (snap-test-hash 220)))
         (old-last (make-hash32 (snap-test-hash 221)))
         (new-target (make-hash32 (snap-test-hash 222)))
         (new-pivot (make-hash32 (snap-test-hash 223)))
         (new-anchor (make-hash32 (snap-test-hash 224)))
         (old-root (make-hash32 (snap-test-hash 225)))
         (new-root (make-hash32 (snap-test-hash 226)))
         (partial-root (make-hash32 (snap-test-hash 227)))
         (cursor (make-byte-vector 32 :initial-element 1))
         (old-skeleton
           (ethereum-lisp.node-store.persistence:make-node-store-snap-skeleton-progress
            :authority-id authority :chain-id chain-id :genesis-hash genesis
            :target-number 164 :target-hash old-target
            :anchor-number 99 :anchor-hash old-anchor
            :pivot-number 100 :pivot-hash old-pivot
            :last-number 164 :last-hash old-last))
         (old-state
           (ethereum-lisp.snap-sync::snap-sync-make-progress
            :pivot-hash old-pivot :pivot-number 100 :state-root old-root
            :next-origin cursor :partial-root partial-root
            :target-hash old-target :chain-id chain-id
            :genesis-hash genesis :authority-id authority :completed-p nil))
         (replacement
           (ethereum-lisp.node-store.persistence:make-node-store-snap-skeleton-progress
            :authority-id authority :chain-id chain-id :genesis-hash genesis
            :target-number 284 :target-hash new-target
            :anchor-number 219 :anchor-hash new-anchor
            :pivot-number 220 :pivot-hash new-pivot
            :last-number 219 :last-hash new-anchor)))
    (snap-test-install-persistence-metadata
     database chain-id genesis authority)
    (let ((batch (make-kv-write-batch)))
      (ethereum-lisp.node-store.persistence::node-store-populate-snap-skeleton-progress-batch
       database batch old-skeleton)
      (ethereum-lisp.snap-sync::snap-sync-populate-progress-batch
       batch old-state)
      (kv-apply-batch database batch))
    (labels ((rebase-batch ()
               (let ((batch (make-kv-write-batch)))
                 (ethereum-lisp.node-store.persistence:node-store-populate-snap-skeleton-rebase-batch
                  database batch replacement)
                 (ethereum-lisp.snap-sync:snap-sync-populate-rebased-progress-batch
                  batch old-state
                  :pivot-hash new-pivot :pivot-number 220
                  :state-root new-root :target-hash new-target
                  :chain-id chain-id :genesis-hash genesis
                  :authority-id authority)
                 batch))
             (assert-session (target pivot skeleton-last state-cursor)
               (multiple-value-bind (skeleton present-p)
                   (ethereum-lisp.node-store.persistence:node-store-read-snap-skeleton-progress
                    database)
                 (is present-p)
                 (is (hash32= target
                              (ethereum-lisp.node-store.persistence:node-store-snap-skeleton-progress-target-hash
                               skeleton)))
                 (is (hash32= pivot
                              (ethereum-lisp.node-store.persistence:node-store-snap-skeleton-progress-pivot-hash
                               skeleton)))
                 (is (hash32= skeleton-last
                              (ethereum-lisp.node-store.persistence:node-store-snap-skeleton-progress-last-hash
                               skeleton))))
               (multiple-value-bind (progress present-p)
                   (ethereum-lisp.snap-sync:snap-sync-read-progress database)
                 (is present-p)
                 (is (hash32= target
                              (ethereum-lisp.snap-sync:snap-sync-progress-target-hash
                               progress)))
                 (is (hash32= pivot
                              (ethereum-lisp.snap-sync:snap-sync-progress-pivot-hash
                               progress)))
                 (is (bytes= state-cursor
                             (ethereum-lisp.snap-sync:snap-sync-progress-next-origin
                              progress)))
                 (is (not
                      (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
                       progress))))))
      (setf (snap-failing-test-database-fail-next-apply-p database) t)
      (signals error (kv-apply-batch database (rebase-batch)))
      (assert-session old-target old-pivot old-last cursor)
      (kv-apply-batch database (rebase-batch))
      (assert-session new-target new-pivot new-anchor cursor))))

(deftest snap-heal-checkpoint-round-trips-and-fails-closed
  (:layer :unit :module :p2p)
  (let* ((pivot (make-hash32 (snap-test-hash 181)))
         (root (make-hash32 (snap-test-hash 182)))
         (target (make-hash32 (snap-test-hash 183)))
         (genesis (make-hash32 (snap-test-hash 184)))
         (authority (make-hash32 (snap-test-hash 185)))
         (progress
           (ethereum-lisp.snap-sync::snap-sync-make-progress
            :pivot-hash pivot :pivot-number 3000 :state-root root
            :partial-root +empty-trie-hash+ :target-hash target
            :chain-id 560048 :genesis-hash genesis :authority-id authority
            :completed-p nil
            :tasks
            (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
             :count 1 :completed-p t)))
         (work
           (ethereum-lisp.snap-sync::snap-sync-make-heal-work
            :storage (snap-test-hash 186) #(1 2 3) (snap-test-hash 187)
            :fetched-p t :marker-state :armed))
         (node-complete-work
           (ethereum-lisp.snap-sync::snap-sync-make-heal-work
            :account nil #(4 5 6) (snap-test-hash 190)
            :fetched-p t :marker-state :node-complete))
         (checkpoint
           (ethereum-lisp.snap-sync::make-snap-sync-heal-checkpoint
            :pivot-hash pivot :pivot-number 3000 :state-root root
            :target-hash target :chain-id 560048 :genesis-hash genesis
            :authority-id authority :stack (list work node-complete-work)
            :processed-nodes 11 :reused-nodes 7 :fetched-nodes 4
            :request-count 2 :response-bytes 999))
         (record
           (ethereum-lisp.snap-sync::snap-sync-heal-checkpoint-record
            checkpoint))
         (decoded
           (ethereum-lisp.snap-sync::snap-sync-heal-checkpoint-from-record
            record))
         (database (make-memory-key-value-database)))
    (is (= 11
           (ethereum-lisp.snap-sync::snap-sync-heal-checkpoint-processed-nodes
            decoded)))
    (is (= 999
           (ethereum-lisp.snap-sync::snap-sync-heal-checkpoint-response-bytes
            decoded)))
    (let ((decoded-work
            (first
             (ethereum-lisp.snap-sync::snap-sync-heal-checkpoint-stack
              decoded))))
      (is (eq :storage
              (ethereum-lisp.snap-sync::snap-sync-heal-work-kind
               decoded-work)))
      (is (ethereum-lisp.snap-sync::snap-sync-heal-work-fetched-p
           decoded-work))
      (is (eq :armed
              (ethereum-lisp.snap-sync::snap-sync-heal-work-marker-state
               decoded-work)))
      (is (bytes= #(1 2 3)
                  (ethereum-lisp.snap-sync::snap-sync-heal-work-path
                   decoded-work))))
    (is
     (eq :node-complete
         (ethereum-lisp.snap-sync::snap-sync-heal-work-marker-state
          (second
           (ethereum-lisp.snap-sync::snap-sync-heal-checkpoint-stack
            decoded)))))
    ;; A pre-epoch-four checkpoint may already omit work skipped by retired
    ;; closure proofs. It is a cache miss, not a resumable authority.
    (let* ((legacy-payload
             (rlp-encode
              (make-rlp-list
               1 (hash32-bytes pivot) 3000 (hash32-bytes root)
               (hash32-bytes target) 560048 (hash32-bytes genesis)
               (hash32-bytes authority) 11 7 4 2 999
               (make-rlp-list
                (make-rlp-list
                 1 (snap-test-hash 186) (ensure-byte-vector #(1 2 3))
                 (snap-test-hash 187) 1)))))
           (legacy-record
             (rlp-encode
              (make-rlp-list legacy-payload (keccak-256 legacy-payload)))))
      (signals error
        (ethereum-lisp.snap-sync::snap-sync-heal-checkpoint-from-record
         legacy-record)))
    (let ((batch (make-kv-write-batch)))
      (ethereum-lisp.database:kv-batch-put-chain-record
       batch :metadata
       ethereum-lisp.snap-sync::+snap-sync-heal-checkpoint-identifier+
       record)
      (kv-apply-batch database batch))
    (multiple-value-bind (loaded present-p)
        (ethereum-lisp.snap-sync::snap-sync-read-heal-checkpoint
         database progress)
      (is present-p)
      (is (= 11
             (ethereum-lisp.snap-sync::snap-sync-heal-checkpoint-processed-nodes
              loaded))))
    ;; The envelope checksum makes a torn or altered cache record an ordinary
    ;; cache miss; it can never authorize completion or a different session.
    (let ((corrupt (copy-seq record)))
      (setf (aref corrupt (1- (length corrupt)))
            (logxor 1 (aref corrupt (1- (length corrupt)))))
      (let ((batch (make-kv-write-batch)))
        (ethereum-lisp.database:kv-batch-put-chain-record
         batch :metadata
         ethereum-lisp.snap-sync::+snap-sync-heal-checkpoint-identifier+
         corrupt)
        (kv-apply-batch database batch))
      (multiple-value-bind (loaded present-p)
          (ethereum-lisp.snap-sync::snap-sync-read-heal-checkpoint
           database progress)
        (is (null loaded))
        (is (not present-p))))
    (signals error
      (ethereum-lisp.snap-sync::snap-sync-populate-heal-checkpoint-batch
       (make-kv-write-batch) progress nil 0 0 0 0 0))
    (signals error
      (ethereum-lisp.snap-sync::snap-sync-make-heal-work
       :account nil #(16) (snap-test-hash 188)))
    (is
     (not
      (bytes=
       (ethereum-lisp.snap-sync::snap-sync-healed-subtree-identifier
        (snap-test-hash 188) :account)
       (ethereum-lisp.snap-sync::snap-sync-healed-subtree-identifier
        (snap-test-hash 188) :storage))))
    (let ((batch (make-kv-write-batch))
          (subtree (snap-test-hash 189)))
      (ethereum-lisp.database:kv-batch-put-chain-record
       batch :metadata
       (ethereum-lisp.snap-sync::snap-sync-healed-subtree-identifier subtree)
       #(2))
      (kv-apply-batch database batch)
      (signals ethereum-lisp.validation:storage-error
        (ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p
         database subtree)))
    (let ((batch (make-kv-write-batch))
          (reference (snap-test-hash 191)))
      (ethereum-lisp.database:kv-batch-put-chain-record
       batch :metadata
       (ethereum-lisp.snap-sync::snap-sync-incomplete-node-identifier
        reference)
       #(2))
      (kv-apply-batch database batch)
      (signals ethereum-lisp.validation:storage-error
        (ethereum-lisp.snap-sync::snap-sync-load-incomplete-nodes
         database)))))

(deftest snap-state-healer-yields-at-a-safe-batch-boundary
  (:layer :unit :module :p2p)
  (let* ((database (make-memory-key-value-database))
         (request-calls 0)
         (yield-calls 0)
         (pivot-bytes (snap-test-hash 230))
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) (declare (ignore request)))
            :storage-ranges (lambda (request) (declare (ignore request)))
            :bytecodes (lambda (request) (declare (ignore request)))
            :trie-nodes
            (lambda (request)
              (declare (ignore request))
              (incf request-calls)
              (error "Healer requested a peer after yielding"))))
         (progress
           (ethereum-lisp.snap-sync::snap-sync-make-progress
            :pivot-hash (make-hash32 pivot-bytes)
            :pivot-number 7000
            :state-root (make-hash32 (snap-test-hash 231))
            :partial-root +empty-trie-hash+
            :target-hash (make-hash32 (snap-test-hash 232))
            :chain-id 560048
            :genesis-hash (make-hash32 (snap-test-hash 233))
            :authority-id (make-hash32 (snap-test-hash 234))
            :completed-p nil
            :tasks
            (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
             :count 1 :completed-p t))))
    (signals ethereum-lisp.snap-sync:snap-sync-heal-yielded
      (ethereum-lisp.snap-sync::snap-sync-heal-state
       database (list source) progress (* 2 1024 1024)
       :heal-yield-p
       (lambda ()
         (incf yield-calls)
         t)))
    (is (= 1 yield-calls))
    (is (= 0 request-calls))
    (multiple-value-bind (root present-p)
        (kv-get-chain-record database :state-history pivot-bytes)
      (is (null root))
      (is (not present-p)))))

#+sbcl
(deftest snap-state-healer-pauses-a-live-pipeline-for-stale-yield
  (:layer :unit :module :p2p)
  (let* ((database (make-memory-key-value-database))
         (pivot-bytes (snap-test-hash 237))
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) (declare (ignore request)))
            :storage-ranges (lambda (request) (declare (ignore request)))
            :bytecodes (lambda (request) (declare (ignore request)))
            :trie-nodes
            (lambda (request)
              (declare (ignore request))
              (error "The synthetic pipeline must not issue a peer request"))))
         (progress
           (ethereum-lisp.snap-sync::snap-sync-make-progress
            :pivot-hash (make-hash32 pivot-bytes)
            :pivot-number 7001
            :state-root (make-hash32 (snap-test-hash 238))
            :partial-root +empty-trie-hash+
            :target-hash (make-hash32 (snap-test-hash 239))
            :chain-id 560048
            :genesis-hash (make-hash32 (snap-test-hash 240))
            :authority-id (make-hash32 (snap-test-hash 241))
            :completed-p nil
            :tasks
            (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
             :count 1 :completed-p t)))
         (pipeline-name
           'ethereum-lisp.snap-sync::snap-sync-heal-run-pipeline)
         (real-pipeline (fdefinition pipeline-name))
         (yield-calls 0)
         (pipeline-pause-seen-p nil))
    (unwind-protect
         (progn
           (setf
            (fdefinition pipeline-name)
            (lambda (&rest arguments)
              (let ((pause-p (nth 9 arguments)))
                (is (functionp pause-p))
                ;; The first coordinator seam retained the pivot.  A stale
                ;; decision reached while the remote pipeline was live must
                ;; request a pause before another response/refill cycle.
                (setf pipeline-pause-seen-p (funcall pause-p 1))
                (values nil nil pipeline-pause-seen-p))))
           (signals ethereum-lisp.snap-sync:snap-sync-heal-yielded
             (ethereum-lisp.snap-sync::snap-sync-heal-state
              database (list source) progress (* 2 1024 1024)
              :heal-yield-p
              (lambda ()
                (incf yield-calls)
                (> yield-calls 1))))
           (is pipeline-pause-seen-p)
           ;; The positive edge is carried across the durable pipeline seam;
           ;; the throttled predicate must not be called again to rediscover it.
           (is (= 2 yield-calls)))
      (setf (fdefinition pipeline-name) real-pipeline))))

(deftest snap-heal-checkpoint-bounds-large-live-frontiers
  (:layer :unit :module :p2p)
  ;; A real Hoodi soft-limit left an older fetched batch below the subtree being
  ;; expanded, taking the exact restart frontier just above the former 4096
  ;; cap.  Keep that live, bounded shape encodable. Missing work is already part
  ;; of the exact frontier, so collecting it into a wire batch does not enlarge
  ;; the checkpoint; local expansion remains independently frontier-bounded.
  (is (= 1024
         (ethereum-lisp.snap-sync::snap-sync-heal-missing-limit 0 1)))
  (is (= 2048
         (ethereum-lisp.snap-sync::snap-sync-heal-missing-limit 3000 2)))
  (is (= 3072
         (ethereum-lisp.snap-sync::snap-sync-heal-missing-limit 4096 3)))
  (is (= 8192
         (ethereum-lisp.snap-sync::snap-sync-heal-missing-limit 8192 8)))
  (is (= 9216
         (ethereum-lisp.snap-sync::snap-sync-heal-missing-limit 8192 9)))
  ;; A checkpoint restored at its durable cap must still fill a peer request.
  ;; Reusing the durable cap as the transient expansion limit returns one here
  ;; and recreates the public-node one-path-per-request failure.
  (is (= 1024
         (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
          8192 0 1024 2048)))
  (signals error
    (ethereum-lisp.snap-sync::snap-sync-heal-missing-limit -1 1))
  (signals error
    (ethereum-lisp.snap-sync::snap-sync-heal-missing-limit 0 0))
  (let* ((pivot (make-hash32 (snap-test-hash 205)))
         (root (make-hash32 (snap-test-hash 206)))
         (target (make-hash32 (snap-test-hash 207)))
         (genesis (make-hash32 (snap-test-hash 208)))
         (authority (make-hash32 (snap-test-hash 209)))
         (work
           (ethereum-lisp.snap-sync::snap-sync-make-heal-work
            :account nil #(1 2 3) (snap-test-hash 210)))
         (checkpoint
           (ethereum-lisp.snap-sync::make-snap-sync-heal-checkpoint
            :pivot-hash pivot :pivot-number 5000 :state-root root
            :target-hash target :chain-id 560048 :genesis-hash genesis
            :authority-id authority
            :stack (loop repeat 5000 collect work)
            :processed-nodes 1 :reused-nodes 1 :fetched-nodes 0
            :request-count 0 :response-bytes 0))
         (record
           (ethereum-lisp.snap-sync::snap-sync-heal-checkpoint-record
            checkpoint))
         (decoded
           (ethereum-lisp.snap-sync::snap-sync-heal-checkpoint-from-record
            record)))
    (is (= 5000
           (length
            (ethereum-lisp.snap-sync::snap-sync-heal-checkpoint-stack
             decoded))))
    (is (< (length record)
           ethereum-lisp.snap-sync::+snap-sync-heal-checkpoint-max-bytes+))))

(deftest snap-state-healer-drains-oversized-overdue-frontier
  (:layer :integration :module :p2p)
  ;; A live Hoodi pivot resumed with a legal 8192-work frontier.  Expanding its
  ;; first 16-way branch made the exact frontier 8207 works at the checkpoint
  ;; boundary.  Keep the older checkpoint authoritative until single-work DFS
  ;; reads drain that transient excess instead of terminating the whole node.
  ;; Production also keeps an O(1) count beside this list: once checkpoint
  ;; eligibility is forced below, the per-work gate must not linearly recount
  ;; all 8,000+ remaining entries.
  (let* ((database (make-memory-key-value-database))
         (account-hash (snap-test-hash 220))
         (leaf-object
           (make-rlp-list
            (ethereum-lisp.trie.encoding:hex-prefix-encode
             #(0) :terminator t)
            (make-byte-vector 1 :initial-element 1)))
         (leaf-encoded (rlp-encode leaf-object))
         (leaf-reference (keccak-256 leaf-encoded))
         (branch-object
           (apply #'make-rlp-list
                  (append
                   (loop repeat 16 collect leaf-reference)
                   (list (make-byte-vector 0)))))
         (branch-encoded (rlp-encode branch-object))
         (branch-reference (keccak-256 branch-encoded))
         (request-widths '())
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) (declare (ignore request)))
            :storage-ranges (lambda (request) (declare (ignore request)))
            :bytecodes (lambda (request) (declare (ignore request)))
            :trie-nodes
            (lambda (request)
              (let* ((path-sets
                       (ethereum-lisp.snap:snap-get-trie-nodes-paths request))
                     ;; Account paths are one-element sets. A storage set has
                     ;; one account hash followed by every grouped compact
                     ;; path; count requested nodes, not outer path sets.
                     (width
                       (loop for path-set in path-sets
                             sum (if (= 1 (length path-set))
                                     1
                                     (1- (length path-set))))))
                (push width request-widths)
                (ethereum-lisp.snap:make-snap-trie-nodes
                 1 (loop repeat width collect leaf-encoded))))))
         (pivot (make-hash32 (snap-test-hash 221)))
         (progress
           (ethereum-lisp.snap-sync::snap-sync-make-progress
            :pivot-hash pivot :pivot-number 6000
            :state-root (make-hash32 branch-reference)
            :partial-root +empty-trie-hash+
            :target-hash (make-hash32 (snap-test-hash 222))
            :chain-id 560048
            :genesis-hash (make-hash32 (snap-test-hash 223))
            :authority-id (make-hash32 (snap-test-hash 224))
            :completed-p nil
            :tasks
            (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
             :count 1 :completed-p t)))
         (leaf-work
           (ethereum-lisp.snap-sync::snap-sync-make-heal-work
            :storage account-hash (make-byte-vector 0) leaf-reference))
         (stack
           (cons
            (ethereum-lisp.snap-sync::snap-sync-make-heal-work
             :storage account-hash (make-byte-vector 0) branch-reference)
            (loop repeat
                  (1-
                   ethereum-lisp.snap-sync::+snap-sync-heal-checkpoint-max-works+)
                  collect leaf-work)))
         (real-due
           (fdefinition
            'ethereum-lisp.snap-sync::snap-sync-heal-checkpoint-due-p))
         (real-populate
           (fdefinition
            'ethereum-lisp.snap-sync::snap-sync-populate-heal-checkpoint-batch))
         (forced-checkpoint-done-p nil)
         (checkpoint-frontiers '())
         (completed nil))
    (let ((batch (make-kv-write-batch)))
      (kv-batch-put-chain-record
       batch :trie-node branch-reference branch-encoded)
      (ethereum-lisp.snap-sync::snap-sync-populate-heal-checkpoint-batch
       batch progress stack 0 0 0 0 0)
      (kv-apply-batch database batch))
    (unwind-protect
         (progn
           (setf
            (fdefinition
             'ethereum-lisp.snap-sync::snap-sync-heal-checkpoint-due-p)
            (lambda (processed-nodes last-checkpoint-processed-nodes)
              (declare (ignore last-checkpoint-processed-nodes))
              (and (not forced-checkpoint-done-p)
                   (plusp processed-nodes))))
           (setf
            (fdefinition
             'ethereum-lisp.snap-sync::snap-sync-populate-heal-checkpoint-batch)
            (lambda (batch progress frontier processed-nodes reused-nodes
                     fetched-nodes request-count response-bytes)
              (push (length frontier) checkpoint-frontiers)
              (setf forced-checkpoint-done-p t)
              (funcall
               real-populate batch progress frontier processed-nodes
               reused-nodes fetched-nodes request-count response-bytes)))
           (setf completed
                 (ethereum-lisp.snap-sync::snap-sync-heal-state
                  database (list source) progress (* 2 1024 1024))))
      (setf
       (fdefinition
        'ethereum-lisp.snap-sync::snap-sync-heal-checkpoint-due-p)
       real-due
       (fdefinition
        'ethereum-lisp.snap-sync::snap-sync-populate-heal-checkpoint-batch)
       real-populate))
    (is forced-checkpoint-done-p)
    (is (= 1 (length checkpoint-frontiers)))
    (is
     (<= 1 (first checkpoint-frontiers)
         ethereum-lisp.snap-sync::+snap-sync-heal-checkpoint-max-works+))
    ;; The live failure shape used to emit one TrieNodes request per node once
    ;; the frontier reached the durable cap. These works are already counted in
    ;; the frontier, so the independently bounded live frontier must let a
    ;; fresh peer start at geth's complete 1,024-lookup width.
    (is (= ethereum-lisp.snap-sync::+snap-sync-heal-paths-per-source+
           (reduce #'max request-widths)))
    ;; A max-width-only assertion is insufficient: the broken production
    ;; refill sent one initial full batch and then thousands of one-path
    ;; requests. This whole 8,207-leaf continuation needs only a small number
    ;; of full/soft-byte-limited flights before the duplicate becomes local.
    (is (<= (length request-widths) 10))
    (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p completed))))

(deftest snap-state-healer-uses-multiple-trie-node-sources
  (:layer :integration :module :p2p)
  (multiple-value-bind (source-state addresses)
      (snap-test-partitioned-state)
    (declare (ignore addresses))
    (let* ((root (state-db-root source-state))
           (target-database (make-memory-key-value-database))
           (calls (make-array 2 :initial-element 0))
           (sources
             (loop for index below 2
                   for source-database = (make-memory-key-value-database)
                   for backend =
                     (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
                      source-database source-state)
                   for base = (snap-test-source backend)
                   collect
                   (ethereum-lisp.snap-sync:make-snap-sync-source
                    :account-range
                    (ethereum-lisp.snap-sync:snap-sync-source-account-range
                     base)
                    :storage-ranges
                    (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
                     base)
                    :bytecodes
                    (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base)
                    :trie-nodes
                    (let ((worker-index index)
                          (callback
                            (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
                             base)))
                      (lambda (request)
                        (incf (aref calls worker-index))
                        (funcall callback request))))))
           (progress
             (ethereum-lisp.snap-sync::snap-sync-make-progress
              :pivot-hash (make-hash32 (snap-test-hash 189))
              :pivot-number 3001 :state-root root
              :partial-root +empty-trie-hash+
              :target-hash (make-hash32 (snap-test-hash 190))
              :chain-id 560048
              :genesis-hash (make-hash32 (snap-test-hash 191))
              :authority-id (make-hash32 (snap-test-hash 192))
              :completed-p nil
              :tasks
              (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
               :count 1 :completed-p t)))
           (completed nil))
      (setf
       completed
       (ethereum-lisp.snap-sync::snap-sync-heal-state
        target-database sources progress 350))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p completed))
      (is (plusp (aref calls 0)))
      ;; Positive wiring witness: the old serial failover loop never called the
      ;; second healthy source while the first continued to answer.
      (is (plusp (aref calls 1))))))

(deftest snap-state-healer-keeps-sources-busy-within-geth-lookup-cap
  (:layer :unit :module :p2p)
  (let* ((source-count 3)
         (per-source
           ethereum-lisp.snap-sync::+snap-sync-heal-paths-per-source+)
         (widths (make-array source-count :initial-element nil))
         (sources
           (loop for index below source-count
                 collect
                 (ethereum-lisp.snap-sync:make-snap-sync-source
                  :account-range (lambda (request) (declare (ignore request)))
                  :storage-ranges
                  (lambda (request) (declare (ignore request)))
                  :bytecodes (lambda (request) (declare (ignore request)))
                  :trie-nodes
                  (let ((worker-index index))
                    (lambda (request)
                      (push
                       (length
                        (ethereum-lisp.snap:snap-get-trie-nodes-paths request))
                       (aref widths worker-index))
                      ;; Request-round scheduling does not inspect payloads;
                      ;; one non-empty blob keeps this healthy source eligible
                      ;; to claim another disjoint chunk.
                      (ethereum-lisp.snap:make-snap-trie-nodes 1 '(#(128))))))))
         (work
           (ethereum-lisp.snap-sync::snap-sync-make-heal-work
            :account nil #(1) (snap-test-hash 193)))
         (missing
           (make-array (* source-count per-source) :initial-element work))
         (results
           (ethereum-lisp.snap-sync::snap-sync-heal-request-round
            sources missing (snap-test-hash 194) (* 2 1024 1024))))
    (is
     (= (ceiling (length missing)
                 ethereum-lisp.snap-sync::*snap-sync-heal-request-target-paths*)
        (length results)))
    (is
     (= (length missing)
        (loop for source-widths across widths
              sum (reduce #'+ source-widths))))
    (loop for source-widths across widths
          do (is (plusp (length source-widths)))
             (loop for width in source-widths
                   do (is (<= 1 width per-source))))
    ;; A static one-request-per-source wave cannot produce more completed
    ;; chunks than sources. Every request remains under geth's lookup cap.
    (is (> (length results) source-count))
    (loop for result across results
          do (is (null
                  (ethereum-lisp.snap-sync::snap-sync-heal-fetch-result-condition
                   result))))))

(deftest snap-state-healer-feedback-bounds-the-global-missing-queue
  (:layer :unit :module :p2p)
  (let* ((capacity
           (ethereum-lisp.snap-sync::snap-sync-heal-request-capacity 2d0))
         (overloaded
           (ethereum-lisp.snap-sync::snap-sync-heal-next-throttle
            2d0 100 10d0))
         (caught-up
           (ethereum-lisp.snap-sync::snap-sync-heal-next-throttle
            2d0 0 100d0))
         (rate
           (ethereum-lisp.snap-sync::snap-sync-heal-processing-rate
            0d0 100 0.5d0)))
    (is (= 256 capacity))
    (is (= (* 3 capacity)
           (ethereum-lisp.snap-sync::snap-sync-heal-missing-limit
            8192 3 capacity)))
    (is (> overloaded 2d0))
    (is (< caught-up 2d0))
    (is (plusp rate))))

(deftest snap-state-healer-bounds-local-refill-before-peer-events
  (:layer :unit :module :p2p)
  (let ((ethereum-lisp.snap-sync::*snap-sync-heal-pipeline-refill-work-quantum*
          4096))
    (is (= 4096
           (ethereum-lisp.snap-sync::snap-sync-heal-pipeline-refill-work-room
            0)))
    (is (= 1
           (ethereum-lisp.snap-sync::snap-sync-heal-pipeline-refill-work-room
            4095)))
    (is (zerop
         (ethereum-lisp.snap-sync::snap-sync-heal-pipeline-refill-work-room
          4096)))
    (is (zerop
         (ethereum-lisp.snap-sync::snap-sync-heal-pipeline-refill-work-room
          8192)))))

#+sbcl
(deftest snap-state-healer-bounds-local-refill-at-production-call-site
  (:layer :unit :module :p2p)
  ;; Model the public-node stall precisely: the missing root arrives from one
  ;; peer while the large descendant trie is already reusable locally.  The
  ;; production REFILL closure must return to the peer event loop after one
  ;; configured work quantum instead of traversing the whole local trie.
  (multiple-value-bind (state addresses)
      (snap-test-partitioned-state)
    (declare (ignore addresses))
    (let* ((database (make-memory-key-value-database))
           (root
             (progn
               (state-db-root state)
               (mpt-persist
                database (ethereum-lisp.state::state-db-state-trie state))))
           (source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range (lambda (request) (declare (ignore request)))
              :storage-ranges (lambda (request) (declare (ignore request)))
              :bytecodes (lambda (request) (declare (ignore request)))
              :trie-node-capacity (lambda () 1024)
              :trie-nodes
              (lambda (request)
                (declare (ignore request))
                (error "The intercepted pipeline must own the root reply"))))
           (progress
             (ethereum-lisp.snap-sync::snap-sync-make-progress
              :pivot-hash (make-hash32 (snap-test-hash 242))
              :pivot-number 7002 :state-root root
              :partial-root +empty-trie-hash+
              :target-hash (make-hash32 (snap-test-hash 243))
              :chain-id 560048
              :genesis-hash (make-hash32 (snap-test-hash 244))
              :authority-id (make-hash32 (snap-test-hash 245))
              :completed-p nil
              :tasks
              (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
               :count 1 :completed-p t)))
           (pipeline-name
             'ethereum-lisp.snap-sync::snap-sync-heal-run-pipeline)
           (real-pipeline (fdefinition pipeline-name))
           (snapshots '())
           (first-refill-processed nil)
           (second-refill-processed nil))
      (multiple-value-bind (encoded-root present-p)
          (ethereum-lisp.trie:trie-node-store-get database root)
        (is present-p)
        (ethereum-lisp.database:kv-delete-chain-record
         database :trie-node (hash32-bytes root))
        (unwind-protect
             (progn
               (setf
                (fdefinition pipeline-name)
                (lambda (&rest arguments)
                  (let* ((initial (nth 1 arguments))
                         (handle-result (nth 6 arguments))
                         (refill (nth 7 arguments))
                         (assignment-capacity (nth 10 arguments))
                         (result
                           (ethereum-lisp.snap-sync::make-snap-sync-heal-fetch-result
                            :source source :start 0 :end 1 :order #(0)
                            :response
                            (ethereum-lisp.snap:make-snap-trie-nodes
                             1 (list encoded-root)))))
                    (is (= 1 (length initial)))
                    (is (functionp assignment-capacity))
                    ;; The production call site begins with geth's 1,024
                    ;; local divisor, so even a full transport capacity keeps
                    ;; the cold one-item probe.
                    (is (= 1 (funcall assignment-capacity source)))
                    (multiple-value-bind (retry condition delivered)
                        (funcall handle-result result initial)
                      (is (null retry))
                      (is (null condition))
                      (is (= 1 delivered)))
                    (is (null (funcall refill most-positive-fixnum 0)))
                    (setf first-refill-processed
                          (ethereum-lisp.snap-sync:snap-sync-heal-progress-processed-nodes
                           (first snapshots)))
                    (is (null (funcall refill most-positive-fixnum 0)))
                    (setf second-refill-processed
                          (ethereum-lisp.snap-sync:snap-sync-heal-progress-processed-nodes
                           (first snapshots)))
                    (values nil nil nil))))
               (let ((ethereum-lisp.snap-sync::*snap-sync-heal-pipeline-refill-work-quantum*
                       1)
                     (ethereum-lisp.snap-sync::*snap-sync-heal-progress-node-interval*
                       1))
                 (let ((completed
                         (ethereum-lisp.snap-sync::snap-sync-heal-state
                          database (list source) progress (* 2 1024 1024)
                          :on-heal-progress
                          (lambda (snapshot) (push snapshot snapshots)))))
                   (is
                    (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
                     completed))))
               (is (= 1 first-refill-processed))
               (is (= 2 second-refill-processed)))
          (setf (fdefinition pipeline-name) real-pipeline))))))

(deftest snap-heal-progress-reports-discovered-work-without-a-denominator
  (:layer :unit :module :p2p)
  (let ((snapshot nil))
    (ethereum-lisp.snap-sync::snap-sync-report-heal-progress
     (lambda (progress) (setf snapshot progress))
     11 7 5 3 4096 2 13 101 17 19 23 nil)
    (is snapshot)
    (is (= 101
           (ethereum-lisp.snap-sync:snap-sync-heal-progress-frontier-works
            snapshot)))
    (is (= 17
           (ethereum-lisp.snap-sync:snap-sync-heal-progress-deferred-storage-works
            snapshot)))
    (is (= 19
           (ethereum-lisp.snap-sync:snap-sync-heal-progress-remote-works
            snapshot)))
    (is (= 23
           (ethereum-lisp.snap-sync:snap-sync-heal-progress-known-incomplete-nodes
            snapshot)))
    (is (not
         (ethereum-lisp.snap-sync:snap-sync-heal-progress-completed-p
          snapshot)))))

(deftest snap-state-healer-sorts-and-groups-storage-paths-by-account
  (:layer :unit :module :p2p)
  (let* ((account-a (make-byte-vector 32 :initial-element #x20))
         (account-b (make-byte-vector 32 :initial-element #x10))
         (reference (snap-test-hash 199))
         (works
           (vector
            (ethereum-lisp.snap-sync::snap-sync-make-heal-work
             :storage account-a #(1 2) reference)
            (ethereum-lisp.snap-sync::snap-sync-make-heal-work
             :storage account-b #(7 8) reference)
            (ethereum-lisp.snap-sync::snap-sync-make-heal-work
             :account nil #(5 6) reference)
            (ethereum-lisp.snap-sync::snap-sync-make-heal-work
             :storage account-a #(3 4) reference)
            (ethereum-lisp.snap-sync::snap-sync-make-heal-work
             :storage account-b #(9 10) reference)))
         (path-sets nil)
         (order nil))
    (multiple-value-setq (path-sets order)
      (ethereum-lisp.snap-sync::snap-sync-heal-request-path-sets
       works 0 (length works)))
    (is (equalp #(2 1 4 0 3) order))
    (is (= 3 (length path-sets)))
    (is (= 1 (length (first path-sets))))
    (is
     (bytes=
      (ethereum-lisp.trie.encoding:hex-prefix-encode
       #(5 6) :terminator nil)
      (first (first path-sets))))
    (is (= 3 (length (second path-sets))))
    (is (bytes= account-b (first (second path-sets))))
    (is
     (bytes=
      (ethereum-lisp.trie.encoding:hex-prefix-encode
       #(9 10) :terminator nil)
      (third (second path-sets))))
    (is (= 3 (length (third path-sets))))
    (is (bytes= account-a (first (third path-sets))))
    ;; The two account-A paths were separated by unrelated work in the exact
    ;; DFS frontier, proving grouping is global within the request slice.
    (is
     (bytes=
      (ethereum-lisp.trie.encoding:hex-prefix-encode
       #(3 4) :terminator nil)
      (third (third path-sets))))))

(deftest snap-state-healer-fast-source-claims-before-slow-source-returns
  (:layer :unit :module :p2p)
  (let* ((lock (sb-thread:make-mutex :name "snap-heal-fast-source"))
         (changed (sb-thread:make-waitqueue :name "snap-heal-fast-source"))
         (fast-calls 0)
         (fast-reused-before-slow-release-p nil)
         (slow-source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) (declare (ignore request)))
            :storage-ranges (lambda (request) (declare (ignore request)))
            :bytecodes (lambda (request) (declare (ignore request)))
            :trie-nodes
            (lambda (request)
              (declare (ignore request))
              (sb-thread:with-mutex (lock)
                ;; A broadcast for the fast source's first request is not the
                ;; witness. Re-check after every wakeup, while keeping the
                ;; total synthetic slow-peer delay bounded to one second.
                (loop repeat 4
                      while (< fast-calls 2)
                      do (sb-thread:condition-wait
                          changed lock :timeout 1/4))
                (setf fast-reused-before-slow-release-p (>= fast-calls 2)))
              (ethereum-lisp.snap:make-snap-trie-nodes 1 '(#(128))))))
         (fast-source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) (declare (ignore request)))
            :storage-ranges (lambda (request) (declare (ignore request)))
            :bytecodes (lambda (request) (declare (ignore request)))
            :trie-nodes
            (lambda (request)
              (declare (ignore request))
              (sb-thread:with-mutex (lock)
                (incf fast-calls)
                (sb-thread:condition-broadcast changed))
              (ethereum-lisp.snap:make-snap-trie-nodes 1 '(#(128))))))
         (work
           (ethereum-lisp.snap-sync::snap-sync-make-heal-work
            :account nil #(1) (snap-test-hash 195)))
         (missing (make-array 16 :initial-element work))
         (results
           (let ((ethereum-lisp.snap-sync::*snap-sync-heal-request-target-paths*
                   4))
             (ethereum-lisp.snap-sync::snap-sync-heal-request-round
              (list slow-source fast-source) missing
              (snap-test-hash 196) (* 2 1024 1024)))))
    (is (= 4 (length results)))
    (is (>= fast-calls 2))
    ;; With the old global wave the fast source made exactly one request and
    ;; could not release this source before its bounded wait elapsed.
    (is fast-reused-before-slow-release-p)))

(deftest snap-state-healer-event-loop-refills-before-slow-peer-returns
  (:layer :unit :module :p2p)
  (let* ((lock (sb-thread:make-mutex :name "snap-heal-event-loop"))
         (changed (sb-thread:make-waitqueue :name "snap-heal-event-loop"))
         (fast-calls 0)
         (refill-enabled-p nil)
         (refilled-p nil)
         (fast-refilled-before-slow-release-p nil)
         (slow-source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) (declare (ignore request)))
            :storage-ranges (lambda (request) (declare (ignore request)))
            :bytecodes (lambda (request) (declare (ignore request)))
            :trie-nodes
            (lambda (request)
              (declare (ignore request))
              (sb-thread:with-mutex (lock)
                (loop repeat 4
                      while (< fast-calls 2)
                      do (sb-thread:condition-wait
                          changed lock :timeout 1/4))
                (setf fast-refilled-before-slow-release-p
                      (>= fast-calls 2)))
              (ethereum-lisp.snap:make-snap-trie-nodes 1 '(#(128))))))
         (fast-source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) (declare (ignore request)))
            :storage-ranges (lambda (request) (declare (ignore request)))
            :bytecodes (lambda (request) (declare (ignore request)))
            :trie-nodes
            (lambda (request)
              (declare (ignore request))
              (sb-thread:with-mutex (lock)
                (incf fast-calls)
                (sb-thread:condition-broadcast changed))
              (ethereum-lisp.snap:make-snap-trie-nodes 1 '(#(128))))))
         (work
           (ethereum-lisp.snap-sync::snap-sync-make-heal-work
            :account nil #(1) (snap-test-hash 197)))
         (initial (vector work work))
         (capacities (make-hash-table :test #'eq))
         (rtts (make-hash-table :test #'eq)))
    ;; Force one initial job per peer. The third work exists only after the
    ;; fast peer's first response is integrated by the coordinator.
    (setf (gethash slow-source capacities) 1
          (gethash fast-source capacities) 1)
    (multiple-value-bind (remaining errors)
        (ethereum-lisp.snap-sync::snap-sync-heal-run-pipeline
         (list slow-source fast-source) initial (snap-test-hash 198)
         (* 2 1024 1024) capacities rtts
         (lambda (result works)
           (declare (ignore works))
           (is (null
                (ethereum-lisp.snap-sync::snap-sync-heal-fetch-result-condition
                 result)))
           (when (eq
                  fast-source
                  (ethereum-lisp.snap-sync::snap-sync-heal-fetch-result-source
                   result))
             (setf refill-enabled-p t))
           (values nil nil 1))
         (lambda (room outstanding)
           (declare (ignore room outstanding))
           (when (and refill-enabled-p (not refilled-p))
             (setf refilled-p t)
             (list work)))
         nil)
      (is (null remaining))
      (is (null errors)))
    (is refilled-p)
    (is (>= fast-calls 2))
    ;; A request-round join cannot discover or assign the third-generation
    ;; work until the synthetic slow peer returns. The event loop can.
    (is fast-refilled-before-slow-release-p)))

(deftest snap-state-healer-learns-and-orders-peer-capacity
  (:layer :unit :module :p2p)
  (let* ((source-a
           (ethereum-lisp.snap-sync:make-snap-sync-source))
         (source-b
           (ethereum-lisp.snap-sync:make-snap-sync-source))
         (slow-partial
           (ethereum-lisp.snap-sync::snap-sync-heal-learn-peer-capacity
            1024 1024 128 2d0))
         (slow-full
           (ethereum-lisp.snap-sync::snap-sync-heal-learn-peer-capacity
            1024 1024 1024 4d0))
         (fast-full
           (ethereum-lisp.snap-sync::snap-sync-heal-learn-peer-capacity
            1024 1024 1024 1d0))
         (peer-a
           (ethereum-lisp.snap-sync::make-snap-sync-heal-pipeline-peer
            source-a slow-full 1d0))
         (peer-b
           (ethereum-lisp.snap-sync::make-snap-sync-heal-pipeline-peer
            source-b fast-full 2d0)))
    (is (< slow-partial slow-full))
    (is (< slow-full fast-full))
    (is (= 1024 fast-full))
    (is
     (eq peer-b
         (first
          (stable-sort
           (list peer-a peer-b)
           #'ethereum-lisp.snap-sync::snap-sync-heal-pipeline-peer<))))
    (is
     (< 1d0
        (ethereum-lisp.snap-sync::snap-sync-heal-learn-peer-rtt 1d0 3d0)
        3d0))))

(deftest snap-state-healer-dispatches-shared-qos-capacity-through-throttle
  (:layer :unit :module :p2p)
  #+sbcl
  (let* ((capacity-a 800)
         (capacity-b 200)
         (source-a
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :trie-node-capacity (lambda () capacity-a)))
         (source-b
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :trie-node-capacity (lambda () capacity-b)))
         (runtime
           (ethereum-lisp.snap-sync::make-snap-sync-heal-pipeline-runtime))
         (peer-a
           (ethereum-lisp.snap-sync::make-snap-sync-heal-pipeline-peer
            source-a 7 1d0))
         (peer-b
           (ethereum-lisp.snap-sync::make-snap-sync-heal-pipeline-peer
            source-b 999 1d0))
         (work
           (ethereum-lisp.snap-sync::snap-sync-make-heal-work
            :account nil #(1) (snap-test-hash 197))))
    ;; Geth begins at the maximum 1,024 divisor, preserving a one-item probe.
    (is (= 1
           (ethereum-lisp.snap-sync::snap-sync-heal-source-request-capacity
            source-a 1024d0)))
    (is (= 200
           (ethereum-lisp.snap-sync::snap-sync-heal-source-request-capacity
            source-a 4d0)))
    (is (= 50
           (ethereum-lisp.snap-sync::snap-sync-heal-source-request-capacity
            source-b 4d0)))
    (setf
     (ethereum-lisp.snap-sync::snap-sync-heal-pipeline-runtime-peers runtime)
     (list peer-b peer-a)
     (ethereum-lisp.snap-sync::snap-sync-heal-pipeline-runtime-pending runtime)
     (make-list 250 :initial-element work))
    (ethereum-lisp.snap-sync::snap-sync-heal-pipeline-dispatch
     runtime
     (lambda (source)
       (ethereum-lisp.snap-sync::snap-sync-heal-source-request-capacity
        source 4d0)))
    ;; The transport tracker overrides both stale local capacities before the
    ;; peers are sorted, then the local processing throttle divides each one.
    (is (= 200
           (length
            (ethereum-lisp.snap-sync::snap-sync-heal-pipeline-peer-job
             peer-a))))
    (is (= 50
           (length
            (ethereum-lisp.snap-sync::snap-sync-heal-pipeline-peer-job
             peer-b))))
    (is
     (ethereum-lisp.snap-sync::
      snap-sync-heal-pipeline-peer-externally-sized-p peer-a))
    (is
     (ethereum-lisp.snap-sync::
      snap-sync-heal-pipeline-peer-externally-sized-p peer-b)))
  #-sbcl
  (is t))

(deftest snap-state-healer-counts-inflight-work-not-requests
  (:layer :unit :module :p2p)
  (let* ((runtime
           (ethereum-lisp.snap-sync::make-snap-sync-heal-pipeline-runtime))
         (source-a (ethereum-lisp.snap-sync:make-snap-sync-source))
         (source-b (ethereum-lisp.snap-sync:make-snap-sync-source))
         (peer-a
           (ethereum-lisp.snap-sync::make-snap-sync-heal-pipeline-peer
            source-a 1024 1d0))
         (peer-b
           (ethereum-lisp.snap-sync::make-snap-sync-heal-pipeline-peer
            source-b 1024 1d0))
         (work
           (ethereum-lisp.snap-sync::snap-sync-make-heal-work
            :account nil #(1) (snap-test-hash 198))))
    (setf
     (ethereum-lisp.snap-sync::snap-sync-heal-pipeline-runtime-peers runtime)
     (list peer-a peer-b)
     (ethereum-lisp.snap-sync::snap-sync-heal-pipeline-runtime-pending runtime)
     (make-list 2048 :initial-element work))
    (ethereum-lisp.snap-sync::snap-sync-heal-pipeline-dispatch runtime)
    (is (= 2048
           (ethereum-lisp.snap-sync::snap-sync-heal-pipeline-outstanding
            runtime)))
    (is (= 1024
           (length
            (ethereum-lisp.snap-sync::snap-sync-heal-pipeline-peer-job
             peer-a))))
    (is (= 1024
           (length
            (ethereum-lisp.snap-sync::snap-sync-heal-pipeline-peer-job
             peer-b))))))

(deftest snap-state-healer-pipeline-returns-failed-work
  (:layer :unit :module :p2p)
  (let* ((source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :trie-nodes
            (lambda (request)
              (declare (ignore request))
              (error
               'ethereum-lisp.snap-sync:snap-sync-state-unavailable
               :request-kind "trie-nodes"))))
         (work
           (ethereum-lisp.snap-sync::snap-sync-make-heal-work
            :account nil #(1) (snap-test-hash 198)))
         (capacities (make-hash-table :test #'eq))
         (rtts (make-hash-table :test #'eq))
         (handled 0)
         (condition-seen-p nil))
    (multiple-value-bind (remaining errors paused-p)
        (ethereum-lisp.snap-sync::snap-sync-heal-run-pipeline
         (list source) (vector work) (snap-test-hash 199) 350
         capacities rtts
         (lambda (result works)
           (incf handled)
           (setf condition-seen-p
                 (not
                  (null
                   (ethereum-lisp.snap-sync::snap-sync-heal-fetch-result-condition
                    result))))
           (values
            (coerce works 'list)
            (ethereum-lisp.snap-sync::snap-sync-heal-fetch-result-condition
             result)
            0))
         (lambda (room outstanding)
           (declare (ignore room outstanding))
           nil)
         nil)
      (is (= 1 handled))
      (is condition-seen-p)
      (is (= 1 (length remaining)))
      (is (= 1 (length errors)))
      (is (not paused-p)))))

(deftest snap-state-healer-pipeline-latches-pause-while-draining
  (:layer :unit :module :p2p)
  (let* ((lock (sb-thread:make-mutex :name "snap-pipeline-pause-test"))
         (changed
           (sb-thread:make-waitqueue :name "snap-pipeline-pause-changed"))
         (release-slow-p nil)
         (slow-source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :trie-nodes
            (lambda (request)
              (declare (ignore request))
              (sb-thread:with-mutex (lock)
                (loop until release-slow-p
                      do (sb-thread:condition-wait changed lock)))
              (ethereum-lisp.snap:make-snap-trie-nodes 1 '(#(128))))))
         (fast-source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :trie-nodes
            (lambda (request)
              (declare (ignore request))
              (ethereum-lisp.snap:make-snap-trie-nodes 1 '(#(128))))))
         (work
           (ethereum-lisp.snap-sync::snap-sync-make-heal-work
            :account nil #(1) (snap-test-hash 200)))
         (capacities (make-hash-table :test #'eq))
         (rtts (make-hash-table :test #'eq))
         (handled 0)
         (pause-calls 0))
    (setf (gethash slow-source capacities) 1
          (gethash fast-source capacities) 1)
    (multiple-value-bind (remaining errors paused-p)
        (ethereum-lisp.snap-sync::snap-sync-heal-run-pipeline
         (list slow-source fast-source) (vector work work work)
         (snap-test-hash 201) 350 capacities rtts
         (lambda (result works)
           (declare (ignore result works))
           (incf handled)
           (values nil nil 1))
         (lambda (room outstanding)
           (declare (ignore room outstanding))
           nil)
         nil
         (lambda (outstanding)
           (declare (ignore outstanding))
           (incf pause-calls)
           (when (= pause-calls 2)
             (sb-thread:with-mutex (lock)
               (setf release-slow-p t)
               (sb-thread:condition-broadcast changed))
             t)))
      (is paused-p)
      (is (null errors))
      (is (= 1 (length remaining)))
      (is (= 2 handled))
      ;; The predicate is edge-triggered.  A latched pause does not call it
      ;; again after the slow in-flight response reaches the coordinator.
      (is (= 2 pause-calls)))))

(deftest snap-state-healer-processes-fetched-nodes-without-rereading-them
  (:layer :unit :module :p2p)
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-instance 'snap-counting-test-database))
         (address
           (address-from-hex
            "0x0000000000000000000000000000000000000051"))
         (pivot (make-hash32 (snap-test-hash 201)))
         (target (make-hash32 (snap-test-hash 202)))
         (genesis (make-hash32 (snap-test-hash 203)))
         (authority (make-hash32 (snap-test-hash 204)))
         (real-get
           (fdefinition 'ethereum-lisp.database:kv-get-chain-record))
         (real-get-many
           (fdefinition 'ethereum-lisp.database:kv-get-chain-records))
         (point-reads 0)
         (batch-reads 0)
         (trie-requests 0))
    (state-db-set-account
     source-state address (make-state-account :nonce 1 :balance 51))
    (let* ((root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base (snap-test-source backend))
           (source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (ethereum-lisp.snap-sync:snap-sync-source-account-range base)
              :storage-ranges
              (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges base)
              :bytecodes
              (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base)
              :trie-nodes
              (lambda (request)
                (incf trie-requests)
                (funcall
                 (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes base)
                 request))))
           (progress
             (ethereum-lisp.snap-sync::snap-sync-make-progress
              :pivot-hash pivot :pivot-number 3004 :state-root root
              :partial-root +empty-trie-hash+ :target-hash target
              :chain-id 560048 :genesis-hash genesis
              :authority-id authority :completed-p nil
              :tasks
              (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
               :count 1 :completed-p t)))
           (completed nil))
      (unwind-protect
           (progn
             (setf
              (fdefinition 'ethereum-lisp.database:kv-get-chain-record)
              (lambda (database kind identifier &optional default)
                (when (and (eq database target-database)
                           (eq kind :trie-node))
                  (incf point-reads))
                (funcall real-get database kind identifier default))
              (fdefinition 'ethereum-lisp.database:kv-get-chain-records)
              (lambda (database kind identifiers &optional default)
                (when (and (eq database target-database)
                           (eq kind :trie-node))
                  (incf batch-reads))
                (funcall real-get-many database kind identifiers default)))
             ;; Positive controls: both counters observe their real production
             ;; entry points before the cost assertion resets them.
             (kv-get-chain-record
              target-database :trie-node (snap-test-hash 205))
             (kv-get-chain-records
              target-database :trie-node (vector (snap-test-hash 206)))
             (is (= 1 point-reads))
             (is (= 1 batch-reads))
             (setf point-reads 0
                   batch-reads 0)
             (setf completed
                   (ethereum-lisp.snap-sync::snap-sync-heal-state
                    target-database (list source) progress
                    (* 2 1024 1024))))
        (setf
         (fdefinition 'ethereum-lisp.database:kv-get-chain-record) real-get
         (fdefinition 'ethereum-lisp.database:kv-get-chain-records)
         real-get-many))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p completed))
      (is (plusp trie-requests))
      ;; One MultiGet discovers the missing root. The verified reply is decoded
      ;; once and consumed from the bounded response cache, causing neither the
      ;; former per-node Get nor a second MultiGet of the node just written.
      (is (= 0 point-reads))
      (is (= 1 batch-reads))
      ;; Remote trie nodes use the buffered prefix; the later completion seam
      ;; supplies the synchronous durability boundary.
      (is (= 1
             (snap-counting-test-database-buffered-apply-count
              target-database)))
      (is (every #'plusp
                 (snap-counting-test-database-buffered-batch-sizes
                  target-database))))))

(deftest snap-state-healer-adds-sources-that-arrive-after-healing-starts
  (:layer :integration :module :p2p)
  (multiple-value-bind (source-state addresses)
      (snap-test-partitioned-state)
    (declare (ignore addresses))
    (let* ((root (state-db-root source-state))
           (target-database (make-memory-key-value-database))
           (calls (make-array 2 :initial-element 0))
           (provider-calls 0)
           (sources
             (loop for index below 2
                   for source-database = (make-memory-key-value-database)
                   for backend =
                     (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
                      source-database source-state)
                   for base = (snap-test-source backend)
                   collect
                   (ethereum-lisp.snap-sync:make-snap-sync-source
                    :account-range
                    (ethereum-lisp.snap-sync:snap-sync-source-account-range
                     base)
                    :storage-ranges
                    (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
                     base)
                    :bytecodes
                    (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base)
                    :trie-nodes
                    (let ((worker-index index)
                          (callback
                            (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
                             base)))
                      (lambda (request)
                        (incf (aref calls worker-index))
                        (funcall callback request))))))
           (progress
             (ethereum-lisp.snap-sync::snap-sync-make-progress
              :pivot-hash (make-hash32 (snap-test-hash 197))
              :pivot-number 3003 :state-root root
              :partial-root +empty-trie-hash+
              :target-hash (make-hash32 (snap-test-hash 198))
              :chain-id 560048
              :genesis-hash (make-hash32 (snap-test-hash 199))
              :authority-id (make-hash32 (snap-test-hash 200))
              :completed-p nil
              :tasks
              (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
               :count 1 :completed-p t))))
      (let ((completed
              (ethereum-lisp.snap-sync::snap-sync-heal-state
               target-database (list (first sources)) progress 350
               :source-provider
               (lambda ()
                 (incf provider-calls)
                 ;; Model the common live-node sequence: the first peer starts
                 ;; sync, then a second session finishes its handshake while
                 ;; the long content-addressed traversal is already running.
                 (if (= provider-calls 1)
                     (list (first sources))
                     sources)))))
        (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p completed))
        (is (> provider-calls 1))
        (is (plusp (aref calls 0)))
        (is (plusp (aref calls 1)))))))

(deftest snap-state-healer-batches-local-trie-lookups
  (:layer :unit :module :p2p)
  (multiple-value-bind (source-state addresses)
      (snap-test-partitioned-state)
    (declare (ignore addresses))
    (let* ((database (make-memory-key-value-database))
           (root
             (mpt-persist
              database
              (ethereum-lisp.state::state-db-state-trie source-state)))
           (pivot (make-hash32 (snap-test-hash 193)))
           (progress
             (ethereum-lisp.snap-sync::snap-sync-make-progress
              :pivot-hash pivot :pivot-number 3002 :state-root root
              :partial-root +empty-trie-hash+
              :target-hash (make-hash32 (snap-test-hash 194))
              :chain-id 560048
              :genesis-hash (make-hash32 (snap-test-hash 195))
              :authority-id (make-hash32 (snap-test-hash 196))
              :completed-p nil
              :tasks
              (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
               :count 1 :completed-p t)))
           (source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range (lambda (request) (declare (ignore request)))
              :storage-ranges (lambda (request) (declare (ignore request)))
              :bytecodes
              (lambda (request)
                (declare (ignore request))
                (error "Complete local trie requested remote bytecode"))
              :trie-nodes
              (lambda (request)
                (declare (ignore request))
                (error "Complete local trie requested remote nodes"))))
           (real-get-many
             (fdefinition 'ethereum-lisp.database:kv-get-chain-records))
           (batch-count 0)
           (largest-batch 0)
           (completed nil))
      (unwind-protect
           (progn
             (setf
              (fdefinition 'ethereum-lisp.database:kv-get-chain-records)
              (lambda (candidate kind identifiers &optional default)
                (when (and (eq candidate database) (eq kind :trie-node))
                  (incf batch-count)
                  (setf largest-batch
                        (max largest-batch (length identifiers))))
                (funcall
                 real-get-many candidate kind identifiers default)))
             (setf
              completed
              (ethereum-lisp.snap-sync::snap-sync-heal-state
               database (list source) progress (* 2 1024 1024))))
        (setf (fdefinition 'ethereum-lisp.database:kv-get-chain-records)
              real-get-many))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p completed))
      (is (plusp batch-count))
      ;; A serial KV-GET loop cannot satisfy this wiring witness.
      (is (> largest-batch 1))
      (is (<= largest-batch
              ethereum-lisp.snap-sync::+snap-sync-heal-local-reads-per-batch+))
      ;; Even if every prefetched work is a 16-way branch, replacing the
      ;; popped batch with all children stays below the hard checkpoint cap
      ;; throughout the soft-target region.
      (loop for stack-count from 1 to
              ethereum-lisp.snap-sync::+snap-sync-heal-checkpoint-frontier-target+
            for batch =
              (min
               stack-count
               (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
                stack-count 0
                (ethereum-lisp.snap-sync::snap-sync-heal-missing-limit
                 stack-count 1)
                ethereum-lisp.snap-sync::+snap-sync-heal-checkpoint-node-interval+))
            do (is
                (<= (+ (- stack-count batch) (* 16 batch))
                    ethereum-lisp.snap-sync::+snap-sync-heal-checkpoint-max-works+)))
      ;; The soft durable region is still bounded by worst-case sixteen-way
      ;; expansion, even though a larger transient frontier may use the full
      ;; database MultiGet width.
      (is
       (= 546
          (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
           1 0 2048 2048)))
      (is
       (= 292
          (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
           3800 0 296 2048)))
      (is
       (= 4096
          (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
           10000 0 8192 8192)))
      (multiple-value-bind (persisted-root present-p)
          (kv-get-chain-record database :state-history (hash32-bytes pivot))
        (is present-p)
        (is (bytes= persisted-root (hash32-bytes root)))))))

#+sbcl
(deftest snap-heal-rocksdb-local-read-batch-uses-bounded-workers
  (:layer :integration :module :p2p)
  (let* ((path
           (merge-pathnames
            (make-pathname
             :directory
             `(:relative ,(format nil "ethereum-lisp-snap-read-~A" (gensym))))
            #P"/private/tmp/"))
         (references
           (map 'vector #'snap-test-index-hash
                (loop for index below
                        ethereum-lisp.snap-sync::+snap-sync-heal-local-reads-per-batch+
                      collect index)))
         (real-get-many
           (fdefinition 'ethereum-lisp.database:kv-get-chain-records))
         (mutex (sb-thread:make-mutex :name "snap-heal-read-test"))
         (worker-threads '())
         (decoder-threads '())
         (metadata-worker-threads '())
         (decoder-call-count 0)
         (call-count 0)
         (metadata-call-count 0))
    (unwind-protect
         (let ((database (make-rocksdb-key-value-database path)))
           (unwind-protect
                (let ((batch (make-kv-write-batch)))
                  (dotimes (index (length references))
                    (unless (zerop (mod index 7))
                      (ethereum-lisp.database:kv-batch-put-chain-record
                       batch :trie-node (aref references index)
                       (vector (mod index 256))))
                    (unless (zerop (mod index 5))
                      (ethereum-lisp.database:kv-batch-put-chain-record
                       batch :metadata
                       (ethereum-lisp.snap-sync::snap-sync-healed-subtree-identifier
                        (aref references index))
                       ethereum-lisp.snap-sync::+snap-sync-healed-subtree-value+)))
                  (kv-apply-batch database batch)
                  (setf
                   (fdefinition 'ethereum-lisp.database:kv-get-chain-records)
                   (lambda (candidate kind identifiers &optional default)
                     (when (and (eq candidate database) (eq kind :trie-node))
                       (sb-thread:with-mutex (mutex)
                         (incf call-count)
                         (pushnew sb-thread:*current-thread* worker-threads
                                  :test #'eq)))
                     (when (and (eq candidate database) (eq kind :metadata))
                       (sb-thread:with-mutex (mutex)
                         (incf metadata-call-count)
                         (pushnew sb-thread:*current-thread*
                                  metadata-worker-threads :test #'eq)))
                     (funcall
                      real-get-many candidate kind identifiers default)))
                  (is
                   (= 8
                      ethereum-lisp.snap-sync::*snap-sync-heal-local-read-workers*))
                  (let ((ethereum-lisp.snap-sync::*snap-sync-heal-local-read-workers*
                          8))
                    (multiple-value-bind (values present decoded)
                        (ethereum-lisp.snap-sync::snap-sync-heal-local-node-batch
                         database references
                         :decoder
                         (lambda (index value)
                           (sb-thread:with-mutex (mutex)
                             (incf decoder-call-count)
                             (pushnew sb-thread:*current-thread*
                                      decoder-threads :test #'eq))
                           (list index (aref value 0))))
                      (is (= 8 call-count))
                      (is (= 8 (length worker-threads)))
                      (is (= 8 (length decoder-threads)))
                      (is (= (- (length references)
                                (ceiling (length references) 7))
                             decoder-call-count))
                      (is (= (length references) (length values)))
                      (is (= (length references) (length present)))
                      (is (= (length references) (length decoded)))
                      (dotimes (index (length references))
                        (if (zerop (mod index 7))
                            (progn
                              (is (zerop (aref present index)))
                              (is (null (aref values index)))
                              (is (null (aref decoded index))))
                            (progn
                              (is (= 1 (aref present index)))
                              (is (bytes= (vector (mod index 256))
                                         (aref values index)))
                              (is (equal (list index (mod index 256))
                                         (aref decoded index))))))))
                  (let ((ethereum-lisp.snap-sync::*snap-sync-heal-local-read-workers*
                          8))
                    (let ((present
                            (ethereum-lisp.snap-sync::snap-sync-healed-subtrees-present
                             database references)))
                      (is (= 8 metadata-call-count))
                      (is (= 8 (length metadata-worker-threads)))
                      (dotimes (index (length references))
                        (is (= (if (zerop (mod index 5)) 0 1)
                               (aref present index))))))
                  (kv-put-chain-record
                   database :metadata
                   (ethereum-lisp.snap-sync::snap-sync-healed-subtree-identifier
                    (aref references 0))
                   #(2))
                  (signals
                   ethereum-lisp.validation:storage-error
                   (ethereum-lisp.snap-sync::snap-sync-healed-subtrees-present
                    database (vector (aref references 0))))
                  (setf
                   (fdefinition 'ethereum-lisp.database:kv-get-chain-records)
                   (lambda (candidate kind identifiers &optional default)
                     (when (and (eq candidate database)
                                (eq kind :trie-node)
                                (bytes= (aref identifiers 0)
                                        (aref references
                                              (floor (length references) 4))))
                       (error "Injected parallel snap read failure"))
                     (funcall
                      real-get-many candidate kind identifiers default)))
                  (let ((ethereum-lisp.snap-sync::*snap-sync-heal-local-read-workers*
                          8))
                    (signals
                     error
                     (ethereum-lisp.snap-sync::snap-sync-heal-local-node-batch
                      database references))))
             (setf (fdefinition 'ethereum-lisp.database:kv-get-chain-records)
                   real-get-many)
             (close-rocksdb-key-value-database database)))
      (setf (fdefinition 'ethereum-lisp.database:kv-get-chain-records)
            real-get-many)
      (when (probe-file path)
        (uiop:delete-directory-tree path :validate t)))))

#+sbcl
(deftest snap-state-healer-peer-first-experiment-falls-back-to-rocksdb
  (:layer :integration :module :p2p)
  (let* ((path
           (merge-pathnames
            (make-pathname
             :directory
             `(:relative ,(format nil "ethereum-lisp-snap-remote-~A" (gensym))))
            #P"/private/tmp/"))
         (source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (address (snap-test-address-from-integer 777))
         (pivot (make-hash32 (snap-test-hash 235)))
         (target (make-hash32 (snap-test-hash 236)))
         (genesis (make-hash32 (snap-test-hash 237)))
         (authority (make-hash32 (snap-test-hash 238)))
         (trie-node-requests 0)
         (unavailable-requests 0))
    ;; A single account produces a hashed root leaf but no four-nibble subtree
    ;; sentinel, so repeated direct heals exercise the root lookup itself.
    (state-db-set-account
     source-state address (make-state-account :balance 777))
    (let* ((root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base-source (snap-test-source backend))
           (source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (ethereum-lisp.snap-sync:snap-sync-source-account-range
               base-source)
              :storage-ranges
              (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
               base-source)
              :bytecodes
              (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base-source)
              :trie-nodes
              (lambda (request)
                (incf trie-node-requests)
                (funcall
                 (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
                  base-source)
                 request))))
           (progress
             (ethereum-lisp.snap-sync::snap-sync-make-progress
              :pivot-hash pivot :pivot-number 2002 :state-root root
              :partial-root +empty-trie-hash+ :target-hash target
              :chain-id 560048 :genesis-hash genesis
              :authority-id authority :completed-p nil
              :tasks
              (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
               :count 1 :completed-p t))))
      (unwind-protect
           (let ((database (make-rocksdb-key-value-database path)))
             (unwind-protect
                  (progn
                    ;; Populate the target through the ordinary miss path.
                    (let ((ethereum-lisp.snap-sync::*snap-sync-heal-remote-first-p*
                            nil))
                      (ethereum-lisp.snap-sync::snap-sync-heal-state
                       database (list source) progress 350))
                    (setf trie-node-requests 0)
                    ;; The mutation/control path must still reuse local data.
                    (let ((ethereum-lisp.snap-sync::*snap-sync-heal-remote-first-p*
                            nil))
                      (ethereum-lisp.snap-sync::snap-sync-heal-state
                       database (list source) progress 350))
                    (is (zerop trie-node-requests))
                    ;; The measured production default stays on local MultiGet;
                    ;; explicitly enabling the experiment replaces cold random
                    ;; reads with authenticated peer path requests.
                    (is
                     (not
                      ethereum-lisp.snap-sync::*snap-sync-heal-remote-first-p*))
                    (let ((ethereum-lisp.snap-sync::*snap-sync-heal-remote-first-p*
                            t))
                      (ethereum-lisp.snap-sync::snap-sync-heal-state
                       database (list source) progress 350))
                    (is (plusp trie-node-requests))
                    ;; Public peers eventually prune an old pivot. After one
                    ;; failed peer generation, durable data must remain a
                    ;; usable fallback instead of causing a restart loop.
                    (let ((unavailable-source
                            (ethereum-lisp.snap-sync:make-snap-sync-source
                             :account-range
                             (ethereum-lisp.snap-sync:snap-sync-source-account-range
                              base-source)
                             :storage-ranges
                             (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
                              base-source)
                             :bytecodes
                             (ethereum-lisp.snap-sync:snap-sync-source-bytecodes
                              base-source)
                             :trie-nodes
                             (lambda (request)
                               (declare (ignore request))
                               (incf unavailable-requests)
                               (error
                                'ethereum-lisp.snap-sync:snap-sync-state-unavailable
                                :request-kind "trie-nodes")))))
                      (let ((ethereum-lisp.snap-sync::*snap-sync-heal-remote-first-p*
                              t))
                        (ethereum-lisp.snap-sync::snap-sync-heal-state
                         database (list unavailable-source) progress 350)))
                    (is (plusp unavailable-requests)))
               (close-rocksdb-key-value-database database)))
        (when (probe-file path)
          (uiop:delete-directory-tree path :validate t))))))

(deftest snap-state-healer-skips-definitely-absent-subtree-proof-reads
  (:layer :integration :module :p2p)
  (multiple-value-bind (source-state addresses)
      (snap-test-partitioned-state)
    (declare (ignore addresses))
    (let* ((source-database (make-memory-key-value-database))
           (target-database (make-memory-key-value-database))
           (root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (source (snap-test-source backend))
           (progress
             (ethereum-lisp.snap-sync::snap-sync-make-progress
              :pivot-hash (make-hash32 (snap-test-hash 217))
              :pivot-number 5990 :state-root root
              :partial-root +empty-trie-hash+
              :target-hash (make-hash32 (snap-test-hash 218))
              :chain-id 560048
              :genesis-hash (make-hash32 (snap-test-hash 219))
              :authority-id (make-hash32 (snap-test-hash 220))
              :completed-p nil
              :tasks
              (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
               :count 1 :completed-p t)))
           (exact-read-count 0)
           (proof-count 0)
           (real-present
             (fdefinition
              'ethereum-lisp.snap-sync::snap-sync-healed-subtrees-present))
           (real-populate
             (fdefinition
              'ethereum-lisp.snap-sync::snap-sync-populate-healed-subtree-batch)))
      ;; The empty target has no durable completion proofs.  Production must
      ;; still publish proofs, but the startup negative filter should reject
      ;; every first-pass candidate without a metadata point/MultiGet.
      (let ((ethereum-lisp.snap-sync::*snap-sync-healed-subtree-prefix-nibbles*
              1)
            (ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles*
              1)
            (ethereum-lisp.snap-sync::*snap-sync-range-nested-subtree-prefix-nibbles*
              1))
        (unwind-protect
             (progn
               (setf
                (fdefinition
                 'ethereum-lisp.snap-sync::snap-sync-healed-subtrees-present)
                (lambda (database references &optional kinds)
                  (incf exact-read-count (length references))
                  (funcall real-present database references kinds))
                (fdefinition
                 'ethereum-lisp.snap-sync::snap-sync-populate-healed-subtree-batch)
                (lambda (batch reference &optional (kind :account))
                  (incf proof-count)
                  (funcall real-populate batch reference kind)))
               (let ((completed
                       (ethereum-lisp.snap-sync::snap-sync-heal-state
                        target-database (list source) progress 350)))
                 (is
                  (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
                   completed))))
          (setf
           (fdefinition
            'ethereum-lisp.snap-sync::snap-sync-healed-subtrees-present)
           real-present
           (fdefinition
            'ethereum-lisp.snap-sync::snap-sync-populate-healed-subtree-batch)
           real-populate)))
      (is (plusp proof-count))
      (is (zerop exact-read-count)))))

(deftest snap-healed-subtree-public-depth-matches-geth-style-shortcut
  (:layer :unit :module :p2p)
  (let ((lookup-depth
          ethereum-lisp.snap-sync::*snap-sync-healed-subtree-prefix-nibbles*)
        (publication-depth
          ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles*)
        (nested-depth
          ethereum-lisp.snap-sync::*snap-sync-range-nested-subtree-prefix-nibbles*))
    (is (= 4 lookup-depth))
    ;; Range pages publish at the first lookup depth for the one-read unchanged
    ;; bucket fast path, plus one bounded child layer for a changed bucket.
    (is (= lookup-depth publication-depth))
    (is (= (1+ publication-depth) nested-depth))
    (is
     (not
      (ethereum-lisp.snap-sync::snap-sync-healed-subtree-candidate-p
       (ethereum-lisp.snap-sync::snap-sync-make-heal-work
        :account nil (make-byte-vector (1- lookup-depth))
        (snap-test-hash 221)))))
    (is
     (not
      (ethereum-lisp.snap-sync::snap-sync-healed-subtree-candidate-p
       (ethereum-lisp.snap-sync::snap-sync-make-heal-work
        :account nil (make-byte-vector 0) (snap-test-hash 220)))))
    (is
     (ethereum-lisp.snap-sync::snap-sync-healed-subtree-candidate-p
      (ethereum-lisp.snap-sync::snap-sync-make-heal-work
       :storage (snap-test-hash 219) (make-byte-vector 0)
       (snap-test-hash 218))))
    (is
     (eq
      :storage-root
      (ethereum-lisp.snap-sync::snap-sync-healed-subtree-proof-kind
       (ethereum-lisp.snap-sync::snap-sync-make-heal-work
        :storage (snap-test-hash 219) (make-byte-vector 0)
        (snap-test-hash 218)))))
    (is
     (ethereum-lisp.snap-sync::snap-sync-healed-subtree-publication-candidate-p
      (ethereum-lisp.snap-sync::snap-sync-make-heal-work
       :storage (snap-test-hash 219) (make-byte-vector 0)
       (snap-test-hash 218))))
    (is
     (eq
      :armed
      (ethereum-lisp.snap-sync::snap-sync-healed-subtree-miss-marker-state
       (ethereum-lisp.snap-sync::snap-sync-make-heal-work
        :storage (snap-test-hash 219) (make-byte-vector 0)
        (snap-test-hash 218) :marker-state :inside))))
    (is
     (ethereum-lisp.snap-sync::snap-sync-healed-subtree-candidate-p
      (ethereum-lisp.snap-sync::snap-sync-make-heal-work
       :account nil (make-byte-vector lookup-depth) (snap-test-hash 222))))
    (is
     (ethereum-lisp.snap-sync::snap-sync-healed-subtree-candidate-p
      (ethereum-lisp.snap-sync::snap-sync-make-heal-work
       :account nil (make-byte-vector publication-depth)
       (snap-test-hash 225) :marker-state :inside)))
    (is
     (ethereum-lisp.snap-sync::snap-sync-healed-subtree-publication-candidate-p
      (ethereum-lisp.snap-sync::snap-sync-make-heal-work
       :account nil (make-byte-vector lookup-depth) (snap-test-hash 223))))
    ;; Finer proofs written by older runtimes and completed changed buckets
    ;; remain eligible below the new coarse publication boundary.
    (is
     (ethereum-lisp.snap-sync::snap-sync-healed-subtree-candidate-p
      (ethereum-lisp.snap-sync::snap-sync-make-heal-work
       :account nil (make-byte-vector nested-depth)
       (snap-test-hash 224))))))

(deftest snap-state-healer-finds-range-proof-inside-coarser-miss
  (:layer :integration :module :p2p)
  ;; An open bucket at the range publication depth may still contain a smaller
  ;; proved subtree. A miss at that parent must not mask the valid nested proof
  ;; and force every already authenticated descendant through the decoder.
  (let* ((trie (make-mpt))
         (first-key (make-byte-vector 32))
         (second-key (make-byte-vector 32))
         (account
           (state-account-rlp
            (make-state-account :nonce 1 :balance 900001)))
         (baseline-database (make-memory-key-value-database))
         (proved-database (make-memory-key-value-database)))
    ;; Both keys share their first two nibbles, making the hashed branch at
    ;; publication depth two the miss that arms the region. Their third nibble
    ;; differs, making each hashed leaf a depth-three proof candidate below
    ;; :INSIDE work.
    (setf (aref second-key 1) #x10)
    (mpt-put trie first-key account)
    (mpt-put trie second-key account)
    (let* ((root (make-hash32 (mpt-root-hash trie)))
           (records (mpt-dirty-node-records trie))
           (nested (mpt-hashed-subtrees-with-prefix-at-depth trie 3))
           (proved-reference (cdar nested))
           (source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (lambda (&rest arguments)
                (declare (ignore arguments))
                (error "Nested-proof fixture requested an account range"))
              :storage-ranges
              (lambda (&rest arguments)
                (declare (ignore arguments))
                (error "Nested-proof fixture requested a storage range"))
              :bytecodes
              (lambda (&rest arguments)
                (declare (ignore arguments))
                (error "Nested-proof fixture requested bytecode"))
              :trie-nodes
              (lambda (&rest arguments)
                (declare (ignore arguments))
                (error "Nested-proof fixture requested a trie node"))))
           (genesis (make-hash32 (snap-test-hash 225)))
           (authority (make-hash32 (snap-test-hash 226))))
      (is proved-reference)
      (is (= 2 (length nested)))
      (dolist (database (list baseline-database proved-database))
        (let ((batch (make-kv-write-batch)))
          (ethereum-lisp.snap-sync::snap-sync-populate-verified-trie-records-batch
           database batch records)
          (ethereum-lisp.snap-sync::snap-sync-populate-incomplete-records-batch
           batch (mapcar #'car records))
          (kv-apply-batch database batch)))
      (let ((batch (make-kv-write-batch)))
        (ethereum-lisp.snap-sync::snap-sync-populate-healed-subtree-batch
         batch proved-reference :account)
        (kv-apply-batch proved-database batch))
      (labels ((progress (seed)
                 (ethereum-lisp.snap-sync::snap-sync-make-progress
                  :pivot-hash (make-hash32 (snap-test-hash seed))
                  :pivot-number 6050 :state-root root
                  :partial-root +empty-trie-hash+
                  :target-hash (make-hash32 (snap-test-hash (1+ seed)))
                  :chain-id 560048 :genesis-hash genesis
                  :authority-id authority :completed-p nil
                  :complete-node-scheme-p t
                  :tasks
                  (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
                   :count 1 :completed-p t)))
               (run (database seed)
                 (let ((processed nil) (fetched nil) (skipped nil))
                   (ethereum-lisp.snap-sync::snap-sync-heal-state
                    database (list source) (progress seed) 350
                    :on-heal-progress
                    (lambda (snapshot)
                      (when
                          (ethereum-lisp.snap-sync:snap-sync-heal-progress-completed-p
                           snapshot)
                        (setf
                         processed
                         (ethereum-lisp.snap-sync:snap-sync-heal-progress-processed-nodes
                          snapshot)
                         fetched
                         (ethereum-lisp.snap-sync:snap-sync-heal-progress-fetched-nodes
                          snapshot)
                         skipped
                         (ethereum-lisp.snap-sync:snap-sync-heal-progress-skipped-subtrees
                          snapshot)))))
                   (values processed fetched skipped))))
        (let ((ethereum-lisp.snap-sync::*snap-sync-healed-subtree-prefix-nibbles*
                1)
              (ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles*
                2)
              (ethereum-lisp.snap-sync::*snap-sync-range-nested-subtree-prefix-nibbles*
                3))
          (multiple-value-bind
                (baseline-processed baseline-fetched baseline-skipped)
              (run baseline-database 227)
            (multiple-value-bind
                  (proved-processed proved-fetched proved-skipped)
                (run proved-database 229)
              (is (zerop baseline-fetched))
              (is (zerop proved-fetched))
              (is (< proved-processed baseline-processed))
              (is (> proved-skipped baseline-skipped)))))))))

(deftest snap-state-healer-layered-proofs-bound-a-changed-coarse-bucket
  (:layer :integration :module :p2p)
  ;; A pivot changes one of sixteen children below a coarse bucket. A stale
  ;; coarse proof must miss, while the nested layer should skip the other
  ;; fifteen children without decoding their local trie nodes.
  (labels ((fixture-trie (changed-p)
             (let ((trie (make-mpt)))
               (dotimes (index 256 trie)
                 (let* ((bucket (floor index 16))
                        (item (mod index 16))
                        (key (make-byte-vector 32))
                        (account
                          (state-account-rlp
                           (make-state-account
                            :nonce (if (and changed-p (zerop index)) 999 index)
                            :balance (+ 100000 index)))))
                   ;; Every key is below coarse prefix 3. The low nibble of
                   ;; byte zero selects one of sixteen nested children.
                   (setf (aref key 0) (+ #x30 bucket)
                         (aref key 31) item)
                   (mpt-put trie key account))))))
    (let* ((old-trie (fixture-trie nil))
           (new-trie (fixture-trie t))
           (new-root (make-hash32 (mpt-root-hash new-trie)))
           (new-records (mpt-dirty-node-records new-trie))
           (old-coarse
             (mapcar #'cdr
                     (mpt-hashed-subtrees-with-prefix-at-depth old-trie 1)))
           (old-nested
             (mapcar #'cdr
                     (mpt-hashed-subtrees-with-prefix-at-depth old-trie 2)))
           (new-nested
             (mapcar #'cdr
                     (mpt-hashed-subtrees-with-prefix-at-depth new-trie 2)))
           (coarse-only-database (make-memory-key-value-database))
           (layered-database (make-memory-key-value-database))
           (source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (lambda (&rest arguments)
                (declare (ignore arguments))
                (error "Layered-proof fixture requested an account range"))
              :storage-ranges
              (lambda (&rest arguments)
                (declare (ignore arguments))
                (error "Layered-proof fixture requested a storage range"))
              :bytecodes
              (lambda (&rest arguments)
                (declare (ignore arguments))
                (error "Layered-proof fixture requested bytecode"))
              :trie-nodes
              (lambda (&rest arguments)
                (declare (ignore arguments))
                (error "Layered-proof fixture requested a trie node"))))
           (genesis (make-hash32 (snap-test-hash 235)))
           (authority (make-hash32 (snap-test-hash 236))))
      (is (= 1 (length old-coarse)))
      (is (= 16 (length old-nested)))
      (is
       (= 15
          (count-if
           (lambda (reference) (find reference new-nested :test #'bytes=))
           old-nested)))
      (dolist (database (list coarse-only-database layered-database))
        (let ((batch (make-kv-write-batch)))
          (ethereum-lisp.snap-sync::snap-sync-populate-verified-trie-records-batch
           database batch new-records)
          (ethereum-lisp.snap-sync::snap-sync-populate-incomplete-records-batch
           batch (mapcar #'car new-records))
          (dolist (reference old-coarse)
            (ethereum-lisp.snap-sync::snap-sync-populate-healed-subtree-batch
             batch reference :account))
          (kv-apply-batch database batch)))
      (let ((batch (make-kv-write-batch)))
        (dolist (reference old-nested)
          (ethereum-lisp.snap-sync::snap-sync-populate-healed-subtree-batch
           batch reference :account))
        (kv-apply-batch layered-database batch))
      (labels ((progress (seed)
                 (ethereum-lisp.snap-sync::snap-sync-make-progress
                  :pivot-hash (make-hash32 (snap-test-hash seed))
                  :pivot-number 6060 :state-root new-root
                  :partial-root +empty-trie-hash+
                  :target-hash (make-hash32 (snap-test-hash (1+ seed)))
                  :chain-id 560048 :genesis-hash genesis
                  :authority-id authority :completed-p nil
                  :complete-node-scheme-p t
                  :tasks
                  (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
                   :count 1 :completed-p t)))
               (run (database seed)
                 (let ((processed nil) (fetched nil) (skipped nil))
                   (ethereum-lisp.snap-sync::snap-sync-heal-state
                    database (list source) (progress seed) 350
                    :on-heal-progress
                    (lambda (snapshot)
                      (when
                          (ethereum-lisp.snap-sync:snap-sync-heal-progress-completed-p
                           snapshot)
                        (setf
                         processed
                         (ethereum-lisp.snap-sync:snap-sync-heal-progress-processed-nodes
                          snapshot)
                         fetched
                         (ethereum-lisp.snap-sync:snap-sync-heal-progress-fetched-nodes
                          snapshot)
                         skipped
                         (ethereum-lisp.snap-sync:snap-sync-heal-progress-skipped-subtrees
                          snapshot)))))
                   (values processed fetched skipped))))
        (let ((ethereum-lisp.snap-sync::*snap-sync-healed-subtree-prefix-nibbles*
                1)
              (ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles*
                1)
              (ethereum-lisp.snap-sync::*snap-sync-range-nested-subtree-prefix-nibbles*
                2))
          (multiple-value-bind
                (coarse-processed coarse-fetched coarse-skipped)
              (run coarse-only-database 237)
            (multiple-value-bind
                  (layered-processed layered-fetched layered-skipped)
                (run layered-database 239)
              (is (zerop coarse-fetched))
              (is (zerop layered-fetched))
              (is (> layered-skipped coarse-skipped))
              (is (>= layered-skipped 15))
              ;; The nested layer turns a changed 16-way bucket into one
              ;; changed child plus bounded metadata lookups.
              (is (< (* 2 layered-processed) coarse-processed)))))))))

(deftest snap-state-healer-reuses-proved-subtrees-across-pivots
  (:layer :integration :module :p2p)
  (multiple-value-bind (source-state addresses)
      (snap-test-partitioned-state)
    ;; A multi-branch storage trie proves that the cache is useful inside one
    ;; large contract, not only after its enclosing account subtree completes.
    (loop for index from 1 to 32
          do (state-db-set-storage
              source-state (first addresses)
              (make-hash32 (snap-test-index-hash index)) index))
    (let* ((first-state (state-db-copy source-state))
           (first-root (state-db-root first-state))
           (first-storage-root
             (state-db-get-storage-root first-state (first addresses)))
           (second-root
             (progn
               ;; Change the account leaf that owns the storage trie while
               ;; preserving its slots. The account proof must miss, but its
               ;; unchanged storage-subtree proofs remain reusable.
               (state-db-set-account
                source-state (first addresses)
                (make-state-account :nonce 999 :balance 999999))
               (state-db-root source-state)))
           (first-source-database (make-memory-key-value-database))
           (second-source-database (make-memory-key-value-database))
           (target-database (make-memory-key-value-database))
           (first-backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              first-source-database first-state))
           (second-backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              second-source-database source-state))
           (first-source (snap-test-source first-backend))
           (second-source (snap-test-source second-backend))
           (genesis (make-hash32 (snap-test-hash 221)))
           (authority (make-hash32 (snap-test-hash 222)))
           (first-processed nil)
           (second-processed nil)
           (second-skipped-subtrees nil)
           (cache-batches 0)
           (cache-hits 0)
           (storage-cache-hits 0)
           (proof-count 0)
           (storage-proof-count 0)
           (proof-batches (make-hash-table :test #'eq))
           (real-present-batch
             (fdefinition
              'ethereum-lisp.snap-sync::snap-sync-healed-subtrees-present))
           (real-populate
             (fdefinition
              'ethereum-lisp.snap-sync::snap-sync-populate-healed-subtree-batch)))
      (labels ((progress (state-root pivot-seed target-seed number)
                 (ethereum-lisp.snap-sync::snap-sync-make-progress
                  :pivot-hash (make-hash32 (snap-test-hash pivot-seed))
                  :pivot-number number :state-root state-root
                  :partial-root +empty-trie-hash+
                  :target-hash (make-hash32 (snap-test-hash target-seed))
                  :chain-id 560048 :genesis-hash genesis
                  :authority-id authority :completed-p nil
                  :tasks
                  (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
                   :count 1 :completed-p t))))
        ;; A one-nibble boundary keeps this fixture small while exercising the
        ;; same content-addressed proof and completion-sentinel path as the
        ;; four-nibble public-network setting.
        (let ((ethereum-lisp.snap-sync::*snap-sync-healed-subtree-prefix-nibbles*
                1)
              (ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles*
                1)
              (ethereum-lisp.snap-sync::*snap-sync-range-nested-subtree-prefix-nibbles*
                2))
          (unwind-protect
               (progn
                 (setf
                  (fdefinition
                   'ethereum-lisp.snap-sync::snap-sync-populate-healed-subtree-batch)
                  (lambda (batch reference &optional (kind :account))
                    (incf proof-count)
                    (when (member kind '(:storage :storage-root))
                      (incf storage-proof-count))
                    (incf (gethash batch proof-batches 0))
                    (funcall real-populate batch reference kind)))
                 (ethereum-lisp.snap-sync::snap-sync-heal-state
                  target-database (list first-source)
                  (progress first-root 223 224 6000) 350
                  :on-heal-progress
                  (lambda (snapshot)
                    (when
                        (ethereum-lisp.snap-sync::snap-sync-heal-progress-completed-p
                         snapshot)
                      (setf first-processed
                            (ethereum-lisp.snap-sync::snap-sync-heal-progress-processed-nodes
                             snapshot))))))
            (setf
             (fdefinition
              'ethereum-lisp.snap-sync::snap-sync-populate-healed-subtree-batch)
             real-populate))
          (is
           (ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p
            target-database (hash32-bytes first-storage-root) :storage-root))
          (unwind-protect
               (progn
                 (setf
                  (fdefinition
                   'ethereum-lisp.snap-sync::snap-sync-healed-subtrees-present)
                  (lambda (database references &optional kinds)
                    (incf cache-batches)
                    (let ((present
                            (funcall
                             real-present-batch database references kinds)))
                      (dotimes (index (length present))
                        (when (= 1 (aref present index))
                          (incf cache-hits)
                          (when (and kinds
                                     (member (elt kinds index)
                                             '(:storage :storage-root)))
                            (incf storage-cache-hits))))
                      present)))
                 (ethereum-lisp.snap-sync::snap-sync-heal-state
                  target-database (list second-source)
                  (progress second-root 225 226 6010) 350
                  :on-heal-progress
                  (lambda (snapshot)
                    (when
                        (ethereum-lisp.snap-sync::snap-sync-heal-progress-completed-p
                         snapshot)
                      (setf second-processed
                            (ethereum-lisp.snap-sync::snap-sync-heal-progress-processed-nodes
                             snapshot)
                            second-skipped-subtrees
                            (ethereum-lisp.snap-sync::snap-sync-heal-progress-skipped-subtrees
                             snapshot))))))
            (setf
             (fdefinition
              'ethereum-lisp.snap-sync::snap-sync-healed-subtrees-present)
             real-present-batch)))
        (is (plusp cache-batches))
        (is (plusp cache-hits))
        (is (= cache-hits second-skipped-subtrees))
        (is (plusp storage-cache-hits))
        (is (plusp first-processed))
        (is (> proof-count 1))
        (is (plusp storage-proof-count))
        ;; Per-subtree KV commits make every proof use a distinct batch.  The
        ;; production path must retain a hard 2,048-proof cap while publishing
        ;; more than one independent proof in the same durable transaction.
        (is (<= (loop for count being the hash-values of proof-batches
                      maximize count)
                ethereum-lisp.snap-sync::+snap-sync-healed-subtrees-per-batch+))
        (is (> (loop for count being the hash-values of proof-batches
                     maximize count)
               1))
        (is (< (hash-table-count proof-batches) proof-count))
        ;; Without the production cache-hit branch the second traversal
        ;; decodes the same number of nodes as the first and this witness fails.
        (is (< second-processed first-processed))
        (multiple-value-bind (persisted-root present-p)
            (kv-get-chain-record
             target-database :state-history (snap-test-hash 225))
          (is present-p)
          (is (bytes= persisted-root (hash32-bytes second-root))))))))

(deftest snap-state-healer-uses-geth-complete-node-difference-frontier
  (:layer :integration :module :p2p)
  ;; Geth's hash scheme stops at any locally present node because its writers
  ;; publish a parent only after every descendant is complete. Reproduce that
  ;; contract independently of coarse subtree proofs and compare it with the
  ;; legacy conservative walk over the exact same stored trie.
  (let ((state (make-state-db))
        (addresses '()))
    (loop for index from 1 to 2048
          for address = (snap-test-address-from-integer index)
          do (push address addresses)
             (state-db-set-account
              state address
              (make-state-account :nonce index :balance (+ 100000 index))))
    (let* ((first-state (state-db-copy state))
           (first-root (state-db-root first-state))
           (changed-address (first addresses))
           (second-root
             (progn
               (state-db-set-account
                state changed-address
                (make-state-account :nonce 999999 :balance 777777))
               (state-db-root state)))
           (source-database (make-memory-key-value-database))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database state))
           (source (snap-test-source backend))
           (exact-database (make-memory-key-value-database))
           (legacy-database (make-memory-key-value-database))
           (records
             (mpt-dirty-node-records
              (first (state-db-persistence-tries first-state))))
           (genesis (make-hash32 (snap-test-hash 227)))
           (authority (make-hash32 (snap-test-hash 228))))
      (declare (ignore first-root))
      (is
       (ethereum-lisp.snap-sync::snap-sync-enable-complete-node-scheme-p
        exact-database))
      (dolist (database (list exact-database legacy-database))
        (let ((batch (make-kv-write-batch)))
          (ethereum-lisp.snap-sync::snap-sync-populate-verified-trie-records-batch
           database batch records)
          (kv-apply-batch database batch)))
      (labels ((progress (seed complete-node-scheme-p)
                 (ethereum-lisp.snap-sync::snap-sync-make-progress
                  :pivot-hash (make-hash32 (snap-test-hash seed))
                  :pivot-number 6100 :state-root second-root
                  :partial-root +empty-trie-hash+
                  :target-hash (make-hash32 (snap-test-hash (1+ seed)))
                  :chain-id 560048 :genesis-hash genesis
                  :authority-id authority :completed-p nil
                  :complete-node-scheme-p complete-node-scheme-p
                  :tasks
                  (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
                   :count 1 :completed-p t)))
               (run (database seed complete-node-scheme-p)
                 (let ((processed nil) (fetched nil) (skipped nil))
                   (ethereum-lisp.snap-sync::snap-sync-heal-state
                    database (list source)
                    (progress seed complete-node-scheme-p) 350
                    :on-heal-progress
                    (lambda (snapshot)
                      (when
                          (ethereum-lisp.snap-sync::snap-sync-heal-progress-completed-p
                           snapshot)
                        (setf
                         processed
                         (ethereum-lisp.snap-sync::snap-sync-heal-progress-processed-nodes
                          snapshot)
                         fetched
                         (ethereum-lisp.snap-sync::snap-sync-heal-progress-fetched-nodes
                          snapshot)
                         skipped
                         (ethereum-lisp.snap-sync::snap-sync-heal-progress-skipped-subtrees
                          snapshot)))))
                   (values processed fetched skipped))))
        (multiple-value-bind (exact-processed exact-fetched exact-skipped)
            (run exact-database 229 t)
          (multiple-value-bind
                (legacy-processed legacy-fetched legacy-skipped)
              (run legacy-database 231 nil)
            (declare (ignore legacy-skipped))
            (is (plusp exact-fetched))
            (is (plusp exact-skipped))
            (is (= exact-fetched legacy-fetched))
            (is (< exact-processed legacy-processed))
            (is
             (zerop
              (hash-table-count
               (ethereum-lisp.snap-sync::snap-sync-load-incomplete-nodes
                exact-database))))
            ;; The mutation control is quantitative: removing the complete-
            ;; node branch makes both runs decode the same full local trie.
            (is (< (* 8 exact-processed) legacy-processed))))))))

(deftest snap-state-healer-batches-deferred-storage-roots
  (:layer :integration :module :p2p)
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-memory-key-value-database))
         (addresses
           (loop for index from 1 to 16
                 collect
                 (make-address
                  (concatenate
                   'vector (make-byte-vector 19) (vector index)))))
         (largest-storage-path-batch 0)
         (request-phases '())
         (deferred-work-count 0))
    (loop for address in addresses
          for index from 1
          do (state-db-set-storage
              source-state address
              (make-hash32
               (make-byte-vector 32 :initial-element index))
              (+ 1000 index)))
    (let* ((root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base (snap-test-source backend))
           (source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (ethereum-lisp.snap-sync:snap-sync-source-account-range base)
              :storage-ranges
              (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges base)
              :bytecodes
              (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base)
              :trie-nodes
              (lambda (request)
                (let ((storage-paths
                        (count-if
                         (lambda (path-set) (= 2 (length path-set)))
                         (ethereum-lisp.snap:snap-get-trie-nodes-paths
                          request))))
                  (push (if (plusp storage-paths) :storage :account)
                        request-phases)
                  (setf largest-storage-path-batch
                        (max largest-storage-path-batch storage-paths)))
                (funcall
                 (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes base)
                 request))))
           (progress
             (ethereum-lisp.snap-sync::snap-sync-make-progress
              :pivot-hash (make-hash32 (snap-test-hash 227))
              :pivot-number 6020 :state-root root
              :partial-root +empty-trie-hash+
              :target-hash (make-hash32 (snap-test-hash 228))
              :chain-id 560048
              :genesis-hash (make-hash32 (snap-test-hash 229))
              :authority-id (make-hash32 (snap-test-hash 230))
              :completed-p nil
              :tasks
              (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
               :count 1 :completed-p t)))
           (real-defer
             (fdefinition
              'ethereum-lisp.snap-sync::snap-sync-heal-deferred-storage-work))
           (completed
             (unwind-protect
                  (progn
                    (setf
                     (fdefinition
                      'ethereum-lisp.snap-sync::snap-sync-heal-deferred-storage-work)
                     (lambda (account-hash reference)
                       (incf deferred-work-count)
                       (funcall real-defer account-hash reference)))
                    (ethereum-lisp.snap-sync::snap-sync-heal-state
                     target-database (list source) progress 350))
               (setf
                (fdefinition
                 'ethereum-lisp.snap-sync::snap-sync-heal-deferred-storage-work)
                real-defer))))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p completed))
      (is (= (length addresses) deferred-work-count))
      ;; Immediate DFS descent issues one network request per account here.
      ;; A bounded deferred frontier must put multiple storage roots on one
      ;; authenticated GetTrieNodes request instead.
      (is (> largest-storage-path-batch 1))
      (let ((seen-storage-p nil))
        (dolist (phase (nreverse request-phases))
          (if (eq phase :storage)
              (setf seen-storage-p t)
              ;; Immediate DFS storage descent turns this red: an account
              ;; request appears after the first storage request.
              (is (not seen-storage-p))))))))

(deftest snap-state-healer-consumes-account-subtree-dependency-proofs
  (:layer :integration :module :p2p)
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-memory-key-value-database))
         (addresses
           (loop with buckets = (make-array 16 :initial-element nil)
                 for integer from 1
                 for address = (snap-test-address-from-integer integer)
                 for account-hash =
                   (ethereum-lisp.crypto:keccak-256 (address-bytes address))
                 for nibble =
                   (aref
                    (ethereum-lisp.trie.encoding:keybytes-to-nibbles
                     account-hash :terminator nil)
                    0)
                 do (push address (aref buckets nibble))
                 when (= 4 (length (aref buckets nibble)))
                   return (nreverse (aref buckets nibble))))
         (account-node-read-p nil)
         (storage-paths 0)
         (skipped-subtrees 0))
    (loop for address in addresses
          for index from 1
          do (state-db-set-storage
              source-state address
              (make-hash32
               (make-byte-vector 32 :initial-element index))
              (+ 7000 index)))
    (let* ((root (state-db-root source-state))
           (account-hashes
             (mapcar
              (lambda (address)
                (ethereum-lisp.crypto:keccak-256 (address-bytes address)))
              addresses))
           (prefix
             (subseq
              (ethereum-lisp.trie.encoding:keybytes-to-nibbles
               (first account-hashes) :terminator nil)
              0 1))
           (dependencies
             (mapcar
              (lambda (address account-hash)
                (cons account-hash
                      (state-db-get-storage-root source-state address)))
              addresses account-hashes))
           (account-trie
             (ethereum-lisp.state::state-db-state-trie source-state))
           (persisted-root (mpt-persist target-database account-trie))
           (reference
             (cdr
              (find
               prefix
               (mpt-hashed-subtrees-with-prefix-at-depth
                (make-persisted-mpt
                 persisted-root
                 (lambda (hash)
                   (trie-node-store-get target-database hash)))
                1)
               :key #'car :test #'equalp)))
           (batch (make-kv-write-batch))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base (snap-test-source backend))
           (source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (ethereum-lisp.snap-sync:snap-sync-source-account-range base)
              :storage-ranges
              (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges base)
              :bytecodes
              (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base)
              :trie-nodes
              (lambda (request)
                (incf
                 storage-paths
                 (count-if
                  (lambda (path-set) (= 2 (length path-set)))
                  (ethereum-lisp.snap:snap-get-trie-nodes-paths request)))
                (funcall
                 (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes base)
                 request))))
           (progress
             (ethereum-lisp.snap-sync::snap-sync-make-progress
              :pivot-hash (make-hash32 (snap-test-hash 245))
              :pivot-number 6030 :state-root root
              :partial-root +empty-trie-hash+
              :target-hash (make-hash32 (snap-test-hash 246))
              :chain-id 560048
              :genesis-hash (make-hash32 (snap-test-hash 247))
              :authority-id (make-hash32 (snap-test-hash 248))
              :completed-p nil
              :tasks
              (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
               :count 1 :completed-p t)))
           (real-get-many
             (fdefinition 'ethereum-lisp.database:kv-get-chain-records)))
      (is (hash32= root persisted-root))
      (is reference)
      (ethereum-lisp.snap-sync::snap-sync-populate-account-subtree-dependencies-batch
       batch reference dependencies)
      (kv-apply-batch target-database batch)
      (unwind-protect
           (progn
             (setf
              (fdefinition 'ethereum-lisp.database:kv-get-chain-records)
              (lambda (database kind identifiers &optional default)
                (when (and (eq database target-database)
                           (eq kind :trie-node)
                           (find reference identifiers :test #'bytes=))
                  (setf account-node-read-p t))
                (funcall real-get-many database kind identifiers default)))
             (let ((ethereum-lisp.snap-sync::*snap-sync-healed-subtree-prefix-nibbles*
                     1)
                   (ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles*
                     1)
                   (ethereum-lisp.snap-sync::*snap-sync-range-nested-subtree-prefix-nibbles*
                     1))
               (is
                (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
                 (ethereum-lisp.snap-sync::snap-sync-heal-state
                  target-database (list source) progress 350
                  :on-heal-progress
                  (lambda (snapshot)
                    (when
                        (ethereum-lisp.snap-sync:snap-sync-heal-progress-completed-p
                         snapshot)
                      (setf skipped-subtrees
                            (ethereum-lisp.snap-sync:snap-sync-heal-progress-skipped-subtrees
                             snapshot)))))))))
        (setf (fdefinition 'ethereum-lisp.database:kv-get-chain-records)
              real-get-many))
      (is (not account-node-read-p))
      (is (= 1 skipped-subtrees))
      (is (plusp storage-paths)))))

(deftest snap-healed-subtree-publication-fails-closed
  (:layer :integration :module :p2p)
  (multiple-value-bind (source-state addresses)
      (snap-test-partitioned-state)
    (declare (ignore addresses))
    (let* ((source-database (make-memory-key-value-database))
           (target-database (make-instance 'snap-failing-test-database))
           (root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (source (snap-test-source backend))
           (pivot (make-hash32 (snap-test-hash 231)))
           (progress
             (ethereum-lisp.snap-sync::snap-sync-make-progress
              :pivot-hash pivot :pivot-number 6030 :state-root root
              :partial-root +empty-trie-hash+
              :target-hash (make-hash32 (snap-test-hash 232))
              :chain-id 560048
              :genesis-hash (make-hash32 (snap-test-hash 233))
              :authority-id (make-hash32 (snap-test-hash 234))
              :completed-p nil
              :tasks
              (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
               :count 1 :completed-p t)))
           (real-populate
             (fdefinition
              'ethereum-lisp.snap-sync::snap-sync-populate-healed-subtree-batch))
           (attempted-reference nil))
      (let ((ethereum-lisp.snap-sync::*snap-sync-healed-subtree-prefix-nibbles*
              1)
            (ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles*
              1)
            (ethereum-lisp.snap-sync::*snap-sync-range-nested-subtree-prefix-nibbles*
              1))
        (unwind-protect
             (progn
               (setf
                (fdefinition
                 'ethereum-lisp.snap-sync::snap-sync-populate-healed-subtree-batch)
                (lambda (batch reference &optional (kind :account))
                  (unless attempted-reference
                    (setf attempted-reference (copy-seq reference)
                          (snap-failing-test-database-fail-next-apply-p
                           target-database)
                          t))
                  (funcall real-populate batch reference kind)))
               (signals error
                 (ethereum-lisp.snap-sync::snap-sync-heal-state
                  target-database (list source) progress 350)))
          (setf
           (fdefinition
            'ethereum-lisp.snap-sync::snap-sync-populate-healed-subtree-batch)
           real-populate))
        (is attempted-reference)
        (is (not
             (ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p
              target-database attempted-reference)))
        (multiple-value-bind (state-root present-p)
            (kv-get-chain-record
             target-database :state-history (hash32-bytes pivot))
          (declare (ignore state-root))
          (is (not present-p)))
        (let ((completed
                (ethereum-lisp.snap-sync::snap-sync-heal-state
                 target-database (list source) progress 350)))
          (is
           (ethereum-lisp.snap-sync:snap-sync-progress-completed-p completed)))
        (is
         (ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p
          target-database attempted-reference))))))

(deftest snap-heal-checkpoint-rebase-and-completion-are-atomic
  (:layer :unit :module :p2p)
  (let* ((database (make-instance 'snap-failing-test-database))
         (pivot-a (make-hash32 (snap-test-hash 197)))
         (pivot-b (make-hash32 (snap-test-hash 198)))
         (root-a (make-hash32 (snap-test-hash 199)))
         (root-b (make-hash32 (snap-test-hash 200)))
         (target-a (make-hash32 (snap-test-hash 201)))
         (target-b (make-hash32 (snap-test-hash 202)))
         (genesis (make-hash32 (snap-test-hash 203)))
         (authority (make-hash32 (snap-test-hash 204)))
         (progress-a
           (ethereum-lisp.snap-sync::snap-sync-make-progress
            :pivot-hash pivot-a :pivot-number 4000 :state-root root-a
            :partial-root +empty-trie-hash+ :target-hash target-a
            :chain-id 560048 :genesis-hash genesis :authority-id authority
            :completed-p nil
            :tasks
            (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
             :count 1 :completed-p t)))
         (work-a
           (ethereum-lisp.snap-sync::snap-sync-make-heal-work
            :account nil (make-byte-vector 0) (hash32-bytes root-a))))
    (let ((batch (make-kv-write-batch)))
      (ethereum-lisp.snap-sync::snap-sync-populate-progress-batch
       batch progress-a)
      (ethereum-lisp.snap-sync::snap-sync-populate-heal-checkpoint-batch
       batch progress-a (list work-a) 1 0 1 1 100)
      (kv-apply-batch database batch))
    (setf (snap-failing-test-database-fail-next-apply-p database) t)
    (signals error
      (ethereum-lisp.snap-sync:snap-sync-rebase-progress
       database :pivot-hash pivot-b :pivot-number 4010 :state-root root-b
       :target-hash target-b :chain-id 560048 :genesis-hash genesis
       :authority-id authority))
    (multiple-value-bind (checkpoint present-p)
        (ethereum-lisp.snap-sync::snap-sync-read-heal-checkpoint
         database progress-a)
      (is present-p)
      (is (not (null checkpoint))))
    (let ((progress-b
            (ethereum-lisp.snap-sync:snap-sync-rebase-progress
             database :pivot-hash pivot-b :pivot-number 4010
             :state-root root-b :target-hash target-b :chain-id 560048
             :genesis-hash genesis :authority-id authority)))
      (is (not
           (hash32=
            root-b
            (ethereum-lisp.snap-sync:snap-sync-progress-partial-root
             progress-b))))
      (is (not
           (hash32=
            +empty-trie-hash+
            (ethereum-lisp.snap-sync:snap-sync-progress-partial-root
             progress-b))))
      (multiple-value-bind (checkpoint present-p)
          (ethereum-lisp.snap-sync::snap-sync-read-heal-checkpoint
           database progress-b)
        (is (null checkpoint))
        (is (not present-p)))
      (let* ((work-b
               (ethereum-lisp.snap-sync::snap-sync-make-heal-work
                :account nil (make-byte-vector 0) (hash32-bytes root-b)))
             (completed
               (ethereum-lisp.snap-sync::snap-sync-make-progress
                :pivot-hash pivot-b :pivot-number 4010 :state-root root-b
                :partial-root root-b :target-hash target-b
                :chain-id 560048 :genesis-hash genesis
                :authority-id authority :completed-p t
                :tasks
                (ethereum-lisp.snap-sync:snap-sync-progress-tasks
                 progress-b))))
        (let ((batch (make-kv-write-batch)))
          (ethereum-lisp.snap-sync::snap-sync-populate-heal-checkpoint-batch
           batch progress-b (list work-b) 2 1 1 1 200)
          (kv-apply-batch database batch))
        (let ((batch (make-kv-write-batch)))
          (ethereum-lisp.snap-sync::snap-sync-complete-batch batch completed)
          (setf (snap-failing-test-database-fail-next-apply-p database) t)
          (signals error (kv-apply-batch database batch)))
        (multiple-value-bind (checkpoint present-p)
            (ethereum-lisp.snap-sync::snap-sync-read-heal-checkpoint
             database progress-b)
          (is present-p)
          (is (not (null checkpoint))))
        (multiple-value-bind (state-root present-p)
            (kv-get-chain-record database :state-history (hash32-bytes pivot-b))
          (declare (ignore state-root))
          (is (not present-p)))
        (let ((batch (make-kv-write-batch)))
          (ethereum-lisp.snap-sync::snap-sync-complete-batch batch completed)
          (kv-apply-batch database batch))
        (multiple-value-bind (record present-p)
            (kv-get-chain-record
             database :metadata
             ethereum-lisp.snap-sync::+snap-sync-heal-checkpoint-identifier+)
          (declare (ignore record))
          (is (not present-p)))
        (multiple-value-bind (state-root present-p)
            (kv-get-chain-record database :state-history (hash32-bytes pivot-b))
          (is present-p)
          (is (bytes= state-root (hash32-bytes root-b))))))))

(deftest snap-state-healer-resumes-the-durable-frontier-after-source-loss
  (:layer :integration :module :p2p)
  (let* ((database (make-memory-key-value-database))
         (account-hash (snap-test-hash 193))
         (leaf-object
           (make-rlp-list
            (ethereum-lisp.trie.encoding:hex-prefix-encode
             #(0) :terminator t)
            (make-byte-vector 1 :initial-element 1)))
         (leaf-encoded (rlp-encode leaf-object))
         (leaf-reference (keccak-256 leaf-encoded))
         (work
           (ethereum-lisp.snap-sync::snap-sync-make-heal-work
            :storage account-hash (make-byte-vector 0) leaf-reference))
         (progress
           (ethereum-lisp.snap-sync::snap-sync-make-progress
            :pivot-hash (make-hash32 (snap-test-hash 194))
            :pivot-number 3002
            :state-root (make-hash32 leaf-reference)
            :partial-root +empty-trie-hash+
            :target-hash (make-hash32 (snap-test-hash 195))
            :chain-id 560048
            :genesis-hash (make-hash32 (snap-test-hash 196))
            :authority-id (make-hash32 (snap-test-hash 197))
            :completed-p nil
            :tasks
            (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
             :count 1 :completed-p t)))
         (trie-calls 0)
         (failing-source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) (declare (ignore request)))
            :storage-ranges (lambda (request) (declare (ignore request)))
            :bytecodes (lambda (request) (declare (ignore request)))
            :trie-nodes
            (lambda (request)
              (declare (ignore request))
              (incf trie-calls)
              (error
               'ethereum-lisp.snap-sync:snap-sync-state-unavailable
               :request-kind "trie-nodes"))))
         (healthy-source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) (declare (ignore request)))
            :storage-ranges (lambda (request) (declare (ignore request)))
            :bytecodes (lambda (request) (declare (ignore request)))
            :trie-nodes
            (lambda (request)
              (declare (ignore request))
              (ethereum-lisp.snap:make-snap-trie-nodes
               1 (list leaf-encoded))))))
    ;; The checkpoint is the trusted crash seam. A failed source must preserve
    ;; its exact work and counters so a new source resumes without restarting
    ;; the authorized root traversal.
    (let ((batch (make-kv-write-batch)))
      (ethereum-lisp.snap-sync::snap-sync-populate-heal-checkpoint-batch
       batch progress (list work) 7 3 4 2 99)
      (kv-apply-batch database batch))
    (let ((unavailable-p nil))
      (handler-case
          (ethereum-lisp.snap-sync::snap-sync-heal-state
           database (list failing-source) progress 350)
        (ethereum-lisp.snap-sync:snap-sync-state-unavailable ()
          (setf unavailable-p t)))
      (unless unavailable-p
        (error "Healer did not surface source loss after ~D trie requests"
               trie-calls)))
    (multiple-value-bind (checkpoint present-p)
        (ethereum-lisp.snap-sync::snap-sync-read-heal-checkpoint
         database progress)
      (is present-p)
      (is (= 7
             (ethereum-lisp.snap-sync::snap-sync-heal-checkpoint-processed-nodes
              checkpoint)))
      (is (= 1
             (length
              (ethereum-lisp.snap-sync::snap-sync-heal-checkpoint-stack
               checkpoint)))))
    (let ((completed
            (ethereum-lisp.snap-sync::snap-sync-heal-state
             database (list healthy-source) progress 350)))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p completed)))
    (multiple-value-bind (record present-p)
        (kv-get-chain-record
         database :metadata
         ethereum-lisp.snap-sync::+snap-sync-heal-checkpoint-identifier+)
      (declare (ignore record))
      (is (not present-p)))))

(deftest snap-state-healer-retries-a-request-timeout-on-the-same-source
  (:layer :integration :module :p2p)
  (let* ((database (make-memory-key-value-database))
         (account-hash (snap-test-hash 251))
         (leaf-object
           (make-rlp-list
            (ethereum-lisp.trie.encoding:hex-prefix-encode
             #(0) :terminator t)
            (make-byte-vector 1 :initial-element 1)))
         (leaf-encoded (rlp-encode leaf-object))
         (leaf-reference (keccak-256 leaf-encoded))
         (work
           (ethereum-lisp.snap-sync::snap-sync-make-heal-work
            :storage account-hash (make-byte-vector 0) leaf-reference))
         (progress
           (ethereum-lisp.snap-sync::snap-sync-make-progress
            :pivot-hash (make-hash32 (snap-test-hash 252))
            :pivot-number 3012
            :state-root (make-hash32 leaf-reference)
            :partial-root +empty-trie-hash+
            :target-hash (make-hash32 (snap-test-hash 253))
            :chain-id 560048
            :genesis-hash (make-hash32 (snap-test-hash 254))
            :authority-id (make-hash32 (snap-test-hash 255))
            :completed-p nil
            :tasks
            (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
             :count 1 :completed-p t)))
         (trie-calls 0)
         (source-errors 0)
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) (declare (ignore request)))
            :storage-ranges (lambda (request) (declare (ignore request)))
            :bytecodes (lambda (request) (declare (ignore request)))
            :trie-node-capacity (lambda () 1)
            :trie-nodes
            (lambda (request)
              (declare (ignore request))
              (if (= 1 (incf trie-calls))
                  (error
                   'ethereum-lisp.snap-sync:snap-sync-request-timeout)
                  (ethereum-lisp.snap:make-snap-trie-nodes
                   1 (list leaf-encoded)))))))
    ;; Seed the same durable storage frontier used by the source-loss restart
    ;; control above.  Starting from STATE-ROOT directly would intentionally
    ;; classify this leaf as an account node instead of a storage node.
    (let ((batch (make-kv-write-batch)))
      (ethereum-lisp.snap-sync::snap-sync-populate-heal-checkpoint-batch
       batch progress (list work) 0 0 0 0 0)
      (kv-apply-batch database batch))
    (let ((completed
            (ethereum-lisp.snap-sync::snap-sync-heal-state
             database (list source) progress 350
             :on-source-error
             (lambda (failed condition)
               (declare (ignore failed condition))
               (incf source-errors)))))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p completed))
      (is (= 2 trie-calls))
      ;; A request expiry is not a source/session verdict.  The exact work is
      ;; retried through the same source without reporting source failure.
      (is (zerop source-errors)))))

(deftest snap-state-healer-fetches-missing-account-storage-and-code-nodes
  (:layer :integration :module :p2p)
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-memory-key-value-database))
         (address
           (address-from-hex
            "0x0000000000000000000000000000000000000099"))
         (slot (make-hash32 (snap-test-hash 211)))
         (code #(96 2 96 0))
         (pivot (make-hash32 (snap-test-hash 212)))
         (target (make-hash32 (snap-test-hash 213)))
         (genesis (make-hash32 (snap-test-hash 214)))
         (authority (make-hash32 (snap-test-hash 215)))
         (trie-node-requests 0)
         (heal-progress-events '()))
    (state-db-set-account
     source-state address (make-state-account :nonce 7 :balance 99))
    (state-db-set-code source-state address code)
    (state-db-set-storage source-state address slot 12345)
    (let* ((root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base-source (snap-test-source backend))
           (source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (ethereum-lisp.snap-sync:snap-sync-source-account-range
               base-source)
              :storage-ranges
              (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
               base-source)
              :bytecodes
              (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base-source)
              :trie-nodes
              (lambda (request)
                (incf trie-node-requests)
                (funcall
                 (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
                  base-source)
                 request))))
           (progress
             (ethereum-lisp.snap-sync::snap-sync-make-progress
              :pivot-hash pivot :pivot-number 2000 :state-root root
              :partial-root +empty-trie-hash+ :target-hash target
              :chain-id 560048 :genesis-hash genesis
              :authority-id authority :completed-p nil
              :tasks
              (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
               :count 1 :completed-p t)))
           (completed
             (ethereum-lisp.snap-sync::snap-sync-heal-state
              target-database (list source) progress 350
              :on-heal-progress
              (lambda (snapshot)
                (push snapshot heal-progress-events)))))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p completed))
      (is (plusp trie-node-requests))
      (let* ((ordered-events (nreverse heal-progress-events))
             (first-fetched
               (find-if
                (lambda (snapshot)
                  (and
                   (not
                    (ethereum-lisp.snap-sync:snap-sync-heal-progress-completed-p
                     snapshot))
                   (zerop
                    (ethereum-lisp.snap-sync:snap-sync-heal-progress-processed-nodes
                     snapshot))
                   (plusp
                    (ethereum-lisp.snap-sync:snap-sync-heal-progress-fetched-nodes
                     snapshot))))
                ordered-events))
             (final (car (last ordered-events))))
        ;; The delivered root has moved from the only in-flight request back to
        ;; the local stack. It is one discovered work item, not one local plus
        ;; one stale remote item.
        (is first-fetched)
        (when first-fetched
          (is (= 1
                 (ethereum-lisp.snap-sync:snap-sync-heal-progress-frontier-works
                  first-fetched)))
          (is (zerop
               (ethereum-lisp.snap-sync:snap-sync-heal-progress-remote-works
                first-fetched))))
        (is final)
        (when final
          (is
           (ethereum-lisp.snap-sync:snap-sync-heal-progress-completed-p final))
          (is (zerop
               (ethereum-lisp.snap-sync:snap-sync-heal-progress-frontier-works
                final)))
          (is (zerop
               (ethereum-lisp.snap-sync:snap-sync-heal-progress-deferred-storage-works
                final)))
          (is (zerop
               (ethereum-lisp.snap-sync:snap-sync-heal-progress-remote-works
                final)))))
      (multiple-value-bind (persisted-root present-p)
          (kv-get-chain-record
           target-database :state-history (hash32-bytes pivot))
        (is present-p)
        (is (bytes= persisted-root (hash32-bytes root))))
      (multiple-value-bind (persisted-code code-present-p)
          (kv-get-chain-record target-database :code (keccak-256 code))
        (is code-present-p)
        (is (bytes= code persisted-code)))
      (let ((trie
              (make-persisted-mpt
               root
               (lambda (hash)
                 (trie-node-store-get target-database hash)))))
        (multiple-value-bind (record present-p)
            (mpt-get trie (keccak-256 (address-bytes address)))
          (is present-p)
          (when present-p
            (let ((account
                    (ethereum-lisp.state:decode-state-account-rlp record)))
              (is (= 99 (state-account-balance account)))
              (multiple-value-bind (storage-node storage-present-p)
                  (trie-node-store-get
                   target-database (state-account-storage-root account))
                (is storage-present-p)
                (is (plusp (length storage-node)))))))))))

(deftest snap-heal-code-hashes-deduplicate-in-linear-work
  (:layer :unit :module :p2p)
  (let* ((database (make-memory-key-value-database))
         (unique-count 2048)
         (unique
           (loop for index below unique-count
                 collect (snap-test-index-hash index)))
         (hashes (append unique (mapcar #'copy-seq unique)))
         (lookup-batches 0)
         (lookup-items 0)
         (comparison-count 0)
         (real-get-many
           (fdefinition 'ethereum-lisp.database:kv-get-chain-records))
         (real-bytes=
           (fdefinition 'ethereum-lisp.bytes:bytes=)))
    (unwind-protect
         (progn
           (setf
            (fdefinition 'ethereum-lisp.database:kv-get-chain-records)
            (lambda (candidate kind identifiers &optional default)
              (if (and (eq candidate database) (eq kind :code))
                  (progn
                    (incf lookup-batches)
                    (incf lookup-items (length identifiers))
                    (values
                     (make-array (length identifiers) :initial-element nil)
                     (make-array (length identifiers) :element-type 'bit
                                                      :initial-element 1)))
                  (funcall real-get-many
                           candidate kind identifiers default))))
           (setf
            (fdefinition 'ethereum-lisp.bytes:bytes=)
            (lambda (left right)
              (incf comparison-count)
              (funcall real-bytes= left right)))
           ;; Positive control: prove the comparison counter intercepts the
           ;; exact function used by the pre-fix REMOVE-DUPLICATES path.
           (is (bytes= (first unique) (copy-seq (first unique))))
           (is (= 1 comparison-count))
           (setf comparison-count 0)
           (is (null
                (ethereum-lisp.snap-sync::snap-sync-heal-missing-code-hashes
                 database hashes)))
           (is (= 1 lookup-batches))
           (is (= unique-count lookup-items))
           (is (= 0 comparison-count)))
      (setf (fdefinition 'ethereum-lisp.database:kv-get-chain-records)
            real-get-many
            (fdefinition 'ethereum-lisp.bytes:bytes=) real-bytes=))))

(deftest snap-heal-code-hashes-preserve-order-and-reject-malformed-input
  (:layer :unit :module :p2p)
  (let* ((database (make-memory-key-value-database))
         (first (snap-test-index-hash 1))
         (present (snap-test-index-hash 2))
         (last (snap-test-index-hash 3))
         (batch (make-kv-write-batch)))
    (kv-batch-put-chain-record batch :code present #(96 0))
    (kv-apply-batch database batch)
    (let ((missing
            (ethereum-lisp.snap-sync::snap-sync-heal-missing-code-hashes
             database
             (list first present (copy-seq first) last
                   (copy-seq present)))))
      (is (= 2 (length missing)))
      (is (bytes= first (first missing)))
      (is (bytes= last (second missing))))
    (signals error
      (ethereum-lisp.snap-sync::snap-sync-heal-missing-code-hashes
       database (list (make-byte-vector 31))))
    (signals error
      (ethereum-lisp.snap-sync::snap-sync-heal-missing-code-hashes
       database (list (make-array 32 :initial-element 0))))))

(deftest snap-state-healer-flushes-unique-code-hashes-in-bounded-batches
  (:layer :integration :module :p2p)
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-memory-key-value-database))
         (addresses
           (loop for index from 1 to 4
                 collect (snap-test-address-from-integer (+ 500 index))))
         (code-a #(96 1))
         (code-b #(96 2))
         (code-c #(96 3))
         (codes (list code-a code-b code-a code-c))
         (pivot (make-hash32 (snap-test-hash 231)))
         (target (make-hash32 (snap-test-hash 232)))
         (genesis (make-hash32 (snap-test-hash 233)))
         (authority (make-hash32 (snap-test-hash 234)))
         (request-sizes '())
         (target-code-point-lookups 0)
         (target-code-lookup-batches 0)
         (target-code-lookup-items 0))
    (loop for address in addresses
          for code in codes
          do (state-db-set-account
              source-state address (make-state-account :balance 1))
             (state-db-set-code source-state address code))
    (let* ((root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base-source (snap-test-source backend))
           (source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (ethereum-lisp.snap-sync:snap-sync-source-account-range
               base-source)
              :storage-ranges
              (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
               base-source)
              :bytecodes
              (lambda (request)
                (push
                 (length
                  (ethereum-lisp.snap:snap-get-bytecodes-hashes request))
                 request-sizes)
                (funcall
                 (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base-source)
                 request))
              :trie-nodes
              (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
               base-source)))
           (progress
             (ethereum-lisp.snap-sync::snap-sync-make-progress
              :pivot-hash pivot :pivot-number 2001 :state-root root
              :partial-root +empty-trie-hash+ :target-hash target
              :chain-id 560048 :genesis-hash genesis
              :authority-id authority :completed-p nil
              :tasks
              (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
               :count 1 :completed-p t)))
           (real-get
             (fdefinition 'ethereum-lisp.database:kv-get-chain-record))
           (real-get-many
             (fdefinition 'ethereum-lisp.database:kv-get-chain-records))
           (completed nil))
      (unwind-protect
           (progn
             (setf
              (fdefinition 'ethereum-lisp.database:kv-get-chain-record)
              (lambda (database kind identifier &optional default)
                (when (and (eq database target-database) (eq kind :code))
                  (incf target-code-point-lookups))
                (funcall real-get database kind identifier default)))
             (setf
              (fdefinition 'ethereum-lisp.database:kv-get-chain-records)
              (lambda (database kind identifiers &optional default)
                (when (and (eq database target-database) (eq kind :code))
                  (incf target-code-lookup-batches)
                  (incf target-code-lookup-items (length identifiers)))
                (funcall real-get-many database kind identifiers default)))
             (setf completed
                   (ethereum-lisp.snap-sync::snap-sync-heal-state
                    target-database (list source) progress 350
                    :code-batch-limit 2)))
        (setf (fdefinition 'ethereum-lisp.database:kv-get-chain-record)
              real-get
              (fdefinition 'ethereum-lisp.database:kv-get-chain-records)
              real-get-many))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p completed))
      (is (equal '(2 1) (nreverse request-sizes)))
      ;; One bounded MultiGet per two-code flush discovers missing hashes.
      ;; Verified content-addressed writes need no collision point reads. The
      ;; repeated account code crosses a flush, proving traversal-wide hashes
      ;; are released: its second bounded MultiGet finds the durable code and
      ;; therefore does not add another peer request.
      (is (zerop target-code-point-lookups))
      (is (= 2 target-code-lookup-batches))
      (is (= 4 target-code-lookup-items))
      (dolist (code (list code-a code-b code-c))
        (multiple-value-bind (persisted present-p)
            (kv-get-chain-record target-database :code (keccak-256 code))
          (is present-p)
          (is (bytes= code persisted)))))))

(deftest snap-state-import-does-not-advance-a-cursor-past-a-failed-batch
  (:layer :integration :module :p2p)
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-instance 'snap-failing-test-database))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000042")))
    ;; No code or storage keeps the setup compact. The account trie is allowed
    ;; to reach buffered WAL first; the injected synchronous cursor failure
    ;; must still leave authoritative progress behind it.
    (state-db-set-account
     source-state address (make-state-account :nonce 1 :balance 42))
    (let* ((root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (source (snap-test-source backend))
           (pivot-hash (make-hash32 (snap-test-hash 101)))
           (genesis-hash (make-hash32 (snap-test-hash 102)))
           (authority-id (make-hash32 (snap-test-hash 103))))
      (is
       (ethereum-lisp.snap-sync::snap-sync-enable-complete-node-scheme-p
        target-database))
      (setf (snap-failing-test-database-fail-next-apply-p target-database) t)
      (signals error
        (ethereum-lisp.snap-sync:snap-sync-import-state
         target-database source
         :pivot-hash pivot-hash :pivot-number 999 :state-root root
         :chain-id 560048 :genesis-hash genesis-hash
         :authority-id authority-id))
      (is (not (nth-value 1
                          (ethereum-lisp.snap-sync:snap-sync-read-progress
                           target-database))))
      ;; The verified content is idempotent and may already be visible in this
      ;; in-memory oracle, just as it may survive a production crash. Without a
      ;; cursor it is unpublished and the retry must remain safe.
      (multiple-value-bind (persisted-account present-p)
          (ethereum-lisp.trie:mpt-get
           (ethereum-lisp.trie:make-persisted-mpt
            root
            (lambda (hash)
              (ethereum-lisp.trie:trie-node-store-get
               target-database hash)))
           (ethereum-lisp.crypto:keccak-256 (address-bytes address)))
        (declare (ignore persisted-account))
        (is present-p))
      (is (not (nth-value
                1 (kv-get-chain-record target-database :state-history
                                       (hash32-bytes pivot-hash)))))
      (let ((completed
              (ethereum-lisp.snap-sync:snap-sync-import-state
               target-database source
               :pivot-hash pivot-hash :pivot-number 999 :state-root root
               :chain-id 560048 :genesis-hash genesis-hash
               :authority-id authority-id)))
        (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p completed))
        (multiple-value-bind (persisted-root present-p)
            (kv-get-chain-record target-database :state-history
                                 (hash32-bytes pivot-hash))
          (is present-p)
          (is (bytes= persisted-root (hash32-bytes root))))))))
