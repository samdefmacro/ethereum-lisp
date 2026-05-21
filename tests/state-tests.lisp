(in-package #:ethereum-lisp.test)

(defparameter +phase-a-shanghai-genesis-fixture-path+
  "tests/fixtures/execution-spec-tests/phase-a-shanghai-genesis.json")

(defparameter +phase-a-shanghai-genesis-fixture-format+
  "ethereum-lisp/phase-a-shanghai-genesis-fixture-v1")

(defparameter +phase-a-shanghai-genesis-top-level-fields+
  '("format"
    "source"
    "executionSpecTests"
    "config"
    "nonce"
    "timestamp"
    "extraData"
    "gasLimit"
    "difficulty"
    "mixHash"
    "coinbase"
    "stateRoot"
    "alloc"))

(defparameter +phase-a-shanghai-genesis-config-fields+
  '("chainId"
    "terminalTotalDifficulty"
    "londonBlock"
    "shanghaiTime"))

(defparameter +phase-a-shanghai-genesis-account-fields+
  '("balance" "nonce" "code" "storage"))

(defun validate-phase-a-shanghai-genesis-object-fields
    (object allowed-fields label)
  (unless (listp object)
    (error "~A must be a JSON object" label))
  (let ((seen-fields (make-hash-table :test 'equal)))
    (dolist (field object)
      (let ((name (car field)))
        (unless (stringp name)
          (error "~A field name must be a string" label))
        (when (gethash name seen-fields)
          (error "~A has duplicate field ~A" label name))
        (setf (gethash name seen-fields) t)
        (unless (member name allowed-fields :test #'string=)
          (error "~A has unknown field ~A" label name))))))

(defun validate-phase-a-shanghai-genesis-non-empty-string (value label)
  (unless (stringp value)
    (error "~A must be a string" label))
  (when (blank-string-p value)
    (error "~A must be present" label))
  value)

(defun validate-phase-a-shanghai-genesis-hex-string (value label)
  (unless (stringp value)
    (error "~A must be a hex string" label))
  (hex-to-bytes value))

(defun validate-phase-a-shanghai-genesis-hash-string (value label)
  (unless (stringp value)
    (error "~A must be a hash hex string" label))
  (hash32-from-hex value))

(defun validate-phase-a-shanghai-genesis-address-string (value label)
  (unless (stringp value)
    (error "~A must be an address hex string" label))
  (address-from-hex value))

(defun validate-phase-a-shanghai-genesis-non-negative-value
    (object field label &key required-p)
  (let ((present-p (fixture-field-present-p object field))
        (value (fixture-object-field object field)))
    (when (or present-p required-p)
      (unless (or (and (integerp value) (not (minusp value)))
                  (and (stringp value)
                       (not (minusp (hex-to-quantity value)))))
        (error "~A field ~A must be a non-negative integer or hex quantity"
               label
               field)))))

(defun validate-phase-a-shanghai-genesis-config-shape (config)
  (validate-phase-a-shanghai-genesis-object-fields
   config
   +phase-a-shanghai-genesis-config-fields+
   "Phase A Shanghai genesis config")
  (dolist (field +phase-a-shanghai-genesis-config-fields+)
    (validate-phase-a-shanghai-genesis-non-negative-value
     config
     field
     "Phase A Shanghai genesis config"
     :required-p t)))

(defun validate-phase-a-shanghai-genesis-storage-shape (storage address)
  (unless (listp storage)
    (error "Phase A Shanghai genesis account ~A storage must be a JSON object"
           address))
  (let ((seen-slots (make-hash-table :test 'equal)))
    (dolist (entry storage)
      (let ((slot (car entry)))
        (unless (stringp slot)
          (error "Phase A Shanghai genesis account ~A has malformed storage slot ~A"
                 address
                 slot))
        (let ((slot-id (quantity-to-hex (hex-to-quantity slot))))
          (when (gethash slot-id seen-slots)
            (error "Phase A Shanghai genesis account ~A storage has duplicate slot ~A"
                   address
                   slot))
          (setf (gethash slot-id seen-slots) t))
        (let ((value (cdr entry)))
          (unless (or (and (integerp value) (not (minusp value)))
                      (and (stringp value)
                           (not (minusp (hex-to-quantity value)))))
            (error "Phase A Shanghai genesis account ~A storage slot ~A has malformed value ~A"
                   address
                   slot
                   value)))))))

(defun validate-phase-a-shanghai-genesis-account-shape (address account)
  (validate-phase-a-shanghai-genesis-address-string
   address
   "Phase A Shanghai genesis account address")
  (validate-phase-a-shanghai-genesis-object-fields
   account
   +phase-a-shanghai-genesis-account-fields+
   (format nil "Phase A Shanghai genesis account ~A" address))
  (validate-phase-a-shanghai-genesis-non-negative-value
   account
   "balance"
   (format nil "Phase A Shanghai genesis account ~A" address)
   :required-p t)
  (validate-phase-a-shanghai-genesis-non-negative-value
   account
   "nonce"
   (format nil "Phase A Shanghai genesis account ~A" address))
  (when (fixture-field-present-p account "code")
    (validate-phase-a-shanghai-genesis-hex-string
     (fixture-required-field account "code")
     (format nil "Phase A Shanghai genesis account ~A code" address)))
  (when (fixture-field-present-p account "storage")
    (validate-phase-a-shanghai-genesis-storage-shape
     (fixture-object-field account "storage")
     address)))

(defun validate-phase-a-shanghai-genesis-alloc-shape (alloc)
  (unless (and (listp alloc) alloc)
    (error "Phase A Shanghai genesis alloc must be a non-empty JSON object"))
  (let ((seen-addresses (make-hash-table :test 'equal)))
    (dolist (entry alloc)
      (let ((address (car entry)))
        (unless (stringp address)
          (error "Phase A Shanghai genesis alloc address must be a string"))
        (let ((address-id
                (address-to-hex
                 (validate-phase-a-shanghai-genesis-address-string
                  address
                  "Phase A Shanghai genesis alloc address"))))
          (when (gethash address-id seen-addresses)
            (error "Phase A Shanghai genesis alloc has duplicate address ~A"
                   address))
          (setf (gethash address-id seen-addresses) t))
        (validate-phase-a-shanghai-genesis-account-shape
         address
         (cdr entry))))))

(defun validate-phase-a-shanghai-genesis-fixture-shape (fixture)
  (validate-phase-a-shanghai-genesis-object-fields
   fixture
   +phase-a-shanghai-genesis-top-level-fields+
   "Phase A Shanghai genesis fixture")
  (dolist (field +phase-a-shanghai-genesis-top-level-fields+)
    (fixture-required-field fixture field))
  (validate-fixture-format fixture +phase-a-shanghai-genesis-fixture-format+)
  (validate-phase-a-shanghai-genesis-non-empty-string
   (fixture-required-field fixture "source")
   "Phase A Shanghai genesis fixture source")
  (validate-fixture-pinned-eest-source fixture)
  (validate-phase-a-shanghai-genesis-config-shape
   (fixture-required-field fixture "config"))
  (dolist (field '("nonce" "timestamp" "gasLimit" "difficulty"))
    (validate-phase-a-shanghai-genesis-non-negative-value
     fixture
     field
     "Phase A Shanghai genesis fixture"
     :required-p t))
  (validate-phase-a-shanghai-genesis-hex-string
   (fixture-required-field fixture "extraData")
   "Phase A Shanghai genesis fixture extraData")
  (validate-phase-a-shanghai-genesis-hash-string
   (fixture-required-field fixture "mixHash")
   "Phase A Shanghai genesis fixture mixHash")
  (validate-phase-a-shanghai-genesis-address-string
   (fixture-required-field fixture "coinbase")
   "Phase A Shanghai genesis fixture coinbase")
  (validate-phase-a-shanghai-genesis-hash-string
   (fixture-required-field fixture "stateRoot")
   "Phase A Shanghai genesis fixture stateRoot")
  (validate-phase-a-shanghai-genesis-alloc-shape
   (fixture-required-field fixture "alloc")))

(deftest state-empty-root
  (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
               (state-db-root-hex (make-state-db)))))

(deftest state-account-root-is-deterministic
  (let ((state (make-state-db))
        (address (address-from-hex "0x0000000000000000000000000000000000000001")))
    (state-db-set-account state address
                          (make-state-account :nonce 1 :balance 1000))
    (is (state-db-get-account state address))
    (is (string= (state-db-root-hex state) (state-db-root-hex state)))))

(deftest state-account-proof-verifies-present-missing-and-bad-root
  (let ((state (make-state-db))
        (address (address-from-hex "0x0000000000000000000000000000000000000010"))
        (missing-address (address-from-hex "0x0000000000000000000000000000000000000011")))
    (state-db-set-account state address
                          (make-state-account :nonce 1 :balance 1000))
    (multiple-value-bind (account-rlp present-p)
        (state-db-verify-account-proof
         (state-db-root state)
         address
         (state-db-get-account-proof state address))
      (is present-p)
      (is (bytes= (state-account-rlp (state-db-get-account state address))
                  account-rlp)))
    (multiple-value-bind (account-rlp present-p)
        (state-db-verify-account-proof
         (state-db-root state)
         missing-address
         (state-db-get-account-proof state missing-address))
      (is (null present-p))
      (is (null account-rlp)))
    (signals error
      (state-db-verify-account-proof
       (zero-hash32)
       address
       (state-db-get-account-proof state address)))))

(deftest state-storage-roundtrip-and-delete
  (let ((state (make-state-db))
        (address (address-from-hex "0x0000000000000000000000000000000000000002"))
        (slot (hash32-from-hex
               "0x0000000000000000000000000000000000000000000000000000000000000007")))
    (state-db-set-storage state address slot 99)
    (is (= 99 (state-db-get-storage state address slot)))
    (state-db-set-storage state address slot 0)
    (is (= 0 (state-db-get-storage state address slot)))))

(deftest state-storage-proof-verifies-present-missing-and-bad-root
  (let ((state (make-state-db))
        (address (address-from-hex "0x0000000000000000000000000000000000000012"))
        (slot (hash32-from-hex
               "0x000000000000000000000000000000000000000000000000000000000000000c"))
        (missing-slot (hash32-from-hex
                       "0x000000000000000000000000000000000000000000000000000000000000000d")))
    (state-db-set-storage state address slot 42)
    (multiple-value-bind (value-rlp present-p)
        (state-db-verify-storage-proof
         (state-db-get-storage-root state address)
         slot
         (state-db-get-storage-proof state address slot))
      (is present-p)
      (is (bytes= (rlp-encode 42) value-rlp)))
    (multiple-value-bind (value-rlp present-p)
        (state-db-verify-storage-proof
         (state-db-get-storage-root state address)
         missing-slot
         (state-db-get-storage-proof state address missing-slot))
      (is (null present-p))
      (is (null value-rlp)))
    (signals error
      (state-db-verify-storage-proof
       (zero-hash32)
       slot
       (state-db-get-storage-proof state address slot)))))

(deftest state-proof-result-builds-and-verifies-account-and-storage-proofs
  (let ((state (make-state-db))
        (address (address-from-hex "0x0000000000000000000000000000000000000013"))
        (slot (hash32-from-hex
               "0x000000000000000000000000000000000000000000000000000000000000000e"))
        (missing-slot (hash32-from-hex
                       "0x000000000000000000000000000000000000000000000000000000000000000f")))
    (state-db-set-account state address
                          (make-state-account :nonce 2 :balance 1000))
    (state-db-set-storage state address slot 42)
    (let* ((proof (state-db-get-proof state address (list slot missing-slot)))
           (storage-proofs (state-proof-result-storage-proofs proof)))
      (is (typep proof 'state-proof-result))
      (is (= 2 (state-proof-result-nonce proof)))
      (is (= 1000 (state-proof-result-balance proof)))
      (is (bytes= (hash32-bytes (state-db-get-storage-root state address))
                  (hash32-bytes (state-proof-result-storage-root proof))))
      (is (plusp (length (state-proof-result-account-proof proof))))
      (is (= 2 (length storage-proofs)))
      (is (= 42 (state-storage-proof-value (first storage-proofs))))
      (is (= 0 (state-storage-proof-value (second storage-proofs))))
      (is (state-db-verify-proof (state-db-root state) proof))
      (signals error
        (state-db-verify-proof (zero-hash32) proof))
      (setf (state-storage-proof-value (first storage-proofs)) 43)
      (signals error
        (state-db-verify-proof (state-db-root state) proof)))))

(deftest state-proof-result-verifies-multiple-storage-proofs-together
  (let ((state (make-state-db))
        (address (address-from-hex "0x0000000000000000000000000000000000000016"))
        (slot-a (hash32-from-hex
                 "0x0000000000000000000000000000000000000000000000000000000000000020"))
        (slot-b (hash32-from-hex
                 "0x0000000000000000000000000000000000000000000000000000000000000021"))
        (missing-slot (hash32-from-hex
                       "0x0000000000000000000000000000000000000000000000000000000000000022")))
    (state-db-set-account state address
                          (make-state-account :nonce 4 :balance 2000))
    (state-db-set-storage state address slot-a 111)
    (state-db-set-storage state address slot-b 222)
    (let* ((proof (state-db-get-proof state address
                                      (list slot-a slot-b missing-slot)))
           (storage-proofs (state-proof-result-storage-proofs proof))
           (slot-b-proof (second storage-proofs)))
      (is (= 3 (length storage-proofs)))
      (is (= 111 (state-storage-proof-value (first storage-proofs))))
      (is (= 222 (state-storage-proof-value slot-b-proof)))
      (is (= 0 (state-storage-proof-value (third storage-proofs))))
      (is (state-db-verify-proof (state-db-root state) proof))
      (setf (state-storage-proof-value slot-b-proof) 223)
      (signals error
        (state-db-verify-proof (state-db-root state) proof))
      (setf (state-storage-proof-value slot-b-proof) 222)
      (setf (state-proof-result-storage-root proof) +empty-trie-hash+)
      (signals error
        (state-db-verify-proof (state-db-root state) proof)))))

(deftest state-proof-result-rejects-tampered-account-fields
  (let ((state (make-state-db))
        (address (address-from-hex "0x0000000000000000000000000000000000000017"))
        (slot (hash32-from-hex
               "0x0000000000000000000000000000000000000000000000000000000000000023")))
    (state-db-set-account state address
                          (make-state-account :nonce 5 :balance 3000))
    (state-db-set-code state address #(96 42 96 0 85))
    (state-db-set-storage state address slot 99)
    (let ((proof (state-db-get-proof state address (list slot))))
      (is (state-db-verify-proof (state-db-root state) proof))
      (setf (state-proof-result-nonce proof) 6)
      (signals error
        (state-db-verify-proof (state-db-root state) proof))
      (setf (state-proof-result-nonce proof) 5
            (state-proof-result-balance proof) 3001)
      (signals error
        (state-db-verify-proof (state-db-root state) proof))
      (setf (state-proof-result-balance proof) 3000
            (state-proof-result-storage-root proof) +empty-trie-hash+)
      (signals error
        (state-db-verify-proof (state-db-root state) proof))
      (setf (state-proof-result-storage-root proof)
            (state-db-get-storage-root state address)
            (state-proof-result-code-hash proof) +empty-code-hash+)
      (signals error
        (state-db-verify-proof (state-db-root state) proof)))))

(deftest state-proof-result-copies-address-and-slot-keys
  (let* ((state (make-state-db))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000018"))
         (slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000024"))
         (address-hex (address-to-hex address))
         (slot-hex (hash32-to-hex slot)))
    (state-db-set-account state address
                          (make-state-account :nonce 6 :balance 4000))
    (state-db-set-storage state address slot 123)
    (let* ((proof (state-db-get-proof state address (list slot)))
           (storage-proof (first (state-proof-result-storage-proofs proof))))
      (setf (aref (address-bytes address) 19) #x19
            (aref (hash32-bytes slot) 31) #x25)
      (is (string= address-hex
                   (address-to-hex (state-proof-result-address proof))))
      (is (string= slot-hex
                   (hash32-to-hex
                    (state-storage-proof-slot storage-proof))))
      (is (state-db-verify-proof (state-db-root state) proof)))))

(deftest state-proof-result-remains-bound-to-original-root
  (let ((state (make-state-db))
        (address (address-from-hex "0x0000000000000000000000000000000000000019"))
        (slot (hash32-from-hex
               "0x0000000000000000000000000000000000000000000000000000000000000026")))
    (state-db-set-account state address
                          (make-state-account :nonce 7 :balance 5000))
    (state-db-set-code state address #(96 1 96 0 85))
    (state-db-set-storage state address slot 321)
    (let ((root (state-db-root state))
          (proof (state-db-get-proof state address (list slot))))
      (state-db-set-code state address #(96 2 96 0 85))
      (state-db-set-storage state address slot 654)
      (is (not (bytes= (hash32-bytes root)
                       (hash32-bytes (state-db-root state)))))
      (is (state-db-verify-proof root proof))
      (signals error
        (state-db-verify-proof (state-db-root state) proof)))))

(deftest state-proof-result-verifies-missing-account
  (let* ((state (make-state-db))
         (address (address-from-hex "0x0000000000000000000000000000000000000014"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000010"))
         (proof (state-db-get-proof state address (list slot))))
    (is (= 0 (state-proof-result-nonce proof)))
    (is (= 0 (state-proof-result-balance proof)))
    (is (bytes= (hash32-bytes +empty-trie-hash+)
                (hash32-bytes (state-proof-result-storage-root proof))))
    (is (= 0 (state-storage-proof-value
              (first (state-proof-result-storage-proofs proof)))))
    (is (state-db-verify-proof (state-db-root state) proof))))

(deftest state-proof-result-rpc-object-uses-eth-get-proof-shape
  (let ((state (make-state-db))
        (address (address-from-hex "0x0000000000000000000000000000000000000015"))
        (slot (hash32-from-hex
               "0x0000000000000000000000000000000000000000000000000000000000000011")))
    (state-db-set-account state address
                          (make-state-account :nonce 3 :balance 1000))
    (state-db-set-storage state address slot 42)
    (let* ((proof (state-db-get-proof state address (list slot)))
           (object (state-proof-result-rpc-object proof))
           (storage-entry (first (fixture-object-field object "storageProof"))))
      (is (string= (address-to-hex address)
                   (fixture-object-field object "address")))
      (is (listp (fixture-object-field object "accountProof")))
      (is (every #'stringp (fixture-object-field object "accountProof")))
      (is (string= (quantity-to-hex 3)
                   (fixture-object-field object "nonce")))
      (is (string= (quantity-to-hex 1000)
                   (fixture-object-field object "balance")))
      (is (string= (hash32-to-hex (state-db-get-code-hash state address))
                   (fixture-object-field object "codeHash")))
      (is (string= (hash32-to-hex (state-db-get-storage-root state address))
                   (fixture-object-field object "storageHash")))
      (is (string= (hash32-to-hex slot)
                   (fixture-object-field storage-entry "key")))
      (is (string= (quantity-to-hex 42)
                   (fixture-object-field storage-entry "value")))
      (is (every #'stringp
                 (fixture-object-field storage-entry "proof"))))))

(deftest state-zero-storage-write-does-not-create-empty-account
  (let* ((state (make-state-db))
         (address (address-from-hex "0x0000000000000000000000000000000000000003"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000008"))
         (empty-root (state-db-root-hex state)))
    (state-db-set-storage state address slot 0)
    (is (null (state-db-get-account state address)))
    (is (= 0 (state-db-get-storage state address slot)))
    (is (string= empty-root (state-db-root-hex state)))))

(deftest state-storage-delete-prunes-empty-storage-created-account
  (let* ((state (make-state-db))
         (address (address-from-hex "0x0000000000000000000000000000000000000004"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000009"))
         (empty-root (state-db-root-hex state)))
    (state-db-set-storage state address slot 99)
    (is (state-db-get-account state address))
    (state-db-set-storage state address slot 0)
    (is (null (state-db-get-account state address)))
    (is (string= empty-root (state-db-root-hex state)))))

(deftest state-storage-delete-keeps-non-empty-account
  (let ((state (make-state-db))
        (address (address-from-hex "0x0000000000000000000000000000000000000005"))
        (slot (hash32-from-hex
               "0x000000000000000000000000000000000000000000000000000000000000000a")))
    (state-db-set-account state address (make-state-account :balance 1))
    (state-db-set-storage state address slot 99)
    (state-db-set-storage state address slot 0)
    (is (= 0 (state-db-get-storage state address slot)))
    (is (= 1 (state-account-balance (state-db-get-account state address))))))

(deftest state-storage-root-reflects-hashed-storage-trie
  (let ((state (make-state-db))
        (address (address-from-hex "0x0000000000000000000000000000000000000006"))
        (slot (hash32-from-hex
               "0x000000000000000000000000000000000000000000000000000000000000000b")))
    (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
                 (hash32-to-hex (state-db-get-storage-root state address))))
    (state-db-set-account state address (make-state-account :balance 1))
    (state-db-set-storage state address slot 42)
    (is (string= "0x5a82156cc229d54915dd2737745f27d84bf65f46e046a2dc1a1c214175747583"
                 (hash32-to-hex (state-db-get-storage-root state address))))
    (is (string= (hash32-to-hex (state-db-get-storage-root state address))
                 (hash32-to-hex
                  (state-account-storage-root
                   (state-db-get-account state address)))))
    (state-db-set-storage state address slot 0)
    (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
                 (hash32-to-hex (state-db-get-storage-root state address))))))

(deftest state-empty-code-write-does-not-create-empty-account
  (let* ((state (make-state-db))
         (address (address-from-hex "0x0000000000000000000000000000000000000007"))
         (empty-root (state-db-root-hex state)))
    (state-db-set-code state address #())
    (is (null (state-db-get-account state address)))
    (is (string= "0x" (bytes-to-hex (state-db-get-code state address))))
    (is (string= empty-root (state-db-root-hex state)))))

(deftest state-code-delete-prunes-empty-code-created-account
  (let* ((state (make-state-db))
         (address (address-from-hex "0x0000000000000000000000000000000000000008"))
         (empty-root (state-db-root-hex state)))
    (state-db-set-code state address (hex-to-bytes "0x60016000"))
    (is (state-db-get-account state address))
    (state-db-set-code state address #())
    (is (null (state-db-get-account state address)))
    (is (string= empty-root (state-db-root-hex state)))))

(deftest state-code-delete-keeps-non-empty-account
  (let ((state (make-state-db))
        (address (address-from-hex "0x0000000000000000000000000000000000000009")))
    (state-db-set-account state address (make-state-account :balance 1))
    (state-db-set-code state address (hex-to-bytes "0x60016000"))
    (state-db-set-code state address #())
    (is (string= "0x" (bytes-to-hex (state-db-get-code state address))))
    (is (= 1 (state-account-balance (state-db-get-account state address))))))

(deftest state-clear-account-removes-code-storage-and-is-missing-noop
  (let* ((state (make-state-db))
         (address (address-from-hex "0x000000000000000000000000000000000000000a"))
         (missing (address-from-hex "0x000000000000000000000000000000000000000b"))
         (slot (hash32-from-hex
                "0x000000000000000000000000000000000000000000000000000000000000000c"))
         (empty-root (state-db-root-hex state)))
    (state-db-clear-account state missing)
    (is (string= empty-root (state-db-root-hex state)))
    (state-db-set-account state address (make-state-account :balance 1))
    (state-db-set-storage state address slot 12)
    (state-db-set-code state address (hex-to-bytes "0x60016000"))
    (is (state-db-get-account state address))
    (is (= 12 (state-db-get-storage state address slot)))
    (is (string= "0x60016000" (bytes-to-hex (state-db-get-code state address))))
    (state-db-clear-account state address)
    (is (null (state-db-get-account state address)))
    (is (zerop (state-db-get-storage state address slot)))
    (is (string= "0x" (bytes-to-hex (state-db-get-code state address))))
    (is (string= empty-root (state-db-root-hex state)))))

(deftest state-db-from-genesis-json-applies-alloc
  (let* ((json (concatenate
                'string
                "{\"alloc\":{"
                "\"0x0000000000000000000000000000000000000001\":{"
                "\"balance\":\"0x10\","
                "\"nonce\":\"2\","
                "\"code\":\"0x60016000\","
                "\"storage\":{"
                "\"0x0000000000000000000000000000000000000000000000000000000000000007\":\"0x2a\""
                "}}}}"))
         (state (state-db-from-genesis-json-string json))
         (address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000007"))
         (account (state-db-get-account state address)))
    (is account)
    (is (= 16 (state-account-balance account)))
    (is (= 2 (state-account-nonce account)))
    (is (string= "0x60016000" (bytes-to-hex (state-db-get-code state address))))
    (is (= 42 (state-db-get-storage state address slot)))
    (is (string= (state-db-root-hex state) (state-db-root-hex state)))))

(deftest state-db-from-genesis-json-applies-short-storage-hex
  (let* ((json (concatenate
                'string
                "{\"alloc\":{"
                "\"0x0000000000000000000000000000000000000001\":{"
                "\"balance\":\"1\","
                "\"storage\":{\"0x07\":\"0x2a\"}"
                "}}}"))
         (state (state-db-from-genesis-json-string json))
         (address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000007")))
    (is (= 42 (state-db-get-storage state address slot)))))

(deftest genesis-state-root-from-json-matches-state-db-root
  (let* ((json (concatenate
                'string
                "{\"alloc\":{"
                "\"0x0000000000000000000000000000000000000001\":{"
                "\"balance\":\"0x10\","
                "\"nonce\":\"2\","
                "\"code\":\"0x60016000\","
                "\"storage\":{\"0x07\":\"0x2a\"}"
                "}}}"))
         (state (state-db-from-genesis-json-string json)))
    (is (string= (state-db-root-hex state)
                 (hash32-to-hex
                  (genesis-state-root-from-genesis-json-string json))))))

(deftest validate-genesis-json-state-root-compares-expected-root
  (let* ((alloc-json (concatenate
                      'string
                      "\"alloc\":{"
                      "\"0x0000000000000000000000000000000000000001\":{"
                      "\"balance\":\"0x10\","
                      "\"storage\":{\"0x07\":\"0x2a\"}"
                      "}}"))
         (computed-root
           (genesis-state-root-from-genesis-json-string
            (format nil "{~A}" alloc-json)))
         (valid-json
           (format nil "{~A,\"stateRoot\":\"~A\"}"
                   alloc-json (hash32-to-hex computed-root))))
    (is (validate-genesis-json-state-root valid-json))
    (signals block-validation-error
      (validate-genesis-json-state-root
       (format nil "{~A,\"stateRoot\":\"~A\"}"
               alloc-json (hash32-to-hex (zero-hash32)))))))

(deftest genesis-header-from-state-genesis-json-uses-computed-root
  (let* ((json (concatenate
                'string
                "{\"config\":{\"londonBlock\":0},"
                "\"alloc\":{"
                "\"0x0000000000000000000000000000000000000001\":{"
                "\"balance\":\"0x10\","
                "\"storage\":{\"0x07\":\"0x2a\"}"
                "}}}"))
         (computed-root (genesis-state-root-from-genesis-json-string json))
         (header (genesis-header-from-state-genesis-json-string json)))
    (is (string= (hash32-to-hex computed-root)
                 (hash32-to-hex (block-header-state-root header))))
    (is (= +initial-base-fee+ (block-header-base-fee-per-gas header)))))

(deftest genesis-header-from-state-genesis-json-rejects-root-mismatch
  (signals block-validation-error
    (genesis-header-from-state-genesis-json-string
     (concatenate
      'string
      "{\"stateRoot\":\"0x0000000000000000000000000000000000000000000000000000000000000000\","
      "\"alloc\":{\"0x0000000000000000000000000000000000000001\":"
      "{\"balance\":\"0x10\"}}}"))))

(deftest genesis-block-from-state-genesis-json-uses-computed-root
  (let* ((json (concatenate
                'string
                "{\"config\":{\"londonBlock\":0,\"shanghaiTime\":0},"
                "\"alloc\":{"
                "\"0x0000000000000000000000000000000000000001\":{"
                "\"balance\":\"0x10\","
                "\"storage\":{\"0x07\":\"0x2a\"}"
                "}}}"))
         (computed-root (genesis-state-root-from-genesis-json-string json))
         (block (genesis-block-from-state-genesis-json-string json))
         (header (block-header block)))
    (is (string= (hash32-to-hex computed-root)
                 (hash32-to-hex (block-header-state-root header))))
    (is (block-withdrawals-present-p block))
    (is (null (block-withdrawals block)))))

(deftest phase-a-shanghai-genesis-fixture-roots
  (let* ((json (fixture-file-string +phase-a-shanghai-genesis-fixture-path+))
         (fixture (parse-json json))
         (expected-root (genesis-expected-state-root-from-genesis-json-string json))
         (computed-root (genesis-state-root-from-genesis-json-string json))
         (state (state-db-from-genesis-json-string json))
         (block (genesis-block-from-state-genesis-json-string json))
         (header (block-header block))
         (sender (address-from-hex "0x0000000000000000000000000000000000001001"))
         (contract (address-from-hex "0x0000000000000000000000000000000000001002"))
         (slot-0 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000000"))
         (slot-1 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000001")))
    (validate-phase-a-shanghai-genesis-fixture-shape fixture)
    (is (validate-genesis-json-state-root json))
    (is (string= (hash32-to-hex expected-root)
                 (hash32-to-hex computed-root)))
    (is (string= (hash32-to-hex computed-root)
                 (state-db-root-hex state)))
    (is (string= (hash32-to-hex computed-root)
                 (hash32-to-hex (block-header-state-root header))))
    (is (block-withdrawals-present-p block))
    (is (null (block-withdrawals block)))
    (is (= 1 (state-account-nonce (state-db-get-account state sender))))
    (is (= 1000000000000000000
           (state-account-balance (state-db-get-account state sender))))
    (is (string= "0x7efcce47028dabcb0d42f3a7eda8820bf6f7f4e618398c2547d52f703cafb073"
                 (hash32-to-hex (state-db-get-code-hash state contract))))
    (is (= 42 (state-db-get-storage state contract slot-0)))
    (is (= 0 (state-db-get-storage state contract slot-1)))
    (is (string= "0x81d1fa699f807735499cf6f7df860797cf66f6a66b565cfcda3fae3521eb6861"
                 (hash32-to-hex
                  (state-db-get-storage-root state contract))))))

(defun phase-a-shanghai-genesis-shape-test-fixture
    (&key top-extra config-extra account-extra storage alloc-extra)
  (append
   (list
    (cons "format" +phase-a-shanghai-genesis-fixture-format+)
    (cons "source" "test fixture")
    (cons "executionSpecTests"
          (list (cons "release" +phase-a-eest-release+)
                (cons "tagTarget" +phase-a-eest-tag-target+)
                (cons "archive" +phase-a-eest-archive+)
                (cons "status" "test")))
    (cons "config"
          (append
           (list (cons "chainId" 1337)
                 (cons "terminalTotalDifficulty" 0)
                 (cons "londonBlock" 0)
                 (cons "shanghaiTime" 0))
           config-extra))
    (cons "nonce" "0x0")
    (cons "timestamp" "0x0")
    (cons "extraData" "0x")
    (cons "gasLimit" "0x1c9c380")
    (cons "difficulty" "0x0")
    (cons "mixHash"
          "0x0000000000000000000000000000000000000000000000000000000000000000")
    (cons "coinbase" "0x0000000000000000000000000000000000000000")
    (cons "stateRoot"
          "0x23cc0c47d1238030e9c1ec18013dcb17024d3d42729567adbb6406a64d3007f3")
    (cons "alloc"
          (append
           (list
            (cons "0x0000000000000000000000000000000000001001"
                  (append
                   (list (cons "balance" "0xde0b6b3a7640000")
                         (cons "nonce" "0x1")
                         (cons "storage"
                               (or storage
                                   (list (cons "0x00" "0x2a")))))
                   account-extra)))
           alloc-extra)))
   top-extra))

(deftest phase-a-shanghai-genesis-fixture-shape-validation
  (validate-phase-a-shanghai-genesis-fixture-shape
   (phase-a-shanghai-genesis-shape-test-fixture))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (cons (cons "source" 42)
           (remove "source"
                   (phase-a-shanghai-genesis-shape-test-fixture)
                   :key #'car
                   :test #'string=))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (cons (cons "extraData" 42)
           (remove "extraData"
                   (phase-a-shanghai-genesis-shape-test-fixture)
                   :key #'car
                   :test #'string=))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (cons (cons "stateRoot" 42)
           (remove "stateRoot"
                   (phase-a-shanghai-genesis-shape-test-fixture)
                   :key #'car
                   :test #'string=))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (phase-a-shanghai-genesis-shape-test-fixture
      :top-extra (list (cons "unexpectedTopField" t)))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (phase-a-shanghai-genesis-shape-test-fixture
      :top-extra (list (cons 42 t)))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (phase-a-shanghai-genesis-shape-test-fixture
      :top-extra (list (cons "source" "duplicate source")))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (phase-a-shanghai-genesis-shape-test-fixture
      :config-extra (list (cons "unexpectedFork" 0)))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (phase-a-shanghai-genesis-shape-test-fixture
      :config-extra (list (cons 42 0)))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (phase-a-shanghai-genesis-shape-test-fixture
      :config-extra (list (cons "chainId" 1338)))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (phase-a-shanghai-genesis-shape-test-fixture
      :account-extra (list (cons "unexpectedAccountField" "0x1")))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (phase-a-shanghai-genesis-shape-test-fixture
      :account-extra (list (cons 42 "0x1")))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (phase-a-shanghai-genesis-shape-test-fixture
      :account-extra (list (cons "code" 42)))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (phase-a-shanghai-genesis-shape-test-fixture
      :account-extra (list (cons "balance" "0x2")))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (phase-a-shanghai-genesis-shape-test-fixture
      :alloc-extra
      (list
       (cons 42 (list (cons "balance" "0x1")))))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (phase-a-shanghai-genesis-shape-test-fixture
      :alloc-extra
      (list
       (cons "0x0000000000000000000000000000000000001001"
             (list (cons "balance" "0x1")))))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (phase-a-shanghai-genesis-shape-test-fixture
      :alloc-extra
      (list
       (cons "0000000000000000000000000000000000001001"
             (list (cons "balance" "0x1")))))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (phase-a-shanghai-genesis-shape-test-fixture
      :storage (list (cons "0x00" "0x2a")
                     (cons "0x0" "0x2b")))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (phase-a-shanghai-genesis-shape-test-fixture
      :storage (list (cons "0x00" -1))))))

(deftest withdrawals-credit-state-balances-in-wei
  (let* ((state (make-state-db))
         (existing (address-from-hex "0x0000000000000000000000000000000000000011"))
         (new (address-from-hex "0x0000000000000000000000000000000000000012"))
         (withdrawals
           (list
            (make-withdrawal :index 0
                             :validator-index 100
                             :address existing
                             :amount 2)
            (make-withdrawal :index 1
                             :validator-index 101
                             :address new
                             :amount 3))))
    (state-db-set-account state existing
                          (make-state-account :nonce 7 :balance 5))
    (apply-withdrawals state withdrawals)
    (is (= (+ 5 (* 2 +wei-per-gwei+))
           (state-account-balance (state-db-get-account state existing))))
    (is (= (* 3 +wei-per-gwei+)
           (state-account-balance (state-db-get-account state new))))
    (is (= 7 (state-account-nonce
              (state-db-get-account state existing))))))

(deftest legacy-transfer-state-transition
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 2
                                      :gas-limit 21000
                                      :to recipient
                                      :value 100)))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (let ((receipt (apply-legacy-transaction state sender tx)))
      (is (= 1 (receipt-status receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (= 57900 (state-account-balance
                    (state-db-get-account state sender))))
      (is (= 100 (state-account-balance
                  (state-db-get-account state recipient)))))))

(deftest legacy-transfer-zero-value-does-not-create-empty-recipient
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 21000
                                      :to recipient)))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (let ((receipt (apply-legacy-transaction state sender tx)))
      (is (= 1 (receipt-status receipt)))
      (is (= 21000 (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (= 79000 (state-account-balance
                    (state-db-get-account state sender))))
      (is (null (state-db-get-account state recipient))))))

(deftest legacy-transfer-self-transfer-preserves-value-balance
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 21000
                                      :to sender
                                      :value 100)))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (let ((receipt (apply-legacy-transaction state sender tx)))
      (is (= 1 (receipt-status receipt)))
      (is (= 21000 (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (= 79000 (state-account-balance
                    (state-db-get-account state sender)))))))

(deftest legacy-transfer-validation-errors
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002")))
    (state-db-set-account state sender
                          (make-state-account :nonce 1 :balance 1))
    (signals transaction-validation-error
      (apply-legacy-transaction
       state sender
       (make-legacy-transaction :nonce 0 :gas-price 1 :gas-limit 21000
                                :to recipient)))
    (signals transaction-validation-error
      (apply-legacy-transaction
       state sender
       (make-legacy-transaction :nonce 1 :gas-price 1 :gas-limit 20000
                                :to recipient)))
    (signals transaction-validation-error
      (apply-legacy-transaction
       state sender
       (make-legacy-transaction :nonce 1 :gas-price 1 :gas-limit 21000
                                :to recipient :value 1)))))

(deftest legacy-transaction-list-execution-roots
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x0000000000000000000000000000000000000002"))
         (txs (list
               (make-legacy-transaction :nonce 0 :gas-price 1 :gas-limit 21000
                                        :to recipient :value 10)
               (make-legacy-transaction :nonce 1 :gas-price 1 :gas-limit 21000
                                        :to recipient :value 20))))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (let ((result (execute-legacy-transactions state sender txs)))
      (is (= 2 (length (execution-result-receipts result))))
      (is (= 42000 (receipt-cumulative-gas-used
                    (second (execution-result-receipts result)))))
      (is (hash32-p (execution-result-state-root result)))
      (is (hash32-p (execution-result-transactions-root result)))
      (is (hash32-p (execution-result-receipts-root result)))
      (is (= 30 (state-account-balance
                 (state-db-get-account state recipient)))))))
