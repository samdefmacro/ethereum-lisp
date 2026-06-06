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

(defun fixture-private-key-address (private-key)
  (let* ((point
           (ethereum-lisp.crypto::secp256k1-scalar-multiply
            private-key
            (ethereum-lisp.crypto::secp256k1-point
             ethereum-lisp.crypto::+secp256k1-gx+
             ethereum-lisp.crypto::+secp256k1-gy+)))
         (public-key
           (concat-bytes
            (ethereum-lisp.crypto::integer-to-fixed-bytes
             (ethereum-lisp.crypto::secp256k1-point-x point) 32)
            (ethereum-lisp.crypto::integer-to-fixed-bytes
             (ethereum-lisp.crypto::secp256k1-point-y point) 32)))
         (hashed (keccak-256 public-key))
         (bytes (make-byte-vector 20)))
    (replace bytes hashed :start2 12)
    (make-address bytes)))

(defun fixture-sign-legacy-transaction (transaction private-key chain-id)
  (let* ((n ethereum-lisp.crypto::+secp256k1-n+)
         (half-n ethereum-lisp.crypto::+secp256k1-half-n+)
         (generator
           (ethereum-lisp.crypto::secp256k1-point
            ethereum-lisp.crypto::+secp256k1-gx+
            ethereum-lisp.crypto::+secp256k1-gy+))
         (hash (legacy-transaction-signing-hash transaction
                                                :chain-id chain-id))
         (message (bytes-to-integer (hash32-bytes hash)))
         (expected-sender (fixture-private-key-address private-key)))
    (loop for k from 1 below 256
          for r-point =
            (ethereum-lisp.crypto::secp256k1-scalar-multiply k generator)
          for r =
            (mod (ethereum-lisp.crypto::secp256k1-point-x r-point) n)
          for inverse-k = (ethereum-lisp.crypto::modular-inverse k n)
          when (and (plusp r) inverse-k)
            do (let* ((raw-s
                        (mod (* (+ message (* r private-key)) inverse-k) n))
                      (s raw-s)
                      (y-parity
                        (if (oddp
                             (ethereum-lisp.crypto::secp256k1-point-y
                              r-point))
                            1
                            0)))
                 (when (plusp raw-s)
                   (when (> s half-n)
                     (setf s (- n s)
                           y-parity (- 1 y-parity)))
                   (let ((signed
                           (make-legacy-transaction
                            :nonce (legacy-transaction-nonce transaction)
                            :gas-price
                            (legacy-transaction-gas-price transaction)
                            :gas-limit
                            (legacy-transaction-gas-limit transaction)
                            :to (legacy-transaction-to transaction)
                            :value (legacy-transaction-value transaction)
                            :data (legacy-transaction-data transaction)
                            :v (+ 35 (* 2 chain-id) y-parity)
                            :r r
                            :s s)))
                     (when (bytes=
                            (address-bytes expected-sender)
                            (address-bytes
                             (legacy-transaction-sender
                              signed :expected-chain-id chain-id)))
                       (return signed)))))
          finally
            (error "Unable to sign legacy transaction fixture"))))

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

(deftest block-from-rlp-decodes-shanghai-empty-body
  (let* ((encoded
           (hex-to-bytes
            "0xf90217f90211a0bd0bfa5377fdd562a7700ec0eab46dcd83a4ba67a3448fc990876c4ff23ec4f6a01dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347940000000000000000000000000000000000000001a056e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421a056e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421a056e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421b9010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000802a82c350806380a0000000000000000000000000000000000000000000000000000000000000000088000000000000000064a056e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421c0c0c0"))
         (block (block-from-rlp encoded))
         (header (block-header block)))
    (is (string= "0x9937880e9ca0115d6d631f925a1b1559d539eff54dde8813c393baec0b82e77b"
                 (hash32-to-hex (block-hash block))))
    (is (string= "0xbd0bfa5377fdd562a7700ec0eab46dcd83a4ba67a3448fc990876c4ff23ec4f6"
                 (hash32-to-hex (block-header-parent-hash header))))
    (is (= #x2a (block-header-number header)))
    (is (= #xc350 (block-header-gas-limit header)))
    (is (= 0 (block-header-gas-used header)))
    (is (= #x64 (block-header-base-fee-per-gas header)))
    (is (block-withdrawals-present-p block))
    (is (= 0 (length (block-withdrawals block))))
    (is (= 0 (length (block-transactions block))))
    (is (= 0 (length (block-ommers block))))))

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

(deftest engine-new-payload-memory-status-validates-known-parent-before-accepted
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
                        :timestamp 98
                        :base-fee-per-gas 100))
         (child-block (make-block :header child-header))
         (payload (execution-payload-envelope-execution-payload
                   (block-to-executable-data child-block)))
         (store (make-engine-payload-memory-store)))
    (engine-payload-store-put-block store parent-block)
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status store 1 payload config)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (string= (hash32-to-hex (block-hash parent-block))
                   (hash32-to-hex
                    (payload-status-latest-valid-hash status))))
      (is (search "Timestamp is not greater than parent timestamp"
                  (payload-status-validation-error status)))
      (is (not block))
      (is (not (engine-payload-store-remote-block
                store
                (block-hash child-block)))))))

(deftest engine-new-payload-memory-status-imports-executable-block
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (config (make-chain-config :chain-id 1 :london-block 0))
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
         (store (make-engine-payload-memory-store)))
    (engine-payload-store-put-block
     store parent-block :state-available-p t)
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status
         store 1 payload config
         :import-function #'execute-and-commit-engine-payload)
      (is (string= +payload-status-valid+ (payload-status-status status)))
      (is (typep block 'ethereum-block))
      (is (engine-payload-store-known-block store (block-hash child-block)))
      (is (chain-store-state-available-p store (block-hash child-block)))
      (is (typep (chain-store-state-db store (block-hash child-block))
                 'state-db)))))

(deftest engine-new-payload-memory-status-executes-known-unprocessed-block
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (config (make-chain-config :chain-id 1 :london-block 0))
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
         (store (make-engine-payload-memory-store)))
    (engine-payload-store-put-block
     store parent-block :state-available-p t)
    (engine-payload-store-put-block store child-block)
    (is (not (chain-store-state-available-p store (block-hash child-block))))
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status
         store 1 payload config
         :import-function #'execute-and-commit-engine-payload)
      (is (string= +payload-status-valid+ (payload-status-status status)))
      (is (typep block 'ethereum-block))
      (is (chain-store-state-available-p store (block-hash child-block)))
      (is (typep (chain-store-state-db store (block-hash child-block))
                 'state-db)))))

(deftest engine-new-payload-memory-status-maps-execution-failure-invalid
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (config (make-chain-config :chain-id 1 :london-block 0))
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
         (bad-child-header (make-block-header
                            :parent-hash (block-hash parent-block)
                            :beneficiary address
                            :state-root (zero-hash32)
                            :mix-hash (zero-hash32)
                            :number 42
                            :gas-limit 50000
                            :gas-used 0
                            :timestamp 99
                            :base-fee-per-gas 100))
         (bad-child-block (make-block :header bad-child-header))
         (payload (execution-payload-envelope-execution-payload
                   (block-to-executable-data bad-child-block)))
         (store (make-engine-payload-memory-store)))
    (engine-payload-store-put-block
     store parent-block :state-available-p t)
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status
         store 1 payload config
         :import-function #'execute-and-commit-engine-payload)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (string= "State root mismatch"
                   (payload-status-validation-error status)))
      (is (string= (hash32-to-hex (block-hash parent-block))
                   (hash32-to-hex
                    (payload-status-latest-valid-hash status))))
      (is (not block))
      (is (not (chain-store-known-block store (block-hash bad-child-block))))
      (is (engine-payload-store-invalid-block
           store
           (block-hash bad-child-block))))))

(deftest engine-new-payload-memory-status-maps-post-execution-commitments-invalid
  (labels ((nonempty-bloom ()
             (let ((bloom (make-byte-vector 256)))
               (setf (aref bloom 0) 1)
               bloom))
           (bad-child-block (parent-block beneficiary &rest header-args)
             (let ((header
                     (make-block-header
                      :parent-hash (block-hash parent-block)
                      :beneficiary beneficiary
                      :state-root +empty-trie-hash+
                      :mix-hash (zero-hash32)
                      :number 42
                      :gas-limit 50000
                      :gas-used 0
                      :timestamp 99
                      :base-fee-per-gas 100)))
               (let ((block (make-block :header header)))
                 (loop for (key value) on header-args by #'cddr
                       do (ecase key
                            (:state-root
                             (setf (block-header-state-root header) value))
                            (:receipts-root
                             (setf (block-header-receipts-root header) value))
                            (:logs-bloom
                             (setf (block-header-logs-bloom header) value))
                            (:gas-used
                             (setf (block-header-gas-used header) value))))
                 block)))
           (check-case (name parent-block bad-block expected-error)
             (declare (ignore name))
             (let* ((config (make-chain-config :chain-id 1 :london-block 0))
                    (store (make-engine-payload-memory-store))
                    (payload
                      (execution-payload-envelope-execution-payload
                       (block-to-executable-data bad-block))))
               (engine-payload-store-put-block
                store parent-block :state-available-p t)
               (multiple-value-bind (status block)
                   (engine-new-payload-memory-status
                    store 1 payload config
                    :import-function #'execute-and-commit-engine-payload)
                 (is (string= +payload-status-invalid+
                              (payload-status-status status)))
                 (is (string= expected-error
                              (payload-status-validation-error status)))
                 (is (string= (hash32-to-hex (block-hash parent-block))
                              (hash32-to-hex
                               (payload-status-latest-valid-hash status))))
                 (is (not block))
                 (is (not (chain-store-known-block
                           store (block-hash bad-block))))
                 (is (engine-payload-store-invalid-block
                      store
                      (block-hash bad-block)))))))
    (let* ((beneficiary
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (parent-block
             (make-block
              :header (make-block-header
                       :parent-hash (zero-hash32)
                       :beneficiary beneficiary
                       :state-root +empty-trie-hash+
                       :mix-hash (zero-hash32)
                       :number 41
                       :gas-limit 50000
                       :gas-used 25000
                       :timestamp 98
                       :base-fee-per-gas 100))))
      (check-case
       "state root"
       parent-block
       (bad-child-block parent-block beneficiary
                        :state-root (zero-hash32))
       "State root mismatch")
      (check-case
       "receipts root"
       parent-block
       (bad-child-block parent-block beneficiary
                        :receipts-root (zero-hash32))
       "Receipts root mismatch")
      (check-case
       "logs bloom"
       parent-block
       (bad-child-block parent-block beneficiary
                        :logs-bloom (nonempty-bloom))
       "Logs bloom mismatch")
      (check-case
       "gas used"
       parent-block
       (bad-child-block parent-block beneficiary
                        :gas-used 1)
       "Gas used mismatch"))))

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

(deftest chain-store-state-db-reconstructs-account-projection
  (let* ((store (make-engine-payload-memory-store))
         (missing-state-store (make-engine-payload-memory-store))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (storage-only
           (address-from-hex "0x0000000000000000000000000000000000000002"))
         (storage-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000003"))
         (storage-only-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000004"))
         (block
           (make-block
            :header
            (make-block-header :number 44
                               :state-root +empty-trie-hash+)))
         (block-hash (block-hash block)))
    (chain-store-put-block missing-state-store block)
    (chain-store-put-block store block :state-available-p t)
    (chain-store-put-account-balance store block-hash address 99)
    (chain-store-put-account-nonce store block-hash address 7)
    (chain-store-put-account-code store block-hash address #(96 42 0))
    (chain-store-put-account-storage store block-hash address storage-slot 5)
    (chain-store-put-account-storage
     store block-hash storage-only storage-only-slot 11)
    (is (not (chain-store-state-db missing-state-store block-hash)))
    (let* ((state (chain-store-state-db store block-hash))
           (account (state-db-get-account state address))
           (storage-only-account
             (state-db-get-account state storage-only)))
      (is (typep state 'state-db))
      (is (= 99 (state-account-balance account)))
      (is (= 7 (state-account-nonce account)))
      (is (bytes= #(96 42 0) (state-db-get-code state address)))
      (is (= 5 (state-db-get-storage state address storage-slot)))
      (is (= 0 (state-account-balance storage-only-account)))
      (is (= 0 (state-account-nonce storage-only-account)))
      (is (= 11
             (state-db-get-storage
              state storage-only storage-only-slot))))))

(deftest chain-store-for-each-account-iterates-deterministically
  (let* ((store (make-engine-payload-memory-store))
         (address-a
           (address-from-hex "0x0000000000000000000000000000000000000501"))
         (address-b
           (address-from-hex "0x0000000000000000000000000000000000000502"))
         (address-c
           (address-from-hex "0x0000000000000000000000000000000000000503"))
         (slot-a
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (slot-b
           (hash32-from-hex
            "0x000000000000000000000000000000000000000000000000000000000000000b"))
         (block
           (make-block
            :header
            (make-block-header :number 46
                               :state-root +empty-trie-hash+)))
         (block-hash (block-hash block))
         (addresses '())
         (slots '()))
    (chain-store-put-block store block :state-available-p t)
    (chain-store-put-account-balance store block-hash address-c 3)
    (chain-store-put-account-balance store block-hash address-a 1)
    (chain-store-put-account-balance store block-hash address-b 2)
    (chain-store-put-account-storage store block-hash address-a slot-b 11)
    (chain-store-put-account-storage store block-hash address-a slot-a 1)
    (chain-store-for-each-account
     store
     block-hash
     (lambda (address balance nonce code storage-entries)
       (declare (ignore balance nonce code))
       (push (address-to-hex address) addresses)
       (when (bytes= (address-bytes address)
                     (address-bytes address-a))
         (setf slots (mapcar (lambda (entry)
                               (hash32-to-hex (car entry)))
                             storage-entries)))))
    (is (equal (list (address-to-hex address-a)
                     (address-to-hex address-b)
                     (address-to-hex address-c))
               (nreverse addresses)))
    (is (equal (list (hash32-to-hex slot-a)
                     (hash32-to-hex slot-b))
               slots))))

(deftest state-db-account-range-uses-secure-half-open-bounds
  (let* ((state (make-state-db))
         (addresses
           (list (address-from-hex "0x0000000000000000000000000000000000000601")
                 (address-from-hex "0x0000000000000000000000000000000000000602")
                 (address-from-hex "0x0000000000000000000000000000000000000603")
                 (address-from-hex "0x0000000000000000000000000000000000000604")))
         (slot
           (hash32-from-hex
            "0x000000000000000000000000000000000000000000000000000000000000000a")))
    (loop for address in addresses
          for balance from 10 by 10
          do (state-db-set-account
              state
              address
              (make-state-account :nonce balance :balance balance)))
    (state-db-set-code state (second addresses) #(96 42))
    (state-db-set-storage state (second addresses) slot 7)
    (let* ((all (state-db-account-range state))
           (proof-keys
             (mapcar (lambda (entry)
                       (bytes-to-hex
                        (state-account-range-entry-proof-key entry)))
                     all))
           (start (state-account-range-entry-proof-key (second all)))
           (end (state-account-range-entry-proof-key (fourth all)))
           (middle (state-db-account-range state :start start :end end))
           (prefix (state-db-account-range state :end start))
           (suffix (state-db-account-range state :start end)))
      (is (= 4 (length all)))
      (is (equal (sort (copy-list proof-keys) #'string<)
                 proof-keys))
      (is (equal (subseq proof-keys 1 3)
                 (mapcar (lambda (entry)
                           (bytes-to-hex
                            (state-account-range-entry-proof-key entry)))
                         middle)))
      (is (= 1 (length prefix)))
      (is (= 1 (length suffix)))
      (is (null (state-db-account-range state :start start :end start)))
      (let ((code-entry
              (find (address-to-hex (second addresses))
                    all
                    :key (lambda (entry)
                           (address-to-hex
                            (state-account-range-entry-address entry)))
                    :test #'string=)))
        (is (bytes= #(96 42)
                    (state-account-range-entry-code code-entry)))
        (is (= 1
               (length
                (state-account-range-entry-storage-entries code-entry))))))))

(deftest state-db-storage-range-uses-secure-half-open-bounds
  (let* ((state (make-state-db))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000611"))
         (slots
           (list (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000001")
                 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000002")
                 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000003")
                 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000004"))))
    (loop for slot in slots
          for value from 100 by 100
          do (state-db-set-storage state address slot value))
    (let* ((all (state-db-storage-range state address))
           (proof-keys
             (mapcar (lambda (entry)
                       (bytes-to-hex
                        (state-storage-range-entry-proof-key entry)))
                     all))
           (start (state-storage-range-entry-proof-key (second all)))
           (end (state-storage-range-entry-proof-key (fourth all)))
           (middle (state-db-storage-range state address :start start :end end)))
      (is (= 4 (length all)))
      (is (equal (sort (copy-list proof-keys) #'string<)
                 proof-keys))
      (is (equal (subseq proof-keys 1 3)
                 (mapcar (lambda (entry)
                           (bytes-to-hex
                            (state-storage-range-entry-proof-key entry)))
                         middle)))
      (is (every #'plusp
                 (mapcar #'state-storage-range-entry-value middle)))
      (is (null (state-db-storage-range state address :start start :end start)))
      (is (null (state-db-storage-range
                 state
                 (address-from-hex
                  "0x0000000000000000000000000000000000000612")))))))

(deftest chain-store-state-db-round-trips-nontrivial-state-root
  (let* ((store (make-engine-payload-memory-store))
         (sender
           (address-from-hex "0x0000000000000000000000000000000000000411"))
         (recipient
           (address-from-hex "0x0000000000000000000000000000000000000412"))
         (sender-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000011"))
         (recipient-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000012"))
         (state (make-state-db))
         (block
           (make-block
            :header
            (make-block-header :number 45
                               :timestamp 450
                               :gas-limit 30000000))))
    (state-db-set-account
     state sender (make-state-account :nonce 7 :balance 1000))
    (state-db-set-code state sender #(96 1 96 0 85))
    (state-db-set-storage state sender sender-slot 42)
    (state-db-set-account
     state recipient (make-state-account :nonce 3 :balance 5))
    (state-db-set-code state recipient #(96 2 96 0 85))
    (state-db-set-storage state recipient recipient-slot 99)
    (ethereum-lisp.state::state-db-transfer-value
     state sender recipient 37)
    (setf (block-header-state-root (block-header block))
          (state-db-root state))
    (chain-store-put-block store block :state-available-p t)
    (commit-state-db-to-chain-store store (block-hash block) state)
    (let* ((reconstructed (chain-store-state-db store (block-hash block)))
           (sender-account (state-db-get-account reconstructed sender))
           (recipient-account
             (state-db-get-account reconstructed recipient)))
      (is (typep reconstructed 'state-db))
      (is (string= (state-db-root-hex state)
                   (state-db-root-hex reconstructed)))
      (is (= 963 (state-account-balance sender-account)))
      (is (= 42 (state-db-get-storage reconstructed sender sender-slot)))
      (is (bytes= #(96 1 96 0 85)
                  (state-db-get-code reconstructed sender)))
      (is (bytes= (hash32-bytes (state-account-storage-root
                                  (state-db-get-account state sender)))
                  (hash32-bytes
                   (state-account-storage-root sender-account))))
      (is (= 42 (state-account-balance recipient-account)))
      (is (= 99
             (state-db-get-storage
              reconstructed recipient recipient-slot)))
      (is (bytes= #(96 2 96 0 85)
                  (state-db-get-code reconstructed recipient)))
      (is (bytes= (hash32-bytes (state-account-code-hash
                                  (state-db-get-account state recipient)))
                  (hash32-bytes
                   (state-account-code-hash recipient-account)))))))

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
         (transaction-hash (transaction-hash transaction))
         (payload-id #(9 0 0 0 0 0 0 1))
         (blob #(#xaa #xbb))
         (commitment (make-byte-vector +kzg-commitment-size+
                                       :initial-element 0))
         (proof #(#xcc #xdd))
         (sidecar nil)
         (versioned-hash nil)
         (head-checkpoint
           (chain-store-head-checkpoint store))
         (prepared-payload
           (make-engine-prepared-payload
            :payload-id payload-id
            :version 3
            :block block))
         (invalid-block
           (make-block
            :header
            (make-block-header :number 7
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+
                               :gas-used 0)))
         (invalid-block-hash (block-hash invalid-block))
         (new-invalid-block
           (make-block
            :header
            (make-block-header :number 8
                               :parent-hash invalid-block-hash
                               :state-root +empty-trie-hash+
                               :gas-used 0)))
         (new-invalid-block-hash (block-hash new-invalid-block))
         (pending-filter-id
           (ethereum-lisp.core::engine-payload-store-put-pending-transaction-filter
            store)))
    (state-db-set-account state address (make-state-account :balance 10))
    (setf (aref commitment 0) #x11
          sidecar (make-blob-sidecar
                   :blobs (list blob)
                   :commitments (list commitment)
                   :proofs (list proof))
          versioned-hash (first (blob-sidecar-versioned-hashes sidecar)))
    (chain-store-put-prepared-payload store prepared-payload)
    (ethereum-lisp.core::engine-payload-store-put-blob-sidecar store sidecar)
    (ethereum-lisp.core::engine-payload-store-mark-invalid store invalid-block)
    (signals error
      (execute-atomic-block-commit
       store state
       (lambda ()
         (chain-store-put-block store block :state-available-p t)
         (chain-store-put-account-balance store block-hash address 99)
         (ethereum-lisp.core::engine-payload-store-put-pending-transaction
          store transaction)
         (setf (ethereum-lisp.core::engine-prepared-payload-version
                (chain-store-prepared-payload store payload-id))
               6)
         (setf (aref
                (ethereum-lisp.core::engine-blob-and-proofs-blob
                 (ethereum-lisp.core::engine-payload-store-blob-and-proofs-v1
                  store versioned-hash))
                0)
               #xff)
         (setf (ethereum-lisp.core::chain-store-checkpoint-label
                (chain-store-head-checkpoint store))
               :mutated-head)
         (setf (block-header-gas-used
                (block-header
                 (ethereum-lisp.core::engine-payload-store-invalid-block
                  store invalid-block-hash)))
               77)
         (ethereum-lisp.core::engine-payload-store-mark-invalid
          store new-invalid-block)
         (state-db-set-account state address
                               (make-state-account :balance 99))
         (error "Injected atomic commit failure"))))
    (is (null (chain-store-known-block store block-hash)))
    (is (null (chain-store-canonical-hash store 0)))
    (is (null (chain-store-transaction-location store transaction-hash)))
    (is (not (chain-store-state-available-p store block-hash)))
    (is (= 0 (chain-store-account-balance store block-hash address)))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (null (ethereum-lisp.core::engine-payload-store-pending-transaction
               store transaction-hash)))
    (is (null
         (ethereum-lisp.core::engine-pending-transaction-filter-hashes
          (ethereum-lisp.core::engine-payload-store-log-filter
           store pending-filter-id))))
    (is (= 3
           (ethereum-lisp.core::engine-prepared-payload-version
            (chain-store-prepared-payload store payload-id))))
    (is (= #xaa
           (aref
            (ethereum-lisp.core::engine-blob-and-proofs-blob
             (ethereum-lisp.core::engine-payload-store-blob-and-proofs-v1
              store versioned-hash))
            0)))
    (is (eq :head
            (ethereum-lisp.core::chain-store-checkpoint-label
             (chain-store-head-checkpoint store))))
    (is (not (eq head-checkpoint
                 (chain-store-head-checkpoint store))))
    (let ((cached-invalid
            (ethereum-lisp.core::engine-payload-store-invalid-block
             store invalid-block-hash)))
      (is cached-invalid)
      (is (not (eq invalid-block cached-invalid)))
      (is (= 0
             (block-header-gas-used
              (block-header cached-invalid)))))
    (is (null
         (ethereum-lisp.core::engine-payload-store-invalid-block
          store new-invalid-block-hash)))
    (is (= 10
           (state-account-balance
            (state-db-get-account state address))))))

(deftest engine-payload-store-indexes-pending-transactions-by-sender-nonce
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
         (sender-key
           (address-to-hex
            (or (transaction-sender transaction)
                (zero-address))))
         (nonce-key (write-to-string (transaction-nonce transaction)
                                     :base 10))
         (hash (transaction-hash transaction))
         (block
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+
                               :gas-used 0)
            :transactions (list transaction))))
    (is (typep
         (ethereum-lisp.core::engine-payload-memory-store-txpool store)
         'ethereum-lisp.core::engine-pending-txpool))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-queued-transaction-count
            store)))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-basefee-transaction-count
            store)))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-blob-transaction-count
            store)))
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store transaction)
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store transaction)
    (let* ((sender-index
             (ethereum-lisp.core::engine-payload-store-pending-transactions-by-sender
              store))
           (sender-transactions (gethash sender-key sender-index)))
      (is (= 1
             (ethereum-lisp.core::engine-payload-store-pending-transaction-count
              store)))
      (is (= 1 (hash-table-count sender-index)))
      (is (= 1 (hash-table-count sender-transactions)))
      (is (eq transaction (gethash nonce-key sender-transactions)))
      (is (eq transaction
              (ethereum-lisp.core::engine-payload-store-pending-transaction
               store hash))))
    (engine-payload-store-put-block store block)
    (let* ((sender-index
             (ethereum-lisp.core::engine-payload-store-pending-transactions-by-sender
              store))
           (sender-transactions (gethash sender-key sender-index)))
      (is (= 0
             (ethereum-lisp.core::engine-payload-store-pending-transaction-count
              store)))
      (is (null
           (ethereum-lisp.core::engine-payload-store-pending-transaction
            store hash)))
      (is (null sender-transactions))
      (is (zerop (hash-table-count sender-index))))))

(deftest engine-payload-store-removes-pending-sender-nonce-on-block-import
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (private-key 1)
         (pending-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 4
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (mined-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 4
             :gas-price 110
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (sender-key
           (address-to-hex
            (or (transaction-sender pending-transaction)
                (zero-address))))
         (block
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+
                               :gas-used 0)
            :transactions (list mined-transaction))))
    (is (not (string= (hash32-to-hex (transaction-hash pending-transaction))
                      (hash32-to-hex (transaction-hash mined-transaction)))))
    (is (bytes= (address-bytes (transaction-sender pending-transaction))
                (address-bytes (transaction-sender mined-transaction))))
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store pending-transaction)
    (engine-payload-store-put-block store block)
    (let* ((sender-index
             (ethereum-lisp.core::engine-payload-store-pending-transactions-by-sender
              store))
           (sender-transactions (gethash sender-key sender-index))
           (location
             (chain-store-transaction-location
              store
              (transaction-hash mined-transaction))))
      (is (= 0
             (ethereum-lisp.core::engine-payload-store-pending-transaction-count
              store)))
      (is (null
           (ethereum-lisp.core::engine-payload-store-pending-transaction
            store
            (transaction-hash pending-transaction))))
      (is (null sender-transactions))
      (is (typep location 'engine-transaction-location))
      (is (eq mined-transaction
              (engine-transaction-location-transaction location))))))

(deftest engine-payload-store-removes-included-transactions-from-subpools
  (labels ((put-queued (store transaction)
             (setf
              (gethash
               (ethereum-lisp.core::engine-pending-txpool-hash-key
                (transaction-hash transaction))
               (ethereum-lisp.core::engine-payload-store-queued-transaction-table
                store))
              transaction)
             (ethereum-lisp.core::engine-payload-store-index-queued-transaction
              store
              transaction)))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (private-key 1)
           (queued-conflict
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 4
               :gas-price 100
               :gas-limit 21000
               :to recipient)
              private-key
              1))
           (mined-conflict
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 4
               :gas-price 110
               :gas-limit 21000
               :to recipient)
              private-key
              1))
           (basefee-exact
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 6
               :gas-price 90
               :gas-limit 21000
               :to recipient)
              private-key
              1))
           (queued-exact
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 5
               :gas-price 120
               :gas-limit 21000
               :to recipient)
              private-key
              1))
           (blob-exact
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 7
               :gas-price 130
               :gas-limit 21000
               :to recipient)
              private-key
              1))
           (sender-key
             (ethereum-lisp.core::engine-payload-store-pending-sender-key
              queued-conflict))
           (block
             (make-block
              :header
              (make-block-header :number 0
                                 :parent-hash (zero-hash32)
                                 :state-root +empty-trie-hash+
                                 :gas-used 0)
              :transactions
              (list mined-conflict queued-exact basefee-exact blob-exact))))
      (is (not (string=
                (hash32-to-hex (transaction-hash queued-conflict))
                (hash32-to-hex (transaction-hash mined-conflict)))))
      (is (bytes= (address-bytes (transaction-sender queued-conflict))
                  (address-bytes (transaction-sender mined-conflict))))
      (put-queued store queued-conflict)
      (put-queued store queued-exact)
      (ethereum-lisp.core::engine-payload-store-put-basefee-transaction
       store
       basefee-exact)
      (ethereum-lisp.core::engine-payload-store-put-blob-transaction
       store
       blob-exact)
      (is (= 2
             (ethereum-lisp.core::engine-payload-store-queued-transaction-count
              store)))
      (is (= 1
             (ethereum-lisp.core::engine-payload-store-basefee-transaction-count
              store)))
      (is (= 1
             (ethereum-lisp.core::engine-payload-store-blob-transaction-count
              store)))
      (engine-payload-store-put-block store block)
      (let ((queued-sender-transactions
              (gethash
               sender-key
               (ethereum-lisp.core::engine-payload-store-queued-sender-index
                store))))
        (is (= 0
               (ethereum-lisp.core::engine-payload-store-queued-transaction-count
                store)))
        (is (= 0
               (ethereum-lisp.core::engine-payload-store-basefee-transaction-count
                store)))
        (is (= 0
               (ethereum-lisp.core::engine-payload-store-blob-transaction-count
                store)))
        (is (null queued-sender-transactions))))))

(deftest engine-payload-store-replaces-same-sender-nonce-with-price-bump
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (private-key 1)
         (base-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 4
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (underpriced-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 4
             :gas-price 109
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (replacement-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 4
             :gas-price 110
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (sender-key
           (address-to-hex
            (or (transaction-sender base-transaction)
                (zero-address))))
         (nonce-key (write-to-string
                     (transaction-nonce base-transaction)
                     :base 10)))
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store base-transaction)
    (signals block-validation-error
      (ethereum-lisp.core::engine-payload-store-put-pending-transaction
       store underpriced-transaction))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (eq base-transaction
            (ethereum-lisp.core::engine-payload-store-pending-transaction
             store (transaction-hash base-transaction))))
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store replacement-transaction)
    (let* ((sender-index
             (ethereum-lisp.core::engine-payload-store-pending-transactions-by-sender
              store))
           (sender-transactions (gethash sender-key sender-index)))
      (is (= 1
             (ethereum-lisp.core::engine-payload-store-pending-transaction-count
              store)))
      (is (null
           (ethereum-lisp.core::engine-payload-store-pending-transaction
            store (transaction-hash base-transaction))))
      (is (eq replacement-transaction
              (ethereum-lisp.core::engine-payload-store-pending-transaction
               store (transaction-hash replacement-transaction))))
      (is (eq replacement-transaction
              (gethash nonce-key sender-transactions))))))

(deftest engine-pending-transaction-filter-records-hashes-in-order
  (let ((filter
          (ethereum-lisp.core::make-engine-pending-transaction-filter))
        (first-hash
          (hash32-from-hex
           "0x0101010101010101010101010101010101010101010101010101010101010101"))
        (second-hash
          (hash32-from-hex
           "0x0202020202020202020202020202020202020202020202020202020202020202")))
    (is (eq filter
            (ethereum-lisp.core::engine-pending-transaction-filter-record-hash
             filter
             first-hash)))
    (ethereum-lisp.core::engine-pending-transaction-filter-record-hash
     filter
     second-hash)
    (is (equal
         (list first-hash second-hash)
         (ethereum-lisp.core::engine-pending-transaction-filter-hashes
          filter)))
    (signals block-validation-error
      (ethereum-lisp.core::engine-pending-transaction-filter-record-hash
       filter
       (make-array 31 :element-type '(unsigned-byte 8) :initial-element 0)))))

(deftest engine-pending-txpool-replaces-same-sender-nonce-directly
  (let* ((txpool (ethereum-lisp.core::make-engine-pending-txpool))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (private-key 1)
         (base-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 6
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (underpriced-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 6
             :gas-price 109
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (replacement-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 6
             :gas-price 110
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (sender-key
           (address-to-hex
            (or (transaction-sender base-transaction)
                (zero-address))))
         (nonce-key (write-to-string
                     (transaction-nonce base-transaction)
                     :base 10)))
    (multiple-value-bind (stored inserted-p)
        (ethereum-lisp.core::engine-pending-txpool-put-pending-transaction
         txpool
         base-transaction)
      (is (eq base-transaction stored))
      (is inserted-p))
    (is (= 1
           (ethereum-lisp.core::engine-pending-txpool-pending-count
            txpool)))
    (is (eq base-transaction
            (ethereum-lisp.core::engine-pending-txpool-pending-transaction
             txpool
             (transaction-hash base-transaction))))
    (is (equal (list base-transaction)
               (ethereum-lisp.core::engine-pending-txpool-pending-transactions
                txpool)))
    (multiple-value-bind (stored inserted-p)
        (ethereum-lisp.core::engine-pending-txpool-put-pending-transaction
         txpool
         base-transaction)
      (is (eq base-transaction stored))
      (is (null inserted-p)))
    (signals block-validation-error
      (ethereum-lisp.core::engine-pending-txpool-put-pending-transaction
       txpool
       underpriced-transaction))
    (multiple-value-bind (stored inserted-p)
        (ethereum-lisp.core::engine-pending-txpool-put-pending-transaction
         txpool
         replacement-transaction)
      (is (eq replacement-transaction stored))
      (is inserted-p))
    (let* ((sender-index
             (ethereum-lisp.core::engine-pending-txpool-transactions-by-sender
              txpool))
           (sender-transactions (gethash sender-key sender-index)))
      (is (= 1
             (ethereum-lisp.core::engine-pending-txpool-pending-count
              txpool)))
      (is (null
           (ethereum-lisp.core::engine-pending-txpool-pending-transaction
            txpool
            (transaction-hash base-transaction))))
      (is (eq replacement-transaction
              (ethereum-lisp.core::engine-pending-txpool-pending-transaction
               txpool
               (transaction-hash replacement-transaction))))
      (is (eq replacement-transaction
              (gethash nonce-key sender-transactions))))))

(deftest engine-pending-txpool-indexes-basefee-and-blob-subpools
  (let* ((txpool (ethereum-lisp.core::make-engine-pending-txpool))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (private-key 1)
         (basefee-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 6
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (underpriced-basefee
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 6
             :gas-price 109
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (replacement-basefee
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 6
             :gas-price 110
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (blob-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 7
             :gas-price 120
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (sender-key
           (address-to-hex
            (or (transaction-sender basefee-transaction)
                (zero-address)))))
    (ethereum-lisp.core::engine-pending-txpool-put-basefee-transaction
     txpool
     basefee-transaction)
    (ethereum-lisp.core::engine-pending-txpool-put-blob-transaction
     txpool
     blob-transaction)
    (let ((basefee-by-nonce
            (gethash
             sender-key
             (ethereum-lisp.core::engine-pending-txpool-basefee-transactions-by-sender
              txpool)))
          (blob-by-nonce
            (gethash
             sender-key
             (ethereum-lisp.core::engine-pending-txpool-blob-transactions-by-sender
              txpool))))
      (is (eq basefee-transaction (gethash "6" basefee-by-nonce)))
      (is (eq blob-transaction (gethash "7" blob-by-nonce))))
    (signals block-validation-error
      (ethereum-lisp.core::engine-pending-txpool-put-basefee-transaction
       txpool
       underpriced-basefee))
    (ethereum-lisp.core::engine-pending-txpool-put-basefee-transaction
     txpool
     replacement-basefee)
    (let ((basefee-by-nonce
            (gethash
             sender-key
             (ethereum-lisp.core::engine-pending-txpool-basefee-transactions-by-sender
              txpool))))
      (is (= 1
             (ethereum-lisp.core::engine-pending-txpool-basefee-count
              txpool)))
      (is (eq replacement-basefee (gethash "6" basefee-by-nonce)))
      (is (null
           (gethash
            (ethereum-lisp.core::engine-pending-txpool-hash-key
             (transaction-hash basefee-transaction))
            (ethereum-lisp.core::engine-pending-txpool-basefee-transactions
             txpool)))))
    (ethereum-lisp.core::engine-pending-txpool-remove-basefee-transaction
     txpool
     (transaction-hash replacement-basefee))
    (ethereum-lisp.core::engine-pending-txpool-remove-blob-transaction
     txpool
     (transaction-hash blob-transaction))
    (is (= 0
           (ethereum-lisp.core::engine-pending-txpool-basefee-count
            txpool)))
    (is (= 0
           (ethereum-lisp.core::engine-pending-txpool-blob-count
            txpool)))
    (is (null
         (gethash
          sender-key
          (ethereum-lisp.core::engine-pending-txpool-basefee-transactions-by-sender
           txpool))))
    (is (null
         (gethash
          sender-key
          (ethereum-lisp.core::engine-pending-txpool-blob-transactions-by-sender
           txpool))))))

(deftest engine-payload-store-uses-sender-index-for-pending-account-view
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (sender-nonce-two
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 2
             :gas-price 2
             :gas-limit 21000
             :to recipient)
            1
            1))
         (sender-nonce-zero
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 1
             :gas-limit 21000
             :to recipient)
            1
            1))
         (replacement
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 3
             :gas-limit 21000
             :to recipient)
            1
            1))
         (other-sender
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            2
            1))
         (sender (transaction-sender sender-nonce-zero :expected-chain-id 1)))
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store
     sender-nonce-two)
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store
     other-sender)
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store
     sender-nonce-zero)
    (let ((sender-transactions
            (ethereum-lisp.core::engine-payload-store-pending-sender-transactions
             store
             sender)))
      (is (= 2 (length sender-transactions)))
      (is (eq sender-nonce-zero (first sender-transactions)))
      (is (eq sender-nonce-two (second sender-transactions))))
    (is (=
         (+ (ethereum-lisp.core::engine-payload-store-txpool-upfront-cost
             sender-nonce-two)
            (ethereum-lisp.core::engine-payload-store-txpool-upfront-cost
             replacement))
         (ethereum-lisp.core::engine-payload-store-pending-sender-expenditure
          store
          sender
          replacement)))))

(deftest txpool-rpc-views-use-subpool-sender-indexes
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (pending-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 100
               :gas-limit 21000
               :to recipient)
              1
              1))
           (queued-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 110
               :gas-limit 21000
               :to recipient)
              1
              1))
           (basefee-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 2
               :gas-price 120
               :gas-limit 21000
               :to recipient)
              1
              1))
           (blob-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 3
               :gas-price 130
               :gas-limit 21000
               :to recipient)
              1
              1))
           (other-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 140
               :gas-limit 21000
               :to recipient)
              2
              1))
           (sender
             (transaction-sender pending-transaction :expected-chain-id 1))
           (sender-key (address-to-hex sender))
           (other-sender
             (transaction-sender other-transaction :expected-chain-id 1)))
      (ethereum-lisp.core::engine-payload-store-put-pending-transaction
       store
       pending-transaction)
      (ethereum-lisp.core::engine-payload-store-put-queued-transaction
       store
       queued-transaction)
      (ethereum-lisp.core::engine-payload-store-put-basefee-transaction
       store
       basefee-transaction)
      (ethereum-lisp.core::engine-payload-store-put-blob-transaction
       store
       blob-transaction)
      (ethereum-lisp.core::engine-payload-store-put-queued-transaction
       store
       other-transaction)
      (let* ((response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":88,"
                 "\"method\":\"txpool_contentFrom\",\"params\":[\""
                 sender-key
                 "\"]}")
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":90,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (inspect-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":91,\"method\":\"txpool_inspect\",\"params\":[]}"
                store
                config))
             (other-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":92,"
                 "\"method\":\"txpool_contentFrom\",\"params\":[\""
                 (address-to-hex other-sender)
                 "\"]}")
                store
                config))
             (result (field response "result"))
             (pending (field result "pending"))
             (queued (field result "queued"))
             (content-queued
               (field (field (field content-response "result") "queued")
                      sender-key))
             (inspect-queued
               (field (field (field inspect-response "result") "queued")
                      sender-key))
             (other-queued (field (field other-response "result")
                                  "queued")))
        (is (string= (hash32-to-hex
                      (transaction-hash pending-transaction))
                     (field (field pending "0") "hash")))
        (is (string= (hash32-to-hex
                      (transaction-hash queued-transaction))
                     (field (field queued "1") "hash")))
        (is (string= (hash32-to-hex
                      (transaction-hash basefee-transaction))
                     (field (field queued "2") "hash")))
        (is (string= (hash32-to-hex
                      (transaction-hash blob-transaction))
                     (field (field queued "3") "hash")))
        (is (null (field queued "4")))
        (is (string= (hash32-to-hex
                      (transaction-hash queued-transaction))
                     (field (field content-queued "1") "hash")))
        (is (string= (hash32-to-hex
                      (transaction-hash basefee-transaction))
                     (field (field content-queued "2") "hash")))
        (is (string= (hash32-to-hex
                      (transaction-hash blob-transaction))
                     (field (field content-queued "3") "hash")))
        (is (search "110 wei" (field inspect-queued "1")))
        (is (search "120 wei" (field inspect-queued "2")))
        (is (search "130 wei" (field inspect-queued "3")))
        (is (string= (hash32-to-hex
                      (transaction-hash other-transaction))
                     (field (field other-queued "1") "hash")))))))

(deftest engine-pending-txpool-copy-isolates-sender-indexes
  (let* ((txpool (ethereum-lisp.core::make-engine-pending-txpool))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 7
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            1
            1))
         (sender-key
           (address-to-hex
            (or (transaction-sender transaction)
                (zero-address))))
         (nonce-key (write-to-string
                     (transaction-nonce transaction)
                     :base 10)))
    (ethereum-lisp.core::engine-pending-txpool-put-pending-transaction
     txpool
     transaction)
    (let* ((copy (ethereum-lisp.core::engine-pending-txpool-copy txpool))
           (sender-transactions
             (gethash
              sender-key
              (ethereum-lisp.core::engine-pending-txpool-transactions-by-sender
               txpool)))
           (copy-sender-transactions
             (gethash
              sender-key
              (ethereum-lisp.core::engine-pending-txpool-transactions-by-sender
               copy))))
      (is (not (eq txpool copy)))
      (is (not (eq
                (ethereum-lisp.core::engine-pending-txpool-transactions
                 txpool)
                (ethereum-lisp.core::engine-pending-txpool-transactions
                 copy))))
      (is (not (eq sender-transactions copy-sender-transactions)))
      (ethereum-lisp.core::engine-pending-txpool-remove-pending-transaction
       txpool
       (transaction-hash transaction))
      (is (= 0
             (hash-table-count
              (ethereum-lisp.core::engine-pending-txpool-transactions
               txpool))))
      (is (= 1
             (hash-table-count
              (ethereum-lisp.core::engine-pending-txpool-transactions
               copy))))
      (is (eq transaction (gethash nonce-key copy-sender-transactions))))))

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

(deftest chain-store-keeps-canonical-transaction-location-over-sidechain-duplicate
  (let* ((store (make-engine-payload-memory-store))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :extra-data #(0))))
         (genesis-hash (block-hash genesis))
         (shared-transaction
           (make-legacy-transaction
            :nonce 7
            :gas-price 2
            :gas-limit 21000
            :value 3
            :data #(7)
            :v 27
            :r 4
            :s 5))
         (shared-hash (transaction-hash shared-transaction)))
    (flet ((child-block (number parent-hash marker &key transactions)
             (make-block
              :header
              (make-block-header :number number
                                 :parent-hash parent-hash
                                 :extra-data (vector marker))
              :transactions transactions
              :receipts
              (loop repeat (length transactions)
                    collect (make-receipt :status 1
                                          :cumulative-gas-used 21000)))))
      (let* ((a1 (child-block 1 genesis-hash 1))
             (a2 (child-block 2 (block-hash a1) 2
                              :transactions (list shared-transaction)))
             (b1 (child-block 1 genesis-hash 11))
             (b2 (child-block 2 (block-hash b1) 12
                              :transactions (list shared-transaction))))
        (dolist (block (list genesis a1 a2))
          (chain-store-put-block store block))
        (let ((location
                (chain-store-transaction-location store shared-hash)))
          (is (typep location 'engine-transaction-location))
          (is (eq a2 (engine-transaction-location-block location))))
        (dolist (block (list b1 b2))
          (chain-store-put-block store block))
        (let ((location
                (chain-store-transaction-location store shared-hash)))
          (is (typep location 'engine-transaction-location))
          (is (eq a2 (engine-transaction-location-block location))))
        (chain-store-set-canonical-head store (block-hash b2))
        (let ((location
                (chain-store-transaction-location store shared-hash)))
          (is (typep location 'engine-transaction-location))
          (is (eq b2 (engine-transaction-location-block location)))
          (is (eq shared-transaction
                  (engine-transaction-location-transaction location))))))))

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
      (let ((executable-store (make-engine-payload-memory-store)))
        (engine-payload-store-put-block
         executable-store parent-block :state-available-p t)
        (let* ((response
                 (engine-rpc-handle-request
                  request executable-store config
                  :import-function #'execute-and-commit-engine-payload))
               (result (field response "result")))
          (is (string= +payload-status-valid+ (field result "status")))
          (is (engine-payload-store-known-block
               executable-store
               (block-hash child-block)))
          (is (chain-store-state-available-p
               executable-store
               (block-hash child-block)))))
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

(deftest engine-rpc-new-payload-v2-imports-one-transaction
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (receipt-request (id hash)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex hash))))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :byzantium-block 0
                                      :constantinople-block 0
                                      :petersburg-block 0
                                      :berlin-block 0
                                      :london-block 0
                                      :shanghai-time 0))
           (sender
             (address-from-hex "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (fee-recipient
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (withdrawal-recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
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
           (withdrawal
             (make-withdrawal :index 0
                              :validator-index 1
                              :address withdrawal-recipient
                              :amount 1))
           (parent-state (make-state-db)))
      (state-db-set-account parent-state sender
                            (make-state-account
                             :nonce 9
                             :balance 2000000000000000000))
      (let* ((parent-header
               (make-block-header
                :parent-hash (zero-hash32)
                :beneficiary fee-recipient
                :state-root (state-db-root parent-state)
                :mix-hash (zero-hash32)
                :number 41
                :gas-limit 50000
                :gas-used 25000
                :timestamp 98
                :base-fee-per-gas 100
                :withdrawals-root (withdrawal-list-root '())))
             (parent-block (make-block :header parent-header))
             (expected-state (state-db-copy parent-state))
             (child-header
               (make-block-header
                :parent-hash (block-hash parent-block)
                :beneficiary fee-recipient
                :mix-hash (zero-hash32)
                :number 42
                :gas-limit 50000
                :gas-used 0
                :timestamp 99
                :base-fee-per-gas 100))
             (child-block
               (execute-signed-block
                expected-state
                (list transaction)
                :expected-chain-id 1
                :header child-header
                :chain-config config
                :withdrawals (list withdrawal)))
             (payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data child-block)))
             (request
               (list (cons "jsonrpc" "2.0")
                     (cons "id" 27)
                     (cons "method" "engine_newPayloadV2")
                     (cons "params"
                           (list (engine-rpc-executable-data-object
                                  payload))))))
        (engine-payload-store-put-block
         store parent-block :state-available-p t)
        (commit-state-db-to-chain-store
         store (block-hash parent-block) parent-state)
        (let* ((response
                 (engine-rpc-handle-request
                  request store config
                  :import-function #'execute-and-commit-engine-payload))
               (result (field response "result")))
          (is (string= "2.0" (field response "jsonrpc")))
          (is (= 27 (field response "id")))
          (is (string= +payload-status-valid+ (field result "status")))
          (is (string= (hash32-to-hex (block-hash child-block))
                       (field result "latestValidHash")))
          (is (engine-payload-store-known-block
               store (block-hash child-block)))
          (is (chain-store-state-available-p
               store (block-hash child-block)))
          (is (= 10
                 (chain-store-account-nonce
                  store (block-hash child-block) sender)))
          (is (= 999580000000000000
                 (chain-store-account-balance
                  store (block-hash child-block) sender)))
          (is (= 1000000000000000000
                 (chain-store-account-balance
                  store (block-hash child-block) recipient)))
          (is (= +wei-per-gwei+
                 (chain-store-account-balance
                  store (block-hash child-block) withdrawal-recipient)))
          (is (typep (chain-store-transaction-location
                      store
                      (transaction-hash transaction))
                     'engine-transaction-location))
          (let* ((receipts
                   (chain-store-block-receipts store (block-hash child-block)))
                 (receipt-response
                   (engine-rpc-handle-request
                    (receipt-request 28 (transaction-hash transaction))
                    store config))
                 (receipt (field receipt-response "result"))
                 (receipts-root
                   (block-header-receipts-root (block-header child-block))))
            (is (= 1 (length receipts)))
            (is (string= (hash32-to-hex (receipt-list-root receipts))
                         (hash32-to-hex receipts-root)))
            (is (string= (hash32-to-hex
                          (transaction-receipt-list-root
                           (list transaction)
                           receipts))
                         (hash32-to-hex receipts-root)))
            (is (string= (quantity-to-hex 0) (field receipt "type")))
            (is (string= (quantity-to-hex 1)
                         (field receipt "status")))))))))

(deftest engine-rpc-new-payload-v2-rolls-back-state-projection-on-bad-commitment
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (bad-logs-bloom ()
             (let ((bloom (make-byte-vector 256)))
               (setf (aref bloom 0) 1)
               bloom)))
    (let* ((config (make-chain-config :chain-id 1
                                      :byzantium-block 0
                                      :constantinople-block 0
                                      :petersburg-block 0
                                      :berlin-block 0
                                      :london-block 0
                                      :shanghai-time 0))
           (sender
             (address-from-hex "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (fee-recipient
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (withdrawal-recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
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
           (withdrawal
             (make-withdrawal :index 0
                              :validator-index 1
                              :address withdrawal-recipient
                              :amount 1))
           (parent-state (make-state-db)))
      (state-db-set-account parent-state sender
                            (make-state-account
                             :nonce 9
                             :balance 2000000000000000000))
      (let* ((parent-header
               (make-block-header
                :parent-hash (zero-hash32)
                :beneficiary fee-recipient
                :state-root (state-db-root parent-state)
                :mix-hash (zero-hash32)
                :number 41
                :gas-limit 50000
                :gas-used 25000
                :timestamp 98
                :base-fee-per-gas 100
                :withdrawals-root (withdrawal-list-root '())))
             (parent-block (make-block :header parent-header)))
        (labels ((child-block ()
                   (execute-signed-block
                    (state-db-copy parent-state)
                    (list transaction)
                    :expected-chain-id 1
                    :header (make-block-header
                             :parent-hash (block-hash parent-block)
                             :beneficiary fee-recipient
                             :mix-hash (zero-hash32)
                             :number 42
                             :gas-limit 50000
                             :gas-used 0
                             :timestamp 99
                             :base-fee-per-gas 100)
                    :chain-config config
                    :withdrawals (list withdrawal)))
                 (check-case (mutate-header expected-error)
                   (let* ((store (make-engine-payload-memory-store))
                          (bad-block (child-block)))
                     (funcall mutate-header (block-header bad-block))
                     (let* ((bad-block-hash (block-hash bad-block))
                            (payload
                              (execution-payload-envelope-execution-payload
                               (block-to-executable-data bad-block)))
                            (request
                              (list
                               (cons "jsonrpc" "2.0")
                               (cons "id" 29)
                               (cons "method" "engine_newPayloadV2")
                               (cons
                                "params"
                                (list (engine-rpc-executable-data-object
                                       payload))))))
                       (engine-payload-store-put-block
                        store parent-block :state-available-p t)
                       (commit-state-db-to-chain-store
                        store (block-hash parent-block) parent-state)
                       (let* ((response
                                (engine-rpc-handle-request
                                 request store config
                                 :import-function
                                 #'execute-and-commit-engine-payload))
                              (result (field response "result")))
                         (is (string= +payload-status-invalid+
                                      (field result "status")))
                         (is (string= expected-error
                                      (field result "validationError")))
                         (is (not (chain-store-known-block
                                   store bad-block-hash)))
                         (is (not (chain-store-state-available-p
                                   store bad-block-hash)))
                         (is (not (chain-store-transaction-location
                                   store
                                   (transaction-hash transaction))))
                         (is (= 0
                                (chain-store-account-nonce
                                 store bad-block-hash sender)))
                         (is (= 0
                                (chain-store-account-balance
                                 store bad-block-hash recipient)))
                         (is (= 0
                                (chain-store-account-balance
                                 store bad-block-hash withdrawal-recipient)))
                         (is (= 9
                                (chain-store-account-nonce
                                 store (block-hash parent-block) sender)))
                         (is (= 2000000000000000000
                                (chain-store-account-balance
                                 store (block-hash parent-block) sender))))))))
          (check-case
           (lambda (header)
             (setf (block-header-state-root header) (zero-hash32)))
           "State root mismatch")
          (check-case
           (lambda (header)
             (setf (block-header-receipts-root header) (zero-hash32)))
           "Receipts root mismatch")
          (check-case
           (lambda (header)
             (setf (block-header-logs-bloom header) (bad-logs-bloom)))
           "Logs bloom mismatch")
          (check-case
           (lambda (header)
             (setf (block-header-gas-used header) 1))
           "Gas used mismatch"))))))

(deftest engine-rpc-new-payload-v2-rejects-wrong-chain-sender
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (execution-config (make-chain-config :chain-id 1
                                                :london-block 0
                                                :shanghai-time 0))
           (import-config (make-chain-config :chain-id 2
                                             :london-block 0
                                             :shanghai-time 0))
           (sender
             (address-from-hex "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (fee-recipient
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (withdrawal-recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
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
           (withdrawal
             (make-withdrawal :index 0
                              :validator-index 1
                              :address withdrawal-recipient
                              :amount 1))
           (parent-state (make-state-db)))
      (state-db-set-account parent-state sender
                            (make-state-account
                             :nonce 9
                             :balance 2000000000000000000))
      (let* ((parent-header
               (make-block-header
                :parent-hash (zero-hash32)
                :beneficiary fee-recipient
                :state-root (state-db-root parent-state)
                :mix-hash (zero-hash32)
                :number 41
                :gas-limit 50000
                :gas-used 25000
                :timestamp 98
                :base-fee-per-gas 100
                :withdrawals-root (withdrawal-list-root '())))
             (parent-block (make-block :header parent-header))
             (execution-state (state-db-copy parent-state))
             (child-block
               (execute-signed-block
                execution-state
                (list transaction)
                :expected-chain-id 1
                :header (make-block-header
                         :parent-hash (block-hash parent-block)
                         :beneficiary fee-recipient
                         :mix-hash (zero-hash32)
                         :number 42
                         :gas-limit 50000
                         :gas-used 0
                         :timestamp 99
                         :base-fee-per-gas 100)
                :chain-config execution-config
                :withdrawals (list withdrawal)))
             (payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data child-block)))
             (request
               (list (cons "jsonrpc" "2.0")
                     (cons "id" 28)
                     (cons "method" "engine_newPayloadV2")
                     (cons "params"
                           (list (engine-rpc-executable-data-object
                                  payload))))))
        (engine-payload-store-put-block
         store parent-block :state-available-p t)
        (commit-state-db-to-chain-store
         store (block-hash parent-block) parent-state)
        (let* ((response
                 (engine-rpc-handle-request
                  request store import-config
                  :import-function #'execute-and-commit-engine-payload))
               (result (field response "result")))
          (is (string= +payload-status-invalid+ (field result "status")))
          (is (string= (hash32-to-hex (block-hash parent-block))
                       (field result "latestValidHash")))
          (is (string= "Invalid transaction signature"
                       (field result "validationError")))
          (is (not (chain-store-known-block store (block-hash child-block))))
          (is (not (chain-store-state-available-p
                    store
                    (block-hash child-block))))
          (is (not (chain-store-transaction-location
                    store
                    (transaction-hash transaction))))
          (is (= 9
                 (chain-store-account-nonce
                  store (block-hash parent-block) sender)))
          (is (= 2000000000000000000
                 (chain-store-account-balance
                  store (block-hash parent-block) sender)))
          (is (= 0
                 (chain-store-account-balance
                  store (block-hash parent-block) recipient))))))))

(deftest engine-rpc-new-payload-v2-receipt-contract-address
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (receipt-request (id hash)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex hash))))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :byzantium-block 0
                                      :constantinople-block 0
                                      :petersburg-block 0
                                      :berlin-block 0
                                      :london-block 0
                                      :shanghai-time 0))
           (private-key 1)
           (sender (fixture-private-key-address private-key))
           (fee-recipient
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (withdrawal-recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
           ;; Store byte 0 in memory, then return it as one byte of runtime code.
           (initcode #(96 0 96 0 83 96 1 96 0 243))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction :nonce 0
                                       :gas-price 100
                                       :gas-limit 80000
                                       :to nil
                                       :value 7
                                       :data initcode)
              private-key
              1))
           (contract
             (make-address
              (subseq
               (keccak-256
                (rlp-encode
                 (make-rlp-list (address-bytes sender) 0)))
               12 32)))
           (withdrawal
             (make-withdrawal :index 0
                              :validator-index 1
                              :address withdrawal-recipient
                              :amount 1))
           (parent-state (make-state-db)))
      (state-db-set-account parent-state sender
                            (make-state-account
                             :nonce 0
                             :balance 1000000000))
      (let* ((parent-header
               (make-block-header
                :parent-hash (zero-hash32)
                :beneficiary fee-recipient
                :state-root (state-db-root parent-state)
                :mix-hash (zero-hash32)
                :number 41
                :gas-limit 100000
                :gas-used 50000
                :timestamp 98
                :base-fee-per-gas 100
                :withdrawals-root (withdrawal-list-root '())))
             (parent-block (make-block :header parent-header))
             (execution-state (state-db-copy parent-state))
             (child-block
               (execute-signed-block
                execution-state
                (list transaction)
                :expected-chain-id 1
                :header (make-block-header
                         :parent-hash (block-hash parent-block)
                         :beneficiary fee-recipient
                         :mix-hash (zero-hash32)
                         :number 42
                         :gas-limit 100000
                         :gas-used 0
                         :timestamp 99
                         :base-fee-per-gas 100)
                :chain-config config
                :withdrawals (list withdrawal)))
             (payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data child-block)))
             (request
               (list (cons "jsonrpc" "2.0")
                     (cons "id" 29)
                     (cons "method" "engine_newPayloadV2")
                     (cons "params"
                           (list (engine-rpc-executable-data-object
                                  payload))))))
        (engine-payload-store-put-block
         store parent-block :state-available-p t)
        (commit-state-db-to-chain-store
         store (block-hash parent-block) parent-state)
        (let* ((import-response
                 (engine-rpc-handle-request
                  request store config
                  :import-function #'execute-and-commit-engine-payload))
               (import-result (field import-response "result"))
               (receipt-response
                 (engine-rpc-handle-request
                  (receipt-request 30 (transaction-hash transaction))
                  store config))
               (receipt (field receipt-response "result")))
          (is (string= +payload-status-valid+
                       (field import-result "status")))
          (is (string= (address-to-hex contract)
                       (field receipt "contractAddress")))
          (is (null (field receipt "to")))
          (is (string= (quantity-to-hex 1) (field receipt "status")))
          (is (string= (quantity-to-hex 0)
                       (field receipt "transactionIndex")))
          (is (string= (hash32-to-hex (transaction-hash transaction))
                       (field receipt "transactionHash")))
          (is (string= (hash32-to-hex (block-hash child-block))
                       (field receipt "blockHash"))))))))

(deftest engine-rpc-new-payload-v2-internal-create2-receipt-has-no-contract-address
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (receipt-request (id hash)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex hash))))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :byzantium-block 0
                                      :constantinople-block 0
                                      :petersburg-block 0
                                      :berlin-block 0
                                      :london-block 0
                                      :shanghai-time 0))
           (private-key 1)
           (sender (fixture-private-key-address private-key))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000ce"))
           (fee-recipient
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (withdrawal-recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
           ;; CODECOPY the initcode after this prefix, then CREATE2 with salt 5.
           ;; The initcode returns one zero runtime byte.
           (initcode #(96 0 96 0 83 96 1 96 0 243))
           (create2-code
             (concat-bytes
              #(96 10 96 14 95 57 96 5 96 10 95 95 245 0)
              initcode))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction :nonce 0
                                       :gas-price 100
                                       :gas-limit 180000
                                       :to contract)
              private-key
              1))
           (salt-bytes (make-byte-vector 32))
           (withdrawal
             (make-withdrawal :index 0
                              :validator-index 1
                              :address withdrawal-recipient
                              :amount 1))
           (parent-state (make-state-db)))
      (setf (aref salt-bytes 31) 5)
      (let ((created-contract
              (make-address
               (subseq
                (keccak-256
                 (concat-bytes #(255)
                               (address-bytes contract)
                               salt-bytes
                               (keccak-256 initcode)))
                12 32))))
        (state-db-set-account parent-state sender
                              (make-state-account
                               :nonce 0
                               :balance 1000000000))
        (state-db-set-code parent-state contract create2-code)
        (let* ((parent-header
                 (make-block-header
                  :parent-hash (zero-hash32)
                  :beneficiary fee-recipient
                  :state-root (state-db-root parent-state)
                  :mix-hash (zero-hash32)
                  :number 41
                  :gas-limit 200000
                  :gas-used 100000
                  :timestamp 98
                  :base-fee-per-gas 100
                  :withdrawals-root (withdrawal-list-root '())))
               (parent-block (make-block :header parent-header))
               (execution-state (state-db-copy parent-state))
               (child-block
                 (execute-signed-block
                  execution-state
                  (list transaction)
                  :expected-chain-id 1
                  :header (make-block-header
                           :parent-hash (block-hash parent-block)
                           :beneficiary fee-recipient
                           :mix-hash (zero-hash32)
                           :number 42
                           :gas-limit 200000
                           :gas-used 0
                           :timestamp 99
                           :base-fee-per-gas 100)
                  :chain-config config
                  :withdrawals (list withdrawal)))
               (payload
                 (execution-payload-envelope-execution-payload
                  (block-to-executable-data child-block)))
               (request
                 (list (cons "jsonrpc" "2.0")
                       (cons "id" 31)
                       (cons "method" "engine_newPayloadV2")
                       (cons "params"
                             (list (engine-rpc-executable-data-object
                                    payload))))))
          (engine-payload-store-put-block
           store parent-block :state-available-p t)
          (commit-state-db-to-chain-store
           store (block-hash parent-block) parent-state)
          (let* ((import-response
                   (engine-rpc-handle-request
                    request store config
                    :import-function #'execute-and-commit-engine-payload))
                 (import-result (field import-response "result"))
                 (receipt-response
                   (engine-rpc-handle-request
                    (receipt-request 32 (transaction-hash transaction))
                    store config))
                 (receipt (field receipt-response "result")))
            (is (string= +payload-status-valid+
                         (field import-result "status")))
            (is (bytes= #(0)
                        (chain-store-account-code
                         store (block-hash child-block) created-contract)))
            (is (null (field receipt "contractAddress")))
            (is (string= (address-to-hex contract)
                         (field receipt "to")))
            (is (string= (quantity-to-hex 1) (field receipt "status")))
            (is (string= (quantity-to-hex 0)
                         (field receipt "transactionIndex")))
            (is (string= (hash32-to-hex (transaction-hash transaction))
                         (field receipt "transactionHash")))
            (is (string= (hash32-to-hex (block-hash child-block))
                         (field receipt "blockHash")))))))))

(deftest engine-rpc-new-payload-v2-dynamic-fee-typed-receipt
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (receipt-request (id hash)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex hash))))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :london-block 0
                                      :shanghai-time 0))
           (sender
             (address-from-hex "0xd02d72e067e77158444ef2020ff2d325f929b363"))
           (recipient
             (address-from-hex "0x1111111111111111111111111111111111111111"))
           (fee-recipient
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (withdrawal-recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
           (transaction
             (make-dynamic-fee-transaction
              :chain-id 1
              :nonce 1
              :max-priority-fee-per-gas 0
              :max-fee-per-gas #x0fa0
              :gas-limit #x84d0
              :to recipient
              :value 0
              :data #()
              :y-parity 1
              :r #xb7dfab36232379bb3d1497a4f91c1966b1f932eae3ade107bf5d723b9cb474e0
              :s #x6261c359a10f2132f126d250485b90cf20f30340801244a08ef6142ab33d1904))
           (withdrawal
             (make-withdrawal :index 0
                              :validator-index 1
                              :address withdrawal-recipient
                              :amount 1))
           (parent-state (make-state-db)))
      (state-db-set-account parent-state sender
                            (make-state-account
                             :nonce 1
                             :balance 1000000000))
      (let* ((parent-header
               (make-block-header
                :parent-hash (zero-hash32)
                :beneficiary fee-recipient
                :state-root (state-db-root parent-state)
                :mix-hash (zero-hash32)
                :number 41
                :gas-limit 100000
                :gas-used 50000
                :timestamp 98
                :base-fee-per-gas 100
                :withdrawals-root (withdrawal-list-root '())))
             (parent-block (make-block :header parent-header))
             (execution-state (state-db-copy parent-state))
             (child-block
               (execute-signed-block
                execution-state
                (list transaction)
                :expected-chain-id 1
                :header (make-block-header
                         :parent-hash (block-hash parent-block)
                         :beneficiary fee-recipient
                         :mix-hash (zero-hash32)
                         :number 42
                         :gas-limit 100000
                         :gas-used 0
                         :timestamp 99
                         :base-fee-per-gas 100)
                :chain-config config
                :withdrawals (list withdrawal)))
             (payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data child-block)))
             (request
               (list (cons "jsonrpc" "2.0")
                     (cons "id" 31)
                     (cons "method" "engine_newPayloadV2")
                     (cons "params"
                           (list (engine-rpc-executable-data-object
                                  payload))))))
        (engine-payload-store-put-block
         store parent-block :state-available-p t)
        (commit-state-db-to-chain-store
         store (block-hash parent-block) parent-state)
        (let* ((import-response
                 (engine-rpc-handle-request
                  request store config
                  :import-function #'execute-and-commit-engine-payload))
               (import-result (field import-response "result"))
               (receipts
                 (chain-store-block-receipts store (block-hash child-block)))
               (receipt-response
                 (engine-rpc-handle-request
                  (receipt-request 32 (transaction-hash transaction))
                  store config))
               (receipt (field receipt-response "result")))
          (is (string= +payload-status-valid+
                       (field import-result "status")))
          (is (= 1 (length receipts)))
          (is (string= (hash32-to-hex
                        (transaction-receipt-list-root
                         (list transaction)
                         receipts))
                       (hash32-to-hex
                        (block-header-receipts-root
                         (block-header child-block)))))
          (is (not
               (string= (hash32-to-hex (receipt-list-root receipts))
                        (hash32-to-hex
                         (block-header-receipts-root
                          (block-header child-block))))))
          (is (string= (quantity-to-hex 2) (field receipt "type")))
          (is (string= (quantity-to-hex 1) (field receipt "status")))
          (is (string= (quantity-to-hex 100)
                       (field receipt "effectiveGasPrice")))
          (is (string= (hash32-to-hex (transaction-hash transaction))
                       (field receipt "transactionHash")))
          (is (string= (hash32-to-hex (block-hash child-block))
                       (field receipt "blockHash"))))))))

(deftest engine-rpc-new-payload-v2-access-list-typed-receipt
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (receipt-request (id hash)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex hash))))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :berlin-block 0
                                      :london-block 0
                                      :shanghai-time 0))
           (sender
             (address-from-hex "0x27cf7d8449c9da59189427619ba59f985cee9c0f"))
           (recipient
             (address-from-hex "0xb94f5374fce5edbc8e2a8697c15331677e6ebf0b"))
           (fee-recipient
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (withdrawal-recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
           (transaction
             (make-access-list-transaction
              :chain-id 1
              :nonce 3
              :gas-price 1
              :gas-limit 25000
              :to recipient
              :value 10
              :data (hex-to-bytes "0x5544")
              :y-parity 1
              :r #xc9519f4f2b30335884581971573fadf60c6204f59a911df35ee8a540456b2660
              :s #x32f1e8e2c5dd761f9e4f88f41c8310aeaba26a8bfcdacfedfa12ec3862d37521))
           (withdrawal
             (make-withdrawal :index 0
                              :validator-index 1
                              :address withdrawal-recipient
                              :amount 1))
           (parent-state (make-state-db)))
      (state-db-set-account parent-state sender
                            (make-state-account
                             :nonce 3
                             :balance 1000000000))
      (let* ((parent-header
               (make-block-header
                :parent-hash (zero-hash32)
                :beneficiary fee-recipient
                :state-root (state-db-root parent-state)
                :mix-hash (zero-hash32)
                :number 41
                :gas-limit 100000
                :gas-used 50000
                :timestamp 98
                :base-fee-per-gas 1
                :withdrawals-root (withdrawal-list-root '())))
             (parent-block (make-block :header parent-header))
             (execution-state (state-db-copy parent-state))
             (child-block
               (execute-signed-block
                execution-state
                (list transaction)
                :expected-chain-id 1
                :header (make-block-header
                         :parent-hash (block-hash parent-block)
                         :beneficiary fee-recipient
                         :mix-hash (zero-hash32)
                         :number 42
                         :gas-limit 100000
                         :gas-used 0
                         :timestamp 99
                         :base-fee-per-gas 1)
                :chain-config config
                :withdrawals (list withdrawal)))
             (payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data child-block)))
             (request
               (list (cons "jsonrpc" "2.0")
                     (cons "id" 33)
                     (cons "method" "engine_newPayloadV2")
                     (cons "params"
                           (list (engine-rpc-executable-data-object
                                  payload))))))
        (engine-payload-store-put-block
         store parent-block :state-available-p t)
        (commit-state-db-to-chain-store
         store (block-hash parent-block) parent-state)
        (let* ((import-response
                 (engine-rpc-handle-request
                  request store config
                  :import-function #'execute-and-commit-engine-payload))
               (import-result (field import-response "result"))
               (receipts
                 (chain-store-block-receipts store (block-hash child-block)))
               (receipt-response
                 (engine-rpc-handle-request
                  (receipt-request 34 (transaction-hash transaction))
                  store config))
               (receipt (field receipt-response "result")))
          (is (string= +payload-status-valid+
                       (field import-result "status")))
          (is (= 1 (length receipts)))
          (is (string= (hash32-to-hex
                        (transaction-receipt-list-root
                         (list transaction)
                         receipts))
                       (hash32-to-hex
                        (block-header-receipts-root
                         (block-header child-block)))))
          (is (not
               (string= (hash32-to-hex (receipt-list-root receipts))
                        (hash32-to-hex
                         (block-header-receipts-root
                          (block-header child-block))))))
          (is (string= (quantity-to-hex 1) (field receipt "type")))
          (is (string= (quantity-to-hex 1) (field receipt "status")))
          (is (string= (quantity-to-hex 1)
                       (field receipt "effectiveGasPrice")))
          (is (string= (hash32-to-hex (transaction-hash transaction))
                       (field receipt "transactionHash")))
          (is (string= (hash32-to-hex (block-hash child-block))
                       (field receipt "blockHash"))))))))

(deftest engine-rpc-new-payload-v3-blob-typed-receipt
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (payload-request (id payload versioned-hashes)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_newPayloadV3")
                   (cons "params"
                         (list (engine-rpc-executable-data-object payload)
                               (mapcar #'hash32-to-hex versioned-hashes)
                               (hash32-to-hex (zero-hash32))))))
           (receipt-request (id hash)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex hash))))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1337
                                      :london-block 0
                                      :shanghai-time 0
                                      :cancun-time 0))
           (sender
             (address-from-hex "0x0c2c51a0990aee1d73c1228de158688341557508"))
           (fee-recipient
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (withdrawal-recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
           (transaction
             (transaction-from-encoding
              (hex-to-bytes
               "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675")))
           (expected-blob-gas-used
             (transaction-blob-gas-used transaction))
           (withdrawal
             (make-withdrawal :index 0
                              :validator-index 1
                              :address withdrawal-recipient
                              :amount 1))
           (parent-state (make-state-db)))
      (state-db-set-account parent-state sender
                            (make-state-account
                             :nonce 0
                             :balance 1000000000000000000000))
      (let* ((parent-header
               (make-block-header
                :parent-hash (zero-hash32)
                :beneficiary fee-recipient
                :state-root (state-db-root parent-state)
                :mix-hash (zero-hash32)
                :number 41
                :gas-limit 100000
                :gas-used 50000
                :timestamp 98
                :base-fee-per-gas 100
                :withdrawals-root (withdrawal-list-root '())
                :blob-gas-used 0
                :excess-blob-gas 0))
             (parent-block (make-block :header parent-header
                                       :withdrawals '()))
             (execution-state (state-db-copy parent-state))
             (child-block
               (execute-signed-block
                execution-state
                (list transaction)
                :expected-chain-id 1337
                :header (make-block-header
                         :parent-hash (block-hash parent-block)
                         :beneficiary fee-recipient
                         :mix-hash (zero-hash32)
                         :number 42
                         :gas-limit 100000
                         :gas-used 0
                         :timestamp 99
                         :base-fee-per-gas 100
                         :blob-gas-used expected-blob-gas-used
                         :excess-blob-gas 0
                         :parent-beacon-root (zero-hash32))
                :chain-config config
                :withdrawals (list withdrawal)))
             (versioned-hashes
               (coerce (transaction-blob-versioned-hashes transaction) 'list))
             (payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data child-block)))
             (request (payload-request 35 payload versioned-hashes)))
        (engine-payload-store-put-block
         store parent-block :state-available-p t)
        (commit-state-db-to-chain-store
         store (block-hash parent-block) parent-state)
        (let* ((import-response
                 (engine-rpc-handle-request
                  request store config
                  :import-function #'execute-and-commit-engine-payload))
               (import-result (field import-response "result"))
               (receipts
                 (chain-store-block-receipts store (block-hash child-block)))
               (receipt-response
                 (engine-rpc-handle-request
                  (receipt-request 36 (transaction-hash transaction))
                  store config))
               (receipt (field receipt-response "result")))
          (is (string= +payload-status-valid+
                       (field import-result "status")))
          (is (= 1 (length receipts)))
          (is (string= (hash32-to-hex
                        (transaction-receipt-list-root
                         (list transaction)
                         receipts))
                       (hash32-to-hex
                        (block-header-receipts-root
                         (block-header child-block)))))
          (is (not
               (string= (hash32-to-hex (receipt-list-root receipts))
                        (hash32-to-hex
                         (block-header-receipts-root
                          (block-header child-block))))))
          (is (string= (quantity-to-hex 3) (field receipt "type")))
          (is (string= (quantity-to-hex 1) (field receipt "status")))
          (is (string= (quantity-to-hex
                        (transaction-effective-gas-price
                         transaction
                         :base-fee (block-header-base-fee-per-gas
                                    (block-header child-block))))
                       (field receipt "effectiveGasPrice")))
          (is (string= (hash32-to-hex (transaction-hash transaction))
                       (field receipt "transactionHash")))
          (is (string= (hash32-to-hex (block-hash child-block))
                       (field receipt "blockHash"))))))))

(deftest engine-rpc-forkchoice-switches-executed-payload-visibility
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (payload-request (id payload)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_newPayloadV2")
                   (cons "params"
                         (list (engine-rpc-executable-data-object payload)))))
           (forkchoice-request (id head)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV1")
                   (cons "params"
                         (list
                          (list
                           (cons "headBlockHash" (hash32-to-hex head))
                           (cons "safeBlockHash" (hash32-to-hex (zero-hash32)))
                           (cons "finalizedBlockHash"
                                 (hash32-to-hex (zero-hash32))))))))
           (balance-request (id address)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getBalance")
                   (cons "params" (list (address-to-hex address) "latest"))))
           (transaction-request (id hash)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionByHash")
                   (cons "params" (list (hash32-to-hex hash)))))
           (receipt-request (id hash)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex hash)))))
           (block-receipts-request (id)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getBlockReceipts")
                   (cons "params" (list "latest"))))
           (block-number-request (id)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_blockNumber")
                   (cons "params" '())))
           (transaction-count-request (id address)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionCount")
                   (cons "params" (list (address-to-hex address) "latest"))))
           (code-request (id address)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getCode")
                   (cons "params" (list (address-to-hex address) "latest"))))
           (storage-request (id address)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getStorageAt")
                   (cons "params"
                         (list (address-to-hex address)
                               (quantity-to-hex 0)
                               "latest")))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :london-block 0
                                      :shanghai-time 0))
           (sender
             (address-from-hex "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (fee-recipient
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (withdrawal-recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
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
           (withdrawal
             (make-withdrawal :index 0
                              :validator-index 1
                              :address withdrawal-recipient
                              :amount 1))
           (parent-state (make-state-db)))
      (state-db-set-account parent-state sender
                            (make-state-account
                             :nonce 9
                             :balance 2000000000000000000))
      (state-db-set-code parent-state contract #(1 2 3))
      (state-db-set-storage parent-state contract (zero-hash32) 42)
      (let* ((parent-header
               (make-block-header
                :parent-hash (zero-hash32)
                :beneficiary fee-recipient
                :state-root (state-db-root parent-state)
                :mix-hash (zero-hash32)
                :number 41
                :gas-limit 50000
                :gas-used 25000
                :timestamp 98
                :base-fee-per-gas 100
                :withdrawals-root (withdrawal-list-root '())))
             (parent-block (make-block :header parent-header))
             (branch-a-state (state-db-copy parent-state))
             (branch-a-block
               (execute-signed-block
                branch-a-state
                (list transaction)
                :expected-chain-id 1
                :header (make-block-header
                         :parent-hash (block-hash parent-block)
                         :beneficiary fee-recipient
                         :mix-hash (zero-hash32)
                         :number 42
                         :gas-limit 50000
                         :gas-used 0
                         :timestamp 99
                         :base-fee-per-gas 100)
                :chain-config config
                :withdrawals (list withdrawal)))
             (branch-a-child-state (state-db-copy branch-a-state))
             (branch-a-child-block
               (execute-signed-block
                branch-a-child-state
                '()
                :expected-chain-id 1
                :header (make-block-header
                         :parent-hash (block-hash branch-a-block)
                         :beneficiary fee-recipient
                         :mix-hash (zero-hash32)
                         :number 43
                         :gas-limit 50000
                         :gas-used 0
                         :timestamp 101
                         :base-fee-per-gas 98)
                :chain-config config
                :withdrawals (list withdrawal)))
             (branch-b-state (state-db-copy parent-state))
             (branch-b-block
               (execute-signed-block
                branch-b-state
                '()
                :expected-chain-id 1
                :header (make-block-header
                         :parent-hash (block-hash parent-block)
                         :beneficiary fee-recipient
                         :mix-hash (hash32-from-hex
                                    "0x0100000000000000000000000000000000000000000000000000000000000000")
                         :number 42
                         :gas-limit 50000
                         :gas-used 0
                         :timestamp 100
                         :base-fee-per-gas 100)
                :chain-config config
                :withdrawals (list withdrawal)))
             (branch-a-payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data branch-a-block)))
             (branch-a-child-payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data branch-a-child-block)))
             (branch-b-payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data branch-b-block)))
             (transaction-hash (transaction-hash transaction)))
        (engine-payload-store-put-block
         store parent-block :state-available-p t)
        (commit-state-db-to-chain-store
         store (block-hash parent-block) parent-state)
        (dolist (request (list (payload-request 37 branch-a-payload)
                               (payload-request 38 branch-a-child-payload)
                               (payload-request 39 branch-b-payload)))
          (let* ((response
                   (engine-rpc-handle-request
                    request store config
                    :import-function #'execute-and-commit-engine-payload))
                 (status
                   (field (field response "result") "status")))
            (is (string= +payload-status-valid+ status))))
        (engine-rpc-handle-request
         (forkchoice-request 40 (block-hash branch-a-block))
         store config)
        (is (string= (hash32-to-hex (block-hash branch-a-block))
                     (hash32-to-hex (chain-store-canonical-hash store 42))))
        (is (field (engine-rpc-handle-request
                    (transaction-request 40 transaction-hash)
                    store config)
                   "result"))
        (is (field (engine-rpc-handle-request
                    (receipt-request 41 transaction-hash)
                    store config)
                   "result"))
        (is (= 1
               (length
                (field (engine-rpc-handle-request
                        (block-receipts-request 42)
                        store config)
                       "result"))))
        (is (string= (quantity-to-hex 1000000000000000000)
                     (field (engine-rpc-handle-request
                             (balance-request 43 recipient)
                             store config)
                            "result")))
        (is (string= (quantity-to-hex 10)
                     (field (engine-rpc-handle-request
                             (transaction-count-request 44 sender)
                             store config)
                            "result")))
        (is (string= "0x010203"
                     (field (engine-rpc-handle-request
                             (code-request 45 contract)
                             store config)
                            "result")))
        (is (string= "0x000000000000000000000000000000000000000000000000000000000000002a"
                     (field (engine-rpc-handle-request
                             (storage-request 46 contract)
                             store config)
                            "result")))
        (engine-rpc-handle-request
         (forkchoice-request 47 (block-hash branch-a-child-block))
         store config)
        (is (string= (hash32-to-hex (block-hash branch-a-child-block))
                     (hash32-to-hex (chain-store-canonical-hash store 43))))
        (is (= 43 (chain-store-block-tag-number store "latest")))
        (is (string= (quantity-to-hex 43)
                     (field (engine-rpc-handle-request
                             (block-number-request 48)
                             store config)
                            "result")))
        (engine-rpc-handle-request
         (forkchoice-request 49 (block-hash branch-b-block))
         store config)
        (is (string= (hash32-to-hex (block-hash branch-b-block))
                     (hash32-to-hex (chain-store-canonical-hash store 42))))
        (is (not (chain-store-canonical-hash store 43)))
        (is (= 42 (chain-store-block-tag-number store "latest")))
        (is (string= (quantity-to-hex 42)
                     (field (engine-rpc-handle-request
                             (block-number-request 50)
                             store config)
                            "result")))
        (is (not (field (engine-rpc-handle-request
                         (transaction-request 51 transaction-hash)
                         store config)
                        "result")))
        (is (not (field (engine-rpc-handle-request
                         (receipt-request 52 transaction-hash)
                         store config)
                        "result")))
        (is (not (field (engine-rpc-handle-request
                         (block-receipts-request 53)
                         store config)
                        "result")))
        (is (string= (quantity-to-hex 0)
                     (field (engine-rpc-handle-request
                             (balance-request 54 recipient)
                             store config)
                            "result")))
        (is (string= (quantity-to-hex 9)
                     (field (engine-rpc-handle-request
                             (transaction-count-request 55 sender)
                             store config)
                            "result")))
        (is (string= "0x010203"
                     (field (engine-rpc-handle-request
                             (code-request 56 contract)
                             store config)
                            "result")))
        (is (string= "0x000000000000000000000000000000000000000000000000000000000000002a"
                     (field (engine-rpc-handle-request
                             (storage-request 57 contract)
                             store config)
                            "result")))))))

(deftest engine-rpc-forkchoice-switches-executed-log-visibility
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (payload-request (id payload)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_newPayloadV2")
                   (cons "params"
                         (list (engine-rpc-executable-data-object payload)))))
           (forkchoice-request (id head)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV1")
                   (cons "params"
                         (list
                          (list
                           (cons "headBlockHash" (hash32-to-hex head))
                           (cons "safeBlockHash" (hash32-to-hex (zero-hash32)))
                           (cons "finalizedBlockHash"
                                 (hash32-to-hex (zero-hash32))))))))
           (logs-request (id)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getLogs")
                   (cons "params"
                         (list
                          (list (cons "fromBlock" "latest")
                                (cons "toBlock" "latest"))))))
           (receipt-request (id hash)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex hash)))))
           (block-receipts-request (id)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getBlockReceipts")
                   (cons "params" (list "latest"))))
           (private-key-address (private-key)
             (let* ((point
                      (ethereum-lisp.crypto::secp256k1-scalar-multiply
                       private-key
                       (ethereum-lisp.crypto::secp256k1-point
                        ethereum-lisp.crypto::+secp256k1-gx+
                        ethereum-lisp.crypto::+secp256k1-gy+)))
                    (public-key
                      (concat-bytes
                       (ethereum-lisp.crypto::integer-to-fixed-bytes
                        (ethereum-lisp.crypto::secp256k1-point-x point)
                        32)
                       (ethereum-lisp.crypto::integer-to-fixed-bytes
                        (ethereum-lisp.crypto::secp256k1-point-y point)
                        32)))
                    (hashed (keccak-256 public-key))
                    (bytes (make-byte-vector 20)))
               (replace bytes hashed :start2 12)
               (make-address bytes)))
           (sign-legacy-transaction (transaction private-key chain-id)
             (let* ((n ethereum-lisp.crypto::+secp256k1-n+)
                    (half-n ethereum-lisp.crypto::+secp256k1-half-n+)
                    (generator
                      (ethereum-lisp.crypto::secp256k1-point
                       ethereum-lisp.crypto::+secp256k1-gx+
                       ethereum-lisp.crypto::+secp256k1-gy+))
                    (hash
                      (legacy-transaction-signing-hash transaction
                                                       :chain-id chain-id))
                    (message (bytes-to-integer (hash32-bytes hash)))
                    (expected-sender (private-key-address private-key)))
               (loop for k from 1 below 256
                     for r-point =
                       (ethereum-lisp.crypto::secp256k1-scalar-multiply
                        k generator)
                     for r =
                       (mod (ethereum-lisp.crypto::secp256k1-point-x r-point)
                            n)
                     for inverse-k =
                       (ethereum-lisp.crypto::modular-inverse k n)
                     when (and (plusp r) inverse-k)
                       do (let* ((raw-s
                                   (mod (* (+ message (* r private-key))
                                           inverse-k)
                                        n))
                                 (s raw-s)
                                 (y-parity
                                   (if (oddp
                                        (ethereum-lisp.crypto::secp256k1-point-y
                                         r-point))
                                       1
                                       0)))
                            (when (plusp raw-s)
                              (when (> s half-n)
                                (setf s (- n s)
                                      y-parity (- 1 y-parity)))
                              (let ((signed
                                      (make-legacy-transaction
                                       :nonce
                                       (legacy-transaction-nonce transaction)
                                       :gas-price
                                       (legacy-transaction-gas-price
                                        transaction)
                                       :gas-limit
                                       (legacy-transaction-gas-limit
                                        transaction)
                                       :to
                                       (legacy-transaction-to transaction)
                                       :value
                                       (legacy-transaction-value transaction)
                                       :data
                                       (legacy-transaction-data transaction)
                                       :v (+ 35 (* 2 chain-id) y-parity)
                                       :r r
                                       :s s)))
                                (when (bytes=
                                       (address-bytes expected-sender)
                                       (address-bytes
                                        (legacy-transaction-sender
                                         signed
                                         :expected-chain-id chain-id)))
                                  (return signed)))))
                     finally
                       (error "Unable to sign legacy transaction fixture")))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :london-block 0
                                      :shanghai-time 0))
           (private-key 1)
           (sender (private-key-address private-key))
           (fee-recipient
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (withdrawal-recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000dd"))
           ;; SSTORE slot 1 := 42; MSTORE 0 := 7; LOG1 topic 9, mem[0:32].
           (contract-code #(96 42 96 1 85 96 7 96 0 82
                            96 9 96 32 96 0 161 0))
           (transaction
             (sign-legacy-transaction
              (make-legacy-transaction :nonce 0
                                       :gas-price 100
                                       :gas-limit 50000
                                       :to contract
                                       :value 5)
              private-key
              1))
           (second-transaction
             (sign-legacy-transaction
              (make-legacy-transaction :nonce 1
                                       :gas-price 100
                                       :gas-limit 50000
                                       :to contract
                                       :value 6)
              private-key
              1))
           (withdrawal
             (make-withdrawal :index 0
                              :validator-index 1
                              :address withdrawal-recipient
                              :amount 1))
           (parent-state (make-state-db)))
      (state-db-set-account parent-state sender
                            (make-state-account
                             :nonce 0
                             :balance 1000000000))
      (state-db-set-code parent-state contract contract-code)
      (let* ((parent-header
               (make-block-header
                :parent-hash (zero-hash32)
                :beneficiary fee-recipient
                :state-root (state-db-root parent-state)
                :mix-hash (zero-hash32)
                :number 50
                :gas-limit 100000
                :gas-used 50000
                :timestamp 200
                :base-fee-per-gas 100
                :withdrawals-root (withdrawal-list-root '())))
             (parent-block (make-block :header parent-header))
             (branch-a-state (state-db-copy parent-state))
             (branch-a-block
               (execute-signed-block
                branch-a-state
                (list transaction second-transaction)
                :expected-chain-id 1
                :header (make-block-header
                         :parent-hash (block-hash parent-block)
                         :beneficiary fee-recipient
                         :mix-hash (zero-hash32)
                         :number 51
                         :gas-limit 100000
                         :gas-used 0
                         :timestamp 201
                         :base-fee-per-gas 100)
                :chain-config config
                :withdrawals (list withdrawal)))
             (branch-b-state (state-db-copy parent-state))
             (branch-b-block
               (execute-signed-block
                branch-b-state
                '()
                :expected-chain-id 1
                :header (make-block-header
                         :parent-hash (block-hash parent-block)
                         :beneficiary fee-recipient
                         :mix-hash (hash32-from-hex
                                    "0x0200000000000000000000000000000000000000000000000000000000000000")
                         :number 51
                         :gas-limit 100000
                         :gas-used 0
                         :timestamp 202
                         :base-fee-per-gas 100)
                :chain-config config
                :withdrawals (list withdrawal)))
             (branch-a-payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data branch-a-block)))
             (branch-b-payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data branch-b-block)))
             (expected-topic-hash
               (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000009"))
             (expected-topic (hash32-to-hex expected-topic-hash))
             (expected-data
               "0x0000000000000000000000000000000000000000000000000000000000000007"))
        (engine-payload-store-put-block
         store parent-block :state-available-p t)
        (commit-state-db-to-chain-store
         store (block-hash parent-block) parent-state)
        (dolist (request (list (payload-request 58 branch-a-payload)
                               (payload-request 59 branch-b-payload)))
          (let* ((response
                   (engine-rpc-handle-request
                    request store config
                    :import-function #'execute-and-commit-engine-payload))
                 (status
                   (field (field response "result") "status")))
            (is (string= +payload-status-valid+ status))))
        (engine-rpc-handle-request
         (forkchoice-request 60 (block-hash branch-a-block))
         store config)
        (let* ((logs
                 (field (engine-rpc-handle-request
                         (logs-request 61)
                         store config)
                        "result"))
               (first-log (first logs))
               (second-log (second logs)))
          (is (= 2 (length logs)))
          (dolist (log logs)
            (is (string= (address-to-hex contract) (field log "address")))
            (is (string= expected-data (field log "data")))
            (is (string= expected-topic (first (field log "topics"))))
            (is (string= (hash32-to-hex (block-hash branch-a-block))
                         (field log "blockHash"))))
          (is (string= (hash32-to-hex (transaction-hash transaction))
                       (field first-log "transactionHash")))
          (is (string= (quantity-to-hex 0)
                       (field first-log "transactionIndex")))
          (is (string= (quantity-to-hex 0)
                       (field first-log "logIndex")))
          (is (string= (hash32-to-hex
                        (transaction-hash second-transaction))
                       (field second-log "transactionHash")))
          (is (string= (quantity-to-hex 1)
                       (field second-log "transactionIndex")))
          (is (string= (quantity-to-hex 1)
                       (field second-log "logIndex"))))
        (let* ((receipt
                 (field (engine-rpc-handle-request
                         (receipt-request 64 (transaction-hash transaction))
                         store config)
                        "result"))
               (bloom
                 (make-bloom (hex-to-bytes (field receipt "logsBloom")))))
          (is (bloom-contains-p bloom (address-bytes contract)))
          (is (bloom-contains-p bloom (hash32-bytes expected-topic-hash))))
        (let* ((receipts
                 (field (engine-rpc-handle-request
                         (block-receipts-request 65)
                         store config)
                        "result"))
               (first-receipt (first receipts))
               (second-receipt (second receipts))
               (first-cumulative
                 (hex-to-quantity
                  (field first-receipt "cumulativeGasUsed")))
               (second-cumulative
                 (hex-to-quantity
                  (field second-receipt "cumulativeGasUsed"))))
          (is (= 2 (length receipts)))
          (is (string= (hash32-to-hex (transaction-hash transaction))
                       (field first-receipt "transactionHash")))
          (is (string= (hash32-to-hex
                        (transaction-hash second-transaction))
                       (field second-receipt "transactionHash")))
          (is (< first-cumulative second-cumulative))
          (is (= (block-header-gas-used (block-header branch-a-block))
                 second-cumulative))
          (is (string= (quantity-to-hex first-cumulative)
                       (field first-receipt "gasUsed")))
          (is (string= (quantity-to-hex
                        (- second-cumulative first-cumulative))
                       (field second-receipt "gasUsed")))
          (is (string= (quantity-to-hex 0)
                       (field first-receipt "transactionIndex")))
          (is (string= (quantity-to-hex 1)
                       (field second-receipt "transactionIndex")))
          (is (= 1 (length (field first-receipt "logs"))))
          (is (= 1 (length (field second-receipt "logs"))))
          (is (string= (quantity-to-hex 0)
                       (field (first (field first-receipt "logs"))
                              "logIndex")))
          (is (string= (quantity-to-hex 1)
                       (field (first (field second-receipt "logs"))
                              "logIndex"))))
        (engine-rpc-handle-request
         (forkchoice-request 62 (block-hash branch-b-block))
         store config)
        (is (string= (hash32-to-hex (block-hash branch-b-block))
                     (hash32-to-hex (chain-store-canonical-hash store 51))))
        (is (zerop
             (length
              (field (engine-rpc-handle-request
                      (logs-request 63)
                      store config)
                     "result"))))
        (is (not
             (field (engine-rpc-handle-request
                     (receipt-request 66 (transaction-hash transaction))
                     store config)
                    "result")))
        (is (not
             (field (engine-rpc-handle-request
                     (receipt-request 67 (transaction-hash second-transaction))
                     store config)
                    "result")))
        (is (not
             (field (engine-rpc-handle-request
                     (block-receipts-request 68)
                     store config)
                    "result")))))))

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
           (unprocessed-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash head-block)
                                         :number 34
                                         :timestamp 34
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
      (engine-payload-store-put-block store unprocessed-block)
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
          (is (string= (hash32-to-hex (block-hash head-block))
                       (hash32-to-hex
                        (chain-store-canonical-hash store 32))))
          (is (not (chain-store-canonical-hash store 33)))
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
                 37
                 (forkchoice-state-object (block-hash unprocessed-block)))
                store
                config))
             (payload-status
               (field (field response "result") "payloadStatus")))
        (is (string= +payload-status-syncing+
                     (field payload-status "status")))
        (is (not (field payload-status "latestValidHash")))
        (is (not (chain-store-canonical-hash
                  store
                  (block-header-number
                   (block-header unprocessed-block))))))
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
      (let* ((unavailable-safe-block
               (make-block
                :header
                (make-block-header
                 :parent-hash (block-hash finalized-block)
                 :number 34
                 :timestamp 34
                 :gas-limit 30000000)))
             (head-over-unavailable-safe-block
               (make-block
                :header
                (make-block-header
                 :parent-hash (block-hash unavailable-safe-block)
                 :number 35
                 :timestamp 35
                 :gas-limit 30000000))))
        (engine-payload-store-put-block store unavailable-safe-block)
        (engine-payload-store-put-block
         store head-over-unavailable-safe-block :state-available-p t)
        (let* ((response
                 (engine-rpc-handle-request
                  (forkchoice-request
                   38
                   (forkchoice-state-object
                    (block-hash head-over-unavailable-safe-block)
                    :safe (block-hash unavailable-safe-block)))
                  store
                  config))
               (error (field response "error")))
          (is (= -38002 (field error "code")))
          (is (string= "forkchoice safe block state is not available"
                       (field error "message")))
          (is (eq safe-block (chain-store-safe-block store)))))
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

(deftest engine-rpc-forkchoice-update-rolls-back-checkpoints-on-head-rewrite-error
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
           (forkchoice-request (id state)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV1")
                   (cons "params" (list state)))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (genesis
             (make-block
              :header (make-block-header :number 0
                                         :parent-hash (zero-hash32)
                                         :timestamp 0
                                         :gas-limit 30000000)))
           (old-head
             (make-block
              :header (make-block-header :parent-hash (block-hash genesis)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000)))
           (missing-parent-hash
             (hash32-from-hex
              "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
           (orphan-head
             (make-block
              :header (make-block-header :parent-hash missing-parent-hash
                                         :number 2
                                         :timestamp 24
                                         :gas-limit 30000000))))
      (engine-payload-store-put-block store genesis :state-available-p t)
      (engine-payload-store-put-block store old-head :state-available-p t)
      (engine-payload-store-put-block store orphan-head :state-available-p t)
      (engine-rpc-handle-request
       (forkchoice-request
        39
        (forkchoice-state-object
         (block-hash old-head)
         :safe (block-hash genesis)
         :finalized (block-hash genesis)))
       store
       config)
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 40
                 (forkchoice-state-object
                  (block-hash orphan-head)))
                store
                config))
             (error (field response "error")))
        (is (= 40 (field response "id")))
        (is (= -32602 (field error "code")))
        (is (string= "Canonical head ancestry must be fully known"
                     (field error "message")))
        (is (eq old-head (chain-store-head-block store)))
        (is (eq genesis (chain-store-safe-block store)))
        (is (eq genesis (chain-store-finalized-block store)))
        (is (string= (hash32-to-hex (block-hash old-head))
                     (hash32-to-hex
                      (chain-store-canonical-hash store 1))))
        (is (not (chain-store-canonical-hash store 2)))))))

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
             (missing-state-error (field missing-state-response "error"))
             (missing-block-error (field missing-block-response "error"))
             (invalid-address-error (field invalid-address-response "error"))
             (invalid-params-error (field invalid-params-response "error")))
        (is (string= (quantity-to-hex 12345)
                     (field number-response "result")))
        (is (string= (quantity-to-hex 12345)
                     (field hash-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field empty-account-response "result")))
        (is (= -32602 (field missing-state-error "code")))
        (is (string= "eth_getBalance state is not available"
                     (field missing-state-error "message")))
        (is (= -32602 (field missing-block-error "code")))
        (is (string= "eth_getBalance block is not available"
                     (field missing-block-error "message")))
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
              :nonce 7
              :gas-price 11
              :gas-limit 21100
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
             (missing-state-error (field missing-state-response "error"))
             (invalid-address-error (field invalid-address-response "error"))
             (invalid-params-error (field invalid-params-response "error")))
        (is (string= (quantity-to-hex 7)
                     (field number-response "result")))
        (is (string= (quantity-to-hex 7)
                     (field hash-response "result")))
        (is (string= (hash32-to-hex (transaction-hash pending-transaction))
                     (field send-pending-response "result")))
        (is (string= (quantity-to-hex 8)
                     (field pending-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field empty-account-response "result")))
        (is (= -32602 (field missing-state-error "code")))
        (is (string= "eth_getTransactionCount state is not available"
                     (field missing-state-error "message")))
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
             (missing-state-error (field missing-state-response "error"))
             (invalid-address-error (field invalid-address-response "error"))
             (invalid-params-error (field invalid-params-response "error")))
        (is (string= "0x60016000"
                     (field number-response "result")))
        (is (string= "0x60016000"
                     (field hash-response "result")))
        (is (string= "0x"
                     (field empty-account-response "result")))
        (is (= -32602 (field missing-state-error "code")))
        (is (string= "eth_getCode state is not available"
                     (field missing-state-error "message")))
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
             (missing-state-error (field missing-state-response "error"))
             (invalid-slot-error (field invalid-slot-response "error"))
             (invalid-params-error (field invalid-params-response "error"))
             (expected-word
               "0x000000000000000000000000000000000000000000000000000000000000002a")
             (zero-word
               "0x0000000000000000000000000000000000000000000000000000000000000000"))
        (is (string= expected-word (field number-response "result")))
        (is (string= expected-word (field hash-response "result")))
        (is (string= zero-word (field empty-account-response "result")))
        (is (= -32602 (field missing-state-error "code")))
        (is (string= "eth_getStorageAt state is not available"
                     (field missing-state-error "message")))
        (is (= -32602 (field invalid-slot-error "code")))
        (is (= -32602 (field invalid-params-error "code")))))))

(deftest eth-rpc-get-proof
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (json-string-list (values)
             (with-output-to-string (stream)
               (write-char #\[ stream)
               (loop for value in values
                     for first-p = t then nil
                     unless first-p do (write-char #\, stream)
                     do (format stream "\"~A\"" value))
               (write-char #\] stream)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof)))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x0000000000000000000000000000000000000103"))
           (empty-address
             (address-from-hex "0x0000000000000000000000000000000000000104"))
           (slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000007"))
           (missing-slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000008"))
           (state (make-state-db))
           (state-block
             (make-block
              :header (make-block-header :number 28
                                         :timestamp 280
                                         :gas-limit 30000000)))
           (missing-state-block
             (make-block
              :header (make-block-header :number 29
                                         :timestamp 290
                                         :gas-limit 30000000)))
           (config (make-chain-config)))
      (state-db-set-account state address
                            (make-state-account :nonce 3 :balance 1000))
      (state-db-set-code state address #(96 1 96 0))
      (state-db-set-storage state address slot #x2a)
      (state-db-set-account state address
                            (make-state-account :nonce 3 :balance 1000))
      (setf (block-header-state-root (block-header state-block))
            (state-db-root state))
      (chain-store-put-block store state-block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash state-block) state)
      (engine-payload-store-put-block store missing-state-block)
      (let* ((proof-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":98,"
                  "\"method\":\"eth_getProof\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",[\"0x7\",\""
                  (hash32-to-hex missing-slot)
                  "\",\"7\",\""
                  (subseq (hash32-to-hex slot) 2)
                  "\",\"0X7\"],\"0x1c\"]}")
                 store
                 config)))
             (empty-account-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":99,"
                  "\"method\":\"eth_getProof\","
                  "\"params\":[\"" (address-to-hex empty-address)
                  "\",[\"0x7\"],\"0x1c\"]}")
                 store
                 config)))
             (missing-state-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":100,"
                  "\"method\":\"eth_getProof\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",[\"0x7\"],\"0x1d\"]}")
                 store
                 config)))
             (invalid-storage-keys-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":101,"
                  "\"method\":\"eth_getProof\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",\"0x7\",\"0x1c\"]}")
                 store
                 config)))
             (invalid-params-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":102,"
                  "\"method\":\"eth_getProof\","
                  "\"params\":[\"" (address-to-hex address) "\"]}")
                 store
                 config)))
             (too-many-storage-keys-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":103,"
                  "\"method\":\"eth_getProof\","
                  "\"params\":[\"" (address-to-hex address)
                  "\","
                  (json-string-list
                   (loop repeat (1+ ethereum-lisp.core::+eth-get-proof-max-storage-keys+)
                         collect "0x0"))
                  ",\"0x1c\"]}")
                 store
                 config)))
             (proof (field proof-response "result"))
             (storage-proofs (field proof "storageProof"))
             (first-storage (first storage-proofs))
             (second-storage (second storage-proofs))
             (third-storage (third storage-proofs))
             (fourth-storage (fourth storage-proofs))
             (fifth-storage (fifth storage-proofs))
             (empty-proof (field empty-account-response "result"))
             (expected-proof
               (state-db-get-proof
                state
                address
                (list slot missing-slot slot slot slot)))
             (missing-state-error (field missing-state-response "error"))
             (invalid-storage-keys-error
               (field invalid-storage-keys-response "error"))
             (invalid-params-error (field invalid-params-response "error"))
             (too-many-storage-keys-error
               (field too-many-storage-keys-response "error")))
        (is (string= (address-to-hex address)
                     (field proof "address")))
        (is (string= (quantity-to-hex 1000)
                     (field proof "balance")))
        (is (string= (quantity-to-hex 3)
                     (field proof "nonce")))
        (is (string= (hash32-to-hex (keccak-256-hash #(96 1 96 0)))
                     (field proof "codeHash")))
        (is (listp (field proof "accountProof")))
        (is (every #'stringp (field proof "accountProof")))
        (is (equal (proof-node-hex-list
                    (state-proof-result-account-proof expected-proof))
                   (field proof "accountProof")))
        (is (= 5 (length storage-proofs)))
        (is (string= (quantity-to-hex 7) (field first-storage "key")))
        (is (string= "0x2a" (field first-storage "value")))
        (is (every #'stringp (field first-storage "proof")))
        (is (equal (proof-node-hex-list
                    (state-storage-proof-proof
                     (first (state-proof-result-storage-proofs expected-proof))))
                   (field first-storage "proof")))
        (is (string= (hash32-to-hex missing-slot)
                     (field second-storage "key")))
        (is (string= (quantity-to-hex 0)
                     (field second-storage "value")))
        (is (every #'stringp (field second-storage "proof")))
        (is (equal (proof-node-hex-list
                    (state-storage-proof-proof
                     (second (state-proof-result-storage-proofs expected-proof))))
                   (field second-storage "proof")))
        (is (string= (quantity-to-hex 7) (field third-storage "key")))
        (is (string= "0x2a" (field third-storage "value")))
        (is (string= (hash32-to-hex slot) (field fourth-storage "key")))
        (is (string= "0x2a" (field fourth-storage "value")))
        (is (every #'stringp (field fourth-storage "proof")))
        (is (string= (quantity-to-hex 7) (field fifth-storage "key")))
        (is (string= "0x2a" (field fifth-storage "value")))
        (is (string= (address-to-hex empty-address)
                     (field empty-proof "address")))
        (is (string= (quantity-to-hex 0)
                     (field empty-proof "balance")))
        (is (string= (hash32-to-hex +empty-code-hash+)
                     (field empty-proof "codeHash")))
        (is (= -32602 (field missing-state-error "code")))
        (is (string= "eth_getProof state is not available"
                     (field missing-state-error "message")))
        (is (= -32602 (field invalid-storage-keys-error "code")))
        (is (= -32602 (field invalid-params-error "code")))
        (is (= -32602 (field too-many-storage-keys-error "code")))))))

(deftest eth-rpc-get-proof-geth-secure-account-state
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (add-account (state address nonce balance)
             (state-db-set-account
              state
              (address-from-hex address)
              (make-state-account :nonce nonce :balance balance)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (address block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 104)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               nil
                               (hash32-to-hex (block-hash block)))))))
    (let* ((store (make-engine-payload-memory-store))
           (state (make-state-db))
           (cases
             '(("0x0194fdc2fa2ffcc041d3ff12045b73c86e4ff95f"
                "0xb79ef856f65f67cf"
                "0x2077ccce0d8fc159")
               ("0xf662a5eee82abdf44a2d0b75fb180daf48a79ee0"
                "0xe242cf3c6a9f4a578bcb9ef2d4a65314768d6d299761ea9e4f"
                "0x64bed6e2edf354c3")
               ("0xb10d394651850fd4a178892ee285ece151145578"
                "0x20efcd6cea84b6925e607be06371"
                "0x1ec678fcc3aea65a"))))
      (add-account state
                   "0x0194fdc2fa2ffcc041d3ff12045b73c86e4ff95f"
                   2339563716805116249
                   13231285807645419471)
      (add-account state
                   "0xf662a5eee82abdf44a2d0b75fb180daf48a79ee0"
                   7259475919510918339
                   1420263156754097894072208833565313120560341020854497370086991)
      (add-account state
                   "0xb10d394651850fd4a178892ee285ece151145578"
                   2217592893536642650
                   668036214256246407260665125299057)
      (let* ((block (commit-state-block store state 30 300))
             (config (make-chain-config)))
        (is (string= "0x65e27b7b7b43826149e6b5674be3ff0f107ff6e988d20c1be165a172eeef399d"
                     (state-db-root-hex state)))
        (dolist (case cases)
          (destructuring-bind (address-hex balance nonce) case
            (let* ((address (address-from-hex address-hex))
                   (response (engine-rpc-handle-request
                              (proof-request address block)
                              store
                              config))
                   (proof (field response "result"))
                   (expected-proof (state-db-get-proof state address nil))
                   (decoded-proof (state-proof-result-from-rpc-object proof)))
              (is (equal (state-proof-result-rpc-object expected-proof)
                         proof))
              (is (string= (address-to-hex address)
                           (field proof "address")))
              (is (string= balance
                           (field proof "balance")))
              (is (string= nonce
                           (field proof "nonce")))
              (is (string= (hash32-to-hex +empty-code-hash+)
                           (field proof "codeHash")))
              (is (string= (hash32-to-hex +empty-trie-hash+)
                           (field proof "storageHash")))
              (is (= 2 (length (field proof "accountProof"))))
              (is (null (field proof "storageProof")))
              (is (state-db-verify-proof (state-db-root state)
                                         decoded-proof)))))))))

(deftest eth-rpc-get-proof-missing-clear-nontrivial-state-tries
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof))
           (add-account (state address nonce balance)
             (state-db-set-account
              state
              (address-from-hex address)
              (make-state-account :nonce nonce :balance balance)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (assert-missing-clear-proof (store state block missing)
             (let* ((response
                      (parse-json
                       (engine-rpc-handle-request-json
                        (concatenate
                         'string
                         "{\"jsonrpc\":\"2.0\",\"id\":109,"
                         "\"method\":\"eth_getProof\","
                         "\"params\":[\"" (address-to-hex missing)
                         "\",[],\"" (hash32-to-hex (block-hash block))
                         "\"]}")
                        store
                        (make-chain-config))))
                    (proof (field response "result"))
                    (expected-proof
                      (state-db-get-proof state missing nil)))
               (is (string= (address-to-hex missing)
                            (field proof "address")))
               (is (string= (quantity-to-hex 0)
                            (field proof "balance")))
               (is (string= (quantity-to-hex 0)
                            (field proof "nonce")))
               (is (string= (hash32-to-hex +empty-code-hash+)
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (is (null (field proof "storageProof")))
               (is (equal (proof-node-hex-list
                           (state-proof-result-account-proof expected-proof))
                          (field proof "accountProof"))))))
    (let* ((store (make-engine-payload-memory-store))
           (missing (address-from-hex
                     "0x00000000000000000000000000000000000002ff"))
           (extension-state (make-state-db))
           (branch-extension-state (make-state-db)))
      (add-account extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (state-db-clear-account extension-state missing)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000203"
                   3 300)
      (state-db-clear-account branch-extension-state missing)
      (assert-missing-clear-proof
       store
       extension-state
       (commit-state-block store extension-state 33 330)
       missing)
      (assert-missing-clear-proof
       store
       branch-extension-state
       (commit-state-block store branch-extension-state 34 340)
       missing))))

(deftest eth-rpc-get-proof-state-trie-delete-collapse
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof))
           (add-account (state address nonce balance)
             (state-db-set-account
              state
              (address-from-hex address)
              (make-state-account :nonce nonce :balance balance)))
           (add-code-storage (state address)
             (state-db-set-storage
              state
              address
              (hash32-from-hex
               "0x000000000000000000000000000000000000000000000000000000000000002a")
              42)
             (state-db-set-code state address #(96 1 96 0)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (assert-delete-collapse-proof
               (store state block address expected-root expected-nodes
                expected-balance expected-nonce)
             (let* ((response
                      (parse-json
                       (engine-rpc-handle-request-json
                        (concatenate
                         'string
                         "{\"jsonrpc\":\"2.0\",\"id\":123,"
                         "\"method\":\"eth_getProof\","
                         "\"params\":[\"" (address-to-hex address)
                         "\",[],\"" (hash32-to-hex (block-hash block))
                         "\"]}")
                        store
                        (make-chain-config))))
                    (proof (field response "result"))
                    (expected-proof
                      (state-db-get-proof state address nil))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (is (string= expected-root (state-db-root-hex state)))
               (is (string= (address-to-hex address)
                            (field proof "address")))
               (is (string= (quantity-to-hex expected-balance)
                            (field proof "balance")))
               (is (string= (quantity-to-hex expected-nonce)
                            (field proof "nonce")))
               (is (string= (hash32-to-hex +empty-code-hash+)
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (is (null (field proof "storageProof")))
               (is (= expected-nodes
                      (length (field proof "accountProof"))))
               (is (equal (proof-node-hex-list
                           (state-proof-result-account-proof expected-proof))
                          (field proof "accountProof")))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (branch-survivor
             (address-from-hex "0x0000000000000000000000000000000000000201"))
           (branch-deleted
             (address-from-hex "0x0000000000000000000000000000000000000211"))
           (extension-survivor
             (address-from-hex "0x0000000000000000000000000000000000000220"))
           (extension-deleted
             (address-from-hex "0x0000000000000000000000000000000000000225"))
           (branch-extension-deleted
             (address-from-hex "0x0000000000000000000000000000000000000203"))
           (branch-state (make-state-db))
           (extension-state (make-state-db))
           (branch-extension-state (make-state-db)))
      (add-account branch-state
                   "0x0000000000000000000000000000000000000201"
                   1 100)
      (add-account branch-state
                   "0x0000000000000000000000000000000000000211"
                   2 200)
      (add-code-storage branch-state branch-deleted)
      (state-db-clear-account branch-state branch-deleted)
      (add-account extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-code-storage extension-state extension-deleted)
      (state-db-clear-account extension-state extension-deleted)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000203"
                   3 300)
      (add-code-storage branch-extension-state branch-extension-deleted)
      (state-db-clear-account branch-extension-state branch-extension-deleted)
      (let ((branch-block (commit-state-block store branch-state 50 500))
            (extension-block (commit-state-block store extension-state 51 510))
            (branch-extension-block
              (commit-state-block store branch-extension-state 52 520)))
        (assert-delete-collapse-proof
         store
         branch-state
         branch-block
         branch-survivor
         "0x18742ec02ab527594bc83d163360c5b677ca92e37b5a0d5673920a895645b8a1"
         1
         100
         1)
        (assert-delete-collapse-proof
         store
         branch-state
         branch-block
         branch-deleted
         "0x18742ec02ab527594bc83d163360c5b677ca92e37b5a0d5673920a895645b8a1"
         1
         0
         0)
        (assert-delete-collapse-proof
         store
         extension-state
         extension-block
         extension-survivor
         "0x006c6cf2120be53e089f44cb328653de92ca2a9a4970a6a9137148b829c47509"
         1
         100
         1)
        (assert-delete-collapse-proof
         store
         extension-state
         extension-block
         extension-deleted
         "0x006c6cf2120be53e089f44cb328653de92ca2a9a4970a6a9137148b829c47509"
         1
         0
         0)
        (assert-delete-collapse-proof
         store
         branch-extension-state
         branch-extension-block
         extension-survivor
         "0x107571af3beeb3b5f3d1b49b593066ac344ab7e98f657ee27670315fcbde6509"
         3
         100
         1)
        (assert-delete-collapse-proof
         store
         branch-extension-state
         branch-extension-block
         branch-extension-deleted
         "0x107571af3beeb3b5f3d1b49b593066ac344ab7e98f657ee27670315fcbde6509"
         1
         0
         0)))))

(deftest eth-rpc-get-proof-balance-add-nontrivial-state-tries
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof))
           (add-account (state address nonce balance)
             (state-db-set-account
              state
              (address-from-hex address)
              (make-state-account :nonce nonce :balance balance)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (assert-balance-add-proof
             (store state block target expected-balance expected-nodes)
             (let* ((response
                      (parse-json
                       (engine-rpc-handle-request-json
                        (concatenate
                         'string
                         "{\"jsonrpc\":\"2.0\",\"id\":110,"
                         "\"method\":\"eth_getProof\","
                         "\"params\":[\"" (address-to-hex target)
                         "\",[],\"" (hash32-to-hex (block-hash block))
                         "\"]}")
                        store
                        (make-chain-config))))
                    (proof (field response "result"))
                    (expected-proof
                      (state-db-get-proof state target nil))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (is (string= (address-to-hex target)
                            (field proof "address")))
               (is (string= (quantity-to-hex expected-balance)
                            (field proof "balance")))
               (is (string= (quantity-to-hex 1)
                            (field proof "nonce")))
               (is (string= (hash32-to-hex +empty-code-hash+)
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (is (null (field proof "storageProof")))
               (is (= expected-nodes
                      (length (field proof "accountProof"))))
               (is (equal (proof-node-hex-list
                           (state-proof-result-account-proof expected-proof))
                          (field proof "accountProof")))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof))))
           (assert-balance-add-zero-missing-proof
             (store state block target expected-nodes)
             (let* ((storage-key
                      "0x0000000000000000000000000000000000000000000000000000000000000001")
                    (response
                      (parse-json
                       (engine-rpc-handle-request-json
                        (concatenate
                         'string
                         "{\"jsonrpc\":\"2.0\",\"id\":111,"
                         "\"method\":\"eth_getProof\","
                         "\"params\":[\"" (address-to-hex target)
                         "\",[\"" storage-key "\"],\""
                         (hash32-to-hex (block-hash block))
                         "\"]}")
                        store
                        (make-chain-config))))
                    (proof (field response "result"))
                    (expected-proof
                      (state-db-get-proof
                       state
                       target
                       (list (hash32-from-hex storage-key))))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof))
                    (storage-proof
                      (first (field proof "storageProof"))))
               (is (string= (address-to-hex target)
                            (field proof "address")))
               (is (string= "0x0" (field proof "balance")))
               (is (string= "0x0" (field proof "nonce")))
               (is (string= (hash32-to-hex +empty-code-hash+)
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (is (= expected-nodes
                      (length (field proof "accountProof"))))
               (is (string= storage-key (field storage-proof "key")))
               (is (string= "0x0" (field storage-proof "value")))
               (is (null (field storage-proof "proof")))
               (is (equal (proof-node-hex-list
                           (state-proof-result-account-proof expected-proof))
                          (field proof "accountProof")))
               (is (equal (state-proof-result-rpc-object expected-proof)
                          proof))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (branch-target
             (address-from-hex "0x0000000000000000000000000000000000000201"))
           (extension-target
             (address-from-hex "0x0000000000000000000000000000000000000220"))
           (missing-target
             (address-from-hex "0x00000000000000000000000000000000000002ff"))
           (branch-state (make-state-db))
           (extension-state (make-state-db))
           (branch-extension-state (make-state-db))
           (branch-existing-zero-state (make-state-db))
           (extension-existing-zero-state (make-state-db))
           (branch-extension-existing-zero-state (make-state-db))
           (branch-zero-state (make-state-db))
           (extension-zero-state (make-state-db))
           (branch-extension-zero-state (make-state-db)))
      (add-account branch-state
                   "0x0000000000000000000000000000000000000201"
                   1 100)
      (add-account branch-state
                   "0x0000000000000000000000000000000000000211"
                   2 200)
      (state-db-add-balance branch-state branch-target 300)
      (add-account extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (state-db-add-balance extension-state extension-target 300)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000203"
                   3 300)
      (state-db-add-balance branch-extension-state extension-target 300)
      (add-account branch-existing-zero-state
                   "0x0000000000000000000000000000000000000201"
                   1 100)
      (add-account branch-existing-zero-state
                   "0x0000000000000000000000000000000000000211"
                   2 200)
      (state-db-add-balance branch-existing-zero-state branch-target 0)
      (add-account extension-existing-zero-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account extension-existing-zero-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (state-db-add-balance extension-existing-zero-state extension-target 0)
      (add-account branch-extension-existing-zero-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account branch-extension-existing-zero-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-existing-zero-state
                   "0x0000000000000000000000000000000000000203"
                   3 300)
      (state-db-add-balance branch-extension-existing-zero-state
                            extension-target
                            0)
      (add-account branch-zero-state
                   "0x0000000000000000000000000000000000000201"
                   1 100)
      (add-account branch-zero-state
                   "0x0000000000000000000000000000000000000211"
                   2 200)
      (state-db-add-balance branch-zero-state missing-target 0)
      (add-account extension-zero-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account extension-zero-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (state-db-add-balance extension-zero-state missing-target 0)
      (add-account branch-extension-zero-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account branch-extension-zero-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-zero-state
                   "0x0000000000000000000000000000000000000203"
                   3 300)
      (state-db-add-balance branch-extension-zero-state missing-target 0)
      (assert-balance-add-proof
       store
       branch-state
       (commit-state-block store branch-state 35 350)
       branch-target
       400
       2)
      (assert-balance-add-proof
       store
       extension-state
       (commit-state-block store extension-state 36 360)
       extension-target
       400
       3)
      (assert-balance-add-proof
       store
       branch-extension-state
       (commit-state-block store branch-extension-state 37 370)
       extension-target
       400
       4)
      (assert-balance-add-proof
       store
       branch-existing-zero-state
       (commit-state-block store branch-existing-zero-state 38 380)
       branch-target
       100
       2)
      (assert-balance-add-proof
       store
       extension-existing-zero-state
       (commit-state-block store extension-existing-zero-state 39 390)
       extension-target
       100
       3)
      (assert-balance-add-proof
       store
       branch-extension-existing-zero-state
       (commit-state-block store branch-extension-existing-zero-state 40 400)
       extension-target
       100
       4)
      (assert-balance-add-zero-missing-proof
       store
       branch-zero-state
       (commit-state-block store branch-zero-state 41 410)
       missing-target
       2)
      (assert-balance-add-zero-missing-proof
       store
       extension-zero-state
       (commit-state-block store extension-zero-state 42 420)
       missing-target
       1)
      (assert-balance-add-zero-missing-proof
       store
       branch-extension-zero-state
       (commit-state-block store branch-extension-zero-state 43 430)
       missing-target
       2))))

(deftest eth-rpc-get-proof-value-transfer
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (id address storage-keys block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (mapcar #'hash32-to-hex storage-keys)
                               (hash32-to-hex (block-hash block))))))
           (assert-transfer-proof
             (store state block address storage-keys expected-root
              expected-balance expected-nonce expected-storage-proof-count
              &key expected-account-proof-count)
             (let* ((response
                      (engine-rpc-handle-request
                       (proof-request 132 address storage-keys block)
                       store
                       (make-chain-config)))
                    (proof (field response "result"))
                    (expected-proof
                      (state-db-get-proof state address storage-keys))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (is (string= expected-root
                            (state-db-root-hex state)))
               (is (equal (state-proof-result-rpc-object expected-proof)
                          proof))
               (is (string= (address-to-hex address)
                            (field proof "address")))
               (is (string= (quantity-to-hex expected-balance)
                            (field proof "balance")))
               (is (string= (quantity-to-hex expected-nonce)
                            (field proof "nonce")))
               (is (string= (hash32-to-hex +empty-code-hash+)
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (when expected-account-proof-count
                 (is (= expected-account-proof-count
                        (length (field proof "accountProof")))))
               (is (= expected-storage-proof-count
                      (length (field proof "storageProof"))))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (sender
             (address-from-hex "0x0000000000000000000000000000000000000301"))
           (recipient
             (address-from-hex "0x0000000000000000000000000000000000000302"))
           (zero-sender
             (address-from-hex "0x0000000000000000000000000000000000000303"))
           (missing-recipient
             (address-from-hex "0x0000000000000000000000000000000000000304"))
           (missing-slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000001"))
           (branch-sender
             (address-from-hex "0x0000000000000000000000000000000000000201"))
           (branch-sibling
             (address-from-hex "0x0000000000000000000000000000000000000211"))
           (branch-recipient
             (address-from-hex "0x0000000000000000000000000000000000000202"))
           (extension-sender
             (address-from-hex "0x0000000000000000000000000000000000000220"))
           (extension-recipient
             (address-from-hex "0x0000000000000000000000000000000000000201"))
           (extension-sibling
             (address-from-hex "0x0000000000000000000000000000000000000225"))
           (branch-extension-extra
             (address-from-hex "0x0000000000000000000000000000000000000203"))
           (transfer-state (make-state-db))
           (zero-transfer-state (make-state-db))
           (branch-transfer-state (make-state-db))
           (extension-transfer-state (make-state-db))
           (branch-extension-transfer-state (make-state-db)))
      (state-db-set-account
       transfer-state sender (make-state-account :nonce 1 :balance 100))
      (ethereum-lisp.state::state-db-transfer-value
       transfer-state sender recipient 37)
      (state-db-set-account
       zero-transfer-state
       zero-sender
       (make-state-account :nonce 2 :balance 100))
      (ethereum-lisp.state::state-db-transfer-value
       zero-transfer-state zero-sender missing-recipient 0)
      (state-db-set-account
       branch-transfer-state
       branch-sender
       (make-state-account :nonce 1 :balance 100))
      (state-db-set-account
       branch-transfer-state
       branch-sibling
       (make-state-account :nonce 2 :balance 200))
      (ethereum-lisp.state::state-db-transfer-value
       branch-transfer-state branch-sender branch-recipient 37)
      (state-db-set-account
       extension-transfer-state
       extension-sender
       (make-state-account :nonce 1 :balance 100))
      (state-db-set-account
       extension-transfer-state
       extension-sibling
       (make-state-account :nonce 2 :balance 200))
      (ethereum-lisp.state::state-db-transfer-value
       extension-transfer-state extension-sender extension-recipient 37)
      (state-db-set-account
       branch-extension-transfer-state
       extension-sender
       (make-state-account :nonce 1 :balance 100))
      (state-db-set-account
       branch-extension-transfer-state
       extension-sibling
       (make-state-account :nonce 2 :balance 200))
      (state-db-set-account
       branch-extension-transfer-state
       branch-extension-extra
       (make-state-account :nonce 3 :balance 300))
      (ethereum-lisp.state::state-db-transfer-value
       branch-extension-transfer-state
       extension-sender
       extension-recipient
       37)
      (let ((transfer-block
              (commit-state-block store transfer-state 44 440))
            (zero-transfer-block
              (commit-state-block store zero-transfer-state 45 450))
            (branch-transfer-block
              (commit-state-block store branch-transfer-state 46 460))
            (extension-transfer-block
              (commit-state-block store extension-transfer-state 47 470))
            (branch-extension-transfer-block
              (commit-state-block
               store branch-extension-transfer-state 48 480)))
        (assert-transfer-proof
         store
         transfer-state
         transfer-block
         sender
         nil
         "0xeb1be297ad9e87812158dcb9b646fe55dfc2e89526b65cf76bd4fe3b40c68da9"
         63
         1
         0)
        (assert-transfer-proof
         store
         transfer-state
         transfer-block
         recipient
         nil
         "0xeb1be297ad9e87812158dcb9b646fe55dfc2e89526b65cf76bd4fe3b40c68da9"
         37
         0
         0)
        (assert-transfer-proof
         store
         zero-transfer-state
         zero-transfer-block
         missing-recipient
         (list missing-slot)
         "0x600e37f427a9f42ebe6b592ff989ec26a865aa3d89c955bb78dbf53890cbeb41"
         0
         0
         1)
        (assert-transfer-proof
         store
         branch-transfer-state
         branch-transfer-block
         branch-sender
         nil
         "0x4dd8ed5858a2fce6bf433fa35e5cc54821ad964aa7a2dd979ea34336ff8b6544"
         63
         1
         0
         :expected-account-proof-count 3)
        (assert-transfer-proof
         store
         branch-transfer-state
         branch-transfer-block
         branch-recipient
         nil
         "0x4dd8ed5858a2fce6bf433fa35e5cc54821ad964aa7a2dd979ea34336ff8b6544"
         37
         0
         0
         :expected-account-proof-count 3)
        (assert-transfer-proof
         store
         extension-transfer-state
         extension-transfer-block
         extension-sender
         nil
         "0x62d868986c4260fa44341f1c75694a5180bb3caaa21efe07f7bab246f22a2aa2"
         63
         1
         0
         :expected-account-proof-count 4)
        (assert-transfer-proof
         store
         extension-transfer-state
         extension-transfer-block
         extension-recipient
         nil
         "0x62d868986c4260fa44341f1c75694a5180bb3caaa21efe07f7bab246f22a2aa2"
         37
         0
         0
         :expected-account-proof-count 3)
        (assert-transfer-proof
         store
         branch-extension-transfer-state
         branch-extension-transfer-block
         extension-sender
         nil
         "0xc86e674a6e90c03f48bc01ea942843efe0eb52fba078dbff71fa44b8c4651aa5"
         63
         1
         0
         :expected-account-proof-count 4)
        (assert-transfer-proof
         store
         branch-extension-transfer-state
         branch-extension-transfer-block
         extension-recipient
         nil
         "0xc86e674a6e90c03f48bc01ea942843efe0eb52fba078dbff71fa44b8c4651aa5"
         37
         0
         0
         :expected-account-proof-count 3)))))

(deftest eth-rpc-get-proof-zero-storage-writes
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (id address slot block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (list (hash32-to-hex slot))
                               (hash32-to-hex (block-hash block))))))
           (assert-zero-storage-proof
               (store state block address slot expected-balance
                expected-code-hash)
             (let* ((response
                      (engine-rpc-handle-request
                       (proof-request 118 address slot block)
                       store
                       (make-chain-config)))
                    (proof (field response "result"))
                    (storage-proof (first (field proof "storageProof")))
                    (expected-proof
                      (state-db-get-proof state address (list slot)))
                    (expected-storage-proof
                      (first (state-proof-result-storage-proofs
                              expected-proof)))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (is (string= (address-to-hex address)
                            (field proof "address")))
               (is (string= (quantity-to-hex expected-balance)
                            (field proof "balance")))
               (is (string= (hash32-to-hex expected-code-hash)
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (is (= 1 (length (field proof "storageProof"))))
               (is (string= (hash32-to-hex slot)
                            (field storage-proof "key")))
               (is (string= (quantity-to-hex 0)
                            (field storage-proof "value")))
               (is (null (field storage-proof "proof")))
               (is (equal (proof-node-hex-list
                           (state-proof-result-account-proof expected-proof))
                          (field proof "accountProof")))
               (is (equal (proof-node-hex-list
                           (state-storage-proof-proof expected-storage-proof))
                          (field storage-proof "proof")))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (missing-address
             (address-from-hex "0x0000000000000000000000000000000000000402"))
           (funded-address
             (address-from-hex "0x0000000000000000000000000000000000000403"))
           (code-address
             (address-from-hex "0x0000000000000000000000000000000000000404"))
           (slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000001"))
           (code #(96 1 96 0))
           (missing-state (make-state-db))
           (funded-state (make-state-db))
           (code-state (make-state-db)))
      (state-db-set-storage missing-state missing-address slot 0)
      (state-db-set-account funded-state funded-address
                            (make-state-account :balance 1))
      (state-db-set-storage funded-state funded-address slot 0)
      (state-db-set-code code-state code-address code)
      (state-db-set-storage code-state code-address slot 0)
      (assert-zero-storage-proof
       store
       missing-state
       (commit-state-block store missing-state 38 380)
       missing-address
       slot
       0
       +empty-code-hash+)
      (assert-zero-storage-proof
       store
       funded-state
       (commit-state-block store funded-state 39 390)
       funded-address
       slot
       1
       +empty-code-hash+)
      (assert-zero-storage-proof
       store
       code-state
       (commit-state-block store code-state 40 400)
       code-address
       slot
       0
       (keccak-256-hash code)))))

(deftest eth-rpc-get-proof-code-update
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (id address slot block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (list (hash32-to-hex slot))
                               (hash32-to-hex (block-hash block)))))))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x0000000000000000000000000000000000000109"))
           (slot
             (hash32-from-hex
              "0x000000000000000000000000000000000000000000000000000000000000000b"))
           (first-code #(96 1 96 0))
           (final-code #(96 2 96 3 1))
           (state (make-state-db)))
      (state-db-set-account state address (make-state-account :balance 1))
      (state-db-set-code state address first-code)
      (state-db-set-code state address final-code)
      (let* ((block (commit-state-block store state 53 530))
             (response
               (engine-rpc-handle-request
                (proof-request 124 address slot block)
                store
                (make-chain-config)))
             (proof (field response "result"))
             (storage-proof (first (field proof "storageProof")))
             (expected-proof
               (state-db-get-proof state address (list slot)))
             (expected-storage-proof
               (first (state-proof-result-storage-proofs expected-proof)))
             (decoded-proof
               (state-proof-result-from-rpc-object proof)))
        (is (string= "0xa71076e81cddb7521d7345f5aa21a0b5781991a366f66861e5faca0a336798ad"
                     (state-db-root-hex state)))
        (is (string= (address-to-hex address)
                     (field proof "address")))
        (is (string= (quantity-to-hex 1)
                     (field proof "balance")))
        (is (string= (quantity-to-hex 0)
                     (field proof "nonce")))
        (is (string= (hash32-to-hex (keccak-256-hash final-code))
                     (field proof "codeHash")))
        (is (string= (hash32-to-hex +empty-trie-hash+)
                     (field proof "storageHash")))
        (is (= 1 (length (field proof "storageProof"))))
        (is (string= (hash32-to-hex slot)
                     (field storage-proof "key")))
        (is (string= (quantity-to-hex 0)
                     (field storage-proof "value")))
        (is (null (field storage-proof "proof")))
        (is (equal (proof-node-hex-list
                    (state-proof-result-account-proof expected-proof))
                   (field proof "accountProof")))
        (is (equal (proof-node-hex-list
                    (state-storage-proof-proof expected-storage-proof))
                   (field storage-proof "proof")))
        (is (state-db-verify-proof (state-db-root state)
                                   decoded-proof))))))

(deftest eth-rpc-get-proof-code-update-preserves-storage
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (id address slots block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (mapcar #'hash32-to-hex slots)
                               (hash32-to-hex (block-hash block)))))))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x000000000000000000000000000000000000010b"))
           (present-slot
             (hash32-from-hex
              "0x000000000000000000000000000000000000000000000000000000000000002c"))
           (missing-slot
             (hash32-from-hex
              "0x000000000000000000000000000000000000000000000000000000000000002d"))
           (first-code #(96 1 96 0))
           (final-code #(96 2 96 3 1))
           (state (make-state-db)))
      (state-db-set-account
       state address (make-state-account :nonce 1 :balance 1000))
      (state-db-set-storage state address present-slot #x2c)
      (state-db-set-code state address first-code)
      (state-db-set-code state address final-code)
      (let* ((block (commit-state-block store state 54 540))
             (slots (list present-slot missing-slot))
             (response
               (engine-rpc-handle-request
                (proof-request 126 address slots block)
                store
                (make-chain-config)))
             (proof (field response "result"))
             (storage-proofs (field proof "storageProof"))
             (present-storage-proof (first storage-proofs))
             (missing-storage-proof (second storage-proofs))
             (expected-proof (state-db-get-proof state address slots))
             (decoded-proof
               (state-proof-result-from-rpc-object proof)))
        (is (string= "0xc7b8d640084dfe51710f52b73da6975f617c6c4503ec763c1e2a2eeef11b3f01"
                     (state-db-root-hex state)))
        (is (equal (state-proof-result-rpc-object expected-proof)
                   proof))
        (is (string= (address-to-hex address)
                     (field proof "address")))
        (is (string= (quantity-to-hex 1000)
                     (field proof "balance")))
        (is (string= (quantity-to-hex 1)
                     (field proof "nonce")))
        (is (string= (hash32-to-hex (keccak-256-hash final-code))
                     (field proof "codeHash")))
        (is (string= "0x39b3b39f4dd43bd60944a54f2478267341aa89516ee9e8b5c9b6272b02cb0f75"
                     (field proof "storageHash")))
        (is (= 2 (length storage-proofs)))
        (is (string= (hash32-to-hex present-slot)
                     (field present-storage-proof "key")))
        (is (string= (quantity-to-hex #x2c)
                     (field present-storage-proof "value")))
        (is (= 1 (length (field present-storage-proof "proof"))))
        (is (string= (hash32-to-hex missing-slot)
                     (field missing-storage-proof "key")))
        (is (string= (quantity-to-hex 0)
                     (field missing-storage-proof "value")))
        (is (= 1 (length (field missing-storage-proof "proof"))))
        (is (state-db-verify-proof (state-db-root state)
                                   decoded-proof))))))

(deftest eth-rpc-get-proof-code-update-nontrivial-state-tries
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof))
           (add-account (state address nonce balance)
             (state-db-set-account
              state
              (address-from-hex address)
              (make-state-account :nonce nonce :balance balance)))
           (set-updated-code (state address)
             (let ((target (address-from-hex address)))
               (state-db-set-code state target #(96 1 96 0))
               (state-db-set-code state target #(96 2 96 3 1))))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (id address slot block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (list (hash32-to-hex slot))
                               (hash32-to-hex (block-hash block))))))
           (assert-code-update-proof
               (store state block target slot expected-root expected-nodes)
             (let* ((response
                      (engine-rpc-handle-request
                       (proof-request 125 target slot block)
                       store
                       (make-chain-config)))
                    (proof (field response "result"))
                    (storage-proof (first (field proof "storageProof")))
                    (expected-proof
                      (state-db-get-proof state target (list slot)))
                    (expected-storage-proof
                      (first (state-proof-result-storage-proofs
                              expected-proof)))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (is (string= expected-root
                            (state-db-root-hex state)))
               (is (string= (address-to-hex target)
                            (field proof "address")))
               (is (string= (quantity-to-hex 1000)
                            (field proof "balance")))
               (is (string= (quantity-to-hex 1)
                            (field proof "nonce")))
               (is (string= (hash32-to-hex
                             (keccak-256-hash #(96 2 96 3 1)))
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (is (= expected-nodes
                      (length (field proof "accountProof"))))
               (is (= 1 (length (field proof "storageProof"))))
               (is (string= (hash32-to-hex slot)
                            (field storage-proof "key")))
               (is (string= (quantity-to-hex 0)
                            (field storage-proof "value")))
               (is (null (field storage-proof "proof")))
               (is (equal (proof-node-hex-list
                           (state-proof-result-account-proof expected-proof))
                          (field proof "accountProof")))
               (is (equal (proof-node-hex-list
                           (state-storage-proof-proof expected-storage-proof))
                          (field storage-proof "proof")))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (branch-target
             (address-from-hex "0x0000000000000000000000000000000000000201"))
           (extension-target
             (address-from-hex "0x0000000000000000000000000000000000000220"))
           (slot
             (hash32-from-hex
              "0x000000000000000000000000000000000000000000000000000000000000000b"))
           (branch-state (make-state-db))
           (extension-state (make-state-db))
           (branch-extension-state (make-state-db)))
      (add-account branch-state
                   "0x0000000000000000000000000000000000000201"
                   1 1000)
      (set-updated-code branch-state
                        "0x0000000000000000000000000000000000000201")
      (add-account branch-state
                   "0x0000000000000000000000000000000000000211"
                   2 200)
      (add-account extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 1000)
      (set-updated-code extension-state
                        "0x0000000000000000000000000000000000000220")
      (add-account extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 1000)
      (set-updated-code branch-extension-state
                        "0x0000000000000000000000000000000000000220")
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000203"
                   3 300)
      (assert-code-update-proof
       store
       branch-state
       (commit-state-block store branch-state 54 540)
       branch-target
       slot
       "0x6ab69fa5095659c9578b4dc266ea51d9e5288674f3a60ba0058189667c74786e"
       2)
      (assert-code-update-proof
       store
       extension-state
       (commit-state-block store extension-state 55 550)
       extension-target
       slot
       "0x258d8cdbcaf278008d357941227e1b102cad65026083bde2621e843cb7c00c85"
       3)
      (assert-code-update-proof
       store
       branch-extension-state
       (commit-state-block store branch-extension-state 56 560)
       extension-target
       slot
       "0xa53fa7b005c9d7d484bc1130c751b0e743bb907657e3d646aa31cc456680f193"
       4))))

(deftest eth-rpc-get-proof-code-deletion
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof))
           (add-account (state address nonce balance)
             (state-db-set-account
              state
              (address-from-hex address)
              (make-state-account :nonce nonce :balance balance)))
           (set-deleted-code (state address)
             (let ((target (address-from-hex address)))
               (state-db-set-code state target #(96 1 96 0))
               (state-db-set-code state target #())))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (id address slot block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (list (hash32-to-hex slot))
                               (hash32-to-hex (block-hash block))))))
           (assert-code-deletion-proof
               (store state block address slot expected-balance
                &optional expected-root expected-nodes (expected-nonce 0))
             (let* ((response
                      (engine-rpc-handle-request
                       (proof-request 119 address slot block)
                       store
                       (make-chain-config)))
                    (proof (field response "result"))
                    (storage-proof (first (field proof "storageProof")))
                    (expected-proof
                      (state-db-get-proof state address (list slot)))
                    (expected-storage-proof
                      (first (state-proof-result-storage-proofs
                              expected-proof)))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (when expected-root
                 (is (string= expected-root
                              (state-db-root-hex state))))
               (is (string= (address-to-hex address)
                            (field proof "address")))
               (is (string= (quantity-to-hex expected-balance)
                            (field proof "balance")))
               (is (string= (quantity-to-hex expected-nonce)
                            (field proof "nonce")))
               (is (string= (hash32-to-hex +empty-code-hash+)
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (when expected-nodes
                 (is (= expected-nodes
                        (length (field proof "accountProof")))))
               (is (= 1 (length (field proof "storageProof"))))
               (is (string= (hash32-to-hex slot)
                            (field storage-proof "key")))
               (is (string= (quantity-to-hex 0)
                            (field storage-proof "value")))
               (is (null (field storage-proof "proof")))
               (is (equal (proof-node-hex-list
                           (state-proof-result-account-proof expected-proof))
                          (field proof "accountProof")))
               (is (equal (proof-node-hex-list
                           (state-storage-proof-proof expected-storage-proof))
                          (field storage-proof "proof")))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (created-address
             (address-from-hex "0x0000000000000000000000000000000000000105"))
           (funded-address
             (address-from-hex "0x0000000000000000000000000000000000000106"))
           (branch-target
             (address-from-hex "0x0000000000000000000000000000000000000201"))
           (extension-target
             (address-from-hex "0x0000000000000000000000000000000000000220"))
           (slot
             (hash32-from-hex
              "0x000000000000000000000000000000000000000000000000000000000000000b"))
           (code #(96 1 96 0))
           (created-state (make-state-db))
           (funded-state (make-state-db))
           (branch-state (make-state-db))
           (extension-state (make-state-db))
           (branch-extension-state (make-state-db)))
      (state-db-set-code created-state created-address code)
      (state-db-set-code created-state created-address #())
      (state-db-set-account funded-state funded-address
                            (make-state-account :balance 1))
      (state-db-set-code funded-state funded-address code)
      (state-db-set-code funded-state funded-address #())
      (add-account branch-state
                   "0x0000000000000000000000000000000000000201"
                   1 1000)
      (set-deleted-code branch-state
                        "0x0000000000000000000000000000000000000201")
      (add-account branch-state
                   "0x0000000000000000000000000000000000000211"
                   2 200)
      (add-account extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 1000)
      (set-deleted-code extension-state
                        "0x0000000000000000000000000000000000000220")
      (add-account extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 1000)
      (set-deleted-code branch-extension-state
                        "0x0000000000000000000000000000000000000220")
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000203"
                   3 300)
      (assert-code-deletion-proof
       store
       created-state
       (commit-state-block store created-state 41 410)
       created-address
       slot
       0)
      (assert-code-deletion-proof
       store
       funded-state
       (commit-state-block store funded-state 42 420)
       funded-address
       slot
       1)
      (assert-code-deletion-proof
       store
       branch-state
       (commit-state-block store branch-state 57 570)
       branch-target
       slot
       1000
       "0x582439b37db3e207275bb7dd5391cb2119286e63ac0c7d52f719adbae41e00bb"
       2
       1)
      (assert-code-deletion-proof
       store
       extension-state
       (commit-state-block store extension-state 58 580)
       extension-target
       slot
       1000
       "0x915d94dd285fc0df8a08abcc98035f585db26f42ff322fdbf202b94de5ad2e8e"
       3
       1)
      (assert-code-deletion-proof
       store
       branch-extension-state
       (commit-state-block store branch-extension-state 59 590)
       extension-target
       slot
       1000
       "0x51eb577604090486f0601db492fe0690432903734494bccedfc7d321659b4e7e"
       4
       1))))

(deftest eth-rpc-get-proof-storage-overwrite-final-value
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (id address slots block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (mapcar #'hash32-to-hex slots)
                               (hash32-to-hex (block-hash block))))))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof)))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x000000000000000000000000000000000000030b"))
           (slot
             (hash32-from-hex
              "0x000000000000000000000000000000000000000000000000000000000000001c"))
           (missing-slot
             (hash32-from-hex
              "0x000000000000000000000000000000000000000000000000000000000000001d"))
           (state (make-state-db)))
      (state-db-set-account state address (make-state-account :nonce 1
                                                              :balance 5))
      (state-db-set-storage state address slot 28)
      (state-db-set-storage state address slot 43)
      (let* ((block (commit-state-block store state 46 460))
             (response
               (engine-rpc-handle-request
                (proof-request 121 address (list slot missing-slot) block)
                store
                (make-chain-config)))
             (proof (field response "result"))
             (storage-proofs (field proof "storageProof"))
             (present-storage-proof (first storage-proofs))
             (missing-storage-proof (second storage-proofs))
             (expected-proof
               (state-db-get-proof state address (list slot missing-slot)))
             (decoded-proof
               (state-proof-result-from-rpc-object proof)))
        (is (equal (state-proof-result-rpc-object expected-proof)
                   proof))
        (is (string= (address-to-hex address)
                     (field proof "address")))
        (is (string= (quantity-to-hex 5)
                     (field proof "balance")))
        (is (string= (quantity-to-hex 1)
                     (field proof "nonce")))
        (is (string= (hash32-to-hex +empty-code-hash+)
                     (field proof "codeHash")))
        (is (equal (proof-node-hex-list
                    (state-proof-result-account-proof expected-proof))
                   (field proof "accountProof")))
        (is (= 2 (length storage-proofs)))
        (is (string= (hash32-to-hex slot)
                     (field present-storage-proof "key")))
        (is (string= (quantity-to-hex 43)
                     (field present-storage-proof "value")))
        (is (= 1 (length (field present-storage-proof "proof"))))
        (is (string= (hash32-to-hex missing-slot)
                     (field missing-storage-proof "key")))
        (is (string= (quantity-to-hex 0)
                     (field missing-storage-proof "value")))
        (is (= 1 (length (field missing-storage-proof "proof"))))
        (is (state-db-verify-proof (state-db-root state)
                                   decoded-proof))))))

(deftest eth-rpc-get-proof-storage-overwrite-to-zero
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (id address slots block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (mapcar #'hash32-to-hex slots)
                               (hash32-to-hex (block-hash block))))))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof)))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x0000000000000000000000000000000000000104"))
           (slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000009"))
           (state (make-state-db)))
      (state-db-set-account state address (make-state-account :balance 1))
      (state-db-set-storage state address slot 99)
      (state-db-set-storage state address slot 100)
      (state-db-set-storage state address slot 0)
      (let* ((block (commit-state-block store state 47 470))
             (response
               (engine-rpc-handle-request
                (proof-request 122 address (list slot) block)
                store
                (make-chain-config)))
             (proof (field response "result"))
             (storage-proofs (field proof "storageProof"))
             (storage-proof (first storage-proofs))
             (expected-proof
               (state-db-get-proof state address (list slot)))
             (expected-storage-proof
               (first (state-proof-result-storage-proofs expected-proof)))
             (decoded-proof
               (state-proof-result-from-rpc-object proof)))
        (is (equal (state-proof-result-rpc-object expected-proof)
                   proof))
        (is (string= (address-to-hex address)
                     (field proof "address")))
        (is (string= (quantity-to-hex 1)
                     (field proof "balance")))
        (is (string= (quantity-to-hex 0)
                     (field proof "nonce")))
        (is (string= (hash32-to-hex +empty-code-hash+)
                     (field proof "codeHash")))
        (is (string= (hash32-to-hex +empty-trie-hash+)
                     (field proof "storageHash")))
        (is (equal (proof-node-hex-list
                    (state-proof-result-account-proof expected-proof))
                   (field proof "accountProof")))
        (is (= 1 (length storage-proofs)))
        (is (string= (hash32-to-hex slot)
                     (field storage-proof "key")))
        (is (string= (quantity-to-hex 0)
                     (field storage-proof "value")))
        (is (null (field storage-proof "proof")))
        (is (equal (proof-node-hex-list
                    (state-storage-proof-proof expected-storage-proof))
                   (field storage-proof "proof")))
        (is (state-db-verify-proof (state-db-root state)
                                   decoded-proof))))))

(deftest eth-rpc-get-proof-storage-trie-update-boundaries
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (id address slots block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (mapcar #'hash32-to-hex slots)
                               (hash32-to-hex (block-hash block))))))
           (storage-slot (value)
             (hash32-from-hex
              (format nil
                      "0x~64,'0x"
                      value)))
           (make-update-state (address slots values update-slot update-value)
             (let ((state (make-state-db)))
               (state-db-set-account state address
                                     (make-state-account :balance 1))
               (loop for slot in slots
                     for value in values
                     do (state-db-set-storage state address slot value))
               (state-db-set-storage state address update-slot update-value)
               state))
           (assert-proof-roundtrip
               (store state block address slots expected-values
                expected-node-counts)
             (let* ((response
                      (engine-rpc-handle-request
                       (proof-request 121 address slots block)
                       store
                       (make-chain-config)))
                    (proof (field response "result"))
                    (storage-proofs (field proof "storageProof"))
                    (expected-proof
                      (state-db-get-proof state address slots))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (is (equal (state-proof-result-rpc-object expected-proof)
                          proof))
               (is (= (length expected-values)
                      (length storage-proofs)))
               (loop for storage-proof in storage-proofs
                     for slot in slots
                     for expected-value in expected-values
                     for expected-node-count in expected-node-counts
                     do (progn
                          (is (string= (hash32-to-hex slot)
                                       (field storage-proof "key")))
                          (is (string= (quantity-to-hex expected-value)
                                       (field storage-proof "value")))
                          (is (= expected-node-count
                                 (length (field storage-proof "proof"))))))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x0000000000000000000000000000000000000401"))
           (slot-1 (storage-slot 1))
           (slot-2 (storage-slot 2))
           (slot-3 (storage-slot 3))
           (slot-e (storage-slot 14))
           (slot-f (storage-slot 15))
           (branch-state
             (make-update-state
              address
              (list slot-1 slot-2)
              '(1 2)
              slot-1
              17))
           (extension-state
             (make-update-state
              address
              (list slot-1 slot-e)
              '(1 14)
              slot-1
              17)))
      (assert-proof-roundtrip
       store
       branch-state
       (commit-state-block store branch-state 48 480)
       address
       (list slot-1 slot-2 slot-3)
       '(17 2 0)
       '(2 2 1))
      (assert-proof-roundtrip
       store
       extension-state
       (commit-state-block store extension-state 49 490)
       address
       (list slot-1 slot-e slot-f)
       '(17 14 0)
       '(3 3 1)))))

(deftest eth-rpc-get-proof-storage-delete-boundaries
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (id address slots block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (mapcar #'hash32-to-hex slots)
                               (hash32-to-hex (block-hash block))))))
           (storage-slot (value)
             (hash32-from-hex
              (format nil
                      "0x~64,'0x"
                     value)))
           (make-delete-preservation-state (address slots values delete-slot)
             (let ((state (make-state-db)))
               (state-db-set-account state address
                                     (make-state-account :balance 1))
               (loop for slot in slots
                     for value in values
                     do (state-db-set-storage state address slot value))
               (state-db-set-storage state address delete-slot 0)
               state))
           (assert-proof-roundtrip
               (store state block address slots expected-values
                expected-node-counts)
             (let* ((response
                      (engine-rpc-handle-request
                       (proof-request 120 address slots block)
                       store
                       (make-chain-config)))
                    (proof (field response "result"))
                    (storage-proofs (field proof "storageProof"))
                    (expected-proof
                      (state-db-get-proof state address slots))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (is (equal (state-proof-result-rpc-object expected-proof)
                          proof))
               (is (= (length expected-values)
                      (length storage-proofs)))
               (loop for storage-proof in storage-proofs
                     for slot in slots
                     for expected-value in expected-values
                     for expected-node-count in expected-node-counts
                     do (progn
                          (is (string= (hash32-to-hex slot)
                                       (field storage-proof "key")))
                          (is (string= (quantity-to-hex expected-value)
                                       (field storage-proof "value")))
                          (is (= expected-node-count
                                 (length (field storage-proof "proof"))))))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x0000000000000000000000000000000000000401"))
           (slot-1 (storage-slot 1))
           (slot-2 (storage-slot 2))
           (slot-3 (storage-slot 3))
           (slot-e (storage-slot 14))
           (slot-f (storage-slot 15))
           (branch-state
             (make-delete-preservation-state
              address
              (list slot-1 slot-2 slot-3)
              '(1 2 3)
              slot-3))
           (extension-state
             (make-delete-preservation-state
              address
              (list slot-1 slot-e slot-f)
              '(1 14 15)
              slot-f))
           (collapse-state
             (make-delete-preservation-state
              address
              (list slot-1 slot-2)
              '(1 2)
              slot-2)))
      (assert-proof-roundtrip
       store
       branch-state
       (commit-state-block store branch-state 43 430)
       address
       (list slot-1 slot-2 slot-3)
       '(1 2 0)
       '(2 2 1))
      (assert-proof-roundtrip
       store
       extension-state
       (commit-state-block store extension-state 44 440)
       address
       (list slot-1 slot-e slot-f)
       '(1 14 0)
       '(3 3 1))
      (assert-proof-roundtrip
       store
       collapse-state
       (commit-state-block store collapse-state 45 450)
       address
       (list slot-1 slot-2)
       '(1 0)
       '(1 1)))))

(deftest eth-rpc-call-executes-retained-state-without-commit
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
           (slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000001"))
           ;; SSTORE slot 1 := 42; MSTORE 0 := 7; RETURN mem[0:32].
           (code #(96 42 96 1 85 96 7 96 0 82 96 32 96 0 243))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 30
                       :timestamp 300
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state))))
           (expected (let ((bytes (make-byte-vector 32)))
                       (setf (aref bytes 31) 7)
                       (bytes-to-hex bytes))))
      (state-db-set-code state contract code)
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 104)
                      (cons "method" "eth_call")
                      (cons "params"
                            (list
                             (list (cons "to" (address-to-hex contract))
                                   (cons "gas" (quantity-to-hex 100000))
                                   (cons "data" "0x"))
                             "latest")))
                store
                config))
             (result (field response "result")))
        (is (string= expected result))
        (is (= 0
               (chain-store-account-storage
                store (block-hash block) contract slot)))))))

(deftest eth-rpc-estimate-gas-binary-searches-retained-state-call
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (hex-quantity-integer (value)
             (parse-integer (subseq value 2) :radix 16)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x00000000000000000000000000000000000000aa"))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
           (reverter
             (address-from-hex "0x00000000000000000000000000000000000000dd"))
           ;; SSTORE slot 1 := 42; MSTORE 0 := 7; RETURN mem[0:32].
           (code #(96 42 96 1 85 96 7 96 0 82 96 32 96 0 243))
           (revert-code #(96 0 96 0 253))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 31
                       :timestamp 310
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state)))))
      (state-db-set-code state contract code)
      (state-db-set-code state reverter revert-code)
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((transfer-response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 105)
                      (cons "method" "eth_estimateGas")
                      (cons "params"
                            (list
                             (list (cons "to" (address-to-hex recipient)))
                             "latest")))
                store
                config))
             (contract-response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 106)
                      (cons "method" "eth_estimateGas")
                      (cons "params"
                            (list
                             (list (cons "to" (address-to-hex contract))
                                   (cons "gas" (quantity-to-hex 100000)))
                             "latest")))
                store
                config))
             (revert-response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 107)
                      (cons "method" "eth_estimateGas")
                      (cons "params"
                            (list
                             (list (cons "to" (address-to-hex reverter))
                                   (cons "gas" (quantity-to-hex 100000)))
                             "latest")))
                store
                config))
             (contract-estimate
               (hex-quantity-integer (field contract-response "result"))))
        (is (string= (quantity-to-hex 21000)
                     (field transfer-response "result")))
        (is (> contract-estimate 21000))
        (is (<= contract-estimate 100000))
        (is (= -32602
               (field (field revert-response "error") "code")))))))

(deftest eth-rpc-create-access-list-reports-touched-state
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (entry-for (access-list address)
             (find (address-to-hex address)
                   access-list
                   :test #'string=
                   :key (lambda (entry) (field entry "address")))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
           (target
             (address-from-hex "0x00000000000000000000000000000000000000bb"))
           (slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000001"))
           ;; SLOAD slot 1; BALANCE target; STOP.
           (code (concat-bytes #(#x60 #x01 #x54 #x73)
                               (address-bytes target)
                               #(#x31 #x00)))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 32
                       :timestamp 320
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state)))))
      (state-db-set-code state contract code)
      (state-db-set-storage state contract slot 7)
      (state-db-set-account state target (make-state-account :balance 11))
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 108)
                      (cons "method" "eth_createAccessList")
                      (cons "params"
                            (list
                             (list (cons "to" (address-to-hex contract))
                                   (cons "gas" (quantity-to-hex 100000)))
                             "latest")))
                store
                config))
             (result (field response "result"))
             (access-list (field result "accessList"))
             (contract-entry (entry-for access-list contract))
             (target-entry (entry-for access-list target)))
        (is (stringp (field result "gasUsed")))
        (is (= 2 (length access-list)))
        (is (string= (hash32-to-hex slot)
                     (first (field contract-entry "storageKeys"))))
        (is (null (field target-entry "storageKeys")))))))

(deftest eth-rpc-simulation-methods-require-retained-state
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (id method)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" method)
                   (cons "params"
                         (list
                          (list
                           (cons "to"
                                 "0x00000000000000000000000000000000000000cc"))
                          "latest"))))
           (assert-state-error (response method)
             (let ((error (field response "error")))
               (is (= -32602 (field error "code")))
               (is (string= (format nil "~A state is not available" method)
                            (field error "message"))))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (block
             (make-block
              :header (make-block-header
                       :number 33
                       :timestamp 330
                       :gas-limit 100000
                       :base-fee-per-gas 0))))
      (engine-payload-store-put-block store block)
      (assert-state-error
       (engine-rpc-handle-request (request 109 "eth_call") store config)
       "eth_call")
      (assert-state-error
       (engine-rpc-handle-request (request 110 "eth_estimateGas") store config)
       "eth_estimateGas")
      (assert-state-error
       (engine-rpc-handle-request
        (request 111 "eth_createAccessList") store config)
       "eth_createAccessList"))))

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

(deftest eth-rpc-send-raw-transaction-applies-basic-admission-preflight
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
               config))))
    (let* ((recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (private-key 1)
           (low-gas-store (make-engine-payload-memory-store))
           (typed-store (make-engine-payload-memory-store))
           (nonce-store (make-engine-payload-memory-store))
           (balance-store (make-engine-payload-memory-store))
           (sender-code-store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (low-gas-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0
               :data #(1))
              private-key
              1))
           (unsupported-access-transaction
             (make-access-list-transaction
              :chain-id 1
              :nonce 3
              :gas-price 1
              :gas-limit 25000
              :to (address-from-hex
                   "0xb94f5374fce5edbc8e2a8697c15331677e6ebf0b")
              :value 10
              :data (hex-to-bytes "0x5544")
              :y-parity 1
              :r #xc9519f4f2b30335884581971573fadf60c6204f59a911df35ee8a540456b2660
              :s #x32f1e8e2c5dd761f9e4f88f41c8310aeaba26a8bfcdacfedfa12ec3862d37521))
           (sender-code-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              private-key
              1))
           (nonce-too-low-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              private-key
              1))
           (insufficient-balance-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 10
               :gas-limit 21000
               :to recipient
               :value 1)
              private-key
              1))
           (sender (transaction-sender sender-code-transaction
                                       :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (chain-store-put-block nonce-store head-block :state-available-p t)
      (chain-store-put-account-nonce
       nonce-store (block-hash head-block) sender 2)
      (chain-store-put-account-balance
       nonce-store (block-hash head-block) sender 1000000)
      (chain-store-put-block balance-store head-block :state-available-p t)
      (chain-store-put-account-balance
       balance-store (block-hash head-block) sender 100)
      (engine-payload-store-put-block sender-code-store head-block)
      (engine-payload-store-put-account-code
       sender-code-store (block-hash head-block) sender #(1 2 3))
      (let* ((low-gas-response
               (send-raw low-gas-transaction 112 low-gas-store config))
             (typed-response
               (send-raw unsupported-access-transaction 113 typed-store config))
             (nonce-too-low-response
               (send-raw nonce-too-low-transaction 114 nonce-store config))
             (insufficient-balance-response
               (send-raw insufficient-balance-transaction
                         115
                         balance-store
                         config))
             (sender-code-response
               (send-raw sender-code-transaction
                         116
                         sender-code-store
                         config))
             (low-gas-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":117,\"method\":\"txpool_status\",\"params\":[]}"
                 low-gas-store
                 config)))
             (typed-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":118,\"method\":\"txpool_status\",\"params\":[]}"
                 typed-store
                 config)))
             (nonce-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":119,\"method\":\"txpool_status\",\"params\":[]}"
                 nonce-store
                 config)))
             (balance-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":120,\"method\":\"txpool_status\",\"params\":[]}"
                 balance-store
                 config)))
             (sender-code-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":121,\"method\":\"txpool_status\",\"params\":[]}"
                 sender-code-store
                 config))))
        (is (= -32602 (field (field low-gas-response "error") "code")))
        (is (string= "eth_sendRawTransaction gas limit below intrinsic gas"
                     (field (field low-gas-response "error") "message")))
        (is (= -32602 (field (field typed-response "error") "code")))
        (is (string= "Access-list transaction before Berlin"
                     (field (field typed-response "error") "message")))
        (is (= -32602
               (field (field nonce-too-low-response "error") "code")))
        (is (string= "eth_sendRawTransaction nonce too low"
                     (field (field nonce-too-low-response "error")
                            "message")))
        (is (= -32602
               (field (field insufficient-balance-response "error")
                      "code")))
        (is (string=
             "eth_sendRawTransaction insufficient sender balance"
             (field (field insufficient-balance-response "error")
                    "message")))
        (is (= -32602 (field (field sender-code-response "error") "code")))
        (is (string=
             "eth_sendRawTransaction sender has non-delegation code"
             (field (field sender-code-response "error") "message")))
        (dolist (status-response
                 (list low-gas-status
                       typed-status
                       nonce-status
                       balance-status
                       sender-code-status))
          (is (string= (quantity-to-hex 0)
                       (field (field status-response "result")
                              "pending"))))))))

(deftest eth-rpc-send-raw-transaction-enforces-pending-balance-expenditure
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (first-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (second-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (first-hash (hash32-to-hex (transaction-hash first-transaction)))
           (second-hash (hash32-to-hex (transaction-hash second-transaction)))
           (sender (transaction-sender first-transaction :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 30000)
      (let* ((first-response (send-raw first-transaction 122 store config))
             (second-response (send-raw second-transaction 123 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":124,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":125,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (second-lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":126,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" second-hash "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (pending
               (field (field content "pending") (address-to-hex sender)))
             (second-error (field second-response "error")))
        (is (string= first-hash (field first-response "result")))
        (is (= -32602 (field second-error "code")))
        (is (string= "eth_sendRawTransaction insufficient sender balance"
                     (field second-error "message")))
        (is (string= (quantity-to-hex 1) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))
        (is (string= first-hash (field (field pending "0") "hash")))
        (is (null (field pending "1")))
        (is (null (field content "queued")))
        (is (null (field second-lookup-response "result")))))))

(deftest eth-rpc-send-raw-transaction-queues-retained-state-nonce-gaps
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 3
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":122,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (send-response (send-raw transaction 123 store config))
             (pending-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":124,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                store
                config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":125,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":126,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (content-from-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":127,"
                 "\"method\":\"txpool_contentFrom\",\"params\":[\""
                 (address-to-hex sender)
                 "\"]}")
                store
                config))
             (transaction-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":128,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" transaction-hash "\"]}")
                store
                config))
             (raw-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":129,"
                 "\"method\":\"eth_getRawTransactionByHash\","
                 "\"params\":[\"" transaction-hash "\"]}")
                store
                config))
             (transaction-count-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":131,"
                 "\"method\":\"eth_getTransactionCount\","
                 "\"params\":[\""
                 (address-to-hex sender)
                 "\",\"pending\"]}")
                store
                config))
             (filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":132,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (queued
               (field (field content "queued") (address-to-hex sender)))
             (queued-from
               (field (field (field content-from-response "result") "queued")
                      "3"))
             (pooled-transaction
               (field transaction-response "result")))
        (is (string= transaction-hash (field send-response "result")))
        (is (= 0 (length (field pending-response "result"))))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (string= (quantity-to-hex 1) (field status "queued")))
        (is (string= transaction-hash (field (field queued "3") "hash")))
        (is (string= transaction-hash (field queued-from "hash")))
        (is (string= transaction-hash (field pooled-transaction "hash")))
        (is (null (field pooled-transaction "blockHash")))
        (is (string= (bytes-to-hex (transaction-encoding transaction))
                     (field raw-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field transaction-count-response "result")))
        (is (= 0 (length (field filter-changes "result"))))))))

(deftest eth-rpc-send-raw-transaction-keeps-contiguous-nonces-pending
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (nonce-zero
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (nonce-one
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (nonce-zero-hash (hash32-to-hex (transaction-hash nonce-zero)))
           (nonce-one-hash (hash32-to-hex (transaction-hash nonce-one)))
           (sender (transaction-sender nonce-zero :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":174,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (nonce-zero-response (send-raw nonce-zero 175 store config))
             (nonce-one-response (send-raw nonce-one 176 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":177,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":178,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (transaction-count-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":179,"
                 "\"method\":\"eth_getTransactionCount\","
                 "\"params\":[\""
                 (address-to-hex sender)
                 "\",\"pending\"]}")
                store
                config))
             (filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":180,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (pending
               (field (field content "pending") (address-to-hex sender)))
             (filter-hashes (field filter-changes "result")))
        (is (string= nonce-zero-hash (field nonce-zero-response "result")))
        (is (string= nonce-one-hash (field nonce-one-response "result")))
        (is (string= (quantity-to-hex 2) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))
        (is (string= nonce-zero-hash
                     (field (field pending "0") "hash")))
        (is (string= nonce-one-hash
                     (field (field pending "1") "hash")))
        (is (null (field content "queued")))
        (is (string= (quantity-to-hex 2)
                     (field transaction-count-response "result")))
        (is (= 2 (length filter-hashes)))
        (is (string= nonce-zero-hash (first filter-hashes)))
        (is (string= nonce-one-hash (second filter-hashes)))))))

(deftest eth-rpc-send-raw-transaction-promotes-contiguous-queued-nonces
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (nonce-zero
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (nonce-one
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (nonce-zero-hash (hash32-to-hex (transaction-hash nonce-zero)))
           (nonce-one-hash (hash32-to-hex (transaction-hash nonce-one)))
           (sender (transaction-sender nonce-zero :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":142,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (queued-response (send-raw nonce-one 143 store config))
             (queued-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":144,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (pending-response (send-raw nonce-zero 145 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":146,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (pending-transactions-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":147,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":148,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (transaction-count-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":149,"
                 "\"method\":\"eth_getTransactionCount\","
                 "\"params\":[\""
                 (address-to-hex sender)
                 "\",\"pending\"]}")
                store
                config))
             (promoted-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":150,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (status (field status-response "result"))
             (pending-transactions
               (field pending-transactions-response "result"))
             (content (field content-response "result"))
             (pending-sender
               (field (field content "pending") (address-to-hex sender)))
             (promoted-hashes (field promoted-filter-changes "result")))
        (is (string= nonce-one-hash (field queued-response "result")))
        (is (= 0 (length (field queued-filter-changes "result"))))
        (is (string= nonce-zero-hash (field pending-response "result")))
        (is (string= (quantity-to-hex 2) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))
        (is (= 2 (length pending-transactions)))
        (is (string= nonce-zero-hash
                     (field (field pending-sender "0") "hash")))
        (is (string= nonce-one-hash
                     (field (field pending-sender "1") "hash")))
        (is (null (field content "queued")))
        (is (string= (quantity-to-hex 2)
                     (field transaction-count-response "result")))
        (is (= 2 (length promoted-hashes)))
        (is (string= nonce-zero-hash (first promoted-hashes)))
        (is (string= nonce-one-hash (second promoted-hashes)))))))

(deftest eth-rpc-send-raw-transaction-queues-basefee-ineligible-transactions
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":133,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (send-response (send-raw transaction 134 store config))
             (pending-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":135,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                store
                config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":136,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":137,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (content-from-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":138,"
                 "\"method\":\"txpool_contentFrom\",\"params\":[\""
                 (address-to-hex sender)
                 "\"]}")
                store
                config))
             (transaction-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":139,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" transaction-hash "\"]}")
                store
                config))
             (transaction-count-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":140,"
                 "\"method\":\"eth_getTransactionCount\","
                 "\"params\":[\""
                 (address-to-hex sender)
                 "\",\"pending\"]}")
                store
                config))
             (filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":141,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (queued
               (field (field content "queued") (address-to-hex sender)))
             (queued-from
               (field (field (field content-from-response "result") "queued")
                      "0"))
             (pooled-transaction
               (field transaction-response "result")))
        (is (string= transaction-hash (field send-response "result")))
        (is (= 0 (length (field pending-response "result"))))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (string= (quantity-to-hex 1) (field status "queued")))
        (is (string= transaction-hash (field (field queued "0") "hash")))
        (is (string= transaction-hash (field queued-from "hash")))
        (is (string= transaction-hash (field pooled-transaction "hash")))
        (is (null (field pooled-transaction "blockHash")))
        (is (string= (quantity-to-hex 0)
                     (field transaction-count-response "result")))
        (is (= 0 (length (field filter-changes "result"))))))))

(deftest eth-rpc-send-raw-transaction-routes-blob-transactions-to-blob-subpool
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1337
                                      :london-block 0
                                      :cancun-time 0))
           (raw-transaction
             "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675")
           (transaction
             (transaction-from-encoding (hex-to-bytes raw-transaction)))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1337))
           (filter-response
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":167,\"method\":\"eth_newPendingTransactionFilter\"}"
              store
              config))
           (filter-id (field filter-response "result"))
           (send-response
             (request
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":166,"
               "\"method\":\"eth_sendRawTransaction\","
               "\"params\":[\"" raw-transaction "\"]}")
              store
              config))
           (pending-response
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":168,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
              store
              config))
           (status-response
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":169,\"method\":\"txpool_status\",\"params\":[]}"
              store
              config))
           (content-response
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":170,\"method\":\"txpool_content\",\"params\":[]}"
              store
              config))
           (content-from-response
             (request
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":171,"
               "\"method\":\"txpool_contentFrom\",\"params\":[\""
               (address-to-hex sender)
               "\"]}")
              store
              config))
           (lookup-response
             (request
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":172,"
               "\"method\":\"eth_getTransactionByHash\","
               "\"params\":[\"" transaction-hash "\"]}")
              store
              config))
           (filter-changes
             (request
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":173,"
               "\"method\":\"eth_getFilterChanges\","
               "\"params\":[\"" filter-id "\"]}")
              store
              config))
           (status (field status-response "result"))
           (content (field content-response "result"))
           (queued (field (field content "queued") (address-to-hex sender)))
           (queued-from
             (field (field (field content-from-response "result") "queued")
                    (write-to-string (transaction-nonce transaction)
                                     :base 10)))
           (pooled-transaction (field lookup-response "result")))
      (is (typep transaction 'blob-transaction))
      (is (string= transaction-hash (field send-response "result")))
      (is (= 0 (length (field pending-response "result"))))
      (is (string= (quantity-to-hex 0) (field status "pending")))
      (is (string= (quantity-to-hex 1) (field status "queued")))
      (is (null (field content "pending")))
      (is (string= transaction-hash
                   (field (field queued
                                 (write-to-string
                                  (transaction-nonce transaction)
                                  :base 10))
                          "hash")))
      (is (string= transaction-hash (field queued-from "hash")))
      (is (string= transaction-hash (field pooled-transaction "hash")))
      (is (null (field pooled-transaction "blockHash")))
      (is (= 0 (length (field filter-changes "result")))))))

(deftest eth-rpc-send-raw-transaction-replaces-basefee-conflict-with-pending
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (old-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (new-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 6
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (old-hash (hash32-to-hex (transaction-hash old-transaction)))
           (new-hash (hash32-to-hex (transaction-hash new-transaction)))
           (sender (transaction-sender new-transaction :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":151,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (old-response (send-raw old-transaction 152 store config))
             (new-response (send-raw new-transaction 153 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":154,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":155,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (old-lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":156,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" old-hash "\"]}")
                store
                config))
             (new-lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":157,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" new-hash "\"]}")
                store
                config))
             (filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":158,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (pending
               (field (field content "pending") (address-to-hex sender)))
             (filter-hashes (field filter-changes "result")))
        (is (string= old-hash (field old-response "result")))
        (is (string= new-hash (field new-response "result")))
        (is (string= (quantity-to-hex 1) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))
        (is (string= new-hash (field (field pending "0") "hash")))
        (is (null (field content "queued")))
        (is (null (field old-lookup-response "result")))
        (is (string= new-hash
                     (field (field new-lookup-response "result") "hash")))
        (is (= 1 (length filter-hashes)))
        (is (string= new-hash (first filter-hashes)))))))

(deftest txpool-basefee-transactions-promote-after-canonical-head-drop
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000
                                         :base-fee-per-gas 3))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":159,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (send-response (send-raw transaction 160 store config))
             (queued-status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":161,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (queued-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":162,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config)))
        (is (string= transaction-hash (field send-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field (field queued-status-response "result")
                            "pending")))
        (is (string= (quantity-to-hex 1)
                     (field (field queued-status-response "result")
                            "queued")))
        (is (= 0 (length (field queued-filter-changes "result"))))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((promoted-status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":163,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":164,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":165,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (status (field promoted-status-response "result"))
               (content (field content-response "result"))
               (pending
                 (field (field content "pending") (address-to-hex sender)))
               (filter-hashes (field filter-changes "result")))
          (is (string= (quantity-to-hex 1) (field status "pending")))
          (is (string= (quantity-to-hex 0) (field status "queued")))
          (is (string= transaction-hash
                       (field (field pending "0") "hash")))
          (is (null (field content "queued")))
          (is (= 1 (length filter-hashes)))
          (is (string= transaction-hash (first filter-hashes))))))))

(deftest txpool-basefee-promotion-drains-newly-contiguous-queued-tail
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (basefee-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (queued-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 5
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (basefee-hash
             (hash32-to-hex (transaction-hash basefee-transaction)))
           (queued-hash
             (hash32-to-hex (transaction-hash queued-transaction)))
           (sender (transaction-sender
                    basefee-transaction
                    :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000
                                         :base-fee-per-gas 3))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":301,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (basefee-response (send-raw basefee-transaction 302 store config))
             (queued-response (send-raw queued-transaction 303 store config))
             (initial-status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":304,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (initial-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":305,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config)))
        (is (string= basefee-hash (field basefee-response "result")))
        (is (string= queued-hash (field queued-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field (field initial-status-response "result")
                            "pending")))
        (is (string= (quantity-to-hex 2)
                     (field (field initial-status-response "result")
                            "queued")))
        (is (= 0 (length (field initial-filter-changes "result"))))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-put-account-nonce
         store (block-hash child-block) sender 0)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 1000000)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":306,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":307,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (transaction-count-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":308,"
                   "\"method\":\"eth_getTransactionCount\","
                   "\"params\":[\""
                   (address-to-hex sender)
                   "\",\"pending\"]}")
                  store
                  config))
               (filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":309,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (status (field status-response "result"))
               (content (field content-response "result"))
               (pending
                 (field (field content "pending") (address-to-hex sender)))
               (filter-hashes (field filter-changes "result")))
          (is (string= (quantity-to-hex 2) (field status "pending")))
          (is (string= (quantity-to-hex 0) (field status "queued")))
          (is (string= basefee-hash
                       (field (field pending "0") "hash")))
          (is (string= queued-hash
                       (field (field pending "1") "hash")))
          (is (null (field content "queued")))
          (is (string= (quantity-to-hex 2)
                       (field transaction-count-response "result")))
          (is (= 2 (length filter-hashes)))
          (is (string= basefee-hash (first filter-hashes)))
          (is (string= queued-hash (second filter-hashes))))))))

(deftest txpool-basefee-promotion-waits-for-contiguous-nonce
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (gap-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (gap-hash (hash32-to-hex (transaction-hash gap-transaction)))
           (closing-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (closing-hash
             (hash32-to-hex (transaction-hash closing-transaction)))
           (sender (transaction-sender gap-transaction :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000
                                         :base-fee-per-gas 3))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":189,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (gap-response (send-raw gap-transaction 190 store config))
             (queued-status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":191,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config)))
        (is (string= gap-hash (field gap-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field (field queued-status-response "result")
                            "pending")))
        (is (string= (quantity-to-hex 1)
                     (field (field queued-status-response "result")
                            "queued")))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((after-drop-status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":192,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (after-drop-content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":193,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (after-drop-filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":194,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (after-drop-status (field after-drop-status-response "result"))
               (after-drop-content (field after-drop-content-response "result"))
               (after-drop-queued
                 (field (field after-drop-content "queued")
                        (address-to-hex sender))))
          (is (string= (quantity-to-hex 0)
                       (field after-drop-status "pending")))
          (is (string= (quantity-to-hex 1)
                       (field after-drop-status "queued")))
          (is (null (field after-drop-content "pending")))
          (is (string= gap-hash
                       (field (field after-drop-queued "1") "hash")))
          (is (= 0 (length (field after-drop-filter-changes "result")))))
        (let* ((closing-response (send-raw closing-transaction 195 store config))
               (promoted-status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":196,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (promoted-content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":197,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":198,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (transaction-count-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":199,"
                   "\"method\":\"eth_getTransactionCount\","
                   "\"params\":[\""
                   (address-to-hex sender)
                   "\",\"pending\"]}")
                  store
                  config))
               (promoted-status (field promoted-status-response "result"))
               (promoted-content (field promoted-content-response "result"))
               (pending
                 (field (field promoted-content "pending")
                        (address-to-hex sender)))
               (filter-hashes (field filter-changes "result")))
          (is (string= closing-hash (field closing-response "result")))
          (is (string= (quantity-to-hex 2)
                       (field promoted-status "pending")))
          (is (string= (quantity-to-hex 0)
                       (field promoted-status "queued")))
          (is (string= closing-hash
                       (field (field pending "0") "hash")))
          (is (string= gap-hash
                       (field (field pending "1") "hash")))
          (is (null (field promoted-content "queued")))
          (is (string= (quantity-to-hex 2)
                       (field transaction-count-response "result")))
          (is (= 2 (length filter-hashes)))
          (is (string= closing-hash (first filter-hashes)))
          (is (string= gap-hash (second filter-hashes))))))))

(deftest engine-payload-store-promotes-basefee-transactions-by-sender-index
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (sender-a-nonce-zero
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            1
            1))
         (sender-a-nonce-one
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            1
            1))
         (sender-a-nonce-three
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 3
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            1
            1))
         (sender-b-nonce-zero
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            2
            1))
         (sender-a
           (transaction-sender sender-a-nonce-zero :expected-chain-id 1))
         (sender-b
           (transaction-sender sender-b-nonce-zero :expected-chain-id 1))
         (head-block
           (make-block
            :header (make-block-header :number 0
                                       :timestamp 0
                                       :gas-limit 30000000
                                       :base-fee-per-gas 3))))
    (chain-store-put-block store head-block :state-available-p t)
    (chain-store-put-account-nonce store (block-hash head-block) sender-a 0)
    (chain-store-put-account-nonce store (block-hash head-block) sender-b 0)
    (chain-store-put-account-balance
     store (block-hash head-block) sender-a 1000000)
    (chain-store-put-account-balance
     store (block-hash head-block) sender-b 1000000)
    (dolist (transaction
             (list sender-a-nonce-three
                   sender-b-nonce-zero
                   sender-a-nonce-one
                   sender-a-nonce-zero))
      (ethereum-lisp.core::engine-payload-store-put-basefee-transaction
       store
       transaction))
    (let ((promoted
            (ethereum-lisp.core::engine-payload-store-promote-basefee-transactions
             store))
          (sender-a-pending
            (ethereum-lisp.core::engine-payload-store-pending-sender-transactions
             store
             sender-a))
          (sender-b-pending
            (ethereum-lisp.core::engine-payload-store-pending-sender-transactions
             store
             sender-b)))
      (is (= 3 (length promoted)))
      (is (= 3
             (ethereum-lisp.core::engine-payload-store-pending-transaction-count
              store)))
      (is (= 1
             (ethereum-lisp.core::engine-payload-store-basefee-transaction-count
              store)))
      (is (eq sender-a-nonce-zero (first sender-a-pending)))
      (is (eq sender-a-nonce-one (second sender-a-pending)))
      (is (eq sender-b-nonce-zero (first sender-b-pending)))
      (is (null
           (ethereum-lisp.core::engine-payload-store-pending-transaction
            store
            (transaction-hash sender-a-nonce-three))))
      (is (eq sender-a-nonce-three
              (ethereum-lisp.core::engine-payload-store-pooled-transaction
               store
               (transaction-hash sender-a-nonce-three)))))))

(deftest txpool-queued-promotion-rechecks-pending-balance
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (gap-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (gap-hash (hash32-to-hex (transaction-hash gap-transaction)))
           (closing-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (closing-hash
             (hash32-to-hex (transaction-hash closing-transaction)))
           (sender (transaction-sender gap-transaction :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 21000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":200,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (gap-response (send-raw gap-transaction 201 store config))
             (closing-response (send-raw closing-transaction 202 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":203,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":204,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":205,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (transaction-count-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":206,"
                 "\"method\":\"eth_getTransactionCount\","
                 "\"params\":[\""
                 (address-to-hex sender)
                 "\",\"pending\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (pending
               (field (field content "pending") (address-to-hex sender)))
             (queued
               (field (field content "queued") (address-to-hex sender)))
             (filter-hashes (field filter-changes "result")))
        (is (string= gap-hash (field gap-response "result")))
        (is (string= closing-hash (field closing-response "result")))
        (is (string= (quantity-to-hex 1) (field status "pending")))
        (is (string= (quantity-to-hex 1) (field status "queued")))
        (is (string= closing-hash
                     (field (field pending "0") "hash")))
        (is (string= gap-hash
                     (field (field queued "1") "hash")))
        (is (string= (quantity-to-hex 1)
                     (field transaction-count-response "result")))
        (is (= 1 (length filter-hashes)))
        (is (string= closing-hash (first filter-hashes)))))))

(deftest txpool-basefee-promotion-rechecks-pending-balance
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (gap-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (gap-hash (hash32-to-hex (transaction-hash gap-transaction)))
           (closing-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (closing-hash
             (hash32-to-hex (transaction-hash closing-transaction)))
           (sender (transaction-sender gap-transaction :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000
                                         :base-fee-per-gas 3))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 84000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":207,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (gap-response (send-raw gap-transaction 208 store config)))
        (is (string= gap-hash (field gap-response "result")))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-put-account-nonce
         store (block-hash child-block) sender 0)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 84000)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((closing-response (send-raw closing-transaction 209 store config))
               (status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":210,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":211,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":212,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (transaction-count-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":213,"
                   "\"method\":\"eth_getTransactionCount\","
                   "\"params\":[\""
                   (address-to-hex sender)
                   "\",\"pending\"]}")
                  store
                  config))
               (status (field status-response "result"))
               (content (field content-response "result"))
               (pending
                 (field (field content "pending") (address-to-hex sender)))
               (queued
                 (field (field content "queued") (address-to-hex sender)))
               (filter-hashes (field filter-changes "result")))
          (is (string= closing-hash (field closing-response "result")))
          (is (string= (quantity-to-hex 1) (field status "pending")))
          (is (string= (quantity-to-hex 1) (field status "queued")))
          (is (string= closing-hash
                       (field (field pending "0") "hash")))
          (is (string= gap-hash
                       (field (field queued "1") "hash")))
          (is (string= (quantity-to-hex 1)
                       (field transaction-count-response "result")))
          (is (= 1 (length filter-hashes)))
          (is (string= closing-hash (first filter-hashes))))))))

(deftest txpool-canonical-basefee-rise-demotes-pending-transaction
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000
                                         :base-fee-per-gas 3)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":214,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (send-response (send-raw transaction 215 store config))
             (initial-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":216,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config)))
        (is (string= transaction-hash (field send-response "result")))
        (is (= 1 (length (field initial-filter-changes "result"))))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-put-account-nonce
         store (block-hash child-block) sender 0)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 1000000)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":217,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (pending-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":218,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                  store
                  config))
               (content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":219,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (transaction-count-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":220,"
                   "\"method\":\"eth_getTransactionCount\","
                   "\"params\":[\""
                   (address-to-hex sender)
                   "\",\"pending\"]}")
                  store
                  config))
               (filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":221,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (status (field status-response "result"))
               (content (field content-response "result"))
               (queued
                 (field (field content "queued") (address-to-hex sender))))
          (is (string= (quantity-to-hex 0) (field status "pending")))
          (is (string= (quantity-to-hex 1) (field status "queued")))
          (is (= 0 (length (field pending-response "result"))))
          (is (null (field content "pending")))
          (is (string= transaction-hash
                       (field (field queued "0") "hash")))
          (is (string= (quantity-to-hex 0)
                       (field transaction-count-response "result")))
          (is (= 0 (length (field filter-changes "result")))))))))

(deftest txpool-canonical-balance-drop-demotes-overbudget-pending-tail
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (nonce-zero
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (nonce-one
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (nonce-zero-hash
             (hash32-to-hex (transaction-hash nonce-zero)))
           (nonce-one-hash
             (hash32-to-hex (transaction-hash nonce-one)))
           (sender (transaction-sender nonce-zero :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 42000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":222,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (nonce-zero-response (send-raw nonce-zero 223 store config))
             (nonce-one-response (send-raw nonce-one 224 store config))
             (initial-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":225,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config)))
        (is (string= nonce-zero-hash (field nonce-zero-response "result")))
        (is (string= nonce-one-hash (field nonce-one-response "result")))
        (is (= 2 (length (field initial-filter-changes "result"))))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-put-account-nonce
         store (block-hash child-block) sender 0)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 21000)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":226,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (pending-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":227,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                  store
                  config))
               (content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":228,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (transaction-count-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":229,"
                   "\"method\":\"eth_getTransactionCount\","
                   "\"params\":[\""
                   (address-to-hex sender)
                   "\",\"pending\"]}")
                  store
                  config))
               (filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":230,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (status (field status-response "result"))
               (pending-transactions (field pending-response "result"))
               (content (field content-response "result"))
               (pending
                 (field (field content "pending") (address-to-hex sender)))
               (queued
                 (field (field content "queued") (address-to-hex sender))))
          (is (string= (quantity-to-hex 1) (field status "pending")))
          (is (string= (quantity-to-hex 1) (field status "queued")))
          (is (= 1 (length pending-transactions)))
          (is (string= nonce-zero-hash
                       (field (field pending "0") "hash")))
          (is (string= nonce-one-hash
                       (field (field queued "1") "hash")))
          (is (string= (quantity-to-hex 1)
                       (field transaction-count-response "result")))
          (is (= 0 (length (field filter-changes "result")))))))))

(deftest txpool-stale-pending-transactions-drop-after-canonical-nonce-advance
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 1000000)
      (let* ((send-response (send-raw transaction 181 store config))
             (pending-status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":182,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config)))
        (is (string= transaction-hash (field send-response "result")))
        (is (string= (quantity-to-hex 1)
                     (field (field pending-status-response "result")
                            "pending")))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-put-account-nonce
         store (block-hash child-block) sender 1)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 1000000)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":183,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (pending-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":184,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                  store
                  config))
               (content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":185,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (lookup-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":186,"
                   "\"method\":\"eth_getTransactionByHash\","
                   "\"params\":[\"" transaction-hash "\"]}")
                  store
                  config))
               (raw-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":187,"
                   "\"method\":\"eth_getRawTransactionByHash\","
                   "\"params\":[\"" transaction-hash "\"]}")
                  store
                  config))
               (transaction-count-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":188,"
                   "\"method\":\"eth_getTransactionCount\","
                   "\"params\":[\""
                   (address-to-hex sender)
                   "\",\"pending\"]}")
                  store
                  config))
               (status (field status-response "result"))
               (content (field content-response "result")))
          (is (string= (quantity-to-hex 0) (field status "pending")))
          (is (string= (quantity-to-hex 0) (field status "queued")))
          (is (= 0 (length (field pending-response "result"))))
          (is (null (field content "pending")))
          (is (null (field content "queued")))
          (is (null (field lookup-response "result")))
          (is (null (field raw-response "result")))
          (is (string= (quantity-to-hex 1)
                       (field transaction-count-response "result"))))))))

(deftest txpool-queued-transactions-promote-after-canonical-nonce-advance
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":166,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (send-response (send-raw transaction 167 store config))
             (queued-status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":168,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (queued-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":169,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config)))
        (is (string= transaction-hash (field send-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field (field queued-status-response "result")
                            "pending")))
        (is (string= (quantity-to-hex 1)
                     (field (field queued-status-response "result")
                            "queued")))
        (is (= 0 (length (field queued-filter-changes "result"))))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-put-account-nonce
         store (block-hash child-block) sender 1)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 1000000)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((promoted-status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":170,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":171,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (transaction-count-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":172,"
                   "\"method\":\"eth_getTransactionCount\","
                   "\"params\":[\""
                   (address-to-hex sender)
                   "\",\"pending\"]}")
                  store
                  config))
               (filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":173,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (status (field promoted-status-response "result"))
               (content (field content-response "result"))
               (pending
                 (field (field content "pending") (address-to-hex sender)))
               (filter-hashes (field filter-changes "result")))
          (is (string= (quantity-to-hex 1) (field status "pending")))
          (is (string= (quantity-to-hex 0) (field status "queued")))
          (is (string= transaction-hash
                       (field (field pending "1") "hash")))
          (is (null (field content "queued")))
          (is (string= (quantity-to-hex 2)
                       (field transaction-count-response "result")))
          (is (= 1 (length filter-hashes)))
          (is (string= transaction-hash (first filter-hashes))))))))

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
      (is (= 405 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: 2x

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 400 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: -1

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 400 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: +2

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 400 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: 2
Content-Length: 2

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 400 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
: nope
Content-Type: application/json

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 400 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.0
Content-Type: application/json

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 400 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1 trailing
Content-Type: application/json

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 400 (http-status response))))))

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
      (is (= 400 (http-status (get-output-stream-string output)))))
    (let* ((input
             (make-string-input-stream
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: 2x

{}"))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input
       output
       (make-engine-payload-memory-store)
       (make-chain-config))
      (is (= 400 (http-status (get-output-stream-string output)))))
    (let* ((input
             (make-string-input-stream
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: +2

{}"))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input
       output
       (make-engine-payload-memory-store)
       (make-chain-config))
      (is (= 400 (http-status (get-output-stream-string output)))))
    (let* ((input
             (make-string-input-stream
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: 2
Content-Length: 2

{}"))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input
       output
       (make-engine-payload-memory-store)
       (make-chain-config))
      (is (= 400 (http-status (get-output-stream-string output)))))
    (let* ((input
             (make-string-input-stream
              "POST / HTTP/1.1
: nope
Content-Type: application/json

{}"))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input
       output
       (make-engine-payload-memory-store)
       (make-chain-config))
      (is (= 400 (http-status (get-output-stream-string output)))))
    (let* ((input
             (make-string-input-stream
              "POST / HTTP/1.0
Content-Type: application/json

{}"))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input
       output
       (make-engine-payload-memory-store)
       (make-chain-config))
      (is (= 400 (http-status (get-output-stream-string output)))))
    (let* ((input
             (make-string-input-stream
              "POST / HTTP/1.1 trailing
Content-Type: application/json

{}"))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input
       output
       (make-engine-payload-memory-store)
       (make-chain-config))
      (is (= 400 (http-status (get-output-stream-string output)))))))

(deftest engine-rpc-http-request-telemetry-includes-response-outcome
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (http-body (response)
             (let ((boundary (search (format nil "~C~C~C~C"
                                             #\Return #\Newline
                                             #\Return #\Newline)
                                     response)))
               (subseq response (+ boundary 4))))
           (request (body)
             (format nil
                     "POST / HTTP/1.1~%Host: localhost~%Content-Type: application/json~%Content-Length: ~D~%~%~A"
                     (length body)
                     body)))
    (let* ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
           (head-hash
             "0x1111111111111111111111111111111111111111111111111111111111111111")
           (zero-hash
             "0x0000000000000000000000000000000000000000000000000000000000000000")
           (body
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":30,"
              "\"method\":\"engine_forkchoiceUpdatedV1\","
              "\"params\":[{\"headBlockHash\":\"" head-hash "\","
              "\"safeBlockHash\":\"" zero-hash "\","
              "\"finalizedBlockHash\":\"" zero-hash "\"},null]}"))
           (input (make-string-input-stream (request body)))
           (output (make-string-output-stream))
           (response
             (engine-rpc-handle-http-stream
              input output
              (make-engine-payload-memory-store)
              (make-chain-config)
              :telemetry-sink sink))
           (rpc-response (parse-json (http-body response)))
           (fields
             (ethereum-lisp.telemetry:telemetry-event-fields
              (first (ethereum-lisp.telemetry:telemetry-events sink)))))
      (is (string= +payload-status-syncing+
                   (field (field (field rpc-response "result")
                                 "payloadStatus")
                          "status")))
      (is (string= +payload-status-syncing+
                   (field fields "rpcPayloadStatus"))))
    (let* ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
           (body
             "{\"jsonrpc\":\"2.0\",\"id\":31,\"method\":\"engine_missingMethod\",\"params\":[]}")
           (input (make-string-input-stream (request body)))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input output
       (make-engine-payload-memory-store)
       (make-chain-config)
       :telemetry-sink sink)
      (let ((fields
              (ethereum-lisp.telemetry:telemetry-event-fields
               (first (ethereum-lisp.telemetry:telemetry-events sink)))))
        (is (string= "-32601" (field fields "rpcErrorCode")))))))

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
           (sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
           (now 3000)
           (service
             (make-engine-rpc-http-service
              :host "127.0.0.1"
              :port 8551
              :jwt-secret secret
              :now-provider (lambda () now)
              :import-function #'execute-and-commit-engine-payload
              :telemetry-sink sink)))
      (is (string= "localhost:8551"
                   (engine-rpc-http-service-endpoint default-service)))
      (is (string= "127.0.0.1:8551"
                   (engine-rpc-http-service-endpoint service)))
      (is (null (engine-rpc-http-service-telemetry-sink default-service)))
      (is (eq sink (engine-rpc-http-service-telemetry-sink service)))
      (is (functionp
           (engine-rpc-http-service-import-function default-service)))
      (is (eq #'execute-and-commit-engine-payload
              (engine-rpc-http-service-import-function default-service)))
      (is (typep (engine-rpc-http-service-store service)
                 'engine-payload-memory-store))
      (is (typep (engine-rpc-http-service-config service) 'chain-config))
      (is (functionp (engine-rpc-http-service-import-function service)))
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
      (let ((events (ethereum-lisp.telemetry:telemetry-events sink)))
        (is (= 4 (length events)))
        (is (string= "engine.rpc.http.stream.start"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (first events))))
        (is (string= "engine.rpc.http.request"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (second events))))
        (is (string= "200"
                     (cdr (assoc "status"
                                 (ethereum-lisp.telemetry:telemetry-event-fields
                                  (second events))
                                 :test #'string=))))
        (is (string= "engine_getClientVersionV1"
                     (cdr (assoc "rpcMethods"
                                 (ethereum-lisp.telemetry:telemetry-event-fields
                                  (second events))
                                 :test #'string=))))
        (is (string= "engine.rpc.http.streams"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (third events))))
        (is (= 1
               (ethereum-lisp.telemetry:telemetry-event-value
                (third events))))
        (is (string= "engine.rpc.http.stream.finish"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (fourth events))))
        (is (string= "127.0.0.1:8551"
                     (cdr (assoc "endpoint"
                                 (ethereum-lisp.telemetry:telemetry-event-fields
                                  (first events))
                                 :test #'string=)))))
      (signals block-validation-error
        (make-engine-rpc-http-service :port 70000))
      (signals block-validation-error
        (make-engine-rpc-http-service
         :jwt-secret (make-byte-vector 31 :initial-element 1)))
      (signals block-validation-error
        (make-engine-rpc-http-service :import-function "not a function")))))

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
    (let* ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
           (service (make-engine-rpc-http-service :telemetry-sink sink))
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
      (let ((events (ethereum-lisp.telemetry:telemetry-events sink)))
        (is (= 11 (length events)))
        (is (string= "engine.rpc.http.listener.start"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (first events))))
        (is (string= "engine.rpc.http.stream.start"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (second events))))
        (is (string= "engine.rpc.http.request"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (third events))))
        (is (string= "200"
                     (cdr (assoc "status"
                                 (ethereum-lisp.telemetry:telemetry-event-fields
                                  (third events))
                                 :test #'string=))))
        (is (string= "engine_getClientVersionV1"
                     (cdr (assoc "rpcMethods"
                                 (ethereum-lisp.telemetry:telemetry-event-fields
                                  (third events))
                                 :test #'string=))))
        (is (string= "engine.rpc.http.stream.finish"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (fifth events))))
        (is (string= "engine.rpc.http.listener.connections"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (tenth events))))
        (is (= 2
               (ethereum-lisp.telemetry:telemetry-event-value
                (tenth events))))
        (is (string= "engine.rpc.http.listener.finish"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (nth 10 events)))))
      (signals block-validation-error
        (engine-rpc-http-listener-accept
         (make-engine-rpc-http-listener
          :endpoint "localhost:8551"
          :accept-function (lambda () "not-a-connection"))))
      (signals block-validation-error
        (engine-rpc-http-service-serve-listener
         service listener :max-connections -1)))))

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets))

#+sbcl
(deftest engine-rpc-http-service-serves-local-socket
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
           (endpoint-port (endpoint)
             (parse-integer
              endpoint
              :start (1+ (position #\: endpoint :from-end t))))
           (read-stream-string (stream)
             (with-output-to-string (out)
               (loop for char = (read-char stream nil nil)
                     while char
                     do (write-char char out))))
           (connect-stream (host port)
             (let ((socket (make-instance 'sb-bsd-sockets:inet-socket
                                          :type :stream
                                          :protocol :tcp)))
               (sb-bsd-sockets:socket-connect
                socket
                (sb-bsd-sockets:make-inet-address host)
                port)
               (sb-bsd-sockets:socket-make-stream
                socket
                :input t
                :output t
                :element-type 'character
                :external-format :utf-8
                :buffering :none))))
    (let* ((service (make-engine-rpc-http-service
                     :host "127.0.0.1"
                     :port 0))
           (listener
             (handler-case
                 (make-engine-rpc-http-socket-listener service)
               (sb-bsd-sockets:operation-not-permitted-error ()
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))))
           (port (endpoint-port
                  (engine-rpc-http-listener-endpoint listener)))
           (server-thread
             (sb-thread:make-thread
              (lambda ()
                (engine-rpc-http-service-serve-listener
                 service listener :max-connections 1)))))
      (unwind-protect
           (let* ((body
                    (concatenate
                     'string
                     "{\"jsonrpc\":\"2.0\",\"id\":23,"
                     "\"method\":\"engine_getClientVersionV1\","
                     "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
                     "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
                  (request
                    (format nil
                            "POST / HTTP/1.1~%Host: localhost~%Content-Type: application/json~%Content-Length: ~D~%~%~A"
                            (length body)
                            body))
                  (stream (connect-stream "127.0.0.1" port)))
             (unwind-protect
                  (progn
                    (write-string request stream)
                    (finish-output stream)
                    (let* ((response (read-stream-string stream))
                           (rpc-response (parse-json (http-body response)))
                           (local (first (field rpc-response "result"))))
                      (is (= 200 (http-status response)))
                      (is (= 23 (field rpc-response "id")))
                      (is (string= "ethereum-lisp"
                                   (field local "name")))))
               (close stream))
             (sb-thread:join-thread server-thread))
        (ignore-errors (engine-rpc-http-listener-close listener))))))

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
       sidecar
       :transaction transaction
       :require-proof-verification t))
    (let ((observed nil))
      (let ((*kzg-blob-proof-verifier*
              (lambda (verified-blob verified-commitment verified-proof)
                (setf observed
                      (list verified-blob verified-commitment verified-proof))
                t)))
        (is (kzg-blob-proof-verification-available-p))
        (is (validate-blob-sidecar-fields
             sidecar
             :transaction transaction
             :require-proof-verification t)))
      (is (bytes= blob (first observed)))
      (is (bytes= commitment (second observed)))
      (is (bytes= proof (third observed))))
    (let ((*kzg-blob-proof-verifier*
            (lambda (verified-blob verified-commitment verified-proof)
              (declare (ignore verified-blob verified-commitment
                               verified-proof))
              nil)))
      (signals block-validation-error
        (validate-blob-sidecar-fields
         sidecar
         :transaction transaction
         :require-proof-verification t)))
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
    (let ((invalid-blob (copy-seq blob))
          (called nil))
      (replace invalid-blob
               (ethereum-lisp.crypto::integer-to-fixed-bytes
                ethereum-lisp.core::+kzg-field-modulus+
                32)
               :start1 0)
      (let ((*kzg-blob-proof-verifier*
              (lambda (verified-blob verified-commitment verified-proof)
                (declare (ignore verified-blob verified-commitment
                                 verified-proof))
                (setf called t)
                t)))
        (signals block-validation-error
          (validate-blob-sidecar-fields
           (make-blob-sidecar :blobs (list invalid-blob)
                              :commitments (list commitment)
                              :proofs (list proof))
           :require-proof-verification t)))
      (is (null called)))
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
         (payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data empty-shanghai-block)))
         (payload-object (engine-rpc-executable-data-object payload))
         (decoded-payload
           (engine-rpc-executable-data-from-object payload-object))
         (decoded-block (executable-data-to-block-no-hash decoded-payload))
         (header-with-missing-body
           (make-block-header :withdrawals-root (withdrawal-list-root '())))
         (missing-body-block (make-block :header header-with-missing-body))
         (pre-shanghai-block (make-block :withdrawals '())))
    (is (block-withdrawals-present-p empty-shanghai-block))
    (is (executable-data-withdrawals-present-p payload))
    (is (assoc "withdrawals" payload-object :test #'string=))
    (is (null (cdr (assoc "withdrawals" payload-object :test #'string=))))
    (is (executable-data-withdrawals-present-p decoded-payload))
    (is (block-withdrawals-present-p decoded-block))
    (is (null (block-withdrawals decoded-block)))
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

(deftest block-execution-rejects-pre-byzantium-receipts-by-config
  (let* ((post-state (make-byte-vector 32 :initial-element #x11))
         (receipt (make-receipt :post-state post-state
                                :cumulative-gas-used 21000))
         (state-root (hash32-from-hex
                      "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (block (make-block :receipts (list receipt)))
         (header (block-header block))
         (pre-byzantium-config (make-chain-config :byzantium-block 100))
         (byzantium-config (make-chain-config :byzantium-block 0)))
    (setf (block-header-number header) 42
          (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root
                                      :chain-config pre-byzantium-config))
    (is (validate-block-execution-roots block (list receipt) state-root
                                        :chain-config byzantium-config))))

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
