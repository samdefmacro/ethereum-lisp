(in-package #:ethereum-lisp.test)

(defun run-state-proof-fixture-request (state request)
  (let ((address (address-from-hex (fixture-object-field request "address")))
        (storage-keys
          (mapcar #'state-proof-fixture-storage-key-from-request
                  (fixture-object-field request "storageKeys"))))
    (state-db-get-proof state address storage-keys)))

