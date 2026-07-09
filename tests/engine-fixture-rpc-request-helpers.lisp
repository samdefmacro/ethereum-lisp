(in-package #:ethereum-lisp.test)

(defun engine-fixture-balance-request (id address)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getBalance")
        (cons "params" (list (address-to-hex address) "latest"))))

(defun engine-fixture-code-request (id address)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getCode")
        (cons "params" (list (address-to-hex address) "latest"))))

(defun engine-fixture-storage-request (id address slot)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getStorageAt")
        (cons "params"
              (list (address-to-hex address)
                    (hash32-to-hex slot)
                    "latest"))))

(defun engine-fixture-proof-request
    (id address &key (storage-keys '()) (block-selector "latest"))
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getProof")
        (cons "params"
              (list (address-to-hex address)
                    (mapcar #'hash32-to-hex storage-keys)
                    block-selector))))

(defun engine-fixture-block-by-number-request (id tag full-transactions-p)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getBlockByNumber")
        (cons "params" (list tag full-transactions-p))))

(defun engine-fixture-block-by-hash-request (id hash full-transactions-p)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getBlockByHash")
        (cons "params" (list (hash32-to-hex hash) full-transactions-p))))

(defun engine-fixture-transaction-count-by-number-request (id tag)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getBlockTransactionCountByNumber")
        (cons "params" (list tag))))

(defun engine-fixture-transaction-count-by-hash-request (id hash)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getBlockTransactionCountByHash")
        (cons "params" (list (hash32-to-hex hash)))))

(defun engine-fixture-raw-transaction-by-block-number-request (id tag index)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getRawTransactionByBlockNumberAndIndex")
        (cons "params" (list tag (quantity-to-hex index)))))

(defun engine-fixture-transaction-by-block-hash-request (id hash index)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getTransactionByBlockHashAndIndex")
        (cons "params" (list (hash32-to-hex hash) (quantity-to-hex index)))))

(defun engine-fixture-transaction-by-hash-request (id hash)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getTransactionByHash")
        (cons "params" (list (hash32-to-hex hash)))))

(defun engine-fixture-receipt-request (id hash)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getTransactionReceipt")
        (cons "params" (list (hash32-to-hex hash)))))

(defun engine-fixture-block-receipts-request (id tag)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getBlockReceipts")
        (cons "params" (list tag))))

