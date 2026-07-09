(in-package #:ethereum-lisp.execution)

(defun make-message-evm-context
    (state sender tx address input gas-price
     &key (base-fee 0)
          (blob-base-fee 0)
          (chain-id 0)
          chain-rules
          chain-config
          (coinbase (zero-address))
          (timestamp 0)
          (block-number 0)
          (prev-randao (zero-hash32))
          (difficulty 0)
          (random-p t)
          (context-gas-limit 0))
  (let ((effective-chain-rules
          (execution-chain-rules chain-rules chain-config block-number timestamp)))
    (make-evm-context
     :state state
     :address address
     :caller sender
     :origin sender
     :call-value (transaction-value tx)
     :input input
     :gas-price gas-price
     :coinbase coinbase
     :timestamp timestamp
     :block-number block-number
     :prev-randao prev-randao
     :difficulty difficulty
     :random-p random-p
     :gas-limit context-gas-limit
     :chain-id chain-id
     :chain-rules effective-chain-rules
     :base-fee base-fee
     :blob-hashes (transaction-blob-versioned-hashes tx)
     :blob-base-fee blob-base-fee
     :accessed-storage (transaction-accessed-storage-table tx)
     :accessed-addresses
     (transaction-accessed-addresses-table tx
                                           :sender sender
                                           :destination address
                                           :coinbase coinbase
                                           :chain-rules effective-chain-rules))))
