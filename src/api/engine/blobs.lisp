(in-package #:ethereum-lisp.engine-api)

(defconstant +engine-rpc-max-payload-bodies-request+ 1024)
(defconstant +engine-rpc-max-get-blobs-request+ 128)

(defun engine-rpc-get-blob-hashes-param (params method)
  (unless (and (listp params) params)
    (block-validation-fail
     "~A params must include blob versioned hashes" method))
  (json-rpc-hash32-list
   (json-rpc-required-param
    params 0 "blobVersionedHashes" method)
   "blobVersionedHashes"))

(defun engine-rpc-validate-get-blobs-request-size (hashes)
  (when (> (length hashes) +engine-rpc-max-get-blobs-request+)
    (engine-rpc-fail
     +engine-rpc-error-too-large-request+
     "The number of requested blobs must not exceed 128")))

(defun engine-rpc-get-blobs-osaka-p (store config)
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head))))
    (chain-config-osaka-p
     config
     (if header (block-header-number header) 0)
     (if header (block-header-timestamp header) 0))))

(defun engine-rpc-handle-get-blobs-v1 (params store config)
  (when (engine-rpc-get-blobs-osaka-p store config)
    (engine-rpc-fail +engine-rpc-error-unsupported-fork+
                     "engine_getBlobsV1 is unsupported after Osaka"))
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

(defun engine-rpc-handle-get-blobs-v2 (params store config)
  (unless (engine-rpc-get-blobs-osaka-p store config)
    (return-from engine-rpc-handle-get-blobs-v2 nil))
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

(defun engine-rpc-handle-get-blobs-v3 (params store config)
  (unless (engine-rpc-get-blobs-osaka-p store config)
    (return-from engine-rpc-handle-get-blobs-v3 nil))
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

(defun engine-rpc-get-blobs-indices-bitmap-param (params method)
  (let ((bitmap
          (json-rpc-bytes
           (json-rpc-required-param params 1 "indices_bitarray" method)
           "indices_bitarray")))
    (unless (= 16 (length bitmap))
      (block-validation-fail
       "~A indices_bitarray must be 16 bytes" method))
    bitmap))

(defun engine-rpc-custody-bitmap-indices (bitmap)
  (loop for byte across bitmap
        for byte-index from 0
        append
        (loop for bit below 8
              when (logbitp bit byte)
                collect (+ (* byte-index 8) bit))))

(defun engine-rpc-handle-get-blobs-v4 (params store config)
  (unless (engine-rpc-get-blobs-osaka-p store config)
    (return-from engine-rpc-handle-get-blobs-v4 nil))
  (let* ((method "engine_getBlobsV4")
         (hashes (engine-rpc-get-blob-hashes-param params method))
         (bitmap (engine-rpc-get-blobs-indices-bitmap-param params method))
         (indices (engine-rpc-custody-bitmap-indices bitmap)))
    (engine-rpc-validate-get-blobs-request-size hashes)
    (mapcar
     (lambda (versioned-hash)
       (let ((blob-and-proofs
               (engine-payload-store-blob-and-proofs-v1
                store versioned-hash)))
         (when blob-and-proofs
           (multiple-value-bind (cells proofs)
               (kzg-compute-cells-and-proofs
                (engine-blob-and-proofs-blob blob-and-proofs))
             (engine-rpc-blob-cells-and-proofs-v1-object
              (mapcar (lambda (index) (nth index cells)) indices)
              (mapcar (lambda (index) (nth index proofs)) indices))))))
     hashes)))

(defun engine-rpc-handle-has-blobs (params store)
  (let* ((method "engine_hasBlobs")
         (hashes (engine-rpc-get-blob-hashes-param params method)))
    (engine-rpc-validate-get-blobs-request-size hashes)
    (mapcar
     (lambda (versioned-hash)
       (if (engine-payload-store-blob-and-proofs-v1 store versioned-hash)
           t
           :false))
     hashes)))

(defun engine-rpc-handle-get-payload-bodies-by-hash
    (params store method body-object-function)
  (unless (and (listp params) params)
    (block-validation-fail
     "~A params must include block hashes" method))
  (let ((hashes
          (json-rpc-hash32-list
           (json-rpc-required-param
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

(defun engine-rpc-handle-get-payload-bodies-by-range
    (params store method body-object-function)
  (unless (and (listp params) params)
    (block-validation-fail
     "~A params must include start and count" method))
  (let ((start (json-rpc-quantity-param
                params 0 "start" method))
        (count (json-rpc-quantity-param
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
