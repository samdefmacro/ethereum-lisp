(in-package #:ethereum-lisp.test)

(defun apply-state-root-fixture-operation (state operation)
  (let* ((op (fixture-object-field operation "op"))
         (address (address-from-hex (fixture-object-field operation "address"))))
    (cond
      ((string= op "setAccount")
       (state-db-set-account
        state address
        (make-state-account
         :nonce (state-fixture-number operation "nonce")
         :balance (state-fixture-number operation "balance"))))
      ((string= op "addBalance")
       (state-db-add-balance
        state address (state-fixture-number operation "amount")))
      ((string= op "transferValue")
       (ethereum-lisp.state::state-db-transfer-value
        state
        address
        (address-from-hex (fixture-object-field operation "recipient"))
        (state-fixture-number operation "amount")))
      ((string= op "setStorage")
       (state-db-set-storage
        state address
        (hash32-from-hex (fixture-object-field operation "slot"))
        (state-fixture-number operation "value")))
      ((string= op "setCode")
       (state-db-set-code
        state address
        (hex-to-bytes (fixture-object-field operation "code"))))
      ((string= op "clearAccount")
       (state-db-clear-account state address))
      (t
       (error "Unknown state root fixture operation: ~A" op))))
  state)

(defun run-state-root-fixture-case (case)
  (let ((state (make-state-db)))
    (dolist (operation (fixture-object-field case "operations"))
      (apply-state-root-fixture-operation state operation))
    state))

(defstruct (state-root-fixture-account-state
            (:constructor make-state-root-fixture-account-state
                (&key (nonce 0) (balance 0)
                      (code (make-byte-vector 0))
                      (storage (make-hash-table :test 'equal))
                      (touched-slots (make-hash-table :test 'equal)))))
  (nonce 0 :type (integer 0 *))
  (balance 0 :type (integer 0 *))
  (code (make-byte-vector 0) :type byte-vector)
  storage
  touched-slots)

(defun state-root-fixture-empty-account-state-p (account-state)
  (and (zerop (state-root-fixture-account-state-nonce account-state))
       (zerop (state-root-fixture-account-state-balance account-state))
       (zerop (length (state-root-fixture-account-state-code account-state)))
       (zerop
        (hash-table-count
         (state-root-fixture-account-state-storage account-state)))))

(defun state-root-fixture-account-state
    (states address &key create-p)
  (or (gethash address states)
      (when create-p
        (setf (gethash address states)
              (make-state-root-fixture-account-state)))))

(defun state-root-fixture-prune-account-state
    (states address account-state)
  (when (state-root-fixture-empty-account-state-p account-state)
    (remhash address states))
  states)

(defun apply-state-root-fixture-operation-model (states operation)
  (let* ((op (fixture-object-field operation "op"))
         (address (fixture-object-field operation "address"))
         (account-state nil))
    (cond
      ((string= op "setAccount")
       (setf account-state
             (state-root-fixture-account-state states address :create-p t)
             (state-root-fixture-account-state-nonce account-state)
             (state-fixture-number operation "nonce")
             (state-root-fixture-account-state-balance account-state)
             (state-fixture-number operation "balance")))
      ((string= op "addBalance")
       (setf account-state
             (state-root-fixture-account-state
              states address
              :create-p (not (zerop (state-fixture-number operation "amount")))))
       (when account-state
         (setf (state-root-fixture-account-state-balance account-state)
               (+ (state-root-fixture-account-state-balance account-state)
                  (state-fixture-number operation "amount")))))
      ((string= op "transferValue")
       (let ((recipient (fixture-object-field operation "recipient"))
             (amount (state-fixture-number operation "amount")))
         (unless (or (zerop amount) (string= address recipient))
           (let ((sender-state
                   (state-root-fixture-account-state states address
                                                     :create-p t))
                 (recipient-state
                   (state-root-fixture-account-state states recipient
                                                     :create-p t)))
             (decf (state-root-fixture-account-state-balance sender-state)
                   amount)
             (incf (state-root-fixture-account-state-balance recipient-state)
                   amount)))))
      ((string= op "setStorage")
       (let* ((slot (fixture-object-field operation "slot"))
              (value (state-fixture-number operation "value"))
              (create-p (not (zerop value))))
         (setf account-state
               (state-root-fixture-account-state
                states address :create-p create-p))
         (when account-state
           (setf (gethash slot
                          (state-root-fixture-account-state-touched-slots
                           account-state))
                 t)
           (if (zerop value)
               (remhash slot
                        (state-root-fixture-account-state-storage
                         account-state))
               (setf (gethash slot
                              (state-root-fixture-account-state-storage
                               account-state))
                     value))
           (state-root-fixture-prune-account-state
            states address account-state))))
      ((string= op "setCode")
       (let* ((code (hex-to-bytes (fixture-object-field operation "code")))
              (create-p (plusp (length code))))
         (setf account-state
               (state-root-fixture-account-state
                states address :create-p create-p))
         (when account-state
           (setf (state-root-fixture-account-state-code account-state)
                 code)
          (state-root-fixture-prune-account-state
           states address account-state))))
      ((string= op "clearAccount")
       (remhash address states))
      (t
       (error "Unknown state root fixture operation: ~A" op))))
  states)

(defun state-root-fixture-final-operation-state (case)
  (let ((states (make-hash-table :test 'equal)))
    (dolist (operation (fixture-object-field case "operations"))
      (apply-state-root-fixture-operation-model states operation))
    states))

(defun assert-state-root-fixture-final-operation-state (state case)
  (let ((expected-states
          (state-root-fixture-final-operation-state case)))
    (dolist (operation (fixture-object-field case "operations"))
      (let* ((address-hex (fixture-object-field operation "address"))
             (address (address-from-hex address-hex))
             (expected (gethash address-hex expected-states))
             (account (state-db-get-account state address)))
        (if expected
            (progn
              (is account)
              (is (= (state-root-fixture-account-state-nonce expected)
                     (state-account-nonce account)))
              (is (= (state-root-fixture-account-state-balance expected)
                     (state-account-balance account)))
              (is (bytes=
                   (state-root-fixture-account-state-code expected)
                   (state-db-get-code state address)))
              (maphash
               (lambda (slot ignored)
                 (declare (ignore ignored))
                 (is (= (gethash
                         slot
                         (state-root-fixture-account-state-storage expected)
                         0)
                        (state-db-get-storage
                         state address (hash32-from-hex slot)))))
               (state-root-fixture-account-state-touched-slots expected)))
            (progn
              (is (null account))
              (is (string= "0x"
                           (bytes-to-hex
                            (state-db-get-code state address))))
              (when (string= "setStorage"
                              (fixture-object-field operation "op"))
                (is (zerop
                     (state-db-get-storage
                      state
                       address
                       (hash32-from-hex
                       (fixture-object-field operation "slot"))))))))))))

(defun assert-state-root-fixture-storage-roots (state case)
  (dolist (expected (fixture-object-field case "expectedStorageRoots"))
    (let ((address (address-from-hex (fixture-object-field expected "address"))))
      (is (string= (fixture-object-field expected "root")
                   (hash32-to-hex
                    (state-db-get-storage-root state address)))))))

(defun state-root-fixture-storage-trie (state address)
  (ethereum-lisp.state::state-object-storage-trie
   (ethereum-lisp.state::state-db-get-object state address)))

(defun assert-state-root-fixture-storage-tries (state case)
  (dolist (expected (fixture-object-field case "expectedStorageTrieShapes"))
    (let* ((address (address-from-hex (fixture-object-field expected "address")))
           (trie (state-root-fixture-storage-trie state address)))
      (is (string= (fixture-object-field expected "shape")
                   (trie-fixture-root-shape trie)))
      (when (fixture-field-present-p expected "rootPathNibbles")
        (is (equal (fixture-object-field expected "rootPathNibbles")
                   (trie-fixture-root-path-nibbles trie))))
      (when (fixture-field-present-p expected "childReference")
        (is (string= (fixture-object-field expected "childReference")
                     (trie-fixture-extension-child-reference-kind trie))))
      (when (fixture-field-present-p expected "rootChildren")
        (is (equal (fixture-object-field expected "rootChildren")
                   (trie-fixture-root-children trie))))
      (dolist (entry (fixture-object-field expected "rootChildShapes"))
        (is (string= (cdr entry)
                     (state-root-fixture-root-child-shape
                      trie
                      (parse-integer (car entry) :junk-allowed nil)))))
      (dolist (entry (fixture-object-field expected "rootChildReferences"))
        (is (string= (cdr entry)
                     (trie-fixture-root-child-reference-kind
                      trie
                      (parse-integer (car entry) :junk-allowed nil))))))))

(defun assert-state-root-fixture-accounts (state case)
  (dolist (expected (fixture-object-field case "expectedAccounts"))
    (let* ((address (address-from-hex (fixture-object-field expected "address")))
           (account (state-db-get-account state address)))
      (is account)
      (let ((nonce (fixture-object-field expected "nonce")))
        (when nonce
          (is (= nonce (state-account-nonce account)))))
      (let ((balance (fixture-object-field expected "balance")))
        (when balance
          (is (= balance (state-account-balance account)))))
      (let ((storage-root (fixture-object-field expected "storageRoot")))
        (when storage-root
          (is (string= storage-root
                       (hash32-to-hex
                        (state-account-storage-root account))))))
      (let ((code-hash (fixture-object-field expected "codeHash")))
        (when code-hash
          (is (string= code-hash
                       (hash32-to-hex
                        (state-account-code-hash account))))))
      (let ((rlp (fixture-object-field expected "rlp")))
        (when rlp
          (is (string= rlp
                       (bytes-to-hex (state-account-rlp account)))))))))

(defun state-root-fixture-optional-proof-key (object field)
  (when (fixture-field-present-p object field)
    (hash32-bytes (hash32-from-hex (fixture-object-field object field)))))

(defun state-root-fixture-account-range-storage (entry)
  (sort (mapcar (lambda (storage)
                  (list (hash32-to-hex (car storage))
                        (cdr storage)))
                (state-account-range-entry-storage-entries entry))
        #'string<
        :key #'first))

(defun state-root-fixture-expected-account-range-storage (expected)
  (mapcar (lambda (storage)
            (list (fixture-required-field storage "slot")
                  (fixture-required-field storage "value")))
          (fixture-required-field expected "storage")))

(defun assert-state-root-fixture-account-ranges (state case)
  (dolist (expected-range (fixture-object-field case "expectedAccountRanges"))
    (let* ((entries
             (state-db-account-range
              state
              :start (state-root-fixture-optional-proof-key
                      expected-range "startProofKey")
              :end (state-root-fixture-optional-proof-key
                    expected-range "endProofKey")))
           (expected-accounts
             (fixture-required-field expected-range "expectedAccounts")))
      (is (= (length expected-accounts) (length entries)))
      (loop for expected in expected-accounts
            for entry in entries
            do (progn
                 (is (string= (fixture-required-field expected "proofKey")
                              (bytes-to-hex
                               (state-account-range-entry-proof-key entry))))
                 (is (string= (fixture-required-field expected "address")
                              (address-to-hex
                               (state-account-range-entry-address entry))))
                 (is (string= (fixture-required-field expected "rlp")
                              (bytes-to-hex
                               (state-account-rlp
                                (state-account-range-entry-account entry)))))
                 (is (string= (fixture-required-field expected "code")
                              (bytes-to-hex
                               (state-account-range-entry-code entry))))
                 (is (equal
                      (state-root-fixture-expected-account-range-storage
                       expected)
                      (state-root-fixture-account-range-storage entry))))))))

(defun assert-state-root-fixture-storage-ranges (state case)
  (dolist (expected-range (fixture-object-field case "expectedStorageRanges"))
    (let* ((address
             (address-from-hex
              (fixture-required-field expected-range "address")))
           (entries
             (state-db-storage-range
              state
              address
              :start (state-root-fixture-optional-proof-key
                      expected-range "startProofKey")
              :end (state-root-fixture-optional-proof-key
                    expected-range "endProofKey")))
           (expected-storage
             (fixture-required-field expected-range "expectedStorage")))
      (is (= (length expected-storage) (length entries)))
      (loop for expected in expected-storage
            for entry in entries
            do (progn
                 (is (string= (fixture-required-field expected "proofKey")
                              (bytes-to-hex
                               (state-storage-range-entry-proof-key entry))))
                 (is (string= (fixture-required-field expected "slot")
                              (hash32-to-hex
                               (state-storage-range-entry-slot entry))))
                 (is (= (fixture-required-field expected "value")
                        (state-storage-range-entry-value entry))))))))

(defun state-root-fixture-state-trie (state)
  (ethereum-lisp.state::state-db-state-trie state))

(defun state-root-fixture-root-child-shape (trie index)
  (let ((root (mpt-root-node trie)))
    (when (typep root 'ethereum-lisp.trie::branch-node)
      (let ((child (aref (ethereum-lisp.trie::branch-node-children root)
                         index)))
        (cond
          ((null child) nil)
          ((typep child 'ethereum-lisp.trie::leaf-node) "leaf")
          ((typep child 'ethereum-lisp.trie::extension-node) "extension")
          ((typep child 'ethereum-lisp.trie::branch-node) "branch")
          (t "unknown"))))))

(defun assert-state-root-fixture-state-trie (state case)
  (let ((trie (state-root-fixture-state-trie state)))
    (when (fixture-field-present-p case "expectedStateTrieShape")
      (is (string= (fixture-object-field case "expectedStateTrieShape")
                   (trie-fixture-root-shape trie))))
    (when (fixture-field-present-p case "expectedStateTrieRootPathNibbles")
      (is (equal (fixture-object-field case "expectedStateTrieRootPathNibbles")
                 (trie-fixture-root-path-nibbles trie))))
    (when (fixture-field-present-p case "expectedStateTrieChildReference")
      (is (string= (fixture-object-field case "expectedStateTrieChildReference")
                   (trie-fixture-extension-child-reference-kind trie))))
    (when (fixture-field-present-p case "expectedStateTrieRootChildren")
      (is (equal (fixture-object-field case "expectedStateTrieRootChildren")
                 (trie-fixture-root-children trie))))
    (dolist (entry (fixture-object-field case "expectedStateTrieRootChildShapes"))
      (is (string= (cdr entry)
                   (state-root-fixture-root-child-shape
                    trie
                    (parse-integer (car entry) :junk-allowed nil)))))
    (dolist (entry (fixture-object-field case "expectedStateTrieRootChildReferences"))
      (is (string= (cdr entry)
                   (trie-fixture-root-child-reference-kind
                    trie
                    (parse-integer (car entry) :junk-allowed nil)))))))

