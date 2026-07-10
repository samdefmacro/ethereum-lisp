(in-package #:ethereum-lisp.core)

(defconstant +engine-rpc-max-payload-bodies-request+ 1024)
(defconstant +engine-rpc-max-get-blobs-request+ 128)

(defun engine-rpc-get-blob-hashes-param (params method)
  (unless (and (listp params) params)
    (block-validation-fail
     "~A params must include blob versioned hashes" method))
  (engine-rpc-hash32-list
   (engine-rpc-required-param
    params 0 "blobVersionedHashes" method)
   "blobVersionedHashes"))

(defun engine-rpc-validate-get-blobs-request-size (hashes)
  (when (> (length hashes) +engine-rpc-max-get-blobs-request+)
    (engine-rpc-fail
     +engine-rpc-error-too-large-request+
     "The number of requested blobs must not exceed 128")))

(defun engine-rpc-handle-get-blobs-v1 (params store)
  (let ((hashes
          (engine-rpc-get-blob-hashes-param
           params "engine_getBlobsV1")))
    (engine-rpc-validate-get-blobs-request-size hashes)
    (mapcar (lambda (versioned-hash)
              (let ((blob-and-proofs
                      (engine-payload-store-blob-and-proofs-v1
                       store versioned-hash)))
                (when blob-and-proofs
                  (engine-rpc-blob-and-proof-v1-object blob-and-proofs))))
            hashes)))

(defun engine-rpc-handle-get-blobs-v2 (params store)
  (let* ((hashes
           (engine-rpc-get-blob-hashes-param
            params "engine_getBlobsV2"))
         (blobs
           (progn
             (engine-rpc-validate-get-blobs-request-size hashes)
             (mapcar (lambda (versioned-hash)
                       (engine-payload-store-blob-and-proofs-v2
                        store versioned-hash))
                     hashes))))
    (if (some #'null blobs)
        nil
        (mapcar #'engine-rpc-blob-and-proof-v2-object blobs))))

(defun engine-rpc-handle-get-blobs-v3 (params store)
  (let ((hashes
          (engine-rpc-get-blob-hashes-param
           params "engine_getBlobsV3")))
    (engine-rpc-validate-get-blobs-request-size hashes)
    (mapcar (lambda (versioned-hash)
              (let ((blob-and-proofs
                      (engine-payload-store-blob-and-proofs-v2
                       store versioned-hash)))
                (when blob-and-proofs
                  (engine-rpc-blob-and-proof-v2-object blob-and-proofs))))
            hashes)))

(defun engine-rpc-handle-get-payload-bodies-by-hash
    (params store method body-object-function)
  (unless (and (listp params) params)
    (block-validation-fail
     "~A params must include block hashes" method))
  (let ((hashes
          (engine-rpc-hash32-list
           (engine-rpc-required-param
            params 0 "blockHashes" method)
           "blockHashes")))
    (when (> (length hashes) +engine-rpc-max-payload-bodies-request+)
      (engine-rpc-fail
       +engine-rpc-error-too-large-request+
       "The number of requested bodies must not exceed 1024"))
    (mapcar (lambda (hash)
              (let ((block (chain-store-known-block store hash)))
                (when block
                  (funcall body-object-function block))))
            hashes)))

(defun engine-rpc-handle-get-payload-bodies-by-hash-v1 (params store)
  (engine-rpc-handle-get-payload-bodies-by-hash
   params store "engine_getPayloadBodiesByHashV1"
   #'engine-rpc-payload-body-v1-object))

(defun engine-rpc-handle-get-payload-bodies-by-hash-v2 (params store)
  (engine-rpc-handle-get-payload-bodies-by-hash
   params store "engine_getPayloadBodiesByHashV2"
   #'engine-rpc-payload-body-v2-object))

(defun engine-rpc-quantity-param (params index label method)
  (parse-json-quantity
   (engine-rpc-required-param params index label method)
   label
   :required-p t))

(defun engine-rpc-handle-get-payload-bodies-by-range
    (params store method body-object-function)
  (unless (and (listp params) params)
    (block-validation-fail
     "~A params must include start and count" method))
  (let ((start (engine-rpc-quantity-param
                params 0 "start" method))
        (count (engine-rpc-quantity-param
                params 1 "count" method)))
    (unless (and (plusp start) (plusp count))
      (block-validation-fail "start and count must be positive numbers"))
    (when (> count +engine-rpc-max-payload-bodies-request+)
      (engine-rpc-fail
       +engine-rpc-error-too-large-request+
       "The number of requested bodies must not exceed 1024"))
    (let* ((head (chain-store-head-number store))
           (last (min (+ start count -1) head)))
      (if (< last start)
          '()
          (loop for number from start to last
                collect
                (let ((block (chain-store-block-by-number store number)))
                  (when block
                    (funcall body-object-function block))))))))

(defun engine-rpc-handle-get-payload-bodies-by-range-v1 (params store)
  (engine-rpc-handle-get-payload-bodies-by-range
   params store "engine_getPayloadBodiesByRangeV1"
   #'engine-rpc-payload-body-v1-object))

(defun engine-rpc-handle-get-payload-bodies-by-range-v2 (params store)
  (engine-rpc-handle-get-payload-bodies-by-range
   params store "engine_getPayloadBodiesByRangeV2"
   #'engine-rpc-payload-body-v2-object))
