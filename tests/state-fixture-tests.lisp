(in-package #:ethereum-lisp.test)

(defparameter +state-root-fixture-path+
  "tests/fixtures/execution-spec-tests/state-roots.json")

(defun state-fixture-number (object name &optional (default 0))
  (let ((value (fixture-object-field object name)))
    (if value value default)))

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
      ((string= op "setStorage")
       (state-db-set-storage
        state address
        (hash32-from-hex (fixture-object-field operation "slot"))
        (state-fixture-number operation "value")))
      ((string= op "setCode")
       (state-db-set-code
        state address
        (hex-to-bytes (fixture-object-field operation "code"))))
      (t
       (error "Unknown state root fixture operation: ~A" op))))
  state)

(defun run-state-root-fixture-case (case)
  (let ((state (make-state-db)))
    (dolist (operation (fixture-object-field case "operations"))
      (apply-state-root-fixture-operation state operation))
    state))

(defun assert-state-root-fixture-storage-roots (state case)
  (dolist (expected (fixture-object-field case "expectedStorageRoots"))
    (let ((address (address-from-hex (fixture-object-field expected "address"))))
      (is (string= (fixture-object-field expected "root")
                   (hash32-to-hex
                    (state-db-get-storage-root state address)))))))

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

(deftest state-root-fixture-vectors
  (let* ((fixture (load-handwritten-fixture-file +state-root-fixture-path+))
         (cases (fixture-object-field fixture "cases")))
    (dolist (case cases)
      (let ((state (run-state-root-fixture-case case)))
        (is (string= (fixture-object-field case "expectedRoot")
                     (state-db-root-hex state)))
        (assert-state-root-fixture-storage-roots state case)
        (assert-state-root-fixture-accounts state case)))))
