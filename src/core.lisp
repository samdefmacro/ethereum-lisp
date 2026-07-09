(in-package #:ethereum-lisp.core)

(defun genesis-alloc-from-genesis-json-string (string)
  (genesis-alloc-from-genesis-object (parse-json string)))

(defun genesis-alloc-from-genesis-json-file (path)
  (genesis-alloc-from-genesis-json-string (read-text-file path)))

(defun genesis-expected-state-root-from-genesis-object (object)
  (let ((state-root (genesis-object-field object "stateRoot")))
    (when state-root
      (unless (stringp state-root)
        (block-validation-fail "Genesis stateRoot must be a hash32"))
      (handler-case
          (hash32-from-hex state-root)
        (error ()
          (block-validation-fail "Genesis stateRoot must be a hash32"))))))

(defun genesis-expected-state-root-from-genesis-json-string (string)
  (genesis-expected-state-root-from-genesis-object (parse-json string)))

(defun genesis-expected-state-root-from-genesis-json-file (path)
  (genesis-expected-state-root-from-genesis-json-string (read-text-file path)))

(defun parse-genesis-hash32-field (object name label &key default)
  (let ((value (if (listp name)
                   (genesis-object-field-any object name)
                   (genesis-object-field object name))))
    (cond
      ((null value) default)
      ((stringp value)
       (handler-case
           (hash32-from-hex value)
         (error ()
           (block-validation-fail "~A must be a hash32" label))))
      (t (block-validation-fail "~A must be a hash32" label)))))

(defun parse-genesis-bytes-field (object name label &key default)
  (let ((value (if (listp name)
                   (genesis-object-field-any object name)
                   (genesis-object-field object name))))
    (cond
      ((null value) default)
      ((stringp value)
       (handler-case
           (hex-to-bytes value)
         (error ()
           (block-validation-fail "~A must be hex bytes" label))))
      (t (block-validation-fail "~A must be hex bytes" label)))))

(defun genesis-uint64-field (object name label &key default)
  (let ((value (parse-genesis-field object name :label label)))
    (cond
      ((null value) default)
      ((< value (expt 2 64)) value)
      (t (block-validation-fail "~A must be uint64" label)))))

(defun uint64-to-8-byte-vector (value label)
  (unless (and (integerp value) (<= 0 value) (< value (expt 2 64)))
    (block-validation-fail "~A must be uint64" label))
  (let ((out (make-byte-vector 8)))
    (dotimes (index 8 out)
      (setf (aref out (- 7 index)) (logand value #xff)
            value (ash value -8)))))

(defun genesis-config-from-genesis-object (object &key config)
  (or config
      (let ((config-object (genesis-object-field object "config")))
        (and config-object (chain-config-from-genesis-config config-object)))))

(defun genesis-header-from-genesis-object (object &key state-root config)
  (let* ((config (genesis-config-from-genesis-object object :config config))
         (number (genesis-uint64-field object "number" "Genesis number"
                                       :default 0))
         (timestamp (genesis-uint64-field object "timestamp" "Genesis timestamp"
                                          :default 0))
         (raw-gas-limit (genesis-uint64-field object "gasLimit"
                                              "Genesis gas limit"
                                              :default +genesis-gas-limit+))
         (gas-limit (if (zerop raw-gas-limit)
                        +genesis-gas-limit+
                        raw-gas-limit))
         (gas-used (genesis-uint64-field object "gasUsed" "Genesis gas used"
                                         :default 0))
         (difficulty (or (parse-genesis-field object "difficulty"
                                              :label "Genesis difficulty")
                         (and config
                              (eql 0
                                   (chain-config-terminal-total-difficulty
                                    config))
                              0)
                         +genesis-difficulty+))
         (base-fee (parse-genesis-field object "baseFeePerGas"
                                        :label "Genesis base fee"))
         (parent-beacon-root (parse-genesis-hash32-field
                              object '("parentBeaconBlockRoot"
                                       "parentBeaconRoot")
                              "Genesis parent beacon block root"))
         (block-access-list-hash (parse-genesis-hash32-field
                                  object '("balHash"
                                           "blockAccessListHash")
                                  "Genesis block access list hash"))
         (slot-number (genesis-uint64-field object "slotNumber"
                                            "Genesis slot number"))
         (header
           (make-block-header
            :parent-hash (parse-genesis-hash32-field
                          object "parentHash" "Genesis parent hash"
                          :default (zero-hash32))
            :ommers-hash +empty-ommers-hash+
            :beneficiary (parse-genesis-address-field
                          object "coinbase" "Genesis coinbase"
                          :default (zero-address))
            :state-root (or state-root
                            (genesis-expected-state-root-from-genesis-object object)
                            +empty-trie-hash+)
            :transactions-root +empty-trie-hash+
            :receipts-root +empty-trie-hash+
            :logs-bloom (make-byte-vector 256)
            :difficulty difficulty
            :number number
            :gas-limit gas-limit
            :gas-used gas-used
            :timestamp timestamp
            :extra-data (parse-genesis-bytes-field
                         object "extraData" "Genesis extra data"
                         :default (make-byte-vector 0))
            :mix-hash (parse-genesis-hash32-field
                       object '("mixHash" "mixhash") "Genesis mix hash"
                       :default (zero-hash32))
            :nonce (uint64-to-8-byte-vector
                    (genesis-uint64-field object "nonce" "Genesis nonce"
                                          :default 0)
                    "Genesis nonce")
            :base-fee-per-gas base-fee
            :blob-gas-used (genesis-uint64-field
                            object "blobGasUsed" "Genesis blob gas used")
            :excess-blob-gas (genesis-uint64-field
                              object "excessBlobGas"
                              "Genesis excess blob gas")
            :block-access-list-hash block-access-list-hash
            :slot-number slot-number)))
    (when (and config
               (chain-config-london-p config number)
               (null (block-header-base-fee-per-gas header)))
      (setf (block-header-base-fee-per-gas header) +initial-base-fee+))
    (when (and config (chain-config-shanghai-p config number timestamp))
      (setf (block-header-withdrawals-root header) (withdrawal-list-root '())))
    (when (and config (chain-config-cancun-p config number timestamp))
      (setf (block-header-parent-beacon-root header)
            (or parent-beacon-root (zero-hash32)))
      (unless (block-header-excess-blob-gas header)
        (setf (block-header-excess-blob-gas header) 0))
      (unless (block-header-blob-gas-used header)
        (setf (block-header-blob-gas-used header) 0)))
    (when (and config (chain-config-prague-p config number timestamp))
      (setf (block-header-requests-hash header) (execution-requests-hash '())))
    (when (and config (chain-config-amsterdam-p config number timestamp))
      (unless (block-header-block-access-list-hash header)
        (setf (block-header-block-access-list-hash header) +empty-ommers-hash+))
      (unless (block-header-slot-number header)
        (setf (block-header-slot-number header) 0)))
    header))

(defun genesis-header-from-genesis-json-string (string &key state-root config)
  (genesis-header-from-genesis-object (parse-json string)
                                      :state-root state-root
                                      :config config))

(defun genesis-header-from-genesis-json-file (path &key state-root config)
  (genesis-header-from-genesis-json-string (read-text-file path)
                                           :state-root state-root
                                           :config config))

(defun genesis-block-from-genesis-header (header)
  (let ((args (list :header header)))
    (when (block-header-withdrawals-root header)
      (setf args (append args (list :withdrawals '()))))
    (when (block-header-requests-hash header)
      (setf args (append args (list :requests '()))))
    (when (block-header-block-access-list-hash header)
      (setf args (append args (list :block-access-list '()))))
    (apply #'make-block args)))

(defun genesis-block-from-genesis-object (object &key state-root config)
  (genesis-block-from-genesis-header
   (genesis-header-from-genesis-object object
                                       :state-root state-root
                                       :config config)))

(defun genesis-block-from-genesis-json-string (string &key state-root config)
  (genesis-block-from-genesis-object (parse-json string)
                                     :state-root state-root
                                     :config config))

(defun genesis-block-from-genesis-json-file (path &key state-root config)
  (genesis-block-from-genesis-json-string (read-text-file path)
                                          :state-root state-root
                                          :config config))

(defstruct (block-header (:constructor make-block-header
                            (&key parent-hash
                                  ommers-hash
                                  beneficiary
                                  state-root
                                  transactions-root
                                  receipts-root
                                  logs-bloom
                                  (difficulty 0)
                                  (number 0)
                                  (gas-limit 0)
                                  (gas-used 0)
                                  (timestamp 0)
                                  (extra-data #())
                                  mix-hash
                                  nonce
                                  base-fee-per-gas
                                  withdrawals-root
                                  blob-gas-used
                                  excess-blob-gas
                                  parent-beacon-root
                                  requests-hash
                                  block-access-list-hash
                                  slot-number)))
  parent-hash
  ommers-hash
  beneficiary
  state-root
  transactions-root
  receipts-root
  logs-bloom
  (difficulty 0 :type (integer 0 *))
  (number 0 :type (integer 0 *))
  (gas-limit 0 :type (integer 0 *))
  (gas-used 0 :type (integer 0 *))
  (timestamp 0 :type (integer 0 *))
  (extra-data (make-byte-vector 0))
  mix-hash
  nonce
  base-fee-per-gas
  withdrawals-root
  blob-gas-used
  excess-blob-gas
  parent-beacon-root
  requests-hash
  block-access-list-hash
  slot-number)

(defun hash-or-zero (hash)
  (hash32-bytes (or hash (zero-hash32))))

(defun address-or-zero (address)
  (address-bytes (or address (zero-address))))

(defun header-fields (header)
  (let ((fields
          (list
           (hash-or-zero (block-header-parent-hash header))
           (hash32-bytes (or (block-header-ommers-hash header) +empty-ommers-hash+))
           (address-or-zero (block-header-beneficiary header))
           (hash32-bytes (or (block-header-state-root header) +empty-trie-hash+))
           (hash32-bytes (or (block-header-transactions-root header) +empty-trie-hash+))
           (hash32-bytes (or (block-header-receipts-root header) +empty-trie-hash+))
           (optional-bytes (or (block-header-logs-bloom header) (make-byte-vector 256))
                           256 "Logs bloom")
           (ensure-uint256 (block-header-difficulty header) "Header difficulty")
           (ensure-uint256 (block-header-number header) "Header number")
           (ensure-uint256 (block-header-gas-limit header) "Header gas limit")
           (ensure-uint256 (block-header-gas-used header) "Header gas used")
           (ensure-uint256 (block-header-timestamp header) "Header timestamp")
           (ensure-byte-vector (block-header-extra-data header))
           (hash-or-zero (block-header-mix-hash header))
           (optional-bytes (or (block-header-nonce header) (make-byte-vector 8))
                           8 "Header nonce"))))
    (when (block-header-base-fee-per-gas header)
      (setf fields (append fields
                           (list (ensure-uint256
                                  (block-header-base-fee-per-gas header)
                                  "Header base fee")))))
    (when (block-header-withdrawals-root header)
      (setf fields (append fields
                           (list (hash32-bytes
                                  (block-header-withdrawals-root header))))))
    (when (block-header-blob-gas-used header)
      (setf fields (append fields
                           (list (ensure-uint256
                                  (block-header-blob-gas-used header)
                                  "Header blob gas used")
                                 (ensure-uint256
                                  (or (block-header-excess-blob-gas header) 0)
                                  "Header excess blob gas")))))
    (when (block-header-parent-beacon-root header)
      (setf fields (append fields
                           (list (hash32-bytes
                                  (block-header-parent-beacon-root header))))))
    (when (block-header-requests-hash header)
      (setf fields (append fields
                           (list (hash32-bytes
                                  (block-header-requests-hash header))))))
    (when (or (block-header-block-access-list-hash header)
              (block-header-slot-number header))
      (setf fields (append fields
                           (list (if (block-header-block-access-list-hash
                                      header)
                                     (hash32-bytes
                                      (block-header-block-access-list-hash
                                       header))
                                     (make-byte-vector 0))))))
    (when (block-header-slot-number header)
      (setf fields (append fields
                           (list (ensure-uint256
                                  (block-header-slot-number header)
                                  "Header slot number")))))
    fields))

(defun block-header-rlp-object (header)
  (apply #'make-rlp-list (header-fields header)))

(defun block-header-rlp (header)
  (rlp-encode (block-header-rlp-object header)))

(defun block-header-hash (header)
  (keccak-256-hash (block-header-rlp header)))

(defun ommers-hash (ommers)
  (keccak-256-hash
   (rlp-encode
    (mapcar #'block-header-rlp-object ommers))))

(defun receipts-logs-bloom (receipts)
  (receipt-bloom
   (loop for receipt in receipts
         append (receipt-logs receipt))))

(defstruct (ethereum-block (:constructor %make-block
                             (&key header
                                   (transactions '())
                                   (receipts '())
                                   (ommers '())
                                   withdrawals
                                   withdrawals-present-p
                                   requests
                                   requests-present-p
                                   block-access-list
                                   block-access-list-present-p
                                   encoded-block-access-list))
                           (:conc-name block-))
  header
  (transactions '() :type list)
  (receipts '() :type list)
  (ommers '() :type list)
  withdrawals
  withdrawals-present-p
  requests
  requests-present-p
  block-access-list
  block-access-list-present-p
  encoded-block-access-list)

(defun make-block (&key (header (make-block-header))
                        (transactions '())
                        (receipts '())
                        (ommers '())
                        (withdrawals nil withdrawals-supplied-p)
                        (requests nil requests-supplied-p)
                        (block-access-list nil block-access-list-supplied-p)
                        (block-access-list-rlp nil
                         block-access-list-rlp-supplied-p))
  (let ((encoded-block-access-list nil))
    (when (and block-access-list-supplied-p
               block-access-list-rlp-supplied-p)
      (block-validation-fail
       "Block access list cannot be supplied as both typed data and RLP"))
    (when block-access-list-rlp-supplied-p
      (setf encoded-block-access-list
            (block-access-list-rlp-input-bytes block-access-list-rlp)
            block-access-list
            (block-access-list-from-rlp encoded-block-access-list)
            block-access-list-supplied-p t))
    (setf (block-header-transactions-root header)
          (transaction-list-root transactions)
          (block-header-receipts-root header)
          (if (= (length transactions) (length receipts))
              (transaction-receipt-list-root transactions receipts)
              (receipt-list-root receipts))
          (block-header-logs-bloom header)
          (bloom-bytes (receipts-logs-bloom receipts))
          (block-header-ommers-hash header)
          (ommers-hash ommers))
    (when withdrawals-supplied-p
      (setf (block-header-withdrawals-root header)
            (withdrawal-list-root withdrawals)))
    (when requests-supplied-p
      (setf (block-header-requests-hash header)
            (execution-requests-hash requests)))
    (when block-access-list-supplied-p
      (unless encoded-block-access-list
        (validate-block-access-list-fields block-access-list)
        (setf encoded-block-access-list
              (block-access-list-rlp block-access-list)))
      (setf (block-header-block-access-list-hash header)
            (keccak-256-hash encoded-block-access-list)))
    (%make-block :header header
                 :transactions transactions
                 :receipts receipts
                 :ommers ommers
                 :withdrawals withdrawals
                 :withdrawals-present-p withdrawals-supplied-p
                 :requests requests
                 :requests-present-p requests-supplied-p
                 :block-access-list block-access-list
                 :block-access-list-present-p block-access-list-supplied-p
                 :encoded-block-access-list encoded-block-access-list)))

(defun block-hash (block)
  (block-header-hash (block-header block)))

(defun rlp-list-field (value label)
  (unless (rlp-list-p value)
    (block-validation-fail "~A must be an RLP list" label))
  (rlp-list-items value))

(defun rlp-sized-bytes-field (value size label)
  (let ((bytes (rlp-bytes-field value label)))
    (unless (= (length bytes) size)
      (block-validation-fail "~A must be exactly ~D bytes" label size))
    bytes))

(defun rlp-hash32-field (value label)
  (make-hash32 (rlp-sized-bytes-field value 32 label)))

(defun rlp-address-field (value label)
  (make-address (rlp-sized-bytes-field value 20 label)))

(defun block-header-from-rlp-object (value)
  (let ((fields (rlp-list-field value "Block header")))
    (unless (member (length fields) '(15 16 17 20 21 22 23))
      (block-validation-fail
       "Block header RLP must contain a supported fork field count"))
    (make-block-header
     :parent-hash (rlp-hash32-field (first fields) "Header parent hash")
     :ommers-hash (rlp-hash32-field (second fields) "Header ommers hash")
     :beneficiary (rlp-address-field (third fields) "Header beneficiary")
     :state-root (rlp-hash32-field (fourth fields) "Header state root")
     :transactions-root (rlp-hash32-field
                         (fifth fields)
                         "Header transactions root")
     :receipts-root (rlp-hash32-field (sixth fields) "Header receipts root")
     :logs-bloom (rlp-sized-bytes-field
                  (seventh fields)
                  256
                  "Header logs bloom")
     :difficulty (rlp-uint-field (eighth fields) "Header difficulty")
     :number (rlp-uint-field (nth 8 fields) "Header number")
     :gas-limit (rlp-uint-field (nth 9 fields) "Header gas limit")
     :gas-used (rlp-uint-field (nth 10 fields) "Header gas used")
     :timestamp (rlp-uint-field (nth 11 fields) "Header timestamp")
     :extra-data (rlp-bytes-field (nth 12 fields) "Header extra data")
     :mix-hash (rlp-hash32-field (nth 13 fields) "Header mix hash")
     :nonce (rlp-sized-bytes-field (nth 14 fields) 8 "Header nonce")
     :base-fee-per-gas
     (when (> (length fields) 15)
       (rlp-uint-field (nth 15 fields) "Header base fee per gas"))
     :withdrawals-root
     (when (> (length fields) 16)
       (rlp-hash32-field (nth 16 fields) "Header withdrawals root"))
     :blob-gas-used
     (when (> (length fields) 17)
       (rlp-uint-field (nth 17 fields) "Header blob gas used"))
     :excess-blob-gas
     (when (> (length fields) 18)
       (rlp-uint-field (nth 18 fields) "Header excess blob gas"))
     :parent-beacon-root
     (when (> (length fields) 19)
       (rlp-hash32-field (nth 19 fields) "Header parent beacon root"))
     :requests-hash
     (when (> (length fields) 20)
       (rlp-hash32-field (nth 20 fields) "Header requests hash"))
     :block-access-list-hash
     (when (> (length fields) 21)
       (let ((bytes (rlp-bytes-field (nth 21 fields)
                                     "Header block access list hash")))
         (unless (or (zerop (length bytes)) (= 32 (length bytes)))
           (block-validation-fail
            "Header block access list hash must be empty or 32 bytes"))
         (when (= 32 (length bytes))
           (make-hash32 bytes))))
     :slot-number
     (when (> (length fields) 22)
       (rlp-uint-field (nth 22 fields) "Header slot number")))))

(defun withdrawal-from-rlp-object (value)
  (let ((fields (rlp-list-field value "Withdrawal")))
    (unless (= (length fields) 4)
      (block-validation-fail "Withdrawal RLP must contain 4 fields"))
    (make-withdrawal
     :index (rlp-uint-field (first fields) "Withdrawal index")
     :validator-index
     (rlp-uint-field (second fields) "Withdrawal validator index")
     :address (rlp-address-field (third fields) "Withdrawal address")
     :amount (rlp-uint-field (fourth fields) "Withdrawal amount"))))

(defun block-transactions-from-rlp-object (value)
  (mapcar
   (lambda (transaction)
     (transaction-from-encoding
      (if (rlp-list-p transaction)
          (rlp-encode transaction)
          (rlp-bytes-field transaction "Block transaction"))))
   (rlp-list-field value "Block transactions")))

(defun block-ommers-from-rlp-object (value)
  (mapcar #'block-header-from-rlp-object
          (rlp-list-field value "Block ommers")))

(defun block-withdrawals-from-rlp-object (value)
  (mapcar #'withdrawal-from-rlp-object
          (rlp-list-field value "Block withdrawals")))

(defun block-requests-from-rlp-object (value)
  (mapcar #'rlp-encode (rlp-list-field value "Block requests")))

(defun block-from-rlp (bytes)
  (let* ((decoded (rlp-decode-one bytes))
         (items (rlp-list-field decoded "Block")))
    (unless (member (length items) '(3 4 5 6))
      (block-validation-fail "Block RLP must contain 3 to 6 fields"))
    (let ((withdrawals-present-p (> (length items) 3))
          (requests-present-p (> (length items) 4))
          (block-access-list-present-p (> (length items) 5)))
      (%make-block
       :header (block-header-from-rlp-object (first items))
       :transactions (block-transactions-from-rlp-object (second items))
       :ommers (block-ommers-from-rlp-object (third items))
       :withdrawals (when withdrawals-present-p
                      (block-withdrawals-from-rlp-object (fourth items)))
       :withdrawals-present-p withdrawals-present-p
       :requests (when requests-present-p
                   (block-requests-from-rlp-object (nth 4 items)))
       :requests-present-p requests-present-p
       :block-access-list (when block-access-list-present-p
                            (block-access-list-from-rlp
                             (rlp-encode (nth 5 items))))
       :block-access-list-present-p block-access-list-present-p
       :encoded-block-access-list (when block-access-list-present-p
                                    (rlp-encode (nth 5 items)))))))

(defun block-transaction-rlp-object (transaction)
  (let ((encoded (transaction-encoding transaction)))
    (if (> (aref encoded 0) #x7f)
        (rlp-decode-one encoded)
        encoded)))

(defun block-transactions-rlp-object (transactions)
  (apply #'make-rlp-list
         (mapcar #'block-transaction-rlp-object transactions)))

(defun block-ommers-rlp-object (ommers)
  (apply #'make-rlp-list
         (mapcar #'block-header-rlp-object ommers)))

(defun block-withdrawals-rlp-object (withdrawals)
  (apply #'make-rlp-list
         (mapcar #'withdrawal-rlp-object withdrawals)))

(defun block-requests-rlp-object (requests)
  (apply #'make-rlp-list
         (mapcar #'rlp-decode-one requests)))

(defun block-access-list-rlp-object-for-block (block)
  (rlp-decode-one
   (or (block-encoded-block-access-list block)
       (block-access-list-rlp (block-block-access-list block)))))

(defun block-rlp (block)
  (let ((fields
          (list (block-header-rlp-object (block-header block))
                (block-transactions-rlp-object
                 (block-transactions block))
                (block-ommers-rlp-object (block-ommers block)))))
    (when (block-withdrawals-present-p block)
      (setf fields
            (append fields
                    (list (block-withdrawals-rlp-object
                           (block-withdrawals block))))))
    (when (block-requests-present-p block)
      (setf fields
            (append fields
                    (list (block-requests-rlp-object
                           (block-requests block))))))
    (when (block-block-access-list-present-p block)
      (setf fields
            (append fields
                    (list (block-access-list-rlp-object-for-block block)))))
    (rlp-encode (apply #'make-rlp-list fields))))

(defstruct (executable-data (:constructor make-executable-data
                              (&key parent-hash
                                    fee-recipient
                                    state-root
                                    receipts-root
                                    logs-bloom
                                    random
                                    number
                                    gas-limit
                                    gas-used
                                    timestamp
                                    extra-data
                                    base-fee-per-gas
                                    block-hash
                                    transactions
                                    withdrawals
                                    withdrawals-present-p
                                    blob-gas-used
                                    excess-blob-gas
                                    slot-number
                                    block-access-list)))
  parent-hash
  fee-recipient
  state-root
  receipts-root
  logs-bloom
  random
  number
  gas-limit
  gas-used
  timestamp
  extra-data
  base-fee-per-gas
  block-hash
  (transactions '() :type list)
  withdrawals
  withdrawals-present-p
  blob-gas-used
  excess-blob-gas
  slot-number
  block-access-list)

(defstruct (execution-payload-envelope
            (:constructor make-execution-payload-envelope
                (&key execution-payload
                      (block-value 0)
                      blobs-bundle
                      requests
                      override-p)))
  execution-payload
  (block-value 0 :type (integer 0 *))
  blobs-bundle
  requests
  override-p)

(defparameter +payload-status-valid+ "VALID")
(defparameter +payload-status-invalid+ "INVALID")
(defparameter +payload-status-syncing+ "SYNCING")
(defparameter +payload-status-accepted+ "ACCEPTED")
(defconstant +eth-protocol-version+ 70)

(defstruct (payload-status
            (:constructor make-payload-status
                (&key status latest-valid-hash validation-error witness)))
  status
  latest-valid-hash
  validation-error
  witness)

(defstruct (forkchoice-state
            (:constructor make-forkchoice-state
                (&key head-block-hash safe-block-hash finalized-block-hash)))
  head-block-hash
  safe-block-hash
  finalized-block-hash)

(defstruct (payload-attributes-v1
            (:constructor make-payload-attributes-v1
                (&key timestamp prev-randao suggested-fee-recipient
                      withdrawals withdrawals-present-p
                      parent-beacon-root parent-beacon-root-present-p
                      slot-number slot-number-present-p)))
  timestamp
  prev-randao
  suggested-fee-recipient
  withdrawals
  withdrawals-present-p
  parent-beacon-root
  parent-beacon-root-present-p
  slot-number
  slot-number-present-p)

(defstruct (engine-prepared-payload
            (:constructor make-engine-prepared-payload
                (&key payload-id version block blobs-bundle)))
  payload-id
  version
  block
  blobs-bundle)

(defun validate-engine-prepared-payload-blobs-bundle (bundle)
  (when bundle
    (unless (typep bundle 'blob-sidecar)
      (block-validation-fail
       "Engine prepared payload blobs bundle must be a blob-sidecar"))
    (handler-case
        (progn
          (mapcar #'ensure-byte-vector (blob-sidecar-blobs bundle))
          (mapcar #'ensure-byte-vector (blob-sidecar-commitments bundle))
          (mapcar #'ensure-byte-vector (blob-sidecar-proofs bundle)))
      (error ()
        (block-validation-fail
         "Engine prepared payload blobs bundle entries must be byte vectors"))))
  bundle)

(defun validate-engine-prepared-payload (prepared-payload)
  (unless (typep prepared-payload 'engine-prepared-payload)
    (block-validation-fail
     "Engine prepared payload must be an engine-prepared-payload"))
  (let ((payload-id
          (validate-sized-byte-vector
           (engine-prepared-payload-payload-id prepared-payload)
           8
           "Engine prepared payload id"))
        (version (engine-prepared-payload-version prepared-payload)))
    (unless (and (integerp version) (<= 1 version 6))
      (block-validation-fail
       "Engine prepared payload version must be between 1 and 6"))
    (unless (= version (aref payload-id 0))
      (block-validation-fail
       "Engine prepared payload id version does not match payload version"))
    (unless (typep (engine-prepared-payload-block prepared-payload)
                   'ethereum-block)
      (block-validation-fail
       "Engine prepared payload block must be an ethereum-block"))
    (validate-engine-prepared-payload-blobs-bundle
     (engine-prepared-payload-blobs-bundle prepared-payload))
    prepared-payload))

(defun maybe-copy-bytes (bytes)
  (when bytes
    (copy-seq (ensure-byte-vector bytes))))

(defun maybe-copy-withdrawals (withdrawals)
  (when withdrawals
    (mapcar #'copy-withdrawal withdrawals)))

(defun maybe-copy-requests (requests)
  (when requests
    (mapcar #'maybe-copy-bytes requests)))

(defun maybe-copy-blob-sidecar (sidecar)
  (when sidecar
    (unless (typep sidecar 'blob-sidecar)
      (block-validation-fail "Blob sidecar must be a blob-sidecar"))
    (make-blob-sidecar
     :blobs (mapcar #'maybe-copy-bytes (blob-sidecar-blobs sidecar))
     :commitments (mapcar #'maybe-copy-bytes
                           (blob-sidecar-commitments sidecar))
     :proofs (mapcar #'maybe-copy-bytes (blob-sidecar-proofs sidecar)))))

(defun block-to-executable-data
    (block &key (block-value 0) requests blobs-bundle)
  (let* ((header (block-header block))
         (payload
           (make-executable-data
            :block-hash (block-hash block)
            :parent-hash (or (block-header-parent-hash header) (zero-hash32))
            :fee-recipient (or (block-header-beneficiary header)
                               (zero-address))
            :state-root (or (block-header-state-root header) +empty-trie-hash+)
            :receipts-root (or (block-header-receipts-root header)
                               +empty-trie-hash+)
            :logs-bloom (maybe-copy-bytes
                         (or (block-header-logs-bloom header)
                             (make-byte-vector 256)))
            :random (or (block-header-mix-hash header) (zero-hash32))
            :number (block-header-number header)
            :gas-limit (block-header-gas-limit header)
            :gas-used (block-header-gas-used header)
            :timestamp (block-header-timestamp header)
            :extra-data (maybe-copy-bytes (block-header-extra-data header))
            :base-fee-per-gas (or (block-header-base-fee-per-gas header) 0)
            :transactions (mapcar (lambda (transaction)
                                    (copy-seq
                                     (transaction-encoding transaction)))
                                  (block-transactions block))
            :withdrawals (when (block-withdrawals-present-p block)
                           (maybe-copy-withdrawals
                            (block-withdrawals block)))
            :withdrawals-present-p (block-withdrawals-present-p block)
            :blob-gas-used (block-header-blob-gas-used header)
            :excess-blob-gas (block-header-excess-blob-gas header)
            :slot-number (block-header-slot-number header)
            :block-access-list
            (when (block-block-access-list-present-p block)
              (maybe-copy-bytes (block-encoded-block-access-list block)))))
         (payload-requests
           (cond
             (requests (maybe-copy-requests requests))
             ((block-requests-present-p block)
              (maybe-copy-requests (block-requests block)))
             (t nil))))
    (make-execution-payload-envelope
     :execution-payload payload
     :block-value block-value
     :blobs-bundle (maybe-copy-blob-sidecar blobs-bundle)
     :requests payload-requests
     :override-p nil)))

(defun executable-data-decoded-transactions (payload)
  (unless (typep payload 'executable-data)
    (block-validation-fail "Executable data payload must be executable-data"))
  (let ((transactions (executable-data-transactions payload)))
    (unless (listp transactions)
      (block-validation-fail "Executable data transactions must be a list"))
    (loop for encoded in transactions
          for index from 0
          collect
          (handler-case
              (transaction-from-encoding
               (validate-byte-sequence-field
                encoded
                (format nil "Executable data transaction ~D" index)))
            (block-validation-error (condition)
              (block-validation-fail
               "Invalid executable data transaction ~D: ~A"
               index condition))))))

(defun executable-data-blob-versioned-hashes (transactions)
  (loop for transaction in transactions
        append (coerce (transaction-blob-versioned-hashes transaction)
                       'list)))

(defun engine-new-payload-require-transaction-senders (block config)
  (let ((chain-id (chain-config-chain-id config)))
    (loop for transaction in (block-transactions block)
          for index from 0
          unless (transaction-sender transaction
                                     :expected-chain-id chain-id)
            do (block-validation-fail
                "Invalid executable data transaction ~D sender"
                index)))
  t)

(defun validate-executable-data-versioned-hashes
    (transactions versioned-hashes)
  (unless (listp versioned-hashes)
    (block-validation-fail "Executable data versioned hashes must be a list"))
  (let ((blob-hashes (executable-data-blob-versioned-hashes transactions)))
    (unless (= (length blob-hashes) (length versioned-hashes))
      (block-validation-fail
       "Executable data versioned hash count mismatch"))
    (loop for blob-hash in blob-hashes
          for versioned-hash in versioned-hashes
          for index from 0
          do (unless (hash32-p versioned-hash)
               (block-validation-fail
                "Executable data versioned hash ~D must be a hash32"
                index))
             (unless (hash32= blob-hash versioned-hash)
               (block-validation-fail
                "Executable data versioned hash ~D mismatch"
                index))))
  t)

(defun executable-data-required-hash32 (value label)
  (unless (hash32-p value)
    (block-validation-fail "~A must be a hash32" label))
  value)

(defun executable-data-required-address (value label)
  (unless (address-p value)
    (block-validation-fail "~A must be an address" label))
  value)

(defun executable-data-required-uint256 (value label)
  (unless (uint256-p value)
    (block-validation-fail "~A must be uint256" label))
  value)

(defun executable-data-to-block-no-hash
    (payload &key parent-beacon-root (versioned-hashes nil)
               (requests nil requests-supplied-p))
  (unless (typep payload 'executable-data)
    (block-validation-fail "Executable data payload must be executable-data"))
  (let* ((transactions (executable-data-decoded-transactions payload))
         (withdrawals (executable-data-withdrawals payload))
         (withdrawals-present-p
           (or (executable-data-withdrawals-present-p payload)
               (not (null withdrawals))))
         (extra-data (validate-byte-sequence-field
                      (executable-data-extra-data payload)
                      "Executable data extra data"))
         (logs-bloom (validate-byte-sequence-field
                      (executable-data-logs-bloom payload)
                      "Executable data logs bloom"
                      :size 256))
         (encoded-block-access-list
           (when (executable-data-block-access-list payload)
             (block-access-list-rlp-input-bytes
              (executable-data-block-access-list payload))))
         (block-access-list
           (when encoded-block-access-list
             (block-access-list-from-rlp encoded-block-access-list))))
    (when (> (length extra-data) +maximum-extra-data-size+)
      (block-validation-fail "Executable data extra data too long"))
    (when withdrawals-present-p
      (validate-withdrawal-list-fields withdrawals))
    (validate-executable-data-versioned-hashes transactions versioned-hashes)
    (validate-optional-hash32-field parent-beacon-root
                                    "Executable data parent beacon root")
    (when requests-supplied-p
      (validate-execution-request-list-fields requests))
    (let ((header
            (make-block-header
             :parent-hash
             (executable-data-required-hash32
              (executable-data-parent-hash payload)
              "Executable data parent hash")
             :ommers-hash +empty-ommers-hash+
             :beneficiary
             (executable-data-required-address
              (executable-data-fee-recipient payload)
              "Executable data fee recipient")
             :state-root
             (executable-data-required-hash32
              (executable-data-state-root payload)
              "Executable data state root")
             :transactions-root (transaction-list-root transactions)
             :receipts-root
             (executable-data-required-hash32
              (executable-data-receipts-root payload)
              "Executable data receipts root")
             :logs-bloom (copy-seq logs-bloom)
             :difficulty 0
             :number
             (executable-data-required-uint256
              (executable-data-number payload)
              "Executable data block number")
             :gas-limit
             (executable-data-required-uint256
              (executable-data-gas-limit payload)
              "Executable data gas limit")
             :gas-used
             (executable-data-required-uint256
              (executable-data-gas-used payload)
              "Executable data gas used")
             :timestamp
             (executable-data-required-uint256
              (executable-data-timestamp payload)
              "Executable data timestamp")
             :extra-data (copy-seq extra-data)
             :mix-hash
             (executable-data-required-hash32
              (executable-data-random payload)
              "Executable data random")
             :base-fee-per-gas
             (executable-data-required-uint256
              (executable-data-base-fee-per-gas payload)
              "Executable data base fee")
             :withdrawals-root (when withdrawals-present-p
                                 (withdrawal-list-root withdrawals))
             :blob-gas-used (executable-data-blob-gas-used payload)
             :excess-blob-gas (executable-data-excess-blob-gas payload)
             :parent-beacon-root parent-beacon-root
             :requests-hash (when requests-supplied-p
                              (execution-requests-hash requests))
             :block-access-list-hash
             (when encoded-block-access-list
               (keccak-256-hash encoded-block-access-list))
             :slot-number (executable-data-slot-number payload))))
      (validate-optional-uint256-field (block-header-blob-gas-used header)
                                       "Executable data blob gas used")
      (validate-optional-uint256-field (block-header-excess-blob-gas header)
                                       "Executable data excess blob gas")
      (validate-optional-uint256-field (block-header-slot-number header)
                                       "Executable data slot number")
      (%make-block :header header
                   :transactions transactions
                   :ommers '()
                   :withdrawals withdrawals
                   :withdrawals-present-p withdrawals-present-p
                   :requests requests
                   :requests-present-p requests-supplied-p
                   :block-access-list block-access-list
                   :block-access-list-present-p
                   (not (null encoded-block-access-list))
                   :encoded-block-access-list encoded-block-access-list))))

(defun executable-data-to-block
    (payload &key parent-beacon-root (versioned-hashes nil)
               (requests nil requests-supplied-p))
  (let* ((block (if requests-supplied-p
                    (executable-data-to-block-no-hash
                     payload
                     :parent-beacon-root parent-beacon-root
                     :versioned-hashes versioned-hashes
                     :requests requests)
                    (executable-data-to-block-no-hash
                     payload
                     :parent-beacon-root parent-beacon-root
                     :versioned-hashes versioned-hashes)))
         (expected-hash
           (executable-data-required-hash32
            (executable-data-block-hash payload)
            "Executable data block hash")))
    (unless (hash32= (block-hash block) expected-hash)
      (block-validation-fail "Executable data block hash mismatch"))
    block))

(defun engine-new-payload-params-status
    (payload &key parent-beacon-root (versioned-hashes nil)
               (requests nil requests-supplied-p))
  (handler-case
      (let ((block
              (if requests-supplied-p
                  (executable-data-to-block
                   payload
                   :parent-beacon-root parent-beacon-root
                   :versioned-hashes versioned-hashes
                   :requests requests)
                  (executable-data-to-block
                   payload
                   :parent-beacon-root parent-beacon-root
                   :versioned-hashes versioned-hashes))))
        (values
         (make-payload-status :status +payload-status-valid+
                              :latest-valid-hash (block-hash block))
         block))
    (block-validation-error (condition)
      (values
       (make-payload-status
        :status +payload-status-invalid+
        :validation-error (block-validation-error-message condition))
       nil))))

(defun invalid-payload-status (message)
  (make-payload-status :status +payload-status-invalid+
                       :validation-error message))

(defun forkchoice-state-zero-head-status ()
  (invalid-payload-status "forkchoice head block hash is zero"))

(defun engine-new-payload-version-invalid-p
    (version payload config versioned-hashes-supplied-p
             parent-beacon-root-supplied-p requests-supplied-p)
  (let* ((number (executable-data-number payload))
         (timestamp (executable-data-timestamp payload))
         (withdrawals (executable-data-withdrawals payload))
         (withdrawals-present-p
           (or (executable-data-withdrawals-present-p payload)
               (not (null withdrawals))))
         (shanghai-p (chain-config-shanghai-p config number timestamp))
         (cancun-p (chain-config-cancun-p config number timestamp))
         (prague-p (chain-config-prague-p config number timestamp))
         (amsterdam-p (chain-config-amsterdam-p config number timestamp)))
    (cond
      ((= version 1)
       (when withdrawals-present-p
         "withdrawals not supported in newPayloadV1"))
      ((= version 2)
       (cond
         (cancun-p "newPayloadV2 cannot be used after Cancun")
         ((and shanghai-p (not withdrawals-present-p))
          "withdrawals required after Shanghai")
         ((and (not shanghai-p) withdrawals-present-p)
          "withdrawals not supported before Shanghai")
         ((executable-data-excess-blob-gas payload)
          "excessBlobGas not supported before Cancun")
         ((executable-data-blob-gas-used payload)
          "blobGasUsed not supported before Cancun")))
      ((= version 3)
       (cond
         ((not withdrawals-present-p) "withdrawals required after Shanghai")
         ((null (executable-data-excess-blob-gas payload))
          "excessBlobGas required after Cancun")
         ((null (executable-data-blob-gas-used payload))
          "blobGasUsed required after Cancun")
         ((not versioned-hashes-supplied-p)
          "versionedHashes required after Cancun")
         ((not parent-beacon-root-supplied-p)
          "parentBeaconBlockRoot required after Cancun")
         ((not cancun-p)
          "newPayloadV3 requires Cancun")))
      ((= version 4)
       (cond
         ((not withdrawals-present-p) "withdrawals required after Shanghai")
         ((null (executable-data-excess-blob-gas payload))
          "excessBlobGas required after Cancun")
         ((null (executable-data-blob-gas-used payload))
          "blobGasUsed required after Cancun")
         ((not versioned-hashes-supplied-p)
          "versionedHashes required after Cancun")
         ((not parent-beacon-root-supplied-p)
          "parentBeaconBlockRoot required after Cancun")
         ((not requests-supplied-p)
          "executionRequests required after Prague")
         ((not prague-p)
          "newPayloadV4 requires Prague or later")))
      ((= version 5)
       (cond
         ((not withdrawals-present-p) "withdrawals required after Shanghai")
         ((null (executable-data-excess-blob-gas payload))
          "excessBlobGas required after Cancun")
         ((null (executable-data-blob-gas-used payload))
          "blobGasUsed required after Cancun")
         ((not versioned-hashes-supplied-p)
          "versionedHashes required after Cancun")
         ((not parent-beacon-root-supplied-p)
          "parentBeaconBlockRoot required after Cancun")
         ((not requests-supplied-p)
          "executionRequests required after Prague")
         ((null (executable-data-slot-number payload))
          "slotNumber required after Amsterdam")
         ((null (executable-data-block-access-list payload))
          "blockAccessList required after Amsterdam")
         ((not amsterdam-p)
          "newPayloadV5 requires Amsterdam")))
      (t "unsupported newPayload version"))))

(defun engine-new-payload-version-status
    (version payload config
     &key (parent-beacon-root nil parent-beacon-root-supplied-p)
          (versioned-hashes nil versioned-hashes-supplied-p)
          (requests nil requests-supplied-p))
  (unless (typep payload 'executable-data)
    (return-from engine-new-payload-version-status
      (values (invalid-payload-status
               "newPayload execution payload must be executable-data")
              nil)))
  (unless (typep config 'chain-config)
    (return-from engine-new-payload-version-status
      (values (invalid-payload-status
               "newPayload chain config must be chain-config")
              nil)))
  (let ((invalid-message
          (engine-new-payload-version-invalid-p
           version payload config
           versioned-hashes-supplied-p
           parent-beacon-root-supplied-p
           requests-supplied-p)))
    (when invalid-message
      (return-from engine-new-payload-version-status
        (values (invalid-payload-status invalid-message) nil))))
  (if requests-supplied-p
      (engine-new-payload-params-status
       payload
       :parent-beacon-root parent-beacon-root
       :versioned-hashes versioned-hashes
       :requests requests)
      (engine-new-payload-params-status
       payload
       :parent-beacon-root parent-beacon-root
       :versioned-hashes versioned-hashes)))

(defun engine-payload-id (version parent-hash attributes)
  (unless (and (integerp version) (<= 0 version 255))
    (block-validation-fail "Engine payload version must fit in one byte"))
  (let* ((digest
           (sha256
            (vector version)
            (hash32-bytes parent-hash)
            (integer-to-minimal-bytes
             (payload-attributes-v1-timestamp attributes))
            (hash32-bytes (payload-attributes-v1-prev-randao attributes))
            (address-bytes
             (payload-attributes-v1-suggested-fee-recipient attributes))
            (if (payload-attributes-v1-withdrawals-present-p attributes)
                (hash32-bytes
                 (withdrawal-list-root
                  (payload-attributes-v1-withdrawals attributes)))
                #())
            (if (payload-attributes-v1-parent-beacon-root-present-p attributes)
                (hash32-bytes
                 (payload-attributes-v1-parent-beacon-root attributes))
                #())
            (if (payload-attributes-v1-slot-number-present-p attributes)
                (integer-to-minimal-bytes
                 (payload-attributes-v1-slot-number attributes))
                #())))
         (payload-id (make-byte-vector 8)))
    (setf (aref payload-id 0) version)
    (replace payload-id digest :start1 1 :start2 0 :end2 7)
    payload-id))

(defun engine-payload-id-v1 (parent-hash attributes)
  (engine-payload-id 1 parent-hash attributes))

(defun engine-payload-id-with-transactions
    (version parent-hash attributes transactions)
  (if (null transactions)
      (engine-payload-id version parent-hash attributes)
      (let* ((digest
               (sha256
                (engine-payload-id version parent-hash attributes)
                (hash32-bytes (transaction-list-root transactions))))
             (payload-id (make-byte-vector 8)))
        (setf (aref payload-id 0) version)
        (replace payload-id digest :start1 1 :start2 0 :end2 7)
        payload-id)))

(defun engine-build-empty-payload (parent-block attributes)
  (unless (typep parent-block 'ethereum-block)
    (block-validation-fail "Payload parent must be a known block"))
  (unless (typep attributes 'payload-attributes-v1)
    (block-validation-fail "Payload attributes must be payload-attributes-v1"))
  (let* ((parent-header (block-header parent-block))
         (timestamp (payload-attributes-v1-timestamp attributes)))
    (unless (> timestamp (block-header-timestamp parent-header))
      (block-validation-fail
       "Payload attributes timestamp must be greater than parent timestamp"))
    (let ((header
            (make-block-header
             :parent-hash (block-hash parent-block)
             :beneficiary
             (payload-attributes-v1-suggested-fee-recipient attributes)
             :state-root (or (block-header-state-root parent-header)
                             +empty-trie-hash+)
             :mix-hash (payload-attributes-v1-prev-randao attributes)
             :number (1+ (block-header-number parent-header))
             :gas-limit (block-header-gas-limit parent-header)
             :gas-used 0
             :timestamp timestamp
             :base-fee-per-gas
             (if (block-header-base-fee-per-gas parent-header)
                 (expected-base-fee-per-gas parent-header)
                 0)
             :parent-beacon-root
             (when (payload-attributes-v1-parent-beacon-root-present-p
                    attributes)
               (payload-attributes-v1-parent-beacon-root attributes))
             :blob-gas-used
             (when (payload-attributes-v1-parent-beacon-root-present-p
                    attributes)
               0)
             :excess-blob-gas
             (when (payload-attributes-v1-parent-beacon-root-present-p
                    attributes)
               0)
             :slot-number
             (when (payload-attributes-v1-slot-number-present-p attributes)
               (payload-attributes-v1-slot-number attributes)))))
      (if (payload-attributes-v1-withdrawals-present-p attributes)
          (make-block
           :header header
           :withdrawals (payload-attributes-v1-withdrawals attributes))
          (make-block :header header)))))

(defun engine-build-empty-payload-v1 (parent-block attributes)
  (engine-build-empty-payload parent-block attributes))
