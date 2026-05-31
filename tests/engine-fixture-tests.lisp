(in-package #:ethereum-lisp.test)

(defparameter +engine-newpayload-v2-fixture-path+
  "tests/fixtures/execution-spec-tests/engine-newpayload-v2.json")

(defparameter +engine-newpayload-v2-fixture-format+
  "ethereum-lisp/engine-newpayload-fixture-v1")

(defparameter +engine-newpayload-v2-smoke-case-names+
  '("shanghai-one-transfer-with-withdrawal"
    "shanghai-access-list-transfer-with-withdrawal"
    "shanghai-dynamic-fee-transfer-with-withdrawal"
    "shanghai-contract-creation-with-withdrawal"
    "shanghai-internal-create2-with-withdrawal"))

(defparameter +engine-newpayload-v2-smoke-coverage-families+
  '(:legacy-transfer :access-list-transfer :dynamic-fee-transfer
    :contract-creation))

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
    "cumulativeGasUsed"))

(defun validate-engine-fixture-non-empty-string (value label)
  (unless (stringp value)
    (error "~A must be a string" label))
  (when (blank-string-p value)
    (error "~A must be present" label))
  value)

(defun validate-engine-newpayload-v2-fixture-metadata (fixture)
  (validate-fixture-object-fields
   fixture
   +engine-newpayload-v2-fixture-top-level-fields+
   "Engine newPayloadV2 fixture")
  (validate-fixture-format fixture +engine-newpayload-v2-fixture-format+)
  (validate-engine-fixture-non-empty-string
   (fixture-required-field fixture "source")
   "Engine newPayloadV2 fixture source")
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
      (validate-engine-fixture-non-empty-string
       (fixture-object-field references client)
       (format nil "Engine newPayloadV2 fixture referenceClients.~A"
               client)))
    (let ((reth (fixture-object-field references "reth")))
      (unless (or (null reth)
                  (and (stringp reth) (not (blank-string-p reth))))
        (error "Engine newPayloadV2 fixture referenceClients.reth must be null or a non-empty string")))))

(defun validate-engine-fixture-quantity-field (object field label)
  (let ((value (fixture-required-field object field)))
    (unless (stringp value)
      (error "~A ~A must be a hex quantity string" label field))
    (handler-case
        (let ((quantity (hex-to-quantity value)))
          (unless (string= value (string-downcase (quantity-to-hex quantity)))
            (error "~A ~A must be a canonical hex quantity"
                   label field)))
      (error (condition)
        (error "~A ~A must be a hex quantity: ~A"
               label field condition)))))

(defun validate-engine-fixture-address-field (object field label)
  (let ((value (fixture-required-field object field)))
    (unless (stringp value)
      (error "~A ~A must be an address hex string" label field))
    (handler-case
        (let ((address (address-from-hex value)))
          (unless (string= value (address-to-hex address))
            (error "~A ~A must be canonical lowercase 0x-prefixed address hex"
                   label field)))
      (error (condition)
        (error "~A ~A must be an address: ~A"
               label field condition)))))

(defun validate-engine-fixture-optional-code-field (object field label)
  (when (fixture-field-present-p object field)
    (let ((value (fixture-object-field object field)))
      (unless (stringp value)
        (error "~A ~A must be a hex string" label field))
      (handler-case
          (let ((bytes (hex-to-bytes value)))
            (unless (string= value (bytes-to-hex bytes))
              (error "~A ~A must be canonical lowercase 0x-prefixed hex"
                     label field)))
        (error (condition)
          (error "~A ~A must be hex bytes: ~A"
                 label field condition))))))

(defun validate-engine-fixture-code-field (object field label)
  (let ((value (fixture-required-field object field)))
    (unless (stringp value)
      (error "~A ~A must be a hex string" label field))
    (handler-case
        (let ((bytes (hex-to-bytes value)))
          (unless (string= value (bytes-to-hex bytes))
            (error "~A ~A must be canonical lowercase 0x-prefixed hex"
                   label field)))
      (error (condition)
        (error "~A ~A must be hex bytes: ~A"
               label field condition)))))

(defun validate-engine-fixture-hash-field (object field label)
  (let ((value (fixture-required-field object field)))
    (unless (stringp value)
      (error "~A ~A must be a hash hex string" label field))
    (handler-case
        (let ((hash (hash32-from-hex value)))
          (unless (string= value (hash32-to-hex hash))
            (error "~A ~A must be canonical lowercase 0x-prefixed hash hex"
                   label field)))
      (error (condition)
        (error "~A ~A must be a 32-byte hash: ~A"
               label field condition)))))

(defun validate-engine-fixture-quantity-array-field
    (object field label expected-length)
  (when (fixture-field-present-p object field)
    (let ((values (fixture-object-field object field)))
      (unless (and (listp values) (= expected-length (length values)))
        (error "~A ~A must be a JSON array with ~D entries"
               label field expected-length))
      (dolist (value values)
        (validate-engine-fixture-quantity-field
         (list (cons field value))
         field
         label)))))

(defun validate-engine-fixture-address-array-field
    (object field label expected-length)
  (when (fixture-field-present-p object field)
    (let ((values (fixture-object-field object field)))
      (unless (and (listp values) (= expected-length (length values)))
        (error "~A ~A must be a JSON array with ~D entries"
               label field expected-length))
      (dolist (value values)
        (validate-engine-fixture-address-field
         (list (cons field value))
         field
         label)))))

(defun validate-engine-fixture-transaction-bytes (value label)
  (unless (stringp value)
    (error "~A transactions entries must be hex strings" label))
  (handler-case
      (let ((bytes (hex-to-bytes value)))
        (unless (string= value (bytes-to-hex bytes))
          (error "~A transactions entries must be canonical lowercase 0x-prefixed hex"
                 label))
        (transaction-from-encoding bytes))
    (error (condition)
      (error "~A transactions entries must be signed transaction bytes: ~A"
             label condition))))

(defun validate-engine-fixture-storage-object (storage label)
  (unless (listp storage)
    (error "~A storage must be a JSON object" label))
  (let ((seen-slots (make-hash-table :test 'equal)))
    (dolist (entry storage)
      (unless (consp entry)
        (error "~A storage entries must be JSON object fields" label))
      (let ((slot (car entry))
            (value (cdr entry)))
        (unless (stringp slot)
          (error "~A storage key must be a 32-byte hash string" label))
        (unless (stringp value)
          (error "~A storage value must be a hex quantity string" label))
        (let ((slot-id
                (handler-case
                    (hash32-to-hex (hash32-from-hex slot))
                  (error (condition)
                    (error "~A storage key must be a 32-byte hash: ~A"
                           label condition)))))
          (when (gethash slot-id seen-slots)
            (error "~A has duplicate storage slot ~A" label slot))
          (setf (gethash slot-id seen-slots) t))
        (handler-case
            (let ((quantity (hex-to-quantity value)))
              (unless (string= value
                               (string-downcase (quantity-to-hex quantity)))
                (error "~A storage value must be a canonical hex quantity"
                       label)))
          (error (condition)
            (error "~A storage value must be a hex quantity: ~A"
                   label condition)))))))

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
    (validate-engine-fixture-quantity-field account "balance" label)
    (validate-engine-fixture-optional-code-field account "code" label)
    (when (fixture-field-present-p account "storage")
      (validate-engine-fixture-storage-object
       (fixture-object-field account "storage")
       label))))

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
        (validate-engine-fixture-transaction-bytes raw label)))
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

(defun validate-engine-fixture-expect-shape
    (expect case-name transaction-count)
  (let ((label (format nil
                       "Engine newPayloadV2 fixture case ~A expect"
                       case-name)))
    (validate-fixture-object-fields
     expect
     +engine-newpayload-v2-fixture-expect-fields+
     label)
    (let ((status (fixture-required-field expect "status")))
      (unless (stringp status)
        (error "~A status must be a string" label))
      (unless (string= +payload-status-valid+ status)
        (error "~A status must be VALID" label)))
    (dolist (field '("sender"
                     "withdrawalRecipient"
                     "codeAddress"
                     "storageAddress"))
      (validate-engine-fixture-address-field expect field label))
    (dolist (field '("recipient" "contractAddress"))
      (when (fixture-field-present-p expect field)
        (validate-engine-fixture-address-field expect field label)))
    (dolist (field '("senderNonce"
                     "senderBalance"
                     "withdrawalBalance"
                     "receiptType"
                     "receiptStatus"))
      (validate-engine-fixture-quantity-field expect field label))
    (dolist (field '("recipientBalance" "contractBalance"))
      (when (fixture-field-present-p expect field)
        (validate-engine-fixture-quantity-field expect field label)))
    (validate-engine-fixture-code-field expect "code" label)
    (validate-engine-fixture-hash-field expect "storageKey" label)
    (validate-engine-fixture-hash-field expect "storageValue" label)
    (validate-engine-fixture-address-array-field
     expect "recipients" label transaction-count)
    (validate-engine-fixture-quantity-array-field
     expect "recipientBalances" label transaction-count)
    (validate-engine-fixture-quantity-array-field
     expect "receiptTypes" label transaction-count)
    (validate-engine-fixture-quantity-array-field
     expect "receiptStatuses" label transaction-count)
    (validate-engine-fixture-quantity-array-field
     expect "cumulativeGasUsed" label transaction-count)))

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

(defun fixture-account-has-code-p (state address)
  (plusp (length (state-db-get-code state address))))

(defun assert-eest-blockchain-post-state-storage
    (state address expected-storage label)
  (unless (listp expected-storage)
    (error "~A storage must be a JSON object" label))
  (dolist (entry expected-storage)
    (unless (consp entry)
      (error "~A storage entries must be JSON object fields" label))
    (let* ((slot
             (hash32-from-hex
              (eest-blockchain-normalized-storage-slot
               (car entry)
               (format nil "~A storage key" label))))
           (expected-value (hex-to-quantity (cdr entry))))
      (is (= expected-value
             (state-db-get-storage state address slot))))))

(defun assert-eest-blockchain-post-state-account
    (state address expected-account label)
  (unless (listp expected-account)
    (error "~A account must be a JSON object" label))
  (let ((account (state-db-get-account state address)))
    (is account)
    (is (= (hex-to-quantity
            (or (fixture-object-field expected-account "nonce") "0x0"))
           (state-account-nonce account)))
    (is (= (hex-to-quantity
            (or (fixture-object-field expected-account "balance") "0x0"))
           (state-account-balance account)))
    (is (bytes= (hex-to-bytes
                 (or (fixture-object-field expected-account "code") "0x"))
                (state-db-get-code state address)))
    (assert-eest-blockchain-post-state-storage
     state
     address
     (or (fixture-object-field expected-account "storage") '())
     label)))

(defun assert-eest-blockchain-post-state (state source-case)
  (let* ((fixture (fixture-required-field source-case "fixture"))
         (post-state (fixture-object-field fixture "postState")))
    (when post-state
      (unless (listp post-state)
        (error "EEST blockchain case ~A postState must be a JSON object"
               (fixture-required-field source-case "name")))
      (dolist (entry post-state)
        (unless (consp entry)
          (error "EEST blockchain case ~A postState entries must be JSON object fields"
                 (fixture-required-field source-case "name")))
        (let ((address (address-from-hex (car entry))))
          (assert-eest-blockchain-post-state-account
           state
           address
           (cdr entry)
           (format nil "EEST blockchain case ~A postState account ~A"
                   (fixture-required-field source-case "name")
                   (car entry))))))))

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
    (unless (= 1 (length withdrawals))
      (error "~A currently requires exactly one withdrawal" label))
    (let* ((transactions
             (mapcar (lambda (raw)
                       (transaction-from-encoding (hex-to-bytes raw)))
                     raw-transactions))
           (transaction (first transactions))
           (withdrawal (first withdrawals))
           (sender (transaction-sender transaction :expected-chain-id chain-id))
           (recipient (transaction-to transaction))
           (parent-state (engine-fixture-parent-state parent)))
      (unless sender
        (error "~A sender recovery failed" label))
      (dolist (tx transactions)
        (let ((tx-sender (transaction-sender tx :expected-chain-id chain-id)))
          (unless tx-sender
            (error "~A sender recovery failed" label))
          (assert-engine-fixture-address=
           tx-sender
           sender
           label
           "sender")))
      (assert-engine-fixture-address=
       (fixture-address-field expect "sender")
       sender
       label
       "sender")
      (when (> (length transactions) 1)
        (unless (and (fixture-field-present-p expect "recipients")
                     (fixture-field-present-p expect "recipientBalances")
                     (fixture-field-present-p expect "receiptTypes")
                     (fixture-field-present-p expect "receiptStatuses")
                     (fixture-field-present-p expect "cumulativeGasUsed"))
          (error "~A multi-transaction cases must provide recipients, recipientBalances, receiptTypes, receiptStatuses, and cumulativeGasUsed"
                 label))
        (loop for tx in transactions
              for index from 0
              unless (= (transaction-nonce tx)
                        (+ (fixture-account-nonce parent-state sender)
                           index))
                do (error "~A transaction ~D nonce is not consecutive"
                          label index))
        (loop for tx in transactions
              for recipient-hex in (fixture-object-field expect "recipients")
              for expected-recipient = (address-from-hex recipient-hex)
              unless (transaction-to tx)
                do (error "~A multi-transaction case contains contract creation"
                          label)
              do (assert-engine-fixture-address=
                  (transaction-to tx)
                  expected-recipient
                  label
                  "recipients"))
        (loop for recipient-hex in (fixture-object-field expect "recipients")
              for balance-hex in (fixture-object-field expect "recipientBalances")
              for expected-recipient = (address-from-hex recipient-hex)
              for expected-balance = (hex-to-quantity balance-hex)
              do (assert-engine-fixture-quantity=
                  expected-balance
                  (+ (fixture-account-balance parent-state expected-recipient)
                     (loop for tx in transactions
                           when (bytes= (address-bytes (transaction-to tx))
                                        (address-bytes expected-recipient))
                             sum (transaction-value tx)))
                  label
                  "recipientBalances"))
        (loop for tx in transactions
              for receipt-type-hex in (fixture-object-field expect "receiptTypes")
              for receipt-status-hex in (fixture-object-field expect "receiptStatuses")
              do (progn
                   (assert-engine-fixture-quantity=
                    (hex-to-quantity receipt-type-hex)
                    (transaction-type tx)
                    label
                    "receiptTypes")
                   (assert-engine-fixture-quantity=
                    (hex-to-quantity receipt-status-hex)
                    1
                    label
                    "receiptStatuses"))))
      (if recipient
          (progn
            (unless (fixture-field-present-p expect "recipient")
              (error "~A recipient must be present for transfer transactions"
                     label))
            (unless (fixture-field-present-p expect "recipientBalance")
              (error "~A recipientBalance must be present for transfer transactions"
                     label))
            (when (fixture-field-present-p expect "contractAddress")
              (error "~A contractAddress must be absent for transfer transactions"
                     label))
            (assert-engine-fixture-address=
             (fixture-address-field expect "recipient")
             recipient
             label
             "recipient")
            (assert-engine-fixture-quantity=
             (fixture-quantity-field expect "recipientBalance")
             (+ (fixture-account-balance parent-state recipient)
                (transaction-value transaction))
             label
             "recipientBalance"))
          (let ((contract-address
                  (make-address
                   (subseq
                    (keccak-256
                     (rlp-encode
                      (make-rlp-list (address-bytes sender)
                                     (transaction-nonce transaction))))
                    12 32))))
            (unless (fixture-field-present-p expect "contractAddress")
              (error "~A contractAddress must be present for contract creation"
                     label))
            (unless (fixture-field-present-p expect "contractBalance")
              (error "~A contractBalance must be present for contract creation"
                     label))
            (when (fixture-field-present-p expect "recipient")
              (error "~A recipient must be absent for contract creation"
                     label))
            (assert-engine-fixture-address=
             (fixture-address-field expect "contractAddress")
             contract-address
             label
             "contractAddress")
            (assert-engine-fixture-quantity=
             (fixture-quantity-field expect "contractBalance")
             (+ (fixture-account-balance parent-state contract-address)
                (transaction-value transaction))
             label
             "contractBalance")))
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
         (+ parent-sender-nonce (length transactions))
         label
         "senderNonce"))
      (assert-engine-fixture-quantity=
       (fixture-quantity-field expect "withdrawalBalance")
       (+ (fixture-account-balance
           parent-state
           (fixture-address-field withdrawal "address"))
          (* (fixture-quantity-field withdrawal "amount") +wei-per-gwei+))
       label
       "withdrawalBalance")
      (when (and recipient
                 (not (fixture-account-has-code-p parent-state recipient)))
        (assert-engine-fixture-quantity=
         (fixture-quantity-field expect "senderBalance")
         (loop with balance = (fixture-account-balance parent-state sender)
               for tx in transactions
               do (decf balance
                        (+ (transaction-value tx)
                           (* (transaction-intrinsic-gas tx)
                              (transaction-effective-gas-price
                               tx
                               :base-fee base-fee))))
               finally (return balance))
         label
         "senderBalance"))
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
    (let ((network (fixture-required-field case "network")))
      (unless (stringp network)
        (error "Engine newPayloadV2 fixture case ~A network must be a string"
               name))
      (unless (string= "Shanghai" network)
        (error "Engine newPayloadV2 fixture case ~A network must be Shanghai"
               name)))
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
      (validate-engine-fixture-expect-shape
       expect
       name
       (length (fixture-required-field
                (fixture-required-field case "payload")
                "transactions")))
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

(defun engine-newpayload-v2-smoke-coverage-family (case)
  (let* ((payload (fixture-required-field case "payload"))
         (raw-transactions (fixture-required-field payload "transactions")))
    (unless (= 1 (length raw-transactions))
      (error "Engine newPayloadV2 smoke case ~A must have exactly one transaction"
             (fixture-required-field case "name")))
    (let ((transaction (transaction-from-encoding
                        (hex-to-bytes (first raw-transactions)))))
      (cond
        ((null (transaction-to transaction))
         :contract-creation)
        ((zerop (transaction-type transaction))
         :legacy-transfer)
        ((= 1 (transaction-type transaction))
         :access-list-transfer)
        ((= 2 (transaction-type transaction))
         :dynamic-fee-transfer)
        (t
         (error "Engine newPayloadV2 smoke case ~A has unsupported coverage transaction type ~A"
                (fixture-required-field case "name")
                (transaction-type transaction)))))))

(defun validate-engine-newpayload-v2-smoke-coverage (cases)
  (let ((case-by-name (make-hash-table :test 'equal))
        (seen-smoke-names (make-hash-table :test 'equal))
        (covered-families (make-hash-table :test 'eq)))
    (dolist (case cases)
      (setf (gethash (fixture-required-field case "name") case-by-name)
            case))
    (dolist (case-name +engine-newpayload-v2-smoke-case-names+)
      (when (gethash case-name seen-smoke-names)
        (error "Engine newPayloadV2 smoke case list has duplicate name ~A"
               case-name))
      (setf (gethash case-name seen-smoke-names) t)
      (let ((case (gethash case-name case-by-name)))
        (unless case
          (error "Engine newPayloadV2 smoke case list references missing case ~A"
                 case-name))
        (setf (gethash (engine-newpayload-v2-smoke-coverage-family case)
                       covered-families)
              t)))
    (dolist (family +engine-newpayload-v2-smoke-coverage-families+)
      (unless (gethash family covered-families)
        (error "Engine newPayloadV2 smoke cases are missing coverage family ~A"
               family)))))

(defun validate-engine-newpayload-v2-fixture (fixture)
  (validate-engine-newpayload-v2-fixture-metadata fixture)
  (let ((cases (fixture-required-field fixture "cases")))
    (validate-engine-newpayload-v2-fixture-cases cases)
    (validate-engine-newpayload-v2-smoke-coverage cases)))

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
     :byzantium-block 0
     :constantinople-block 0
     :petersburg-block 0
     :istanbul-block 0
     :berlin-block (fixture-quantity-field config "berlinBlock")
     :london-block (fixture-quantity-field config "londonBlock")
     :shanghai-time (fixture-quantity-field config "shanghaiTime"))))

(defun engine-fixture-parent-state (parent)
  (let ((state (make-state-db)))
    (dolist (account (fixture-object-field parent "accounts"))
      (let ((address (fixture-address-field account "address")))
        (state-db-set-account
         state
         address
         (make-state-account
          :nonce (fixture-quantity-field account "nonce")
          :balance (fixture-quantity-field account "balance")))
        (when (fixture-field-present-p account "code")
          (state-db-set-code
           state
           address
           (hex-to-bytes (fixture-object-field account "code"))))
        (dolist (entry (fixture-object-field account "storage"))
          (state-db-set-storage
           state
           address
           (hash32-from-hex (car entry))
           (hex-to-quantity (cdr entry))))))
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

(defun engine-fixture-forkchoice-request
    (id head &key (safe (zero-hash32)) (finalized (zero-hash32)))
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "engine_forkchoiceUpdatedV1")
        (cons "params"
              (list
               (list
                (cons "headBlockHash" (hash32-to-hex head))
                (cons "safeBlockHash" (hash32-to-hex safe))
                (cons "finalizedBlockHash" (hash32-to-hex finalized)))))))

(deftest eest-blockchain-engine-newpayload-v2-empty-replay
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let ((root (execution-spec-tests-blockchain-test-root
                 "tests/fixtures/execution-spec-tests-root/")))
      (dolist (source-name '("shanghai/phase-a-empty-engine.json"
                             "shanghai/phase-a-empty-standard.json"))
        (let* ((source-case
                 (first
                  (load-eest-blockchain-test-root-cases
                   root
                   :names (list source-name))))
               (case (materialize-eest-blockchain-engine-newpayload-v2-case
                      source-case))
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
                         (fixture-object-field payload-case "withdrawals"))))
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
                 (child-state (state-db-copy parent-state))
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
                    child-state
                    transactions
                    :expected-chain-id (chain-config-chain-id config)
                    :header child-header
                    :chain-config config
                    :withdrawals withdrawals))
                 (payload
                   (execution-payload-envelope-execution-payload
                    (block-to-executable-data child-block))))
            (engine-payload-store-put-block
             store parent-block :state-available-p t)
            (commit-state-db-to-chain-store
             store (block-hash parent-block) parent-state)
            (let* ((response
                     (engine-rpc-handle-request
                      (engine-fixture-payload-request 301 payload)
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
              (is (string= (fixture-object-field expect "stateRoot")
                           (hash32-to-hex
                            (block-header-state-root
                             (block-header child-block)))))
              (is (string= (fixture-object-field expect "receiptsRoot")
                           (hash32-to-hex
                            (block-header-receipts-root
                             (block-header child-block)))))
              (is (= (hex-to-quantity (fixture-object-field expect "gasUsed"))
                      (block-header-gas-used
                       (block-header child-block)))))))))))

(defun assert-eest-blockchain-engine-newpayload-v2-replay
    (case &key source-case)
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
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
                     (fixture-object-field payload-case "withdrawals"))))
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
             (child-state (state-db-copy parent-state))
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
                child-state
                transactions
                :expected-chain-id (chain-config-chain-id config)
                :header child-header
                :chain-config config
                :withdrawals withdrawals))
             (payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data child-block))))
        (engine-payload-store-put-block
         store parent-block :state-available-p t)
        (commit-state-db-to-chain-store
         store (block-hash parent-block) parent-state)
        (let* ((response
                 (engine-rpc-handle-request
                  (engine-fixture-payload-request 301 payload)
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
          (is (string= (fixture-object-field expect "stateRoot")
                       (hash32-to-hex
                        (block-header-state-root
                         (block-header child-block)))))
          (is (string= (fixture-object-field expect "receiptsRoot")
                       (hash32-to-hex
                        (block-header-receipts-root
                         (block-header child-block)))))
          (is (= (hex-to-quantity (fixture-object-field expect "gasUsed"))
                 (block-header-gas-used
                  (block-header child-block))))
          (when source-case
            (assert-eest-blockchain-post-state
             (chain-store-state-db store (block-hash child-block))
             source-case)))))))

(deftest optional-phase-a-eest-blockchain-replay-executes
  (dolist (source-case (load-optional-phase-a-eest-blockchain-replay-cases))
    (assert-eest-blockchain-engine-newpayload-v2-replay
     (materialize-eest-blockchain-engine-newpayload-v2-case source-case)
     :source-case source-case)))

(defun engine-fixture-balance-request (id address)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getBalance")
        (cons "params" (list (address-to-hex address) "latest"))))

(defun engine-fixture-code-request (id address)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getCode")
        (cons "params" (list (address-to-hex address) "latest"))))

(defun engine-fixture-storage-request (id address slot)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getStorageAt")
        (cons "params"
              (list (address-to-hex address)
                    (hash32-to-hex slot)
                    "latest"))))

(defun engine-fixture-proof-request
    (id address &key (storage-keys '()) (block-selector "latest"))
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getProof")
        (cons "params"
              (list (address-to-hex address)
                    (mapcar #'hash32-to-hex storage-keys)
                    block-selector))))

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

(defun engine-fixture-block-receipts-request (id tag)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getBlockReceipts")
        (cons "params" (list tag))))

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
          (list (cons "berlinBlock" "0x0")
                (cons "londonBlock" "0x0")
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
           (cons "codeAddress" "0x0000000000000000000000000000000000001002")
           (cons "code" "0x6001600055")
           (cons "storageAddress" "0x0000000000000000000000000000000000001002")
           (cons "storageKey"
                 "0x0000000000000000000000000000000000000000000000000000000000000000")
           (cons "storageValue"
                 "0x000000000000000000000000000000000000000000000000000000000000002a")
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
     (cons (cons "source" 42)
           (remove "source"
                   (engine-newpayload-v2-metadata-shape-test-fixture)
                   :key #'car
                   :test #'string=))))
  (signals error
    (validate-engine-newpayload-v2-fixture-metadata
     (engine-newpayload-v2-metadata-shape-test-fixture
      :eest-extra (list (cons "unexpectedPinnedField" t)))))
  (signals error
    (validate-engine-newpayload-v2-fixture-metadata
     (engine-newpayload-v2-metadata-shape-test-fixture
      :reference-extra (list (cons "besu" "test-besu")))))
  (signals error
    (let* ((fixture (engine-newpayload-v2-metadata-shape-test-fixture))
           (references (fixture-required-field fixture "referenceClients")))
      (validate-engine-newpayload-v2-fixture-metadata
       (cons (cons "referenceClients"
                   (cons (cons "geth" 42)
                         (remove "geth" references
                                 :key #'car
                                 :test #'string=)))
             (remove "referenceClients" fixture
                     :key #'car
                     :test #'string=)))))
  (signals error
    (let* ((fixture (engine-newpayload-v2-metadata-shape-test-fixture))
           (references (fixture-required-field fixture "referenceClients")))
      (validate-engine-newpayload-v2-fixture-metadata
       (cons (cons "referenceClients"
                   (cons (cons "reth" "")
                         (remove "reth" references
                                 :key #'car
                                 :test #'string=)))
             (remove "referenceClients" fixture
                     :key #'car
                     :test #'string=)))))
  (signals error
    (let* ((fixture (engine-newpayload-v2-metadata-shape-test-fixture))
           (references (fixture-required-field fixture "referenceClients")))
      (validate-engine-newpayload-v2-fixture-metadata
       (cons (cons "referenceClients"
                   (cons (cons "reth" 42)
                         (remove "reth" references
                                 :key #'car
                                 :test #'string=)))
             (remove "referenceClients" fixture
                     :key #'car
                     :test #'string=))))))

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
         (list (replace-field case "network" 42))))
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
                (list (cons "berlinBlock" "0x0")
                      (cons "londonBlock" "0x0")
                      (cons "shanghaiTime" "0x0")
                      (cons "unknownFork" "0x0"))))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "config"
                (replace-field
                 (fixture-required-field case "config")
                 "londonBlock"
                 42)))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "config"
                (replace-field
                 (fixture-required-field case "config")
                 "londonBlock"
                 "0")))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "config"
                (replace-field
                 (fixture-required-field case "config")
                 "londonBlock"
                 "0X0")))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "config"
                (replace-field
                 (fixture-required-field case "config")
                 "londonBlock"
                 "0x00")))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "parent"
                (replace-field
                 (fixture-required-field case "parent")
                 "feeRecipient"
                 42)))))
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
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "parent"
                (replace-field
                 (fixture-required-field case "parent")
                 "feeRecipient"
                 "0000000000000000000000000000000000000001")))))
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
        (let* ((parent (fixture-required-field case "parent"))
               (accounts (fixture-required-field parent "accounts"))
               (account (first accounts))
               (bad-account (replace-field account "code" "6000")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "parent"
                  (replace-field parent "accounts" (list bad-account)))))))
      (signals error
        (let* ((parent (fixture-required-field case "parent"))
               (accounts (fixture-required-field parent "accounts"))
               (account (first accounts))
               (bad-account (replace-field account "code" "0X6000")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "parent"
                  (replace-field parent "accounts" (list bad-account)))))))
      (signals error
        (let* ((parent (fixture-required-field case "parent"))
               (accounts (fixture-required-field parent "accounts"))
               (account (first accounts))
               (bad-account
                 (replace-field
                  account
                  "storage"
                  (list
                   (cons
                    "0x00000000000000000000000000000000000000000000000000000000000000aa"
                    "0x1")
                   (cons
                    "00000000000000000000000000000000000000000000000000000000000000AA"
                    "0x2")))))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "parent"
                  (replace-field parent "accounts" (list bad-account)))))))
      (signals error
        (let* ((parent (fixture-required-field case "parent"))
               (accounts (fixture-required-field parent "accounts"))
               (account (first accounts))
               (bad-account
                 (replace-field
                  account
                  "storage"
                  (list
                   (cons
                    "0x00000000000000000000000000000000000000000000000000000000000000aa"
                    "0X1")))))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "parent"
                  (replace-field parent "accounts" (list bad-account)))))))
      (signals error
        (let* ((parent (fixture-required-field case "parent"))
               (accounts (fixture-required-field parent "accounts"))
               (account (first accounts))
               (bad-account
                 (replace-field
                  account
                  "storage"
                  (list
                   (cons
                    "0x00000000000000000000000000000000000000000000000000000000000000aa"
                    "0x01")))))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "parent"
                  (replace-field parent "accounts" (list bad-account)))))))
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
               (raw (first (fixture-required-field payload "transactions"))))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "payload"
                  (replace-field
                   payload
                   "transactions"
                   (list (subseq raw 2))))))))
      (signals error
        (let* ((payload (fixture-required-field case "payload"))
               (raw (first (fixture-required-field payload "transactions"))))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "payload"
                  (replace-field
                   payload
                   "transactions"
                   (list (string-upcase raw))))))))
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
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "expect"
                (replace-field
                 (fixture-required-field case "expect")
                 "status"
                 42)))))
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
                  (replace-field expect "storageKey" 42))))))
      (signals error
        (let ((expect (fixture-required-field case "expect")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "expect"
                  (replace-field
                   expect
                   "storageKey"
                   "0000000000000000000000000000000000000000000000000000000000000000"))))))
      (signals error
        (let ((expect (fixture-required-field case "expect")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "expect"
                  (replace-field expect "code" "6001600055"))))))
      (signals error
        (let ((expect (fixture-required-field case "expect")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "expect"
                  (replace-field expect "withdrawalBalance" "0x1")))))))))

(deftest engine-newpayload-v2-smoke-coverage-validation
  (let* ((fixture
           (load-handwritten-fixture-file
            +engine-newpayload-v2-fixture-path+))
         (cases (handwritten-fixture-cases fixture)))
    (validate-engine-newpayload-v2-fixture-cases cases)
    (validate-engine-newpayload-v2-smoke-coverage cases)
    (signals error
      (let ((+engine-newpayload-v2-smoke-case-names+
              '("shanghai-one-transfer-with-withdrawal"
                "shanghai-dynamic-fee-transfer-with-withdrawal")))
        (validate-engine-newpayload-v2-smoke-coverage cases)))
    (signals error
      (let ((+engine-newpayload-v2-smoke-case-names+
              '("shanghai-one-transfer-with-withdrawal"
                "shanghai-one-transfer-with-withdrawal"
                "shanghai-contract-creation-with-withdrawal")))
        (validate-engine-newpayload-v2-smoke-coverage cases)))
    (signals error
      (let ((+engine-newpayload-v2-smoke-case-names+
              '("shanghai-one-transfer-with-withdrawal"
                "shanghai-dynamic-fee-transfer-with-withdrawal"
                "missing-engine-smoke-case")))
        (validate-engine-newpayload-v2-smoke-coverage cases)))))

(deftest engine-newpayload-v2-fixture-multi-transaction-receipts
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((case
             (select-engine-newpayload-v2-fixture-case
              +engine-newpayload-v2-fixture-path+
              "shanghai-two-legacy-transfers-with-withdrawal"))
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
           (transaction-hashes (mapcar #'transaction-hash transactions))
           (expected-cumulative-gas
             (fixture-object-field expect "cumulativeGasUsed"))
           (expected-receipt-types
             (fixture-object-field expect "receiptTypes"))
           (expected-receipt-statuses
             (fixture-object-field expect "receiptStatuses")))
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
             (child-state (state-db-copy parent-state))
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
                child-state
                transactions
                :expected-chain-id (chain-config-chain-id config)
                :header child-header
                :chain-config config
                :withdrawals withdrawals))
             (side-state (state-db-copy parent-state))
             (side-header
               (make-block-header
                :parent-hash (block-hash parent-block)
                :beneficiary fee-recipient
                :mix-hash
                (hash32-from-hex
                 "0x0200000000000000000000000000000000000000000000000000000000000000")
                :number (fixture-quantity-field payload-case "number")
                :gas-limit (fixture-quantity-field payload-case "gasLimit")
                :gas-used 0
                :timestamp
                (1+ (fixture-quantity-field payload-case "timestamp"))
                :base-fee-per-gas
                (fixture-quantity-field payload-case "baseFeePerGas")))
             (side-block
               (execute-signed-block
                side-state
                '()
                :expected-chain-id (chain-config-chain-id config)
                :header side-header
                :chain-config config
                :withdrawals withdrawals))
             (payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data child-block)))
             (side-payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data side-block))))
        (engine-payload-store-put-block
         store parent-block :state-available-p t)
        (commit-state-db-to-chain-store
         store (block-hash parent-block) parent-state)
        (is (string= +payload-status-valid+
                     (field
                      (field
                       (engine-rpc-handle-request
                        (engine-fixture-payload-request 201 payload)
                        store config
                        :import-function #'execute-and-commit-engine-payload)
                       "result")
                      "status")))
        (is (string= +payload-status-valid+
                     (field
                      (field
                       (engine-rpc-handle-request
                        (engine-fixture-payload-request 202 side-payload)
                        store config
                        :import-function #'execute-and-commit-engine-payload)
                       "result")
                      "status")))
        (engine-rpc-handle-request
         (engine-fixture-forkchoice-request
          203 (block-hash child-block)
          :safe (block-hash parent-block)
          :finalized (block-hash parent-block))
         store config)
        (let* ((block-receipts
                 (field (engine-rpc-handle-request
                         (engine-fixture-block-receipts-request
                          204 "latest")
                         store config)
                        "result"))
               (full-block
                 (field (engine-rpc-handle-request
                         (engine-fixture-block-by-number-request
                          205 "latest" t)
                         store config)
                        "result"))
               (full-transactions (field full-block "transactions")))
          (is (= 2 (length block-receipts)))
          (is (= 2 (length full-transactions)))
          (is (string= (quantity-to-hex 2)
                       (field
                        (engine-rpc-handle-request
                         (engine-fixture-transaction-count-by-number-request
                          206 "latest")
                         store config)
                        "result")))
          (is (string= (quantity-to-hex 2)
                       (field
                        (engine-rpc-handle-request
                         (engine-fixture-transaction-count-by-hash-request
                          207 (block-hash child-block))
                         store config)
                        "result")))
          (loop for tx in transactions
                for tx-hash in transaction-hashes
                for receipt in block-receipts
                for full-transaction in full-transactions
                for receipt-type in expected-receipt-types
                for receipt-status in expected-receipt-statuses
                for cumulative-gas in expected-cumulative-gas
                for index from 0
                do (let* ((receipt-by-hash
                            (field
                             (engine-rpc-handle-request
                              (engine-fixture-receipt-request
                               (+ 210 index) tx-hash)
                              store config)
                             "result"))
                          (raw-transaction
                            (field
                             (engine-rpc-handle-request
                              (engine-fixture-raw-transaction-by-block-number-request
                               (+ 220 index) "latest" index)
                              store config)
                             "result"))
                          (transaction-by-block
                            (field
                             (engine-rpc-handle-request
                              (engine-fixture-transaction-by-block-hash-request
                               (+ 230 index) (block-hash child-block) index)
                              store config)
                             "result"))
                          (transaction-by-hash
                            (field
                             (engine-rpc-handle-request
                              (engine-fixture-transaction-by-hash-request
                               (+ 240 index) tx-hash)
                              store config)
                             "result"))
                          (previous-cumulative
                            (if (zerop index)
                                0
                                (hex-to-quantity
                                 (nth (1- index)
                                      expected-cumulative-gas))))
                          (gas-used
                            (- (hex-to-quantity cumulative-gas)
                               previous-cumulative)))
                     (is (string= (hash32-to-hex tx-hash)
                                  (field receipt "transactionHash")))
                     (is (string= (field receipt "transactionHash")
                                  (field receipt-by-hash "transactionHash")))
                     (is (string= receipt-type (field receipt "type")))
                     (is (string= receipt-status (field receipt "status")))
                     (is (string= cumulative-gas
                                  (field receipt "cumulativeGasUsed")))
                     (is (string= (quantity-to-hex gas-used)
                                  (field receipt "gasUsed")))
                     (is (string= (quantity-to-hex index)
                                  (field receipt "transactionIndex")))
                     (is (string= (hash32-to-hex tx-hash)
                                  (field full-transaction "hash")))
                     (is (string= (quantity-to-hex index)
                                  (field full-transaction "transactionIndex")))
                     (is (string= (bytes-to-hex (transaction-encoding tx))
                                  raw-transaction))
                     (is (string= (field full-transaction "hash")
                                  (field transaction-by-block "hash")))
                     (is (string= (field full-transaction "hash")
                                  (field transaction-by-hash "hash"))))))
        (engine-rpc-handle-request
         (engine-fixture-forkchoice-request
          250 (block-hash side-block)
          :safe (block-hash parent-block)
          :finalized (block-hash parent-block))
         store config)
        (is (null
             (field (engine-rpc-handle-request
                     (engine-fixture-block-receipts-request 251 "latest")
                     store config)
                    "result")))
        (dolist (tx-hash transaction-hashes)
          (is (null
               (field (engine-rpc-handle-request
                       (engine-fixture-transaction-by-hash-request
                        252 tx-hash)
                       store config)
                      "result")))
          (is (null
               (field (engine-rpc-handle-request
                       (engine-fixture-receipt-request 253 tx-hash)
                       store config)
                      "result"))))))))

(deftest engine-newpayload-v2-fixture-executes-and-becomes-canonical
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (dolist (case-name +engine-newpayload-v2-smoke-case-names+)
      (let* ((case
               (select-engine-newpayload-v2-fixture-case
                +engine-newpayload-v2-fixture-path+
                case-name))
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
             (recipient
               (when (fixture-field-present-p expect "recipient")
                 (fixture-address-field expect "recipient")))
             (contract-address
               (when (fixture-field-present-p expect "contractAddress")
                 (fixture-address-field expect "contractAddress")))
             (value-address (or recipient contract-address))
             (value-balance-field
               (if recipient "recipientBalance" "contractBalance"))
             (withdrawal-recipient
               (fixture-address-field expect "withdrawalRecipient"))
             (code-address (fixture-address-field expect "codeAddress"))
             (storage-address (fixture-address-field expect "storageAddress"))
             (storage-key
               (hash32-from-hex (fixture-object-field expect "storageKey"))))
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
             (side-state (state-db-copy parent-state))
             (side-header
               (make-block-header
                :parent-hash (block-hash parent-block)
                :beneficiary fee-recipient
                :mix-hash
                (hash32-from-hex
                 "0x0100000000000000000000000000000000000000000000000000000000000000")
                :number (fixture-quantity-field payload-case "number")
                :gas-limit (fixture-quantity-field payload-case "gasLimit")
                :gas-used 0
                :timestamp
                (1+ (fixture-quantity-field payload-case "timestamp"))
                :base-fee-per-gas
                (fixture-quantity-field payload-case "baseFeePerGas")))
             (side-block
               (execute-signed-block
                side-state
                '()
                :expected-chain-id (chain-config-chain-id config)
                :header side-header
                :chain-config config
                :withdrawals withdrawals))
             (payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data child-block)))
             (side-payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data side-block)))
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
                  (fixture-object-field expect value-balance-field))
                 (chain-store-account-balance
                  store (block-hash child-block) value-address)))
          (is (= (hex-to-quantity
                  (fixture-object-field expect "withdrawalBalance"))
                 (chain-store-account-balance
                  store (block-hash child-block)
                  withdrawal-recipient))))
        (let* ((side-response
                 (engine-rpc-handle-request
                  (engine-fixture-payload-request 116 side-payload)
                  store config
                  :import-function #'execute-and-commit-engine-payload))
               (side-result (field side-response "result")))
          (is (string= (fixture-object-field expect "status")
                       (field side-result "status")))
          (is (string= (hash32-to-hex (block-hash side-block))
                       (field side-result "latestValidHash")))
          (is (engine-payload-store-known-block
               store (block-hash side-block)))
          (is (chain-store-state-available-p
               store (block-hash side-block))))
        (let* ((forkchoice-response
                 (engine-rpc-handle-request
                  (engine-fixture-forkchoice-request
                   102 (block-hash child-block)
                   :safe (block-hash parent-block)
                   :finalized (block-hash parent-block))
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
                  (engine-fixture-balance-request 104 value-address)
                  store config))
               (withdrawal-balance-response
                 (engine-rpc-handle-request
                  (engine-fixture-balance-request 105 withdrawal-recipient)
                  store config))
               (code-response
                 (engine-rpc-handle-request
                  (engine-fixture-code-request 106 code-address)
                  store config))
               (storage-response
                 (engine-rpc-handle-request
                  (engine-fixture-storage-request
                   107 storage-address storage-key)
                  store config))
               (proof-response
                 (engine-rpc-handle-request
                  (engine-fixture-proof-request 133 value-address)
                  store config))
               (proof
                 (field proof-response "result"))
               (expected-proof
                 (state-db-get-proof expected-state value-address nil))
               (decoded-proof
                 (state-proof-result-from-rpc-object proof))
               (latest-sender-proof-response
                 (engine-rpc-handle-request
                  (engine-fixture-proof-request 137 sender)
                  store config))
               (latest-sender-proof
                 (field latest-sender-proof-response "result"))
               (expected-sender-proof
                 (state-db-get-proof expected-state sender nil))
               (latest-sender-decoded-proof
                 (state-proof-result-from-rpc-object latest-sender-proof))
               (safe-sender-proof-response
                 (engine-rpc-handle-request
                  (engine-fixture-proof-request
                   138 sender :block-selector "safe")
                  store config))
               (safe-sender-proof
                 (field safe-sender-proof-response "result"))
               (parent-sender-proof
                 (state-db-get-proof parent-state sender nil))
               (safe-sender-decoded-proof
                 (state-proof-result-from-rpc-object safe-sender-proof))
               (finalized-sender-proof-response
                 (engine-rpc-handle-request
                  (engine-fixture-proof-request
                   139 sender :block-selector "finalized")
                  store config))
               (finalized-sender-proof
                 (field finalized-sender-proof-response "result"))
               (finalized-sender-decoded-proof
                 (state-proof-result-from-rpc-object finalized-sender-proof))
               (storage-proof-response
                 (engine-rpc-handle-request
                  (engine-fixture-proof-request
                   136 storage-address :storage-keys (list storage-key))
                  store config))
               (storage-proof
                 (field storage-proof-response "result"))
               (storage-proof-entry
                 (first (field storage-proof "storageProof")))
               (expected-storage-proof
                 (state-db-get-proof expected-state storage-address
                                     (list storage-key)))
               (expected-storage-entry
                 (first (state-proof-result-storage-proofs
                         expected-storage-proof)))
               (decoded-storage-proof
                 (state-proof-result-from-rpc-object storage-proof))
               (block-by-number-response
                 (engine-rpc-handle-request
                  (engine-fixture-block-by-number-request 108 "latest" nil)
                  store config))
               (block-by-number
                 (field block-by-number-response "result"))
               (safe-block-response
                 (engine-rpc-handle-request
                  (engine-fixture-block-by-number-request 130 "safe" nil)
                  store config))
               (safe-block
                 (field safe-block-response "result"))
               (finalized-block-response
                 (engine-rpc-handle-request
                  (engine-fixture-block-by-number-request 131 "finalized" nil)
                  store config))
               (finalized-block
                 (field finalized-block-response "result"))
               (full-block-response
                 (engine-rpc-handle-request
                  (engine-fixture-block-by-number-request 109 "latest" t)
                  store config))
               (full-block
                 (field full-block-response "result"))
               (full-block-transaction
                 (first (field full-block "transactions")))
               (block-by-hash-response
                 (engine-rpc-handle-request
                  (engine-fixture-block-by-hash-request
                   110 (block-hash child-block) nil)
                  store config))
               (block-by-hash
                 (field block-by-hash-response "result"))
               (side-block-by-hash-response
                 (engine-rpc-handle-request
                  (engine-fixture-block-by-hash-request
                   117 (block-hash side-block) nil)
                  store config))
               (side-block-by-hash
                 (field side-block-by-hash-response "result"))
               (transaction-count-by-number-response
                 (engine-rpc-handle-request
                  (engine-fixture-transaction-count-by-number-request
                   111 "latest")
                  store config))
               (transaction-count-by-hash-response
                 (engine-rpc-handle-request
                  (engine-fixture-transaction-count-by-hash-request
                   112 (block-hash child-block))
                  store config))
               (side-transaction-count-by-hash-response
                 (engine-rpc-handle-request
                  (engine-fixture-transaction-count-by-hash-request
                   118 (block-hash side-block))
                  store config))
               (raw-transaction-response
                 (engine-rpc-handle-request
                  (engine-fixture-raw-transaction-by-block-number-request
                   113 "latest" 0)
                  store config))
               (transaction-by-block-response
                 (engine-rpc-handle-request
                  (engine-fixture-transaction-by-block-hash-request
                   114 (block-hash child-block) 0)
                  store config))
               (transaction-by-block
                 (field transaction-by-block-response "result"))
               (transaction-by-hash-response
                 (engine-rpc-handle-request
                  (engine-fixture-transaction-by-hash-request
                   115 transaction-hash)
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
          (if (zerop (transaction-type (first transactions)))
              (is (string= (hash32-to-hex (receipt-list-root receipts))
                           (hash32-to-hex receipts-root)))
              (is (not
                   (string= (hash32-to-hex (receipt-list-root receipts))
                            (hash32-to-hex receipts-root)))))
          (is (string= (hash32-to-hex
                        (transaction-receipt-list-root
                         transactions
                         receipts))
                       (hash32-to-hex receipts-root)))
          (is (string= (fixture-object-field expect "receiptType")
                       (field receipt "type")))
          (is (string= (fixture-object-field expect "receiptStatus")
                       (field receipt "status")))
          (if recipient
              (progn
                (is (null (field receipt "contractAddress")))
                (is (string= (address-to-hex recipient)
                             (field receipt "to"))))
              (progn
                (is (string= (address-to-hex contract-address)
                             (field receipt "contractAddress")))
                (is (null (field receipt "to")))))
          (is (string= (quantity-to-hex
                        (hex-to-quantity
                         (fixture-object-field expect value-balance-field)))
                       (field recipient-balance-response "result")))
          (is (string= (quantity-to-hex
                        (hex-to-quantity
                         (fixture-object-field expect "withdrawalBalance")))
                       (field withdrawal-balance-response "result")))
          (is (string= (fixture-object-field expect "code")
                       (field code-response "result")))
          (is (string= (fixture-object-field expect "storageValue")
                       (field storage-response "result")))
          (is (string= (address-to-hex value-address)
                       (field proof "address")))
          (is (string= (quantity-to-hex
                        (hex-to-quantity
                         (fixture-object-field expect value-balance-field)))
                       (field proof "balance")))
          (is (string= (quantity-to-hex
                        (state-proof-result-nonce expected-proof))
                       (field proof "nonce")))
          (is (listp (field proof "accountProof")))
          (is (equal (mapcar #'bytes-to-hex
                             (state-proof-result-account-proof expected-proof))
                     (field proof "accountProof")))
          (is (null (field proof "storageProof")))
          (is (state-db-verify-proof
               (block-header-state-root (block-header child-block))
               decoded-proof))
          (is (string= (address-to-hex sender)
                       (field latest-sender-proof "address")))
          (is (string= (quantity-to-hex
                        (state-proof-result-balance expected-sender-proof))
                       (field latest-sender-proof "balance")))
          (is (string= (quantity-to-hex
                        (state-proof-result-nonce expected-sender-proof))
                       (field latest-sender-proof "nonce")))
          (is (equal (mapcar #'bytes-to-hex
                             (state-proof-result-account-proof
                              expected-sender-proof))
                     (field latest-sender-proof "accountProof")))
          (is (null (field latest-sender-proof "storageProof")))
          (is (state-db-verify-proof
               (block-header-state-root (block-header child-block))
               latest-sender-decoded-proof))
          (is (string= (address-to-hex sender)
                       (field safe-sender-proof "address")))
          (is (string= (quantity-to-hex
                        (state-proof-result-balance parent-sender-proof))
                       (field safe-sender-proof "balance")))
          (is (string= (quantity-to-hex
                        (state-proof-result-nonce parent-sender-proof))
                       (field safe-sender-proof "nonce")))
          (is (equal (mapcar #'bytes-to-hex
                             (state-proof-result-account-proof
                              parent-sender-proof))
                     (field safe-sender-proof "accountProof")))
          (is (null (field safe-sender-proof "storageProof")))
          (is (state-db-verify-proof
               (block-header-state-root (block-header parent-block))
               safe-sender-decoded-proof))
          (is (string= (address-to-hex sender)
                       (field finalized-sender-proof "address")))
          (is (string= (field safe-sender-proof "balance")
                       (field finalized-sender-proof "balance")))
          (is (string= (field safe-sender-proof "nonce")
                       (field finalized-sender-proof "nonce")))
          (is (equal (field safe-sender-proof "accountProof")
                     (field finalized-sender-proof "accountProof")))
          (is (null (field finalized-sender-proof "storageProof")))
          (is (state-db-verify-proof
               (block-header-state-root (block-header parent-block))
               finalized-sender-decoded-proof))
          (is (not (string= (field latest-sender-proof "nonce")
                            (field safe-sender-proof "nonce"))))
          (is (string= (address-to-hex storage-address)
                       (field storage-proof "address")))
          (is (equal (mapcar #'bytes-to-hex
                             (state-proof-result-account-proof
                              expected-storage-proof))
                     (field storage-proof "accountProof")))
          (is (= 1 (length (field storage-proof "storageProof"))))
          (is (string= (hash32-to-hex storage-key)
                       (field storage-proof-entry "key")))
          (is (string= (quantity-to-hex
                        (state-storage-proof-value expected-storage-entry))
                       (field storage-proof-entry "value")))
          (is (equal (mapcar #'bytes-to-hex
                             (state-storage-proof-proof
                              expected-storage-entry))
                     (field storage-proof-entry "proof")))
          (is (state-db-verify-proof
               (block-header-state-root (block-header child-block))
               decoded-storage-proof))
          (is (string= (hash32-to-hex (block-hash child-block))
                       (field block-by-number "hash")))
          (is (string= (hash32-to-hex (block-hash parent-block))
                       (field safe-block "hash")))
          (is (string= (hash32-to-hex (block-hash parent-block))
                       (field finalized-block "hash")))
          (is (string= (quantity-to-hex
                        (block-header-number (block-header child-block)))
                       (field block-by-number "number")))
          (is (equal (list (hash32-to-hex transaction-hash))
                     (field block-by-number "transactions")))
          (is (string= (field block-by-number "hash")
                       (field block-by-hash "hash")))
          (is (string= (hash32-to-hex (block-hash side-block))
                       (field side-block-by-hash "hash")))
          (is (string= (quantity-to-hex
                        (block-header-number (block-header side-block)))
                       (field side-block-by-hash "number")))
          (is (not (string= (field block-by-number "hash")
                            (field side-block-by-hash "hash"))))
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
          (if recipient
              (is (string= (address-to-hex recipient)
                           (field full-block-transaction "to")))
              (is (null (field full-block-transaction "to"))))
          (is (string= (quantity-to-hex 1)
                       (field transaction-count-by-number-response "result")))
          (is (string= (quantity-to-hex 1)
                       (field transaction-count-by-hash-response "result")))
          (is (string= (quantity-to-hex 0)
                       (field side-transaction-count-by-hash-response "result")))
          (is (string= (bytes-to-hex
                        (transaction-encoding (first transactions)))
                       (field raw-transaction-response "result")))
          (is (string= (field block-by-number "hash")
                       (field transaction-by-block "blockHash")))
          (is (string= (hash32-to-hex transaction-hash)
                       (field transaction-by-block "hash")))
          (is (string= (address-to-hex sender)
                       (field transaction-by-block "from")))
          (if recipient
              (is (string= (address-to-hex recipient)
                           (field transaction-by-block "to")))
              (is (null (field transaction-by-block "to"))))
          (is (string= (field transaction-by-block "hash")
                       (field transaction-by-hash "hash")))
          (is (string= (field transaction-by-block "blockHash")
                       (field transaction-by-hash "blockHash")))
          (let* ((side-forkchoice-response
                   (engine-rpc-handle-request
                    (engine-fixture-forkchoice-request
                     119 (block-hash side-block)
                     :safe (block-hash parent-block)
                     :finalized (block-hash parent-block))
                    store config))
                 (side-forkchoice-result
                   (field side-forkchoice-response "result"))
                 (side-payload-status
                   (field side-forkchoice-result "payloadStatus"))
                 (side-latest-response
                   (engine-rpc-handle-request
                    (engine-fixture-block-by-number-request 120 "latest" nil)
                    store config))
                 (side-latest
                   (field side-latest-response "result"))
                 (side-safe-response
                   (engine-rpc-handle-request
                    (engine-fixture-block-by-number-request 132 "safe" nil)
                    store config))
                 (side-safe
                   (field side-safe-response "result"))
                 (side-latest-count-response
                   (engine-rpc-handle-request
                    (engine-fixture-transaction-count-by-number-request
                     121 "latest")
                    store config))
                 (side-latest-raw-response
                   (engine-rpc-handle-request
                    (engine-fixture-raw-transaction-by-block-number-request
                     122 "latest" 0)
                    store config))
                 (side-transaction-by-hash-response
                   (engine-rpc-handle-request
                    (engine-fixture-transaction-by-hash-request
                     123 transaction-hash)
                    store config))
                 (side-receipt-response
                   (engine-rpc-handle-request
                    (engine-fixture-receipt-request 124 transaction-hash)
                    store config))
                 (side-latest-proof-response
                   (engine-rpc-handle-request
                    (engine-fixture-proof-request 134 value-address)
                    store config))
                 (side-latest-proof
                   (field side-latest-proof-response "result"))
                 (side-expected-proof
                   (state-db-get-proof side-state value-address nil))
                 (side-decoded-proof
                   (state-proof-result-from-rpc-object side-latest-proof))
                 (child-proof-by-hash-response
                   (engine-rpc-handle-request
                    (engine-fixture-proof-request
                     135 value-address
                     :block-selector (hash32-to-hex (block-hash child-block)))
                    store config))
                 (child-proof-by-hash
                   (field child-proof-by-hash-response "result"))
                 (child-by-hash-after-side-response
                   (engine-rpc-handle-request
                    (engine-fixture-block-by-hash-request
                     125 (block-hash child-block) nil)
                    store config))
                 (child-by-hash-after-side
                   (field child-by-hash-after-side-response "result")))
            (is (string= +payload-status-valid+
                         (field side-payload-status "status")))
            (is (string= (hash32-to-hex (block-hash side-block))
                         (hash32-to-hex
                          (chain-store-canonical-hash
                           store
                           (block-header-number
                            (block-header side-block))))))
            (is (string= (hash32-to-hex (block-hash side-block))
                         (field side-latest "hash")))
            (is (string= (hash32-to-hex (block-hash parent-block))
                         (field side-safe "hash")))
            (is (string= (quantity-to-hex 0)
                         (field side-latest-count-response "result")))
            (is (null (field side-latest-raw-response "result")))
            (is (null (field side-transaction-by-hash-response "result")))
            (is (null (field side-receipt-response "result")))
            (is (string= (quantity-to-hex
                          (state-proof-result-balance side-expected-proof))
                         (field side-latest-proof "balance")))
            (is (equal (mapcar #'bytes-to-hex
                               (state-proof-result-account-proof
                                side-expected-proof))
                       (field side-latest-proof "accountProof")))
            (is (state-db-verify-proof
                 (block-header-state-root (block-header side-block))
                 side-decoded-proof))
            (is (string= (field proof "balance")
                         (field child-proof-by-hash "balance")))
            (is (equal (field proof "accountProof")
                       (field child-proof-by-hash "accountProof")))
            (is (string= (hash32-to-hex (block-hash child-block))
                         (field child-by-hash-after-side "hash"))))
          (let* ((child-forkchoice-response
                   (engine-rpc-handle-request
                    (engine-fixture-forkchoice-request
                     126 (block-hash child-block)
                     :safe (block-hash parent-block)
                     :finalized (block-hash parent-block))
                    store config))
                 (child-forkchoice-result
                   (field child-forkchoice-response "result"))
                 (child-payload-status
                   (field child-forkchoice-result "payloadStatus"))
                 (child-latest-response
                   (engine-rpc-handle-request
                    (engine-fixture-block-by-number-request 127 "latest" nil)
                    store config))
                 (child-latest
                   (field child-latest-response "result"))
                 (child-transaction-by-hash-response
                   (engine-rpc-handle-request
                    (engine-fixture-transaction-by-hash-request
                     128 transaction-hash)
                    store config))
                 (child-transaction-by-hash
                   (field child-transaction-by-hash-response "result"))
                 (child-receipt-response
                   (engine-rpc-handle-request
                    (engine-fixture-receipt-request 129 transaction-hash)
                    store config))
                 (child-receipt
                   (field child-receipt-response "result")))
            (is (string= +payload-status-valid+
                         (field child-payload-status "status")))
            (is (string= (hash32-to-hex (block-hash child-block))
                         (hash32-to-hex
                          (chain-store-canonical-hash
                           store
                           (block-header-number
                            (block-header child-block))))))
            (is (string= (hash32-to-hex (block-hash child-block))
                         (field child-latest "hash")))
            (is (string= (hash32-to-hex transaction-hash)
                         (field child-transaction-by-hash "hash")))
            (is (string= (field child-latest "hash")
                         (field child-transaction-by-hash "blockHash")))
            (is (string= (fixture-object-field expect "receiptStatus")
                         (field child-receipt "status"))))))))))
