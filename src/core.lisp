(in-package #:ethereum-lisp.core)

(defparameter +empty-ommers-hash+ (keccak-256-hash (rlp-encode '())))
(defconstant +initial-base-fee+ 1000000000)
(defconstant +base-fee-elasticity-multiplier+ 2)
(defconstant +base-fee-change-denominator+ 8)
(defconstant +blob-byte-size+ +blob-gas-per-blob+)
(defconstant +kzg-proof-size+ +kzg-commitment-size+)
(defconstant +cell-proofs-per-blob+ 128)
(defconstant +min-blobs-per-transaction+ 1)
(defconstant +min-blob-gas-price+ 1)
(defconstant +blob-base-cost+ 8192)
(defconstant +maximum-extra-data-size+ 32)
(defconstant +gas-limit-bound-divisor+ 1024)
(defconstant +minimum-gas-limit+ 5000)
(defconstant +max-header-gas-limit+ #x7fffffffffffffff)
(defconstant +block-access-list-max-code-size+ 24576)
(defconstant +block-access-list-amsterdam-max-code-size+ 32768)
(defconstant +block-access-list-item-gas-cost+ 2000)
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

(defun optional-bytes (value size label)
  (cond
    ((null value) (make-byte-vector 0))
    ((and size (= (length (ensure-byte-vector value)) size))
     (ensure-byte-vector value))
    (size (error "~A must be exactly ~D bytes" label size))
    (t (ensure-byte-vector value))))

(defstruct (state-account (:constructor make-state-account
                             (&key (nonce 0)
                                   (balance 0)
                                   (storage-root +empty-trie-hash+)
                                   (code-hash +empty-code-hash+))))
  (nonce 0 :type (integer 0 *))
  (balance 0 :type (integer 0 *))
  (storage-root +empty-trie-hash+ :type hash32)
  (code-hash +empty-code-hash+ :type hash32))

(defun state-account-rlp (account)
  (rlp-encode
   (make-rlp-list
    (ensure-uint256 (state-account-nonce account) "Account nonce")
    (ensure-uint256 (state-account-balance account) "Account balance")
    (hash32-bytes (state-account-storage-root account))
    (hash32-bytes (state-account-code-hash account)))))

(defun state-account-hash (account)
  (keccak-256-hash (state-account-rlp account)))

(defstruct (legacy-transaction (:constructor make-legacy-transaction
                                  (&key (nonce 0)
                                        (gas-price 0)
                                        (gas-limit 0)
                                        to
                                        (value 0)
                                        (data #())
                                        (v 0)
                                        (r 0)
                                        (s 0))))
  (nonce 0 :type (integer 0 *))
  (gas-price 0 :type (integer 0 *))
  (gas-limit 0 :type (integer 0 *))
  to
  (value 0 :type (integer 0 *))
  (data (make-byte-vector 0))
  (v 0 :type (integer 0 *))
  (r 0 :type (integer 0 *))
  (s 0 :type (integer 0 *)))

(defun transaction-to-bytes (to)
  (etypecase to
    (null (make-byte-vector 0))
    (address (address-bytes to))
    (byte-vector (optional-bytes to 20 "Transaction recipient"))
    (vector (optional-bytes to 20 "Transaction recipient"))))

(defun required-transaction-to-bytes (to label)
  (etypecase to
    (address (address-bytes to))
    (byte-vector (optional-bytes to 20 label))
    (vector (optional-bytes to 20 label))))

(defun legacy-transaction-rlp (transaction)
  (rlp-encode
   (make-rlp-list
    (ensure-uint256 (legacy-transaction-nonce transaction) "Transaction nonce")
    (ensure-uint256 (legacy-transaction-gas-price transaction) "Transaction gas price")
    (ensure-uint256 (legacy-transaction-gas-limit transaction) "Transaction gas limit")
    (transaction-to-bytes (legacy-transaction-to transaction))
    (ensure-uint256 (legacy-transaction-value transaction) "Transaction value")
    (ensure-byte-vector (legacy-transaction-data transaction))
    (ensure-uint256 (legacy-transaction-v transaction) "Transaction v")
    (ensure-uint256 (legacy-transaction-r transaction) "Transaction r")
    (ensure-uint256 (legacy-transaction-s transaction) "Transaction s"))))

(defun legacy-transaction-recipient-from-rlp (bytes)
  (let ((bytes (ensure-byte-vector bytes)))
    (cond
      ((zerop (length bytes)) nil)
      ((= (length bytes) 20) (make-address bytes))
      (t (block-validation-fail
          "Legacy transaction recipient must be empty or 20 bytes")))))

(defun rlp-uint-field (value label)
  (unless (byte-vector-p value)
    (block-validation-fail "~A must be RLP bytes" label))
  (bytes-to-integer value))

(defun rlp-bytes-field (value label)
  (unless (byte-vector-p value)
    (block-validation-fail "~A must be RLP bytes" label))
  (copy-seq value))

(defun legacy-transaction-from-rlp (bytes)
  (handler-case
      (let ((value (rlp-decode-one bytes)))
        (unless (rlp-list-p value)
          (block-validation-fail "Legacy transaction must be an RLP list"))
        (let ((fields (rlp-list-items value)))
          (unless (= (length fields) 9)
            (block-validation-fail
             "Legacy transaction must contain 9 fields"))
          (make-legacy-transaction
           :nonce (rlp-uint-field (first fields) "Transaction nonce")
           :gas-price (rlp-uint-field (second fields)
                                      "Transaction gas price")
           :gas-limit (rlp-uint-field (third fields)
                                      "Transaction gas limit")
           :to (legacy-transaction-recipient-from-rlp (fourth fields))
           :value (rlp-uint-field (fifth fields) "Transaction value")
           :data (rlp-bytes-field (sixth fields) "Transaction data")
           :v (rlp-uint-field (seventh fields) "Transaction v")
           :r (rlp-uint-field (eighth fields) "Transaction r")
           :s (rlp-uint-field (ninth fields) "Transaction s"))))
    (block-validation-error (condition)
      (error condition))
    (rlp-error (condition)
      (block-validation-fail "Invalid legacy transaction RLP: ~A"
                             condition))))

(defun legacy-transaction-hash (transaction)
  (keccak-256-hash (legacy-transaction-rlp transaction)))

(defun legacy-transaction-signing-payload
    (transaction &key (chain-id nil chain-id-provided-p))
  (let ((payload
          (list
           (ensure-uint256 (legacy-transaction-nonce transaction)
                           "Transaction nonce")
           (ensure-uint256 (legacy-transaction-gas-price transaction)
                           "Transaction gas price")
           (ensure-uint256 (legacy-transaction-gas-limit transaction)
                           "Transaction gas limit")
           (transaction-to-bytes (legacy-transaction-to transaction))
           (ensure-uint256 (legacy-transaction-value transaction)
                           "Transaction value")
           (ensure-byte-vector (legacy-transaction-data transaction)))))
    (when chain-id-provided-p
      (setf payload (append payload (list (ensure-uint256 chain-id
                                                          "Transaction chain id")
                                          0
                                          0))))
    (apply #'make-rlp-list payload)))

(defun legacy-transaction-signing-hash
    (transaction &key (chain-id nil chain-id-provided-p))
  (keccak-256-hash
   (rlp-encode
    (if chain-id-provided-p
        (legacy-transaction-signing-payload transaction :chain-id chain-id)
        (legacy-transaction-signing-payload transaction)))))

(defun legacy-transaction-protected-p (transaction)
  (>= (legacy-transaction-v transaction) 35))

(defun legacy-transaction-chain-id (transaction)
  (let ((v (legacy-transaction-v transaction)))
    (cond
      ((or (= v 27) (= v 28)) 0)
      ((>= v 35) (floor (- v 35) 2))
      (t nil))))

(defun legacy-transaction-y-parity (transaction)
  (let ((v (legacy-transaction-v transaction)))
    (cond
      ((or (= v 27) (= v 28)) (- v 27))
      ((>= v 35) (mod (- v 35) 2))
      (t nil))))

(defun legacy-transaction-sender
    (transaction &key expected-chain-id (homestead-p t))
  "Recover the sender address from a legacy transaction signature.
Returns NIL when V/R/S are invalid or the expected chain id does not match."
  (let* ((chain-id (legacy-transaction-chain-id transaction))
         (protected-p (legacy-transaction-protected-p transaction))
         (y-parity (legacy-transaction-y-parity transaction))
         (r (legacy-transaction-r transaction))
         (s (legacy-transaction-s transaction)))
    (when (and chain-id
               y-parity
               (or (not expected-chain-id)
                   (not protected-p)
                   (= expected-chain-id chain-id))
               (secp256k1-valid-signature-values-p
                y-parity r s :low-s-p homestead-p))
      (let ((hash (if protected-p
                      (legacy-transaction-signing-hash transaction
                                                       :chain-id chain-id)
                      (legacy-transaction-signing-hash transaction))))
        (secp256k1-recover-address (hash32-bytes hash) y-parity r s)))))

(defstruct (access-list-entry (:constructor make-access-list-entry
                                 (&key address (storage-keys '()))))
  address
  (storage-keys '() :type list))

(defun access-list-entry-rlp-object (entry)
  (make-rlp-list
   (address-bytes (access-list-entry-address entry))
   (mapcar #'hash32-bytes (access-list-entry-storage-keys entry))))

(defun access-list-rlp-object (access-list)
  (mapcar #'access-list-entry-rlp-object access-list))

(defun access-list-address-from-rlp (value label)
  (let ((bytes (rlp-bytes-field value label)))
    (unless (= (length bytes) 20)
      (block-validation-fail "~A must be exactly 20 bytes" label))
    (make-address bytes)))

(defun access-list-storage-key-from-rlp (value label)
  (let ((bytes (rlp-bytes-field value label)))
    (unless (= (length bytes) 32)
      (block-validation-fail "~A must be exactly 32 bytes" label))
    (make-hash32 bytes)))

(defun access-list-entry-from-rlp-object (value)
  (unless (rlp-list-p value)
    (block-validation-fail "Access list entry must be an RLP list"))
  (let ((fields (rlp-list-items value)))
    (unless (= (length fields) 2)
      (block-validation-fail "Access list entry must contain 2 fields"))
    (unless (rlp-list-p (second fields))
      (block-validation-fail "Access list storage keys must be an RLP list"))
    (make-access-list-entry
     :address (access-list-address-from-rlp
               (first fields)
               "Access list entry address")
     :storage-keys
     (mapcar (lambda (storage-key)
               (access-list-storage-key-from-rlp
                storage-key
                "Access list storage key"))
             (rlp-list-items (second fields))))))

(defun access-list-from-rlp-object (value)
  (unless (rlp-list-p value)
    (block-validation-fail "Access list must be an RLP list"))
  (mapcar #'access-list-entry-from-rlp-object
          (rlp-list-items value)))

(defstruct (access-list-transaction (:constructor make-access-list-transaction
                                      (&key (chain-id 0)
                                            (nonce 0)
                                            (gas-price 0)
                                            (gas-limit 0)
                                            to
                                            (value 0)
                                            (data #())
                                            (access-list '())
                                            (y-parity 0)
                                            (r 0)
                                            (s 0))))
  (chain-id 0 :type (integer 0 *))
  (nonce 0 :type (integer 0 *))
  (gas-price 0 :type (integer 0 *))
  (gas-limit 0 :type (integer 0 *))
  to
  (value 0 :type (integer 0 *))
  data
  (access-list '() :type list)
  (y-parity 0 :type (integer 0 *))
  (r 0 :type (integer 0 *))
  (s 0 :type (integer 0 *)))

(defun access-list-transaction-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (access-list-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (access-list-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (access-list-transaction-gas-price transaction) "Transaction gas price")
   (ensure-uint256 (access-list-transaction-gas-limit transaction) "Transaction gas limit")
   (transaction-to-bytes (access-list-transaction-to transaction))
   (ensure-uint256 (access-list-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (access-list-transaction-data transaction))
   (access-list-rlp-object (access-list-transaction-access-list transaction))
   (ensure-uint256 (access-list-transaction-y-parity transaction) "Transaction y parity")
   (ensure-uint256 (access-list-transaction-r transaction) "Transaction r")
   (ensure-uint256 (access-list-transaction-s transaction) "Transaction s")))

(defun access-list-transaction-encoding (transaction)
  (concat-bytes #(1) (rlp-encode (access-list-transaction-payload transaction))))

(defun access-list-transaction-from-rlp (bytes)
  (handler-case
      (let ((value (rlp-decode-one bytes)))
        (unless (rlp-list-p value)
          (block-validation-fail
           "Access-list transaction payload must be an RLP list"))
        (let ((fields (rlp-list-items value)))
          (unless (= (length fields) 11)
            (block-validation-fail
             "Access-list transaction payload must contain 11 fields"))
          (make-access-list-transaction
           :chain-id (rlp-uint-field (first fields)
                                     "Transaction chain id")
           :nonce (rlp-uint-field (second fields) "Transaction nonce")
           :gas-price (rlp-uint-field (third fields)
                                      "Transaction gas price")
           :gas-limit (rlp-uint-field (fourth fields)
                                      "Transaction gas limit")
           :to (legacy-transaction-recipient-from-rlp (fifth fields))
           :value (rlp-uint-field (sixth fields) "Transaction value")
           :data (rlp-bytes-field (seventh fields) "Transaction data")
           :access-list (access-list-from-rlp-object (eighth fields))
           :y-parity (rlp-uint-field (ninth fields) "Transaction y parity")
           :r (rlp-uint-field (tenth fields) "Transaction r")
           :s (rlp-uint-field (nth 10 fields) "Transaction s"))))
    (block-validation-error (condition)
      (error condition))
    (rlp-error (condition)
      (block-validation-fail "Invalid access-list transaction RLP: ~A"
                             condition))))

(defun access-list-transaction-signing-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (access-list-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (access-list-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (access-list-transaction-gas-price transaction) "Transaction gas price")
   (ensure-uint256 (access-list-transaction-gas-limit transaction) "Transaction gas limit")
   (transaction-to-bytes (access-list-transaction-to transaction))
   (ensure-uint256 (access-list-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (access-list-transaction-data transaction))
   (access-list-rlp-object (access-list-transaction-access-list transaction))))

(defun access-list-transaction-signing-hash (transaction)
  (keccak-256-hash
   (concat-bytes #(1)
                 (rlp-encode
                  (access-list-transaction-signing-payload transaction)))))

(defun access-list-transaction-hash (transaction)
  (keccak-256-hash (access-list-transaction-encoding transaction)))

(defstruct (dynamic-fee-transaction (:constructor make-dynamic-fee-transaction
                                     (&key (chain-id 0)
                                           (nonce 0)
                                           (max-priority-fee-per-gas 0)
                                           (max-fee-per-gas 0)
                                           (gas-limit 0)
                                           to
                                           (value 0)
                                           (data #())
                                           (access-list '())
                                           (y-parity 0)
                                           (r 0)
                                           (s 0))))
  (chain-id 0 :type (integer 0 *))
  (nonce 0 :type (integer 0 *))
  (max-priority-fee-per-gas 0 :type (integer 0 *))
  (max-fee-per-gas 0 :type (integer 0 *))
  (gas-limit 0 :type (integer 0 *))
  to
  (value 0 :type (integer 0 *))
  data
  (access-list '() :type list)
  (y-parity 0 :type (integer 0 *))
  (r 0 :type (integer 0 *))
  (s 0 :type (integer 0 *)))

(defun dynamic-fee-transaction-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (dynamic-fee-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (dynamic-fee-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (dynamic-fee-transaction-max-priority-fee-per-gas transaction)
                   "Transaction max priority fee")
   (ensure-uint256 (dynamic-fee-transaction-max-fee-per-gas transaction)
                   "Transaction max fee")
   (ensure-uint256 (dynamic-fee-transaction-gas-limit transaction) "Transaction gas limit")
   (transaction-to-bytes (dynamic-fee-transaction-to transaction))
   (ensure-uint256 (dynamic-fee-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (dynamic-fee-transaction-data transaction))
   (access-list-rlp-object (dynamic-fee-transaction-access-list transaction))
   (ensure-uint256 (dynamic-fee-transaction-y-parity transaction) "Transaction y parity")
   (ensure-uint256 (dynamic-fee-transaction-r transaction) "Transaction r")
   (ensure-uint256 (dynamic-fee-transaction-s transaction) "Transaction s")))

(defun dynamic-fee-transaction-encoding (transaction)
  (concat-bytes #(2) (rlp-encode (dynamic-fee-transaction-payload transaction))))

(defun dynamic-fee-transaction-from-rlp (bytes)
  (handler-case
      (let ((value (rlp-decode-one bytes)))
        (unless (rlp-list-p value)
          (block-validation-fail
           "Dynamic-fee transaction payload must be an RLP list"))
        (let ((fields (rlp-list-items value)))
          (unless (= (length fields) 12)
            (block-validation-fail
             "Dynamic-fee transaction payload must contain 12 fields"))
          (make-dynamic-fee-transaction
           :chain-id (rlp-uint-field (first fields)
                                     "Transaction chain id")
           :nonce (rlp-uint-field (second fields) "Transaction nonce")
           :max-priority-fee-per-gas
           (rlp-uint-field (third fields)
                           "Transaction max priority fee")
           :max-fee-per-gas
           (rlp-uint-field (fourth fields) "Transaction max fee")
           :gas-limit (rlp-uint-field (fifth fields)
                                      "Transaction gas limit")
           :to (legacy-transaction-recipient-from-rlp (sixth fields))
           :value (rlp-uint-field (seventh fields) "Transaction value")
           :data (rlp-bytes-field (eighth fields) "Transaction data")
           :access-list (access-list-from-rlp-object (ninth fields))
           :y-parity (rlp-uint-field (tenth fields) "Transaction y parity")
           :r (rlp-uint-field (nth 10 fields) "Transaction r")
           :s (rlp-uint-field (nth 11 fields) "Transaction s"))))
    (block-validation-error (condition)
      (error condition))
    (rlp-error (condition)
      (block-validation-fail "Invalid dynamic-fee transaction RLP: ~A"
                             condition))))

(defun dynamic-fee-transaction-signing-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (dynamic-fee-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (dynamic-fee-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (dynamic-fee-transaction-max-priority-fee-per-gas transaction)
                   "Transaction max priority fee")
   (ensure-uint256 (dynamic-fee-transaction-max-fee-per-gas transaction)
                   "Transaction max fee")
   (ensure-uint256 (dynamic-fee-transaction-gas-limit transaction) "Transaction gas limit")
   (transaction-to-bytes (dynamic-fee-transaction-to transaction))
   (ensure-uint256 (dynamic-fee-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (dynamic-fee-transaction-data transaction))
   (access-list-rlp-object (dynamic-fee-transaction-access-list transaction))))

(defun dynamic-fee-transaction-signing-hash (transaction)
  (keccak-256-hash
   (concat-bytes #(2)
                 (rlp-encode
                  (dynamic-fee-transaction-signing-payload transaction)))))

(defun dynamic-fee-transaction-hash (transaction)
  (keccak-256-hash (dynamic-fee-transaction-encoding transaction)))

(defstruct (blob-transaction (:constructor make-blob-transaction
                               (&key (chain-id 0)
                                     (nonce 0)
                                     (max-priority-fee-per-gas 0)
                                     (max-fee-per-gas 0)
                                     (gas-limit 0)
                                     to
                                     (value 0)
                                     (data #())
                                     (access-list '())
                                     (max-fee-per-blob-gas 0)
                                     (blob-versioned-hashes '())
                                     (y-parity 0)
                                     (r 0)
                                     (s 0))))
  (chain-id 0 :type (integer 0 *))
  (nonce 0 :type (integer 0 *))
  (max-priority-fee-per-gas 0 :type (integer 0 *))
  (max-fee-per-gas 0 :type (integer 0 *))
  (gas-limit 0 :type (integer 0 *))
  to
  (value 0 :type (integer 0 *))
  data
  (access-list '() :type list)
  (max-fee-per-blob-gas 0 :type (integer 0 *))
  (blob-versioned-hashes '() :type list)
  (y-parity 0 :type (integer 0 *))
  (r 0 :type (integer 0 *))
  (s 0 :type (integer 0 *)))

(defun blob-versioned-hash-bytes (hash)
  (etypecase hash
    (hash32 (hash32-bytes hash))
    (byte-vector (optional-bytes hash 32 "Blob versioned hash"))
    (vector (optional-bytes hash 32 "Blob versioned hash"))))

(defun required-transaction-recipient-from-rlp (value label)
  (let ((recipient (legacy-transaction-recipient-from-rlp value)))
    (unless recipient
      (block-validation-fail "~A must be exactly 20 bytes" label))
    recipient))

(defun blob-versioned-hash-from-rlp (value)
  (let ((bytes (rlp-bytes-field value "Blob versioned hash")))
    (unless (= (length bytes) 32)
      (block-validation-fail "Blob versioned hash must be exactly 32 bytes"))
    (make-hash32 bytes)))

(defun blob-versioned-hashes-from-rlp-object (value)
  (unless (rlp-list-p value)
    (block-validation-fail "Blob versioned hashes must be an RLP list"))
  (mapcar #'blob-versioned-hash-from-rlp
          (rlp-list-items value)))

(defun blob-transaction-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (blob-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (blob-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (blob-transaction-max-priority-fee-per-gas transaction)
                   "Transaction max priority fee")
   (ensure-uint256 (blob-transaction-max-fee-per-gas transaction)
                   "Transaction max fee")
   (ensure-uint256 (blob-transaction-gas-limit transaction) "Transaction gas limit")
   (required-transaction-to-bytes (blob-transaction-to transaction)
                                  "Blob transaction recipient")
   (ensure-uint256 (blob-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (blob-transaction-data transaction))
   (access-list-rlp-object (blob-transaction-access-list transaction))
   (ensure-uint256 (blob-transaction-max-fee-per-blob-gas transaction)
                   "Transaction max blob fee")
   (mapcar #'blob-versioned-hash-bytes
           (blob-transaction-blob-versioned-hashes transaction))
   (ensure-uint256 (blob-transaction-y-parity transaction) "Transaction y parity")
   (ensure-uint256 (blob-transaction-r transaction) "Transaction r")
   (ensure-uint256 (blob-transaction-s transaction) "Transaction s")))

(defun blob-transaction-signing-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (blob-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (blob-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (blob-transaction-max-priority-fee-per-gas transaction)
                   "Transaction max priority fee")
   (ensure-uint256 (blob-transaction-max-fee-per-gas transaction)
                   "Transaction max fee")
   (ensure-uint256 (blob-transaction-gas-limit transaction) "Transaction gas limit")
   (required-transaction-to-bytes (blob-transaction-to transaction)
                                  "Blob transaction recipient")
   (ensure-uint256 (blob-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (blob-transaction-data transaction))
   (access-list-rlp-object (blob-transaction-access-list transaction))
   (ensure-uint256 (blob-transaction-max-fee-per-blob-gas transaction)
                   "Transaction max blob fee")
   (mapcar #'blob-versioned-hash-bytes
           (blob-transaction-blob-versioned-hashes transaction))))

(defun blob-transaction-encoding (transaction)
  (concat-bytes #(3) (rlp-encode (blob-transaction-payload transaction))))

(defun blob-transaction-from-rlp (bytes)
  (handler-case
      (let ((value (rlp-decode-one bytes)))
        (unless (rlp-list-p value)
          (block-validation-fail
           "Blob transaction payload must be an RLP list"))
        (let ((fields (rlp-list-items value)))
          (unless (= (length fields) 14)
            (block-validation-fail
             "Blob transaction payload must contain 14 fields"))
          (make-blob-transaction
           :chain-id (rlp-uint-field (first fields)
                                     "Transaction chain id")
           :nonce (rlp-uint-field (second fields) "Transaction nonce")
           :max-priority-fee-per-gas
           (rlp-uint-field (third fields)
                           "Transaction max priority fee")
           :max-fee-per-gas
           (rlp-uint-field (fourth fields) "Transaction max fee")
           :gas-limit (rlp-uint-field (fifth fields)
                                      "Transaction gas limit")
           :to (required-transaction-recipient-from-rlp
                (sixth fields)
                "Blob transaction recipient")
           :value (rlp-uint-field (seventh fields) "Transaction value")
           :data (rlp-bytes-field (eighth fields) "Transaction data")
           :access-list (access-list-from-rlp-object (ninth fields))
           :max-fee-per-blob-gas
           (rlp-uint-field (nth 9 fields) "Transaction max blob fee")
           :blob-versioned-hashes
           (blob-versioned-hashes-from-rlp-object (nth 10 fields))
           :y-parity (rlp-uint-field (nth 11 fields)
                                     "Transaction y parity")
           :r (rlp-uint-field (nth 12 fields) "Transaction r")
           :s (rlp-uint-field (nth 13 fields) "Transaction s"))))
    (block-validation-error (condition)
      (error condition))
    (rlp-error (condition)
      (block-validation-fail "Invalid blob transaction RLP: ~A"
                             condition))))

(defun blob-transaction-signing-hash (transaction)
  (keccak-256-hash
   (concat-bytes #(3)
                 (rlp-encode
                  (blob-transaction-signing-payload transaction)))))

(defun blob-transaction-hash (transaction)
  (keccak-256-hash (blob-transaction-encoding transaction)))

(defstruct (blob-sidecar (:constructor make-blob-sidecar
                            (&key (blobs '())
                                  (commitments '())
                                  (proofs '()))))
  (blobs '() :type list)
  (commitments '() :type list)
  (proofs '() :type list))

(defun blob-sidecar-versioned-hashes (sidecar)
  (mapcar #'kzg-commitment-to-versioned-hash
          (blob-sidecar-commitments sidecar)))

(defstruct (set-code-authorization (:constructor make-set-code-authorization
                                     (&key (chain-id 0)
                                           address
                                           (nonce 0)
                                           (y-parity 0)
                                           (r 0)
                                           (s 0))))
  (chain-id 0 :type (integer 0 *))
  address
  (nonce 0 :type (integer 0 *))
  (y-parity 0 :type (integer 0 *))
  (r 0 :type (integer 0 *))
  (s 0 :type (integer 0 *)))

(defun set-code-authorization-rlp-object (authorization)
  (make-rlp-list
   (ensure-uint256 (set-code-authorization-chain-id authorization)
                   "Authorization chain id")
   (required-transaction-to-bytes (set-code-authorization-address authorization)
                                  "Authorization address")
   (ensure-uint256 (set-code-authorization-nonce authorization)
                   "Authorization nonce")
   (ensure-uint256 (set-code-authorization-y-parity authorization)
                   "Authorization y parity")
   (ensure-uint256 (set-code-authorization-r authorization)
                   "Authorization r")
   (ensure-uint256 (set-code-authorization-s authorization)
                   "Authorization s")))

(defun set-code-authorization-from-rlp-object (value)
  (unless (rlp-list-p value)
    (block-validation-fail "Set-code authorization must be an RLP list"))
  (let ((fields (rlp-list-items value)))
    (unless (= (length fields) 6)
      (block-validation-fail
       "Set-code authorization must contain 6 fields"))
    (make-set-code-authorization
     :chain-id (rlp-uint-field (first fields) "Authorization chain id")
     :address (required-transaction-recipient-from-rlp
               (second fields)
               "Authorization address")
     :nonce (rlp-uint-field (third fields) "Authorization nonce")
     :y-parity (rlp-uint-field (fourth fields)
                               "Authorization y parity")
     :r (rlp-uint-field (fifth fields) "Authorization r")
     :s (rlp-uint-field (sixth fields) "Authorization s"))))

(defun set-code-authorization-signing-hash (authorization)
  (keccak-256-hash
   (concat-bytes
    #(5)
    (rlp-encode
     (make-rlp-list
      (ensure-uint256 (set-code-authorization-chain-id authorization)
                      "Authorization chain id")
      (required-transaction-to-bytes (set-code-authorization-address authorization)
                                     "Authorization address")
      (ensure-uint256 (set-code-authorization-nonce authorization)
                      "Authorization nonce"))))))

(defun set-code-authorization-authority (authorization)
  "Recover the authority address from an EIP-7702 authorization tuple."
  (let ((y-parity (set-code-authorization-y-parity authorization))
        (r (set-code-authorization-r authorization))
        (s (set-code-authorization-s authorization)))
    (when (secp256k1-valid-signature-values-p y-parity r s :low-s-p t)
      (secp256k1-recover-address
       (hash32-bytes (set-code-authorization-signing-hash authorization))
       y-parity
       r
       s))))

(defparameter +set-code-delegation-prefix+ #(#xef #x01 #x00))

(defun set-code-delegation-code (address)
  (concat-bytes +set-code-delegation-prefix+ (address-bytes address)))

(defun set-code-delegation-target (code)
  (let ((code (ensure-byte-vector code)))
    (when (and (= 23 (length code))
               (loop for i below (length +set-code-delegation-prefix+)
                     always (= (aref code i)
                               (aref +set-code-delegation-prefix+ i))))
      (make-address (subseq code (length +set-code-delegation-prefix+))))))

(defstruct (set-code-transaction (:constructor make-set-code-transaction
                                   (&key (chain-id 0)
                                         (nonce 0)
                                         (max-priority-fee-per-gas 0)
                                         (max-fee-per-gas 0)
                                         (gas-limit 0)
                                         to
                                         (value 0)
                                         (data #())
                                         (access-list '())
                                         (authorization-list '())
                                         (y-parity 0)
                                         (r 0)
                                         (s 0))))
  (chain-id 0 :type (integer 0 *))
  (nonce 0 :type (integer 0 *))
  (max-priority-fee-per-gas 0 :type (integer 0 *))
  (max-fee-per-gas 0 :type (integer 0 *))
  (gas-limit 0 :type (integer 0 *))
  to
  (value 0 :type (integer 0 *))
  data
  (access-list '() :type list)
  (authorization-list '() :type list)
  (y-parity 0 :type (integer 0 *))
  (r 0 :type (integer 0 *))
  (s 0 :type (integer 0 *)))

(defun set-code-authorization-list-rlp-object (authorization-list)
  (mapcar #'set-code-authorization-rlp-object authorization-list))

(defun set-code-authorization-list-from-rlp-object (value)
  (unless (rlp-list-p value)
    (block-validation-fail "Set-code authorization list must be an RLP list"))
  (mapcar #'set-code-authorization-from-rlp-object
          (rlp-list-items value)))

(defun set-code-transaction-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (set-code-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (set-code-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (set-code-transaction-max-priority-fee-per-gas transaction)
                   "Transaction max priority fee")
   (ensure-uint256 (set-code-transaction-max-fee-per-gas transaction)
                   "Transaction max fee")
   (ensure-uint256 (set-code-transaction-gas-limit transaction) "Transaction gas limit")
   (required-transaction-to-bytes (set-code-transaction-to transaction)
                                  "Set-code transaction recipient")
   (ensure-uint256 (set-code-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (set-code-transaction-data transaction))
   (access-list-rlp-object (set-code-transaction-access-list transaction))
   (set-code-authorization-list-rlp-object
    (set-code-transaction-authorization-list transaction))
   (ensure-uint256 (set-code-transaction-y-parity transaction) "Transaction y parity")
   (ensure-uint256 (set-code-transaction-r transaction) "Transaction r")
   (ensure-uint256 (set-code-transaction-s transaction) "Transaction s")))

(defun set-code-transaction-signing-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (set-code-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (set-code-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (set-code-transaction-max-priority-fee-per-gas transaction)
                   "Transaction max priority fee")
   (ensure-uint256 (set-code-transaction-max-fee-per-gas transaction)
                   "Transaction max fee")
   (ensure-uint256 (set-code-transaction-gas-limit transaction) "Transaction gas limit")
   (required-transaction-to-bytes (set-code-transaction-to transaction)
                                  "Set-code transaction recipient")
   (ensure-uint256 (set-code-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (set-code-transaction-data transaction))
   (access-list-rlp-object (set-code-transaction-access-list transaction))
   (set-code-authorization-list-rlp-object
    (set-code-transaction-authorization-list transaction))))

(defun set-code-transaction-encoding (transaction)
  (concat-bytes #(4) (rlp-encode (set-code-transaction-payload transaction))))

(defun set-code-transaction-from-rlp (bytes)
  (handler-case
      (let ((value (rlp-decode-one bytes)))
        (unless (rlp-list-p value)
          (block-validation-fail
           "Set-code transaction payload must be an RLP list"))
        (let ((fields (rlp-list-items value)))
          (unless (= (length fields) 13)
            (block-validation-fail
             "Set-code transaction payload must contain 13 fields"))
          (make-set-code-transaction
           :chain-id (rlp-uint-field (first fields)
                                     "Transaction chain id")
           :nonce (rlp-uint-field (second fields) "Transaction nonce")
           :max-priority-fee-per-gas
           (rlp-uint-field (third fields)
                           "Transaction max priority fee")
           :max-fee-per-gas
           (rlp-uint-field (fourth fields) "Transaction max fee")
           :gas-limit (rlp-uint-field (fifth fields)
                                      "Transaction gas limit")
           :to (required-transaction-recipient-from-rlp
                (sixth fields)
                "Set-code transaction recipient")
           :value (rlp-uint-field (seventh fields) "Transaction value")
           :data (rlp-bytes-field (eighth fields) "Transaction data")
           :access-list (access-list-from-rlp-object (ninth fields))
           :authorization-list
           (set-code-authorization-list-from-rlp-object (nth 9 fields))
           :y-parity (rlp-uint-field (nth 10 fields)
                                     "Transaction y parity")
           :r (rlp-uint-field (nth 11 fields) "Transaction r")
           :s (rlp-uint-field (nth 12 fields) "Transaction s"))))
    (block-validation-error (condition)
      (error condition))
    (rlp-error (condition)
      (block-validation-fail "Invalid set-code transaction RLP: ~A"
                             condition))))

(defun set-code-transaction-signing-hash (transaction)
  (keccak-256-hash
   (concat-bytes
    #(4)
    (rlp-encode (set-code-transaction-signing-payload transaction)))))

(defun set-code-transaction-hash (transaction)
  (keccak-256-hash (set-code-transaction-encoding transaction)))

(defun transaction-nonce (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-nonce transaction))
    (access-list-transaction (access-list-transaction-nonce transaction))
    (dynamic-fee-transaction (dynamic-fee-transaction-nonce transaction))
    (blob-transaction (blob-transaction-nonce transaction))
    (set-code-transaction (set-code-transaction-nonce transaction))))

(defun transaction-gas-limit (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-gas-limit transaction))
    (access-list-transaction (access-list-transaction-gas-limit transaction))
    (dynamic-fee-transaction (dynamic-fee-transaction-gas-limit transaction))
    (blob-transaction (blob-transaction-gas-limit transaction))
    (set-code-transaction (set-code-transaction-gas-limit transaction))))

(defun transaction-to (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-to transaction))
    (access-list-transaction (access-list-transaction-to transaction))
    (dynamic-fee-transaction (dynamic-fee-transaction-to transaction))
    (blob-transaction (blob-transaction-to transaction))
    (set-code-transaction (set-code-transaction-to transaction))))

(defun transaction-value (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-value transaction))
    (access-list-transaction (access-list-transaction-value transaction))
    (dynamic-fee-transaction (dynamic-fee-transaction-value transaction))
    (blob-transaction (blob-transaction-value transaction))
    (set-code-transaction (set-code-transaction-value transaction))))

(defun transaction-data (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-data transaction))
    (access-list-transaction (access-list-transaction-data transaction))
    (dynamic-fee-transaction (dynamic-fee-transaction-data transaction))
    (blob-transaction (blob-transaction-data transaction))
    (set-code-transaction (set-code-transaction-data transaction))))

(defun transaction-access-list (transaction)
  (etypecase transaction
    (legacy-transaction '())
    (access-list-transaction (access-list-transaction-access-list transaction))
    (dynamic-fee-transaction (dynamic-fee-transaction-access-list transaction))
    (blob-transaction (blob-transaction-access-list transaction))
    (set-code-transaction (set-code-transaction-access-list transaction))))

(defun transaction-authorization-list (transaction)
  (etypecase transaction
    ((or legacy-transaction
         access-list-transaction
         dynamic-fee-transaction
         blob-transaction)
     '())
    (set-code-transaction
     (set-code-transaction-authorization-list transaction))))

(defun transaction-type (transaction)
  (etypecase transaction
    (legacy-transaction 0)
    (access-list-transaction 1)
    (dynamic-fee-transaction 2)
    (blob-transaction 3)
    (set-code-transaction 4)))

(defun validate-transaction-type-for-config
    (transaction config block-number timestamp)
  (let* ((rules (chain-config-rules config block-number timestamp))
         (type (transaction-type transaction)))
    (when (chain-rules-transaction-type-supported-p rules transaction)
      (return-from validate-transaction-type-for-config t))
    (cond
      ((= type 1)
       (block-validation-fail "Access-list transaction before Berlin"))
      ((= type 2)
       (block-validation-fail "Dynamic-fee transaction before London"))
      ((= type 3)
       (block-validation-fail "Blob transaction before Cancun"))
      ((= type 4)
       (block-validation-fail "Set-code transaction before Prague"))
      (t
       (block-validation-fail "Unsupported transaction type"))))
  t)

(defun transaction-blob-versioned-hashes (transaction)
  (etypecase transaction
    ((or legacy-transaction
         access-list-transaction
         dynamic-fee-transaction
         set-code-transaction)
     #())
    (blob-transaction
     (coerce (blob-transaction-blob-versioned-hashes transaction) 'vector))))

(defun transaction-blob-gas-used (transaction)
  (* (length (transaction-blob-versioned-hashes transaction))
     +blob-gas-per-blob+))

(defun access-list-storage-key-count (access-list)
  (loop for entry in access-list
        sum (length (access-list-entry-storage-keys entry))))

(defun transaction-max-priority-fee-per-gas (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-gas-price transaction))
    (access-list-transaction (access-list-transaction-gas-price transaction))
    (dynamic-fee-transaction
     (dynamic-fee-transaction-max-priority-fee-per-gas transaction))
    (blob-transaction
     (blob-transaction-max-priority-fee-per-gas transaction))
    (set-code-transaction
     (set-code-transaction-max-priority-fee-per-gas transaction))))

(defun transaction-max-fee-per-gas (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-gas-price transaction))
    (access-list-transaction (access-list-transaction-gas-price transaction))
    (dynamic-fee-transaction
     (dynamic-fee-transaction-max-fee-per-gas transaction))
    (blob-transaction
     (blob-transaction-max-fee-per-gas transaction))
    (set-code-transaction
     (set-code-transaction-max-fee-per-gas transaction))))

(defun validate-1559-transaction-fees (transaction base-fee)
  (let ((max-priority-fee (transaction-max-priority-fee-per-gas transaction))
        (max-fee (transaction-max-fee-per-gas transaction)))
    (unless (uint256-p max-priority-fee)
      (block-validation-fail "Max priority fee must be uint256"))
    (unless (uint256-p max-fee)
      (block-validation-fail "Max fee per gas must be uint256"))
    (when (< max-fee max-priority-fee)
      (block-validation-fail "Max priority fee exceeds max fee"))
    (when (< max-fee base-fee)
      (block-validation-fail "Max fee per gas below base fee"))
    t))

(defun transaction-effective-gas-price
    (transaction &key (base-fee 0) (eip1559-enabled-p t))
  (if (not eip1559-enabled-p)
      (transaction-max-priority-fee-per-gas transaction)
      (progn
        (validate-1559-transaction-fees transaction base-fee)
        (if (or (typep transaction 'legacy-transaction)
                (typep transaction 'access-list-transaction))
            (transaction-max-fee-per-gas transaction)
            (+ base-fee
               (min (transaction-max-priority-fee-per-gas transaction)
                    (- (transaction-max-fee-per-gas transaction)
                       base-fee)))))))

(defun transaction-priority-fee-per-gas
    (transaction &key (base-fee 0) (eip1559-enabled-p t))
  (if (not eip1559-enabled-p)
      (transaction-max-priority-fee-per-gas transaction)
      (max 0 (- (transaction-effective-gas-price transaction
                                                 :base-fee base-fee)
                base-fee))))

(defun transaction-encoding (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-rlp transaction))
    (access-list-transaction (access-list-transaction-encoding transaction))
    (dynamic-fee-transaction (dynamic-fee-transaction-encoding transaction))
    (blob-transaction (blob-transaction-encoding transaction))
    (set-code-transaction (set-code-transaction-encoding transaction))))

(defun transaction-from-encoding (bytes)
  (let ((bytes (ensure-byte-vector bytes)))
    (when (zerop (length bytes))
      (block-validation-fail "Transaction encoding is empty"))
    (if (> (aref bytes 0) #x7f)
        (legacy-transaction-from-rlp bytes)
        (case (aref bytes 0)
          (1 (access-list-transaction-from-rlp (subseq bytes 1)))
          (2 (dynamic-fee-transaction-from-rlp (subseq bytes 1)))
          (3 (blob-transaction-from-rlp (subseq bytes 1)))
          (4 (set-code-transaction-from-rlp (subseq bytes 1)))
          (otherwise
           (block-validation-fail
            "Typed transaction decoding is not implemented yet"))))))

(defun transaction-hash (transaction)
  (keccak-256-hash (transaction-encoding transaction)))

(defun typed-transaction-sender
    (chain-id y-parity r s signing-hash &key expected-chain-id)
  (when (and (or (not expected-chain-id)
                 (= expected-chain-id chain-id))
             (secp256k1-valid-signature-values-p y-parity r s :low-s-p t))
    (secp256k1-recover-address (hash32-bytes signing-hash) y-parity r s)))

(defun access-list-transaction-sender (transaction &key expected-chain-id)
  "Recover the sender address from an EIP-2930 transaction signature."
  (typed-transaction-sender
   (access-list-transaction-chain-id transaction)
   (access-list-transaction-y-parity transaction)
   (access-list-transaction-r transaction)
   (access-list-transaction-s transaction)
   (access-list-transaction-signing-hash transaction)
   :expected-chain-id expected-chain-id))

(defun dynamic-fee-transaction-sender (transaction &key expected-chain-id)
  "Recover the sender address from an EIP-1559 transaction signature."
  (typed-transaction-sender
   (dynamic-fee-transaction-chain-id transaction)
   (dynamic-fee-transaction-y-parity transaction)
   (dynamic-fee-transaction-r transaction)
   (dynamic-fee-transaction-s transaction)
   (dynamic-fee-transaction-signing-hash transaction)
   :expected-chain-id expected-chain-id))

(defun blob-transaction-sender (transaction &key expected-chain-id)
  "Recover the sender address from an EIP-4844 transaction signature."
  (typed-transaction-sender
   (blob-transaction-chain-id transaction)
   (blob-transaction-y-parity transaction)
   (blob-transaction-r transaction)
   (blob-transaction-s transaction)
   (blob-transaction-signing-hash transaction)
   :expected-chain-id expected-chain-id))

(defun set-code-transaction-sender (transaction &key expected-chain-id)
  "Recover the sender address from an EIP-7702 set-code transaction signature."
  (typed-transaction-sender
   (set-code-transaction-chain-id transaction)
   (set-code-transaction-y-parity transaction)
   (set-code-transaction-r transaction)
   (set-code-transaction-s transaction)
   (set-code-transaction-signing-hash transaction)
   :expected-chain-id expected-chain-id))

(defun transaction-sender (transaction &key expected-chain-id)
  (etypecase transaction
    (legacy-transaction
     (legacy-transaction-sender transaction
                                :expected-chain-id expected-chain-id))
    (access-list-transaction
     (access-list-transaction-sender transaction
                                     :expected-chain-id expected-chain-id))
    (dynamic-fee-transaction
     (dynamic-fee-transaction-sender transaction
                                     :expected-chain-id expected-chain-id))
    (blob-transaction
     (blob-transaction-sender transaction
                              :expected-chain-id expected-chain-id))
    (set-code-transaction
     (set-code-transaction-sender transaction
                                  :expected-chain-id expected-chain-id))))

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

(defun block-header-rlp (header)
  (rlp-encode (apply #'make-rlp-list (header-fields header))))

(defun block-header-hash (header)
  (keccak-256-hash (block-header-rlp header)))

(defun ommers-hash (ommers)
  (keccak-256-hash
   (rlp-encode
    (mapcar (lambda (header)
              (apply #'make-rlp-list (header-fields header)))
            ommers))))

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
    (when withdrawals
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
             :withdrawals-root (when withdrawals
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
                   :withdrawals-present-p (not (null withdrawals))
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
         (shanghai-p (chain-config-shanghai-p config number timestamp))
         (cancun-p (chain-config-cancun-p config number timestamp))
         (prague-p (chain-config-prague-p config number timestamp))
         (amsterdam-p (chain-config-amsterdam-p config number timestamp)))
    (cond
      ((= version 1)
       (when withdrawals
         "withdrawals not supported in newPayloadV1"))
      ((= version 2)
       (cond
         (cancun-p "newPayloadV2 cannot be used after Cancun")
         ((and shanghai-p (null withdrawals))
          "withdrawals required after Shanghai")
         ((and (not shanghai-p) withdrawals)
          "withdrawals not supported before Shanghai")
         ((executable-data-excess-blob-gas payload)
          "excessBlobGas not supported before Cancun")
         ((executable-data-blob-gas-used payload)
          "blobGasUsed not supported before Cancun")))
      ((= version 3)
       (cond
         ((null withdrawals) "withdrawals required after Shanghai")
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
         ((null withdrawals) "withdrawals required after Shanghai")
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
         ((null withdrawals) "withdrawals required after Shanghai")
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
                      (pending-transactions (make-hash-table :test 'equal))
                      (pending-transactions-by-sender
                       (make-hash-table :test 'equal))
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
  pending-transactions
  pending-transactions-by-sender
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
                (&key blob proof cell-proofs)))
  blob
  proof
  cell-proofs)

(defstruct (engine-log-filter
            (:constructor make-engine-log-filter
                (&key criteria last-block-number block-hash-consumed-p)))
  criteria
  last-block-number
  (block-hash-consumed-p nil :type boolean))

(defstruct (engine-block-filter
            (:constructor make-engine-block-filter (&key last-block-number)))
  (last-block-number 0 :type (integer 0 *)))

(defstruct (engine-pending-transaction-filter
            (:constructor make-engine-pending-transaction-filter
                (&key hashes)))
  hashes)

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

(defun engine-payload-store-put-block
    (store block &key (state-available-p nil))
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep block 'ethereum-block)
    (block-validation-fail "Engine payload store block must be a block"))
  (let ((key (engine-payload-store-key (block-hash block)))
        (canonicalized-p nil))
    (setf (gethash key (engine-payload-memory-store-blocks store)) block)
    (let ((number (block-header-number (block-header block))))
      (when (and (integerp number) (not (minusp number)))
        (setf (gethash number
                       (engine-payload-memory-store-number-blocks store))
              block)
        (when (and (not (gethash
                         number
                         (engine-payload-memory-store-canonical-hashes store)))
                   (engine-payload-store-canonical-parent-p store block))
          (setf (gethash number
                         (engine-payload-memory-store-canonical-hashes store))
                key
                canonicalized-p t))
        (when (and canonicalized-p
                   (> number (engine-payload-memory-store-head-number store)))
          (setf (engine-payload-memory-store-head-number store) number))))
    (loop with receipts = (block-receipts block)
          with log-index-start = 0
          for transaction in (block-transactions block)
          for index from 0
          for receipt = (nth index receipts)
          for transaction-key =
            (engine-payload-store-key (transaction-hash transaction))
          do (progn
               (setf (gethash transaction-key
                              (engine-payload-memory-store-transaction-locations
                               store))
                     (make-engine-transaction-location
                      :block block
                      :index index
                      :transaction transaction
                      :receipt receipt
                      :log-index-start log-index-start))
               (engine-payload-store-remove-pending-transaction
                store
                (transaction-hash transaction))
               (when receipt
                 (incf log-index-start
                       (length (receipt-logs receipt))))))
    (if state-available-p
        (setf (gethash key
                       (engine-payload-memory-store-state-blocks store))
              t)
        (remhash key (engine-payload-memory-store-state-blocks store)))
    block))

(defun engine-payload-store-known-block
    (store hash)
  (gethash (engine-payload-store-key hash)
           (engine-payload-memory-store-blocks store)))

(defun engine-payload-store-checkpoint-number (store checkpoint)
  (let* ((hash (and checkpoint
                    (chain-store-checkpoint-block-hash checkpoint)))
         (block (and hash (engine-payload-store-known-block store hash))))
    (if block
        (block-header-number (block-header block))
        (engine-payload-memory-store-head-number store))))

(defun engine-payload-store-head-number (store)
  (engine-payload-store-checkpoint-number
   store
   (engine-payload-memory-store-head-checkpoint store)))

(defun engine-payload-store-block-tag-number (store tag)
  (cond
    ((or (string= tag "latest") (string= tag "pending"))
     (engine-payload-store-head-number store))
    ((string= tag "safe")
     (engine-payload-store-checkpoint-number
      store
      (engine-payload-memory-store-safe-checkpoint store)))
    ((string= tag "finalized")
     (engine-payload-store-checkpoint-number
      store
      (engine-payload-memory-store-finalized-checkpoint store)))))

(defun engine-payload-store-forkchoice-checkpoint-hash (hash)
  (unless (hash32= hash (zero-hash32))
    hash))

(defun engine-payload-store-update-forkchoice-checkpoints (store state)
  (let ((head-hash (forkchoice-state-head-block-hash state))
        (safe-hash
          (engine-payload-store-forkchoice-checkpoint-hash
           (forkchoice-state-safe-block-hash state)))
        (finalized-hash
          (engine-payload-store-forkchoice-checkpoint-hash
           (forkchoice-state-finalized-block-hash state))))
    (when (and safe-hash
               (not (engine-payload-store-ancestor-p
                     store safe-hash head-hash)))
      (block-validation-fail
       "forkchoice safe block is not an ancestor of head"))
    (when (and finalized-hash
               (not (engine-payload-store-ancestor-p
                     store finalized-hash head-hash)))
      (block-validation-fail
       "forkchoice finalized block is not an ancestor of head")))
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

(defun engine-payload-store-set-canonical-head (store hash)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (let ((head-block (engine-payload-store-known-block store hash)))
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
      (dolist (block path)
        (let* ((header (block-header block))
               (number (block-header-number header))
               (key (engine-payload-store-key (block-hash block))))
          (setf (gethash number
                         (engine-payload-memory-store-canonical-hashes store))
                key
                (gethash number
                         (engine-payload-memory-store-number-blocks store))
                block)))
      (let ((new-head-number
              (block-header-number (block-header head-block)))
            (stale-numbers '()))
        (maphash (lambda (number key)
                   (declare (ignore key))
                   (when (> number new-head-number)
                     (push number stale-numbers)))
                 (engine-payload-memory-store-canonical-hashes store))
        (dolist (number stale-numbers)
          (remhash number
                   (engine-payload-memory-store-canonical-hashes store)))
        (setf (engine-payload-memory-store-head-number store) new-head-number
              (engine-payload-memory-store-head-checkpoint store)
              (make-chain-store-checkpoint :label :head :block-hash hash)))
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
      location)))

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
      :block-hash-consumed-p
      (engine-log-filter-block-hash-consumed-p filter)))
    ((typep filter 'engine-block-filter)
     (make-engine-block-filter
      :last-block-number (engine-block-filter-last-block-number filter)))
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
      :block (engine-prepared-payload-block prepared-payload)
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

(defun engine-payload-store-copy-block (block)
  (cond
    ((typep block 'ethereum-block)
     (let ((copy (copy-ethereum-block block)))
       (setf (block-header copy)
             (engine-payload-store-copy-block-header (block-header block))
             (block-transactions copy) (copy-list (block-transactions block))
             (block-receipts copy) (copy-list (block-receipts block))
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

(defun engine-payload-store-copy-checkpoint (checkpoint)
  (when checkpoint
    (make-chain-store-checkpoint
     :label (chain-store-checkpoint-label checkpoint)
     :block-hash (chain-store-checkpoint-block-hash checkpoint))))

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
   (engine-payload-store-copy-table
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
   :pending-transactions
   (engine-payload-store-copy-table
    (engine-payload-memory-store-pending-transactions store))
   :pending-transactions-by-sender
   (engine-payload-store-copy-pending-sender-index
    (engine-payload-memory-store-pending-transactions-by-sender store))
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
        (engine-payload-memory-store-pending-transactions store)
        (engine-payload-memory-store-pending-transactions snapshot)
        (engine-payload-memory-store-pending-transactions-by-sender store)
        (engine-payload-memory-store-pending-transactions-by-sender snapshot)
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

(defun chain-store-set-canonical-head (store hash)
  (engine-payload-store-set-canonical-head
   (chain-store-require-memory-store store)
   hash))

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
      (copy-list (block-receipts block)))))

(defun chain-store-state-available-p (store hash)
  (engine-payload-store-state-available-p
   (chain-store-require-memory-store store)
   hash))

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

(defun engine-payload-store-pending-sender-key (transaction)
  (address-to-hex (or (transaction-sender transaction)
                      (zero-address))))

(defun engine-payload-store-pending-nonce-key (transaction)
  (write-to-string (transaction-nonce transaction) :base 10))

(defun engine-payload-store-copy-pending-sender-index (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (sender nonce-table)
               (setf (gethash sender copy)
                     (engine-payload-store-copy-table nonce-table)))
             table)
    copy))

(defun engine-payload-store-index-pending-transaction (store transaction)
  (let* ((sender (engine-payload-store-pending-sender-key transaction))
         (nonce (engine-payload-store-pending-nonce-key transaction))
         (sender-transactions
           (or (gethash
                sender
                (engine-payload-memory-store-pending-transactions-by-sender
                 store))
               (setf
                (gethash
                 sender
                 (engine-payload-memory-store-pending-transactions-by-sender
                  store))
                (make-hash-table :test 'equal)))))
    (setf (gethash nonce sender-transactions) transaction)))

(defun engine-payload-store-unindex-pending-transaction (store transaction)
  (when transaction
    (let* ((sender (engine-payload-store-pending-sender-key transaction))
           (nonce (engine-payload-store-pending-nonce-key transaction))
           (sender-index
             (engine-payload-memory-store-pending-transactions-by-sender
              store))
           (sender-transactions (gethash sender sender-index))
           (indexed-transaction
             (and sender-transactions
                  (gethash nonce sender-transactions))))
      (when (and indexed-transaction
                 (hash32= (transaction-hash indexed-transaction)
                          (transaction-hash transaction)))
        (remhash nonce sender-transactions)
        (when (zerop (hash-table-count sender-transactions))
          (remhash sender sender-index))))))

(defun engine-payload-store-remove-pending-transaction (store hash)
  (let* ((key (engine-payload-store-key hash))
         (transaction
           (gethash key
                    (engine-payload-memory-store-pending-transactions store))))
    (when transaction
      (engine-payload-store-unindex-pending-transaction store transaction)
      (remhash key (engine-payload-memory-store-pending-transactions store)))
    transaction))

(defun engine-payload-store-put-pending-transaction (store transaction)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep transaction
                 '(or legacy-transaction
                      access-list-transaction
                      dynamic-fee-transaction
                      blob-transaction
                      set-code-transaction))
    (block-validation-fail "Pending transaction must be a transaction"))
  (let ((key (engine-payload-store-key (transaction-hash transaction))))
    (unless (gethash key
                     (engine-payload-memory-store-pending-transactions store))
      (setf (gethash key
                     (engine-payload-memory-store-pending-transactions store))
            transaction)
      (engine-payload-store-index-pending-transaction store transaction)
      (loop for filter
              being the hash-values of
                (engine-payload-memory-store-log-filters store)
            when (typep filter 'engine-pending-transaction-filter)
              do (setf (engine-pending-transaction-filter-hashes filter)
                       (append
                        (engine-pending-transaction-filter-hashes filter)
                        (list (transaction-hash transaction)))))))
  transaction)

(defun engine-payload-store-pending-transaction (store hash)
  (gethash (engine-payload-store-key hash)
           (engine-payload-memory-store-pending-transactions store)))

(defun engine-payload-store-pending-transactions (store)
  (sort
   (loop for transaction
           being the hash-values of
             (engine-payload-memory-store-pending-transactions store)
         collect transaction)
   #'string<
   :key (lambda (transaction)
          (hash32-to-hex (transaction-hash transaction)))))

(defun engine-payload-store-pending-transactions-by-sender (store)
  (engine-payload-memory-store-pending-transactions-by-sender store))

(defun engine-payload-store-pending-transaction-count (store)
  (hash-table-count
   (engine-payload-memory-store-pending-transactions store)))

(defun engine-payload-store-put-log-filter (store filter)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (let ((id (engine-payload-memory-store-next-log-filter-id store)))
    (setf (gethash id (engine-payload-memory-store-log-filters store))
          (make-engine-log-filter :criteria filter))
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

(defun engine-payload-store-account-storage-entries
    (memory-store block-hash address)
  (let ((account-prefix
          (format nil "~A:"
                  (engine-payload-store-account-key block-hash address)))
        (entries '()))
    (maphash
     (lambda (key value)
       (when (engine-payload-store-string-prefix-p account-prefix key)
         (push (cons (hash32-from-hex
                      (subseq key (length account-prefix)))
                     value)
               entries)))
     (engine-payload-memory-store-account-storage memory-store))
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
        (maphash
         (lambda (address-hex value)
           (declare (ignore value))
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
         accounts)
        store))))

(defun engine-payload-store-state-available-p
    (store hash)
  (not (null
        (gethash (engine-payload-store-key hash)
                 (engine-payload-memory-store-state-blocks store)))))

(defun engine-payload-store-remote-block
    (store hash)
  (gethash (engine-payload-store-key hash)
           (engine-payload-memory-store-remote-blocks store)))

(defun engine-payload-store-put-remote-block
    (store block)
  (setf (gethash (engine-payload-store-key (block-hash block))
                 (engine-payload-memory-store-remote-blocks store))
        block)
  block)

(defun engine-payload-store-mark-invalid
    (store invalid-block &key head-hash)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep invalid-block 'ethereum-block)
    (block-validation-fail "Engine payload invalid marker must be a block"))
  (let* ((invalid-hash (block-hash invalid-block))
         (key (engine-payload-store-key (or head-hash invalid-hash))))
    (setf (gethash key (engine-payload-memory-store-invalid-tipsets store))
          invalid-block)
    invalid-block))

(defun engine-payload-store-invalid-block
    (store hash)
  (gethash (engine-payload-store-key hash)
           (engine-payload-memory-store-invalid-tipsets store)))

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
  (unless (typep prepared-payload 'engine-prepared-payload)
    (block-validation-fail
     "Engine prepared payload must be an engine-prepared-payload"))
  (setf (gethash
         (engine-payload-id-key
          (engine-prepared-payload-payload-id prepared-payload))
         (engine-payload-memory-store-prepared-payloads store))
        prepared-payload)
  prepared-payload)

(defun engine-payload-store-prepared-payload (store payload-id)
  (gethash (engine-payload-id-key payload-id)
           (engine-payload-memory-store-prepared-payloads store)))

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
                    :proof (maybe-copy-bytes proof)
                    :cell-proofs (mapcar #'maybe-copy-bytes
                                         cell-proofs)))))
  sidecar)

(defun engine-payload-store-blob-and-proofs-v1
    (store versioned-hash)
  (gethash (engine-payload-store-key versioned-hash)
           (engine-payload-memory-store-blob-sidecars store)))

(defun engine-payload-store-blob-and-proofs-v2
    (store versioned-hash)
  (let ((blob-and-proofs
          (engine-payload-store-blob-and-proofs-v1 store versioned-hash)))
    (when (and blob-and-proofs
               (= +cell-proofs-per-blob+
                  (length
                   (engine-blob-and-proofs-cell-proofs blob-and-proofs))))
      blob-and-proofs)))

(defun engine-rpc-required-field (object name)
  (unless (genesis-object-field-present-p object name)
    (block-validation-fail "Engine RPC field ~A is missing" name))
  (genesis-object-field object name))

(defun engine-rpc-optional-quantity-field (object name)
  (when (genesis-object-field-present-p object name)
    (parse-genesis-field object name :label name)))

(defun engine-rpc-required-quantity-field (object name)
  (parse-genesis-field object name :label name :required-p t))

(defun engine-rpc-hash32 (value label)
  (unless (stringp value)
    (block-validation-fail "~A must be a hex hash" label))
  (handler-case
      (hash32-from-hex value)
    (error ()
      (block-validation-fail "~A must be a hash32" label))))

(defun engine-rpc-address (value label)
  (unless (stringp value)
    (block-validation-fail "~A must be a hex address" label))
  (handler-case
      (address-from-hex value)
    (error ()
      (block-validation-fail "~A must be an address" label))))

(defun engine-rpc-bytes (value label)
  (unless (stringp value)
    (block-validation-fail "~A must be a hex byte string" label))
  (handler-case
      (hex-to-bytes value)
    (error ()
      (block-validation-fail "~A must be a hex byte string" label))))

(defun engine-rpc-required-hash32-field (object name)
  (engine-rpc-hash32 (engine-rpc-required-field object name) name))

(defun engine-rpc-optional-hash32-value (value label)
  (when value
    (engine-rpc-hash32 value label)))

(defun engine-rpc-required-address-field (object name)
  (engine-rpc-address (engine-rpc-required-field object name) name))

(defun engine-rpc-required-bytes-field (object name)
  (engine-rpc-bytes (engine-rpc-required-field object name) name))

(defun engine-rpc-optional-bytes-field (object name)
  (when (genesis-object-field-present-p object name)
    (engine-rpc-bytes (genesis-object-field object name) name)))

(defun engine-rpc-byte-list (values label)
  (unless (listp values)
    (block-validation-fail "~A must be a list" label))
  (loop for value in values
        for index from 0
        collect (engine-rpc-bytes value (format nil "~A ~D" label index))))

(defun engine-rpc-hash32-list (values label)
  (unless (listp values)
    (block-validation-fail "~A must be a list" label))
  (loop for value in values
        for index from 0
        collect (engine-rpc-hash32 value (format nil "~A ~D" label index))))

(defun engine-rpc-withdrawal-from-object (object)
  (make-withdrawal
   :index (engine-rpc-required-quantity-field object "index")
   :validator-index
   (engine-rpc-required-quantity-field object "validatorIndex")
   :address (engine-rpc-required-address-field object "address")
   :amount (engine-rpc-required-quantity-field object "amount")))

(defun engine-rpc-withdrawals-field (object)
  (when (genesis-object-field-present-p object "withdrawals")
    (let ((withdrawals (genesis-object-field object "withdrawals")))
      (unless (listp withdrawals)
        (block-validation-fail "withdrawals must be a list"))
      (loop for withdrawal in withdrawals
            collect (engine-rpc-withdrawal-from-object withdrawal)))))

(defun engine-rpc-withdrawal-object (withdrawal)
  (list (cons "index" (quantity-to-hex (withdrawal-index withdrawal)))
        (cons "validatorIndex"
              (quantity-to-hex (withdrawal-validator-index withdrawal)))
        (cons "address" (address-to-hex (withdrawal-address withdrawal)))
        (cons "amount" (quantity-to-hex (withdrawal-amount withdrawal)))))

(defun engine-rpc-executable-data-from-object (object)
  (unless (listp object)
    (block-validation-fail "Engine RPC payload must be an object"))
  (make-executable-data
   :parent-hash (engine-rpc-required-hash32-field object "parentHash")
   :fee-recipient (engine-rpc-required-address-field object "feeRecipient")
   :state-root (engine-rpc-required-hash32-field object "stateRoot")
   :receipts-root (engine-rpc-required-hash32-field object "receiptsRoot")
   :logs-bloom (engine-rpc-required-bytes-field object "logsBloom")
   :random (engine-rpc-required-hash32-field object "prevRandao")
   :number (engine-rpc-required-quantity-field object "blockNumber")
   :gas-limit (engine-rpc-required-quantity-field object "gasLimit")
   :gas-used (engine-rpc-required-quantity-field object "gasUsed")
   :timestamp (engine-rpc-required-quantity-field object "timestamp")
   :extra-data (engine-rpc-required-bytes-field object "extraData")
   :base-fee-per-gas
   (engine-rpc-required-quantity-field object "baseFeePerGas")
   :block-hash (engine-rpc-required-hash32-field object "blockHash")
   :transactions
   (engine-rpc-byte-list
    (engine-rpc-required-field object "transactions")
    "transactions")
   :withdrawals (engine-rpc-withdrawals-field object)
   :blob-gas-used (engine-rpc-optional-quantity-field object "blobGasUsed")
   :excess-blob-gas
   (engine-rpc-optional-quantity-field object "excessBlobGas")
   :slot-number (engine-rpc-optional-quantity-field object "slotNumber")
   :block-access-list
   (engine-rpc-optional-bytes-field object "blockAccessList")))

(defun engine-rpc-executable-data-object (payload)
  (unless (typep payload 'executable-data)
    (block-validation-fail "Engine RPC payload must be executable-data"))
  (append
   (list
    (cons "parentHash"
          (hash32-to-hex (executable-data-parent-hash payload)))
    (cons "feeRecipient"
          (address-to-hex (executable-data-fee-recipient payload)))
    (cons "stateRoot"
          (hash32-to-hex (executable-data-state-root payload)))
    (cons "receiptsRoot"
          (hash32-to-hex (executable-data-receipts-root payload)))
    (cons "logsBloom"
          (bytes-to-hex (executable-data-logs-bloom payload)))
    (cons "prevRandao"
          (hash32-to-hex (executable-data-random payload)))
    (cons "blockNumber"
          (quantity-to-hex (executable-data-number payload)))
    (cons "gasLimit"
          (quantity-to-hex (executable-data-gas-limit payload)))
    (cons "gasUsed"
          (quantity-to-hex (executable-data-gas-used payload)))
    (cons "timestamp"
          (quantity-to-hex (executable-data-timestamp payload)))
    (cons "extraData"
          (bytes-to-hex (executable-data-extra-data payload)))
    (cons "baseFeePerGas"
          (quantity-to-hex (executable-data-base-fee-per-gas payload)))
    (cons "blockHash"
          (hash32-to-hex (executable-data-block-hash payload)))
    (cons "transactions"
          (mapcar #'bytes-to-hex (executable-data-transactions payload))))
   (when (executable-data-withdrawals payload)
     (list (cons "withdrawals"
                 (mapcar #'engine-rpc-withdrawal-object
                         (executable-data-withdrawals payload)))))
   (when (executable-data-blob-gas-used payload)
     (list
      (cons "blobGasUsed"
            (quantity-to-hex (executable-data-blob-gas-used payload)))
      (cons "excessBlobGas"
            (quantity-to-hex (executable-data-excess-blob-gas payload)))))
   (when (executable-data-slot-number payload)
     (list
      (cons "slotNumber"
            (quantity-to-hex (executable-data-slot-number payload)))))
   (when (executable-data-block-access-list payload)
     (list
      (cons "blockAccessList"
            (bytes-to-hex
             (executable-data-block-access-list payload)))))))

(defun engine-rpc-blobs-bundle-object (bundle)
  (let ((sidecar (or bundle (make-blob-sidecar))))
    (unless (typep sidecar 'blob-sidecar)
      (block-validation-fail
       "Engine RPC blobs bundle must be a blob sidecar"))
    (list
     (cons "commitments"
           (mapcar #'bytes-to-hex
                   (blob-sidecar-commitments sidecar)))
     (cons "proofs"
           (mapcar #'bytes-to-hex
                   (blob-sidecar-proofs sidecar)))
     (cons "blobs"
           (mapcar #'bytes-to-hex
                   (blob-sidecar-blobs sidecar))))))

(defun engine-rpc-blob-and-proof-v1-object (blob-and-proofs)
  (unless (typep blob-and-proofs 'engine-blob-and-proofs)
    (block-validation-fail
     "Engine RPC blob response must be an engine-blob-and-proofs"))
  (list
   (cons "blob"
         (bytes-to-hex
          (engine-blob-and-proofs-blob blob-and-proofs)))
   (cons "proof"
         (bytes-to-hex
          (engine-blob-and-proofs-proof blob-and-proofs)))))

(defun engine-rpc-blob-and-proof-v2-object (blob-and-proofs)
  (unless (typep blob-and-proofs 'engine-blob-and-proofs)
    (block-validation-fail
     "Engine RPC blob response must be an engine-blob-and-proofs"))
  (let ((cell-proofs
          (engine-blob-and-proofs-cell-proofs blob-and-proofs)))
    (unless (= +cell-proofs-per-blob+ (length cell-proofs))
      (block-validation-fail
       "Engine RPC V2 blob response must have 128 cell proofs"))
    (list
     (cons "blob"
           (bytes-to-hex
            (engine-blob-and-proofs-blob blob-and-proofs)))
     (cons "proofs"
           (mapcar #'bytes-to-hex cell-proofs)))))

(defun engine-rpc-execution-payload-envelope-object
    (envelope &key include-blobs-bundle-p include-override-p)
  (unless (typep envelope 'execution-payload-envelope)
    (block-validation-fail
     "Engine RPC payload envelope must be execution-payload-envelope"))
  (append
   (list
    (cons "executionPayload"
          (engine-rpc-executable-data-object
           (execution-payload-envelope-execution-payload envelope)))
    (cons "blockValue"
          (quantity-to-hex (execution-payload-envelope-block-value envelope))))
   (when (execution-payload-envelope-requests envelope)
     (list
      (cons "executionRequests"
            (mapcar #'bytes-to-hex
                    (execution-payload-envelope-requests envelope)))))
   (when include-blobs-bundle-p
     (list
      (cons "blobsBundle"
            (engine-rpc-blobs-bundle-object
             (execution-payload-envelope-blobs-bundle envelope)))))
   (when (or include-override-p
             (execution-payload-envelope-override-p envelope))
     (list
      (cons "shouldOverrideBuilder"
            (if (execution-payload-envelope-override-p envelope)
                t
                :false))))))

(defun engine-rpc-payload-body-v1-object (block)
  (unless (typep block 'ethereum-block)
    (block-validation-fail "Engine RPC payload body block must be a block"))
  (append
   (list
    (cons "transactions"
          (mapcar (lambda (transaction)
                    (bytes-to-hex (transaction-encoding transaction)))
                  (block-transactions block))))
   (when (block-withdrawals-present-p block)
     (list
      (cons "withdrawals"
            (mapcar #'engine-rpc-withdrawal-object
                    (block-withdrawals block)))))))

(defun engine-rpc-payload-body-v2-object (block)
  (append
   (engine-rpc-payload-body-v1-object block)
   (when (block-block-access-list-present-p block)
     (list (cons "blockAccessList"
                 (bytes-to-hex (block-encoded-block-access-list block)))))))

(defun engine-rpc-payload-status-object (status)
  (list (cons "status" (payload-status-status status))
        (cons "latestValidHash"
              (when (payload-status-latest-valid-hash status)
                (hash32-to-hex (payload-status-latest-valid-hash status))))
        (cons "validationError" (payload-status-validation-error status))
        (cons "witness" (payload-status-witness status))))

(defun engine-rpc-forkchoice-state-from-object (object)
  (unless (json-object-p object)
    (block-validation-fail
     "engine_forkchoiceUpdated params must contain forkchoice state object"))
  (make-forkchoice-state
   :head-block-hash
   (engine-rpc-required-hash32-field object "headBlockHash")
   :safe-block-hash
   (engine-rpc-required-hash32-field object "safeBlockHash")
   :finalized-block-hash
   (engine-rpc-required-hash32-field object "finalizedBlockHash")))

(defun engine-rpc-validate-payload-attributes-v1
    (object &key (method "engine_forkchoiceUpdatedV1")
                 withdrawals-field-required-p)
  (unless (json-object-p object)
    (block-validation-fail
     "~A payloadAttributes must be an object or null" method))
  (when (and withdrawals-field-required-p
             (not (genesis-object-field-present-p object "withdrawals")))
    (block-validation-fail "~A payloadAttributes withdrawals is missing" method))
  (make-payload-attributes-v1
   :timestamp (engine-rpc-required-quantity-field object "timestamp")
   :prev-randao (engine-rpc-required-hash32-field object "prevRandao")
   :suggested-fee-recipient
   (engine-rpc-required-address-field object "suggestedFeeRecipient")
   :withdrawals (engine-rpc-withdrawals-field object)
   :withdrawals-present-p
   (genesis-object-field-present-p object "withdrawals")))

(defun engine-rpc-validate-payload-attributes-v2 (object)
  (engine-rpc-validate-payload-attributes-v1
   object :method "engine_forkchoiceUpdatedV2"))

(defun engine-rpc-validate-payload-attributes-v3 (object)
  (let ((attributes
          (engine-rpc-validate-payload-attributes-v1
           object
           :method "engine_forkchoiceUpdatedV3"
           :withdrawals-field-required-p t)))
    (unless (genesis-object-field-present-p object "parentBeaconBlockRoot")
      (block-validation-fail
       "engine_forkchoiceUpdatedV3 payloadAttributes parentBeaconBlockRoot is missing"))
    (setf (payload-attributes-v1-parent-beacon-root attributes)
          (engine-rpc-required-hash32-field object "parentBeaconBlockRoot")
          (payload-attributes-v1-parent-beacon-root-present-p attributes)
          t)
    attributes))

(defun engine-rpc-validate-payload-attributes-v4 (object)
  (let ((attributes (engine-rpc-validate-payload-attributes-v3 object)))
    (unless (genesis-object-field-present-p object "slotNumber")
      (block-validation-fail
       "engine_forkchoiceUpdatedV4 payloadAttributes slotNumber is missing"))
    (setf (payload-attributes-v1-slot-number attributes)
          (engine-rpc-required-quantity-field object "slotNumber")
          (payload-attributes-v1-slot-number-present-p attributes)
          t)
    attributes))

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

(defun engine-forkchoice-checkpoint-error-message
    (store hash label &key head-hash)
  (when (not (hash32= hash (zero-hash32)))
    (cond
      ((not (chain-store-known-block store hash))
       (format nil "forkchoice ~A block is not available" label))
      ((and head-hash
            (not (engine-payload-store-ancestor-p store hash head-hash)))
       (format nil "forkchoice ~A block is not an ancestor of head"
               label)))))

(defun engine-forkchoice-memory-status (store state)
  (unless (typep store 'engine-payload-memory-store)
    (return-from engine-forkchoice-memory-status
      (invalid-payload-status
       "forkchoiceUpdated store must be engine-payload-memory-store")))
  (unless (typep state 'forkchoice-state)
    (return-from engine-forkchoice-memory-status
      (invalid-payload-status "forkchoice state must be forkchoice-state")))
  (let ((head-hash (forkchoice-state-head-block-hash state)))
    (cond
      ((hash32= head-hash (zero-hash32))
       (forkchoice-state-zero-head-status))
      ((engine-payload-store-invalid-ancestor-status
        store head-hash head-hash))
      ((chain-store-known-block store head-hash)
       (make-payload-status
        :status +payload-status-valid+
        :latest-valid-hash head-hash))
      (t
       (make-payload-status :status +payload-status-syncing+)))))

(defun engine-rpc-forkchoice-response-object (status &key payload-id)
  (list (cons "payloadStatus" (engine-rpc-payload-status-object status))
        (cons "payloadId" (when payload-id
                            (engine-payload-id-to-hex payload-id)))))

(defparameter +engine-rpc-capabilities+
  '("engine_exchangeTransitionConfigurationV1"
    "engine_forkchoiceUpdatedV1"
    "engine_forkchoiceUpdatedV2"
    "engine_forkchoiceUpdatedV3"
    "engine_forkchoiceUpdatedV4"
    "engine_getPayloadBodiesByHashV1"
    "engine_getPayloadBodiesByHashV2"
    "engine_getPayloadBodiesByRangeV1"
    "engine_getPayloadBodiesByRangeV2"
    "engine_getPayloadV1"
    "engine_getPayloadV2"
    "engine_getPayloadV3"
    "engine_getPayloadV4"
    "engine_getPayloadV5"
    "engine_getPayloadV6"
    "engine_getBlobsV1"
    "engine_getBlobsV2"
    "engine_getBlobsV3"
    "engine_getClientVersionV1"
    "engine_newPayloadV1"
    "engine_newPayloadV2"
    "engine_newPayloadV3"
    "engine_newPayloadV4"
    "engine_newPayloadV5"))

(defun engine-rpc-capabilities ()
  (copy-list +engine-rpc-capabilities+))

(defparameter +engine-rpc-client-version+
  '(("code" . "CL")
    ("name" . "ethereum-lisp")
    ("version" . "0.1.0")
    ("commit" . "0x00000000")))

(defun engine-rpc-client-version ()
  (copy-tree +engine-rpc-client-version+))

(defun engine-rpc-transition-configuration-object (config)
  (unless (typep config 'chain-config)
    (block-validation-fail
     "engine_exchangeTransitionConfigurationV1 config must be chain-config"))
  (list (cons "terminalTotalDifficulty"
              (quantity-to-hex
               (or (chain-config-terminal-total-difficulty config) 0)))
        (cons "terminalBlockHash" (hash32-to-hex (zero-hash32)))
        (cons "terminalBlockNumber" (quantity-to-hex 0))))

(defun engine-rpc-new-payload-version (method)
  (cond
    ((string= method "engine_newPayloadV1") 1)
    ((string= method "engine_newPayloadV2") 2)
    ((string= method "engine_newPayloadV3") 3)
    ((string= method "engine_newPayloadV4") 4)
    ((string= method "engine_newPayloadV5") 5)
    (t nil)))

(defun engine-rpc-required-param
    (params index label &optional (method "engine_newPayload"))
  (unless (< index (length params))
    (block-validation-fail "~A param ~A is missing" method label))
  (nth index params))

(defun engine-rpc-handle-new-payload
    (version params store config &key import-function)
  (unless (and (listp params) params)
    (block-validation-fail "engine_newPayload params must include payload"))
  (let* ((payload
           (engine-rpc-executable-data-from-object
            (engine-rpc-required-param params 0 "payload")))
         (versioned-hashes
           (when (>= version 3)
             (engine-rpc-hash32-list
              (engine-rpc-required-param params 1 "versionedHashes")
              "versionedHashes")))
         (parent-beacon-root
           (when (>= version 3)
             (engine-rpc-optional-hash32-value
              (engine-rpc-required-param params 2 "parentBeaconBlockRoot")
              "parentBeaconBlockRoot")))
         (requests
           (when (>= version 4)
             (engine-rpc-byte-list
              (engine-rpc-required-param params 3 "executionRequests")
              "executionRequests"))))
    (multiple-value-bind (status block)
        (cond
          ((<= version 2)
           (engine-new-payload-memory-status
            store version payload config
            :import-function import-function))
          ((= version 3)
           (engine-new-payload-memory-status
            store version payload config
            :versioned-hashes versioned-hashes
            :parent-beacon-root parent-beacon-root
            :import-function import-function))
          (t
           (engine-new-payload-memory-status
            store version payload config
            :versioned-hashes versioned-hashes
            :parent-beacon-root parent-beacon-root
            :requests requests
            :import-function import-function)))
      (declare (ignore block))
      (engine-rpc-payload-status-object status))))

(defun engine-rpc-handle-exchange-capabilities (params)
  (when params
    (let ((remote (first params)))
      (unless (and (listp remote)
                   (every #'stringp remote))
        (block-validation-fail
         "engine_exchangeCapabilities params must contain a string list"))))
  (engine-rpc-capabilities))

(defun engine-rpc-handle-get-client-version (params)
  (when params
    (let ((caller (first params)))
      (unless (json-object-p caller)
        (block-validation-fail
         "engine_getClientVersionV1 params must contain a client version object"))
      (dolist (field '("code" "name" "version" "commit"))
        (let ((value (engine-rpc-required-field caller field)))
          (unless (stringp value)
            (block-validation-fail
             "engine_getClientVersionV1 client version fields must be strings"))))))
  (list (engine-rpc-client-version)))

(defun engine-rpc-validate-transition-configuration (object)
  (unless (json-object-p object)
    (block-validation-fail
     "engine_exchangeTransitionConfigurationV1 params must contain transition configuration object"))
  (engine-rpc-required-quantity-field object "terminalTotalDifficulty")
  (engine-rpc-required-hash32-field object "terminalBlockHash")
  (engine-rpc-required-quantity-field object "terminalBlockNumber")
  t)

(defun engine-rpc-handle-exchange-transition-configuration (params config)
  (unless params
    (block-validation-fail
     "engine_exchangeTransitionConfigurationV1 params must include transition configuration"))
  (engine-rpc-validate-transition-configuration (first params))
  (engine-rpc-transition-configuration-object config))

(defun engine-rpc-handle-web3-client-version (params)
  (when params
    (block-validation-fail "web3_clientVersion params must be empty"))
  (let ((version (engine-rpc-client-version)))
    (format nil "~A/~A/~A/~A"
            (engine-rpc-required-field version "name")
            (engine-rpc-required-field version "version")
            (engine-rpc-required-field version "code")
            (engine-rpc-required-field version "commit"))))

(defun engine-rpc-handle-web3-sha3 (params)
  (unless (= 1 (length params))
    (block-validation-fail "web3_sha3 params must contain exactly one data value"))
  (bytes-to-hex (keccak-256 (engine-rpc-bytes (first params) "web3_sha3 data"))))

(defun engine-rpc-handle-net-version (params config)
  (when params
    (block-validation-fail "net_version params must be empty"))
  (write-to-string (chain-config-chain-id config) :base 10))

(defun engine-rpc-handle-net-listening (params)
  (when params
    (block-validation-fail "net_listening params must be empty"))
  :false)

(defun engine-rpc-handle-net-peer-count (params)
  (when params
    (block-validation-fail "net_peerCount params must be empty"))
  (quantity-to-hex 0))

(defun engine-rpc-handle-eth-chain-id (params config)
  (when params
    (block-validation-fail "eth_chainId params must be empty"))
  (quantity-to-hex (chain-config-chain-id config)))

(defun engine-rpc-handle-eth-block-number (params store)
  (when params
    (block-validation-fail "eth_blockNumber params must be empty"))
  (quantity-to-hex (chain-store-head-number store)))

(defun engine-rpc-handle-eth-protocol-version (params)
  (when params
    (block-validation-fail "eth_protocolVersion params must be empty"))
  (quantity-to-hex +eth-protocol-version+))

(defun engine-rpc-handle-eth-syncing (params)
  (when params
    (block-validation-fail "eth_syncing params must be empty"))
  :false)

(defun engine-rpc-handle-eth-accounts (params)
  (when params
    (block-validation-fail "eth_accounts params must be empty"))
  (make-array 0))

(defun engine-rpc-handle-eth-coinbase (params)
  (when params
    (block-validation-fail "eth_coinbase params must be empty"))
  (address-to-hex (zero-address)))

(defun engine-rpc-handle-eth-mining (params)
  (when params
    (block-validation-fail "eth_mining params must be empty"))
  :false)

(defun engine-rpc-handle-eth-hashrate (params)
  (when params
    (block-validation-fail "eth_hashrate params must be empty"))
  (quantity-to-hex 0))

(defun engine-rpc-suggest-gas-tip-cap (store)
  (declare (ignore store))
  0)

(defun engine-rpc-handle-eth-max-priority-fee-per-gas (params store)
  (when params
    (block-validation-fail "eth_maxPriorityFeePerGas params must be empty"))
  (quantity-to-hex (engine-rpc-suggest-gas-tip-cap store)))

(defun engine-rpc-handle-eth-gas-price (params store)
  (when params
    (block-validation-fail "eth_gasPrice params must be empty"))
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head)))
         (base-fee (if header
                       (or (block-header-base-fee-per-gas header) 0)
                       0)))
    (quantity-to-hex (+ base-fee
                        (engine-rpc-suggest-gas-tip-cap store)))))

(defun engine-payload-store-head-block (store)
  (chain-store-block-by-number
   store
   (engine-payload-store-head-number store)))

(defun engine-rpc-handle-eth-base-fee (params store config)
  (when params
    (block-validation-fail "eth_baseFee params must be empty"))
  (let ((head (chain-store-latest-block store)))
    (when (and head
               (chain-config-london-p
                config
                (1+ (block-header-number (block-header head)))))
      (quantity-to-hex
       (expected-base-fee-per-gas
        (block-header head)
        :london-parent-p
        (not (null (block-header-base-fee-per-gas (block-header head)))))))))

(defun engine-rpc-handle-eth-blob-base-fee (params store config)
  (when params
    (block-validation-fail "eth_blobBaseFee params must be empty"))
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head))))
    (when (and header (block-header-excess-blob-gas header))
      (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
          (chain-config-blob-schedule
           config
           (block-header-number header)
           (block-header-timestamp header))
        (declare (ignore target-blob-gas max-blob-gas))
        (quantity-to-hex
         (block-header-blob-base-fee
          header :update-fraction update-fraction))))))

(defconstant +eth-rpc-max-fee-history-block-count+ 1024)
(defconstant +eth-rpc-max-fee-history-reward-percentiles+ 100)

(defun eth-rpc-head-block-tag-p (value)
  (and (stringp value)
       (or (string= value "latest")
           (string= value "pending")
           (string= value "safe")
           (string= value "finalized"))))

(defun eth-rpc-fee-history-block-count (params method)
  (let ((count (parse-genesis-quantity
                (engine-rpc-required-param params 0 "block count" method)
                "fee history block count"
                :required-p t)))
    (when (< count 1)
      (block-validation-fail
       "~A block count must be greater than zero" method))
    (min count +eth-rpc-max-fee-history-block-count+)))

(defun eth-rpc-fee-history-newest-block-number (params store method)
  (let ((value (engine-rpc-required-param params 1 "newest block" method)))
    (cond
      ((eth-rpc-head-block-tag-p value)
       (chain-store-block-tag-number store value))
      ((and (stringp value) (string= value "earliest")) 0)
      ((and (stringp value) (genesis-hex-quantity-string-p value))
       (parse-genesis-quantity value "newest block" :required-p t))
      (t
       (block-validation-fail
        "~A newest block must be latest, pending, safe, finalized, earliest, or a hex quantity"
        method)))))

(defun eth-rpc-fee-history-reward-percentiles (params method)
  (let ((percentiles (engine-rpc-required-param
                      params 2 "reward percentiles" method)))
    (unless (listp percentiles)
      (block-validation-fail
       "~A reward percentiles must be an array" method))
    (when (> (length percentiles)
             +eth-rpc-max-fee-history-reward-percentiles+)
      (block-validation-fail
       "~A reward percentiles exceed the query limit" method))
    (loop with previous = nil
          for percentile in percentiles
          do (progn
               (unless (realp percentile)
                 (block-validation-fail
                  "~A reward percentiles must be numbers" method))
               (unless (<= 0 percentile 100)
                 (block-validation-fail
                  "~A reward percentiles must be between 0 and 100" method))
               (when (and previous (<= percentile previous))
                 (block-validation-fail
                  "~A reward percentiles must be strictly increasing" method))
               (setf previous percentile))
          collect percentile)))

(defun eth-rpc-fee-history-blocks (store newest-number block-count method)
  (let* ((effective-count (min block-count (1+ newest-number)))
         (oldest-number (- newest-number effective-count -1))
         (blocks '()))
    (loop for number from oldest-number to newest-number
          for block = (chain-store-block-by-number store number)
          do (unless block
               (block-validation-fail
                "~A requested block is not available" method))
             (push block blocks))
    (values oldest-number (nreverse blocks))))

(defun eth-rpc-fee-history-gas-used-ratio (header)
  (if (plusp (block-header-gas-limit header))
      (/ (block-header-gas-used header)
         (block-header-gas-limit header))
      0))

(defun eth-rpc-fee-history-base-fee (header)
  (quantity-to-hex (or (block-header-base-fee-per-gas header) 0)))

(defun eth-rpc-fee-history-next-base-fee (header config)
  (quantity-to-hex
   (if (chain-config-london-p config (1+ (block-header-number header)))
       (expected-base-fee-per-gas
        header
        :london-parent-p
        (not (null (block-header-base-fee-per-gas header))))
       (or (block-header-base-fee-per-gas header) 0))))

(defun eth-rpc-fee-history-blob-enabled-p (blocks)
  (some (lambda (block)
          (let ((header (block-header block)))
            (or (block-header-blob-gas-used header)
                (block-header-excess-blob-gas header))))
        blocks))

(defun eth-rpc-fee-history-blob-schedule (header config)
  (chain-config-blob-schedule
   config
   (block-header-number header)
   (block-header-timestamp header)))

(defun eth-rpc-fee-history-blob-base-fee (header config)
  (if (block-header-excess-blob-gas header)
      (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
          (eth-rpc-fee-history-blob-schedule header config)
        (declare (ignore target-blob-gas max-blob-gas))
        (quantity-to-hex
         (block-header-blob-base-fee
          header :update-fraction update-fraction)))
      (quantity-to-hex 0)))

(defun eth-rpc-fee-history-next-blob-base-fee (header config)
  (if (block-header-excess-blob-gas header)
      (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
          (eth-rpc-fee-history-blob-schedule header config)
        (quantity-to-hex
         (blob-base-fee
          (expected-excess-blob-gas
           header
           :target-blob-gas target-blob-gas
           :max-blob-gas max-blob-gas
           :update-fraction update-fraction)
          :update-fraction update-fraction)))
      (quantity-to-hex 0)))

(defun eth-rpc-fee-history-blob-gas-used-ratio (header config)
  (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
      (eth-rpc-fee-history-blob-schedule header config)
    (declare (ignore target-blob-gas update-fraction))
    (if (plusp max-blob-gas)
        (/ (or (block-header-blob-gas-used header) 0) max-blob-gas)
        0)))

(defun eth-rpc-fee-history-zero-reward (percentiles)
  (loop repeat (length percentiles)
        collect (quantity-to-hex 0)))

(defun engine-rpc-handle-eth-fee-history (params store config)
  (let* ((method "eth_feeHistory")
         (block-count
           (progn
             (unless (= 3 (length params))
               (block-validation-fail
                "~A params must contain block count, newest block, and reward percentiles"
                method))
             (eth-rpc-fee-history-block-count params method)))
         (newest-number
           (eth-rpc-fee-history-newest-block-number params store method))
         (percentiles (eth-rpc-fee-history-reward-percentiles params method)))
    (multiple-value-bind (oldest-number blocks)
        (eth-rpc-fee-history-blocks store newest-number block-count method)
      (let* ((headers (mapcar #'block-header blocks))
             (newest-header (car (last headers)))
             (object
               (list
                (cons "oldestBlock" (quantity-to-hex oldest-number))
                (cons "baseFeePerGas"
                      (append
                       (mapcar #'eth-rpc-fee-history-base-fee headers)
                       (list
                        (eth-rpc-fee-history-next-base-fee
                         newest-header config))))
                (cons "gasUsedRatio"
                      (mapcar #'eth-rpc-fee-history-gas-used-ratio
                              headers)))))
        (when percentiles
          (setf object
                (append object
                        (list
                         (cons "reward"
                               (loop repeat (length blocks)
                                     collect
                                     (eth-rpc-fee-history-zero-reward
                                      percentiles)))))))
        (when (eth-rpc-fee-history-blob-enabled-p blocks)
          (setf object
                (append
                 object
                 (list
                  (cons "baseFeePerBlobGas"
                        (append
                         (mapcar
                          (lambda (header)
                            (eth-rpc-fee-history-blob-base-fee
                             header config))
                          headers)
                         (list
                          (eth-rpc-fee-history-next-blob-base-fee
                           newest-header config))))
                  (cons "blobGasUsedRatio"
                        (mapcar
                         (lambda (header)
                           (eth-rpc-fee-history-blob-gas-used-ratio
                            header config))
                         headers))))))
        object))))

(defun eth-rpc-address-param (value method label)
  (handler-case
      (engine-rpc-address value label)
    (block-validation-error ()
      (block-validation-fail "~A ~A must be an address" method label))))

(defun eth-rpc-storage-slot-param-values (value method)
  (handler-case
      (let ((text value))
        (unless (stringp text)
          (block-validation-fail "~A storage key must be a hex string" method))
        (let ((hex (if (and (>= (length text) 2)
                            (char= (char text 0) #\0)
                            (member (char text 1) '(#\x #\X)))
                       (subseq text 2)
                       text)))
          (when (oddp (length hex))
            (setf hex (concatenate 'string "0" hex)))
          (when (> (length hex) 64)
            (block-validation-fail
             "~A storage key must be at most 32 bytes" method))
          (let* ((bytes (hex-to-bytes hex))
                 (padded (make-byte-vector 32)))
            (replace padded bytes :start1 (- 32 (length bytes)))
            (values (make-hash32 padded) (length bytes)))))
    (block-validation-error (condition)
      (error condition))
    (error ()
      (block-validation-fail "~A storage key must be hex bytes" method))))

(defun eth-rpc-storage-slot-param (value method)
  (nth-value 0 (eth-rpc-storage-slot-param-values value method)))

(defun eth-rpc-uint256-word-hex (value)
  (let* ((bytes (integer-to-minimal-bytes
                 (ensure-uint256 value "RPC storage value")))
         (word (make-byte-vector 32)))
    (replace word bytes :start1 (- 32 (length bytes)))
    (bytes-to-hex word)))

(defun eth-rpc-block-number-param (params store method)
  (unless (= 1 (length params))
    (block-validation-fail "~A params must contain exactly one block number"
                           method))
  (let ((value (first params)))
    (cond
      ((eth-rpc-head-block-tag-p value)
       (chain-store-block-tag-number store value))
      ((and (stringp value) (string= value "earliest")) 0)
      ((and (stringp value)
            (genesis-hex-quantity-string-p value))
       (parse-genesis-quantity value "block number" :required-p t))
      (t
       (block-validation-fail
        "~A block number must be latest, pending, safe, finalized, earliest, or a hex quantity"
        method)))))

(defun eth-rpc-block-param (params store method)
  (unless (= 1 (length params))
    (block-validation-fail "~A params must contain exactly one block id"
                           method))
  (let ((value (first params)))
    (if (and (stringp value)
             (= 66 (length value)))
        (chain-store-known-block
         store
         (eth-rpc-hash-param params method "block hash"))
        (chain-store-block-by-number
         store
         (eth-rpc-block-number-param params store method)))))

(defun engine-rpc-handle-eth-get-balance (params store)
  (unless (= 2 (length params))
    (block-validation-fail
     "eth_getBalance params must contain address and block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getBalance" "address"))
         (block (eth-rpc-block-param
                 (list (second params)) store "eth_getBalance")))
    (when (and block
               (chain-store-state-available-p
                store (block-hash block)))
      (quantity-to-hex
       (chain-store-account-balance
        store (block-hash block) address)))))

(defun eth-rpc-pending-account-nonce (store address state-nonce)
  (loop with next-nonce = state-nonce
        for transaction in (engine-payload-store-pending-transactions store)
        for sender = (or (transaction-sender transaction) (zero-address))
        when (bytes= (address-bytes sender) (address-bytes address))
          do (setf next-nonce
                   (max next-nonce (1+ (transaction-nonce transaction))))
        finally (return next-nonce)))

(defun engine-rpc-handle-eth-get-transaction-count (params store)
  (unless (= 2 (length params))
    (block-validation-fail
     "eth_getTransactionCount params must contain address and block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getTransactionCount" "address"))
         (block-id (second params))
         (block (eth-rpc-block-param
                 (list block-id) store "eth_getTransactionCount")))
    (when (and block
               (chain-store-state-available-p
                store (block-hash block)))
      (let ((state-nonce
              (chain-store-account-nonce
               store (block-hash block) address)))
        (quantity-to-hex
         (if (and (stringp block-id) (string= block-id "pending"))
             (eth-rpc-pending-account-nonce store address state-nonce)
             state-nonce))))))

(defun engine-rpc-handle-eth-get-code (params store)
  (unless (= 2 (length params))
    (block-validation-fail
     "eth_getCode params must contain address and block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getCode" "address"))
         (block (eth-rpc-block-param
                 (list (second params)) store "eth_getCode")))
    (when (and block
               (chain-store-state-available-p
                store (block-hash block)))
      (bytes-to-hex
       (chain-store-account-code
        store (block-hash block) address)))))

(defun engine-rpc-handle-eth-get-storage-at (params store)
  (unless (= 3 (length params))
    (block-validation-fail
     "eth_getStorageAt params must contain address, storage key, and block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getStorageAt" "address"))
         (slot (eth-rpc-storage-slot-param
                (second params) "eth_getStorageAt"))
         (block (eth-rpc-block-param
                 (list (third params)) store "eth_getStorageAt")))
    (when (and block
               (chain-store-state-available-p
                store (block-hash block)))
      (eth-rpc-uint256-word-hex
       (chain-store-account-storage
        store (block-hash block) address slot)))))

(defun eth-rpc-proof-key-for-address (address)
  (keccak-256 (address-bytes address)))

(defun eth-rpc-proof-key-for-storage-slot (slot)
  (keccak-256 (hash32-bytes slot)))

(defun eth-rpc-storage-trie-from-entries (storage-entries)
  (let ((trie (make-mpt)))
    (dolist (entry storage-entries trie)
      (mpt-put trie
               (eth-rpc-proof-key-for-storage-slot (car entry))
               (rlp-encode (cdr entry))))))

(defconstant +eth-get-proof-max-storage-keys+ 1024)

(defstruct (eth-rpc-proof-storage-slot
            (:constructor make-eth-rpc-proof-storage-slot
                (&key slot output-key)))
  slot
  output-key)

(defun eth-rpc-proof-storage-slot-param (value method)
  (multiple-value-bind (slot input-length)
      (eth-rpc-storage-slot-param-values value method)
    (make-eth-rpc-proof-storage-slot
     :slot slot
     :output-key
     (if (= input-length 32)
         (hash32-to-hex slot)
         (quantity-to-hex (bytes-to-integer (hash32-bytes slot)))))))

(defun eth-rpc-storage-proof-object (trie proof-slot value)
  (let ((slot (eth-rpc-proof-storage-slot-slot proof-slot)))
    (list (cons "key" (eth-rpc-proof-storage-slot-output-key proof-slot))
          (cons "value" (quantity-to-hex value))
          (cons "proof"
                (mapcar #'bytes-to-hex
                        (mpt-get-proof
                         trie
                         (eth-rpc-proof-key-for-storage-slot slot)))))))

(defun eth-rpc-proof-storage-slots-param (value method)
  (unless (listp value)
    (block-validation-fail "~A storage keys must be a list" method))
  (when (> (length value) +eth-get-proof-max-storage-keys+)
    (block-validation-fail
     "~A storage keys must contain at most ~D entries"
     method +eth-get-proof-max-storage-keys+))
  (mapcar (lambda (slot)
            (eth-rpc-proof-storage-slot-param slot method))
          value))

(defun eth-rpc-build-proof-object (store block-hash address slots)
  (let ((state-trie (make-mpt))
        (target-account nil)
        (target-storage-trie nil)
        (target-storage-values (make-hash-table :test #'equal)))
    (chain-store-for-each-account
     store
     block-hash
     (lambda (account-address balance nonce code storage-entries)
       (let* ((storage-trie
                (eth-rpc-storage-trie-from-entries storage-entries))
              (account
                (make-state-account
                 :nonce nonce
                 :balance balance
                 :storage-root (make-hash32 (mpt-root-hash storage-trie))
                 :code-hash (keccak-256-hash code))))
         (mpt-put state-trie
                  (eth-rpc-proof-key-for-address account-address)
                  (state-account-rlp account))
         (when (bytes= (address-bytes account-address)
                       (address-bytes address))
           (setf target-account account
                 target-storage-trie storage-trie)
           (dolist (entry storage-entries)
             (setf (gethash (hash32-to-hex (car entry))
                            target-storage-values)
                   (cdr entry)))))))
    (unless target-account
      (setf target-account (make-state-account)
            target-storage-trie (make-mpt)))
    (list
     (cons "address" (address-to-hex address))
     (cons "accountProof"
           (mapcar #'bytes-to-hex
                   (mpt-get-proof
                    state-trie
                    (eth-rpc-proof-key-for-address address))))
     (cons "balance" (quantity-to-hex (state-account-balance target-account)))
     (cons "codeHash"
           (hash32-to-hex (state-account-code-hash target-account)))
     (cons "nonce" (quantity-to-hex (state-account-nonce target-account)))
     (cons "storageHash"
           (hash32-to-hex (state-account-storage-root target-account)))
     (cons "storageProof"
           (mapcar
            (lambda (slot)
              (let ((slot-hash (eth-rpc-proof-storage-slot-slot slot)))
                (eth-rpc-storage-proof-object
                 target-storage-trie
                 slot
                 (gethash (hash32-to-hex slot-hash) target-storage-values 0))))
            slots)))))

(defun engine-rpc-handle-eth-get-proof (params store)
  (unless (= 3 (length params))
    (block-validation-fail
     "eth_getProof params must contain address, storage keys, and block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getProof" "address"))
         (slots (eth-rpc-proof-storage-slots-param
                 (second params) "eth_getProof"))
         (block (eth-rpc-block-param
                 (list (third params)) store "eth_getProof")))
    (when (and block
               (chain-store-state-available-p
                store (block-hash block)))
      (eth-rpc-build-proof-object store (block-hash block) address slots))))

(defun eth-rpc-header-object (header)
  (unless (block-header-p header)
    (block-validation-fail "eth header result must be a block header"))
  (append
   (list
    (cons "number" (quantity-to-hex (block-header-number header)))
    (cons "hash" (hash32-to-hex (block-header-hash header)))
    (cons "parentHash"
          (hash32-to-hex (or (block-header-parent-hash header)
                             (zero-hash32))))
    (cons "nonce"
          (bytes-to-hex (or (block-header-nonce header)
                            (make-byte-vector 8))))
    (cons "mixHash"
          (hash32-to-hex (or (block-header-mix-hash header)
                             (zero-hash32))))
    (cons "sha3Uncles"
          (hash32-to-hex (or (block-header-ommers-hash header)
                             +empty-ommers-hash+)))
    (cons "logsBloom"
          (bytes-to-hex (or (block-header-logs-bloom header)
                            (make-byte-vector 256))))
    (cons "stateRoot"
          (hash32-to-hex (or (block-header-state-root header)
                             +empty-trie-hash+)))
    (cons "miner"
          (address-to-hex (or (block-header-beneficiary header)
                              (zero-address))))
    (cons "difficulty" (quantity-to-hex (block-header-difficulty header)))
    (cons "extraData" (bytes-to-hex (block-header-extra-data header)))
    (cons "gasLimit" (quantity-to-hex (block-header-gas-limit header)))
    (cons "gasUsed" (quantity-to-hex (block-header-gas-used header)))
    (cons "timestamp" (quantity-to-hex (block-header-timestamp header)))
    (cons "transactionsRoot"
          (hash32-to-hex (or (block-header-transactions-root header)
                             +empty-trie-hash+)))
    (cons "receiptsRoot"
          (hash32-to-hex (or (block-header-receipts-root header)
                             +empty-trie-hash+))))
   (when (block-header-base-fee-per-gas header)
     (list (cons "baseFeePerGas"
                 (quantity-to-hex
                  (block-header-base-fee-per-gas header)))))
   (when (block-header-withdrawals-root header)
     (list (cons "withdrawalsRoot"
                 (hash32-to-hex
                  (block-header-withdrawals-root header)))))
   (when (block-header-blob-gas-used header)
     (list (cons "blobGasUsed"
                 (quantity-to-hex (block-header-blob-gas-used header)))))
   (when (block-header-excess-blob-gas header)
     (list (cons "excessBlobGas"
                 (quantity-to-hex
                  (block-header-excess-blob-gas header)))))
   (when (block-header-parent-beacon-root header)
     (list (cons "parentBeaconBlockRoot"
                 (hash32-to-hex
                  (block-header-parent-beacon-root header)))))
   (when (block-header-requests-hash header)
     (list (cons "requestsHash"
                 (hash32-to-hex (block-header-requests-hash header)))))
   (when (block-header-block-access-list-hash header)
     (list (cons "balHash"
                 (hash32-to-hex
                  (block-header-block-access-list-hash header)))))
   (when (block-header-slot-number header)
     (list (cons "slotNumber"
                 (quantity-to-hex (block-header-slot-number header)))))))

(defun engine-rpc-handle-eth-get-header-by-number (params store)
  (let* ((number (eth-rpc-block-number-param
                  params store "eth_getHeaderByNumber"))
         (block (chain-store-block-by-number store number)))
    (when block
      (eth-rpc-header-object (block-header block)))))

(defun eth-rpc-hash-param (params method label)
  (unless (= 1 (length params))
    (block-validation-fail "~A params must contain exactly one ~A"
                           method label))
  (engine-rpc-hash32 (first params) label))

(defun engine-rpc-handle-eth-get-header-by-hash (params store)
  (let* ((hash (eth-rpc-hash-param
                params "eth_getHeaderByHash" "block hash"))
         (block (chain-store-known-block store hash)))
    (when block
      (eth-rpc-header-object (block-header block)))))

(defun eth-rpc-rlp-length-prefix (offset length)
  (if (<= length 55)
      (ensure-byte-vector (list (+ offset length)))
      (let ((length-bytes (integer-to-minimal-bytes length)))
        (concat-bytes
         (ensure-byte-vector (list (+ offset 55 (length length-bytes))))
         length-bytes))))

(defun eth-rpc-encoded-rlp-list (encoded-items)
  (let ((payload (if encoded-items
                     (apply #'concat-bytes encoded-items)
                     (make-byte-vector 0))))
    (concat-bytes (eth-rpc-rlp-length-prefix #xc0 (length payload))
                  payload)))

(defun eth-rpc-block-rlp (block)
  (unless (typep block 'ethereum-block)
    (block-validation-fail "eth block result must be a block"))
  (let ((items
          (list
           (block-header-rlp (block-header block))
           (eth-rpc-encoded-rlp-list
            (mapcar #'transaction-encoding (block-transactions block)))
           (eth-rpc-encoded-rlp-list
            (mapcar #'block-header-rlp (block-ommers block))))))
    (when (block-withdrawals-present-p block)
      (setf items
            (append items
                    (list (eth-rpc-encoded-rlp-list
                           (mapcar #'withdrawal-rlp
                                   (block-withdrawals block)))))))
    (when (block-requests-present-p block)
      (setf items
            (append items
                    (list (eth-rpc-encoded-rlp-list
                           (mapcar #'rlp-encode
                                   (block-requests block)))))))
    (when (block-block-access-list-present-p block)
      (setf items
            (append items
                    (list (or (block-encoded-block-access-list block)
                              (block-access-list-rlp
                               (block-block-access-list block)))))))
    (eth-rpc-encoded-rlp-list items)))

(defun eth-rpc-block-full-transactions-param (params method)
  (unless (= 2 (length params))
    (block-validation-fail
     "~A params must contain block id and full transaction flag" method))
  (let ((full-transactions-p (second params)))
    (unless (or (null full-transactions-p)
                (eq full-transactions-p t))
      (block-validation-fail
       "~A full transaction flag must be a boolean" method))
    full-transactions-p))

(defun eth-rpc-block-transactions-object (block full-transactions-p)
  (if full-transactions-p
      (loop for transaction in (block-transactions block)
            for index from 0
            collect (eth-rpc-transaction-object transaction block index))
      (mapcar (lambda (transaction)
                (hash32-to-hex (transaction-hash transaction)))
              (block-transactions block))))

(defun eth-rpc-block-object (block full-transactions-p)
  (unless (typep block 'ethereum-block)
    (block-validation-fail "eth block result must be a block"))
  (append
   (eth-rpc-header-object (block-header block))
   (list
    (cons "size" (quantity-to-hex (length (eth-rpc-block-rlp block))))
    (cons "transactions"
          (eth-rpc-block-transactions-object block full-transactions-p))
    (cons "uncles"
          (mapcar (lambda (ommer)
                    (hash32-to-hex (block-header-hash ommer)))
                  (block-ommers block))))
   (when (block-withdrawals-present-p block)
     (list
      (cons "withdrawals"
            (mapcar #'engine-rpc-withdrawal-object
                    (block-withdrawals block)))))))

(defun engine-rpc-handle-eth-get-block-by-number (params store)
  (let* ((full-transactions-p
           (eth-rpc-block-full-transactions-param params "eth_getBlockByNumber"))
         (number (eth-rpc-block-number-param
                  (list (first params)) store "eth_getBlockByNumber"))
         (block (chain-store-block-by-number store number)))
    (when block
      (eth-rpc-block-object block full-transactions-p))))

(defun engine-rpc-handle-eth-get-block-by-hash (params store)
  (let* ((full-transactions-p
           (eth-rpc-block-full-transactions-param params "eth_getBlockByHash"))
         (hash (eth-rpc-hash-param
                (list (first params)) "eth_getBlockByHash" "block hash"))
         (block (chain-store-known-block store hash)))
    (when block
      (eth-rpc-block-object block full-transactions-p))))

(defun eth-rpc-block-transaction-count (block)
  (when block
    (quantity-to-hex (length (block-transactions block)))))

(defun engine-rpc-handle-eth-get-block-transaction-count-by-number
    (params store)
  (let* ((number (eth-rpc-block-number-param
                  params store
                  "eth_getBlockTransactionCountByNumber"))
         (block (chain-store-block-by-number store number)))
    (eth-rpc-block-transaction-count block)))

(defun engine-rpc-handle-eth-get-block-transaction-count-by-hash
    (params store)
  (let* ((hash (eth-rpc-hash-param
                params
                "eth_getBlockTransactionCountByHash"
                "block hash"))
         (block (chain-store-known-block store hash)))
    (eth-rpc-block-transaction-count block)))

(defun eth-rpc-block-ommer-count (block)
  (when block
    (quantity-to-hex (length (block-ommers block)))))

(defun eth-rpc-ommer-object (header)
  (when header
    (let ((block (make-block :header header)))
      (append
       (eth-rpc-header-object header)
       (list
        (cons "size" (quantity-to-hex (length (eth-rpc-block-rlp block))))
        (cons "uncles" '()))))))

(defun eth-rpc-ommer-by-index (block index)
  (when (and block (< index (length (block-ommers block))))
    (eth-rpc-ommer-object (nth index (block-ommers block)))))

(defun engine-rpc-handle-eth-get-uncle-count-by-number (params store)
  (let* ((number (eth-rpc-block-number-param
                  params store "eth_getUncleCountByBlockNumber"))
         (block (chain-store-block-by-number store number)))
    (eth-rpc-block-ommer-count block)))

(defun engine-rpc-handle-eth-get-uncle-count-by-hash (params store)
  (let* ((hash (eth-rpc-hash-param
                params "eth_getUncleCountByBlockHash" "block hash"))
         (block (chain-store-known-block store hash)))
    (eth-rpc-block-ommer-count block)))

(defun engine-rpc-handle-eth-get-uncle-by-block-number-and-index
    (params store)
  (unless (= 2 (length params))
    (block-validation-fail
     "eth_getUncleByBlockNumberAndIndex params must contain block id and uncle index"))
  (let* ((number (eth-rpc-block-number-param
                  (list (first params)) store
                  "eth_getUncleByBlockNumberAndIndex"))
         (index (engine-rpc-quantity-param
                 params 1 "uncle index"
                 "eth_getUncleByBlockNumberAndIndex"))
         (block (chain-store-block-by-number store number)))
    (eth-rpc-ommer-by-index block index)))

(defun engine-rpc-handle-eth-get-uncle-by-block-hash-and-index
    (params store)
  (unless (= 2 (length params))
    (block-validation-fail
     "eth_getUncleByBlockHashAndIndex params must contain block id and uncle index"))
  (let* ((hash (eth-rpc-hash-param
                (list (first params))
                "eth_getUncleByBlockHashAndIndex"
                "block hash"))
         (index (engine-rpc-quantity-param
                 params 1 "uncle index"
                 "eth_getUncleByBlockHashAndIndex"))
         (block (chain-store-known-block store hash)))
    (eth-rpc-ommer-by-index block index)))

(defun eth-rpc-transaction-index-param (params method)
  (unless (= 2 (length params))
    (block-validation-fail
     "~A params must contain block id and transaction index" method))
  (engine-rpc-quantity-param params 1 "transaction index" method))

(defun eth-rpc-raw-transaction-by-index (block index)
  (when (and block (< index (length (block-transactions block))))
    (bytes-to-hex (transaction-encoding
                   (nth index (block-transactions block))))))

(defun eth-rpc-address-or-null (address)
  (when address
    (address-to-hex address)))

(defun eth-rpc-access-list-entry-object (entry)
  (list
   (cons "address" (address-to-hex (access-list-entry-address entry)))
   (cons "storageKeys"
         (mapcar #'hash32-to-hex
                 (access-list-entry-storage-keys entry)))))

(defun eth-rpc-access-list-object (access-list)
  (mapcar #'eth-rpc-access-list-entry-object access-list))

(defun eth-rpc-set-code-authorization-object (authorization)
  (list
   (cons "chainId"
         (quantity-to-hex
          (set-code-authorization-chain-id authorization)))
   (cons "address"
         (address-to-hex
          (set-code-authorization-address authorization)))
   (cons "nonce"
         (quantity-to-hex
          (set-code-authorization-nonce authorization)))
   (cons "yParity"
         (quantity-to-hex
          (set-code-authorization-y-parity authorization)))
   (cons "r" (quantity-to-hex (set-code-authorization-r authorization)))
   (cons "s" (quantity-to-hex (set-code-authorization-s authorization)))))

(defun eth-rpc-transaction-core-fields (transaction)
  (etypecase transaction
    (legacy-transaction
     (values (legacy-transaction-nonce transaction)
             (legacy-transaction-gas-price transaction)
             (legacy-transaction-gas-limit transaction)
             (legacy-transaction-to transaction)
             (legacy-transaction-value transaction)
             (legacy-transaction-data transaction)
             (legacy-transaction-v transaction)
             (legacy-transaction-r transaction)
             (legacy-transaction-s transaction)))
    (access-list-transaction
     (values (access-list-transaction-nonce transaction)
             (access-list-transaction-gas-price transaction)
             (access-list-transaction-gas-limit transaction)
             (access-list-transaction-to transaction)
             (access-list-transaction-value transaction)
             (access-list-transaction-data transaction)
             (access-list-transaction-y-parity transaction)
             (access-list-transaction-r transaction)
             (access-list-transaction-s transaction)))
    (dynamic-fee-transaction
     (values (dynamic-fee-transaction-nonce transaction)
             (dynamic-fee-transaction-max-fee-per-gas transaction)
             (dynamic-fee-transaction-gas-limit transaction)
             (dynamic-fee-transaction-to transaction)
             (dynamic-fee-transaction-value transaction)
             (dynamic-fee-transaction-data transaction)
             (dynamic-fee-transaction-y-parity transaction)
             (dynamic-fee-transaction-r transaction)
             (dynamic-fee-transaction-s transaction)))
    (blob-transaction
     (values (blob-transaction-nonce transaction)
             (blob-transaction-max-fee-per-gas transaction)
             (blob-transaction-gas-limit transaction)
             (blob-transaction-to transaction)
             (blob-transaction-value transaction)
             (blob-transaction-data transaction)
             (blob-transaction-y-parity transaction)
             (blob-transaction-r transaction)
             (blob-transaction-s transaction)))
    (set-code-transaction
     (values (set-code-transaction-nonce transaction)
             (set-code-transaction-max-fee-per-gas transaction)
             (set-code-transaction-gas-limit transaction)
             (set-code-transaction-to transaction)
             (set-code-transaction-value transaction)
             (set-code-transaction-data transaction)
             (set-code-transaction-y-parity transaction)
             (set-code-transaction-r transaction)
             (set-code-transaction-s transaction)))))

(defun eth-rpc-transaction-gas-price (transaction header)
  (if (or (typep transaction 'legacy-transaction)
          (typep transaction 'access-list-transaction)
          (not header)
          (not (block-header-base-fee-per-gas header)))
      (transaction-max-fee-per-gas transaction)
      (transaction-effective-gas-price
       transaction :base-fee (block-header-base-fee-per-gas header))))

(defun eth-rpc-transaction-sender (transaction)
  (or (transaction-sender transaction)
      (block-validation-fail
       "eth transaction sender recovery failed")))

(defun eth-rpc-transaction-type-fields (transaction)
  (etypecase transaction
    (legacy-transaction
     (let ((chain-id (legacy-transaction-chain-id transaction)))
       (when (and chain-id (plusp chain-id))
         (list (cons "chainId" (quantity-to-hex chain-id))))))
    (access-list-transaction
     (list
      (cons "accessList"
            (eth-rpc-access-list-object
             (access-list-transaction-access-list transaction)))
      (cons "chainId"
            (quantity-to-hex
             (access-list-transaction-chain-id transaction)))
      (cons "yParity"
            (quantity-to-hex
             (access-list-transaction-y-parity transaction)))))
    (dynamic-fee-transaction
     (list
      (cons "accessList"
            (eth-rpc-access-list-object
             (dynamic-fee-transaction-access-list transaction)))
      (cons "chainId"
            (quantity-to-hex
             (dynamic-fee-transaction-chain-id transaction)))
      (cons "yParity"
            (quantity-to-hex
             (dynamic-fee-transaction-y-parity transaction)))
      (cons "maxFeePerGas"
            (quantity-to-hex
             (dynamic-fee-transaction-max-fee-per-gas transaction)))
      (cons "maxPriorityFeePerGas"
            (quantity-to-hex
             (dynamic-fee-transaction-max-priority-fee-per-gas transaction)))))
    (blob-transaction
     (list
      (cons "accessList"
            (eth-rpc-access-list-object
             (blob-transaction-access-list transaction)))
      (cons "chainId"
            (quantity-to-hex
             (blob-transaction-chain-id transaction)))
      (cons "yParity"
            (quantity-to-hex
             (blob-transaction-y-parity transaction)))
      (cons "maxFeePerGas"
            (quantity-to-hex
             (blob-transaction-max-fee-per-gas transaction)))
      (cons "maxPriorityFeePerGas"
            (quantity-to-hex
             (blob-transaction-max-priority-fee-per-gas transaction)))
      (cons "maxFeePerBlobGas"
            (quantity-to-hex
             (blob-transaction-max-fee-per-blob-gas transaction)))
      (cons "blobVersionedHashes"
            (mapcar #'hash32-to-hex
                    (blob-transaction-blob-versioned-hashes
                     transaction)))))
    (set-code-transaction
     (list
      (cons "accessList"
            (eth-rpc-access-list-object
             (set-code-transaction-access-list transaction)))
      (cons "chainId"
            (quantity-to-hex
             (set-code-transaction-chain-id transaction)))
      (cons "yParity"
            (quantity-to-hex
             (set-code-transaction-y-parity transaction)))
      (cons "maxFeePerGas"
            (quantity-to-hex
             (set-code-transaction-max-fee-per-gas transaction)))
      (cons "maxPriorityFeePerGas"
            (quantity-to-hex
             (set-code-transaction-max-priority-fee-per-gas transaction)))
      (cons "authorizationList"
            (mapcar #'eth-rpc-set-code-authorization-object
                    (set-code-transaction-authorization-list
                     transaction)))))))

(defun eth-rpc-transaction-object (transaction block index)
  (let ((header (when block
                  (block-header block))))
    (multiple-value-bind (nonce gas-price gas-limit to value data v r s)
        (eth-rpc-transaction-core-fields transaction)
      (append
       (list
        (cons "blockHash" (when block
                            (hash32-to-hex (block-hash block))))
        (cons "blockNumber"
              (when header
                (quantity-to-hex (block-header-number header))))
        (cons "blockTimestamp"
              (when header
                (quantity-to-hex (block-header-timestamp header))))
        (cons "from"
              (address-to-hex
               (eth-rpc-transaction-sender transaction)))
        (cons "gas" (quantity-to-hex gas-limit))
        (cons "gasPrice"
              (quantity-to-hex
               (eth-rpc-transaction-gas-price transaction header)))
        (cons "hash" (hash32-to-hex (transaction-hash transaction)))
        (cons "input" (bytes-to-hex data))
        (cons "nonce" (quantity-to-hex nonce))
        (cons "to" (eth-rpc-address-or-null to))
        (cons "transactionIndex" (when index
                                   (quantity-to-hex index)))
        (cons "value" (quantity-to-hex value))
        (cons "type" (quantity-to-hex (transaction-type transaction))))
       (eth-rpc-transaction-type-fields transaction)
       (list
        (cons "v" (quantity-to-hex v))
        (cons "r" (quantity-to-hex r))
        (cons "s" (quantity-to-hex s)))))))

(defun eth-rpc-transaction-by-index (block index)
  (when (and block (< index (length (block-transactions block))))
    (eth-rpc-transaction-object
     (nth index (block-transactions block)) block index)))

(defun eth-rpc-transaction-from-location (location)
  (when location
    (eth-rpc-transaction-object
     (engine-transaction-location-transaction location)
     (engine-transaction-location-block location)
     (engine-transaction-location-index location))))

(defun eth-rpc-pending-transaction-object (transaction)
  (when transaction
    (eth-rpc-transaction-object transaction nil nil)))

(defun eth-rpc-pending-transaction-objects (transactions)
  (eth-rpc-json-array
   (mapcar #'eth-rpc-pending-transaction-object transactions)))

(defun eth-rpc-hash-table-object (table)
  (if (zerop (hash-table-count table))
      +json-empty-object+
      (loop for key in (sort (loop for key being the hash-keys of table
                                   collect key)
                             #'string<)
            collect (cons key (gethash key table)))))

(defun txpool-rpc-transaction-sender (transaction)
  (or (transaction-sender transaction)
      (zero-address)))

(defun txpool-rpc-transaction-sender-p (transaction address)
  (bytes= (address-bytes (txpool-rpc-transaction-sender transaction))
          (address-bytes address)))

(defun txpool-rpc-nonce-transactions (transactions)
  (let ((nonce-transactions (make-hash-table :test 'equal)))
    (dolist (transaction transactions)
      (setf (gethash
             (write-to-string (transaction-nonce transaction) :base 10)
             nonce-transactions)
            (eth-rpc-pending-transaction-object transaction)))
    (eth-rpc-hash-table-object nonce-transactions)))

(defun txpool-rpc-indexed-nonce-transactions
    (sender-transactions value-function)
  (if (or (null sender-transactions)
          (zerop (hash-table-count sender-transactions)))
      +json-empty-object+
      (loop for nonce in (sort (loop for nonce being the hash-keys
                                       of sender-transactions
                                     collect nonce)
                               #'string<)
            collect
            (cons nonce
                  (funcall value-function
                           (gethash nonce sender-transactions))))))

(defun txpool-rpc-indexed-sender-transactions
    (sender-index value-function)
  (if (zerop (hash-table-count sender-index))
      +json-empty-object+
      (loop for sender in (sort (loop for sender being the hash-keys
                                        of sender-index
                                      collect sender)
                                #'string<)
            collect
            (cons sender
                  (txpool-rpc-indexed-nonce-transactions
                   (gethash sender sender-index)
                   value-function)))))

(defun txpool-rpc-transaction-summary (transaction)
  (let ((to (transaction-to transaction)))
    (format nil "~A: ~D wei + ~D gas x ~D wei"
            (if to
                (address-to-hex to)
                "contract creation")
            (transaction-value transaction)
            (transaction-gas-limit transaction)
            (transaction-max-fee-per-gas transaction))))

(defun txpool-rpc-content-transactions (transactions)
  (let ((senders (make-hash-table :test 'equal)))
    (dolist (transaction transactions)
      (let* ((sender (address-to-hex
                      (txpool-rpc-transaction-sender transaction)))
             (nonce (write-to-string (transaction-nonce transaction)
                                     :base 10))
             (sender-transactions (or (gethash sender senders)
                                      (setf (gethash sender senders)
                                            (make-hash-table :test 'equal)))))
        (setf (gethash nonce sender-transactions)
              (eth-rpc-pending-transaction-object transaction))))
    (if (zerop (hash-table-count senders))
        +json-empty-object+
        (loop for sender in (sort (loop for sender being the hash-keys
                                          of senders
                                        collect sender)
                                  #'string<)
              collect
              (cons sender
                    (eth-rpc-hash-table-object
                     (gethash sender senders)))))))

(defun txpool-rpc-indexed-content-transactions (sender-index)
  (txpool-rpc-indexed-sender-transactions
   sender-index
   #'eth-rpc-pending-transaction-object))

(defun txpool-rpc-inspect-transactions (transactions)
  (let ((senders (make-hash-table :test 'equal)))
    (dolist (transaction transactions)
      (let* ((sender (address-to-hex
                      (txpool-rpc-transaction-sender transaction)))
             (nonce (write-to-string (transaction-nonce transaction)
                                     :base 10))
             (sender-transactions (or (gethash sender senders)
                                      (setf (gethash sender senders)
                                            (make-hash-table :test 'equal)))))
        (setf (gethash nonce sender-transactions)
              (txpool-rpc-transaction-summary transaction))))
    (if (zerop (hash-table-count senders))
        +json-empty-object+
        (loop for sender in (sort (loop for sender being the hash-keys
                                          of senders
                                        collect sender)
                                  #'string<)
              collect
              (cons sender
                    (eth-rpc-hash-table-object
                     (gethash sender senders)))))))

(defun txpool-rpc-indexed-inspect-transactions (sender-index)
  (txpool-rpc-indexed-sender-transactions
   sender-index
   #'txpool-rpc-transaction-summary))

(defun eth-rpc-raw-transaction-from-location (location)
  (when location
    (bytes-to-hex
     (transaction-encoding
      (engine-transaction-location-transaction location)))))

(defun eth-rpc-raw-transaction (transaction)
  (when transaction
    (bytes-to-hex (transaction-encoding transaction))))

(defun eth-rpc-contract-creation-address (transaction sender)
  (when (and (null (transaction-to transaction)) sender)
    (let* ((hash (keccak-256
                  (rlp-encode
                   (make-rlp-list (address-bytes sender)
                                  (transaction-nonce transaction)))))
           (bytes (make-byte-vector 20)))
      (replace bytes hash :start2 12)
      (make-address bytes))))

(defun eth-rpc-validate-set-code-authorization-signatures (transaction)
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

(defun eth-rpc-receipt-gas-used (receipt previous-receipt)
  (- (receipt-cumulative-gas-used receipt)
     (if previous-receipt
         (receipt-cumulative-gas-used previous-receipt)
         0)))

(defun eth-rpc-log-object
    (log block transaction transaction-index log-index)
  (let ((header (block-header block)))
    (list
     (cons "address" (address-to-hex (log-entry-address log)))
     (cons "topics" (mapcar #'hash32-to-hex
                            (log-entry-topics log)))
     (cons "data" (bytes-to-hex (log-entry-data log)))
     (cons "blockHash" (hash32-to-hex (block-hash block)))
     (cons "blockNumber"
           (quantity-to-hex (block-header-number header)))
     (cons "transactionHash"
           (hash32-to-hex (transaction-hash transaction)))
     (cons "transactionIndex" (quantity-to-hex transaction-index))
     (cons "logIndex" (quantity-to-hex log-index))
     (cons "removed" :false))))

(defun eth-rpc-receipt-object (location)
  (let* ((receipt (engine-transaction-location-receipt location))
         (block (engine-transaction-location-block location))
         (transaction (engine-transaction-location-transaction location))
         (index (engine-transaction-location-index location)))
    (when receipt
      (let* ((header (block-header block))
             (previous-receipt
               (when (plusp index)
                 (nth (1- index) (block-receipts block))))
             (from (or (transaction-sender transaction)
                       (zero-address)))
             (logs
               (loop for log in (receipt-logs receipt)
                     for log-index
                       from (engine-transaction-location-log-index-start
                             location)
                     collect (eth-rpc-log-object
                              log block transaction index log-index))))
        (append
         (list
          (cons "transactionHash"
                (hash32-to-hex (transaction-hash transaction)))
          (cons "transactionIndex" (quantity-to-hex index))
          (cons "blockHash" (hash32-to-hex (block-hash block)))
          (cons "blockNumber"
                (quantity-to-hex (block-header-number header)))
          (cons "from" (address-to-hex from))
          (cons "to"
                (eth-rpc-address-or-null
                 (nth-value 3
                            (eth-rpc-transaction-core-fields
                             transaction))))
          (cons "cumulativeGasUsed"
                (quantity-to-hex
                 (receipt-cumulative-gas-used receipt)))
          (cons "gasUsed"
                (quantity-to-hex
                 (eth-rpc-receipt-gas-used receipt previous-receipt)))
          (cons "contractAddress"
                (eth-rpc-address-or-null
                 (eth-rpc-contract-creation-address transaction from)))
          (cons "logs" logs)
          (cons "logsBloom"
                (bytes-to-hex
                 (bloom-bytes
                  (receipt-bloom (receipt-logs receipt)))))
          (cons "type" (quantity-to-hex (transaction-type transaction)))
          (cons "effectiveGasPrice"
                (quantity-to-hex
                 (eth-rpc-transaction-gas-price transaction header))))
         (if (receipt-post-state receipt)
             (list (cons "root"
                         (bytes-to-hex (receipt-post-state receipt))))
             (list (cons "status"
                         (quantity-to-hex (receipt-status receipt))))))))))

(defun eth-rpc-block-receipts-object (block)
  (when (and block
             (= (length (block-transactions block))
                (length (block-receipts block))))
    (loop with log-index-start = 0
          for transaction in (block-transactions block)
          for receipt in (block-receipts block)
          for index from 0
          for location = (make-engine-transaction-location
                          :block block
                          :index index
                          :transaction transaction
                          :receipt receipt
                          :log-index-start log-index-start)
          collect (prog1 (eth-rpc-receipt-object location)
                    (incf log-index-start
                          (length (receipt-logs receipt)))))))

(defun eth-rpc-json-array (items)
  (if items
      items
      (make-array 0)))

(defun eth-rpc-address= (left right)
  (and left
       right
       (bytes= (address-bytes left) (address-bytes right))))

(defun eth-rpc-log-address-match-p (log addresses)
  (or (null addresses)
      (some (lambda (address)
              (eth-rpc-address= (log-entry-address log) address))
            addresses)))

(defun eth-rpc-log-topics-match-p (log topic-filters)
  (let ((topics (log-entry-topics log)))
    (loop for slot in topic-filters
          for index from 0
          always (or (null slot)
                     (and (< index (length topics))
                          (some (lambda (topic)
                                  (hash32= (nth index topics) topic))
                                slot))))))

(defun eth-rpc-log-filter-object (params method)
  (unless (= 1 (length params))
    (block-validation-fail "~A params must contain exactly one filter"
                           method))
  (let ((filter (first params)))
    (unless (or (null filter) (json-object-p filter))
      (block-validation-fail "~A filter must be an object" method))
    filter))

(defun eth-rpc-log-filter-addresses (filter method)
  (let ((value (genesis-object-field filter "address")))
    (cond
      ((null value) nil)
      ((stringp value)
       (list (eth-rpc-address-param value method "address")))
      ((listp value)
       (mapcar (lambda (address)
                 (unless (stringp address)
                   (block-validation-fail
                    "~A address filter entries must be addresses" method))
                 (eth-rpc-address-param address method "address"))
               value))
      (t
       (block-validation-fail
        "~A address filter must be an address or address array" method)))))

(defun eth-rpc-log-filter-topic (value method)
  (cond
    ((null value) nil)
    ((stringp value)
     (list (eth-rpc-hash-param (list value) method "topic")))
    ((listp value)
     (mapcar (lambda (topic)
               (unless (stringp topic)
                 (block-validation-fail
                  "~A topic filter entries must be topics" method))
               (eth-rpc-hash-param (list topic) method "topic"))
             value))
    (t
     (block-validation-fail
      "~A topic filter slots must be null, a topic, or topic array" method))))

(defun eth-rpc-log-filter-topics (filter method)
  (let ((topics (genesis-object-field filter "topics")))
    (cond
      ((null topics) nil)
      ((listp topics)
       (mapcar (lambda (topic)
                 (eth-rpc-log-filter-topic topic method))
               topics))
      (t
       (block-validation-fail
        "~A topics filter must be an array" method)))))

(defun eth-rpc-log-filter-blocks (filter store method)
  (if (genesis-object-field-present-p filter "blockHash")
      (progn
        (when (or (genesis-object-field-present-p filter "fromBlock")
                  (genesis-object-field-present-p filter "toBlock"))
          (block-validation-fail
           "~A blockHash cannot be combined with fromBlock or toBlock"
           method))
        (let ((block-hash (eth-rpc-hash-param
                           (list (genesis-object-field filter "blockHash"))
                           method
                           "block hash")))
          (let ((block (chain-store-known-block store block-hash)))
            (if block
                (list block)
                '()))))
      (let* ((from-number (eth-rpc-block-number-param
                           (list (or (genesis-object-field filter "fromBlock")
                                     "earliest"))
                           store
                           method))
             (to-number (eth-rpc-block-number-param
                         (list (or (genesis-object-field filter "toBlock")
                                   "latest"))
                         store
                         method)))
        (when (> from-number to-number)
          (block-validation-fail
           "~A fromBlock must be less than or equal to toBlock" method))
        (loop for number from from-number to to-number
              for block = (chain-store-block-by-number store number)
              when block
                collect block))))

(defun eth-rpc-block-logs-object (block addresses topic-filters)
  (when (and block
             (= (length (block-transactions block))
                (length (block-receipts block))))
    (loop with log-index-start = 0
          for transaction in (block-transactions block)
          for receipt in (block-receipts block)
          for transaction-index from 0
          append (loop for log in (receipt-logs receipt)
                       for log-index from log-index-start
                       when (and (eth-rpc-log-address-match-p log addresses)
                                 (eth-rpc-log-topics-match-p
                                  log topic-filters))
                         collect (eth-rpc-log-object
                                  log
                                  block
                                  transaction
                                  transaction-index
                                  log-index))
          do (incf log-index-start (length (receipt-logs receipt))))))

(defun eth-rpc-filter-logs (filter store method)
  (let* ((addresses (eth-rpc-log-filter-addresses filter method))
         (topic-filters (eth-rpc-log-filter-topics filter method))
         (blocks (eth-rpc-log-filter-blocks filter store method))
         (logs (loop for block in blocks
                     append (eth-rpc-block-logs-object
                             block addresses topic-filters))))
    (eth-rpc-json-array logs)))

(defun eth-rpc-log-filter-range-bounds (filter store method)
  (unless (genesis-object-field-present-p filter "blockHash")
    (values
     (eth-rpc-block-number-param
      (list (or (genesis-object-field filter "fromBlock") "earliest"))
      store
      method)
     (eth-rpc-block-number-param
      (list (or (genesis-object-field filter "toBlock") "latest"))
      store
      method))))

(defun eth-rpc-log-filter-with-range (filter from-number to-number)
  (append
   (remove-if (lambda (entry)
                (member (car entry) '("fromBlock" "toBlock" "blockHash")
                        :test #'string=))
              filter)
   (list (cons "fromBlock" (quantity-to-hex from-number))
         (cons "toBlock" (quantity-to-hex to-number)))))

(defun engine-log-filter-changes (log-filter store method)
  (let ((criteria (engine-log-filter-criteria log-filter)))
    (if (genesis-object-field-present-p criteria "blockHash")
        (if (engine-log-filter-block-hash-consumed-p log-filter)
            (eth-rpc-json-array '())
            (prog1 (eth-rpc-filter-logs criteria store method)
              (setf (engine-log-filter-block-hash-consumed-p log-filter) t)))
        (multiple-value-bind (from-number to-number)
            (eth-rpc-log-filter-range-bounds criteria store method)
          (let* ((cursor (engine-log-filter-last-block-number log-filter))
                 (change-from (if cursor
                                  (max from-number (1+ cursor))
                                  from-number)))
            (prog1
                (if (> change-from to-number)
                    (eth-rpc-json-array '())
                    (eth-rpc-filter-logs
                     (eth-rpc-log-filter-with-range
                      criteria change-from to-number)
                     store
                     method))
              (setf (engine-log-filter-last-block-number log-filter)
                    (max (or cursor 0) to-number))))))))

(defun engine-block-filter-changes (block-filter store)
  (let* ((cursor (engine-block-filter-last-block-number block-filter))
         (latest (chain-store-head-number store))
         (hashes (loop for number from (1+ cursor) to latest
                       for block =
                         (chain-store-block-by-number store number)
                       when block
                         collect (hash32-to-hex (block-hash block)))))
    (prog1 (eth-rpc-json-array hashes)
      (setf (engine-block-filter-last-block-number block-filter) latest))))

(defun engine-pending-transaction-filter-changes (pending-filter)
  (let ((hashes (engine-pending-transaction-filter-hashes pending-filter)))
    (prog1 (eth-rpc-json-array (mapcar #'hash32-to-hex hashes))
      (setf (engine-pending-transaction-filter-hashes pending-filter) nil))))

(defun engine-rpc-handle-eth-get-logs (params store)
  (let* ((method "eth_getLogs")
         (filter (eth-rpc-log-filter-object params method)))
    (eth-rpc-filter-logs filter store method)))

(defun engine-rpc-handle-eth-new-filter (params store)
  (let* ((method "eth_newFilter")
         (filter (eth-rpc-log-filter-object params method)))
    (eth-rpc-log-filter-addresses filter method)
    (eth-rpc-log-filter-topics filter method)
    (eth-rpc-log-filter-blocks filter store method)
    (quantity-to-hex
     (engine-payload-store-put-log-filter store filter))))

(defun engine-rpc-handle-eth-new-block-filter (params store)
  (when params
    (block-validation-fail "eth_newBlockFilter params must be empty"))
  (quantity-to-hex
   (engine-payload-store-put-block-filter store)))

(defun engine-rpc-handle-eth-new-pending-transaction-filter (params store)
  (when params
    (block-validation-fail
     "eth_newPendingTransactionFilter params must be empty"))
  (quantity-to-hex
   (engine-payload-store-put-pending-transaction-filter store)))

(defun eth-rpc-filter-id-param (params method)
  (unless (= 1 (length params))
    (block-validation-fail "~A params must contain exactly one filter id"
                           method))
  (engine-rpc-quantity-param params 0 "filter id" method))

(defun engine-rpc-handle-eth-get-filter-logs (params store)
  (let* ((method "eth_getFilterLogs")
         (id (eth-rpc-filter-id-param params method))
         (log-filter (engine-payload-store-log-filter store id)))
    (unless (typep log-filter 'engine-log-filter)
      (block-validation-fail "~A filter not found" method))
    (eth-rpc-filter-logs
     (engine-log-filter-criteria log-filter) store method)))

(defun engine-rpc-handle-eth-get-filter-changes (params store)
  (let* ((method "eth_getFilterChanges")
         (id (eth-rpc-filter-id-param params method))
         (filter (engine-payload-store-log-filter store id)))
    (cond
      ((typep filter 'engine-log-filter)
       (engine-log-filter-changes filter store method))
      ((typep filter 'engine-block-filter)
       (engine-block-filter-changes filter store))
      ((typep filter 'engine-pending-transaction-filter)
       (engine-pending-transaction-filter-changes filter))
      (t
       (block-validation-fail "~A filter not found" method)))))

(defun engine-rpc-handle-eth-uninstall-filter (params store)
  (let* ((method "eth_uninstallFilter")
         (id (eth-rpc-filter-id-param params method)))
    (if (engine-payload-store-uninstall-log-filter store id)
        t
        :false)))

(defun engine-rpc-handle-eth-get-raw-transaction-by-block-number-and-index
    (params store)
  (let* ((number (eth-rpc-block-number-param
                  (list (first params)) store
                  "eth_getRawTransactionByBlockNumberAndIndex"))
         (index (eth-rpc-transaction-index-param
                 params "eth_getRawTransactionByBlockNumberAndIndex"))
         (block (chain-store-block-by-number store number)))
    (eth-rpc-raw-transaction-by-index block index)))

(defun engine-rpc-handle-eth-get-raw-transaction-by-block-hash-and-index
    (params store)
  (let* ((hash (eth-rpc-hash-param
                (list (first params))
                "eth_getRawTransactionByBlockHashAndIndex"
                "block hash"))
         (index (eth-rpc-transaction-index-param
                 params "eth_getRawTransactionByBlockHashAndIndex"))
         (block (chain-store-known-block store hash)))
    (eth-rpc-raw-transaction-by-index block index)))

(defun engine-rpc-handle-eth-get-raw-transaction-by-hash (params store)
  (let* ((hash (eth-rpc-hash-param
                params "eth_getRawTransactionByHash" "transaction hash"))
         (location (chain-store-transaction-location store hash)))
    (or (eth-rpc-raw-transaction-from-location location)
        (eth-rpc-raw-transaction
         (engine-payload-store-pending-transaction store hash)))))

(defun engine-rpc-handle-eth-send-raw-transaction (params store config)
  (unless (= 1 (length params))
    (block-validation-fail
     "eth_sendRawTransaction params must contain exactly one transaction"))
  (let* ((raw-bytes
            (engine-rpc-bytes
             (first params)
             "eth_sendRawTransaction transaction"))
         (transaction (transaction-from-encoding raw-bytes))
         (hash (transaction-hash transaction)))
    (validate-set-code-transaction-fields transaction)
    (eth-rpc-validate-set-code-authorization-signatures transaction)
    (unless (transaction-sender
             transaction
             :expected-chain-id (chain-config-chain-id config))
      (block-validation-fail
       "eth_sendRawTransaction transaction sender recovery failed"))
    (unless (chain-store-transaction-location store hash)
      (engine-payload-store-put-pending-transaction store transaction))
    (hash32-to-hex hash)))

(defun engine-rpc-handle-eth-pending-transactions (params store)
  (when params
    (block-validation-fail "eth_pendingTransactions params must be empty"))
  (eth-rpc-pending-transaction-objects
   (engine-payload-store-pending-transactions store)))

(defun engine-rpc-handle-txpool-status (params store)
  (when params
    (block-validation-fail "txpool_status params must be empty"))
  (list
   (cons "pending"
         (quantity-to-hex
          (engine-payload-store-pending-transaction-count store)))
   (cons "queued" (quantity-to-hex 0))))

(defun engine-rpc-handle-txpool-content (params store)
  (when params
    (block-validation-fail "txpool_content params must be empty"))
  (list
   (cons "pending"
         (txpool-rpc-indexed-content-transactions
          (engine-payload-store-pending-transactions-by-sender store)))
   (cons "queued" +json-empty-object+)))

(defun engine-rpc-handle-txpool-content-from (params store)
  (unless (= 1 (length params))
    (block-validation-fail
     "txpool_contentFrom params must contain exactly one address"))
  (let ((address (eth-rpc-address-param
                  (first params) "txpool_contentFrom" "address")))
    (list
     (cons "pending"
           (txpool-rpc-indexed-nonce-transactions
            (gethash
             (address-to-hex address)
             (engine-payload-store-pending-transactions-by-sender store))
            #'eth-rpc-pending-transaction-object))
     (cons "queued" +json-empty-object+))))

(defun engine-rpc-handle-txpool-inspect (params store)
  (when params
    (block-validation-fail "txpool_inspect params must be empty"))
  (list
   (cons "pending"
         (txpool-rpc-indexed-inspect-transactions
          (engine-payload-store-pending-transactions-by-sender store)))
   (cons "queued" +json-empty-object+)))

(defun engine-rpc-handle-eth-get-transaction-by-block-number-and-index
    (params store)
  (let* ((number (eth-rpc-block-number-param
                  (list (first params)) store
                  "eth_getTransactionByBlockNumberAndIndex"))
         (index (eth-rpc-transaction-index-param
                 params "eth_getTransactionByBlockNumberAndIndex"))
         (block (chain-store-block-by-number store number)))
    (eth-rpc-transaction-by-index block index)))

(defun engine-rpc-handle-eth-get-transaction-by-block-hash-and-index
    (params store)
  (let* ((hash (eth-rpc-hash-param
                (list (first params))
                "eth_getTransactionByBlockHashAndIndex"
                "block hash"))
         (index (eth-rpc-transaction-index-param
                 params "eth_getTransactionByBlockHashAndIndex"))
         (block (chain-store-known-block store hash)))
    (eth-rpc-transaction-by-index block index)))

(defun engine-rpc-handle-eth-get-transaction-by-hash (params store)
  (let* ((hash (eth-rpc-hash-param
                params "eth_getTransactionByHash" "transaction hash"))
         (location (chain-store-transaction-location store hash)))
    (or (eth-rpc-transaction-from-location location)
        (eth-rpc-pending-transaction-object
         (engine-payload-store-pending-transaction store hash)))))

(defun engine-rpc-handle-eth-get-transaction-receipt (params store)
  (let* ((hash (eth-rpc-hash-param
                params "eth_getTransactionReceipt" "transaction hash"))
         (location (chain-store-transaction-location store hash)))
    (when location
      (eth-rpc-receipt-object location))))

(defun engine-rpc-handle-eth-get-block-receipts (params store)
  (let ((block (eth-rpc-block-param params store "eth_getBlockReceipts")))
    (eth-rpc-block-receipts-object block)))

(defconstant +engine-rpc-error-unknown-payload+ -38001)
(defconstant +engine-rpc-error-invalid-forkchoice-state+ -38002)
(defconstant +engine-rpc-error-invalid-payload-attributes+ -38003)
(defconstant +engine-rpc-error-too-large-request+ -38004)

(define-condition engine-rpc-error (error)
  ((code :initarg :code :reader engine-rpc-error-code)
   (message :initarg :message :reader engine-rpc-error-message))
  (:report (lambda (condition stream)
             (format stream "~A" (engine-rpc-error-message condition)))))

(defun engine-rpc-fail (code message)
  (error 'engine-rpc-error :code code :message message))

(defun engine-rpc-payload-id-from-value (value)
  (unless (stringp value)
    (block-validation-fail "engine_getPayload payload id must be a hex string"))
  (let ((payload-id
          (handler-case
              (hex-to-bytes value)
            (error ()
              (block-validation-fail
               "engine_getPayload payload id must be hex bytes")))))
    (unless (= 8 (length payload-id))
      (block-validation-fail "engine_getPayload payload id must be 8 bytes"))
    payload-id))

(defun engine-rpc-prepared-payload (params store method)
  (unless (and (listp params) params)
    (block-validation-fail "~A params must include payload id" method))
  (let* ((payload-id
           (engine-rpc-payload-id-from-value
            (engine-rpc-required-param
             params 0 "payloadId" method)))
         (prepared-payload
           (chain-store-prepared-payload store payload-id)))
    (unless prepared-payload
      (engine-rpc-fail +engine-rpc-error-unknown-payload+
                       "Unknown payload"))
    prepared-payload))

(defun engine-rpc-prepared-payload-envelope (prepared-payload)
  (block-to-executable-data
   (engine-prepared-payload-block prepared-payload)
   :blobs-bundle (engine-prepared-payload-blobs-bundle prepared-payload)))

(defun engine-rpc-handle-get-payload-v1 (params store)
  (let ((prepared-payload
          (engine-rpc-prepared-payload
           params store "engine_getPayloadV1")))
    (unless (= 1 (engine-prepared-payload-version prepared-payload))
      (block-validation-fail "payload id is not for engine_getPayloadV1"))
    (engine-rpc-executable-data-object
     (execution-payload-envelope-execution-payload
      (engine-rpc-prepared-payload-envelope prepared-payload)))))

(defun engine-rpc-handle-get-payload-v2 (params store)
  (let ((prepared-payload
          (engine-rpc-prepared-payload
           params store "engine_getPayloadV2")))
    (unless (member (engine-prepared-payload-version prepared-payload)
                    '(1 2))
      (block-validation-fail "payload id is not for engine_getPayloadV2"))
    (engine-rpc-execution-payload-envelope-object
     (engine-rpc-prepared-payload-envelope prepared-payload))))

(defun engine-rpc-handle-get-payload-v3 (params store)
  (let ((prepared-payload
          (engine-rpc-prepared-payload
           params store "engine_getPayloadV3")))
    (unless (= 3 (engine-prepared-payload-version prepared-payload))
      (block-validation-fail "payload id is not for engine_getPayloadV3"))
    (engine-rpc-execution-payload-envelope-object
     (engine-rpc-prepared-payload-envelope prepared-payload)
     :include-blobs-bundle-p t
     :include-override-p t)))

(defun engine-rpc-handle-get-payload-v4 (params store)
  (let ((prepared-payload
          (engine-rpc-prepared-payload
           params store "engine_getPayloadV4")))
    (unless (= 4 (engine-prepared-payload-version prepared-payload))
      (block-validation-fail "payload id is not for engine_getPayloadV4"))
    (engine-rpc-execution-payload-envelope-object
     (engine-rpc-prepared-payload-envelope prepared-payload)
     :include-blobs-bundle-p t
     :include-override-p t)))

(defun engine-rpc-handle-get-payload-v5 (params store)
  (let ((prepared-payload
          (engine-rpc-prepared-payload
           params store "engine_getPayloadV5")))
    (unless (= 5 (engine-prepared-payload-version prepared-payload))
      (block-validation-fail "payload id is not for engine_getPayloadV5"))
    (engine-rpc-execution-payload-envelope-object
     (engine-rpc-prepared-payload-envelope prepared-payload)
     :include-blobs-bundle-p t
     :include-override-p t)))

(defun engine-rpc-handle-get-payload-v6 (params store)
  (let ((prepared-payload
          (engine-rpc-prepared-payload
           params store "engine_getPayloadV6")))
    (unless (= 6 (engine-prepared-payload-version prepared-payload))
      (block-validation-fail "payload id is not for engine_getPayloadV6"))
    (engine-rpc-execution-payload-envelope-object
     (engine-rpc-prepared-payload-envelope prepared-payload)
     :include-blobs-bundle-p t
     :include-override-p t)))

(defconstant +engine-rpc-max-payload-bodies-request+ 1024)
(defconstant +engine-rpc-max-get-blobs-request+ 128)

(defun engine-rpc-get-blob-hashes-param (params method)
  (unless (and (listp params) params)
    (block-validation-fail
     "~A params must include blob versioned hashes" method))
  (engine-rpc-hash32-list
   (engine-rpc-required-param
    params 0 "blobVersionedHashes" method)
   "blobVersionedHashes"))

(defun engine-rpc-validate-get-blobs-request-size (hashes)
  (when (> (length hashes) +engine-rpc-max-get-blobs-request+)
    (engine-rpc-fail
     +engine-rpc-error-too-large-request+
     "The number of requested blobs must not exceed 128")))

(defun engine-rpc-handle-get-blobs-v1 (params store)
  (let ((hashes
          (engine-rpc-get-blob-hashes-param
           params "engine_getBlobsV1")))
    (engine-rpc-validate-get-blobs-request-size hashes)
    (mapcar (lambda (versioned-hash)
              (let ((blob-and-proofs
                      (engine-payload-store-blob-and-proofs-v1
                       store versioned-hash)))
                (when blob-and-proofs
                  (engine-rpc-blob-and-proof-v1-object blob-and-proofs))))
            hashes)))

(defun engine-rpc-handle-get-blobs-v2 (params store)
  (let* ((hashes
           (engine-rpc-get-blob-hashes-param
            params "engine_getBlobsV2"))
         (blobs
           (progn
             (engine-rpc-validate-get-blobs-request-size hashes)
             (mapcar (lambda (versioned-hash)
                       (engine-payload-store-blob-and-proofs-v2
                        store versioned-hash))
                     hashes))))
    (if (some #'null blobs)
        nil
        (mapcar #'engine-rpc-blob-and-proof-v2-object blobs))))

(defun engine-rpc-handle-get-blobs-v3 (params store)
  (let ((hashes
          (engine-rpc-get-blob-hashes-param
           params "engine_getBlobsV3")))
    (engine-rpc-validate-get-blobs-request-size hashes)
    (mapcar (lambda (versioned-hash)
              (let ((blob-and-proofs
                      (engine-payload-store-blob-and-proofs-v2
                       store versioned-hash)))
                (when blob-and-proofs
                  (engine-rpc-blob-and-proof-v2-object blob-and-proofs))))
            hashes)))

(defun engine-rpc-handle-get-payload-bodies-by-hash
    (params store method body-object-function)
  (unless (and (listp params) params)
    (block-validation-fail
     "~A params must include block hashes" method))
  (let ((hashes
          (engine-rpc-hash32-list
           (engine-rpc-required-param
            params 0 "blockHashes" method)
           "blockHashes")))
    (when (> (length hashes) +engine-rpc-max-payload-bodies-request+)
      (engine-rpc-fail
       +engine-rpc-error-too-large-request+
       "The number of requested bodies must not exceed 1024"))
    (mapcar (lambda (hash)
              (let ((block (chain-store-known-block store hash)))
                (when block
                  (funcall body-object-function block))))
            hashes)))

(defun engine-rpc-handle-get-payload-bodies-by-hash-v1 (params store)
  (engine-rpc-handle-get-payload-bodies-by-hash
   params store "engine_getPayloadBodiesByHashV1"
   #'engine-rpc-payload-body-v1-object))

(defun engine-rpc-handle-get-payload-bodies-by-hash-v2 (params store)
  (engine-rpc-handle-get-payload-bodies-by-hash
   params store "engine_getPayloadBodiesByHashV2"
   #'engine-rpc-payload-body-v2-object))

(defun engine-rpc-quantity-param (params index label method)
  (parse-genesis-quantity
   (engine-rpc-required-param params index label method)
   label
   :required-p t))

(defun engine-rpc-handle-get-payload-bodies-by-range
    (params store method body-object-function)
  (unless (and (listp params) params)
    (block-validation-fail
     "~A params must include start and count" method))
  (let ((start (engine-rpc-quantity-param
                params 0 "start" method))
        (count (engine-rpc-quantity-param
                params 1 "count" method)))
    (unless (and (plusp start) (plusp count))
      (block-validation-fail "start and count must be positive numbers"))
    (when (> count +engine-rpc-max-payload-bodies-request+)
      (engine-rpc-fail
       +engine-rpc-error-too-large-request+
       "The number of requested bodies must not exceed 1024"))
    (let* ((head (chain-store-head-number store))
           (last (min (+ start count -1) head)))
      (if (< last start)
          '()
          (loop for number from start to last
                collect
                (let ((block (chain-store-block-by-number store number)))
                  (when block
                    (funcall body-object-function block))))))))

(defun engine-rpc-handle-get-payload-bodies-by-range-v1 (params store)
  (engine-rpc-handle-get-payload-bodies-by-range
   params store "engine_getPayloadBodiesByRangeV1"
   #'engine-rpc-payload-body-v1-object))

(defun engine-rpc-handle-get-payload-bodies-by-range-v2 (params store)
  (engine-rpc-handle-get-payload-bodies-by-range
   params store "engine_getPayloadBodiesByRangeV2"
   #'engine-rpc-payload-body-v2-object))

(defun engine-rpc-handle-forkchoice-updated
    (params store method payload-version payload-attributes-parser)
  (unless (and (listp params) params)
    (block-validation-fail "~A params must include forkchoice state" method))
  (let ((state
          (engine-rpc-forkchoice-state-from-object
           (engine-rpc-required-param
            params 0 "forkchoiceState" method)))
        (payload-attributes
          (when (< 1 (length params))
            (second params))))
    (setf payload-attributes
          (when payload-attributes
            (funcall payload-attributes-parser payload-attributes)))
    (let ((status (engine-forkchoice-memory-status store state))
          (payload-id nil))
      (when (string= +payload-status-valid+
                     (payload-status-status status))
        (let ((checkpoint-error
                (or
                 (engine-forkchoice-checkpoint-error-message
                  store (forkchoice-state-finalized-block-hash state)
                  "finalized"
                  :head-hash (forkchoice-state-head-block-hash state))
                 (engine-forkchoice-checkpoint-error-message
                  store (forkchoice-state-safe-block-hash state)
                  "safe"
                  :head-hash (forkchoice-state-head-block-hash state)))))
          (when checkpoint-error
            (engine-rpc-fail
             +engine-rpc-error-invalid-forkchoice-state+
             checkpoint-error)))
        (chain-store-update-forkchoice-checkpoints store state)
        (chain-store-set-canonical-head
         store
         (forkchoice-state-head-block-hash state)))
      (when (and payload-attributes
                 (string= +payload-status-valid+
                          (payload-status-status status)))
        (let* ((head-hash (forkchoice-state-head-block-hash state))
               (parent-block
                 (chain-store-known-block store head-hash))
               (candidate-id
                 (engine-payload-id
                  payload-version head-hash payload-attributes)))
          (unless (chain-store-prepared-payload
                   store candidate-id)
            (chain-store-put-prepared-payload
             store
             (make-engine-prepared-payload
              :payload-id candidate-id
              :version payload-version
              :block
              (handler-case
                  (engine-build-empty-payload parent-block payload-attributes)
                (block-validation-error (condition)
                  (engine-rpc-fail
                   +engine-rpc-error-invalid-payload-attributes+
                   (block-validation-error-message condition)))))))
          (setf payload-id candidate-id)))
      (engine-rpc-forkchoice-response-object
       status
       :payload-id payload-id))))

(defun engine-rpc-handle-forkchoice-updated-v1 (params store)
  (engine-rpc-handle-forkchoice-updated
   params store "engine_forkchoiceUpdatedV1" 1
   (lambda (payload-attributes)
     (engine-rpc-validate-payload-attributes-v1
      payload-attributes :method "engine_forkchoiceUpdatedV1"))))

(defun engine-rpc-handle-forkchoice-updated-v2 (params store)
  (engine-rpc-handle-forkchoice-updated
   params store "engine_forkchoiceUpdatedV2" 2
   #'engine-rpc-validate-payload-attributes-v2))

(defun engine-rpc-handle-forkchoice-updated-v3 (params store)
  (engine-rpc-handle-forkchoice-updated
   params store "engine_forkchoiceUpdatedV3" 3
   #'engine-rpc-validate-payload-attributes-v3))

(defun engine-rpc-handle-forkchoice-updated-v4 (params store)
  (engine-rpc-handle-forkchoice-updated
   params store "engine_forkchoiceUpdatedV4" 4
   #'engine-rpc-validate-payload-attributes-v4))

(defun engine-rpc-response (id &key result error)
  (append (list (cons "jsonrpc" "2.0")
                (cons "id" id))
          (if error
              (list (cons "error" error))
              (list (cons "result" result)))))

(defun engine-rpc-error-object (code message)
  (list (cons "code" code)
        (cons "message" message)))

(defun engine-rpc-invalid-request-response ()
  (engine-rpc-response
   nil
   :error
   (engine-rpc-error-object -32600 "Invalid Request")))

(defun engine-rpc-handle-request
    (request store config &key import-function)
  (let ((id (and (listp request)
                 (genesis-object-field request "id"))))
    (handler-case
        (progn
          (unless (listp request)
            (block-validation-fail "JSON-RPC request must be an object"))
          (let* ((method (engine-rpc-required-field request "method"))
                 (params (or (genesis-object-field request "params") '()))
                 (version (and (stringp method)
                               (engine-rpc-new-payload-version method))))
            (unless (stringp method)
              (block-validation-fail "JSON-RPC method must be a string"))
            (unless (listp params)
              (block-validation-fail "JSON-RPC params must be a list"))
            (cond
              (version
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-new-payload
                 version params store config
                 :import-function import-function)))
              ((string= method "engine_exchangeCapabilities")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-exchange-capabilities params)))
              ((string= method "engine_forkchoiceUpdatedV1")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-forkchoice-updated-v1 params store)))
              ((string= method "engine_forkchoiceUpdatedV2")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-forkchoice-updated-v2 params store)))
              ((string= method "engine_forkchoiceUpdatedV3")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-forkchoice-updated-v3 params store)))
              ((string= method "engine_forkchoiceUpdatedV4")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-forkchoice-updated-v4 params store)))
              ((string= method "engine_getPayloadV1")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-get-payload-v1 params store)))
              ((string= method "engine_getPayloadV2")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-get-payload-v2 params store)))
              ((string= method "engine_getPayloadV3")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-get-payload-v3 params store)))
              ((string= method "engine_getPayloadV4")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-get-payload-v4 params store)))
              ((string= method "engine_getPayloadV5")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-get-payload-v5 params store)))
              ((string= method "engine_getPayloadV6")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-get-payload-v6 params store)))
              ((string= method "engine_getPayloadBodiesByHashV1")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-get-payload-bodies-by-hash-v1
                 params store)))
              ((string= method "engine_getPayloadBodiesByHashV2")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-get-payload-bodies-by-hash-v2
                 params store)))
              ((string= method "engine_getPayloadBodiesByRangeV1")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-get-payload-bodies-by-range-v1
                 params store)))
              ((string= method "engine_getPayloadBodiesByRangeV2")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-get-payload-bodies-by-range-v2
                 params store)))
              ((string= method "engine_getBlobsV1")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-get-blobs-v1 params store)))
              ((string= method "engine_getBlobsV2")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-get-blobs-v2 params store)))
              ((string= method "engine_getBlobsV3")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-get-blobs-v3 params store)))
              ((string= method "engine_getClientVersionV1")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-get-client-version params)))
              ((string= method "engine_exchangeTransitionConfigurationV1")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-exchange-transition-configuration
                 params config)))
              ((string= method "web3_clientVersion")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-web3-client-version params)))
              ((string= method "web3_sha3")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-web3-sha3 params)))
              ((string= method "net_version")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-net-version params config)))
              ((string= method "net_listening")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-net-listening params)))
              ((string= method "net_peerCount")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-net-peer-count params)))
              ((string= method "eth_chainId")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-chain-id params config)))
              ((string= method "eth_blockNumber")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-block-number params store)))
              ((string= method "eth_protocolVersion")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-protocol-version params)))
              ((string= method "eth_syncing")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-syncing params)))
              ((string= method "eth_accounts")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-accounts params)))
              ((string= method "eth_coinbase")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-coinbase params)))
              ((string= method "eth_mining")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-mining params)))
              ((string= method "eth_hashrate")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-hashrate params)))
              ((string= method "eth_gasPrice")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-gas-price params store)))
              ((string= method "eth_maxPriorityFeePerGas")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-max-priority-fee-per-gas
                 params store)))
              ((string= method "eth_baseFee")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-base-fee params store config)))
              ((string= method "eth_blobBaseFee")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-blob-base-fee params store config)))
              ((string= method "eth_feeHistory")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-fee-history params store config)))
              ((string= method "eth_getBalance")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-balance params store)))
              ((string= method "eth_getTransactionCount")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-transaction-count params store)))
              ((string= method "eth_getCode")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-code params store)))
              ((string= method "eth_getStorageAt")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-storage-at params store)))
              ((string= method "eth_getProof")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-proof params store)))
              ((string= method "eth_getHeaderByNumber")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-header-by-number params store)))
              ((string= method "eth_getHeaderByHash")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-header-by-hash params store)))
              ((string= method "eth_getBlockByNumber")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-block-by-number params store)))
              ((string= method "eth_getBlockByHash")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-block-by-hash params store)))
              ((string= method "eth_getBlockTransactionCountByNumber")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-block-transaction-count-by-number
                 params store)))
              ((string= method "eth_getBlockTransactionCountByHash")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-block-transaction-count-by-hash
                 params store)))
              ((string= method "eth_getUncleCountByBlockNumber")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-uncle-count-by-number
                 params store)))
              ((string= method "eth_getUncleCountByBlockHash")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-uncle-count-by-hash
                 params store)))
              ((string= method "eth_getUncleByBlockNumberAndIndex")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-uncle-by-block-number-and-index
                 params store)))
              ((string= method "eth_getUncleByBlockHashAndIndex")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-uncle-by-block-hash-and-index
                 params store)))
              ((string= method
                        "eth_getTransactionByBlockNumberAndIndex")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-transaction-by-block-number-and-index
                 params store)))
              ((string= method
                        "eth_getTransactionByBlockHashAndIndex")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-transaction-by-block-hash-and-index
                 params store)))
              ((string= method "eth_getTransactionByHash")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-transaction-by-hash
                 params store)))
              ((string= method "eth_getTransactionReceipt")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-transaction-receipt
                 params store)))
              ((string= method "eth_getBlockReceipts")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-block-receipts
                 params store)))
              ((string= method "eth_getLogs")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-logs params store)))
              ((string= method "eth_newFilter")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-new-filter params store)))
              ((string= method "eth_newBlockFilter")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-new-block-filter params store)))
              ((string= method "eth_newPendingTransactionFilter")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-new-pending-transaction-filter
                 params store)))
              ((string= method "eth_getFilterLogs")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-filter-logs params store)))
              ((string= method "eth_getFilterChanges")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-filter-changes params store)))
              ((string= method "eth_uninstallFilter")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-uninstall-filter params store)))
              ((string= method
                        "eth_getRawTransactionByBlockNumberAndIndex")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-raw-transaction-by-block-number-and-index
                 params store)))
              ((string= method
                        "eth_getRawTransactionByBlockHashAndIndex")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-raw-transaction-by-block-hash-and-index
                 params store)))
              ((string= method "eth_getRawTransactionByHash")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-get-raw-transaction-by-hash
                 params store)))
              ((string= method "eth_sendRawTransaction")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-send-raw-transaction
                 params store config)))
              ((string= method "eth_pendingTransactions")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-eth-pending-transactions
                 params store)))
              ((string= method "txpool_status")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-txpool-status params store)))
              ((string= method "txpool_content")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-txpool-content params store)))
              ((string= method "txpool_contentFrom")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-txpool-content-from params store)))
              ((string= method "txpool_inspect")
               (engine-rpc-response
                id
                :result
                (engine-rpc-handle-txpool-inspect params store)))
              (t
               (engine-rpc-response
                id
                :error
                (engine-rpc-error-object -32601 "Method not found"))))))
      (engine-rpc-error (condition)
        (engine-rpc-response
         id
         :error
         (engine-rpc-error-object
          (engine-rpc-error-code condition)
          (engine-rpc-error-message condition))))
      (block-validation-error (condition)
        (engine-rpc-response
         id
         :error
         (engine-rpc-error-object
          -32602
          (block-validation-error-message condition)))))))

(defun engine-rpc-handle-request-value
    (request store config &key import-function)
  (cond
    ((json-object-p request)
     (engine-rpc-handle-request request store config
                                :import-function import-function))
    ((and (listp request) request)
     (mapcar (lambda (item)
               (if (json-object-p item)
                   (engine-rpc-handle-request
                    item store config
                    :import-function import-function)
                   (engine-rpc-invalid-request-response)))
             request))
    (t (engine-rpc-invalid-request-response))))

(defun engine-rpc-handle-request-string
    (request-json store config &key import-function)
  (engine-rpc-handle-request-value
   (parse-json request-json)
   store
   config
   :import-function import-function))

(defun engine-rpc-handle-request-json
    (request-json store config &key import-function)
  (json-encode
   (engine-rpc-handle-request-string
    request-json store config
    :import-function import-function)))

(defparameter +engine-rpc-http-accepted-content-types+
  '("application/json" "application/json-rpc" "application/jsonrequest"))

(defparameter +engine-rpc-default-http-host+ "localhost")
(defconstant +engine-rpc-default-http-port+ 8551)

(defconstant +engine-rpc-jwt-expiry-seconds+ 60)

(defparameter +engine-rpc-base64url-alphabet+
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

(defstruct (engine-rpc-http-service
            (:constructor %make-engine-rpc-http-service
                (&key host port store config jwt-secret now-provider
                      import-function)))
  host
  port
  store
  config
  jwt-secret
  now-provider
  import-function)

(defstruct (engine-rpc-http-connection
            (:constructor %make-engine-rpc-http-connection
                (&key input-stream output-stream close-function)))
  input-stream
  output-stream
  close-function)

(defstruct (engine-rpc-http-listener
            (:constructor %make-engine-rpc-http-listener
                (&key endpoint accept-function close-function)))
  endpoint
  accept-function
  close-function)

(defun engine-rpc-default-import-function ()
  (let* ((package (find-package "ETHEREUM-LISP.EXECUTION"))
         (symbol (and package
                      (find-symbol "EXECUTE-AND-COMMIT-ENGINE-PAYLOAD"
                                   package))))
    (when (and symbol (fboundp symbol))
      (symbol-function symbol))))

(defun make-engine-rpc-http-service
    (&key
       (host +engine-rpc-default-http-host+)
       (port +engine-rpc-default-http-port+)
       (store (make-engine-payload-memory-store))
       (config (make-chain-config))
       jwt-secret
       (now-provider (lambda () 0))
       (import-function (engine-rpc-default-import-function)))
  (unless (stringp host)
    (block-validation-fail "Engine RPC HTTP host must be a string"))
  (unless (and (integerp port) (<= 0 port 65535))
    (block-validation-fail "Engine RPC HTTP port must be between 0 and 65535"))
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail
     "Engine RPC HTTP store must be engine-payload-memory-store"))
  (unless (typep config 'chain-config)
    (block-validation-fail "Engine RPC HTTP config must be chain-config"))
  (when (and jwt-secret
             (not (and (byte-vector-p jwt-secret)
                       (= 32 (length jwt-secret)))))
    (block-validation-fail "Engine JWT secret must be 32 bytes"))
  (unless (functionp now-provider)
    (block-validation-fail "Engine RPC HTTP now provider must be a function"))
  (when (and import-function
             (not (functionp import-function)))
    (block-validation-fail "Engine RPC HTTP import function must be a function"))
  (%make-engine-rpc-http-service
   :host host
   :port port
   :store store
   :config config
   :jwt-secret jwt-secret
   :now-provider now-provider
   :import-function import-function))

(defun engine-rpc-http-service-endpoint (service)
  (unless (typep service 'engine-rpc-http-service)
    (block-validation-fail
     "Engine RPC HTTP service must be engine-rpc-http-service"))
  (format nil "~A:~D"
          (engine-rpc-http-service-host service)
          (engine-rpc-http-service-port service)))

(defun make-engine-rpc-http-connection
    (&key input-stream output-stream (close-function (lambda () nil)))
  (unless (input-stream-p input-stream)
    (block-validation-fail
     "Engine RPC HTTP connection input stream must be readable"))
  (unless (output-stream-p output-stream)
    (block-validation-fail
     "Engine RPC HTTP connection output stream must be writable"))
  (unless (functionp close-function)
    (block-validation-fail
     "Engine RPC HTTP connection close function must be a function"))
  (%make-engine-rpc-http-connection
   :input-stream input-stream
   :output-stream output-stream
   :close-function close-function))

(defun make-engine-rpc-http-listener
    (&key endpoint accept-function (close-function (lambda () nil)))
  (unless (stringp endpoint)
    (block-validation-fail "Engine RPC HTTP listener endpoint must be a string"))
  (unless (functionp accept-function)
    (block-validation-fail
     "Engine RPC HTTP listener accept function must be a function"))
  (unless (functionp close-function)
    (block-validation-fail
     "Engine RPC HTTP listener close function must be a function"))
  (%make-engine-rpc-http-listener
   :endpoint endpoint
   :accept-function accept-function
   :close-function close-function))

(defun engine-rpc-http-listener-accept (listener)
  (unless (typep listener 'engine-rpc-http-listener)
    (block-validation-fail
     "Engine RPC HTTP listener must be engine-rpc-http-listener"))
  (let ((connection
          (funcall (engine-rpc-http-listener-accept-function listener))))
    (when connection
      (unless (typep connection 'engine-rpc-http-connection)
        (block-validation-fail
         "Engine RPC HTTP listener accept function returned non-connection")))
    connection))

(defun engine-rpc-http-connection-close (connection)
  (unless (typep connection 'engine-rpc-http-connection)
    (block-validation-fail
     "Engine RPC HTTP connection must be engine-rpc-http-connection"))
  (funcall (engine-rpc-http-connection-close-function connection)))

(defun engine-rpc-http-listener-close (listener)
  (unless (typep listener 'engine-rpc-http-listener)
    (block-validation-fail
     "Engine RPC HTTP listener must be engine-rpc-http-listener"))
  (funcall (engine-rpc-http-listener-close-function listener)))

(defun engine-rpc-http-trim (string)
  (string-trim '(#\Space #\Tab #\Return #\Newline) string))

(defun engine-rpc-string-prefix-p (prefix string)
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun engine-rpc-base64url-encode (bytes)
  (let ((bytes (ensure-byte-vector bytes)))
    (with-output-to-string (stream)
      (loop for index from 0 below (length bytes) by 3
            for remaining = (- (length bytes) index)
            for b0 = (aref bytes index)
            for b1 = (if (>= remaining 2) (aref bytes (1+ index)) 0)
            for b2 = (if (>= remaining 3) (aref bytes (+ index 2)) 0)
            for value = (logior (ash b0 16) (ash b1 8) b2)
            do (write-char
                (aref +engine-rpc-base64url-alphabet+
                      (ldb (byte 6 18) value))
                stream)
               (write-char
                (aref +engine-rpc-base64url-alphabet+
                      (ldb (byte 6 12) value))
                stream)
               (when (>= remaining 2)
                 (write-char
                  (aref +engine-rpc-base64url-alphabet+
                        (ldb (byte 6 6) value))
                  stream))
               (when (>= remaining 3)
                 (write-char
                  (aref +engine-rpc-base64url-alphabet+
                        (ldb (byte 6 0) value))
                  stream))))))

(defun engine-rpc-base64url-value (char)
  (let ((position (position char +engine-rpc-base64url-alphabet+)))
    (unless position
      (block-validation-fail "JWT contains invalid base64url data"))
    position))

(defun engine-rpc-base64url-decode (string)
  (when (= (mod (length string) 4) 1)
    (block-validation-fail "JWT contains invalid base64url length"))
  (let ((bytes '())
        (accumulator 0)
        (bits 0))
    (loop for char across string
          for value = (engine-rpc-base64url-value char)
          do (setf accumulator (logior (ash accumulator 6) value)
                   bits (+ bits 6))
             (loop while (>= bits 8)
                   do (decf bits 8)
                      (push (logand #xff (ash accumulator (- bits))) bytes)))
    (ensure-byte-vector (nreverse bytes))))

(defun engine-rpc-hmac-sha256 (key message)
  (let* ((block-size 64)
         (key (ensure-byte-vector key))
         (message (ensure-byte-vector message))
         (short-key (if (> (length key) block-size)
                        (sha256 key)
                        key))
         (padded-key (make-byte-vector block-size)))
    (replace padded-key short-key)
    (let ((inner-pad (make-byte-vector block-size))
          (outer-pad (make-byte-vector block-size)))
      (loop for index below block-size
            for byte = (aref padded-key index)
            do (setf (aref inner-pad index) (logxor byte #x36)
                     (aref outer-pad index) (logxor byte #x5c)))
      (sha256 outer-pad (sha256 inner-pad message)))))

(defun engine-rpc-constant-time-bytes= (left right)
  (let ((left (ensure-byte-vector left))
        (right (ensure-byte-vector right)))
    (and (= (length left) (length right))
         (zerop
          (loop for index below (length left)
                for difference = (logxor (aref left index)
                                         (aref right index))
                then (logior difference
                             (logxor (aref left index)
                                     (aref right index)))
                finally (return (or difference 0)))))))

(defun engine-rpc-jwt-signature (secret signing-input)
  (engine-rpc-base64url-encode
   (engine-rpc-hmac-sha256 secret (ascii-to-bytes signing-input))))

(defun engine-rpc-make-jwt-token (secret issued-at &key expires-at)
  (unless (and (byte-vector-p secret) (= 32 (length secret)))
    (block-validation-fail "Engine JWT secret must be 32 bytes"))
  (let* ((header (engine-rpc-base64url-encode
                  (ascii-to-bytes "{\"alg\":\"HS256\",\"typ\":\"JWT\"}")))
         (payload
           (engine-rpc-base64url-encode
            (ascii-to-bytes
             (if expires-at
                 (format nil "{\"iat\":~D,\"exp\":~D}" issued-at expires-at)
                 (format nil "{\"iat\":~D}" issued-at)))))
         (signing-input (concatenate 'string header "." payload))
         (signature (engine-rpc-jwt-signature secret signing-input)))
    (concatenate 'string signing-input "." signature)))

(defun engine-rpc-token-parts (token)
  (let* ((first-dot (position #\. token))
         (second-dot (and first-dot (position #\. token :start (1+ first-dot)))))
    (unless (and first-dot second-dot
                 (not (position #\. token :start (1+ second-dot))))
      (block-validation-fail "JWT must contain three parts"))
    (values (subseq token 0 first-dot)
            (subseq token (1+ first-dot) second-dot)
            (subseq token (1+ second-dot)))))

(defun engine-rpc-jwt-object (part label)
  (let ((decoded (bytes-to-ascii (engine-rpc-base64url-decode part))))
    (handler-case
        (let ((object (parse-json decoded)))
          (unless (json-object-p object)
            (block-validation-fail "JWT ~A must be a JSON object" label))
          object)
      (error ()
        (block-validation-fail "JWT ~A is not valid JSON" label)))))

(defun engine-rpc-required-jwt-field (object name)
  (unless (genesis-object-field-present-p object name)
    (block-validation-fail "JWT field ~A is missing" name))
  (genesis-object-field object name))

(defun engine-rpc-validate-jwt-token (token secret now)
  (unless (and (byte-vector-p secret) (= 32 (length secret)))
    (block-validation-fail "Engine JWT secret must be 32 bytes"))
  (multiple-value-bind (header-part payload-part signature-part)
      (engine-rpc-token-parts token)
    (let* ((header (engine-rpc-jwt-object header-part "header"))
           (payload (engine-rpc-jwt-object payload-part "payload"))
           (algorithm (engine-rpc-required-jwt-field header "alg"))
           (issued-at (engine-rpc-required-jwt-field payload "iat"))
           (expires-at (genesis-object-field payload "exp"))
           (signing-input (concatenate 'string header-part "." payload-part))
           (expected-signature
             (engine-rpc-base64url-decode
              (engine-rpc-jwt-signature secret signing-input)))
           (actual-signature
             (engine-rpc-base64url-decode signature-part)))
      (unless (string= algorithm "HS256")
        (block-validation-fail "JWT algorithm must be HS256"))
      (unless (integerp issued-at)
        (block-validation-fail "JWT issued-at must be an integer"))
      (when (and expires-at
                 (or (not (integerp expires-at))
                     (< expires-at now)))
        (block-validation-fail "JWT is expired"))
      (when (> (- now issued-at) +engine-rpc-jwt-expiry-seconds+)
        (block-validation-fail "JWT is stale"))
      (when (> (- issued-at now) +engine-rpc-jwt-expiry-seconds+)
        (block-validation-fail "JWT is from the future"))
      (unless (engine-rpc-constant-time-bytes=
               expected-signature actual-signature)
        (block-validation-fail "JWT signature is invalid"))
      t)))

(defun engine-rpc-http-authorized-p (authorization secret now)
  (unless authorization
    (block-validation-fail "missing token"))
  (unless (engine-rpc-string-prefix-p "Bearer " authorization)
    (block-validation-fail "missing token"))
  (engine-rpc-validate-jwt-token
   (subseq authorization (length "Bearer "))
   secret
   now))

(defun engine-rpc-http-split-lines (string)
  (loop with start = 0
        for end = (position #\Newline string :start start)
        collect (engine-rpc-http-trim
                 (subseq string start (or end (length string))))
        while end
        do (setf start (1+ end))))

(defun engine-rpc-http-request-target (request-line)
  (let* ((first-space (position #\Space request-line))
         (second-space
           (and first-space
                (position #\Space request-line :start (1+ first-space)))))
    (unless (and first-space second-space)
      (block-validation-fail "HTTP request line is malformed"))
    (values (subseq request-line 0 first-space)
            (subseq request-line (1+ first-space) second-space))))

(defun engine-rpc-http-headers (lines)
  (loop for line in lines
        unless (string= line "")
          collect
          (let ((colon (position #\: line)))
            (unless colon
              (block-validation-fail "HTTP header is malformed"))
            (cons (string-downcase
                   (engine-rpc-http-trim (subseq line 0 colon)))
                  (engine-rpc-http-trim (subseq line (1+ colon)))))))

(defun engine-rpc-http-header (headers name)
  (cdr (assoc (string-downcase name) headers :test #'string=)))

(defun engine-rpc-http-media-type (content-type)
  (when content-type
    (string-downcase
     (engine-rpc-http-trim
      (subseq content-type
              0
              (or (position #\; content-type)
                  (length content-type)))))))

(defun engine-rpc-http-accepted-content-type-p (content-type)
  (let ((media-type (engine-rpc-http-media-type content-type)))
    (and media-type
         (member media-type
                 +engine-rpc-http-accepted-content-types+
                 :test #'string=))))

(defun engine-rpc-http-header-boundary (request)
  (let ((crlf-boundary
          (search (format nil "~C~C~C~C"
                          #\Return #\Newline #\Return #\Newline)
                  request))
        (lf-boundary (search (format nil "~C~C" #\Newline #\Newline)
                             request)))
    (cond
      (crlf-boundary (values crlf-boundary 4))
      (lf-boundary (values lf-boundary 2))
      (t (block-validation-fail "HTTP request is missing header boundary")))))

(defun engine-rpc-http-body (body headers)
  (let ((content-length (engine-rpc-http-header headers "content-length")))
    (if content-length
        (let ((length (parse-integer content-length :junk-allowed t)))
          (unless (and length (<= 0 length (length body)))
            (block-validation-fail "HTTP content length is invalid"))
          (subseq body 0 length))
        body)))

(defun engine-rpc-http-content-length (headers)
  (let ((content-length (engine-rpc-http-header headers "content-length")))
    (if content-length
        (let ((length (parse-integer content-length :junk-allowed t)))
          (unless (and length (<= 0 length))
            (block-validation-fail "HTTP content length is invalid"))
          length)
        0)))

(defun engine-rpc-read-http-request-string (input-stream)
  (let ((lines '()))
    (loop for line = (read-line input-stream nil nil)
          while line
          do (push line lines)
             (when (string= "" (engine-rpc-http-trim line))
               (return)))
    (unless (and lines (string= "" (engine-rpc-http-trim (first lines))))
      (block-validation-fail "HTTP request is missing header boundary"))
    (let* ((lines (nreverse lines))
           (headers (engine-rpc-http-headers (rest lines)))
           (content-length (engine-rpc-http-content-length headers))
           (body (make-string content-length))
           (read-count (read-sequence body input-stream)))
      (unless (= read-count content-length)
        (block-validation-fail "HTTP request body is shorter than content length"))
      (with-output-to-string (request)
        (dolist (line lines)
          (write-string (engine-rpc-http-trim line) request)
          (format request "~C~C" #\Return #\Newline))
        (write-string body request)))))

(defun engine-rpc-http-response-string (status-code reason body
                                        &key
                                          (content-type "application/json"))
  (with-output-to-string (stream)
    (format stream "HTTP/1.1 ~D ~A~C~C" status-code reason
            #\Return #\Newline)
    (when content-type
      (format stream "Content-Type: ~A~C~C" content-type #\Return #\Newline))
    (format stream "Content-Length: ~D~C~C" (length body) #\Return #\Newline)
    (format stream "~C~C" #\Return #\Newline)
    (write-string body stream)))

(defun engine-rpc-http-error-response (status-code reason message)
  (engine-rpc-http-response-string
   status-code reason message :content-type "text/plain"))

(defun engine-rpc-handle-http-request-string
    (request store config &key jwt-secret now import-function)
  (handler-case
      (multiple-value-bind (boundary boundary-length)
          (engine-rpc-http-header-boundary request)
        (let* ((head (subseq request 0 boundary))
               (body (subseq request (+ boundary boundary-length)))
               (lines (engine-rpc-http-split-lines head)))
          (unless lines
            (block-validation-fail "HTTP request is empty"))
          (multiple-value-bind (method target)
              (engine-rpc-http-request-target (first lines))
            (declare (ignore target))
            (let ((headers (engine-rpc-http-headers (rest lines))))
              (when jwt-secret
                (handler-case
                    (engine-rpc-http-authorized-p
                     (engine-rpc-http-header headers "authorization")
                     jwt-secret
                     (or now 0))
                  (block-validation-error (condition)
                    (return-from engine-rpc-handle-http-request-string
                      (engine-rpc-http-error-response
                       401 "Unauthorized"
                       (block-validation-error-message condition))))))
              (cond
                ((and (string= method "GET") (string= body ""))
                 (engine-rpc-http-response-string
                  200 "OK" "" :content-type nil))
                ((not (string= method "POST"))
                 (engine-rpc-http-error-response
                  405 "Method Not Allowed" "method not allowed"))
                ((not (engine-rpc-http-accepted-content-type-p
                       (engine-rpc-http-header headers "content-type")))
                 (engine-rpc-http-error-response
                  415 "Unsupported Media Type"
                  "invalid content type, only application/json is supported"))
                (t
                 (engine-rpc-http-response-string
                  200 "OK"
                  (engine-rpc-handle-request-json
                   (engine-rpc-http-body body headers)
                   store
                   config
                   :import-function import-function))))))))
    (error (condition)
      (engine-rpc-http-error-response
       400 "Bad Request"
       (format nil "~A" condition)))))

(defun engine-rpc-handle-http-stream
    (input-stream output-stream store config
     &key jwt-secret now import-function)
  (let ((response
          (handler-case
              (engine-rpc-handle-http-request-string
               (engine-rpc-read-http-request-string input-stream)
               store
               config
               :jwt-secret jwt-secret
               :now now
               :import-function import-function)
            (error (condition)
              (engine-rpc-http-error-response
               400 "Bad Request"
               (format nil "~A" condition))))))
    (write-string response output-stream)
    response))

(defun engine-rpc-http-service-handle-stream
    (service input-stream output-stream)
  (unless (typep service 'engine-rpc-http-service)
    (block-validation-fail
     "Engine RPC HTTP service must be engine-rpc-http-service"))
  (engine-rpc-handle-http-stream
   input-stream
   output-stream
   (engine-rpc-http-service-store service)
   (engine-rpc-http-service-config service)
   :jwt-secret (engine-rpc-http-service-jwt-secret service)
   :now (funcall (engine-rpc-http-service-now-provider service))
   :import-function (engine-rpc-http-service-import-function service)))

(defun engine-rpc-http-service-serve-listener
    (service listener &key max-connections stop-p)
  (unless (typep service 'engine-rpc-http-service)
    (block-validation-fail
     "Engine RPC HTTP service must be engine-rpc-http-service"))
  (unless (typep listener 'engine-rpc-http-listener)
    (block-validation-fail
     "Engine RPC HTTP listener must be engine-rpc-http-listener"))
  (unless (or (null max-connections)
              (and (integerp max-connections) (<= 0 max-connections)))
    (block-validation-fail "Engine RPC HTTP max connections must be non-negative"))
  (let ((served 0)
        (stop-p (or stop-p (lambda () nil))))
    (unless (functionp stop-p)
      (block-validation-fail "Engine RPC HTTP stop predicate must be a function"))
    (unwind-protect
         (loop until (or (and max-connections (>= served max-connections))
                         (funcall stop-p))
               for connection = (engine-rpc-http-listener-accept listener)
               while connection
               do (unwind-protect
                       (engine-rpc-http-service-handle-stream
                        service
                        (engine-rpc-http-connection-input-stream connection)
                        (engine-rpc-http-connection-output-stream connection))
                    (engine-rpc-http-connection-close connection))
                  (incf served))
      (engine-rpc-http-listener-close listener))
    served))

(defun engine-new-payload-memory-status
    (store version payload config
     &key (parent-beacon-root nil parent-beacon-root-supplied-p)
          (versioned-hashes nil versioned-hashes-supplied-p)
          (requests nil requests-supplied-p)
          import-function
          (import-state-available-p t))
  (unless (typep store 'engine-payload-memory-store)
    (return-from engine-new-payload-memory-status
      (values (invalid-payload-status
               "newPayload store must be engine-payload-memory-store")
              nil)))
  (multiple-value-bind (status block)
      (if requests-supplied-p
          (engine-new-payload-version-status
           version payload config
           :parent-beacon-root parent-beacon-root
           :versioned-hashes versioned-hashes
           :requests requests)
          (engine-new-payload-version-status
           version payload config
           :parent-beacon-root parent-beacon-root
           :versioned-hashes versioned-hashes))
    (unless (string= +payload-status-valid+
                     (payload-status-status status))
      (return-from engine-new-payload-memory-status
        (values status nil)))
    (let* ((hash (block-hash block))
           (invalid-status
             (engine-payload-store-invalid-ancestor-status
              store hash hash))
           (known-block (chain-store-known-block store hash)))
      (when invalid-status
        (return-from engine-new-payload-memory-status
          (values invalid-status nil)))
      (when known-block
        (return-from engine-new-payload-memory-status
          (values (make-payload-status
                   :status +payload-status-valid+
                   :latest-valid-hash hash)
                  known-block)))
      (let* ((header (block-header block))
             (number (block-header-number header))
             (parent-hash (block-header-parent-hash header))
             (parent-block (and (plusp number)
                                (chain-store-known-block
                                 store parent-hash))))
        (when (plusp number)
          (let ((parent-invalid-status
                  (engine-payload-store-invalid-ancestor-status
                   store parent-hash hash)))
            (when parent-invalid-status
              (return-from engine-new-payload-memory-status
                (values parent-invalid-status nil)))))
        (when (and (plusp number) (null parent-block))
          (engine-payload-store-put-remote-block store block)
          (return-from engine-new-payload-memory-status
            (values (make-payload-status :status +payload-status-syncing+)
                    block)))
        (when (and parent-block
                   (not (chain-store-state-available-p
                         store parent-hash)))
          (engine-payload-store-put-remote-block store block)
          (return-from engine-new-payload-memory-status
            (values (make-payload-status :status +payload-status-accepted+)
                    block)))
        (when parent-block
          (handler-case
              (validate-block-against-config
               (block-header parent-block)
               block
               config)
            (block-validation-error (condition)
              (engine-payload-store-mark-invalid store block)
              (return-from engine-new-payload-memory-status
                (values
                 (make-payload-status
                  :status +payload-status-invalid+
                  :latest-valid-hash parent-hash
                  :validation-error
                  (block-validation-error-message condition))
                 nil)))))
        (if import-function
            (handler-case
                (multiple-value-bind (imported-block receipts)
                    (funcall import-function store block config)
                  (declare (ignore receipts))
                  (let ((imported-block (or imported-block block)))
                    (values (make-payload-status
                             :status +payload-status-valid+
                             :latest-valid-hash (block-hash imported-block))
                            imported-block)))
              (error (condition)
                (engine-payload-store-mark-invalid store block)
                (values
                 (make-payload-status
                  :status +payload-status-invalid+
                  :latest-valid-hash parent-hash
                  :validation-error
                  (if (typep condition 'block-validation-error)
                      (block-validation-error-message condition)
                      (format nil "~A" condition)))
                 nil)))
            (progn
              (engine-payload-store-put-block
               store block
               :state-available-p import-state-available-p)
              (values (make-payload-status
                       :status +payload-status-valid+
                       :latest-valid-hash hash)
                      block)))))))

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

(defun validate-block-base-fee (parent-header header &key (london-parent-p t))
  (unless (block-header-base-fee-per-gas header)
    (block-validation-fail "Header is missing base fee"))
  (let ((expected (expected-base-fee-per-gas
                   parent-header :london-parent-p london-parent-p)))
    (unless (= expected (block-header-base-fee-per-gas header))
      (block-validation-fail "Base fee mismatch"))
    t))

(defun validate-gas-limit-delta
    (parent-gas-limit header-gas-limit
     &key (bound-divisor +gas-limit-bound-divisor+)
          (minimum-gas-limit +minimum-gas-limit+))
  (let ((limit (floor parent-gas-limit bound-divisor))
        (diff (abs (- parent-gas-limit header-gas-limit))))
    (when (>= diff limit)
      (block-validation-fail "Gas limit changed too much"))
    (when (< header-gas-limit minimum-gas-limit)
      (block-validation-fail "Gas limit below minimum"))
    t))

(defun adjusted-parent-gas-limit-for-1559 (parent-header london-parent-p)
  (let ((parent-gas-limit (block-header-gas-limit parent-header)))
    (if london-parent-p
        parent-gas-limit
        (* parent-gas-limit +base-fee-elasticity-multiplier+))))

(defun validate-block-blob-gas-fields
    (header &key (blob-gas-enabled-p
                  (or (block-header-blob-gas-used header)
                      (block-header-excess-blob-gas header)))
                 (max-blob-gas (* +max-blobs-per-block+
                                  +blob-gas-per-blob+)))
  (cond
    (blob-gas-enabled-p
     (unless (block-header-blob-gas-used header)
       (block-validation-fail "Header is missing blob gas used"))
     (unless (block-header-excess-blob-gas header)
       (block-validation-fail "Header is missing excess blob gas"))
     (when (and max-blob-gas
                (> (block-header-blob-gas-used header) max-blob-gas))
       (block-validation-fail "Blob gas used exceeds maximum"))
     (unless (zerop (mod (block-header-blob-gas-used header)
                         +blob-gas-per-blob+))
       (block-validation-fail "Blob gas used is not a blob-sized multiple")))
    ((or (block-header-blob-gas-used header)
         (block-header-excess-blob-gas header))
     (block-validation-fail "Blob gas fields present before Cancun")))
  t)

(defun expected-excess-blob-gas
    (parent-header &key (target-blob-gas
                         (* +target-blobs-per-block+
                            +blob-gas-per-blob+))
                        (max-blob-gas
                         (* +max-blobs-per-block+
                            +blob-gas-per-blob+))
                        eip7918-p
                        (update-fraction
                         +blob-base-fee-update-fraction+))
  (let* ((parent-excess (or (block-header-excess-blob-gas parent-header) 0))
         (parent-used (or (block-header-blob-gas-used parent-header) 0))
         (parent-blob-gas (+ parent-excess parent-used)))
    (cond
      ((< parent-blob-gas target-blob-gas) 0)
      ((and eip7918-p
            (block-header-base-fee-per-gas parent-header)
            (> (* +blob-base-cost+
                  (block-header-base-fee-per-gas parent-header))
               (* +blob-gas-per-blob+
                  (blob-base-fee parent-excess
                                 :update-fraction update-fraction))))
       (+ parent-excess
          (floor (* parent-used (- max-blob-gas target-blob-gas))
                 max-blob-gas)))
      (t (- parent-blob-gas target-blob-gas)))))

(defun fake-exponential (factor numerator denominator)
  (let ((output 0)
        (accumulator (* factor denominator)))
    (loop for i from 1
          while (plusp accumulator)
          do (incf output accumulator)
             (setf accumulator
                   (floor (* accumulator numerator)
                          (* denominator i))))
    (floor output denominator)))

(defun blob-base-fee
    (excess-blob-gas &key (min-blob-gas-price +min-blob-gas-price+)
                          (update-fraction
                           +blob-base-fee-update-fraction+))
  (fake-exponential min-blob-gas-price
                    excess-blob-gas
                    update-fraction))

(defun block-header-blob-base-fee
    (header &key (update-fraction +blob-base-fee-update-fraction+))
  (unless (block-header-excess-blob-gas header)
    (block-validation-fail "Header is missing excess blob gas"))
  (blob-base-fee (block-header-excess-blob-gas header)
                 :update-fraction update-fraction))

(defun validate-block-excess-blob-gas
    (parent-header header &key (target-blob-gas
                                (* +target-blobs-per-block+
                                   +blob-gas-per-blob+))
                              (max-blob-gas
                               (* +max-blobs-per-block+
                                  +blob-gas-per-blob+))
                              eip7918-p
                              (update-fraction
                               +blob-base-fee-update-fraction+))
  (validate-block-blob-gas-fields header :max-blob-gas max-blob-gas)
  (let ((expected (expected-excess-blob-gas
                   parent-header
                   :target-blob-gas target-blob-gas
                   :max-blob-gas max-blob-gas
                   :eip7918-p eip7918-p
                   :update-fraction update-fraction)))
    (unless (= expected (block-header-excess-blob-gas header))
      (block-validation-fail "Excess blob gas mismatch"))
    t))

(defun block-header-cancun-fields-present-p (header)
  (or (block-header-blob-gas-used header)
      (block-header-excess-blob-gas header)))

(defun validate-block-cancun-fields (header &key (cancun-enabled-p
                                                  (block-header-cancun-fields-present-p
                                                   header)))
  (if cancun-enabled-p
      (unless (block-header-parent-beacon-root header)
        (block-validation-fail "Header is missing parent beacon root"))
      (when (block-header-parent-beacon-root header)
        (block-validation-fail "Parent beacon root present before Cancun")))
  t)

(defun validate-block-withdrawals-field
    (header &key (withdrawals-enabled-p (block-header-withdrawals-root header)))
  (if withdrawals-enabled-p
      (unless (block-header-withdrawals-root header)
        (block-validation-fail "Header is missing withdrawals root"))
      (when (block-header-withdrawals-root header)
        (block-validation-fail "Withdrawals root present before Shanghai")))
  t)

(defun validate-block-requests-hash-field
    (header &key (requests-enabled-p (block-header-requests-hash header)))
  (if requests-enabled-p
      (unless (block-header-requests-hash header)
        (block-validation-fail "Header is missing requests hash"))
      (when (block-header-requests-hash header)
        (block-validation-fail "Requests hash present before Prague")))
  t)

(defun block-header-amsterdam-fields-present-p (header)
  (or (block-header-block-access-list-hash header)
      (block-header-slot-number header)))

(defun validate-block-amsterdam-fields
    (header &key (amsterdam-enabled-p
                  (block-header-amsterdam-fields-present-p header)))
  (if amsterdam-enabled-p
      (progn
        (unless (block-header-block-access-list-hash header)
          (block-validation-fail
           "Header is missing block access list hash"))
        (unless (block-header-slot-number header)
          (block-validation-fail "Header is missing slot number")))
      (progn
        (when (block-header-block-access-list-hash header)
          (block-validation-fail
           "Block access list hash present before Amsterdam"))
        (when (block-header-slot-number header)
          (block-validation-fail "Slot number present before Amsterdam"))))
  t)

(defun validate-block-amsterdam-slot-number (parent-header header)
  (let ((parent-slot-number (block-header-slot-number parent-header))
        (slot-number (block-header-slot-number header)))
    (when (and parent-slot-number
               slot-number
               (<= slot-number parent-slot-number))
      (block-validation-fail
       "Amsterdam header slot number must exceed parent slot number")))
  t)

(defun block-header-post-merge-p (header)
  (and (plusp (block-header-number header))
       (zerop (block-header-difficulty header))))

(defun block-header-zero-nonce-p (header)
  (let ((nonce (block-header-nonce header)))
    (or (null nonce)
        (let ((bytes (ensure-byte-vector nonce)))
          (and (= 8 (length bytes))
               (every #'zerop bytes))))))

(defun validate-block-merge-transition (parent-header header)
  (when (and (block-header-post-merge-p parent-header)
             (plusp (block-header-difficulty header)))
    (block-validation-fail "Cannot revert from post-Merge to PoW difficulty"))
  t)

(defun validate-block-merge-fields
    (header &key (post-merge-p (block-header-post-merge-p header)))
  (when post-merge-p
    (unless (zerop (block-header-difficulty header))
      (block-validation-fail "Post-Merge header difficulty must be zero"))
    (unless (block-header-zero-nonce-p header)
      (block-validation-fail "Post-Merge header nonce must be zero"))
    (unless (hash32= (or (block-header-ommers-hash header) +empty-ommers-hash+)
                     +empty-ommers-hash+)
      (block-validation-fail "Post-Merge header ommers hash must be empty"))
    (when (> (block-header-gas-limit header) +max-header-gas-limit+)
      (block-validation-fail "Post-Merge header gas limit exceeds maximum")))
  t)

(defun validate-block-header-field-shapes
    (header &key require-parent-hash-p)
  (unless (block-header-p header)
    (block-validation-fail "Block header must be a block header"))
  (if require-parent-hash-p
      (unless (hash32-p (block-header-parent-hash header))
        (block-validation-fail "Header parent hash must be a hash32"))
      (validate-optional-hash32-field (block-header-parent-hash header)
                                      "Header parent hash"))
  (validate-optional-hash32-field (block-header-ommers-hash header)
                                  "Header ommers hash")
  (validate-optional-address-field (block-header-beneficiary header)
                                   "Header beneficiary")
  (validate-optional-hash32-field (block-header-state-root header)
                                  "Header state root")
  (validate-optional-hash32-field (block-header-transactions-root header)
                                  "Header transactions root")
  (validate-optional-hash32-field (block-header-receipts-root header)
                                  "Header receipts root")
  (when (block-header-logs-bloom header)
    (validate-byte-sequence-field (block-header-logs-bloom header)
                                  "Header logs bloom"
                                  :size 256))
  (unless (uint256-p (block-header-difficulty header))
    (block-validation-fail "Header difficulty must be uint256"))
  (unless (uint256-p (block-header-number header))
    (block-validation-fail "Header number must be uint256"))
  (unless (uint256-p (block-header-gas-limit header))
    (block-validation-fail "Header gas limit must be uint256"))
  (unless (uint256-p (block-header-gas-used header))
    (block-validation-fail "Header gas used must be uint256"))
  (unless (uint256-p (block-header-timestamp header))
    (block-validation-fail "Header timestamp must be uint256"))
  (validate-byte-sequence-field (block-header-extra-data header)
                                "Header extra data")
  (validate-optional-hash32-field (block-header-mix-hash header)
                                  "Header mix hash")
  (when (block-header-nonce header)
    (validate-byte-sequence-field (block-header-nonce header)
                                  "Header nonce"
                                  :size 8))
  (validate-optional-uint256-field (block-header-base-fee-per-gas header)
                                   "Header base fee")
  (validate-optional-hash32-field (block-header-withdrawals-root header)
                                  "Header withdrawals root")
  (validate-optional-uint256-field (block-header-blob-gas-used header)
                                   "Header blob gas used")
  (validate-optional-uint256-field (block-header-excess-blob-gas header)
                                   "Header excess blob gas")
  (validate-optional-hash32-field (block-header-parent-beacon-root header)
                                  "Header parent beacon root")
  (validate-optional-hash32-field (block-header-requests-hash header)
                                  "Header requests hash")
  (validate-optional-hash32-field (block-header-block-access-list-hash header)
                                  "Header block access list hash")
  (validate-optional-uint64-field (block-header-slot-number header)
                                  "Header slot number")
  t)

(defun validate-block-header-basics
    (parent-header header &key (validate-base-fee-p nil
                                validate-base-fee-p-supplied-p)
                         (london-parent-p t)
                         (withdrawals-enabled-p nil
                          withdrawals-enabled-p-supplied-p)
                         (cancun-enabled-p nil
                          cancun-enabled-p-supplied-p)
                         (requests-enabled-p nil
                          requests-enabled-p-supplied-p)
                         (amsterdam-enabled-p nil
                          amsterdam-enabled-p-supplied-p)
                         (osaka-enabled-p nil)
                         (expanded-blob-schedule-p nil
                          expanded-blob-schedule-p-supplied-p)
                         blob-schedule-target-gas
                         blob-schedule-max-gas
                         blob-schedule-update-fraction
                         (post-merge-p nil post-merge-p-supplied-p))
  (validate-block-header-field-shapes parent-header)
  (validate-block-header-field-shapes header :require-parent-hash-p t)
  (let ((validate-base-fee-p
          (if validate-base-fee-p-supplied-p
              validate-base-fee-p
              (block-header-base-fee-per-gas header)))
        (withdrawals-enabled-p
          (if withdrawals-enabled-p-supplied-p
              withdrawals-enabled-p
              (block-header-withdrawals-root header)))
        (cancun-enabled-p
          (if cancun-enabled-p-supplied-p
              cancun-enabled-p
              (block-header-cancun-fields-present-p header)))
        (requests-enabled-p
          (if requests-enabled-p-supplied-p
              requests-enabled-p
              (block-header-requests-hash header)))
        (amsterdam-enabled-p
          (if amsterdam-enabled-p-supplied-p
              amsterdam-enabled-p
              (block-header-amsterdam-fields-present-p header)))
        (expanded-blob-schedule-p
          (if expanded-blob-schedule-p-supplied-p
              expanded-blob-schedule-p
              osaka-enabled-p))
        (post-merge-p
          (if post-merge-p-supplied-p
              post-merge-p
              (block-header-post-merge-p header))))
    (unless (hash32= (block-header-parent-hash header)
                     (block-header-hash parent-header))
      (block-validation-fail "Parent hash mismatch"))
    (validate-block-merge-transition parent-header header)
    (validate-block-merge-fields header :post-merge-p post-merge-p)
    (unless (= (block-header-number header)
               (1+ (block-header-number parent-header)))
      (block-validation-fail "Block number is not parent plus one"))
    (unless (> (block-header-timestamp header)
               (block-header-timestamp parent-header))
      (block-validation-fail "Timestamp is not greater than parent timestamp"))
    (when (> (block-header-gas-used header)
             (block-header-gas-limit header))
      (block-validation-fail "Gas used exceeds gas limit"))
    (validate-gas-limit-delta (adjusted-parent-gas-limit-for-1559
                               parent-header
                               london-parent-p)
                              (block-header-gas-limit header))
    (when (> (length (ensure-byte-vector (block-header-extra-data header)))
             +maximum-extra-data-size+)
      (block-validation-fail "Extra data too long"))
    (if cancun-enabled-p
        (let ((target-blob-gas
                (or blob-schedule-target-gas
                    (* (if expanded-blob-schedule-p
                           +osaka-target-blobs-per-block+
                           +target-blobs-per-block+)
                       +blob-gas-per-blob+)))
              (max-blob-gas
                (or blob-schedule-max-gas
                    (* (if expanded-blob-schedule-p
                           +osaka-max-blobs-per-block+
                           +max-blobs-per-block+)
                       +blob-gas-per-blob+)))
              (update-fraction
                (or blob-schedule-update-fraction
                    (if expanded-blob-schedule-p
                        +osaka-blob-base-fee-update-fraction+
                        +blob-base-fee-update-fraction+))))
          (validate-block-cancun-fields header :cancun-enabled-p t)
          (validate-block-excess-blob-gas
           parent-header header
           :target-blob-gas target-blob-gas
           :max-blob-gas max-blob-gas
           :eip7918-p osaka-enabled-p
           :update-fraction update-fraction))
        (progn
          (validate-block-cancun-fields header :cancun-enabled-p nil)
          (validate-block-blob-gas-fields header)))
    (validate-block-withdrawals-field
     header :withdrawals-enabled-p withdrawals-enabled-p)
    (validate-block-requests-hash-field
     header :requests-enabled-p requests-enabled-p)
    (validate-block-amsterdam-fields
     header :amsterdam-enabled-p amsterdam-enabled-p)
    (when amsterdam-enabled-p
      (validate-block-amsterdam-slot-number parent-header header))
    (when validate-base-fee-p
      (validate-block-base-fee parent-header header
                               :london-parent-p london-parent-p)))
  t)

(defun validate-block-header-against-config (parent-header header config)
  (let ((number (block-header-number header))
        (timestamp (block-header-timestamp header)))
    (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
        (chain-config-blob-schedule config number timestamp)
      (validate-block-header-basics
       parent-header header
       :validate-base-fee-p (chain-config-london-p config number)
       :london-parent-p (chain-config-london-p
                         config (block-header-number parent-header))
       :withdrawals-enabled-p (chain-config-shanghai-p config number timestamp)
       :cancun-enabled-p (chain-config-cancun-p config number timestamp)
       :requests-enabled-p (chain-config-prague-p config number timestamp)
       :amsterdam-enabled-p (chain-config-amsterdam-p config number timestamp)
       :osaka-enabled-p (chain-config-osaka-p config number timestamp)
       :expanded-blob-schedule-p
       (chain-config-expanded-blob-schedule-p config number timestamp)
       :blob-schedule-target-gas target-blob-gas
       :blob-schedule-max-gas max-blob-gas
       :blob-schedule-update-fraction update-fraction
       :post-merge-p (block-header-post-merge-p header)))))

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

(defun validate-blob-sidecar-fields (sidecar &key transaction)
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
      (validate-sized-byte-vector blob +blob-byte-size+ "Blob"))
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
    t))

(defun validate-withdrawal-fields (withdrawal)
  (unless (uint256-p (withdrawal-index withdrawal))
    (block-validation-fail "Withdrawal index must be uint256"))
  (unless (uint256-p (withdrawal-validator-index withdrawal))
    (block-validation-fail "Withdrawal validator index must be uint256"))
  (unless (address-p (withdrawal-address withdrawal))
    (block-validation-fail "Withdrawal address must be an address"))
  (unless (uint256-p (withdrawal-amount withdrawal))
    (block-validation-fail "Withdrawal amount must be uint256"))
  t)

(defun validate-withdrawal-list-fields (withdrawals)
  (unless (listp withdrawals)
    (block-validation-fail "Withdrawals must be a list"))
  (dolist (withdrawal withdrawals t)
    (validate-withdrawal-fields withdrawal)))

(defun transaction-object-p (value)
  (typep value
         '(or legacy-transaction
              access-list-transaction
              dynamic-fee-transaction
              blob-transaction
              set-code-transaction)))

(defun validate-block-transaction-list-fields (transactions)
  (unless (listp transactions)
    (block-validation-fail "Block transactions must be a list"))
  (dolist (transaction transactions t)
    (unless (transaction-object-p transaction)
      (block-validation-fail "Block transaction must be a transaction"))))

(defun validate-block-ommer-list-fields (ommers)
  (unless (listp ommers)
    (block-validation-fail "Block ommers must be a list"))
  (dolist (ommer ommers t)
    (unless (block-header-p ommer)
      (block-validation-fail "Block ommer must be a block header"))))

(defun validate-block-body-commitment-fields (header)
  (unless (hash32-p (block-header-ommers-hash header))
    (block-validation-fail "Header ommers hash must be a hash32"))
  (unless (hash32-p (block-header-transactions-root header))
    (block-validation-fail "Header transactions root must be a hash32"))
  (when (block-header-withdrawals-root header)
    (unless (hash32-p (block-header-withdrawals-root header))
      (block-validation-fail "Header withdrawals root must be a hash32")))
  (when (block-header-requests-hash header)
    (unless (hash32-p (block-header-requests-hash header))
      (block-validation-fail "Header requests hash must be a hash32")))
  (when (block-header-block-access-list-hash header)
    (unless (hash32-p (block-header-block-access-list-hash header))
      (block-validation-fail
       "Header block access list hash must be a hash32")))
  t)

(defun transaction-blob-count (transaction)
  (typecase transaction
    (blob-transaction
     (length (blob-transaction-blob-versioned-hashes transaction)))
    (t 0)))

(defun blob-gas-used (transactions)
  (* +blob-gas-per-blob+
     (loop for transaction in transactions
           sum (transaction-blob-count transaction))))

(defun validate-block-transactions-against-config (block config)
  (let ((header (block-header block)))
    (validate-block-transaction-list-fields (block-transactions block))
    (dolist (transaction (block-transactions block) t)
      (validate-transaction-type-for-config
       transaction config
       (block-header-number header)
       (block-header-timestamp header)))))

(defun validate-block-body-against-config (block config)
  (let* ((header (block-header block))
         (number (block-header-number header))
         (timestamp (block-header-timestamp header))
         (block-access-list-max-code-size
           (if (chain-config-amsterdam-p config number timestamp)
               +block-access-list-amsterdam-max-code-size+
               +block-access-list-max-code-size+)))
    (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
        (chain-config-blob-schedule config number timestamp)
      (declare (ignore target-blob-gas))
      (validate-block-transactions-against-config block config)
      (validate-block-body-roots block
                                 :blob-base-fee-update-fraction
                                 update-fraction
                                 :max-blob-gas max-blob-gas
                                 :block-access-list-max-code-size
                                 block-access-list-max-code-size))))

(defun validate-block-against-config (parent-header block config)
  (validate-block-header-against-config parent-header (block-header block)
                                        config)
  (validate-block-body-against-config block config))

(defun validate-block-body-roots
    (block &key (blob-base-fee-update-fraction
                 +blob-base-fee-update-fraction+)
                (max-blob-gas
                 (* +max-blobs-per-block+ +blob-gas-per-blob+))
                block-access-list-max-code-size)
  (let* ((header (block-header block))
         (ommers (block-ommers block))
         (ommers-root nil)
         (transactions (block-transactions block))
         (transactions-root nil)
         (blob-gas-used nil)
         (base-fee (block-header-base-fee-per-gas header))
         (blob-base-fee (when (block-header-excess-blob-gas header)
                          (block-header-blob-base-fee
                           header
                           :update-fraction
                           blob-base-fee-update-fraction))))
    (validate-block-body-commitment-fields header)
    (validate-block-ommer-list-fields ommers)
    (setf ommers-root (ommers-hash ommers))
    (validate-block-transaction-list-fields transactions)
    (setf blob-gas-used (blob-gas-used transactions))
    (dolist (transaction transactions)
      (validate-transaction-recipient-field transaction)
      (validate-transaction-data-field transaction)
      (validate-transaction-scalar-fields transaction)
      (validate-transaction-signature-fields transaction)
      (validate-access-list-fields transaction)
      (validate-set-code-transaction-fields transaction)
      (when base-fee
        (validate-1559-transaction-fees transaction base-fee))
      (when (typep transaction 'blob-transaction)
        (validate-blob-transaction-fields transaction)
        (when blob-base-fee
          (validate-blob-transaction-fee-cap transaction blob-base-fee))))
    (setf transactions-root (transaction-list-root transactions))
    (when (block-withdrawals-present-p block)
      (validate-withdrawal-list-fields (block-withdrawals block)))
    (when (block-requests-present-p block)
      (validate-execution-request-list-fields (block-requests block)))
    (when (block-block-access-list-present-p block)
      (validated-block-access-list-commitment
       block
       :max-code-size block-access-list-max-code-size
       :max-items (when (plusp (block-header-gas-limit header))
                    (floor (block-header-gas-limit header)
                           +block-access-list-item-gas-cost+))))
    (unless (hash32= ommers-root (block-header-ommers-hash header))
      (block-validation-fail "Ommers root hash mismatch"))
    (when (and (block-header-post-merge-p header)
               ommers)
      (block-validation-fail "Post-Merge blocks cannot contain ommers"))
    (unless (hash32= transactions-root
                     (block-header-transactions-root header))
      (block-validation-fail "Transaction root hash mismatch"))
    (cond
      ((block-header-withdrawals-root header)
       (unless (block-withdrawals-present-p block)
         (block-validation-fail "Missing withdrawals in block body"))
       (unless (hash32= (withdrawal-list-root (block-withdrawals block))
                        (block-header-withdrawals-root header))
         (block-validation-fail "Withdrawals root hash mismatch")))
      ((block-withdrawals-present-p block)
       (block-validation-fail "Withdrawals present before withdrawals root")))
    (cond
      ((block-header-requests-hash header)
       (unless (block-requests-present-p block)
         (block-validation-fail "Missing execution requests in block body"))
       (unless (hash32= (execution-requests-hash (block-requests block))
                        (block-header-requests-hash header))
         (block-validation-fail "Execution requests hash mismatch")))
      ((block-requests-present-p block)
       (block-validation-fail "Execution requests present before requests hash")))
    (cond
      ((block-header-block-access-list-hash header)
       (unless (block-block-access-list-present-p block)
         (block-validation-fail "Missing block access list in block body"))
       (unless (hash32= (validated-block-access-list-commitment
                         block
                         :max-code-size block-access-list-max-code-size
                         :max-items
                         (when (plusp (block-header-gas-limit header))
                           (floor (block-header-gas-limit header)
                                  +block-access-list-item-gas-cost+)))
                        (block-header-block-access-list-hash header))
         (block-validation-fail "Block access list hash mismatch")))
      ((block-block-access-list-present-p block)
       (block-validation-fail
        "Block access list present before block access list hash")))
    (cond
      ((block-header-blob-gas-used header)
       (unless (= blob-gas-used (block-header-blob-gas-used header))
         (block-validation-fail "Blob gas used mismatch")))
      ((plusp blob-gas-used)
       (block-validation-fail "Blob transactions present before blob gas header")))
    (when (> blob-gas-used max-blob-gas)
      (block-validation-fail "Blob gas used exceeds maximum"))
    t))

(defun receipts-gas-used (receipts)
  (if receipts
      (receipt-cumulative-gas-used (car (last receipts)))
      0))

(defun validate-block-execution-commitment-fields (header state-root)
  (unless (uint256-p (block-header-gas-used header))
    (block-validation-fail "Header gas used must be uint256"))
  (validate-sized-byte-vector (block-header-logs-bloom header)
                              256
                              "Header logs bloom")
  (unless (hash32-p (block-header-receipts-root header))
    (block-validation-fail "Header receipts root must be a hash32"))
  (unless (hash32-p (block-header-state-root header))
    (block-validation-fail "Header state root must be a hash32"))
  (unless (hash32-p state-root)
    (block-validation-fail "Computed state root must be a hash32"))
  t)

(defun validate-log-topic-field (topic)
  (handler-case
      (progn
        (topic-bytes topic)
        t)
    (error ()
      (block-validation-fail "Log topic must be a hash32 or 32-byte value"))))

(defun validate-log-entry-fields (log)
  (unless (log-entry-p log)
    (block-validation-fail "Receipt log must be a log entry"))
  (unless (address-p (log-entry-address log))
    (block-validation-fail "Receipt log address must be an address"))
  (unless (listp (log-entry-topics log))
    (block-validation-fail "Receipt log topics must be a list"))
  (dolist (topic (log-entry-topics log))
    (validate-log-topic-field topic))
  (handler-case
      (progn
        (ensure-byte-vector (log-entry-data log))
        t)
    (error ()
      (block-validation-fail "Receipt log data must be a byte sequence"))))

(defun validate-receipt-fields (receipt)
  (unless (receipt-p receipt)
    (block-validation-fail "Block receipt must be a receipt"))
  (if (receipt-post-state receipt)
      (validate-sized-byte-vector (receipt-post-state receipt)
                                  32
                                  "Receipt post-state")
      (unless (member (receipt-status receipt) '(0 1))
        (block-validation-fail "Receipt status must be 0 or 1")))
  (unless (uint64-value-p (receipt-cumulative-gas-used receipt))
    (block-validation-fail "Receipt cumulative gas used must be uint64"))
  (unless (listp (receipt-logs receipt))
    (block-validation-fail "Receipt logs must be a list"))
  (dolist (log (receipt-logs receipt) t)
    (validate-log-entry-fields log)))

(defun validate-receipt-list-fields (receipts)
  (unless (listp receipts)
    (block-validation-fail "Block receipts must be a list"))
  (let ((previous-gas-used nil))
    (dolist (receipt receipts t)
      (validate-receipt-fields receipt)
      (let ((gas-used (receipt-cumulative-gas-used receipt)))
        (when (and previous-gas-used (<= gas-used previous-gas-used))
          (block-validation-fail
           "Receipt cumulative gas used must increase"))
        (setf previous-gas-used gas-used)))))

(defun validate-block-execution-receipt-fork-semantics
    (header chain-config)
  (when chain-config
    (unless (chain-config-byzantium-p chain-config
                                      (block-header-number header))
      (block-validation-fail
       "Pre-Byzantium receipt roots are outside Phase A scope"))))

(defun validate-block-execution-roots
    (block receipts state-root &key
       (transactions nil transactions-supplied-p)
       chain-config)
  (let ((header (block-header block)))
    (validate-block-execution-commitment-fields header state-root)
    (validate-block-execution-receipt-fork-semantics header chain-config)
    (validate-receipt-list-fields receipts)
    (when transactions-supplied-p
      (validate-block-transaction-list-fields transactions))
    (let* ((gas-used (receipts-gas-used receipts))
           (logs-bloom (bloom-bytes (receipts-logs-bloom receipts)))
           (receipts-root (if transactions-supplied-p
                              (transaction-receipt-list-root transactions
                                                             receipts)
                              (receipt-list-root receipts))))
      (unless (= gas-used (block-header-gas-used header))
        (block-validation-fail "Gas used mismatch"))
      (unless (and (block-header-logs-bloom header)
                   (bytes= logs-bloom (block-header-logs-bloom header)))
        (block-validation-fail "Logs bloom mismatch"))
      (unless (hash32= receipts-root (block-header-receipts-root header))
        (block-validation-fail "Receipts root mismatch"))
      (unless (hash32= state-root (block-header-state-root header))
        (block-validation-fail "State root mismatch")))
    t))

(defstruct (withdrawal (:constructor make-withdrawal
                         (&key (index 0)
                               (validator-index 0)
                               (address (zero-address))
                               (amount 0))))
  (index 0 :type (integer 0 *))
  (validator-index 0 :type (integer 0 *))
  address
  (amount 0 :type (integer 0 *)))

(defun withdrawal-rlp-object (withdrawal)
  (make-rlp-list
   (ensure-uint256 (withdrawal-index withdrawal) "Withdrawal index")
   (ensure-uint256 (withdrawal-validator-index withdrawal)
                   "Withdrawal validator index")
   (address-bytes (withdrawal-address withdrawal))
   (ensure-uint256 (withdrawal-amount withdrawal) "Withdrawal amount")))

(defun withdrawal-rlp (withdrawal)
  (rlp-encode (withdrawal-rlp-object withdrawal)))

(defstruct (log-entry (:constructor make-log-entry
                         (&key (address (zero-address))
                               (topics '())
                               (data #()))))
  address
  (topics '() :type list)
  data)

(defun topic-bytes (topic)
  (etypecase topic
    (hash32 (hash32-bytes topic))
    (byte-vector (optional-bytes topic 32 "Log topic"))
    (vector (optional-bytes topic 32 "Log topic"))))

(defun log-entry-rlp-object (log)
  (make-rlp-list
   (address-bytes (log-entry-address log))
   (mapcar #'topic-bytes (log-entry-topics log))
   (ensure-byte-vector (log-entry-data log))))

(defstruct (bloom (:constructor %make-bloom (bytes)))
  (bytes (make-byte-vector 256) :type byte-vector))

(defun make-bloom (&optional bytes)
  (%make-bloom (if bytes
                   (optional-bytes bytes 256 "Bloom")
                   (make-byte-vector 256))))

(defun bloom-values (data)
  (let ((hash (keccak-256 data)))
    (labels ((bit-index (offset)
               (logand #x7ff
                       (logior (ash (aref hash offset) 8)
                               (aref hash (1+ offset)))))
             (byte-index (bit-index)
               (- 256 (ash bit-index -3) 1))
             (byte-value (offset)
               (ash 1 (logand (aref hash (1+ offset)) #x7))))
      (list (byte-index (bit-index 0)) (byte-value 0)
            (byte-index (bit-index 2)) (byte-value 2)
            (byte-index (bit-index 4)) (byte-value 4)))))

(defun bloom-add (bloom data)
  (destructuring-bind (i1 v1 i2 v2 i3 v3) (bloom-values data)
    (let ((bytes (bloom-bytes bloom)))
      (setf (aref bytes i1) (logior (aref bytes i1) v1)
            (aref bytes i2) (logior (aref bytes i2) v2)
            (aref bytes i3) (logior (aref bytes i3) v3))))
  bloom)

(defun bloom-contains-p (bloom data)
  (destructuring-bind (i1 v1 i2 v2 i3 v3) (bloom-values data)
    (let ((bytes (bloom-bytes bloom)))
      (and (= v1 (logand v1 (aref bytes i1)))
           (= v2 (logand v2 (aref bytes i2)))
           (= v3 (logand v3 (aref bytes i3)))))))

(defun receipt-bloom (logs)
  (let ((bloom (make-bloom)))
    (dolist (log logs bloom)
      (bloom-add bloom (address-bytes (log-entry-address log)))
      (dolist (topic (log-entry-topics log))
        (bloom-add bloom (topic-bytes topic))))))

(defstruct (receipt (:constructor make-receipt
                       (&key post-state
                             (status 1)
                             (cumulative-gas-used 0)
                             (logs '()))))
  post-state
  (status 1 :type (integer 0 1))
  (cumulative-gas-used 0 :type (integer 0 *))
  (logs '() :type list))

(defun receipt-status-bytes (receipt)
  (if (receipt-post-state receipt)
      (ensure-byte-vector (receipt-post-state receipt))
      (if (= (receipt-status receipt) 1)
          (ensure-byte-vector #(1))
          (make-byte-vector 0))))

(defun receipt-rlp-object (receipt)
  (let ((logs (receipt-logs receipt)))
    (make-rlp-list
     (receipt-status-bytes receipt)
     (ensure-uint256 (receipt-cumulative-gas-used receipt)
                     "Receipt cumulative gas used")
     (bloom-bytes (receipt-bloom logs))
     (mapcar #'log-entry-rlp-object logs))))

(defun receipt-rlp (receipt)
  (rlp-encode (receipt-rlp-object receipt)))

(defun transaction-receipt-encoding (transaction receipt)
  (let ((type (transaction-type transaction))
        (receipt-rlp (receipt-rlp receipt)))
    (if (zerop type)
        receipt-rlp
        (concat-bytes (vector type) receipt-rlp))))

(defun derive-list-root (encoded-items)
  (let ((trie (make-mpt)))
    (loop for item in encoded-items
          for index from 0
          do (mpt-put trie (rlp-encode index) item))
    (make-hash32 (mpt-root-hash trie))))

(defun transaction-list-root (transactions)
  (derive-list-root (mapcar #'transaction-encoding transactions)))

(defun receipt-list-root (receipts)
  (derive-list-root (mapcar #'receipt-rlp receipts)))

(defun transaction-receipt-list-root (transactions receipts)
  (unless (= (length transactions) (length receipts))
    (block-validation-fail "Transaction and receipt count mismatch"))
  (derive-list-root
   (mapcar #'transaction-receipt-encoding transactions receipts)))

(defun withdrawal-list-root (withdrawals)
  (derive-list-root (mapcar #'withdrawal-rlp withdrawals)))
