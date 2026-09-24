(in-package #:ethereum-lisp.test)

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
         (recipient (address-from-hex "0x00000000000000000000000000000000000000f2"))
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
         (recipient (address-from-hex "0x00000000000000000000000000000000000000f2"))
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
         (sender (address-from-hex "0x00000000000000000000000000000000000000aa"))
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
         (recipient (address-from-hex "0x00000000000000000000000000000000000000f2")))
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

(deftest legacy-transaction-contract-creation-uses-message-executor
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (initcode #(96 0 96 0 83 96 1 96 0 243))
         (contract
           (make-address
            (subseq
             (keccak-256
              (rlp-encode
               (make-rlp-list (address-bytes sender) 0)))
             12 32)))
         (tx (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 80000
                                      :to nil
                                      :value 7
                                      :data initcode)))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (let ((receipt (apply-legacy-transaction state sender tx)))
      (is (= 1 (receipt-status receipt)))
      (is (= (+ (transaction-intrinsic-gas tx) 18 200)
             (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (= (- 100000
                (receipt-cumulative-gas-used receipt)
                (legacy-transaction-value tx))
             (state-account-balance (state-db-get-account state sender))))
      (is (= 7 (state-account-balance
                (state-db-get-account state contract))))
      (is (bytes= #(0) (state-db-get-code state contract))))))

(deftest legacy-transaction-list-execution-roots
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x00000000000000000000000000000000000000f2"))
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

(deftest legacy-transaction-list-executes-contract-creation
  (let* ((state (make-state-db))
         (sender (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex "0x00000000000000000000000000000000000000f2"))
         (initcode #(96 0 96 0 83 96 1 96 0 243))
         (contract
           (make-address
            (subseq
             (keccak-256
              (rlp-encode
               (make-rlp-list (address-bytes sender) 0)))
             12 32)))
         (creation (make-legacy-transaction :nonce 0
                                            :gas-price 1
                                            :gas-limit 80000
                                            :to nil
                                            :value 7
                                            :data initcode))
         (transfer (make-legacy-transaction :nonce 1
                                            :gas-price 1
                                            :gas-limit 21000
                                            :to recipient
                                            :value 3))
         (txs (list creation transfer)))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 200000))
    (let* ((result (execute-legacy-transactions state sender txs))
           (receipts (execution-result-receipts result)))
      (is (= 2 (length receipts)))
      (is (= (+ (transaction-intrinsic-gas creation) 18 200)
             (receipt-cumulative-gas-used (first receipts))))
      (is (= (+ (receipt-cumulative-gas-used (first receipts))
                (transaction-intrinsic-gas transfer))
             (receipt-cumulative-gas-used (second receipts))))
      (is (hash32-p (execution-result-state-root result)))
      (is (hash32-p (execution-result-transactions-root result)))
      (is (hash32-p (execution-result-receipts-root result)))
      (is (bytes= #(0) (state-db-get-code state contract)))
      (is (= 7 (state-account-balance
                (state-db-get-account state contract))))
      (is (= 3 (state-account-balance
                (state-db-get-account state recipient))))
      (is (= 2 (state-account-nonce
                (state-db-get-account state sender)))))))

;;; A reverted call frame that read a slot for the first time after its
;;; account's first write must not change what the rest of the transaction
;;; reads.  This is the shape of Hoodi block 3684027's ninth transaction
;;; (0xff0ed042...): six reverted calls, after which the node read a zero where
;;; the chain holds a value and charged 18,602 gas less than go-ethereum.  It
;;; only shows on a lazily-backed state, the one the node executes on; the
;;; in-memory state EEST drives answers correctly, and serves as the oracle.

(defun backed-execution-test-state (accounts mode)
  "State holding ACCOUNTS ((address balance code ((slot . value) ...)) ...).
MODE :MEMORY builds it in memory; :FLAT and :TRIE serve it lazily, storage
through the flat loader or through each account's storage trie."
  (flet ((entry (address)
           (find-if (lambda (account)
                      (bytes= (address-bytes (first account))
                              (address-bytes address)))
                    accounts)))
    (ecase mode
      (:memory
       (let ((state (make-state-db)))
         (loop for (address balance code storage) in accounts
               do (state-db-set-account state address
                                        (make-state-account :balance balance))
                  (state-db-set-code state address code)
                  (loop for (slot . value) in storage
                        do (state-db-set-storage state address slot value)))
         state))
      ((:flat :trie)
       (make-lazy-state-db
        (lambda (address)
          (let ((account (entry address)))
            (if account
                (destructuring-bind (address balance code storage) account
                  (declare (ignore address))
                  (let ((trie (when (eq mode :trie)
                                (let ((trie (make-mpt)))
                                  (loop for (slot . value) in storage
                                        do (mpt-put
                                            trie
                                            (ethereum-lisp.state::state-db-storage-proof-key
                                             slot)
                                            (rlp-encode value)))
                                  trie))))
                    (values (make-state-account
                             :balance balance
                             :storage-root (if trie
                                               (make-hash32 (mpt-root-hash trie))
                                               +empty-trie-hash+)
                             :code-hash (keccak-256-hash code))
                            code t '() trie)))
                (values nil nil nil))))
        (when (eq mode :flat)
          (lambda (address slot)
            (or (cdr (assoc slot (fourth (entry address)) :test #'hash32=))
                0)))
        (lambda (state) (declare (ignore state))))))))

(deftest backed-state-read-in-a-reverted-frame-survives-the-revert
  (let* ((sender (address-from-hex "0x00000000000000000000000000000000000000a1"))
         (contract (address-from-hex "0x00000000000000000000000000000000000000c1"))
         ;; No calldata: CALL itself with one byte, then copy slot 2 to slot 3.
         ;; One byte of calldata: write slot 1 (journals the account), read
         ;; slot 2 for the first time, then REVERT.
         (code (hex-to-bytes
                (concatenate 'string
                             "0x3660195760006000600160006000305af150"
                             "600254600355005b600160015560025450"
                             "60006000fd")))
         (slot (lambda (n) (lazy-storage-test-slot n)))
         (accounts (list (list sender (expt 10 18) (make-byte-vector 0) '())
                         (list contract 0 code
                               (list (cons (funcall slot 2) 42)))))
         (rules (eest-state-test-chain-rules "Osaka"))
         (results
           (loop for mode in '(:memory :flat :trie)
                 collect
                 (let* ((state (backed-execution-test-state accounts mode))
                        (receipt
                          (apply-message
                           state sender
                           (make-legacy-transaction :nonce 0 :gas-price 1
                                                    :gas-limit 200000
                                                    :to contract)
                           :chain-id 1 :chain-rules rules)))
                   (list mode
                         (receipt-status receipt)
                         (receipt-cumulative-gas-used receipt)
                         (state-db-get-storage state contract
                                               (funcall slot 3))
                         (state-db-get-storage state contract
                                               (funcall slot 1)))))))
    (destructuring-bind (memory flat trie) results
      ;; The oracle: the frame's write is undone, slot 2 copies through.
      (is (= 1 (second memory)))
      (is (= 42 (fourth memory)))
      (is (= 0 (fifth memory)))
      ;; Both lazily-backed forms agree with it, gas included.
      (dolist (lazy (list flat trie))
        (is (equal (rest memory) (rest lazy)))))))

;;; The live block itself, when its fixture is present (it is 1.3 MB of
;;; contract code, so it is fetched rather than committed; the commands are in
;;; docs/evidence/sec5-hoodi-gas-mismatch.txt).  PRESTATE.JSON is the merged
;;; go-ethereum prestateTracer output of the block's eleven transactions and
;;; TRANSACTIONS.TXT their signed envelopes, one hex string per line.

(defparameter +hoodi-3684027-fixture-directory+
  ".eest-fixtures-hoodi-3684027/")

(defun hoodi-3684027-fixture-path (name)
  (repository-relative-pathname
   (concatenate 'string +hoodi-3684027-fixture-directory+ name)))

(defun hoodi-3684027-quantity (value)
  (cond ((null value) 0)
        ((integerp value) value)
        (t (hex-to-quantity value))))

(defun hoodi-3684027-trie-backed-prestate ()
  "The block's pre-state served the way the durable node store serves it:
accounts from a loader, storage through each account's own storage trie."
  (let ((accounts (make-hash-table :test 'equal)))
    (dolist (entry (ethereum-lisp.json:json-object-entries
                    (ethereum-lisp.json:parse-json
                     (fixture-file-string
                      (hoodi-3684027-fixture-path "prestate.json")))
                    "Hoodi 3684027 prestate"))
      (let* ((account (cdr entry))
             (code (hex-to-bytes (or (fixture-object-field account "code") "0x")))
             (trie (make-mpt)))
        (let ((storage (fixture-object-field account "storage")))
          (when storage
            (dolist (slot (ethereum-lisp.json:json-object-entries
                           storage "Hoodi 3684027 storage"))
              (let ((value (hex-to-quantity (cdr slot))))
                (unless (zerop value)
                  (mpt-put trie
                           (ethereum-lisp.state::state-db-storage-proof-key
                            (hash32-from-hex (car slot)))
                           (rlp-encode value)))))))
        (setf (gethash (string-downcase (car entry)) accounts)
              (list (make-state-account
                     :nonce (hoodi-3684027-quantity
                             (fixture-object-field account "nonce"))
                     :balance (hoodi-3684027-quantity
                               (fixture-object-field account "balance"))
                     :storage-root (make-hash32 (mpt-root-hash trie))
                     :code-hash (keccak-256-hash code))
                    code
                    trie))))
    (make-lazy-state-db
     (lambda (address)
       (let ((entry (gethash (string-downcase (address-to-hex address))
                             accounts)))
         (if entry
             (destructuring-bind (account code trie) entry
               (values account code t '() trie))
             (values nil nil nil))))
     nil
     nil)))

(deftest hoodi-3684027-gas-used-matches-its-header-on-a-backed-state
  (:layer :integration)
  (unless (probe-file (hoodi-3684027-fixture-path "prestate.json"))
    (skip-test "Hoodi block 3684027 fixture is not present"))
  (let* ((config (ethereum-lisp.genesis::hoodi-chain-config))
         (number 3684027)
         (timestamp #x6ab47d6c)
         (rules (chain-config-rules config number timestamp))
         (transactions
           (with-open-file (in (hoodi-3684027-fixture-path "transactions.txt"))
             (loop for line = (read-line in nil nil)
                   while line
                   unless (blank-string-p line)
                     collect (transaction-from-encoding
                              (hex-to-bytes (string-trim " " line)))))))
    (is (= 11 (length transactions)))
    ;; The block is past BPO2 on Hoodi's schedule, as go-ethereum has it.
    (is (chain-rules-osaka-p rules))
    (is (chain-rules-bpo2-p rules))
    (multiple-value-bind (target max update-fraction)
        (chain-rules-blob-schedule rules)
      (declare (ignore target max))
      (multiple-value-bind (receipts gas-used)
          (apply-signed-message-list
           (hoodi-3684027-trie-backed-prestate) transactions
           :expected-chain-id 560048
           :chain-rules rules
           :base-fee #x3dfcfbc5
           :blob-base-fee (blob-base-fee #xc5def15
                                         :update-fraction update-fraction)
           :coinbase (address-from-hex
                      "0x25941dc771bb64514fc8abbce970307fb9d477e9")
           :block-number number
           :timestamp timestamp
           :prev-randao
           (hash32-from-hex
            "0x88a3a7cd592db1c25cd5aff99b92938ec5640a5dfae5b0dffc6a71f32cec2b15")
           :context-gas-limit #x3938700)
        ;; go-ethereum's receipts: the ninth transaction used 342,412 gas and
        ;; the block 4,348,360 (header gasUsed 0x4259c8). 04a3aff4 computed
        ;; 323,810 and 4,329,758 here, exactly the live rejection.
        (is (= 342412 (- (receipt-cumulative-gas-used (nth 9 receipts))
                         (receipt-cumulative-gas-used (nth 8 receipts)))))
        (is (= #x4259c8 gas-used))))))
