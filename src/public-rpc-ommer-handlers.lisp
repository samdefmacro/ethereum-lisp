(in-package #:ethereum-lisp.core)

(defun eth-rpc-block-ommer-count (block)
  (when block
    (quantity-to-hex (length (block-ommers block)))))

(defun eth-rpc-ommer-object (header)
  (when header
    (let ((block (make-block :header header)))
      (append
       (eth-rpc-header-object header)
       (list
        (cons "size" (quantity-to-hex (length (eth-rpc-block-rlp block))))
        (cons "uncles" '()))))))

(defun eth-rpc-ommer-by-index (block index)
  (when (and block (< index (length (block-ommers block))))
    (eth-rpc-ommer-object (nth index (block-ommers block)))))

(defun engine-rpc-handle-eth-get-uncle-count-by-number (params store)
  (unless (= 1 (length params))
    (block-validation-fail
     "eth_getUncleCountByBlockNumber params must contain exactly one block number"))
  (if (eth-rpc-pending-block-tag-p (first params))
      (quantity-to-hex 0)
      (let* ((number (eth-rpc-block-number-param
                      params store "eth_getUncleCountByBlockNumber"))
             (block (chain-store-block-by-number store number)))
        (eth-rpc-block-ommer-count block))))

(defun engine-rpc-handle-eth-get-uncle-count-by-hash (params store)
  (let* ((hash (eth-rpc-hash-param
                params "eth_getUncleCountByBlockHash" "block hash"))
         (block (chain-store-known-block store hash)))
    (eth-rpc-block-ommer-count block)))

(defun engine-rpc-handle-eth-get-uncle-by-block-number-and-index
    (params store)
  (unless (= 2 (length params))
    (block-validation-fail
     "eth_getUncleByBlockNumberAndIndex params must contain block id and uncle index"))
  (if (eth-rpc-pending-block-tag-p (first params))
      (progn
        (json-rpc-quantity-param
         params 1 "uncle index" "eth_getUncleByBlockNumberAndIndex")
        nil)
      (let* ((number (eth-rpc-block-number-param
                      (list (first params)) store
                      "eth_getUncleByBlockNumberAndIndex"))
             (index (json-rpc-quantity-param
                     params 1 "uncle index"
                     "eth_getUncleByBlockNumberAndIndex"))
             (block (chain-store-block-by-number store number)))
        (eth-rpc-ommer-by-index block index))))

(defun engine-rpc-handle-eth-get-uncle-by-block-hash-and-index
    (params store)
  (unless (= 2 (length params))
    (block-validation-fail
     "eth_getUncleByBlockHashAndIndex params must contain block id and uncle index"))
  (let* ((hash (eth-rpc-hash-param
                (list (first params))
                "eth_getUncleByBlockHashAndIndex"
                "block hash"))
         (index (json-rpc-quantity-param
                 params 1 "uncle index"
                 "eth_getUncleByBlockHashAndIndex"))
         (block (chain-store-known-block store hash)))
    (eth-rpc-ommer-by-index block index)))
