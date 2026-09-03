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

(defun eth-rpc-simulate-call-object
    (object block store config method
     &key gas-limit state-overrides block-overrides state)
  (when (and block-overrides (not (json-object-p block-overrides)))
    (block-validation-fail "~A block overrides must be an object" method))
  (multiple-value-bind (sender tx)
      (eth-rpc-call-object-transaction
       object (block-header block) method config
       :gas-limit-override gas-limit)
    (handler-case
        (let* ((header (block-header block))
               (simulation-state
                 (or state
                 (ethereum-lisp.execution-service:chain-store-state-db
                  store (block-hash block)))))
          (eth-rpc-apply-state-overrides
           simulation-state state-overrides method)
          (ethereum-lisp.execution:execute-message-call
           simulation-state
           sender
           tx
           :base-fee
           (eth-rpc-block-override-quantity
            block-overrides "baseFeePerGas"
            (or (block-header-base-fee-per-gas header) 0))
           :chain-id (if config (chain-config-chain-id config) 0)
           :chain-config config
           :coinbase
           (eth-rpc-block-override-address
            block-overrides "feeRecipient"
            (or (block-header-beneficiary header) (zero-address))
            method)
           :timestamp
           (eth-rpc-block-override-quantity
            block-overrides "time" (block-header-timestamp header))
           :block-number
           (eth-rpc-block-override-quantity
            block-overrides "number" (block-header-number header))
           :prev-randao
           (eth-rpc-block-override-hash
            block-overrides "prevRandao"
            (or (block-header-mix-hash header) (zero-hash32)))
           :difficulty (block-header-difficulty header)
           :random-p t
           :context-gas-limit
           (eth-rpc-block-override-quantity
            block-overrides "gasLimit" (block-header-gas-limit header))
           :block-hashes
           (ethereum-lisp.execution-service:chain-store-block-hashes-for-header
            store header)))
      (ethereum-lisp.execution:transaction-validation-error ()
        (block-validation-fail
         "~A transaction is invalid" method)))))

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

(defun eth-rpc-simulate-call-result
    (call block store config state block-overrides)
  (multiple-value-bind
        (status return-data gas-used accessed-addresses accessed-storage)
      (eth-rpc-simulate-call-object
       call block store config "eth_simulateV1"
       :state state
       :block-overrides block-overrides)
    (declare (ignore accessed-addresses accessed-storage))
    (list
     (cons "status"
           (if (eth-rpc-call-status-success-p status) "0x1" "0x0"))
     (cons "returnData" (bytes-to-hex return-data))
     (cons "gasUsed" (quantity-to-hex gas-used))
     (cons "logs" (eth-rpc-json-array '())))))

(defun eth-rpc-simulate-block-result
    (block calls results block-overrides index)
  (declare (ignore calls))
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
     (quantity-to-hex
      (eth-rpc-block-override-quantity
       block-overrides "gasLimit" (block-header-gas-limit header))))
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
      (when (eq t (json-object-field payload "traceTransfers"))
        (block-validation-fail
         "eth_simulateV1 traceTransfers is not supported"))
      (let* ((block
               (eth-rpc-state-block-param
                (list (if (= 2 (length params)) (second params) "latest"))
                store "eth_simulateV1"))
             (state
               (ethereum-lisp.execution-service:chain-store-state-db
                store (block-hash block))))
        (eth-rpc-json-array
         (loop for block-state-call
                 in (json-array-values block-state-calls)
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
                              (eth-rpc-json-array '()))))
                   (unless (json-array-p calls)
                     (block-validation-fail
                      "eth_simulateV1 calls must be an array"))
                   (eth-rpc-apply-state-overrides
                    state state-overrides "eth_simulateV1")
                   (eth-rpc-simulate-block-result
                    block
                    (json-array-values calls)
                    (loop for call in (json-array-values calls)
                          collect
                          (eth-rpc-simulate-call-result
                           call block store config state block-overrides))
                    block-overrides index)))))))))
