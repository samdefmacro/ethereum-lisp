(in-package #:ethereum-lisp.execution)

;;;; Protocol-level calls that run outside the ordinary transaction list.

(defparameter +protocol-system-address+
  (address-from-hex "0xfffffffffffffffffffffffffffffffffffffffe"))

(defparameter +beacon-roots-address+
  (address-from-hex "0x000f3df6d732807ef1319fb7b8bb8522d0beac02"))

(defparameter +history-storage-address+
  (address-from-hex "0x0000f90827f1c53a10cb7a02335b175320002935"))

(defconstant +protocol-system-call-gas-limit+ 30000000)

(defun protocol-system-call-accessed-addresses (target)
  (let ((accessed-addresses (make-hash-table :test 'equalp)))
    ;; geth prepares protocol calls with zero sender/coinbase values and then
    ;; explicitly warms the system contract target.
    (prewarm-execution-address accessed-addresses (zero-address))
    (prewarm-execution-address accessed-addresses target)
    accessed-addresses))

(defun execute-protocol-system-call
    (state target input header chain-rules
     &key (caller +protocol-system-address+)
          (gas-limit +protocol-system-call-gas-limit+)
          (blob-base-fee 0)
          (block-hashes (make-hash-table))
          (require-code-p nil)
          (require-success-p nil))
  "Execute a protocol call without transaction accounting or a receipt.

The target is warm at call entry.  A revert or EVM execution error rolls back
only this call. REQUIRE-CODE-P rejects an empty target and REQUIRE-SUCCESS-P
rejects execution failure for protocol calls whose EIPs mandate both."
  (let ((code (if (or (null chain-rules)
                      (chain-rules-prague-p chain-rules))
                  (execution-resolved-code state target)
                  (state-db-get-code state target))))
    (when (and require-code-p (zerop (length code)))
      (block-validation-fail
       "Required protocol system contract ~A has no code"
       (address-to-hex target)))
    (when (plusp (length code))
      (let* ((snapshot (state-db-copy state))
             (context
               (make-evm-context
                :state state
                :address target
                :caller caller
                :origin caller
                :call-value 0
                :gas-price 0
                :input (ensure-byte-vector input)
                :coinbase (or (block-header-beneficiary header)
                              (zero-address))
                :timestamp (block-header-timestamp header)
                :block-number (block-header-number header)
                :prev-randao (or (block-header-mix-hash header)
                                  (zero-hash32))
                :difficulty (block-header-difficulty header)
                :random-p (block-header-post-merge-p header)
                :gas-limit (block-header-gas-limit header)
                :chain-id (if chain-rules
                              (chain-rules-chain-id chain-rules)
                              0)
                :chain-rules chain-rules
                :base-fee (or (block-header-base-fee-per-gas header) 0)
                :blob-base-fee blob-base-fee
                :block-hashes block-hashes
                :accessed-addresses
                (protocol-system-call-accessed-addresses target))))
        (flet ((rollback-failed-call (&optional result)
                 (state-db-restore state snapshot)
                 (when require-success-p
                   (block-validation-fail
                    "Protocol system call to ~A failed"
                    (address-to-hex target)))
                 result))
          (handler-case
              (let ((result
                      (execute-bytecode code
                                        :context context
                                        :gas-limit gas-limit
                                        :max-steps (1+ gas-limit))))
                (if (eq (evm-result-status result) :reverted)
                    (rollback-failed-call result)
                    (finalize-evm-selfdestructs state context))
                result)
            (evm-error ()
              (rollback-failed-call))))))))

(defun process-parent-beacon-block-root
    (state header chain-rules
     &key (blob-base-fee 0) (block-hashes (make-hash-table)))
  "Apply the EIP-4788 parent beacon block root transition when active."
  (when (and (plusp (block-header-number header))
             (if chain-rules
                 (chain-rules-cancun-p chain-rules)
                 (block-header-parent-beacon-root header)))
    (let ((parent-beacon-root (block-header-parent-beacon-root header)))
      (unless parent-beacon-root
        (error 'block-validation-error
               :message "Header is missing parent beacon root"))
      (execute-protocol-system-call
       state
       +beacon-roots-address+
       (hash32-bytes parent-beacon-root)
       header
       chain-rules
       :blob-base-fee blob-base-fee
       :block-hashes block-hashes)))
  state)

(defun process-parent-block-hash-history
    (state header chain-rules
     &key (blob-base-fee 0) (block-hashes (make-hash-table)))
  "Apply the EIP-2935 parent block hash transition when active."
  (when (and (plusp (block-header-number header))
             (if chain-rules
                 (or (chain-rules-prague-p chain-rules)
                     (chain-rules-ubt-p chain-rules))
                 (block-header-requests-hash header)))
    (let ((parent-hash (block-header-parent-hash header)))
      (unless parent-hash
        (block-validation-fail
         "Header is missing parent hash for EIP-2935"))
      (execute-protocol-system-call
       state
       +history-storage-address+
       (hash32-bytes parent-hash)
       header
       chain-rules
       :blob-base-fee blob-base-fee
       :block-hashes block-hashes)))
  state)
