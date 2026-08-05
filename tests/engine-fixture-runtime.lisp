(in-package #:ethereum-lisp.test)

(defun fixture-quantity-field (object name)
  (hex-to-quantity (fixture-object-field object name)))

(defun fixture-address-field (object name)
  (address-from-hex (fixture-object-field object name)))

(defun fixture-optional-quantity-field (object name default)
  (hex-to-quantity (or (fixture-object-field object name) default)))

(defun fixture-optional-time-field (config name)
  "Parse a time-based fork activation key, or NIL when it is absent.

A missing key must stay NIL rather than default to 0: FORK-TIME-ACTIVE-P
treats a NIL activation time as never-active, so an absent CANCUNTIME leaves
Cancun off, whereas a 0 would activate it at genesis."
  (let ((value (fixture-object-field config name)))
    (when value (hex-to-quantity value))))

(defun engine-fixture-chain-config (case)
  (let ((config (fixture-object-field case "config")))
    (make-chain-config
     :chain-id (hex-to-quantity (fixture-object-field case "chainId"))
     :homestead-block (fixture-optional-quantity-field config "homesteadBlock" "0x0")
     :eip150-block (fixture-optional-quantity-field config "eip150Block" "0x0")
     :eip155-block (fixture-optional-quantity-field config "eip155Block" "0x0")
     :eip158-block (fixture-optional-quantity-field config "eip158Block" "0x0")
     :byzantium-block 0
     :constantinople-block 0
     :petersburg-block 0
     :istanbul-block 0
     :berlin-block (fixture-quantity-field config "berlinBlock")
     :london-block (fixture-quantity-field config "londonBlock")
     :shanghai-time (fixture-quantity-field config "shanghaiTime")
     :cancun-time (fixture-optional-time-field config "cancunTime")
     :prague-time (fixture-optional-time-field config "pragueTime")
     :osaka-time (fixture-optional-time-field config "osakaTime"))))

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

