(in-package #:ethereum-lisp.test)

(deftest chain-store-export-import-kv-restores-txpool-subpools
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-txpool-~A" (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (restored (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (pending
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            1
            1))
         (queued
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 110
             :gas-limit 21000
             :to recipient)
            1
            1))
         (basefee
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 120
             :gas-limit 21000
             :to recipient)
            2
            1))
         (blob
           (transaction-from-encoding
            (hex-to-bytes
             "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675")))
         (pending-hash (transaction-hash pending))
         (pending-id (hash32-bytes pending-hash))
         (pending-sender
           (transaction-sender pending :expected-chain-id 1)))
    (unwind-protect
         (progn
           (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
            source pending)
           (ethereum-lisp.txpool:engine-payload-store-put-queued-transaction
            source queued)
           (ethereum-lisp.txpool:engine-payload-store-put-basefee-transaction
            source basefee)
           (ethereum-lisp.txpool:engine-payload-store-put-blob-transaction
            source blob)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record database :txpool pending-id)
               (is present-p)
               (let ((fields (rlp-list-items (rlp-decode-one record))))
                 (is (string= "pending" (bytes-to-ascii (first fields))))
                 (is (bytes= (transaction-encoding pending)
                             (second fields))))))
           (let ((database (make-file-key-value-database path)))
             (is (eq restored
                     (chain-store-import-from-kv restored database))))
           (is (= 1
                  (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
                   restored)))
           (is (= 1
                  (ethereum-lisp.txpool:engine-payload-store-queued-transaction-count
                   restored)))
           (is (= 1
                  (ethereum-lisp.txpool:engine-payload-store-basefee-transaction-count
                   restored)))
           (is (= 1
                  (ethereum-lisp.txpool:engine-payload-store-blob-transaction-count
                   restored)))
           (is (bytes= (transaction-encoding pending)
                       (transaction-encoding
                        (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
                         restored
                         pending-hash))))
           (is (eq (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
                    restored
                    (transaction-hash queued))
                   (ethereum-lisp.txpool:engine-payload-store-queued-transaction
                    restored
                    (transaction-hash queued))))
           (is (bytes= (transaction-encoding basefee)
                       (transaction-encoding
                        (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
                         restored
                         (transaction-hash basefee)))))
           (is (typep blob 'blob-transaction))
           (is (bytes= (transaction-encoding blob)
                       (transaction-encoding
                        (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
                         restored
                         (transaction-hash blob)))))
           (is (eq (ethereum-lisp.txpool:engine-payload-store-pending-transaction
                    restored
                    pending-hash)
                   (first
                    (ethereum-lisp.txpool:engine-payload-store-pending-sender-transactions
                     restored
                     pending-sender))))
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv
              (make-engine-payload-memory-store)
              database))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record database :txpool pending-id :missing)
               (is (eq :missing record))
               (is (not present-p)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-revalidates-restored-txpool
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-txpool-revalidate-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (restored (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (head-block
           (make-block
            :header
            (make-block-header
             :number 1
             :timestamp 12
             :gas-limit 30000
             :base-fee-per-gas 5)))
         (stale-pending
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 6
             :gas-limit 21000
             :to recipient)
            1
            1))
         (basefee-ready
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 6
             :gas-limit 21000
             :to recipient)
            1
            1))
         (queued-ready
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 2
             :gas-price 6
             :gas-limit 21000
             :to recipient)
            1
            1))
         (queued-over-gas
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 3
             :gas-price 6
             :gas-limit 40000
             :to recipient)
            1
            1))
         (sender (transaction-sender basefee-ready :expected-chain-id 1)))
    (unwind-protect
         (progn
           (let ((state (make-state-db)))
             (state-db-set-account
              state
              sender
              (make-state-account :balance 10000000 :nonce 1))
             (setf (block-header-state-root (block-header head-block))
                   (state-db-root state)))
           (chain-store-put-block source head-block :state-available-p t)
           (chain-store-put-account-nonce
            source (block-hash head-block) sender 1)
           (chain-store-put-account-balance
            source (block-hash head-block) sender 10000000)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash stale-pending))
              (ethereum-lisp.chain-store.persistence::chain-store-txpool-transaction-record-rlp
               :pending
               stale-pending))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash basefee-ready))
              (ethereum-lisp.chain-store.persistence::chain-store-txpool-transaction-record-rlp
               :basefee
               basefee-ready))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash queued-ready))
              (ethereum-lisp.chain-store.persistence::chain-store-txpool-transaction-record-rlp
               :queued
               queued-ready))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash queued-over-gas))
              (ethereum-lisp.chain-store.persistence::chain-store-txpool-transaction-record-rlp
               :queued
               queued-over-gas)))
           (let ((database (make-file-key-value-database path)))
             (is (eq restored
                     (chain-store-import-from-kv restored database))))
           (is (= 2
                  (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
                   restored)))
           (is (= 0
                  (ethereum-lisp.txpool:engine-payload-store-queued-transaction-count
                   restored)))
           (is (= 0
                  (ethereum-lisp.txpool:engine-payload-store-basefee-transaction-count
                   restored)))
           (is (eq nil
                   (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
                    restored
                    (transaction-hash stale-pending))))
           (is (eq nil
                   (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
                    restored
                    (transaction-hash queued-over-gas))))
           (is (bytes= (transaction-encoding basefee-ready)
                       (transaction-encoding
                        (ethereum-lisp.txpool:engine-payload-store-pending-transaction
                         restored
                         (transaction-hash basefee-ready)))))
           (is (bytes= (transaction-encoding queued-ready)
                       (transaction-encoding
                        (ethereum-lisp.txpool:engine-payload-store-pending-transaction
                         restored
                         (transaction-hash queued-ready)))))
           (let ((sender-transactions
                   (ethereum-lisp.txpool:engine-payload-store-pending-sender-transactions
                    restored
                    sender)))
             (is (= 2 (length sender-transactions)))
             (is (= 1 (transaction-nonce (first sender-transactions))))
             (is (= 2 (transaction-nonce (second sender-transactions))))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-prunes-overbudget-parked-txpool
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-txpool-budget-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (restored (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (head-block
           (make-block
            :header
            (make-block-header
             :number 1
             :timestamp 12
             :gas-limit 30000
             :base-fee-per-gas 5)))
         (basefee-parked
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            1
            1))
         (queued-overbudget
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 1
             :gas-limit 21000
             :to recipient)
            1
            1))
         (sender (transaction-sender basefee-parked :expected-chain-id 1)))
    (unwind-protect
         (progn
           (let ((state (make-state-db)))
             (state-db-set-account
              state
              sender
              (make-state-account :balance 100000 :nonce 0))
             (setf (block-header-state-root (block-header head-block))
                   (state-db-root state)))
           (chain-store-put-block source head-block :state-available-p t)
           (chain-store-put-account-nonce
            source (block-hash head-block) sender 0)
           (chain-store-put-account-balance
            source (block-hash head-block) sender 100000)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash basefee-parked))
              (ethereum-lisp.chain-store.persistence::chain-store-txpool-transaction-record-rlp
               :basefee
               basefee-parked))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash queued-overbudget))
              (ethereum-lisp.chain-store.persistence::chain-store-txpool-transaction-record-rlp
               :queued
               queued-overbudget)))
           (let ((database (make-file-key-value-database path)))
             (is (eq restored
                     (chain-store-import-from-kv restored database))))
           (is (= 0
                  (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
                   restored)))
           (is (= 0
                  (ethereum-lisp.txpool:engine-payload-store-queued-transaction-count
                   restored)))
           (is (= 1
                  (ethereum-lisp.txpool:engine-payload-store-basefee-transaction-count
                   restored)))
           (is (bytes= (transaction-encoding basefee-parked)
                       (transaction-encoding
                        (ethereum-lisp.txpool:engine-payload-store-basefee-transaction
                         restored
                         (transaction-hash basefee-parked)))))
           (is (null
                (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
                 restored
                 (transaction-hash queued-overbudget)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-prunes-sender-code-invalid-txpool
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-txpool-code-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (restored (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (sender-code #(1 2 3))
         (head-block
           (make-block
            :header
            (make-block-header
             :number 1
             :timestamp 12
             :gas-limit 30000
             :base-fee-per-gas 5)))
         (pending-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 6
             :gas-limit 21000
             :to recipient)
            1
            1))
         (queued-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 6
             :gas-limit 21000
             :to recipient)
            1
            1))
         (basefee-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 2
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            1
            1))
         (sender (transaction-sender pending-transaction
                                     :expected-chain-id 1)))
    (unwind-protect
         (progn
           (let ((state (make-state-db)))
             (state-db-set-account
              state
              sender
              (make-state-account :balance 10000000
                                  :nonce 0
                                  :code-hash
                                  (keccak-256-hash sender-code)))
             (setf (block-header-state-root (block-header head-block))
                   (state-db-root state)))
           (chain-store-put-block source head-block :state-available-p t)
           (chain-store-put-account-nonce
            source (block-hash head-block) sender 0)
           (chain-store-put-account-balance
            source (block-hash head-block) sender 10000000)
           (chain-store-put-account-code
            source (block-hash head-block) sender sender-code)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash pending-transaction))
              (ethereum-lisp.chain-store.persistence::chain-store-txpool-transaction-record-rlp
               :pending
               pending-transaction))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash queued-transaction))
              (ethereum-lisp.chain-store.persistence::chain-store-txpool-transaction-record-rlp
               :queued
               queued-transaction))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash basefee-transaction))
              (ethereum-lisp.chain-store.persistence::chain-store-txpool-transaction-record-rlp
               :basefee
               basefee-transaction)))
           (let ((database (make-file-key-value-database path)))
             (is (eq restored
                     (chain-store-import-from-kv restored database))))
           (is (= 0
                  (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
                   restored)))
           (is (= 0
                  (ethereum-lisp.txpool:engine-payload-store-queued-transaction-count
                   restored)))
           (is (= 0
                  (ethereum-lisp.txpool:engine-payload-store-basefee-transaction-count
                   restored)))
           (dolist (transaction (list pending-transaction
                                      queued-transaction
                                      basefee-transaction))
             (is (null
                  (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
                   restored
                   (transaction-hash transaction))))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-rejects-wrong-chain-txpool-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-txpool-chain-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (target (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (target-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 9
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            1
            1))
         (wrong-chain-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            2
            2)))
    (unwind-protect
         (progn
           (is (transaction-sender wrong-chain-transaction
                                   :expected-chain-id nil))
           (is (null (transaction-sender wrong-chain-transaction
                                         :expected-chain-id 1)))
           (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
            target target-transaction)
           (let ((database (make-file-key-value-database path)))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash wrong-chain-transaction))
              (ethereum-lisp.chain-store.persistence::chain-store-txpool-transaction-record-rlp
               :pending
               wrong-chain-transaction)))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)
              :expected-chain-id 1))
           (is (= 1
                  (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
                   target)))
           (is (eq target-transaction
                   (ethereum-lisp.txpool:engine-payload-store-pending-transaction
                    target
                    (transaction-hash target-transaction)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-enforces-txpool-fork-rules
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-txpool-fork-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (pre-cancun-config
           (make-chain-config :chain-id 1337
                              :london-block 0
                              :cancun-time 100))
         (cancun-config
           (make-chain-config :chain-id 1337
                              :london-block 0
                              :cancun-time 0))
         (transaction
           (transaction-from-encoding
            (hex-to-bytes
             "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675"))))
    (unwind-protect
         (progn
           (is (typep transaction 'blob-transaction))
           (is (transaction-sender transaction :expected-chain-id 1337))
           (let ((database (make-file-key-value-database path)))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash transaction))
              (ethereum-lisp.chain-store.persistence::chain-store-txpool-transaction-record-rlp
               :blob
               transaction)))
           (signals block-validation-error
             (chain-store-import-from-kv
              (make-engine-payload-memory-store)
              (make-file-key-value-database path)
              :expected-chain-id 1337
              :chain-config pre-cancun-config))
           (let ((restored (make-engine-payload-memory-store)))
             (chain-store-import-from-kv
              restored
              (make-file-key-value-database path)
              :expected-chain-id 1337
              :chain-config cancun-config)
             (is (= 1
                    (ethereum-lisp.txpool:engine-payload-store-blob-transaction-count
                     restored)))
             (is (typep
                  (ethereum-lisp.txpool:engine-payload-store-blob-transaction
                   restored
                   (transaction-hash transaction))
                  'blob-transaction))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-enforces-txpool-blob-fee-cap
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-txpool-blob-fee-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (config (make-chain-config :chain-id 1337
                                    :london-block 0
                                    :cancun-time 0))
         (head-block
           (make-block
            :header
            (make-block-header
             :number 1
             :timestamp 12
             :gas-limit 30000000
             :blob-gas-used 0
             :excess-blob-gas (* 64 1024 1024))))
         (transaction
           (transaction-from-encoding
            (hex-to-bytes
             "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675"))))
    (unwind-protect
         (progn
           (is (typep transaction 'blob-transaction))
           (is (> (block-header-blob-base-fee (block-header head-block))
                  (blob-transaction-max-fee-per-blob-gas transaction)))
           (is (transaction-sender transaction :expected-chain-id 1337))
           (chain-store-put-block source head-block :state-available-p t)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash transaction))
              (ethereum-lisp.chain-store.persistence::chain-store-txpool-transaction-record-rlp
               :blob
               transaction)))
           (signals block-validation-error
             (chain-store-import-from-kv
              (make-engine-payload-memory-store)
              (make-file-key-value-database path)
              :expected-chain-id 1337
              :chain-config config)))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-enforces-txpool-static-fields
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-txpool-static-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (config
           (make-chain-config :chain-id 1337
                              :london-block 0
                              :cancun-time 0))
         (transaction
           (transaction-from-encoding
            (hex-to-bytes
             "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675")))
         (malformed
           (transaction-from-encoding (transaction-encoding transaction))))
    (setf (blob-transaction-blob-versioned-hashes malformed) '())
    (unwind-protect
         (progn
           (is (transaction-sender malformed :expected-chain-id 1337))
           (signals block-validation-error
             (validate-blob-transaction-fields malformed))
           (let ((database (make-file-key-value-database path)))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash malformed))
              (ethereum-lisp.chain-store.persistence::chain-store-txpool-transaction-record-rlp
               :blob
               malformed)))
           (signals block-validation-error
             (chain-store-import-from-kv
              (make-engine-payload-memory-store)
              (make-file-key-value-database path)
              :expected-chain-id 1337
              :chain-config config)))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-enforces-set-code-authorization-signatures
  (labels ((first-authorization (transaction)
             (first (set-code-transaction-authorization-list transaction))))
    (let* ((path
             (merge-pathnames
              (make-pathname
               :name (format nil "ethereum-lisp-chain-txpool-auth-~A"
                             (gensym))
               :type "sexp")
              #P"/private/tmp/"))
           (config (make-chain-config :chain-id 1337))
           (transaction
             (transaction-from-encoding
              (hex-to-bytes
               "0x04f90126820539800285012a05f2008307a1209471562b71999873db5b286df957af199ec94617f78080c0f8baf85c82053994000000000000000000000000000000000000aaaa0101a07ed17af7d2d2b9ba7d797a202125bf505b9a0f962a67b3b61b56783d8faf7461a001b73b6e586edc706dce6c074eaec28692fa6359fb3446a2442f36777e1c0669f85a8094000000000000000000000000000000000000bbbb8001a05011890f198f0356a887b0779bde5afa1ed04e6acb1e3f37f8f18c7b6f521b98a056c3fa3456b103f3ef4a0acb4b647b9cab9ec4bc68fbcdf1e10b49fb2bcbcf6101a0167b0ecfc343a497095c22ee4270d3cc3b971cc3599fc73bbff727e0d2ed432da01c003c72306807492bf1150e39b2f79da23b49a4e83eb6e9209ae30d3572368f")))
           (malformed
             (transaction-from-encoding (transaction-encoding transaction))))
      (setf (set-code-authorization-s (first-authorization malformed))
            #x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a1)
      (unwind-protect
           (progn
             (is (transaction-sender malformed :expected-chain-id 1337))
             (signals block-validation-error
               (ethereum-lisp.consensus:validate-set-code-authorization-signatures
                malformed))
             (let ((database (make-file-key-value-database path)))
               (kv-put-chain-record
                database
                :txpool
                (hash32-bytes (transaction-hash malformed))
                (ethereum-lisp.chain-store.persistence::chain-store-txpool-transaction-record-rlp
                 :pending
                 malformed)))
             (signals block-validation-error
               (chain-store-import-from-kv
                (make-engine-payload-memory-store)
                (make-file-key-value-database path)
                :expected-chain-id 1337
                :chain-config config)))
        (when (probe-file path)
          (delete-file path))))))

(deftest chain-store-import-from-kv-rejects-corrupt-txpool-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-txpool-corrupt-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (target-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 9
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            1
            1))
         (transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            2
            1))
         (replacement
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 2
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            3
            1)))
    (unwind-protect
         (progn
           (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
            target target-transaction)
           (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
            source transaction)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash transaction))
              (ethereum-lisp.chain-store.persistence::chain-store-txpool-transaction-record-rlp
               :pending
               replacement)))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (= 1
                  (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
                   target)))
           (is (eq target-transaction
                   (ethereum-lisp.txpool:engine-payload-store-pending-transaction
                    target
                    (transaction-hash target-transaction)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-rejects-txpool-subpool-type-mismatch
  (labels ((with-database-record (subpool transaction thunk)
             (let ((path
                     (merge-pathnames
                      (make-pathname
                       :name
                       (format nil "ethereum-lisp-chain-txpool-subpool-~A"
                               (gensym))
                       :type "sexp")
                      #P"/private/tmp/")))
               (unwind-protect
                    (progn
                      (let ((database (make-file-key-value-database path)))
                        (kv-put-chain-record
                         database
                         :txpool
                         (hash32-bytes (transaction-hash transaction))
                         (ethereum-lisp.chain-store.persistence::chain-store-txpool-transaction-record-rlp
                          subpool
                          transaction)))
                      (funcall thunk path))
                 (when (probe-file path)
                   (delete-file path))))))
    (let* ((recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (legacy-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 100
               :gas-limit 21000
               :to recipient)
              1
              1))
           (blob-transaction
             (transaction-from-encoding
              (hex-to-bytes
               "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675")))
           (config (make-chain-config :chain-id 1337
                                      :london-block 0
                                      :cancun-time 0)))
      (with-database-record
       :blob
       legacy-transaction
       (lambda (path)
         (let ((target (make-engine-payload-memory-store)))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (= 0
                  (ethereum-lisp.txpool:engine-payload-store-blob-transaction-count
                   target))))))
      (with-database-record
       :pending
       blob-transaction
       (lambda (path)
         (let ((target (make-engine-payload-memory-store)))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)
              :expected-chain-id 1337
              :chain-config config))
           (is (= 0
                  (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
                   target)))))))))

(deftest chain-store-import-from-kv-rejects-conflicting-txpool-records
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-txpool-conflict-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (target (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (target-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 9
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            1
            1))
         (pending
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            2
            1))
         (queued-conflict
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 120
             :gas-limit 21000
             :to recipient)
            2
            1)))
    (unwind-protect
         (progn
           (is (not (bytes= (hash32-bytes (transaction-hash pending))
                            (hash32-bytes
                             (transaction-hash queued-conflict)))))
           (is (bytes= (address-bytes
                        (transaction-sender pending :expected-chain-id 1))
                       (address-bytes
                        (transaction-sender queued-conflict
                                            :expected-chain-id 1))))
           (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
            target target-transaction)
           (let ((database (make-file-key-value-database path)))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash pending))
              (ethereum-lisp.chain-store.persistence::chain-store-txpool-transaction-record-rlp
               :pending
               pending))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash queued-conflict))
              (ethereum-lisp.chain-store.persistence::chain-store-txpool-transaction-record-rlp
               :queued
               queued-conflict)))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (= 1
                  (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
                   target)))
           (is (= 0
                  (ethereum-lisp.txpool:engine-payload-store-queued-transaction-count
                   target)))
           (is (eq target-transaction
                   (ethereum-lisp.txpool:engine-payload-store-pending-transaction
                    target
                    (transaction-hash target-transaction))))
           (is (null
                (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
                 target
                 (transaction-hash pending))))
           (is (null
                (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
                 target
                 (transaction-hash queued-conflict)))))
      (when (probe-file path)
        (delete-file path)))))
