(asdf:defsystem #:ethereum-lisp
  :description "Common Lisp Ethereum execution-layer implementation."
  :author "ethereum-lisp contributors"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "packages")
     (:file "bytes")
     (:file "hex")
     (:file "types")
     (:file "rlp")
     (:file "crypto")
     (:file "trie-encoding")
     (:file "trie")
     (:file "chain-config")
     (:file "genesis")
     (:file "core")
     (:file "block-validation")
     (:file "engine-rpc")
     (:file "state")
     (:file "evm")
     (:file "execution")))))

(asdf:defsystem #:ethereum-lisp/test
  :description "Tests for ethereum-lisp."
  :depends-on (#:ethereum-lisp)
  :serial t
  :components
  ((:module "tests"
    :serial t
    :components
    ((:file "test-framework")
     (:file "bytes-tests")
     (:file "hex-tests")
     (:file "types-tests")
     (:file "rlp-tests")
     (:file "crypto-tests")
     (:file "trie-encoding-tests")
     (:file "trie-tests")
     (:file "fixture-tests")
     (:file "fixture-runner-tests")
     (:file "transaction-fixture-tests")
     (:file "core-tests")
     (:file "state-tests")
     (:file "evm-tests")
     (:file "execution-tests"))))
  :perform (asdf:test-op (op c)
             (declare (ignore op c))
             (uiop:symbol-call '#:ethereum-lisp.test '#:run-all-tests)))
