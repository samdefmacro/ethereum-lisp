(in-package #:ethereum-lisp.test)

(defparameter +engine-newpayload-v2-fixture-path+
  "tests/fixtures/execution-spec-tests/engine-newpayload-v2.json")

(defparameter +engine-newpayload-v2-fixture-format+
  "ethereum-lisp/engine-newpayload-fixture-v1")

(defparameter +engine-newpayload-v2-smoke-case-names+
  '("shanghai-one-transfer-with-withdrawal"
    "shanghai-two-legacy-transfers-with-withdrawal"
    "shanghai-log-contract-call-with-withdrawal"
    "shanghai-access-list-transfer-with-withdrawal"
    "shanghai-dynamic-fee-transfer-with-withdrawal"
    "shanghai-contract-creation-with-withdrawal"
    "shanghai-internal-create2-with-withdrawal"))

(defparameter +engine-newpayload-v2-smoke-coverage-families+
  '(:legacy-transfer :access-list-transfer :dynamic-fee-transfer
    :contract-creation :multi-legacy-transfer :log-producing-call
    :internal-create2-call))

(defparameter +engine-newpayload-v2-fixture-top-level-fields+
  '("format" "source" "executionSpecTests" "referenceClients" "cases"))

(defparameter +engine-fixture-reference-client-fields+
  '("geth" "nethermind" "reth"))

(defparameter +engine-newpayload-v2-fixture-case-fields+
  '("name" "network" "chainId" "config" "parent" "payload" "expect"))

(defparameter +engine-newpayload-v2-fixture-config-fields+
  '("berlinBlock" "londonBlock" "shanghaiTime"))

(defparameter +engine-newpayload-v2-fixture-parent-fields+
  '("number"
    "gasLimit"
    "gasUsed"
    "timestamp"
    "baseFeePerGas"
    "feeRecipient"
    "accounts"))

(defparameter +engine-newpayload-v2-fixture-account-fields+
  '("address" "nonce" "balance" "code" "storage"))

(defparameter +engine-newpayload-v2-fixture-payload-fields+
  '("number"
    "gasLimit"
    "timestamp"
    "baseFeePerGas"
    "transactions"
    "withdrawals"))

(defparameter +engine-newpayload-v2-fixture-withdrawal-fields+
  '("index" "validatorIndex" "address" "amount"))

(defparameter +engine-newpayload-v2-fixture-expect-fields+
  '("status"
    "sender"
    "senderNonce"
    "senderBalance"
    "recipient"
    "recipientBalance"
    "contractAddress"
    "contractBalance"
    "withdrawalRecipient"
    "withdrawalBalance"
    "codeAddress"
    "code"
    "storageAddress"
    "storageKey"
    "storageValue"
    "recipients"
    "recipientBalances"
    "receiptType"
    "receiptStatus"
    "receiptTypes"
    "receiptStatuses"
    "cumulativeGasUsed"
    "logAddress"
    "logTopic"
    "logData"
    "logCount"))

