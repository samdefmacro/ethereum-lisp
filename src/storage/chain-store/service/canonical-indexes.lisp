(in-package #:ethereum-lisp.chain-store)

(defun engine-payload-store-canonical-parent-p (store block)
  (setf store (chain-store-require-memory-store store))
  (let* ((header (block-header block))
         (number (block-header-number header))
         (parent-hash (block-header-parent-hash header))
         (parent-block
           (and parent-hash
                (engine-payload-store-known-block store parent-hash))))
    (or (zerop number)
        (null parent-hash)
        (hash32= parent-hash (zero-hash32))
        (null parent-block)
        (/= (block-header-number (block-header parent-block))
            (1- number))
        (let ((canonical-parent
                (engine-payload-store-canonical-hash store (1- number))))
          (and canonical-parent
               (hash32= canonical-parent parent-hash))))))

(defun engine-payload-store-block-by-number (store number)
  (setf store (chain-store-require-memory-store store))
  (unless (and (integerp number) (not (minusp number)))
    (block-validation-fail "Engine payload store block number must be non-negative"))
  (let ((canonical-hash
          (engine-payload-store-canonical-hash store number)))
    (and canonical-hash
         (engine-payload-store-known-block store canonical-hash))))

(defun engine-payload-store-canonical-hash (store number)
  (setf store (chain-store-require-memory-store store))
  (unless (and (integerp number) (not (minusp number)))
    (block-validation-fail
     "Engine payload store canonical block number must be non-negative"))
  (let ((hashes (memory-chain-store-canonical-hashes store)))
    (multiple-value-bind (canonical-key cached-p) (gethash number hashes)
      (cond
        (cached-p
         (and canonical-key (hash32-from-hex canonical-key)))
        (t
         (multiple-value-bind (persisted persisted-p)
             (chain-store-backing-canonical-hash store number)
           (when persisted-p
             (unless (hash32-p persisted)
               (storage-fail
                "Durable canonical index does not contain a hash32"))
             (when (chain-store-cache-backing-read-p store)
               (setf (gethash number hashes)
                     (engine-payload-store-key persisted)))
             persisted)))))))

(defun engine-payload-store-canonical-block-p (store block)
  (setf store (chain-store-require-memory-store store))
  (let* ((header (block-header block))
         (number (block-header-number header))
         (canonical-hash
           (and (integerp number)
                (not (minusp number))
                (engine-payload-store-canonical-hash store number))))
    (and canonical-hash
         (hash32= canonical-hash (block-hash block)))))

(defun engine-payload-store-ancestor-p (store ancestor-hash head-hash)
  (setf store (chain-store-require-memory-store store))
  (cond
    ((hash32= ancestor-hash head-hash) t)
    ((or (hash32= ancestor-hash (zero-hash32))
         (hash32= head-hash (zero-hash32)))
     nil)
    (t
     (let ((ancestor-block
             (engine-payload-store-known-block store ancestor-hash))
           (current
             (engine-payload-store-known-block store head-hash)))
       (when (and ancestor-block current)
         (let ((ancestor-number
                 (block-header-number (block-header ancestor-block))))
           (loop
             (let* ((header (block-header current))
                    (number (block-header-number header)))
               (cond
                 ((< number ancestor-number)
                  (return nil))
                 ((and (= number ancestor-number)
                       (hash32= (block-hash current) ancestor-hash))
                  (return t))
                 ((zerop number)
                  (return nil))
                 (t
                  (let* ((parent-hash (block-header-parent-hash header))
                         (parent-block
                           (and parent-hash
                                (engine-payload-store-known-block
                                 store parent-hash))))
                    (unless parent-block
                      (return nil))
                    (setf current parent-block))))))))))))
