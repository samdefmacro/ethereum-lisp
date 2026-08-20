(in-package #:ethereum-lisp.test)

(defclass snap-failing-test-database (memory-key-value-database)
  ((fail-next-apply-p
    :initform nil
    :accessor snap-failing-test-database-fail-next-apply-p)))

(defmethod kv-apply-batch :around
    ((database snap-failing-test-database) (batch kv-write-batch))
  (if (snap-failing-test-database-fail-next-apply-p database)
      (progn
        (setf (snap-failing-test-database-fail-next-apply-p database) nil)
        (error "Simulated snap progress batch failure"))
      (call-next-method)))

(defclass snap-counting-test-database (memory-key-value-database)
  ((apply-count :initform 0 :accessor snap-counting-test-database-apply-count)
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
         (observed-limit-length nil))
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
                        request)))
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
      (is (zerop observed-limit-length)))))

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
      ;; One WAL batch installs every verified storage trie in the response;
      ;; the account data and terminal range each advance the durable cursor;
      ;; the final traversal alone writes the completion marker.
      (let ((apply-count
              (snap-counting-test-database-apply-count target-database)))
        (unless (= 4 apply-count)
          (error "Expected four storage/account/completion batches, got ~D (~S)"
                 apply-count
                 (list
                  (nreverse
                   (snap-counting-test-database-batch-sizes target-database))
                  (nreverse
                   (snap-counting-test-database-batch-prefixes
                    target-database)))))
        (is (= 4 apply-count)))
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

(deftest snap-state-import-defers-byte-capped-storage-to-resumable-healing
  (:layer :integration :module :p2p)
  ;; A large storage trie can outlive a public peer's retained pivot while the
  ;; account page is otherwise valid.  Do not restart that entire account page
  ;; from its durable cursor: keep the initial bounded storage response as an
  ;; availability hint and let content-addressed TrieNodes healing fill the
  ;; byte-capped trie after the account ranges are durable.
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-memory-key-value-database))
         (address
           (address-from-hex
            "0x0000000000000000000000000000000000000043"))
         (storage-calls 0)
         (trie-node-requests 0)
         (trie-node-responses 0)
         (trie-node-response-bytes 0)
         (heal-progress-events '())
         (saw-byte-capped-storage-p nil))
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
           (source
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
                (let ((response
                        (snap-test-call-backend
                         backend
                         ethereum-lisp.snap:+snap-message-get-storage-ranges+
                         request)))
                  (setf saw-byte-capped-storage-p
                        (not
                         (null
                          (ethereum-lisp.snap:snap-storage-ranges-proof
                           response))))
                  response))
              :bytecodes
              (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base-source)
              :trie-nodes
              (lambda (request)
                (incf trie-node-requests)
                (let* ((response
                         (funcall
                          (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
                           base-source)
                          request))
                       (nodes
                         (ethereum-lisp.snap:snap-trie-nodes-nodes response)))
                  (incf trie-node-responses (length nodes))
                  (incf trie-node-response-bytes
                        (reduce #'+ nodes :key #'length :initial-value 0))
                  response))))
           (progress
             (let ((ethereum-lisp.snap-sync::*snap-sync-heal-progress-node-interval*
                     1))
               (ethereum-lisp.snap-sync:snap-sync-import-state
                target-database source
                :pivot-hash (make-hash32 (snap-test-hash 124))
                :pivot-number 42 :state-root root
                :target-hash (make-hash32 (snap-test-hash 125))
                :chain-id 560048
                :genesis-hash (make-hash32 (snap-test-hash 126))
                :authority-id (make-hash32 (snap-test-hash 127))
                :byte-limit 350
                :on-heal-progress
                (lambda (heal-progress)
                  (push heal-progress heal-progress-events))))))
      (is saw-byte-capped-storage-p)
      (is (= 1 storage-calls))
      (is (plusp trie-node-requests))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p progress))
      (is (plusp (length heal-progress-events)))
      (is (some
           (lambda (event)
             (not
              (ethereum-lisp.snap-sync:snap-sync-heal-progress-completed-p
               event)))
           heal-progress-events))
      (is (some
           (lambda (event)
             (and
              (not
               (ethereum-lisp.snap-sync:snap-sync-heal-progress-completed-p
                event))
              (plusp
               (ethereum-lisp.snap-sync:snap-sync-heal-progress-reused-nodes
                event))))
           heal-progress-events))
      (let ((final (first heal-progress-events)))
        (is (ethereum-lisp.snap-sync:snap-sync-heal-progress-completed-p final))
        (is (= trie-node-requests
               (ethereum-lisp.snap-sync:snap-sync-heal-progress-request-count
                final)))
        (is (= trie-node-responses
               (ethereum-lisp.snap-sync:snap-sync-heal-progress-fetched-nodes
                final)))
        (is (= trie-node-response-bytes
               (ethereum-lisp.snap-sync:snap-sync-heal-progress-response-bytes
                final)))
        (is (plusp
             (ethereum-lisp.snap-sync:snap-sync-heal-progress-reused-nodes
              final)))
        (is (>=
             (ethereum-lisp.snap-sync:snap-sync-heal-progress-processed-nodes
              final)
             (+
              (ethereum-lisp.snap-sync:snap-sync-heal-progress-reused-nodes
               final)
              (ethereum-lisp.snap-sync:snap-sync-heal-progress-fetched-nodes
               final)))))
      (loop for (older newer) on (nreverse heal-progress-events)
            while newer
            do (is (<=
                    (ethereum-lisp.snap-sync:snap-sync-heal-progress-processed-nodes
                     older)
                    (ethereum-lisp.snap-sync:snap-sync-heal-progress-processed-nodes
                     newer)))
               (is (<=
                    (ethereum-lisp.snap-sync:snap-sync-heal-progress-request-count
                     older)
                    (ethereum-lisp.snap-sync:snap-sync-heal-progress-request-count
                     newer))))
      (multiple-value-bind (node present-p)
          (ethereum-lisp.trie:trie-node-store-get
           target-database storage-root)
        (is present-p)
        (is (plusp (length node)))))))

(deftest snap-sync-progress-v3-round-trips-and-migrates-v2
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
            :completed-p nil :tasks tasks))
         (record
           (ethereum-lisp.snap-sync::snap-sync-progress-record progress))
         (round-tripped
           (ethereum-lisp.snap-sync::snap-sync-progress-from-record record))
         (healing-progress
           (ethereum-lisp.snap-sync::snap-sync-make-progress
            :pivot-hash pivot :pivot-number 43 :state-root state-root
            :partial-root +empty-trie-hash+ :target-hash target
            :chain-id 560048 :genesis-hash genesis :authority-id authority
            :completed-p nil
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
         (migrated
           (ethereum-lisp.snap-sync::snap-sync-progress-with-task-count
            legacy 16)))
    (is (= 16
           (length
            (ethereum-lisp.snap-sync:snap-sync-progress-tasks
             round-tripped))))
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
    (is (= 16
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
             (copy-list (rlp-list-items (nth 11 fields))))
           (second-fields
             (copy-list (rlp-list-items (second task-objects)))))
      (setf (first second-fields) (make-byte-vector 32)
            (second task-objects) (apply #'make-rlp-list second-fields)
            (nth 11 fields) (apply #'make-rlp-list task-objects))
      (signals error
        (ethereum-lisp.snap-sync::snap-sync-progress-from-record
         (rlp-encode (apply #'make-rlp-list fields)))))))

#+sbcl
(deftest snap-state-import-multi-uses-three-sources-and-sixteen-ranges
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
                   (let ((first-p t))
                     (snap-test-source-with-account-callback
                      base-source
                      (lambda (request)
                        (let ((barrier-p first-p))
                          (when barrier-p
                            (setf first-p nil)
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
      (is (every (lambda (limit) (= limit (* 2 1024 1024))) byte-limits))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p progress))
      (is (= 16
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
           (source (snap-test-source backend))
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
               :authority-id authority-id :byte-limit 180)))
        (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p completed))
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
            :fetched-p t))
         (checkpoint
           (ethereum-lisp.snap-sync::make-snap-sync-heal-checkpoint
            :pivot-hash pivot :pivot-number 3000 :state-root root
            :target-hash target :chain-id 560048 :genesis-hash genesis
            :authority-id authority :stack (list work)
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
      (is (bytes= #(1 2 3)
                  (ethereum-lisp.snap-sync::snap-sync-heal-work-path
                   decoded-work))))
    ;; Version two adds durable marker sentinels, but an upgrade must still
    ;; resume the version-one checkpoint shape deployed before this cache.
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
              (make-rlp-list legacy-payload (keccak-256 legacy-payload))))
           (legacy
             (ethereum-lisp.snap-sync::snap-sync-heal-checkpoint-from-record
              legacy-record))
           (legacy-work
             (first
              (ethereum-lisp.snap-sync::snap-sync-heal-checkpoint-stack
               legacy))))
      (is (= 11
             (ethereum-lisp.snap-sync::snap-sync-heal-checkpoint-processed-nodes
              legacy)))
      (is (eq :storage
              (ethereum-lisp.snap-sync::snap-sync-heal-work-kind legacy-work)))
      (is (null
           (ethereum-lisp.snap-sync::snap-sync-heal-work-marker-state
            legacy-work))))
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
    (let ((batch (make-kv-write-batch))
          (subtree (snap-test-hash 189)))
      (ethereum-lisp.database:kv-batch-put-chain-record
       batch :metadata
       (ethereum-lisp.snap-sync::snap-sync-healed-subtree-identifier subtree)
       #(2))
      (kv-apply-batch database batch)
      (signals ethereum-lisp.validation:storage-error
        (ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p
         database subtree)))))

(deftest snap-heal-checkpoint-bounds-large-live-frontiers
  (:layer :unit :module :p2p)
  ;; A real Hoodi soft-limit left an older fetched batch below the subtree being
  ;; expanded, taking the exact restart frontier just above the former 4096
  ;; cap.  Keep that live, bounded shape encodable while forcing later missing
  ;; batches to shrink before they can accumulate another full 2048 entries.
  (is (= 2048
         (ethereum-lisp.snap-sync::snap-sync-heal-missing-limit 0)))
  (is (= 1096
         (ethereum-lisp.snap-sync::snap-sync-heal-missing-limit 3000)))
  (is (= 1
         (ethereum-lisp.snap-sync::snap-sync-heal-missing-limit 4096)))
  (is (= 1
         (ethereum-lisp.snap-sync::snap-sync-heal-missing-limit 8192)))
  (signals error
    (ethereum-lisp.snap-sync::snap-sync-heal-missing-limit -1))
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

(deftest snap-state-healer-uses-multiple-trie-node-sources
  (:layer :integration :module :p2p)
  (multiple-value-bind (source-state addresses)
      (snap-test-partitioned-state)
    (declare (ignore addresses))
    (let* ((root (state-db-root source-state))
           (target-database (make-memory-key-value-database))
           (calls (make-array 2 :initial-element 0))
           (round-first-sources '())
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
           (real-round
             (fdefinition
              'ethereum-lisp.snap-sync::snap-sync-heal-request-round))
           (completed nil))
      (unwind-protect
           (progn
             (setf
              (fdefinition
               'ethereum-lisp.snap-sync::snap-sync-heal-request-round)
              (lambda (round-sources missing root-bytes byte-limit)
                (push (first round-sources) round-first-sources)
                (funcall
                 real-round round-sources missing root-bytes byte-limit)))
             (setf
              completed
              (ethereum-lisp.snap-sync::snap-sync-heal-state
               target-database sources progress 350)))
        (setf
         (fdefinition
          'ethereum-lisp.snap-sync::snap-sync-heal-request-round)
         real-round))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p completed))
      (is (plusp (aref calls 0)))
      ;; Positive wiring witness: the old serial failover loop never called the
      ;; second healthy source while the first continued to answer.
      (is (plusp (aref calls 1)))
      (let ((round-first-sources (nreverse round-first-sources)))
        (is (> (length round-first-sources) 1))
        ;; A partially pruned peer may answer only part of its disjoint slice.
        ;; Rotate the next round so retained work is not pinned to that peer.
        (loop for (left right) on round-first-sources
              while right
              do (is (not (eq left right))))))))

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
                 stack-count)
                ethereum-lisp.snap-sync::+snap-sync-heal-checkpoint-node-interval+))
            do (is
                (<= (+ (- stack-count batch) (* 16 batch))
                    ethereum-lisp.snap-sync::+snap-sync-heal-checkpoint-max-works+)))
      (is
       (= 512
          (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
           1 0 2048 2048)))
      (is
       (= 292
          (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
           3800 0 296 2048)))
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
                (loop for index below 512 collect index)))
         (real-get-many
           (fdefinition 'ethereum-lisp.database:kv-get-chain-records))
         (mutex (sb-thread:make-mutex :name "snap-heal-read-test"))
         (worker-threads '())
         (call-count 0))
    (unwind-protect
         (let ((database (make-rocksdb-key-value-database path)))
           (unwind-protect
                (let ((batch (make-kv-write-batch)))
                  (dotimes (index (length references))
                    (unless (zerop (mod index 7))
                      (ethereum-lisp.database:kv-batch-put-chain-record
                       batch :trie-node (aref references index)
                       (vector (mod index 256)))))
                  (kv-apply-batch database batch)
                  (setf
                   (fdefinition 'ethereum-lisp.database:kv-get-chain-records)
                   (lambda (candidate kind identifiers &optional default)
                     (when (and (eq candidate database) (eq kind :trie-node))
                       (sb-thread:with-mutex (mutex)
                         (incf call-count)
                         (pushnew sb-thread:*current-thread* worker-threads
                                  :test #'eq)))
                     (funcall
                      real-get-many candidate kind identifiers default)))
                  (let ((ethereum-lisp.snap-sync::*snap-sync-heal-local-read-workers*
                          4))
                    (multiple-value-bind (values present)
                        (ethereum-lisp.snap-sync::snap-sync-heal-local-node-batch
                         database references)
                      (is (= 4 call-count))
                      (is (= 4 (length worker-threads)))
                      (is (= 512 (length values)))
                      (is (= 512 (length present)))
                      (dotimes (index 512)
                        (if (zerop (mod index 7))
                            (progn
                              (is (zerop (aref present index)))
                              (is (null (aref values index))))
                            (progn
                              (is (= 1 (aref present index)))
                              (is (bytes= (vector (mod index 256))
                                         (aref values index))))))))
                  (setf
                   (fdefinition 'ethereum-lisp.database:kv-get-chain-records)
                   (lambda (candidate kind identifiers &optional default)
                     (when (and (eq candidate database)
                                (eq kind :trie-node)
                                (bytes= (aref identifiers 0)
                                        (aref references 128)))
                       (error "Injected parallel snap read failure"))
                     (funcall
                      real-get-many candidate kind identifiers default)))
                  (let ((ethereum-lisp.snap-sync::*snap-sync-heal-local-read-workers*
                          4))
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

(deftest snap-state-healer-reuses-proved-subtrees-across-pivots
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
           (genesis (make-hash32 (snap-test-hash 221)))
           (authority (make-hash32 (snap-test-hash 222)))
           (first-processed nil)
           (second-processed nil)
           (cache-hits 0)
           (real-present
             (fdefinition
              'ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p)))
      (labels ((progress (pivot-seed target-seed number)
                 (ethereum-lisp.snap-sync::snap-sync-make-progress
                  :pivot-hash (make-hash32 (snap-test-hash pivot-seed))
                  :pivot-number number :state-root root
                  :partial-root +empty-trie-hash+
                  :target-hash (make-hash32 (snap-test-hash target-seed))
                  :chain-id 560048 :genesis-hash genesis
                  :authority-id authority :completed-p nil
                  :tasks
                  (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
                   :count 1 :completed-p t))))
        ;; A one-nibble boundary keeps this fixture small while exercising the
        ;; same content-addressed proof and completion-sentinel path as the
        ;; six-nibble public-network setting.
        (let ((ethereum-lisp.snap-sync::*snap-sync-healed-subtree-prefix-nibbles*
                1))
          (ethereum-lisp.snap-sync::snap-sync-heal-state
           target-database (list source) (progress 223 224 6000) 350
           :on-heal-progress
           (lambda (snapshot)
             (when
                 (ethereum-lisp.snap-sync::snap-sync-heal-progress-completed-p
                  snapshot)
               (setf first-processed
                     (ethereum-lisp.snap-sync::snap-sync-heal-progress-processed-nodes
                      snapshot)))))
          (unwind-protect
               (progn
                 (setf
                  (fdefinition
                   'ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p)
                  (lambda (database reference)
                    (let ((present-p
                            (funcall real-present database reference)))
                      (when present-p (incf cache-hits))
                      present-p)))
                 (ethereum-lisp.snap-sync::snap-sync-heal-state
                  target-database (list source) (progress 225 226 6010) 350
                  :on-heal-progress
                  (lambda (snapshot)
                    (when
                        (ethereum-lisp.snap-sync::snap-sync-heal-progress-completed-p
                         snapshot)
                      (setf second-processed
                            (ethereum-lisp.snap-sync::snap-sync-heal-progress-processed-nodes
                             snapshot))))))
            (setf
             (fdefinition
              'ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p)
             real-present)))
        (is (plusp cache-hits))
        (is (plusp first-processed))
        ;; Without the production cache-hit branch the second traversal
        ;; decodes the same number of nodes as the first and this witness fails.
        (is (< second-processed first-processed))
        (multiple-value-bind (persisted-root present-p)
            (kv-get-chain-record
             target-database :state-history (snap-test-hash 225))
          (is present-p)
          (is (bytes= persisted-root (hash32-bytes root))))))))

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
              1))
        (unwind-protect
             (progn
               (setf
                (fdefinition
                 'ethereum-lisp.snap-sync::snap-sync-populate-healed-subtree-batch)
                (lambda (batch reference)
                  (unless attempted-reference
                    (setf attempted-reference (copy-seq reference)
                          (snap-failing-test-database-fail-next-apply-p
                           target-database)
                          t))
                  (funcall real-populate batch reference)))
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
  (multiple-value-bind (source-state addresses)
      (snap-test-partitioned-state)
    (declare (ignore addresses))
    (let* ((source-database (make-memory-key-value-database))
           (target-database (make-memory-key-value-database))
           (root (state-db-root source-state))
           (root-bytes (hash32-bytes root))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base (snap-test-source backend))
           (trie-calls 0)
           (failing-source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (ethereum-lisp.snap-sync:snap-sync-source-account-range base)
              :storage-ranges
              (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges base)
              :bytecodes
              (ethereum-lisp.snap-sync:snap-sync-source-bytecodes base)
              :trie-nodes
              (lambda (request)
                (incf trie-calls)
                (if (= trie-calls 2)
                    (error
                     'ethereum-lisp.snap-sync:snap-sync-state-unavailable
                     :request-kind "trie-nodes")
                    (funcall
                     (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes base)
                     request)))))
           (progress
             (ethereum-lisp.snap-sync::snap-sync-make-progress
              :pivot-hash (make-hash32 (snap-test-hash 193))
              :pivot-number 3002 :state-root root
              :partial-root +empty-trie-hash+
              :target-hash (make-hash32 (snap-test-hash 194))
              :chain-id 560048
              :genesis-hash (make-hash32 (snap-test-hash 195))
              :authority-id (make-hash32 (snap-test-hash 196))
              :completed-p nil
              :tasks
              (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
               :count 1 :completed-p t))))
      (signals ethereum-lisp.snap-sync:snap-sync-state-unavailable
        (ethereum-lisp.snap-sync::snap-sync-heal-state
         target-database (list failing-source) progress 350))
      (multiple-value-bind (checkpoint present-p)
          (ethereum-lisp.snap-sync::snap-sync-read-heal-checkpoint
           target-database progress)
        (is present-p)
        (is (plusp
             (ethereum-lisp.snap-sync::snap-sync-heal-checkpoint-processed-nodes
              checkpoint))))
      (let ((root-reads 0)
            (real-get
              (fdefinition 'ethereum-lisp.trie:trie-node-store-get)))
        (unwind-protect
             (progn
               (setf
                (fdefinition 'ethereum-lisp.trie:trie-node-store-get)
                (lambda (database identifier)
                  (when (and (eq database target-database)
                             (bytes= identifier root-bytes))
                    (incf root-reads))
                  (funcall real-get database identifier)))
               (let ((completed
                       (ethereum-lisp.snap-sync::snap-sync-heal-state
                        target-database (list base) progress 350)))
                 (is
                  (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
                   completed)))
               (is (= 0 root-reads)))
          (setf (fdefinition 'ethereum-lisp.trie:trie-node-store-get)
                real-get)))
      (multiple-value-bind (record present-p)
          (kv-get-chain-record
           target-database :metadata
           ethereum-lisp.snap-sync::+snap-sync-heal-checkpoint-identifier+)
        (declare (ignore record))
        (is (not present-p))))))

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
         (trie-node-requests 0))
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
              target-database (list source) progress 350)))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p completed))
      (is (plusp trie-node-requests))
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
         (lookup-count 0)
         (comparison-count 0)
         (real-get
           (fdefinition 'ethereum-lisp.database:kv-get-chain-record))
         (real-bytes=
           (fdefinition 'ethereum-lisp.bytes:bytes=)))
    (unwind-protect
         (progn
           (setf
            (fdefinition 'ethereum-lisp.database:kv-get-chain-record)
            (lambda (candidate kind identifier &optional default)
              (if (and (eq candidate database) (eq kind :code))
                  (progn
                    (incf lookup-count)
                    (values (make-byte-vector 0) t))
                  (funcall real-get candidate kind identifier default))))
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
           (is (= unique-count lookup-count))
           (is (= 0 comparison-count)))
      (setf (fdefinition 'ethereum-lisp.database:kv-get-chain-record) real-get
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
         (target-code-lookups 0))
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
           (completed nil))
      (unwind-protect
           (progn
             (setf
              (fdefinition 'ethereum-lisp.database:kv-get-chain-record)
              (lambda (database kind identifier &optional default)
                (when (and (eq database target-database) (eq kind :code))
                  (incf target-code-lookups))
                (funcall real-get database kind identifier default)))
             (setf completed
                   (ethereum-lisp.snap-sync::snap-sync-heal-state
                    target-database (list source) progress 350
                    :code-batch-limit 2)))
        (setf (fdefinition 'ethereum-lisp.database:kv-get-chain-record)
              real-get))
      (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p completed))
      (is (equal '(2 1) (nreverse request-sizes)))
      ;; One missing check and one collision-safe batch check per distinct
      ;; code hash.  The repeated account code does not add a database lookup.
      (is (= 6 target-code-lookups))
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
    ;; No code or storage keeps the injected failure on the account
    ;; trie+cursor batch whose atomicity this test is proving.
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
