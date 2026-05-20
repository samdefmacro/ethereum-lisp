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
        (when (gethash name seen-fields)
          (error "~A has duplicate field ~A" label name))
        (setf (gethash name seen-fields) t)
        (unless (member name allowed-fields :test #'string=)
          (error "~A has unknown field ~A" label name))))))

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
        (when (gethash slot seen-slots)
          (error "Phase A Shanghai genesis account ~A storage has duplicate slot ~A"
                 address
                 slot))
        (setf (gethash slot seen-slots) t)
        (unless (and (stringp slot)
                     (not (minusp (hex-to-quantity slot))))
          (error "Phase A Shanghai genesis account ~A has malformed storage slot ~A"
                 address
                 slot))
        (let ((value (cdr entry)))
          (unless (or (and (integerp value) (not (minusp value)))
                      (and (stringp value)
                           (not (minusp (hex-to-quantity value)))))
            (error "Phase A Shanghai genesis account ~A storage slot ~A has malformed value ~A"
                   address
                   slot
                   value)))))))

(defun validate-phase-a-shanghai-genesis-account-shape (address account)
  (address-from-hex address)
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
    (hex-to-bytes (fixture-required-field account "code")))
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
        (when (gethash address seen-addresses)
          (error "Phase A Shanghai genesis alloc has duplicate address ~A"
                 address))
        (setf (gethash address seen-addresses) t)
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
  (when (blank-string-p (fixture-required-field fixture "source"))
    (error "Phase A Shanghai genesis fixture source must be present"))
  (validate-fixture-pinned-eest-source fixture)
  (validate-phase-a-shanghai-genesis-config-shape
   (fixture-required-field fixture "config"))
  (dolist (field '("nonce" "timestamp" "gasLimit" "difficulty"))
    (validate-phase-a-shanghai-genesis-non-negative-value
     fixture
     field
     "Phase A Shanghai genesis fixture"
     :required-p t))
  (hex-to-bytes (fixture-required-field fixture "extraData"))
  (hash32-from-hex (fixture-required-field fixture "mixHash"))
  (address-from-hex (fixture-required-field fixture "coinbase"))
  (hash32-from-hex (fixture-required-field fixture "stateRoot"))
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
     (phase-a-shanghai-genesis-shape-test-fixture
      :top-extra (list (cons "unexpectedTopField" t)))))
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
      :config-extra (list (cons "chainId" 1338)))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (phase-a-shanghai-genesis-shape-test-fixture
      :account-extra (list (cons "unexpectedAccountField" "0x1")))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (phase-a-shanghai-genesis-shape-test-fixture
      :account-extra (list (cons "balance" "0x2")))))
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
      :storage (list (cons "0x00" "0x2a")
                     (cons "0x00" "0x2b")))))
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
