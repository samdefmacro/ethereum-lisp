(in-package #:ethereum-lisp.public-api)

(defun eth-rpc-block-full-transactions-param (params method)
  (unless (= 2 (length params))
    (block-validation-fail
     "~A params must contain block id and full transaction flag" method))
  (let ((full-transactions-p (second params)))
    (cond
      ((eq full-transactions-p t) t)
      ((or (null full-transactions-p)
           (json-false-p full-transactions-p))
       nil)
      (t
       (block-validation-fail
        "~A full transaction flag must be a boolean" method)))))

(defun eth-rpc-block-transactions-object
    (block full-transactions-p &key expected-chain-id config)
  ;; An existing block with no transactions serialises as [], not null.
  (eth-rpc-json-array
   (if full-transactions-p
       (loop with rules = (eth-rpc-block-signer-rules config block)
             for transaction in (block-transactions block)
             for index from 0
             collect (eth-rpc-transaction-object
                      transaction block index
                      :expected-chain-id expected-chain-id
                      :rules rules))
       (mapcar (lambda (transaction)
                 (hash32-to-hex (transaction-hash transaction)))
               (block-transactions block)))))

(defun eth-rpc-block-object
    (block full-transactions-p &key expected-chain-id config)
  "BLOCK as an RPC object. Full transactions recover `from` with BLOCK's own
signer under CONFIG (ETH-RPC-SIGNER-RULES); without CONFIG, the latest."
  (unless (typep block 'ethereum-block)
    (block-validation-fail "eth block result must be a block"))
  (append
   (eth-rpc-header-object (block-header block))
   (list
    (cons "size" (quantity-to-hex (length (eth-rpc-block-rlp block))))
    (cons "transactions"
          (eth-rpc-block-transactions-object
           block full-transactions-p
           :expected-chain-id expected-chain-id
           :config config))
    (cons "uncles"
          (eth-rpc-json-array
           (mapcar (lambda (ommer)
                     (hash32-to-hex (block-header-hash ommer)))
                   (block-ommers block)))))
   (when (block-withdrawals-present-p block)
     (list
      (cons "withdrawals"
            (eth-rpc-json-array
             (mapcar #'engine-rpc-withdrawal-object
                     (block-withdrawals block))))))))

(defun eth-rpc-pending-block-transactions-object
    (transactions full-transactions-p &key expected-chain-id rules)
  (eth-rpc-json-array
   (if full-transactions-p
       (loop for transaction in transactions
             collect (eth-rpc-pending-transaction-object
                      transaction
                      :expected-chain-id expected-chain-id
                      :rules rules))
       (mapcar (lambda (transaction)
                 (hash32-to-hex (transaction-hash transaction)))
               transactions))))

(defun eth-rpc-pending-block-object
    (pending-block transactions full-transactions-p config
     &key expected-chain-id)
  "PENDING-BLOCK as an RPC object carrying TRANSACTIONS. Their `from` is
recovered with the pending block's signer, as go-ethereum v1.17.6
RPCMarshalBlock renders a pending block's transactions
(newRPCTransactionFromBlockIndex)."
  (let ((object
          (eth-rpc-block-object
           pending-block full-transactions-p
           :expected-chain-id expected-chain-id
           :config config)))
    (eth-rpc-set-object-field object "hash" nil)
    (eth-rpc-set-object-field object "nonce" nil)
    (eth-rpc-set-object-field
     object
     "transactions"
     (eth-rpc-pending-block-transactions-object
      transactions full-transactions-p
      :expected-chain-id expected-chain-id
      :rules (eth-rpc-block-signer-rules config pending-block)))
    object))
