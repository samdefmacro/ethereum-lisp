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

(defun fixture-sign-blob-transaction (transaction private-key)
  (let* ((n ethereum-lisp.crypto::+secp256k1-n+)
         (half-n ethereum-lisp.crypto::+secp256k1-half-n+)
         (generator
           (ethereum-lisp.crypto::secp256k1-point
            ethereum-lisp.crypto::+secp256k1-gx+
            ethereum-lisp.crypto::+secp256k1-gy+))
         (hash (blob-transaction-signing-hash transaction))
         (message (bytes-to-integer (hash32-bytes hash)))
         (chain-id (blob-transaction-chain-id transaction))
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
                           (make-blob-transaction
                            :chain-id chain-id
                            :nonce (blob-transaction-nonce transaction)
                            :max-priority-fee-per-gas
                            (blob-transaction-max-priority-fee-per-gas
                             transaction)
                            :max-fee-per-gas
                            (blob-transaction-max-fee-per-gas transaction)
                            :gas-limit
                            (blob-transaction-gas-limit transaction)
                            :to (blob-transaction-to transaction)
                            :value (blob-transaction-value transaction)
                            :data (blob-transaction-data transaction)
                            :access-list
                            (blob-transaction-access-list transaction)
                            :max-fee-per-blob-gas
                            (blob-transaction-max-fee-per-blob-gas
                             transaction)
                            :blob-versioned-hashes
                            (blob-transaction-blob-versioned-hashes
                             transaction)
                            :y-parity y-parity
                            :r r
                            :s s)))
                     (when (bytes=
                            (address-bytes expected-sender)
                            (address-bytes
                             (blob-transaction-sender
                              signed :expected-chain-id chain-id)))
                       (return signed)))))
          finally
            (error "Unable to sign blob transaction fixture"))))

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

