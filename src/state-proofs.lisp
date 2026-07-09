(in-package #:ethereum-lisp.state)

(defun rlp-uint256-value (value label)
  (unless (typep value 'byte-vector)
    (error "~A must be an RLP byte string" label))
  (let ((integer (bytes-to-integer value)))
    (ensure-state-uint256 integer label)))

(defun decode-state-account-rlp (bytes)
  (let ((decoded (rlp-decode-one bytes)))
    (unless (typep decoded 'rlp-list)
      (error "State account proof value must decode to an RLP list"))
    (let ((items (rlp-list-items decoded)))
      (unless (= 4 (length items))
        (error "State account proof value must contain four fields, got ~D"
               (length items)))
      (destructuring-bind (nonce balance storage-root code-hash) items
        (make-state-account
         :nonce (rlp-uint256-value nonce "Account nonce")
         :balance (rlp-uint256-value balance "Account balance")
         :storage-root (make-hash32 storage-root)
         :code-hash (make-hash32 code-hash))))))

(defun decode-storage-value-rlp (bytes)
  (rlp-uint256-value (rlp-decode-one bytes) "Storage proof value"))

(defun copy-state-proof-nodes (proof)
  (mapcar (lambda (node)
            (copy-seq (ensure-byte-vector node)))
          proof))

(defun copy-state-proof-address (address)
  (make-address (copy-seq (address-bytes address))))

(defun copy-state-proof-hash32 (hash)
  (make-hash32 (copy-seq (hash32-bytes hash))))

(defun account-proof-result-account (result)
  (make-state-account
   :nonce (state-proof-result-nonce result)
   :balance (state-proof-result-balance result)
   :storage-root (state-proof-result-storage-root result)
   :code-hash (state-proof-result-code-hash result)))

(defun state-storage-proof-for-slot (state address slot)
  (make-state-storage-proof
   :slot (copy-state-proof-hash32 slot)
   :value (state-db-get-storage state address slot)
   :proof (copy-state-proof-nodes
           (state-db-get-storage-proof state address slot))))

(defun state-db-get-proof (state address slots)
  (let ((account (or (state-db-get-account state address)
                     (make-state-account))))
    (make-state-proof-result
     :address (copy-state-proof-address address)
     :nonce (state-account-nonce account)
     :balance (state-account-balance account)
     :storage-root (copy-state-proof-hash32
                    (state-account-storage-root account))
     :code-hash (copy-state-proof-hash32
                 (state-account-code-hash account))
     :account-proof (copy-state-proof-nodes
                     (state-db-get-account-proof state address))
     :storage-proofs
     (mapcar (lambda (slot)
               (state-storage-proof-for-slot state address slot))
             slots))))

(defun ensure-state-account-equal (expected actual)
  (unless (and (= (state-account-nonce expected) (state-account-nonce actual))
               (= (state-account-balance expected) (state-account-balance actual))
               (bytes= (hash32-bytes (state-account-storage-root expected))
                       (hash32-bytes (state-account-storage-root actual)))
               (bytes= (hash32-bytes (state-account-code-hash expected))
                       (hash32-bytes (state-account-code-hash actual))))
    (error "State proof account fields do not match account proof value"))
  t)

(defun state-db-verify-proof (state-root proof)
  (unless (typep proof 'state-proof-result)
    (error "State proof must be a state-proof-result"))
  (multiple-value-bind (account-rlp present-p)
      (state-db-verify-account-proof
       state-root
       (state-proof-result-address proof)
       (state-proof-result-account-proof proof))
    (let ((expected-account (account-proof-result-account proof)))
      (if present-p
          (ensure-state-account-equal expected-account
                                      (decode-state-account-rlp account-rlp))
          (ensure-state-account-equal expected-account
                                      (make-state-account)))))
  (dolist (storage-proof (state-proof-result-storage-proofs proof) t)
    (unless (typep storage-proof 'state-storage-proof)
      (error "Storage proof entry must be a state-storage-proof"))
    (multiple-value-bind (value-rlp present-p)
        (state-db-verify-storage-proof
         (state-proof-result-storage-root proof)
         (state-storage-proof-slot storage-proof)
         (state-storage-proof-proof storage-proof))
      (let ((expected-value (state-storage-proof-value storage-proof)))
        (unless (if present-p
                    (= expected-value (decode-storage-value-rlp value-rlp))
                    (zerop expected-value))
          (error "State proof storage value does not match storage proof"))))))

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
