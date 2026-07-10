(in-package #:ethereum-lisp.public-api)

(defun eth-rpc-block-full-transactions-param (params method)
  (unless (= 2 (length params))
    (block-validation-fail
     "~A params must contain block id and full transaction flag" method))
  (let ((full-transactions-p (second params)))
    (unless (or (null full-transactions-p)
                (eq full-transactions-p t))
      (block-validation-fail
       "~A full transaction flag must be a boolean" method))
    full-transactions-p))

(defun eth-rpc-block-transactions-object
    (block full-transactions-p &key expected-chain-id)
  (if full-transactions-p
      (loop for transaction in (block-transactions block)
            for index from 0
            collect (eth-rpc-transaction-object
                     transaction block index
                     :expected-chain-id expected-chain-id))
      (mapcar (lambda (transaction)
                (hash32-to-hex (transaction-hash transaction)))
              (block-transactions block))))

(defun eth-rpc-block-object (block full-transactions-p &key expected-chain-id)
  (unless (typep block 'ethereum-block)
    (block-validation-fail "eth block result must be a block"))
  (append
   (eth-rpc-header-object (block-header block))
   (list
    (cons "size" (quantity-to-hex (length (eth-rpc-block-rlp block))))
    (cons "transactions"
          (eth-rpc-block-transactions-object
           block full-transactions-p
           :expected-chain-id expected-chain-id))
    (cons "uncles"
          (mapcar (lambda (ommer)
                    (hash32-to-hex (block-header-hash ommer)))
                  (block-ommers block))))
   (when (block-withdrawals-present-p block)
     (list
      (cons "withdrawals"
            (mapcar #'engine-rpc-withdrawal-object
                    (block-withdrawals block)))))))

(defun eth-rpc-pending-block-transactions-object
    (transactions full-transactions-p &key expected-chain-id)
  (eth-rpc-json-array
   (if full-transactions-p
       (loop for transaction in transactions
             collect (eth-rpc-pending-transaction-object
                      transaction
                      :expected-chain-id expected-chain-id))
       (mapcar (lambda (transaction)
                 (hash32-to-hex (transaction-hash transaction)))
               transactions))))

(defun eth-rpc-pending-block-object
    (base-block transactions full-transactions-p config &key expected-chain-id)
  (let ((object
          (eth-rpc-block-object
           base-block full-transactions-p
           :expected-chain-id expected-chain-id)))
    (eth-rpc-set-object-field object "number"
                              (quantity-to-hex
                               (1+ (block-header-number
                                    (block-header base-block)))))
    (eth-rpc-set-object-field object "parentHash"
                              (hash32-to-hex
                               (block-hash base-block)))
    (eth-rpc-set-object-field object "hash" nil)
    (eth-rpc-set-object-field object "nonce" nil)
    (let ((base-fee
            (eth-rpc-pending-base-fee (block-header base-block) config)))
      (when base-fee
        (eth-rpc-set-object-field object "baseFeePerGas" base-fee)))
    (eth-rpc-set-object-field
     object
     "transactions"
     (eth-rpc-pending-block-transactions-object
      transactions full-transactions-p
      :expected-chain-id expected-chain-id))
    object))
