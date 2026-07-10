(in-package #:ethereum-lisp.chain-store)

(defun engine-payload-store-remote-block
    (store hash)
  (engine-payload-store-copy-block
   (gethash (engine-payload-store-key hash)
            (engine-payload-memory-store-remote-blocks store))))

(defun engine-payload-store-put-remote-block
    (store block)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep block 'ethereum-block)
    (block-validation-fail "Engine remote block cache value must be a block"))
  (setf (gethash (engine-payload-store-key (block-hash block))
                 (engine-payload-memory-store-remote-blocks store))
        (engine-payload-store-copy-block block))
  block)

(defun engine-payload-store-remove-remote-block
    (store hash)
  (remhash (engine-payload-store-key hash)
           (engine-payload-memory-store-remote-blocks store)))

(defun engine-payload-store-prune-prepared-payloads-for-block
    (store block-key)
  (let ((stale-payload-id-keys nil))
    (maphash
     (lambda (payload-id-key prepared-payload)
       (when (string= block-key
                      (engine-payload-store-key
                       (block-hash
                        (engine-prepared-payload-block prepared-payload))))
         (push payload-id-key stale-payload-id-keys)))
     (engine-payload-memory-store-prepared-payloads store))
    (dolist (payload-id-key stale-payload-id-keys)
      (remhash payload-id-key
               (engine-payload-memory-store-prepared-payloads store)))))

(defun engine-payload-store-mark-invalid
    (store invalid-block &key head-hash)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep invalid-block 'ethereum-block)
    (block-validation-fail "Engine payload invalid marker must be a block"))
  (let* ((invalid-hash (block-hash invalid-block))
         (key (engine-payload-store-key (or head-hash invalid-hash))))
    (engine-payload-store-remove-remote-block store invalid-hash)
    (engine-payload-store-prune-prepared-payloads-for-block
     store
     (engine-payload-store-key invalid-hash))
    (when head-hash
      (engine-payload-store-remove-remote-block store head-hash)
      (engine-payload-store-prune-prepared-payloads-for-block store key))
    (setf (gethash key (engine-payload-memory-store-invalid-tipsets store))
          (engine-payload-store-copy-block invalid-block))
    invalid-block))

(defun engine-payload-store-invalid-block
    (store hash)
  (engine-payload-store-copy-block
   (gethash (engine-payload-store-key hash)
            (engine-payload-memory-store-invalid-tipsets store))))

(defun engine-payload-id-key (payload-id)
  (let ((bytes (ensure-byte-vector payload-id)))
    (unless (= 8 (length bytes))
      (block-validation-fail "Engine payload id must be 8 bytes"))
    (bytes-to-hex bytes)))

(defun engine-payload-id-to-hex (payload-id)
  (engine-payload-id-key payload-id))

(defun engine-payload-store-put-prepared-payload
    (store prepared-payload)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (validate-engine-prepared-payload prepared-payload)
  (let ((stored-payload
          (engine-payload-store-copy-prepared-payload prepared-payload)))
    (setf (gethash
           (engine-payload-id-key
            (engine-prepared-payload-payload-id stored-payload))
           (engine-payload-memory-store-prepared-payloads store))
          stored-payload))
  prepared-payload)

(defun engine-payload-store-prepared-payload (store payload-id)
  (engine-payload-store-copy-prepared-payload
   (gethash (engine-payload-id-key payload-id)
            (engine-payload-memory-store-prepared-payloads store))))

(defun chain-store-put-prepared-payload (store prepared-payload)
  (engine-payload-store-put-prepared-payload
   (chain-store-require-memory-store store)
   prepared-payload))

(defun chain-store-prepared-payload (store payload-id)
  (engine-payload-store-prepared-payload
   (chain-store-require-memory-store store)
   payload-id))

(defun engine-payload-store-put-blob-sidecar
    (store sidecar)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep sidecar 'blob-sidecar)
    (block-validation-fail
     "Engine blob sidecar store value must be a blob sidecar"))
  (let ((hashes (blob-sidecar-versioned-hashes sidecar))
        (blobs (blob-sidecar-blobs sidecar))
        (proofs (blob-sidecar-proofs sidecar)))
    (unless (= (length hashes) (length blobs))
      (block-validation-fail
       "Engine blob sidecar blobs and commitments must have matching lengths"))
    (unless (or (= (length proofs) (length blobs))
                (= (length proofs)
                   (* (length blobs) +cell-proofs-per-blob+)))
      (block-validation-fail
       "Engine blob sidecar proofs must be one per blob or cell proofs per blob"))
    (loop for versioned-hash in hashes
          for blob in blobs
          for index from 0
          for proof = (if (= (length proofs) (length blobs))
                          (nth index proofs)
                          (nth (* index +cell-proofs-per-blob+) proofs))
          for cell-proofs = (when (= (length proofs)
                                     (* (length blobs)
                                        +cell-proofs-per-blob+))
                              (subseq proofs
                                      (* index +cell-proofs-per-blob+)
                                      (* (1+ index)
                                         +cell-proofs-per-blob+)))
          do (setf (gethash
                    (engine-payload-store-key versioned-hash)
                    (engine-payload-memory-store-blob-sidecars store))
                   (make-engine-blob-and-proofs
                    :blob (maybe-copy-bytes blob)
                    :commitment
                    (maybe-copy-bytes
                     (nth index (blob-sidecar-commitments sidecar)))
                    :proof (maybe-copy-bytes proof)
                    :cell-proofs (mapcar #'maybe-copy-bytes
                                         cell-proofs)))))
  sidecar)

(defun engine-payload-store-blob-and-proofs-v1
    (store versioned-hash)
  (engine-payload-store-copy-blob-and-proofs
   (gethash (engine-payload-store-key versioned-hash)
            (engine-payload-memory-store-blob-sidecars store))))

(defun engine-payload-store-blob-and-proofs-v2
    (store versioned-hash)
  (let ((blob-and-proofs
          (engine-payload-store-blob-and-proofs-v1 store versioned-hash)))
    (when (and blob-and-proofs
               (= +cell-proofs-per-blob+
                  (length
                   (engine-blob-and-proofs-cell-proofs blob-and-proofs))))
      blob-and-proofs)))
