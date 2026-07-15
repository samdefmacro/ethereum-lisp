(in-package #:ethereum-lisp.test)

(deftest set-code-intrinsic-gas-adds-authorization-cost
  (let* ((address (address-from-hex
                   "0x00000000000000000000000000000000000000f2"))
         (authorization (make-set-code-authorization
                         :chain-id 1
                         :address address
                         :nonce 0))
         (transaction (make-set-code-transaction
                       :gas-limit 80000
                       :to address
                       :authorization-list
                       (list authorization authorization))))
    (is (= (+ 21000 (* 2 25000))
           (transaction-intrinsic-gas transaction)))))

(deftest set-code-message-requires-nonempty-authorization-list-and-to
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex
                     "0x00000000000000000000000000000000000000f2"))
         (authorization (make-set-code-authorization
                         :chain-id 1
                         :address recipient
                         :nonce 0)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (signals transaction-validation-error
      (apply-message state sender
                     (make-set-code-transaction
                      :gas-limit 50000
                      :to recipient)))
    (signals transaction-validation-error
      (apply-message state sender
                     (make-set-code-transaction
                      :gas-limit 80000
                      :to nil
                      :authorization-list (list authorization))))
    (is (= 0 (state-account-nonce
              (state-db-get-account state sender))))))

(deftest set-code-message-validates-authorization-fields-before-state-mutation
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex
                     "0x00000000000000000000000000000000000000f2"))
         (balance 100000)
         (malformed-address-authorization
           (make-set-code-authorization
            :chain-id 1
            :address nil
            :nonce 0
            :y-parity 1
            :r 1
            :s 1))
         (overwide-chain-authorization
           (make-set-code-authorization
            :chain-id (1+ +uint256-max+)
            :address recipient
            :nonce 0
            :y-parity 1
            :r 1
            :s 1)))
    (state-db-set-account state sender
                          (make-state-account :balance balance))
    (signals transaction-validation-error
      (apply-message state sender
                     (make-set-code-transaction
                      :gas-limit 50000
                      :to recipient
                      :authorization-list
                      (list malformed-address-authorization))))
    (signals transaction-validation-error
      (apply-message state sender
                     (make-set-code-transaction
                      :gas-limit 50000
                      :to recipient
                      :authorization-list
                      (list overwide-chain-authorization))))
    (is (= 0 (state-account-nonce
              (state-db-get-account state sender))))
    (is (= balance
           (state-account-balance
            (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest set-code-message-applies-valid-authorization-delegation
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x71562b71999873db5b286df957af199ec94617f7"))
         (recipient (address-from-hex
                     "0x00000000000000000000000000000000000000f2"))
         (delegated-address (address-from-hex
                             "0x000000000000000000000000000000000000aaaa"))
         (authorization
           (make-set-code-authorization
            :chain-id 1337
            :address delegated-address
            :nonce 1
            :y-parity 1
            :r #x7ed17af7d2d2b9ba7d797a202125bf505b9a0f962a67b3b61b56783d8faf7461
            :s #x01b73b6e586edc706dce6c074eaec28692fa6359fb3446a2442f36777e1c0669))
         (transaction
           (make-set-code-transaction
            :chain-id 1337
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas 1
            :gas-limit 46000
            :to recipient
            :authorization-list (list authorization))))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (let ((receipt (apply-message state sender transaction :chain-id 1337)))
      (is (= 1 (receipt-status receipt)))
      (is (= 36800 (receipt-cumulative-gas-used receipt)))
      (is (= 2 (state-account-nonce
                (state-db-get-account state sender))))
      (is (bytes= (set-code-delegation-code delegated-address)
                  (state-db-get-code state sender)))
      (is (string= (address-to-hex delegated-address)
                   (address-to-hex
                   (set-code-delegation-target
                    (state-db-get-code state sender))))))))

(deftest set-code-message-does-not-refund-new-authority-account
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x71562b71999873db5b286df957af199ec94617f7"))
         (authority (address-from-hex
                     "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
         (recipient (address-from-hex
                     "0x00000000000000000000000000000000000000f2"))
         (delegated-address (address-from-hex
                             "0x000000000000000000000000000000000000bbbb"))
         (authorization
           (make-set-code-authorization
            :chain-id 1337
            :address delegated-address
            :nonce 0
            :y-parity 0
            :r #x4e87877b1ceac0f507bd190e5635ceaaf9c8ead07a83a6fc17ebf0b2eca77b2a
            :s #x513a91f278ece01d0ae0adf08d2b035cdcf06d4524177c93a88ab5e0f17be886))
         (transaction
           (make-set-code-transaction
            :chain-id 1337
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas 1
            :gas-limit 46000
            :to recipient
            :authorization-list (list authorization))))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (let ((receipt (apply-message state sender transaction :chain-id 1337)))
      (is (= 1 (receipt-status receipt)))
      (is (= 46000 (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (= 1 (state-account-nonce
                (state-db-get-account state authority))))
      (is (bytes= (set-code-delegation-code delegated-address)
                  (state-db-get-code state authority))))))

(deftest set-code-message-applies-sequential-authorizations-for-same-authority
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x71562b71999873db5b286df957af199ec94617f7"))
         (authority (address-from-hex
                     "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
         (recipient (address-from-hex
                     "0x00000000000000000000000000000000000000f2"))
         (first-delegated-address (address-from-hex
                                   "0x000000000000000000000000000000000000bbbb"))
         (second-delegated-address (address-from-hex
                                    "0x000000000000000000000000000000000000cccc"))
         (first-authorization
           (make-set-code-authorization
            :chain-id 1337
            :address first-delegated-address
            :nonce 0
            :y-parity 0
            :r #x4e87877b1ceac0f507bd190e5635ceaaf9c8ead07a83a6fc17ebf0b2eca77b2a
            :s #x513a91f278ece01d0ae0adf08d2b035cdcf06d4524177c93a88ab5e0f17be886))
         (second-authorization
           (make-set-code-authorization
            :chain-id 1337
            :address second-delegated-address
            :nonce 1
            :y-parity 1
            :r #xb2c581c09af7db2163ec3947a2fbcae978069374873e262d155857e6460a10f0
            :s #x1e21e98a465c88d201a5b9f582bfdc58145eca358dee2e7bb15f335375b3a28c))
         (transaction
           (make-set-code-transaction
            :chain-id 1337
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas 1
            :gas-limit 71000
            :to recipient
            :authorization-list (list first-authorization
                                      second-authorization))))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (let ((receipt (apply-message state sender transaction :chain-id 1337)))
      (is (= 1 (receipt-status receipt)))
      (is (= 58500 (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (= 2 (state-account-nonce
                (state-db-get-account state authority))))
      (is (bytes= (set-code-delegation-code second-delegated-address)
                  (state-db-get-code state authority))))))

(deftest set-code-authorization-persists-when-recipient-reverts
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x71562b71999873db5b286df957af199ec94617f7"))
         (recipient (address-from-hex
                     "0x00000000000000000000000000000000000000f2"))
         (delegated-address (address-from-hex
                             "0x000000000000000000000000000000000000aaaa"))
         (authorization
           (make-set-code-authorization
            :chain-id 1337
            :address delegated-address
            :nonce 1
            :y-parity 1
            :r #x7ed17af7d2d2b9ba7d797a202125bf505b9a0f962a67b3b61b56783d8faf7461
            :s #x01b73b6e586edc706dce6c074eaec28692fa6359fb3446a2442f36777e1c0669))
         (transaction
           (make-set-code-transaction
            :chain-id 1337
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas 1
            :gas-limit 50000
            :to recipient
            :authorization-list (list authorization))))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-code state recipient #(95 95 #xfd))
    (let ((receipt (apply-message state sender transaction :chain-id 1337)))
      (is (= 0 (receipt-status receipt)))
      (is (= 36804 (receipt-cumulative-gas-used receipt)))
      (is (= 2 (state-account-nonce
                (state-db-get-account state sender))))
      (is (bytes= (set-code-delegation-code delegated-address)
                  (state-db-get-code state sender))))))

(deftest set-code-message-skips-wrong-chain-authorization
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x71562b71999873db5b286df957af199ec94617f7"))
         (recipient (address-from-hex
                     "0x00000000000000000000000000000000000000f2"))
         (delegated-address (address-from-hex
                             "0x000000000000000000000000000000000000aaaa"))
         (authorization
           (make-set-code-authorization
            :chain-id 1337
            :address delegated-address
            :nonce 1
            :y-parity 1
            :r #x7ed17af7d2d2b9ba7d797a202125bf505b9a0f962a67b3b61b56783d8faf7461
            :s #x01b73b6e586edc706dce6c074eaec28692fa6359fb3446a2442f36777e1c0669))
         (transaction
           (make-set-code-transaction
            :chain-id 1
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas 1
            :gas-limit 46000
            :to recipient
            :authorization-list (list authorization))))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (let ((receipt (apply-message state sender transaction :chain-id 1)))
      (is (= 1 (receipt-status receipt)))
      (is (= 46000 (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (zerop (length (state-db-get-code state sender)))))))

(deftest set-code-message-skips-nonce-mismatch-authorization
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x71562b71999873db5b286df957af199ec94617f7"))
         (authority (address-from-hex
                     "0x703c4b2bd70c169f5717101caee543299fc946c7"))
         (recipient (address-from-hex
                     "0x00000000000000000000000000000000000000f2"))
         (delegated-address (address-from-hex
                             "0x000000000000000000000000000000000000bbbb"))
         (authorization
           (make-set-code-authorization
            :chain-id 1337
            :address delegated-address
            :nonce 0
            :y-parity 1
            :r #x5011890f198f0356a887b0779bde5afa1ed04e6acb1e3f37f8f18c7b6f521b98
            :s #x56c3fa3456b103f3ef4a0acb4b647b9cab9ec4bc68fbcdf1e10b49fb2bcbcf61))
         (transaction
           (make-set-code-transaction
            :chain-id 1337
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas 1
            :gas-limit 46000
            :to recipient
            :authorization-list (list authorization))))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (state-db-set-account state authority
                          (make-state-account :nonce 1))
    (let ((receipt (apply-message state sender transaction :chain-id 1337)))
      (is (= 1 (receipt-status receipt)))
      (is (= 46000 (receipt-cumulative-gas-used receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (= 1 (state-account-nonce
                (state-db-get-account state authority))))
      (is (zerop (length (state-db-get-code state authority)))))))

(deftest set-code-message-skips-max-nonce-authorization
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x71562b71999873db5b286df957af199ec94617f7"))
         (authority (address-from-hex
                     "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
         (recipient (address-from-hex
                     "0x00000000000000000000000000000000000000f2"))
         (delegated-address (address-from-hex
                             "0x000000000000000000000000000000000000bbbb"))
         (authorization
           (make-set-code-authorization
            :chain-id 1337
            :address delegated-address
            :nonce #xffffffffffffffff
            :y-parity 0
            :r #xdf70aeed45ec378d210bc3d5739164187460ed3bb3beaad729eb7d4195d1889a
            :s #x1133f2cc049be60413c177e08e0b1a517bdc0ec3943fed1ad350dd04612437c9))
         (transaction
           (make-set-code-transaction
            :chain-id 1337
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas 1
            :gas-limit 46000
            :to recipient
            :authorization-list (list authorization))))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (state-db-set-account state authority
                          (make-state-account :nonce #xffffffffffffffff))
    (let ((receipt (apply-message state sender transaction :chain-id 1337)))
      (is (= 1 (receipt-status receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (= #xffffffffffffffff
             (state-account-nonce
              (state-db-get-account state authority))))
      (is (zerop (length (state-db-get-code state authority)))))))

(deftest set-code-message-skips-authority-with-nondelegation-code
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x71562b71999873db5b286df957af199ec94617f7"))
         (authority (address-from-hex
                     "0x703c4b2bd70c169f5717101caee543299fc946c7"))
         (recipient (address-from-hex
                     "0x00000000000000000000000000000000000000f2"))
         (delegated-address (address-from-hex
                             "0x000000000000000000000000000000000000bbbb"))
         (authority-code #(96 0 96 0))
         (authorization
           (make-set-code-authorization
            :chain-id 1337
            :address delegated-address
            :nonce 0
            :y-parity 1
            :r #x5011890f198f0356a887b0779bde5afa1ed04e6acb1e3f37f8f18c7b6f521b98
            :s #x56c3fa3456b103f3ef4a0acb4b647b9cab9ec4bc68fbcdf1e10b49fb2bcbcf61))
         (transaction
           (make-set-code-transaction
            :chain-id 1337
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas 1
            :gas-limit 46000
            :to recipient
            :authorization-list (list authorization))))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (state-db-set-account state authority
                          (make-state-account :nonce 0))
    (state-db-set-code state authority authority-code)
    (let ((receipt (apply-message state sender transaction :chain-id 1337)))
      (is (= 1 (receipt-status receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (= 0 (state-account-nonce
                (state-db-get-account state authority))))
      (is (bytes= authority-code
                  (state-db-get-code state authority))))))

(deftest set-code-message-skips-invalid-zero-address-authorization
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x71562b71999873db5b286df957af199ec94617f7"))
         (recipient (address-from-hex
                     "0x00000000000000000000000000000000000000f2"))
         (old-delegated-address (address-from-hex
                                 "0x000000000000000000000000000000000000aaaa"))
         (authorization
           (make-set-code-authorization
            :chain-id 1337
            :address (zero-address)
            :nonce 1
            :y-parity 1
            :r #x167b0ecfc343a497095c22ee4270d3cc3b971cc3599fc73bbff727e0d2ed432d
            :s #x1c003c72306807492bf1150e39b2f79da23b49a4e83eb6e9209ae30d3572368f))
         (transaction
           (make-set-code-transaction
            :chain-id 1337
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas 1
            :gas-limit 46000
            :to recipient
            :authorization-list (list authorization))))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-code state sender
                       (set-code-delegation-code old-delegated-address))
    (let ((receipt (apply-message state sender transaction :chain-id 1337)))
      (is (= 1 (receipt-status receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (bytes= (set-code-delegation-code old-delegated-address)
                  (state-db-get-code state sender))))))

(deftest set-code-message-clears-delegation-with-zero-address-authorization
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x71562b71999873db5b286df957af199ec94617f7"))
         (authority (address-from-hex
                     "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
         (recipient (address-from-hex
                     "0x00000000000000000000000000000000000000f2"))
         (old-delegated-address (address-from-hex
                                 "0x000000000000000000000000000000000000aaaa"))
         (authorization
           (make-set-code-authorization
            :chain-id 1337
            :address (zero-address)
            :nonce 1
            :y-parity 1
            :r #x8948ba19b8c3795a0af4c43e5ee7c8d70c435b2972f6c119b6e38d711e20febf
            :s #x5610c3123ed0ecbce774751954cac6ee7cdfb02f76e87b65a6e3528eaee0f4d8))
         (transaction
           (make-set-code-transaction
            :chain-id 1337
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas 1
            :gas-limit 46000
            :to recipient
            :authorization-list (list authorization))))
    (state-db-set-account state sender
                          (make-state-account :nonce 0 :balance 100000))
    (state-db-set-account state authority
                          (make-state-account :nonce 1))
    (state-db-set-code state authority
                       (set-code-delegation-code old-delegated-address))
    (let ((receipt (apply-message state sender transaction :chain-id 1337)))
      (is (= 1 (receipt-status receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender))))
      (is (= 2 (state-account-nonce
                (state-db-get-account state authority))))
      (is (zerop (length (state-db-get-code state authority)))))))

(deftest message-rejects-sender-with-nondelegation-code
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex
                     "0x00000000000000000000000000000000000000f2"))
         (transaction (make-legacy-transaction
                       :nonce 0
                       :gas-price 1
                       :gas-limit 21000
                       :to recipient)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-code state sender #(0))
    (signals transaction-validation-error
      (apply-message state sender transaction))
    (is (= 0 (state-account-nonce
              (state-db-get-account state sender))))))

(deftest message-allows-sender-with-delegation-code
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex
                     "0x00000000000000000000000000000000000000f2"))
         (target (address-from-hex
                  "0x00000000000000000000000000000000000000aa"))
         (transaction (make-legacy-transaction
                       :nonce 0
                       :gas-price 1
                       :gas-limit 21000
                       :to recipient)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-code state sender (set-code-delegation-code target))
    (let ((receipt (apply-message state sender transaction)))
      (is (= 1 (receipt-status receipt)))
      (is (= 1 (state-account-nonce
                (state-db-get-account state sender)))))))

(deftest delegated-message-executes-target-code-at-delegated-address
  (let* ((state (make-state-db))
         (sender (address-from-hex
                  "0x0000000000000000000000000000000000000001"))
         (delegated (address-from-hex
                     "0x00000000000000000000000000000000000000dd"))
         (target (address-from-hex
                  "0x00000000000000000000000000000000000000aa"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000001"))
         ;; Store ADDRESS at slot 1. Delegated execution should keep ADDRESS
         ;; equal to the originally called account, not the code target.
         (target-code #(#x30 96 1 #x55 0))
         (transaction (make-legacy-transaction
                       :nonce 0
                       :gas-price 1
                       :gas-limit 50000
                       :to delegated)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-code state delegated (set-code-delegation-code target))
    (state-db-set-code state target target-code)
    (let ((receipt (apply-message state sender transaction)))
      (is (= 1 (receipt-status receipt)))
      (is (= (bytes-to-integer (address-bytes delegated))
             (state-db-get-storage state delegated slot)))
      (is (= 0 (state-db-get-storage state target slot))))))
