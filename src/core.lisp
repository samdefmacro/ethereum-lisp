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

(defstruct (chain-store-checkpoint
            (:constructor make-chain-store-checkpoint
                (&key label block-hash)))
  label
  block-hash)

(defstruct (engine-payload-memory-store
            (:constructor make-engine-payload-memory-store
                (&key (blocks (make-hash-table :test 'equal))
                      (number-blocks (make-hash-table :test 'eql))
                      (canonical-hashes (make-hash-table :test 'eql))
                      (transaction-locations (make-hash-table :test 'equal))
                      (account-balances (make-hash-table :test 'equal))
                      (account-nonces (make-hash-table :test 'equal))
                      (account-codes (make-hash-table :test 'equal))
                      (account-storage (make-hash-table :test 'equal))
                      (head-number 0)
                      (state-blocks (make-hash-table :test 'equal))
                      (remote-blocks (make-hash-table :test 'equal))
                      (invalid-tipsets (make-hash-table :test 'equal))
                      (prepared-payloads (make-hash-table :test 'equal))
                      (blob-sidecars (make-hash-table :test 'equal))
                      (txpool (make-engine-pending-txpool))
                      (log-filters (make-hash-table :test 'eql))
                      (next-log-filter-id 1)
                      (head-checkpoint
                       (make-chain-store-checkpoint :label :head))
                      (safe-checkpoint
                       (make-chain-store-checkpoint :label :safe))
                      (finalized-checkpoint
                       (make-chain-store-checkpoint :label :finalized)))))
  blocks
  number-blocks
  canonical-hashes
  transaction-locations
  account-balances
  account-nonces
  account-codes
  account-storage
  (head-number 0 :type (integer 0 *))
  state-blocks
  remote-blocks
  invalid-tipsets
  prepared-payloads
  blob-sidecars
  txpool
  log-filters
  (next-log-filter-id 1 :type (integer 1 *))
  head-checkpoint
  safe-checkpoint
  finalized-checkpoint)

(defstruct (engine-transaction-location
            (:constructor make-engine-transaction-location
                (&key block index transaction receipt log-index-start)))
  block
  (index 0 :type (integer 0 *))
  transaction
  receipt
  (log-index-start 0 :type (integer 0 *)))

(defstruct (engine-blob-and-proofs
            (:constructor make-engine-blob-and-proofs
                (&key blob commitment proof cell-proofs)))
  blob
  commitment
  proof
  cell-proofs)

(defstruct (engine-log-filter
            (:constructor make-engine-log-filter
                (&key criteria last-block-number block-hash-consumed-p
                      pending-changes)))
  criteria
  last-block-number
  pending-changes
  (block-hash-consumed-p nil :type boolean))

(defstruct (engine-log-filter-change
            (:constructor make-engine-log-filter-change
                (&key block removed-p)))
  block
  (removed-p nil :type boolean))

(defstruct (engine-block-filter
            (:constructor make-engine-block-filter
                (&key last-block-number hashes)))
  (last-block-number 0 :type (integer 0 *))
  hashes)

(defstruct (engine-pending-transaction-filter
            (:constructor make-engine-pending-transaction-filter
                (&key hashes)))
  hashes)

(defun engine-pending-transaction-filter-record-hash (filter hash)
  (unless (typep filter 'engine-pending-transaction-filter)
    (block-validation-fail
     "Pending transaction filter must be a pending transaction filter"))
  (unless (hash32-p hash)
    (block-validation-fail "Pending transaction filter hash must be a hash32"))
  (setf (engine-pending-transaction-filter-hashes filter)
        (append
         (engine-pending-transaction-filter-hashes filter)
         (list hash)))
  filter)

(defun engine-block-filter-record-hash (filter hash)
  (unless (typep filter 'engine-block-filter)
    (block-validation-fail "Block filter must be a block filter"))
  (unless (hash32-p hash)
    (block-validation-fail "Block filter hash must be a hash32"))
  (setf (engine-block-filter-hashes filter)
        (append
         (engine-block-filter-hashes filter)
         (list hash)))
  filter)

(defun engine-payload-store-key (hash)
  (unless (hash32-p hash)
    (block-validation-fail "Engine payload store key must be a hash32"))
  (hash32-to-hex hash))

(defun engine-payload-store-canonical-parent-p (store block)
  (let* ((header (block-header block))
         (number (block-header-number header))
         (parent-hash (block-header-parent-hash header))
         (parent-block
           (and parent-hash
                (engine-payload-store-known-block store parent-hash))))
    (or (zerop number)
        (null parent-hash)
        (hash32= parent-hash (zero-hash32))
        (null parent-block)
        (/= (block-header-number (block-header parent-block))
            (1- number))
        (let ((parent-key
                (gethash (1- number)
                         (engine-payload-memory-store-canonical-hashes
                          store))))
          (and parent-key
               (string= parent-key
                        (engine-payload-store-key parent-hash)))))))

(defun engine-payload-store-put-transaction-location
    (store block index transaction receipt log-index-start &key force)
  (let* ((transaction-key
           (engine-payload-store-key (transaction-hash transaction)))
         (locations
           (engine-payload-memory-store-transaction-locations store))
         (existing-location (gethash transaction-key locations))
         (existing-canonical-p
           (and existing-location
                (engine-payload-store-canonical-block-p
                 store
                 (engine-transaction-location-block existing-location)))))
    (when (or force
              (null existing-location)
              (engine-payload-store-canonical-block-p store block)
              (not existing-canonical-p))
      (setf (gethash transaction-key locations)
            (make-engine-transaction-location
             :block block
             :index index
             :transaction transaction
             :receipt receipt
             :log-index-start log-index-start)))))

(defun engine-payload-store-index-block-transactions
    (store block &key force)
  (loop with receipts = (block-receipts block)
        with log-index-start = 0
        for transaction in (block-transactions block)
        for index from 0
        for receipt = (nth index receipts)
        do (progn
             (engine-payload-store-put-transaction-location
              store
              block
              index
              transaction
              receipt
              log-index-start
              :force force)
             (when receipt
               (incf log-index-start
                     (length (receipt-logs receipt)))))))

(defun engine-payload-store-remove-block-transaction-locations (store block)
  (let ((locations
          (engine-payload-memory-store-transaction-locations store)))
    (dolist (transaction (block-transactions block))
      (let* ((transaction-key
               (engine-payload-store-key (transaction-hash transaction)))
             (location (gethash transaction-key locations)))
        (when (and location
                   (hash32= (block-hash block)
                             (block-hash
                              (engine-transaction-location-block location))))
          (remhash transaction-key locations)))))
  block)

(defun engine-payload-store-remove-included-block-transactions (store block)
  (dolist (transaction (block-transactions block))
    (engine-payload-store-remove-included-transaction store transaction))
  block)

(defun engine-payload-store-transaction-basefee-ineligible-p
    (store transaction)
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head)))
         (base-fee (and header
                        (block-header-base-fee-per-gas header))))
    (and base-fee
         (< (transaction-max-fee-per-gas transaction) base-fee))))

(defun engine-payload-store-current-blob-base-fee
    (store &optional chain-config)
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head))))
    (when (and header (block-header-excess-blob-gas header))
      (if chain-config
          (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
              (chain-config-blob-schedule
               chain-config
               (block-header-number header)
               (block-header-timestamp header))
            (declare (ignore target-blob-gas max-blob-gas))
            (block-header-blob-base-fee
             header
             :update-fraction update-fraction))
          (block-header-blob-base-fee header)))))

(defun engine-payload-store-validate-txpool-blob-fee-cap
    (store transaction &key chain-config label)
  (when (typep transaction 'blob-transaction)
    (let ((blob-base-fee
            (engine-payload-store-current-blob-base-fee
             store
             chain-config)))
      (when blob-base-fee
        (handler-case
            (validate-blob-transaction-fee-cap transaction blob-base-fee)
          (block-validation-error ()
            (block-validation-fail
             "~@[~A: ~]Max fee per blob gas below blob base fee"
             label))))))
  t)

(defun engine-payload-store-sender-code-admissible-p
    (store head sender)
  (or (null head)
      (not (chain-store-state-available-p store (block-hash head)))
      (let ((code (chain-store-account-code store (block-hash head) sender)))
        (or (zerop (length code))
            (set-code-delegation-target code)))))

(defun engine-payload-store-transaction-admission-funded-p
    (store sender transaction)
  (let ((head (chain-store-latest-block store)))
    (or (null head)
        (not (chain-store-state-available-p store (block-hash head)))
        (>= (chain-store-account-balance store (block-hash head) sender)
            (engine-payload-store-sender-admission-expenditure
             store
             sender
             transaction)))))

(defun engine-payload-store-reinsert-displaced-transaction
    (store transaction &key expected-chain-id chain-config)
  (let* ((hash (transaction-hash transaction))
         (head (chain-store-latest-block store))
         (sender (transaction-sender transaction
                                     :expected-chain-id expected-chain-id)))
    (when (and sender
               (not (chain-store-transaction-location store hash))
               (not (engine-payload-store-pooled-transaction store hash))
               (not (engine-payload-store-txpool-conflict-p
                     store transaction))
               (or (null head)
                   (not (engine-payload-store-over-gas-limit-txpool-transaction-p
                         head transaction)))
               (handler-case
                   (engine-payload-store-validate-txpool-blob-fee-cap
                    store
                    transaction
                    :chain-config chain-config)
                 (block-validation-error () nil))
               (engine-payload-store-sender-code-admissible-p
                store head sender)
               (engine-payload-store-transaction-admission-funded-p
                store sender transaction))
      (cond
        ((typep transaction 'blob-transaction)
         (engine-payload-store-put-blob-transaction store transaction))
        ((engine-payload-store-transaction-basefee-ineligible-p
          store transaction)
         (engine-payload-store-put-basefee-transaction store transaction))
        ((not (engine-payload-store-transaction-executable-nonce-p
               store transaction
               :expected-chain-id expected-chain-id))
         (engine-payload-store-put-queued-transaction store transaction))
        (t
         (engine-payload-store-put-pending-transaction store transaction))))))

(defun engine-payload-store-reinsert-displaced-block-transactions
    (store blocks &key expected-chain-id chain-config)
  (let ((seen-transactions (make-hash-table :test 'equal))
        (reinserted-transactions nil))
    (dolist (block (sort (copy-list blocks)
                         #'<
                         :key (lambda (block)
                                (block-header-number
                                 (block-header block)))))
      (dolist (transaction (block-transactions block))
        (let ((key (engine-payload-store-key
                    (transaction-hash transaction))))
          (unless (gethash key seen-transactions)
            (setf (gethash key seen-transactions) t)
            (when (engine-payload-store-reinsert-displaced-transaction
                   store transaction
                   :expected-chain-id expected-chain-id
                   :chain-config chain-config)
              (push transaction reinserted-transactions))))))
    (nreverse reinserted-transactions)))

(defun engine-payload-store-notify-block-filters (store block)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep block 'ethereum-block)
    (block-validation-fail "Block filter notification block must be a block"))
  (loop for filter
          being the hash-values of
            (engine-payload-memory-store-log-filters store)
        when (typep filter 'engine-block-filter)
          do (engine-block-filter-record-hash filter (block-hash block))))

(defun engine-log-filter-record-change (filter block &key removed-p)
  (unless (typep filter 'engine-log-filter)
    (block-validation-fail "Log filter must be a log filter"))
  (unless (typep block 'ethereum-block)
    (block-validation-fail "Log filter change block must be a block"))
  (setf (engine-log-filter-pending-changes filter)
        (append
         (engine-log-filter-pending-changes filter)
         (list (make-engine-log-filter-change
                :block block
                :removed-p (not (null removed-p))))))
  filter)

(defun engine-payload-store-notify-log-filters
    (store block &key removed-p)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (loop for filter
          being the hash-values of
            (engine-payload-memory-store-log-filters store)
        when (and (typep filter 'engine-log-filter)
                  (not (genesis-object-field-present-p
                        (engine-log-filter-criteria filter)
                        "blockHash")))
          do (engine-log-filter-record-change
              filter
              block
              :removed-p removed-p)))

(defun engine-payload-store-put-block
    (store block &key (state-available-p nil))
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep block 'ethereum-block)
    (block-validation-fail "Engine payload store block must be a block"))
  (let ((txpool (engine-payload-store-txpool store)))
    (unless (engine-pending-txpool-empty-p txpool)
      (dolist (transaction (block-transactions block))
        (engine-pending-txpool-sender transaction))))
  (let ((stored-block (engine-payload-store-copy-block block))
        (key (engine-payload-store-key (block-hash block)))
        (canonicalized-p nil)
        (notify-head-p nil))
    (remhash key (engine-payload-memory-store-remote-blocks store))
    (setf (gethash key (engine-payload-memory-store-blocks store))
          stored-block)
    (engine-payload-store-prune-prepared-payloads-for-block store key)
    (let ((number (block-header-number (block-header stored-block))))
      (when (and (integerp number) (not (minusp number)))
        (setf (gethash number
                       (engine-payload-memory-store-number-blocks store))
              stored-block)
        (when (and (not (gethash
                         number
                         (engine-payload-memory-store-canonical-hashes store)))
                   (engine-payload-store-canonical-parent-p store stored-block))
          (setf (gethash number
                         (engine-payload-memory-store-canonical-hashes store))
                key
                canonicalized-p t))
        (when (and canonicalized-p
                   (> number (engine-payload-memory-store-head-number store)))
          (setf notify-head-p t)
          (setf (engine-payload-memory-store-head-number store) number))))
    (loop with receipts = (block-receipts stored-block)
          with log-index-start = 0
          for transaction in (block-transactions stored-block)
          for index from 0
          for receipt = (nth index receipts)
          do (progn
               (engine-payload-store-put-transaction-location
                store
                stored-block
                index
                transaction
                receipt
                log-index-start)
               (when receipt
                 (incf log-index-start
                       (length (receipt-logs receipt))))))
    (when (engine-payload-store-canonical-block-p store stored-block)
      (engine-payload-store-remove-included-block-transactions store stored-block))
    (if state-available-p
        (setf (gethash key
                       (engine-payload-memory-store-state-blocks store))
              t)
        (remhash key (engine-payload-memory-store-state-blocks store)))
    (when notify-head-p
      (engine-payload-store-notify-block-filters store stored-block))
    block))

(defun engine-payload-store-known-block
    (store hash)
  (gethash (engine-payload-store-key hash)
           (engine-payload-memory-store-blocks store)))

(defun engine-payload-store-checkpoint-number
    (store checkpoint &key label fallback-to-head-p)
  (let* ((hash (and checkpoint
                    (chain-store-checkpoint-block-hash checkpoint)))
         (block (and hash (engine-payload-store-known-block store hash))))
    (cond
      (block
       (block-header-number (block-header block)))
      (fallback-to-head-p
       (engine-payload-memory-store-head-number store))
      (t
       (block-validation-fail "~A block not found" label)))))

(defun engine-payload-store-head-number (store)
  (engine-payload-store-checkpoint-number
   store
   (engine-payload-memory-store-head-checkpoint store)
   :label "head"
   :fallback-to-head-p t))

(defun engine-payload-store-block-tag-number (store tag)
  (cond
    ((or (string= tag "latest") (string= tag "pending"))
     (engine-payload-store-head-number store))
    ((string= tag "safe")
     (engine-payload-store-checkpoint-number
      store
      (engine-payload-memory-store-safe-checkpoint store)
      :label "safe"))
    ((string= tag "finalized")
     (engine-payload-store-checkpoint-number
      store
      (engine-payload-memory-store-finalized-checkpoint store)
      :label "finalized"))))

(defun engine-payload-store-forkchoice-checkpoint-hash (hash)
  (unless (hash32= hash (zero-hash32))
    hash))

(defun engine-payload-store-update-forkchoice-checkpoints (store state)
  (let* ((head-hash (forkchoice-state-head-block-hash state))
         (head-block (engine-payload-store-known-block store head-hash))
         (safe-hash
           (engine-payload-store-forkchoice-checkpoint-hash
            (forkchoice-state-safe-block-hash state)))
         (finalized-hash
           (engine-payload-store-forkchoice-checkpoint-hash
            (forkchoice-state-finalized-block-hash state))))
    (unless head-block
      (block-validation-fail "forkchoice head block is not available"))
    (unless (engine-payload-store-state-available-p store head-hash)
      (block-validation-fail "forkchoice head block state is not available"))
    (when (and safe-hash
               (not (engine-payload-store-known-block store safe-hash)))
      (block-validation-fail "forkchoice safe block is not available"))
    (when (and safe-hash
               (not (engine-payload-store-state-available-p
                     store safe-hash)))
      (block-validation-fail "forkchoice safe block state is not available"))
    (when (and finalized-hash
               (not (engine-payload-store-known-block store finalized-hash)))
      (block-validation-fail "forkchoice finalized block is not available"))
    (when (and finalized-hash
               (not (engine-payload-store-state-available-p
                     store finalized-hash)))
      (block-validation-fail
       "forkchoice finalized block state is not available"))
    (when (and safe-hash
               (not (engine-payload-store-ancestor-p
                     store safe-hash head-hash)))
      (block-validation-fail
       "forkchoice safe block is not an ancestor of head"))
    (when (and finalized-hash
               (not (engine-payload-store-ancestor-p
                     store finalized-hash head-hash)))
      (block-validation-fail
       "forkchoice finalized block is not an ancestor of head"))
    (let ((safe-block
            (and safe-hash
                 (engine-payload-store-known-block store safe-hash)))
          (finalized-block
            (and finalized-hash
                 (engine-payload-store-known-block store finalized-hash))))
      (when (and safe-block finalized-block
                 (< (block-header-number (block-header safe-block))
                    (block-header-number (block-header finalized-block))))
        (block-validation-fail
         "forkchoice safe block is older than finalized block"))))
  (setf (engine-payload-memory-store-head-checkpoint store)
        (make-chain-store-checkpoint
         :label :head
         :block-hash
         (engine-payload-store-forkchoice-checkpoint-hash
          (forkchoice-state-head-block-hash state)))
        (engine-payload-memory-store-safe-checkpoint store)
        (make-chain-store-checkpoint
         :label :safe
         :block-hash
         (engine-payload-store-forkchoice-checkpoint-hash
          (forkchoice-state-safe-block-hash state)))
        (engine-payload-memory-store-finalized-checkpoint store)
        (make-chain-store-checkpoint
         :label :finalized
         :block-hash
         (engine-payload-store-forkchoice-checkpoint-hash
          (forkchoice-state-finalized-block-hash state))))
  store)

(defun engine-payload-store-block-by-number (store number)
  (unless (and (integerp number) (not (minusp number)))
    (block-validation-fail "Engine payload store block number must be non-negative"))
  (let ((canonical-key
          (gethash number
                   (engine-payload-memory-store-canonical-hashes store))))
    (when canonical-key
      (gethash canonical-key
               (engine-payload-memory-store-blocks store)))))

(defun engine-payload-store-canonical-hash (store number)
  (unless (and (integerp number) (not (minusp number)))
    (block-validation-fail
     "Engine payload store canonical block number must be non-negative"))
  (let ((canonical-key
          (gethash number
                   (engine-payload-memory-store-canonical-hashes store))))
    (when canonical-key
      (hash32-from-hex canonical-key))))

(defun engine-payload-store-canonical-block-p (store block)
  (let* ((header (block-header block))
         (number (block-header-number header))
         (canonical-key
           (and (integerp number)
                (not (minusp number))
                (gethash number
                         (engine-payload-memory-store-canonical-hashes
                          store)))))
    (and canonical-key
         (string= canonical-key
                  (engine-payload-store-key (block-hash block))))))

(defun engine-payload-store-ancestor-p (store ancestor-hash head-hash)
  (cond
    ((hash32= ancestor-hash head-hash) t)
    ((or (hash32= ancestor-hash (zero-hash32))
         (hash32= head-hash (zero-hash32)))
     nil)
    (t
     (let ((ancestor-block
             (engine-payload-store-known-block store ancestor-hash))
           (current
             (engine-payload-store-known-block store head-hash)))
       (when (and ancestor-block current)
         (let ((ancestor-number
                 (block-header-number (block-header ancestor-block))))
           (loop
             (let* ((header (block-header current))
                    (number (block-header-number header)))
               (cond
                 ((< number ancestor-number)
                  (return nil))
                 ((and (= number ancestor-number)
                       (hash32= (block-hash current) ancestor-hash))
                  (return t))
                 ((zerop number)
                  (return nil))
                 (t
                  (let* ((parent-hash (block-header-parent-hash header))
                         (parent-block
                           (and parent-hash
                                (engine-payload-store-known-block
                                 store parent-hash))))
                    (unless parent-block
                      (return nil))
                    (setf current parent-block))))))))))))

(defun engine-payload-store-set-canonical-head
    (store hash &key expected-chain-id chain-config)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (let* ((head-block (engine-payload-store-known-block store hash))
         (previous-head-hash
           (engine-payload-store-canonical-hash
            store
            (engine-payload-memory-store-head-number store)))
         (head-changed-p
           (or (null previous-head-hash)
               (not (hash32= previous-head-hash hash)))))
    (unless head-block
      (block-validation-fail "Canonical head block must be known"))
    (let ((path '()))
      (loop with current = head-block
            do (let* ((header (block-header current))
                      (number (block-header-number header))
                      (current-hash (block-hash current))
                      (current-key (engine-payload-store-key current-hash))
                      (canonical-key
                        (gethash
                         number
                         (engine-payload-memory-store-canonical-hashes store))))
                 (when (and canonical-key
                            (string= canonical-key current-key))
                   (return))
                 (push current path)
                 (when (zerop number)
                   (return))
                 (let* ((parent-hash (block-header-parent-hash header))
                        (parent-block
                          (and parent-hash
                               (engine-payload-store-known-block
                                store parent-hash))))
                   (when (or (null parent-hash)
                             (hash32= parent-hash (zero-hash32)))
                     (return))
                   (unless parent-block
                     (block-validation-fail
                      "Canonical head ancestry must be fully known"))
                   (setf current parent-block))))
      (let ((displaced-blocks '()))
        (dolist (block path)
          (let* ((header (block-header block))
                 (number (block-header-number header))
                 (old-block (engine-payload-store-block-by-number
                             store number)))
            (when (and old-block
                       (not (hash32= (block-hash old-block)
                                     (block-hash block))))
              (push old-block displaced-blocks))))
        (dolist (block path)
          (let* ((header (block-header block))
                 (number (block-header-number header))
                 (key (engine-payload-store-key (block-hash block))))
            (setf (gethash number
                           (engine-payload-memory-store-canonical-hashes store))
                  key
                  (gethash number
                           (engine-payload-memory-store-number-blocks store))
                  block)
            (engine-payload-store-index-block-transactions
             store
             block
             :force t)
            (engine-payload-store-remove-included-block-transactions
             store
             block)))
        (let ((new-head-number
                (block-header-number (block-header head-block)))
              (stale-numbers '()))
          (maphash (lambda (number key)
                     (declare (ignore key))
                     (when (> number new-head-number)
                       (let ((old-block
                               (engine-payload-store-block-by-number
                                store number)))
                         (when old-block
                           (push old-block displaced-blocks)))
                       (push number stale-numbers)))
                   (engine-payload-memory-store-canonical-hashes store))
          (dolist (number stale-numbers)
            (remhash number
                     (engine-payload-memory-store-canonical-hashes store)))
          (setf (engine-payload-memory-store-head-number store) new-head-number
                (engine-payload-memory-store-head-checkpoint store)
                (make-chain-store-checkpoint :label :head :block-hash hash)))
        (engine-payload-store-remove-new-head-invalid-txpool-transactions
         store
         :chain-config chain-config)
        (dolist (block displaced-blocks)
          (engine-payload-store-remove-block-transaction-locations
           store
           block))
        (engine-payload-store-reinsert-displaced-block-transactions
         store
         displaced-blocks
         :expected-chain-id expected-chain-id
         :chain-config chain-config)
        (when head-changed-p
          (dolist (block (sort (copy-list displaced-blocks)
                               #'<
                               :key (lambda (block)
                                      (block-header-number
                                       (block-header block)))))
            (engine-payload-store-notify-log-filters
             store
             block
             :removed-p t))
          (dolist (block (sort (copy-list path)
                               #'<
                               :key (lambda (block)
                                      (block-header-number
                                       (block-header block)))))
            (engine-payload-store-notify-log-filters store block))))
      (engine-payload-store-remove-new-head-invalid-txpool-transactions
       store
       :chain-config chain-config)
      (engine-payload-store-revalidate-pending-transactions
       store
       :expected-chain-id expected-chain-id)
      (engine-payload-store-promote-queued-transactions
       store
       nil
       :expected-chain-id expected-chain-id)
      (engine-payload-store-promote-basefee-and-queued-transactions
       store
       :expected-chain-id expected-chain-id)
      (when head-changed-p
        (engine-payload-store-notify-block-filters store head-block))
      head-block)))

(defun engine-payload-store-transaction-location (store hash)
  (let ((location
          (gethash (engine-payload-store-key hash)
                   (engine-payload-memory-store-transaction-locations
                    store))))
    (when (and location
               (engine-payload-store-canonical-block-p
                store
                (engine-transaction-location-block location)))
      (engine-payload-store-copy-transaction-location location))))

(defun chain-store-require-memory-store (store)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Chain store must be an engine payload memory store"))
  store)

(defun engine-payload-store-copy-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy) value))
             table)
    copy))

(defun engine-payload-store-copy-filter (filter)
  (cond
    ((typep filter 'engine-log-filter)
     (make-engine-log-filter
      :criteria (copy-tree (engine-log-filter-criteria filter))
      :last-block-number (engine-log-filter-last-block-number filter)
      :pending-changes
      (copy-list (engine-log-filter-pending-changes filter))
      :block-hash-consumed-p
      (engine-log-filter-block-hash-consumed-p filter)))
    ((typep filter 'engine-block-filter)
     (make-engine-block-filter
      :last-block-number (engine-block-filter-last-block-number filter)
      :hashes (copy-list (engine-block-filter-hashes filter))))
    ((typep filter 'engine-pending-transaction-filter)
     (make-engine-pending-transaction-filter
      :hashes (copy-list
               (engine-pending-transaction-filter-hashes filter))))
    (t filter)))

(defun engine-payload-store-copy-filter-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy)
                     (engine-payload-store-copy-filter value)))
             table)
    copy))

(defun engine-payload-store-copy-prepared-payload (prepared-payload)
  (cond
    ((typep prepared-payload 'engine-prepared-payload)
     (make-engine-prepared-payload
      :payload-id (maybe-copy-bytes
                   (engine-prepared-payload-payload-id prepared-payload))
      :version (engine-prepared-payload-version prepared-payload)
      :block
      (engine-payload-store-copy-block
       (engine-prepared-payload-block prepared-payload))
      :blobs-bundle
      (maybe-copy-blob-sidecar
       (engine-prepared-payload-blobs-bundle prepared-payload))))
    (t prepared-payload)))

(defun engine-payload-store-copy-prepared-payload-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy)
                     (engine-payload-store-copy-prepared-payload value)))
             table)
    copy))

(defun engine-payload-store-copy-blob-and-proofs (blob-and-proofs)
  (cond
    ((typep blob-and-proofs 'engine-blob-and-proofs)
     (make-engine-blob-and-proofs
      :blob (maybe-copy-bytes
             (engine-blob-and-proofs-blob blob-and-proofs))
      :commitment (maybe-copy-bytes
                   (engine-blob-and-proofs-commitment blob-and-proofs))
      :proof (maybe-copy-bytes
              (engine-blob-and-proofs-proof blob-and-proofs))
      :cell-proofs
      (mapcar #'maybe-copy-bytes
              (engine-blob-and-proofs-cell-proofs blob-and-proofs))))
    (t blob-and-proofs)))

(defun engine-payload-store-copy-blob-sidecar-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy)
                     (engine-payload-store-copy-blob-and-proofs value)))
             table)
    copy))

(defun maybe-copy-hash32 (hash)
  (when hash
    (make-hash32 (copy-seq (hash32-bytes hash)))))

(defun maybe-copy-address (address)
  (when address
    (make-address (copy-seq (address-bytes address)))))

(defun engine-payload-store-copy-block-header (header)
  (when header
    (make-block-header
     :parent-hash (maybe-copy-hash32 (block-header-parent-hash header))
     :ommers-hash (maybe-copy-hash32 (block-header-ommers-hash header))
     :beneficiary (maybe-copy-address (block-header-beneficiary header))
     :state-root (maybe-copy-hash32 (block-header-state-root header))
     :transactions-root
     (maybe-copy-hash32 (block-header-transactions-root header))
     :receipts-root (maybe-copy-hash32 (block-header-receipts-root header))
     :logs-bloom (maybe-copy-bytes (block-header-logs-bloom header))
     :difficulty (block-header-difficulty header)
     :number (block-header-number header)
     :gas-limit (block-header-gas-limit header)
     :gas-used (block-header-gas-used header)
     :timestamp (block-header-timestamp header)
     :extra-data (maybe-copy-bytes (block-header-extra-data header))
     :mix-hash (maybe-copy-hash32 (block-header-mix-hash header))
     :nonce (maybe-copy-bytes (block-header-nonce header))
     :base-fee-per-gas (block-header-base-fee-per-gas header)
     :withdrawals-root (maybe-copy-hash32 (block-header-withdrawals-root header))
     :blob-gas-used (block-header-blob-gas-used header)
     :excess-blob-gas (block-header-excess-blob-gas header)
     :parent-beacon-root
     (maybe-copy-hash32 (block-header-parent-beacon-root header))
     :requests-hash (maybe-copy-hash32 (block-header-requests-hash header))
     :block-access-list-hash
     (maybe-copy-hash32 (block-header-block-access-list-hash header))
     :slot-number (block-header-slot-number header))))

(defun engine-payload-store-copy-log-entry (log)
  (cond
    ((typep log 'log-entry)
     (make-log-entry
      :address (maybe-copy-address (log-entry-address log))
      :topics (mapcar (lambda (topic)
                        (if (typep topic 'hash32)
                            (maybe-copy-hash32 topic)
                            (maybe-copy-bytes topic)))
                      (log-entry-topics log))
      :data (maybe-copy-bytes (log-entry-data log))))
    (t log)))

(defun engine-payload-store-copy-receipt (receipt)
  (cond
    ((typep receipt 'receipt)
     (make-receipt
      :post-state (maybe-copy-bytes (receipt-post-state receipt))
      :status (receipt-status receipt)
      :cumulative-gas-used (receipt-cumulative-gas-used receipt)
      :logs (mapcar #'engine-payload-store-copy-log-entry
                    (receipt-logs receipt))))
    (t receipt)))

(defun engine-payload-store-copy-block (block)
  (cond
    ((typep block 'ethereum-block)
     (let ((copy (copy-ethereum-block block)))
       (setf (block-header copy)
             (engine-payload-store-copy-block-header (block-header block))
             (block-transactions copy)
             (mapcar (lambda (transaction)
                       (transaction-from-encoding
                        (transaction-encoding transaction)))
                     (block-transactions block))
             (block-receipts copy)
             (mapcar #'engine-payload-store-copy-receipt
                     (block-receipts block))
             (block-ommers copy) (copy-list (block-ommers block))
             (block-withdrawals copy)
             (maybe-copy-withdrawals (block-withdrawals block))
             (block-requests copy) (maybe-copy-requests (block-requests block))
             (block-block-access-list copy)
             (copy-tree (block-block-access-list block))
             (block-encoded-block-access-list copy)
             (maybe-copy-bytes (block-encoded-block-access-list block)))
       copy))
    (t block)))

(defun engine-payload-store-copy-block-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy)
                     (engine-payload-store-copy-block value)))
             table)
    copy))

(defun engine-payload-store-copy-transaction (transaction)
  (transaction-from-encoding (transaction-encoding transaction)))

(defun engine-payload-store-copy-transaction-location (location)
  (cond
    ((typep location 'engine-transaction-location)
     (let* ((index (engine-transaction-location-index location))
            (block-copy
              (engine-payload-store-copy-block
               (engine-transaction-location-block location)))
            (transaction
              (engine-transaction-location-transaction location))
            (receipt (engine-transaction-location-receipt location)))
       (make-engine-transaction-location
        :block block-copy
        :index index
        :transaction (or (nth index (block-transactions block-copy))
                         (and transaction
                              (engine-payload-store-copy-transaction
                               transaction)))
        :receipt (or (nth index (block-receipts block-copy))
                     (engine-payload-store-copy-receipt receipt))
        :log-index-start
        (engine-transaction-location-log-index-start location))))
    (t location)))

(defun engine-payload-store-copy-transaction-location-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy)
                     (engine-payload-store-copy-transaction-location value)))
             table)
    copy))

(defun engine-payload-store-snapshot (store)
  (make-engine-payload-memory-store
   :blocks
   (engine-payload-store-copy-table
    (engine-payload-memory-store-blocks store))
   :number-blocks
   (engine-payload-store-copy-table
    (engine-payload-memory-store-number-blocks store))
   :canonical-hashes
   (engine-payload-store-copy-table
    (engine-payload-memory-store-canonical-hashes store))
   :transaction-locations
   (engine-payload-store-copy-transaction-location-table
    (engine-payload-memory-store-transaction-locations store))
   :account-balances
   (engine-payload-store-copy-table
    (engine-payload-memory-store-account-balances store))
   :account-nonces
   (engine-payload-store-copy-table
    (engine-payload-memory-store-account-nonces store))
   :account-codes
   (engine-payload-store-copy-table
    (engine-payload-memory-store-account-codes store))
   :account-storage
   (engine-payload-store-copy-table
    (engine-payload-memory-store-account-storage store))
   :head-number (engine-payload-memory-store-head-number store)
   :state-blocks
   (engine-payload-store-copy-table
    (engine-payload-memory-store-state-blocks store))
   :remote-blocks
   (engine-payload-store-copy-table
    (engine-payload-memory-store-remote-blocks store))
   :invalid-tipsets
   (engine-payload-store-copy-block-table
    (engine-payload-memory-store-invalid-tipsets store))
   :prepared-payloads
   (engine-payload-store-copy-prepared-payload-table
    (engine-payload-memory-store-prepared-payloads store))
   :blob-sidecars
   (engine-payload-store-copy-blob-sidecar-table
    (engine-payload-memory-store-blob-sidecars store))
   :txpool
   (engine-pending-txpool-copy
    (engine-payload-memory-store-txpool store))
   :log-filters
   (engine-payload-store-copy-filter-table
    (engine-payload-memory-store-log-filters store))
   :next-log-filter-id
   (engine-payload-memory-store-next-log-filter-id store)
   :head-checkpoint
   (engine-payload-store-copy-checkpoint
    (engine-payload-memory-store-head-checkpoint store))
   :safe-checkpoint
   (engine-payload-store-copy-checkpoint
    (engine-payload-memory-store-safe-checkpoint store))
   :finalized-checkpoint
   (engine-payload-store-copy-checkpoint
    (engine-payload-memory-store-finalized-checkpoint store))))

(defun engine-payload-store-restore (store snapshot)
  (setf (engine-payload-memory-store-blocks store)
        (engine-payload-memory-store-blocks snapshot)
        (engine-payload-memory-store-number-blocks store)
        (engine-payload-memory-store-number-blocks snapshot)
        (engine-payload-memory-store-canonical-hashes store)
        (engine-payload-memory-store-canonical-hashes snapshot)
        (engine-payload-memory-store-transaction-locations store)
        (engine-payload-memory-store-transaction-locations snapshot)
        (engine-payload-memory-store-account-balances store)
        (engine-payload-memory-store-account-balances snapshot)
        (engine-payload-memory-store-account-nonces store)
        (engine-payload-memory-store-account-nonces snapshot)
        (engine-payload-memory-store-account-codes store)
        (engine-payload-memory-store-account-codes snapshot)
        (engine-payload-memory-store-account-storage store)
        (engine-payload-memory-store-account-storage snapshot)
        (engine-payload-memory-store-head-number store)
        (engine-payload-memory-store-head-number snapshot)
        (engine-payload-memory-store-state-blocks store)
        (engine-payload-memory-store-state-blocks snapshot)
        (engine-payload-memory-store-remote-blocks store)
        (engine-payload-memory-store-remote-blocks snapshot)
        (engine-payload-memory-store-invalid-tipsets store)
        (engine-payload-memory-store-invalid-tipsets snapshot)
        (engine-payload-memory-store-prepared-payloads store)
        (engine-payload-memory-store-prepared-payloads snapshot)
        (engine-payload-memory-store-blob-sidecars store)
        (engine-payload-memory-store-blob-sidecars snapshot)
        (engine-payload-memory-store-txpool store)
        (engine-payload-memory-store-txpool snapshot)
        (engine-payload-memory-store-log-filters store)
        (engine-payload-memory-store-log-filters snapshot)
        (engine-payload-memory-store-next-log-filter-id store)
        (engine-payload-memory-store-next-log-filter-id snapshot)
        (engine-payload-memory-store-head-checkpoint store)
        (engine-payload-memory-store-head-checkpoint snapshot)
        (engine-payload-memory-store-safe-checkpoint store)
        (engine-payload-memory-store-safe-checkpoint snapshot)
        (engine-payload-memory-store-finalized-checkpoint store)
        (engine-payload-memory-store-finalized-checkpoint snapshot))
  store)

(defun chain-store-atomic-commit (store thunk)
  (let* ((store (chain-store-require-memory-store store))
         (snapshot (engine-payload-store-snapshot store)))
    (handler-case
        (funcall thunk)
      (error (condition)
        (engine-payload-store-restore store snapshot)
        (error condition)))))

(defun chain-store-put-block (store block &key (state-available-p nil))
  (engine-payload-store-put-block
   (chain-store-require-memory-store store)
   block
   :state-available-p state-available-p))

(defun chain-store-known-block (store hash)
  (engine-payload-store-known-block
   (chain-store-require-memory-store store)
   hash))

(defun chain-store-block-by-number (store number)
  (engine-payload-store-block-by-number
   (chain-store-require-memory-store store)
   number))

(defun chain-store-canonical-hash (store number)
  (engine-payload-store-canonical-hash
   (chain-store-require-memory-store store)
   number))

(defun chain-store-set-canonical-head
    (store hash &key expected-chain-id chain-config)
  (engine-payload-store-set-canonical-head
   (chain-store-require-memory-store store)
   hash
   :expected-chain-id expected-chain-id
   :chain-config chain-config))

(defun chain-store-head-number (store)
  (engine-payload-store-head-number
   (chain-store-require-memory-store store)))

(defun chain-store-block-tag-number (store tag)
  (engine-payload-store-block-tag-number
   (chain-store-require-memory-store store)
   tag))

(defun chain-store-latest-block (store)
  (chain-store-block-by-number
   store
   (chain-store-head-number store)))

(defun chain-store-transaction-location (store hash)
  (engine-payload-store-transaction-location
   (chain-store-require-memory-store store)
   hash))

(defun chain-store-block-receipts (store hash)
  (let ((block (chain-store-known-block store hash)))
    (when block
      (mapcar #'engine-payload-store-copy-receipt
              (block-receipts block)))))

(defun chain-store-state-available-p (store hash)
  (engine-payload-store-state-available-p
   (chain-store-require-memory-store store)
   hash))

(defun engine-payload-store-remove-prefixed-keys (table prefix)
  (let ((keys '()))
    (maphash
     (lambda (key value)
       (declare (ignore value))
       (when (engine-payload-store-string-prefix-p prefix key)
         (push key keys)))
     table)
    (dolist (key keys)
      (remhash key table))
    (length keys)))

(defun engine-payload-store-prune-state-snapshot (store block-key)
  (let ((prefix (format nil "~A:" block-key)))
    (remhash block-key (engine-payload-memory-store-state-blocks store))
    (+ (engine-payload-store-remove-prefixed-keys
        (engine-payload-memory-store-account-balances store)
        prefix)
       (engine-payload-store-remove-prefixed-keys
        (engine-payload-memory-store-account-nonces store)
        prefix)
       (engine-payload-store-remove-prefixed-keys
        (engine-payload-memory-store-account-codes store)
        prefix)
       (engine-payload-store-remove-prefixed-keys
        (engine-payload-memory-store-account-storage store)
        prefix))))

(defun chain-store-prune-state-before (store block-number)
  (let ((store (chain-store-require-memory-store store)))
    (unless (and (integerp block-number) (not (minusp block-number)))
      (block-validation-fail
       "Chain state pruning block number must be a non-negative integer"))
    (let ((block-keys '())
          (head-block-key
            (let ((checkpoint
                    (engine-payload-memory-store-head-checkpoint store)))
              (let ((hash (and checkpoint
                               (chain-store-checkpoint-block-hash
                                checkpoint))))
                (if hash
                    (engine-payload-store-key hash)
                    (gethash
                     (engine-payload-memory-store-head-number store)
                     (engine-payload-memory-store-canonical-hashes
                      store)))))))
      (maphash
       (lambda (block-key state-available-p)
         (when state-available-p
           (let ((block (gethash block-key
                                  (engine-payload-memory-store-blocks store))))
             (when (and block
                        (or (null head-block-key)
                            (not (string= block-key head-block-key)))
                        (< (block-header-number (block-header block))
                           block-number))
               (push block-key block-keys)))))
       (engine-payload-memory-store-state-blocks store))
      (dolist (block-key block-keys)
        (engine-payload-store-prune-state-snapshot store block-key))
      (length block-keys))))

(defun chain-store-update-forkchoice-checkpoints (store state)
  (engine-payload-store-update-forkchoice-checkpoints
   (chain-store-require-memory-store store)
   state))

(defun chain-store-head-checkpoint (store)
  (engine-payload-memory-store-head-checkpoint
   (chain-store-require-memory-store store)))

(defun chain-store-safe-checkpoint (store)
  (engine-payload-memory-store-safe-checkpoint
   (chain-store-require-memory-store store)))

(defun chain-store-finalized-checkpoint (store)
  (engine-payload-memory-store-finalized-checkpoint
   (chain-store-require-memory-store store)))

(defun chain-store-checkpoint-block (store checkpoint)
  (let ((hash (and checkpoint
                   (chain-store-checkpoint-block-hash checkpoint))))
    (when hash
      (chain-store-known-block store hash))))

(defun chain-store-head-block (store)
  (chain-store-checkpoint-block
   store
   (chain-store-head-checkpoint store)))

(defun chain-store-safe-block (store)
  (chain-store-checkpoint-block
   store
   (chain-store-safe-checkpoint store)))

(defun chain-store-finalized-block (store)
  (chain-store-checkpoint-block
   store
   (chain-store-finalized-checkpoint store)))

(defun chain-store-put-prepared-payload (store prepared-payload)
  (engine-payload-store-put-prepared-payload
   (chain-store-require-memory-store store)
   prepared-payload))

(defun chain-store-prepared-payload (store payload-id)
  (engine-payload-store-prepared-payload
   (chain-store-require-memory-store store)
   payload-id))

(defun engine-payload-store-put-log-filter (store filter)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (let ((id (engine-payload-memory-store-next-log-filter-id store)))
    (setf (gethash id (engine-payload-memory-store-log-filters store))
          (make-engine-log-filter
           :criteria filter
           :last-block-number
           (unless (genesis-object-field-present-p filter "blockHash")
             (let ((from-block (genesis-object-field filter "fromBlock")))
               (when (or (null from-block)
                         (and (stringp from-block)
                              (or (string= from-block "latest")
                                  (string= from-block "pending"))))
                 (engine-payload-memory-store-head-number store))))))
    (incf (engine-payload-memory-store-next-log-filter-id store))
    id))

(defun engine-payload-store-put-block-filter (store)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (let ((id (engine-payload-memory-store-next-log-filter-id store)))
    (setf (gethash id (engine-payload-memory-store-log-filters store))
          (make-engine-block-filter
           :last-block-number
           (engine-payload-memory-store-head-number store)))
    (incf (engine-payload-memory-store-next-log-filter-id store))
    id))

(defun engine-payload-store-put-pending-transaction-filter (store)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (let ((id (engine-payload-memory-store-next-log-filter-id store)))
    (setf (gethash id (engine-payload-memory-store-log-filters store))
          (make-engine-pending-transaction-filter))
    (incf (engine-payload-memory-store-next-log-filter-id store))
    id))

(defun engine-payload-store-log-filter (store id)
  (gethash id (engine-payload-memory-store-log-filters store)))

(defun engine-payload-store-uninstall-log-filter (store id)
  (remhash id (engine-payload-memory-store-log-filters store)))

(defun engine-payload-store-account-key (block-hash address)
  (format nil "~A:~A"
          (engine-payload-store-key block-hash)
          (address-to-hex address)))

(defun engine-payload-store-account-storage-key (block-hash address slot)
  (format nil "~A:~A"
          (engine-payload-store-account-key block-hash address)
          (hash32-to-hex slot)))

(defun engine-payload-store-put-account-balance
    (store block-hash address balance)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (address-p address)
    (block-validation-fail "Engine account balance address must be an address"))
  (unless (uint256-p balance)
    (block-validation-fail "Engine account balance must be uint256"))
  (let ((block (engine-payload-store-known-block store block-hash)))
    (unless block
      (block-validation-fail
       "Engine account balance block must be known by the memory store"))
    (setf (gethash (engine-payload-store-account-key block-hash address)
                   (engine-payload-memory-store-account-balances store))
          balance
          (gethash (engine-payload-store-key block-hash)
                   (engine-payload-memory-store-state-blocks store))
          t)
    balance))

(defun engine-payload-store-account-balance (store block-hash address)
  (gethash (engine-payload-store-account-key block-hash address)
           (engine-payload-memory-store-account-balances store)
           0))

(defun engine-payload-store-put-account-nonce
    (store block-hash address nonce)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (address-p address)
    (block-validation-fail "Engine account nonce address must be an address"))
  (unless (uint64-value-p nonce)
    (block-validation-fail "Engine account nonce must be uint64"))
  (let ((block (engine-payload-store-known-block store block-hash)))
    (unless block
      (block-validation-fail
       "Engine account nonce block must be known by the memory store"))
    (setf (gethash (engine-payload-store-account-key block-hash address)
                   (engine-payload-memory-store-account-nonces store))
          nonce
          (gethash (engine-payload-store-key block-hash)
                   (engine-payload-memory-store-state-blocks store))
          t)
    nonce))

(defun engine-payload-store-account-nonce (store block-hash address)
  (gethash (engine-payload-store-account-key block-hash address)
           (engine-payload-memory-store-account-nonces store)
           0))

(defun engine-payload-store-put-account-code
    (store block-hash address code)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (address-p address)
    (block-validation-fail "Engine account code address must be an address"))
  (let ((block (engine-payload-store-known-block store block-hash))
        (code (ensure-byte-vector code)))
    (unless block
      (block-validation-fail
       "Engine account code block must be known by the memory store"))
    (setf (gethash (engine-payload-store-account-key block-hash address)
                   (engine-payload-memory-store-account-codes store))
          (copy-seq code)
          (gethash (engine-payload-store-key block-hash)
                   (engine-payload-memory-store-state-blocks store))
          t)
    code))

(defun engine-payload-store-account-code (store block-hash address)
  (let ((code
          (gethash (engine-payload-store-account-key block-hash address)
                   (engine-payload-memory-store-account-codes store))))
    (if code
        (copy-seq code)
        (make-byte-vector 0))))

(defun engine-payload-store-put-account-storage
    (store block-hash address slot value)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (address-p address)
    (block-validation-fail "Engine account storage address must be an address"))
  (unless (hash32-p slot)
    (block-validation-fail "Engine account storage slot must be a hash32"))
  (unless (uint256-p value)
    (block-validation-fail "Engine account storage value must be uint256"))
  (let ((block (engine-payload-store-known-block store block-hash)))
    (unless block
      (block-validation-fail
       "Engine account storage block must be known by the memory store"))
    (setf (gethash
           (engine-payload-store-account-storage-key block-hash address slot)
           (engine-payload-memory-store-account-storage store))
          value
          (gethash (engine-payload-store-key block-hash)
                   (engine-payload-memory-store-state-blocks store))
          t)
    value))

(defun engine-payload-store-account-storage (store block-hash address slot)
  (gethash (engine-payload-store-account-storage-key block-hash address slot)
           (engine-payload-memory-store-account-storage store)
           0))

(defun chain-store-put-account-balance
    (store block-hash address balance)
  (engine-payload-store-put-account-balance
   (chain-store-require-memory-store store)
   block-hash
   address
   balance))

(defun chain-store-account-balance (store block-hash address)
  (engine-payload-store-account-balance
   (chain-store-require-memory-store store)
   block-hash
   address))

(defun chain-store-put-account-nonce
    (store block-hash address nonce)
  (engine-payload-store-put-account-nonce
   (chain-store-require-memory-store store)
   block-hash
   address
   nonce))

(defun chain-store-account-nonce (store block-hash address)
  (engine-payload-store-account-nonce
   (chain-store-require-memory-store store)
   block-hash
   address))

(defun chain-store-put-account-code
    (store block-hash address code)
  (engine-payload-store-put-account-code
   (chain-store-require-memory-store store)
   block-hash
   address
   code))

(defun chain-store-account-code (store block-hash address)
  (engine-payload-store-account-code
   (chain-store-require-memory-store store)
   block-hash
   address))

(defun chain-store-put-account-storage
    (store block-hash address slot value)
  (engine-payload-store-put-account-storage
   (chain-store-require-memory-store store)
   block-hash
   address
   slot
   value))

(defun chain-store-account-storage (store block-hash address slot)
  (engine-payload-store-account-storage
   (chain-store-require-memory-store store)
   block-hash
   address
   slot))

(defun engine-payload-store-string-prefix-p (prefix string)
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun engine-payload-store-remember-account-key
    (accounts block-prefix key &key storage-key-p)
  (when (engine-payload-store-string-prefix-p block-prefix key)
    (let* ((rest (subseq key (length block-prefix)))
           (address-hex
             (if storage-key-p
                 (let ((slot-separator (position #\: rest)))
                   (and slot-separator
                        (subseq rest 0 slot-separator)))
                 rest)))
      (when address-hex
        (setf (gethash address-hex accounts) t)))))

(defun engine-payload-store-sorted-hash-keys (table)
  (let (keys)
    (maphash (lambda (key value)
               (declare (ignore value))
               (push key keys))
             table)
    (sort keys #'string<)))

(defun engine-payload-store-account-storage-entries
    (memory-store block-hash address)
  (let ((account-prefix
          (format nil "~A:"
                  (engine-payload-store-account-key block-hash address)))
        (entries '()))
    (dolist (key (engine-payload-store-sorted-hash-keys
                  (engine-payload-memory-store-account-storage memory-store)))
      (when (engine-payload-store-string-prefix-p account-prefix key)
        (push (cons (hash32-from-hex
                     (subseq key (length account-prefix)))
                    (gethash
                     key
                     (engine-payload-memory-store-account-storage memory-store)))
              entries)))
    (nreverse entries)))

(defun chain-store-for-each-account (store block-hash function)
  (let ((memory-store (chain-store-require-memory-store store)))
    (when (chain-store-state-available-p store block-hash)
      (let ((block-prefix
              (format nil "~A:" (engine-payload-store-key block-hash)))
            (accounts (make-hash-table :test #'equal)))
        (maphash
         (lambda (key value)
           (declare (ignore value))
           (engine-payload-store-remember-account-key
            accounts block-prefix key))
         (engine-payload-memory-store-account-balances memory-store))
        (maphash
         (lambda (key value)
           (declare (ignore value))
           (engine-payload-store-remember-account-key
            accounts block-prefix key))
         (engine-payload-memory-store-account-nonces memory-store))
        (maphash
         (lambda (key value)
           (declare (ignore value))
           (engine-payload-store-remember-account-key
            accounts block-prefix key))
         (engine-payload-memory-store-account-codes memory-store))
        (maphash
         (lambda (key value)
           (declare (ignore value))
           (engine-payload-store-remember-account-key
            accounts block-prefix key :storage-key-p t))
         (engine-payload-memory-store-account-storage memory-store))
        (dolist (address-hex (engine-payload-store-sorted-hash-keys accounts))
           (let* ((address (address-from-hex address-hex))
                  (account-key
                    (engine-payload-store-account-key block-hash address)))
             (funcall
              function
              address
              (gethash account-key
                       (engine-payload-memory-store-account-balances
                        memory-store)
                       0)
              (gethash account-key
                       (engine-payload-memory-store-account-nonces
                        memory-store)
                       0)
              (engine-payload-store-account-code
               memory-store block-hash address)
              (engine-payload-store-account-storage-entries
               memory-store block-hash address))))
        store))))

(defun engine-payload-store-state-available-p
    (store hash)
  (not (null
        (gethash (engine-payload-store-key hash)
                 (engine-payload-memory-store-state-blocks store)))))

(defun engine-payload-store-remote-block
    (store hash)
  (engine-payload-store-copy-block
   (gethash (engine-payload-store-key hash)
            (engine-payload-memory-store-remote-blocks store))))

(defun engine-payload-store-put-remote-block
    (store block)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep block 'ethereum-block)
    (block-validation-fail "Engine remote block cache value must be a block"))
  (setf (gethash (engine-payload-store-key (block-hash block))
                 (engine-payload-memory-store-remote-blocks store))
        (engine-payload-store-copy-block block))
  block)

(defun engine-payload-store-remove-remote-block
    (store hash)
  (remhash (engine-payload-store-key hash)
           (engine-payload-memory-store-remote-blocks store)))

(defun engine-payload-store-prune-prepared-payloads-for-block
    (store block-key)
  (let ((stale-payload-id-keys nil))
    (maphash
     (lambda (payload-id-key prepared-payload)
       (when (string= block-key
                      (engine-payload-store-key
                       (block-hash
                        (engine-prepared-payload-block prepared-payload))))
         (push payload-id-key stale-payload-id-keys)))
     (engine-payload-memory-store-prepared-payloads store))
    (dolist (payload-id-key stale-payload-id-keys)
      (remhash payload-id-key
               (engine-payload-memory-store-prepared-payloads store)))))

(defun engine-payload-store-mark-invalid
    (store invalid-block &key head-hash)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep invalid-block 'ethereum-block)
    (block-validation-fail "Engine payload invalid marker must be a block"))
  (let* ((invalid-hash (block-hash invalid-block))
         (key (engine-payload-store-key (or head-hash invalid-hash))))
    (engine-payload-store-remove-remote-block store invalid-hash)
    (engine-payload-store-prune-prepared-payloads-for-block
     store
     (engine-payload-store-key invalid-hash))
    (when head-hash
      (engine-payload-store-remove-remote-block store head-hash)
      (engine-payload-store-prune-prepared-payloads-for-block store key))
    (setf (gethash key (engine-payload-memory-store-invalid-tipsets store))
          (engine-payload-store-copy-block invalid-block))
    invalid-block))

(defun engine-payload-store-invalid-block
    (store hash)
  (engine-payload-store-copy-block
   (gethash (engine-payload-store-key hash)
            (engine-payload-memory-store-invalid-tipsets store))))

(defun engine-payload-store-invalid-ancestor-status
    (store check-hash head-hash)
  (let ((invalid-block
          (engine-payload-store-invalid-block store check-hash)))
    (when invalid-block
      (unless (string= (engine-payload-store-key check-hash)
                       (engine-payload-store-key head-hash))
        (engine-payload-store-mark-invalid
         store invalid-block :head-hash head-hash))
      (make-payload-status
       :status +payload-status-invalid+
       :latest-valid-hash
       (block-header-parent-hash (block-header invalid-block))
       :validation-error "links to previously rejected block"))))

(defun engine-payload-id-key (payload-id)
  (let ((bytes (ensure-byte-vector payload-id)))
    (unless (= 8 (length bytes))
      (block-validation-fail "Engine payload id must be 8 bytes"))
    (bytes-to-hex bytes)))

(defun engine-payload-id-to-hex (payload-id)
  (engine-payload-id-key payload-id))

(defun engine-payload-store-put-prepared-payload
    (store prepared-payload)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (validate-engine-prepared-payload prepared-payload)
  (let ((stored-payload
          (engine-payload-store-copy-prepared-payload prepared-payload)))
    (setf (gethash
           (engine-payload-id-key
            (engine-prepared-payload-payload-id stored-payload))
           (engine-payload-memory-store-prepared-payloads store))
          stored-payload))
  prepared-payload)

(defun engine-payload-store-prepared-payload (store payload-id)
  (engine-payload-store-copy-prepared-payload
   (gethash (engine-payload-id-key payload-id)
            (engine-payload-memory-store-prepared-payloads store))))

(defun engine-payload-store-put-blob-sidecar
    (store sidecar)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep sidecar 'blob-sidecar)
    (block-validation-fail
     "Engine blob sidecar store value must be a blob sidecar"))
  (let ((hashes (blob-sidecar-versioned-hashes sidecar))
        (blobs (blob-sidecar-blobs sidecar))
        (proofs (blob-sidecar-proofs sidecar)))
    (unless (= (length hashes) (length blobs))
      (block-validation-fail
       "Engine blob sidecar blobs and commitments must have matching lengths"))
    (unless (or (= (length proofs) (length blobs))
                (= (length proofs)
                   (* (length blobs) +cell-proofs-per-blob+)))
      (block-validation-fail
       "Engine blob sidecar proofs must be one per blob or cell proofs per blob"))
    (loop for versioned-hash in hashes
          for blob in blobs
          for index from 0
          for proof = (if (= (length proofs) (length blobs))
                          (nth index proofs)
                          (nth (* index +cell-proofs-per-blob+) proofs))
          for cell-proofs = (when (= (length proofs)
                                     (* (length blobs)
                                        +cell-proofs-per-blob+))
                              (subseq proofs
                                      (* index +cell-proofs-per-blob+)
                                      (* (1+ index)
                                         +cell-proofs-per-blob+)))
          do (setf (gethash
                    (engine-payload-store-key versioned-hash)
                    (engine-payload-memory-store-blob-sidecars store))
                   (make-engine-blob-and-proofs
                    :blob (maybe-copy-bytes blob)
                    :commitment
                    (maybe-copy-bytes
                     (nth index (blob-sidecar-commitments sidecar)))
                    :proof (maybe-copy-bytes proof)
                    :cell-proofs (mapcar #'maybe-copy-bytes
                                         cell-proofs)))))
  sidecar)

(defun engine-payload-store-blob-and-proofs-v1
    (store versioned-hash)
  (engine-payload-store-copy-blob-and-proofs
   (gethash (engine-payload-store-key versioned-hash)
            (engine-payload-memory-store-blob-sidecars store))))

(defun engine-payload-store-blob-and-proofs-v2
    (store versioned-hash)
  (let ((blob-and-proofs
          (engine-payload-store-blob-and-proofs-v1 store versioned-hash)))
    (when (and blob-and-proofs
               (= +cell-proofs-per-blob+
                  (length
                   (engine-blob-and-proofs-cell-proofs blob-and-proofs))))
      blob-and-proofs)))

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

(defun execution-requests-hash (requests)
  (sha256-hash
   (apply #'concat-bytes
          (loop for request in requests
                for bytes = (validate-execution-request-fields request)
                when (> (length bytes) 1)
                  collect (sha256 bytes)))))

(defstruct (block-access-account (:constructor make-block-access-account
                                      (&key address
                                            (storage-writes '())
                                            (storage-reads '())
                                            (balance-changes '())
                                            (nonce-changes '())
                                            (code-changes '()))))
  address
  (storage-writes '() :type list)
  (storage-reads '() :type list)
  (balance-changes '() :type list)
  (nonce-changes '() :type list)
  (code-changes '() :type list))

(defstruct (block-access-storage-write
            (:constructor make-block-access-storage-write
                (&key tx-index value-after)))
  tx-index
  value-after)

(defstruct (block-access-slot-writes
            (:constructor make-block-access-slot-writes
                (&key slot (accesses '()))))
  slot
  (accesses '() :type list))

(defstruct (block-access-balance-change
            (:constructor make-block-access-balance-change
                (&key tx-index balance)))
  tx-index
  balance)

(defstruct (block-access-nonce-change
            (:constructor make-block-access-nonce-change
                (&key tx-index nonce)))
  tx-index
  nonce)

(defstruct (block-access-code-change
            (:constructor make-block-access-code-change
                (&key tx-index code)))
  tx-index
  code)

(defun hash32-uint256 (hash)
  (bytes-to-integer (hash32-bytes hash)))

(defun block-access-storage-write-rlp-object (write)
  (make-rlp-list
   (block-access-storage-write-tx-index write)
   (block-access-storage-write-value-after write)))

(defun block-access-slot-writes-rlp-object (slot-writes)
  (make-rlp-list
   (hash32-uint256 (block-access-slot-writes-slot slot-writes))
   (apply #'make-rlp-list
          (mapcar #'block-access-storage-write-rlp-object
                  (block-access-slot-writes-accesses slot-writes)))))

(defun block-access-balance-change-rlp-object (change)
  (make-rlp-list
   (block-access-balance-change-tx-index change)
   (block-access-balance-change-balance change)))

(defun block-access-nonce-change-rlp-object (change)
  (make-rlp-list
   (block-access-nonce-change-tx-index change)
   (block-access-nonce-change-nonce change)))

(defun block-access-code-change-rlp-object (change)
  (make-rlp-list
   (block-access-code-change-tx-index change)
   (ensure-byte-vector (block-access-code-change-code change))))

(defun block-access-account-rlp-object (account)
  (make-rlp-list
   (address-bytes (block-access-account-address account))
   (mapcar #'block-access-slot-writes-rlp-object
           (block-access-account-storage-writes account))
   (mapcar #'hash32-uint256 (block-access-account-storage-reads account))
   (mapcar #'block-access-balance-change-rlp-object
           (block-access-account-balance-changes account))
   (mapcar #'block-access-nonce-change-rlp-object
           (block-access-account-nonce-changes account))
   (mapcar #'block-access-code-change-rlp-object
           (block-access-account-code-changes account))))

(defun block-access-account-rlp (account)
  (rlp-encode (block-access-account-rlp-object account)))

(defun block-access-list-rlp (block-access-list)
  (rlp-encode
   (apply #'make-rlp-list
          (mapcar #'block-access-account-rlp-object block-access-list))))

(defun require-block-access-rlp-list (value label)
  (unless (rlp-list-p value)
    (block-validation-fail "Block access list ~A must be an RLP list" label))
  (rlp-list-items value))

(defun require-block-access-rlp-list-fields (value count label)
  (let ((items (require-block-access-rlp-list value label)))
    (unless (= (length items) count)
      (block-validation-fail "Block access list ~A must contain ~D fields"
                             label count))
    items))

(defun require-block-access-rlp-bytes (value label)
  (unless (byte-vector-p value)
    (block-validation-fail "Block access list ~A must be RLP bytes" label))
  value)

(defun block-access-address-from-rlp-bytes (value label)
  (let ((bytes (require-block-access-rlp-bytes value label)))
    (unless (= (length bytes) 20)
      (block-validation-fail "Block access list ~A must be exactly 20 bytes"
                             label))
    (make-address bytes)))

(defun block-access-rlp-uint (value label)
  (bytes-to-integer (require-block-access-rlp-bytes value label)))

(defun uint256-to-hash32 (value label)
  (unless (uint256-p value)
    (block-validation-fail "Block access list ~A must be uint256" label))
  (let* ((bytes (integer-to-minimal-bytes value))
         (out (make-byte-vector 32)))
    (replace out bytes :start1 (- 32 (length bytes)))
    (make-hash32 out)))

(defun decode-block-access-storage-write-rlp-object (value)
  (let ((items (require-block-access-rlp-list-fields value 2
                                                     "storage write")))
    (make-block-access-storage-write
     :tx-index (block-access-rlp-uint (first items) "storage write tx index")
     :value-after (block-access-rlp-uint (second items)
                                         "storage write value-after"))))

(defun decode-block-access-slot-writes-rlp-object (value)
  (let ((items (require-block-access-rlp-list-fields value 2
                                                     "storage writes entry")))
    (make-block-access-slot-writes
     :slot (uint256-to-hash32
            (block-access-rlp-uint (first items) "storage write slot")
            "storage write slot")
     :accesses
     (mapcar #'decode-block-access-storage-write-rlp-object
             (require-block-access-rlp-list (second items)
                                            "storage write accesses")))))

(defun decode-block-access-balance-change-rlp-object (value)
  (let ((items (require-block-access-rlp-list-fields value 2
                                                     "balance change")))
    (make-block-access-balance-change
     :tx-index (block-access-rlp-uint (first items) "balance change tx index")
     :balance (block-access-rlp-uint (second items)
                                     "balance change balance"))))

(defun decode-block-access-nonce-change-rlp-object (value)
  (let ((items (require-block-access-rlp-list-fields value 2
                                                     "nonce change")))
    (make-block-access-nonce-change
     :tx-index (block-access-rlp-uint (first items) "nonce change tx index")
     :nonce (block-access-rlp-uint (second items) "nonce change nonce"))))

(defun decode-block-access-code-change-rlp-object (value)
  (let ((items (require-block-access-rlp-list-fields value 2
                                                     "code change")))
    (make-block-access-code-change
     :tx-index (block-access-rlp-uint (first items) "code change tx index")
     :code (require-block-access-rlp-bytes (second items)
                                           "code change code"))))

(defun decode-block-access-account-rlp-object (value)
  (let ((items (require-block-access-rlp-list-fields value 6 "account")))
    (make-block-access-account
     :address (block-access-address-from-rlp-bytes (first items)
                                                   "account address")
     :storage-writes
     (mapcar #'decode-block-access-slot-writes-rlp-object
             (require-block-access-rlp-list (second items)
                                            "storage writes"))
     :storage-reads
     (mapcar (lambda (slot)
               (uint256-to-hash32
                (block-access-rlp-uint slot "storage read")
                "storage read"))
             (require-block-access-rlp-list (third items)
                                            "storage reads"))
     :balance-changes
     (mapcar #'decode-block-access-balance-change-rlp-object
             (require-block-access-rlp-list (fourth items)
                                            "balance changes"))
     :nonce-changes
     (mapcar #'decode-block-access-nonce-change-rlp-object
             (require-block-access-rlp-list (fifth items)
                                            "nonce changes"))
     :code-changes
     (mapcar #'decode-block-access-code-change-rlp-object
             (require-block-access-rlp-list (sixth items)
                                            "code changes")))))

(defun decode-block-access-list-rlp-object (value)
  (mapcar #'decode-block-access-account-rlp-object
          (require-block-access-rlp-list value "root")))

(defun block-access-list-hash (block-access-list)
  (validate-block-access-list-fields block-access-list)
  (keccak-256-hash (block-access-list-rlp block-access-list)))

(defun block-access-list-rlp-input-bytes (bytes)
  (handler-case
      (ensure-byte-vector bytes)
    (error ()
      (block-validation-fail
       "Block access list RLP must be a byte sequence"))))

(defun block-access-list-from-rlp
    (bytes &key max-code-size max-items)
  (let ((bytes (block-access-list-rlp-input-bytes bytes)))
    (handler-case
        (let ((access-list (decode-block-access-list-rlp-object
                            (rlp-decode-one bytes))))
          (validate-block-access-list-fields access-list
                                             :max-code-size max-code-size
                                             :max-items max-items)
          access-list)
      (block-validation-error (condition)
        (error condition))
      (rlp-error (condition)
        (block-validation-fail "Invalid block access list RLP: ~A" condition)))))

(defun block-access-list-rlp-hash
    (bytes &key max-code-size max-items)
  (let ((bytes (block-access-list-rlp-input-bytes bytes)))
    (block-access-list-from-rlp bytes
                                :max-code-size max-code-size
                                :max-items max-items)
    (keccak-256-hash bytes)))

(defun validated-block-access-list-commitment
    (block &key max-code-size max-items)
  (let ((access-list (block-block-access-list block))
        (encoded (block-encoded-block-access-list block)))
    (validate-block-access-list-fields access-list
                                       :max-code-size max-code-size
                                       :max-items max-items)
    (if encoded
        (let ((decoded (block-access-list-from-rlp
                        encoded
                        :max-code-size max-code-size
                        :max-items max-items)))
          (unless (bytes= (block-access-list-rlp decoded)
                          (block-access-list-rlp access-list))
            (block-validation-fail
             "Encoded block access list does not match block access list body"))
          (keccak-256-hash encoded))
        (block-access-list-hash access-list))))

(defun validate-byte-sequence-field (value label &key size)
  (let ((bytes (handler-case
                   (ensure-byte-vector value)
                 (error ()
                   (block-validation-fail "~A must be a byte sequence"
                                          label)))))
    (when (and size (/= size (length bytes)))
      (block-validation-fail "~A must be exactly ~D bytes" label size))
    bytes))

(defun validate-optional-hash32-field (value label)
  (when (and value (not (hash32-p value)))
    (block-validation-fail "~A must be a hash32" label))
  t)

(defun validate-optional-address-field (value label)
  (when (and value (not (address-p value)))
    (block-validation-fail "~A must be an address" label))
  t)

(defun validate-optional-uint256-field (value label)
  (when (and value (not (uint256-p value)))
    (block-validation-fail "~A must be uint256" label))
  t)

(defun validate-optional-uint64-field (value label)
  (when (and value
             (not (and (integerp value)
                       (<= 0 value)
                       (< value (expt 2 64)))))
    (block-validation-fail "~A must be uint64" label))
  t)

(defun validate-execution-request-fields (request)
  (let ((bytes (handler-case
                   (ensure-byte-vector request)
                 (error ()
                   (block-validation-fail
                    "Execution request must be a byte vector")))))
    (when (zerop (length bytes))
      (block-validation-fail "Execution request is missing request type"))
    bytes))

(defun validate-execution-request-list-fields (requests)
  (unless (listp requests)
    (block-validation-fail "Execution requests must be a list"))
  (loop with previous-type = nil
        for request in requests
        for bytes = (validate-execution-request-fields request)
        for request-type = (aref bytes 0)
        do (when (< (length bytes) 2)
             (block-validation-fail
              "Execution request must contain request type and payload"))
           (when (and previous-type
                      (<= request-type previous-type))
             (block-validation-fail
              "Execution requests must be ordered by unique request type"))
           (setf previous-type request-type)
        finally (return t)))

(defun byte-vector-lexicographic< (left right)
  (let ((left (ensure-byte-vector left))
        (right (ensure-byte-vector right)))
    (loop for index below (min (length left) (length right))
          for left-byte = (aref left index)
          for right-byte = (aref right index)
          when (< left-byte right-byte)
            do (return t)
          when (> left-byte right-byte)
            do (return nil)
          finally (return (< (length left) (length right))))))

(defun uint32-value-p (value)
  (and (integerp value)
       (<= 0 value)
       (< value (expt 2 32))))

(defun validate-block-access-storage-write-fields (write)
  (unless (block-access-storage-write-p write)
    (block-validation-fail
     "Block access list storage write must be a storage write"))
  (unless (uint32-value-p (block-access-storage-write-tx-index write))
    (block-validation-fail "Block access list storage write tx index must be uint32"))
  (unless (uint256-p (block-access-storage-write-value-after write))
    (block-validation-fail
     "Block access list storage write value-after must be uint256"))
  t)

(defun validate-block-access-slot-writes-fields (slot-writes)
  (unless (block-access-slot-writes-p slot-writes)
    (block-validation-fail
     "Block access list storage writes entry must be slot writes"))
  (unless (hash32-p (block-access-slot-writes-slot slot-writes))
    (block-validation-fail "Block access list storage write slot must be a hash32"))
  (unless (listp (block-access-slot-writes-accesses slot-writes))
    (block-validation-fail
     "Block access list storage write accesses must be a list"))
  (when (null (block-access-slot-writes-accesses slot-writes))
    (block-validation-fail
     "Block access list storage write slot must contain at least one access"))
  (let ((previous-tx-index nil))
    (dolist (write (block-access-slot-writes-accesses slot-writes))
      (validate-block-access-storage-write-fields write)
      (let ((tx-index (block-access-storage-write-tx-index write)))
        (when (and previous-tx-index
                   (<= tx-index previous-tx-index))
          (block-validation-fail
           "Block access list storage write tx indices must be sorted"))
        (setf previous-tx-index tx-index))))
  t)

(defun validate-block-access-balance-change-fields (change)
  (unless (block-access-balance-change-p change)
    (block-validation-fail
     "Block access list balance change must be a balance change"))
  (unless (uint32-value-p (block-access-balance-change-tx-index change))
    (block-validation-fail
     "Block access list balance change tx index must be uint32"))
  (unless (uint256-p (block-access-balance-change-balance change))
    (block-validation-fail
     "Block access list balance change balance must be uint256"))
  t)

(defun validate-block-access-nonce-change-fields (change)
  (unless (block-access-nonce-change-p change)
    (block-validation-fail
     "Block access list nonce change must be a nonce change"))
  (unless (uint32-value-p (block-access-nonce-change-tx-index change))
    (block-validation-fail
     "Block access list nonce change tx index must be uint32"))
  (unless (uint64-value-p (block-access-nonce-change-nonce change))
    (block-validation-fail
     "Block access list nonce change nonce must be uint64"))
  t)

(defun validate-block-access-code-change-fields (change &key max-code-size)
  (unless (block-access-code-change-p change)
    (block-validation-fail
     "Block access list code change must be a code change"))
  (unless (uint32-value-p (block-access-code-change-tx-index change))
    (block-validation-fail
     "Block access list code change tx index must be uint32"))
  (let ((code (validate-byte-sequence-field
               (block-access-code-change-code change)
               "Block access list code change code")))
    (when (and max-code-size
               (> (length code) max-code-size))
      (block-validation-fail
       "Block access list code change exceeds maximum code size")))
  t)

(defun validate-block-access-indexed-change-list
    (changes validate-change tx-index-fn label)
  (unless (listp changes)
    (block-validation-fail "Block access list ~A must be a list" label))
  (let ((previous-tx-index nil))
    (dolist (change changes)
      (funcall validate-change change)
      (let ((tx-index (funcall tx-index-fn change)))
        (when (and previous-tx-index
                   (<= tx-index previous-tx-index))
          (block-validation-fail
           "Block access list ~A tx indices must be sorted" label))
        (setf previous-tx-index tx-index))))
  t)

(defun validate-block-access-account-fields (account &key max-code-size)
  (unless (block-access-account-p account)
    (block-validation-fail
     "Block access list account must be a block access account"))
  (unless (address-p (block-access-account-address account))
    (block-validation-fail "Block access list account address must be an address"))
  (unless (listp (block-access-account-storage-writes account))
    (block-validation-fail "Block access list storage writes must be a list"))
  (unless (listp (block-access-account-storage-reads account))
    (block-validation-fail "Block access list storage reads must be a list"))
  (validate-block-access-indexed-change-list
   (block-access-account-balance-changes account)
   #'validate-block-access-balance-change-fields
   #'block-access-balance-change-tx-index
   "balance changes")
  (validate-block-access-indexed-change-list
   (block-access-account-nonce-changes account)
   #'validate-block-access-nonce-change-fields
   #'block-access-nonce-change-tx-index
   "nonce changes")
  (validate-block-access-indexed-change-list
   (block-access-account-code-changes account)
   (lambda (change)
     (validate-block-access-code-change-fields
      change
      :max-code-size max-code-size))
   #'block-access-code-change-tx-index
   "code changes")
  (let ((previous-slot-bytes nil)
        (write-slot-table (make-hash-table :test #'equal)))
    (dolist (slot-writes (block-access-account-storage-writes account))
      (validate-block-access-slot-writes-fields slot-writes)
      (let* ((slot (block-access-slot-writes-slot slot-writes))
             (slot-bytes (hash32-bytes slot)))
        (when (and previous-slot-bytes
                   (not (byte-vector-lexicographic< previous-slot-bytes
                                                    slot-bytes)))
          (block-validation-fail
           "Block access list storage write slots must be sorted"))
        (setf (gethash (bytes-to-hex slot-bytes :prefix nil) write-slot-table)
              t)
        (setf previous-slot-bytes slot-bytes)))
    (setf previous-slot-bytes nil)
    (dolist (slot (block-access-account-storage-reads account))
      (unless (hash32-p slot)
        (block-validation-fail "Block access list storage read must be a hash32"))
      (let ((slot-bytes (hash32-bytes slot)))
        (when (and previous-slot-bytes
                   (not (byte-vector-lexicographic< previous-slot-bytes
                                                    slot-bytes)))
          (block-validation-fail
           "Block access list storage reads must be sorted"))
        (when (gethash (bytes-to-hex slot-bytes :prefix nil) write-slot-table)
          (block-validation-fail
           "Block access list storage read duplicates a storage write slot"))
        (setf previous-slot-bytes slot-bytes))))
  t)

(defun block-access-list-item-count (block-access-list)
  (unless (listp block-access-list)
    (block-validation-fail "Block access list must be a list"))
  (loop for account in block-access-list
        do (unless (block-access-account-p account)
             (block-validation-fail
              "Block access list account must be a block access account"))
        sum (+ 1
               (length (block-access-account-storage-writes account))
               (length (block-access-account-storage-reads account)))))

(defun validate-block-access-list-fields
    (block-access-list &key max-code-size max-items)
  (unless (listp block-access-list)
    (block-validation-fail "Block access list must be a list"))
  (let ((previous-address-bytes nil)
        (item-count 0))
    (dolist (account block-access-list)
      (validate-block-access-account-fields account
                                            :max-code-size max-code-size)
      (incf item-count
            (+ 1
               (length (block-access-account-storage-writes account))
               (length (block-access-account-storage-reads account))))
      (let ((address-bytes (address-bytes
                            (block-access-account-address account))))
        (when (and previous-address-bytes
                   (not (byte-vector-lexicographic< previous-address-bytes
                                                    address-bytes)))
          (block-validation-fail
           "Block access list account addresses must be sorted"))
        (setf previous-address-bytes address-bytes)))
    (when (and max-items
               (> item-count max-items))
      (block-validation-fail
       "Block access list item count exceeds gas limit")))
  t)

(defun expected-base-fee-per-gas
    (parent-header &key (london-parent-p t)
                        (elasticity-multiplier
                         +base-fee-elasticity-multiplier+)
                        (change-denominator
                         +base-fee-change-denominator+))
  (if (not london-parent-p)
      +initial-base-fee+
      (let* ((parent-base-fee (block-header-base-fee-per-gas parent-header))
             (parent-gas-limit (block-header-gas-limit parent-header))
             (parent-gas-used (block-header-gas-used parent-header))
             (parent-gas-target (floor parent-gas-limit
                                       elasticity-multiplier)))
        (unless parent-base-fee
          (block-validation-fail "Parent header is missing base fee"))
        (cond
          ((or (zerop parent-gas-target) (zerop change-denominator))
           parent-base-fee)
          ((= parent-gas-used parent-gas-target)
           parent-base-fee)
          ((> parent-gas-used parent-gas-target)
           (let* ((gas-delta (- parent-gas-used parent-gas-target))
                  (fee-delta (floor (* parent-base-fee gas-delta)
                                    (* parent-gas-target
                                       change-denominator))))
             (+ parent-base-fee (max 1 fee-delta))))
          (t
           (let* ((gas-delta (- parent-gas-target parent-gas-used))
                  (fee-delta (floor (* parent-base-fee gas-delta)
                                    (* parent-gas-target
                                       change-denominator))))
             (max 0 (- parent-base-fee fee-delta))))))))

(defun hash32= (left right)
  (and left
       right
       (bytes= (hash32-bytes left) (hash32-bytes right))))

(defun validate-blob-versioned-hash (hash)
  (when (null hash)
    (block-validation-fail "Missing blob versioned hash"))
  (let ((bytes (handler-case
                   (etypecase hash
                     (hash32 (hash32-bytes hash))
                     (byte-vector (ensure-byte-vector hash))
                     (vector (ensure-byte-vector hash)))
                 (error ()
                   (block-validation-fail "Invalid blob versioned hash")))))
    (unless (= 32 (length bytes))
      (block-validation-fail "Invalid blob versioned hash size"))
    (unless (= +kzg-commitment-version+ (aref bytes 0))
      (block-validation-fail "Invalid blob versioned hash version"))
    t))

(defun validate-blob-transaction-fields
    (transaction &key (min-blobs +min-blobs-per-transaction+)
                      (max-blobs +max-blobs-per-block+))
  (let* ((hashes (blob-transaction-blob-versioned-hashes transaction))
         (count (length hashes)))
    (unless (blob-transaction-to transaction)
      (block-validation-fail "Blob transaction cannot create contracts"))
    (when (< count min-blobs)
      (block-validation-fail "Blob transaction missing blob hashes"))
    (when (and max-blobs (> count max-blobs))
      (block-validation-fail "Blob transaction has too many blob hashes"))
    (dolist (hash hashes t)
      (validate-blob-versioned-hash hash))))

(defun validate-blob-transaction-fee-cap (transaction blob-base-fee)
  (unless (uint256-p (blob-transaction-max-fee-per-blob-gas transaction))
    (block-validation-fail "Max fee per blob gas must be uint256"))
  (when (< (blob-transaction-max-fee-per-blob-gas transaction)
           blob-base-fee)
    (block-validation-fail "Max fee per blob gas below blob base fee"))
  t)

(defun validate-transaction-data-field (transaction)
  (handler-case
      (progn
        (ensure-byte-vector (transaction-data transaction))
        t)
    (error ()
      (block-validation-fail "Transaction data must be a byte sequence"))))

(defun validate-transaction-recipient-field (transaction)
  (handler-case
      (progn
        (transaction-to-bytes (transaction-to transaction))
        t)
    (error ()
      (block-validation-fail
       "Transaction recipient must be nil or a 20-byte value"))))

(defun uint64-value-p (value)
  (and (integerp value)
       (<= 0 value (1- (ash 1 64)))))

(defun validate-transaction-scalar-fields (transaction)
  (unless (uint64-value-p (transaction-nonce transaction))
    (block-validation-fail "Transaction nonce must be uint64"))
  (unless (uint64-value-p (transaction-gas-limit transaction))
    (block-validation-fail "Transaction gas limit must be uint64"))
  (unless (uint256-p (transaction-value transaction))
    (block-validation-fail "Transaction value must be uint256"))
  (let ((max-priority-fee (transaction-max-priority-fee-per-gas transaction))
        (max-fee (transaction-max-fee-per-gas transaction)))
    (unless (uint256-p max-priority-fee)
      (block-validation-fail "Max priority fee must be uint256"))
    (unless (uint256-p max-fee)
      (block-validation-fail "Max fee per gas must be uint256"))
    (when (< max-fee max-priority-fee)
      (block-validation-fail "Max priority fee exceeds max fee")))
  (when (typep transaction 'blob-transaction)
    (unless (uint256-p (blob-transaction-max-fee-per-blob-gas transaction))
      (block-validation-fail "Max fee per blob gas must be uint256")))
  t)

(defun validate-transaction-signature-fields (transaction)
  (etypecase transaction
    (legacy-transaction
     (unless (uint256-p (legacy-transaction-v transaction))
       (block-validation-fail "Transaction v must be uint256"))
     (unless (uint256-p (legacy-transaction-r transaction))
       (block-validation-fail "Transaction r must be uint256"))
     (unless (uint256-p (legacy-transaction-s transaction))
       (block-validation-fail "Transaction s must be uint256")))
    ((or access-list-transaction
         dynamic-fee-transaction
         blob-transaction
         set-code-transaction)
     (unless (uint256-p
              (etypecase transaction
                (access-list-transaction
                 (access-list-transaction-chain-id transaction))
                (dynamic-fee-transaction
                 (dynamic-fee-transaction-chain-id transaction))
                (blob-transaction
                 (blob-transaction-chain-id transaction))
                (set-code-transaction
                 (set-code-transaction-chain-id transaction))))
       (block-validation-fail "Transaction chain id must be uint256"))
     (unless (uint256-p
              (etypecase transaction
                (access-list-transaction
                 (access-list-transaction-y-parity transaction))
                (dynamic-fee-transaction
                 (dynamic-fee-transaction-y-parity transaction))
                (blob-transaction
                 (blob-transaction-y-parity transaction))
                (set-code-transaction
                 (set-code-transaction-y-parity transaction))))
       (block-validation-fail "Transaction y parity must be uint256"))
     (unless (uint256-p
              (etypecase transaction
                (access-list-transaction
                 (access-list-transaction-r transaction))
                (dynamic-fee-transaction
                 (dynamic-fee-transaction-r transaction))
                (blob-transaction
                 (blob-transaction-r transaction))
                (set-code-transaction
                 (set-code-transaction-r transaction))))
       (block-validation-fail "Transaction r must be uint256"))
     (unless (uint256-p
              (etypecase transaction
                (access-list-transaction
                 (access-list-transaction-s transaction))
                (dynamic-fee-transaction
                 (dynamic-fee-transaction-s transaction))
                (blob-transaction
                 (blob-transaction-s transaction))
                (set-code-transaction
                 (set-code-transaction-s transaction))))
       (block-validation-fail "Transaction s must be uint256"))))
  t)

(defun validate-access-list-fields (transaction)
  (dolist (entry (transaction-access-list transaction) t)
    (unless (typep entry 'access-list-entry)
      (block-validation-fail
       "Access list entry must be an access-list entry"))
    (unless (address-p (access-list-entry-address entry))
      (block-validation-fail "Access list entry address must be an address"))
    (unless (listp (access-list-entry-storage-keys entry))
      (block-validation-fail "Access list storage keys must be a list"))
    (dolist (slot (access-list-entry-storage-keys entry))
      (unless (hash32-p slot)
        (block-validation-fail "Access list storage key must be a hash32")))))

(defun validate-set-code-authorization-fields (authorization)
  (unless (typep authorization 'set-code-authorization)
    (block-validation-fail
     "Set-code authorization must be a set-code authorization"))
  (unless (uint256-p (set-code-authorization-chain-id authorization))
    (block-validation-fail "Authorization chain id must be uint256"))
  (unless (address-p (set-code-authorization-address authorization))
    (block-validation-fail "Authorization address must be an address"))
  (unless (and (integerp (set-code-authorization-nonce authorization))
               (<= 0 (set-code-authorization-nonce authorization)
                   (1- (ash 1 64))))
    (block-validation-fail "Authorization nonce must be uint64"))
  (unless (uint256-p (set-code-authorization-y-parity authorization))
    (block-validation-fail "Authorization y parity must be uint256"))
  (unless (uint256-p (set-code-authorization-r authorization))
    (block-validation-fail "Authorization r must be uint256"))
  (unless (uint256-p (set-code-authorization-s authorization))
    (block-validation-fail "Authorization s must be uint256"))
  t)

(defun validate-set-code-transaction-fields (transaction)
  (when (typep transaction 'set-code-transaction)
    (unless (transaction-to transaction)
      (block-validation-fail "Set-code transaction cannot create contracts"))
    (when (null (transaction-authorization-list transaction))
      (block-validation-fail
       "Set-code transaction requires an authorization list"))
    (dolist (authorization (transaction-authorization-list transaction))
      (validate-set-code-authorization-fields authorization)))
  t)

(defun validate-set-code-authorization-signatures (transaction)
  (when (typep transaction 'set-code-transaction)
    (dolist (authorization (set-code-transaction-authorization-list transaction))
      (unless (secp256k1-valid-signature-values-p
               (set-code-authorization-y-parity authorization)
               (set-code-authorization-r authorization)
               (set-code-authorization-s authorization)
               :low-s-p t)
        (block-validation-fail
         "Authorization signature values are invalid"))))
  t)

(defun validate-sized-byte-vector (value size label)
  (let ((bytes (handler-case
                   (ensure-byte-vector value)
                 (error ()
                   (block-validation-fail
                    (format nil "~A must be exactly ~D bytes" label size))))))
    (unless (= (length bytes) size)
      (block-validation-fail
       (format nil "~A must be exactly ~D bytes" label size)))
    bytes))

(defvar *kzg-point-proof-verifier* nil
  "Optional verifier for EIP-4844 point proofs.

When non-NIL, the value must be a function of COMMITMENT, Z, Y, and PROOF byte
vectors. It should return true only when the proof is valid.")

(defvar *kzg-blob-proof-verifier* nil
  "Optional verifier for EIP-4844 blob proofs.

When non-NIL, the value must be a function of BLOB, COMMITMENT, and PROOF byte
vectors. It should return true only when the proof is valid.")

(defparameter *kzg-verifier-command-timeout-seconds* 5
  "Maximum wall-clock seconds to wait for an external KZG verifier command.")

(defun kzg-point-proof-verification-available-p ()
  (functionp *kzg-point-proof-verifier*))

(defun kzg-blob-proof-verification-available-p ()
  (functionp *kzg-blob-proof-verifier*))

(defun kzg-proof-verification-available-p ()
  (and (kzg-point-proof-verification-available-p)
       (kzg-blob-proof-verification-available-p)))

(defun normalize-kzg-verifier-command (command)
  (labels ((valid-command-string-p (value)
             (and (stringp value)
                  (plusp (length value))
                  (not (every (lambda (char)
                                (find char '(#\Space #\Tab #\Newline #\Return)))
                              value)))))
    (cond
      ((valid-command-string-p command)
       (list command))
      ((and (listp command)
            command
            (every #'valid-command-string-p command))
       (copy-list command))
      (t
       (error "KZG verifier command must be a non-empty string or list of non-empty strings")))))

(defun kzg-verifier-command-executable-file-p (path)
  (let ((file (uiop:file-exists-p path)))
    (when file
      #+sbcl
      (handler-case
          (progn
            (require :sb-posix)
            (let* ((package (find-package "SB-POSIX"))
                   (access (and package (find-symbol "ACCESS" package)))
                   (x-ok (and package (find-symbol "X-OK" package))))
              (and access
                   x-ok
                   (zerop (funcall access
                                   (namestring file)
                                   (symbol-value x-ok))))))
        (error () nil))
      #-sbcl
      t)))

(defun kzg-verifier-command-program-executable-p (program)
  (labels ((blank-string-p (value)
             (or (null value)
                 (zerop (length
                         (string-trim '(#\Space #\Tab #\Newline #\Return)
                                      value)))))
           (candidate (directory)
             (format nil "~A/~A"
                     (if (blank-string-p directory) "." directory)
                     program)))
    (if (find #\/ program)
        (kzg-verifier-command-executable-file-p program)
        (loop for directory in (uiop:split-string
                                (or (uiop:getenv "PATH") "")
                                :separator ":")
              thereis (kzg-verifier-command-executable-file-p
                       (candidate directory))))))

(defun validate-kzg-verifier-command (command)
  (let* ((normalized (normalize-kzg-verifier-command command))
         (program (first normalized)))
    (unless (kzg-verifier-command-program-executable-p program)
      (error "KZG verifier command is not executable: ~A" program))
    normalized))

(defun kzg-verifier-command-accepted-output-p (output)
  (let ((token (string-downcase
                (string-trim '(#\Space #\Tab #\Newline #\Return)
                             output))))
    (member token '("1" "ok" "true" "valid") :test #'string=)))

(defun read-kzg-verifier-command-stream (stream)
  (if stream
      (with-output-to-string (output)
        (loop for char = (read-char stream nil nil)
              while char
              do (write-char char output)))
      ""))

(defun wait-kzg-verifier-command (process timeout-seconds)
  (let* ((timeout-units (* timeout-seconds internal-time-units-per-second))
         (deadline (+ (get-internal-real-time) timeout-units)))
    (loop while (uiop:process-alive-p process)
          do (when (>= (get-internal-real-time) deadline)
               (uiop:terminate-process process)
               (ignore-errors (uiop:wait-process process))
               (error "KZG verifier command timed out after ~D seconds"
                      timeout-seconds))
             (sleep 0.01))
    (uiop:wait-process process)))

(defun run-kzg-verifier-command (command mode byte-arguments)
  (let ((argv (append command
                      (list mode)
                      (mapcar (lambda (bytes)
                                (bytes-to-hex bytes))
                              byte-arguments))))
    (let ((process nil))
      (unwind-protect
           (progn
             (setf process
                   (handler-case
                       (uiop:launch-program argv
                                            :output :stream
                                            :error-output nil)
                     (error (condition)
                       (error "KZG verifier command failed to start: ~A"
                              condition))))
             (let ((status
                     (wait-kzg-verifier-command
                      process
                      *kzg-verifier-command-timeout-seconds*))
                   (stdout
                     (read-kzg-verifier-command-stream
                      (uiop:process-info-output process))))
               (and (numberp status)
                    (= 0 status)
                    (kzg-verifier-command-accepted-output-p stdout))))
        (when (and process (uiop:process-alive-p process))
          (ignore-errors (uiop:terminate-process process)))))))

(defun make-kzg-point-proof-command-verifier (command)
  "Return a point-proof verifier backed by COMMAND.

COMMAND is a string executable name/path or a list of executable plus fixed
arguments. The command is invoked as:

  COMMAND point COMMITMENT_HEX Z_HEX Y_HEX PROOF_HEX

It must exit 0 and print one of true, ok, valid, or 1 to stdout when the proof
is valid."
  (let ((command (validate-kzg-verifier-command command)))
    (lambda (commitment z y proof)
      (run-kzg-verifier-command command
                                "point"
                                (list commitment z y proof)))))

(defun make-kzg-blob-proof-command-verifier (command)
  "Return a blob-proof verifier backed by COMMAND.

COMMAND is a string executable name/path or a list of executable plus fixed
arguments. The command is invoked as:

  COMMAND blob BLOB_HEX COMMITMENT_HEX PROOF_HEX

It must exit 0 and print one of true, ok, valid, or 1 to stdout when the proof
is valid."
  (let ((command (validate-kzg-verifier-command command)))
    (lambda (blob commitment proof)
      (run-kzg-verifier-command command
                                "blob"
                                (list blob commitment proof)))))

(defun configure-kzg-proof-command-verifiers (command)
  "Install COMMAND-backed point and blob proof verifiers.

This wires the existing KZG verification hooks to an external verifier process
without changing consensus behavior when no verifier is configured."
  (setf *kzg-point-proof-verifier*
        (make-kzg-point-proof-command-verifier command)
        *kzg-blob-proof-verifier*
        (make-kzg-blob-proof-command-verifier command))
  t)

(defun validate-kzg-field-element (bytes label)
  (let ((bytes (ensure-byte-vector bytes)))
    (unless (= +kzg-field-element-size+ (length bytes))
      (error "~A must be exactly ~D bytes" label +kzg-field-element-size+))
    (unless (< (bytes-to-integer bytes) +kzg-field-modulus+)
      (error "~A must be less than BLS field modulus" label))
    bytes))

(defun validate-kzg-blob-field-elements (blob)
  (let ((blob (ensure-byte-vector blob)))
    (unless (= +blob-byte-size+ (length blob))
      (error "Blob must be exactly ~D bytes" +blob-byte-size+))
    (unless (= +kzg-blob-field-elements-per-blob+
               (/ (length blob) +kzg-field-element-size+))
      (error "Blob must contain exactly ~D field elements"
             +kzg-blob-field-elements-per-blob+))
    (loop for start below (length blob) by +kzg-field-element-size+
          for index from 0
          do (validate-kzg-field-element
              (subseq blob start (+ start +kzg-field-element-size+))
              (format nil "Blob field element ~D" index))))
  t)

(defun verify-kzg-point-proof (commitment z y proof)
  (unless (kzg-point-proof-verification-available-p)
    (error "KZG point proof verification is not available"))
  (let ((commitment (ensure-byte-vector commitment))
        (z (ensure-byte-vector z))
        (y (ensure-byte-vector y))
        (proof (ensure-byte-vector proof)))
    (unless (= +kzg-commitment-size+ (length commitment))
      (error "KZG commitment must be exactly ~D bytes" +kzg-commitment-size+))
    (validate-kzg-field-element z "KZG point z")
    (validate-kzg-field-element y "KZG point y")
    (unless (= +kzg-proof-size+ (length proof))
      (error "KZG proof must be exactly ~D bytes" +kzg-proof-size+))
    (unless (funcall *kzg-point-proof-verifier* commitment z y proof)
      (error "KZG point proof verification failed")))
  t)

(defun verify-kzg-blob-proof (blob commitment proof)
  (unless (kzg-blob-proof-verification-available-p)
    (error "KZG blob proof verification is not available"))
  (let ((blob (ensure-byte-vector blob))
        (commitment (ensure-byte-vector commitment))
        (proof (ensure-byte-vector proof)))
    (validate-kzg-blob-field-elements blob)
    (unless (= +kzg-commitment-size+ (length commitment))
      (error "KZG commitment must be exactly ~D bytes" +kzg-commitment-size+))
    (unless (= +kzg-proof-size+ (length proof))
      (error "KZG proof must be exactly ~D bytes" +kzg-proof-size+))
    (unless (funcall *kzg-blob-proof-verifier* blob commitment proof)
      (error "KZG blob proof verification failed")))
  t)

(defun validate-blob-sidecar-kzg-proofs (sidecar)
  (unless (kzg-blob-proof-verification-available-p)
    (block-validation-fail
     "KZG proof verification is not available; blob sidecars are shape-checked only"))
  (let ((blobs (blob-sidecar-blobs sidecar))
        (commitments (blob-sidecar-commitments sidecar))
        (proofs (blob-sidecar-proofs sidecar)))
    (unless (= (length proofs) (length blobs))
      (block-validation-fail
       "KZG cell proof verification is not available; blob proof verification requires one proof per blob"))
    (handler-case
        (loop for blob in blobs
              for commitment in commitments
              for proof in proofs
              do (verify-kzg-blob-proof blob commitment proof))
      (error (condition)
        (block-validation-fail "~A" condition))))
  t)

(defun validate-blob-sidecar-fields
    (sidecar &key transaction require-proof-verification)
  (let* ((blobs (blob-sidecar-blobs sidecar))
         (commitments (blob-sidecar-commitments sidecar))
         (proofs (blob-sidecar-proofs sidecar))
         (blob-count (length blobs))
         (commitment-count (length commitments))
         (proof-count (length proofs)))
    (unless (= blob-count commitment-count)
      (block-validation-fail
       "Blob sidecar blob and commitment counts must match"))
    (unless (or (= proof-count blob-count)
                (= proof-count (* blob-count +cell-proofs-per-blob+)))
      (block-validation-fail
       "Blob sidecar proof count must match blobs or cell proofs per blob"))
    (dolist (blob blobs)
      (validate-sized-byte-vector blob +blob-byte-size+ "Blob")
      (handler-case
          (validate-kzg-blob-field-elements blob)
        (error (condition)
          (block-validation-fail "~A" condition))))
    (dolist (commitment commitments)
      (validate-sized-byte-vector commitment +kzg-commitment-size+
                                  "KZG commitment"))
    (dolist (proof proofs)
      (validate-sized-byte-vector proof +kzg-proof-size+ "KZG proof"))
    (when transaction
      (unless (= blob-count (transaction-blob-count transaction))
        (block-validation-fail
         "Blob sidecar count does not match transaction blob hash count"))
      (loop for actual in (blob-sidecar-versioned-hashes sidecar)
            for expected across (transaction-blob-versioned-hashes transaction)
            unless (bytes= (hash32-bytes actual)
                           (blob-versioned-hash-bytes expected))
              do (block-validation-fail
                  "Blob sidecar commitment does not match transaction blob hash")))
    (when require-proof-verification
      (validate-blob-sidecar-kzg-proofs sidecar))
    t))
