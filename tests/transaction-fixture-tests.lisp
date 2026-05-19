(in-package #:ethereum-lisp.test)

(defparameter +transaction-envelope-fixture-path+
  "tests/fixtures/execution-spec-tests/transaction-envelopes.json")

(defun transaction-fixture-type-keyword (type)
  (cond
    ((string= type "legacy") :legacy)
    ((string= type "access-list") :access-list)
    ((string= type "dynamic-fee") :dynamic-fee)
    ((string= type "blob") :blob)
    ((string= type "set-code") :set-code)
    (t (error "Unknown transaction fixture type: ~A" type))))

(defun load-transaction-envelope-vectors (path)
  (let* ((fixture (load-handwritten-fixture-file path))
         (vectors (fixture-object-field fixture "vectors")))
    (unless (listp vectors)
      (error "Transaction fixture vectors must be a JSON array"))
    vectors))

(defun transaction-fixture-fork-config (fork)
  (cond
    ((string= fork "Frontier")
     (make-chain-config))
    ((string= fork "Berlin")
     (make-chain-config :berlin-block 0))
    ((string= fork "London")
     (make-chain-config :berlin-block 0
                        :london-block 0))
    ((string= fork "Cancun")
     (make-chain-config :berlin-block 0
                        :london-block 0
                        :cancun-time 0))
    ((string= fork "Prague")
     (make-chain-config :berlin-block 0
                        :london-block 0
                        :cancun-time 0
                        :prague-time 0))
    (t (error "Unknown transaction fixture fork: ~A" fork))))

(defun transaction-fixture-fork-checks (vector)
  (let ((checks (fixture-object-field vector "forkChecks")))
    (unless (listp checks)
      (error "Transaction fixture forkChecks must be a JSON array"))
    checks))

(defun transaction-vector-type (transaction)
  (typecase transaction
    (legacy-transaction :legacy)
    (access-list-transaction :access-list)
    (dynamic-fee-transaction :dynamic-fee)
    (blob-transaction :blob)
    (set-code-transaction :set-code)
    (otherwise :unknown)))

(deftest transaction-envelope-fixture-vectors
  (dolist (vector (load-transaction-envelope-vectors
                   +transaction-envelope-fixture-path+))
    (let* ((raw (fixture-object-field vector "raw"))
           (chain-id (fixture-object-field vector "chainId"))
           (transaction (transaction-from-encoding (hex-to-bytes raw)))
           (sender (transaction-sender transaction :expected-chain-id chain-id)))
      (is (eq (transaction-fixture-type-keyword
               (fixture-object-field vector "type"))
              (transaction-vector-type transaction)))
      (is (string= raw (bytes-to-hex (transaction-encoding transaction))))
      (is (string= (fixture-object-field vector "hash")
                   (hash32-to-hex (transaction-hash transaction))))
      (is sender)
      (is (string= (fixture-object-field vector "sender")
                   (address-to-hex sender)))
      (is (null (transaction-sender transaction
                                    :expected-chain-id (1+ chain-id))))
      (dolist (check (transaction-fixture-fork-checks vector))
        (let ((config
                (transaction-fixture-fork-config
                 (fixture-object-field check "fork"))))
          (if (fixture-object-field check "valid")
              (is (validate-transaction-type-for-config
                   transaction config 0 0))
              (signals error
                (validate-transaction-type-for-config
                 transaction config 0 0))))))))
