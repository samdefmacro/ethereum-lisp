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
      (t
       (error "Unknown state root fixture operation: ~A" op))))
  state)

(defun run-state-root-fixture-case (case)
  (let ((state (make-state-db)))
    (dolist (operation (fixture-object-field case "operations"))
      (apply-state-root-fixture-operation state operation))
    state))

(deftest state-root-fixture-vectors
  (let* ((fixture (load-handwritten-fixture-file +state-root-fixture-path+))
         (cases (fixture-object-field fixture "cases")))
    (dolist (case cases)
      (let ((state (run-state-root-fixture-case case)))
        (is (string= (fixture-object-field case "expectedRoot")
                     (state-db-root-hex state)))))))
