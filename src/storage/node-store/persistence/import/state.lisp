(in-package #:ethereum-lisp.node-store.persistence)

(defun state-storage-entry-from-rlp-object (value)
  (let ((fields (rlp-list-field value "State storage snapshot entry")))
    (unless (= (length fields) 2)
      (block-validation-fail
       "State storage snapshot entry must contain 2 fields"))
    (cons (rlp-hash32-field (first fields) "State storage snapshot slot")
          (rlp-uint-field (second fields)
                          "State storage snapshot value"))))

(defun state-account-snapshot-from-rlp-object (value code-resolver)
  (let ((fields (rlp-list-field value "State account snapshot")))
    (unless (= (length fields) 5)
      (block-validation-fail
       "State account snapshot must contain 5 fields"))
    (values
     (rlp-address-field (first fields) "State account snapshot address")
     (rlp-uint-field (second fields) "State account snapshot balance")
     (rlp-uint-field (third fields) "State account snapshot nonce")
     (node-store-resolve-code
      code-resolver
      (rlp-bytes-field (fourth fields) "State account snapshot code")
      "State account snapshot")
     (mapcar #'state-storage-entry-from-rlp-object
             (rlp-list-field (fifth fields)
                             "State account snapshot storage")))))

(defun chain-store-state-snapshot-storage-root (storage-entries)
  (let ((trie (make-mpt)))
    (dolist (entry storage-entries)
      (mpt-put trie
               (keccak-256 (hash32-bytes (car entry)))
               (rlp-encode (cdr entry))))
    (make-hash32 (mpt-root-hash trie))))

(defun chain-store-state-snapshot-account
    (balance nonce code storage-entries)
  (make-state-account
   :nonce nonce
   :balance balance
   :storage-root (chain-store-state-snapshot-storage-root storage-entries)
   :code-hash (if (plusp (length code))
                  (keccak-256-hash code)
                  +empty-code-hash+)))

(defun chain-store-state-snapshot-root (store block-hash)
  (let ((trie (make-mpt)))
    (chain-store-for-each-account
     store
     block-hash
     (lambda (address balance nonce code storage-entries)
       (mpt-put trie
                (keccak-256 (address-bytes address))
                (state-account-rlp
                 (chain-store-state-snapshot-account
                  balance nonce code storage-entries)))))
    (make-hash32 (mpt-root-hash trie))))

(defun chain-store-validate-imported-state-root (store block-hash)
  (let* ((block (chain-store-known-block store block-hash))
         (expected-root
           (and block (block-header-state-root (block-header block)))))
    (when expected-root
      (unless (chain-store-state-available-p store block-hash)
        (block-validation-fail
         "KV state record did not restore an available state snapshot"))
      (unless (hash32= expected-root
                       (chain-store-state-snapshot-root store block-hash))
        (block-validation-fail
         "KV state record root does not match block header")))))

(defun chain-store-import-state-record-from-kv
    (store block-identifier state-record &key code-resolver)
  "Install a full account snapshot.

CODE-RESOLVER names the record's layout: a resolver reads content-addressed
code (schema v3+), NIL reads the pre-v3 inline bodies. The caller must derive
it from the source database's schema marker, never from the record."
  (setf store (chain-store-require-memory-store store))
  (let ((block-hash (make-hash32 block-identifier)))
    (unless (chain-store-known-block store block-hash)
      (block-validation-fail "KV state record references an unknown block"))
    (handler-case
        (progn
          (setf (gethash (engine-payload-store-key block-hash)
                         (memory-chain-store-state-blocks store))
                t)
          (dolist (account (rlp-list-field (rlp-decode-one state-record)
                                           "State snapshot"))
            (multiple-value-bind (address balance nonce code storage-entries)
                (state-account-snapshot-from-rlp-object account code-resolver)
              (chain-store-put-account-balance store block-hash address balance)
              (chain-store-put-account-nonce store block-hash address nonce)
              (chain-store-put-account-code store block-hash address code)
              (dolist (entry storage-entries)
                (chain-store-put-account-storage
                 store block-hash address (car entry) (cdr entry)))))
          (chain-store-validate-imported-state-root store block-hash))
      (rlp-error (condition)
        (block-validation-fail
         "Invalid KV state record RLP: ~A" condition)))))

(defun state-diff-field-from-rlp (tag-field value-field parse-value label)
  "Decode one diff field: NIL when unchanged, :ABSENT for a tombstone, or
the parsed value."
  (ecase (rlp-uint-field tag-field (format nil "~A tag" label))
    (0 nil)
    (1 (funcall parse-value value-field label))
    (2 :absent)))

(defun chain-store-import-state-diff-account
    (account balances nonces codes storage code-resolver)
  (let ((fields (rlp-list-field account "State diff account")))
    (unless (= (length fields) 8)
      (block-validation-fail "State diff account must contain 8 fields"))
    (let* ((address (rlp-address-field (first fields)
                                       "State diff address"))
           (address-hex (address-to-hex address))
           (balance (state-diff-field-from-rlp
                     (second fields) (third fields)
                     #'rlp-uint-field "State diff balance"))
           (nonce (state-diff-field-from-rlp
                   (fourth fields) (fifth fields)
                   #'rlp-uint-field "State diff nonce"))
           (code (state-diff-field-from-rlp
                  (sixth fields) (seventh fields)
                  #'rlp-bytes-field "State diff code")))
      (when balance
        (setf (gethash address-hex balances) balance))
      (when nonce
        (setf (gethash address-hex nonces) nonce))
      (when code
        (setf (gethash address-hex codes)
              (if (eq code :absent)
                  :absent
                  (node-store-resolve-code
                   code-resolver code "State diff code"))))
      (dolist (entry (rlp-list-field (eighth fields)
                                     "State diff storage"))
        (let ((entry (state-storage-entry-from-rlp-object entry)))
          (setf (gethash (format nil "~A:~A"
                                 address-hex
                                 (hash32-to-hex (car entry)))
                         storage)
                (cdr entry)))))))

(defun node-store-state-diff-fields-from-record (record code-resolver)
  "Decode RECORD independently of a memory chain store.

The five values are its parent hash and four changed-value tables.  Sharing
this decoder keeps ordinary flat-store import and the v4 trie migration on the
same validation path."
  (handler-case
      (let ((fields (rlp-list-field (rlp-decode-one record)
                                    "State diff record")))
        (unless (= (length fields) 2)
          (block-validation-fail
           "State diff record must contain 2 fields"))
        (let ((parent-hash (rlp-hash32-field
                            (first fields) "State diff parent"))
              (balances (make-hash-table :test 'equal))
              (nonces (make-hash-table :test 'equal))
              (codes (make-hash-table :test 'equal))
              (storage (make-hash-table :test 'equal)))
          (dolist (account (rlp-list-field (second fields)
                                           "State diff accounts"))
            (chain-store-import-state-diff-account
             account balances nonces codes storage code-resolver))
          (values parent-hash balances nonces codes storage)))
    (rlp-error (condition)
      (block-validation-fail
       "Invalid KV state diff record RLP: ~A" condition))))

(defun chain-store-import-state-diff-record-from-kv
    (store block-identifier record &key code-resolver)
  (setf store (chain-store-require-memory-store store))
  (let ((block-hash (make-hash32 block-identifier)))
    (unless (chain-store-known-block store block-hash)
      (block-validation-fail
       "KV state diff record references an unknown block"))
    (multiple-value-bind (parent-hash balances nonces codes storage)
        (node-store-state-diff-fields-from-record record code-resolver)
      (chain-store-put-state-diff
       store block-hash parent-hash
       :balances balances
       :nonces nonces
       :codes codes
       :storage storage)
      block-hash)))

(defun chain-store-import-state-records-from-kv (store database)
  (let ((code-resolver (node-store-code-resolver-for-database database)))
    (dolist (entry (kv-chain-record-entries database :state))
      (chain-store-import-state-record-from-kv
       store (car entry) (cdr entry) :code-resolver code-resolver))
    ;; Diff records may arrive in any order, so their roots are only
    ;; checkable once every diff is installed.
    (let ((diff-hashes '()))
      (dolist (entry (kv-chain-record-entries database :state-diff))
        (push (chain-store-import-state-diff-record-from-kv
               store (car entry) (cdr entry) :code-resolver code-resolver)
              diff-hashes))
      (dolist (block-hash (nreverse diff-hashes))
        (chain-store-validate-imported-state-root store block-hash)))))

;;; Schema-v4 flat-state -> persisted-trie migration.

(defun node-store-migration-trie-node-loader (database)
  (lambda (hash)
    (kv-get-chain-record
     database :trie-node
     (if (hash32-p hash)
         (hash32-bytes hash)
         (ensure-byte-vector hash)))))

(defun node-store-migration-state-db-at-root (database root)
  "Open ROOT as a lazy state without constructing the production provider.

The public provider refuses an in-progress schema migration by design.  This
private view is used only by the migration that owns the progress marker, and
performs the same hash-addressed point reads."
  (let* ((trie-node-loader
           (node-store-migration-trie-node-loader database))
         (code-resolver (node-store-database-code-resolver database))
         (account-trie (make-persisted-mpt root trie-node-loader)))
    (ethereum-lisp.state:make-lazy-state-db
     (lambda (address)
       (multiple-value-bind (account-record present-p)
           (mpt-get account-trie (keccak-256 (address-bytes address)))
         (if present-p
             (let* ((account
                      (ethereum-lisp.state:decode-state-account-rlp
                       account-record))
                    (code-hash (state-account-code-hash account))
                    (code
                      (if (hash32= code-hash +empty-code-hash+)
                          (make-byte-vector 0)
                          (node-store-resolve-code
                           code-resolver (hash32-bytes code-hash)
                           "Migrated state account")))
                    (storage-trie
                      (make-persisted-mpt
                       (state-account-storage-root account)
                       trie-node-loader)))
               (values account code t nil storage-trie))
             (values nil nil nil))))
     nil
     nil
     :trie account-trie
     :cached-root root
     :direct-trie-p t)))

(defun node-store-migration-state-db-from-snapshot
    (record code-resolver)
  (let ((state (ethereum-lisp.state:make-state-db)))
    (handler-case
        (dolist (account
                  (rlp-list-field (rlp-decode-one record) "State snapshot"))
          (multiple-value-bind (address balance nonce code storage-entries)
              (state-account-snapshot-from-rlp-object account code-resolver)
            (ethereum-lisp.state:state-db-set-account
             state address
             (make-state-account :nonce nonce :balance balance))
            (ethereum-lisp.state:state-db-set-code state address code)
            (dolist (entry storage-entries)
              (ethereum-lisp.state:state-db-set-storage
               state address (car entry) (cdr entry)))))
      (rlp-error (condition)
        (block-validation-fail
         "Invalid state snapshot while migrating trie history: ~A"
         condition)))
    state))

(defun node-store-migration-diff-addresses
    (balances nonces codes storage)
  (let ((addresses (make-hash-table :test 'equal)))
    (flet ((remember (table)
             (maphash
              (lambda (key value)
                (declare (ignore value))
                (setf (gethash key addresses) t))
              table)))
      (remember balances)
      (remember nonces)
      (remember codes))
    (maphash
     (lambda (key value)
       (declare (ignore value))
       (let ((separator (position #\: key)))
         (unless separator
           (block-validation-fail
            "Migrated state storage change has no address prefix"))
         (setf (gethash (subseq key 0 separator) addresses) t)))
     storage)
    (sort
     (loop for address being the hash-keys of addresses collect address)
     #'string<)))

(defun node-store-migration-storage-by-address (storage)
  (let ((entries (make-hash-table :test 'equal)))
    (maphash
     (lambda (key value)
       (let ((separator (position #\: key)))
         (unless separator
           (block-validation-fail
            "Migrated state storage change has no address prefix"))
         (push (cons (subseq key (1+ separator)) value)
               (gethash (subseq key 0 separator) entries))))
     storage)
    entries))

(defun node-store-apply-migration-state-diff
    (state balances nonces codes storage)
  (let ((storage-by-address
          (node-store-migration-storage-by-address storage)))
    (dolist (address-hex
              (node-store-migration-diff-addresses
               balances nonces codes storage))
      (let ((address (address-from-hex address-hex)))
        (multiple-value-bind (balance balance-p)
            (gethash address-hex balances)
          (multiple-value-bind (nonce nonce-p)
              (gethash address-hex nonces)
            (multiple-value-bind (code code-p)
                (gethash address-hex codes)
              (let ((deleted-p
                      (or (eq balance :absent)
                          (eq nonce :absent)
                          (eq code :absent))))
                (when (and deleted-p
                           (not (and balance-p nonce-p code-p
                                     (eq balance :absent)
                                     (eq nonce :absent)
                                     (eq code :absent))))
                  (block-validation-fail
                   "Migrated state account tombstone is incomplete"))
                (if deleted-p
                    (ethereum-lisp.state:state-db-clear-account state address)
                    (progn
                      (when (or balance-p nonce-p)
                        (let ((account
                                (or (ethereum-lisp.state:state-db-get-account
                                     state address)
                                    (make-state-account))))
                          (ethereum-lisp.state:state-db-set-account
                           state address
                           (make-state-account
                            :nonce (if nonce-p
                                       nonce
                                       (state-account-nonce account))
                            :balance (if balance-p
                                         balance
                                         (state-account-balance account))
                            :storage-root
                            (state-account-storage-root account)
                            :code-hash
                            (state-account-code-hash account)))))
                      (when code-p
                        (ethereum-lisp.state:state-db-set-code
                         state address code))
                      (dolist (entry (gethash address-hex
                                              storage-by-address))
                        (ethereum-lisp.state:state-db-set-storage
                         state address
                         (hash32-from-hex (car entry))
                         (cdr entry)))))))))))
  state))

(defun node-store-migration-state-db-from-diff
    (database block record code-resolver)
  (multiple-value-bind (parent-hash balances nonces codes storage)
      (node-store-state-diff-fields-from-record record code-resolver)
    (unless (hash32= parent-hash
                     (block-header-parent-hash (block-header block)))
      (block-validation-fail
       "State diff parent does not match its block during trie migration"))
    (multiple-value-bind (parent-root present-p)
        (kv-get-chain-record
         database :state-history (hash32-bytes parent-hash))
      (unless (and present-p (= 32 (length parent-root)))
        (block-validation-fail
         "State diff parent has no migrated trie root"))
      (node-store-apply-migration-state-diff
       (node-store-migration-state-db-at-root
        database (make-hash32 parent-root))
       balances nonces codes storage))))

(defun node-store-populate-trie-history-migration-record
    (database batch full-key ordered-block-record)
  "Migrate one height-ordered flat post-state and return its dirty trie nodes.

The caller writes these nodes, the block->root history record, and the progress
cursor in one batch, then marks the returned nodes clean only after that batch
succeeds.  Existing history is validated and makes restart/idempotent paths
cheap."
  (let ((ordered-identifier
          (kv-chain-record-key-identifier :ordered-block full-key)))
    (multiple-value-bind (number block-identifier)
        (kv-chain-height-hash-identifier-values ordered-identifier)
      (multiple-value-bind
            (block legacy-requests legacy-requests-present-p
                   legacy-block-access-list
                   legacy-block-access-list-present-p)
          (chain-store-decode-persisted-block-record
           ordered-block-record "Ordered block during trie migration")
        (declare (ignore legacy-requests legacy-requests-present-p
                         legacy-block-access-list
                         legacy-block-access-list-present-p))
        (unless (and (= number
                        (block-header-number (block-header block)))
                     (bytes= block-identifier
                             (hash32-bytes (block-hash block))))
          (block-validation-fail
           "Ordered block key does not match its block during trie migration"))
        (let ((expected-root
                (block-header-state-root (block-header block))))
          (unless expected-root
            (block-validation-fail
             "Persisted block has no state root during trie migration"))
          (multiple-value-bind (existing-root existing-p)
              (kv-get-chain-record database :state-history block-identifier)
            (when existing-p
              (unless (and (= 32 (length existing-root))
                           (bytes= existing-root
                                   (hash32-bytes expected-root)))
                (block-validation-fail
                 "Existing state history conflicts during trie migration"))
              ;; A normal v4 batch creates the root and height mirror together.
              ;; Backfill the derived mirror here as well so an idempotent
              ;; resume can repair a datadir produced by an earlier v4 build
              ;; without re-walking or rewriting the trie.
              (let ((ordered-state-identifier
                      (kv-chain-height-hash-identifier
                       number block-identifier)))
                (multiple-value-bind (ordered-root ordered-p)
                    (kv-get-chain-record
                     database :ordered-state-history
                     ordered-state-identifier)
                  (cond
                    ((not ordered-p)
                     (kv-batch-put-chain-record
                      batch :ordered-state-history
                      ordered-state-identifier existing-root))
                    ((not (bytes= ordered-root existing-root))
                     (block-validation-fail
                      "Existing height-ordered state history conflicts during trie migration")))))
              (return-from
                  node-store-populate-trie-history-migration-record
                nil)))
          (multiple-value-bind (snapshot snapshot-p)
              (kv-get-chain-record database :state block-identifier)
            (multiple-value-bind (diff diff-p)
                (kv-get-chain-record database :state-diff block-identifier)
              (when (and snapshot-p diff-p)
                (block-validation-fail
                 "Block has both state snapshot and diff during trie migration"))
              (unless (or snapshot-p diff-p)
                (return-from
                    node-store-populate-trie-history-migration-record
                  nil))
              (let* ((code-resolver
                       (node-store-database-code-resolver database))
                     (state
                       (if snapshot-p
                           (node-store-migration-state-db-from-snapshot
                            snapshot code-resolver)
                           (node-store-migration-state-db-from-diff
                            database block diff code-resolver)))
                     (root (ethereum-lisp.state:state-db-root state)))
                (unless (hash32= root expected-root)
                  (block-validation-fail
                   "Migrated account trie root does not match block header"))
                (kv-batch-put-chain-record
                 batch :state-history block-identifier (hash32-bytes root))
                (kv-batch-put-chain-record
                 batch
                 :ordered-state-history
                 (kv-chain-height-hash-identifier number block-identifier)
                 (hash32-bytes root))
                (let ((nodes nil))
                  (dolist (trie
                            (ethereum-lisp.state:state-db-persistence-tries
                             state))
                    (setf nodes
                          (nconc nodes
                                 (mpt-populate-dirty-batch
                                  batch trie database))))
                  nodes)))))))))
