(in-package #:ethereum-lisp.test)

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

