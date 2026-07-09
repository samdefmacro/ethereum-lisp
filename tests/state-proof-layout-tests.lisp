(in-package #:ethereum-lisp.test)

(defun make-state-proof-layout-state (entries)
  (let ((state (make-state-db)))
    (dolist (entry entries state)
      (destructuring-bind (address nonce balance) entry
        (state-db-set-account
         state
         (address-from-hex address)
         (make-state-account :nonce nonce :balance balance))))))

(defun state-proof-layout-trie (state)
  (ethereum-lisp.state::state-db-state-trie state))

(defun assert-state-proof-layout-shape
    (state expected-shape &key path-nibbles child-indexes child-shapes)
  (let ((trie (state-proof-layout-trie state)))
    (is (string= expected-shape (trie-fixture-root-shape trie)))
    (when path-nibbles
      (is (equal path-nibbles (trie-fixture-root-path-nibbles trie))))
    (when child-indexes
      (is (equal child-indexes (trie-fixture-root-children trie))))
    (dolist (entry child-shapes)
      (is (string= (cdr entry)
                   (state-root-fixture-root-child-shape trie (car entry)))))))

(deftest state-proof-result-verifies-nethermind-state-trie-layouts
  (dolist
      (case
       (list
        (list
         :entries
         '(("0x0000000000000000000000000000000000000201" 1 100))
         :target "0x0000000000000000000000000000000000000201"
         :nonce 1
         :balance 100
         :shape "leaf")
        (list
         :entries
         '(("0x0000000000000000000000000000000000000201" 1 100)
           ("0x0000000000000000000000000000000000000211" 2 200))
         :target "0x0000000000000000000000000000000000000211"
         :nonce 2
         :balance 200
         :shape "branch"
         :child-indexes '(11 13)
         :child-shapes '((11 . "leaf") (13 . "leaf")))
        (list
         :entries
         '(("0x0000000000000000000000000000000000000220" 1 100)
           ("0x0000000000000000000000000000000000000225" 2 200))
         :target "0x0000000000000000000000000000000000000225"
         :nonce 2
         :balance 200
         :shape "extension"
         :path-nibbles '(13 7))
        (list
         :entries
         '(("0x0000000000000000000000000000000000000220" 1 100)
           ("0x0000000000000000000000000000000000000225" 2 200)
           ("0x0000000000000000000000000000000000000203" 3 300))
         :target "0x0000000000000000000000000000000000000220"
         :nonce 1
         :balance 100
         :shape "branch"
         :child-indexes '(12 13)
         :child-shapes '((12 . "leaf") (13 . "extension")))))
    (let* ((state (make-state-proof-layout-state (getf case :entries)))
           (target (address-from-hex (getf case :target)))
           (proof (state-db-get-proof state target nil)))
      (assert-state-proof-layout-shape
       state
       (getf case :shape)
       :path-nibbles (getf case :path-nibbles)
       :child-indexes (getf case :child-indexes)
       :child-shapes (getf case :child-shapes))
      (is (= (getf case :nonce) (state-proof-result-nonce proof)))
      (is (= (getf case :balance) (state-proof-result-balance proof)))
      (is (plusp (length (state-proof-result-account-proof proof))))
      (is (null (state-proof-result-storage-proofs proof)))
      (is (state-db-verify-proof (state-db-root state) proof))
      (multiple-value-bind (account-rlp present-p)
          (state-db-verify-account-proof
           (state-db-root state)
           target
           (state-proof-result-account-proof proof))
        (is present-p)
        (is (bytes= (state-account-rlp (state-db-get-account state target))
                    account-rlp))))))

(deftest state-proof-result-verifies-missing-account-in-non-empty-layout
  (let* ((state
           (make-state-proof-layout-state
            '(("0x0000000000000000000000000000000000000220" 1 100)
              ("0x0000000000000000000000000000000000000225" 2 200)
              ("0x0000000000000000000000000000000000000203" 3 300))))
         (missing (address-from-hex
                   "0x0000000000000000000000000000000000000221"))
         (proof (state-db-get-proof state missing nil)))
    (assert-state-proof-layout-shape
     state
     "branch"
     :child-indexes '(12 13)
     :child-shapes '((12 . "leaf") (13 . "extension")))
    (is (= 0 (state-proof-result-nonce proof)))
    (is (= 0 (state-proof-result-balance proof)))
    (is (bytes= (hash32-bytes +empty-trie-hash+)
                (hash32-bytes (state-proof-result-storage-root proof))))
    (is (bytes= (hash32-bytes +empty-code-hash+)
                (hash32-bytes (state-proof-result-code-hash proof))))
    (is (plusp (length (state-proof-result-account-proof proof))))
    (is (state-db-verify-proof (state-db-root state) proof))
    (multiple-value-bind (account-rlp present-p)
        (state-db-verify-account-proof
         (state-db-root state)
         missing
         (state-proof-result-account-proof proof))
      (is (null present-p))
      (is (null account-rlp)))))

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

(deftest state-proof-result-rpc-object-round-trips-and-verifies
  (let ((state (make-state-db))
        (address (address-from-hex "0x000000000000000000000000000000000000001a"))
        (slot (hash32-from-hex
               "0x0000000000000000000000000000000000000000000000000000000000000011"))
        (missing-slot (hash32-from-hex
                       "0x0000000000000000000000000000000000000000000000000000000000000012")))
    (state-db-set-account state address
                          (make-state-account :nonce 4 :balance 2000))
    (state-db-set-code state address #(96 2 96 0))
    (state-db-set-storage state address slot 77)
    (let* ((proof (state-db-get-proof state address (list slot missing-slot)))
           (object (state-proof-result-rpc-object proof))
           (decoded (state-proof-result-from-rpc-object object))
           (storage-entry (first (fixture-object-field object "storageProof"))))
      (is (state-db-verify-proof (state-db-root state) decoded))
      (is (equal object (state-proof-result-rpc-object decoded)))
      (let* ((short-key-storage-entry
               (cons (cons "key" "0x11")
                     (remove "key" storage-entry :key #'car :test #'string=)))
             (short-key-object
               (cons
                (cons "storageProof"
                      (cons short-key-storage-entry
                            (rest (fixture-object-field object "storageProof"))))
                (remove "storageProof" object :key #'car :test #'string=)))
             (short-key-decoded
               (state-proof-result-from-rpc-object short-key-object)))
        (is (state-db-verify-proof (state-db-root state) short-key-decoded))
        (is (string= (hash32-to-hex slot)
                     (hash32-to-hex
                      (state-storage-proof-slot
                       (first
                        (state-proof-result-storage-proofs
                         short-key-decoded)))))))
      (let* ((tampered-storage-entry
               (cons (cons "value" "0x4e")
                     (remove "value" storage-entry :key #'car :test #'string=)))
             (tampered-object
               (cons
                (cons "storageProof"
                      (cons tampered-storage-entry
                            (rest (fixture-object-field object "storageProof"))))
                (remove "storageProof" object :key #'car :test #'string=))))
        (signals error
          (state-db-verify-proof
           (state-db-root state)
           (state-proof-result-from-rpc-object tampered-object))))
      (signals error
        (state-proof-result-from-rpc-object
         (cons (cons "accountProof" "0x80")
               (remove "accountProof" object :key #'car :test #'string=)))))))

