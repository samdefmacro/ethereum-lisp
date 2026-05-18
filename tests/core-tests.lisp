(in-package #:ethereum-lisp.test)

(deftest empty-ommers-hash-vector
  (is (string= "0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347"
               (hash32-to-hex +empty-ommers-hash+))))

(deftest state-account-rlp-empty-account
  (let ((account (make-state-account)))
    (is (string= "0xf8448080a056e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421a0c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
                 (bytes-to-hex (state-account-rlp account))))))

(deftest legacy-transaction-rlp-contract-creation
  (let ((tx (make-legacy-transaction :nonce 1
                                     :gas-price 2
                                     :gas-limit 3
                                     :value 4
                                     :data #(96 0)
                                     :v 27
                                     :r 5
                                     :s 6)))
    (is (string= "0xcb01020380048260001b0506"
                 (bytes-to-hex (legacy-transaction-rlp tx))))))

(deftest legacy-transaction-signing-hash-vectors
  (let ((homestead
          (make-legacy-transaction
           :nonce 3
           :gas-price 1
           :gas-limit 2000
           :to (address-from-hex "0xb94f5374fce5edbc8e2a8697c15331677e6ebf0b")
           :value 10
           :data (hex-to-bytes "0x5544")
           :v 28
           :r #x98ff921201554726367d2be8c804a7ff89ccf285ebc57dff8ae4c44b9c19ac4a
           :s #x8887321be575c8095f789dd4c743dfe42c1820f9231f98a962b210e3ac2452a3))
        (eip155
          (make-legacy-transaction
           :nonce 9
           :gas-price 20000000000
           :gas-limit 21000
           :to (address-from-hex "0x3535353535353535353535353535353535353535")
           :value 1000000000000000000
           :v 37
           :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
           :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83)))
    (is (string= "0xfe7a79529ed5f7c3375d06b26b186a8644e0e16c373d7a12be41c62d6042b77a"
                 (hash32-to-hex (legacy-transaction-signing-hash homestead))))
    (is (string= "0xec098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a764000080018080"
                 (bytes-to-hex
                  (rlp-encode
                   (legacy-transaction-signing-payload eip155
                                                       :chain-id 1)))))
    (is (string= "0xdaf5a779ae972f972197303d7b574746c7ef83eadac0f2791ad23db92e4c8e53"
                 (hash32-to-hex
                  (legacy-transaction-signing-hash eip155 :chain-id 1))))))

(deftest legacy-transaction-sender-recovery
  (let ((tx
          (make-legacy-transaction
           :nonce 9
           :gas-price 20000000000
           :gas-limit 21000
           :to (address-from-hex "0x3535353535353535353535353535353535353535")
           :value 1000000000000000000
           :v 37
           :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
           :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83)))
    (is (legacy-transaction-protected-p tx))
    (is (= 1 (legacy-transaction-chain-id tx)))
    (is (string= "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"
                 (address-to-hex
                  (legacy-transaction-sender tx :expected-chain-id 1))))
    (is (null (legacy-transaction-sender tx :expected-chain-id 2)))
    (setf (legacy-transaction-r tx) 0)
    (is (null (legacy-transaction-sender tx :expected-chain-id 1)))))

(deftest typed-transaction-signing-hash-vectors
  (let ((empty-access
          (make-access-list-transaction :chain-id 1 :nonce 1))
        (signed-access
          (make-access-list-transaction
           :chain-id 1
           :nonce 3
           :gas-price 1
           :gas-limit 25000
           :to (address-from-hex "0xb94f5374fce5edbc8e2a8697c15331677e6ebf0b")
           :value 10
           :data (hex-to-bytes "0x5544")
           :y-parity 1
           :r #xc9519f4f2b30335884581971573fadf60c6204f59a911df35ee8a540456b2660
           :s #x32f1e8e2c5dd761f9e4f88f41c8310aeaba26a8bfcdacfedfa12ec3862d37521))
        (signed-dynamic
          (make-dynamic-fee-transaction
           :chain-id 1
           :nonce 1
           :max-priority-fee-per-gas 0
           :max-fee-per-gas #x0fa0
           :gas-limit #x84d0
           :to (address-from-hex "0x1111111111111111111111111111111111111111")
           :value 0
           :data #()
           :y-parity 1
           :r #xb7dfab36232379bb3d1497a4f91c1966b1f932eae3ade107bf5d723b9cb474e0
           :s #x6261c359a10f2132f126d250485b90cf20f30340801244a08ef6142ab33d1904)))
    (is (string= "0x846ad7672f2a3a40c1f959cd4a8ad21786d620077084d84c8d7c077714caa139"
                 (hash32-to-hex
                  (access-list-transaction-signing-hash empty-access))))
    (is (string= "0x49b486f0ec0a60dfbbca2d30cb07c9e8ffb2a2ff41f29a1ab6737475f6ff69f3"
                 (hash32-to-hex
                  (access-list-transaction-signing-hash signed-access))))
    (is (string= "0x01f8630103018261a894b94f5374fce5edbc8e2a8697c15331677e6ebf0b0a825544c001a0c9519f4f2b30335884581971573fadf60c6204f59a911df35ee8a540456b2660a032f1e8e2c5dd761f9e4f88f41c8310aeaba26a8bfcdacfedfa12ec3862d37521"
                 (bytes-to-hex
                  (access-list-transaction-encoding signed-access))))
    (is (string= "0x02f864010180820fa08284d09411111111111111111111111111111111111111118080c001a0b7dfab36232379bb3d1497a4f91c1966b1f932eae3ade107bf5d723b9cb474e0a06261c359a10f2132f126d250485b90cf20f30340801244a08ef6142ab33d1904"
                 (bytes-to-hex
                  (dynamic-fee-transaction-encoding signed-dynamic))))))

(deftest typed-transaction-sender-recovery
  (let ((access
          (make-access-list-transaction
           :chain-id 1
           :nonce 3
           :gas-price 1
           :gas-limit 25000
           :to (address-from-hex "0xb94f5374fce5edbc8e2a8697c15331677e6ebf0b")
           :value 10
           :data (hex-to-bytes "0x5544")
           :y-parity 1
           :r #xc9519f4f2b30335884581971573fadf60c6204f59a911df35ee8a540456b2660
           :s #x32f1e8e2c5dd761f9e4f88f41c8310aeaba26a8bfcdacfedfa12ec3862d37521))
        (dynamic
          (make-dynamic-fee-transaction
           :chain-id 1
           :nonce 1
           :max-priority-fee-per-gas 0
           :max-fee-per-gas #x0fa0
           :gas-limit #x84d0
           :to (address-from-hex "0x1111111111111111111111111111111111111111")
           :value 0
           :data #()
           :y-parity 1
           :r #xb7dfab36232379bb3d1497a4f91c1966b1f932eae3ade107bf5d723b9cb474e0
           :s #x6261c359a10f2132f126d250485b90cf20f30340801244a08ef6142ab33d1904)))
    (is (string= "0x27cf7d8449c9da59189427619ba59f985cee9c0f"
                 (address-to-hex
                  (access-list-transaction-sender access
                                                  :expected-chain-id 1))))
    (is (string= "0xd02d72e067e77158444ef2020ff2d325f929b363"
                 (address-to-hex
                  (dynamic-fee-transaction-sender dynamic
                                                  :expected-chain-id 1))))
    (is (string= "0xd02d72e067e77158444ef2020ff2d325f929b363"
                 (address-to-hex
                  (transaction-sender dynamic :expected-chain-id 1))))
    (is (null (transaction-sender access :expected-chain-id 2)))
    (setf (access-list-transaction-r access) 0)
    (is (null (transaction-sender access :expected-chain-id 1)))))

(deftest blob-and-set-code-transaction-sender-recovery
  (labels ((uint (bytes) (bytes-to-integer bytes))
           (address (bytes) (make-address bytes))
           (hash (bytes) (make-hash32 bytes))
           (empty-access-list-p (item)
             (null (rlp-list-items item)))
           (decode-authorization (item)
             (let ((items (rlp-list-items item)))
               (make-set-code-authorization
                :chain-id (uint (first items))
                :address (address (second items))
                :nonce (uint (third items))
                :y-parity (uint (fourth items))
                :r (uint (fifth items))
                :s (uint (sixth items))))))
    (let* ((blob-raw
             (hex-to-bytes
              "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675"))
           (blob-items (rlp-list-items (rlp-decode-one (subseq blob-raw 1))))
           (blob-tx
             (make-blob-transaction
              :chain-id (uint (first blob-items))
              :nonce (uint (second blob-items))
              :max-priority-fee-per-gas (uint (third blob-items))
              :max-fee-per-gas (uint (fourth blob-items))
              :gas-limit (uint (fifth blob-items))
              :to (address (sixth blob-items))
              :value (uint (seventh blob-items))
              :data (eighth blob-items)
              :access-list '()
              :max-fee-per-blob-gas (uint (nth 9 blob-items))
              :blob-versioned-hashes
              (mapcar #'hash (rlp-list-items (nth 10 blob-items)))
              :y-parity (uint (nth 11 blob-items))
              :r (uint (nth 12 blob-items))
              :s (uint (nth 13 blob-items))))
           (set-code-raw
             (hex-to-bytes
              "0x04f90126820539800285012a05f2008307a1209471562b71999873db5b286df957af199ec94617f78080c0f8baf85c82053994000000000000000000000000000000000000aaaa0101a07ed17af7d2d2b9ba7d797a202125bf505b9a0f962a67b3b61b56783d8faf7461a001b73b6e586edc706dce6c074eaec28692fa6359fb3446a2442f36777e1c0669f85a8094000000000000000000000000000000000000bbbb8001a05011890f198f0356a887b0779bde5afa1ed04e6acb1e3f37f8f18c7b6f521b98a056c3fa3456b103f3ef4a0acb4b647b9cab9ec4bc68fbcdf1e10b49fb2bcbcf6101a0167b0ecfc343a497095c22ee4270d3cc3b971cc3599fc73bbff727e0d2ed432da01c003c72306807492bf1150e39b2f79da23b49a4e83eb6e9209ae30d3572368f"))
           (set-code-items
             (rlp-list-items (rlp-decode-one (subseq set-code-raw 1))))
           (authorizations
             (mapcar #'decode-authorization
                     (rlp-list-items (nth 9 set-code-items))))
           (set-code-tx
             (make-set-code-transaction
              :chain-id (uint (first set-code-items))
              :nonce (uint (second set-code-items))
              :max-priority-fee-per-gas (uint (third set-code-items))
              :max-fee-per-gas (uint (fourth set-code-items))
              :gas-limit (uint (fifth set-code-items))
              :to (address (sixth set-code-items))
              :value (uint (seventh set-code-items))
              :data (eighth set-code-items)
              :access-list '()
              :authorization-list authorizations
              :y-parity (uint (nth 10 set-code-items))
              :r (uint (nth 11 set-code-items))
              :s (uint (nth 12 set-code-items)))))
      (is (empty-access-list-p (nth 8 blob-items)))
      (is (bytes= blob-raw (blob-transaction-encoding blob-tx)))
      (is (string= "0x0c2c51a0990aee1d73c1228de158688341557508"
                   (address-to-hex
                    (transaction-sender blob-tx :expected-chain-id 1337))))
      (is (null (transaction-sender blob-tx :expected-chain-id 1)))
      (is (empty-access-list-p (nth 8 set-code-items)))
      (is (bytes= set-code-raw (set-code-transaction-encoding set-code-tx)))
      (is (string= "0x71562b71999873db5b286df957af199ec94617f7"
                   (address-to-hex
                    (transaction-sender set-code-tx
                                        :expected-chain-id 1337))))
      (is (string= "0x71562b71999873db5b286df957af199ec94617f7"
                   (address-to-hex
                    (set-code-authorization-authority
                     (first authorizations)))))
      (is (string= "0x703c4b2bd70c169f5717101caee543299fc946c7"
                   (address-to-hex
                    (set-code-authorization-authority
                     (second authorizations))))))))

(deftest block-header-hash-is-hash32
  (let ((hash (block-header-hash (make-block-header))))
    (is (hash32-p hash))
    (is (= 66 (length (hash32-to-hex hash))))))

(deftest execution-requests-hash-skips-empty-request-payloads
  (flet ((requests-hash-hex (requests)
           (hash32-to-hex (execution-requests-hash requests))))
    (is (string= "0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
                 (requests-hash-hex '())))
    (is (string= "0x5718d61e4ad0bf7361f89a3d32dd9b29967017c96043bed3e6f7f0a29912f49e"
                 (requests-hash-hex (list #(#x00) #(#x01 #xaa)))))
    (is (string= "0xf050ca62d7d8be620cce73c1100a9d310f09935cee72604b696542da6d0f7496"
                 (requests-hash-hex
                  (list #(#x01 #xaa) #(#x02 #xbb #xcc)))))))

(deftest execution-request-fields-validation
  (let ((block (make-block)))
    (is (bytes= #(#x01)
                (validate-execution-request-fields #(#x01))))
    (signals block-validation-error
      (validate-execution-request-fields #()))
    (signals block-validation-error
      (validate-execution-request-fields "not bytes"))
    (setf (block-requests block) (list #())
          (block-requests-present-p block) t
          (block-header-requests-hash (block-header block))
          (execution-requests-hash '()))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest eip1559-base-fee-calculation-and-validation
  (let* ((parent (make-block-header :gas-limit 2000
                                    :gas-used 1000
                                    :base-fee-per-gas 1000))
         (same-target (make-block-header :base-fee-per-gas 1000))
         (over-target (make-block-header :base-fee-per-gas 1125))
         (under-target (make-block-header :base-fee-per-gas 875))
         (low-base-parent (make-block-header :gas-limit 2000
                                             :gas-used 2000
                                             :base-fee-per-gas 7))
         (first-london (make-block-header :base-fee-per-gas
                                          +initial-base-fee+)))
    (is (= 1000 (expected-base-fee-per-gas parent)))
    (is (validate-block-base-fee parent same-target))
    (setf (block-header-gas-used parent) 2000)
    (is (= 1125 (expected-base-fee-per-gas parent)))
    (is (validate-block-base-fee parent over-target))
    (setf (block-header-gas-used parent) 0)
    (is (= 875 (expected-base-fee-per-gas parent)))
    (is (validate-block-base-fee parent under-target))
    (is (= 8 (expected-base-fee-per-gas low-base-parent)))
    (is (= +initial-base-fee+
           (expected-base-fee-per-gas parent :london-parent-p nil)))
    (is (validate-block-base-fee parent first-london
                                 :london-parent-p nil))
    (setf (block-header-base-fee-per-gas same-target) 999)
    (signals block-validation-error
      (validate-block-base-fee parent same-target))))

(deftest eip1559-transaction-fee-validation
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (legacy (make-legacy-transaction :gas-price 7))
         (dynamic (make-dynamic-fee-transaction
                   :to recipient
                   :max-priority-fee-per-gas 3
                   :max-fee-per-gas 10))
         (capped (make-dynamic-fee-transaction
                  :to recipient
                  :max-priority-fee-per-gas 10
                  :max-fee-per-gas 12))
         (tip-too-high (make-dynamic-fee-transaction
                        :to recipient
                        :max-priority-fee-per-gas 11
                        :max-fee-per-gas 10))
         (tip-too-wide (make-dynamic-fee-transaction
                        :to recipient
                        :max-priority-fee-per-gas (1+ +uint256-max+)
                        :max-fee-per-gas (1+ +uint256-max+)))
         (fee-too-wide (make-dynamic-fee-transaction
                        :to recipient
                        :max-priority-fee-per-gas 1
                        :max-fee-per-gas (1+ +uint256-max+)))
         (fee-too-low (make-dynamic-fee-transaction
                       :to recipient
                       :max-priority-fee-per-gas 1
                       :max-fee-per-gas 4)))
    (is (= 7 (transaction-effective-gas-price legacy :base-fee 5)))
    (is (= 8 (transaction-effective-gas-price dynamic :base-fee 5)))
    (is (= 12 (transaction-effective-gas-price capped :base-fee 5)))
    (is (validate-1559-transaction-fees dynamic 5))
    (signals block-validation-error
      (validate-1559-transaction-fees tip-too-high 5))
    (signals block-validation-error
      (validate-1559-transaction-fees tip-too-wide 5))
    (signals block-validation-error
      (validate-1559-transaction-fees fee-too-wide 5))
    (signals block-validation-error
      (transaction-effective-gas-price fee-too-low :base-fee 5))))

(deftest transaction-constructors-reject-negative-fee-fields
  (let ((negative (parse-integer "-1"))
        (recipient (address-from-hex
                    "0x0000000000000000000000000000000000000001"))
        (blob-hash (hash32-from-hex
                    "0x0100000000000000000000000000000000000000000000000000000000000000")))
    (signals type-error
      (make-legacy-transaction :gas-price negative))
    (signals type-error
      (make-dynamic-fee-transaction :to recipient
                                    :max-priority-fee-per-gas negative
                                    :max-fee-per-gas 10))
    (signals type-error
      (make-dynamic-fee-transaction :to recipient
                                    :max-priority-fee-per-gas 1
                                    :max-fee-per-gas negative))
    (signals type-error
      (make-blob-transaction :to recipient
                             :max-fee-per-blob-gas negative
                             :blob-versioned-hashes (list blob-hash)))))

(deftest chain-config-fork-activation
  (let ((config (make-chain-config :chain-id 1
                                   :constantinople-block 7
                                   :london-block 10
                                   :shanghai-time 100
                                   :cancun-time 200
                                   :prague-time 300
                                   :osaka-time 400
                                   :bpo1-time 500
                                   :bpo2-time 600
                                   :bpo3-time 700
                                   :bpo4-time 800
                                   :bpo5-time 900
                                   :amsterdam-time 1000
                                   :ubt-time 1100
                                   :enable-ubt-at-genesis-p t)))
    (is (not (fork-block-active-p nil 10)))
    (is (not (fork-block-active-p 10 9)))
    (is (fork-block-active-p 10 10))
    (is (not (fork-time-active-p nil 100)))
    (is (not (fork-time-active-p 100 99)))
    (is (fork-time-active-p 100 100))
    (is (= 1 (chain-config-chain-id config)))
    (is (not (chain-config-london-p config 9)))
    (is (chain-config-london-p config 10))
    (is (not (chain-config-shanghai-p config 9 100)))
    (is (chain-config-shanghai-p config 10 100))
    (is (not (chain-config-cancun-p config 10 199)))
    (is (chain-config-cancun-p config 10 200))
    (is (not (chain-config-prague-p config 10 299)))
    (is (chain-config-prague-p config 10 300))
    (is (not (chain-config-expanded-blob-schedule-p config 10 299)))
    (is (chain-config-expanded-blob-schedule-p config 10 300))
    (is (not (chain-config-osaka-p config 10 399)))
    (is (chain-config-osaka-p config 10 400))
    (is (not (chain-config-bpo1-p config 10 499)))
    (is (chain-config-bpo1-p config 10 500))
    (is (not (chain-config-bpo2-p config 10 599)))
    (is (chain-config-bpo2-p config 10 600))
    (is (not (chain-config-bpo3-p config 10 699)))
    (is (chain-config-bpo3-p config 10 700))
    (is (not (chain-config-bpo4-p config 10 799)))
    (is (chain-config-bpo4-p config 10 800))
    (is (not (chain-config-bpo5-p config 10 899)))
    (is (chain-config-bpo5-p config 10 900))
    (is (not (chain-config-amsterdam-p config 10 999)))
    (is (chain-config-amsterdam-p config 10 1000))
    (is (not (chain-config-ubt-p config 10 1099)))
    (is (chain-config-ubt-p config 10 1100))
    (is (chain-config-ubt-genesis-p config))
    (is (not (chain-config-petersburg-p config 6)))
    (is (chain-config-petersburg-p config 7))))

(deftest chain-config-rules-snapshot
  (let* ((config (make-chain-config :chain-id 5
                                    :berlin-block 5
                                    :london-block 10
                                    :shanghai-time 20
                                    :cancun-time 30
                                    :prague-time 40
                                    :osaka-time 50
                                    :bpo1-time 60
                                    :bpo2-time 70
                                    :bpo3-time 80
                                    :bpo4-time 90
                                    :bpo5-time 100
                                    :amsterdam-time 110
                                    :ubt-time 120))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (access-list (make-access-list-transaction :to recipient))
         (dynamic (make-dynamic-fee-transaction :to recipient))
         (blob (make-blob-transaction
                :to recipient
                :blob-versioned-hashes
                (list (hash32-from-hex
                       "0x0100000000000000000000000000000000000000000000000000000000000000"))))
         (set-code (make-set-code-transaction
                    :to recipient
                    :authorization-list
                    (list (make-set-code-authorization
                           :address recipient))))
         (london-rules (chain-config-rules config 10 20))
         (prague-rules (chain-config-rules config 10 40))
         (osaka-rules (chain-config-rules config 10 50))
         (bpo1-rules (chain-config-rules config 10 60))
         (bpo2-rules (chain-config-rules config 10 70))
         (bpo3-rules (chain-config-rules config 10 80))
         (bpo4-rules (chain-config-rules config 10 90))
         (bpo5-rules (chain-config-rules config 10 100))
         (amsterdam-rules (chain-config-rules config 10 110))
         (ubt-rules (chain-config-rules config 10 120)))
    (is (= 5 (chain-rules-chain-id london-rules)))
    (is (chain-rules-berlin-p london-rules))
    (is (chain-rules-london-p london-rules))
    (is (chain-rules-shanghai-p london-rules))
    (is (not (chain-rules-cancun-p london-rules)))
    (is (not (chain-rules-prague-p london-rules)))
    (is (chain-rules-transaction-type-supported-p london-rules access-list))
    (is (chain-rules-transaction-type-supported-p london-rules dynamic))
    (is (not (chain-rules-transaction-type-supported-p london-rules blob)))
    (is (chain-rules-cancun-p prague-rules))
    (is (chain-rules-prague-p prague-rules))
    (is (not (chain-rules-osaka-p prague-rules)))
    (is (chain-rules-expanded-blob-schedule-p prague-rules))
    (is (chain-rules-osaka-p osaka-rules))
    (is (chain-rules-expanded-blob-schedule-p osaka-rules))
    (is (chain-rules-bpo1-p bpo1-rules))
    (is (chain-rules-bpo2-p bpo2-rules))
    (is (chain-rules-bpo3-p bpo3-rules))
    (is (chain-rules-bpo4-p bpo4-rules))
    (is (chain-rules-bpo5-p bpo5-rules))
    (is (chain-rules-amsterdam-p amsterdam-rules))
    (is (not (chain-rules-ubt-p amsterdam-rules)))
    (is (chain-rules-ubt-p ubt-rules))
    (is (chain-rules-transaction-type-supported-p prague-rules blob))
    (is (chain-rules-transaction-type-supported-p prague-rules set-code))
    (multiple-value-bind (target max update-fraction)
        (chain-config-blob-schedule config 10 60)
      (is (= (* +bpo1-target-blobs-per-block+ +blob-gas-per-blob+)
             target))
      (is (= (* +bpo1-max-blobs-per-block+ +blob-gas-per-blob+) max))
      (is (= +bpo1-blob-base-fee-update-fraction+ update-fraction)))
    (multiple-value-bind (target max update-fraction)
        (chain-rules-blob-schedule bpo2-rules)
      (is (= (* +bpo2-target-blobs-per-block+ +blob-gas-per-blob+)
             target))
      (is (= (* +bpo2-max-blobs-per-block+ +blob-gas-per-blob+) max))
      (is (= +bpo2-blob-base-fee-update-fraction+ update-fraction)))
    (multiple-value-bind (target max update-fraction)
        (chain-config-blob-schedule config 10 80)
      (is (= (* +bpo3-target-blobs-per-block+ +blob-gas-per-blob+)
             target))
      (is (= (* +bpo3-max-blobs-per-block+ +blob-gas-per-blob+) max))
      (is (= +bpo3-blob-base-fee-update-fraction+ update-fraction)))
    (multiple-value-bind (target max update-fraction)
        (chain-rules-blob-schedule bpo4-rules)
      (is (= (* +bpo4-target-blobs-per-block+ +blob-gas-per-blob+)
             target))
      (is (= (* +bpo4-max-blobs-per-block+ +blob-gas-per-blob+) max))
      (is (= +bpo4-blob-base-fee-update-fraction+ update-fraction)))))

(deftest custom-blob-schedule-overrides-fork-defaults
  (let* ((early-entry (make-blob-schedule-entry :timestamp 40
                                                :target-blobs 5
                                                :max-blobs 7
                                                :update-fraction 424242))
         (late-entry (make-blob-schedule-entry :timestamp 90
                                               :target-blobs 2
                                               :max-blobs 4
                                               :update-fraction 999999))
         (config (make-chain-config :london-block 0
                                    :cancun-time 0
                                    :bpo3-time 80
                                    :custom-blob-schedule
                                    (list late-entry early-entry))))
    (multiple-value-bind (target max update-fraction)
        (chain-config-blob-schedule config 1 39)
      (is (= (* +target-blobs-per-block+ +blob-gas-per-blob+) target))
      (is (= (* +max-blobs-per-block+ +blob-gas-per-blob+) max))
      (is (= +blob-base-fee-update-fraction+ update-fraction)))
    (multiple-value-bind (target max update-fraction)
        (chain-config-blob-schedule config 1 80)
      (is (= (* 5 +blob-gas-per-blob+) target))
      (is (= (* 7 +blob-gas-per-blob+) max))
      (is (= 424242 update-fraction)))
    (multiple-value-bind (target max update-fraction)
        (chain-config-blob-schedule config 1 90)
      (is (= (* 2 +blob-gas-per-blob+) target))
      (is (= (* 4 +blob-gas-per-blob+) max))
      (is (= 999999 update-fraction)))
    (let ((rules (chain-config-rules config 1 80)))
      (multiple-value-bind (target max update-fraction)
          (chain-rules-blob-schedule rules)
        (is (= (* 5 +blob-gas-per-blob+) target))
        (is (= (* 7 +blob-gas-per-blob+) max))
        (is (= 424242 update-fraction))))))

(deftest chain-config-from-genesis-config-parses-geth-fields
  (let* ((genesis-config
           '(("chainId" . "123")
             ("homesteadBlock" . 0)
             ("daoForkBlock" . 2)
             ("daoForkSupport" . t)
             ("londonBlock" . "5")
             ("muirGlacierBlock" . 6)
             ("arrowGlacierBlock" . 7)
             ("grayGlacierBlock" . 8)
             ("cancunTime" . "0x10")
             ("bpo3Time" . 30)
             ("bpo5Time" . 40)
             ("amsterdamTime" . 50)
             ("ubtTime" . 60)
             ("enableUBTAtGenesis" . t)
             ("terminalTotalDifficulty" . 0)
             ("terminalTotalDifficultyPassed" . t)
             ("mergeNetsplitBlock" . "9")
             ("depositContractAddress" .
              "0x00000000219ab540356cbb839cbe05303d7705fa")
             ("blobSchedule" .
              (("bpo3" .
                (("target" . 8)
                 ("max" . 11)
                 ("baseFeeUpdateFraction" . "12345")))
               ("bpo5" .
                (("target" . 34)
                 ("max" . 55)
                 ("baseFeeUpdateFraction" . 98765)))
               ("bpo4" .
                (("target" . 13)
                 ("max" . 17)
                 ("baseFeeUpdateFraction" . 67890)))))))
         (config (chain-config-from-genesis-config genesis-config)))
    (is (= 123 (chain-config-chain-id config)))
    (is (= 0 (chain-config-homestead-block config)))
    (is (= 2 (chain-config-dao-fork-block config)))
    (is (chain-config-dao-fork-support config))
    (is (chain-config-dao-fork-p config 2))
    (is (= 5 (chain-config-london-block config)))
    (is (= 6 (chain-config-muir-glacier-block config)))
    (is (= 7 (chain-config-arrow-glacier-block config)))
    (is (= 8 (chain-config-gray-glacier-block config)))
    (is (= 16 (chain-config-cancun-time config)))
    (is (= 30 (chain-config-bpo3-time config)))
    (is (= 40 (chain-config-bpo5-time config)))
    (is (= 50 (chain-config-amsterdam-time config)))
    (is (= 60 (chain-config-ubt-time config)))
    (is (chain-config-enable-ubt-at-genesis-p config))
    (is (= 0 (chain-config-terminal-total-difficulty config)))
    (is (chain-config-terminal-total-difficulty-passed config))
    (is (= 9 (chain-config-merge-netsplit-block config)))
    (is (string= "0x00000000219ab540356cbb839cbe05303d7705fa"
                 (address-to-hex
                  (chain-config-deposit-contract-address config))))
    (is (= 2 (length (chain-config-custom-blob-schedule config))))
    (multiple-value-bind (target max update-fraction)
        (chain-config-blob-schedule config 6 30)
      (is (= (* 8 +blob-gas-per-blob+) target))
      (is (= (* 11 +blob-gas-per-blob+) max))
      (is (= 12345 update-fraction)))
    (multiple-value-bind (target max update-fraction)
        (chain-config-blob-schedule config 6 40)
      (is (= (* 34 +blob-gas-per-blob+) target))
      (is (= (* 55 +blob-gas-per-blob+) max))
      (is (= 98765 update-fraction)))))

(deftest chain-config-from-genesis-config-parses-nethermind-fork-aliases
  (let ((config (chain-config-from-genesis-config
                 '(("chainId" . 1)
                   ("tangerineWhistleBlock" . 11)
                   ("spuriousDragonBlock" . 22)))))
    (is (= 11 (chain-config-eip150-block config)))
    (is (= 22 (chain-config-eip155-block config)))
    (is (= 22 (chain-config-eip158-block config)))))

(deftest chain-config-from-genesis-config-rejects-bad-blob-schedule
  (signals block-validation-error
    (chain-config-from-genesis-config
     '(("chainId" . 1)
       ("cancunTime" . 0)
       ("blobSchedule" .
        (("cancun" .
          (("target" . 3)
           ("max" . 6)))))))))

(deftest chain-config-from-genesis-config-rejects-bad-merge-flag
  (signals block-validation-error
    (chain-config-from-genesis-config
     '(("chainId" . 1)
       ("terminalTotalDifficultyPassed" . "true")))))

(deftest chain-config-from-genesis-json-string-parses-config
  (let* ((json "{\"config\":{\"chainId\":\"0x7b\",\"londonBlock\":\"5\",\"cancunTime\":16,\"bpo3Time\":30,\"terminalTotalDifficultyPassed\":true,\"depositContractAddress\":\"0x00000000219ab540356cbb839cbe05303d7705fa\",\"blobSchedule\":{\"bpo3\":{\"target\":8,\"max\":11,\"baseFeeUpdateFraction\":\"12345\"}}}}")
         (config (chain-config-from-genesis-json-string json)))
    (is (= 123 (chain-config-chain-id config)))
    (is (= 5 (chain-config-london-block config)))
    (is (= 16 (chain-config-cancun-time config)))
    (is (= 30 (chain-config-bpo3-time config)))
    (is (chain-config-terminal-total-difficulty-passed config))
    (is (string= "0x00000000219ab540356cbb839cbe05303d7705fa"
                 (address-to-hex
                  (chain-config-deposit-contract-address config))))
    (multiple-value-bind (target max update-fraction)
        (chain-config-blob-schedule config 6 30)
      (is (= (* 8 +blob-gas-per-blob+) target))
      (is (= (* 11 +blob-gas-per-blob+) max))
      (is (= 12345 update-fraction)))))

(deftest chain-config-from-genesis-json-file-parses-config
  (let ((path (make-pathname :name "ethereum-lisp-genesis-test"
                             :type "json"
                             :defaults #P"/private/tmp/")))
    (unwind-protect
         (progn
           (with-open-file (stream path
                                   :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
             (write-string
              "{\"config\":{\"chainId\":9,\"londonBlock\":0,\"cancunTime\":0}}"
              stream))
           (let ((config (chain-config-from-genesis-json-file path)))
             (is (= 9 (chain-config-chain-id config)))
             (is (= 0 (chain-config-london-block config)))
             (is (= 0 (chain-config-cancun-time config)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest genesis-json-parser-rejects-non-integer-numbers
  (signals block-validation-error
    (chain-config-from-genesis-json-string
     "{\"config\":{\"chainId\":1.5}}")))

(deftest genesis-alloc-from-json-parses-account-fields
  (let* ((json (concatenate
                'string
                "{\"alloc\":{"
                "\"0000000000000000000000000000000000000001\":{"
                "\"balance\":\"0x10\","
                "\"nonce\":\"2\","
                "\"code\":\"0x60016000\","
                "\"storage\":{"
                "\"0x0000000000000000000000000000000000000000000000000000000000000007\":\"0x2a\""
                "}}}}"))
         (alloc (genesis-alloc-from-genesis-json-string json))
         (account (first alloc))
         (storage-entry (first (genesis-account-storage account))))
    (is (= 1 (length alloc)))
    (is (string= "0x0000000000000000000000000000000000000001"
                 (address-to-hex (genesis-account-address account))))
    (is (= 16 (genesis-account-balance account)))
    (is (= 2 (genesis-account-nonce account)))
    (is (string= "0x60016000"
                 (bytes-to-hex (genesis-account-code account))))
    (is (string= "0x0000000000000000000000000000000000000000000000000000000000000007"
                 (hash32-to-hex (car storage-entry))))
    (is (= 42 (cdr storage-entry)))))

(deftest genesis-alloc-from-json-rejects-negative-quantities
  (signals block-validation-error
    (genesis-alloc-from-genesis-json-string
     "{\"alloc\":{\"0000000000000000000000000000000000000001\":{\"balance\":\"-1\"}}}")))

(deftest genesis-alloc-storage-pads-short-hex-keys-and-values
  (let* ((json (concatenate
                'string
                "{\"alloc\":{"
                "\"0000000000000000000000000000000000000001\":{"
                "\"balance\":\"1\","
                "\"storage\":{\"0x07\":\"0x2a\"}"
                "}}}"))
         (account (first (genesis-alloc-from-genesis-json-string json)))
         (storage-entry (first (genesis-account-storage account))))
    (is (string= "0x0000000000000000000000000000000000000000000000000000000000000007"
                 (hash32-to-hex (car storage-entry))))
    (is (= 42 (cdr storage-entry)))))

(deftest genesis-alloc-storage-rejects-overwide-hex-values
  (signals block-validation-error
    (genesis-alloc-from-genesis-json-string
     (concatenate
      'string
      "{\"alloc\":{\"0000000000000000000000000000000000000001\":"
      "{\"balance\":\"1\",\"storage\":{\"0x01\":\"0x"
      "010000000000000000000000000000000000000000000000000000000000000000"
      "\"}}}}"))))

(deftest genesis-expected-state-root-from-json-parses-hash
  (let* ((root "0x0000000000000000000000000000000000000000000000000000000000000007")
         (json (format nil "{\"stateRoot\":\"~A\"}" root)))
    (is (string= root
                 (hash32-to-hex
                  (genesis-expected-state-root-from-genesis-json-string json))))))

(deftest genesis-expected-state-root-from-json-rejects-bad-hash
  (signals block-validation-error
    (genesis-expected-state-root-from-genesis-json-string
     "{\"stateRoot\":\"0x1234\"}")))

(deftest genesis-header-from-json-maps-geth-fields-and-fork-defaults
  (let* ((state-root (hash32-from-hex
                      "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (mix-hash (hash32-from-hex
                    "0x0200000000000000000000000000000000000000000000000000000000000000"))
         (json (concatenate
                'string
                "{\"config\":{"
                "\"londonBlock\":0,"
                "\"shanghaiTime\":0,"
                "\"cancunTime\":0,"
                "\"pragueTime\":0,"
                "\"amsterdamTime\":0"
                "},"
                "\"nonce\":\"0x0102030405060708\","
                "\"timestamp\":0,"
                "\"extraData\":\"0x1234\","
                "\"gasLimit\":0,"
                "\"gasUsed\":\"0x09\","
                "\"difficulty\":\"0x02\","
                "\"mixHash\":\"" (hash32-to-hex mix-hash) "\","
                "\"coinbase\":\"0x0000000000000000000000000000000000000001\""
                "}"))
         (header (genesis-header-from-genesis-json-string
                  json :state-root state-root)))
    (is (string= (hash32-to-hex state-root)
                 (hash32-to-hex (block-header-state-root header))))
    (is (= +genesis-gas-limit+ (block-header-gas-limit header)))
    (is (= 9 (block-header-gas-used header)))
    (is (= 2 (block-header-difficulty header)))
    (is (= +initial-base-fee+ (block-header-base-fee-per-gas header)))
    (is (string= "0x0102030405060708"
                 (bytes-to-hex (block-header-nonce header))))
    (is (string= "0x1234" (bytes-to-hex (block-header-extra-data header))))
    (is (string= "0x0000000000000000000000000000000000000001"
                 (address-to-hex (block-header-beneficiary header))))
    (is (string= (hash32-to-hex mix-hash)
                 (hash32-to-hex (block-header-mix-hash header))))
    (is (string= (hash32-to-hex (withdrawal-list-root '()))
                 (hash32-to-hex (block-header-withdrawals-root header))))
    (is (string= (hash32-to-hex (zero-hash32))
                 (hash32-to-hex (block-header-parent-beacon-root header))))
    (is (= 0 (block-header-excess-blob-gas header)))
    (is (= 0 (block-header-blob-gas-used header)))
    (is (string= (hash32-to-hex (execution-requests-hash '()))
                 (hash32-to-hex (block-header-requests-hash header))))
    (is (string= (hash32-to-hex +empty-ommers-hash+)
                 (hash32-to-hex
                  (block-header-block-access-list-hash header))))
    (is (= 0 (block-header-slot-number header)))))

(deftest genesis-header-from-json-accepts-geth-field-aliases
  (let* ((mix-hash (hash32-from-hex
                    "0x0300000000000000000000000000000000000000000000000000000000000000"))
         (parent-beacon-root
           (hash32-from-hex
            "0x0400000000000000000000000000000000000000000000000000000000000000"))
         (json (concatenate
                'string
                "{\"config\":{\"londonBlock\":0,\"cancunTime\":0},"
                "\"timestamp\":0,"
                "\"mixhash\":\"" (hash32-to-hex mix-hash) "\","
                "\"parentBeaconBlockRoot\":\""
                (hash32-to-hex parent-beacon-root) "\""
                "}"))
         (header (genesis-header-from-genesis-json-string json)))
    (is (string= (hash32-to-hex mix-hash)
                 (hash32-to-hex (block-header-mix-hash header))))
    (is (string= (hash32-to-hex parent-beacon-root)
                 (hash32-to-hex
                  (block-header-parent-beacon-root header))))))

(deftest genesis-header-ignores-parent-beacon-root-before-cancun
  (let* ((parent-beacon-root
           (hash32-from-hex
            "0x0400000000000000000000000000000000000000000000000000000000000000"))
         (json (concatenate
                'string
                "{\"config\":{\"londonBlock\":0},"
                "\"timestamp\":0,"
                "\"parentBeaconBlockRoot\":\""
                (hash32-to-hex parent-beacon-root) "\""
                "}"))
         (header (genesis-header-from-genesis-json-string json)))
    (is (null (block-header-parent-beacon-root header)))))

(deftest genesis-header-defaults-difficulty-to-zero-at-merge-genesis
  (let* ((json (concatenate
                'string
                "{\"config\":{\"terminalTotalDifficulty\":0},"
                "\"timestamp\":0"
                "}"))
         (header (genesis-header-from-genesis-json-string json)))
    (is (= 0 (block-header-difficulty header)))))

(deftest genesis-block-from-json-carries-empty-fork-bodies
  (let* ((state-root (hash32-from-hex
                      "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (json (concatenate
                'string
                "{\"config\":{"
                "\"londonBlock\":0,"
                "\"shanghaiTime\":0,"
                "\"cancunTime\":0,"
                "\"pragueTime\":0,"
                "\"amsterdamTime\":0"
                "},"
                "\"timestamp\":0"
                "}"))
         (block (genesis-block-from-genesis-json-string
                 json :state-root state-root))
         (header (block-header block)))
    (is (string= (hash32-to-hex state-root)
                 (hash32-to-hex (block-header-state-root header))))
    (is (null (block-transactions block)))
    (is (null (block-ommers block)))
    (is (block-withdrawals-present-p block))
    (is (null (block-withdrawals block)))
    (is (block-requests-present-p block))
    (is (null (block-requests block)))
    (is (block-block-access-list-present-p block))
    (is (null (block-block-access-list block)))
    (is (string= (hash32-to-hex (withdrawal-list-root '()))
                 (hash32-to-hex (block-header-withdrawals-root header))))
    (is (string= (hash32-to-hex (execution-requests-hash '()))
                 (hash32-to-hex (block-header-requests-hash header))))
    (is (string= (hash32-to-hex (block-access-list-hash '()))
                 (hash32-to-hex
                  (block-header-block-access-list-hash header))))))

(deftest transaction-type-validation-uses-chain-config
  (let* ((config (make-chain-config :berlin-block 5
                                    :london-block 10
                                    :cancun-time 20
                                    :prague-time 30))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (legacy (make-legacy-transaction :to recipient))
         (access-list (make-access-list-transaction :to recipient))
         (dynamic (make-dynamic-fee-transaction :to recipient))
         (blob (make-blob-transaction
                :to recipient
                :blob-versioned-hashes (list blob-hash)))
         (set-code (make-set-code-transaction
                    :to recipient
                    :authorization-list
                    (list (make-set-code-authorization
                           :address recipient)))))
    (is (validate-transaction-type-for-config legacy config 0 0))
    (signals block-validation-error
      (validate-transaction-type-for-config access-list config 4 0))
    (is (validate-transaction-type-for-config access-list config 5 0))
    (signals block-validation-error
      (validate-transaction-type-for-config dynamic config 9 0))
    (is (validate-transaction-type-for-config dynamic config 10 0))
    (signals block-validation-error
      (validate-transaction-type-for-config blob config 10 19))
    (is (validate-transaction-type-for-config blob config 10 20))
    (signals block-validation-error
      (validate-transaction-type-for-config set-code config 10 29))
    (is (validate-transaction-type-for-config set-code config 10 30))))

(deftest block-header-basic-parent-validation
  (let* ((parent (make-block-header :number 7
                                    :gas-limit 1024000
                                    :gas-used 512000
                                    :timestamp 100
                                    :base-fee-per-gas 1000))
         (parent-hash (block-header-hash parent)))
    (flet ((child (&key (parent-hash parent-hash)
                        (number 8)
                        (gas-limit 1024000)
                        (gas-used 1000)
                        (timestamp 101)
                        (extra-data #())
                        (base-fee-per-gas 1000)
                        withdrawals-root
                        blob-gas-used
                        excess-blob-gas
                        parent-beacon-root
                        requests-hash)
             (make-block-header :parent-hash parent-hash
                                :number number
                                :gas-limit gas-limit
                                :gas-used gas-used
                                :timestamp timestamp
                                :extra-data extra-data
                                :base-fee-per-gas base-fee-per-gas
                                :withdrawals-root withdrawals-root
                                :blob-gas-used blob-gas-used
                                :excess-blob-gas excess-blob-gas
                                :parent-beacon-root parent-beacon-root
                                :requests-hash requests-hash)))
      (is (validate-block-header-basics parent (child)))
      (is (validate-gas-limit-delta 1024000 1024999))
      (is (validate-block-header-basics
           parent
           (child :blob-gas-used +blob-gas-per-blob+
                  :excess-blob-gas 0
                  :parent-beacon-root (zero-hash32))))
      (is (validate-block-header-basics
           parent
           (child :requests-hash (execution-requests-hash '()))
           :requests-enabled-p t))
      (is (validate-block-header-basics
           parent
           (child :withdrawals-root (withdrawal-list-root '()))
           :withdrawals-enabled-p t))
      (is (= 0 (expected-excess-blob-gas parent)))
      (signals block-validation-error
        (validate-block-header-basics parent (child :parent-hash (zero-hash32))))
      (signals block-validation-error
        (validate-block-header-basics parent (child :number 9)))
      (signals block-validation-error
        (validate-block-header-basics parent (child :timestamp 100)))
      (signals block-validation-error
        (validate-block-header-basics parent (child :gas-used 1024001)))
      (signals block-validation-error
        (validate-block-header-basics parent (child :gas-limit 1025000)))
      (signals block-validation-error
        (validate-gas-limit-delta 1024000 4999))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :blob-gas-used
                                             +blob-gas-per-blob+)))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :blob-gas-used 1
                                             :excess-blob-gas 0
                                             :parent-beacon-root
                                             (zero-hash32))))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :parent-beacon-root
                                             (zero-hash32))))
      (signals block-validation-error
        (validate-block-header-basics parent (child)
                                      :requests-enabled-p t))
      (signals block-validation-error
        (validate-block-header-basics parent (child)
                                      :withdrawals-enabled-p t))
      (signals block-validation-error
        (validate-block-header-basics
         parent
         (child :withdrawals-root (withdrawal-list-root '()))
         :withdrawals-enabled-p nil))
      (signals block-validation-error
        (validate-block-header-basics
         parent
         (child :requests-hash (execution-requests-hash '()))
         :requests-enabled-p nil))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :blob-gas-used
                                             +blob-gas-per-blob+
                                             :excess-blob-gas 0)))
      (signals block-validation-error
        (validate-block-header-basics
         parent
         (child :extra-data
                (make-array (1+ +maximum-extra-data-size+)
                            :element-type '(unsigned-byte 8)
                            :initial-element 0))))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :base-fee-per-gas 999))))))

(deftest block-header-validates-field-shapes-before-comparison
  (let* ((parent (make-block-header :number 7
                                    :gas-limit 1024000
                                    :gas-used 512000
                                    :timestamp 100
                                    :base-fee-per-gas 1000))
         (parent-hash (block-header-hash parent)))
    (flet ((child (&key (parent-hash parent-hash)
                        beneficiary
                        state-root
                        logs-bloom
                        (extra-data #())
                        nonce
                        (base-fee-per-gas 1000)
                        blob-gas-used
                        excess-blob-gas
                        parent-beacon-root)
             (make-block-header :parent-hash parent-hash
                                :beneficiary beneficiary
                                :state-root state-root
                                :number 8
                                :gas-limit 1024000
                                :gas-used 1000
                                :timestamp 101
                                :logs-bloom logs-bloom
                                :extra-data extra-data
                                :nonce nonce
                                :base-fee-per-gas base-fee-per-gas
                                :blob-gas-used blob-gas-used
                                :excess-blob-gas excess-blob-gas
                                :parent-beacon-root parent-beacon-root)))
      (signals block-validation-error
        (validate-block-header-basics "not a header" (child)))
      (signals block-validation-error
        (validate-block-header-basics parent "not a header"))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :parent-hash "not a hash")))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :beneficiary "not an address")))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :state-root "not a root")))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :logs-bloom #())))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :extra-data "not bytes")))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :nonce #())))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :base-fee-per-gas "fee")))
      (signals block-validation-error
        (validate-block-header-basics
         parent
         (child :blob-gas-used "blob"
                :excess-blob-gas 0
                :parent-beacon-root (zero-hash32)))))))

(deftest post-merge-header-validates-seal-fields
  (let* ((parent (make-block-header :number 7
                                    :difficulty 1
                                    :gas-limit 1024000
                                    :gas-used 512000
                                    :timestamp 100
                                    :base-fee-per-gas 1000))
         (parent-hash (block-header-hash parent)))
    (flet ((child (&key (difficulty 0)
                        (nonce (make-byte-vector 8))
                        (ommers-hash +empty-ommers-hash+)
                        (parent-hash parent-hash)
                        (number 8)
                        (gas-limit 1024000)
                        (timestamp 101))
             (make-block-header :parent-hash parent-hash
                                :ommers-hash ommers-hash
                                :difficulty difficulty
                                :number number
                                :gas-limit gas-limit
                                :gas-used 1000
                                :timestamp timestamp
                                :nonce nonce
                                :base-fee-per-gas 1000)))
      (is (validate-block-header-basics parent (child)))
      (signals block-validation-error
        (validate-block-header-basics
         parent
         (child :nonce #(#x00 #x00 #x00 #x00 #x00 #x00 #x00 #x01))))
      (signals block-validation-error
        (validate-block-header-basics parent
                                      (child :ommers-hash (zero-hash32))))
      (signals block-validation-error
        (validate-block-header-basics
         parent
         (child :gas-limit #x8000000000000000)))
      (let ((post-merge-parent (child)))
        (signals block-validation-error
          (validate-block-header-basics
           post-merge-parent
           (child :difficulty 1
                  :number 9
                  :timestamp 102
                  :parent-hash (block-header-hash post-merge-parent))))))))

(deftest block-header-validation-uses-chain-config-forks
  (let* ((config (make-chain-config :london-block 0
                                    :shanghai-time 150
                                    :cancun-time 200
                                    :prague-time 300
                                    :amsterdam-time 400))
         (parent (make-block-header :number 7
                                    :gas-limit 1024000
                                    :gas-used 512000
                                    :timestamp 198
                                    :base-fee-per-gas 1000))
         (parent-hash (block-header-hash parent)))
    (flet ((child (&key (timestamp 200)
                        withdrawals-root
                        blob-gas-used
                        excess-blob-gas
                        parent-beacon-root
                        requests-hash
                        block-access-list-hash
                        slot-number)
             (make-block-header
              :parent-hash parent-hash
              :number 8
              :gas-limit 1024000
              :gas-used 1000
              :timestamp timestamp
              :base-fee-per-gas 1000
              :withdrawals-root withdrawals-root
              :blob-gas-used blob-gas-used
              :excess-blob-gas excess-blob-gas
              :parent-beacon-root parent-beacon-root
              :requests-hash requests-hash
              :block-access-list-hash block-access-list-hash
              :slot-number slot-number)))
      (is (validate-block-header-against-config
           parent
           (child :blob-gas-used 0
                  :excess-blob-gas 0
                  :parent-beacon-root (zero-hash32)
                  :withdrawals-root (withdrawal-list-root '()))
           config))
      (is (validate-block-header-against-config
           parent
           (child :timestamp 300
                  :blob-gas-used 0
                  :excess-blob-gas 0
                  :parent-beacon-root (zero-hash32)
                  :withdrawals-root (withdrawal-list-root '())
                  :requests-hash (execution-requests-hash '()))
           config))
      (is (validate-block-header-against-config
           parent
           (child :timestamp 400
                  :blob-gas-used 0
                  :excess-blob-gas 0
                  :parent-beacon-root (zero-hash32)
                  :withdrawals-root (withdrawal-list-root '())
                  :requests-hash (execution-requests-hash '())
                  :block-access-list-hash +empty-ommers-hash+
                  :slot-number 0)
           config))
      (is (validate-block-header-against-config
           parent
           (child :timestamp 300
                  :blob-gas-used (* +osaka-max-blobs-per-block+
                                    +blob-gas-per-blob+)
                  :excess-blob-gas 0
                  :parent-beacon-root (zero-hash32)
                  :withdrawals-root (withdrawal-list-root '())
                  :requests-hash (execution-requests-hash '()))
           config))
      (signals block-validation-error
        (validate-block-header-against-config
         parent
         (child :timestamp 149
                :withdrawals-root (withdrawal-list-root '()))
         config))
      (signals block-validation-error
        (validate-block-header-against-config
         parent
         (child :timestamp 150)
         config))
      (signals block-validation-error
        (validate-block-header-against-config parent (child) config))
      (signals block-validation-error
        (validate-block-header-against-config
         parent
         (child :timestamp 199
                :blob-gas-used 0
                :excess-blob-gas 0
                :parent-beacon-root (zero-hash32)
                :withdrawals-root (withdrawal-list-root '()))
         config))
      (signals block-validation-error
        (validate-block-header-against-config
         parent
         (child :timestamp 300
                :blob-gas-used 0
                :excess-blob-gas 0
                :parent-beacon-root (zero-hash32)
                :withdrawals-root (withdrawal-list-root '()))
         config))
      (signals block-validation-error
        (validate-block-header-against-config
         parent
         (child :timestamp 300
                :blob-gas-used 0
                :excess-blob-gas 0
                :parent-beacon-root (zero-hash32)
                :withdrawals-root (withdrawal-list-root '())
                :requests-hash (execution-requests-hash '())
                :block-access-list-hash +empty-ommers-hash+
                :slot-number 0)
         config))
      (signals block-validation-error
        (validate-block-header-against-config
         parent
         (child :timestamp 400
                :blob-gas-used 0
                :excess-blob-gas 0
                :parent-beacon-root (zero-hash32)
                :withdrawals-root (withdrawal-list-root '())
                :requests-hash (execution-requests-hash '()))
         config)))))

(deftest amsterdam-header-slot-number-must-exceed-parent
  (let* ((config (make-chain-config :london-block 0
                                    :shanghai-time 150
                                    :cancun-time 200
                                    :prague-time 300
                                    :amsterdam-time 400))
         (parent (make-block-header :number 8
                                    :gas-limit 1024000
                                    :gas-used 512000
                                    :timestamp 400
                                    :base-fee-per-gas 1000
                                    :withdrawals-root (withdrawal-list-root '())
                                    :blob-gas-used 0
                                    :excess-blob-gas 0
                                    :parent-beacon-root (zero-hash32)
                                    :requests-hash (execution-requests-hash '())
                                    :block-access-list-hash +empty-ommers-hash+
                                    :slot-number 10))
         (parent-hash (block-header-hash parent)))
    (flet ((child (slot-number)
             (make-block-header
              :parent-hash parent-hash
              :number 9
              :gas-limit 1024000
              :gas-used 1000
              :timestamp 410
              :base-fee-per-gas 1000
              :withdrawals-root (withdrawal-list-root '())
              :blob-gas-used 0
              :excess-blob-gas 0
              :parent-beacon-root (zero-hash32)
              :requests-hash (execution-requests-hash '())
              :block-access-list-hash +empty-ommers-hash+
              :slot-number slot-number)))
      (is (validate-block-header-against-config parent (child 11) config))
      (signals block-validation-error
        (validate-block-header-against-config parent (child 10) config))
      (signals block-validation-error
        (validate-block-header-against-config parent (child 9) config)))))

(deftest london-fork-block-validates-gas-limit-against-elastic-parent
  (let* ((parent (make-block-header :number 7
                                    :gas-limit 1024000
                                    :gas-used 512000
                                    :timestamp 100))
         (parent-hash (block-header-hash parent))
         (valid-london
           (make-block-header :parent-hash parent-hash
                              :number 8
                              :gas-limit 2048999
                              :gas-used 1000
                              :timestamp 101
                              :base-fee-per-gas +initial-base-fee+))
         (too-far
           (make-block-header :parent-hash parent-hash
                              :number 8
                              :gas-limit 2050000
                              :gas-used 1000
                              :timestamp 101
                              :base-fee-per-gas +initial-base-fee+)))
    (is (= 2048000 (adjusted-parent-gas-limit-for-1559 parent nil)))
    (is (validate-block-header-basics parent valid-london
                                      :london-parent-p nil))
    (signals block-validation-error
      (validate-block-header-basics parent too-far
                                    :london-parent-p nil))))

(deftest excess-blob-gas-calculation-and-validation
  (let* ((parent (make-block-header :blob-gas-used (* 4 +blob-gas-per-blob+)
                                    :excess-blob-gas (* 2 +blob-gas-per-blob+)))
         (expected (* 3 +blob-gas-per-blob+))
         (header (make-block-header :blob-gas-used +blob-gas-per-blob+
                                    :excess-blob-gas expected))
         (empty-parent (make-block-header)))
    (is (= expected (expected-excess-blob-gas parent)))
    (is (validate-block-excess-blob-gas parent header))
    (is (= 0 (expected-excess-blob-gas empty-parent)))
    (setf (block-header-excess-blob-gas header) (1+ expected))
    (signals block-validation-error
      (validate-block-excess-blob-gas parent header))))

(deftest eip7918-excess-blob-gas-calculation-and-validation
  (let* ((osaka-target-gas (* +osaka-target-blobs-per-block+
                              +blob-gas-per-blob+))
         (osaka-max-gas (* +osaka-max-blobs-per-block+
                           +blob-gas-per-blob+))
         (below-reserve-parent
           (make-block-header :base-fee-per-gas 1000000000
                              :gas-limit 30000000
                              :gas-used 15000000
                              :timestamp 9
                              :blob-gas-used osaka-target-gas
                              :excess-blob-gas 0))
         (below-reserve-expected (floor osaka-target-gas 3))
         (below-reserve-header
           (make-block-header :blob-gas-used 0
                              :excess-blob-gas below-reserve-expected))
         (above-reserve-parent
           (make-block-header :base-fee-per-gas 1
                              :blob-gas-used osaka-target-gas
                              :excess-blob-gas 0))
         (above-reserve-header
           (make-block-header :blob-gas-used 0
                              :excess-blob-gas 0))
         (config (make-chain-config :london-block 0
                                    :cancun-time 0
                                    :osaka-time 10))
         (parent-hash (block-header-hash below-reserve-parent))
         (config-child
           (make-block-header :parent-hash parent-hash
                              :number 1
                              :timestamp 10
                              :gas-limit 30000000
                              :base-fee-per-gas 1000000000
                              :blob-gas-used 0
                              :excess-blob-gas below-reserve-expected
                              :parent-beacon-root (zero-hash32))))
    (is (= below-reserve-expected
           (expected-excess-blob-gas
            below-reserve-parent
            :target-blob-gas osaka-target-gas
            :max-blob-gas osaka-max-gas
            :eip7918-p t
            :update-fraction +osaka-blob-base-fee-update-fraction+)))
    (is (= 0
           (expected-excess-blob-gas
            above-reserve-parent
            :target-blob-gas osaka-target-gas
            :max-blob-gas osaka-max-gas
            :eip7918-p t
            :update-fraction +osaka-blob-base-fee-update-fraction+)))
    (is (validate-block-excess-blob-gas
         below-reserve-parent below-reserve-header
         :target-blob-gas osaka-target-gas
         :max-blob-gas osaka-max-gas
         :eip7918-p t
         :update-fraction +osaka-blob-base-fee-update-fraction+))
    (is (validate-block-excess-blob-gas
         above-reserve-parent above-reserve-header
         :target-blob-gas osaka-target-gas
         :max-blob-gas osaka-max-gas
         :eip7918-p t
         :update-fraction +osaka-blob-base-fee-update-fraction+))
    (is (validate-block-header-against-config
         below-reserve-parent config-child config))
    (setf (block-header-excess-blob-gas config-child) 0)
    (signals block-validation-error
      (validate-block-header-against-config
       below-reserve-parent config-child config))))

(deftest blob-base-fee-fake-exponential-vectors
  (dolist (case '((1 0 1 1)
                  (38493 0 1000 38493)
                  (0 1234 2345 0)
                  (1 2 1 6)
                  (1 4 2 6)
                  (1 3 1 16)
                  (1 6 2 18)
                  (1 4 1 49)
                  (1 8 2 50)
                  (10 8 2 542)
                  (11 8 2 596)
                  (1 5 1 136)
                  (1 5 2 11)
                  (2 5 2 23)
                  (1 50000000 2225652 5709098764)))
    (destructuring-bind (factor numerator denominator expected) case
      (is (= expected
             (fake-exponential factor numerator denominator)))))
  (is (= 1 (blob-base-fee 0)))
  (is (= 1 (blob-base-fee 2314057)))
  (is (= 2 (blob-base-fee 2314058)))
  (is (= 23 (blob-base-fee (* 10 1024 1024))))
  (is (= 23 (block-header-blob-base-fee
             (make-block-header :excess-blob-gas (* 10 1024 1024))))))

(deftest withdrawal-rlp-and-root
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (withdrawal (make-withdrawal :index 1
                                      :validator-index 2
                                      :address address
                                      :amount 3))
         (root (withdrawal-list-root (list withdrawal))))
    (is (string= "0xd8010294000000000000000000000000000000000000000103"
                 (bytes-to-hex (withdrawal-rlp withdrawal))))
    (is (hash32-p root))
    (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
                 (hash32-to-hex (withdrawal-list-root '()))))))

(deftest block-access-list-rlp-encodes-account-shells
  (let* ((account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")))
         (access-list (list account)))
    (is (string=
         "0xdbda940000000000000000000000000000000000000001c0c0c0c0c0"
         (bytes-to-hex (block-access-list-rlp access-list))))
    (is (string= (hash32-to-hex +empty-ommers-hash+)
                 (hash32-to-hex (block-access-list-hash '()))))
    (is (not (string= (hash32-to-hex +empty-ommers-hash+)
                      (hash32-to-hex
                       (block-access-list-hash access-list)))))))

(deftest block-access-list-rlp-encodes-storage-reads
  (let* ((slot-1 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (slot-2 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")
                   :storage-reads (list slot-1 slot-2)))
         (access-list (list account)))
    (is (string=
         "0xdddc940000000000000000000000000000000000000001c0c20102c0c0c0"
         (bytes-to-hex (block-access-list-rlp access-list))))
    (is (validate-block-access-list-fields access-list))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :storage-reads (list slot-2 slot-1)))))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :storage-reads (list slot-1 slot-1)))))))

(deftest block-access-list-rlp-encodes-storage-writes
  (let* ((slot-1 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (slot-2 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (write-1 (make-block-access-storage-write :tx-index 1 :value-after 2))
         (write-2 (make-block-access-storage-write :tx-index 2 :value-after 3))
         (slot-writes (make-block-access-slot-writes
                       :slot slot-1
                       :accesses (list write-1 write-2)))
         (account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")
                   :storage-writes (list slot-writes)))
         (access-list (list account)))
    (is (string=
         "0xe4e3940000000000000000000000000000000000000001c9c801c6c20102c20203c0c0c0c0"
         (bytes-to-hex (block-access-list-rlp access-list))))
    (is (validate-block-access-list-fields access-list))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :storage-writes
              (list (make-block-access-slot-writes
                     :slot slot-2
                     :accesses (list write-1))
                    (make-block-access-slot-writes
                     :slot slot-1
                     :accesses (list write-1)))))))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :storage-writes
              (list (make-block-access-slot-writes
                     :slot slot-1
                     :accesses (list write-2 write-1)))))))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :storage-writes
              (list (make-block-access-slot-writes
                     :slot slot-1
                     :accesses (list write-1)))
              :storage-reads (list slot-1)))))))

(deftest block-access-list-rlp-encodes-balance-changes
  (let* ((change-1 (make-block-access-balance-change
                    :tx-index 1
                    :balance 100))
         (change-2 (make-block-access-balance-change
                    :tx-index 2
                    :balance 500))
         (account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")
                   :balance-changes (list change-1 change-2)))
         (access-list (list account)))
    (is (string=
         "0xe3e2940000000000000000000000000000000000000001c0c0c8c20164c4028201f4c0c0"
         (bytes-to-hex (block-access-list-rlp access-list))))
    (is (validate-block-access-list-fields access-list))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :balance-changes (list change-2 change-1)))))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :balance-changes (list change-1 change-1)))))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :balance-changes
              (list (make-block-access-balance-change
                     :tx-index (expt 2 32)
                     :balance 100))))))))

(deftest block-access-list-rlp-encodes-nonce-changes
  (let* ((change-1 (make-block-access-nonce-change
                    :tx-index 1
                    :nonce 2))
         (change-2 (make-block-access-nonce-change
                    :tx-index 2
                    :nonce 6))
         (account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")
                   :nonce-changes (list change-1 change-2)))
         (access-list (list account)))
    (is (string=
         "0xe1e0940000000000000000000000000000000000000001c0c0c0c6c20102c20206c0"
         (bytes-to-hex (block-access-list-rlp access-list))))
    (is (validate-block-access-list-fields access-list))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :nonce-changes (list change-2 change-1)))))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :nonce-changes (list change-1 change-1)))))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :nonce-changes
              (list (make-block-access-nonce-change
                     :tx-index 1
                     :nonce (expt 2 64)))))))))

(deftest block-access-list-rlp-encodes-code-changes
  (let* ((change-1 (make-block-access-code-change
                    :tx-index 1
                    :code #(222 173 190 239)))
         (change-2 (make-block-access-code-change
                    :tx-index 2
                    :code #(96 0)))
         (account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")
                   :code-changes (list change-1 change-2)))
         (access-list (list account)))
    (is (string=
         "0xe7e6940000000000000000000000000000000000000001c0c0c0c0ccc60184deadbeefc402826000"
         (bytes-to-hex (block-access-list-rlp access-list))))
    (is (validate-block-access-list-fields access-list))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :code-changes (list change-2 change-1)))))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :code-changes (list change-1 change-1)))))
    (signals block-validation-error
      (validate-block-access-list-fields
       (list (make-block-access-account
              :address (address-from-hex
                        "0x0000000000000000000000000000000000000001")
              :code-changes
              (list (make-block-access-code-change
                     :tx-index 1
                     :code "not bytes"))))))
    (signals block-validation-error
      (validate-block-access-list-fields
       access-list
       :max-code-size 3))))

(deftest block-access-list-rlp-decodes-round-trip
  (let* ((slot-1 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (slot-2 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (slot-writes
           (make-block-access-slot-writes
            :slot slot-1
            :accesses
            (list (make-block-access-storage-write
                   :tx-index 1
                   :value-after 2)
                  (make-block-access-storage-write
                   :tx-index 3
                   :value-after 4))))
         (account
           (make-block-access-account
            :address (address-from-hex
                      "0x0000000000000000000000000000000000000001")
            :storage-writes (list slot-writes)
            :storage-reads (list slot-2)
            :balance-changes
            (list (make-block-access-balance-change
                   :tx-index 1
                   :balance 100))
            :nonce-changes
            (list (make-block-access-nonce-change
                   :tx-index 2
                   :nonce 7))
            :code-changes
            (list (make-block-access-code-change
                   :tx-index 4
                   :code #(96 0 96 1)))))
         (access-list (list account))
         (encoded (block-access-list-rlp access-list))
         (decoded (block-access-list-from-rlp
                   encoded
                   :max-code-size 4
                   :max-items 3)))
    (is (= 3 (block-access-list-item-count decoded)))
    (is (bytes= encoded (block-access-list-rlp decoded)))
    (is (string= (hash32-to-hex (keccak-256-hash encoded))
                 (hash32-to-hex (block-access-list-rlp-hash encoded))))
    (is (string= (hash32-to-hex (block-access-list-hash access-list))
                 (hash32-to-hex (block-access-list-hash decoded))))
    (signals block-validation-error
      (block-access-list-from-rlp encoded :max-code-size 3))
    (signals block-validation-error
      (block-access-list-from-rlp encoded :max-items 2))
    (signals block-validation-error
      (block-access-list-rlp-hash encoded :max-code-size 3))
    (signals block-validation-error
      (block-access-list-rlp-hash "not bytes"))))

(deftest block-access-list-rlp-decode-rejects-malformed-shape
  (signals block-validation-error
    (block-access-list-from-rlp (make-byte-vector 0)))
  (signals block-validation-error
    (block-access-list-from-rlp (rlp-encode (ensure-byte-vector '(1 2 3)))))
  (signals block-validation-error
    (block-access-list-from-rlp
     (rlp-encode
      (list (make-rlp-list
             (make-byte-vector 20))))))
  (signals block-validation-error
    (block-access-list-from-rlp
     (rlp-encode
      (list (make-rlp-list
             (make-byte-vector 19)
             '()
             '()
             '()
             '()
             '()))))))

(deftest block-access-list-validates-account-order
  (let ((first (make-block-access-account
                :address (address-from-hex
                          "0x0000000000000000000000000000000000000001")))
        (second (make-block-access-account
                 :address (address-from-hex
                           "0x0000000000000000000000000000000000000002"))))
    (is (validate-block-access-list-fields (list first second)))
    (signals block-validation-error
      (validate-block-access-list-fields (list second first)))
    (signals block-validation-error
      (validate-block-access-list-fields (list first first)))))

(deftest block-derives-body-roots
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (topic (hash32-from-hex
                 "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (transaction (make-legacy-transaction :nonce 1
                                               :gas-price 2
                                               :gas-limit 3
                                               :to address
                                               :value 4
                                               :data #(5)
                                               :v 27
                                               :r 6
                                               :s 7))
         (log (make-log-entry :address address :topics (list topic) :data #(9)))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000
                                :logs (list log)))
         (withdrawal (make-withdrawal :index 1
                                      :validator-index 2
                                      :address address
                                      :amount 3))
         (block (make-block :transactions (list transaction)
                            :receipts (list receipt)
                            :withdrawals (list withdrawal)
                            :requests (list #(#x00) #(#x01 #xaa))
                            :block-access-list '()))
         (header (block-header block)))
    (is (hash32-p (block-hash block)))
    (is (= 1 (length (block-transactions block))))
    (is (= 1 (length (block-withdrawals block))))
    (is (= 2 (length (block-requests block))))
    (is (block-block-access-list-present-p block))
    (is (string= (hash32-to-hex (transaction-list-root (list transaction)))
                 (hash32-to-hex (block-header-transactions-root header))))
    (is (string= (hash32-to-hex (receipt-list-root (list receipt)))
                 (hash32-to-hex (block-header-receipts-root header))))
    (is (string= (hash32-to-hex (withdrawal-list-root (list withdrawal)))
                 (hash32-to-hex (block-header-withdrawals-root header))))
    (is (string= (hash32-to-hex
                  (execution-requests-hash (list #(#x00) #(#x01 #xaa))))
                 (hash32-to-hex (block-header-requests-hash header))))
    (is (string= (hash32-to-hex (block-access-list-hash '()))
                 (hash32-to-hex
                  (block-header-block-access-list-hash header))))
    (is (bytes= (bloom-bytes (receipt-bloom (list log)))
                (block-header-logs-bloom header)))))

(deftest block-body-root-validation
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (transaction (make-legacy-transaction :nonce 1
                                               :gas-price 2
                                               :gas-limit 3
                                               :to address
                                               :value 4))
         (withdrawal (make-withdrawal :index 1
                                      :validator-index 2
                                      :address address
                                      :amount 3))
         (block (make-block :transactions (list transaction)
                            :withdrawals (list withdrawal))))
    (is (validate-block-body-roots block))
    (setf (block-header-transactions-root (block-header block)) (zero-hash32))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-transaction-list-before-derived-fields
  (let ((block (make-block)))
    (setf (block-transactions block) (list "not a transaction"))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-ommer-list-before-root-derivation
  (let ((block (make-block)))
    (setf (block-ommers block) (list "not a header"))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-commitment-fields-before-comparison
  (let* ((block (make-block))
         (header (block-header block)))
    (setf (block-header-ommers-hash header) nil)
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-header-ommers-hash header) +empty-ommers-hash+
          (block-header-transactions-root header) nil)
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-header-transactions-root header) +empty-trie-hash+
          (block-header-withdrawals-root header) "not a hash")
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-header-withdrawals-root header) nil
          (block-header-requests-hash header) "not a hash")
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validation-uses-chain-config-transaction-types
  (let* ((config (make-chain-config :berlin-block 5
                                    :london-block 10
                                    :prague-time 30))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (access-list (make-access-list-transaction :to recipient))
         (dynamic (make-dynamic-fee-transaction :to recipient))
         (set-code (make-set-code-transaction
                    :to recipient
                    :authorization-list
                    (list (make-set-code-authorization
                           :address recipient))))
         (berlin-block
           (make-block :header (make-block-header :number 5 :timestamp 0)
                       :transactions (list access-list)))
         (pre-london-block
           (make-block :header (make-block-header :number 9 :timestamp 0)
                       :transactions (list dynamic)))
         (london-block
           (make-block :header (make-block-header :number 10 :timestamp 0)
                       :transactions (list dynamic)))
         (pre-prague-block
           (make-block :header (make-block-header :number 10 :timestamp 29)
                       :transactions (list set-code)))
         (prague-block
           (make-block :header (make-block-header :number 10 :timestamp 30)
                       :transactions (list set-code))))
    (is (validate-block-body-against-config berlin-block config))
    (signals block-validation-error
      (validate-block-body-against-config pre-london-block config))
    (is (validate-block-body-against-config london-block config))
    (signals block-validation-error
      (validate-block-body-against-config pre-prague-block config))
    (is (validate-block-body-against-config prague-block config))))

(deftest block-body-validates-1559-fee-caps
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (valid (make-dynamic-fee-transaction
                 :to recipient
                 :max-priority-fee-per-gas 1
                 :max-fee-per-gas 5))
         (fee-too-low (make-dynamic-fee-transaction
                       :to recipient
                       :max-priority-fee-per-gas 1
                       :max-fee-per-gas 4))
         (tip-too-high (make-set-code-transaction
                        :to recipient
                        :max-priority-fee-per-gas 6
                        :max-fee-per-gas 5
                        :authorization-list
                        (list (make-set-code-authorization
                               :address recipient)))))
    (is (validate-block-body-roots
         (make-block :header (make-block-header :base-fee-per-gas 5)
                     :transactions (list valid))))
    (signals block-validation-error
      (validate-block-body-roots
       (make-block :header (make-block-header :base-fee-per-gas 5)
                   :transactions (list fee-too-low))))
    (signals block-validation-error
      (validate-block-body-roots
       (make-block :header (make-block-header :base-fee-per-gas 5)
                   :transactions (list tip-too-high))))))

(deftest block-body-validates-access-list-fields-before-root-derivation
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (block (make-block))
         (bad-address-tx
           (make-access-list-transaction
            :to recipient
            :access-list
            (list (make-access-list-entry :address nil))))
         (bad-slot-tx
           (make-access-list-transaction
            :to recipient
            :access-list
            (list (make-access-list-entry
                   :address recipient
                   :storage-keys (list nil))))))
    (setf (block-transactions block) (list bad-address-tx))
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-transactions block) (list bad-slot-tx))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-transaction-data-before-root-derivation
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (block (make-block))
         (bad-data-tx
           (make-legacy-transaction :to recipient
                                    :data "not bytes")))
    (setf (block-transactions block) (list bad-data-tx))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-transaction-recipient-before-root-derivation
  (let* ((block (make-block))
         (bad-recipient-tx
           (make-legacy-transaction :to #(1 2 3))))
    (setf (block-transactions block) (list bad-recipient-tx))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-transaction-scalars-before-root-derivation
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (block (make-block))
         (bad-nonce-tx
           (make-legacy-transaction :nonce (ash 1 64)
                                    :to recipient))
         (bad-gas-limit-tx
           (make-legacy-transaction :gas-limit (ash 1 64)
                                    :to recipient))
         (bad-value-tx
           (make-legacy-transaction :value (1+ +uint256-max+)
                                    :to recipient))
         (bad-fee-tx
           (make-dynamic-fee-transaction
            :to recipient
            :max-priority-fee-per-gas 2
            :max-fee-per-gas 1))
         (bad-blob-fee-tx
           (make-blob-transaction
            :to recipient
            :blob-versioned-hashes
            (list (hash32-from-hex
                   "0x0100000000000000000000000000000000000000000000000000000000000000"))
            :max-fee-per-blob-gas (1+ +uint256-max+))))
    (dolist (transaction (list bad-nonce-tx
                               bad-gas-limit-tx
                               bad-value-tx
                               bad-fee-tx
                               bad-blob-fee-tx))
      (setf (block-transactions block) (list transaction))
      (signals block-validation-error
        (validate-block-body-roots block)))))

(deftest block-body-validates-transaction-signature-fields-before-root-derivation
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (block (make-block))
         (bad-legacy-v-tx
           (make-legacy-transaction :to recipient
                                    :v (1+ +uint256-max+)))
         (bad-typed-chain-tx
           (make-dynamic-fee-transaction :to recipient
                                         :chain-id (1+ +uint256-max+)))
         (bad-typed-y-parity-tx
           (make-dynamic-fee-transaction :to recipient
                                         :y-parity (1+ +uint256-max+)))
         (bad-typed-r-tx
           (make-dynamic-fee-transaction :to recipient
                                         :r (1+ +uint256-max+)))
         (bad-typed-s-tx
           (make-dynamic-fee-transaction :to recipient
                                         :s (1+ +uint256-max+))))
    (dolist (transaction (list bad-legacy-v-tx
                               bad-typed-chain-tx
                               bad-typed-y-parity-tx
                               bad-typed-r-tx
                               bad-typed-s-tx))
      (setf (block-transactions block) (list transaction))
      (signals block-validation-error
        (validate-block-body-roots block)))))

(deftest block-body-validates-set-code-fields-before-root-derivation
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (block (make-block))
         (missing-to-tx
           (make-set-code-transaction
            :to nil
            :authorization-list
            (list (make-set-code-authorization :address recipient))))
         (missing-auth-tx
           (make-set-code-transaction :to recipient))
         (bad-auth-address-tx
           (make-set-code-transaction
            :to recipient
            :authorization-list
            (list (make-set-code-authorization :address nil))))
         (bad-auth-chain-tx
           (make-set-code-transaction
            :to recipient
            :authorization-list
            (list (make-set-code-authorization
                   :chain-id (1+ +uint256-max+)
                   :address recipient)))))
    (setf (block-transactions block) (list missing-to-tx))
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-transactions block) (list missing-auth-tx))
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-transactions block) (list bad-auth-address-tx))
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-transactions block) (list bad-auth-chain-tx))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-validation-combines-config-header-and-body-checks
  (let* ((config (make-chain-config :london-block 0
                                    :shanghai-time 150
                                    :cancun-time 200
                                    :prague-time 300))
         (parent (make-block-header :number 7
                                    :gas-limit 1024000
                                    :gas-used 512000
                                    :timestamp 198
                                    :base-fee-per-gas 1000))
         (parent-hash (block-header-hash parent))
         (valid-header
           (make-block-header :parent-hash parent-hash
                              :number 8
                              :gas-limit 1024000
                              :gas-used 0
                              :timestamp 300
                              :base-fee-per-gas 1000
                              :blob-gas-used 0
                              :excess-blob-gas 0
                              :parent-beacon-root (zero-hash32)))
         (valid-block
           (make-block :header valid-header
                       :withdrawals '()
                       :requests '()))
         (missing-withdrawals-parent
           (make-block-header :number 7
                              :gas-limit 1024000
                              :gas-used 512000
                              :timestamp 149
                              :base-fee-per-gas 1000))
         (missing-withdrawals-root
           (make-block :header
                       (make-block-header :parent-hash
                                          (block-header-hash
                                           missing-withdrawals-parent)
                                          :number 8
                                          :gas-limit 1024000
                                          :gas-used 0
                                          :timestamp 150
                                          :base-fee-per-gas 1000)))
         (pre-london-parent
           (make-block-header :number 8
                              :gas-limit 1024000
                              :gas-used 512000
                              :timestamp 10))
         (pre-london-header
           (make-block-header :parent-hash
                              (block-header-hash pre-london-parent)
                              :number 9
                              :gas-limit 1024000
                              :gas-used 0
                              :timestamp 11))
         (pre-london-block
           (make-block :header pre-london-header
                       :transactions
                       (list (make-dynamic-fee-transaction
                              :to (address-from-hex
                                   "0x0000000000000000000000000000000000000001"))))))
    (is (validate-block-against-config parent valid-block config))
    (signals block-validation-error
      (validate-block-against-config missing-withdrawals-parent
                                     missing-withdrawals-root config))
    (signals block-validation-error
      (validate-block-against-config pre-london-parent pre-london-block
                                     (make-chain-config :london-block 10)))))

(deftest block-body-validates-execution-requests-hash
  (let* ((block (make-block :requests (list #(#x00) #(#x01 #xaa))))
         (header (block-header block)))
    (is (validate-block-body-roots block))
    (is (string= (hash32-to-hex
                  (execution-requests-hash (block-requests block)))
                 (hash32-to-hex (block-header-requests-hash header))))
    (setf (block-header-requests-hash header) (zero-hash32))
    (signals block-validation-error
      (validate-block-body-roots block)))
  (let ((header-without-requests
          (make-block-header :requests-hash
                             (execution-requests-hash (list #(#x01 #xaa))))))
    (signals block-validation-error
      (validate-block-body-roots
       (make-block :header header-without-requests))))
  (let ((pre-prague-block (make-block :requests (list #(#x01 #xaa)))))
    (setf (block-header-requests-hash (block-header pre-prague-block)) nil)
    (signals block-validation-error
      (validate-block-body-roots pre-prague-block))))

(deftest block-body-validates-request-list-before-hash-derivation
  (let ((block (make-block)))
    (setf (block-requests block) "not a request list"
          (block-requests-present-p block) t)
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-block-access-list-hash
  (let* ((block (make-block :block-access-list '()))
         (header (block-header block)))
    (is (validate-block-body-roots block))
    (is (string= (hash32-to-hex (block-access-list-hash '()))
                 (hash32-to-hex
                  (block-header-block-access-list-hash header))))
    (setf (block-header-block-access-list-hash header) (zero-hash32))
    (signals block-validation-error
      (validate-block-body-roots block)))
  (let* ((account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")))
         (block (make-block :block-access-list (list account))))
    (is (validate-block-body-roots block))
    (is (string= (hash32-to-hex (block-access-list-hash (list account)))
                 (hash32-to-hex
                  (block-header-block-access-list-hash
                   (block-header block))))))
  (let ((header-without-body
          (make-block-header :block-access-list-hash
                             (block-access-list-hash '()))))
    (signals block-validation-error
      (validate-block-body-roots
       (make-block :header header-without-body))))
  (let ((pre-amsterdam-block (make-block :block-access-list '())))
    (setf (block-header-block-access-list-hash
           (block-header pre-amsterdam-block)) nil)
    (signals block-validation-error
      (validate-block-body-roots pre-amsterdam-block))))

(deftest block-body-validates-block-access-list-code-change-size
  (let* ((address (address-from-hex
                   "0x0000000000000000000000000000000000000001"))
         (config (make-chain-config :london-block 0
                                    :amsterdam-time 0))
         (limit-code (make-byte-vector
                      +block-access-list-amsterdam-max-code-size+))
         (oversized-code (make-byte-vector
                          (1+ +block-access-list-amsterdam-max-code-size+)))
         (limit-account
           (make-block-access-account
            :address address
            :code-changes
            (list (make-block-access-code-change :tx-index 1
                                                 :code limit-code))))
         (oversized-account
           (make-block-access-account
            :address address
            :code-changes
            (list (make-block-access-code-change :tx-index 1
                                                 :code oversized-code))))
         (limit-block
           (make-block :header (make-block-header :timestamp 0)
                       :block-access-list (list limit-account)))
         (oversized-block
           (make-block :header (make-block-header :timestamp 0)
                       :block-access-list (list oversized-account))))
    (is (validate-block-body-against-config limit-block config))
    (signals block-validation-error
      (validate-block-body-against-config oversized-block config))
    (signals block-validation-error
      (validate-block-body-roots
       limit-block
       :block-access-list-max-code-size
       +block-access-list-max-code-size+))))

(deftest block-body-validates-block-access-list-item-gas-limit
  (let* ((address (address-from-hex
                   "0x0000000000000000000000000000000000000001"))
         (read-slot (hash32-from-hex
                     "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (write-slot (hash32-from-hex
                      "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (slot-writes (make-block-access-slot-writes
                       :slot write-slot
                       :accesses
                       (list (make-block-access-storage-write
                              :tx-index 0
                              :value-after 7))))
         (account (make-block-access-account
                   :address address
                   :storage-writes (list slot-writes)
                   :storage-reads (list read-slot)))
         (access-list (list account))
         (config (make-chain-config :london-block 0
                                    :amsterdam-time 0))
         (limit-block
           (make-block :header (make-block-header
                                :timestamp 0
                                :gas-limit
                                (* 3 +block-access-list-item-gas-cost+))
                       :block-access-list access-list))
         (oversized-block
           (make-block :header (make-block-header
                                :timestamp 0
                                :gas-limit
                                (* 2 +block-access-list-item-gas-cost+))
                       :block-access-list access-list)))
    (is (= 3 (block-access-list-item-count access-list)))
    (is (validate-block-access-list-fields access-list
                                           :max-items 3))
    (signals block-validation-error
      (validate-block-access-list-fields access-list
                                         :max-items 2))
    (is (validate-block-body-against-config limit-block config))
    (signals block-validation-error
      (validate-block-body-against-config oversized-block config))))

(deftest block-body-validates-block-access-list-shape-before-hash
  (let ((block (make-block)))
    (setf (block-block-access-list block) "not a block access list"
          (block-block-access-list-present-p block) t)
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-blob-gas-used
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (bad-version-hash (hash32-from-hex
                            "0x0200000000000000000000000000000000000000000000000000000000000000"))
         (transaction (make-blob-transaction
                       :chain-id 1
                       :nonce 1
                       :max-priority-fee-per-gas 2
                       :max-fee-per-gas 3
                       :gas-limit 21000
                       :to address
                       :max-fee-per-blob-gas 4
                       :blob-versioned-hashes (list blob-hash)))
         (block (make-block :transactions (list transaction))))
    (is (= +blob-gas-per-blob+
           (blob-gas-used (block-transactions block))))
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-header-blob-gas-used (block-header block))
          +blob-gas-per-blob+)
    (is (validate-block-body-roots block))
    (setf (block-header-blob-gas-used (block-header block))
          (1+ +blob-gas-per-blob+))
    (signals block-validation-error
      (validate-block-body-roots block))
    (signals block-validation-error
      (validate-block-body-roots
       (make-block
        :transactions
        (list (make-blob-transaction :to address
                                     :blob-versioned-hashes '())))))
    (signals block-validation-error
      (validate-block-body-roots
       (make-block
        :transactions
        (list (make-blob-transaction
              :to address
              :blob-versioned-hashes (list bad-version-hash))))))))

(deftest blob-gas-limit-validation
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (max-hashes (loop repeat +max-blobs-per-block+
                           collect blob-hash))
         (too-many-hashes (append max-hashes (list blob-hash)))
         (max-tx (make-blob-transaction :to address
                                        :blob-versioned-hashes max-hashes))
         (too-large-tx (make-blob-transaction
                        :to address
                        :blob-versioned-hashes too-many-hashes))
         (max-block (make-block :transactions (list max-tx)))
         (too-large-header
           (make-block-header :blob-gas-used (* (1+ +max-blobs-per-block+)
                                                +blob-gas-per-blob+)
                              :excess-blob-gas 0)))
    (setf (block-header-blob-gas-used (block-header max-block))
          (* +max-blobs-per-block+ +blob-gas-per-blob+))
    (is (validate-block-body-roots max-block))
    (signals block-validation-error
      (validate-blob-transaction-fields too-large-tx))
    (signals block-validation-error
      (validate-blob-transaction-fields
       (make-blob-transaction :to nil
                              :blob-versioned-hashes (list blob-hash))))
    (signals block-validation-error
      (validate-blob-transaction-fields
       (make-blob-transaction :to address
                              :blob-versioned-hashes (list nil))))
    (signals block-validation-error
      (validate-blob-transaction-fields
       (make-blob-transaction :to address
                              :blob-versioned-hashes (list #(#x01 #x02)))))
    (signals block-validation-error
      (validate-block-blob-gas-fields too-large-header))))

(deftest osaka-block-body-allows-higher-aggregate-blob-limit
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (six-hashes (loop repeat +max-blobs-per-block+
                           collect blob-hash))
         (three-hashes (loop repeat (- +osaka-max-blobs-per-block+
                                       +max-blobs-per-block+)
                             collect blob-hash))
         (config (make-chain-config :london-block 0
                                    :cancun-time 0
                                    :osaka-time 10))
         (transactions
           (list (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes six-hashes)
                 (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes three-hashes)))
         (block (make-block :header (make-block-header
                                      :number 1
                                      :timestamp 10
                                      :blob-gas-used
                                      (* +osaka-max-blobs-per-block+
                                         +blob-gas-per-blob+)
                                      :excess-blob-gas 0)
                            :transactions transactions)))
    (signals block-validation-error
      (validate-block-body-roots block))
    (is (validate-block-body-against-config block config))))

(deftest prague-block-body-uses-expanded-blob-schedule
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (six-hashes (loop repeat +max-blobs-per-block+
                           collect blob-hash))
         (three-hashes (loop repeat (- +osaka-max-blobs-per-block+
                                       +max-blobs-per-block+)
                             collect blob-hash))
         (config (make-chain-config :london-block 0
                                    :cancun-time 0
                                    :prague-time 10))
         (transactions
           (list (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes six-hashes)
                 (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes three-hashes)))
         (block (make-block :header (make-block-header
                                      :number 1
                                      :timestamp 10
                                      :blob-gas-used
                                      (* +osaka-max-blobs-per-block+
                                         +blob-gas-per-blob+)
                                      :excess-blob-gas 0)
                            :transactions transactions)))
    (signals block-validation-error
      (validate-block-body-roots block))
    (is (validate-block-body-against-config block config))))

(deftest bpo-block-body-uses-scheduled-blob-limits
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (six-hashes (loop repeat +max-blobs-per-block+
                           collect blob-hash))
         (three-hashes (loop repeat 3 collect blob-hash))
         (two-hashes (loop repeat 2 collect blob-hash))
         (bpo1-transactions
           (list (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes six-hashes)
                 (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes six-hashes)
                 (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes three-hashes)))
         (bpo2-transactions
           (append bpo1-transactions
                   (list (make-blob-transaction
                          :to address
                          :max-fee-per-blob-gas 1
                          :blob-versioned-hashes six-hashes))))
         (bpo3-transactions
           (append (loop repeat 5
                         collect (make-blob-transaction
                                  :to address
                                  :max-fee-per-blob-gas 1
                                  :blob-versioned-hashes six-hashes))
                   (list (make-blob-transaction
                          :to address
                          :max-fee-per-blob-gas 1
                          :blob-versioned-hashes two-hashes))))
         (config (make-chain-config :london-block 0
                                    :cancun-time 0
                                    :bpo1-time 30
                                    :bpo2-time 40
                                    :bpo3-time 50
                                    :bpo4-time 60))
         (bpo1-block
           (make-block :header (make-block-header
                                :number 1
                                :timestamp 30
                                :blob-gas-used
                                (* +bpo1-max-blobs-per-block+
                                   +blob-gas-per-blob+)
                                :excess-blob-gas 0)
                       :transactions bpo1-transactions))
         (bpo2-block
           (make-block :header (make-block-header
                                :number 2
                                :timestamp 40
                                :blob-gas-used
                                (* +bpo2-max-blobs-per-block+
                                   +blob-gas-per-blob+)
                                :excess-blob-gas 0)
                       :transactions bpo2-transactions))
         (bpo3-block
           (make-block :header (make-block-header
                                :number 3
                                :timestamp 50
                                :blob-gas-used
                                (* +bpo3-max-blobs-per-block+
                                   +blob-gas-per-blob+)
                                :excess-blob-gas 0)
                       :transactions bpo3-transactions))
         (bpo4-block
           (make-block :header (make-block-header
                                :number 4
                                :timestamp 60
                                :blob-gas-used
                                (* +bpo4-max-blobs-per-block+
                                   +blob-gas-per-blob+)
                                :excess-blob-gas 0)
                       :transactions bpo2-transactions)))
    (signals block-validation-error
      (validate-block-body-roots bpo1-block))
    (signals block-validation-error
      (validate-block-body-roots bpo2-block))
    (signals block-validation-error
      (validate-block-body-roots bpo3-block))
    (signals block-validation-error
      (validate-block-body-roots bpo4-block))
    (is (validate-block-body-against-config bpo1-block config))
    (is (validate-block-body-against-config bpo2-block config))
    (is (validate-block-body-against-config bpo3-block config))
    (is (validate-block-body-against-config bpo4-block config))))

(deftest custom-blob-schedule-body-validation-uses-active-entry
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (six-hashes (loop repeat +max-blobs-per-block+
                           collect blob-hash))
         (one-hash (list blob-hash))
         (config (make-chain-config
                  :london-block 0
                  :cancun-time 0
                  :custom-blob-schedule
                  (list (make-blob-schedule-entry :timestamp 20
                                                  :target-blobs 5
                                                  :max-blobs 7
                                                  :update-fraction 424242))))
         (transactions
           (list (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes six-hashes)
                 (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes one-hash)))
         (block (make-block :header (make-block-header
                                      :number 1
                                      :timestamp 20
                                      :blob-gas-used (* 7 +blob-gas-per-blob+)
                                      :excess-blob-gas 0)
                            :transactions transactions)))
    (signals block-validation-error
      (validate-block-body-roots block))
    (is (validate-block-body-against-config block config))))

(deftest blob-sidecar-field-validation
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob (make-byte-vector +blob-byte-size+))
         (commitment (make-byte-vector +kzg-commitment-size+))
         (proof (make-byte-vector +kzg-proof-size+))
         (versioned-hash (kzg-commitment-to-versioned-hash commitment))
         (transaction (make-blob-transaction
                       :to address
                       :blob-versioned-hashes (list versioned-hash)))
         (sidecar (make-blob-sidecar :blobs (list blob)
                                     :commitments (list commitment)
                                     :proofs (list proof))))
    (is (validate-blob-sidecar-fields sidecar :transaction transaction))
    (is (bytes= (hash32-bytes versioned-hash)
                (hash32-bytes (first (blob-sidecar-versioned-hashes sidecar)))))
    (signals block-validation-error
      (validate-blob-sidecar-fields
       (make-blob-sidecar :blobs (list blob)
                          :commitments (list commitment)
                          :proofs '())
       :transaction transaction))
    (signals block-validation-error
      (validate-blob-sidecar-fields
       (make-blob-sidecar :blobs (list #())
                          :commitments (list commitment)
                          :proofs (list proof))))
    (signals block-validation-error
      (validate-blob-sidecar-fields
       (make-blob-sidecar :blobs (list blob)
                          :commitments (list #())
                          :proofs (list proof))))
    (signals block-validation-error
      (validate-blob-sidecar-fields
       (make-blob-sidecar :blobs (list blob)
                          :commitments (list commitment)
                          :proofs (list #()))))
    (let ((other-commitment (copy-seq commitment)))
      (setf (aref other-commitment 0) 1)
      (signals block-validation-error
        (validate-blob-sidecar-fields
         (make-blob-sidecar :blobs (list blob)
                            :commitments (list other-commitment)
                            :proofs (list proof))
         :transaction transaction)))))

(deftest blob-transaction-fee-cap-validation
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (transaction (make-blob-transaction
                       :to address
                       :max-fee-per-blob-gas 1
                       :blob-versioned-hashes (list blob-hash)))
         (overwide-transaction (make-blob-transaction
                                :to address
                                :max-fee-per-blob-gas (1+ +uint256-max+)
                                :blob-versioned-hashes (list blob-hash)))
         (block (make-block :transactions (list transaction)))
         (header (block-header block)))
    (setf (block-header-blob-gas-used header) +blob-gas-per-blob+
          (block-header-excess-blob-gas header) 2314058)
    (is (= 2 (block-header-blob-base-fee header)))
    (signals block-validation-error
      (validate-blob-transaction-fee-cap overwide-transaction 2))
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (blob-transaction-max-fee-per-blob-gas transaction) 2)
    (setf (block-header-transactions-root header)
          (transaction-list-root (block-transactions block)))
    (is (validate-block-body-roots block)))
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (transaction (make-blob-transaction
                       :to address
                       :max-fee-per-blob-gas 1
                       :blob-versioned-hashes (list blob-hash)))
         (config (make-chain-config :london-block 0
                                    :cancun-time 0
                                    :osaka-time 10))
         (block (make-block :transactions (list transaction)))
         (header (block-header block)))
    (setf (block-header-number header) 1
          (block-header-timestamp header) 10
          (block-header-blob-gas-used header) +blob-gas-per-blob+
          (block-header-excess-blob-gas header) 2314058)
    (is (= 1 (block-header-blob-base-fee
              header
              :update-fraction +osaka-blob-base-fee-update-fraction+)))
    (signals block-validation-error
      (validate-block-body-roots block))
    (is (validate-block-body-against-config block config))))

(deftest block-withdrawals-presence-is-distinct-from-empty-list
  (let* ((empty-shanghai-block (make-block :withdrawals '()))
         (header-with-missing-body
           (make-block-header :withdrawals-root (withdrawal-list-root '())))
         (missing-body-block (make-block :header header-with-missing-body))
         (pre-shanghai-block (make-block :withdrawals '())))
    (is (block-withdrawals-present-p empty-shanghai-block))
    (is (validate-block-body-roots empty-shanghai-block))
    (signals block-validation-error
      (validate-block-body-roots missing-body-block))
    (setf (block-header-withdrawals-root (block-header pre-shanghai-block)) nil)
    (signals block-validation-error
      (validate-block-body-roots pre-shanghai-block))))

(deftest block-body-validates-withdrawal-fields
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (withdrawal (make-withdrawal :index 0
                                      :validator-index 42
                                      :address recipient
                                      :amount 1))
         (block (make-block :withdrawals (list withdrawal))))
    (setf (withdrawal-amount withdrawal) (1+ +uint256-max+))
    (signals block-validation-error
      (validate-withdrawal-fields withdrawal))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-withdrawal-list-before-root-derivation
  (let ((block (make-block)))
    (setf (block-withdrawals block) "not a withdrawal list"
          (block-withdrawals-present-p block) t)
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest post-merge-block-body-rejects-ommers
  (let* ((ommer (make-block-header :beneficiary
                                   (address-from-hex
                                    "0x00000000000000000000000000000000000000dd")
                                   :difficulty 1
                                   :number 7))
         (block (make-block :header (make-block-header :difficulty 0
                                                       :number 8)
                            :ommers (list ommer))))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-execution-root-validation
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (topic (hash32-from-hex
                 "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (log (make-log-entry :address address :topics (list topic) :data #(7)))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000
                                :logs (list log)))
         (state-root (hash32-from-hex
                      "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (block (make-block :receipts (list receipt)))
         (header (block-header block)))
    (setf (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (is (= 21000 (receipts-gas-used (list receipt))))
    (is (validate-block-execution-roots block (list receipt) state-root))
    (setf (block-header-gas-used header) 21001)
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root))
    (setf (block-header-gas-used header) 21000
          (block-header-receipts-root header) (zero-hash32))
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root))))

(deftest block-execution-validates-commitment-fields-before-comparison
  (let* ((receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (state-root (hash32-from-hex
                      "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (block (make-block :receipts (list receipt)))
         (header (block-header block)))
    (setf (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (setf (block-header-logs-bloom header) "not a bloom")
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root))
    (setf (block-header-logs-bloom header) (make-byte-vector 256)
          (block-header-receipts-root header) nil)
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root))
    (setf (block-header-receipts-root header) (receipt-list-root (list receipt))
          (block-header-state-root header) nil)
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root))
    (setf (block-header-state-root header) state-root)
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) nil))))

(deftest block-execution-validates-receipts-before-derived-fields
  (let* ((state-root (hash32-from-hex
                      "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (good-receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (block (make-block :receipts (list good-receipt)))
         (header (block-header block)))
    (setf (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (signals block-validation-error
      (validate-block-execution-roots block "not a receipt list" state-root))
    (signals block-validation-error
      (validate-block-execution-roots block (list "not a receipt") state-root))
    (signals block-validation-error
      (validate-block-execution-roots
       block
       (list (make-receipt :status 1
                           :cumulative-gas-used (ash 1 64)))
       state-root))
    (signals block-validation-error
      (validate-block-execution-roots
       block
       (list (make-receipt :post-state "not bytes"
                           :cumulative-gas-used 21000))
       state-root))
    (signals block-validation-error
      (validate-block-execution-roots
       block
       (list (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry :address nil))))
       state-root))
    (signals block-validation-error
      (validate-block-execution-roots
       block
       (list (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry
                           :topics (list nil)))))
       state-root))
    (signals block-validation-error
      (validate-block-execution-roots
       block
       (list (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry :data "not bytes"))))
       state-root))))

(deftest block-execution-validates-receipt-cumulative-gas-order
  (let* ((first-receipt (make-receipt :status 1
                                      :cumulative-gas-used 30000))
         (second-receipt (make-receipt :status 1
                                       :cumulative-gas-used 21000))
         (receipts (list first-receipt second-receipt))
         (state-root (hash32-from-hex
                      "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (block (make-block :receipts receipts))
         (header (block-header block)))
    (setf (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (signals block-validation-error
      (validate-block-execution-roots block receipts state-root)))
  (let* ((first-receipt (make-receipt :status 1
                                      :cumulative-gas-used 21000))
         (second-receipt (make-receipt :status 1
                                       :cumulative-gas-used 21000))
         (receipts (list first-receipt second-receipt))
         (state-root (hash32-from-hex
                      "0x2222222222222222222222222222222222222222222222222222222222222222"))
         (block (make-block :receipts receipts))
         (header (block-header block)))
    (setf (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (signals block-validation-error
      (validate-block-execution-roots block receipts state-root))))

(deftest bloom-add-and-lookup-log-values
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (topic (hash32-from-hex
                 "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (log (make-log-entry :address address :topics (list topic)))
         (bloom (receipt-bloom (list log))))
    (is (bloom-contains-p bloom (address-bytes address)))
    (is (bloom-contains-p bloom (hash32-bytes topic)))))

(deftest receipt-rlp-and-root
  (let* ((receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (root (receipt-list-root (list receipt))))
    (is (= 267 (length (receipt-rlp receipt))))
    (is (string= "0xf9010801825208"
                 (subseq (bytes-to-hex (receipt-rlp receipt)) 0 16)))
    (is (hash32-p root))))

(deftest typed-receipt-encoding-and-root
  (let* ((legacy (make-legacy-transaction :gas-price 1))
         (dynamic (make-dynamic-fee-transaction
                   :max-priority-fee-per-gas 1
                   :max-fee-per-gas 2))
         (legacy-receipt (make-receipt :status 1
                                       :cumulative-gas-used 21000))
         (dynamic-receipt (make-receipt :status 1
                                        :cumulative-gas-used 42000))
         (typed-encoding
           (transaction-receipt-encoding dynamic dynamic-receipt))
         (root
           (transaction-receipt-list-root
            (list legacy dynamic)
            (list legacy-receipt dynamic-receipt))))
    (is (= 2 (transaction-type dynamic)))
    (is (= 2 (aref typed-encoding 0)))
    (is (bytes= (receipt-rlp dynamic-receipt)
                (subseq typed-encoding 1)))
    (is (string= (hash32-to-hex (receipt-list-root
                                 (list legacy-receipt)))
                 (hash32-to-hex
                  (transaction-receipt-list-root
                   (list legacy)
                   (list legacy-receipt)))))
    (is (not (string= (hash32-to-hex
                       (receipt-list-root
                        (list legacy-receipt dynamic-receipt)))
                      (hash32-to-hex root))))
    (signals block-validation-error
      (transaction-receipt-list-root (list legacy) '()))))

(deftest transaction-list-root-empty-and-single
  (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
               (hash32-to-hex (transaction-list-root '()))))
  (let ((root (transaction-list-root
               (list (make-legacy-transaction :nonce 1
                                              :gas-price 2
                                              :gas-limit 3
                                              :value 4
                                              :data #(96 0)
                                              :v 27
                                              :r 5
                                              :s 6)))))
    (is (hash32-p root))))

(deftest typed-transaction-encodings
  (let* ((recipient (address-from-hex "0x0000000000000000000000000000000000000001"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (access (list (make-access-list-entry :address recipient
                                               :storage-keys (list slot))))
         (tx1 (make-access-list-transaction :chain-id 1
                                            :nonce 2
                                            :gas-price 3
                                            :gas-limit 4
                                            :to recipient
                                            :value 5
                                            :data #(6)
                                            :access-list access
                                            :y-parity 1
                                            :r 7
                                            :s 8))
         (tx2 (make-dynamic-fee-transaction :chain-id 1
                                            :nonce 2
                                            :max-priority-fee-per-gas 3
                                            :max-fee-per-gas 4
                                            :gas-limit 5
                                            :to recipient
                                            :value 6
                                            :data #(7)
                                            :access-list access
                                            :y-parity 1
                                            :r 8
                                            :s 9))
         (blob-hash
           (hash32-from-hex
            "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (tx3 (make-blob-transaction :chain-id 1
                                      :nonce 2
                                      :max-priority-fee-per-gas 3
                                      :max-fee-per-gas 4
                                      :gas-limit 5
                                      :to recipient
                                      :value 6
                                      :data #(7)
                                      :access-list access
                                      :max-fee-per-blob-gas 10
                                      :blob-versioned-hashes (list blob-hash)
                                      :y-parity 1
                                      :r 8
                                      :s 9))
         (authorization
           (make-set-code-authorization :chain-id 1
                                        :address recipient
                                        :nonce 11
                                        :y-parity 1
                                        :r 12
                                        :s 13))
         (tx4 (make-set-code-transaction :chain-id 1
                                          :nonce 2
                                          :max-priority-fee-per-gas 3
                                          :max-fee-per-gas 4
                                          :gas-limit 5
                                          :to recipient
                                          :value 6
                                          :data #(7)
                                          :access-list access
                                          :authorization-list (list authorization)
                                          :y-parity 1
                                          :r 8
                                          :s 9))
         (blob-encoding (blob-transaction-encoding tx3))
         (blob-payload (rlp-decode-one (subseq blob-encoding 1)))
         (blob-items (rlp-list-items blob-payload))
         (blob-hash-items (rlp-list-items (nth 10 blob-items)))
         (set-code-encoding (set-code-transaction-encoding tx4))
         (set-code-payload (rlp-decode-one (subseq set-code-encoding 1)))
         (set-code-items (rlp-list-items set-code-payload))
         (authorization-items
           (rlp-list-items
            (first (rlp-list-items (nth 9 set-code-items))))))
    (is (= 1 (aref (access-list-transaction-encoding tx1) 0)))
    (is (= 2 (aref (dynamic-fee-transaction-encoding tx2) 0)))
    (is (= 3 (aref blob-encoding 0)))
    (is (= 4 (aref set-code-encoding 0)))
    (is (= 14 (length blob-items)))
    (is (= 10 (bytes-to-integer (nth 9 blob-items))))
    (is (= 1 (length blob-hash-items)))
    (is (bytes= (hash32-bytes blob-hash) (first blob-hash-items)))
    (is (= 13 (length set-code-items)))
    (is (= 6 (length authorization-items)))
    (is (= 11 (bytes-to-integer (third authorization-items))))
    (is (hash32-p (transaction-hash tx1)))
    (is (hash32-p (blob-transaction-signing-hash tx3)))
    (is (not (string= (hash32-to-hex (blob-transaction-signing-hash tx3))
                      (hash32-to-hex (blob-transaction-hash tx3)))))
    (is (hash32-p (set-code-authorization-signing-hash authorization)))
    (is (hash32-p (set-code-transaction-signing-hash tx4)))
    (is (not (string= (hash32-to-hex (set-code-transaction-signing-hash tx4))
                      (hash32-to-hex (set-code-transaction-hash tx4)))))
    (is (hash32-p (transaction-list-root (list tx1 tx2 tx3 tx4))))))
