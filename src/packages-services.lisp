(defpackage #:ethereum-lisp.txpool
  (:use #:cl
        #:ethereum-lisp.bytes
        #:ethereum-lisp.hex
        #:ethereum-lisp.types
        #:ethereum-lisp.validation
        #:ethereum-lisp.chain-config
        #:ethereum-lisp.transactions
        #:ethereum-lisp.blocks
        #:ethereum-lisp.consensus
        #:ethereum-lisp.txpool.index
        #:ethereum-lisp.node-state
        #:ethereum-lisp.chain-store)
  (:export
   #:engine-payload-store-txpool
   #:engine-payload-store-queued-sender-index
   #:engine-payload-store-basefee-sender-index
   #:engine-payload-store-blob-sender-index
   #:engine-payload-store-put-pending-transaction
   #:engine-payload-store-put-queued-transaction
   #:engine-payload-store-put-basefee-transaction
   #:engine-payload-store-put-blob-transaction
   #:engine-payload-store-pending-transaction
   #:engine-payload-store-queued-transaction
   #:engine-payload-store-basefee-transaction
   #:engine-payload-store-blob-transaction
   #:engine-payload-store-pooled-transaction
   #:engine-payload-store-pending-transactions
   #:engine-payload-store-queued-transactions
   #:engine-payload-store-basefee-transactions
   #:engine-payload-store-blob-transactions
   #:engine-payload-store-pooled-transactions
   #:engine-payload-store-pending-transactions-by-sender
   #:engine-payload-store-pending-sender-transactions
   #:engine-payload-store-pending-contiguous-nonce
   #:engine-payload-store-pending-transaction-count
   #:engine-payload-store-queued-transaction-count
   #:engine-payload-store-basefee-transaction-count
   #:engine-payload-store-blob-transaction-count
   #:engine-payload-store-pending-mining-transactions
   #:engine-select-mining-transactions
   #:engine-payload-store-txpool-upfront-cost
   #:engine-payload-store-sender-admission-expenditure
   #:engine-payload-store-validate-txpool-blob-fee-cap
   #:engine-payload-store-promote-queued-transactions
   #:engine-payload-store-promote-basefee-transactions
   #:engine-payload-store-promote-basefee-and-queued-transactions
   #:engine-payload-store-prune-overbudget-parked-transactions
   #:engine-payload-store-remove-expired-txpool-queued-view-transactions
   #:engine-payload-store-remove-new-head-invalid-txpool-transactions
   #:engine-payload-store-revalidate-pending-transactions
   #:engine-payload-store-reinsert-displaced-block-transactions))

(defpackage #:ethereum-lisp.canonical-chain
  (:use #:cl
        #:ethereum-lisp.types
        #:ethereum-lisp.validation
        #:ethereum-lisp.chain-config
        #:ethereum-lisp.blocks
        #:ethereum-lisp.chain-store.model
        #:ethereum-lisp.node-state
        #:ethereum-lisp.chain-store
        #:ethereum-lisp.txpool)
  (:export
   #:chain-store-set-canonical-head))

(defpackage #:ethereum-lisp.engine
  (:use #:cl
        #:ethereum-lisp.types
        #:ethereum-lisp.validation
        #:ethereum-lisp.chain-config
        #:ethereum-lisp.transactions
        #:ethereum-lisp.blocks
        #:ethereum-lisp.consensus
        #:ethereum-lisp.engine-payloads
        #:ethereum-lisp.chain-store.model
        #:ethereum-lisp.node-state
        #:ethereum-lisp.chain-store)
  (:export
   #:engine-payload-store-invalid-ancestor-status
   #:engine-forkchoice-checkpoint-error-message
   #:engine-forkchoice-checkpoint-order-error-message
   #:engine-forkchoice-memory-status
   #:engine-new-payload-memory-status))
