(in-package #:ethereum-lisp.test)

(defun engine-newpayload-v2-metadata-shape-test-fixture
    (&key top-extra eest-extra reference-extra)
  (append
   (list
    (cons "format" +engine-newpayload-v2-fixture-format+)
    (cons "source" "test fixture")
    (cons "executionSpecTests"
          (append
           (list (cons "release" +phase-a-eest-release+)
                 (cons "tagTarget" +phase-a-eest-tag-target+)
                 (cons "archive" +phase-a-eest-archive+)
                 (cons "status" "test"))
           eest-extra))
    (cons "referenceClients"
          (append
           (list (cons "geth" "test-geth")
                 (cons "nethermind" "test-nethermind")
                 (cons "reth" nil))
           reference-extra))
    (cons "cases" nil))
   top-extra))

(defun engine-newpayload-v2-case-shape-test-case (&key extra name)
  (append
   (list
    (cons "name" (or name "valid-engine-case"))
    (cons "network" "Shanghai")
    (cons "chainId" "0x1")
    (cons "config"
          (list (cons "berlinBlock" "0x0")
                (cons "londonBlock" "0x0")
                (cons "shanghaiTime" "0x0")))
    (cons "parent"
          (list
           (cons "number" "0x29")
           (cons "gasLimit" "0xc350")
           (cons "gasUsed" "0x61a8")
           (cons "timestamp" "0x62")
           (cons "baseFeePerGas" "0x64")
           (cons "feeRecipient" "0x0000000000000000000000000000000000000001")
           (cons "accounts"
                 (list
                  (list
                   (cons "address"
                         "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f")
                   (cons "nonce" "0x9")
                   (cons "balance" "0x1bc16d674ec80000"))))))
    (cons "payload"
          (list
           (cons "number" "0x2a")
           (cons "gasLimit" "0xc350")
           (cons "timestamp" "0x63")
           (cons "baseFeePerGas" "0x64")
           (cons "transactions"
                 (list
                  "0xf86c098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a76400008025a028ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276a067cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83"))
           (cons "withdrawals"
                 (list
                  (list
                   (cons "index" "0x0")
                   (cons "validatorIndex" "0x1")
                   (cons "address"
                         "0x0000000000000000000000000000000000000002")
                   (cons "amount" "0x1"))))))
    (cons "expect"
          (list
           (cons "status" "VALID")
           (cons "sender" "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f")
           (cons "senderNonce" "0xa")
           (cons "senderBalance" "0xddf38b6c895c000")
           (cons "recipient" "0x3535353535353535353535353535353535353535")
           (cons "recipientBalance" "0xde0b6b3a7640000")
           (cons "withdrawalRecipient"
                 "0x0000000000000000000000000000000000000002")
           (cons "withdrawalBalance" "0x3b9aca00")
           (cons "codeAddress" "0x0000000000000000000000000000000000001002")
           (cons "code" "0x6001600055")
           (cons "storageAddress" "0x0000000000000000000000000000000000001002")
           (cons "storageKey"
                 "0x0000000000000000000000000000000000000000000000000000000000000000")
           (cons "storageValue"
                 "0x000000000000000000000000000000000000000000000000000000000000002a")
           (cons "receiptType" "0x0")
           (cons "receiptStatus" "0x1"))))
   extra))

(deftest engine-newpayload-v2-fixture-metadata-validation
  (validate-engine-newpayload-v2-fixture-metadata
   (engine-newpayload-v2-metadata-shape-test-fixture))
  (signals error
    (validate-engine-newpayload-v2-fixture-metadata
     (engine-newpayload-v2-metadata-shape-test-fixture
      :top-extra (list (cons "unexpectedTopField" t)))))
  (signals error
    (validate-engine-newpayload-v2-fixture-metadata
     (engine-newpayload-v2-metadata-shape-test-fixture
      :top-extra (list (cons "source" "duplicate source")))))
  (signals error
    (validate-engine-newpayload-v2-fixture-metadata
     (cons (cons "source" 42)
           (remove "source"
                   (engine-newpayload-v2-metadata-shape-test-fixture)
                   :key #'car
                   :test #'string=))))
  (signals error
    (validate-engine-newpayload-v2-fixture-metadata
     (engine-newpayload-v2-metadata-shape-test-fixture
      :eest-extra (list (cons "unexpectedPinnedField" t)))))
  (signals error
    (validate-engine-newpayload-v2-fixture-metadata
     (engine-newpayload-v2-metadata-shape-test-fixture
      :reference-extra (list (cons "besu" "test-besu")))))
  (signals error
    (let* ((fixture (engine-newpayload-v2-metadata-shape-test-fixture))
           (references (fixture-required-field fixture "referenceClients")))
      (validate-engine-newpayload-v2-fixture-metadata
       (cons (cons "referenceClients"
                   (cons (cons "geth" 42)
                         (remove "geth" references
                                 :key #'car
                                 :test #'string=)))
             (remove "referenceClients" fixture
                     :key #'car
                     :test #'string=)))))
  (signals error
    (let* ((fixture (engine-newpayload-v2-metadata-shape-test-fixture))
           (references (fixture-required-field fixture "referenceClients")))
      (validate-engine-newpayload-v2-fixture-metadata
       (cons (cons "referenceClients"
                   (cons (cons "reth" "")
                         (remove "reth" references
                                 :key #'car
                                 :test #'string=)))
             (remove "referenceClients" fixture
                     :key #'car
                     :test #'string=)))))
  (signals error
    (let* ((fixture (engine-newpayload-v2-metadata-shape-test-fixture))
           (references (fixture-required-field fixture "referenceClients")))
      (validate-engine-newpayload-v2-fixture-metadata
       (cons (cons "referenceClients"
                   (cons (cons "reth" 42)
                         (remove "reth" references
                                 :key #'car
                                 :test #'string=)))
             (remove "referenceClients" fixture
                     :key #'car
                     :test #'string=))))))

(deftest engine-newpayload-v2-fixture-case-validation
  (let ((case (engine-newpayload-v2-case-shape-test-case)))
    (labels ((replace-field (object field value)
               (cons (cons field value)
                     (remove field object :key #'car :test #'string=))))
      (validate-engine-newpayload-v2-fixture-cases (list case))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases nil))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (engine-newpayload-v2-case-shape-test-case
                :extra (list (cons "unexpected" t))))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (engine-newpayload-v2-case-shape-test-case :name ""))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field case "network" 42))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list case
               (engine-newpayload-v2-case-shape-test-case
                :name "valid-engine-case"))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "config"
                (list (cons "berlinBlock" "0x0")
                      (cons "londonBlock" "0x0")
                      (cons "shanghaiTime" "0x0")
                      (cons "unknownFork" "0x0"))))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "config"
                (replace-field
                 (fixture-required-field case "config")
                 "londonBlock"
                 42)))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "config"
                (replace-field
                 (fixture-required-field case "config")
                 "londonBlock"
                 "0")))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "config"
                (replace-field
                 (fixture-required-field case "config")
                 "londonBlock"
                 "0X0")))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "config"
                (replace-field
                 (fixture-required-field case "config")
                 "londonBlock"
                 "0x00")))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "parent"
                (replace-field
                 (fixture-required-field case "parent")
                 "feeRecipient"
                 42)))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "parent"
                (replace-field
                 (fixture-required-field case "parent")
                 "feeRecipient"
                 "0x1234")))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "parent"
                (replace-field
                 (fixture-required-field case "parent")
                 "feeRecipient"
                 "0000000000000000000000000000000000000001")))))
      (signals error
        (let* ((parent (fixture-required-field case "parent"))
               (accounts (fixture-required-field parent "accounts"))
               (duplicate-accounts
                 (append accounts (list (first accounts)))))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "parent"
                  (replace-field parent "accounts" duplicate-accounts))))))
      (signals error
        (let* ((parent (fixture-required-field case "parent"))
               (accounts (fixture-required-field parent "accounts"))
               (account (first accounts))
               (bad-account (replace-field account "code" "6000")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "parent"
                  (replace-field parent "accounts" (list bad-account)))))))
      (signals error
        (let* ((parent (fixture-required-field case "parent"))
               (accounts (fixture-required-field parent "accounts"))
               (account (first accounts))
               (bad-account (replace-field account "code" "0X6000")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "parent"
                  (replace-field parent "accounts" (list bad-account)))))))
      (signals error
        (let* ((parent (fixture-required-field case "parent"))
               (accounts (fixture-required-field parent "accounts"))
               (account (first accounts))
               (bad-account
                 (replace-field
                  account
                  "storage"
                  (list
                   (cons
                    "0x00000000000000000000000000000000000000000000000000000000000000aa"
                    "0x1")
                   (cons
                    "00000000000000000000000000000000000000000000000000000000000000AA"
                    "0x2")))))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "parent"
                  (replace-field parent "accounts" (list bad-account)))))))
      (signals error
        (let* ((parent (fixture-required-field case "parent"))
               (accounts (fixture-required-field parent "accounts"))
               (account (first accounts))
               (bad-account
                 (replace-field
                  account
                  "storage"
                  (list
                   (cons
                    "0x00000000000000000000000000000000000000000000000000000000000000aa"
                    "0X1")))))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "parent"
                  (replace-field parent "accounts" (list bad-account)))))))
      (signals error
        (let* ((parent (fixture-required-field case "parent"))
               (accounts (fixture-required-field parent "accounts"))
               (account (first accounts))
               (bad-account
                 (replace-field
                  account
                  "storage"
                  (list
                   (cons
                    "0x00000000000000000000000000000000000000000000000000000000000000aa"
                    "0x01")))))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "parent"
                  (replace-field parent "accounts" (list bad-account)))))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "payload"
                (replace-field
                 (fixture-required-field case "payload")
                 "transactions"
                 nil)))))
      (signals error
        (let* ((payload (fixture-required-field case "payload"))
               (raw (first (fixture-required-field payload "transactions"))))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "payload"
                  (replace-field
                   payload
                   "transactions"
                   (list (subseq raw 2))))))))
      (signals error
        (let* ((payload (fixture-required-field case "payload"))
               (raw (first (fixture-required-field payload "transactions"))))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "payload"
                  (replace-field
                   payload
                   "transactions"
                   (list (string-upcase raw))))))))
      (signals error
        (let* ((payload (fixture-required-field case "payload"))
               (withdrawals (fixture-required-field payload "withdrawals"))
               (duplicate-withdrawals
                 (append withdrawals (list (first withdrawals)))))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "payload"
                  (replace-field
                   payload
                   "withdrawals"
                   duplicate-withdrawals))))))
      (signals error
        (let ((payload (fixture-required-field case "payload")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "payload"
                  (replace-field payload "number" "0x2b"))))))
      (signals error
        (let ((payload (fixture-required-field case "payload")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "payload"
                  (replace-field payload "timestamp" "0x62"))))))
      (signals error
        (let ((payload (fixture-required-field case "payload")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "payload"
                  (replace-field payload "gasLimit" "0x1"))))))
      (signals error
        (let ((payload (fixture-required-field case "payload")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "payload"
                  (replace-field payload "baseFeePerGas" "0x65"))))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "expect"
                (replace-field
                 (fixture-required-field case "expect")
                 "status"
                 "INVALID")))))
      (signals error
        (validate-engine-newpayload-v2-fixture-cases
         (list (replace-field
                case
                "expect"
                (replace-field
                 (fixture-required-field case "expect")
                 "status"
                 42)))))
      (signals error
        (let ((expect (fixture-required-field case "expect")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "expect"
                  (replace-field
                   expect
                   "sender"
                   "0x0000000000000000000000000000000000000001"))))))
      (signals error
        (let ((expect (fixture-required-field case "expect")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "expect"
                  (replace-field expect "senderNonce" "0xb"))))))
      (signals error
        (let ((expect (fixture-required-field case "expect")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "expect"
                  (replace-field expect "storageKey" 42))))))
      (signals error
        (let ((expect (fixture-required-field case "expect")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "expect"
                  (replace-field
                   expect
                   "storageKey"
                   "0000000000000000000000000000000000000000000000000000000000000000"))))))
      (signals error
        (let ((expect (fixture-required-field case "expect")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "expect"
                  (replace-field expect "code" "6001600055"))))))
      (signals error
        (let ((expect (fixture-required-field case "expect")))
          (validate-engine-newpayload-v2-fixture-cases
           (list (replace-field
                  case
                  "expect"
                  (replace-field expect "withdrawalBalance" "0x1")))))))))

(deftest engine-newpayload-v2-smoke-coverage-validation
  (let* ((fixture
           (load-handwritten-fixture-file
            +engine-newpayload-v2-fixture-path+))
         (cases (handwritten-fixture-cases fixture)))
    (validate-engine-newpayload-v2-fixture-cases cases)
    (validate-engine-newpayload-v2-smoke-coverage cases)
    (signals error
      (let ((+engine-newpayload-v2-smoke-case-names+
              '("shanghai-one-transfer-with-withdrawal"
                "shanghai-dynamic-fee-transfer-with-withdrawal")))
        (validate-engine-newpayload-v2-smoke-coverage cases)))
    (signals error
      (let ((+engine-newpayload-v2-smoke-case-names+
              '("shanghai-one-transfer-with-withdrawal"
                "shanghai-one-transfer-with-withdrawal"
                "shanghai-contract-creation-with-withdrawal")))
        (validate-engine-newpayload-v2-smoke-coverage cases)))
    (signals error
      (let ((+engine-newpayload-v2-smoke-case-names+
              '("shanghai-one-transfer-with-withdrawal"
                "shanghai-dynamic-fee-transfer-with-withdrawal"
                "missing-engine-smoke-case")))
        (validate-engine-newpayload-v2-smoke-coverage cases)))))

