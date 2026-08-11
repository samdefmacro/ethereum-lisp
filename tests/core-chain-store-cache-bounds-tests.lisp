(in-package #:ethereum-lisp.test)

(defun cache-bounds-test-block (marker number)
  (make-block
   :header
   (make-block-header
    :parent-hash (zero-hash32)
    :state-root +empty-trie-hash+
    :mix-hash (zero-hash32)
    :number number
    :gas-limit 50000
    :timestamp (+ 1000 marker)
    :extra-data (vector marker))))

(defun cache-bounds-test-payload-id (marker)
  (let ((payload-id (make-byte-vector 8)))
    (setf (aref payload-id 0) 2
          (aref payload-id 7) marker)
    payload-id))

(defun cache-bounds-test-sidecar (marker)
  (let ((blob (make-byte-vector +blob-byte-size+))
        (commitment (make-byte-vector +kzg-commitment-size+))
        (proof (make-byte-vector +kzg-proof-size+)))
    (setf (aref blob 0) marker
          (aref commitment 0) marker
          (aref proof 0) marker)
    (make-blob-sidecar
     :blobs (list blob)
     :commitments (list commitment)
     :proofs (list proof))))

(defun cache-bounds-test-install (store kind marker now number)
  (ecase kind
    (:remote-block
     (let ((block (cache-bounds-test-block marker number)))
       (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
        store block :now now)
       (ethereum-lisp.chain-store.model:engine-payload-store-key
        (block-hash block))))
    (:forkchoice-target
     (let ((hash (block-hash (cache-bounds-test-block marker number))))
       (ethereum-lisp.chain-store:engine-payload-store-put-forkchoice-sync-target
        store hash :now now :block-number number)
       (ethereum-lisp.chain-store.model:engine-payload-store-key hash)))
    (:invalid
     (let ((block (cache-bounds-test-block marker number)))
       (ethereum-lisp.chain-store:engine-payload-store-mark-invalid
        store block :now now)
       (ethereum-lisp.chain-store.model:engine-payload-store-key
        (block-hash block))))
    (:prepared-payload
     (let* ((payload-id (cache-bounds-test-payload-id marker))
            (payload
              (make-engine-prepared-payload
               :payload-id payload-id
               :version 2
               :block (cache-bounds-test-block marker number))))
       (ethereum-lisp.chain-store:engine-payload-store-put-prepared-payload
        store payload :now now)
       (ethereum-lisp.chain-store:engine-payload-id-key payload-id)))
    (:sidecar
     (let* ((sidecar (cache-bounds-test-sidecar marker))
            (hash (first (blob-sidecar-versioned-hashes sidecar))))
       (let ((*kzg-blob-proof-verifier*
               (lambda (blob commitment proof)
                 (declare (ignore blob commitment proof))
                 t)))
         (ethereum-lisp.chain-store:engine-payload-store-put-blob-sidecar
          store sidecar :now now :block-number number))
       (ethereum-lisp.chain-store.model:engine-payload-store-key hash)))))

(defun cache-bounds-test-cache-keys (store kind)
  (multiple-value-bind (values metadata)
      (ethereum-lisp.chain-store::engine-payload-store-cache-tables
       store kind)
    (declare (ignore metadata))
    (sort (loop for key being the hash-keys of values collect key) #'string<)))

(defun cache-bounds-test-enforce
    (store kind now finalized-number count-limit byte-limit max-age)
  (ethereum-lisp.chain-store::engine-payload-store-enforce-cache-bounds
   store kind now finalized-number
   :count-limit count-limit
   :byte-limit byte-limit
   :max-age max-age))

(deftest chain-store-cache-production-policies-match-public-testnet-bounds
  (is (= 96
         ethereum-lisp.chain-store:+engine-remote-block-cache-count-limit+))
  (is (= 96
         ethereum-lisp.chain-store:+engine-forkchoice-target-cache-count-limit+))
  (is (= 512 ethereum-lisp.chain-store:+engine-invalid-tipsets-cap+))
  (is (= 10
         ethereum-lisp.chain-store:+engine-prepared-payload-cache-count-limit+))
  (is (= 512
         ethereum-lisp.chain-store:+engine-blob-sidecar-cache-count-limit+))
  (is (plusp ethereum-lisp.chain-store:+engine-remote-block-cache-byte-limit+))
  (is (plusp
       ethereum-lisp.chain-store:+engine-prepared-payload-cache-byte-limit+))
  (is (plusp
       ethereum-lisp.chain-store:+engine-blob-sidecar-cache-byte-limit+)))

(deftest chain-store-cache-tombstones-stay-disabled-without-a-durable-sink
  (let* ((store (make-engine-payload-memory-store))
         (chain
           (ethereum-lisp.chain-store.state:chain-store-require-memory-store
            store)))
    (loop for number from 1 to 1000
          do (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
              store (cache-bounds-test-block (mod number 256) number)
              :now number))
    (loop for number from 1001 to 2000
          do (engine-payload-store-mark-invalid
              store (cache-bounds-test-block (mod number 256) number)
              :now number))
    (is (not
         (engine-payload-store-durable-cache-change-tracking-enabled-p
          store)))
    (is (zerop
         (hash-table-count
          (ethereum-lisp.chain-store.state:memory-chain-store-remote-block-durable-deletions
           chain))))
    (is (zerop
         (hash-table-count
          (ethereum-lisp.chain-store.state:memory-chain-store-invalid-tipset-durable-deletions
           chain))))))

(deftest chain-store-cache-count-eviction-is-deterministic-for-all-kinds
  (dolist (kind '(:remote-block :forkchoice-target :invalid
                  :prepared-payload :sidecar))
    (let ((forward (make-engine-payload-memory-store))
          (reverse (make-engine-payload-memory-store))
          (forward-keys nil))
      (dolist (marker '(1 2 3))
        (push (cache-bounds-test-install
               forward kind marker 100 (+ 10 marker))
              forward-keys))
      (dolist (marker '(3 2 1))
        (cache-bounds-test-install
         reverse kind marker 100 (+ 10 marker)))
      (cache-bounds-test-enforce
       forward kind 100 nil 2 most-positive-fixnum most-positive-fixnum)
      (cache-bounds-test-enforce
       reverse kind 100 nil 2 most-positive-fixnum most-positive-fixnum)
      (let ((expected
              (rest (sort (copy-list forward-keys) #'string<))))
        (is (equal expected (cache-bounds-test-cache-keys forward kind)))
        (is (equal expected (cache-bounds-test-cache-keys reverse kind)))))))

(deftest chain-store-cache-byte-eviction-is-independent-of-count
  (dolist (kind '(:remote-block :forkchoice-target :invalid
                  :prepared-payload :sidecar))
    (let* ((store (make-engine-payload-memory-store))
           (old-key (cache-bounds-test-install store kind 1 100 21))
           (new-key (cache-bounds-test-install store kind 2 101 22)))
      (multiple-value-bind (count bytes)
          (ethereum-lisp.chain-store:engine-payload-store-cache-statistics
           store kind :now 101)
        (is (= 2 count))
        (is (plusp bytes))
        (cache-bounds-test-enforce
         store kind 101 nil 10 (1- bytes) most-positive-fixnum))
      (is (not (member old-key
                       (cache-bounds-test-cache-keys store kind)
                       :test #'string=)))
      (is (member new-key
                  (cache-bounds-test-cache-keys store kind)
                  :test #'string=)))))

(deftest chain-store-cache-age-and-finality-boundaries-cover-all-kinds
  (dolist (kind '(:remote-block :forkchoice-target :invalid
                  :prepared-payload :sidecar))
    (let* ((age-store (make-engine-payload-memory-store))
           (expired-key
             (cache-bounds-test-install age-store kind 1 100 31))
           (live-key
             (cache-bounds-test-install age-store kind 2 101 32)))
      (cache-bounds-test-enforce
       age-store kind 110 nil 10 most-positive-fixnum 10)
      (is (not (member expired-key
                       (cache-bounds-test-cache-keys age-store kind)
                       :test #'string=)))
      (is (member live-key
                  (cache-bounds-test-cache-keys age-store kind)
                  :test #'string=)))
    (let* ((finality-store (make-engine-payload-memory-store))
           (finalized-key
             (cache-bounds-test-install finality-store kind 3 200 40))
           (unfinalized-key
             (cache-bounds-test-install finality-store kind 4 200 41)))
      (cache-bounds-test-enforce
       finality-store kind 200 40 10 most-positive-fixnum
       most-positive-fixnum)
      (is (not (member finalized-key
                       (cache-bounds-test-cache-keys finality-store kind)
                       :test #'string=)))
      (is (member unfinalized-key
                  (cache-bounds-test-cache-keys finality-store kind)
                  :test #'string=)))))

(deftest chain-store-cache-duplicate-put-does-not-refresh-age
  (let* ((store (make-engine-payload-memory-store))
         (block (cache-bounds-test-block 7 77))
         (key
           (ethereum-lisp.chain-store.model:engine-payload-store-key
            (block-hash block))))
    (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
     store block :now 100)
    (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
     store block :now 109)
    (cache-bounds-test-enforce
     store :remote-block 110 nil 10 most-positive-fixnum 10)
    (is (not (member key
                     (cache-bounds-test-cache-keys store :remote-block)
                     :test #'string=)))))

(deftest chain-store-remote-list-prunes-expired-gap-fill-targets
  (let ((store (make-engine-payload-memory-store)))
    (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
     store (cache-bounds-test-block 8 88) :now 100)
    (is (= 1
           (length
            (ethereum-lisp.chain-store:engine-payload-store-remote-block-list
             store :now 100))))
    (is (null
         (ethereum-lisp.chain-store:engine-payload-store-remote-block-list
          store
          :now (+ 100
                  ethereum-lisp.chain-store:+engine-remote-block-cache-max-age-seconds+))))))

(deftest chain-store-sidecar-cache-uses-exact-record-rlp-bytes
  (let* ((store (make-engine-payload-memory-store))
         (sidecar (cache-bounds-test-sidecar 9))
         (blob (first (blob-sidecar-blobs sidecar)))
         (commitment (first (blob-sidecar-commitments sidecar)))
         (proof (first (blob-sidecar-proofs sidecar)))
         (expected
           (length
            (rlp-encode
             (make-rlp-list
              blob commitment proof (make-rlp-list))))))
    (let ((*kzg-blob-proof-verifier*
            (lambda (checked-blob checked-commitment checked-proof)
              (declare (ignore checked-blob checked-commitment checked-proof))
              t)))
      (ethereum-lisp.chain-store:engine-payload-store-put-blob-sidecar
       store sidecar :now 300))
    (multiple-value-bind (count bytes)
        (ethereum-lisp.chain-store:engine-payload-store-cache-statistics
         store :sidecar :now 300)
      (is (= 1 count))
      (is (= expected bytes)))))

(deftest chain-store-cache-metadata-copies-and-rolls-back-with-values
  (let ((store (make-engine-payload-memory-store))
        (initial-keys (make-hash-table :test 'eq))
        (reached-injected-failure-p nil))
    (loop for kind in '(:remote-block :forkchoice-target :invalid
                        :prepared-payload :sidecar)
          for marker from 1
          do (setf (gethash kind initial-keys)
                   (cache-bounds-test-install
                    store kind marker 400 (+ 50 marker))))
    (let* ((copy (ethereum-lisp.chain-store:copy-memory-chain-store store))
           (source-chain
             (ethereum-lisp.chain-store.state:chain-store-require-memory-store
              store)))
      (dolist (kind '(:remote-block :forkchoice-target :invalid
                      :prepared-payload :sidecar))
        (multiple-value-bind (source-values source-metadata)
            (ethereum-lisp.chain-store::engine-payload-store-cache-tables
             source-chain kind)
          (declare (ignore source-values))
          (multiple-value-bind (copy-values copy-metadata)
              (ethereum-lisp.chain-store::engine-payload-store-cache-tables
               copy kind)
            (declare (ignore copy-values))
            (let ((key (gethash kind initial-keys)))
              (is (not (eq (gethash key source-metadata)
                           (gethash key copy-metadata))))
              (is (= 400
                     (ethereum-lisp.chain-store.model:chain-store-cache-entry-metadata-inserted-at
                      (gethash key copy-metadata)))))))))
    (signals error
      (chain-store-atomic-commit
       store
       (lambda ()
         (loop for kind in '(:remote-block :forkchoice-target :invalid
                             :prepared-payload :sidecar)
               for marker from 11
               do (cache-bounds-test-install
                   store kind marker 401 (+ 50 marker)))
         (let* ((chain
                  (ethereum-lisp.chain-store.state:chain-store-require-memory-store
                   store))
                (metadata
                  (ethereum-lisp.chain-store.state:memory-chain-store-remote-block-metadata
                   chain))
                (entry (gethash (gethash :remote-block initial-keys) metadata)))
           (setf (ethereum-lisp.chain-store.model:chain-store-cache-entry-metadata-inserted-at
                  entry)
                 999))
         (setf reached-injected-failure-p t)
         (error "Injected cache rollback failure"))))
    (is reached-injected-failure-p)
    (dolist (kind '(:remote-block :forkchoice-target :invalid
                    :prepared-payload :sidecar))
      (multiple-value-bind (count bytes)
          (ethereum-lisp.chain-store:engine-payload-store-cache-statistics
           store kind :now 400)
        (is (= 1 count))
        (is (plusp bytes))))
    (let* ((chain
             (ethereum-lisp.chain-store.state:chain-store-require-memory-store
              store))
           (metadata
             (ethereum-lisp.chain-store.state:memory-chain-store-remote-block-metadata
              chain))
           (entry (gethash (gethash :remote-block initial-keys) metadata)))
      (is (= 400
             (ethereum-lisp.chain-store.model:chain-store-cache-entry-metadata-inserted-at
              entry))))))
