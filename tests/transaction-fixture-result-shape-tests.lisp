(in-package #:ethereum-lisp.test)

(deftest transaction-fixture-result-shape-validation
  (let ((vector (list (cons "name" "shape-test")
                      (cons "type" "dynamic-fee"))))
    (signals error
      (validate-transaction-fixture-result-shape "shape-test"))
    (signals error
      (validate-transaction-fixture-result-shape
       (list (cons "name" "missing-fork")
             (cons "type" "dynamic-fee")
             (cons "result"
                   (list (cons "Frontier"
                               (list (cons "exception"
                                           "TransactionException.TYPE_2_TX_PRE_FORK"))))))))
    (signals error
      (validate-transaction-fixture-result-shape
       (list (cons "name" "unknown-fork")
             (cons "type" "dynamic-fee")
             (cons "result"
                   (append
                    (mapcar
                     (lambda (fork)
                       (cons fork
                             (if (string= fork "London")
                                 (list (cons "intrinsicGas" "0x5208"))
                                 (list (cons "exception"
                                             "TransactionException.TYPE_2_TX_PRE_FORK")))))
                     +transaction-fixture-forks+)
                    (list (cons "Osaka"
                                (list (cons "intrinsicGas" "0x5208")))))))))
    (signals error
      (validate-transaction-fixture-result-shape
       (list (cons "name" "duplicate-fork")
             (cons "type" "dynamic-fee")
             (cons "result"
                   (append
                    (mapcar
                     (lambda (fork)
                       (cons fork
                             (if (string= fork "London")
                                 (list (cons "intrinsicGas" "0x5208"))
                                 (list (cons "exception"
                                             "TransactionException.TYPE_2_TX_PRE_FORK")))))
                     +transaction-fixture-forks+)
                    (list (cons "London"
                                (list (cons "intrinsicGas" "0x5208")))))))))
    (signals error
      (validate-transaction-fixture-result-shape
       (list (cons "name" "malformed-fork-entry")
             (cons "type" "dynamic-fee")
             (cons "result"
                   (append
                    (mapcar
                     (lambda (fork)
                       (cons fork
                             (if (string= fork "London")
                                 (list (cons "intrinsicGas" "0x5208"))
                                 (list (cons "exception"
                                             "TransactionException.TYPE_2_TX_PRE_FORK")))))
                     +transaction-fixture-forks+)
                    (list "bad-entry"))))))
    (signals error
      (validate-transaction-fixture-result-shape
       (list (cons "name" "non-string-fork")
             (cons "type" "dynamic-fee")
             (cons "result"
                   (append
                    (mapcar
                     (lambda (fork)
                       (cons fork
                             (if (string= fork "London")
                                 (list (cons "intrinsicGas" "0x5208"))
                                 (list (cons "exception"
                                             "TransactionException.TYPE_2_TX_PRE_FORK")))))
                     +transaction-fixture-forks+)
                    (list (cons 42
                                (list (cons "intrinsicGas" "0x5208")))))))))
    (signals error
      (validate-transaction-fixture-result-shape
       (list (cons "name" "non-string-fork-first")
             (cons "type" "dynamic-fee")
             (cons "result"
                   (cons
                    (cons 42 (list (cons "intrinsicGas" "0x5208")))
                    (mapcar
                     (lambda (fork)
                       (cons fork
                             (if (string= fork "London")
                                 (list (cons "intrinsicGas" "0x5208"))
                                 (list (cons "exception"
                                             "TransactionException.TYPE_2_TX_PRE_FORK")))))
                     +transaction-fixture-forks+))))))
    (signals error
      (validate-transaction-fixture-result-shape
       (list (cons "name" "blank-fork")
             (cons "type" "dynamic-fee")
             (cons "result"
                   (append
                    (mapcar
                     (lambda (fork)
                       (cons fork
                             (if (string= fork "London")
                                 (list (cons "intrinsicGas" "0x5208"))
                                 (list (cons "exception"
                                             "TransactionException.TYPE_2_TX_PRE_FORK")))))
                     +transaction-fixture-forks+)
                    (list (cons ""
                                (list (cons "intrinsicGas" "0x5208")))))))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector :dynamic-fee "London" nil))
    (signals error
      (validate-transaction-fixture-result-entry
       vector :dynamic-fee "London" (list (cons "exception" ""))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "London"
       (list (cons "exception" "")
             (cons "intrinsicGas" "0x5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "London"
       (list (cons "intrinsicGas" "0x5208")
             (cons "gas" "0x5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "London"
       (list (cons "hash"
                   "0xa98a24882ea90916c6a86da650fbc6b14238e46f0af04a131ce92be897507476")
             (cons "intrinsicGas" "0x5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "London"
       (list (cons "sender"
                   "0xd02d72e067e77158444ef2020ff2d325f929b363")
             (cons "intrinsicGas" "0x5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "London"
       (list (cons "hash"
                   "a98a24882ea90916c6a86da650fbc6b14238e46f0af04a131ce92be897507476")
             (cons "sender"
                   "0xd02d72e067e77158444ef2020ff2d325f929b363")
             (cons "intrinsicGas" "0x5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "London"
       (list (cons "hash" 42)
             (cons "sender"
                   "0xd02d72e067e77158444ef2020ff2d325f929b363")
             (cons "intrinsicGas" "0x5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "London"
       (list (cons "hash"
                   "0xa98a24882ea90916c6a86da650fbc6b14238e46f0af04a131ce92be897507476")
             (cons "sender"
                   "d02d72e067e77158444ef2020ff2d325f929b363")
             (cons "intrinsicGas" "0x5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "London"
       (list (cons "hash"
                   "0xa98a24882ea90916c6a86da650fbc6b14238e46f0af04a131ce92be897507476")
             (cons "sender" 42)
             (cons "intrinsicGas" "0x5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "London"
       (list (cons "intrinsicGas" "0x5208")
             (cons "intrinsicGas" "0x5209"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector :dynamic-fee "London" (list (cons "intrinsicGas" 42))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector :dynamic-fee "London" (list (cons "intrinsicGas" "5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector :dynamic-fee "London" (list (cons "intrinsicGas" "0X5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector :dynamic-fee "London" (list (cons "intrinsicGas" "0x05208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "Berlin"
       (list (cons "exception" "TransactionException.UNKNOWN"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "Berlin"
       (list (cons "exception" 42))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "Berlin"
       (list (cons "exception" "TransactionException.TYPE_2_TX_PRE_FORK")
             (cons "intrinsicGas" "0x5208"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "Berlin"
       (list (cons "exception" "TransactionException.TYPE_2_TX_PRE_FORK")
             (cons "intrinsicGas" nil))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "London"
       (list (cons "exception" "TransactionException.TYPE_2_TX_PRE_FORK")
             (cons "intrinsicGas" nil))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector
       :dynamic-fee
       "Berlin"
       (list (cons "exception" "TransactionException.TYPE_1_TX_PRE_FORK"))))
    (signals error
      (validate-transaction-fixture-result-entry
       vector :dynamic-fee "London" (list (cons "intrinsicGas" "0x5208"))))
    (validate-transaction-fixture-result-entry
     vector
     :dynamic-fee
     "London"
     (list (cons "hash"
                 "0xa98a24882ea90916c6a86da650fbc6b14238e46f0af04a131ce92be897507476")
           (cons "sender"
                 "0xd02d72e067e77158444ef2020ff2d325f929b363")
           (cons "intrinsicGas" "0x5208")))
    (validate-transaction-fixture-result-entry
     vector :dynamic-fee "Berlin" (list (cons "exception"
                                 "TransactionException.TYPE_2_TX_PRE_FORK")))))

(defun transaction-fixture-metadata-shape-test-fixture
    (&key
       top-extra
       reference-extra
       (source "test fixture")
       (geth "test-geth")
       (nethermind "test-nethermind")
       (reth nil))
  (append
   (list
    (cons "format" +transaction-envelope-fixture-format+)
    (cons "source" source)
    (cons "executionSpecTests"
          (list (cons "release" +phase-a-eest-release+)
                (cons "tagTarget" +phase-a-eest-tag-target+)
                (cons "archive" +phase-a-eest-archive+)
                (cons "status" "test")))
    (cons "referenceClients"
          (append
           (list (cons "geth" geth)
                 (cons "nethermind" nethermind)
                 (cons "reth" reth))
           reference-extra))
    (cons "vectors" nil))
   top-extra))

(deftest transaction-fixture-metadata-shape-validation
  (validate-transaction-envelope-fixture-metadata
   (transaction-fixture-metadata-shape-test-fixture))
  (signals error
    (validate-transaction-envelope-fixture-metadata
     (transaction-fixture-metadata-shape-test-fixture
      :top-extra (list (cons "unexpectedTopField" t)))))
  (signals error
    (validate-transaction-envelope-fixture-metadata
     (transaction-fixture-metadata-shape-test-fixture
      :top-extra (list (cons 42 t)))))
  (signals error
    (validate-transaction-envelope-fixture-metadata
     (transaction-fixture-metadata-shape-test-fixture
      :top-extra (list (cons "source" "duplicate source")))))
  (is (handler-case
          (progn
            (validate-transaction-envelope-fixture-metadata
             (transaction-fixture-metadata-shape-test-fixture :source 42))
            nil)
        (error (condition)
          (search "source must be a string" (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-envelope-fixture-metadata
             (transaction-fixture-metadata-shape-test-fixture :geth 42))
            nil)
        (error (condition)
          (search "referenceClients.geth must be a string"
                  (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-envelope-fixture-metadata
             (transaction-fixture-metadata-shape-test-fixture :nethermind 42))
            nil)
        (error (condition)
          (search "referenceClients.nethermind must be a string"
                  (princ-to-string condition)))))
  (validate-transaction-envelope-fixture-metadata
   (transaction-fixture-metadata-shape-test-fixture :reth "test-reth"))
  (is (handler-case
          (progn
            (validate-transaction-envelope-fixture-metadata
             (transaction-fixture-metadata-shape-test-fixture :reth 42))
            nil)
        (error (condition)
          (search "referenceClients.reth must be null or a string"
                  (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-envelope-fixture-metadata
             (transaction-fixture-metadata-shape-test-fixture :reth ""))
            nil)
        (error (condition)
          (search "referenceClients.reth must be null or present"
                  (princ-to-string condition)))))
  (signals error
    (validate-transaction-envelope-fixture-metadata
     (transaction-fixture-metadata-shape-test-fixture
      :reference-extra (list (cons "besu" "test-besu"))))))

