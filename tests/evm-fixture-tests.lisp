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
  (unless (listp storage)
    (error "~A storage must be a JSON object" label))
  (let ((seen-slots (make-hash-table :test 'equal)))
    (dolist (entry storage)
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
  (unless (listp accounts)
    (error "~A must be a JSON object" label))
  (let ((seen-addresses (make-hash-table :test 'equal)))
    (dolist (entry accounts)
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
  (unless (listp access-list)
    (error "EVM state fixture accessList must be a JSON array"))
  (let ((seen-addresses (make-hash-table :test 'equal)))
    (dolist (entry access-list)
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
        (unless (listp keys)
          (error "EVM state fixture access list storageKeys must be a JSON array"))
        (dolist (key keys)
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
    (dolist (entry (fixture-object-field account "storage"))
      (state-db-set-storage
       state
       address
       (hash32-from-hex (car entry))
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

(defun eest-state-test-post-entry (case fork)
  (let* ((post (fixture-required-field
                (fixture-required-field case "fixture")
                "post"))
         (entries (fixture-required-field post fork)))
    (unless (and (listp entries) (= 1 (length entries)))
      (error "EEST state test case ~A must have one ~A post entry"
             (fixture-required-field case "name")
             fork))
    (first entries)))

(defun eest-state-test-indexed-transaction-value
    (transaction field indexes index-name)
  (let* ((values (fixture-required-field transaction field))
         (index (fixture-required-field indexes index-name)))
    (unless (and (integerp index)
                 (<= 0 index)
                 (< index (length values)))
      (error "EEST state transaction index ~A is out of range" index-name))
    (nth index values)))

(defun eest-state-test-access-list-entry (entry)
  (make-access-list-entry
   :address (address-from-hex (fixture-required-field entry "address"))
   :storage-keys
   (mapcar #'hash32-from-hex
           (fixture-required-field entry "storageKeys"))))

(defun eest-state-test-selected-access-list (transaction indexes)
  (when (fixture-field-present-p transaction "accessLists")
    (mapcar #'eest-state-test-access-list-entry
            (eest-state-test-indexed-transaction-value
             transaction
             "accessLists"
             indexes
             "accessList"))))

(defun eest-state-test-transaction (case post-entry)
  (let* ((fixture (fixture-required-field case "fixture"))
         (transaction (fixture-required-field fixture "transaction"))
         (indexes (fixture-required-field post-entry "indexes"))
         (to (fixture-required-field transaction "to"))
         (gas-limit
           (evm-state-fixture-quantity-string
            (eest-state-test-indexed-transaction-value
             transaction "gasLimit" indexes "gas")
            "EEST state test transaction gasLimit"))
         (value
           (evm-state-fixture-quantity-string
            (eest-state-test-indexed-transaction-value
             transaction "value" indexes "value")
            "EEST state test transaction value"))
         (data
           (hex-to-bytes
            (eest-state-test-indexed-transaction-value
             transaction "data" indexes "data")))
         (recipient (unless (blank-string-p to)
                      (address-from-hex to))))
    (if (fixture-field-present-p transaction "accessLists")
        (make-access-list-transaction
         :chain-id 1
         :nonce (evm-state-fixture-quantity transaction "nonce")
         :gas-price (evm-state-fixture-quantity transaction "gasPrice")
         :gas-limit gas-limit
         :to recipient
         :value value
         :data data
         :access-list (eest-state-test-selected-access-list
                       transaction
                       indexes))
        (make-legacy-transaction
         :nonce (evm-state-fixture-quantity transaction "nonce")
         :gas-price (evm-state-fixture-quantity transaction "gasPrice")
         :gas-limit gas-limit
         :to recipient
         :value value
         :data data))))

(defun eest-state-test-sender (case)
  (let* ((transaction (fixture-required-field
                       (fixture-required-field case "fixture")
                       "transaction"))
         (secret-key (fixture-required-field transaction "secretKey")))
    (secp256k1-private-key-address (hex-to-quantity secret-key))))

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

(defun execute-eest-state-test-case (case &key (fork "London"))
  (let* ((fixture (fixture-required-field case "fixture"))
         (env (fixture-required-field fixture "env"))
         (post-entry (eest-state-test-post-entry case fork))
         (state (make-state-db))
         (sender (eest-state-test-sender case))
         (tx (eest-state-test-transaction case post-entry))
         (rules (make-chain-rules :chain-id 1
                                  :homestead-p t
                                  :eip150-p t
                                  :eip155-p t
                                  :eip158-p t
                                  :byzantium-p t
                                  :constantinople-p t
                                  :petersburg-p t
                                  :istanbul-p t
                                  :berlin-p t
                                  :london-p t)))
    (dolist (entry (fixture-required-field fixture "pre"))
      (apply-evm-state-fixture-account state (car entry) (cdr entry)))
    (let ((receipt
            (apply-message
             state sender tx
             :chain-id 1
             :chain-rules rules
             :base-fee
             (hex-to-quantity
              (or (fixture-object-field env "currentBaseFee") "0x0"))
             :coinbase
             (address-from-hex
              (fixture-required-field env "currentCoinbase"))
             :block-number
             (hex-to-quantity (fixture-required-field env "currentNumber"))
             :timestamp
             (hex-to-quantity (fixture-required-field env "currentTimestamp"))
             :difficulty
             (hex-to-quantity
              (or (fixture-object-field env "currentDifficulty") "0x0")))))
      (values state receipt post-entry))))

(defun assert-eest-state-test-case (case &key (fork "London"))
  (multiple-value-bind (state receipt post-entry)
      (execute-eest-state-test-case case :fork fork)
    (is (string= (fixture-required-field post-entry "hash")
                 (state-db-root-hex state)))
    (is (string= (fixture-required-field post-entry "logs")
                 (hash32-to-hex
                  (eest-state-test-logs-hash (receipt-logs receipt)))))))

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

(deftest eest-state-test-root-london-vector-executes
  (let* ((root (execution-spec-tests-state-test-root
                "tests/fixtures/execution-spec-tests-root/"))
         (case (first
                (load-eest-state-test-root-cases
                 root
                 :names '("london/phase-a-state-sample.json/phase_a_london_state_sample")))))
    (assert-eest-state-test-case case)))

(deftest eest-state-test-root-london-access-list-vector-executes
  (let* ((root (execution-spec-tests-state-test-root
                "tests/fixtures/execution-spec-tests-root/"))
         (case (first
                (load-eest-state-test-root-cases
                 root
                 :names '("london/phase-a-state-sample.json/phase_a_london_access_list_state_sample")))))
    (assert-eest-state-test-case case)))
