(in-package #:ethereum-lisp.public-api)

(defun eth-rpc-block-rlp (block)
  (unless (typep block 'ethereum-block)
    (block-validation-fail "eth block result must be a block"))
  ;; RPC's `size` is the canonical network block encoding.  In particular,
  ;; EIP-2718 transactions are RLP byte strings containing type || payload;
  ;; concatenating TRANSACTION-ENCODING directly into the transaction list
  ;; omits that string wrapper and under-counts every typed transaction.
  (block-rlp block))
