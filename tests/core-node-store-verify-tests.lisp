(in-package #:ethereum-lisp.test)

;;;; The offline datadir audit: a clean database reports nothing, and each
;;;; corruption a node would fail to start on is reported as its own finding
;;;; rather than ending the walk.

(defun verify-test-finding-kinds (findings)
  (mapcar #'ethereum-lisp.node-store.persistence:node-store-database-finding-kind
          findings))

(defun verify-test-database ()
  "Export a small chain -- blocks, canonical index, checkpoints, and a state
snapshot with two accounts sharing one contract -- and return the database."
  (let* ((store (make-engine-payload-memory-store))
         (contract
           (address-from-hex "0x0000000000000000000000000000000000000021"))
         (twin
           (address-from-hex "0x0000000000000000000000000000000000000022"))
         (storage-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000023"))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :timestamp 0
                               :gas-limit 30000000)))
         (head
           nil)
         (state (make-state-db))
         (database (make-memory-key-value-database)))
    (dolist (address (list contract twin))
      (state-db-set-account
       state address (make-state-account :balance 5))
      (state-db-set-code state address *code-store-test-contract-a*))
    (state-db-set-storage state contract storage-slot 77)
    (setf head
          (make-block
           :header
           (make-block-header :number 1
                              :parent-hash (block-hash genesis)
                              :state-root (state-db-root state)
                              :timestamp 1
                              :gas-limit 30000000)))
    (chain-store-put-block store genesis :state-available-p nil)
    (chain-store-put-block store head :state-available-p t)
    (commit-state-db-to-chain-store store (block-hash head) state)
    (chain-store-update-forkchoice-checkpoints
     store
     (make-forkchoice-state
      :head-block-hash (block-hash head)
      :safe-block-hash (block-hash head)
      :finalized-block-hash (block-hash head)))
    (node-store-export-to-kv store database)
    (values database store head (state-db-get-storage-root state contract))))

(deftest node-store-verify-reports-nothing-for-a-consistent-database
  (let ((database (verify-test-database)))
    (is (null (ethereum-lisp.node-store.persistence:node-store-verify-chain-database
               database)))))

(deftest node-store-verify-reports-a-code-record-filed-under-the-wrong-hash
  (let ((database (verify-test-database)))
    (dolist (entry (kv-chain-record-entries database :code))
      (kv-put-chain-record database :code (car entry) #(#xfe #xfe)))
    (let ((findings
            (ethereum-lisp.node-store.persistence:node-store-verify-chain-database
             database)))
      ;; The bad body is reported once as a broken :CODE record and again for
      ;; every account whose reference no longer resolves to it.
      (is (member :code (verify-test-finding-kinds findings)))
      (is (member :state (verify-test-finding-kinds findings))))))

(deftest node-store-verify-reports-a-missing-contract-body
  (let ((database (verify-test-database)))
    (dolist (entry (kv-chain-record-entries database :code))
      (kv-delete-chain-record database :code (car entry)))
    (let ((findings
            (ethereum-lisp.node-store.persistence:node-store-verify-chain-database
             database)))
      ;; The flat oracle record and the direct account-trie leaf independently
      ;; expose the missing body.  The latter remains detectable after flat
      ;; state retention removes the former.
      (is (member :state (verify-test-finding-kinds findings)))
      (is (member :code (verify-test-finding-kinds findings)))
      (is (find-if
           (lambda (finding)
             (search "not stored"
                     (ethereum-lisp.node-store.persistence:node-store-database-finding-message
                      finding)))
           findings)))))

(deftest node-store-verify-finds-code-missing-from-trie-only-state
  (let ((database (verify-test-database)))
    ;; Remove the redundant flat snapshot first, then remove the shared code.
    ;; Verification must still reach the code hash through :STATE-HISTORY and
    ;; account-trie leaf payloads.
    (dolist (entry (kv-chain-record-entries database :state))
      (kv-delete-chain-record database :state (car entry)))
    (dolist (entry (kv-chain-record-entries database :code))
      (kv-delete-chain-record database :code (car entry)))
    (let ((findings
            (ethereum-lisp.node-store.persistence:node-store-verify-chain-database
             database)))
      (is (member :code (verify-test-finding-kinds findings)))
      (is (find-if
           (lambda (finding)
             (search "referenced by state root"
                     (ethereum-lisp.node-store.persistence:node-store-database-finding-message
                      finding)))
           findings)))))

(deftest node-store-verify-finds-storage-root-missing-from-account-leaf
  (multiple-value-bind (database store head storage-root)
      (verify-test-database)
    (declare (ignore store head))
    ;; A storage root is account-leaf payload, not an MPT child pointer.  Only
    ;; walking the retained account state can reveal this missing subtree.
    (kv-delete-chain-record
     database :trie-node (hash32-bytes storage-root))
    (let ((findings
            (ethereum-lisp.node-store.persistence:node-store-verify-chain-database
             database)))
      (is (find-if
           (lambda (finding)
             (and (eq :trie-node
                      (ethereum-lisp.node-store.persistence:node-store-database-finding-kind
                       finding))
                  (search "storage trie referenced by state root"
                          (ethereum-lisp.node-store.persistence:node-store-database-finding-message
                           finding))))
           findings)))))

(deftest node-store-verify-reports-references-to-a-deleted-block
  (multiple-value-bind (database store head) (verify-test-database)
    (declare (ignore store))
    (let ((identifier (hash32-bytes (block-hash head))))
      (kv-delete-chain-record database :block identifier)
      (let ((kinds
              (verify-test-finding-kinds
               (ethereum-lisp.node-store.persistence:node-store-verify-chain-database
                database))))
        ;; Every index that pointed at the block is named, not just the first.
        (dolist (kind '(:header :receipt :state :canonical-hash :checkpoint
                        :ordered-block :ordered-header :ordered-receipt))
          (is (member kind kinds)))))))

(deftest node-store-verify-reports-a-block-record-under-the-wrong-key
  (multiple-value-bind (database store head) (verify-test-database)
    (declare (ignore store))
    (let ((identifier (hash32-bytes (block-hash head))))
      (kv-put-chain-record database :block identifier #(#xc0))
      (let ((findings
              (ethereum-lisp.node-store.persistence:node-store-verify-chain-database
               database)))
        (is (member :block (verify-test-finding-kinds findings)))))))

(deftest node-store-verify-reports-an-unreadable-schema-marker-alone
  (let ((database (verify-test-database)))
    (kv-put-chain-schema-version database (1+ +kv-chain-schema-version+))
    ;; Nothing after the marker can be interpreted without knowing the layout,
    ;; so the audit stops rather than reporting defects it inferred wrongly.
    (let ((findings
            (ethereum-lisp.node-store.persistence:node-store-verify-chain-database
             database)))
      (is (equal '(:schema-version) (verify-test-finding-kinds findings))))))

(deftest node-store-verify-reports-corrupt-and-missing-trie-nodes
  (let ((database (verify-test-database)))
    (let ((entries (kv-chain-record-entries database :trie-node)))
      (is entries)
      (when entries
        (kv-put-chain-record database :trie-node (caar entries) #(#xc0)))
      (let ((findings
              (ethereum-lisp.node-store.persistence:node-store-verify-chain-database
               database)))
        (is (member :trie-node (verify-test-finding-kinds findings)))))))

(deftest node-store-verify-reports-state-history-root-mismatch
  (multiple-value-bind (database store head) (verify-test-database)
    (declare (ignore store))
    (kv-put-chain-record
     database :state-history (hash32-bytes (block-hash head))
     (hash32-bytes (zero-hash32)))
    (let ((findings
            (ethereum-lisp.node-store.persistence:node-store-verify-chain-database
             database)))
      (is (member :state-history (verify-test-finding-kinds findings))))))

(deftest node-store-verify-reports-missing-direct-state-history
  (multiple-value-bind (database store head) (verify-test-database)
    (declare (ignore store))
    (kv-delete-chain-record
     database :state-history (hash32-bytes (block-hash head)))
    (let ((findings
            (ethereum-lisp.node-store.persistence:node-store-verify-chain-database
             database)))
      (is (member :state-history (verify-test-finding-kinds findings)))
      (is (find-if
           (lambda (finding)
             (search "persisted trie root"
                     (ethereum-lisp.node-store.persistence:node-store-database-finding-message
                      finding)))
           findings)))))

(deftest node-store-verify-reads-a-legacy-inline-code-database
  (multiple-value-bind (database store) (verify-test-database)
    (code-store-test-downgrade-to-inline-code store database)
    ;; A pre-v3 datadir is consistent for its own layout, and the audit must
    ;; not read its inline bodies as content addresses.
    (is (null (ethereum-lisp.node-store.persistence:node-store-verify-chain-database
               database)))))
