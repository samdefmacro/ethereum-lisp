(in-package #:ethereum-lisp.test)

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

(deftest state-code-update-preserves-storage-commitments
  (let ((state (make-state-db))
        (address (address-from-hex "0x000000000000000000000000000000000000000a"))
        (slot (hash32-from-hex
               "0x000000000000000000000000000000000000000000000000000000000000000c"))
        (first-code (hex-to-bytes "0x60016000"))
        (final-code (hex-to-bytes "0x6002600301")))
    (state-db-set-account state address
                          (make-state-account :nonce 1 :balance 1000))
    (state-db-set-storage state address slot 12)
    (state-db-set-code state address first-code)
    (let ((storage-root (state-db-get-storage-root state address)))
      (state-db-set-code state address final-code)
      (let ((account (state-db-get-account state address)))
        (is account)
        (is (= 12 (state-db-get-storage state address slot)))
        (is (bytes= final-code (state-db-get-code state address)))
        (is (bytes= (hash32-bytes storage-root)
                    (hash32-bytes (state-account-storage-root account))))
        (is (bytes= (hash32-bytes (keccak-256-hash final-code))
                    (hash32-bytes
                     (state-account-code-hash account))))))))

(deftest state-account-update-preserves-code-and-storage-commitments
  (let ((state (make-state-db))
        (address (address-from-hex "0x000000000000000000000000000000000000000b"))
        (slot (hash32-from-hex
               "0x000000000000000000000000000000000000000000000000000000000000000c"))
        (code (hex-to-bytes "0x6001600201")))
    (state-db-set-account state address
                          (make-state-account :nonce 1 :balance 1000))
    (state-db-set-storage state address slot 12)
    (state-db-set-code state address code)
    (let ((storage-root (state-db-get-storage-root state address))
          (code-hash (keccak-256-hash code)))
      (state-db-set-account state address
                            (make-state-account :nonce 0 :balance 0))
      (let ((account (state-db-get-account state address)))
        (is account)
        (is (zerop (state-account-nonce account)))
        (is (zerop (state-account-balance account)))
        (is (bytes= (hash32-bytes storage-root)
                    (hash32-bytes (state-account-storage-root account))))
        (is (bytes= (hash32-bytes code-hash)
                    (hash32-bytes (state-account-code-hash account))))
        (is (= 12 (state-db-get-storage state address slot)))
        (is (bytes= code (state-db-get-code state address)))))))

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

(deftest state-db-for-each-account-iterates-deterministically
  (let ((state (make-state-db))
        (address-a (address-from-hex "0x0000000000000000000000000000000000000001"))
        (address-b (address-from-hex "0x0000000000000000000000000000000000000002"))
        (address-c (address-from-hex "0x0000000000000000000000000000000000000003"))
        (slot-a (hash32-from-hex
                 "0x0000000000000000000000000000000000000000000000000000000000000001"))
        (slot-b (hash32-from-hex
                 "0x000000000000000000000000000000000000000000000000000000000000000b"))
        (addresses '())
        (storage-slots '()))
    (state-db-set-account state address-c (make-state-account :balance 3))
    (state-db-set-account state address-a (make-state-account :balance 1))
    (state-db-set-account state address-b (make-state-account :balance 2))
    (state-db-set-storage state address-a slot-b 11)
    (state-db-set-storage state address-a slot-a 1)
    (state-db-for-each-account
     state
     (lambda (address account code storage-entries)
       (declare (ignore account code))
       (push (address-to-hex address) addresses)
       (when (bytes= (address-bytes address-a) (address-bytes address))
         (setf storage-slots
               (mapcar (lambda (entry)
                         (hash32-to-hex (car entry)))
                       storage-entries)))))
    (is (equal (list "0x0000000000000000000000000000000000000001"
                     "0x0000000000000000000000000000000000000002"
                     "0x0000000000000000000000000000000000000003")
               (nreverse addresses)))
    (is (equal (list
                "0x0000000000000000000000000000000000000000000000000000000000000001"
                "0x000000000000000000000000000000000000000000000000000000000000000b")
               storage-slots))))

