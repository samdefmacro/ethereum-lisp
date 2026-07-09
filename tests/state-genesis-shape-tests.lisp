(in-package #:ethereum-lisp.test)

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
     (cons (cons "extraData" "00")
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
     (cons (cons "stateRoot"
                 "0X23CC0C47D1238030E9C1EC18013DCB17024D3D42729567ADBB6406A64D3007F3")
           (remove "stateRoot"
                   (phase-a-shanghai-genesis-shape-test-fixture)
                   :key #'car
                   :test #'string=))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (cons (cons "gasLimit" "0X1C9C380")
           (remove "gasLimit"
                   (phase-a-shanghai-genesis-shape-test-fixture)
                   :key #'car
                   :test #'string=))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (cons (cons "gasLimit" "0x01c9c380")
           (remove "gasLimit"
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
      :account-extra (list (cons "code" "6000")))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (phase-a-shanghai-genesis-shape-test-fixture
      :account-extra (list (cons "balance" "0x2")))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (phase-a-shanghai-genesis-shape-test-fixture
      :alloc-extra
      (list
       (cons "0x0000000000000000000000000000000000001003"
             (list (cons "balance" "0X1")))))))
  (signals error
    (validate-phase-a-shanghai-genesis-fixture-shape
     (phase-a-shanghai-genesis-shape-test-fixture
      :alloc-extra
      (list
       (cons "0x0000000000000000000000000000000000001003"
             (list (cons "balance" "0x01")))))))
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

