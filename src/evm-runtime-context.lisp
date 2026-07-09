(in-package #:ethereum-lisp.evm)

(defun make-child-evm-context (parent
                               &key state address caller call-value input
                                    read-only-p)
  (make-evm-context
   :state state
   :address address
   :caller caller
   :origin (evm-context-origin parent)
   :call-value call-value
   :gas-price (evm-context-gas-price parent)
   :input input
   :coinbase (evm-context-coinbase parent)
   :timestamp (evm-context-timestamp parent)
   :block-number (evm-context-block-number parent)
   :prev-randao (evm-context-prev-randao parent)
   :difficulty (evm-context-difficulty parent)
   :random-p (evm-context-random-p parent)
   :gas-limit (evm-context-gas-limit parent)
   :chain-id (evm-context-chain-id parent)
   :chain-rules (evm-context-chain-rules parent)
   :base-fee (evm-context-base-fee parent)
   :blob-hashes (evm-context-blob-hashes parent)
   :blob-base-fee (evm-context-blob-base-fee parent)
   :transient-storage (evm-context-transient-storage parent)
   :storage-originals (evm-context-storage-originals parent)
   :storage-clears (evm-context-storage-clears parent)
   :selfdestructed-addresses (evm-context-selfdestructed-addresses parent)
   :accessed-storage (evm-context-accessed-storage parent)
   :accessed-addresses (evm-context-accessed-addresses parent)
   :block-hashes (evm-context-block-hashes parent)
   :read-only-p read-only-p))
