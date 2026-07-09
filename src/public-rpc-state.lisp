(in-package #:ethereum-lisp.core)

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

(defun eth-rpc-state-block-param (params store method)
  (let ((block (eth-rpc-block-param params store method)))
    (unless block
      (block-validation-fail "~A block is not available" method))
    (unless (chain-store-state-available-p store (block-hash block))
      (block-validation-fail "~A state is not available" method))
    block))

(defun engine-rpc-handle-eth-get-balance (params store)
  (unless (= 2 (length params))
    (block-validation-fail
     "eth_getBalance params must contain address and block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getBalance" "address"))
         (block (eth-rpc-state-block-param
                 (list (second params)) store "eth_getBalance")))
    (quantity-to-hex
     (chain-store-account-balance
      store (block-hash block) address))))

(defun eth-rpc-pending-account-nonce
    (store address state-nonce &key expected-chain-id)
  (engine-payload-store-pending-contiguous-nonce
   store
   address
   state-nonce
   :expected-chain-id expected-chain-id))

(defun engine-rpc-handle-eth-get-transaction-count (params store config)
  (unless (= 2 (length params))
    (block-validation-fail
     "eth_getTransactionCount params must contain address and block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getTransactionCount" "address"))
         (block-id (second params))
         (block (eth-rpc-state-block-param
                 (list block-id) store "eth_getTransactionCount")))
    (let ((state-nonce
            (chain-store-account-nonce
             store (block-hash block) address)))
      (quantity-to-hex
       (if (and (stringp block-id) (string= block-id "pending"))
           (eth-rpc-pending-account-nonce
            store
            address
            state-nonce
            :expected-chain-id (chain-config-chain-id config))
           state-nonce)))))

(defun engine-rpc-handle-eth-get-code (params store)
  (unless (= 2 (length params))
    (block-validation-fail
     "eth_getCode params must contain address and block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getCode" "address"))
         (block (eth-rpc-state-block-param
                 (list (second params)) store "eth_getCode")))
    (bytes-to-hex
     (chain-store-account-code
      store (block-hash block) address))))

(defun engine-rpc-handle-eth-get-storage-at (params store)
  (unless (= 3 (length params))
    (block-validation-fail
     "eth_getStorageAt params must contain address, storage key, and block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getStorageAt" "address"))
         (slot (eth-rpc-storage-slot-param
                (second params) "eth_getStorageAt"))
         (block (eth-rpc-state-block-param
                 (list (third params)) store "eth_getStorageAt")))
    (eth-rpc-uint256-word-hex
     (chain-store-account-storage
      store (block-hash block) address slot))))

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

(defun eth-rpc-state-db-from-chain-store (store block-hash)
  (ethereum-lisp.execution:chain-store-state-db store block-hash))

(defun eth-rpc-proof-node-hex-list (proof)
  (mapcar #'bytes-to-hex proof))

(defun eth-rpc-storage-proof-object-from-state-proof (proof proof-slot)
  (list (cons "key" (eth-rpc-proof-storage-slot-output-key proof-slot))
        (cons "value"
              (quantity-to-hex
               (ethereum-lisp.state:state-storage-proof-value proof)))
        (cons "proof"
              (eth-rpc-proof-node-hex-list
               (ethereum-lisp.state:state-storage-proof-proof proof)))))

(defun eth-rpc-proof-storage-slots-param (value method)
  (unless (json-array-p value)
    (block-validation-fail "~A storage keys must be a list" method))
  (when (> (length (json-array-values value)) +eth-get-proof-max-storage-keys+)
    (block-validation-fail
     "~A storage keys must contain at most ~D entries"
     method +eth-get-proof-max-storage-keys+))
  (mapcar (lambda (slot)
            (eth-rpc-proof-storage-slot-param slot method))
          (json-array-values value)))

(defun eth-rpc-build-proof-object (store block-hash address slots)
  (let* ((state (eth-rpc-state-db-from-chain-store store block-hash))
         (proof
           (ethereum-lisp.state:state-db-get-proof
            state
            address
            (mapcar #'eth-rpc-proof-storage-slot-slot slots))))
    (list
     (cons "address" (address-to-hex address))
     (cons "accountProof"
           (eth-rpc-proof-node-hex-list
            (ethereum-lisp.state:state-proof-result-account-proof proof)))
     (cons "balance"
           (quantity-to-hex
            (ethereum-lisp.state:state-proof-result-balance proof)))
     (cons "codeHash"
           (hash32-to-hex
            (ethereum-lisp.state:state-proof-result-code-hash proof)))
     (cons "nonce"
           (quantity-to-hex
            (ethereum-lisp.state:state-proof-result-nonce proof)))
     (cons "storageHash"
           (hash32-to-hex
            (ethereum-lisp.state:state-proof-result-storage-root proof)))
     (cons "storageProof"
           (loop for storage-proof in
                 (ethereum-lisp.state:state-proof-result-storage-proofs proof)
                 for slot in slots
                 collect
                 (eth-rpc-storage-proof-object-from-state-proof
                  storage-proof
                  slot))))))

(defun engine-rpc-handle-eth-get-proof (params store)
  (unless (= 3 (length params))
    (block-validation-fail
     "eth_getProof params must contain address, storage keys, and block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getProof" "address"))
         (slots (eth-rpc-proof-storage-slots-param
                 (second params) "eth_getProof"))
         (block (eth-rpc-state-block-param
                 (list (third params)) store "eth_getProof")))
    (eth-rpc-build-proof-object store (block-hash block) address slots)))

(defun eth-rpc-call-object-optional-address (object name method)
  (when (genesis-object-field-present-p object name)
    (eth-rpc-address-param (genesis-object-field object name) method name)))

(defun eth-rpc-call-object-quantity-field (object name method &key default)
  (if (genesis-object-field-present-p object name)
      (parse-genesis-quantity
       (genesis-object-field object name)
       name
       :required-p t)
      default))

(defun eth-rpc-call-object-data (object method)
  (let* ((data-present-p (genesis-object-field-present-p object "data"))
         (input-present-p (genesis-object-field-present-p object "input"))
         (data (when data-present-p
                 (engine-rpc-bytes (genesis-object-field object "data")
                                   (format nil "~A data" method))))
         (input (when input-present-p
                  (engine-rpc-bytes (genesis-object-field object "input")
                                    (format nil "~A input" method)))))
    (or input data (make-byte-vector 0))))

(defun eth-rpc-call-object-access-list-storage-key (value method)
  (handler-case
      (engine-rpc-hash32 value "accessList storage key")
    (block-validation-error ()
      (block-validation-fail
       "~A accessList storage key must be a 32-byte hash"
       method))))

(defun eth-rpc-call-object-access-list-entry (entry method)
  (unless (json-object-p entry)
    (block-validation-fail "~A accessList entry must be an object" method))
  (unless (genesis-object-field-present-p entry "address")
    (block-validation-fail "~A accessList entry address is missing" method))
  (unless (genesis-object-field-present-p entry "storageKeys")
    (block-validation-fail "~A accessList entry storageKeys is missing" method))
  (let ((storage-keys (genesis-object-field entry "storageKeys")))
    (when (json-object-p storage-keys)
      (block-validation-fail
       "~A accessList storageKeys must be an array"
       method))
    (unless (json-array-p storage-keys)
      (block-validation-fail
       "~A accessList storageKeys must be an array"
       method))
    (make-access-list-entry
     :address
     (eth-rpc-address-param
      (genesis-object-field entry "address")
      method
      "accessList address")
     :storage-keys
     (mapcar
      (lambda (storage-key)
        (eth-rpc-call-object-access-list-storage-key storage-key method))
      (json-array-values storage-keys)))))

(defun eth-rpc-call-object-access-list (object method)
  (if (genesis-object-field-present-p object "accessList")
      (let ((access-list (genesis-object-field object "accessList")))
        (when (json-object-p access-list)
          (block-validation-fail
           "~A accessList must be an array"
           method))
        (unless (json-array-p access-list)
          (block-validation-fail
           "~A accessList must be an array"
           method))
        (values
         (mapcar
          (lambda (entry)
            (eth-rpc-call-object-access-list-entry entry method))
          (json-array-values access-list))
         t))
      (values '() nil)))

(defun eth-rpc-call-object-fees (object method)
  (let ((gas-price-present-p
          (genesis-object-field-present-p object "gasPrice"))
        (max-fee-present-p
          (genesis-object-field-present-p object "maxFeePerGas"))
        (max-priority-present-p
          (genesis-object-field-present-p object "maxPriorityFeePerGas")))
    (when (and gas-price-present-p
               (or max-fee-present-p max-priority-present-p))
      (block-validation-fail
       "~A cannot specify gasPrice with maxFeePerGas or maxPriorityFeePerGas"
       method))
    (if (or max-fee-present-p max-priority-present-p)
        (let ((max-fee
                (eth-rpc-call-object-quantity-field
                 object "maxFeePerGas" method :default 0))
              (max-priority
                (eth-rpc-call-object-quantity-field
                 object "maxPriorityFeePerGas" method :default 0)))
          (values :dynamic max-fee max-priority))
        (values :legacy
                (eth-rpc-call-object-quantity-field
                 object "gasPrice" method :default 0)
                0))))

(defun eth-rpc-call-object-chain-id (object method config)
  (let ((chain-id (if config (chain-config-chain-id config) 0)))
    (when (genesis-object-field-present-p object "chainId")
      (let ((supplied
              (eth-rpc-call-object-quantity-field
               object "chainId" method :default chain-id)))
        (unless (= supplied chain-id)
          (block-validation-fail
           "~A chainId does not match configured chain id"
           method))))
    chain-id))

(defun eth-rpc-call-object-transaction
    (object header method config &key gas-limit-override)
  (unless (json-object-p object)
    (block-validation-fail "~A call object must be a JSON object" method))
  (let* ((sender (or (eth-rpc-call-object-optional-address object "from" method)
                     (zero-address)))
         (recipient
           (eth-rpc-call-object-optional-address object "to" method))
         (gas-limit
           (or gas-limit-override
               (eth-rpc-call-object-quantity-field
                object "gas" method
                :default (eth-rpc-call-object-default-gas-limit
                          header method))))
         (value
           (eth-rpc-call-object-quantity-field
            object "value" method :default 0))
         (nonce
           (eth-rpc-call-object-quantity-field
            object "nonce" method :default 0))
         (data (eth-rpc-call-object-data object method))
         (chain-id (eth-rpc-call-object-chain-id object method config)))
    (multiple-value-bind (access-list access-list-present-p)
        (eth-rpc-call-object-access-list object method)
      (multiple-value-bind (fee-style max-fee max-priority-fee)
          (eth-rpc-call-object-fees object method)
        (values
         sender
         (case fee-style
           (:dynamic
            (make-dynamic-fee-transaction
             :chain-id chain-id
             :nonce nonce
             :max-fee-per-gas max-fee
             :max-priority-fee-per-gas max-priority-fee
             :gas-limit gas-limit
             :to recipient
             :value value
             :data data
             :access-list access-list))
           (otherwise
            (if access-list-present-p
                (make-access-list-transaction
                 :chain-id chain-id
                 :nonce nonce
                 :gas-price max-fee
                 :gas-limit gas-limit
                 :to recipient
                 :value value
                 :data data
                 :access-list access-list)
                (make-legacy-transaction :nonce nonce
                                         :gas-price max-fee
                                         :gas-limit gas-limit
                                         :to recipient
                                         :value value
                                         :data data)))))))))

(defun eth-rpc-simulate-call-object
    (object block store config method &key gas-limit)
  (multiple-value-bind (sender tx)
      (eth-rpc-call-object-transaction
       object (block-header block) method config
       :gas-limit-override gas-limit)
    (handler-case
        (ethereum-lisp.execution:execute-message-call
         (ethereum-lisp.execution:chain-store-state-db
          store (block-hash block))
         sender
         tx
         :base-fee (or (block-header-base-fee-per-gas
                        (block-header block))
                       0)
         :chain-id (if config (chain-config-chain-id config) 0)
         :chain-config config
         :coinbase (or (block-header-beneficiary (block-header block))
                       (zero-address))
         :timestamp (block-header-timestamp (block-header block))
         :block-number (block-header-number (block-header block))
         :prev-randao (or (block-header-mix-hash (block-header block))
                          (zero-hash32))
         :difficulty (block-header-difficulty (block-header block))
         :random-p t
         :context-gas-limit (block-header-gas-limit (block-header block)))
      (ethereum-lisp.state:transaction-validation-error ()
        (block-validation-fail
         "~A transaction is invalid" method)))))

(defun engine-rpc-handle-eth-call (params store config)
  (unless (or (= 1 (length params)) (= 2 (length params)))
    (block-validation-fail
     "eth_call params must contain call object and optional block id"))
  (let* ((block (eth-rpc-state-block-param
                 (list (if (= 2 (length params)) (second params) "latest"))
                 store
                 "eth_call")))
    (multiple-value-bind (status return-data gas-used)
        (eth-rpc-simulate-call-object
         (first params) block store config "eth_call")
      (declare (ignore gas-used))
      (unless (or (eth-rpc-call-status-success-p status)
                  (eq status :reverted))
        (block-validation-fail "eth_call execution failed"))
      (bytes-to-hex return-data))))

(defun eth-rpc-call-status-success-p (status)
  (member status '(:stopped :returned :selfdestructed :successful)))

(defun eth-rpc-call-object-gas-cap (object header method)
  (unless (json-object-p object)
    (block-validation-fail "~A call object must be a JSON object" method))
  (let* ((block-limit (or (and header (block-header-gas-limit header))
                          +genesis-gas-limit+))
         (requested
           (eth-rpc-call-object-quantity-field
            object "gas" method :default block-limit)))
    (min requested block-limit)))

(defun eth-rpc-estimate-gas-success-p
    (object block store config gas-limit)
  (multiple-value-bind (status return-data gas-used)
      (eth-rpc-simulate-call-object
       object block store config "eth_estimateGas" :gas-limit gas-limit)
    (declare (ignore return-data gas-used))
    (eth-rpc-call-status-success-p status)))

(defun eth-rpc-call-intrinsic-gas (tx header config)
  (let ((rules (and config
                    header
                    (chain-config-rules config
                                        (block-header-number header)
                                        (block-header-timestamp header)))))
    (ethereum-lisp.state:transaction-intrinsic-gas
     tx
     :eip3860-p (or (null rules) (chain-rules-shanghai-p rules)))))

(defun engine-rpc-handle-eth-estimate-gas (params store config)
  (unless (or (= 1 (length params)) (= 2 (length params)))
    (block-validation-fail
     "eth_estimateGas params must contain call object and optional block id"))
  (let* ((object (first params))
         (block (eth-rpc-state-block-param
                 (list (if (= 2 (length params)) (second params) "latest"))
                 store
                 "eth_estimateGas")))
    (multiple-value-bind (sender tx)
        (eth-rpc-call-object-transaction
         object (block-header block) "eth_estimateGas" config)
      (declare (ignore sender))
      (let* ((intrinsic-gas
               (eth-rpc-call-intrinsic-gas
                tx (block-header block) config))
             (high
               (eth-rpc-call-object-gas-cap
                object (block-header block) "eth_estimateGas")))
        (when (> intrinsic-gas high)
          (block-validation-fail
           "eth_estimateGas intrinsic gas exceeds gas cap"))
        (unless (eth-rpc-estimate-gas-success-p
                 object block store config high)
          (block-validation-fail
           "eth_estimateGas execution reverted or exceeded gas cap"))
        (loop with low = intrinsic-gas
              while (< low high)
              for mid = (floor (+ low high) 2)
              do (if (eth-rpc-estimate-gas-success-p
                      object block store config mid)
                     (setf high mid)
                     (setf low (1+ mid)))
              finally (return (quantity-to-hex low)))))))

(defun eth-rpc-precompile-access-key-p (key)
  (loop for index from 1 to 10
        thereis (bytes= key (address-bytes
                             (ethereum-lisp.evm:precompile-address index)))))

(defun eth-rpc-implicit-access-key-p (key sender recipient coinbase)
  (or (and sender (bytes= key (address-bytes sender)))
      (and recipient (bytes= key (address-bytes recipient)))
      (and coinbase (bytes= key (address-bytes coinbase)))
      (eth-rpc-precompile-access-key-p key)))

(defun eth-rpc-access-list-groups (accessed-addresses accessed-storage)
  (let ((groups (make-hash-table :test 'equal)))
    (labels ((ensure-group (address-hex)
               (or (gethash address-hex groups)
                   (setf (gethash address-hex groups)
                         (make-hash-table :test 'equal)))))
      (maphash
       (lambda (key value)
         (declare (ignore value))
         (when (= (length key) 52)
           (let* ((address (make-address (subseq key 0 20)))
                  (slot (make-hash32 (subseq key 20 52)))
                  (slots (ensure-group (address-to-hex address))))
             (setf (gethash (hash32-to-hex slot) slots) t))))
       accessed-storage)
      (maphash
       (lambda (key value)
         (declare (ignore value))
         (when (= (length key) 20)
           (ensure-group (address-to-hex (make-address key)))))
       accessed-addresses))
    groups))

(defun eth-rpc-created-access-list-object
    (accessed-addresses accessed-storage sender recipient coinbase)
  (let ((groups (eth-rpc-access-list-groups
                 accessed-addresses accessed-storage)))
    (loop for address-hex being the hash-keys of groups
          using (hash-value slots)
          unless (and (zerop (hash-table-count slots))
                      (eth-rpc-implicit-access-key-p
                       (hex-to-bytes address-hex) sender recipient coinbase))
            collect
            (list
             (cons "address" address-hex)
             (cons "storageKeys"
                   (sort
                    (loop for slot being the hash-keys of slots collect slot)
                    #'string<)))
              into entries
          finally
             (return
               (sort entries
                     #'string<
                     :key (lambda (entry)
                            (cdr (assoc "address" entry :test #'string=))))))))

(defun engine-rpc-handle-eth-create-access-list (params store config)
  (unless (or (= 1 (length params)) (= 2 (length params)))
    (block-validation-fail
     "eth_createAccessList params must contain call object and optional block id"))
  (let* ((object (first params))
         (block (eth-rpc-state-block-param
                 (list (if (= 2 (length params)) (second params) "latest"))
                 store
                 "eth_createAccessList")))
    (multiple-value-bind (sender tx)
        (eth-rpc-call-object-transaction
         object (block-header block) "eth_createAccessList" config)
      (multiple-value-bind
            (status return-data gas-used accessed-addresses accessed-storage)
          (eth-rpc-simulate-call-object
           object block store config "eth_createAccessList")
        (declare (ignore return-data))
        (unless (eth-rpc-call-status-success-p status)
          (block-validation-fail
           "eth_createAccessList execution reverted or exceeded gas cap"))
        (list
         (cons "accessList"
               (eth-rpc-created-access-list-object
                accessed-addresses
                accessed-storage
                sender
                (transaction-to tx)
                (or (block-header-beneficiary (block-header block))
                    (zero-address))))
         (cons "gasUsed" (quantity-to-hex gas-used)))))))
