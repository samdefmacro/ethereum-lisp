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
     (:file "database")
     (:file "telemetry")
     (:file "types")
     (:file "rlp")
     (:file "crypto")
     (:file "trie-encoding")
     (:file "trie")
     (:file "chain-config")
     (:file "genesis")
     (:file "core-constants")
     (:file "accounts")
     (:file "transactions")
     (:file "receipts")
     (:file "txpool-types")
     (:file "core")
     (:file "block-access-list")
     (:file "kzg")
     (:file "txpool")
     (:file "chain-store-persistence")
     (:file "block-validation")
     (:file "engine-payload-status")
     (:file "engine-rpc-protocol")
     (:file "engine-rpc")
     (:file "public-rpc")
     (:file "engine-rpc-http")
     (:file "state")
     (:file "evm")
     (:file "execution")
     (:file "cli")))))

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
     (:file "database-tests")
     (:file "telemetry-tests")
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
     (:file "execution-tests")
     (:file "cli-tests"))))
  :perform (asdf:test-op (op c)
             (declare (ignore op c))
             (uiop:symbol-call '#:ethereum-lisp.test '#:run-all-tests)))
