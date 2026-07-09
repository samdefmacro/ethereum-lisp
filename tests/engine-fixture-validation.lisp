(in-package #:ethereum-lisp.test)

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
    (when (fixture-field-present-p expect "logAddress")
      (validate-engine-fixture-address-field expect "logAddress" label))
    (dolist (field '("senderNonce"
                     "senderBalance"
                     "withdrawalBalance"
                     "receiptType"
                     "receiptStatus"))
      (validate-engine-fixture-quantity-field expect field label))
    (when (fixture-field-present-p expect "logCount")
      (validate-engine-fixture-quantity-field expect "logCount" label))
    (dolist (field '("recipientBalance" "contractBalance"))
      (when (fixture-field-present-p expect field)
        (validate-engine-fixture-quantity-field expect field label)))
    (validate-engine-fixture-code-field expect "code" label)
    (validate-engine-fixture-hash-field expect "storageKey" label)
    (validate-engine-fixture-hash-field expect "storageValue" label)
    (when (fixture-field-present-p expect "logTopic")
      (validate-engine-fixture-hash-field expect "logTopic" label))
    (when (fixture-field-present-p expect "logData")
      (validate-engine-fixture-hash-field expect "logData" label))
    (when (some (lambda (field)
                  (fixture-field-present-p expect field))
                '("logAddress" "logTopic" "logData" "logCount"))
      (unless (and (fixture-field-present-p expect "logAddress")
                   (fixture-field-present-p expect "logTopic")
                   (fixture-field-present-p expect "logData")
                   (fixture-field-present-p expect "logCount"))
        (error "~A log expectations must provide logAddress, logTopic, logData, and logCount"
               label)))
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
    (if (< 1 (length raw-transactions))
        (let ((transactions
                (mapcar (lambda (raw)
                          (transaction-from-encoding (hex-to-bytes raw)))
                        raw-transactions)))
          (unless (every (lambda (transaction)
                           (and (transaction-to transaction)
                                (zerop (transaction-type transaction))))
                         transactions)
            (error "Engine newPayloadV2 smoke case ~A has unsupported multi-transaction coverage shape"
                   (fixture-required-field case "name")))
          :multi-legacy-transfer)
        (let ((transaction (transaction-from-encoding
                            (hex-to-bytes (first raw-transactions)))))
          (cond
            ((fixture-field-present-p
              (fixture-required-field case "expect")
              "logAddress")
             :log-producing-call)
            ((string= (fixture-required-field case "name")
                      "shanghai-internal-create2-with-withdrawal")
             :internal-create2-call)
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
                    (transaction-type transaction))))))))

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

