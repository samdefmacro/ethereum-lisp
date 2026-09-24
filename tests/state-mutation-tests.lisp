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
    (let ((snapshot (state-db-snapshot state)))
      (state-db-set-storage state address slot 0)
      (state-db-finalize-transaction state snapshot t))
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
    (let ((snapshot (state-db-snapshot state)))
      (state-db-set-code state address #())
      (state-db-finalize-transaction state snapshot t))
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

(deftest state-journal-reverts-nested-account-mutations
  (let ((state (make-state-db))
        (address (address-from-hex
                  "0x0000000000000000000000000000000000000010"))
        (slot (hash32-from-hex
               "0x0000000000000000000000000000000000000000000000000000000000000010")))
    (state-db-set-account state address (make-state-account :balance 1))
    (let ((outer (state-db-snapshot state))
          (root (state-db-root state)))
      (state-db-set-storage state address slot 7)
      (let ((inner (state-db-snapshot state)))
        (state-db-set-code state address #(1 2 3))
        (state-db-clear-account state address)
        (state-db-revert-to-snapshot state inner)
        (is (= 7 (state-db-get-storage state address slot)))
        (is (zerop (length (state-db-get-code state address)))))
      (state-db-revert-to-snapshot state outer)
      (is (= 1 (state-account-balance (state-db-get-account state address))))
      (is (= 0 (state-db-get-storage state address slot)))
      (is (ethereum-lisp.types:hash32= root (state-db-root state))))))

(deftest state-journal-touch-restores-lazily-loaded-account
  (let* ((address (address-from-hex
                   "0x0000000000000000000000000000000000000011"))
         (state
           (make-lazy-state-db
            (lambda (requested)
              (if (bytes= (address-bytes requested) (address-bytes address))
                  (values (make-state-account :balance 7)
                          (make-byte-vector 0)
                          t
                          '())
                  (values nil nil nil)))
            (lambda (requested slot)
              (declare (ignore requested slot))
              0)
            (lambda (state)
              (declare (ignore state))))))
    (let ((snapshot (state-db-snapshot state)))
      (state-db-touch-account state address)
      (is (= 7 (state-account-balance (state-db-get-account state address))))
      (state-db-revert-to-snapshot state snapshot))
    (is (= 7 (state-account-balance (state-db-get-account state address))))))

(deftest state-finalization-is-fork-gated
  (let ((state (make-state-db))
        (address (address-from-hex
                  "0x0000000000000000000000000000000000000011")))
    (let ((snapshot (state-db-snapshot state)))
      (state-db-set-account state address (make-state-account))
      (state-db-finalize-transaction state snapshot nil)
      (is (state-db-get-account state address)))
    (let ((snapshot (state-db-snapshot state)))
      (state-db-set-account state address (make-state-account))
      (state-db-finalize-transaction state snapshot t)
      (is (null (state-db-get-account state address))))))


;;; A slot first read AFTER its account was journaled must survive a revert of
;;; that journal entry.  Hoodi block 3684027 (2026-09-24): the lazily-backed
;;; state lost such a read on every reverted call frame and answered 0 for the
;;; rest of the state's life, so the node charged 18,602 gas less than
;;; go-ethereum and rejected a canonical block.  The in-memory state that EEST
;;; drives has no backing to lose, which is why the corpus never saw it.

(defun lazy-storage-test-state (address backing &key trie-backed-p)
  "A lazy state whose only account is ADDRESS, holding BACKING ((slot . value) ...).
TRIE-BACKED-P serves storage through the account's storage trie, as the
durable node store does; otherwise through the flat storage loader."
  (let ((trie (when trie-backed-p
                (let ((trie (make-mpt)))
                  (loop for (slot . value) in backing
                        do (mpt-put trie
                                    (ethereum-lisp.state::state-db-storage-proof-key slot)
                                    (rlp-encode value)))
                  trie))))
    (make-lazy-state-db
     (lambda (requested)
       (if (bytes= (address-bytes requested) (address-bytes address))
           (values (make-state-account :balance 1)
                   (make-byte-vector 0)
                   t
                   '()
                   trie)
           (values nil nil nil)))
     (lambda (requested slot)
       (if (bytes= (address-bytes requested) (address-bytes address))
           (or (cdr (assoc slot backing :test #'hash32=)) 0)
           0))
     (lambda (state) (declare (ignore state))))))

(defun lazy-storage-test-slot (n)
  (hash32-from-hex (format nil "0x~64,'0X" n)))

(defun check-lazy-slot-read-after-journal-survives-revert (trie-backed-p)
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000012"))
         (written (lazy-storage-test-slot 1))
         (read-later (lazy-storage-test-slot 2))
         (state (lazy-storage-test-state
                 address (list (cons written 5) (cons read-later 9))
                 :trie-backed-p trie-backed-p)))
    (let ((snapshot (state-db-snapshot state)))
      ;; The write journals the account's before-image; READ-LATER is not in it.
      (state-db-set-storage state address written 6)
      (is (= 9 (state-db-get-storage state address read-later)))
      (state-db-revert-to-snapshot state snapshot))
    (is (= 5 (state-db-get-storage state address written)))
    (is (= 9 (state-db-get-storage state address read-later)))))

(deftest state-journal-revert-keeps-a-lazily-read-flat-storage-slot
  (check-lazy-slot-read-after-journal-survives-revert nil))

(deftest state-journal-revert-keeps-a-lazily-read-trie-storage-slot
  (check-lazy-slot-read-after-journal-survives-revert t))

(deftest state-journal-revert-keeps-a-slot-deleted-before-the-snapshot-deleted
  ;; Guard for the fix above: a slot zeroed BEFORE the snapshot must stay zero
  ;; after the revert, not come back from the backing store.
  (dolist (trie-backed-p '(nil t))
    (let* ((address (address-from-hex "0x0000000000000000000000000000000000000013"))
           (deleted (lazy-storage-test-slot 1))
           (other (lazy-storage-test-slot 3))
           (state (lazy-storage-test-state
                   address (list (cons deleted 5) (cons other 7))
                   :trie-backed-p trie-backed-p)))
      (is (= 5 (state-db-get-storage state address deleted)))
      (state-db-set-storage state address deleted 0)
      (let ((snapshot (state-db-snapshot state)))
        (state-db-set-storage state address other 8)
        (state-db-revert-to-snapshot state snapshot))
      (is (= 0 (state-db-get-storage state address deleted)))
      (is (= 7 (state-db-get-storage state address other))))))

(deftest state-recreated-account-does-not-read-its-predecessor-storage
  ;; A cleared account starts with empty storage; a slot never read before the
  ;; clear must not be fetched from the pre-clear backing afterwards.
  (dolist (trie-backed-p '(nil t))
    (let* ((address (address-from-hex "0x0000000000000000000000000000000000000014"))
           (slot (lazy-storage-test-slot 4))
           (state (lazy-storage-test-state
                   address (list (cons slot 11))
                   :trie-backed-p trie-backed-p)))
      (is (state-db-get-account state address))
      (state-db-clear-account state address)
      (state-db-set-account state address (make-state-account :balance 2))
      (is (= 0 (state-db-get-storage state address slot))))))
