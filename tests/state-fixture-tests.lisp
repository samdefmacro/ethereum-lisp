(in-package #:ethereum-lisp.test)

(defparameter +state-root-fixture-path+
  "tests/fixtures/execution-spec-tests/state-roots.json")

(defun state-fixture-number (object name &optional (default 0))
  (let ((value (fixture-object-field object name)))
    (if value value default)))

(defun validate-state-root-fixture-non-negative-integer
    (operation name &key required-p)
  (let ((present-p (fixture-field-present-p operation name))
        (value (fixture-object-field operation name)))
    (when (or present-p required-p)
      (unless (and (integerp value) (not (minusp value)))
        (error "State root fixture operation ~A must contain non-negative integer ~A"
               (fixture-object-field operation "op")
               name)))))

(defun validate-state-root-fixture-address (operation)
  (address-from-hex (fixture-required-field operation "address")))

(defun validate-state-root-fixture-operation-shape (operation)
  (unless (listp operation)
    (error "State root fixture operation must be a JSON object"))
  (let ((op (fixture-required-field operation "op")))
    (validate-state-root-fixture-address operation)
    (cond
      ((string= op "setAccount")
       (validate-state-root-fixture-non-negative-integer operation "nonce")
       (validate-state-root-fixture-non-negative-integer operation "balance"))
      ((string= op "setStorage")
       (hash32-from-hex (fixture-required-field operation "slot"))
       (validate-state-root-fixture-non-negative-integer
        operation "value" :required-p t))
      ((string= op "setCode")
       (hex-to-bytes (fixture-required-field operation "code")))
      (t
       (error "Unknown state root fixture operation: ~A" op)))))

(defun validate-state-root-fixture-case-shape (case)
  (unless (listp case)
    (error "State root fixture case must be a JSON object"))
  (when (blank-string-p (fixture-required-field case "name"))
    (error "State root fixture case name must be present"))
  (let ((operations (fixture-required-field case "operations")))
    (unless (listp operations)
      (error "State root fixture case operations must be a JSON array"))
    (dolist (operation operations)
      (validate-state-root-fixture-operation-shape operation)))
  (hash32-from-hex (fixture-required-field case "expectedRoot")))

(defun validate-state-root-fixture-cases (cases)
  (unless (listp cases)
    (error "State root fixture cases must be a JSON array"))
  (dolist (case cases)
    (validate-state-root-fixture-case-shape case)))

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
                            (state-db-get-code state address))))))))))

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

(deftest state-root-fixture-shape-validation
  (let ((valid-case
          (list
           (cons "name" "valid-shape")
           (cons "operations"
                 (list
                  (list (cons "op" "setAccount")
                        (cons "address"
                              "0x0000000000000000000000000000000000000001")
                        (cons "nonce" 1)
                        (cons "balance" 2))
                  (list (cons "op" "setStorage")
                        (cons "address"
                              "0x0000000000000000000000000000000000000001")
                        (cons "slot"
                              "0x0000000000000000000000000000000000000000000000000000000000000001")
                        (cons "value" 3))
                  (list (cons "op" "setCode")
                        (cons "address"
                              "0x0000000000000000000000000000000000000001")
                        (cons "code" "0x6001"))))
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
    (validate-state-root-fixture-case-shape valid-case))
  (signals error
    (validate-state-root-fixture-operation-shape
     (list (cons "op" "setAccount")
           (cons "address" "0x01")
           (cons "balance" 1))))
  (signals error
    (validate-state-root-fixture-operation-shape
     (list (cons "op" "setStorage")
           (cons "address" "0x0000000000000000000000000000000000000001")
           (cons "slot" "0x01")
           (cons "value" 1))))
  (signals error
    (validate-state-root-fixture-operation-shape
     (list (cons "op" "setStorage")
           (cons "address" "0x0000000000000000000000000000000000000001")
           (cons "slot"
                 "0x0000000000000000000000000000000000000000000000000000000000000001"))))
  (signals error
    (validate-state-root-fixture-operation-shape
     (list (cons "op" "setAccount")
           (cons "address" "0x0000000000000000000000000000000000000001")
           (cons "balance" -1))))
  (signals error
    (validate-state-root-fixture-operation-shape
     (list (cons "op" "setCode")
           (cons "address" "0x0000000000000000000000000000000000000001")
           (cons "code" "0x0")))))

(deftest state-root-fixture-vectors
  (let* ((fixture (load-handwritten-fixture-file +state-root-fixture-path+))
         (cases (fixture-object-field fixture "cases")))
    (validate-fixture-format fixture "ethereum-lisp/state-root-fixture-v1")
    (validate-fixture-pinned-eest-source fixture)
    (validate-state-root-fixture-cases cases)
    (dolist (case cases)
      (let ((state (run-state-root-fixture-case case)))
        (is (string= (fixture-object-field case "expectedRoot")
                     (state-db-root-hex state)))
        (assert-state-root-fixture-final-operation-state state case)
        (assert-state-root-fixture-storage-roots state case)
        (assert-state-root-fixture-accounts state case)))))
