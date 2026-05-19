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

(deftest legacy-transaction-rlp-decodes-round-trip
  (let* ((recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (tx (make-legacy-transaction :nonce 9
                                      :gas-price 20000000000
                                      :gas-limit 21000
                                      :to recipient
                                      :value 1000000000000000000
                                      :data #(1 2 3)
                                      :v 37
                                      :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
                                      :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
         (encoded (legacy-transaction-rlp tx))
         (decoded (legacy-transaction-from-rlp encoded)))
    (is (typep (transaction-from-encoding encoded) 'legacy-transaction))
    (is (= 9 (legacy-transaction-nonce decoded)))
    (is (= 20000000000 (legacy-transaction-gas-price decoded)))
    (is (= 21000 (legacy-transaction-gas-limit decoded)))
    (is (string= (address-to-hex recipient)
                 (address-to-hex (legacy-transaction-to decoded))))
    (is (= 1000000000000000000 (legacy-transaction-value decoded)))
    (is (bytes= #(1 2 3) (legacy-transaction-data decoded)))
    (is (= 37 (legacy-transaction-v decoded)))
    (is (= #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
           (legacy-transaction-r decoded)))
    (is (= #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83
           (legacy-transaction-s decoded)))
    (is (bytes= encoded (legacy-transaction-rlp decoded))))
  (let* ((tx (make-legacy-transaction :nonce 1
                                      :gas-price 2
                                      :gas-limit 3
                                      :value 4
                                      :data #(96 0)
                                      :v 27
                                      :r 5
                                      :s 6))
         (decoded (transaction-from-encoding (transaction-encoding tx))))
    (is (null (legacy-transaction-to decoded)))
    (is (bytes= (legacy-transaction-rlp tx)
                (legacy-transaction-rlp decoded))))
  (signals block-validation-error
    (legacy-transaction-from-rlp (rlp-encode (list 1 2 3))))
  (signals block-validation-error
    (legacy-transaction-from-rlp
     (rlp-encode (list 0 1 2 (make-byte-vector 19) 3 4 5 6 7))))
  (signals block-validation-error
    (transaction-from-encoding #())))

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
      (validate-block-body-roots block))
    (is (validate-execution-request-list-fields
         (list #(#x00 #xaa) #(#x01 #xbb))))
    (signals block-validation-error
      (validate-execution-request-list-fields (list #(#x00))))
    (signals block-validation-error
      (validate-execution-request-list-fields
       (list #(#x00 #xaa) #(#x00 #xbb))))
    (signals block-validation-error
      (validate-execution-request-list-fields
       (list #(#x01 #xaa) #(#x00 #xbb))))))

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

(deftest json-encode-round-trips-rpc-shaped-objects
  (let* ((object
           (list (cons "jsonrpc" "2.0")
                 (cons "id" 4)
                 (cons "result"
                       (list (cons "status" +payload-status-valid+)
                             (cons "latestValidHash" nil)
                             (cons "labels" '("engine" "newPayload"))
                             (cons "quote" (format nil "line~%break"))))))
         (encoded (json-encode object))
         (decoded (parse-json encoded))
         (result (cdr (assoc "result" decoded :test #'string=))))
    (is (string= "2.0" (cdr (assoc "jsonrpc" decoded :test #'string=))))
    (is (= 4 (cdr (assoc "id" decoded :test #'string=))))
    (is (string= +payload-status-valid+
                 (cdr (assoc "status" result :test #'string=))))
    (is (not (cdr (assoc "latestValidHash" result :test #'string=))))
    (is (equal '("engine" "newPayload")
               (cdr (assoc "labels" result :test #'string=))))
    (is (string= (format nil "line~%break")
                 (cdr (assoc "quote" result :test #'string=))))))

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
                            :requests (list #(#x00 #xbb) #(#x01 #xaa))
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
                  (execution-requests-hash
                   (list #(#x00 #xbb) #(#x01 #xaa))))
                 (hash32-to-hex (block-header-requests-hash header))))
    (is (string= (hash32-to-hex (block-access-list-hash '()))
                 (hash32-to-hex
                  (block-header-block-access-list-hash header))))
    (is (bytes= (bloom-bytes (receipt-bloom (list log)))
                (block-header-logs-bloom header)))))

(deftest block-to-executable-data-maps-engine-payload-fields
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (parent-hash (hash32-from-hex
                       "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (state-root (hash32-from-hex
                      "0x0200000000000000000000000000000000000000000000000000000000000000"))
         (mix-hash (hash32-from-hex
                    "0x0300000000000000000000000000000000000000000000000000000000000000"))
         (transaction (make-legacy-transaction :nonce 1
                                               :gas-price 2
                                               :gas-limit 21000
                                               :to recipient
                                               :value 4
                                               :v 27
                                               :r 6
                                               :s 7))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (withdrawal (make-withdrawal :index 1
                                      :validator-index 2
                                      :address address
                                      :amount 3))
         (requests (list #(#x00 #xaa) #(#x01 #xbb)))
         (header (make-block-header :parent-hash parent-hash
                                    :beneficiary address
                                    :state-root state-root
                                    :mix-hash mix-hash
                                    :number 42
                                    :gas-limit 50000
                                    :gas-used 21000
                                    :timestamp 99
                                    :extra-data #(1 2 3)
                                    :base-fee-per-gas 100
                                    :blob-gas-used 0
                                    :excess-blob-gas 7
                                    :slot-number 11))
         (block (make-block :header header
                            :transactions (list transaction)
                            :receipts (list receipt)
                            :withdrawals (list withdrawal)
                            :requests requests))
         (envelope (block-to-executable-data block :block-value 123))
         (payload (execution-payload-envelope-execution-payload envelope)))
    (is (= 123 (execution-payload-envelope-block-value envelope)))
    (is (not (execution-payload-envelope-override-p envelope)))
    (is (hash32-p (executable-data-block-hash payload)))
    (is (string= (hash32-to-hex (block-hash block))
                 (hash32-to-hex (executable-data-block-hash payload))))
    (is (string= (hash32-to-hex parent-hash)
                 (hash32-to-hex (executable-data-parent-hash payload))))
    (is (string= (address-to-hex address)
                 (address-to-hex (executable-data-fee-recipient payload))))
    (is (string= (hash32-to-hex state-root)
                 (hash32-to-hex (executable-data-state-root payload))))
    (is (string= (hash32-to-hex mix-hash)
                 (hash32-to-hex (executable-data-random payload))))
    (is (= 42 (executable-data-number payload)))
    (is (= 50000 (executable-data-gas-limit payload)))
    (is (= 21000 (executable-data-gas-used payload)))
    (is (= 99 (executable-data-timestamp payload)))
    (is (= 100 (executable-data-base-fee-per-gas payload)))
    (is (= 0 (executable-data-blob-gas-used payload)))
    (is (= 7 (executable-data-excess-blob-gas payload)))
    (is (= 11 (executable-data-slot-number payload)))
    (is (bytes= #(1 2 3) (executable-data-extra-data payload)))
    (is (bytes= (transaction-encoding transaction)
                (first (executable-data-transactions payload))))
    (is (= 1 (length (executable-data-withdrawals payload))))
    (is (= 1 (withdrawal-index
              (first (executable-data-withdrawals payload)))))
    (is (= 2 (length (execution-payload-envelope-requests envelope))))
    (is (bytes= (first requests)
                (first (execution-payload-envelope-requests envelope))))))

(deftest executable-data-decodes-transaction-bytes
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000003"))
         (access (list (make-access-list-entry :address recipient
                                               :storage-keys (list slot))))
         (blob-hash
           (hash32-from-hex
            "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (authorization
           (make-set-code-authorization :chain-id 1
                                        :address recipient
                                        :nonce 11
                                        :y-parity 1
                                        :r 12
                                        :s 13))
         (transactions
           (list
            (make-legacy-transaction :nonce 1
                                     :gas-price 2
                                     :gas-limit 21000
                                     :to recipient
                                     :value 4
                                     :v 27
                                     :r 6
                                     :s 7)
            (make-access-list-transaction :chain-id 1
                                          :nonce 2
                                          :gas-price 3
                                          :gas-limit 4
                                          :to recipient
                                          :value 5
                                          :data #(6)
                                          :access-list access
                                          :y-parity 1
                                          :r 7
                                          :s 8)
            (make-dynamic-fee-transaction :chain-id 1
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
                                          :s 9)
            (make-blob-transaction :chain-id 1
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
                                   :s 9)
            (make-set-code-transaction :chain-id 1
                                       :nonce 2
                                       :max-priority-fee-per-gas 3
                                       :max-fee-per-gas 4
                                       :gas-limit 5
                                       :to recipient
                                       :value 6
                                       :data #(7)
                                       :access-list access
                                       :authorization-list
                                       (list authorization)
                                       :y-parity 1
                                       :r 8
                                       :s 9)))
         (payload (make-executable-data
                   :transactions (mapcar #'transaction-encoding
                                         transactions)))
         (decoded (executable-data-decoded-transactions payload)))
    (is (= (length transactions) (length decoded)))
    (loop for original in transactions
          for decoded-transaction in decoded
          do (is (typep decoded-transaction (type-of original)))
             (is (bytes= (transaction-encoding original)
                         (transaction-encoding decoded-transaction))))
    (signals block-validation-error
      (executable-data-decoded-transactions
       (make-executable-data
        :transactions (append (mapcar #'transaction-encoding
                                      transactions)
                              (list #())))))
    (signals block-validation-error
      (executable-data-decoded-transactions
       (make-executable-data :transactions (list 5))))))

(deftest executable-data-to-block-no-hash-builds-local-block
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (parent-hash (hash32-from-hex
                       "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (state-root (hash32-from-hex
                      "0x0200000000000000000000000000000000000000000000000000000000000000"))
         (mix-hash (hash32-from-hex
                    "0x0300000000000000000000000000000000000000000000000000000000000000"))
         (transaction (make-dynamic-fee-transaction
                       :chain-id 1
                       :nonce 2
                       :max-priority-fee-per-gas 3
                       :max-fee-per-gas 4
                       :gas-limit 21000
                       :to recipient
                       :value 5
                       :data #(6)
                       :y-parity 1
                       :r 7
                       :s 8))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (withdrawal (make-withdrawal :index 1
                                      :validator-index 2
                                      :address address
                                      :amount 3))
         (requests (list #(#x00 #xaa) #(#x01 #xbb)))
         (header (make-block-header :parent-hash parent-hash
                                    :beneficiary address
                                    :state-root state-root
                                    :mix-hash mix-hash
                                    :number 42
                                    :gas-limit 50000
                                    :gas-used 21000
                                    :timestamp 99
                                    :extra-data #(1 2 3)
                                    :base-fee-per-gas 100
                                    :blob-gas-used 0
                                    :excess-blob-gas 7
                                    :slot-number 11))
         (source-block (make-block :header header
                                   :transactions (list transaction)
                                   :receipts (list receipt)
                                   :withdrawals (list withdrawal)
                                   :requests requests))
         (payload (execution-payload-envelope-execution-payload
                   (block-to-executable-data source-block)))
         (reconstructed
           (executable-data-to-block-no-hash payload :requests requests))
         (reconstructed-header (block-header reconstructed)))
    (is (= 1 (length (block-transactions reconstructed))))
    (is (typep (first (block-transactions reconstructed))
               'dynamic-fee-transaction))
    (is (bytes= (transaction-encoding transaction)
                (transaction-encoding
                 (first (block-transactions reconstructed)))))
    (is (block-withdrawals-present-p reconstructed))
    (is (= 1 (length (block-withdrawals reconstructed))))
    (is (block-requests-present-p reconstructed))
    (is (= 2 (length (block-requests reconstructed))))
    (is (string= (hash32-to-hex (block-header-transactions-root header))
                 (hash32-to-hex
                  (block-header-transactions-root reconstructed-header))))
    (is (string= (hash32-to-hex (block-header-receipts-root header))
                 (hash32-to-hex
                  (block-header-receipts-root reconstructed-header))))
    (is (string= (hash32-to-hex (block-header-withdrawals-root header))
                 (hash32-to-hex
                  (block-header-withdrawals-root reconstructed-header))))
    (is (string= (hash32-to-hex (block-header-requests-hash header))
                 (hash32-to-hex
                  (block-header-requests-hash reconstructed-header))))
    (is (string= (hash32-to-hex (block-hash source-block))
                 (hash32-to-hex (block-hash reconstructed))))
    (is (= 42 (block-header-number reconstructed-header)))
    (is (= 100 (block-header-base-fee-per-gas reconstructed-header)))
    (is (= 7 (block-header-excess-blob-gas reconstructed-header)))
    (is (= 11 (block-header-slot-number reconstructed-header)))
    (let ((bad-extra payload))
      (setf (executable-data-extra-data bad-extra) (make-byte-vector 33))
      (signals block-validation-error
        (executable-data-to-block-no-hash bad-extra)))
    (let ((bad-bloom (block-to-executable-data source-block)))
      (let ((bad-payload
              (execution-payload-envelope-execution-payload bad-bloom)))
        (setf (executable-data-logs-bloom bad-payload) #(1 2))
        (signals block-validation-error
          (executable-data-to-block-no-hash bad-payload))))))

(deftest executable-data-to-block-checks-payload-block-hash
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (parent-hash (hash32-from-hex
                       "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (state-root (hash32-from-hex
                      "0x0200000000000000000000000000000000000000000000000000000000000000"))
         (mix-hash (hash32-from-hex
                    "0x0300000000000000000000000000000000000000000000000000000000000000"))
         (transaction (make-legacy-transaction :nonce 1
                                               :gas-price 2
                                               :gas-limit 21000
                                               :to recipient
                                               :value 4
                                               :v 27
                                               :r 6
                                               :s 7))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (withdrawal (make-withdrawal :index 1
                                      :validator-index 2
                                      :address address
                                      :amount 3))
         (requests (list #(#x00 #xaa) #(#x01 #xbb)))
         (header (make-block-header :parent-hash parent-hash
                                    :beneficiary address
                                    :state-root state-root
                                    :mix-hash mix-hash
                                    :number 42
                                    :gas-limit 50000
                                    :gas-used 21000
                                    :timestamp 99
                                    :extra-data #(1 2 3)
                                    :base-fee-per-gas 100))
         (source-block (make-block :header header
                                   :transactions (list transaction)
                                   :receipts (list receipt)
                                   :withdrawals (list withdrawal)
                                   :requests requests))
         (payload (execution-payload-envelope-execution-payload
                   (block-to-executable-data source-block)))
         (reconstructed (executable-data-to-block payload :requests requests)))
    (is (string= (hash32-to-hex (block-hash source-block))
                 (hash32-to-hex (block-hash reconstructed))))
    (setf (executable-data-block-hash payload)
          (hash32-from-hex
           "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"))
    (signals block-validation-error
      (executable-data-to-block payload :requests requests))
    (setf (executable-data-block-hash payload) #(1 2))
    (signals block-validation-error
      (executable-data-to-block payload :requests requests))))

(deftest executable-data-to-block-validates-blob-versioned-hashes
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash
           (hash32-from-hex
            "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (other-blob-hash
           (hash32-from-hex
            "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (transaction (make-blob-transaction
                       :chain-id 1
                       :nonce 2
                       :max-priority-fee-per-gas 3
                       :max-fee-per-gas 4
                       :gas-limit 21000
                       :to address
                       :value 5
                       :max-fee-per-blob-gas 6
                       :blob-versioned-hashes (list blob-hash)
                       :y-parity 1
                       :r 7
                       :s 8))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (header (make-block-header
                  :parent-hash (zero-hash32)
                  :beneficiary address
                  :state-root +empty-trie-hash+
                  :mix-hash (zero-hash32)
                  :number 42
                  :gas-limit 50000
                  :gas-used 21000
                  :timestamp 99
                  :base-fee-per-gas 100
                  :blob-gas-used +blob-gas-per-blob+
                  :excess-blob-gas 0))
         (source-block (make-block :header header
                                   :transactions (list transaction)
                                   :receipts (list receipt)))
         (payload (execution-payload-envelope-execution-payload
                   (block-to-executable-data source-block)))
         (reconstructed
           (executable-data-to-block
            payload
            :versioned-hashes (list blob-hash))))
    (is (string= (hash32-to-hex (block-hash source-block))
                 (hash32-to-hex (block-hash reconstructed))))
    (signals block-validation-error
      (executable-data-to-block payload))
    (signals block-validation-error
      (executable-data-to-block payload :versioned-hashes '()))
    (signals block-validation-error
      (executable-data-to-block
       payload
       :versioned-hashes (list other-blob-hash)))
    (signals block-validation-error
      (executable-data-to-block
       payload
       :versioned-hashes (list blob-hash other-blob-hash)))
    (signals block-validation-error
      (executable-data-to-block
       payload
       :versioned-hashes (list #(1 2))))))

(deftest engine-new-payload-params-status-wraps-validation
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (transaction (make-legacy-transaction :nonce 1
                                               :gas-price 2
                                               :gas-limit 21000
                                               :to recipient
                                               :value 4
                                               :v 27
                                               :r 6
                                               :s 7))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (header (make-block-header
                  :parent-hash (zero-hash32)
                  :beneficiary address
                  :state-root +empty-trie-hash+
                  :mix-hash (zero-hash32)
                  :number 42
                  :gas-limit 50000
                  :gas-used 21000
                  :timestamp 99
                  :base-fee-per-gas 100))
         (source-block (make-block :header header
                                   :transactions (list transaction)
                                   :receipts (list receipt)))
         (payload (execution-payload-envelope-execution-payload
                   (block-to-executable-data source-block))))
    (multiple-value-bind (status block)
        (engine-new-payload-params-status payload)
      (is (string= +payload-status-valid+ (payload-status-status status)))
      (is (not (payload-status-validation-error status)))
      (is (typep block 'ethereum-block))
      (is (string= (hash32-to-hex (block-hash source-block))
                   (hash32-to-hex
                    (payload-status-latest-valid-hash status))))
      (is (string= (hash32-to-hex (block-hash source-block))
                   (hash32-to-hex (block-hash block)))))
    (setf (executable-data-block-hash payload)
          (hash32-from-hex
           "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"))
    (multiple-value-bind (status block)
        (engine-new-payload-params-status payload)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (not block))
      (is (not (payload-status-latest-valid-hash status)))
      (is (search "block hash mismatch"
                  (payload-status-validation-error status))))))

(deftest engine-new-payload-version-status-enforces-fork-parameters
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (parent-beacon-root
           (hash32-from-hex
            "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (transaction (make-legacy-transaction :nonce 1
                                               :gas-price 2
                                               :gas-limit 21000
                                               :to recipient
                                               :value 4
                                               :v 27
                                               :r 6
                                               :s 7))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (withdrawal (make-withdrawal :index 1
                                      :validator-index 2
                                      :address address
                                      :amount 3))
         (requests (list #(#x00 #xaa)))
         (london-config (make-chain-config :london-block 0))
         (cancun-config (make-chain-config :london-block 0
                                           :shanghai-time 0
                                           :cancun-time 0))
         (prague-config (make-chain-config :london-block 0
                                           :shanghai-time 0
                                           :cancun-time 0
                                           :prague-time 0))
         (amsterdam-config (make-chain-config :london-block 0
                                              :shanghai-time 0
                                              :cancun-time 0
                                              :prague-time 0
                                              :amsterdam-time 0))
         (legacy-header (make-block-header
                         :parent-hash (zero-hash32)
                         :beneficiary address
                         :state-root +empty-trie-hash+
                         :mix-hash (zero-hash32)
                         :number 42
                         :gas-limit 50000
                         :gas-used 21000
                         :timestamp 99
                         :base-fee-per-gas 100))
         (cancun-header (make-block-header
                         :parent-hash (zero-hash32)
                         :beneficiary address
                         :state-root +empty-trie-hash+
                         :mix-hash (zero-hash32)
                         :number 42
                         :gas-limit 50000
                         :gas-used 21000
                         :timestamp 99
                         :base-fee-per-gas 100
                         :withdrawals-root (withdrawal-list-root
                                            (list withdrawal))
                         :blob-gas-used 0
                         :excess-blob-gas 0
                         :parent-beacon-root parent-beacon-root))
         (prague-header (make-block-header
                         :parent-hash (zero-hash32)
                         :beneficiary address
                         :state-root +empty-trie-hash+
                         :mix-hash (zero-hash32)
                         :number 42
                         :gas-limit 50000
                         :gas-used 21000
                         :timestamp 99
                         :base-fee-per-gas 100
                         :withdrawals-root (withdrawal-list-root
                                            (list withdrawal))
                         :blob-gas-used 0
                         :excess-blob-gas 0
                         :parent-beacon-root parent-beacon-root
                         :requests-hash (execution-requests-hash requests)))
         (amsterdam-header (make-block-header
                            :parent-hash (zero-hash32)
                            :beneficiary address
                            :state-root +empty-trie-hash+
                            :mix-hash (zero-hash32)
                            :number 42
                            :gas-limit 50000
                            :gas-used 21000
                            :timestamp 99
                            :base-fee-per-gas 100
                            :withdrawals-root (withdrawal-list-root
                                               (list withdrawal))
                            :blob-gas-used 0
                            :excess-blob-gas 0
                            :parent-beacon-root parent-beacon-root
                            :requests-hash (execution-requests-hash requests)
                            :slot-number 7))
         (amsterdam-header-without-block-access-list
           (make-block-header
            :parent-hash (zero-hash32)
            :beneficiary address
            :state-root +empty-trie-hash+
            :mix-hash (zero-hash32)
            :number 42
            :gas-limit 50000
            :gas-used 21000
            :timestamp 99
            :base-fee-per-gas 100
            :withdrawals-root (withdrawal-list-root (list withdrawal))
            :blob-gas-used 0
            :excess-blob-gas 0
            :parent-beacon-root parent-beacon-root
            :requests-hash (execution-requests-hash requests)
            :slot-number 7))
         (legacy-payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data
             (make-block :header legacy-header
                         :transactions (list transaction)
                         :receipts (list receipt)))))
         (cancun-payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data
             (make-block :header cancun-header
                         :transactions (list transaction)
                         :receipts (list receipt)
                         :withdrawals (list withdrawal)))))
         (prague-payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data
             (make-block :header prague-header
                         :transactions (list transaction)
                         :receipts (list receipt)
                         :withdrawals (list withdrawal)
                         :requests requests))))
         (amsterdam-payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data
             (make-block :header amsterdam-header
                         :transactions (list transaction)
                         :receipts (list receipt)
                         :withdrawals (list withdrawal)
                         :requests requests
                         :block-access-list '()))))
         (amsterdam-payload-without-block-access-list
           (execution-payload-envelope-execution-payload
            (block-to-executable-data
             (make-block :header amsterdam-header-without-block-access-list
                         :transactions (list transaction)
                         :receipts (list receipt)
                         :withdrawals (list withdrawal)
                         :requests requests)))))
    (multiple-value-bind (status block)
        (engine-new-payload-version-status 1 legacy-payload london-config)
      (is (string= +payload-status-valid+ (payload-status-status status)))
      (is (typep block 'ethereum-block)))
    (multiple-value-bind (status block)
        (engine-new-payload-version-status 1 cancun-payload cancun-config)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (not block)))
    (multiple-value-bind (status block)
        (engine-new-payload-version-status 2 legacy-payload cancun-config)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (not block)))
    (multiple-value-bind (status block)
        (engine-new-payload-version-status
         3 cancun-payload cancun-config
         :parent-beacon-root parent-beacon-root
         :versioned-hashes '())
      (is (string= +payload-status-valid+ (payload-status-status status)))
      (is (typep block 'ethereum-block)))
    (multiple-value-bind (status block)
        (engine-new-payload-version-status
         3 cancun-payload cancun-config
         :parent-beacon-root parent-beacon-root)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (not block)))
    (multiple-value-bind (status block)
        (engine-new-payload-version-status
         4 prague-payload prague-config
         :parent-beacon-root parent-beacon-root
         :versioned-hashes '()
         :requests requests)
      (is (string= +payload-status-valid+ (payload-status-status status)))
      (is (typep block 'ethereum-block)))
    (multiple-value-bind (status block)
        (engine-new-payload-version-status
         4 prague-payload prague-config
         :parent-beacon-root parent-beacon-root
         :versioned-hashes '())
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (not block)))
    (multiple-value-bind (status block)
        (engine-new-payload-version-status
         5 amsterdam-payload amsterdam-config
         :parent-beacon-root parent-beacon-root
         :versioned-hashes '()
         :requests requests)
      (is (string= +payload-status-valid+ (payload-status-status status)))
      (is (typep block 'ethereum-block)))
    (multiple-value-bind (status block)
        (engine-new-payload-version-status
         5 prague-payload prague-config
         :parent-beacon-root parent-beacon-root
         :versioned-hashes '()
         :requests requests)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (not block)))
    (multiple-value-bind (status block)
        (engine-new-payload-version-status
         5 amsterdam-payload-without-block-access-list amsterdam-config
         :parent-beacon-root parent-beacon-root
         :versioned-hashes '()
         :requests requests)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (string= "blockAccessList required after Amsterdam"
                   (payload-status-validation-error status)))
      (is (not block)))))

(deftest engine-new-payload-memory-status-tracks-parent-availability
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (config (make-chain-config :london-block 0))
         (parent-header (make-block-header
                         :parent-hash (zero-hash32)
                         :beneficiary address
                         :state-root +empty-trie-hash+
                         :mix-hash (zero-hash32)
                         :number 41
                         :gas-limit 50000
                         :gas-used 25000
                         :timestamp 98
                         :base-fee-per-gas 100))
         (parent-block (make-block :header parent-header))
         (child-header (make-block-header
                        :parent-hash (block-hash parent-block)
                        :beneficiary address
                        :state-root +empty-trie-hash+
                        :mix-hash (zero-hash32)
                        :number 42
                        :gas-limit 50000
                        :gas-used 0
                        :timestamp 99
                        :base-fee-per-gas 100))
         (child-block (make-block :header child-header))
         (payload (execution-payload-envelope-execution-payload
                   (block-to-executable-data child-block)))
         (missing-parent-store (make-engine-payload-memory-store))
         (missing-state-store (make-engine-payload-memory-store))
         (ready-store (make-engine-payload-memory-store)))
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status
         missing-parent-store 1 payload config)
      (is (string= +payload-status-syncing+ (payload-status-status status)))
      (is (typep block 'ethereum-block))
      (is (engine-payload-store-remote-block
           missing-parent-store
           (block-hash child-block))))
    (engine-payload-store-put-block missing-state-store parent-block)
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status
         missing-state-store 1 payload config)
      (is (string= +payload-status-accepted+ (payload-status-status status)))
      (is (typep block 'ethereum-block))
      (is (engine-payload-store-remote-block
           missing-state-store
           (block-hash child-block))))
    (engine-payload-store-put-block
     ready-store parent-block :state-available-p t)
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status ready-store 1 payload config)
      (is (string= +payload-status-valid+ (payload-status-status status)))
      (is (string= (hash32-to-hex (block-hash child-block))
                   (hash32-to-hex
                    (payload-status-latest-valid-hash status))))
      (is (typep block 'ethereum-block))
      (is (engine-payload-store-known-block ready-store
                                            (block-hash child-block))))
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status ready-store 1 payload config)
      (is (string= +payload-status-valid+ (payload-status-status status)))
      (is (typep block 'ethereum-block)))))

(deftest chain-store-interface-wraps-memory-payload-store
  (let* ((store (make-engine-payload-memory-store))
         (payload-id #(1 2 3 4 5 6 7 8))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (storage-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (transaction
           (make-legacy-transaction
            :nonce 1
            :gas-price 2
            :gas-limit 21000
            :to address
            :value 3
            :v 27
            :r 4
            :s 5))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (header (make-block-header :number 43
                                    :state-root +empty-trie-hash+))
         (block (make-block :header header
                            :transactions (list transaction)
                            :receipts (list receipt)))
         (competing-block
           (make-block
            :header
            (make-block-header :number 43
                               :timestamp 1
                               :extra-data #(99))))
         (block-hash (block-hash block))
         (competing-block-hash (block-hash competing-block))
         (transaction-hash (transaction-hash transaction))
         (forkchoice-state
           (make-forkchoice-state
            :head-block-hash block-hash
            :safe-block-hash block-hash
            :finalized-block-hash block-hash))
         (prepared-payload
           (make-engine-prepared-payload
            :payload-id payload-id
            :version 3
            :block block)))
    (is (eq block
            (chain-store-put-block store block :state-available-p t)))
    (is (eq block (chain-store-known-block store block-hash)))
    (is (eq block (chain-store-block-by-number store 43)))
    (is (string= (hash32-to-hex block-hash)
                 (hash32-to-hex (chain-store-canonical-hash store 43))))
    (is (= 43 (chain-store-head-number store)))
    (is (= 43 (chain-store-block-tag-number store "latest")))
    (is (eq block (chain-store-latest-block store)))
    (chain-store-put-block store competing-block)
    (is (eq competing-block
            (chain-store-known-block store competing-block-hash)))
    (is (eq block (chain-store-block-by-number store 43)))
    (is (eq block (chain-store-latest-block store)))
    (is (string= (hash32-to-hex block-hash)
                 (hash32-to-hex (chain-store-canonical-hash store 43))))
    (is (chain-store-state-available-p store block-hash))
    (is (= 99
           (chain-store-put-account-balance
            store block-hash address 99)))
    (is (= 99
           (chain-store-account-balance store block-hash address)))
    (is (= 7
           (chain-store-put-account-nonce store block-hash address 7)))
    (is (= 7
           (chain-store-account-nonce store block-hash address)))
    (is (bytes= #(1 2 3)
                (chain-store-put-account-code
                 store block-hash address #(1 2 3))))
    (is (bytes= #(1 2 3)
                (chain-store-account-code store block-hash address)))
    (is (= 5
           (chain-store-put-account-storage
            store block-hash address storage-slot 5)))
    (is (= 5
           (chain-store-account-storage
            store block-hash address storage-slot)))
    (let ((location
            (chain-store-transaction-location store transaction-hash)))
      (is (typep location 'engine-transaction-location))
      (is (eq block (engine-transaction-location-block location)))
      (is (= 0 (engine-transaction-location-index location)))
      (is (eq transaction
              (engine-transaction-location-transaction location)))
      (is (eq receipt (engine-transaction-location-receipt location))))
    (is (equal (list receipt)
               (chain-store-block-receipts store block-hash)))
    (is (eq store
            (chain-store-update-forkchoice-checkpoints
             store forkchoice-state)))
    (is (typep (chain-store-head-checkpoint store)
               'chain-store-checkpoint))
    (is (eq :head
            (chain-store-checkpoint-label
             (chain-store-head-checkpoint store))))
    (is (string= (hash32-to-hex block-hash)
                 (hash32-to-hex
                  (chain-store-checkpoint-block-hash
                   (chain-store-head-checkpoint store)))))
    (is (typep (chain-store-safe-checkpoint store)
               'chain-store-checkpoint))
    (is (eq :safe
            (chain-store-checkpoint-label
             (chain-store-safe-checkpoint store))))
    (is (typep (chain-store-finalized-checkpoint store)
               'chain-store-checkpoint))
    (is (eq :finalized
            (chain-store-checkpoint-label
             (chain-store-finalized-checkpoint store))))
    (is (eq block (chain-store-head-block store)))
    (is (eq block (chain-store-safe-block store)))
    (is (eq block (chain-store-finalized-block store)))
    (is (= 43 (chain-store-block-tag-number store "safe")))
    (is (= 43 (chain-store-block-tag-number store "finalized")))
    (is (eq prepared-payload
            (chain-store-put-prepared-payload store prepared-payload)))
    (is (eq prepared-payload
            (chain-store-prepared-payload store payload-id)))))

(deftest execute-atomic-block-commit-commits-state-and-store-together
  (let* ((store (make-engine-payload-memory-store))
         (state (make-state-db))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (transaction
           (make-legacy-transaction
            :nonce 1
            :gas-price 2
            :gas-limit 21000
            :to address
            :value 3
            :v 27
            :r 4
            :s 5))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (block
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+)
            :transactions (list transaction)
            :receipts (list receipt)))
         (block-hash (block-hash block))
         (transaction-hash (transaction-hash transaction)))
    (multiple-value-bind (result committed-block)
        (execute-atomic-block-commit
         store state
         (lambda ()
           (chain-store-put-block store block :state-available-p t)
           (chain-store-put-account-balance store block-hash address 99)
           (state-db-set-account state address
                                 (make-state-account :balance 99))
           (values :committed block)))
      (is (eq :committed result))
      (is (eq block committed-block)))
    (is (eq block (chain-store-known-block store block-hash)))
    (is (chain-store-state-available-p store block-hash))
    (is (= 99 (chain-store-account-balance store block-hash address)))
    (is (typep (chain-store-transaction-location store transaction-hash)
               'engine-transaction-location))
    (is (= 99
           (state-account-balance
            (state-db-get-account state address))))))

(deftest execute-atomic-block-commit-rolls-back-state-and-store-on-error
  (let* ((store (make-engine-payload-memory-store))
         (state (make-state-db))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (transaction
           (make-legacy-transaction
            :nonce 1
            :gas-price 2
            :gas-limit 21000
            :to address
            :value 3
            :v 27
            :r 4
            :s 5))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (block
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+)
            :transactions (list transaction)
            :receipts (list receipt)))
         (block-hash (block-hash block))
         (transaction-hash (transaction-hash transaction)))
    (state-db-set-account state address (make-state-account :balance 10))
    (signals error
      (execute-atomic-block-commit
       store state
       (lambda ()
         (chain-store-put-block store block :state-available-p t)
         (chain-store-put-account-balance store block-hash address 99)
         (state-db-set-account state address
                               (make-state-account :balance 99))
         (error "Injected atomic commit failure"))))
    (is (null (chain-store-known-block store block-hash)))
    (is (null (chain-store-canonical-hash store 0)))
    (is (null (chain-store-transaction-location store transaction-hash)))
    (is (not (chain-store-state-available-p store block-hash)))
    (is (= 0 (chain-store-account-balance store block-hash address)))
    (is (= 10
           (state-account-balance
            (state-db-get-account state address))))))

(deftest execute-and-commit-block-stores-only-after-execution-success
  (let* ((store (make-engine-payload-memory-store))
         (state (make-state-db))
         (sender
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient
           (address-from-hex "0x0000000000000000000000000000000000000002"))
         (contract
           (address-from-hex "0x0000000000000000000000000000000000000003"))
         (storage-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000004"))
         (transaction
           (make-legacy-transaction :nonce 0
                                    :gas-price 1
                                    :gas-limit 21000
                                    :to recipient
                                    :value 10))
         (header (make-block-header :number 0
                                    :parent-hash (zero-hash32)
                                    :gas-limit 50000)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-account state contract
                          (make-state-account :balance 7))
    (state-db-set-code state contract #(1 2 3))
    (state-db-set-storage state contract storage-slot 5)
    (multiple-value-bind (block receipts)
        (execute-and-commit-block
         store state
         (lambda ()
           (execute-legacy-block state sender (list transaction)
                                 :header header)))
      (is (= 1 (length receipts)))
      (is (eq block (chain-store-known-block store (block-hash block))))
      (is (eq block (chain-store-block-by-number store 0)))
      (is (chain-store-state-available-p store (block-hash block)))
      (is (typep (chain-store-transaction-location
                  store
                  (transaction-hash transaction))
                 'engine-transaction-location))
      (is (= 10
             (state-account-balance
              (state-db-get-account state recipient))))
      (is (= 78990
             (chain-store-account-balance store (block-hash block) sender)))
      (is (= 1
             (chain-store-account-nonce store (block-hash block) sender)))
      (is (= 10
             (chain-store-account-balance store (block-hash block) recipient)))
      (is (= 7
             (chain-store-account-balance store (block-hash block) contract)))
      (is (bytes= #(1 2 3)
                  (chain-store-account-code store (block-hash block)
                                            contract)))
      (is (= 5
             (chain-store-account-storage store (block-hash block)
                                          contract storage-slot))))))

(deftest execute-and-commit-block-rolls-back-bad-execution-commitments
  (let ((sender
          (address-from-hex "0x0000000000000000000000000000000000000001"))
        (recipient
          (address-from-hex "0x0000000000000000000000000000000000000002")))
    (labels ((bad-logs-bloom ()
               (let ((bloom (make-byte-vector 256)))
                 (setf (aref bloom 0) 1)
                 bloom))
             (assert-rejected-header (header)
               (let* ((store (make-engine-payload-memory-store))
                      (state (make-state-db))
                      (transaction
                        (make-legacy-transaction
                         :nonce 0
                         :gas-price 1
                         :gas-limit 21000
                         :to recipient
                         :value 10)))
                 (state-db-set-account state sender
                                       (make-state-account :balance 100000))
                 (signals error
                   (execute-and-commit-block
                    store state
                    (lambda ()
                      (execute-legacy-block state sender (list transaction)
                                            :header header))))
                 (is (null (chain-store-block-by-number store 0)))
                 (is (null (chain-store-canonical-hash store 0)))
                 (is (null (chain-store-transaction-location
                            store
                            (transaction-hash transaction))))
                 (is (= 100000
                        (state-account-balance
                         (state-db-get-account state sender))))
                 (is (null (state-db-get-account state recipient))))))
      (assert-rejected-header
       (make-block-header :number 0
                          :parent-hash (zero-hash32)
                          :gas-limit 50000
                          :state-root (zero-hash32)))
      (assert-rejected-header
       (make-block-header :number 0
                          :parent-hash (zero-hash32)
                          :gas-limit 50000
                          :receipts-root (zero-hash32)))
      (assert-rejected-header
       (make-block-header :number 0
                          :parent-hash (zero-hash32)
                          :gas-limit 50000
                          :logs-bloom (bad-logs-bloom)))
      (assert-rejected-header
       (make-block-header :number 0
                          :parent-hash (zero-hash32)
                          :gas-limit 50000
                          :gas-used 1)))))

(deftest execute-and-commit-block-rolls-back-intra-transaction-error
  (let* ((store (make-engine-payload-memory-store))
         (state (make-state-db))
         (sender
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient
           (address-from-hex "0x0000000000000000000000000000000000000002"))
         (transaction
           (make-legacy-transaction :nonce 0
                                    :gas-price 1
                                    :gas-limit 21000
                                    :to recipient
                                    :value 10))
         (header (make-block-header :number 0
                                    :parent-hash (zero-hash32)
                                    :gas-limit 50000)))
    (state-db-set-account state sender
                          (make-state-account :balance 1))
    (signals error
      (execute-and-commit-block
       store state
       (lambda ()
         (execute-legacy-block state sender (list transaction)
                               :header header))))
    (is (null (chain-store-block-by-number store 0)))
    (is (null (chain-store-transaction-location
               store
               (transaction-hash transaction))))
    (is (= 1
           (state-account-balance
            (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest execute-and-commit-signed-block-recovers-sender-and-stores-indexes
  (let* ((store (make-engine-payload-memory-store))
         (state (make-state-db))
         (sender
           (address-from-hex "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (transaction
           (make-legacy-transaction
            :nonce 9
            :gas-price 20000000000
            :gas-limit 21000
            :to recipient
            :value 1000000000000000000
            :v 37
            :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
            :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
         (header (make-block-header :number 0
                                    :parent-hash (zero-hash32)
                                    :gas-limit 50000)))
    (state-db-set-account state sender
                          (make-state-account
                           :nonce 9
                           :balance 2000000000000000000))
    (multiple-value-bind (block receipts)
        (execute-and-commit-signed-block
         store state (list transaction)
         :expected-chain-id 1
         :header header)
      (is (= 1 (length receipts)))
      (is (eq block (chain-store-block-by-number store 0)))
      (is (typep (chain-store-transaction-location
                  store
                  (transaction-hash transaction))
                 'engine-transaction-location))
      (is (= 10
             (chain-store-account-nonce store (block-hash block) sender)))
      (is (= 999580000000000000
             (chain-store-account-balance store (block-hash block) sender)))
      (is (= 1000000000000000000
             (chain-store-account-balance store (block-hash block)
                                          recipient))))))

(deftest execute-and-commit-signed-block-rejects-wrong-chain-id-atomically
  (let* ((store (make-engine-payload-memory-store))
         (state (make-state-db))
         (sender
           (address-from-hex "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (transaction
           (make-legacy-transaction
            :nonce 9
            :gas-price 20000000000
            :gas-limit 21000
            :to recipient
            :value 1000000000000000000
            :v 37
            :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
            :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
         (header (make-block-header :number 0
                                    :parent-hash (zero-hash32)
                                    :gas-limit 50000)))
    (state-db-set-account state sender
                          (make-state-account
                           :nonce 9
                           :balance 2000000000000000000))
    (signals transaction-validation-error
      (execute-and-commit-signed-block
       store state (list transaction)
       :expected-chain-id 2
       :header header))
    (is (null (chain-store-block-by-number store 0)))
    (is (null (chain-store-transaction-location
               store
               (transaction-hash transaction))))
    (is (= 9
           (state-account-nonce
            (state-db-get-account state sender))))
    (is (= 2000000000000000000
           (state-account-balance
            (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest chain-store-set-canonical-head-rewrites-number-indexes
  (let* ((store (make-engine-payload-memory-store))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :extra-data #(0))))
         (genesis-hash (block-hash genesis)))
    (flet ((child-block (number parent-hash marker)
             (make-block
              :header
              (make-block-header :number number
                                 :parent-hash parent-hash
                                 :extra-data (vector marker)))))
      (let* ((a1 (child-block 1 genesis-hash 1))
             (a2-header (block-header (child-block 2 (block-hash a1) 2)))
             (b1 (child-block 1 genesis-hash 11))
             (b2 (child-block 2 (block-hash b1) 12))
             (a2-transaction
               (make-legacy-transaction
                :nonce 1
                :gas-price 2
                :gas-limit 21000
                :value 3
                :data #(1)
                :v 27
                :r 4
                :s 5))
             (b3-transaction
               (make-legacy-transaction
                :nonce 2
                :gas-price 3
                :gas-limit 21000
                :value 4
                :data #(2)
                :v 27
                :r 6
                :s 7))
             (a2-receipt
               (make-receipt :status 1 :cumulative-gas-used 21000))
             (b3-receipt
               (make-receipt :status 1 :cumulative-gas-used 21000))
             (b3
               (make-block
                :header
                (make-block-header :number 3
                                   :parent-hash (block-hash b2)
                                   :extra-data #(13))
                :transactions (list b3-transaction)
                :receipts (list b3-receipt)))
             (a2
               (make-block
                :header a2-header
                :transactions (list a2-transaction)
                :receipts (list a2-receipt)))
             (a1-hash (block-hash a1))
             (a2-hash (block-hash a2))
             (b1-hash (block-hash b1))
             (b2-hash (block-hash b2))
             (b3-hash (block-hash b3))
             (a2-transaction-hash (transaction-hash a2-transaction))
             (b3-transaction-hash (transaction-hash b3-transaction)))
        (dolist (block (list genesis a1 a2 b1 b2 b3))
          (chain-store-put-block store block))
        (is (eq a1 (chain-store-block-by-number store 1)))
        (is (eq a2 (chain-store-block-by-number store 2)))
        (is (null (chain-store-canonical-hash store 3)))
        (is (= 2 (chain-store-head-number store)))
        (is (eq a2 (chain-store-latest-block store)))
        (is (typep (chain-store-transaction-location
                    store a2-transaction-hash)
                   'engine-transaction-location))
        (is (null (chain-store-transaction-location
                   store b3-transaction-hash)))
        (is (eq b3 (chain-store-known-block store b3-hash)))
        (is (eq b3
                (chain-store-set-canonical-head store b3-hash)))
        (is (eq b1 (chain-store-block-by-number store 1)))
        (is (eq b2 (chain-store-block-by-number store 2)))
        (is (eq b3 (chain-store-block-by-number store 3)))
        (is (string= (hash32-to-hex b1-hash)
                     (hash32-to-hex
                      (chain-store-canonical-hash store 1))))
        (is (string= (hash32-to-hex b2-hash)
                     (hash32-to-hex
                      (chain-store-canonical-hash store 2))))
        (is (string= (hash32-to-hex b3-hash)
                     (hash32-to-hex
                      (chain-store-canonical-hash store 3))))
        (is (eq a1 (chain-store-known-block store a1-hash)))
        (is (eq a2 (chain-store-known-block store a2-hash)))
        (is (null (chain-store-transaction-location
                   store a2-transaction-hash)))
        (let ((location
                (chain-store-transaction-location
                 store b3-transaction-hash)))
          (is (typep location 'engine-transaction-location))
          (is (eq b3 (engine-transaction-location-block location)))
          (is (eq b3-transaction
                  (engine-transaction-location-transaction location)))
          (is (eq b3-receipt
                  (engine-transaction-location-receipt location))))
        (is (eq b3 (chain-store-latest-block store)))
        (is (= 3 (chain-store-block-tag-number store "latest")))))))

(deftest engine-new-payload-memory-status-caches-invalid-ancestors
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (config (make-chain-config :london-block 0))
         (parent-header (make-block-header
                         :parent-hash (zero-hash32)
                         :beneficiary address
                         :state-root +empty-trie-hash+
                         :mix-hash (zero-hash32)
                         :number 41
                         :gas-limit 50000
                         :gas-used 25000
                         :timestamp 98
                         :base-fee-per-gas 100))
         (parent-block (make-block :header parent-header))
         (invalid-child-header (make-block-header
                                :parent-hash (block-hash parent-block)
                                :beneficiary address
                                :state-root +empty-trie-hash+
                                :mix-hash (zero-hash32)
                                :number 42
                                :gas-limit 50000
                                :gas-used 0
                                :timestamp 98
                                :base-fee-per-gas 100))
         (invalid-child-block (make-block :header invalid-child-header))
         (grandchild-header (make-block-header
                             :parent-hash (block-hash invalid-child-block)
                             :beneficiary address
                             :state-root +empty-trie-hash+
                             :mix-hash (zero-hash32)
                             :number 43
                             :gas-limit 50000
                             :gas-used 0
                             :timestamp 100
                             :base-fee-per-gas 100))
         (grandchild-block (make-block :header grandchild-header))
         (invalid-child-payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data invalid-child-block)))
         (grandchild-payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data grandchild-block)))
         (store (make-engine-payload-memory-store)))
    (engine-payload-store-put-block store parent-block :state-available-p t)
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status
         store 1 invalid-child-payload config)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (string= (hash32-to-hex (block-hash parent-block))
                   (hash32-to-hex
                    (payload-status-latest-valid-hash status))))
      (is (not block))
      (is (engine-payload-store-invalid-block
           store
           (block-hash invalid-child-block))))
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status
         store 1 grandchild-payload config)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (string= (hash32-to-hex (block-hash parent-block))
                   (hash32-to-hex
                    (payload-status-latest-valid-hash status))))
      (is (string= "links to previously rejected block"
                   (payload-status-validation-error status)))
      (is (not block))
      (let ((cached-head
              (engine-payload-store-invalid-block
               store
               (block-hash grandchild-block))))
        (is cached-head)
        (is (string= (hash32-to-hex (block-hash invalid-child-block))
                     (hash32-to-hex (block-hash cached-head))))))))

(deftest engine-rpc-handle-request-dispatches-new-payload
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (payload-object (payload)
             (list
              (cons "parentHash"
                    (hash32-to-hex (executable-data-parent-hash payload)))
              (cons "feeRecipient"
                    (address-to-hex (executable-data-fee-recipient payload)))
              (cons "stateRoot"
                    (hash32-to-hex (executable-data-state-root payload)))
              (cons "receiptsRoot"
                    (hash32-to-hex (executable-data-receipts-root payload)))
              (cons "logsBloom"
                    (bytes-to-hex (executable-data-logs-bloom payload)))
              (cons "prevRandao"
                    (hash32-to-hex (executable-data-random payload)))
              (cons "blockNumber"
                    (quantity-to-hex (executable-data-number payload)))
              (cons "gasLimit"
                    (quantity-to-hex (executable-data-gas-limit payload)))
              (cons "gasUsed"
                    (quantity-to-hex (executable-data-gas-used payload)))
              (cons "timestamp"
                    (quantity-to-hex (executable-data-timestamp payload)))
              (cons "extraData"
                    (bytes-to-hex (executable-data-extra-data payload)))
              (cons "baseFeePerGas"
                    (quantity-to-hex
                     (executable-data-base-fee-per-gas payload)))
              (cons "blockHash"
                    (hash32-to-hex (executable-data-block-hash payload)))
              (cons "transactions"
                    (mapcar #'bytes-to-hex
                            (executable-data-transactions payload))))))
    (let* ((address
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (config (make-chain-config :london-block 0))
           (parent-header (make-block-header
                           :parent-hash (zero-hash32)
                           :beneficiary address
                           :state-root +empty-trie-hash+
                           :mix-hash (zero-hash32)
                           :number 1
                           :gas-limit 50000
                           :gas-used 25000
                           :timestamp 10
                           :base-fee-per-gas 100))
           (parent-block (make-block :header parent-header))
           (child-header (make-block-header
                          :parent-hash (block-hash parent-block)
                          :beneficiary address
                          :state-root +empty-trie-hash+
                          :receipts-root +empty-trie-hash+
                          :logs-bloom (make-byte-vector 256)
                          :mix-hash (zero-hash32)
                          :number 2
                          :gas-limit 50000
                          :gas-used 0
                          :timestamp 11
                          :base-fee-per-gas 100))
           (child-block (make-block :header child-header))
           (payload
             (execution-payload-envelope-execution-payload
              (block-to-executable-data child-block)))
           (store (make-engine-payload-memory-store))
           (request
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 7)
                   (cons "method" "engine_newPayloadV1")
                   (cons "params" (list (payload-object payload))))))
      (engine-payload-store-put-block store parent-block :state-available-p t)
      (let* ((response (engine-rpc-handle-request request store config))
             (result (field response "result")))
        (is (string= "2.0" (field response "jsonrpc")))
        (is (= 7 (field response "id")))
        (is (string= +payload-status-valid+ (field result "status")))
        (is (string= (hash32-to-hex (block-hash child-block))
                     (field result "latestValidHash")))
        (is (engine-payload-store-known-block store
                                              (block-hash child-block))))
      (let* ((response
               (engine-rpc-handle-request-string
                "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"engine_nope\",\"params\":[]}"
                store
                config))
             (error (field response "error")))
        (is (= -32601 (field error "code"))))
      (let* ((response-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"engine_nope\",\"params\":[]}"
                store
                config))
             (response (parse-json response-json))
             (error (field response "error")))
        (is (string= "2.0" (field response "jsonrpc")))
        (is (= 9 (field response "id")))
        (is (= -32601 (field error "code")))
        (is (string= "Method not found" (field error "message"))))
      (let* ((batch-json
               (engine-rpc-handle-request-json
                "[{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"engine_nope\",\"params\":[]},7]"
                store
                config))
             (responses (parse-json batch-json))
             (first-error (field (first responses) "error"))
             (second-error (field (second responses) "error")))
        (is (= 2 (length responses)))
        (is (= 10 (field (first responses) "id")))
        (is (= -32601 (field first-error "code")))
        (is (not (field (second responses) "id")))
        (is (= -32600 (field second-error "code")))))))

(deftest engine-rpc-forkchoice-updated-v1-reports-memory-status
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (forkchoice-state-object
               (head &key
                     (safe (zero-hash32))
                     (finalized (zero-hash32)))
             (list (cons "headBlockHash" (hash32-to-hex head))
                   (cons "safeBlockHash" (hash32-to-hex safe))
                   (cons "finalizedBlockHash"
                         (hash32-to-hex finalized))))
           (payload-attributes-object ()
             (list (cons "timestamp" "0x1")
                   (cons "prevRandao" (hash32-to-hex (zero-hash32)))
                   (cons "suggestedFeeRecipient"
                         (address-to-hex (zero-address)))))
           (invalid-payload-attributes-object ()
             (list (cons "timestamp" "0x0")
                   (cons "prevRandao" (hash32-to-hex (zero-hash32)))
                   (cons "suggestedFeeRecipient"
                         (address-to-hex (zero-address)))))
           (forkchoice-request (id state &optional payload-attributes)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV1")
                   (cons "params" (list state payload-attributes)))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (known-block (make-block))
           (known-hash (block-hash known-block))
           (finalized-block
             (make-block
              :header (make-block-header :number 30
                                         :parent-hash (zero-hash32)
                                         :timestamp 30
                                         :gas-limit 30000000)))
           (safe-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash finalized-block)
                                         :number 31
                                         :timestamp 31
                                         :gas-limit 30000000)))
           (head-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash safe-block)
                                         :number 32
                                         :timestamp 32
                                         :gas-limit 30000000)))
           (non-head-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash finalized-block)
                                         :number 33
                                         :timestamp 33
                                         :gas-limit 30000000)))
           (unknown-hash
             (hash32-from-hex
              "0x1111111111111111111111111111111111111111111111111111111111111111")))
      (engine-payload-store-put-block
       store known-block :state-available-p t)
      (engine-payload-store-put-block
       store finalized-block :state-available-p t)
      (engine-payload-store-put-block
       store safe-block :state-available-p t)
      (engine-payload-store-put-block
       store head-block :state-available-p t)
      (engine-payload-store-put-block
       store non-head-block :state-available-p t)
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 17
                 (forkchoice-state-object known-hash)
                 (payload-attributes-object))
                store
                config))
             (result (field response "result"))
             (payload-status (field result "payloadStatus")))
        (is (= 17 (field response "id")))
        (is (string= +payload-status-valid+
                     (field payload-status "status")))
        (is (string= (hash32-to-hex known-hash)
                     (field payload-status "latestValidHash")))
        (is (stringp (field result "payloadId")))
        (is (= 18 (length (field result "payloadId"))))
        (let* ((get-payload-response
                 (engine-rpc-handle-request
                  (list (cons "jsonrpc" "2.0")
                        (cons "id" 21)
                        (cons "method" "engine_getPayloadV1")
                        (cons "params" (list (field result "payloadId"))))
                  store
                  config))
               (payload (field get-payload-response "result")))
          (is (= 21 (field get-payload-response "id")))
          (is (string= (hash32-to-hex known-hash)
                       (field payload "parentHash")))
          (is (= 1 (hex-to-quantity (field payload "blockNumber"))))
          (is (string= "0x1" (field payload "timestamp")))
          (is (string= (hash32-to-hex (zero-hash32))
                       (field payload "prevRandao")))
          (is (string= (address-to-hex (zero-address))
                       (field payload "feeRecipient")))
          (is (not (field payload "transactions"))))
        (let* ((get-payload-v2-response
                 (engine-rpc-handle-request
                  (list (cons "jsonrpc" "2.0")
                        (cons "id" 22)
                        (cons "method" "engine_getPayloadV2")
                        (cons "params" (list (field result "payloadId"))))
                  store
                  config))
               (envelope (field get-payload-v2-response "result"))
               (payload (field envelope "executionPayload")))
          (is (= 22 (field get-payload-v2-response "id")))
          (is (string= "0x0" (field envelope "blockValue")))
          (is (string= (hash32-to-hex known-hash)
                       (field payload "parentHash")))
          (is (= 1 (hex-to-quantity (field payload "blockNumber"))))
          (is (not (field payload "transactions"))))
        (let* ((checkpoint-response
                 (engine-rpc-handle-request
                  (forkchoice-request
                   28
                   (forkchoice-state-object
                    (block-hash head-block)
                    :safe (block-hash safe-block)
                    :finalized (block-hash finalized-block)))
                  store
                  config))
               (checkpoint-status
                 (field (field checkpoint-response "result") "payloadStatus"))
               (safe-header-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":29,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"safe\"]}"
                   store
                   config)))
               (finalized-header-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":30,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"finalized\"]}"
                   store
                   config)))
               (latest-header-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":31,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"latest\"]}"
                   store
                   config)))
               (pending-header-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":32,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"pending\"]}"
                   store
                   config)))
               (block-number-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":33,\"method\":\"eth_blockNumber\",\"params\":[]}"
                   store
                   config))))
          (is (= 28 (field checkpoint-response "id")))
          (is (string= +payload-status-valid+
                       (field checkpoint-status "status")))
          (is (string= (quantity-to-hex 32)
                       (field (field latest-header-response "result")
                              "number")))
          (is (string= (quantity-to-hex 32)
                       (field (field pending-header-response "result")
                              "number")))
          (is (string= (quantity-to-hex 32)
                       (field block-number-response "result")))
          (is (string= (quantity-to-hex 31)
                       (field (field safe-header-response "result")
                              "number")))
          (is (string= (quantity-to-hex 30)
                       (field (field finalized-header-response "result")
                              "number"))))
      (let* ((get-payload-response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 25)
                      (cons "method" "engine_getPayloadV1")
                      (cons "params" (list "0x0200000000000000")))
                store
                config))
             (error (field get-payload-response "error")))
        (is (= 25 (field get-payload-response "id")))
        (is (= -38001 (field error "code")))
        (is (string= "Unknown payload" (field error "message"))))
      (let* ((get-payload-response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 27)
                      (cons "method" "engine_getPayloadV2")
                      (cons "params" (list "0x0200000000000000")))
                store
                config))
             (error (field get-payload-response "error")))
        (is (= 27 (field get-payload-response "id")))
        (is (= -38001 (field error "code")))
        (is (string= "Unknown payload" (field error "message"))))
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 26
                 (forkchoice-state-object known-hash)
                 (invalid-payload-attributes-object))
                store
                config))
             (error (field response "error")))
        (is (= 26 (field response "id")))
        (is (= -38003 (field error "code")))
        (is (string= "Payload attributes timestamp must be greater than parent timestamp"
                     (field error "message"))))
      (engine-rpc-handle-request
       (forkchoice-request
        36
        (forkchoice-state-object
         (block-hash head-block)
         :safe (block-hash safe-block)
         :finalized (block-hash finalized-block)))
       store
       config)
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 18
                 (forkchoice-state-object unknown-hash))
                store
                config))
             (payload-status
               (field (field response "result") "payloadStatus")))
        (is (string= +payload-status-syncing+
                     (field payload-status "status")))
        (is (not (field payload-status "latestValidHash"))))
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 19
                 (forkchoice-state-object (zero-hash32)))
                store
                config))
             (payload-status
               (field (field response "result") "payloadStatus")))
        (is (string= +payload-status-invalid+
                     (field payload-status "status")))
        (is (string= "forkchoice head block hash is zero"
                     (field payload-status "validationError"))))
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 22
                 (forkchoice-state-object known-hash :safe unknown-hash))
                store
                config))
             (error (field response "error")))
        (is (= -38002 (field error "code")))
        (is (string= "forkchoice safe block is not available"
                     (field error "message"))))
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 34
                 (forkchoice-state-object
                  (block-hash head-block)
                  :safe (block-hash non-head-block)))
                store
                config))
             (error (field response "error")))
        (is (= -38002 (field error "code")))
        (is (string= "forkchoice safe block is not an ancestor of head"
                     (field error "message")))
        (is (eq safe-block (chain-store-safe-block store))))
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 23
                 (forkchoice-state-object
                  known-hash :finalized unknown-hash))
                store
                config))
             (error (field response "error")))
        (is (= -38002 (field error "code")))
        (is (string= "forkchoice finalized block is not available"
                     (field error "message"))))
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 35
                 (forkchoice-state-object
                  (block-hash head-block)
                  :finalized (block-hash non-head-block)))
                store
                config))
             (error (field response "error")))
        (is (= -38002 (field error "code")))
        (is (string= "forkchoice finalized block is not an ancestor of head"
                     (field error "message")))
        (is (eq finalized-block (chain-store-finalized-block store))))
      (let* ((bad-state
               (list (cons "headBlockHash" (hash32-to-hex known-hash))))
             (response
               (engine-rpc-handle-request
                (forkchoice-request 24 bad-state)
                store
                config))
             (error (field response "error")))
        (is (= -32602 (field error "code"))))))))

(deftest engine-rpc-forkchoice-updated-v2-prepares-withdrawal-payload
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (forkchoice-state-object
               (head &key
                     (safe (zero-hash32))
                     (finalized (zero-hash32)))
             (list (cons "headBlockHash" (hash32-to-hex head))
                   (cons "safeBlockHash" (hash32-to-hex safe))
                   (cons "finalizedBlockHash"
                         (hash32-to-hex finalized))))
           (withdrawal-object ()
             (list (cons "index" "0x1")
                   (cons "validatorIndex" "0x2")
                   (cons "address" (address-to-hex (zero-address)))
                   (cons "amount" "0x3")))
           (payload-attributes-object ()
             (list (cons "timestamp" "0x1")
                   (cons "prevRandao" (hash32-to-hex (zero-hash32)))
                   (cons "suggestedFeeRecipient"
                         (address-to-hex (zero-address)))
                   (cons "withdrawals" (list (withdrawal-object)))))
           (forkchoice-request (id state payload-attributes)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV2")
                   (cons "params" (list state payload-attributes)))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (known-block (make-block))
           (known-hash (block-hash known-block)))
      (engine-payload-store-put-block
       store known-block :state-available-p t)
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 28
                 (forkchoice-state-object known-hash)
                 (payload-attributes-object))
                store
                config))
             (result (field response "result"))
             (payload-status (field result "payloadStatus"))
             (payload-id (field result "payloadId")))
        (is (= 28 (field response "id")))
        (is (string= +payload-status-valid+
                     (field payload-status "status")))
        (is (stringp payload-id))
        (is (string= "02" (subseq payload-id 2 4)))
        (let* ((get-payload-response
                 (engine-rpc-handle-request
                  (list (cons "jsonrpc" "2.0")
                        (cons "id" 29)
                        (cons "method" "engine_getPayloadV2")
                        (cons "params" (list payload-id)))
                  store
                  config))
               (envelope (field get-payload-response "result"))
               (payload (field envelope "executionPayload"))
               (withdrawals (field payload "withdrawals"))
               (withdrawal (first withdrawals)))
          (is (= 29 (field get-payload-response "id")))
          (is (string= "0x0" (field envelope "blockValue")))
          (is (string= (hash32-to-hex known-hash)
                       (field payload "parentHash")))
          (is (= 1 (hex-to-quantity (field payload "blockNumber"))))
          (is (= 1 (length withdrawals)))
          (is (string= "0x1" (field withdrawal "index")))
          (is (string= "0x2" (field withdrawal "validatorIndex")))
          (is (string= (address-to-hex (zero-address))
                       (field withdrawal "address")))
          (is (string= "0x3" (field withdrawal "amount"))))))))

(deftest engine-rpc-forkchoice-updated-v3-prepares-cancun-payload
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (forkchoice-state-object
               (head &key
                     (safe (zero-hash32))
                     (finalized (zero-hash32)))
             (list (cons "headBlockHash" (hash32-to-hex head))
                   (cons "safeBlockHash" (hash32-to-hex safe))
                   (cons "finalizedBlockHash"
                         (hash32-to-hex finalized))))
           (withdrawal-object ()
             (list (cons "index" "0x4")
                   (cons "validatorIndex" "0x5")
                   (cons "address" (address-to-hex (zero-address)))
                   (cons "amount" "0x6")))
           (payload-attributes-object (parent-beacon-root)
             (list (cons "timestamp" "0x1")
                   (cons "prevRandao" (hash32-to-hex (zero-hash32)))
                   (cons "suggestedFeeRecipient"
                         (address-to-hex (zero-address)))
                   (cons "withdrawals" (list (withdrawal-object)))
                   (cons "parentBeaconBlockRoot"
                         (hash32-to-hex parent-beacon-root))))
           (forkchoice-request (id state payload-attributes)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV3")
                   (cons "params" (list state payload-attributes)))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (known-block (make-block))
           (known-hash (block-hash known-block))
           (parent-beacon-root
             (hash32-from-hex
              "0x3333333333333333333333333333333333333333333333333333333333333333")))
      (engine-payload-store-put-block
       store known-block :state-available-p t)
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 30
                 (forkchoice-state-object known-hash)
                 (payload-attributes-object parent-beacon-root))
                store
                config))
             (result (field response "result"))
             (payload-status (field result "payloadStatus"))
             (payload-id (field result "payloadId"))
             (prepared-payload
               (engine-payload-store-prepared-payload
                store (hex-to-bytes payload-id)))
             (prepared-header
               (block-header
                (engine-prepared-payload-block prepared-payload))))
        (is (= 30 (field response "id")))
        (is (string= +payload-status-valid+
                     (field payload-status "status")))
        (is (stringp payload-id))
        (is (string= "03" (subseq payload-id 2 4)))
        (is (string= (hash32-to-hex parent-beacon-root)
                     (hash32-to-hex
                      (block-header-parent-beacon-root prepared-header))))
        (let* ((get-payload-response
                 (engine-rpc-handle-request
                  (list (cons "jsonrpc" "2.0")
                        (cons "id" 31)
                        (cons "method" "engine_getPayloadV3")
                        (cons "params" (list payload-id)))
                  store
                  config))
               (envelope (field get-payload-response "result"))
               (payload (field envelope "executionPayload"))
               (bundle (field envelope "blobsBundle"))
               (withdrawals (field payload "withdrawals")))
          (is (= 31 (field get-payload-response "id")))
          (is (eq :false (field envelope "shouldOverrideBuilder")))
          (is (string= "0x0" (field payload "blobGasUsed")))
          (is (string= "0x0" (field payload "excessBlobGas")))
          (is (= 1 (length withdrawals)))
          (is (listp (field bundle "commitments")))
          (is (listp (field bundle "proofs")))
          (is (listp (field bundle "blobs"))))))))

(deftest engine-rpc-forkchoice-updated-v4-prepares-amsterdam-payload
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (forkchoice-state-object
               (head &key
                     (safe (zero-hash32))
                     (finalized (zero-hash32)))
             (list (cons "headBlockHash" (hash32-to-hex head))
                   (cons "safeBlockHash" (hash32-to-hex safe))
                   (cons "finalizedBlockHash"
                         (hash32-to-hex finalized))))
           (withdrawal-object ()
             (list (cons "index" "0x7")
                   (cons "validatorIndex" "0x8")
                   (cons "address" (address-to-hex (zero-address)))
                   (cons "amount" "0x9")))
           (payload-attributes-object (parent-beacon-root)
             (list (cons "timestamp" "0x1")
                   (cons "prevRandao" (hash32-to-hex (zero-hash32)))
                   (cons "suggestedFeeRecipient"
                         (address-to-hex (zero-address)))
                   (cons "withdrawals" (list (withdrawal-object)))
                   (cons "parentBeaconBlockRoot"
                         (hash32-to-hex parent-beacon-root))
                   (cons "slotNumber" "0x2a")))
           (forkchoice-request (id state payload-attributes)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV4")
                   (cons "params" (list state payload-attributes)))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (known-block (make-block))
           (known-hash (block-hash known-block))
           (parent-beacon-root
             (hash32-from-hex
              "0x4444444444444444444444444444444444444444444444444444444444444444")))
      (engine-payload-store-put-block
       store known-block :state-available-p t)
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 32
                 (forkchoice-state-object known-hash)
                 (payload-attributes-object parent-beacon-root))
                store
                config))
             (result (field response "result"))
             (payload-status (field result "payloadStatus"))
             (payload-id (field result "payloadId"))
             (prepared-payload
               (engine-payload-store-prepared-payload
                store (hex-to-bytes payload-id)))
             (prepared-header
               (block-header
                (engine-prepared-payload-block prepared-payload))))
        (is (= 32 (field response "id")))
        (is (string= +payload-status-valid+
                     (field payload-status "status")))
        (is (string= "04" (subseq payload-id 2 4)))
        (is (= 42 (block-header-slot-number prepared-header)))
        (let* ((get-payload-response
                 (engine-rpc-handle-request
                  (list (cons "jsonrpc" "2.0")
                        (cons "id" 33)
                        (cons "method" "engine_getPayloadV4")
                        (cons "params" (list payload-id)))
                  store
                  config))
               (envelope (field get-payload-response "result"))
               (payload (field envelope "executionPayload"))
               (bundle (field envelope "blobsBundle"))
               (withdrawals (field payload "withdrawals")))
          (is (= 33 (field get-payload-response "id")))
          (is (eq :false (field envelope "shouldOverrideBuilder")))
          (is (string= (quantity-to-hex 42) (field payload "slotNumber")))
          (is (string= "0x0" (field payload "blobGasUsed")))
          (is (string= "0x0" (field payload "excessBlobGas")))
          (is (= 1 (length withdrawals)))
          (is (listp (field bundle "commitments")))
          (is (listp (field bundle "proofs")))
          (is (listp (field bundle "blobs"))))))))

(deftest engine-rpc-get-payload-v3-returns-cancun-envelope
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((payload-id #(3 0 0 0 0 0 0 1))
           (block
             (make-block
              :header
              (make-block-header :number 7
                                 :timestamp 12
                                 :blob-gas-used 0
                                 :excess-blob-gas 0)))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-prepared-payload
       store
       (make-engine-prepared-payload
        :payload-id payload-id
        :version 3
        :block block))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 37)
                      (cons "method" "engine_getPayloadV3")
                      (cons "params" (list (bytes-to-hex payload-id))))
                store
                config))
             (envelope (field response "result"))
             (payload (field envelope "executionPayload"))
             (bundle (field envelope "blobsBundle")))
        (is (= 37 (field response "id")))
        (is (string= "0x0" (field envelope "blockValue")))
        (is (eq :false (field envelope "shouldOverrideBuilder")))
        (is (string= "0x0" (field payload "blobGasUsed")))
        (is (string= "0x0" (field payload "excessBlobGas")))
        (is (listp (field bundle "commitments")))
        (is (listp (field bundle "proofs")))
        (is (listp (field bundle "blobs")))
        (is (= 0 (length (field bundle "commitments")))))
      (let* ((response-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":38,\"method\":\"engine_getPayloadV3\",\"params\":[\"0x0300000000000001\"]}"
                store
                config)))
        (is (search "\"shouldOverrideBuilder\":false" response-json))))))

(deftest engine-rpc-get-payload-v4-returns-prague-execution-requests
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((payload-id #(4 0 0 0 0 0 0 1))
           (requests (list #(#x00 #xaa) #(#x01 #xbb)))
           (block
             (make-block
              :header
              (make-block-header :number 8
                                 :timestamp 13
                                 :blob-gas-used 0
                                 :excess-blob-gas 0)
              :requests requests))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-prepared-payload
       store
       (make-engine-prepared-payload
        :payload-id payload-id
        :version 4
        :block block))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 39)
                      (cons "method" "engine_getPayloadV4")
                      (cons "params" (list (bytes-to-hex payload-id))))
                store
                config))
             (envelope (field response "result"))
             (payload (field envelope "executionPayload"))
             (bundle (field envelope "blobsBundle"))
             (encoded-requests (field envelope "executionRequests")))
        (is (= 39 (field response "id")))
        (is (eq :false (field envelope "shouldOverrideBuilder")))
        (is (string= "0x0" (field payload "blobGasUsed")))
        (is (string= "0x0" (field payload "excessBlobGas")))
        (is (= 0 (length (field bundle "blobs"))))
        (is (= 2 (length encoded-requests)))
        (is (string= "0x00aa" (first encoded-requests)))
        (is (string= "0x01bb" (second encoded-requests)))))))

(deftest engine-rpc-get-payload-v5-returns-osaka-blobs-bundle
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((payload-id #(5 0 0 0 0 0 0 1))
           (requests (list #(#x02 #xcc)))
           (sidecar
             (make-blob-sidecar
              :blobs (list #(#x03 #xdd))
              :commitments (list #(#x04 #xee))
              :proofs (list #(#x05 #xff) #(#x06 #x11))))
           (block
             (make-block
              :header
              (make-block-header :number 9
                                 :timestamp 14
                                 :blob-gas-used 0
                                 :excess-blob-gas 0)
              :requests requests))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-prepared-payload
       store
       (make-engine-prepared-payload
        :payload-id payload-id
        :version 5
        :block block
        :blobs-bundle sidecar))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 40)
                      (cons "method" "engine_getPayloadV5")
                      (cons "params" (list (bytes-to-hex payload-id))))
                store
                config))
             (envelope (field response "result"))
             (bundle (field envelope "blobsBundle")))
        (is (= 40 (field response "id")))
        (is (eq :false (field envelope "shouldOverrideBuilder")))
        (is (string= "0x02cc"
                     (first (field envelope "executionRequests"))))
        (is (string= "0x04ee" (first (field bundle "commitments"))))
        (is (string= "0x05ff" (first (field bundle "proofs"))))
        (is (string= "0x0611" (second (field bundle "proofs"))))
        (is (string= "0x03dd" (first (field bundle "blobs"))))))))

(deftest engine-rpc-get-payload-v6-returns-amsterdam-fields
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((payload-id #(6 0 0 0 0 0 0 1))
           (sidecar
             (make-blob-sidecar
              :blobs (list #(#x07 #xaa))
              :commitments (list #(#x08 #xbb))
              :proofs (list #(#x09 #xcc))))
           (block
             (make-block
              :header
              (make-block-header :number 10
                                 :timestamp 15
                                 :blob-gas-used 0
                                 :excess-blob-gas 0
                                 :slot-number 42)
              :requests (list #(#x03 #xdd))
              :block-access-list '()))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-prepared-payload
       store
       (make-engine-prepared-payload
        :payload-id payload-id
        :version 6
        :block block
        :blobs-bundle sidecar))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 41)
                      (cons "method" "engine_getPayloadV6")
                      (cons "params" (list (bytes-to-hex payload-id))))
                store
                config))
             (envelope (field response "result"))
             (payload (field envelope "executionPayload"))
             (bundle (field envelope "blobsBundle")))
        (is (= 41 (field response "id")))
        (is (string= (quantity-to-hex 42) (field payload "slotNumber")))
        (is (string= (bytes-to-hex (block-encoded-block-access-list block))
                     (field payload "blockAccessList")))
        (is (string= "0x03dd"
                     (first (field envelope "executionRequests"))))
        (is (string= "0x08bb" (first (field bundle "commitments"))))
        (is (string= "0x09cc" (first (field bundle "proofs"))))
        (is (string= "0x07aa" (first (field bundle "blobs"))))))))

(deftest engine-rpc-get-blobs-v1-returns-blobs-and-proofs
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((blob (make-byte-vector +blob-byte-size+))
           (commitment (make-byte-vector +kzg-commitment-size+))
           (proof (make-byte-vector +kzg-proof-size+))
           (unknown-hash
             (make-hash32 (make-byte-vector 32 :initial-element #x11)))
           (sidecar nil)
           (versioned-hash nil)
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (setf (aref blob 0) #xaa
            (aref commitment 0) #xbb
            (aref proof 0) #xcc
            sidecar (make-blob-sidecar
                     :blobs (list blob)
                     :commitments (list commitment)
                     :proofs (list proof))
            versioned-hash (first (blob-sidecar-versioned-hashes sidecar)))
      (engine-payload-store-put-blob-sidecar store sidecar)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 42)
                      (cons "method" "engine_getBlobsV1")
                      (cons "params"
                            (list (list (hash32-to-hex versioned-hash)
                                        (hash32-to-hex unknown-hash)))))
                store
                config))
             (result (field response "result"))
             (first-blob (first result)))
        (is (= 42 (field response "id")))
        (is (= 2 (length result)))
        (is (string= (bytes-to-hex blob) (field first-blob "blob")))
        (is (string= (bytes-to-hex proof) (field first-blob "proof")))
        (is (null (second result))))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 43)
                      (cons "method" "engine_getBlobsV1")
                      (cons "params"
                            (list
                             (loop repeat 129
                                   collect (hash32-to-hex unknown-hash)))))
                store
                config))
             (error (field response "error")))
        (is (= -38004 (field error "code")))
        (is (string= "The number of requested blobs must not exceed 128"
                     (field error "message")))))))

(deftest engine-rpc-get-blobs-v2-v3-return-cell-proofs
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((blob (make-byte-vector +blob-byte-size+))
           (commitment (make-byte-vector +kzg-commitment-size+))
           (proofs
             (loop for i below +cell-proofs-per-blob+
                   collect
                   (let ((proof (make-byte-vector +kzg-proof-size+)))
                     (setf (aref proof 0) i)
                     proof)))
           (unknown-hash
             (make-hash32 (make-byte-vector 32 :initial-element #x22)))
           (sidecar nil)
           (versioned-hash nil)
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (setf (aref blob 0) #xaa
            (aref commitment 0) #xbb
            sidecar (make-blob-sidecar
                     :blobs (list blob)
                     :commitments (list commitment)
                     :proofs proofs)
            versioned-hash (first (blob-sidecar-versioned-hashes sidecar)))
      (engine-payload-store-put-blob-sidecar store sidecar)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 44)
                      (cons "method" "engine_getBlobsV2")
                      (cons "params"
                            (list (list (hash32-to-hex versioned-hash)))))
                store
                config))
             (result (field response "result"))
             (first-blob (first result))
             (encoded-proofs (field first-blob "proofs")))
        (is (= 44 (field response "id")))
        (is (= 1 (length result)))
        (is (string= (bytes-to-hex blob) (field first-blob "blob")))
        (is (= +cell-proofs-per-blob+ (length encoded-proofs)))
        (is (string= (bytes-to-hex (first proofs)) (first encoded-proofs)))
        (is (string= (bytes-to-hex (car (last proofs)))
                     (car (last encoded-proofs)))))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 45)
                      (cons "method" "engine_getBlobsV2")
                      (cons "params"
                            (list (list (hash32-to-hex versioned-hash)
                                        (hash32-to-hex unknown-hash)))))
                store
                config)))
        (is (= 45 (field response "id")))
        (is (null (field response "result"))))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 46)
                      (cons "method" "engine_getBlobsV3")
                      (cons "params"
                            (list (list (hash32-to-hex versioned-hash)
                                        (hash32-to-hex unknown-hash)))))
                store
                config))
             (result (field response "result"))
             (first-blob (first result)))
        (is (= 46 (field response "id")))
        (is (= 2 (length result)))
        (is (string= (bytes-to-hex blob) (field first-blob "blob")))
        (is (string= (bytes-to-hex (first proofs))
                     (first (field first-blob "proofs"))))
        (is (null (second result)))))))

(deftest engine-rpc-get-payload-bodies-by-hash-v1-returns-bodies
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
           (withdrawal-address
             (address-from-hex "0x0000000000000000000000000000000000000003"))
           (transaction
             (make-legacy-transaction :nonce 1
                                      :gas-price 2
                                      :gas-limit 21000
                                      :to recipient
                                      :value 4
                                      :v 27
                                      :r 6
                                      :s 7))
           (withdrawal
             (make-withdrawal :index 1
                              :validator-index 2
                              :address withdrawal-address
                              :amount 3))
           (block (make-block :transactions (list transaction)
                              :withdrawals (list withdrawal)))
           (empty-withdrawals-block (make-block :withdrawals '()))
           (unknown-hash
             (hash32-from-hex
              "0x2222222222222222222222222222222222222222222222222222222222222222"))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (engine-payload-store-put-block
       store empty-withdrawals-block :state-available-p t)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 28)
                      (cons "method" "engine_getPayloadBodiesByHashV1")
                      (cons "params"
                            (list
                             (list (hash32-to-hex (block-hash block))
                                   (hash32-to-hex unknown-hash)
                                   (hash32-to-hex
                                    (block-hash empty-withdrawals-block))))))
                store
                config))
             (bodies (field response "result"))
             (first-body (first bodies))
             (third-body (third bodies)))
        (is (= 28 (field response "id")))
        (is (= 3 (length bodies)))
        (is (string= (bytes-to-hex (transaction-encoding transaction))
                     (first (field first-body "transactions"))))
        (is (= 1 (length (field first-body "withdrawals"))))
        (is (not (second bodies)))
        (is (not (field third-body "transactions")))
        (is (listp (field third-body "withdrawals")))
        (is (= 0 (length (field third-body "withdrawals")))))
      (let* ((too-many-hashes
               (loop repeat 1025 collect (hash32-to-hex (block-hash block))))
             (response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 29)
                      (cons "method" "engine_getPayloadBodiesByHashV1")
                      (cons "params" (list too-many-hashes)))
                store
                config))
             (error (field response "error")))
        (is (= -38004 (field error "code")))
        (is (string= "The number of requested bodies must not exceed 1024"
                     (field error "message")))))))

(deftest engine-rpc-get-payload-bodies-by-hash-v2-returns-block-access-list
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((plain-block (make-block))
           (bal-block (make-block :block-access-list '()))
           (unknown-hash
             (hash32-from-hex
              "0x3333333333333333333333333333333333333333333333333333333333333333"))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-block store plain-block :state-available-p t)
      (engine-payload-store-put-block store bal-block :state-available-p t)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 33)
                      (cons "method" "engine_getPayloadBodiesByHashV2")
                      (cons "params"
                            (list
                             (list (hash32-to-hex (block-hash plain-block))
                                   (hash32-to-hex (block-hash bal-block))
                                   (hash32-to-hex unknown-hash)))))
                store
                config))
             (bodies (field response "result"))
             (plain-body (first bodies))
             (bal-body (second bodies)))
        (is (= 33 (field response "id")))
        (is (= 3 (length bodies)))
        (is (not (field plain-body "blockAccessList")))
        (is (string= (bytes-to-hex (block-encoded-block-access-list bal-block))
                     (field bal-body "blockAccessList")))
        (is (not (third bodies)))))
    (let* ((too-many-hashes
             (loop repeat 1025 collect (hash32-to-hex (zero-hash32))))
           (response
             (engine-rpc-handle-request
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 34)
                    (cons "method" "engine_getPayloadBodiesByHashV2")
                    (cons "params" (list too-many-hashes)))
              (make-engine-payload-memory-store)
              (make-chain-config)))
           (error (field response "error")))
      (is (= -38004 (field error "code")))
      (is (string= "The number of requested bodies must not exceed 1024"
                   (field error "message"))))))

(deftest engine-rpc-get-payload-bodies-by-range-v1-returns-bodies
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (numbered-block (number &key transactions withdrawals)
             (make-block
              :header (make-block-header :number number
                                         :timestamp number)
              :transactions transactions
              :withdrawals withdrawals)))
    (let* ((recipient
             (address-from-hex "0x0000000000000000000000000000000000000004"))
           (transaction
             (make-legacy-transaction :nonce 2
                                      :gas-price 3
                                      :gas-limit 21000
                                      :to recipient
                                      :value 5
                                      :v 27
                                      :r 8
                                      :s 9))
           (block-1 (numbered-block 1 :transactions (list transaction)))
           (block-2 (numbered-block 2 :withdrawals '()))
           (block-4 (numbered-block 4 :transactions '()))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block-1 :state-available-p t)
      (engine-payload-store-put-block store block-2 :state-available-p t)
      (engine-payload-store-put-block store block-4 :state-available-p t)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 30)
                      (cons "method" "engine_getPayloadBodiesByRangeV1")
                      (cons "params" (list "0x1" "0x4")))
                store
                config))
             (bodies (field response "result"))
             (first-body (first bodies))
             (second-body (second bodies))
             (fourth-body (fourth bodies)))
        (is (= 30 (field response "id")))
        (is (= 4 (length bodies)))
        (is (string= (bytes-to-hex (transaction-encoding transaction))
                     (first (field first-body "transactions"))))
        (is (not (field first-body "withdrawals")))
        (is (not (field second-body "transactions")))
        (is (listp (field second-body "withdrawals")))
        (is (not (third bodies)))
        (is (not (field fourth-body "transactions"))))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 31)
                      (cons "method" "engine_getPayloadBodiesByRangeV1")
                      (cons "params" (list "0x0" "0x1")))
                store
                config))
             (error (field response "error")))
        (is (= -32602 (field error "code"))))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 32)
                      (cons "method" "engine_getPayloadBodiesByRangeV1")
                      (cons "params" (list 1 1025)))
                store
                config))
             (error (field response "error")))
        (is (= -38004 (field error "code")))
        (is (string= "The number of requested bodies must not exceed 1024"
                     (field error "message")))))))

(deftest engine-rpc-get-payload-bodies-by-range-v2-returns-block-access-list
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (numbered-block
               (number &key (block-access-list nil block-access-list-p))
             (let ((header (make-block-header :number number
                                              :timestamp number)))
               (if block-access-list-p
                   (make-block :header header
                               :block-access-list block-access-list)
                   (make-block :header header)))))
    (let* ((plain-block (numbered-block 1))
           (bal-block (numbered-block 2 :block-access-list '()))
           (tail-block (numbered-block 4 :block-access-list '()))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-block store plain-block :state-available-p t)
      (engine-payload-store-put-block store bal-block :state-available-p t)
      (engine-payload-store-put-block store tail-block :state-available-p t)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 35)
                      (cons "method" "engine_getPayloadBodiesByRangeV2")
                      (cons "params" (list "0x1" "0x4")))
                store
                config))
             (bodies (field response "result"))
             (plain-body (first bodies))
             (bal-body (second bodies))
             (tail-body (fourth bodies)))
        (is (= 35 (field response "id")))
        (is (= 4 (length bodies)))
        (is (not (field plain-body "blockAccessList")))
        (is (string= (bytes-to-hex (block-encoded-block-access-list bal-block))
                     (field bal-body "blockAccessList")))
        (is (not (third bodies)))
        (is (string= (bytes-to-hex (block-encoded-block-access-list tail-block))
                     (field tail-body "blockAccessList"))))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 36)
                      (cons "method" "engine_getPayloadBodiesByRangeV2")
                      (cons "params" (list "0x1" "0x401")))
                store
                config))
             (error (field response "error")))
        (is (= -38004 (field error "code")))
        (is (string= "The number of requested bodies must not exceed 1024"
                     (field error "message")))))))

(deftest engine-rpc-exchange-capabilities-advertises-supported-methods
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (request-json
             "{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"engine_exchangeCapabilities\",\"params\":[[\"engine_newPayloadV1\",\"engine_forkchoiceUpdatedV1\"]]}")
           (response (parse-json
                      (engine-rpc-handle-request-json
                       request-json store config)))
           (capabilities (field response "result")))
      (is (= 11 (field response "id")))
      (is (member "engine_newPayloadV1" capabilities :test #'string=))
      (is (member "engine_newPayloadV5" capabilities :test #'string=))
      (is (member "engine_forkchoiceUpdatedV1"
                  capabilities
                  :test #'string=))
      (is (member "engine_forkchoiceUpdatedV2"
                  capabilities
                  :test #'string=))
      (is (member "engine_forkchoiceUpdatedV3"
                  capabilities
                  :test #'string=))
      (is (member "engine_forkchoiceUpdatedV4"
                  capabilities
                  :test #'string=))
      (is (member "engine_getPayloadV1" capabilities :test #'string=))
      (is (member "engine_getPayloadV2" capabilities :test #'string=))
      (is (member "engine_getPayloadV3" capabilities :test #'string=))
      (is (member "engine_getPayloadV4" capabilities :test #'string=))
      (is (member "engine_getPayloadV5" capabilities :test #'string=))
      (is (member "engine_getPayloadV6" capabilities :test #'string=))
      (is (member "engine_getPayloadBodiesByHashV1"
                  capabilities
                  :test #'string=))
      (is (member "engine_getPayloadBodiesByHashV2"
                  capabilities
                  :test #'string=))
      (is (member "engine_getPayloadBodiesByRangeV1"
                  capabilities
                  :test #'string=))
      (is (member "engine_getPayloadBodiesByRangeV2"
                  capabilities
                  :test #'string=))
      (is (member "engine_getBlobsV1" capabilities :test #'string=))
      (is (member "engine_getBlobsV2" capabilities :test #'string=))
      (is (member "engine_getBlobsV3" capabilities :test #'string=))
      (is (member "engine_getClientVersionV1" capabilities :test #'string=))
      (is (member "engine_exchangeTransitionConfigurationV1"
                  capabilities
                  :test #'string=))
      (is (not (member "engine_exchangeCapabilities"
                       capabilities
                       :test #'string=))))
    (let* ((response (parse-json
                      (engine-rpc-handle-request-json
                       "{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"engine_exchangeCapabilities\",\"params\":[7]}"
                       (make-engine-payload-memory-store)
                       (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))))

(deftest engine-rpc-get-client-version-returns-local-identity
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((request-json
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":13,"
              "\"method\":\"engine_getClientVersionV1\","
              "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
              "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
           (response
             (parse-json
              (engine-rpc-handle-request-json
               request-json
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (versions (field response "result"))
           (local (first versions)))
      (is (= 13 (field response "id")))
      (is (= 1 (length versions)))
      (is (string= "CL" (field local "code")))
      (is (string= "ethereum-lisp" (field local "name")))
      (is (string= "0.1.0" (field local "version")))
      (is (string= "0x00000000" (field local "commit"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":14,\"method\":\"engine_getClientVersionV1\",\"params\":[7]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))))

(deftest engine-rpc-exchange-transition-configuration-returns-local-config
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((config (make-chain-config :terminal-total-difficulty 12345))
           (request-json
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":15,"
              "\"method\":\"engine_exchangeTransitionConfigurationV1\","
              "\"params\":[{\"terminalTotalDifficulty\":\"0x3039\","
              "\"terminalBlockHash\":\"0x0000000000000000000000000000000000000000000000000000000000000000\","
              "\"terminalBlockNumber\":\"0x0\"}]}"))
           (response
             (parse-json
              (engine-rpc-handle-request-json
               request-json
               (make-engine-payload-memory-store)
               config)))
           (result (field response "result")))
      (is (= 15 (field response "id")))
      (is (string= "0x3039" (field result "terminalTotalDifficulty")))
      (is (string= (hash32-to-hex (zero-hash32))
                   (field result "terminalBlockHash")))
      (is (string= "0x0" (field result "terminalBlockNumber"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":16,"
                "\"method\":\"engine_exchangeTransitionConfigurationV1\","
                "\"params\":[{\"terminalTotalDifficulty\":\"bad\"}]}")
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))))

(deftest eth-rpc-chain-id-and-block-number
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1701))
           (block
             (make-block
              :header (make-block-header :number 12
                                         :timestamp 1))))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((responses
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "[{\"jsonrpc\":\"2.0\",\"id\":17,"
                  "\"method\":\"eth_chainId\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":18,"
                  "\"method\":\"eth_blockNumber\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":33,"
                  "\"method\":\"eth_protocolVersion\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":45,"
                  "\"method\":\"net_version\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":52,"
                  "\"method\":\"net_listening\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":53,"
                  "\"method\":\"net_peerCount\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":46,"
                  "\"method\":\"web3_clientVersion\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":49,"
                  "\"method\":\"web3_sha3\","
                  "\"params\":[\"0x68656c6c6f\"]}]")
                 store
                 config))))
        (is (= 8 (length responses)))
        (is (= 17 (field (first responses) "id")))
        (is (string= (quantity-to-hex 1701)
                     (field (first responses) "result")))
        (is (= 18 (field (second responses) "id")))
        (is (string= (quantity-to-hex 12)
                     (field (second responses) "result")))
        (is (= 33 (field (third responses) "id")))
        (is (string= (quantity-to-hex 70)
                     (field (third responses) "result")))
        (is (= 45 (field (fourth responses) "id")))
        (is (string= "1701" (field (fourth responses) "result")))
        (is (= 52 (field (fifth responses) "id")))
        (is (null (field (fifth responses) "result")))
        (is (= 53 (field (sixth responses) "id")))
        (is (string= (quantity-to-hex 0)
                     (field (sixth responses) "result")))
        (is (= 46 (field (seventh responses) "id")))
        (is (string= "ethereum-lisp/0.1.0/CL/0x00000000"
                     (field (seventh responses) "result")))
        (is (= 49 (field (eighth responses) "id")))
        (is (string= "0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8"
                     (field (eighth responses) "result")))))
    (let* ((response-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":20,\"method\":\"eth_syncing\",\"params\":[]}"
              (make-engine-payload-memory-store)
              (make-chain-config)))
           (response (parse-json response-json)))
      (is (= 20 (field response "id")))
      (is (null (field response "result")))
      (is (search "\"result\":false" response-json)))
    (let* ((response-json
             (engine-rpc-handle-request-json
              (concatenate
               'string
               "[{\"jsonrpc\":\"2.0\",\"id\":22,"
               "\"method\":\"eth_accounts\",\"params\":[]},"
               "{\"jsonrpc\":\"2.0\",\"id\":23,"
               "\"method\":\"eth_coinbase\",\"params\":[]},"
               "{\"jsonrpc\":\"2.0\",\"id\":41,"
               "\"method\":\"eth_mining\",\"params\":[]},"
               "{\"jsonrpc\":\"2.0\",\"id\":42,"
               "\"method\":\"eth_hashrate\",\"params\":[]}]")
              (make-engine-payload-memory-store)
              (make-chain-config)))
           (responses (parse-json response-json)))
      (is (= 4 (length responses)))
      (is (= 22 (field (first responses) "id")))
      (is (null (field (first responses) "result")))
      (is (search "\"result\":[]" response-json))
      (is (= 23 (field (second responses) "id")))
      (is (string= (address-to-hex (zero-address))
                   (field (second responses) "result")))
      (is (= 41 (field (third responses) "id")))
      (is (null (field (third responses) "result")))
      (is (search "\"id\":41,\"result\":false" response-json))
      (is (= 42 (field (fourth responses) "id")))
      (is (string= (quantity-to-hex 0)
                   (field (fourth responses) "result"))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :london-block 0
                                      :cancun-time 0))
           (parent
             (make-block
              :header (make-block-header
                       :number 29
                       :timestamp 8
                       :gas-limit 200
                       :gas-used 100
                       :base-fee-per-gas 900)))
           (head
             (make-block
              :header (make-block-header
                       :number 30
                       :timestamp 9
                       :gas-limit 200
                       :gas-used 150
                       :base-fee-per-gas 1000
                       :blob-gas-used 0
                       :excess-blob-gas 0))))
      (engine-payload-store-put-block store parent)
      (engine-payload-store-put-block store head)
      (let* ((responses
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "[{\"jsonrpc\":\"2.0\",\"id\":26,"
                  "\"method\":\"eth_baseFee\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":27,"
                  "\"method\":\"eth_blobBaseFee\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":35,"
                  "\"method\":\"eth_gasPrice\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":36,"
                  "\"method\":\"eth_maxPriorityFeePerGas\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":56,"
                  "\"method\":\"eth_feeHistory\","
                  "\"params\":[\"0x2\",\"latest\",[10.5,90]]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":59,"
                  "\"method\":\"eth_feeHistory\","
                  "\"params\":[\"0x1\",\"safe\",[]]}]")
                 store
                 config))))
        (is (= 6 (length responses)))
        (is (= 26 (field (first responses) "id")))
        (is (string= (quantity-to-hex
                      (expected-base-fee-per-gas (block-header head)))
                     (field (first responses) "result")))
        (is (= 27 (field (second responses) "id")))
        (is (string= (quantity-to-hex
                      (block-header-blob-base-fee (block-header head)))
                     (field (second responses) "result")))
        (is (= 35 (field (third responses) "id")))
        (is (string= (quantity-to-hex 1000)
                     (field (third responses) "result")))
        (is (= 36 (field (fourth responses) "id")))
        (is (string= (quantity-to-hex 0)
                     (field (fourth responses) "result")))
        (let* ((fee-history (field (fifth responses) "result"))
               (base-fees (field fee-history "baseFeePerGas"))
               (gas-ratios (field fee-history "gasUsedRatio"))
               (rewards (field fee-history "reward"))
               (blob-base-fees (field fee-history "baseFeePerBlobGas"))
               (blob-ratios (field fee-history "blobGasUsedRatio")))
          (is (= 56 (field (fifth responses) "id")))
          (is (string= (quantity-to-hex 29)
                       (field fee-history "oldestBlock")))
          (is (string= (quantity-to-hex 900) (first base-fees)))
          (is (string= (quantity-to-hex 1000) (second base-fees)))
          (is (string= (quantity-to-hex
                        (expected-base-fee-per-gas (block-header head)))
                       (third base-fees)))
          (is (= 1/2 (first gas-ratios)))
          (is (= 3/4 (second gas-ratios)))
          (is (string= (quantity-to-hex 0)
                       (first (first rewards))))
          (is (string= (quantity-to-hex 0)
                       (second (second rewards))))
          (is (string= (quantity-to-hex 0) (first blob-base-fees)))
          (is (string= (quantity-to-hex
                        (block-header-blob-base-fee (block-header head)))
                       (second blob-base-fees)))
          (is (string= (quantity-to-hex
                        (block-header-blob-base-fee (block-header head)))
                       (third blob-base-fees)))
          (is (= 0 (first blob-ratios)))
          (is (= 0 (second blob-ratios))))
        (let ((safe-fee-history (field (sixth responses) "result")))
          (is (= 59 (field (sixth responses) "id")))
          (is (string= (quantity-to-hex 30)
                       (field safe-fee-history "oldestBlock"))))))
    (let* ((responses
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "[{\"jsonrpc\":\"2.0\",\"id\":37,"
                "\"method\":\"eth_gasPrice\",\"params\":[]},"
                "{\"jsonrpc\":\"2.0\",\"id\":38,"
                "\"method\":\"eth_maxPriorityFeePerGas\",\"params\":[]}]")
               (make-engine-payload-memory-store)
               (make-chain-config)))))
      (is (= 2 (length responses)))
      (is (string= (quantity-to-hex 0)
                   (field (first responses) "result")))
      (is (string= (quantity-to-hex 0)
                   (field (second responses) "result"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":28,\"method\":\"eth_baseFee\",\"params\":[]}"
               (make-engine-payload-memory-store)
               (make-chain-config :london-block 0)))))
      (is (= 28 (field response "id")))
      (is (null (field response "result"))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :london-block nil))
           (block
             (make-block
              :header (make-block-header
                       :number 2
                       :timestamp 5
                       :gas-limit 200
                       :gas-used 100))))
      (engine-payload-store-put-block store block)
      (let ((response
              (parse-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":29,\"method\":\"eth_baseFee\",\"params\":[]}"
                store
                config))))
        (is (= 29 (field response "id")))
        (is (null (field response "result")))))
    (let* ((store (make-engine-payload-memory-store))
           (block
             (make-block
              :header (make-block-header
                       :number 3
                       :timestamp 5
                       :gas-limit 200
                       :gas-used 100))))
      (engine-payload-store-put-block store block)
      (let ((response
              (parse-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":30,\"method\":\"eth_blobBaseFee\",\"params\":[]}"
                store
                (make-chain-config :cancun-time 0)))))
        (is (= 30 (field response "id")))
        (is (null (field response "result")))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":19,\"method\":\"eth_chainId\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":21,\"method\":\"eth_syncing\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":24,\"method\":\"eth_accounts\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":25,\"method\":\"eth_coinbase\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":43,\"method\":\"eth_mining\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":44,\"method\":\"eth_hashrate\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":31,\"method\":\"eth_baseFee\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":32,\"method\":\"eth_blobBaseFee\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":34,\"method\":\"eth_protocolVersion\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":47,\"method\":\"net_version\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":48,\"method\":\"web3_clientVersion\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":54,\"method\":\"net_listening\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":55,\"method\":\"net_peerCount\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":50,\"method\":\"web3_sha3\",\"params\":[]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":51,\"method\":\"web3_sha3\",\"params\":[\"0xzz\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":39,\"method\":\"eth_gasPrice\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":40,\"method\":\"eth_maxPriorityFeePerGas\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":57,\"method\":\"eth_feeHistory\",\"params\":[\"0x0\",\"latest\",[]]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":58,\"method\":\"eth_feeHistory\",\"params\":[\"0x1\",\"latest\",[90,10]]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))))

(deftest eth-rpc-get-balance
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x00000000000000000000000000000000000000aa"))
           (empty-address
             (address-from-hex "0x00000000000000000000000000000000000000bb"))
           (state-block
             (make-block
              :header (make-block-header :number 20
                                         :timestamp 200
                                         :gas-limit 30000000)))
           (missing-state-block
             (make-block
              :header (make-block-header :number 21
                                         :timestamp 210
                                         :gas-limit 30000000)))
           (state-block-hash-hex (hash32-to-hex (block-hash state-block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store state-block)
      (engine-payload-store-put-account-balance
       store (block-hash state-block) address 12345)
      (engine-payload-store-put-block store missing-state-block)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":73,"
                  "\"method\":\"eth_getBalance\","
                  "\"params\":[\"" (address-to-hex address) "\",\"0x14\"]}")
                 store
                 config)))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":74,"
                  "\"method\":\"eth_getBalance\","
                  "\"params\":[\"" (address-to-hex address) "\",\""
                  state-block-hash-hex "\"]}")
                 store
                 config)))
             (empty-account-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":75,"
                  "\"method\":\"eth_getBalance\","
                  "\"params\":[\"" (address-to-hex empty-address)
                  "\",\"0x14\"]}")
                 store
                 config)))
             (missing-state-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":76,"
                  "\"method\":\"eth_getBalance\","
                  "\"params\":[\"" (address-to-hex address) "\",\"0x15\"]}")
                 store
                 config)))
             (missing-block-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":77,"
                  "\"method\":\"eth_getBalance\","
                  "\"params\":[\"" (address-to-hex address) "\",\"0x63\"]}")
                 store
                 config)))
             (invalid-address-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":78,\"method\":\"eth_getBalance\",\"params\":[\"0x1234\",\"0x14\"]}"
                 store
                 config)))
             (invalid-params-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":79,"
                  "\"method\":\"eth_getBalance\","
                  "\"params\":[\"" (address-to-hex address) "\"]}")
                 store
                 config)))
             (invalid-address-error (field invalid-address-response "error"))
             (invalid-params-error (field invalid-params-response "error")))
        (is (string= (quantity-to-hex 12345)
                     (field number-response "result")))
        (is (string= (quantity-to-hex 12345)
                     (field hash-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field empty-account-response "result")))
        (is (null (field missing-state-response "result")))
        (is (null (field missing-block-response "result")))
        (is (= -32602 (field invalid-address-error "code")))
        (is (= -32602 (field invalid-params-error "code")))))))

(deftest eth-rpc-get-transaction-count
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (empty-address
             (address-from-hex "0x00000000000000000000000000000000000000dd"))
           (pending-transaction
             (make-legacy-transaction
              :nonce 9
              :gas-price 11
              :gas-limit 21000
              :to empty-address
              :value 13
              :data #(1 2 3)
              :v 27
              :r 1
              :s 2))
           (address
             (or (transaction-sender pending-transaction) (zero-address)))
           (state-block
             (make-block
              :header (make-block-header :number 22
                                         :timestamp 220
                                         :gas-limit 30000000)))
           (missing-state-block
             (make-block
              :header (make-block-header :number 23
                                         :timestamp 230
                                         :gas-limit 30000000)))
           (raw-pending-transaction
             (bytes-to-hex (transaction-encoding pending-transaction)))
           (state-block-hash-hex (hash32-to-hex (block-hash state-block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store state-block)
      (engine-payload-store-put-account-nonce
       store (block-hash state-block) address 7)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":80,"
                  "\"method\":\"eth_getTransactionCount\","
                  "\"params\":[\"" (address-to-hex address) "\",\"0x16\"]}")
                 store
                 config)))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":81,"
                  "\"method\":\"eth_getTransactionCount\","
                  "\"params\":[\"" (address-to-hex address) "\",\""
                  state-block-hash-hex "\"]}")
                 store
                 config)))
             (send-pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":87,"
                  "\"method\":\"eth_sendRawTransaction\","
                  "\"params\":[\"" raw-pending-transaction "\"]}")
                 store
                 config)))
             (pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":86,"
                  "\"method\":\"eth_getTransactionCount\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",\"pending\"]}")
                 store
                 config)))
             (empty-account-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":82,"
                  "\"method\":\"eth_getTransactionCount\","
                  "\"params\":[\"" (address-to-hex empty-address)
                  "\",\"0x16\"]}")
                 store
                 config)))
             (missing-state-response
               (parse-json
                (progn
                  (engine-payload-store-put-block store missing-state-block)
                  (engine-rpc-handle-request-json
                   (concatenate
                    'string
                    "{\"jsonrpc\":\"2.0\",\"id\":83,"
                    "\"method\":\"eth_getTransactionCount\","
                    "\"params\":[\"" (address-to-hex address) "\",\"0x17\"]}")
                   store
                   config))))
             (invalid-address-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":84,\"method\":\"eth_getTransactionCount\",\"params\":[\"0x1234\",\"0x16\"]}"
                 store
                 config)))
             (invalid-params-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":85,"
                  "\"method\":\"eth_getTransactionCount\","
                  "\"params\":[\"" (address-to-hex address) "\"]}")
                 store
                 config)))
             (invalid-address-error (field invalid-address-response "error"))
             (invalid-params-error (field invalid-params-response "error")))
        (is (string= (quantity-to-hex 7)
                     (field number-response "result")))
        (is (string= (quantity-to-hex 7)
                     (field hash-response "result")))
        (is (string= (hash32-to-hex (transaction-hash pending-transaction))
                     (field send-pending-response "result")))
        (is (string= (quantity-to-hex 10)
                     (field pending-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field empty-account-response "result")))
        (is (null (field missing-state-response "result")))
        (is (= -32602 (field invalid-address-error "code")))
        (is (= -32602 (field invalid-params-error "code")))))))

(deftest eth-rpc-get-code
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x00000000000000000000000000000000000000ee"))
           (empty-address
             (address-from-hex "0x00000000000000000000000000000000000000ff"))
           (state-block
             (make-block
              :header (make-block-header :number 24
                                         :timestamp 240
                                         :gas-limit 30000000)))
           (missing-state-block
             (make-block
              :header (make-block-header :number 25
                                         :timestamp 250
                                         :gas-limit 30000000)))
           (state-block-hash-hex (hash32-to-hex (block-hash state-block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store state-block)
      (engine-payload-store-put-account-code
       store (block-hash state-block) address #(96 1 96 0))
      (engine-payload-store-put-block store missing-state-block)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":86,"
                  "\"method\":\"eth_getCode\","
                  "\"params\":[\"" (address-to-hex address) "\",\"0x18\"]}")
                 store
                 config)))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":87,"
                  "\"method\":\"eth_getCode\","
                  "\"params\":[\"" (address-to-hex address) "\",\""
                  state-block-hash-hex "\"]}")
                 store
                 config)))
             (empty-account-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":88,"
                  "\"method\":\"eth_getCode\","
                  "\"params\":[\"" (address-to-hex empty-address)
                  "\",\"0x18\"]}")
                 store
                 config)))
             (missing-state-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":89,"
                  "\"method\":\"eth_getCode\","
                  "\"params\":[\"" (address-to-hex address) "\",\"0x19\"]}")
                 store
                 config)))
             (invalid-address-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":90,\"method\":\"eth_getCode\",\"params\":[\"0x1234\",\"0x18\"]}"
                 store
                 config)))
             (invalid-params-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":91,"
                  "\"method\":\"eth_getCode\","
                  "\"params\":[\"" (address-to-hex address) "\"]}")
                 store
                 config)))
             (invalid-address-error (field invalid-address-response "error"))
             (invalid-params-error (field invalid-params-response "error")))
        (is (string= "0x60016000"
                     (field number-response "result")))
        (is (string= "0x60016000"
                     (field hash-response "result")))
        (is (string= "0x"
                     (field empty-account-response "result")))
        (is (null (field missing-state-response "result")))
        (is (= -32602 (field invalid-address-error "code")))
        (is (= -32602 (field invalid-params-error "code")))))))

(deftest eth-rpc-get-storage-at
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x0000000000000000000000000000000000000101"))
           (empty-address
             (address-from-hex "0x0000000000000000000000000000000000000102"))
           (slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000007"))
           (state-block
             (make-block
              :header (make-block-header :number 26
                                         :timestamp 260
                                         :gas-limit 30000000)))
           (missing-state-block
             (make-block
              :header (make-block-header :number 27
                                         :timestamp 270
                                         :gas-limit 30000000)))
           (state-block-hash-hex (hash32-to-hex (block-hash state-block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store state-block)
      (engine-payload-store-put-account-storage
       store (block-hash state-block) address slot #x2a)
      (engine-payload-store-put-block store missing-state-block)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":92,"
                  "\"method\":\"eth_getStorageAt\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",\"0x7\",\"0x1a\"]}")
                 store
                 config)))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":93,"
                  "\"method\":\"eth_getStorageAt\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",\"7\",\"" state-block-hash-hex "\"]}")
                 store
                 config)))
             (empty-account-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":94,"
                  "\"method\":\"eth_getStorageAt\","
                  "\"params\":[\"" (address-to-hex empty-address)
                  "\",\"0x7\",\"0x1a\"]}")
                 store
                 config)))
             (missing-state-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":95,"
                  "\"method\":\"eth_getStorageAt\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",\"0x7\",\"0x1b\"]}")
                 store
                 config)))
             (invalid-slot-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":96,"
                  "\"method\":\"eth_getStorageAt\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",\"0x"
                  "111111111111111111111111111111111111111111111111111111111111111111"
                  "\",\"0x1a\"]}")
                 store
                 config)))
             (invalid-params-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":97,"
                  "\"method\":\"eth_getStorageAt\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",\"0x7\"]}")
                 store
                 config)))
             (invalid-slot-error (field invalid-slot-response "error"))
             (invalid-params-error (field invalid-params-response "error"))
             (expected-word
               "0x000000000000000000000000000000000000000000000000000000000000002a")
             (zero-word
               "0x0000000000000000000000000000000000000000000000000000000000000000"))
        (is (string= expected-word (field number-response "result")))
        (is (string= expected-word (field hash-response "result")))
        (is (string= zero-word (field empty-account-response "result")))
        (is (null (field missing-state-response "result")))
        (is (= -32602 (field invalid-slot-error "code")))
        (is (= -32602 (field invalid-params-error "code")))))))

(deftest eth-rpc-get-header-by-number
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (beneficiary
             (make-address (make-byte-vector 20 :initial-element #xab)))
           (genesis
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 1
                                         :gas-limit 30000000)
              :withdrawals '()
              :requests '()
              :block-access-list '()))
           (parent-hash (block-hash genesis))
           (header
             (make-block-header
              :parent-hash parent-hash
              :beneficiary beneficiary
              :state-root +empty-trie-hash+
              :difficulty 0
              :number 12
              :gas-limit 30000000
              :gas-used 21000
              :timestamp 123
              :extra-data #(170 187)
              :mix-hash (zero-hash32)
              :nonce (make-byte-vector 8)
              :base-fee-per-gas 7
              :blob-gas-used 0
              :excess-blob-gas 0
              :parent-beacon-root (zero-hash32)
              :slot-number 99))
           (block
             (make-block :header header
                         :withdrawals '()
                         :requests '()
                         :block-access-list '()))
           (config (make-chain-config)))
      (engine-payload-store-put-block store genesis :state-available-p t)
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((latest-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":20,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"latest\"]}"
                 store
                 config)))
             (latest (field latest-response "result"))
             (earliest-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":21,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"earliest\"]}"
                 store
                 config)))
             (quantity-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":22,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"0xc\"]}"
                 store
                 config)))
             (pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":120,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"pending\"]}"
                 store
                 config)))
             (safe-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":121,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"safe\"]}"
                 store
                 config)))
             (finalized-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":122,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"finalized\"]}"
                 store
                 config)))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":23,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"0x63\"]}"
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":24,\"method\":\"eth_getHeaderByNumber\",\"params\":[]}"
                 store
                 config)))
             (invalid-error (field invalid-response "error")))
        (is (string= (quantity-to-hex 12) (field latest "number")))
        (is (string= (hash32-to-hex (block-hash block))
                     (field latest "hash")))
        (is (string= (hash32-to-hex parent-hash)
                     (field latest "parentHash")))
        (is (string= (address-to-hex beneficiary)
                     (field latest "miner")))
        (is (string= (quantity-to-hex 30000000)
                     (field latest "gasLimit")))
        (is (string= (quantity-to-hex 21000)
                     (field latest "gasUsed")))
        (is (string= (quantity-to-hex 123)
                     (field latest "timestamp")))
        (is (string= (quantity-to-hex 7)
                     (field latest "baseFeePerGas")))
        (is (string= (quantity-to-hex 0)
                     (field latest "blobGasUsed")))
        (is (string= (quantity-to-hex 0)
                     (field latest "excessBlobGas")))
        (is (string= (hash32-to-hex (zero-hash32))
                     (field latest "parentBeaconBlockRoot")))
        (is (string= (hash32-to-hex (execution-requests-hash '()))
                     (field latest "requestsHash")))
        (is (string= (hash32-to-hex (block-access-list-hash '()))
                     (field latest "balHash")))
        (is (string= (quantity-to-hex 99) (field latest "slotNumber")))
        (is (string= (hash32-to-hex (block-header-transactions-root header))
                     (field latest "transactionsRoot")))
        (is (string= (quantity-to-hex 0)
                     (field (field earliest-response "result")
                            "number")))
        (is (string= (field latest "hash")
                     (field (field quantity-response "result") "hash")))
        (is (string= (field latest "hash")
                     (field (field pending-response "result") "hash")))
        (is (string= (field latest "hash")
                     (field (field safe-response "result") "hash")))
        (is (string= (field latest "hash")
                     (field (field finalized-response "result") "hash")))
        (is (null (field missing-response "result")))
        (is (= -32602 (field invalid-error "code")))))))

(deftest eth-rpc-get-header-by-hash
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (header
             (make-block-header :number 5
                                :timestamp 55
                                :gas-limit 1000000
                                :gas-used 21000
                                :base-fee-per-gas 9))
           (block (make-block :header header))
           (hash (block-hash block))
           (hash-hex (hash32-to-hex hash))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((found-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":25,"
                  "\"method\":\"eth_getHeaderByHash\",\"params\":[\""
                  hash-hex "\"]}")
                 store
                 config)))
             (found (field found-response "result"))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":26,"
                  "\"method\":\"eth_getHeaderByHash\",\"params\":[\""
                  (hash32-to-hex (zero-hash32)) "\"]}")
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":27,\"method\":\"eth_getHeaderByHash\",\"params\":[\"0x1234\"]}"
                 store
                 config)))
             (invalid-error (field invalid-response "error")))
        (is (string= (quantity-to-hex 5) (field found "number")))
        (is (string= hash-hex (field found "hash")))
        (is (string= (quantity-to-hex 55) (field found "timestamp")))
        (is (string= (quantity-to-hex 9) (field found "baseFeePerGas")))
        (is (null (field missing-response "result")))
        (is (= -32602 (field invalid-error "code")))))))

(deftest eth-rpc-get-block-by-number-with-transaction-hashes
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (make-legacy-transaction :nonce 1
                                      :gas-price 20000000000
                                      :gas-limit 21000
                                      :to recipient
                                      :value 1000000000000000000
                                      :v 37
                                      :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
                                      :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
           (withdrawal
             (make-withdrawal :index 1
                              :validator-index 2
                              :address recipient
                              :amount 4))
           (ommer (make-block-header :number 7
                                     :timestamp 70))
           (block
             (make-block
              :header (make-block-header :number 8
                                         :timestamp 80
                                         :gas-limit 30000000
                                         :gas-used 21000
                                         :base-fee-per-gas 9)
              :transactions (list transaction)
              :ommers (list ommer)
              :withdrawals (list withdrawal)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":28,\"method\":\"eth_getBlockByNumber\",\"params\":[\"0x8\",false]}"
                 store
                 config)))
             (result (field response "result"))
             (transactions (field result "transactions"))
             (uncles (field result "uncles"))
             (withdrawals (field result "withdrawals"))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":29,\"method\":\"eth_getBlockByNumber\",\"params\":[\"0x63\",false]}"
                 store
                 config)))
             (full-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":30,\"method\":\"eth_getBlockByNumber\",\"params\":[\"0x8\",true]}"
                 store
                 config)))
             (full-result (field full-response "result"))
             (full-transactions (field full-result "transactions"))
             (full-transaction (first full-transactions)))
        (is (string= (quantity-to-hex 8) (field result "number")))
        (is (string= (hash32-to-hex (block-hash block))
                     (field result "hash")))
        (is (stringp (field result "size")))
        (is (= 1 (length transactions)))
        (is (string= (hash32-to-hex (transaction-hash transaction))
                     (first transactions)))
        (is (= 1 (length uncles)))
        (is (string= (hash32-to-hex (block-header-hash ommer))
                     (first uncles)))
        (is (= 1 (length withdrawals)))
        (is (string= (quantity-to-hex 1)
                     (field (first withdrawals) "index")))
        (is (null (field missing-response "result")))
        (is (string= (field result "hash")
                     (field full-result "hash")))
        (is (= 1 (length full-transactions)))
        (is (string= (hash32-to-hex (transaction-hash transaction))
                     (field full-transaction "hash")))
        (is (string= (field result "hash")
                     (field full-transaction "blockHash")))
        (is (string= (quantity-to-hex 8)
                     (field full-transaction "blockNumber")))
        (is (string= (quantity-to-hex 0)
                     (field full-transaction "transactionIndex")))
        (is (string= (address-to-hex recipient)
                     (field full-transaction "to")))
        (is (string= (address-to-hex
                      (transaction-sender transaction))
                     (field full-transaction "from")))
        (is (string= (quantity-to-hex 0)
                     (field full-transaction "type")))))))

(deftest eth-rpc-get-block-by-hash-with-transaction-hashes
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (make-legacy-transaction
              :nonce 9
              :gas-price 20000000000
              :gas-limit 21000
              :to recipient
              :value 1000000000000000000
              :v 37
              :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
              :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
           (block
             (make-block
              :header (make-block-header :number 9
                                         :timestamp 90
                                         :gas-limit 30000000
                                         :gas-used 21000
                                         :base-fee-per-gas 10)
              :transactions (list transaction)))
           (hash (block-hash block))
           (hash-hex (hash32-to-hex hash))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":31,"
                  "\"method\":\"eth_getBlockByHash\",\"params\":[\""
                  hash-hex "\",false]}")
                 store
                 config)))
             (result (field response "result"))
             (transactions (field result "transactions"))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":32,"
                  "\"method\":\"eth_getBlockByHash\",\"params\":[\""
                  (hash32-to-hex (zero-hash32)) "\",false]}")
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":33,\"method\":\"eth_getBlockByHash\",\"params\":[\"0x1234\",false]}"
                 store
                 config)))
             (invalid-error (field invalid-response "error"))
             (full-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":54,"
                  "\"method\":\"eth_getBlockByHash\",\"params\":[\""
                  hash-hex "\",true]}")
                 store
                 config)))
             (full-result (field full-response "result"))
             (full-transaction (first (field full-result "transactions"))))
        (is (string= (quantity-to-hex 9) (field result "number")))
        (is (string= hash-hex (field result "hash")))
        (is (= 1 (length transactions)))
        (is (string= (hash32-to-hex (transaction-hash transaction))
                     (first transactions)))
        (is (null (field missing-response "result")))
        (is (= -32602 (field invalid-error "code")))
        (is (string= hash-hex (field full-transaction "blockHash")))
        (is (string= (hash32-to-hex (transaction-hash transaction))
                     (field full-transaction "hash")))
        (is (string= (quantity-to-hex 9)
                     (field full-transaction "blockNumber")))
        (is (string= (quantity-to-hex 0)
                     (field full-transaction "transactionIndex")))))))

(deftest eth-rpc-get-block-transaction-count
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (tx-1 (make-legacy-transaction :nonce 1
                                          :gas-price 7
                                          :gas-limit 21000))
           (tx-2 (make-legacy-transaction :nonce 2
                                          :gas-price 8
                                          :gas-limit 21000))
           (block
             (make-block
              :header (make-block-header :number 10
                                         :timestamp 100
                                         :gas-limit 30000000)
              :transactions (list tx-1 tx-2)))
           (hash-hex (hash32-to-hex (block-hash block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":34,\"method\":\"eth_getBlockTransactionCountByNumber\",\"params\":[\"0xa\"]}"
                 store
                 config)))
             (latest-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":35,\"method\":\"eth_getBlockTransactionCountByNumber\",\"params\":[\"latest\"]}"
                 store
                 config)))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":36,"
                  "\"method\":\"eth_getBlockTransactionCountByHash\","
                  "\"params\":[\"" hash-hex "\"]}")
                 store
                 config)))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":37,\"method\":\"eth_getBlockTransactionCountByNumber\",\"params\":[\"0x63\"]}"
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":38,\"method\":\"eth_getBlockTransactionCountByHash\",\"params\":[\"0x1234\"]}"
                 store
                 config)))
             (invalid-error (field invalid-response "error")))
        (is (string= (quantity-to-hex 2)
                     (field number-response "result")))
        (is (string= (quantity-to-hex 2)
                     (field latest-response "result")))
        (is (string= (quantity-to-hex 2)
                     (field hash-response "result")))
        (is (null (field missing-response "result")))
        (is (= -32602 (field invalid-error "code")))))))

(deftest eth-rpc-get-uncle-count
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (ommer-1 (make-block-header :number 10
                                       :timestamp 101))
           (ommer-2 (make-block-header :number 10
                                       :timestamp 102))
           (block
             (make-block
              :header (make-block-header :number 11
                                         :timestamp 110
                                         :gas-limit 30000000)
              :ommers (list ommer-1 ommer-2)))
           (hash-hex (hash32-to-hex (block-hash block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":39,\"method\":\"eth_getUncleCountByBlockNumber\",\"params\":[\"0xb\"]}"
                 store
                 config)))
             (latest-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":40,\"method\":\"eth_getUncleCountByBlockNumber\",\"params\":[\"latest\"]}"
                 store
                 config)))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":41,"
                  "\"method\":\"eth_getUncleCountByBlockHash\","
                  "\"params\":[\"" hash-hex "\"]}")
                 store
                 config)))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":42,\"method\":\"eth_getUncleCountByBlockNumber\",\"params\":[\"0x63\"]}"
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":43,\"method\":\"eth_getUncleCountByBlockHash\",\"params\":[\"0x1234\"]}"
                 store
                 config)))
             (invalid-error (field invalid-response "error")))
        (is (string= (quantity-to-hex 2)
                     (field number-response "result")))
        (is (string= (quantity-to-hex 2)
                     (field latest-response "result")))
        (is (string= (quantity-to-hex 2)
                     (field hash-response "result")))
        (is (null (field missing-response "result")))
        (is (= -32602 (field invalid-error "code")))))))

(deftest eth-rpc-get-uncle-by-block-and-index
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (beneficiary
             (make-address (make-byte-vector 20 :initial-element #x99)))
           (ommer-1
             (make-block-header :number 10
                                :timestamp 101
                                :gas-limit 30000000
                                :gas-used 0))
           (ommer-2
             (make-block-header :number 10
                                :timestamp 102
                                :beneficiary beneficiary
                                :gas-limit 30000000
                                :gas-used 21000
                                :base-fee-per-gas 8))
           (block
             (make-block
              :header (make-block-header :number 11
                                         :timestamp 111
                                         :gas-limit 30000000)
              :ommers (list ommer-1 ommer-2)))
           (hash-hex (hash32-to-hex (block-hash block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":67,\"method\":\"eth_getUncleByBlockNumberAndIndex\",\"params\":[\"0xb\",\"0x1\"]}"
                 store
                 config)))
             (number-result (field number-response "result"))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":68,"
                  "\"method\":\"eth_getUncleByBlockHashAndIndex\","
                  "\"params\":[\"" hash-hex "\",\"0x0\"]}")
                 store
                 config)))
             (hash-result (field hash-response "result"))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":69,\"method\":\"eth_getUncleByBlockNumberAndIndex\",\"params\":[\"0x63\",\"0x0\"]}"
                 store
                 config)))
             (out-of-range-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":70,\"method\":\"eth_getUncleByBlockNumberAndIndex\",\"params\":[\"0xb\",\"0x2\"]}"
                 store
                 config)))
             (invalid-hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":71,\"method\":\"eth_getUncleByBlockHashAndIndex\",\"params\":[\"0x1234\",\"0x0\"]}"
                 store
                 config)))
             (invalid-params-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":72,\"method\":\"eth_getUncleByBlockNumberAndIndex\",\"params\":[\"0xb\"]}"
                 store
                 config)))
             (invalid-hash-error (field invalid-hash-response "error"))
             (invalid-params-error (field invalid-params-response "error")))
        (is (string= (quantity-to-hex 10)
                     (field number-result "number")))
        (is (string= (hash32-to-hex (block-header-hash ommer-2))
                     (field number-result "hash")))
        (is (string= (address-to-hex beneficiary)
                     (field number-result "miner")))
        (is (string= (quantity-to-hex 102)
                     (field number-result "timestamp")))
        (is (string= (quantity-to-hex 8)
                     (field number-result "baseFeePerGas")))
        (is (stringp (field number-result "size")))
        (is (null (assoc "transactions" number-result :test #'string=)))
        (is (null (field number-result "uncles")))
        (is (string= (hash32-to-hex (block-header-hash ommer-1))
                     (field hash-result "hash")))
        (is (null (field missing-response "result")))
        (is (null (field out-of-range-response "result")))
        (is (= -32602 (field invalid-hash-error "code")))
        (is (= -32602 (field invalid-params-error "code")))))))

(deftest eth-rpc-get-raw-transaction-by-block-and-index
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (tx-1 (make-legacy-transaction :nonce 1
                                          :gas-price 7
                                          :gas-limit 21000
                                          :value 3))
           (tx-2 (make-dynamic-fee-transaction
                  :chain-id 1
                  :nonce 2
                  :max-priority-fee-per-gas 1
                  :max-fee-per-gas 9
                  :gas-limit 21000
                  :value 4))
           (block
             (make-block
              :header (make-block-header :number 12
                                         :timestamp 120
                                         :gas-limit 30000000)
              :transactions (list tx-1 tx-2)))
           (hash-hex (hash32-to-hex (block-hash block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":44,\"method\":\"eth_getRawTransactionByBlockNumberAndIndex\",\"params\":[\"0xc\",\"0x1\"]}"
                 store
                 config)))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":45,"
                  "\"method\":\"eth_getRawTransactionByBlockHashAndIndex\","
                  "\"params\":[\"" hash-hex "\",\"0x0\"]}")
                 store
                 config)))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":46,\"method\":\"eth_getRawTransactionByBlockNumberAndIndex\",\"params\":[\"0x63\",\"0x0\"]}"
                 store
                 config)))
             (out-of-range-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":47,\"method\":\"eth_getRawTransactionByBlockNumberAndIndex\",\"params\":[\"0xc\",\"0x2\"]}"
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":48,\"method\":\"eth_getRawTransactionByBlockHashAndIndex\",\"params\":[\"0x1234\",\"0x0\"]}"
                 store
                 config)))
             (invalid-error (field invalid-response "error")))
        (is (string= (bytes-to-hex (transaction-encoding tx-2))
                     (field number-response "result")))
        (is (string= (bytes-to-hex (transaction-encoding tx-1))
                     (field hash-response "result")))
        (is (null (field missing-response "result")))
        (is (null (field out-of-range-response "result")))
        (is (= -32602 (field invalid-error "code")))))))

(deftest eth-rpc-get-transaction-by-block-and-index
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (dynamic-recipient
             (address-from-hex "0x1111111111111111111111111111111111111111"))
           (tx-1 (make-legacy-transaction :nonce 9
                                          :gas-price 20000000000
                                          :gas-limit 21000
                                          :to recipient
                                          :value 1000000000000000000
                                          :v 37
                                          :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
                                          :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
           (tx-2 (make-dynamic-fee-transaction
                  :chain-id 1
                  :nonce 1
                  :max-priority-fee-per-gas 0
                  :max-fee-per-gas #x0fa0
                  :gas-limit #x84d0
                  :to dynamic-recipient
                  :value 0
                  :data #()
                  :y-parity 1
                  :r #xb7dfab36232379bb3d1497a4f91c1966b1f932eae3ade107bf5d723b9cb474e0
                  :s #x6261c359a10f2132f126d250485b90cf20f30340801244a08ef6142ab33d1904))
           (block
             (make-block
              :header (make-block-header :number 13
                                         :timestamp 130
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5)
              :transactions (list tx-1 tx-2)))
           (hash-hex (hash32-to-hex (block-hash block)))
           (tx-2-from (transaction-sender tx-2))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":49,\"method\":\"eth_getTransactionByBlockNumberAndIndex\",\"params\":[\"0xd\",\"0x1\"]}"
                 store
                 config)))
             (number-result (field number-response "result"))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":50,"
                  "\"method\":\"eth_getTransactionByBlockHashAndIndex\","
                  "\"params\":[\"" hash-hex "\",\"0x0\"]}")
                 store
                 config)))
             (hash-result (field hash-response "result"))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":51,\"method\":\"eth_getTransactionByBlockNumberAndIndex\",\"params\":[\"0x63\",\"0x0\"]}"
                 store
                 config)))
             (out-of-range-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":52,\"method\":\"eth_getTransactionByBlockNumberAndIndex\",\"params\":[\"0xd\",\"0x2\"]}"
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":53,\"method\":\"eth_getTransactionByBlockHashAndIndex\",\"params\":[\"0x1234\",\"0x0\"]}"
                 store
                 config)))
             (invalid-error (field invalid-response "error")))
        (is (string= hash-hex (field number-result "blockHash")))
        (is (string= (quantity-to-hex 13)
                     (field number-result "blockNumber")))
        (is (string= (quantity-to-hex 130)
                     (field number-result "blockTimestamp")))
        (is (string= (address-to-hex tx-2-from)
                     (field number-result "from")))
        (is (string= (quantity-to-hex #x84d0)
                     (field number-result "gas")))
        (is (string= (quantity-to-hex 5)
                     (field number-result "gasPrice")))
        (is (string= (hash32-to-hex (transaction-hash tx-2))
                     (field number-result "hash")))
        (is (string= "0x" (field number-result "input")))
        (is (string= (quantity-to-hex 1)
                     (field number-result "nonce")))
        (is (string= (address-to-hex dynamic-recipient)
                     (field number-result "to")))
        (is (string= (quantity-to-hex 1)
                     (field number-result "transactionIndex")))
        (is (string= (quantity-to-hex 0)
                     (field number-result "value")))
        (is (string= (quantity-to-hex 2)
                     (field number-result "type")))
        (is (string= (quantity-to-hex 1)
                     (field number-result "chainId")))
        (is (string= (quantity-to-hex #x0fa0)
                     (field number-result "maxFeePerGas")))
        (is (string= (quantity-to-hex 0)
                     (field number-result "maxPriorityFeePerGas")))
        (is (string= (quantity-to-hex 1)
                     (field number-result "yParity")))
        (is (string= (quantity-to-hex 1) (field number-result "v")))
        (is (string= (quantity-to-hex #xb7dfab36232379bb3d1497a4f91c1966b1f932eae3ade107bf5d723b9cb474e0)
                     (field number-result "r")))
        (is (string= (quantity-to-hex #x6261c359a10f2132f126d250485b90cf20f30340801244a08ef6142ab33d1904)
                     (field number-result "s")))
        (is (string= hash-hex (field hash-result "blockHash")))
        (is (string= (hash32-to-hex (transaction-hash tx-1))
                     (field hash-result "hash")))
        (is (string= (quantity-to-hex 0) (field hash-result "type")))
        (is (string= (quantity-to-hex 20000000000)
                     (field hash-result "gasPrice")))
        (is (string= "0x" (field hash-result "input")))
        (is (string= (address-to-hex recipient)
                     (field hash-result "to")))
        (is (string= (quantity-to-hex 0)
                     (field hash-result "transactionIndex")))
        (is (null (field missing-response "result")))
        (is (null (field out-of-range-response "result")))
        (is (= -32602 (field invalid-error "code")))))))

(deftest eth-rpc-get-transaction-by-hash
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (dynamic-recipient
             (address-from-hex "0x1111111111111111111111111111111111111111"))
           (tx-1 (make-legacy-transaction :nonce 9
                                          :gas-price 20000000000
                                          :gas-limit 21000
                                          :to recipient
                                          :value 1000000000000000000
                                          :v 37
                                          :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
                                          :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
           (tx-2 (make-dynamic-fee-transaction
                  :chain-id 1
                  :nonce 1
                  :max-priority-fee-per-gas 0
                  :max-fee-per-gas #x0fa0
                  :gas-limit #x84d0
                  :to dynamic-recipient
                  :value 0
                  :data #()
                  :y-parity 1
                  :r #xb7dfab36232379bb3d1497a4f91c1966b1f932eae3ade107bf5d723b9cb474e0
                  :s #x6261c359a10f2132f126d250485b90cf20f30340801244a08ef6142ab33d1904))
           (block
             (make-block
              :header (make-block-header :number 14
                                         :timestamp 140
                                         :gas-limit 30000000
                                         :base-fee-per-gas 6)
              :transactions (list tx-1 tx-2)))
           (block-hash-hex (hash32-to-hex (block-hash block)))
           (tx-2-hash-hex (hash32-to-hex (transaction-hash tx-2)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((transaction-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":55,"
                  "\"method\":\"eth_getTransactionByHash\","
                  "\"params\":[\"" tx-2-hash-hex "\"]}")
                 store
                 config)))
             (transaction-result (field transaction-response "result"))
             (raw-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":56,"
                  "\"method\":\"eth_getRawTransactionByHash\","
                  "\"params\":[\"" tx-2-hash-hex "\"]}")
                 store
                 config)))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":57,"
                  "\"method\":\"eth_getTransactionByHash\","
                  "\"params\":[\""
                  (hash32-to-hex (zero-hash32)) "\"]}")
                 store
                 config)))
             (missing-raw-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":58,"
                  "\"method\":\"eth_getRawTransactionByHash\","
                  "\"params\":[\""
                  (hash32-to-hex (zero-hash32)) "\"]}")
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":59,\"method\":\"eth_getTransactionByHash\",\"params\":[\"0x1234\"]}"
                 store
                 config)))
             (invalid-error (field invalid-response "error")))
        (is (string= tx-2-hash-hex (field transaction-result "hash")))
        (is (string= block-hash-hex
                     (field transaction-result "blockHash")))
        (is (string= (quantity-to-hex 14)
                     (field transaction-result "blockNumber")))
        (is (string= (quantity-to-hex 140)
                     (field transaction-result "blockTimestamp")))
        (is (string= (quantity-to-hex 1)
                     (field transaction-result "transactionIndex")))
        (is (string= (quantity-to-hex 6)
                     (field transaction-result "gasPrice")))
        (is (string= (quantity-to-hex 2)
                     (field transaction-result "type")))
        (is (string= (bytes-to-hex (transaction-encoding tx-2))
                     (field raw-response "result")))
        (is (null (field missing-response "result")))
        (is (null (field missing-raw-response "result")))
        (is (= -32602 (field invalid-error "code")))))))

(deftest eth-rpc-transaction-objects-require-recoverable-sender
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (make-legacy-transaction
              :nonce 9
              :gas-price 20000000000
              :gas-limit 21000
              :to recipient
              :value 1000000000000000000
              :v 37
              :r 0
              :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
           (transaction-hash-hex (hash32-to-hex (transaction-hash transaction)))
           (block
             (make-block
              :header (make-block-header :number 16
                                         :timestamp 160
                                         :gas-limit 30000000)
              :transactions (list transaction)))
           (block-hash-hex (hash32-to-hex (block-hash block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((by-hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":97,"
                  "\"method\":\"eth_getTransactionByHash\","
                  "\"params\":[\"" transaction-hash-hex "\"]}")
                 store
                 config)))
             (by-index-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":98,\"method\":\"eth_getTransactionByBlockNumberAndIndex\",\"params\":[\"0x10\",\"0x0\"]}"
                 store
                 config)))
             (full-block-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":99,"
                  "\"method\":\"eth_getBlockByHash\","
                  "\"params\":[\"" block-hash-hex "\",true]}")
                 store
                 config)))
             (by-hash-error (field by-hash-response "error"))
             (by-index-error (field by-index-response "error"))
             (full-block-error (field full-block-response "error")))
        (is (= -32602 (field by-hash-error "code")))
        (is (= -32602 (field by-index-error "code")))
        (is (= -32602 (field full-block-error "code")))))))

(deftest eth-rpc-send-raw-transaction
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction (make-legacy-transaction
                         :nonce 9
                         :gas-price 20000000000
                         :gas-limit 21000
                         :to recipient
                         :value 1000000000000000000
                         :v 37
                         :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
                         :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
           (raw-transaction (bytes-to-hex (transaction-encoding transaction)))
           (transaction-hash (hash32-to-hex (transaction-hash transaction)))
           (mined-block
             (make-block
              :header (make-block-header :number 15
                                         :timestamp 150
                                         :gas-limit 30000000)
              :transactions (list transaction)))
           (config (make-chain-config)))
      (let* ((new-pending-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":77,\"method\":\"eth_newPendingTransactionFilter\"}"
                 store
                 config)))
             (pending-filter-id
               (field new-pending-filter-response "result"))
             (initial-pending-filter-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":78,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" pending-filter-id "\"]}")
                store
                config))
             (send-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":60,"
                  "\"method\":\"eth_sendRawTransaction\","
                  "\"params\":[\"" raw-transaction "\"]}")
                 store
                 config)))
             (pending-filter-changes-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":79,"
                  "\"method\":\"eth_getFilterChanges\","
                  "\"params\":[\"" pending-filter-id "\"]}")
                 store
                 config)))
             (pending-filter-changes
               (field pending-filter-changes-response "result"))
             (empty-pending-filter-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":80,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" pending-filter-id "\"]}")
                store
                config))
             (duplicate-pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":89,"
                  "\"method\":\"eth_sendRawTransaction\","
                  "\"params\":[\"" raw-transaction "\"]}")
                 store
                 config)))
             (duplicate-pending-filter-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":90,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" pending-filter-id "\"]}")
                store
                config))
             (duplicate-pending-status-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":91,\"method\":\"txpool_status\",\"params\":[]}"
                 store
                 config)))
             (raw-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":61,"
                  "\"method\":\"eth_getRawTransactionByHash\","
                  "\"params\":[\"" transaction-hash "\"]}")
                 store
                 config)))
             (transaction-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":62,"
                  "\"method\":\"eth_getTransactionByHash\","
                  "\"params\":[\"" transaction-hash "\"]}")
                 store
                 config)))
             (pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":65,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                 store
                 config)))
             (txpool-status-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":67,\"method\":\"txpool_status\",\"params\":[]}"
                 store
                 config)))
             (txpool-content-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":69,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (txpool-content-response (parse-json txpool-content-json))
             (txpool-content-from-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":71,"
                 "\"method\":\"txpool_contentFrom\",\"params\":[\""
                 (address-to-hex
                  (or (transaction-sender transaction)
                      (zero-address)))
                 "\"]}")
                store
                config))
             (txpool-content-from-response
               (parse-json txpool-content-from-json))
             (txpool-content-from-missing-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":72,"
                 "\"method\":\"txpool_contentFrom\",\"params\":[\""
                 (address-to-hex
                  (make-address
                   (make-byte-vector 20 :initial-element #x99)))
                 "\"]}")
                store
                config))
             (txpool-inspect-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":75,\"method\":\"txpool_inspect\",\"params\":[]}"
                store
                config))
             (txpool-inspect-response (parse-json txpool-inspect-json))
             (invalid-rlp-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":63,\"method\":\"eth_sendRawTransaction\",\"params\":[\"0x01\"]}"
                 store
                 config)))
             (invalid-count-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":64,\"method\":\"eth_sendRawTransaction\",\"params\":[]}"
                 store
                 config)))
             (invalid-pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":66,\"method\":\"eth_pendingTransactions\",\"params\":[\"unexpected\"]}"
                 store
                 config)))
             (invalid-new-pending-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":81,\"method\":\"eth_newPendingTransactionFilter\",\"params\":[\"unexpected\"]}"
                 store
                 config)))
             (invalid-txpool-status-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":68,\"method\":\"txpool_status\",\"params\":[\"unexpected\"]}"
                 store
                 config)))
             (invalid-txpool-content-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":70,\"method\":\"txpool_content\",\"params\":[\"unexpected\"]}"
                 store
                 config)))
             (invalid-txpool-content-from-count-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":73,\"method\":\"txpool_contentFrom\",\"params\":[]}"
                 store
                 config)))
             (invalid-txpool-content-from-address-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":74,\"method\":\"txpool_contentFrom\",\"params\":[\"0x1234\"]}"
                 store
                 config)))
             (invalid-txpool-inspect-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":76,\"method\":\"txpool_inspect\",\"params\":[\"unexpected\"]}"
                 store
                 config))))
        (is (string= (quantity-to-hex 1) pending-filter-id))
        (is (search "\"result\":[]" initial-pending-filter-json))
        (is (string= transaction-hash (field send-response "result")))
        (is (= 1 (length pending-filter-changes)))
        (is (string= transaction-hash (first pending-filter-changes)))
        (is (search "\"result\":[]" empty-pending-filter-json))
        (is (string= transaction-hash
                     (field duplicate-pending-response "result")))
        (is (search "\"result\":[]" duplicate-pending-filter-json))
        (is (string= (quantity-to-hex 1)
                     (field (field duplicate-pending-status-response "result")
                            "pending")))
        (is (string= raw-transaction (field raw-response "result")))
        (let ((pending-transaction (field transaction-response "result")))
          (is (string= transaction-hash
                       (field pending-transaction "hash")))
          (is (null (field pending-transaction "blockHash")))
          (is (null (field pending-transaction "blockNumber")))
          (is (null (field pending-transaction "blockTimestamp")))
          (is (null (field pending-transaction "transactionIndex")))
          (is (string= (quantity-to-hex 20000000000)
                       (field pending-transaction "gasPrice")))
          (is (string= (quantity-to-hex 1000000000000000000)
                       (field pending-transaction "value"))))
        (let ((pending-transactions (field pending-response "result")))
          (is (= 1 (length pending-transactions)))
          (is (string= transaction-hash
                       (field (first pending-transactions) "hash")))
          (is (null (field (first pending-transactions) "blockHash"))))
        (let ((txpool-status (field txpool-status-response "result")))
          (is (string= (quantity-to-hex 1)
                       (field txpool-status "pending")))
          (is (string= (quantity-to-hex 0)
                       (field txpool-status "queued"))))
        (let* ((txpool-content (field txpool-content-response "result"))
               (pending (field txpool-content "pending"))
               (sender-transactions
                 (field pending
                        (address-to-hex
                         (or (transaction-sender transaction)
                             (zero-address)))))
               (nonce-transaction (field sender-transactions "9")))
          (is (string= transaction-hash
                       (field nonce-transaction "hash")))
          (is (null (field nonce-transaction "blockHash")))
          (is (search "\"queued\":{}" txpool-content-json)))
        (let* ((txpool-content-from
                 (field txpool-content-from-response "result"))
               (pending (field txpool-content-from "pending"))
               (nonce-transaction (field pending "9")))
          (is (string= transaction-hash
                       (field nonce-transaction "hash")))
          (is (search "\"queued\":{}" txpool-content-from-json))
          (is (search "\"pending\":{}" txpool-content-from-missing-json)))
        (let* ((txpool-inspect (field txpool-inspect-response "result"))
               (pending (field txpool-inspect "pending"))
               (sender-transactions
                 (field pending
                        (address-to-hex
                         (or (transaction-sender transaction)
                             (zero-address)))))
               (summary (field sender-transactions "9")))
          (is (string= (format nil "~A: 1000000000000000000 wei + 21000 gas x 20000000000 wei"
                               (address-to-hex recipient))
                       summary))
          (is (search "\"queued\":{}" txpool-inspect-json)))
        (engine-payload-store-put-block store mined-block)
        (let* ((mined-transaction-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   (concatenate
                    'string
                    "{\"jsonrpc\":\"2.0\",\"id\":82,"
                    "\"method\":\"eth_getTransactionByHash\","
                    "\"params\":[\"" transaction-hash "\"]}")
                   store
                   config)))
               (post-mined-pending-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":83,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                   store
                   config)))
               (post-mined-status-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":84,\"method\":\"txpool_status\",\"params\":[]}"
                   store
                   config)))
               (resend-mined-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   (concatenate
                    'string
                    "{\"jsonrpc\":\"2.0\",\"id\":85,"
                    "\"method\":\"eth_sendRawTransaction\","
                    "\"params\":[\"" raw-transaction "\"]}")
                   store
                   config)))
               (post-resend-pending-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":86,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                   store
                   config)))
               (post-resend-status-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":87,\"method\":\"txpool_status\",\"params\":[]}"
                   store
                   config)))
               (post-resend-filter-json
                 (engine-rpc-handle-request-json
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":88,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" pending-filter-id "\"]}")
                  store
                  config))
               (mined-transaction
                 (field mined-transaction-response "result"))
               (post-mined-status
                 (field post-mined-status-response "result"))
               (post-resend-status
                 (field post-resend-status-response "result")))
          (is (string= transaction-hash
                       (field mined-transaction "hash")))
          (is (string= (hash32-to-hex (block-hash mined-block))
                       (field mined-transaction "blockHash")))
          (is (string= (quantity-to-hex 15)
                       (field mined-transaction "blockNumber")))
          (is (string= (quantity-to-hex 0)
                       (field mined-transaction "transactionIndex")))
          (is (= 0 (length (field post-mined-pending-response "result"))))
          (is (string= (quantity-to-hex 0)
                       (field post-mined-status "pending")))
          (is (string= transaction-hash
                       (field resend-mined-response "result")))
          (is (= 0 (length (field post-resend-pending-response "result"))))
          (is (string= (quantity-to-hex 0)
                       (field post-resend-status "pending")))
          (is (search "\"result\":[]" post-resend-filter-json)))
        (is (= -32602
               (field (field invalid-rlp-response "error") "code")))
        (is (= -32602
               (field (field invalid-count-response "error") "code")))
        (is (= -32602
               (field (field invalid-pending-response "error") "code")))
        (is (= -32602
               (field (field invalid-new-pending-filter-response "error")
                      "code")))
        (is (= -32602
               (field (field invalid-txpool-status-response "error")
                      "code")))
        (is (= -32602
               (field (field invalid-txpool-content-response "error")
                      "code")))
        (is (= -32602
               (field (field invalid-txpool-content-from-count-response
                             "error")
                      "code")))
        (is (= -32602
               (field (field invalid-txpool-content-from-address-response
                             "error")
                      "code")))
        (is (= -32602
               (field (field invalid-txpool-inspect-response "error")
                      "code")))))))

(deftest eth-rpc-send-raw-transaction-requires-recoverable-sender
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (make-legacy-transaction
              :nonce 9
              :gas-price 20000000000
              :gas-limit 21000
              :to recipient
              :value 1000000000000000000
              :v 37
              :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
              :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
           (raw-transaction
             (bytes-to-hex (transaction-encoding transaction)))
           (config (make-chain-config :chain-id 2))
           (new-filter-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":92,\"method\":\"eth_newPendingTransactionFilter\"}"
               store
               config)))
           (filter-id (field new-filter-response "result"))
           (send-response
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":93,"
                "\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\"" raw-transaction "\"]}")
               store
               config)))
           (pending-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":94,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
               store
               config)))
           (status-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":95,\"method\":\"txpool_status\",\"params\":[]}"
               store
               config)))
           (filter-response
             (engine-rpc-handle-request-json
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":96,"
               "\"method\":\"eth_getFilterChanges\","
               "\"params\":[\"" filter-id "\"]}")
              store
              config))
           (send-error (field send-response "error"))
           (status (field status-response "result")))
      (is (= -32602 (field send-error "code")))
      (is (= 0 (length (field pending-response "result"))))
      (is (string= (quantity-to-hex 0) (field status "pending")))
      (is (search "\"result\":[]" filter-response)))))

(deftest eth-rpc-send-raw-transaction-rejects-malformed-signatures
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (address-from-hex "0x1111111111111111111111111111111111111111"))
           (bad-y-parity-transaction
             (make-dynamic-fee-transaction
              :chain-id 1
              :nonce 1
              :max-priority-fee-per-gas 0
              :max-fee-per-gas #x0fa0
              :gas-limit #x84d0
              :to recipient
              :value 0
              :y-parity 2
              :r #xb7dfab36232379bb3d1497a4f91c1966b1f932eae3ade107bf5d723b9cb474e0
              :s #x6261c359a10f2132f126d250485b90cf20f30340801244a08ef6142ab33d1904))
           (high-s-transaction
             (make-dynamic-fee-transaction
              :chain-id 1
              :nonce 1
              :max-priority-fee-per-gas 0
              :max-fee-per-gas #x0fa0
              :gas-limit #x84d0
              :to recipient
              :value 0
              :y-parity 1
              :r #xb7dfab36232379bb3d1497a4f91c1966b1f932eae3ade107bf5d723b9cb474e0
              :s #x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a1))
           (config (make-chain-config))
           (new-filter-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":100,\"method\":\"eth_newPendingTransactionFilter\"}"
               store
               config)))
           (filter-id (field new-filter-response "result"))
           (bad-y-parity-response
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":101,"
                "\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\""
                (bytes-to-hex
                 (transaction-encoding bad-y-parity-transaction))
                "\"]}")
               store
               config)))
           (high-s-response
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":102,"
                "\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\""
                (bytes-to-hex (transaction-encoding high-s-transaction))
                "\"]}")
               store
               config)))
           (pending-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":103,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
               store
               config)))
           (status-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":104,\"method\":\"txpool_status\",\"params\":[]}"
               store
               config)))
           (filter-response
             (engine-rpc-handle-request-json
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":105,"
               "\"method\":\"eth_getFilterChanges\","
               "\"params\":[\"" filter-id "\"]}")
              store
              config))
           (bad-y-parity-error (field bad-y-parity-response "error"))
           (high-s-error (field high-s-response "error"))
           (status (field status-response "result")))
      (is (= -32602 (field bad-y-parity-error "code")))
      (is (= -32602 (field high-s-error "code")))
      (is (= 0 (length (field pending-response "result"))))
      (is (string= (quantity-to-hex 0) (field status "pending")))
      (is (search "\"result\":[]" filter-response)))))

(deftest eth-rpc-send-raw-transaction-rejects-malformed-set-code-authorizations
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (send-raw (transaction id store config)
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
                ",\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\""
               (bytes-to-hex (transaction-encoding transaction))
               "\"]}")
               store
               config)))
           (first-authorization (transaction)
             (first (set-code-transaction-authorization-list transaction))))
    (let* ((raw-transaction
             "0x04f90126820539800285012a05f2008307a1209471562b71999873db5b286df957af199ec94617f78080c0f8baf85c82053994000000000000000000000000000000000000aaaa0101a07ed17af7d2d2b9ba7d797a202125bf505b9a0f962a67b3b61b56783d8faf7461a001b73b6e586edc706dce6c074eaec28692fa6359fb3446a2442f36777e1c0669f85a8094000000000000000000000000000000000000bbbb8001a05011890f198f0356a887b0779bde5afa1ed04e6acb1e3f37f8f18c7b6f521b98a056c3fa3456b103f3ef4a0acb4b647b9cab9ec4bc68fbcdf1e10b49fb2bcbcf6101a0167b0ecfc343a497095c22ee4270d3cc3b971cc3599fc73bbff727e0d2ed432da01c003c72306807492bf1150e39b2f79da23b49a4e83eb6e9209ae30d3572368f")
           (store (make-engine-payload-memory-store))
           (bad-y-parity-transaction
             (transaction-from-encoding (hex-to-bytes raw-transaction)))
           (high-s-transaction
             (transaction-from-encoding (hex-to-bytes raw-transaction)))
           (config (make-chain-config :chain-id 1337))
           (new-filter-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":106,\"method\":\"eth_newPendingTransactionFilter\"}"
               store
               config)))
           (filter-id (field new-filter-response "result")))
      (setf (set-code-authorization-y-parity
             (first-authorization bad-y-parity-transaction))
            2)
      (setf (set-code-authorization-s
             (first-authorization high-s-transaction))
            #x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a1)
      (let* ((bad-y-parity-response
               (send-raw bad-y-parity-transaction 107 store config))
             (high-s-response
               (send-raw high-s-transaction 108 store config))
             (pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":109,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                 store
                 config)))
             (status-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":110,\"method\":\"txpool_status\",\"params\":[]}"
                 store
                 config)))
             (filter-response
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":111,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (bad-y-parity-error (field bad-y-parity-response "error"))
             (high-s-error (field high-s-response "error"))
             (status (field status-response "result")))
        (is (= -32602 (field bad-y-parity-error "code")))
        (is (string= "Authorization signature values are invalid"
                     (field bad-y-parity-error "message")))
        (is (= -32602 (field high-s-error "code")))
        (is (string= "Authorization signature values are invalid"
                     (field high-s-error "message")))
        (is (= 0 (length (field pending-response "result"))))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (search "\"result\":[]" filter-response))))))

(deftest eth-rpc-get-transaction-receipt
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (make-address (make-byte-vector 20 :initial-element #x55)))
           (log-address
             (make-address (make-byte-vector 20 :initial-element #x66)))
           (topic-1 (make-hash32
                     (make-byte-vector 32 :initial-element #x11)))
           (topic-2 (make-hash32
                     (make-byte-vector 32 :initial-element #x22)))
           (tx-1 (make-legacy-transaction :nonce 5
                                          :gas-price 8
                                          :gas-limit 21000
                                          :to recipient
                                          :value 7))
           (tx-2 (make-dynamic-fee-transaction
                  :chain-id 1
                  :nonce 6
                  :max-priority-fee-per-gas 3
                  :max-fee-per-gas 10
                  :gas-limit 23000
                  :to recipient
                  :value 8
                  :y-parity 1
                  :r 6
                  :s 7))
           (receipt-1
             (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry
                           :address log-address
                           :topics (list topic-1)
                           :data #(1)))))
           (receipt-2
             (make-receipt
              :status 1
              :cumulative-gas-used 44000
              :logs (list (make-log-entry
                           :address log-address
                           :topics (list topic-2)
                           :data #(2 3)))))
           (block
             (make-block
              :header (make-block-header :number 15
                                         :timestamp 150
                                         :gas-limit 30000000
                                         :base-fee-per-gas 6)
              :transactions (list tx-1 tx-2)
              :receipts (list receipt-1 receipt-2)))
           (block-hash-hex (hash32-to-hex (block-hash block)))
           (tx-2-hash-hex (hash32-to-hex (transaction-hash tx-2)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((receipt-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":60,"
                  "\"method\":\"eth_getTransactionReceipt\","
                  "\"params\":[\"" tx-2-hash-hex "\"]}")
                 store
                 config)))
             (receipt-result (field receipt-response "result"))
             (logs (field receipt-result "logs"))
             (log (first logs))
             (removed-entry (assoc "removed" log :test #'string=))
             (topics (field log "topics"))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":61,"
                  "\"method\":\"eth_getTransactionReceipt\","
                  "\"params\":[\""
                  (hash32-to-hex (zero-hash32)) "\"]}")
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":62,\"method\":\"eth_getTransactionReceipt\",\"params\":[\"0x1234\"]}"
                 store
                 config)))
             (invalid-error (field invalid-response "error")))
        (is (string= tx-2-hash-hex
                     (field receipt-result "transactionHash")))
        (is (string= (quantity-to-hex 1)
                     (field receipt-result "transactionIndex")))
        (is (string= block-hash-hex (field receipt-result "blockHash")))
        (is (string= (quantity-to-hex 15)
                     (field receipt-result "blockNumber")))
        (is (string= (address-to-hex recipient)
                     (field receipt-result "to")))
        (is (string= (quantity-to-hex 44000)
                     (field receipt-result "cumulativeGasUsed")))
        (is (string= (quantity-to-hex 23000)
                     (field receipt-result "gasUsed")))
        (is (null (field receipt-result "contractAddress")))
        (is (= 1 (length logs)))
        (is (string= (address-to-hex log-address)
                     (field log "address")))
        (is (= 1 (length topics)))
        (is (string= (hash32-to-hex topic-2) (first topics)))
        (is (string= "0x0203" (field log "data")))
        (is (string= (quantity-to-hex 1) (field log "logIndex")))
        (is removed-entry)
        (is (null (cdr removed-entry)))
        (is (stringp (field receipt-result "logsBloom")))
        (is (string= (quantity-to-hex 2)
                     (field receipt-result "type")))
        (is (string= (quantity-to-hex 9)
                     (field receipt-result "effectiveGasPrice")))
        (is (string= (quantity-to-hex 1)
                     (field receipt-result "status")))
        (is (null (field missing-response "result")))
        (is (= -32602 (field invalid-error "code")))))))

(deftest eth-rpc-get-block-receipts
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (make-address (make-byte-vector 20 :initial-element #x77)))
           (log-address
             (make-address (make-byte-vector 20 :initial-element #x88)))
           (topic (make-hash32
                   (make-byte-vector 32 :initial-element #x33)))
           (tx-1 (make-legacy-transaction :nonce 7
                                          :gas-price 8
                                          :gas-limit 21000
                                          :to recipient
                                          :value 9))
           (tx-2 (make-dynamic-fee-transaction
                  :chain-id 1
                  :nonce 8
                  :max-priority-fee-per-gas 3
                  :max-fee-per-gas 10
                  :gas-limit 23000
                  :to recipient
                  :value 10
                  :y-parity 1
                  :r 8
                  :s 9))
           (receipt-1
             (make-receipt :status 1
                           :cumulative-gas-used 21000))
           (receipt-2
             (make-receipt
              :status 1
              :cumulative-gas-used 44000
              :logs (list (make-log-entry
                           :address log-address
                           :topics (list topic)
                           :data #(9)))))
           (block
             (make-block
              :header (make-block-header :number 16
                                         :timestamp 160
                                         :gas-limit 30000000
                                         :base-fee-per-gas 6)
              :transactions (list tx-1 tx-2)
              :receipts (list receipt-1 receipt-2)))
           (block-hash-hex (hash32-to-hex (block-hash block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((latest-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":63,\"method\":\"eth_getBlockReceipts\",\"params\":[\"latest\"]}"
                 store
                 config)))
             (latest-receipts (field latest-response "result"))
             (first-receipt (first latest-receipts))
             (second-receipt (second latest-receipts))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":64,"
                  "\"method\":\"eth_getBlockReceipts\","
                  "\"params\":[\"" block-hash-hex "\"]}")
                 store
                 config)))
             (hash-receipts (field hash-response "result"))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":65,\"method\":\"eth_getBlockReceipts\",\"params\":[\"0x63\"]}"
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":66,\"method\":\"eth_getBlockReceipts\",\"params\":[]}"
                 store
                 config)))
             (invalid-error (field invalid-response "error")))
        (is (= 2 (length latest-receipts)))
        (is (= 2 (length hash-receipts)))
        (is (string= (hash32-to-hex (transaction-hash tx-1))
                     (field first-receipt "transactionHash")))
        (is (string= (hash32-to-hex (transaction-hash tx-2))
                     (field second-receipt "transactionHash")))
        (is (string= block-hash-hex (field second-receipt "blockHash")))
        (is (string= (quantity-to-hex 16)
                     (field second-receipt "blockNumber")))
        (is (string= (quantity-to-hex 1)
                     (field second-receipt "transactionIndex")))
        (is (string= (quantity-to-hex 23000)
                     (field second-receipt "gasUsed")))
        (is (= 1 (length (field second-receipt "logs"))))
        (is (string= (quantity-to-hex 0)
                     (field (first (field second-receipt "logs"))
                            "logIndex")))
        (is (string= (field second-receipt "transactionHash")
                     (field (second hash-receipts)
                            "transactionHash")))
        (is (null (field missing-response "result")))
        (is (= -32602 (field invalid-error "code")))))))

(deftest eth-rpc-get-logs
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (make-address (make-byte-vector 20 :initial-element #x44)))
           (address-a
             (make-address (make-byte-vector 20 :initial-element #xaa)))
           (address-b
             (make-address (make-byte-vector 20 :initial-element #xbb)))
           (topic-a (make-hash32
                     (make-byte-vector 32 :initial-element #x11)))
           (topic-b (make-hash32
                     (make-byte-vector 32 :initial-element #x22)))
           (topic-c (make-hash32
                     (make-byte-vector 32 :initial-element #x33)))
           (tx-1 (make-legacy-transaction :nonce 1
                                          :gas-price 8
                                          :gas-limit 21000
                                          :to recipient
                                          :value 1))
           (tx-2 (make-legacy-transaction :nonce 2
                                          :gas-price 9
                                          :gas-limit 22000
                                          :to recipient
                                          :value 2))
           (tx-3 (make-legacy-transaction :nonce 3
                                          :gas-price 10
                                          :gas-limit 23000
                                          :to recipient
                                          :value 3))
           (tx-4 (make-legacy-transaction :nonce 4
                                          :gas-price 11
                                          :gas-limit 24000
                                          :to recipient
                                          :value 4))
           (receipt-1
             (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry
                           :address address-a
                           :topics (list topic-a topic-b)
                           :data #(1 2)))))
           (receipt-2
             (make-receipt
              :status 1
              :cumulative-gas-used 43000
              :logs (list (make-log-entry
                           :address address-b
                           :topics (list topic-a topic-c)
                           :data #(3)))))
           (receipt-3
             (make-receipt
              :status 1
              :cumulative-gas-used 23000
              :logs (list (make-log-entry
                           :address address-a
                           :topics (list topic-a topic-c)
                           :data #(4 5)))))
           (receipt-4
             (make-receipt
              :status 1
              :cumulative-gas-used 24000
              :logs (list (make-log-entry
                           :address address-a
                           :topics (list topic-a topic-b)
                           :data #(6)))))
           (block-1
             (make-block
              :header (make-block-header :number 40
                                         :timestamp 400
                                         :gas-limit 30000000)
              :transactions (list tx-1 tx-2)
              :receipts (list receipt-1 receipt-2)))
           (block-2
             (make-block
              :header (make-block-header :number 41
                                         :timestamp 410
                                         :gas-limit 30000000)
              :transactions (list tx-3)
              :receipts (list receipt-3)))
           (block-3
             (make-block
              :header (make-block-header :number 42
                                         :timestamp 420
                                         :gas-limit 30000000)
              :transactions (list tx-4)
              :receipts (list receipt-4)))
           (config (make-chain-config))
           (block-2-hash-hex (hash32-to-hex (block-hash block-2))))
      (engine-payload-store-put-block store block-1 :state-available-p t)
      (engine-payload-store-put-block store block-2 :state-available-p t)
      (let* ((range-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":67,"
                  "\"method\":\"eth_getLogs\","
                  "\"params\":[{\"fromBlock\":\"0x28\","
                  "\"toBlock\":\"0x28\","
                  "\"address\":\"" (address-to-hex address-a) "\","
                  "\"topics\":[\"" (hash32-to-hex topic-a) "\"]}]}")
                 store
                 config)))
             (range-logs (field range-response "result"))
             (range-log (first range-logs))
             (range-topics (field range-log "topics"))
             (block-hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":68,"
                  "\"method\":\"eth_getLogs\","
                  "\"params\":[{\"blockHash\":\"" block-2-hash-hex "\","
                  "\"topics\":[null,\"" (hash32-to-hex topic-c) "\"]}]}")
                 store
                 config)))
             (block-hash-logs (field block-hash-response "result"))
             (empty-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":69,"
                 "\"method\":\"eth_getLogs\","
                 "\"params\":[{\"fromBlock\":\"0x28\","
                 "\"toBlock\":\"0x29\","
                 "\"address\":\"" (address-to-hex recipient) "\"}]}")
                store
                config))
             (invalid-range-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":70,\"method\":\"eth_getLogs\",\"params\":[{\"fromBlock\":\"0x29\",\"toBlock\":\"0x28\"}]}"
                 store
                 config)))
             (invalid-range-error
               (field invalid-range-response "error"))
             (invalid-address-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":71,\"method\":\"eth_getLogs\",\"params\":[{\"address\":\"0x1234\"}]}"
                 store
                 config)))
             (invalid-address-error
               (field invalid-address-response "error")))
        (is (= 1 (length range-logs)))
        (is (string= (address-to-hex address-a)
                     (field range-log "address")))
        (is (string= "0x0102" (field range-log "data")))
        (is (string= (hash32-to-hex (block-hash block-1))
                     (field range-log "blockHash")))
        (is (string= (quantity-to-hex 40)
                     (field range-log "blockNumber")))
        (is (string= (hash32-to-hex (transaction-hash tx-1))
                     (field range-log "transactionHash")))
        (is (string= (quantity-to-hex 0)
                     (field range-log "transactionIndex")))
        (is (string= (quantity-to-hex 0)
                     (field range-log "logIndex")))
        (is (= 2 (length range-topics)))
        (is (string= (hash32-to-hex topic-a) (first range-topics)))
        (is (string= (hash32-to-hex topic-b) (second range-topics)))
        (is (= 1 (length block-hash-logs)))
        (is (string= block-2-hash-hex
                     (field (first block-hash-logs) "blockHash")))
        (is (string= (quantity-to-hex 41)
                     (field (first block-hash-logs) "blockNumber")))
        (is (search "\"result\":[]" empty-json))
        (is (= -32602 (field invalid-range-error "code")))
        (is (= -32602 (field invalid-address-error "code"))))
      (let* ((new-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":72,"
                  "\"method\":\"eth_newFilter\","
                  "\"params\":[{\"fromBlock\":\"0x28\","
                  "\"address\":\"" (address-to-hex address-a) "\","
                  "\"topics\":[\"" (hash32-to-hex topic-a) "\"]}]}")
                 store
                 config)))
             (filter-id (field new-filter-response "result"))
             (filter-logs-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":73,"
                  "\"method\":\"eth_getFilterLogs\","
                  "\"params\":[\"" filter-id "\"]}")
                 store
                 config)))
             (filter-logs (field filter-logs-response "result"))
             (first-changes-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":77,"
                  "\"method\":\"eth_getFilterChanges\","
                  "\"params\":[\"" filter-id "\"]}")
                 store
                 config)))
             (first-changes (field first-changes-response "result"))
             (second-changes-response
               (progn
                 (engine-payload-store-put-block
                  store block-3 :state-available-p t)
                 (parse-json
                  (engine-rpc-handle-request-json
                   (concatenate
                    'string
                    "{\"jsonrpc\":\"2.0\",\"id\":78,"
                    "\"method\":\"eth_getFilterChanges\","
                    "\"params\":[\"" filter-id "\"]}")
                   store
                   config))))
             (second-changes (field second-changes-response "result"))
             (empty-changes-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":79,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (uninstall-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":74,"
                  "\"method\":\"eth_uninstallFilter\","
                  "\"params\":[\"" filter-id "\"]}")
                 store
                 config)))
             (missing-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":75,"
                  "\"method\":\"eth_getFilterLogs\","
                  "\"params\":[\"" filter-id "\"]}")
                 store
                 config)))
             (missing-filter-error (field missing-filter-response "error"))
             (uninstall-missing-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":76,"
                 "\"method\":\"eth_uninstallFilter\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (uninstall-missing-response
               (parse-json uninstall-missing-json)))
        (is (string= (quantity-to-hex 1) filter-id))
        (is (= 2 (length filter-logs)))
        (is (string= (quantity-to-hex 40)
                     (field (first filter-logs) "blockNumber")))
        (is (string= (quantity-to-hex 41)
                     (field (second filter-logs) "blockNumber")))
        (is (= 2 (length first-changes)))
        (is (string= (quantity-to-hex 40)
                     (field (first first-changes) "blockNumber")))
        (is (string= (quantity-to-hex 41)
                     (field (second first-changes) "blockNumber")))
        (is (= 1 (length second-changes)))
        (is (string= (quantity-to-hex 42)
                     (field (first second-changes) "blockNumber")))
        (is (search "\"result\":[]" empty-changes-json))
        (is (eq t (field uninstall-response "result")))
        (is (= -32602 (field missing-filter-error "code")))
        (is (null (field uninstall-missing-response "result")))
        (is (search "\"result\":false" uninstall-missing-json))))))

(deftest eth-rpc-block-filter
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (block-1
             (make-block
              :header (make-block-header :number 7
                                         :timestamp 70
                                         :gas-limit 30000000)))
           (block-2
             (make-block
              :header (make-block-header :number 8
                                         :timestamp 80
                                         :gas-limit 30000000)))
           (block-3
             (make-block
              :header (make-block-header :number 10
                                         :timestamp 100
                                         :gas-limit 30000000))))
      (engine-payload-store-put-block store block-1 :state-available-p t)
      (let* ((new-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":80,\"method\":\"eth_newBlockFilter\"}"
                 store
                 config)))
             (filter-id (field new-filter-response "result"))
             (initial-changes-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":81,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (first-changes-response
               (progn
                 (engine-payload-store-put-block
                  store block-2 :state-available-p t)
                 (parse-json
                  (engine-rpc-handle-request-json
                   (concatenate
                    'string
                    "{\"jsonrpc\":\"2.0\",\"id\":82,"
                    "\"method\":\"eth_getFilterChanges\","
                    "\"params\":[\"" filter-id "\"]}")
                   store
                   config))))
             (first-changes (field first-changes-response "result"))
             (empty-changes-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":83,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (second-changes-response
               (progn
                 (engine-payload-store-put-block
                  store block-3 :state-available-p t)
                 (parse-json
                  (engine-rpc-handle-request-json
                   (concatenate
                    'string
                    "{\"jsonrpc\":\"2.0\",\"id\":84,"
                    "\"method\":\"eth_getFilterChanges\","
                    "\"params\":[\"" filter-id "\"]}")
                   store
                   config))))
             (second-changes (field second-changes-response "result"))
             (get-logs-error-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":85,"
                  "\"method\":\"eth_getFilterLogs\","
                  "\"params\":[\"" filter-id "\"]}")
                 store
                 config)))
             (uninstall-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":86,"
                  "\"method\":\"eth_uninstallFilter\","
                  "\"params\":[\"" filter-id "\"]}")
                 store
                 config)))
             (missing-changes-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":87,"
                  "\"method\":\"eth_getFilterChanges\","
                  "\"params\":[\"" filter-id "\"]}")
                 store
                 config)))
             (invalid-new-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":88,\"method\":\"eth_newBlockFilter\",\"params\":[\"unexpected\"]}"
                 store
                 config))))
        (is (string= (quantity-to-hex 1) filter-id))
        (is (search "\"result\":[]" initial-changes-json))
        (is (= 1 (length first-changes)))
        (is (string= (hash32-to-hex (block-hash block-2))
                     (first first-changes)))
        (is (search "\"result\":[]" empty-changes-json))
        (is (= 1 (length second-changes)))
        (is (string= (hash32-to-hex (block-hash block-3))
                     (first second-changes)))
        (is (= -32602
               (field (field get-logs-error-response "error") "code")))
        (is (eq t (field uninstall-response "result")))
        (is (= -32602
               (field (field missing-changes-response "error") "code")))
        (is (= -32602
               (field (field invalid-new-filter-response "error")
                      "code")))))))

(deftest engine-rpc-http-post-dispatches-json-rpc
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (http-body (response)
             (let ((boundary (search (format nil "~C~C~C~C"
                                             #\Return #\Newline
                                             #\Return #\Newline)
                                     response)))
               (subseq response (+ boundary 4))))
           (http-status (response)
             (let* ((line-end (position #\Return response))
                    (status-line (subseq response 0 line-end)))
               (parse-integer status-line :start 9 :end 12))))
    (let* ((body
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":17,"
              "\"method\":\"engine_getClientVersionV1\","
              "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
              "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
           (request
             (format nil
                     "POST / HTTP/1.1~%Host: localhost~%Content-Type: application/json; charset=utf-8~%Content-Length: ~D~%~%~A"
                     (length body)
                     body))
           (http-response
             (engine-rpc-handle-http-request-string
              request
              (make-engine-payload-memory-store)
              (make-chain-config)))
           (rpc-response (parse-json (http-body http-response)))
           (local (first (field rpc-response "result"))))
      (is (= 200 (http-status http-response)))
      (is (= 17 (field rpc-response "id")))
      (is (string= "ethereum-lisp" (field local "name"))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
Content-Type: text/plain

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 415 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "PUT / HTTP/1.1
Content-Type: application/json

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 405 (http-status response))))))

(deftest engine-rpc-http-validates-jwt-bearer-auth
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (http-body (response)
             (let ((boundary (search (format nil "~C~C~C~C"
                                             #\Return #\Newline
                                             #\Return #\Newline)
                                     response)))
               (subseq response (+ boundary 4))))
           (http-status (response)
             (let* ((line-end (position #\Return response))
                    (status-line (subseq response 0 line-end)))
               (parse-integer status-line :start 9 :end 12)))
           (request (body &key token)
             (with-output-to-string (stream)
               (format stream "POST / HTTP/1.1~%Host: localhost~%")
               (format stream "Content-Type: application/json~%")
               (when token
                 (format stream "Authorization: Bearer ~A~%" token))
               (format stream "Content-Length: ~D~%~%~A" (length body) body))))
    (let* ((secret (make-byte-vector 32 :initial-element #x42))
           (now 1000)
           (body
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":18,"
              "\"method\":\"engine_getClientVersionV1\","
              "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
              "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
           (token (engine-rpc-make-jwt-token secret now))
           (http-response
             (engine-rpc-handle-http-request-string
              (request body :token token)
              (make-engine-payload-memory-store)
              (make-chain-config)
              :jwt-secret secret
              :now now))
           (rpc-response (parse-json (http-body http-response)))
           (local (first (field rpc-response "result"))))
      (is (string=
           "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjEwMDB9.WR0G-_BFmXHetdB5_3grgcntOfG-gyUJd1ALOObOAbM"
           token))
      (is (= 200 (http-status http-response)))
      (is (= 18 (field rpc-response "id")))
      (is (string= "ethereum-lisp" (field local "name")))
      (let ((missing-response
              (engine-rpc-handle-http-request-string
               (request body)
               (make-engine-payload-memory-store)
               (make-chain-config)
               :jwt-secret secret
               :now now)))
        (is (= 401 (http-status missing-response))))
      (let* ((stale-token (engine-rpc-make-jwt-token secret (- now 61)))
             (stale-response
               (engine-rpc-handle-http-request-string
                (request body :token stale-token)
                (make-engine-payload-memory-store)
                (make-chain-config)
                :jwt-secret secret
                :now now)))
        (is (= 401 (http-status stale-response))))
      (let* ((expired-token
               (engine-rpc-make-jwt-token
                secret now :expires-at (1- now)))
             (expired-response
               (engine-rpc-handle-http-request-string
                (request body :token expired-token)
                (make-engine-payload-memory-store)
                (make-chain-config)
                :jwt-secret secret
                :now now)))
        (is (= 401 (http-status expired-response)))))))

(deftest engine-rpc-http-stream-handles-single-connection
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (http-body (response)
             (let ((boundary (search (format nil "~C~C~C~C"
                                             #\Return #\Newline
                                             #\Return #\Newline)
                                     response)))
               (subseq response (+ boundary 4))))
           (http-status (response)
             (let* ((line-end (position #\Return response))
                    (status-line (subseq response 0 line-end)))
               (parse-integer status-line :start 9 :end 12))))
    (let* ((secret (make-byte-vector 32 :initial-element #x24))
           (now 2000)
           (token (engine-rpc-make-jwt-token secret now))
           (body
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":19,"
              "\"method\":\"engine_getClientVersionV1\","
              "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
              "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
           (request
             (format nil
                     "POST / HTTP/1.1~%Host: localhost~%Content-Type: application/json~%Authorization: Bearer ~A~%Content-Length: ~D~%~%~A"
                     token
                     (length body)
                     body))
           (input (make-string-input-stream request))
           (output (make-string-output-stream))
           (returned-response
             (engine-rpc-handle-http-stream
              input
              output
              (make-engine-payload-memory-store)
              (make-chain-config)
              :jwt-secret secret
              :now now))
           (written-response (get-output-stream-string output))
           (rpc-response (parse-json (http-body written-response)))
           (local (first (field rpc-response "result"))))
      (is (string= returned-response written-response))
      (is (= 200 (http-status written-response)))
      (is (= 19 (field rpc-response "id")))
      (is (string= "ethereum-lisp" (field local "name"))))
    (let* ((input
             (make-string-input-stream
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: 4

{}"))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input
       output
       (make-engine-payload-memory-store)
       (make-chain-config))
      (is (= 400 (http-status (get-output-stream-string output)))))))

(deftest engine-rpc-http-service-wraps-stream-configuration
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (http-body (response)
             (let ((boundary (search (format nil "~C~C~C~C"
                                             #\Return #\Newline
                                             #\Return #\Newline)
                                     response)))
               (subseq response (+ boundary 4))))
           (http-status (response)
             (let* ((line-end (position #\Return response))
                    (status-line (subseq response 0 line-end)))
               (parse-integer status-line :start 9 :end 12))))
    (let* ((default-service (make-engine-rpc-http-service))
           (secret (make-byte-vector 32 :initial-element #x55))
           (now 3000)
           (service
             (make-engine-rpc-http-service
              :host "127.0.0.1"
              :port 8551
              :jwt-secret secret
              :now-provider (lambda () now))))
      (is (string= "localhost:8551"
                   (engine-rpc-http-service-endpoint default-service)))
      (is (string= "127.0.0.1:8551"
                   (engine-rpc-http-service-endpoint service)))
      (is (typep (engine-rpc-http-service-store service)
                 'engine-payload-memory-store))
      (is (typep (engine-rpc-http-service-config service) 'chain-config))
      (let* ((body
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":20,"
                "\"method\":\"engine_getClientVersionV1\","
                "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
                "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
             (token (engine-rpc-make-jwt-token secret now))
             (request
               (format nil
                       "POST / HTTP/1.1~%Host: localhost~%Content-Type: application/json~%Authorization: Bearer ~A~%Content-Length: ~D~%~%~A"
                       token
                       (length body)
                       body))
             (input (make-string-input-stream request))
             (output (make-string-output-stream))
             (response
               (engine-rpc-http-service-handle-stream
                service input output))
             (rpc-response (parse-json (http-body response)))
             (local (first (field rpc-response "result"))))
        (is (= 200 (http-status response)))
        (is (string= response (get-output-stream-string output)))
        (is (= 20 (field rpc-response "id")))
        (is (string= "ethereum-lisp" (field local "name"))))
      (signals block-validation-error
        (make-engine-rpc-http-service :port 70000))
      (signals block-validation-error
        (make-engine-rpc-http-service
         :jwt-secret (make-byte-vector 31 :initial-element 1))))))

(deftest engine-rpc-http-service-serves-listener-connections
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (http-body (response)
             (let ((boundary (search (format nil "~C~C~C~C"
                                             #\Return #\Newline
                                             #\Return #\Newline)
                                     response)))
               (subseq response (+ boundary 4))))
           (http-status (response)
             (let* ((line-end (position #\Return response))
                    (status-line (subseq response 0 line-end)))
               (parse-integer status-line :start 9 :end 12)))
           (request (id)
             (let ((body
                     (format nil
                             "{\"jsonrpc\":\"2.0\",\"id\":~D,\"method\":\"engine_getClientVersionV1\",\"params\":[{\"code\":\"TT\",\"name\":\"test\",\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"
                             id)))
               (format nil
                       "POST / HTTP/1.1~%Host: localhost~%Content-Type: application/json~%Content-Length: ~D~%~%~A"
                       (length body)
                       body))))
    (let* ((service (make-engine-rpc-http-service))
           (output-a (make-string-output-stream))
           (output-b (make-string-output-stream))
           (closed-connections 0)
           (closed-listener-p nil)
           (connections
             (list
              (make-engine-rpc-http-connection
               :input-stream (make-string-input-stream (request 21))
               :output-stream output-a
               :close-function (lambda () (incf closed-connections)))
              (make-engine-rpc-http-connection
               :input-stream (make-string-input-stream (request 22))
               :output-stream output-b
               :close-function (lambda () (incf closed-connections)))))
           (listener
             (make-engine-rpc-http-listener
              :endpoint (engine-rpc-http-service-endpoint service)
              :accept-function
              (lambda ()
                (when connections
                  (pop connections)))
              :close-function
              (lambda () (setf closed-listener-p t)))))
      (is (string= "localhost:8551"
                   (engine-rpc-http-listener-endpoint listener)))
      (is (= 2 (engine-rpc-http-service-serve-listener
                service listener :max-connections 10)))
      (is (= 2 closed-connections))
      (is closed-listener-p)
      (let* ((response-a (get-output-stream-string output-a))
             (response-b (get-output-stream-string output-b))
             (rpc-a (parse-json (http-body response-a)))
             (rpc-b (parse-json (http-body response-b))))
        (is (= 200 (http-status response-a)))
        (is (= 200 (http-status response-b)))
        (is (= 21 (field rpc-a "id")))
        (is (= 22 (field rpc-b "id"))))
      (signals block-validation-error
        (engine-rpc-http-listener-accept
         (make-engine-rpc-http-listener
          :endpoint "localhost:8551"
          :accept-function (lambda () "not-a-connection"))))
      (signals block-validation-error
        (engine-rpc-http-service-serve-listener
         service listener :max-connections -1)))))

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
  (let* ((block (make-block :requests (list #(#x00 #xbb) #(#x01 #xaa))))
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
    (is (bytes= (block-access-list-rlp (list account))
                (block-encoded-block-access-list block)))
    (is (string= (hash32-to-hex (block-access-list-hash (list account)))
                 (hash32-to-hex
                  (block-header-block-access-list-hash
                   (block-header block))))))
  (let* ((account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")))
         (encoded (block-access-list-rlp (list account)))
         (block (make-block :block-access-list-rlp encoded)))
    (is (block-block-access-list-present-p block))
    (is (bytes= encoded (block-encoded-block-access-list block)))
    (is (bytes= encoded
                (block-access-list-rlp (block-block-access-list block))))
    (is (string= (hash32-to-hex (block-access-list-rlp-hash encoded))
                 (hash32-to-hex
                  (block-header-block-access-list-hash
                   (block-header block)))))
    (is (validate-block-body-roots block))
    (setf (block-encoded-block-access-list block) (block-access-list-rlp '()))
    (signals block-validation-error
      (validate-block-body-roots block))
    (signals block-validation-error
      (make-block :block-access-list (list account)
                  :block-access-list-rlp encoded)))
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
    (let ((decoded (transaction-from-encoding
                    (access-list-transaction-encoding tx1))))
      (is (typep decoded 'access-list-transaction))
      (is (= 1 (access-list-transaction-chain-id decoded)))
      (is (= 2 (access-list-transaction-nonce decoded)))
      (is (= 3 (access-list-transaction-gas-price decoded)))
      (is (= 4 (access-list-transaction-gas-limit decoded)))
      (is (string= (address-to-hex recipient)
                   (address-to-hex (access-list-transaction-to decoded))))
      (is (= 5 (access-list-transaction-value decoded)))
      (is (bytes= #(6) (access-list-transaction-data decoded)))
      (is (= 1 (length (access-list-transaction-access-list decoded))))
      (is (bytes= (hash32-bytes slot)
                  (hash32-bytes
                   (first (access-list-entry-storage-keys
                           (first (access-list-transaction-access-list
                                   decoded)))))))
      (is (= 1 (access-list-transaction-y-parity decoded)))
      (is (= 7 (access-list-transaction-r decoded)))
      (is (= 8 (access-list-transaction-s decoded)))
      (is (bytes= (access-list-transaction-encoding tx1)
                  (access-list-transaction-encoding decoded))))
    (signals block-validation-error
      (access-list-transaction-from-rlp (rlp-encode (list 1 2 3))))
    (signals block-validation-error
      (access-list-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4
                       (make-byte-vector 20)
                       5
                       (make-byte-vector 1 :initial-element 6)
                       (make-rlp-list
                        (make-rlp-list
                         (make-byte-vector 19)
                         (make-rlp-list)))
                       1 7 8))))
    (let ((decoded (transaction-from-encoding
                    (dynamic-fee-transaction-encoding tx2))))
      (is (typep decoded 'dynamic-fee-transaction))
      (is (= 1 (dynamic-fee-transaction-chain-id decoded)))
      (is (= 2 (dynamic-fee-transaction-nonce decoded)))
      (is (= 3 (dynamic-fee-transaction-max-priority-fee-per-gas decoded)))
      (is (= 4 (dynamic-fee-transaction-max-fee-per-gas decoded)))
      (is (= 5 (dynamic-fee-transaction-gas-limit decoded)))
      (is (string= (address-to-hex recipient)
                   (address-to-hex (dynamic-fee-transaction-to decoded))))
      (is (= 6 (dynamic-fee-transaction-value decoded)))
      (is (bytes= #(7) (dynamic-fee-transaction-data decoded)))
      (is (= 1 (length (dynamic-fee-transaction-access-list decoded))))
      (is (bytes= (hash32-bytes slot)
                  (hash32-bytes
                   (first (access-list-entry-storage-keys
                           (first (dynamic-fee-transaction-access-list
                                   decoded)))))))
      (is (= 1 (dynamic-fee-transaction-y-parity decoded)))
      (is (= 8 (dynamic-fee-transaction-r decoded)))
      (is (= 9 (dynamic-fee-transaction-s decoded)))
      (is (bytes= (dynamic-fee-transaction-encoding tx2)
                  (dynamic-fee-transaction-encoding decoded))))
    (signals block-validation-error
      (dynamic-fee-transaction-from-rlp (rlp-encode (list 1 2 3))))
    (signals block-validation-error
      (dynamic-fee-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4 5
                       (make-byte-vector 20)
                       6
                       (make-byte-vector 1 :initial-element 7)
                       (make-rlp-list
                        (make-rlp-list
                         (make-byte-vector 20)
                         (make-rlp-list (make-byte-vector 31))))
                       1 8 9))))
    (let ((decoded (transaction-from-encoding
                    (blob-transaction-encoding tx3))))
      (is (typep decoded 'blob-transaction))
      (is (= 1 (blob-transaction-chain-id decoded)))
      (is (= 2 (blob-transaction-nonce decoded)))
      (is (= 3 (blob-transaction-max-priority-fee-per-gas decoded)))
      (is (= 4 (blob-transaction-max-fee-per-gas decoded)))
      (is (= 5 (blob-transaction-gas-limit decoded)))
      (is (string= (address-to-hex recipient)
                   (address-to-hex (blob-transaction-to decoded))))
      (is (= 6 (blob-transaction-value decoded)))
      (is (bytes= #(7) (blob-transaction-data decoded)))
      (is (= 1 (length (blob-transaction-access-list decoded))))
      (is (= 10 (blob-transaction-max-fee-per-blob-gas decoded)))
      (is (= 1 (length (blob-transaction-blob-versioned-hashes decoded))))
      (is (bytes= (hash32-bytes blob-hash)
                  (hash32-bytes
                   (first (blob-transaction-blob-versioned-hashes decoded)))))
      (is (= 1 (blob-transaction-y-parity decoded)))
      (is (= 8 (blob-transaction-r decoded)))
      (is (= 9 (blob-transaction-s decoded)))
      (is (bytes= (blob-transaction-encoding tx3)
                  (blob-transaction-encoding decoded))))
    (signals block-validation-error
      (blob-transaction-from-rlp (rlp-encode (list 1 2 3))))
    (signals block-validation-error
      (blob-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4 5
                       (make-byte-vector 0)
                       6
                       (make-byte-vector 1 :initial-element 7)
                       (make-rlp-list)
                       10
                       (make-rlp-list (hash32-bytes blob-hash))
                       1 8 9))))
    (signals block-validation-error
      (blob-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4 5
                       (address-bytes recipient)
                       6
                       (make-byte-vector 1 :initial-element 7)
                       (make-rlp-list)
                       10
                       (make-rlp-list (make-byte-vector 31))
                       1 8 9))))
    (let ((decoded (transaction-from-encoding
                    (set-code-transaction-encoding tx4))))
      (is (typep decoded 'set-code-transaction))
      (is (= 1 (set-code-transaction-chain-id decoded)))
      (is (= 2 (set-code-transaction-nonce decoded)))
      (is (= 3 (set-code-transaction-max-priority-fee-per-gas decoded)))
      (is (= 4 (set-code-transaction-max-fee-per-gas decoded)))
      (is (= 5 (set-code-transaction-gas-limit decoded)))
      (is (string= (address-to-hex recipient)
                   (address-to-hex (set-code-transaction-to decoded))))
      (is (= 6 (set-code-transaction-value decoded)))
      (is (bytes= #(7) (set-code-transaction-data decoded)))
      (is (= 1 (length (set-code-transaction-access-list decoded))))
      (is (= 1 (length (set-code-transaction-authorization-list decoded))))
      (let ((decoded-authorization
              (first (set-code-transaction-authorization-list decoded))))
        (is (= 1 (set-code-authorization-chain-id decoded-authorization)))
        (is (string= (address-to-hex recipient)
                     (address-to-hex
                      (set-code-authorization-address
                       decoded-authorization))))
        (is (= 11 (set-code-authorization-nonce decoded-authorization)))
        (is (= 1 (set-code-authorization-y-parity decoded-authorization)))
        (is (= 12 (set-code-authorization-r decoded-authorization)))
        (is (= 13 (set-code-authorization-s decoded-authorization))))
      (is (= 1 (set-code-transaction-y-parity decoded)))
      (is (= 8 (set-code-transaction-r decoded)))
      (is (= 9 (set-code-transaction-s decoded)))
      (is (bytes= (set-code-transaction-encoding tx4)
                  (set-code-transaction-encoding decoded))))
    (signals block-validation-error
      (set-code-transaction-from-rlp (rlp-encode (list 1 2 3))))
    (signals block-validation-error
      (set-code-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4 5
                       (make-byte-vector 0)
                       6
                       (make-byte-vector 1 :initial-element 7)
                       (make-rlp-list)
                       (make-rlp-list
                        (make-rlp-list 1
                                       (address-bytes recipient)
                                       11 1 12 13))
                       1 8 9))))
    (signals block-validation-error
      (set-code-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4 5
                       (address-bytes recipient)
                       6
                       (make-byte-vector 1 :initial-element 7)
                       (make-rlp-list)
                       (make-rlp-list
                        (make-rlp-list 1
                                       (make-byte-vector 0)
                                       11 1 12 13))
                       1 8 9))))
    (is (hash32-p (transaction-hash tx1)))
    (is (hash32-p (blob-transaction-signing-hash tx3)))
    (is (not (string= (hash32-to-hex (blob-transaction-signing-hash tx3))
                      (hash32-to-hex (blob-transaction-hash tx3)))))
    (is (hash32-p (set-code-authorization-signing-hash authorization)))
    (is (hash32-p (set-code-transaction-signing-hash tx4)))
    (is (not (string= (hash32-to-hex (set-code-transaction-signing-hash tx4))
                      (hash32-to-hex (set-code-transaction-hash tx4)))))
    (is (hash32-p (transaction-list-root (list tx1 tx2 tx3 tx4))))))
