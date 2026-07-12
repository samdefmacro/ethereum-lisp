(in-package #:ethereum-lisp.node-store.persistence)

(defun chain-store-import-invalid-tipset-from-kv
    (store tipset-identifier record)
  (setf store (chain-store-require-memory-store store))
  (handler-case
      (let ((tipset-hash (make-hash32 tipset-identifier))
            (invalid-block (block-from-rlp record)))
        (unless (hash32= tipset-hash (block-hash invalid-block))
          (block-validation-fail
           "KV invalid-tipset record key does not match encoded block hash"))
        (when (chain-store-known-block store tipset-hash)
          (block-validation-fail
           "KV invalid-tipset record duplicates a known block"))
        (setf (gethash
               (engine-payload-store-key tipset-hash)
               (memory-chain-store-invalid-tipsets store))
              invalid-block))
    (rlp-error (condition)
      (block-validation-fail
       "Invalid KV invalid-tipset record RLP: ~A" condition))))

(defun chain-store-import-invalid-tipsets-from-kv (store database)
  (dolist (entry (kv-chain-record-entries database :invalid-tipset))
    (chain-store-import-invalid-tipset-from-kv
     store (car entry) (cdr entry))))

(defun chain-store-import-remote-block-from-kv
    (store block-identifier record)
  (setf store (chain-store-require-memory-store store))
  (handler-case
      (let* ((block-hash (make-hash32 block-identifier))
             (block (block-from-rlp record)))
        (unless (hash32= block-hash (block-hash block))
          (block-validation-fail
           "KV remote-block record key does not match encoded block hash"))
        (unless (or (chain-store-known-block store block-hash)
                    (engine-payload-store-invalid-block store block-hash))
          (setf (gethash
                 (engine-payload-store-key block-hash)
                 (memory-chain-store-remote-blocks store))
                block)))
    (rlp-error (condition)
      (block-validation-fail
       "Invalid KV remote-block record RLP: ~A" condition))))

(defun chain-store-import-remote-blocks-from-kv (store database)
  (dolist (entry (kv-chain-record-entries database :remote-block))
    (chain-store-import-remote-block-from-kv
     store (car entry) (cdr entry))))
