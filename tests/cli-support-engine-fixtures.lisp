(in-package #:ethereum-lisp.test)

(defun devnet-cli-engine-fixture-payload-number (case-name)
  (let* ((case (select-engine-newpayload-v2-fixture-case
                +engine-newpayload-v2-fixture-path+
                case-name))
         (payload (fixture-object-field case "payload")))
    (fixture-object-field payload "number")))

(defun devnet-cli-engine-fixture-parent-genesis-config (case)
  (let ((config (fixture-object-field case "config")))
    (list
     (cons "chainId" (fixture-object-field case "chainId"))
     (cons "terminalTotalDifficulty" "0x0")
     (cons "homesteadBlock" "0x0")
     (cons "eip150Block" "0x0")
     (cons "eip155Block" "0x0")
     (cons "eip158Block" "0x0")
     (cons "byzantiumBlock" "0x0")
     (cons "constantinopleBlock" "0x0")
     (cons "petersburgBlock" "0x0")
     (cons "istanbulBlock" "0x0")
     (cons "berlinBlock" (fixture-object-field config "berlinBlock"))
     (cons "londonBlock" (fixture-object-field config "londonBlock"))
     (cons "shanghaiTime" (fixture-object-field config "shanghaiTime")))))

(defun devnet-cli-engine-fixture-genesis-account (account)
  (let ((fields
          (list (cons "balance" (fixture-object-field account "balance"))
                (cons "nonce" (fixture-object-field account "nonce")))))
    (when (fixture-object-field account "code")
      (setf fields (append fields
                           (list (cons "code"
                                       (fixture-object-field account
                                                             "code"))))))
    (when (fixture-object-field account "storage")
      (setf fields (append fields
                           (list (cons "storage"
                                       (fixture-object-field account
                                                             "storage"))))))
    (cons (fixture-object-field account "address") fields)))

(defun devnet-cli-engine-fixture-parent-genesis-object (case)
  (let* ((parent (fixture-object-field case "parent"))
         (parent-state (engine-fixture-parent-state parent)))
    (list
     (cons "format" "ethereum-lisp/engine-fixture-parent-genesis-v1")
     (cons "config" (devnet-cli-engine-fixture-parent-genesis-config case))
     (cons "parentHash"
           "0x0000000000000000000000000000000000000000000000000000000000000000")
     (cons "number" (fixture-object-field parent "number"))
     (cons "nonce" "0x0")
     (cons "timestamp" (fixture-object-field parent "timestamp"))
     (cons "extraData" "0x")
     (cons "gasLimit" (fixture-object-field parent "gasLimit"))
     (cons "gasUsed" (fixture-object-field parent "gasUsed"))
     (cons "difficulty" "0x0")
     (cons "mixHash"
           "0x0000000000000000000000000000000000000000000000000000000000000000")
     (cons "coinbase" (fixture-object-field parent "feeRecipient"))
     (cons "baseFeePerGas" (fixture-object-field parent "baseFeePerGas"))
     (cons "stateRoot" (hash32-to-hex (state-db-root parent-state)))
     (cons "alloc"
           (mapcar #'devnet-cli-engine-fixture-genesis-account
                   (fixture-object-field parent "accounts"))))))

(defun devnet-cli-engine-fixture-parent-genesis-with-txpool-account (case)
  (let* ((parent (fixture-object-field case "parent"))
         (parent-state (engine-fixture-parent-state parent))
         (sender (devnet-cli-txpool-sender-address))
         (genesis (devnet-cli-engine-fixture-parent-genesis-object case))
         (alloc (fixture-object-field genesis "alloc"))
         (account
           (list (cons "balance"
                       (quantity-to-hex +devnet-cli-txpool-balance+))
                 (cons "nonce" "0x0"))))
    (state-db-set-account
     parent-state
     sender
     (make-state-account :nonce 0 :balance +devnet-cli-txpool-balance+))
    (setf (cdr (assoc "stateRoot" genesis :test #'string=))
          (hash32-to-hex (state-db-root parent-state)))
    (setf (cdr (assoc "alloc" genesis :test #'string=))
          (append alloc (list (cons (address-to-hex sender) account))))
    genesis))

(defun devnet-cli-engine-fixture-parent-block (case)
  (let* ((parent (fixture-object-field case "parent"))
         (parent-state (engine-fixture-parent-state parent))
         (fee-recipient (fixture-address-field parent "feeRecipient"))
         (parent-header
           (make-block-header
            :parent-hash (zero-hash32)
            :beneficiary fee-recipient
            :state-root (state-db-root parent-state)
            :mix-hash (zero-hash32)
            :number (fixture-quantity-field parent "number")
            :gas-limit (fixture-quantity-field parent "gasLimit")
            :gas-used (fixture-quantity-field parent "gasUsed")
            :timestamp (fixture-quantity-field parent "timestamp")
            :base-fee-per-gas (fixture-quantity-field parent "baseFeePerGas")
            :withdrawals-root (withdrawal-list-root '()))))
    (make-block :header parent-header)))

(defun devnet-cli-engine-fixture-child-block (case)
  (let* ((config (engine-fixture-chain-config case))
         (parent (fixture-object-field case "parent"))
         (payload-case (fixture-object-field case "payload"))
         (parent-state (engine-fixture-parent-state parent))
         (fee-recipient (fixture-address-field parent "feeRecipient"))
         (transactions
           (mapcar (lambda (raw)
                     (transaction-from-encoding (hex-to-bytes raw)))
                   (fixture-object-field payload-case "transactions")))
         (withdrawals
           (mapcar #'engine-fixture-withdrawal
                   (fixture-object-field payload-case "withdrawals")))
         (parent-block (devnet-cli-engine-fixture-parent-block case))
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
            (fixture-quantity-field payload-case "baseFeePerGas"))))
    (execute-signed-block
     child-state
     transactions
     :expected-chain-id (chain-config-chain-id config)
     :header child-header
     :chain-config config
     :withdrawals withdrawals)))

(defun devnet-cli-engine-fixture-side-sibling-block (case parent-block)
  (let* ((config (engine-fixture-chain-config case))
         (parent (fixture-object-field case "parent"))
         (payload-case (fixture-object-field case "payload"))
         (parent-state (engine-fixture-parent-state parent))
         (fee-recipient (fixture-address-field parent "feeRecipient"))
         (withdrawals
           (mapcar #'engine-fixture-withdrawal
                   (fixture-object-field payload-case "withdrawals")))
         (side-state (state-db-copy parent-state))
         (side-header
           (make-block-header
            :parent-hash (block-hash parent-block)
            :beneficiary fee-recipient
            :mix-hash
            (hash32-from-hex
             "0x0300000000000000000000000000000000000000000000000000000000000000")
            :number (fixture-quantity-field payload-case "number")
            :gas-limit (fixture-quantity-field payload-case "gasLimit")
            :gas-used 0
            :timestamp (1+ (fixture-quantity-field payload-case "timestamp"))
            :base-fee-per-gas
            (fixture-quantity-field payload-case "baseFeePerGas"))))
    (execute-signed-block
     side-state
     '()
     :expected-chain-id (chain-config-chain-id config)
     :header side-header
     :chain-config config
     :withdrawals withdrawals)))

(defun devnet-cli-remote-block (parent-block)
  (let ((parent-header (block-header parent-block)))
    (make-block
     :header
     (make-block-header
      :parent-hash
      (hash32-from-hex
       "0x9999999999999999999999999999999999999999999999999999999999999999")
      :beneficiary (block-header-beneficiary parent-header)
      :state-root +empty-trie-hash+
      :mix-hash (zero-hash32)
      :number (1+ (block-header-number parent-header))
      :gas-limit (block-header-gas-limit parent-header)
      :gas-used 0
      :timestamp (1+ (block-header-timestamp parent-header))
      :base-fee-per-gas (block-header-base-fee-per-gas parent-header))
     :withdrawals '())))

(defun devnet-cli-invalid-child-block (parent-block)
  (let ((parent-header (block-header parent-block)))
    (make-block
     :header
     (make-block-header
      :parent-hash (block-hash parent-block)
      :beneficiary (block-header-beneficiary parent-header)
      :state-root +empty-trie-hash+
      :mix-hash (zero-hash32)
      :number (1+ (block-header-number parent-header))
      :gas-limit (block-header-gas-limit parent-header)
      :gas-used 0
      :timestamp (block-header-timestamp parent-header)
      :base-fee-per-gas (block-header-base-fee-per-gas parent-header))
     :withdrawals '())))

