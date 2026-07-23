(in-package #:ethereum-lisp.node-store.persistence)

(defun state-storage-entry-from-rlp-object (value)
  (let ((fields (rlp-list-field value "State storage snapshot entry")))
    (unless (= (length fields) 2)
      (block-validation-fail
       "State storage snapshot entry must contain 2 fields"))
    (cons (rlp-hash32-field (first fields) "State storage snapshot slot")
          (rlp-uint-field (second fields)
                          "State storage snapshot value"))))

(defun state-account-snapshot-from-rlp-object (value)
  (let ((fields (rlp-list-field value "State account snapshot")))
    (unless (= (length fields) 5)
      (block-validation-fail
       "State account snapshot must contain 5 fields"))
    (values
     (rlp-address-field (first fields) "State account snapshot address")
     (rlp-uint-field (second fields) "State account snapshot balance")
     (rlp-uint-field (third fields) "State account snapshot nonce")
     (rlp-bytes-field (fourth fields) "State account snapshot code")
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
    (store block-identifier state-record)
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
                (state-account-snapshot-from-rlp-object account)
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
    (account balances nonces codes storage)
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
              (if (eq code :absent) :absent (ensure-byte-vector code))))
      (dolist (entry (rlp-list-field (eighth fields)
                                     "State diff storage"))
        (let ((entry (state-storage-entry-from-rlp-object entry)))
          (setf (gethash (format nil "~A:~A"
                                 address-hex
                                 (hash32-to-hex (car entry)))
                         storage)
                (cdr entry)))))))

(defun chain-store-import-state-diff-record-from-kv
    (store block-identifier record)
  (setf store (chain-store-require-memory-store store))
  (let ((block-hash (make-hash32 block-identifier)))
    (unless (chain-store-known-block store block-hash)
      (block-validation-fail
       "KV state diff record references an unknown block"))
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
               account balances nonces codes storage))
            (chain-store-put-state-diff
             store block-hash parent-hash
             :balances balances
             :nonces nonces
             :codes codes
             :storage storage)
            block-hash))
      (rlp-error (condition)
        (block-validation-fail
         "Invalid KV state diff record RLP: ~A" condition)))))

(defun chain-store-import-state-records-from-kv (store database)
  (dolist (entry (kv-chain-record-entries database :state))
    (chain-store-import-state-record-from-kv store (car entry) (cdr entry)))
  ;; Diff records may arrive in any order, so their roots are only
  ;; checkable once every diff is installed.
  (let ((diff-hashes '()))
    (dolist (entry (kv-chain-record-entries database :state-diff))
      (push (chain-store-import-state-diff-record-from-kv
             store (car entry) (cdr entry))
            diff-hashes))
    (dolist (block-hash (nreverse diff-hashes))
      (chain-store-validate-imported-state-root store block-hash))))
