(in-package #:ethereum-lisp.test)

;;;; Per-block state diffs: commit policy, resolution, tombstones,
;;;; branches, pruning promotion, and KV round-trips.

(defun state-diff-test-address (byte)
  (address-from-hex
   (format nil "0x~38,'0X~2,'0X" 0 byte)))

(defun state-diff-test-slot (byte)
  (hash32-from-hex
   (format nil "0x~62,'0X~2,'0X" 0 byte)))

(defun state-diff-test-block (number parent-hash)
  (make-block
   :header
   (make-block-header :number number
                      :parent-hash parent-hash
                      :timestamp (1+ number)
                      :gas-limit 30000000)))

(defun state-diff-test-chain (store count &key (start-number 0))
  "Put COUNT chained blocks and return them as a list."
  (let ((parent-hash (zero-hash32))
        (blocks '()))
    (dotimes (index count (nreverse blocks))
      (let ((block (state-diff-test-block (+ start-number index)
                                          parent-hash)))
        (chain-store-put-block store block :state-available-p nil)
        (push block blocks)
        (setf parent-hash (block-hash block))))))

(defun state-diff-test-commit (store block accounts)
  "Commit ACCOUNTS — a list of (ADDRESS BALANCE NONCE CODE
STORAGE-ENTRIES) — as BLOCK's post-state and return the stored kind."
  (ethereum-lisp.chain-store:chain-store-commit-post-state
   store (block-hash block)
   (lambda (visit)
     (dolist (account accounts)
       (apply visit account)))))

(defun state-diff-test-collect-accounts (store block)
  "Return the for-each-account view as an alist keyed by address hex."
  (let ((accounts '()))
    (chain-store-for-each-account
     store (block-hash block)
     (lambda (address balance nonce code storage-entries)
       (push (list (address-to-hex address) balance nonce code
                   storage-entries)
             accounts)))
    (nreverse accounts)))

(deftest chain-store-diff-commit-resolves-values-through-parents
  (let* ((store (make-engine-payload-memory-store))
         (blocks (state-diff-test-chain store 3))
         (address-a (state-diff-test-address 1))
         (address-b (state-diff-test-address 2))
         (slot (state-diff-test-slot 1)))
    (destructuring-bind (block-0 block-1 block-2) blocks
      (is (eq :baseline
              (state-diff-test-commit
               store block-0
               (list (list address-a 10 1 #(1 2)
                           (list (cons slot 5)))))))
      (is (eq :diff
              (state-diff-test-commit
               store block-1
               (list (list address-a 20 1 #(1 2)
                           (list (cons slot 5)))))))
      (is (eq :diff
              (state-diff-test-commit
               store block-2
               (list (list address-a 20 1 #(1 2)
                           (list (cons slot 5)))
                     (list address-b 7 0 #() '())))))
      ;; Values at every height, changed and inherited alike.
      (is (= 10 (chain-store-account-balance
                 store (block-hash block-0) address-a)))
      (is (= 20 (chain-store-account-balance
                 store (block-hash block-1) address-a)))
      (is (= 20 (chain-store-account-balance
                 store (block-hash block-2) address-a)))
      (is (= 5 (chain-store-account-storage
                store (block-hash block-2) address-a slot)))
      (is (bytes= #(1 2) (chain-store-account-code
                          store (block-hash block-2) address-a)))
      (is (= 0 (chain-store-account-balance
                store (block-hash block-1) address-b)))
      (is (= 7 (chain-store-account-balance
                store (block-hash block-2) address-b)))
      ;; The reconstructed account list matches at the diff tip.
      (let ((accounts (state-diff-test-collect-accounts store block-2)))
        (is (= 2 (length accounts)))
        (destructuring-bind (entry-a entry-b) accounts
          (is (string= (address-to-hex address-a) (first entry-a)))
          (is (= 20 (second entry-a)))
          (is (= 1 (third entry-a)))
          (is (bytes= #(1 2) (fourth entry-a)))
          (is (equalp (list (cons slot 5)) (fifth entry-a)))
          (is (string= (address-to-hex address-b) (first entry-b)))
          (is (= 7 (second entry-b))))))))

(deftest chain-store-diff-commit-tombstones-deleted-accounts-and-slots
  (let* ((store (make-engine-payload-memory-store))
         (blocks (state-diff-test-chain store 2))
         (address-a (state-diff-test-address 1))
         (address-b (state-diff-test-address 2))
         (slot (state-diff-test-slot 1)))
    (destructuring-bind (block-0 block-1) blocks
      (state-diff-test-commit
       store block-0
       (list (list address-a 10 1 #(1 2) (list (cons slot 5)))
             (list address-b 3 0 #() '())))
      ;; Block 1 zeroes A's slot and destroys B entirely.
      (is (eq :diff
              (state-diff-test-commit
               store block-1
               (list (list address-a 10 1 #(1 2) '())))))
      (is (= 0 (chain-store-account-storage
                store (block-hash block-1) address-a slot)))
      (is (= 0 (chain-store-account-balance
                store (block-hash block-1) address-b)))
      (is (bytes= #() (chain-store-account-code
                       store (block-hash block-1) address-b)))
      ;; The parent's view is untouched.
      (is (= 5 (chain-store-account-storage
                store (block-hash block-0) address-a slot)))
      (is (= 3 (chain-store-account-balance
                store (block-hash block-0) address-b)))
      ;; Reconstruction drops the dead account and the zeroed slot.
      (let ((accounts (state-diff-test-collect-accounts store block-1)))
        (is (= 1 (length accounts)))
        (is (string= (address-to-hex address-a) (first (first accounts))))
        (is (null (fifth (first accounts)))))
      (is (= 2 (length (state-diff-test-collect-accounts
                        store block-0)))))))

(deftest chain-store-diff-baseline-interval-bounds-diff-chains
  (let* ((store (make-engine-payload-memory-store
                 :chain-store
                 (ethereum-lisp.chain-store.state:make-memory-chain-store
                  :state-baseline-interval 3)))
         (blocks (state-diff-test-chain store 7))
         (address (state-diff-test-address 1))
         (kinds '()))
    (loop for block in blocks
          for balance from 10
          do (push (state-diff-test-commit
                    store block
                    (list (list address balance 0 #() '())))
                   kinds))
    (is (equal '(:baseline :diff :diff :baseline :diff :diff :baseline)
               (nreverse kinds)))
    ;; Every height still resolves its own balance.
    (loop for block in blocks
          for balance from 10
          do (is (= balance
                    (chain-store-account-balance
                     store (block-hash block) address))))))

(deftest chain-store-diff-branches-resolve-independently
  (let* ((store (make-engine-payload-memory-store))
         (parent (state-diff-test-block 0 (zero-hash32)))
         (child-a (state-diff-test-block 1 (block-hash parent)))
         (child-b
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash parent)
                               :timestamp 99
                               :gas-limit 30000000)))
         (address (state-diff-test-address 1)))
    (chain-store-put-block store parent :state-available-p nil)
    (chain-store-put-block store child-a :state-available-p nil)
    (chain-store-put-block store child-b :state-available-p nil)
    (state-diff-test-commit store parent
                            (list (list address 10 0 #() '())))
    (is (eq :diff (state-diff-test-commit
                   store child-a
                   (list (list address 11 0 #() '())))))
    (is (eq :diff (state-diff-test-commit
                   store child-b
                   (list (list address 12 0 #() '())))))
    (is (= 10 (chain-store-account-balance
               store (block-hash parent) address)))
    (is (= 11 (chain-store-account-balance
               store (block-hash child-a) address)))
    (is (= 12 (chain-store-account-balance
               store (block-hash child-b) address)))))

(deftest chain-store-prune-promotes-boundary-diffs-to-baselines
  (let* ((store (make-engine-payload-memory-store))
         (blocks (state-diff-test-chain store 4))
         (address (state-diff-test-address 1))
         (slot (state-diff-test-slot 1)))
    (loop for block in blocks
          for balance from 10
          do (state-diff-test-commit
              store block
              (list (list address balance 1 #(9)
                          (list (cons slot balance))))))
    (chain-store-set-canonical-head store (block-hash (fourth blocks)))
    (is (= 2 (chain-store-prune-state-before
              store (block-header-number
                     (block-header (third blocks))))))
    ;; The oldest kept block was promoted so its chain stays whole.
    (is (eq :baseline
            (ethereum-lisp.chain-store:chain-store-state-kind
             store (block-hash (third blocks)))))
    (is (= 12 (chain-store-account-balance
               store (block-hash (third blocks)) address)))
    (is (= 12 (chain-store-account-storage
               store (block-hash (third blocks)) address slot)))
    (is (= 13 (chain-store-account-balance
               store (block-hash (fourth blocks)) address)))
    (is (not (chain-store-state-available-p
              store (block-hash (first blocks)))))
    (is (not (chain-store-state-available-p
              store (block-hash (second blocks)))))
    ;; The promoted view reconstructs completely.
    (let ((accounts (state-diff-test-collect-accounts
                     store (third blocks))))
      (is (= 1 (length accounts)))
      (is (equalp (list (cons slot 12)) (fifth (first accounts)))))))

(deftest chain-store-diff-and-baseline-roots-agree
  (let* ((diff-store (make-engine-payload-memory-store))
         (baseline-store
           (make-engine-payload-memory-store
            :chain-store
            (ethereum-lisp.chain-store.state:make-memory-chain-store
             :state-baseline-interval 1)))
         (address-a (state-diff-test-address 1))
         (address-b (state-diff-test-address 2))
         (slot (state-diff-test-slot 1))
         (states
           (list
            (list (list address-a 10 1 #(1 2) (list (cons slot 5)))
                  (list address-b 3 0 #() '()))
            (list (list address-a 20 2 #(1 2) (list (cons slot 6)))
                  (list address-b 3 0 #() '()))
            (list (list address-a 20 2 #(1 2) '())))))
    (let ((diff-blocks (state-diff-test-chain diff-store 3))
          (baseline-blocks (state-diff-test-chain baseline-store 3)))
      (loop for accounts in states
            for diff-block in diff-blocks
            for baseline-block in baseline-blocks
            do (state-diff-test-commit diff-store diff-block accounts)
               (state-diff-test-commit
                baseline-store baseline-block accounts))
      (is (eq :diff (ethereum-lisp.chain-store:chain-store-state-kind
                     diff-store (block-hash (third diff-blocks)))))
      (is (eq :baseline
              (ethereum-lisp.chain-store:chain-store-state-kind
               baseline-store (block-hash (third baseline-blocks)))))
      (loop for diff-block in diff-blocks
            for baseline-block in baseline-blocks
            do (is (ethereum-lisp.types:hash32=
                    (ethereum-lisp.node-store.persistence::chain-store-state-snapshot-root
                     diff-store (block-hash diff-block))
                    (ethereum-lisp.node-store.persistence::chain-store-state-snapshot-root
                     baseline-store (block-hash baseline-block))))))))

(deftest chain-store-diff-records-round-trip-through-kv
  (let* ((store (make-engine-payload-memory-store))
         (blocks (state-diff-test-chain store 3))
         (address-a (state-diff-test-address 1))
         (address-b (state-diff-test-address 2))
         (slot (state-diff-test-slot 1))
         (database (make-memory-key-value-database)))
    (destructuring-bind (block-0 block-1 block-2) blocks
      (state-diff-test-commit
       store block-0
       (list (list address-a 10 1 #(1 2) (list (cons slot 5)))
             (list address-b 3 0 #() '())))
      (state-diff-test-commit
       store block-1
       (list (list address-a 20 1 #(1 2) (list (cons slot 5)))
             (list address-b 3 0 #() '())))
      ;; Block 2 destroys B and zeroes the slot: tombstones must survive
      ;; the KV round trip.
      (state-diff-test-commit
       store block-2
       (list (list address-a 20 1 #(1 2) '())))
      (chain-store-export-state-records-to-kv store database)
      (is (= 1 (length (kv-chain-record-entries database :state))))
      (is (= 2 (length (kv-chain-record-entries database :state-diff))))
      (let ((restored (make-engine-payload-memory-store)))
        (dolist (block blocks)
          (chain-store-put-block restored block :state-available-p nil))
        (ethereum-lisp.node-store.persistence::chain-store-import-state-records-from-kv
         restored database)
        (is (eq :diff (ethereum-lisp.chain-store:chain-store-state-kind
                       restored (block-hash block-2))))
        (is (= 20 (chain-store-account-balance
                   restored (block-hash block-2) address-a)))
        (is (= 0 (chain-store-account-balance
                  restored (block-hash block-2) address-b)))
        (is (= 0 (chain-store-account-storage
                  restored (block-hash block-2) address-a slot)))
        (is (= 5 (chain-store-account-storage
                  restored (block-hash block-1) address-a slot)))
        (is (= 3 (chain-store-account-balance
                  restored (block-hash block-1) address-b)))
        (let ((accounts (state-diff-test-collect-accounts
                         restored block-2)))
          (is (= 1 (length accounts))))))))

(deftest chain-store-legacy-availability-marker-reads-as-baseline
  (let* ((store (make-engine-payload-memory-store))
         (blocks (state-diff-test-chain store 1))
         (block (first blocks))
         (address (state-diff-test-address 1)))
    (chain-store-put-account-balance store (block-hash block) address 42)
    ;; Databases written before diff support marked availability with T.
    (setf (gethash (hash32-to-hex (block-hash block))
                   (ethereum-lisp.chain-store.state:memory-chain-store-state-blocks
                    (ethereum-lisp.chain-store.state:chain-store-require-memory-store
                     store)))
          t)
    (is (eq :baseline
            (ethereum-lisp.chain-store:chain-store-state-kind
             store (block-hash block))))
    (is (= 42 (chain-store-account-balance
               store (block-hash block) address)))
    (is (= 1 (length (state-diff-test-collect-accounts store block))))))

(deftest chain-store-diff-with-broken-chain-behaves-unavailable
  (let* ((store (make-engine-payload-memory-store))
         (blocks (state-diff-test-chain store 2))
         (address (state-diff-test-address 1)))
    (destructuring-bind (block-0 block-1) blocks
      ;; A diff whose parent has no state cannot resolve.
      (ethereum-lisp.chain-store:chain-store-put-state-diff
       store (block-hash block-1) (block-hash block-0))
      (is (= 0 (chain-store-account-balance
                store (block-hash block-1) address)))
      (is (null (state-diff-test-collect-accounts store block-1))))))

(deftest chain-store-diff-recreates-a-destroyed-account
  (let* ((store (make-engine-payload-memory-store))
         (blocks (state-diff-test-chain store 3))
         (address-a (state-diff-test-address 1))
         (address-b (state-diff-test-address 2))
         (slot (state-diff-test-slot 1)))
    (destructuring-bind (block-0 block-1 block-2) blocks
      (state-diff-test-commit
       store block-0
       (list (list address-a 10 1 #(1 2) (list (cons slot 5)))
             (list address-b 3 0 #() '())))
      ;; Destroy A, then recreate it with entirely different fields: the
      ;; recreation diff must record every field against the tombstone.
      (state-diff-test-commit
       store block-1
       (list (list address-b 3 0 #() '())))
      (state-diff-test-commit
       store block-2
       (list (list address-a 7 0 #(3) (list (cons slot 9)))
             (list address-b 3 0 #() '())))
      (is (= 0 (chain-store-account-balance
                store (block-hash block-1) address-a)))
      (is (bytes= #() (chain-store-account-code
                       store (block-hash block-1) address-a)))
      (is (= 0 (chain-store-account-storage
                store (block-hash block-1) address-a slot)))
      (is (= 7 (chain-store-account-balance
                store (block-hash block-2) address-a)))
      (is (= 0 (chain-store-account-nonce
                store (block-hash block-2) address-a)))
      (is (bytes= #(3) (chain-store-account-code
                        store (block-hash block-2) address-a)))
      (is (= 9 (chain-store-account-storage
                store (block-hash block-2) address-a slot)))
      (is (= 10 (chain-store-account-balance
                 store (block-hash block-0) address-a)))
      (is (= 1 (length (state-diff-test-collect-accounts
                        store block-1))))
      (is (= 2 (length (state-diff-test-collect-accounts
                        store block-2)))))))

(deftest chain-store-diff-keeps-explicit-zero-fields-on-live-accounts
  (let* ((store (make-engine-payload-memory-store))
         (blocks (state-diff-test-chain store 2))
         (address (state-diff-test-address 1)))
    (destructuring-bind (block-0 block-1) blocks
      (state-diff-test-commit
       store block-0
       (list (list address 10 1 #(1) '())))
      ;; The account survives with zeroed balance and emptied code: these
      ;; are stored values, not tombstones.
      (state-diff-test-commit
       store block-1
       (list (list address 0 1 #() '())))
      (is (= 0 (chain-store-account-balance
                store (block-hash block-1) address)))
      (is (= 1 (chain-store-account-nonce
                store (block-hash block-1) address)))
      (is (bytes= #() (chain-store-account-code
                       store (block-hash block-1) address)))
      (is (= 10 (chain-store-account-balance
                 store (block-hash block-0) address)))
      (let ((accounts (state-diff-test-collect-accounts store block-1)))
        (is (= 1 (length accounts)))
        (is (= 0 (second (first accounts))))
        (is (= 1 (third (first accounts))))))))

(deftest chain-store-diff-resurrects-a-zeroed-storage-slot
  (let* ((store (make-engine-payload-memory-store))
         (blocks (state-diff-test-chain store 3))
         (address (state-diff-test-address 1))
         (slot (state-diff-test-slot 1)))
    (destructuring-bind (block-0 block-1 block-2) blocks
      (state-diff-test-commit
       store block-0
       (list (list address 1 1 #() (list (cons slot 5)))))
      (state-diff-test-commit
       store block-1
       (list (list address 1 1 #() '())))
      (state-diff-test-commit
       store block-2
       (list (list address 1 1 #() (list (cons slot 6)))))
      (is (= 5 (chain-store-account-storage
                store (block-hash block-0) address slot)))
      (is (= 0 (chain-store-account-storage
                store (block-hash block-1) address slot)))
      (is (= 6 (chain-store-account-storage
                store (block-hash block-2) address slot)))
      (is (null (fifth (first (state-diff-test-collect-accounts
                               store block-1)))))
      (is (equalp (list (cons slot 6))
                  (fifth (first (state-diff-test-collect-accounts
                                 store block-2))))))))

(deftest chain-store-prune-promotes-side-chain-boundaries
  (let* ((store (make-engine-payload-memory-store))
         (parent (state-diff-test-block 0 (zero-hash32)))
         (child-a (state-diff-test-block 1 (block-hash parent)))
         (side-b
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash parent)
                               :timestamp 99
                               :gas-limit 30000000)))
         (grandchild (state-diff-test-block 2 (block-hash child-a)))
         (address (state-diff-test-address 1)))
    (dolist (block (list parent child-a side-b grandchild))
      (chain-store-put-block store block :state-available-p nil))
    (state-diff-test-commit store parent
                            (list (list address 10 0 #() '())))
    (state-diff-test-commit store child-a
                            (list (list address 11 0 #() '())))
    (state-diff-test-commit store side-b
                            (list (list address 12 0 #() '())))
    (state-diff-test-commit store grandchild
                            (list (list address 13 0 #() '())))
    (chain-store-set-canonical-head store (block-hash grandchild))
    ;; Dropping the shared parent must promote BOTH branch boundaries,
    ;; while the grandchild keeps its diff onto the kept child.
    (is (= 1 (chain-store-prune-state-before store 1)))
    (is (eq :baseline (ethereum-lisp.chain-store:chain-store-state-kind
                       store (block-hash child-a))))
    (is (eq :baseline (ethereum-lisp.chain-store:chain-store-state-kind
                       store (block-hash side-b))))
    (is (eq :diff (ethereum-lisp.chain-store:chain-store-state-kind
                   store (block-hash grandchild))))
    (is (= 11 (chain-store-account-balance
               store (block-hash child-a) address)))
    (is (= 12 (chain-store-account-balance
               store (block-hash side-b) address)))
    (is (= 13 (chain-store-account-balance
               store (block-hash grandchild) address)))
    (is (not (chain-store-state-available-p
              store (block-hash parent))))))

(deftest chain-store-diff-cycle-guard-returns-defaults
  (let* ((store (make-engine-payload-memory-store))
         (blocks (state-diff-test-chain store 3))
         (address (state-diff-test-address 1)))
    (destructuring-bind (block-0 block-1 block-2) blocks
      (declare (ignore block-0))
      ;; A corrupt import could produce a self-referential diff, or two
      ;; diffs pointing at each other. Reads must not hang.
      (ethereum-lisp.chain-store:chain-store-put-state-diff
       store (block-hash block-1) (block-hash block-1))
      (is (= 0 (chain-store-account-balance
                store (block-hash block-1) address)))
      (is (null (state-diff-test-collect-accounts store block-1)))
      (ethereum-lisp.chain-store:chain-store-put-state-diff
       store (block-hash block-1) (block-hash block-2))
      (ethereum-lisp.chain-store:chain-store-put-state-diff
       store (block-hash block-2) (block-hash block-1))
      (is (= 0 (chain-store-account-balance
                store (block-hash block-2) address)))
      (is (null (state-diff-test-collect-accounts store block-2))))))

(deftest chain-store-candidate-export-updates-promoted-record-kinds
  (let* ((store (make-engine-payload-memory-store))
         (blocks (state-diff-test-chain store 4))
         (address (state-diff-test-address 1))
         (database (make-memory-key-value-database)))
    (loop for block in blocks
          for balance from 10
          do (state-diff-test-commit
              store block
              (list (list address balance 0 #() '()))))
    (chain-store-set-canonical-head store (block-hash (fourth blocks)))
    (node-store-export-payload-candidate-to-kv
     store (fourth blocks) database)
    (is (= 1 (length (kv-chain-record-entries database :state))))
    (is (= 3 (length (kv-chain-record-entries database :state-diff))))
    ;; Pruning promotes the boundary block; the next incremental export
    ;; must flip its record kind and drop the stale diff record.
    (chain-store-prune-state-before
     store (block-header-number (block-header (third blocks))))
    (node-store-export-payload-candidate-to-kv
     store (fourth blocks) database)
    (let ((promoted-id (hash32-bytes (block-hash (third blocks)))))
      (multiple-value-bind (value present-p)
          (kv-get-chain-record database :state promoted-id)
        (declare (ignore value))
        (is present-p))
      (multiple-value-bind (value present-p)
          (kv-get-chain-record database :state-diff promoted-id :missing)
        (is (eq :missing value))
        (is (not present-p))))
    (multiple-value-bind (value present-p)
        (kv-get-chain-record
         database :state-diff
         (hash32-bytes (block-hash (fourth blocks))))
      (declare (ignore value))
      (is present-p))))
