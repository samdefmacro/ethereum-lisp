(in-package #:ethereum-lisp.test)

(deftest eest-transaction-success-result-consistency-validation
  (let* ((case (first (load-eest-transaction-test-file
                       +eest-transaction-test-sample-path+)))
         (result (fixture-required-field case "result"))
         (success (eest-transaction-case-success-result case)))
    (validate-eest-transaction-success-results-consistent case success)
    (labels ((replace-field (object field value)
               (cons (cons field value)
                     (remove field object :key #'car :test #'string=)))
             (replace-fork-entry (fork entry)
               (cons (cons fork entry)
                     (remove fork result :key #'car :test #'string=))))
      (signals error
        (let* ((london (fixture-required-field result "London"))
               (bad-london
                 (replace-field
                  london
                  "hash"
                  "0x0000000000000000000000000000000000000000000000000000000000000001"))
               (bad-case
                 (replace-field
                  case
                  "result"
                  (replace-fork-entry "London" bad-london))))
          (convert-eest-transaction-case-to-vector bad-case)))
      (signals error
        (let* ((london (fixture-required-field result "London"))
               (bad-london
                 (replace-field
                  london
                  "sender"
                  "0x0000000000000000000000000000000000000001"))
               (bad-case
                 (replace-field
                  case
                  "result"
                  (replace-fork-entry "London" bad-london))))
          (convert-eest-transaction-case-to-vector bad-case))))))

(deftest eest-transaction-success-result-derived-validation
  (let* ((case (first (load-eest-transaction-test-file
                       +eest-transaction-test-sample-path+)))
         (result (fixture-required-field case "result")))
    (labels ((replace-field (object field value)
               (cons (cons field value)
                     (remove field object :key #'car :test #'string=)))
             (replace-fork-entry (fork entry)
               (cons (cons fork entry)
                     (remove fork result :key #'car :test #'string=))))
      (convert-eest-transaction-case-to-vector case)
      (signals error
        (let* ((frontier (fixture-required-field result "Frontier"))
               (bad-frontier
                 (replace-field
                  frontier
                  "hash"
                  "0x0000000000000000000000000000000000000000000000000000000000000001"))
               (bad-case
                 (replace-field
                  case
                  "result"
                  (replace-fork-entry "Frontier" bad-frontier))))
          (convert-eest-transaction-case-to-vector bad-case)))
      (signals error
        (let* ((frontier (fixture-required-field result "Frontier"))
               (bad-frontier
                 (replace-field
                  frontier
                  "sender"
                  "0x0000000000000000000000000000000000000001"))
               (bad-case
                 (replace-field
                  case
                  "result"
                  (replace-fork-entry "Frontier" bad-frontier))))
          (convert-eest-transaction-case-to-vector bad-case)))
      (signals error
        (let* ((frontier (fixture-required-field result "Frontier"))
               (bad-frontier
                 (replace-field
                  frontier
                  "intrinsicGas"
                  "0x5209"))
               (bad-case
                 (replace-field
                  case
                  "result"
                  (replace-fork-entry "Frontier" bad-frontier))))
          (convert-eest-transaction-case-to-vector bad-case))))))

(deftest eest-transaction-test-file-shape-validation
  (let* ((case (find "legacy-eip155-sample"
                     (load-eest-transaction-test-file
                      +eest-transaction-test-sample-path+)
                     :key (lambda (candidate)
                            (fixture-required-field candidate "name"))
                     :test #'string=))
         (result (fixture-object-field case "result"))
         (shanghai (fixture-object-field result "Shanghai"))
         (vector (convert-eest-transaction-case-to-vector case)))
    (is (string= "legacy-eip155-sample"
                 (fixture-object-field case "name")))
    (is (string= "0xf86c098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a76400008025a028ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276a067cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83"
                 (fixture-object-field case "txbytes")))
    (is (string= "0x33469b22e9f636356c4160a87eb19df52b7412e8eac32a4a55ffe88ea8350788"
                 (fixture-object-field shanghai "hash")))
    (is (string= "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"
                 (fixture-object-field shanghai "sender")))
    (is (string= "0x5208"
                 (fixture-object-field shanghai "intrinsicGas")))
    (is (string= "legacy"
                 (fixture-object-field vector "type")))
    (is (= 1 (fixture-object-field vector "chainId")))
    (is (string= "0x33469b22e9f636356c4160a87eb19df52b7412e8eac32a4a55ffe88ea8350788"
                 (fixture-object-field vector "hash")))
    (is (string= "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"
                 (fixture-object-field vector "sender"))))

  (let* ((cases (load-eest-transaction-test-file
                 +eest-transaction-test-sample-path+))
         (legacy-case
           (find "legacy-eip155-sample" cases
                 :key (lambda (case) (fixture-required-field case "name"))
                 :test #'string=))
         (access-list-case
           (find "typed-eip2930-access-list-sample" cases
                 :key (lambda (case) (fixture-required-field case "name"))
                 :test #'string=)))
    (labels ((without-fork-result (case fork)
               (let ((result (fixture-required-field case "result")))
                 (cons (cons "result"
                             (remove fork result :key #'car :test #'string=))
                       (remove "result" case :key #'car :test #'string=)))))
      (let* ((sparse-legacy
               (without-fork-result legacy-case "Homestead"))
             (legacy-vector
               (convert-eest-transaction-case-to-vector sparse-legacy))
             (legacy-result
               (fixture-required-field legacy-vector "result"))
             (frontier
               (fixture-required-field legacy-result "Frontier"))
             (homestead
               (fixture-required-field legacy-result "Homestead")))
        (is (equal frontier homestead))
        (validate-transaction-fixture-result-shape legacy-vector))
      (let* ((sparse-access-list
               (without-fork-result access-list-case "Homestead"))
             (access-list-vector
               (convert-eest-transaction-case-to-vector sparse-access-list))
             (homestead
               (fixture-required-field
                (fixture-required-field access-list-vector "result")
                "Homestead")))
        (is (string= "TransactionException.TYPE_1_TX_PRE_FORK"
                     (fixture-required-field homestead "exception")))
        (validate-transaction-fixture-result-shape access-list-vector))
      (let* ((sparse-access-list
               (without-fork-result access-list-case "Berlin"))
             (access-list-vector
               (convert-eest-transaction-case-to-vector sparse-access-list))
             (access-list-result
               (fixture-required-field access-list-vector "result"))
             (berlin
               (fixture-required-field access-list-result "Berlin"))
             (london
               (fixture-required-field access-list-result "London")))
        (is (equal london berlin))
        (validate-transaction-fixture-result-shape access-list-vector))))

  (signals error
    (normalize-eest-transaction-test-case
     "missing-result"
     (list (cons "txbytes" "0x01"))))
  (signals error
    (normalize-eest-transaction-test-case
     ""
     (list (cons "txbytes" "0x01")
           (cons "result" nil))))
  (signals error
    (normalize-eest-transaction-test-case
     nil
     (list (cons "txbytes" "0x01")
           (cons "result" nil))))
  (signals error
    (normalize-eest-transaction-test-case
     42
     (list (cons "txbytes" "0x01")
           (cons "result" nil))))
  (signals error
    (normalize-eest-transaction-test-case
     "empty-result"
     (list (cons "txbytes" "0x01")
           (cons "result" nil))))
  (validate-eest-transaction-test-file-entries
   (list (cons "valid-case" nil))
   "sample.json")
  (signals error
    (validate-eest-transaction-test-file-entries nil "empty.json"))
  (signals error
    (validate-eest-transaction-test-file-entries
     '("not-an-object-entry")
     "array.json"))
  (signals error
    (validate-eest-transaction-test-file-entries
     (list (cons "" nil))
     "sample.json"))
  (signals error
    (validate-eest-transaction-test-file-entries
     (list (cons nil nil))
     "sample.json"))
  (signals error
    (validate-eest-transaction-test-file-entries
     (list (cons "duplicate" nil)
           (cons "duplicate" nil))
     "sample.json"))
  (let ((case
          (normalize-eest-transaction-test-case
           "uppercase-success-fields"
           (list
            (cons "txbytes" "0XAB")
            (cons "result"
                  (list
                   (cons "Shanghai"
                         (list
                          (cons "hash"
                                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
                          (cons "sender"
                                "ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD")
                          (cons "intrinsicGas" "0x1")))))))))
    (let ((shanghai (fixture-object-field
                     (fixture-object-field case "result")
                     "Shanghai")))
      (is (string= "0xab" (fixture-object-field case "txbytes")))
      (is (string=
           "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
           (fixture-object-field shanghai "hash")))
      (is (string=
           "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"
           (fixture-object-field shanghai "sender")))))
  (signals error
    (normalize-eest-transaction-test-case
     "unknown-case-field"
     (list (cons "txbytes" "0x01")
           (cons "result" nil)
           (cons "unexpected" t))))
  (signals error
    (normalize-eest-transaction-test-case
     "non-string-case-field"
     (list (cons "txbytes" "0x01")
           (cons "result" nil)
           (cons 42 t))))
  (signals error
    (normalize-eest-transaction-test-case
     "non-string-txbytes"
     (list (cons "txbytes" 42)
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "exception"
                               "TransactionException.TYPE_2_TX_PRE_FORK"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "unknown-result-fork"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Osaka"
                        (list
                         (cons "exception"
                               "TransactionException.TYPE_2_TX_PRE_FORK"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "malformed-result-entry"
     (list (cons "txbytes" "0x01")
           (cons "result" '("not-a-fork-entry")))))
  (signals error
    (normalize-eest-transaction-test-case
     "non-string-result-fork"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons nil
                        (list
                         (cons "exception"
                               "TransactionException.TYPE_2_TX_PRE_FORK"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "blank-result-fork"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons ""
                        (list
                         (cons "exception"
                               "TransactionException.TYPE_2_TX_PRE_FORK"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "unknown-exception"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "exception"
                               "TransactionException.UNKNOWN"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "non-string-exception"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "exception" 42))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "duplicate-result-fork"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "exception"
                               "TransactionException.TYPE_2_TX_PRE_FORK")))
                  (cons "Shanghai"
                        (list
                         (cons "exception"
                               "TransactionException.TYPE_2_TX_PRE_FORK"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "missing-success-sender"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "hash"
                               "0x0000000000000000000000000000000000000000000000000000000000000001")
                         (cons "intrinsicGas" "0x5208")))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "success-non-string-hash"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "hash" 42)
                         (cons "sender"
                               "0x0000000000000000000000000000000000000001")
                         (cons "intrinsicGas" "0x5208"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "success-non-string-sender"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "hash"
                               "0x0000000000000000000000000000000000000000000000000000000000000001")
                         (cons "sender" 42)
                         (cons "intrinsicGas" "0x5208"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "success-non-string-gas"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "hash"
                               "0x0000000000000000000000000000000000000000000000000000000000000001")
                         (cons "sender"
                               "0x0000000000000000000000000000000000000001")
                         (cons "intrinsicGas" 42))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "success-with-exception"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "hash"
                               "0x0000000000000000000000000000000000000000000000000000000000000001")
                         (cons "sender"
                               "0x0000000000000000000000000000000000000001")
                         (cons "intrinsicGas" "0x5208")
                         (cons "exception"
                               "TransactionException.TYPE_2_TX_PRE_FORK"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "success-with-blank-exception"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "hash"
                               "0x0000000000000000000000000000000000000000000000000000000000000001")
                         (cons "sender"
                               "0x0000000000000000000000000000000000000001")
                         (cons "intrinsicGas" "0x5208")
                         (cons "exception" nil))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "success-prefixless-gas"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "hash"
                               "0x0000000000000000000000000000000000000000000000000000000000000001")
                         (cons "sender"
                               "0x0000000000000000000000000000000000000001")
                         (cons "intrinsicGas" "5208"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "success-leading-zero-gas"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "hash"
                               "0x0000000000000000000000000000000000000000000000000000000000000001")
                         (cons "sender"
                               "0x0000000000000000000000000000000000000001")
                         (cons "intrinsicGas" "0x05208"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "exception-with-sender"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "exception"
                               "TransactionException.TYPE_2_TX_PRE_FORK")
                         (cons "sender"
                               "0x0000000000000000000000000000000000000001"))))))))
  (signals error
    (normalize-eest-transaction-test-case
     "exception-with-gas"
     (list (cons "txbytes" "0x01")
           (cons "result"
                 (list
                  (cons "Shanghai"
                        (list
                         (cons "exception"
                               "TransactionException.TYPE_2_TX_PRE_FORK")
                         (cons "intrinsicGas" "0x5208"))))))))
  (signals error
    (convert-eest-transaction-case-to-vector
     (list
      (cons "name" "missing-tracked-fork")
      (cons "txbytes"
            "0xf86c098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a76400008025a028ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276a067cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83")
      (cons "result"
            (list
             (cons "Shanghai"
                   (list (cons "hash"
                               "0x33469b22e9f636356c4160a87eb19df52b7412e8eac32a4a55ffe88ea8350788")
                         (cons "sender"
                               "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f")
                         (cons "intrinsicGas" "0x5208"))))))))

