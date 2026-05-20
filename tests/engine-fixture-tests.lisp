(in-package #:ethereum-lisp.test)

(defparameter +engine-newpayload-v2-fixture-path+
  "tests/fixtures/execution-spec-tests/engine-newpayload-v2.json")

(defparameter +engine-newpayload-v2-fixture-format+
  "ethereum-lisp/engine-newpayload-fixture-v1")

(defparameter +engine-newpayload-v2-fixture-top-level-fields+
  '("format" "source" "executionSpecTests" "referenceClients" "cases"))

(defparameter +engine-fixture-reference-client-fields+
  '("geth" "nethermind" "reth"))

(defparameter +engine-newpayload-v2-fixture-case-fields+
  '("name" "network" "chainId" "config" "parent" "payload" "expect"))

(defparameter +engine-newpayload-v2-fixture-config-fields+
  '("londonBlock" "shanghaiTime"))

(defparameter +engine-newpayload-v2-fixture-parent-fields+
  '("number"
    "gasLimit"
    "gasUsed"
    "timestamp"
    "baseFeePerGas"
    "feeRecipient"
    "accounts"))

(defparameter +engine-newpayload-v2-fixture-account-fields+
  '("address" "nonce" "balance"))

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
    "withdrawalRecipient"
    "withdrawalBalance"
    "receiptType"
    "receiptStatus"))

(defun validate-engine-newpayload-v2-fixture-metadata (fixture)
  (validate-fixture-object-fields
   fixture
   +engine-newpayload-v2-fixture-top-level-fields+
   "Engine newPayloadV2 fixture")
  (validate-fixture-format fixture +engine-newpayload-v2-fixture-format+)
  (when (blank-string-p (fixture-required-field fixture "source"))
    (error "Engine newPayloadV2 fixture source must be present"))
  (validate-fixture-pinned-eest-source fixture)
  (let ((references (fixture-required-field fixture "referenceClients")))
    (validate-fixture-object-fields
     references
     +engine-fixture-reference-client-fields+
     "Engine newPayloadV2 fixture referenceClients")
    (dolist (client +engine-fixture-reference-client-fields+)
      (unless (fixture-field-present-p references client)
        (error "Engine newPayloadV2 fixture referenceClients is missing ~A"
               client)))
    (dolist (client '("geth" "nethermind"))
      (when (blank-string-p (fixture-object-field references client))
        (error "Engine newPayloadV2 fixture referenceClients.~A must be present"
               client)))))

(defun validate-engine-fixture-quantity-field (object field label)
  (handler-case
      (hex-to-quantity (fixture-required-field object field))
    (error (condition)
      (error "~A ~A must be a hex quantity: ~A"
             label field condition))))

(defun validate-engine-fixture-address-field (object field label)
  (handler-case
      (address-from-hex (fixture-required-field object field))
    (error (condition)
      (error "~A ~A must be an address: ~A"
             label field condition))))

(defun validate-engine-fixture-config-shape (config case-name)
  (validate-fixture-object-fields
   config
   +engine-newpayload-v2-fixture-config-fields+
   (format nil "Engine newPayloadV2 fixture case ~A config" case-name))
  (dolist (field +engine-newpayload-v2-fixture-config-fields+)
    (validate-engine-fixture-quantity-field
     config
     field
     (format nil "Engine newPayloadV2 fixture case ~A config" case-name))))

(defun validate-engine-fixture-parent-account-shape (account case-name)
  (let ((label
          (format nil
                  "Engine newPayloadV2 fixture case ~A parent account"
                  case-name)))
    (validate-fixture-object-fields
     account
     +engine-newpayload-v2-fixture-account-fields+
     label)
    (validate-engine-fixture-address-field account "address" label)
    (validate-engine-fixture-quantity-field account "nonce" label)
    (validate-engine-fixture-quantity-field account "balance" label)))

(defun validate-engine-fixture-parent-account-uniqueness
    (accounts case-name)
  (let ((seen-addresses (make-hash-table :test 'equal)))
    (dolist (account accounts)
      (let* ((address (address-from-hex
                       (fixture-required-field account "address")))
             (key (bytes-to-hex (address-bytes address) :prefix nil)))
        (when (gethash key seen-addresses)
          (error "Engine newPayloadV2 fixture case ~A has duplicate parent account ~A"
                 case-name
                 (address-to-hex address)))
        (setf (gethash key seen-addresses) t)))))

(defun validate-engine-fixture-parent-shape (parent case-name)
  (let ((label (format nil
                       "Engine newPayloadV2 fixture case ~A parent"
                       case-name)))
    (validate-fixture-object-fields
     parent
     +engine-newpayload-v2-fixture-parent-fields+
     label)
    (dolist (field '("number" "gasLimit" "gasUsed" "timestamp" "baseFeePerGas"))
      (validate-engine-fixture-quantity-field parent field label))
    (validate-engine-fixture-address-field parent "feeRecipient" label)
    (let ((accounts (fixture-required-field parent "accounts")))
      (unless (listp accounts)
        (error "~A accounts must be a JSON array" label))
      (dolist (account accounts)
        (validate-engine-fixture-parent-account-shape account case-name))
      (validate-engine-fixture-parent-account-uniqueness
       accounts
       case-name))))

(defun validate-engine-fixture-withdrawal-shape (withdrawal case-name)
  (let ((label
          (format nil
                  "Engine newPayloadV2 fixture case ~A payload withdrawal"
                  case-name)))
    (validate-fixture-object-fields
     withdrawal
     +engine-newpayload-v2-fixture-withdrawal-fields+
     label)
    (dolist (field '("index" "validatorIndex" "amount"))
      (validate-engine-fixture-quantity-field withdrawal field label))
    (validate-engine-fixture-address-field withdrawal "address" label)))

(defun validate-engine-fixture-withdrawal-index-uniqueness
    (withdrawals case-name)
  (let ((seen-indexes (make-hash-table :test 'eql)))
    (dolist (withdrawal withdrawals)
      (let ((index (hex-to-quantity
                    (fixture-required-field withdrawal "index"))))
        (when (gethash index seen-indexes)
          (error "Engine newPayloadV2 fixture case ~A has duplicate withdrawal index ~A"
                 case-name
                 (quantity-to-hex index)))
        (setf (gethash index seen-indexes) t)))))

(defun validate-engine-fixture-payload-shape (payload case-name)
  (let ((label (format nil
                       "Engine newPayloadV2 fixture case ~A payload"
                       case-name)))
    (validate-fixture-object-fields
     payload
     +engine-newpayload-v2-fixture-payload-fields+
     label)
    (dolist (field '("number" "gasLimit" "timestamp" "baseFeePerGas"))
      (validate-engine-fixture-quantity-field payload field label))
    (let ((transactions (fixture-required-field payload "transactions")))
      (unless (and (listp transactions) transactions)
        (error "~A transactions must be a non-empty JSON array" label))
      (dolist (raw transactions)
        (unless (stringp raw)
          (error "~A transactions entries must be hex strings" label))
        (transaction-from-encoding (hex-to-bytes raw))))
    (let ((withdrawals (fixture-required-field payload "withdrawals")))
      (unless (listp withdrawals)
        (error "~A withdrawals must be a JSON array" label))
      (dolist (withdrawal withdrawals)
        (validate-engine-fixture-withdrawal-shape withdrawal case-name))
      (validate-engine-fixture-withdrawal-index-uniqueness
       withdrawals
       case-name))))

(defun validate-engine-fixture-parent-payload-coherence
    (parent payload case-name)
  (let* ((parent-number (fixture-quantity-field parent "number"))
         (parent-gas-limit (fixture-quantity-field parent "gasLimit"))
         (parent-gas-used (fixture-quantity-field parent "gasUsed"))
         (parent-timestamp (fixture-quantity-field parent "timestamp"))
         (parent-base-fee (fixture-quantity-field parent "baseFeePerGas"))
         (payload-number (fixture-quantity-field payload "number"))
         (payload-gas-limit (fixture-quantity-field payload "gasLimit"))
         (payload-timestamp (fixture-quantity-field payload "timestamp"))
         (payload-base-fee (fixture-quantity-field payload "baseFeePerGas"))
         (label (format nil
                        "Engine newPayloadV2 fixture case ~A"
                        case-name)))
    (when (> parent-gas-used parent-gas-limit)
      (error "~A parent gasUsed exceeds parent gasLimit" label))
    (unless (= payload-number (1+ parent-number))
      (error "~A payload number must be parent number plus one" label))
    (unless (> payload-timestamp parent-timestamp)
      (error "~A payload timestamp must be greater than parent timestamp"
             label))
    (handler-case
        (validate-gas-limit-delta parent-gas-limit payload-gas-limit)
      (block-validation-error (condition)
        (error "~A payload gasLimit is not parent-relative: ~A"
               label
               (block-validation-error-message condition))))
    (let* ((parent-header
             (make-block-header
              :gas-limit parent-gas-limit
              :gas-used parent-gas-used
              :base-fee-per-gas parent-base-fee))
           (expected-base-fee (expected-base-fee-per-gas parent-header)))
      (unless (= payload-base-fee expected-base-fee)
        (error "~A payload baseFeePerGas must be ~A, got ~A"
               label
               (quantity-to-hex expected-base-fee)
               (quantity-to-hex payload-base-fee))))))

(defun validate-engine-fixture-expect-shape (expect case-name)
  (let ((label (format nil
                       "Engine newPayloadV2 fixture case ~A expect"
                       case-name)))
    (validate-fixture-object-fields
     expect
     +engine-newpayload-v2-fixture-expect-fields+
     label)
    (unless (string= +payload-status-valid+
                     (fixture-required-field expect "status"))
      (error "~A status must be VALID" label))
    (dolist (field '("sender" "recipient" "withdrawalRecipient"))
      (validate-engine-fixture-address-field expect field label))
    (dolist (field '("senderNonce"
                     "senderBalance"
                     "recipientBalance"
                     "withdrawalBalance"
                     "receiptType"
                     "receiptStatus"))
      (validate-engine-fixture-quantity-field expect field label))))

(defun fixture-account-balance (state address)
  (let ((account (state-db-get-account state address)))
    (if account
        (state-account-balance account)
        0)))

(defun fixture-account-nonce (state address)
  (let ((account (state-db-get-account state address)))
    (if account
        (state-account-nonce account)
        0)))

(defun assert-engine-fixture-address=
    (actual expected label field)
  (unless (bytes= (address-bytes actual) (address-bytes expected))
    (error "~A ~A mismatch: expected ~A, got ~A"
           label
           field
           (address-to-hex expected)
           (address-to-hex actual))))

(defun assert-engine-fixture-quantity=
    (actual expected label field)
  (unless (= actual expected)
    (error "~A ~A mismatch: expected ~A, got ~A"
           label
           field
           (quantity-to-hex expected)
           (quantity-to-hex actual))))

(defun validate-engine-fixture-expect-coherence
    (case parent payload expect case-name)
  (let* ((label (format nil
                        "Engine newPayloadV2 fixture case ~A expect"
                        case-name))
         (chain-id (fixture-quantity-field case "chainId"))
         (base-fee (fixture-quantity-field payload "baseFeePerGas"))
         (raw-transactions (fixture-object-field payload "transactions"))
         (withdrawals (fixture-object-field payload "withdrawals")))
    (unless (= 1 (length raw-transactions))
      (error "~A currently requires exactly one transaction" label))
    (unless (= 1 (length withdrawals))
      (error "~A currently requires exactly one withdrawal" label))
    (let* ((transaction (transaction-from-encoding
                         (hex-to-bytes (first raw-transactions))))
           (withdrawal (first withdrawals))
           (sender (transaction-sender transaction :expected-chain-id chain-id))
           (recipient (transaction-to transaction))
           (parent-state (engine-fixture-parent-state parent)))
      (unless sender
        (error "~A sender recovery failed" label))
      (unless recipient
        (error "~A transaction recipient must be present" label))
      (assert-engine-fixture-address=
       (fixture-address-field expect "sender")
       sender
       label
       "sender")
      (assert-engine-fixture-address=
       (fixture-address-field expect "recipient")
       recipient
       label
       "recipient")
      (assert-engine-fixture-address=
       (fixture-address-field expect "withdrawalRecipient")
       (fixture-address-field withdrawal "address")
       label
       "withdrawalRecipient")
      (let ((parent-sender-nonce (fixture-account-nonce parent-state sender)))
        (assert-engine-fixture-quantity=
         (transaction-nonce transaction)
         parent-sender-nonce
         label
         "transactionNonce")
        (assert-engine-fixture-quantity=
         (fixture-quantity-field expect "senderNonce")
         (1+ parent-sender-nonce)
         label
         "senderNonce"))
      (assert-engine-fixture-quantity=
       (fixture-quantity-field expect "recipientBalance")
       (+ (fixture-account-balance parent-state recipient)
          (transaction-value transaction))
       label
       "recipientBalance")
      (assert-engine-fixture-quantity=
       (fixture-quantity-field expect "withdrawalBalance")
       (+ (fixture-account-balance
           parent-state
           (fixture-address-field withdrawal "address"))
          (* (fixture-quantity-field withdrawal "amount") +wei-per-gwei+))
       label
       "withdrawalBalance")
      (assert-engine-fixture-quantity=
       (fixture-quantity-field expect "senderBalance")
       (- (fixture-account-balance parent-state sender)
          (transaction-value transaction)
          (* (transaction-intrinsic-gas transaction)
             (transaction-effective-gas-price transaction
                                              :base-fee base-fee)))
       label
       "senderBalance")
      (assert-engine-fixture-quantity=
       (fixture-quantity-field expect "receiptType")
       (transaction-type transaction)
       label
       "receiptType")
      (assert-engine-fixture-quantity=
       (fixture-quantity-field expect "receiptStatus")
       1
       label
       "receiptStatus"))))

(defun validate-engine-newpayload-v2-fixture-case-shape (case)
  (validate-fixture-object-fields
   case
   +engine-newpayload-v2-fixture-case-fields+
   "Engine newPayloadV2 fixture case")
  (let ((name (fixture-required-field case "name")))
    (unless (stringp name)
      (error "Engine newPayloadV2 fixture case name must be a string"))
    (when (blank-string-p name)
      (error "Engine newPayloadV2 fixture case name must be present"))
    (unless (string= "Shanghai" (fixture-required-field case "network"))
      (error "Engine newPayloadV2 fixture case ~A network must be Shanghai"
             name))
    (validate-engine-fixture-quantity-field
     case
     "chainId"
     (format nil "Engine newPayloadV2 fixture case ~A" name))
    (validate-engine-fixture-config-shape
     (fixture-required-field case "config")
     name)
    (let ((parent (fixture-required-field case "parent"))
          (payload (fixture-required-field case "payload")))
      (validate-engine-fixture-parent-shape parent name)
      (validate-engine-fixture-payload-shape payload name)
      (validate-engine-fixture-parent-payload-coherence
       parent
       payload
       name))
    (let ((expect (fixture-required-field case "expect")))
      (validate-engine-fixture-expect-shape expect name)
      (validate-engine-fixture-expect-coherence
       case
       (fixture-required-field case "parent")
       (fixture-required-field case "payload")
       expect
       name))))

(defun validate-engine-newpayload-v2-fixture-cases (cases)
  (unless (and (listp cases) cases)
    (error "Engine newPayloadV2 fixture cases must be a non-empty JSON array"))
  (let ((seen-names (make-hash-table :test 'equal)))
    (dolist (case cases)
      (validate-engine-newpayload-v2-fixture-case-shape case)
      (let ((name (fixture-object-field case "name")))
        (when (gethash name seen-names)
          (error "Engine newPayloadV2 fixture has duplicate case name ~A"
                 name))
        (setf (gethash name seen-names) t)))))

(defun validate-engine-newpayload-v2-fixture (fixture)
  (validate-engine-newpayload-v2-fixture-metadata fixture)
  (validate-engine-newpayload-v2-fixture-cases
   (fixture-required-field fixture "cases")))

(defun load-engine-newpayload-v2-fixture-cases (path)
  (let ((fixture (load-handwritten-fixture-file path)))
    (validate-engine-newpayload-v2-fixture fixture)
    (handwritten-fixture-cases fixture)))

(defun select-engine-newpayload-v2-fixture-case (path name)
  (let ((case (find name
                    (load-engine-newpayload-v2-fixture-cases path)
                    :key (lambda (case)
                           (fixture-object-field case "name"))
                    :test #'string=)))
    (unless case
      (error "Engine newPayloadV2 fixture case not found: ~A" name))
    case))

(defun fixture-quantity-field (object name)
  (hex-to-quantity (fixture-object-field object name)))

(defun fixture-address-field (object name)
  (address-from-hex (fixture-object-field object name)))

(defun engine-fixture-chain-config (case)
  (let ((config (fixture-object-field case "config")))
    (make-chain-config
     :chain-id (hex-to-quantity (fixture-object-field case "chainId"))
     :london-block (fixture-quantity-field config "londonBlock")
     :shanghai-time (fixture-quantity-field config "shanghaiTime"))))

(defun engine-fixture-parent-state (parent)
  (let ((state (make-state-db)))
    (dolist (account (fixture-object-field parent "accounts"))
      (state-db-set-account
       state
       (fixture-address-field account "address")
       (make-state-account
        :nonce (fixture-quantity-field account "nonce")
        :balance (fixture-quantity-field account "balance"))))
    state))

(defun engine-fixture-withdrawal (object)
  (make-withdrawal
   :index (fixture-quantity-field object "index")
   :validator-index (fixture-quantity-field object "validatorIndex")
   :address (fixture-address-field object "address")
   :amount (fixture-quantity-field object "amount")))

(defun engine-fixture-payload-request (id payload)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "engine_newPayloadV2")
        (cons "params"
              (list (engine-rpc-executable-data-object payload)))))

(defun engine-fixture-forkchoice-request (id head)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "engine_forkchoiceUpdatedV1")
        (cons "params"
              (list
               (list
                (cons "headBlockHash" (hash32-to-hex head))
                (cons "safeBlockHash" (hash32-to-hex (zero-hash32)))
                (cons "finalizedBlockHash"
                      (hash32-to-hex (zero-hash32))))))))

(defun engine-fixture-balance-request (id address)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getBalance")
        (cons "params" (list (address-to-hex address) "latest"))))

(defun engine-fixture-block-by-number-request (id tag full-transactions-p)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getBlockByNumber")
        (cons "params" (list tag full-transactions-p))))

(defun engine-fixture-block-by-hash-request (id hash full-transactions-p)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getBlockByHash")
        (cons "params" (list (hash32-to-hex hash) full-transactions-p))))

(defun engine-fixture-transaction-count-by-number-request (id tag)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getBlockTransactionCountByNumber")
        (cons "params" (list tag))))

(defun engine-fixture-transaction-count-by-hash-request (id hash)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getBlockTransactionCountByHash")
        (cons "params" (list (hash32-to-hex hash)))))

(defun engine-fixture-raw-transaction-by-block-number-request (id tag index)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getRawTransactionByBlockNumberAndIndex")
        (cons "params" (list tag (quantity-to-hex index)))))

(defun engine-fixture-transaction-by-block-hash-request (id hash index)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getTransactionByBlockHashAndIndex")
        (cons "params" (list (hash32-to-hex hash) (quantity-to-hex index)))))

(defun engine-fixture-transaction-by-hash-request (id hash)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getTransactionByHash")
        (cons "params" (list (hash32-to-hex hash)))))

(defun engine-fixture-receipt-request (id hash)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getTransactionReceipt")
        (cons "params" (list (hash32-to-hex hash)))))

(defun engine-newpayload-v2-metadata-shape-test-fixture
    (&key top-extra eest-extra reference-extra)
  (append
   (list
    (cons "format" +engine-newpayload-v2-fixture-format+)
    (cons "source" "test fixture")
    (cons "executionSpecTests"
          (append
           (list (cons "release" +phase-a-eest-release+)
                 (cons "tagTarget" +phase-a-eest-tag-target+)
                 (cons "archive" +phase-a-eest-archive+)
                 (cons "status" "test"))
           eest-extra))
    (cons "referenceClients"
          (append
           (list (cons "geth" "test-geth")
                 (cons "nethermind" "test-nethermind")
                 (cons "reth" nil))
           reference-extra))
    (cons "cases" nil))
   top-extra))

(defun engine-newpayload-v2-case-shape-test-case (&key extra name)
  (append
   (list
    (cons "name" (or name "valid-engine-case"))
    (cons "network" "Shanghai")
    (cons "chainId" "0x1")
    (cons "config"
          (list (cons "londonBlock" "0x0")
                (cons "shanghaiTime" "0x0")))
    (cons "parent"
          (list
           (cons "number" "0x29")
           (cons "gasLimit" "0xc350")
           (cons "gasUsed" "0x61a8")
           (cons "timestamp" "0x62")
           (cons "baseFeePerGas" "0x64")
           (cons "feeRecipient" "0x0000000000000000000000000000000000000001")
           (cons "accounts"
                 (list
                  (list
                   (cons "address"
                         "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f")
                   (cons "nonce" "0x9")
                   (cons "balance" "0x1bc16d674ec80000"))))))
    (cons "payload"
          (list
           (cons "number" "0x2a")
           (cons "gasLimit" "0xc350")
           (cons "timestamp" "0x63")
           (cons "baseFeePerGas" "0x64")
           (cons "transactions"
                 (list
                  "0xf86c098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a76400008025a028ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276a067cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83"))
           (cons "withdrawals"
                 (list
                  (list
                   (cons "index" "0x0")
                   (cons "validatorIndex" "0x1")
                   (cons "address"
                         "0x0000000000000000000000000000000000000002")
                   (cons "amount" "0x1"))))))
    (cons "expect"
          (list
           (cons "status" "VALID")
           (cons "sender" "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f")
           (cons "senderNonce" "0xa")
           (cons "senderBalance" "0xddf38b6c895c000")
           (cons "recipient" "0x3535353535353535353535353535353535353535")
           (cons "recipientBalance" "0xde0b6b3a7640000")
           (cons "withdrawalRecipient"
                 "0x0000000000000000000000000000000000000002")
           (cons "withdrawalBalance" "0x3b9aca00")
           (cons "receiptType" "0x0")
           (cons "receiptStatus" "0x1"))))
   extra))

(deftest engine-newpayload-v2-fixture-metadata-validation
  (validate-engine-newpayload-v2-fixture-metadata
   (engine-newpayload-v2-metadata-shape-test-fixture))
  (signals error
    (validate-engine-newpayload-v2-fixture-metadata
     (engine-newpayload-v2-metadata-shape-test-fixture
      :top-extra (list (cons "unexpectedTopField" t)))))
  (signals error
    (validate-engine-newpayload-v2-fixture-metadata
     (engine-newpayload-v2-metadata-shape-test-fixture
      :top-extra (list (cons "source" "duplicate source")))))
  (signals error
    (validate-engine-newpayload-v2-fixture-metadata
     (engine-newpayload-v2-metadata-shape-test-fixture
      :eest-extra (list (cons "unexpectedPinnedField" t)))))
  (signals error
    (validate-engine-newpayload-v2-fixture-metadata
     (engine-newpayload-v2-metadata-shape-test-fixture
      :reference-extra (list (cons "besu" "test-besu"))))))

(deftest engine-newpayload-v2-fixture-case-validation
  (let ((case (engine-newpayload-v2-case-shape-test-case)))
    (labels ((replace-field (object field value)
               (cons (cons field value)
                     (remove field object :key #'car :test #'string=))))
      (validate-engine-newpayload-v2-fixture-cases (list case))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases nil))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (engine-newpayload-v2-case-shape-test-case
                :extra (list (cons "unexpected" t))))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (engine-newpayload-v2-case-shape-test-case :name ""))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list case
               (engine-newpayload-v2-case-shape-test-case
                :name "valid-engine-case"))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "config"
                (list (cons "londonBlock" "0x0")
                      (cons "shanghaiTime" "0x0")
                      (cons "unknownFork" "0x0"))))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "parent"
                (replace-field
                 (fixture-required-field case "parent")
                 "feeRecipient"
                 "0x1234")))))
      (signals error
        (let* ((parent (fixture-required-field case "parent"))
               (accounts (fixture-required-field parent "accounts"))
               (duplicate-accounts
                 (append accounts (list (first accounts)))))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "parent"
                  (replace-field parent "accounts" duplicate-accounts))))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "payload"
                (replace-field
                 (fixture-required-field case "payload")
                 "transactions"
                 nil)))))
      (signals error
        (let* ((payload (fixture-required-field case "payload"))
               (withdrawals (fixture-required-field payload "withdrawals"))
               (duplicate-withdrawals
                 (append withdrawals (list (first withdrawals)))))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "payload"
                  (replace-field
                   payload
                   "withdrawals"
                   duplicate-withdrawals))))))
      (signals error
        (let ((payload (fixture-required-field case "payload")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "payload"
                  (replace-field payload "number" "0x2b"))))))
      (signals error
        (let ((payload (fixture-required-field case "payload")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "payload"
                  (replace-field payload "timestamp" "0x62"))))))
      (signals error
        (let ((payload (fixture-required-field case "payload")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "payload"
                  (replace-field payload "gasLimit" "0x1"))))))
      (signals error
        (let ((payload (fixture-required-field case "payload")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "payload"
                  (replace-field payload "baseFeePerGas" "0x65"))))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "expect"
                (replace-field
                 (fixture-required-field case "expect")
                 "status"
                 "INVALID")))))
      (signals error
        (let ((expect (fixture-required-field case "expect")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "expect"
                  (replace-field
                   expect
                   "sender"
                   "0x0000000000000000000000000000000000000001"))))))
      (signals error
        (let ((expect (fixture-required-field case "expect")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "expect"
                  (replace-field expect "senderNonce" "0xb"))))))
      (signals error
        (let ((expect (fixture-required-field case "expect")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "expect"
                  (replace-field expect "withdrawalBalance" "0x1")))))))))

(deftest engine-newpayload-v2-fixture-executes-and-becomes-canonical
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((case
             (select-engine-newpayload-v2-fixture-case
              +engine-newpayload-v2-fixture-path+
              "shanghai-one-transfer-with-withdrawal"))
           (store (make-engine-payload-memory-store))
           (config (engine-fixture-chain-config case))
           (parent (fixture-object-field case "parent"))
           (payload-case (fixture-object-field case "payload"))
           (expect (fixture-object-field case "expect"))
           (parent-state (engine-fixture-parent-state parent))
           (fee-recipient (fixture-address-field parent "feeRecipient"))
           (transactions
             (mapcar (lambda (raw)
                       (transaction-from-encoding (hex-to-bytes raw)))
                     (fixture-object-field payload-case "transactions")))
           (withdrawals
             (mapcar #'engine-fixture-withdrawal
                     (fixture-object-field payload-case "withdrawals")))
           (sender (fixture-address-field expect "sender"))
           (recipient (fixture-address-field expect "recipient"))
           (withdrawal-recipient
             (fixture-address-field expect "withdrawalRecipient")))
      (let* ((parent-header
               (make-block-header
                :parent-hash (zero-hash32)
                :beneficiary fee-recipient
                :state-root (state-db-root parent-state)
                :mix-hash (zero-hash32)
                :number (fixture-quantity-field parent "number")
                :gas-limit (fixture-quantity-field parent "gasLimit")
                :gas-used (fixture-quantity-field parent "gasUsed")
                :timestamp (fixture-quantity-field parent "timestamp")
                :base-fee-per-gas
                (fixture-quantity-field parent "baseFeePerGas")
                :withdrawals-root (withdrawal-list-root '())))
             (parent-block (make-block :header parent-header))
             (expected-state (state-db-copy parent-state))
             (child-header
               (make-block-header
                :parent-hash (block-hash parent-block)
                :beneficiary fee-recipient
                :mix-hash (zero-hash32)
                :number (fixture-quantity-field payload-case "number")
                :gas-limit (fixture-quantity-field payload-case "gasLimit")
                :gas-used 0
                :timestamp (fixture-quantity-field payload-case "timestamp")
                :base-fee-per-gas
                (fixture-quantity-field payload-case "baseFeePerGas")))
             (child-block
               (execute-signed-block
                expected-state
                transactions
                :expected-chain-id (chain-config-chain-id config)
                :header child-header
                :chain-config config
                :withdrawals withdrawals))
             (payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data child-block)))
             (transaction-hash (transaction-hash (first transactions))))
        (engine-payload-store-put-block
         store parent-block :state-available-p t)
        (commit-state-db-to-chain-store
         store (block-hash parent-block) parent-state)
        (let* ((response
                 (engine-rpc-handle-request
                  (engine-fixture-payload-request 101 payload)
                  store config
                  :import-function #'execute-and-commit-engine-payload))
               (result (field response "result")))
          (is (string= (fixture-object-field expect "status")
                       (field result "status")))
          (is (string= (hash32-to-hex (block-hash child-block))
                       (field result "latestValidHash")))
          (is (engine-payload-store-known-block
               store (block-hash child-block)))
          (is (chain-store-state-available-p
               store (block-hash child-block)))
          (is (= (hex-to-quantity (fixture-object-field expect "senderNonce"))
                 (chain-store-account-nonce
                  store (block-hash child-block) sender)))
          (is (= (hex-to-quantity
                  (fixture-object-field expect "senderBalance"))
                 (chain-store-account-balance
                  store (block-hash child-block) sender)))
          (is (= (hex-to-quantity
                  (fixture-object-field expect "recipientBalance"))
                 (chain-store-account-balance
                  store (block-hash child-block) recipient)))
          (is (= (hex-to-quantity
                  (fixture-object-field expect "withdrawalBalance"))
                 (chain-store-account-balance
                  store (block-hash child-block)
                  withdrawal-recipient))))
        (let* ((forkchoice-response
                 (engine-rpc-handle-request
                  (engine-fixture-forkchoice-request
                   102 (block-hash child-block))
                  store config))
               (forkchoice-result
                 (field forkchoice-response "result"))
               (payload-status
                 (field forkchoice-result "payloadStatus"))
               (receipt-response
                 (engine-rpc-handle-request
                  (engine-fixture-receipt-request 103 transaction-hash)
                  store config))
               (receipt (field receipt-response "result"))
               (recipient-balance-response
                 (engine-rpc-handle-request
                  (engine-fixture-balance-request 104 recipient)
                  store config))
               (withdrawal-balance-response
                 (engine-rpc-handle-request
                  (engine-fixture-balance-request 105 withdrawal-recipient)
                  store config))
               (block-by-number-response
                 (engine-rpc-handle-request
                  (engine-fixture-block-by-number-request 106 "latest" nil)
                  store config))
               (block-by-number
                 (field block-by-number-response "result"))
               (full-block-response
                 (engine-rpc-handle-request
                  (engine-fixture-block-by-number-request 107 "latest" t)
                  store config))
               (full-block
                 (field full-block-response "result"))
               (full-block-transaction
                 (first (field full-block "transactions")))
               (block-by-hash-response
                 (engine-rpc-handle-request
                  (engine-fixture-block-by-hash-request
                   108 (block-hash child-block) nil)
                  store config))
               (block-by-hash
                 (field block-by-hash-response "result"))
               (transaction-count-by-number-response
                 (engine-rpc-handle-request
                  (engine-fixture-transaction-count-by-number-request
                   109 "latest")
                  store config))
               (transaction-count-by-hash-response
                 (engine-rpc-handle-request
                  (engine-fixture-transaction-count-by-hash-request
                   110 (block-hash child-block))
                  store config))
               (raw-transaction-response
                 (engine-rpc-handle-request
                  (engine-fixture-raw-transaction-by-block-number-request
                   111 "latest" 0)
                  store config))
               (transaction-by-block-response
                 (engine-rpc-handle-request
                  (engine-fixture-transaction-by-block-hash-request
                   112 (block-hash child-block) 0)
                  store config))
               (transaction-by-block
                 (field transaction-by-block-response "result"))
               (transaction-by-hash-response
                 (engine-rpc-handle-request
                  (engine-fixture-transaction-by-hash-request
                   113 transaction-hash)
                  store config))
               (transaction-by-hash
                 (field transaction-by-hash-response "result"))
               (receipts
                 (chain-store-block-receipts
                  store (block-hash child-block)))
               (receipts-root
                 (block-header-receipts-root (block-header child-block))))
          (is (string= +payload-status-valid+
                       (field payload-status "status")))
          (is (string= (hash32-to-hex (block-hash child-block))
                       (hash32-to-hex
                        (chain-store-canonical-hash
                         store
                         (block-header-number
                          (block-header child-block))))))
          (is (= 1 (length receipts)))
          (is (string= (hash32-to-hex (receipt-list-root receipts))
                       (hash32-to-hex receipts-root)))
          (is (string= (hash32-to-hex
                        (transaction-receipt-list-root
                         transactions
                         receipts))
                       (hash32-to-hex receipts-root)))
          (is (string= (fixture-object-field expect "receiptType")
                       (field receipt "type")))
          (is (string= (fixture-object-field expect "receiptStatus")
                       (field receipt "status")))
          (is (string= (quantity-to-hex
                        (hex-to-quantity
                         (fixture-object-field expect "recipientBalance")))
                       (field recipient-balance-response "result")))
          (is (string= (quantity-to-hex
                        (hex-to-quantity
                         (fixture-object-field expect "withdrawalBalance")))
                       (field withdrawal-balance-response "result")))
          (is (string= (hash32-to-hex (block-hash child-block))
                       (field block-by-number "hash")))
          (is (string= (quantity-to-hex
                        (block-header-number (block-header child-block)))
                       (field block-by-number "number")))
          (is (equal (list (hash32-to-hex transaction-hash))
                     (field block-by-number "transactions")))
          (is (string= (field block-by-number "hash")
                       (field block-by-hash "hash")))
          (is (string= (hash32-to-hex transaction-hash)
                       (field full-block-transaction "hash")))
          (is (string= (field block-by-number "hash")
                       (field full-block-transaction "blockHash")))
          (is (string= (field block-by-number "number")
                       (field full-block-transaction "blockNumber")))
          (is (string= (quantity-to-hex 0)
                       (field full-block-transaction "transactionIndex")))
          (is (string= (address-to-hex sender)
                       (field full-block-transaction "from")))
          (is (string= (address-to-hex recipient)
                       (field full-block-transaction "to")))
          (is (string= (quantity-to-hex 1)
                       (field transaction-count-by-number-response "result")))
          (is (string= (quantity-to-hex 1)
                       (field transaction-count-by-hash-response "result")))
          (is (string= (bytes-to-hex
                        (transaction-encoding (first transactions)))
                       (field raw-transaction-response "result")))
          (is (string= (field block-by-number "hash")
                       (field transaction-by-block "blockHash")))
          (is (string= (hash32-to-hex transaction-hash)
                       (field transaction-by-block "hash")))
          (is (string= (address-to-hex sender)
                       (field transaction-by-block "from")))
          (is (string= (address-to-hex recipient)
                       (field transaction-by-block "to")))
          (is (string= (field transaction-by-block "hash")
                       (field transaction-by-hash "hash")))
          (is (string= (field transaction-by-block "blockHash")
                       (field transaction-by-hash "blockHash"))))))))
