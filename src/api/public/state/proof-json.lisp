(in-package #:ethereum-lisp.state-proof-json)

;;;; JSON-RPC object conversion for state proof results.

(defun state-proof-node-hex-list (proof)
  (mapcar #'bytes-to-hex proof))

(defun state-storage-proof-rpc-object (proof)
  (unless (typep proof 'state-storage-proof)
    (error "Storage proof entry must be a state-storage-proof"))
  (list (cons "key" (hash32-to-hex (state-storage-proof-slot proof)))
        (cons "value" (quantity-to-hex (state-storage-proof-value proof)))
        (cons "proof" (state-proof-node-hex-list
                       (state-storage-proof-proof proof)))))

(defun state-proof-result-rpc-object (proof)
  (unless (typep proof 'state-proof-result)
    (error "State proof must be a state-proof-result"))
  (list (cons "address" (address-to-hex (state-proof-result-address proof)))
        (cons "accountProof"
              (state-proof-node-hex-list
               (state-proof-result-account-proof proof)))
        (cons "balance" (quantity-to-hex (state-proof-result-balance proof)))
        (cons "codeHash" (hash32-to-hex (state-proof-result-code-hash proof)))
        (cons "nonce" (quantity-to-hex (state-proof-result-nonce proof)))
        (cons "storageHash"
              (hash32-to-hex (state-proof-result-storage-root proof)))
        (cons "storageProof"
              (mapcar #'state-storage-proof-rpc-object
                      (state-proof-result-storage-proofs proof)))))

(defun state-proof-rpc-required-field (object field label)
  (unless (listp object)
    (error "~A must be a JSON object" label))
  (let ((entry (assoc field object :test #'string=)))
    (unless entry
      (error "~A is missing ~A" label field))
    (cdr entry)))

(defun state-proof-rpc-string-field (object field label)
  (let ((value (state-proof-rpc-required-field object field label)))
    (unless (stringp value)
      (error "~A.~A must be a string" label field))
    value))

(defun state-proof-rpc-node-list (object field label)
  (let ((nodes (state-proof-rpc-required-field object field label)))
    (unless (listp nodes)
      (error "~A.~A must be a list" label field))
    (mapcar (lambda (node)
              (unless (stringp node)
                (error "~A.~A entries must be hex strings" label field))
              (hex-to-bytes node))
            nodes)))

(defun state-proof-rpc-storage-key (value)
  (unless (stringp value)
    (error "Storage proof key must be a string"))
  (let* ((digits (if (and (>= (length value) 2)
                          (char= (char value 0) #\0)
                          (member (char value 1) '(#\x #\X)))
                     (subseq value 2)
                     value))
         (normalized
           (concatenate 'string
                        "0x"
                        (if (oddp (length digits))
                            (concatenate 'string "0" digits)
                            digits)))
         (bytes (hex-to-bytes normalized)))
    (when (> (length bytes) 32)
      (error "Storage proof key is wider than 32 bytes"))
    (let ((padded (make-byte-vector 32)))
      (replace padded bytes :start1 (- 32 (length bytes)))
      (make-hash32 padded))))

(defun state-storage-proof-from-rpc-object (object)
  (make-state-storage-proof
   :slot (state-proof-rpc-storage-key
          (state-proof-rpc-string-field object "key" "Storage proof"))
   :value (hex-to-quantity
           (state-proof-rpc-string-field object "value" "Storage proof"))
   :proof (state-proof-rpc-node-list object "proof" "Storage proof")))

(defun state-proof-result-from-rpc-object (object)
  (make-state-proof-result
   :address (address-from-hex
             (state-proof-rpc-string-field object "address" "State proof"))
   :nonce (hex-to-quantity
           (state-proof-rpc-string-field object "nonce" "State proof"))
   :balance (hex-to-quantity
             (state-proof-rpc-string-field object "balance" "State proof"))
   :code-hash (hash32-from-hex
               (state-proof-rpc-string-field object "codeHash" "State proof"))
   :storage-root
   (hash32-from-hex
    (state-proof-rpc-string-field object "storageHash" "State proof"))
   :account-proof (state-proof-rpc-node-list
                   object "accountProof" "State proof")
   :storage-proofs
   (let ((storage-proofs
           (state-proof-rpc-required-field
            object "storageProof" "State proof")))
     (unless (listp storage-proofs)
       (error "State proof.storageProof must be a list"))
     (mapcar #'state-storage-proof-from-rpc-object storage-proofs))))
