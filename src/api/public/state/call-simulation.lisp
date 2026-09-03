(in-package #:ethereum-lisp.public-api)

;;;; Public JSON-RPC call simulation and eth_call response handling.

;; Solidity encodes `revert("reason")` as the Error(string) selector followed by
;; a standard ABI string: a 32-byte offset, a 32-byte length, then the bytes.
(defparameter +eth-rpc-error-string-selector+
  (hex-to-bytes "0x08c379a0"))

(defun eth-rpc-octets-to-string (octets)
  "Decode OCTETS as UTF-8, falling back to NIL when they are not valid UTF-8."
  #+sbcl
  (handler-case (sb-ext:octets-to-string octets :external-format :utf-8)
    (error () nil))
  #-sbcl
  (map 'string #'code-char octets))

(defun eth-rpc-decode-revert-reason (return-data)
  "Return the string carried by Error(string) revert data, or NIL.

Anything that is not exactly a well-formed Error(string) payload — a custom
error, truncated data, an out-of-range offset — yields NIL rather than a guess."
  (let ((bytes (ensure-byte-vector return-data)))
    ;; The shortest well-formed Error(string) payload is revert(""), which is
    ;; exactly 68 bytes: selector + 32-byte offset + 32-byte length of zero.
    (when (and (>= (length bytes) 68)
               (bytes= +eth-rpc-error-string-selector+ (subseq bytes 0 4)))
      (let ((offset (bytes-to-integer (subseq bytes 4 36)))
            (length (bytes-to-integer (subseq bytes 36 68))))
        ;; Only the canonical single-argument encoding is accepted.
        (when (and (= offset 32)
                   (<= (+ 68 length) (length bytes)))
          (eth-rpc-octets-to-string (subseq bytes 68 (+ 68 length))))))))

(defun eth-rpc-fail-execution-reverted (return-data)
  "Signal a reverted call as a JSON-RPC error carrying the revert bytes.

Mirrors go-ethereum: code 3, the revert reason appended to the message when it
decodes, and the raw revert data in the error object's data member."
  (let* ((bytes (ensure-byte-vector return-data))
         (reason (eth-rpc-decode-revert-reason bytes)))
    (engine-rpc-fail-with-data
     +engine-rpc-error-execution-reverted+
     (if reason
         (format nil "execution reverted: ~A" reason)
         "execution reverted")
     (bytes-to-hex bytes))))

(defun eth-rpc-override-storage-entry (state address slot-text value-text method)
  (state-db-set-storage
   state
   address
   (eth-rpc-storage-slot-param slot-text method)
   (bytes-to-integer
    (hash32-bytes
     (json-rpc-hash32 value-text "state override storage value")))))

(defun eth-rpc-apply-state-overrides (state overrides method)
  (when overrides
    (unless (json-object-p overrides)
      (block-validation-fail "~A state overrides must be an object" method))
    (dolist (entry overrides)
      (let* ((address
               (eth-rpc-address-param (car entry) method "override address"))
             (override (cdr entry)))
        (unless (json-object-p override)
          (block-validation-fail
           "~A account override must be an object" method))
        (when (and (json-object-field-present-p override "state")
                   (json-object-field-present-p override "stateDiff"))
          (block-validation-fail
           "~A account override cannot contain both state and stateDiff"
           method))
        (let* ((account (or (state-db-get-account state address)
                            (make-state-account)))
               (nonce
                 (if (json-object-field-present-p override "nonce")
                     (parse-json-quantity
                      (json-object-field override "nonce")
                      "state override nonce" :required-p t)
                     (state-account-nonce account)))
               (balance
                 (if (json-object-field-present-p override "balance")
                     (parse-json-quantity
                      (json-object-field override "balance")
                      "state override balance" :required-p t)
                     (state-account-balance account)))
               (code
                 (if (json-object-field-present-p override "code")
                     (json-rpc-bytes
                      (json-object-field override "code")
                      "state override code")
                     (state-db-get-code state address)))
               (state-object
                 (when (json-object-field-present-p override "state")
                   (json-object-field override "state")))
               (state-diff
                 (when (json-object-field-present-p override "stateDiff")
                   (json-object-field override "stateDiff"))))
          (when state-object
            (unless (json-object-p state-object)
              (block-validation-fail
               "~A state override state must be an object" method))
            (state-db-clear-account state address))
          (state-db-set-account
           state address
           (make-state-account :nonce nonce :balance balance))
          (state-db-set-code state address code)
          (dolist (storage-entry (or state-object state-diff))
            (eth-rpc-override-storage-entry
             state address (car storage-entry) (cdr storage-entry) method)))))
    state))

(defun eth-rpc-block-override-quantity
    (overrides name default)
  (if (and overrides (json-object-field-present-p overrides name))
      (parse-json-quantity
       (json-object-field overrides name)
       (format nil "block override ~A" name) :required-p t)
      default))

(defun eth-rpc-block-override-address
    (overrides name default method)
  (if (and overrides (json-object-field-present-p overrides name))
      (eth-rpc-address-param
       (json-object-field overrides name) method name)
      default))

(defun eth-rpc-block-override-hash
    (overrides name default)
  (if (and overrides (json-object-field-present-p overrides name))
      (json-rpc-hash32
       (json-object-field overrides name)
       (format nil "block override ~A" name))
      default))

(defun eth-rpc-simulate-intrinsic-gas (tx block block-overrides config)
  (let* ((header (block-header block))
         (number
           (eth-rpc-block-override-quantity
            block-overrides "number" (block-header-number header)))
         (timestamp
           (eth-rpc-block-override-quantity
            block-overrides "time" (block-header-timestamp header)))
         (rules (and config (chain-config-rules config number timestamp))))
    (ethereum-lisp.execution:transaction-intrinsic-gas
     tx
     :eip3860-p (or (null rules) (chain-rules-shanghai-p rules))
     :chain-rules rules)))

(defconstant +eth-rpc-max-account-nonce+ (1- (ash 1 64)))

(defun eth-rpc-simulation-account (state address)
  (or (state-db-get-account state address)
      (make-state-account)))

(defun eth-rpc-validate-simulation-nonce (state sender tx)
  "Reject a simulated transaction whose nonce cannot enter the current state."
  (let* ((account (eth-rpc-simulation-account state sender))
         (state-nonce (state-account-nonce account))
         (tx-nonce (transaction-nonce tx)))
    (cond
      ((< tx-nonce state-nonce)
       (engine-rpc-fail
        -38010
        (format nil "nonce too low: address ~A, tx: ~D state: ~D"
                (address-to-hex sender) tx-nonce state-nonce)))
      ((> tx-nonce state-nonce)
       (engine-rpc-fail
        -38011
        (format nil "nonce too high: address ~A, tx: ~D state: ~D"
                (address-to-hex sender) tx-nonce state-nonce)))
      ((= state-nonce +eth-rpc-max-account-nonce+)
       (engine-rpc-fail
        -32603
        (format nil "nonce has max value: address ~A, nonce: ~D (supplied gas ~D)"
                (address-to-hex sender)
                state-nonce
                (transaction-gas-limit tx)))))))

(defun eth-rpc-validate-simulation-funds (state sender tx)
  "Require SENDER to cover the simulated transaction's maximum upfront cost."
  (let* ((account (eth-rpc-simulation-account state sender))
         (balance (state-account-balance account))
         (required
           (+ (transaction-value tx)
              (* (transaction-gas-limit tx)
                 (transaction-max-fee-per-gas tx)))))
    (when (< balance required)
      (engine-rpc-fail
       -38014
       (format nil
               "insufficient funds for gas * price + value: address ~A ~
                have ~D want ~D (supplied gas ~D)"
               (address-to-hex sender)
               balance
               required
               (transaction-gas-limit tx))))))

(defun eth-rpc-charge-simulation-upfront
    (state sender tx base-fee eip1559-enabled-p)
  "Buy gas and advance SENDER before an included simulated transaction."
  (let* ((account (eth-rpc-simulation-account state sender))
         (gas-price
           (call-transaction-effective-gas-price
            tx :base-fee base-fee
               :eip1559-enabled-p eip1559-enabled-p)))
    (state-db-set-account
     state sender
     (make-state-account
      :nonce (mod (1+ (state-account-nonce account)) (ash 1 64))
      :balance (- (state-account-balance account)
                  (* (transaction-gas-limit tx) gas-price))
      :storage-root (state-account-storage-root account)
      :code-hash (state-account-code-hash account)))
    gas-price))

(defun eth-rpc-finalize-simulation-fees
    (state sender fee-recipient tx base-fee eip1559-enabled-p
     gas-used refund-counter rules)
  "Refund unused gas, burn the base fee, and credit the synthetic coinbase."
  (multiple-value-bind (billed-gas max-used-gas)
      (finalized-transaction-gas-values
       tx gas-used refund-counter rules)
    (let* ((gas-price
             (call-transaction-effective-gas-price
              tx :base-fee base-fee
                 :eip1559-enabled-p eip1559-enabled-p))
           (priority-fee-per-gas
             (if eip1559-enabled-p
                 (max 0 (- gas-price base-fee))
                 gas-price))
           (unused-gas (- (transaction-gas-limit tx) billed-gas)))
      (when (plusp unused-gas)
        (state-db-add-balance state sender (* unused-gas gas-price)))
      (when (plusp priority-fee-per-gas)
        (state-db-add-balance
         state fee-recipient (* billed-gas priority-fee-per-gas)))
      (values billed-gas max-used-gas))))

(defun eth-rpc-simulate-call-object
    (object block store config method
     &key gas-limit state-overrides block-overrides state
          intrinsic-gas-error-code base-fee-error-code commit-state-p
          validation-p)
  (when (and block-overrides (not (json-object-p block-overrides)))
    (block-validation-fail "~A block overrides must be an object" method))
  (unless (json-object-p object)
    (block-validation-fail "~A call object must be a JSON object" method))
  (handler-case
      (let* ((header (block-header block))
             (simulation-state
               (or state
                   (ethereum-lisp.execution-service:chain-store-state-db
                    store (block-hash block))))
             (simulate-v1-p (string= method "eth_simulateV1")))
        (eth-rpc-apply-state-overrides
         simulation-state state-overrides method)
        (let* ((default-sender
                 (or (eth-rpc-call-object-optional-address
                      object "from" method)
                     (zero-address)))
               (nonce-default
                 (if simulate-v1-p
                     (state-account-nonce
                      (eth-rpc-simulation-account
                       simulation-state default-sender))
                     0)))
          (multiple-value-bind (sender tx)
              (eth-rpc-call-object-transaction
               object header method config
               :gas-limit-override gas-limit
               :nonce-default nonce-default)
            (when (and simulate-v1-p validation-p)
              ;; Geth's state transition checks nonce mismatch/overflow before
              ;; intrinsic-gas and fee-cap admission. The standardized nonce
              ;; error must therefore win when several fields are invalid.
              (eth-rpc-validate-simulation-nonce
               simulation-state sender tx))
            (when intrinsic-gas-error-code
              (let ((intrinsic-gas
                      (eth-rpc-simulate-intrinsic-gas
                       tx block block-overrides config)))
                (when (< (transaction-gas-limit tx) intrinsic-gas)
                  (engine-rpc-fail
                   intrinsic-gas-error-code
                   (format nil
                           "intrinsic gas too low: have ~D, want ~D (supplied gas ~D)"
                           (transaction-gas-limit tx)
                           intrinsic-gas
                           (transaction-gas-limit tx))))))
            (when base-fee-error-code
              (let ((base-fee
                      (eth-rpc-block-override-quantity
                       block-overrides "baseFeePerGas"
                       (or (block-header-base-fee-per-gas header) 0))))
                (when (< (transaction-max-fee-per-gas tx) base-fee)
                  (engine-rpc-fail
                   base-fee-error-code
                   (format nil
                           "max fee per gas less than block base fee: address ~A, ~
                            maxFeePerGas: ~D, baseFee: ~D (supplied gas ~D)"
                           (address-to-hex sender)
                           (transaction-max-fee-per-gas tx)
                           base-fee
                           (transaction-gas-limit tx))))))
            (let* ((base-fee
                     (eth-rpc-block-override-quantity
                      block-overrides "baseFeePerGas"
                      (or (block-header-base-fee-per-gas header) 0)))
                   (block-number
                     (eth-rpc-block-override-quantity
                      block-overrides "number"
                      (block-header-number header)))
                   (block-timestamp
                     (eth-rpc-block-override-quantity
                      block-overrides "time"
                      (block-header-timestamp header)))
                   (rules
                     (and config
                          (chain-config-rules
                           config block-number block-timestamp)))
                   (eip1559-enabled-p
                     (or (null config)
                         (chain-config-london-p config block-number)))
                   (fee-recipient
                     (eth-rpc-block-override-address
                      block-overrides "feeRecipient"
                      (or (block-header-beneficiary header) (zero-address))
                      method)))
              (when simulate-v1-p
                (eth-rpc-validate-simulation-funds
                 simulation-state sender tx))
              ;; Transaction prechecks have passed. Buy gas and advance before
              ;; EVM execution so both effects survive a revert, while the
              ;; copied call-state still rolls later execution changes back.
              (when simulate-v1-p
                (eth-rpc-charge-simulation-upfront
                 simulation-state sender tx base-fee eip1559-enabled-p))
              (multiple-value-bind
                    (status return-data gas-used
                     accessed-addresses accessed-storage refund-counter)
                  (ethereum-lisp.execution:execute-message-call
                   simulation-state
                   sender
                   tx
                   :base-fee base-fee
                   :chain-id (if config (chain-config-chain-id config) 0)
                   :chain-config config
                   :coinbase fee-recipient
                   :timestamp block-timestamp
                   :block-number block-number
                   :prev-randao
                   (eth-rpc-block-override-hash
                    block-overrides "prevRandao"
                    (or (block-header-mix-hash header) (zero-hash32)))
                   :difficulty (block-header-difficulty header)
                   :random-p t
                   :commit-state-p commit-state-p
                   :context-gas-limit
                   (eth-rpc-block-override-quantity
                    block-overrides "gasLimit" (block-header-gas-limit header))
                   :block-hashes
                   (ethereum-lisp.execution-service:chain-store-block-hashes-for-header
                    store header))
                (if simulate-v1-p
                    (multiple-value-bind (billed-gas max-used-gas)
                        (eth-rpc-finalize-simulation-fees
                         simulation-state sender fee-recipient tx
                         base-fee eip1559-enabled-p gas-used
                         refund-counter rules)
                      (values status return-data billed-gas
                              accessed-addresses accessed-storage max-used-gas))
                    (values status return-data gas-used
                            accessed-addresses accessed-storage gas-used)))))))
    (ethereum-lisp.execution:transaction-validation-error ()
      (block-validation-fail
       "~A transaction is invalid" method))))

(defun engine-rpc-handle-eth-call (params store config)
  (unless (<= 1 (length params) 4)
    (block-validation-fail
     "eth_call params must contain call object, optional block id, state overrides, and block overrides"))
  (let* ((block (eth-rpc-state-block-param
                 (list (if (>= (length params) 2) (second params) "latest"))
                 store
                 "eth_call")))
    (multiple-value-bind (status return-data gas-used)
        (eth-rpc-simulate-call-object
         (first params) block store config "eth_call"
         :state-overrides (third params)
         :block-overrides (fourth params))
      (declare (ignore gas-used))
      (when (eq status :reverted)
        (eth-rpc-fail-execution-reverted return-data))
      (unless (eth-rpc-call-status-success-p status)
        (block-validation-fail "eth_call execution failed"))
      (bytes-to-hex return-data))))

(defconstant +eth-rpc-simulate-max-blocks+ 256)
(defconstant +eth-rpc-simulate-max-calls-per-block+ 5000)
(defconstant +eth-rpc-simulate-max-total-calls+ 10000)
(defconstant +eth-rpc-simulate-timestamp-increment+ 12)

(defun eth-rpc-validate-simulate-call-counts (block-state-calls)
  "Enforce Geth's per-block and request-wide eth_simulateV1 call budgets."
  (let ((total-calls 0))
    (dolist (block-state-call block-state-calls total-calls)
      (unless (json-object-p block-state-call)
        (block-validation-fail
         "eth_simulateV1 blockStateCalls entries must be objects"))
      (let ((calls
              (or (json-object-field block-state-call "calls")
                  (eth-rpc-json-array '()))))
        (unless (json-array-p calls)
          (block-validation-fail
           "eth_simulateV1 calls must be an array"))
        (let ((call-count (length (json-array-values calls))))
          (when (> call-count +eth-rpc-simulate-max-calls-per-block+)
            (engine-rpc-fail
             -38026
             (format nil "too many calls in block: ~D > ~D"
                     call-count +eth-rpc-simulate-max-calls-per-block+)))
          (incf total-calls call-count)
          (when (> total-calls +eth-rpc-simulate-max-total-calls+)
            (engine-rpc-fail
             -38026
             (format nil "too many calls: ~D > ~D"
                     total-calls +eth-rpc-simulate-max-total-calls+))))))))

(defun eth-rpc-simulate-boolean-option (payload name)
  (if (json-object-field-present-p payload name)
      (let ((value (json-object-field payload name)))
        (cond
          ((eq value t) t)
          ((json-false-p value) nil)
          (t
           (block-validation-fail
            "eth_simulateV1 ~A must be a boolean"
            name))))
      nil))

(defun eth-rpc-simulate-block-base-fee
    (parent-header block-overrides config validation-p)
  "Return the EIP-1559 base fee for one synthetic block, or NIL pre-London."
  (let ((number
          (eth-rpc-block-override-quantity
           block-overrides "number" (1+ (block-header-number parent-header)))))
    (cond
      ((json-object-field-present-p block-overrides "baseFeePerGas")
       (eth-rpc-block-override-quantity block-overrides "baseFeePerGas" 0))
      ((and config (not (chain-config-london-p config number)))
       nil)
      (validation-p
       (expected-base-fee-per-gas
        parent-header
        :london-parent-p
        (or (null config)
            (chain-config-london-p config
                                   (block-header-number parent-header)))))
      (t 0))))

(defun eth-rpc-simulated-block-state-call
    (block-state-call block-overrides number timestamp)
  "Copy BLOCK-STATE-CALL with explicit NUMBER and TIMESTAMP overrides."
  (let ((result
          (if (json-empty-object-p block-state-call)
              '()
              (copy-tree block-state-call)))
        (overrides
          (if (or (null block-overrides)
                  (json-empty-object-p block-overrides))
              '()
              (copy-tree block-overrides))))
    (setf overrides
          (eth-rpc-set-object-field
           overrides "number" (quantity-to-hex number)))
    (setf overrides
          (eth-rpc-set-object-field
           overrides "time" (quantity-to-hex timestamp)))
    (eth-rpc-set-object-field result "blockOverrides" overrides)))

(defun eth-rpc-sanitize-simulated-block-sequence (block-state-calls block)
  "Validate and expand the simulated block sequence.

Missing values advance from the preceding simulated block. Number gaps become
explicit empty blocks, and the expanded span remains bounded by
`+eth-rpc-simulate-max-blocks+`. This follows Execution APIs e5d1bb60's
`ethSimulate-add-more-non-defined-BlockStateCalls-than-fit*` fixtures."
  (let* ((header (block-header block))
         (base-number (block-header-number header))
         (previous-number base-number)
         (previous-timestamp (block-header-timestamp header))
         (result '()))
    (dolist (block-state-call block-state-calls (nreverse result))
      (unless (json-object-p block-state-call)
        (block-validation-fail
         "eth_simulateV1 blockStateCalls entries must be objects"))
      (let ((block-overrides
              (json-object-field block-state-call "blockOverrides")))
        (when (and block-overrides (not (json-object-p block-overrides)))
          (block-validation-fail
           "eth_simulateV1 block overrides must be an object"))
        (let ((number
                (eth-rpc-block-override-quantity
                 block-overrides "number" (1+ previous-number))))
          (when (<= number previous-number)
            (engine-rpc-fail
             -38020
             (format nil "block numbers must be in order: ~D <= ~D"
                     number previous-number)))
          (when (> (- number base-number) +eth-rpc-simulate-max-blocks+)
            (engine-rpc-fail -38026 "too many blocks"))
          (loop while (> number (1+ previous-number))
                do (incf previous-number)
                   (incf previous-timestamp
                         +eth-rpc-simulate-timestamp-increment+)
                   (push
                    (eth-rpc-simulated-block-state-call
                     +json-empty-object+ nil
                     previous-number previous-timestamp)
                    result))
          (let ((timestamp
                  (eth-rpc-block-override-quantity
                   block-overrides "time"
                   (+ previous-timestamp
                      +eth-rpc-simulate-timestamp-increment+))))
            (when (<= timestamp previous-timestamp)
              (engine-rpc-fail
               -38021
               (format nil "block timestamps must be in order: ~D <= ~D"
                       timestamp previous-timestamp)))
            (setf previous-number number
                  previous-timestamp timestamp)
            (push
             (eth-rpc-simulated-block-state-call
              block-state-call block-overrides number timestamp)
             result)))))))

(defun eth-rpc-simulate-call-result
    (call block store config state block-overrides gas-limit
     &key validation-p)
  (multiple-value-bind
        (status return-data gas-used accessed-addresses accessed-storage
         max-used-gas)
      (eth-rpc-simulate-call-object
       call block store config "eth_simulateV1"
       :gas-limit gas-limit
       :state state
       :block-overrides block-overrides
       :intrinsic-gas-error-code -38013
       :base-fee-error-code (and validation-p -38012)
       :commit-state-p t
       :validation-p validation-p)
    (declare (ignore accessed-addresses accessed-storage))
    (values
     (list
      (cons "status"
            (if (eth-rpc-call-status-success-p status) "0x1" "0x0"))
      (cons "returnData" (bytes-to-hex return-data))
      (cons "gasUsed" (quantity-to-hex gas-used))
      (cons "maxUsedGas" (quantity-to-hex max-used-gas))
      (cons "logs" (eth-rpc-json-array '())))
     gas-used)))

(defun eth-rpc-simulate-required-call-gas (call remaining-gas)
  (unless (json-object-p call)
    (block-validation-fail
     "eth_simulateV1 call object must be a JSON object"))
  (let ((required
          (if (json-object-field-present-p call "gas")
              (parse-json-quantity
               (json-object-field call "gas")
               "eth_simulateV1 gas"
               :required-p t)
              remaining-gas)))
    (when (> required remaining-gas)
      (engine-rpc-fail
       -38015
       (format nil "block gas limit reached: remaining: ~D, required: ~D"
               remaining-gas required)))
    required))

(defun eth-rpc-simulate-block-call-results
    (calls block store config state block-overrides block-gas-limit
     &key validation-p)
  (let ((remaining-gas block-gas-limit)
        (gas-used 0)
        (results '()))
    (dolist (call calls (values (nreverse results) gas-used))
      (let ((call-gas
              (eth-rpc-simulate-required-call-gas call remaining-gas)))
        (multiple-value-bind (result call-gas-used)
            (eth-rpc-simulate-call-result
             call block store config state block-overrides call-gas
             :validation-p validation-p)
          (incf gas-used call-gas-used)
          (decf remaining-gas call-gas-used)
          (push result results))))))

(defun eth-rpc-simulate-block-result
    (block results block-overrides index gas-used base-fee block-gas-limit
     state-root)
  (let* ((header (block-header block))
         (object (eth-rpc-block-object block nil))
         (number
           (eth-rpc-block-override-quantity
            block-overrides "number"
            (+ (block-header-number header) index 1)))
         (timestamp
           (eth-rpc-block-override-quantity
            block-overrides "time"
            (+ (block-header-timestamp header) index 1))))
    (eth-rpc-set-object-field object "number" (quantity-to-hex number))
    (eth-rpc-set-object-field object "timestamp" (quantity-to-hex timestamp))
    (eth-rpc-set-object-field
     object "gasLimit"
     (quantity-to-hex block-gas-limit))
    (when base-fee
      (eth-rpc-set-object-field
       object "baseFeePerGas" (quantity-to-hex base-fee)))
    (eth-rpc-set-object-field object "gasUsed" (quantity-to-hex gas-used))
    (eth-rpc-set-object-field object "stateRoot" (hash32-to-hex state-root))
    (eth-rpc-set-object-field object "hash" nil)
    (eth-rpc-set-object-field object "nonce" nil)
    (eth-rpc-set-object-field object "transactions" (eth-rpc-json-array '()))
    (append object (list (cons "calls" (eth-rpc-json-array results))))))

(defun engine-rpc-handle-eth-simulate-v1 (params store config)
  (unless (<= 1 (length params) 2)
    (block-validation-fail
     "eth_simulateV1 params must contain payload and optional block id"))
  (let ((payload (first params)))
    (unless (json-object-p payload)
      (block-validation-fail "eth_simulateV1 payload must be an object"))
    (let ((block-state-calls
            (json-object-field payload "blockStateCalls")))
      (unless (json-array-p block-state-calls)
        (block-validation-fail
         "eth_simulateV1 blockStateCalls must be an array"))
      (when (> (length (json-array-values block-state-calls))
               +eth-rpc-simulate-max-blocks+)
        (engine-rpc-fail -38026 "too many blocks"))
      (eth-rpc-validate-simulate-call-counts
       (json-array-values block-state-calls))
      (when (eq t (json-object-field payload "traceTransfers"))
        (block-validation-fail
         "eth_simulateV1 traceTransfers is not supported"))
      (let* ((block
               (eth-rpc-state-block-param
                (list (if (= 2 (length params)) (second params) "latest"))
                store "eth_simulateV1"))
             (state
               (ethereum-lisp.execution-service:chain-store-state-db
                store (block-hash block)))
             (validation-p
               (eth-rpc-simulate-boolean-option payload "validation"))
             (sanitized-block-state-calls
               (eth-rpc-sanitize-simulated-block-sequence
                (json-array-values block-state-calls) block)))
        (eth-rpc-json-array
         (loop for block-state-call in sanitized-block-state-calls
               with parent-header = (block-header block)
               for index from 0
               collect
               (progn
                 (unless (json-object-p block-state-call)
                   (block-validation-fail
                    "eth_simulateV1 blockStateCalls entries must be objects"))
                 (let* ((state-overrides
                          (json-object-field
                           block-state-call "stateOverrides"))
                        (block-overrides
                          (json-object-field
                           block-state-call "blockOverrides"))
                        (calls
                          (or (json-object-field block-state-call "calls")
                              (eth-rpc-json-array '())))
                        (number
                          (eth-rpc-block-override-quantity
                           block-overrides "number"
                           (1+ (block-header-number parent-header))))
                        (timestamp
                          (eth-rpc-block-override-quantity
                           block-overrides "time"
                           (1+ (block-header-timestamp parent-header))))
                        (block-gas-limit
                          (eth-rpc-block-override-quantity
                           block-overrides "gasLimit"
                           (block-header-gas-limit parent-header)))
                        (base-fee
                          (eth-rpc-simulate-block-base-fee
                           parent-header block-overrides config validation-p))
                        (effective-block-overrides
                          (if base-fee
                              (eth-rpc-set-object-field
                               (copy-tree block-overrides)
                               "baseFeePerGas"
                               (quantity-to-hex base-fee))
                              block-overrides)))
                   (unless (json-array-p calls)
                     (block-validation-fail
                      "eth_simulateV1 calls must be an array"))
                   (eth-rpc-apply-state-overrides
                    state state-overrides "eth_simulateV1")
                   (multiple-value-bind (results gas-used)
                       (eth-rpc-simulate-block-call-results
                        (json-array-values calls)
                        block store config state effective-block-overrides
                        block-gas-limit
                        :validation-p validation-p)
                     (prog1
                         (eth-rpc-simulate-block-result
                          block results block-overrides index gas-used
                          base-fee block-gas-limit (state-db-root state))
                       (setf parent-header
                             (make-block-header
                              :number number
                              :timestamp timestamp
                              :gas-limit block-gas-limit
                              :gas-used gas-used
                              :base-fee-per-gas base-fee
                              :state-root (state-db-root state)))))))))))))
