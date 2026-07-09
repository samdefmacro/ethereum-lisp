(in-package #:ethereum-lisp.core)

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
