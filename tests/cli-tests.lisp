(in-package #:ethereum-lisp.test)

(defconstant +devnet-cli-genesis-fixture+
  "tests/fixtures/execution-spec-tests/phase-a-shanghai-genesis.json")

(deftest devnet-node-loads-genesis-summary
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 0))
         (summary (ethereum-lisp.cli:devnet-node-summary node))
         (store (ethereum-lisp.cli:devnet-node-store node))
         (head (ethereum-lisp.cli:devnet-node-genesis-block node))
         (head-hash (block-hash head))
         (funded (address-from-hex "0x0000000000000000000000000000000000001001")))
    (is (= 1337 (getf summary :chain-id)))
    (is (= 0 (getf summary :head-number)))
    (is (string= "127.0.0.1:0" (getf summary :engine-endpoint)))
    (is (string= (hash32-to-hex head-hash) (getf summary :head-hash)))
    (is (getf summary :state-available-p))
    (is (= #xde0b6b3a7640000
           (chain-store-account-balance store head-hash funded)))))

(deftest devnet-cli-main-no-serve-prints-summary
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--genesis" +devnet-cli-genesis-fixture+
                  "--port" "0"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (read-from-string (get-output-stream-string output))))
      (is (= 1337 (getf summary :chain-id)))
      (is (= 0 (getf summary :head-number)))
      (is (string= "127.0.0.1:0" (getf summary :rpc-endpoint)))
      (is (getf summary :state-available-p)))))

(deftest devnet-cli-rejects-missing-genesis
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 1
           (ethereum-lisp.cli:main
            (list "devnet" "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string output)))
    (is (search "--genesis is required"
                (get-output-stream-string errors)))))
