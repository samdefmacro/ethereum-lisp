(in-package #:ethereum-lisp.test)

(defparameter +evm-state-fixture-path+
  "tests/fixtures/execution-spec-tests/evm-state.json")

(defparameter +evm-state-fixture-format+
  "ethereum-lisp/evm-state-fixture-v1")

(defparameter +evm-state-fixture-top-level-fields+
  '("format" "source" "executionSpecTests" "cases"))

(defparameter +evm-state-fixture-case-fields+
  '("name" "tags" "env" "pre" "transaction" "expect"))

(defparameter +evm-state-fixture-env-fields+
  '("fork" "chainId" "number" "timestamp" "coinbase"))

(defparameter +evm-state-fixture-account-fields+
  '("nonce" "balance" "code" "storage"))

(defparameter +evm-state-fixture-transaction-fields+
  '("from" "to" "nonce" "gasPrice" "gasLimit" "value" "data"
    "type" "chainId" "accessList"))

(defparameter +evm-state-fixture-access-list-entry-fields+
  '("address" "storageKeys"))

(defparameter +evm-state-fixture-expect-fields+
  '("stateRoot" "post" "receipt"))

(defparameter +evm-state-fixture-receipt-fields+
  '("status" "cumulativeGasUsed" "logsBloom" "logs"))

(defparameter +evm-state-fixture-log-fields+
  '("address" "topics" "data"))

(defparameter +evm-state-fixture-known-tags+
  '("legacy-call" "nested-call" "revert" "returndata" "code-resolution"
    "delegated-code" "error"
    "staticcall" "read-only" "value-transfer" "access-list"
    "gas-forwarding" "memory-expansion" "sstore" "log" "post-state-root"))

(defparameter +evm-state-fixture-required-tags+
  '("legacy-call" "sstore" "log" "post-state-root"))

(defparameter +evm-state-fixture-required-case-names+
  '("legacy-call-sstore-log1-london"
    "nested-call-revert-returndata-london"
    "staticcall-readonly-sstore-fails-london"
    "nested-call-value-transfer-london"
    "call-resolves-delegated-code-london"
    "access-list-call-prewarms-callee-london"
    "call-forwards-stack-gas-london"
    "call-value-stipend-gas-london"
    "staticcall-memory-expansion-before-child-gas-london"
    "call-error-clears-returndata-london"))

(defun validate-evm-state-fixture-metadata (fixture)
  (validate-fixture-object-fields
   fixture
   +evm-state-fixture-top-level-fields+
   "EVM state fixture")
  (validate-fixture-format fixture +evm-state-fixture-format+)
  (evm-state-fixture-non-empty-string
   (fixture-required-field fixture "source")
   "EVM state fixture source")
  (validate-fixture-pinned-eest-source fixture))

(defun evm-state-fixture-quantity (object name)
  (evm-state-fixture-quantity-string
   (fixture-required-field object name)
   (format nil "EVM state fixture ~A" name)))

(defun evm-state-fixture-quantity-string (value label)
  (unless (stringp value)
    (error "~A must be a hex quantity string" label))
  (let ((quantity (hex-to-quantity value)))
    (unless (string= value (string-downcase (quantity-to-hex quantity)))
      (error "~A must be a canonical hex quantity" label))
    quantity))

(defun evm-state-fixture-hex-bytes (value label)
  (unless (stringp value)
    (error "~A must be a hex string" label))
  (let ((bytes (hex-to-bytes value)))
    (unless (string= value (bytes-to-hex bytes))
      (error "~A must be canonical lowercase 0x-prefixed hex" label))
    bytes))

(defun evm-state-fixture-fixed-hex-bytes (value size label)
  (let ((bytes (evm-state-fixture-hex-bytes value label)))
    (unless (= (length bytes) size)
      (error "~A must be exactly ~D bytes" label size))))

(defun evm-state-fixture-address (value label)
  (unless (stringp value)
    (error "~A must be an address hex string" label))
  (let ((address (address-from-hex value)))
    (unless (string= value (address-to-hex address))
      (error "~A must be canonical lowercase 0x-prefixed address hex" label))
    address))

(defun evm-state-fixture-hash (value label)
  (unless (stringp value)
    (error "~A must be a hash hex string" label))
  (let ((hash (hash32-from-hex value)))
    (unless (string= value (hash32-to-hex hash))
      (error "~A must be canonical lowercase 0x-prefixed hash hex" label))
    hash))

(defun evm-state-fixture-non-empty-string (value label)
  (unless (stringp value)
    (error "~A must be a string" label))
  (when (blank-string-p value)
    (error "~A must be present" label))
  value)

(defun validate-evm-state-fixture-storage-shape (storage label)
  (unless (fixture-json-object-p storage)
    (error "~A storage must be a JSON object" label))
  (let ((seen-slots (make-hash-table :test 'equal)))
    (dolist (entry (ethereum-lisp.json:json-object-entries storage label))
      (unless (consp entry)
        (error "~A storage entries must be JSON object fields" label))
      (let* ((slot (car entry))
             (slot-id
               (hash32-to-hex
                (evm-state-fixture-hash
                 slot
                 (format nil "~A storage slot" label)))))
        (when (gethash slot-id seen-slots)
          (error "~A storage has duplicate slot ~A" label slot))
        (setf (gethash slot-id seen-slots) t)
        (evm-state-fixture-quantity-string
         (cdr entry)
         (format nil "~A storage value" label))))))

(defun validate-evm-state-fixture-account-shape (address account label)
  (evm-state-fixture-address address (format nil "~A address" label))
  (validate-fixture-object-fields
   account
   +evm-state-fixture-account-fields+
   label)
  (evm-state-fixture-quantity account "nonce")
  (evm-state-fixture-quantity account "balance")
  (evm-state-fixture-hex-bytes
   (fixture-required-field account "code")
   (format nil "~A code" label))
  (validate-evm-state-fixture-storage-shape
   (fixture-required-field account "storage")
   label))

(defun validate-evm-state-fixture-accounts-shape (accounts label)
  (unless (fixture-json-object-p accounts)
    (error "~A must be a JSON object" label))
  (let ((seen-addresses (make-hash-table :test 'equal)))
    (dolist (entry (ethereum-lisp.json:json-object-entries accounts label))
      (unless (consp entry)
        (error "~A entries must be JSON object fields" label))
      (let* ((address (car entry))
             (address-id
               (address-to-hex
                (evm-state-fixture-address
                 address
                 (format nil "~A account address" label)))))
        (when (gethash address-id seen-addresses)
          (error "~A has duplicate address ~A" label address))
        (setf (gethash address-id seen-addresses) t)
        (validate-evm-state-fixture-account-shape
         address
         (cdr entry)
         (format nil "~A account ~A" label address))))))

(defun validate-evm-state-fixture-env-shape (env)
  (validate-fixture-object-fields
   env
   +evm-state-fixture-env-fields+
   "EVM state fixture env")
  (let ((fork (fixture-required-field env "fork")))
    (unless (stringp fork)
      (error "EVM state fixture env fork must be a string"))
    (unless (string= "London" fork)
      (error "EVM state fixture currently supports only London fork vectors")))
  (dolist (field '("chainId" "number" "timestamp"))
    (evm-state-fixture-quantity env field))
  (evm-state-fixture-address
   (fixture-required-field env "coinbase")
   "EVM state fixture env coinbase"))

(defun validate-evm-state-fixture-transaction-shape (transaction)
  (validate-fixture-object-fields
   transaction
   +evm-state-fixture-transaction-fields+
   "EVM state fixture transaction")
  (evm-state-fixture-address
   (fixture-required-field transaction "from")
   "EVM state fixture transaction from")
  (evm-state-fixture-address
   (fixture-required-field transaction "to")
   "EVM state fixture transaction to")
  (dolist (field '("nonce" "gasPrice" "gasLimit" "value"))
    (evm-state-fixture-quantity transaction field))
  (evm-state-fixture-hex-bytes
   (fixture-required-field transaction "data")
   "EVM state fixture transaction data")
  (let ((type (or (fixture-object-field transaction "type") "legacy")))
    (unless (stringp type)
      (error "EVM state fixture transaction type must be a string"))
    (unless (member type '("legacy" "access-list") :test #'string=)
      (error "EVM state fixture transaction has unsupported type ~A" type))
    (if (string= type "access-list")
        (progn
          (evm-state-fixture-quantity transaction "chainId")
          (validate-evm-state-fixture-access-list-shape
           (fixture-required-field transaction "accessList")))
        (when (fixture-field-present-p transaction "accessList")
          (error "EVM state fixture legacy transaction must not include accessList")))))

(defun validate-evm-state-fixture-access-list-shape (access-list)
  (unless (ethereum-lisp.json:json-array-p access-list)
    (error "EVM state fixture accessList must be a JSON array"))
  (let ((seen-addresses (make-hash-table :test 'equal)))
    (dolist (entry (ethereum-lisp.json:json-array-values access-list))
      (validate-fixture-object-fields
       entry
       +evm-state-fixture-access-list-entry-fields+
       "EVM state fixture access list entry")
      (let* ((address (fixture-required-field entry "address"))
             (address-id
               (address-to-hex
                (evm-state-fixture-address
                 address
                 "EVM state fixture access list address"))))
        (when (gethash address-id seen-addresses)
          (error "EVM state fixture accessList has duplicate address ~A"
                 address))
        (setf (gethash address-id seen-addresses) t))
      (let ((keys (fixture-required-field entry "storageKeys"))
            (seen-keys (make-hash-table :test 'equal)))
        (unless (ethereum-lisp.json:json-array-p keys)
          (error "EVM state fixture access list storageKeys must be a JSON array"))
        (dolist (key (ethereum-lisp.json:json-array-values keys))
          (let ((key-id
                  (hash32-to-hex
                   (evm-state-fixture-hash
                    key
                    "EVM state fixture access list storage key"))))
            (when (gethash key-id seen-keys)
              (error "EVM state fixture access list entry has duplicate storage key ~A"
                     key))
            (setf (gethash key-id seen-keys) t)))))))

(defun validate-evm-state-fixture-log-shape (log)
  (validate-fixture-object-fields
   log
   +evm-state-fixture-log-fields+
   "EVM state fixture expected log")
  (evm-state-fixture-address
   (fixture-required-field log "address")
   "EVM state fixture expected log address")
  (let ((topics (fixture-required-field log "topics")))
    (unless (listp topics)
      (error "EVM state fixture expected log topics must be a JSON array"))
    (dolist (topic topics)
      (evm-state-fixture-hash
       topic
       "EVM state fixture expected log topic")))
  (evm-state-fixture-hex-bytes
   (fixture-required-field log "data")
   "EVM state fixture expected log data"))

(defun validate-evm-state-fixture-receipt-shape (receipt)
  (validate-fixture-object-fields
   receipt
   +evm-state-fixture-receipt-fields+
   "EVM state fixture expected receipt")
  (let ((status (evm-state-fixture-quantity receipt "status")))
    (unless (or (= status 0) (= status 1))
      (error "EVM state fixture expected receipt status must be 0x0 or 0x1")))
  (evm-state-fixture-quantity receipt "cumulativeGasUsed")
  (evm-state-fixture-fixed-hex-bytes
   (fixture-required-field receipt "logsBloom")
   256
   "EVM state fixture expected receipt logsBloom")
  (let ((logs (fixture-required-field receipt "logs")))
    (unless (listp logs)
      (error "EVM state fixture expected receipt logs must be a JSON array"))
    (dolist (log logs)
      (validate-evm-state-fixture-log-shape log))))

(defun validate-evm-state-fixture-expect-shape (expect)
  (validate-fixture-object-fields
   expect
   +evm-state-fixture-expect-fields+
   "EVM state fixture expect")
  (evm-state-fixture-hash
   (fixture-required-field expect "stateRoot")
   "EVM state fixture expected stateRoot")
  (validate-evm-state-fixture-accounts-shape
   (fixture-required-field expect "post")
   "EVM state fixture expected post")
  (validate-evm-state-fixture-receipt-shape
   (fixture-required-field expect "receipt")))

(defun validate-evm-state-fixture-case-tags (case seen-tags)
  (let ((name (fixture-object-field case "name"))
        (tags (fixture-object-field case "tags")))
    (unless (and (listp tags) tags)
      (error "EVM state fixture case ~A must include non-empty tags" name))
    (let ((case-tags (make-hash-table :test 'equal)))
      (dolist (tag tags)
        (when (gethash tag case-tags)
          (error "EVM state fixture case ~A has duplicate tag ~A" name tag))
        (setf (gethash tag case-tags) t)
        (unless (and (stringp tag)
                     (member tag +evm-state-fixture-known-tags+
                             :test #'string=))
          (error "EVM state fixture case ~A has unknown tag ~A" name tag))
        (setf (gethash tag seen-tags) t)))))

(defun validate-evm-state-fixture-case-shape (case)
  (validate-fixture-object-fields
   case
   +evm-state-fixture-case-fields+
   "EVM state fixture case")
  (evm-state-fixture-non-empty-string
   (fixture-required-field case "name")
   "EVM state fixture case name")
  (validate-evm-state-fixture-case-tags case (make-hash-table :test 'equal))
  (validate-evm-state-fixture-env-shape
   (fixture-required-field case "env"))
  (validate-evm-state-fixture-accounts-shape
   (fixture-required-field case "pre")
   "EVM state fixture pre")
  (validate-evm-state-fixture-transaction-shape
   (fixture-required-field case "transaction"))
  (validate-evm-state-fixture-expect-shape
   (fixture-required-field case "expect")))

(defun validate-evm-state-fixture-cases (cases)
  (unless (listp cases)
    (error "EVM state fixture cases must be a JSON array"))
  (let ((seen-names (make-hash-table :test 'equal))
        (seen-tags (make-hash-table :test 'equal)))
    (dolist (case cases)
      (unless (listp case)
        (error "EVM state fixture case must be a JSON object"))
      (let ((name (fixture-object-field case "name")))
        (evm-state-fixture-non-empty-string
         name
         "EVM state fixture case name")
        (when (gethash name seen-names)
          (error "Duplicate EVM state fixture case name: ~A" name))
        (setf (gethash name seen-names) t))
      (validate-evm-state-fixture-case-tags case seen-tags)
      (validate-evm-state-fixture-case-shape case))
    (dolist (tag +evm-state-fixture-required-tags+)
      (unless (gethash tag seen-tags)
        (error "EVM state fixture is missing required coverage tag ~A" tag)))))

(defun validate-evm-state-fixture-required-case-names (cases)
  (let ((case-by-name (make-hash-table :test 'equal))
        (seen-required-names (make-hash-table :test 'equal)))
    (dolist (case cases)
      (setf (gethash (fixture-required-field case "name") case-by-name)
            case))
    (dolist (name +evm-state-fixture-required-case-names+)
      (when (gethash name seen-required-names)
        (error "EVM state fixture required case list has duplicate name ~A"
               name))
      (setf (gethash name seen-required-names) t)
      (unless (gethash name case-by-name)
        (error "EVM state fixture is missing required seed case ~A"
               name)))))

(defun apply-evm-state-fixture-account (state address-hex account)
  (let ((address (address-from-hex address-hex)))
    (state-db-set-account
     state
     address
     (make-state-account
      :nonce (evm-state-fixture-quantity account "nonce")
      :balance (evm-state-fixture-quantity account "balance")))
    (state-db-set-code state address (hex-to-bytes (fixture-object-field account "code")))
    (dolist (entry
             (ethereum-lisp.json:json-object-entries
              (fixture-object-field account "storage")
              "EVM state fixture account storage"))
      (state-db-set-storage
       state
       address
       (hash32-from-hex (car entry))
       (hex-to-quantity (cdr entry))))))

(defun eest-state-test-storage-key (value)
  (let* ((quantity (eest-state-test-quantity-string
                    value
                    "EEST state test storage key"))
         (bytes (integer-to-minimal-bytes quantity)))
    (when (> (length bytes) 32)
      (error "EEST state test storage key exceeds 32 bytes: ~A" value))
    (let ((padded (make-byte-vector 32)))
      (replace padded bytes :start1 (- 32 (length bytes)))
      (make-hash32 padded))))

(defun apply-eest-state-test-account (state address-hex account)
  (let ((address (address-from-hex address-hex)))
    (state-db-set-account
     state
     address
     (make-state-account
      :nonce (eest-state-test-quantity-string
              (fixture-required-field account "nonce")
              "EEST state test account nonce")
      :balance (eest-state-test-quantity-string
                (fixture-required-field account "balance")
                "EEST state test account balance")))
    (state-db-set-code state address (hex-to-bytes (fixture-object-field account "code")))
    (dolist (entry
             (ethereum-lisp.json:json-object-entries
              (fixture-object-field account "storage")
              "EEST state test account storage"))
      (state-db-set-storage
       state
       address
       (eest-state-test-storage-key (car entry))
       (hex-to-quantity (cdr entry))))))

(defun evm-state-fixture-pre-state (case)
  (let ((state (make-state-db)))
    (dolist (entry (fixture-object-field case "pre"))
      (apply-evm-state-fixture-account state (car entry) (cdr entry)))
    state))

(defun evm-state-fixture-chain-rules (env)
  (declare (ignore env))
  (make-chain-rules :chain-id 1
                    :homestead-p t
                    :eip150-p t
                    :eip155-p t
                    :eip158-p t
                    :byzantium-p t
                    :constantinople-p t
                    :petersburg-p t
                    :istanbul-p t
                    :berlin-p t
                    :london-p t))

(defun evm-state-fixture-access-list (object)
  (mapcar
   (lambda (entry)
     (make-access-list-entry
      :address (address-from-hex (fixture-object-field entry "address"))
      :storage-keys
      (mapcar #'hash32-from-hex
              (fixture-object-field entry "storageKeys"))))
   (fixture-object-field object "accessList")))

(defun evm-state-fixture-transaction (object)
  (let ((type (or (fixture-object-field object "type") "legacy")))
    (cond
      ((string= type "legacy")
       (make-legacy-transaction
        :nonce (evm-state-fixture-quantity object "nonce")
        :gas-price (evm-state-fixture-quantity object "gasPrice")
        :gas-limit (evm-state-fixture-quantity object "gasLimit")
        :to (address-from-hex (fixture-object-field object "to"))
        :value (evm-state-fixture-quantity object "value")
        :data (hex-to-bytes (fixture-object-field object "data"))))
      ((string= type "access-list")
       (make-access-list-transaction
        :chain-id (evm-state-fixture-quantity object "chainId")
        :nonce (evm-state-fixture-quantity object "nonce")
        :gas-price (evm-state-fixture-quantity object "gasPrice")
        :gas-limit (evm-state-fixture-quantity object "gasLimit")
        :to (address-from-hex (fixture-object-field object "to"))
        :value (evm-state-fixture-quantity object "value")
        :data (hex-to-bytes (fixture-object-field object "data"))
        :access-list (evm-state-fixture-access-list object)))
      (t
       (error "Unsupported EVM state fixture transaction type ~A" type)))))

(defun execute-evm-state-fixture-case (case)
  (let* ((state (evm-state-fixture-pre-state case))
         (env (fixture-object-field case "env"))
         (tx-object (fixture-object-field case "transaction"))
         (sender (address-from-hex (fixture-object-field tx-object "from")))
         (tx (evm-state-fixture-transaction tx-object))
         (receipt
           (apply-message
            state sender tx
            :chain-id (evm-state-fixture-quantity env "chainId")
            :chain-rules (evm-state-fixture-chain-rules env)
            :coinbase (address-from-hex (fixture-object-field env "coinbase"))
            :block-number (evm-state-fixture-quantity env "number")
            :timestamp (evm-state-fixture-quantity env "timestamp"))))
    (values state receipt)))

(defun eest-state-test-post-entries (case fork)
  (let* ((post (fixture-required-field
                (fixture-required-field case "fixture")
                "post"))
         (entries (fixture-required-field post fork)))
    (unless (and (listp entries) entries)
      (error "EEST state test case ~A must have non-empty ~A post entries"
             (fixture-required-field case "name")
             fork))
    entries))

(defun eest-state-test-indexed-transaction-value
    (transaction field indexes index-name)
  (let* ((values (fixture-required-field transaction field))
         (index (fixture-required-field indexes index-name)))
    (unless (and (integerp index)
                 (<= 0 index)
                 (< index (length values)))
      (error "EEST state transaction index ~A is out of range" index-name))
    (nth index values)))

(defun eest-state-test-quantity-string (value label)
  (unless (stringp value)
    (error "~A must be a hex quantity string" label))
  (hex-to-quantity value))

(defun eest-state-test-access-list-entry (entry)
  (make-access-list-entry
   :address (address-from-hex (fixture-required-field entry "address"))
   :storage-keys
   (mapcar #'hash32-from-hex
           (fixture-required-field entry "storageKeys"))))

(defun eest-state-test-selected-access-list (transaction indexes)
  (when (fixture-field-present-p transaction "accessLists")
    (let ((entries
            (if (fixture-field-present-p indexes "accessList")
                (eest-state-test-indexed-transaction-value
                 transaction
                 "accessLists"
                 indexes
                 "accessList")
                (let ((access-lists
                        (fixture-required-field transaction "accessLists")))
                  (unless (= 1 (length access-lists))
                    (error "EEST state transaction accessList index is required when multiple accessLists are present"))
                  (first access-lists)))))
      (mapcar #'eest-state-test-access-list-entry
              (ethereum-lisp.json:json-array-values entries)))))

(defun eest-state-test-dynamic-fee-transaction-p (transaction)
  (or (fixture-field-present-p transaction "maxFeePerGas")
      (fixture-field-present-p transaction "maxPriorityFeePerGas")))

(defun eest-state-test-authorization (object)
  (make-set-code-authorization
   :chain-id
   (eest-state-test-quantity-string
    (fixture-required-field object "chainId")
    "EEST state test authorization chainId")
   :address (address-from-hex (fixture-required-field object "address"))
   :nonce
   (eest-state-test-quantity-string
    (fixture-required-field object "nonce")
    "EEST state test authorization nonce")
   :y-parity
   (eest-state-test-quantity-string
    (or (fixture-object-field object "yParity")
        (fixture-required-field object "v"))
    "EEST state test authorization yParity")
   :r
   (eest-state-test-quantity-string
    (fixture-required-field object "r")
    "EEST state test authorization r")
   :s
   (eest-state-test-quantity-string
    (fixture-required-field object "s")
    "EEST state test authorization s")))

(defun eest-state-test-authorization-list (transaction)
  (mapcar #'eest-state-test-authorization
          (ethereum-lisp.json:json-array-values
           (fixture-required-field transaction "authorizationList"))))

(defun eest-state-test-transaction (case post-entry)
  (let* ((fixture (fixture-required-field case "fixture"))
         (transaction (fixture-required-field fixture "transaction"))
         (indexes (fixture-required-field post-entry "indexes"))
         (to (fixture-required-field transaction "to"))
         (gas-limit
           (eest-state-test-quantity-string
            (eest-state-test-indexed-transaction-value
             transaction "gasLimit" indexes "gas")
            "EEST state test transaction gasLimit"))
         (value
           (eest-state-test-quantity-string
            (eest-state-test-indexed-transaction-value
             transaction "value" indexes "value")
            "EEST state test transaction value"))
         (data
           (hex-to-bytes
            (eest-state-test-indexed-transaction-value
             transaction "data" indexes "data")))
         (recipient (unless (blank-string-p to)
                      (address-from-hex to))))
    (cond
      ((fixture-field-present-p transaction "authorizationList")
       (make-set-code-transaction
        :chain-id 1
        :nonce (eest-state-test-quantity-string
                (fixture-required-field transaction "nonce")
                "EEST state test transaction nonce")
        :max-priority-fee-per-gas
        (eest-state-test-quantity-string
         (fixture-required-field transaction "maxPriorityFeePerGas")
         "EEST state test transaction maxPriorityFeePerGas")
        :max-fee-per-gas
        (eest-state-test-quantity-string
         (fixture-required-field transaction "maxFeePerGas")
         "EEST state test transaction maxFeePerGas")
        :gas-limit gas-limit
        :to recipient
        :value value
        :data data
        :access-list (or (eest-state-test-selected-access-list
                          transaction
                          indexes)
                         '())
        :authorization-list
        (eest-state-test-authorization-list transaction)))
      ((fixture-field-present-p transaction "blobVersionedHashes")
       (make-blob-transaction
        :chain-id 1
        :nonce (eest-state-test-quantity-string
                (fixture-required-field transaction "nonce")
                "EEST state test transaction nonce")
        :max-priority-fee-per-gas
        (eest-state-test-quantity-string
         (fixture-required-field transaction "maxPriorityFeePerGas")
         "EEST state test transaction maxPriorityFeePerGas")
        :max-fee-per-gas
        (eest-state-test-quantity-string
         (fixture-required-field transaction "maxFeePerGas")
         "EEST state test transaction maxFeePerGas")
        :gas-limit gas-limit
        :to recipient
        :value value
        :data data
        :access-list (or (eest-state-test-selected-access-list
                          transaction
                          indexes)
                         '())
        :max-fee-per-blob-gas
        (eest-state-test-quantity-string
         (fixture-required-field transaction "maxFeePerBlobGas")
         "EEST state test transaction maxFeePerBlobGas")
        :blob-versioned-hashes
        (mapcar #'hash32-from-hex
                (fixture-required-field transaction
                                        "blobVersionedHashes"))))
      ((eest-state-test-dynamic-fee-transaction-p transaction)
       (make-dynamic-fee-transaction
        :chain-id 1
        :nonce (eest-state-test-quantity-string
                (fixture-required-field transaction "nonce")
                "EEST state test transaction nonce")
        :max-priority-fee-per-gas
        (eest-state-test-quantity-string
         (fixture-required-field transaction "maxPriorityFeePerGas")
         "EEST state test transaction maxPriorityFeePerGas")
        :max-fee-per-gas
        (eest-state-test-quantity-string
         (fixture-required-field transaction "maxFeePerGas")
         "EEST state test transaction maxFeePerGas")
        :gas-limit gas-limit
        :to recipient
        :value value
        :data data
        :access-list (or (eest-state-test-selected-access-list
                          transaction
                          indexes)
                         '())))
      ((fixture-field-present-p transaction "accessLists")
       (make-access-list-transaction
        :chain-id 1
        :nonce (eest-state-test-quantity-string
                (fixture-required-field transaction "nonce")
                "EEST state test transaction nonce")
        :gas-price (eest-state-test-quantity-string
                    (fixture-required-field transaction "gasPrice")
                    "EEST state test transaction gasPrice")
        :gas-limit gas-limit
        :to recipient
        :value value
        :data data
        :access-list (eest-state-test-selected-access-list
                      transaction
                      indexes)))
      (t
       (make-legacy-transaction
        :nonce (eest-state-test-quantity-string
                (fixture-required-field transaction "nonce")
                "EEST state test transaction nonce")
        :gas-price (eest-state-test-quantity-string
                    (fixture-required-field transaction "gasPrice")
                    "EEST state test transaction gasPrice")
        :gas-limit gas-limit
        :to recipient
        :value value
        :data data)))))

(defun eest-state-test-sender (case)
  (let* ((transaction (fixture-required-field
                       (fixture-required-field case "fixture")
                       "transaction"))
         (secret-key (fixture-required-field transaction "secretKey")))
    (secp256k1-private-key-address (hex-to-quantity secret-key))))

(defun eest-state-test-post-transaction (post-entry)
  "Decode the fixture's authoritative, signed transaction bytes.

State-test JSON has input-field arrays for selecting a post case, but TXBYTES
is the exact signed envelope.  Reconstructing a transaction from the input
fields loses deliberately malformed signatures and chain IDs, which are
themselves conformance vectors.  Small in-tree adapter fixtures predate
TXBYTES, so callers retain a reconstruction fallback for those fixtures only."
  (let ((txbytes (fixture-object-field post-entry "txbytes")))
    (when txbytes
      (transaction-from-encoding (hex-to-bytes txbytes)))))

(defun eest-state-test-logs-hash (logs)
  (keccak-256-hash
   (rlp-encode
    (mapcar
     (lambda (log)
       (make-rlp-list
        (address-bytes (log-entry-address log))
        (mapcar #'hash32-bytes (log-entry-topics log))
        (log-entry-data log)))
     logs))))

(defun eest-state-test-expected-exception (post-entry)
  (fixture-object-field post-entry "expectException"))

(defun eest-state-test-expected-exception-tokens (expected-exception)
  (unless (stringp expected-exception)
    (error "EEST state test expectException must be a string"))
  (let ((tokens
          (mapcar #'eest-fixture-trim-string
                  (eest-fixture-split-string expected-exception #\|))))
    (when (or (null tokens) (some #'blank-string-p tokens))
      (error "EEST state test expectException ~S is malformed"
             expected-exception))
    tokens))

(defun eest-state-test-condition-message (condition)
  (princ-to-string condition))

(defun eest-state-test-condition-matches-exception-token-p (condition token)
  (let ((message (eest-state-test-condition-message condition)))
    (cond
      ((string= token "TransactionException.INTRINSIC_GAS_TOO_LOW")
       (and (typep condition 'transaction-validation-error)
            (search "gas limit" message :test #'char-equal)
            (search "intrinsic gas" message :test #'char-equal)))
      ((member token
               '("TransactionException.GAS_ALLOWANCE_EXCEEDED"
                 "TransactionException.INTRINSIC_GAS_BELOW_FLOOR_GAS_COST")
               :test #'string=)
       (and (typep condition 'transaction-validation-error)
            (search "gas limit below intrinsic gas" message
                    :test #'char-equal)))
      ((string= token "TransactionException.GAS_LIMIT_EXCEEDS_MAXIMUM")
       (and (typep condition 'transaction-validation-error)
            (search "transaction gas limit exceeds the EIP-7825 cap" message
                    :test #'char-equal)))
      ((string= token "TransactionException.INITCODE_SIZE_EXCEEDED")
       (and (typep condition 'transaction-validation-error)
            (search "contract initcode exceeds maximum size" message
                    :test #'char-equal)))
      ((string= token "TransactionException.INSUFFICIENT_ACCOUNT_FUNDS")
       (and (typep condition 'transaction-validation-error)
            (search "insufficient sender balance" message
                    :test #'char-equal)))
      ((string= token "TransactionException.NONCE_IS_MAX")
       (and (typep condition 'transaction-validation-error)
            (search "sender nonce has maximum value" message
                    :test #'char-equal)))
      ((member token
               '("TransactionException.NONCE_MISMATCH_TOO_HIGH"
                 "TransactionException.NONCE_MISMATCH_TOO_LOW")
               :test #'string=)
       (and (typep condition 'transaction-validation-error)
            (search "invalid transaction nonce" message
                    :test #'char-equal)))
      ((string= token "TransactionException.SENDER_NOT_EOA")
       (and (typep condition 'transaction-validation-error)
            (search "transaction sender has non-delegation code" message
                    :test #'char-equal)))
      ((string= token "TransactionException.TYPE_3_TX_INVALID_BLOB_VERSIONED_HASH")
       (and (typep condition 'block-validation-error)
            (search "invalid blob versioned hash version" message
                    :test #'char-equal)))
      ((string= token "TransactionException.INSUFFICIENT_MAX_FEE_PER_GAS")
       (and (typep condition 'block-validation-error)
            (search "max fee per gas below base fee" message
                    :test #'char-equal)))
      ((string= token "TransactionException.INSUFFICIENT_MAX_FEE_PER_BLOB_GAS")
       (and (typep condition 'block-validation-error)
            (search "max fee per blob gas below blob base fee" message
                    :test #'char-equal)))
      ((member token
               '("TransactionException.TYPE_3_TX_ZERO_BLOBS")
               :test #'string=)
       (and (typep condition 'block-validation-error)
            (search "blob transaction missing blob hashes" message
                    :test #'char-equal)))
      ((member token
               '("TransactionException.TYPE_3_TX_BLOB_COUNT_EXCEEDED"
                 "TransactionException.TYPE_3_TX_MAX_BLOB_GAS_ALLOWANCE_EXCEEDED")
               :test #'string=)
       (and (typep condition 'block-validation-error)
            (search "blob transaction has too many blob hashes" message
                    :test #'char-equal)))
      ((string= token "TransactionException.TYPE_3_TX_CONTRACT_CREATION")
       (and (typep condition 'block-validation-error)
            (search "blob transaction cannot create contracts" message
                    :test #'char-equal)))
      ((string= token "TransactionException.TYPE_4_EMPTY_AUTHORIZATION_LIST")
       (and (typep condition 'transaction-validation-error)
            (search "set-code transactions require an authorization list"
                    message :test #'char-equal)))
      ((string= token "TransactionException.TYPE_4_TX_CONTRACT_CREATION")
       (or (and (typep condition 'transaction-validation-error)
                (search "set-code transactions cannot create contracts"
                        message :test #'char-equal))
           ;; Canonical typed-envelope decoding may reject the empty recipient
           ;; before execution validation gets a transaction object.
           (and (typep condition 'block-validation-error)
                (search "set-code transaction recipient must be exactly 20 bytes"
                        message :test #'char-equal))))
      ((string= token "TransactionException.PRIORITY_GREATER_THAN_MAX_FEE_PER_GAS")
       (and (typep condition '(or block-validation-error
                                  transaction-validation-error))
            (search "max priority fee exceeds max fee" message
                    :test #'char-equal)))
      ((string= token "TransactionException.INVALID_CHAINID")
       (and (typep condition 'transaction-validation-error)
            (search "chain id does not match expected chain id" message
                    :test #'char-equal)))
      ((string= token "TransactionException.INVALID_SIGNATURE_VRS")
       (and (typep condition 'transaction-validation-error)
            (search "invalid transaction signature" message
                    :test #'char-equal)))
      (t
       (error "Unsupported EEST state test expectException token ~A for ~S: ~A"
              token (type-of condition) message)))))

(defun eest-state-test-condition-matches-expected-exception-p
    (condition expected-exception)
  (some (lambda (token)
          (eest-state-test-condition-matches-exception-token-p condition token))
        (eest-state-test-expected-exception-tokens expected-exception)))

(defun eest-state-test-chain-rules (fork)
  (unless (member fork '("London" "Shanghai" "Cancun" "Prague" "Osaka")
                  :test #'string=)
    (error "Unsupported EEST state test fork ~A" fork))
  (let ((rules
          (make-chain-rules
           :chain-id 1
           :homestead-p t
           :eip150-p t
           :eip155-p t
           :eip158-p t
           :byzantium-p t
           :constantinople-p t
           :petersburg-p t
           :istanbul-p t
           :berlin-p t
           :london-p t
           :shanghai-p
           (member fork '("Shanghai" "Cancun" "Prague" "Osaka")
                   :test #'string=)
           :cancun-p
           (member fork '("Cancun" "Prague" "Osaka") :test #'string=)
           :prague-p
           (member fork '("Prague" "Osaka") :test #'string=)
           :osaka-p (string= fork "Osaka"))))
    ;; CHAIN-CONFIG-RULES normally materializes the active blob schedule into
    ;; these slots.  State tests construct rules directly, so do the equivalent
    ;; here; otherwise Prague incorrectly retains Cancun's six-blob block cap.
    (multiple-value-bind (target-gas max-gas update-fraction)
        (chain-rules-blob-schedule rules)
      (setf (chain-rules-blob-schedule-target-gas rules) target-gas
            (chain-rules-blob-schedule-max-gas rules) max-gas
            (chain-rules-blob-schedule-update-fraction rules) update-fraction))
    rules))

(defun eest-state-test-blob-base-fee (env rules)
  "Return the EIP-4844 blob base fee declared by an EEST execution environment.

EEST supplies the already-derived excess blob gas for the block under test.
The fee schedule still belongs to the active fork, since its update fraction
changes at later forks.  A missing field describes a pre-Cancun environment
and consequently has no blob fee."
  (let ((excess-blob-gas
          (fixture-object-field env "currentExcessBlobGas")))
    (if excess-blob-gas
        (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
            (chain-rules-blob-schedule rules)
          (declare (ignore target-blob-gas max-blob-gas))
          (blob-base-fee (hex-to-quantity excess-blob-gas)
                         :update-fraction update-fraction))
        0)))

(defun eest-state-test-block-hashes (env)
  "Build the state-test BLOCKHASH history for the execution context.

The canonical go-ethereum state-test runner defines block N's hash as
keccak256(decimal(N)); EEST state-test fixtures rely on the same convention and
do not serialize their source Environment's block_hashes map.  Seed the
protocol-visible 256-block window with that deterministic test-only provider.
`blockHashes` and the legacy `previousHash` field remain explicit overrides."
  (let* ((hashes (make-hash-table :test 'eql))
         (current-number
           (eest-state-test-quantity-string
            (fixture-required-field env "currentNumber")
            "EEST state test current block number")))
    (loop for number from (max 0 (- current-number 256)) below current-number
          do (setf (gethash number hashes)
                   (keccak-256-hash
                    (ascii-to-bytes (format nil "~D" number)))))
    (let ((fixture-hashes (fixture-object-field env "blockHashes")))
      (when fixture-hashes
        (dolist (entry
                 (ethereum-lisp.json:json-object-entries
                  fixture-hashes "EEST state test blockHashes"))
          (setf (gethash (eest-state-test-quantity-string
                          (car entry) "EEST state test block hash number")
                         hashes)
                (hash32-from-hex (cdr entry))))))
    (let ((previous-hash (fixture-object-field env "previousHash")))
      (when previous-hash
        (when (plusp current-number)
          (setf (gethash (1- current-number) hashes)
                (hash32-from-hex previous-hash)))))
    hashes))

(deftest eest-state-test-block-hashes-preserve-explicit-history
  (let ((hashes
          (eest-state-test-block-hashes
           '(("currentNumber" . "0x02")
             ("blockHashes"
              . (("0x00"
                  . "0x1111111111111111111111111111111111111111111111111111111111111111")))
             ("previousHash"
              . "0x2222222222222222222222222222222222222222222222222222222222222222")))))
    (is (string=
         "0x1111111111111111111111111111111111111111111111111111111111111111"
         (hash32-to-hex (gethash 0 hashes))))
    (is (string=
         "0x2222222222222222222222222222222222222222222222222222222222222222"
         (hash32-to-hex (gethash 1 hashes))))))

(deftest eest-state-test-block-hashes-use-canonical-test-provider
  (let ((hashes
          (eest-state-test-block-hashes
           '(("currentNumber" . "0x01")))))
    (is (string=
         "0x044852b2a670ade5407e78fb2863c51de9fcb96542a07186fe3aeda6bb8a116d"
         (hash32-to-hex (gethash 0 hashes))))))

(deftest eest-late-fork-state-tests-select-active-rules
  (let ((cancun (eest-state-test-chain-rules "Cancun"))
        (prague (eest-state-test-chain-rules "Prague"))
        (osaka (eest-state-test-chain-rules "Osaka")))
    (is (chain-rules-cancun-p cancun))
    (is (not (chain-rules-prague-p cancun)))
    (is (chain-rules-prague-p prague))
    (is (not (chain-rules-osaka-p prague)))
    (is (= 9 (chain-rules-max-blobs-per-transaction prague)))
    (is (chain-rules-osaka-p osaka))
    (is (= 6 (chain-rules-max-blobs-per-transaction osaka)))))

(defun execute-eest-state-test-post-entry (case post-entry &key (fork "London"))
  (let* ((fixture (fixture-required-field case "fixture"))
         (env (fixture-required-field fixture "env"))
         (state (make-state-db))
         (rules (eest-state-test-chain-rules fork)))
    (dolist (entry (fixture-required-field fixture "pre"))
      (apply-eest-state-test-account state (car entry) (cdr entry)))
    (let ((snapshot (state-db-copy state)))
      (handler-case
          (let* ((signed-tx (eest-state-test-post-transaction post-entry))
                 (arguments
                   (list :chain-rules rules
                         :base-fee
                         (hex-to-quantity
                          (or (fixture-object-field env "currentBaseFee") "0x0"))
                         :blob-base-fee (eest-state-test-blob-base-fee env rules)
                         :coinbase
                         (address-from-hex
                          (fixture-required-field env "currentCoinbase"))
                         :block-number
                         (hex-to-quantity
                          (fixture-required-field env "currentNumber"))
                         :timestamp
                         (hex-to-quantity
                          (fixture-required-field env "currentTimestamp"))
                         :difficulty
                         (hex-to-quantity
                          (or (fixture-object-field env "currentDifficulty") "0x0"))
                         :context-gas-limit
                         (hex-to-quantity
                          (fixture-required-field env "currentGasLimit"))
                         :block-hashes (eest-state-test-block-hashes env)))
                 (receipt
                   (if signed-tx
                       (apply #'apply-signed-message state signed-tx
                              :expected-chain-id 1 arguments)
                       (apply #'apply-message state
                              (eest-state-test-sender case)
                              (eest-state-test-transaction case post-entry)
                              :chain-id 1 arguments))))
            (values state receipt post-entry nil))
        (error (condition)
          (state-db-restore state snapshot)
          (values state nil post-entry condition))))))

(defun execute-eest-state-test-case (case &key (fork "London"))
  (execute-eest-state-test-post-entry
   case
   (first (eest-state-test-post-entries case fork))
   :fork fork))

(defun assert-eest-state-test-field= (case post-entry fork field expected actual)
  "Assert one EEST post-state field with fixture context on a mismatch."
  (unless (string= expected actual)
    (error "EEST state case ~A fork ~A indexes ~S has wrong ~A: expected ~A, got ~A"
           (fixture-required-field case "name")
           fork
           (fixture-object-field post-entry "indexes")
           field expected actual))
  (is t))

(defun assert-eest-state-test-quantity= (case post-entry fork field expected actual)
  "Compare an EEST hex quantity by value, retaining fixture spelling on error."
  (let ((expected-value (eest-state-test-quantity-string expected field)))
    (unless (= expected-value actual)
      (error "EEST state case ~A fork ~A indexes ~S has wrong ~A: expected ~A, got ~A"
             (fixture-required-field case "name")
             fork
             (fixture-object-field post-entry "indexes")
             field expected (quantity-to-hex actual)))
    (is t)))

(defun assert-eest-state-test-expected-condition
    (case post-entry fork condition expected-exception)
  "Require an EEST exception fixture to fail, retaining its exact identity."
  (unless condition
    (error "EEST state case ~A fork ~A indexes ~S expected ~A, but execution succeeded"
           (fixture-required-field case "name")
           fork
           (fixture-object-field post-entry "indexes")
           expected-exception))
  (is t))

(defun assert-eest-state-test-no-unexpected-condition
    (case post-entry fork condition)
  "Require a successful EEST fixture to finish without a condition."
  (when condition
    (error "EEST state case ~A fork ~A indexes ~S unexpectedly failed with ~S: ~A"
           (fixture-required-field case "name")
           fork
           (fixture-object-field post-entry "indexes")
           (type-of condition)
           (eest-state-test-condition-message condition)))
  (is t))

(defun assert-eest-state-test-account-state
    (state case post-entry fork address-hex expected)
  "Check one authoritative EEST post-state account before its aggregate root."
  (let* ((address (address-from-hex address-hex))
         (account (state-db-get-account state address))
         (expected-storage (fixture-required-field expected "storage")))
    (unless account
      (error "EEST state case ~A fork ~A indexes ~S lost expected account ~A"
             (fixture-required-field case "name") fork
             (fixture-object-field post-entry "indexes") address-hex))
    (assert-eest-state-test-quantity=
     case post-entry fork (format nil "nonce for ~A" address-hex)
     (fixture-required-field expected "nonce")
     (state-account-nonce account))
    (assert-eest-state-test-quantity=
     case post-entry fork (format nil "balance for ~A" address-hex)
     (fixture-required-field expected "balance")
     (state-account-balance account))
    (assert-eest-state-test-field=
     case post-entry fork (format nil "code for ~A" address-hex)
     (fixture-required-field expected "code")
     (bytes-to-hex (state-db-get-code state address)))
    (dolist (entry expected-storage)
      (assert-eest-state-test-quantity=
       case post-entry fork
       (format nil "storage ~A at ~A" (car entry) address-hex)
       (cdr entry)
       (state-db-get-storage state address
                             (eest-state-test-storage-key (car entry)))))))

(defun assert-eest-state-test-post-state (state case post-entry fork)
  "Check every EEST-specified account to make root mismatches actionable."
  ;; The external v20 corpus has this authoritative expanded state; the small
  ;; in-tree compatibility fixtures intentionally carry only a root.
  (when (fixture-field-present-p post-entry "state")
    (dolist (entry (fixture-required-field post-entry "state"))
      (assert-eest-state-test-account-state
       state case post-entry fork (car entry) (cdr entry)))))

(defun assert-eest-state-test-post-entry (case post-entry &key (fork "London"))
  (multiple-value-bind (state receipt post-entry condition)
      (execute-eest-state-test-post-entry case post-entry :fork fork)
    (let ((expected-exception
            (eest-state-test-expected-exception post-entry)))
      (if expected-exception
          (progn
            (assert-eest-state-test-expected-condition
             case post-entry fork condition expected-exception)
            (unless (eest-state-test-condition-matches-expected-exception-p
                     condition expected-exception)
              (error "EEST state case ~A fork ~A indexes ~S expected ~A, got ~S: ~A"
                     (fixture-required-field case "name")
                     fork
                     (fixture-object-field post-entry "indexes")
                     expected-exception
                     (type-of condition)
                     (eest-state-test-condition-message condition)))
            (is t)
            (assert-eest-state-test-field=
             case post-entry fork "state root"
             (fixture-required-field post-entry "hash")
             (state-db-root-hex state)))
          (progn
            (assert-eest-state-test-no-unexpected-condition
             case post-entry fork condition)
            (assert-eest-state-test-post-state state case post-entry fork)
            (assert-eest-state-test-field=
             case post-entry fork "state root"
             (fixture-required-field post-entry "hash")
             (state-db-root-hex state))
            (assert-eest-state-test-field=
             case post-entry fork "logs hash"
             (fixture-required-field post-entry "logs")
             (hash32-to-hex
              (eest-state-test-logs-hash (receipt-logs receipt)))))))))

(defun assert-eest-state-test-case (case &key fork)
  (dolist (fork (if fork
                    (list fork)
                    (eest-state-test-case-fork-names case)))
    (dolist (post-entry (eest-state-test-post-entries case fork))
      (assert-eest-state-test-post-entry case post-entry :fork fork))))

(defun assert-evm-state-fixture-account (state address-hex expected)
  (let* ((address (address-from-hex address-hex))
         (account (state-db-get-account state address))
         (expected-storage (fixture-object-field expected "storage"))
         (actual-storage '()))
    (is account)
    (is (= (evm-state-fixture-quantity expected "nonce")
           (state-account-nonce account)))
    (is (= (evm-state-fixture-quantity expected "balance")
           (state-account-balance account)))
    (is (bytes= (hex-to-bytes (fixture-object-field expected "code"))
                (state-db-get-code state address)))
    (state-db-for-each-account
     state
     (lambda (actual-address actual-account actual-code storage-entries)
       (declare (ignore actual-account actual-code))
       (when (bytes= (address-bytes address) (address-bytes actual-address))
         (setf actual-storage storage-entries))))
    (is (= (length expected-storage) (length actual-storage)))
    (dolist (entry expected-storage)
      (is (= (hex-to-quantity (cdr entry))
             (state-db-get-storage
              state
              address
              (hash32-from-hex (car entry))))))))

(defun assert-evm-state-fixture-log (actual expected)
  (is (string= (fixture-object-field expected "address")
               (address-to-hex (log-entry-address actual))))
  (let ((expected-topics (fixture-object-field expected "topics"))
        (actual-topics (log-entry-topics actual)))
    (is (= (length expected-topics) (length actual-topics)))
    (loop for expected-topic in expected-topics
          for actual-topic in actual-topics
          do (is (string= expected-topic (hash32-to-hex actual-topic)))))
  (is (string= (fixture-object-field expected "data")
               (bytes-to-hex (log-entry-data actual)))))

(defun assert-evm-state-fixture-receipt (receipt expected)
  (is (= (evm-state-fixture-quantity expected "status")
         (receipt-status receipt)))
  (is (= (evm-state-fixture-quantity expected "cumulativeGasUsed")
         (receipt-cumulative-gas-used receipt)))
  (is (string= (fixture-object-field expected "logsBloom")
               (bytes-to-hex (bloom-bytes (receipt-bloom (receipt-logs receipt))))))
  (let ((expected-logs (fixture-object-field expected "logs"))
        (actual-logs (receipt-logs receipt)))
    (is (= (length expected-logs) (length actual-logs)))
    (loop for expected-log in expected-logs
          for actual-log in actual-logs
          do (assert-evm-state-fixture-log actual-log expected-log))))

(deftest evm-state-fixture-shape-validation
  (signals error
    (validate-evm-state-fixture-metadata
     (list (cons "format" +evm-state-fixture-format+)
           (cons "source" "seed")
           (cons "source" "duplicate seed")
           (cons "executionSpecTests"
                 (list (cons "release" +phase-a-eest-release+)
                       (cons "tagTarget" +phase-a-eest-tag-target+)
                       (cons "archive" +phase-a-eest-archive+)
                       (cons "status" "seed"))))))
  (signals error
    (validate-evm-state-fixture-case-shape
     (list (cons "name" "unknown-case-field")
           (cons "tags" +evm-state-fixture-required-tags+)
           (cons "env" nil)
           (cons "pre" nil)
           (cons "transaction" nil)
           (cons "expect" nil)
           (cons "unexpected" t))))
  (signals error
    (evm-state-fixture-quantity (list (cons "nonce" 1)) "nonce"))
  (signals error
    (evm-state-fixture-quantity (list (cons "gasLimit" nil)) "gasLimit"))
  (signals error
    (evm-state-fixture-quantity (list (cons "nonce" "0")) "nonce"))
  (signals error
    (evm-state-fixture-quantity (list (cons "nonce" "0X0")) "nonce"))
  (signals error
    (evm-state-fixture-quantity (list (cons "nonce" "0x00")) "nonce"))
  (signals error
    (evm-state-fixture-address 1 "inline address"))
  (signals error
    (evm-state-fixture-address
     "00000000000000000000000000000000000000aa"
     "inline address"))
  (signals error
    (evm-state-fixture-address
     "0X00000000000000000000000000000000000000AA"
     "inline address"))
  (signals error
    (evm-state-fixture-hash 1 "inline hash"))
  (signals error
    (evm-state-fixture-hash
     "00000000000000000000000000000000000000000000000000000000000000aa"
     "inline hash"))
  (signals error
    (evm-state-fixture-hash
     "0X00000000000000000000000000000000000000000000000000000000000000AA"
     "inline hash"))
  (signals error
    (evm-state-fixture-hex-bytes 1 "inline bytes"))
  (signals error
    (evm-state-fixture-hex-bytes "6000" "inline bytes"))
  (signals error
    (evm-state-fixture-hex-bytes "0XAB" "inline bytes"))
  (signals error
    (evm-state-fixture-non-empty-string 1 "inline string"))
  (signals error
    (evm-state-fixture-non-empty-string "" "inline string"))
  (signals error
    (validate-evm-state-fixture-storage-shape
     (list "not-a-storage-field")
     "inline account"))
  (signals error
    (validate-evm-state-fixture-storage-shape
     (list (cons "0x00000000000000000000000000000000000000000000000000000000000000aa"
                 "0x1")
           (cons "0x00000000000000000000000000000000000000000000000000000000000000AA"
                 "0x2"))
     "inline account"))
  (signals error
    (validate-evm-state-fixture-accounts-shape
     (list "not-an-account-field")
     "inline accounts"))
  (signals error
    (let ((account
            (list (cons "nonce" "0x0")
                  (cons "balance" "0x0")
                  (cons "code" "0x")
                  (cons "storage" nil))))
      (validate-evm-state-fixture-accounts-shape
       (list (cons "0x00000000000000000000000000000000000000aa"
                   account)
             (cons "0x00000000000000000000000000000000000000AA"
                   account))
       "inline accounts")))
  (signals error
    (validate-evm-state-fixture-access-list-shape
     (list
      (list (cons "address" "0x00000000000000000000000000000000000000aa")
            (cons "storageKeys" nil))
      (list (cons "address" "0x00000000000000000000000000000000000000AA")
            (cons "storageKeys" nil)))))
  (signals error
    (validate-evm-state-fixture-access-list-shape
     (list
      (list
       (cons "address" "0x00000000000000000000000000000000000000aa")
       (cons "storageKeys"
             (list
              "0x00000000000000000000000000000000000000000000000000000000000000bb"
              "0x00000000000000000000000000000000000000000000000000000000000000BB"))))))
  (signals error
    (validate-evm-state-fixture-receipt-shape
     (list (cons "status" "0x1")
           (cons "cumulativeGasUsed" "0x0")
           (cons "logsBloom" "0x00")
           (cons "logs" nil))))
  (signals error
    (validate-evm-state-fixture-receipt-shape
     (list (cons "status" "0x2")
           (cons "cumulativeGasUsed" "0x0")
           (cons "logsBloom"
                 (bytes-to-hex (make-byte-vector 256)))
           (cons "logs" nil))))
  (signals error
    (validate-evm-state-fixture-cases
     (list "not-a-case-object")))
  (let ((+evm-state-fixture-required-case-names+ '("present" "missing")))
    (signals error
      (validate-evm-state-fixture-required-case-names
       (list (list (cons "name" "present"))))))
  (let ((+evm-state-fixture-required-case-names+ '("present" "present")))
    (signals error
      (validate-evm-state-fixture-required-case-names
       (list (list (cons "name" "present")))))))

(deftest evm-state-fixture-vectors
  (let* ((fixture (load-handwritten-fixture-file +evm-state-fixture-path+))
         (cases (fixture-object-field fixture "cases")))
    (validate-evm-state-fixture-metadata fixture)
    (validate-evm-state-fixture-cases cases)
    (validate-evm-state-fixture-required-case-names cases)
    (dolist (case cases)
      (multiple-value-bind (state receipt)
          (execute-evm-state-fixture-case case)
        (let ((expect (fixture-object-field case "expect")))
          (is (string= (fixture-object-field expect "stateRoot")
                       (state-db-root-hex state)))
          (dolist (entry (fixture-object-field expect "post"))
            (assert-evm-state-fixture-account state (car entry) (cdr entry)))
          (assert-evm-state-fixture-receipt
           receipt
           (fixture-object-field expect "receipt")))))))

(deftest eest-state-test-expected-exception-mapping
  (let ((intrinsic-gas-condition
          (make-condition
           'transaction-validation-error
           :message "Gas limit below intrinsic gas"))
        (insufficient-funds-condition
          (make-condition
           'transaction-validation-error
           :message "Insufficient sender balance")))
    (is (equal '("TransactionException.INTRINSIC_GAS_TOO_LOW")
               (eest-state-test-expected-exception-tokens
                "TransactionException.INTRINSIC_GAS_TOO_LOW")))
    (is (eest-state-test-condition-matches-expected-exception-p
         intrinsic-gas-condition
         "TransactionException.INTRINSIC_GAS_TOO_LOW"))
    (is (eest-state-test-condition-matches-expected-exception-p
         intrinsic-gas-condition
         "TransactionException.GAS_ALLOWANCE_EXCEEDED"))
    (is (eest-state-test-condition-matches-expected-exception-p
         intrinsic-gas-condition
         "TransactionException.INTRINSIC_GAS_BELOW_FLOOR_GAS_COST"))
    (is (eest-state-test-condition-matches-expected-exception-p
         (make-condition 'transaction-validation-error
                         :message "Transaction gas limit exceeds the EIP-7825 cap")
         "TransactionException.GAS_LIMIT_EXCEEDS_MAXIMUM"))
    (is (eest-state-test-condition-matches-expected-exception-p
         (make-condition 'transaction-validation-error
                         :message "Contract initcode exceeds maximum size")
         "TransactionException.INITCODE_SIZE_EXCEEDED"))
    (is (eest-state-test-condition-matches-expected-exception-p
         insufficient-funds-condition
         "TransactionException.INSUFFICIENT_ACCOUNT_FUNDS"))
    (is (eest-state-test-condition-matches-expected-exception-p
         (make-condition 'transaction-validation-error
                         :message "Sender nonce has maximum value")
         "TransactionException.NONCE_IS_MAX"))
    (dolist (token '("TransactionException.NONCE_MISMATCH_TOO_HIGH"
                     "TransactionException.NONCE_MISMATCH_TOO_LOW"))
      (is (eest-state-test-condition-matches-expected-exception-p
           (make-condition 'transaction-validation-error
                           :message "Invalid transaction nonce")
           token)))
    (is (eest-state-test-condition-matches-expected-exception-p
         (make-condition 'transaction-validation-error
                         :message "Transaction sender has non-delegation code")
         "TransactionException.SENDER_NOT_EOA"))
    (is (eest-state-test-condition-matches-expected-exception-p
         (make-condition 'block-validation-error
                         :message "Invalid blob versioned hash version")
         "TransactionException.TYPE_3_TX_INVALID_BLOB_VERSIONED_HASH"))
    (is (eest-state-test-condition-matches-expected-exception-p
         (make-condition 'block-validation-error
                         :message "Max fee per gas below base fee")
         "TransactionException.INSUFFICIENT_MAX_FEE_PER_GAS"))
    (is (eest-state-test-condition-matches-expected-exception-p
         (make-condition 'block-validation-error
                         :message "Max fee per blob gas below blob base fee")
         "TransactionException.INSUFFICIENT_MAX_FEE_PER_BLOB_GAS"))
    (is (eest-state-test-condition-matches-expected-exception-p
         (make-condition 'block-validation-error
                         :message "Blob transaction missing blob hashes")
         "TransactionException.TYPE_3_TX_ZERO_BLOBS"))
    (is (eest-state-test-condition-matches-expected-exception-p
         (make-condition 'block-validation-error
                         :message "Blob transaction has too many blob hashes")
         "TransactionException.TYPE_3_TX_BLOB_COUNT_EXCEEDED"))
    (is (eest-state-test-condition-matches-expected-exception-p
         (make-condition 'block-validation-error
                         :message "Blob transaction cannot create contracts")
         "TransactionException.TYPE_3_TX_CONTRACT_CREATION"))
    (is (eest-state-test-condition-matches-expected-exception-p
         (make-condition 'transaction-validation-error
                         :message "Set-code transactions require an authorization list")
         "TransactionException.TYPE_4_EMPTY_AUTHORIZATION_LIST"))
    (is (eest-state-test-condition-matches-expected-exception-p
         (make-condition 'transaction-validation-error
                         :message "Set-code transactions cannot create contracts")
         "TransactionException.TYPE_4_TX_CONTRACT_CREATION"))
    (is (eest-state-test-condition-matches-expected-exception-p
         (make-condition 'block-validation-error
                         :message "Set-code transaction recipient must be exactly 20 bytes")
         "TransactionException.TYPE_4_TX_CONTRACT_CREATION"))
    (is (eest-state-test-condition-matches-expected-exception-p
         (make-condition 'block-validation-error
                         :message "Max priority fee exceeds max fee")
         "TransactionException.PRIORITY_GREATER_THAN_MAX_FEE_PER_GAS"))
    (is (eest-state-test-condition-matches-expected-exception-p
         (make-condition 'transaction-validation-error
                         :message "Max priority fee exceeds max fee")
         "TransactionException.PRIORITY_GREATER_THAN_MAX_FEE_PER_GAS"))
    (is (eest-state-test-condition-matches-expected-exception-p
         (make-condition 'transaction-validation-error
                         :message "Transaction chain ID does not match expected chain ID")
         "TransactionException.INVALID_CHAINID"))
    (is (eest-state-test-condition-matches-expected-exception-p
         (make-condition 'transaction-validation-error
                         :message "Invalid transaction signature")
         "TransactionException.INVALID_SIGNATURE_VRS"))
    (signals error
      (eest-state-test-condition-matches-expected-exception-p
       intrinsic-gas-condition
       "TransactionException.UNKNOWN"))
    (signals error
      (eest-state-test-expected-exception-tokens
       "TransactionException.INTRINSIC_GAS_TOO_LOW|"))))

(deftest phase-a-eest-state-test-root-vectors-execute
  (let ((root (execution-spec-tests-state-test-root
               "tests/fixtures/execution-spec-tests-root/")))
    (dolist (case (load-phase-a-eest-state-test-root-cases root))
      (assert-eest-state-test-case case))))

(defparameter +pinned-v5.4.0-late-fork-state-test-cases+
  '(("cancun/eip1153_tstore/test_basic_tload_after_store.json/tests/cancun/eip1153_tstore/test_basic_tload.py::test_basic_tload_after_store[fork_Cancun-state_test]"
     . "Cancun")
    ("prague/eip2537_bls_12_381_precompiles/test_invalid_length_pairing.json/tests/prague/eip2537_bls_12_381_precompiles/test_bls12_variable_length_input_contracts.py::test_invalid_length_pairing[fork_Prague-full_discount_table-state_test-precompile_address_15--input_one_byte_too_long]"
     . "Prague")
    ;; EEST v5.4.0's Osaka feature directory contains pre-activation vectors
    ;; whose expected post-state is Prague. The archive has no Amsterdam tree.
    ("osaka/eip7825_transaction_gas_limit_cap/test_transaction_gas_limit_cap.json/tests/osaka/eip7825_transaction_gas_limit_cap/test_tx_gas_limit.py::test_transaction_gas_limit_cap[fork_Prague-tx_gas_limit_cap_none0-state_test]"
     . "Prague")))

(deftest pinned-v5.4.0-late-fork-state-test-families-execute
  (with-execution-spec-tests-state-test-root (root)
    ;; These selectors name the v5.4.0 archive's historical layout. The stable
    ;; corpus intentionally has a different layout and is covered by auto
    ;; discovery below; treating it as v5.4.0 would turn a corpus-selection
    ;; mismatch into a fabricated execution failure.
    (unless (search "v5.4.0" (namestring (truename root)) :test #'char-equal)
      (skip-test "Pinned v5.4.0 selector control is inapplicable to this EEST corpus"))
    (let* ((selectors
             (mapcar #'car +pinned-v5.4.0-late-fork-state-test-cases+))
           (cases (load-eest-state-test-root-cases root :names selectors)))
      (is (= (length +pinned-v5.4.0-late-fork-state-test-cases+)
             (length cases)))
      (dolist (case cases)
        (let* ((name (fixture-required-field case "name"))
               (fork
                 (cdr (assoc name
                             +pinned-v5.4.0-late-fork-state-test-cases+
                             :test #'string=))))
          (is fork)
          (assert-eest-state-test-case case :fork fork))))))

(defun call-with-eest-kzg-cffi-verifier (thunk)
  "Run THUNK with the image's real c-kzg verifier installed.

The current EEST state corpus includes Cancun point-evaluation precompile
vectors.  Those are proof-verification vectors, not shape-only fixtures, so a
missing libethckzg setup is a conformance failure rather than an optional
capability or a reason to skip the case."
  (let ((verifier (make-kzg-cffi-verifier)))
    (unless verifier
      (error "EEST current-fork conformance requires the c-kzg CFFI verifier"))
    (let ((*kzg-verifier* verifier))
      (funcall thunk))))

(defun call-with-eest-cryptographic-backends (thunk)
  "Run current-fork EEST with the same mandatory crypto backends as the CLI.

Cancun point-evaluation vectors require c-kzg, while Prague and Osaka include
BLS12-381 precompile vectors backed by blst.  An external conformance run must
not turn either missing backend into an Engine internal error or an optional
skip, so both are installed for the whole streamed fixture execution and their
absence is an explicit gate failure."
  (let ((kzg-verifier (make-kzg-cffi-verifier))
        (bls-backend (make-bls12381-cffi-backend)))
    (unless kzg-verifier
      (error "EEST current-fork conformance requires the c-kzg CFFI verifier"))
    (unless bls-backend
      (error "EEST current-fork conformance requires the blst CFFI backend"))
    (let ((*kzg-verifier* kzg-verifier)
          (*bls12381-backend* bls-backend))
      (funcall thunk))))

(deftest optional-phase-a-eest-state-test-root-vectors-execute
  (:layer :integration :module :eest)
  ;; Execute only the forks this build implements. A post map from the stable
  ;; corpus can also carry a not-yet-implemented fork (e.g. Amsterdam, which is
  ;; deliberately gated out of this wave); running EVERY fork name would turn
  ;; the gate red on a fork we never claimed to execute rather than on a real
  ;; divergence. Discovery already guarantees at least one supported fork per
  ;; case, so the intersection is non-empty and nothing is silently skipped.
  (call-with-eest-cryptographic-backends
   (lambda ()
     (let ((supported (phase-a-eest-state-test-supported-forks)))
       (map-optional-phase-a-eest-state-test-root-cases
        (lambda (case)
          (dolist (fork (intersection supported
                                      (eest-state-test-case-fork-names case)
                                      :test #'string=))
            (assert-eest-state-test-case case :fork fork))))))))
