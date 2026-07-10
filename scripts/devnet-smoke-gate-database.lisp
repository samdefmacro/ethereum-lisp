(in-package #:ethereum-lisp.test)

(defun devnet-smoke-gate-verify-database
    (path expected-block-number balance-targets
     sender-address expected-sender-nonce
     code-address expected-code storage-address storage-key expected-storage
     transaction-checks log-targets block-hash
     expected-safe-block-number expected-safe-block-hash
     expected-finalized-block-number expected-finalized-block-hash
     config
     &key state-prune-before pruned-state-hash
          (expected-head-block-number expected-block-number)
          checkpoint-balance-targets
          prepared-payload-id prepared-payload-parent-hash
          prepared-payload-block-number
          remote-payload remote-block
          invalid-block invalid-descendant-payload
          txpool-transactions
          selected-txpool-transaction
          side-payload side-block child-block)
  (let* ((database (make-file-key-value-database path))
         (node
           (devnet-smoke-gate-make-restored-node path config :port 0))
         (summary (ethereum-lisp.cli:devnet-node-summary node))
         (restored-store (ethereum-lisp.cli:devnet-node-store node))
         (pruned-state-expected-p
           (and state-prune-before
                pruned-state-hash
                (< (hex-to-quantity expected-safe-block-number)
                   state-prune-before)))
         (public-rpc-summary
           (devnet-smoke-gate-verify-restored-public-rpc
            node
            expected-block-number
            balance-targets
            sender-address
            expected-sender-nonce
            code-address
            expected-code
            storage-address
            storage-key
            expected-storage
            transaction-checks
            log-targets
            block-hash
            expected-safe-block-number
            expected-safe-block-hash
            expected-finalized-block-number
            expected-finalized-block-hash
            :pruned-state-rpc-tag
            (when pruned-state-expected-p "safe")
            :expected-head-block-number expected-head-block-number))
         (engine-rpc-summary
           (and prepared-payload-id
                (devnet-smoke-gate-verify-restored-engine-rpc
                 node
                 prepared-payload-id
                 prepared-payload-parent-hash
                 prepared-payload-block-number
                 expected-head-block-number)))
         (remote-block-hash (and remote-block (block-hash remote-block)))
         (restored-remote-block
           (and remote-block-hash
                (ethereum-lisp.chain-store:engine-payload-store-remote-block
                 restored-store remote-block-hash)))
         (remote-block-rpc-summary
           (and remote-payload
                remote-block
                (devnet-smoke-gate-verify-restored-remote-block-rpc
                 node
                 remote-payload
                 remote-block-hash
                 expected-head-block-number)))
         (invalid-block-hash (and invalid-block (block-hash invalid-block)))
         (restored-invalid-block
           (and invalid-block-hash
                (ethereum-lisp.chain-store:engine-payload-store-invalid-block
                 restored-store invalid-block-hash)))
         (invalid-tipset-rpc-summary
           (and invalid-block
                invalid-descendant-payload
                (devnet-smoke-gate-verify-restored-invalid-tipset-rpc
                 node
                 invalid-descendant-payload
                 (block-header-parent-hash (block-header invalid-block))
                 expected-head-block-number)))
         (txpool-rpc-summary
           (and txpool-transactions
                (devnet-smoke-gate-verify-restored-txpool-rpc
                 node txpool-transactions
                 :selected-pending-imported-p
                 (and expected-head-block-number
                      (not (string= expected-block-number
                                    expected-head-block-number)))
                 :selected-pending-transaction
                 selected-txpool-transaction)))
         (side-reorg-rpc-summary
           (and (not state-prune-before)
                side-payload
                side-block
                child-block
                (devnet-smoke-gate-verify-restored-side-reorg-rpc
                 path
                 side-payload
                 side-block
                 child-block
                 balance-targets
                 checkpoint-balance-targets
                 transaction-checks
                 expected-safe-block-hash
                 sender-address
                 code-address
                 storage-address
                 storage-key
                 config))))
    (devnet-smoke-gate-require
     (< 0 (length (kv-chain-record-entries database :block)))
     "Database export did not write block records")
    (devnet-smoke-gate-require
     (< 0 (length (kv-chain-record-entries database :canonical-hash)))
     "Database export did not write canonical hash records")
    (when prepared-payload-id
      (devnet-smoke-gate-require
       (< 0 (length (kv-chain-record-entries database :prepared-payload)))
       "Database export did not write prepared payload records"))
    (when remote-block
      (devnet-smoke-gate-require
       (< 0 (length (kv-chain-record-entries database :remote-block)))
       "Database export did not write remote block records")
      (devnet-smoke-gate-require
       restored-remote-block
       "Database restore did not publish the remote block cache")
      (devnet-smoke-gate-require
       (bytes= (block-rlp remote-block)
               (block-rlp restored-remote-block))
       "Database restore changed the remote block RLP"))
    (when invalid-block
      (devnet-smoke-gate-require
       (< 0 (length (kv-chain-record-entries database :invalid-tipset)))
       "Database export did not write invalid-tipset records")
      (devnet-smoke-gate-require
       restored-invalid-block
       "Database restore did not publish the invalid-tipset cache")
      (devnet-smoke-gate-require
       (bytes= (block-rlp invalid-block)
               (block-rlp restored-invalid-block))
       "Database restore changed the invalid-tipset block RLP"))
    (when txpool-transactions
      (devnet-smoke-gate-require
       (< 0 (length (kv-chain-record-entries database :txpool)))
       "Database export did not write txpool records"))
    (devnet-smoke-gate-require
     (= (hex-to-quantity expected-head-block-number)
        (getf summary :head-number))
     "Database restored head mismatch: expected ~A got ~A"
     expected-head-block-number
     (quantity-to-hex (getf summary :head-number)))
    (devnet-smoke-gate-require
     (string= path (getf summary :database-path))
     "Database path missing from restored node summary")
    (when pruned-state-expected-p
      (devnet-smoke-gate-require
       (chain-store-known-block restored-store pruned-state-hash)
       "Pruned-state block was not restored by hash")
      (devnet-smoke-gate-require
       (not (chain-store-state-available-p restored-store pruned-state-hash))
       "Pruned state snapshot is still available after restore"))
    (append summary
            (list :pruned-state-before state-prune-before
                  :pruned-state-available-p
                  (and pruned-state-hash
                       (chain-store-state-available-p
                        restored-store pruned-state-hash))
                  :rpc-block-number
                  (getf public-rpc-summary :block-number)
                  :rpc-balance
                  (getf public-rpc-summary :balance)
                  :rpc-nonce
                  (getf public-rpc-summary :nonce)
                  :rpc-code
                  (getf public-rpc-summary :code)
                  :rpc-storage
                  (getf public-rpc-summary :storage)
                  :rpc-proof-address
                  (getf public-rpc-summary :proof-address)
                  :rpc-proof-code-hash
                  (getf public-rpc-summary :proof-code-hash)
                  :rpc-proof-storage-key
                  (getf public-rpc-summary :proof-storage-key)
                  :rpc-proof-storage-value
                  (getf public-rpc-summary :proof-storage-value)
                  :rpc-proof-storage-count
                  (getf public-rpc-summary :proof-storage-count)
                  :rpc-proof-account-proof-count
                  (getf public-rpc-summary :proof-account-proof-count)
                  :rpc-receipt-transaction-hash
                  (getf public-rpc-summary :receipt-transaction-hash)
                  :rpc-receipt-block-number
                  (getf public-rpc-summary :receipt-block-number)
                  :rpc-block-hash
                  (getf public-rpc-summary :block-hash)
                  :rpc-block-by-hash-number
                  (getf public-rpc-summary :block-by-hash-number)
                  :rpc-block-transaction-hash
                  (getf public-rpc-summary :block-transaction-hash)
                  :rpc-block-by-number-hash
                  (getf public-rpc-summary :block-by-number-hash)
                  :rpc-block-by-number-number
                  (getf public-rpc-summary :block-by-number-number)
                  :rpc-block-by-number-transaction-hash
                  (getf public-rpc-summary
                        :block-by-number-transaction-hash)
                  :rpc-full-block-transaction-count
                  (getf public-rpc-summary
                        :full-block-transaction-count)
                  :rpc-full-block-transaction-hash
                  (getf public-rpc-summary :full-block-transaction-hash)
                  :rpc-full-block-transaction-index
                  (getf public-rpc-summary :full-block-transaction-index)
                  :rpc-full-block-by-number-transaction-count
                  (getf public-rpc-summary
                        :full-block-by-number-transaction-count)
                  :rpc-full-block-by-number-transaction-hash
                  (getf public-rpc-summary
                        :full-block-by-number-transaction-hash)
                  :rpc-full-block-by-number-transaction-index
                  (getf public-rpc-summary
                        :full-block-by-number-transaction-index)
                  :rpc-transaction-hash
                  (getf public-rpc-summary :transaction-hash)
                  :rpc-transaction-block-hash
                  (getf public-rpc-summary :transaction-block-hash)
                  :rpc-transaction-block-number
                  (getf public-rpc-summary :transaction-block-number)
                  :rpc-block-receipts-count
                  (getf public-rpc-summary :block-receipts-count)
                  :rpc-block-receipt-transaction-hash
                  (getf public-rpc-summary :block-receipt-transaction-hash)
                  :rpc-block-receipt-block-hash
                  (getf public-rpc-summary :block-receipt-block-hash)
                  :rpc-block-receipt-block-number
                  (getf public-rpc-summary :block-receipt-block-number)
                  :rpc-block-transaction-count-by-hash
                  (getf public-rpc-summary
                        :block-transaction-count-by-hash)
                  :rpc-block-transaction-count-by-number
                  (getf public-rpc-summary
                        :block-transaction-count-by-number)
                  :rpc-canonical-hash-balance
                  (getf public-rpc-summary :canonical-hash-balance)
                  :rpc-canonical-hash-require-balance
                  (getf public-rpc-summary
                        :canonical-hash-require-balance)
                  :rpc-transaction-count
                  (getf public-rpc-summary :transaction-count)
                  :rpc-balance-count
                  (getf public-rpc-summary :balance-count)
                  :rpc-log-count
                  (getf public-rpc-summary :log-count)
                  :rpc-log-filter-count
                  (getf public-rpc-summary :log-filter-count)
                  :rpc-log-filter-log-count
                  (getf public-rpc-summary :log-filter-log-count)
                  :rpc-log-filter-uninstall-count
                  (getf public-rpc-summary
                        :log-filter-uninstall-count)
                  :rpc-log-filter-missing-error-codes
                  (getf public-rpc-summary
                        :log-filter-missing-error-codes)
                  :rpc-block-filter-id
                  (getf public-rpc-summary :block-filter-id)
                  :rpc-block-filter-change-count
                  (getf public-rpc-summary :block-filter-change-count)
                  :rpc-block-filter-get-logs-error-code
                  (getf public-rpc-summary
                        :block-filter-get-logs-error-code)
                  :rpc-block-filter-uninstall-result
                  (getf public-rpc-summary
                        :block-filter-uninstall-result)
                  :rpc-block-filter-missing-error-code
                  (getf public-rpc-summary
                        :block-filter-missing-error-code)
                  :rpc-raw-transaction
                  (getf public-rpc-summary :raw-transaction)
                  :rpc-raw-transaction-by-hash
                  (getf public-rpc-summary :raw-transaction-by-hash)
                  :rpc-raw-transaction-by-number
                  (getf public-rpc-summary :raw-transaction-by-number)
                  :rpc-transaction-by-hash-index-hash
                  (getf public-rpc-summary
                        :transaction-by-hash-index-hash)
                  :rpc-transaction-by-hash-index-block-hash
                  (getf public-rpc-summary
                        :transaction-by-hash-index-block-hash)
                  :rpc-transaction-by-hash-index-block-number
                  (getf public-rpc-summary
                        :transaction-by-hash-index-block-number)
                  :rpc-transaction-by-hash-index-transaction-index
                  (getf public-rpc-summary
                        :transaction-by-hash-index-transaction-index)
                  :rpc-transaction-by-number-index-hash
                  (getf public-rpc-summary
                        :transaction-by-number-index-hash)
                  :rpc-transaction-by-number-index-block-hash
                  (getf public-rpc-summary
                        :transaction-by-number-index-block-hash)
                  :rpc-transaction-by-number-index-block-number
                  (getf public-rpc-summary
                        :transaction-by-number-index-block-number)
                  :rpc-transaction-by-number-index-transaction-index
                  (getf public-rpc-summary
                        :transaction-by-number-index-transaction-index)
                  :rpc-safe-block-hash
                  (getf public-rpc-summary :safe-block-hash)
                  :rpc-safe-block-number
                  (getf public-rpc-summary :safe-block-number)
                  :rpc-finalized-block-hash
                  (getf public-rpc-summary :finalized-block-hash)
                  :rpc-finalized-block-number
                  (getf public-rpc-summary :finalized-block-number)
                  :rpc-call-result
                  (getf public-rpc-summary :call-result)
                  :rpc-failed-call-error-message
                  (getf public-rpc-summary :failed-call-error-message)
                  :rpc-estimate-gas
                  (getf public-rpc-summary :estimate-gas)
                  :rpc-access-list-count
                  (getf public-rpc-summary :access-list-count)
                  :rpc-access-list-gas-used
                  (getf public-rpc-summary :access-list-gas-used)
                  :rpc-post-call-storage
                  (getf public-rpc-summary :post-call-storage)
                  :rpc-simulation-count
                  (getf public-rpc-summary :simulation-count)
                  :rpc-pruned-state-error-message
                  (getf public-rpc-summary :pruned-state-error-message)
                  :rpc-pruned-state-error-messages
                  (getf public-rpc-summary :pruned-state-error-messages)
                  :rpc-public-connections
                  (getf public-rpc-summary :public-connections)
                  :rpc-prepared-payload-id
                  (and engine-rpc-summary
                       (getf engine-rpc-summary :prepared-payload-id))
                  :rpc-prepared-payload-parent-hash
                  (and engine-rpc-summary
                       (getf engine-rpc-summary
                             :prepared-payload-parent-hash))
                  :rpc-prepared-payload-block-number
                  (and engine-rpc-summary
                       (getf engine-rpc-summary
                             :prepared-payload-block-number))
                  :rpc-engine-connections
                  (and engine-rpc-summary
                       (getf engine-rpc-summary :engine-connections))
                  :remote-block-hash
                  (and remote-block-rpc-summary
                       (getf remote-block-rpc-summary :remote-block-hash))
                  :rpc-remote-block-status
                  (and remote-block-rpc-summary
                       (getf remote-block-rpc-summary :remote-block-status))
                  :rpc-remote-block-engine-connections
                  (and remote-block-rpc-summary
                       (getf remote-block-rpc-summary
                             :engine-connections))
                  :invalid-tipset-block-hash
                  (and invalid-block
                       (hash32-to-hex (block-hash invalid-block)))
                  :rpc-invalid-tipset-status
                  (and invalid-tipset-rpc-summary
                       (getf invalid-tipset-rpc-summary
                             :invalid-tipset-status))
                  :rpc-invalid-tipset-validation-error
                  (and invalid-tipset-rpc-summary
                       (getf invalid-tipset-rpc-summary
                             :invalid-tipset-validation-error))
                  :rpc-invalid-tipset-engine-connections
                  (and invalid-tipset-rpc-summary
                       (getf invalid-tipset-rpc-summary
                             :engine-connections))
                  :rpc-txpool-transaction-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-transaction-hash))
                  :rpc-txpool-raw-transaction
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-raw-transaction))
                  :rpc-txpool-sender
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary :txpool-sender))
                  :rpc-txpool-nonce
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary :txpool-nonce))
                  :rpc-txpool-inspect-summary
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-inspect-summary))
                  :rpc-txpool-basefee-transaction-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-basefee-transaction-hash))
                  :rpc-txpool-basefee-raw-transaction
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-basefee-raw-transaction))
                  :rpc-txpool-basefee-nonce
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-basefee-nonce))
                  :rpc-txpool-basefee-inspect-summary
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-basefee-inspect-summary))
                  :rpc-txpool-queued-transaction-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-queued-transaction-hash))
                  :rpc-txpool-queued-raw-transaction
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-queued-raw-transaction))
                  :rpc-txpool-queued-nonce
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-queued-nonce))
                  :rpc-txpool-queued-inspect-summary
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-queued-inspect-summary))
                  :rpc-txpool-status-pending
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-status-pending))
                  :rpc-txpool-status-queued
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-status-queued))
                  :rpc-txpool-pending-block-count
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-block-count))
                  :rpc-txpool-pending-block-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-block-hash))
                  :rpc-txpool-pending-block-base-fee
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-block-base-fee))
                  :rpc-txpool-pending-header-number
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-header-number))
                  :rpc-txpool-pending-header-parent-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-header-parent-hash))
                  :rpc-txpool-pending-header-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-header-hash))
                  :rpc-txpool-pending-header-nonce
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-header-nonce))
                  :rpc-txpool-pending-header-base-fee
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-header-base-fee))
                  :rpc-txpool-pending-fee-history-next-base-fee
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-fee-history-next-base-fee))
                  :rpc-txpool-pending-sender-nonce
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-sender-nonce))
                  :rpc-txpool-pending-block-transaction-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-block-transaction-hash))
                  :rpc-txpool-pending-block-transaction-block-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-block-transaction-block-hash))
                  :rpc-txpool-pending-index-transaction-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-index-transaction-hash))
                  :rpc-txpool-pending-index-block-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-index-block-hash))
                  :rpc-txpool-pending-raw-index-transaction
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-raw-index-transaction))
                  :rpc-txpool-content-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-content-hash))
                  :rpc-txpool-content-from-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-content-from-hash))
                  :rpc-txpool-basefee-content-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-basefee-content-hash))
                  :rpc-txpool-basefee-content-from-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-basefee-content-from-hash))
                  :rpc-txpool-queued-content-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-queued-content-hash))
                  :rpc-txpool-queued-content-from-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-queued-content-from-hash))
                  :rpc-txpool-public-connections
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :public-connections))
                  :rpc-side-block-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary :side-block-hash))
                  :rpc-side-forkchoice-status
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-forkchoice-status))
                  :rpc-side-rejected-checkpoint-error
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-rejected-checkpoint-error))
                  :rpc-side-block-number
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary :side-block-number))
                  :rpc-side-latest-block-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-latest-block-hash))
                  :rpc-side-transaction-reinserted-p
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-transaction-reinserted-p))
                  :rpc-side-transaction-by-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-transaction-by-hash))
                  :rpc-side-raw-transaction
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-raw-transaction))
                  :rpc-side-pending-transaction
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-pending-transaction))
                  :rpc-side-reinserted-transaction-count
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-reinserted-transaction-count))
                  :rpc-side-reinserted-transaction-hashes
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-reinserted-transaction-hashes))
                  :rpc-side-receipt
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary :side-receipt))
                  :rpc-side-hidden-receipt-count
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-hidden-receipt-count))
                  :rpc-side-child-block-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-child-block-hash))
                  :rpc-side-block-receipts-count
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-block-receipts-count))
                  :rpc-side-log-count
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary :side-log-count))
                  :rpc-side-restored-head-number
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-head-number))
                  :rpc-side-restored-head-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-head-hash))
                  :rpc-side-restored-rpc-block-number
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-rpc-block-number))
                  :rpc-side-restored-rpc-latest-block-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-rpc-latest-block-hash))
                  :rpc-side-restored-safe-number
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-safe-number))
                  :rpc-side-restored-safe-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-safe-hash))
                  :rpc-side-restored-finalized-number
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-finalized-number))
                  :rpc-side-restored-finalized-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-finalized-hash))
                  :rpc-side-restored-rpc-safe-number
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-rpc-safe-number))
                  :rpc-side-restored-rpc-safe-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-rpc-safe-hash))
                  :rpc-side-restored-rpc-finalized-number
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-rpc-finalized-number))
                  :rpc-side-restored-rpc-finalized-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-rpc-finalized-hash))
                  :rpc-side-restored-safe-balance
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-safe-balance))
                  :rpc-side-restored-finalized-balance
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-finalized-balance))
                  :rpc-side-restored-raw-transaction
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-raw-transaction))
                  :rpc-side-restored-pending-transaction
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-pending-transaction))
                  :rpc-side-restored-reinserted-transaction-count
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-reinserted-transaction-count))
                  :rpc-side-restored-reinserted-transaction-hashes
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-reinserted-transaction-hashes))
                  :rpc-side-restored-receipt
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-receipt))
                  :rpc-side-restored-hidden-receipt-count
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-hidden-receipt-count))
                  :rpc-side-restored-child-block-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-child-block-hash))
                  :rpc-side-restored-child-require-canonical-error
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-child-require-canonical-error))
                  :rpc-side-restored-child-require-canonical-errors
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-child-require-canonical-errors))
                  :rpc-side-restored-block-receipts-count
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-block-receipts-count))
                  :rpc-side-restored-log-count
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-log-count))
                  :rpc-side-restored-public-connections
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-public-connections))
                  :rpc-side-engine-connections
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary :engine-connections))
                  :rpc-side-public-connections
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :public-connections))))))
