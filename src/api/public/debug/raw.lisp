(in-package #:ethereum-lisp.public-api)

;;;; debug_getRaw* — canonical RLP encodings of stored chain data.
;;;;
;;;; These return exactly the bytes that were hashed and gossiped, so tooling
;;;; and conformance harnesses can compare a node's encoding against a reference
;;;; client's without going through the JSON object shapes.

(defun eth-rpc-debug-block-param (params store method)
  "Resolve a blockNrOrHash parameter to a stored block."
  (let ((block (eth-rpc-block-param params store method)))
    (unless block
      (block-validation-fail "~A block is not available" method))
    block))

(defun engine-rpc-handle-debug-get-raw-header (params store)
  (let ((block (eth-rpc-debug-block-param params store "debug_getRawHeader")))
    (bytes-to-hex (block-header-rlp (block-header block)))))

(defun engine-rpc-handle-debug-get-raw-block (params store)
  (let ((block (eth-rpc-debug-block-param params store "debug_getRawBlock")))
    (bytes-to-hex (block-rlp block))))

(defun engine-rpc-handle-debug-get-raw-receipts (params store)
  "Return the consensus-encoded receipts of a block, in block order.

A receipt for an EIP-2718 typed transaction is encoded as type || rlp, so the
type prefix has to come from the paired transaction; the bare RLP body would not
match what other clients hash and serve."
  (let* ((block (eth-rpc-debug-block-param params store "debug_getRawReceipts"))
         (transactions (block-transactions block))
         (receipts (block-receipts block)))
    (unless (= (length transactions) (length receipts))
      (block-validation-fail "debug_getRawReceipts block receipts are unavailable"))
    (eth-rpc-json-array
     (loop for transaction in transactions
           for receipt in receipts
           collect (bytes-to-hex
                    (transaction-receipt-encoding transaction receipt))))))

(defun engine-rpc-handle-debug-get-raw-transaction (params store config)
  "Return the consensus encoding of a transaction by hash.

go-ethereum exposes the same value as eth_getRawTransactionByHash; both consult
the canonical chain first and then the pool."
  (let* ((hash (eth-rpc-hash-param
                params "debug_getRawTransaction" "transaction hash"))
         (location (chain-store-transaction-location store hash)))
    (or (eth-rpc-raw-transaction-from-location
         location
         :expected-chain-id (chain-config-chain-id config))
        (eth-rpc-pooled-raw-transaction
         (engine-payload-store-pooled-transaction store hash)
         (chain-config-chain-id config)))))
