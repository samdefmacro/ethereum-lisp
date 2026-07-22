(in-package #:ethereum-lisp.public-api)

(defun eth-rpc-precompile-access-key-p (key rules)
  "True when KEY is a precompile that is active under RULES.

RULES must describe the fork the call was simulated against. Treating every
precompile address as always present would omit addresses that are ordinary
accounts before their precompile activates — 0x0b..0x11 before Prague and 0x100
before Osaka — and those touches belong in a reported access list."
  (and (= (length key) 20)
       (ethereum-lisp.evm:active-precompile-address-p (make-address key) rules)))

(defun eth-rpc-implicit-access-key-p (key sender recipient coinbase rules)
  (or (and sender (bytes= key (address-bytes sender)))
      (and recipient (bytes= key (address-bytes recipient)))
      (and coinbase (bytes= key (address-bytes coinbase)))
      (eth-rpc-precompile-access-key-p key rules)))

(defun eth-rpc-access-list-groups (accessed-addresses accessed-storage)
  (let ((groups (make-hash-table :test 'equalp)))
    (labels ((ensure-group (address-hex)
               (or (gethash address-hex groups)
                   (setf (gethash address-hex groups)
                         (make-hash-table :test 'equalp)))))
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
    (accessed-addresses accessed-storage sender recipient coinbase rules)
  (let ((groups (eth-rpc-access-list-groups
                 accessed-addresses accessed-storage)))
    (loop for address-hex being the hash-keys of groups
          using (hash-value slots)
          unless (and (zerop (hash-table-count slots))
                      (eth-rpc-implicit-access-key-p
                       (hex-to-bytes address-hex)
                       sender recipient coinbase rules))
            collect
            (list
             (cons "address" address-hex)
             (cons "storageKeys"
                   (eth-rpc-json-array
                    (sort
                     (loop for slot being the hash-keys of slots collect slot)
                     #'string<))))
              into entries
          finally
             (return
               ;; An access list with every entry filtered out is empty, not
               ;; absent, so it must serialise as [] rather than null.
               (eth-rpc-json-array
                (sort entries
                      #'string<
                      :key (lambda (entry)
                             (cdr (assoc "address" entry :test #'string=)))))))))

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
                    (zero-address))
                (and config
                     (chain-config-rules
                      config
                      (block-header-number (block-header block))
                      (block-header-timestamp (block-header block))))))
         (cons "gasUsed" (quantity-to-hex gas-used)))))))
