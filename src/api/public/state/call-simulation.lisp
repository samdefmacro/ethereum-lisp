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
    (when (and (>= (length bytes) 100)
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

(defun eth-rpc-simulate-call-object
    (object block store config method &key gas-limit)
  (multiple-value-bind (sender tx)
      (eth-rpc-call-object-transaction
       object (block-header block) method config
       :gas-limit-override gas-limit)
    (handler-case
        (ethereum-lisp.execution:execute-message-call
         (ethereum-lisp.execution-service:chain-store-state-db
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
         :context-gas-limit (block-header-gas-limit (block-header block))
         :block-hashes
         (ethereum-lisp.execution-service:chain-store-block-hashes-for-header
          store (block-header block)))
      (ethereum-lisp.execution:transaction-validation-error ()
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
      (when (eq status :reverted)
        (eth-rpc-fail-execution-reverted return-data))
      (unless (eth-rpc-call-status-success-p status)
        (block-validation-fail "eth_call execution failed"))
      (bytes-to-hex return-data))))
