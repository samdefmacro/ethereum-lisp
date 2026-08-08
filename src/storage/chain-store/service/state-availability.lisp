(in-package #:ethereum-lisp.chain-store)

(declaim (ftype (function (t t) t) chain-store-state-root))

(defun engine-payload-store-state-available-p
    (store hash)
  (setf store (chain-store-require-memory-store store))
  (or (not (null
            (gethash (engine-payload-store-key hash)
                     (memory-chain-store-state-blocks store))))
      (not (null (chain-store-state-root store hash)))))

(defun chain-store-state-root (store hash)
  "Return HASH's persisted account-trie root, point-reading backing on miss."
  (setf store (chain-store-require-memory-store store))
  (unless (hash32-p hash)
    (block-validation-fail "Chain state root lookup requires a hash32"))
  (let* ((key (engine-payload-store-key hash))
         (roots (memory-chain-store-state-roots store)))
    (multiple-value-bind (root cached-p) (gethash key roots)
      (if cached-p
          root
          (multiple-value-bind (persisted present-p)
              (chain-store-backing-state-root store hash)
            (when present-p
              (unless (hash32-p persisted)
                (block-validation-fail
                 "Durable chain state root is not a hash32"))
              (when (chain-store-cache-backing-read-p store)
                (setf (gethash key roots) persisted))
              persisted))))))

(defun chain-store-put-state-persistence
    (store block-hash root tries &optional code-bodies)
  "Retain BLOCK-HASH's root and dirty trie set for its durable block batch."
  (setf store (chain-store-require-memory-store store))
  (unless (and (hash32-p block-hash) (hash32-p root))
    (block-validation-fail
     "State persistence block and root must be hash32 values"))
  (unless (and (listp tries) tries)
    (block-validation-fail "State persistence requires at least one trie"))
  (unless (and (listp code-bodies)
               (every #'byte-vector-p code-bodies))
    (block-validation-fail
     "State persistence code bodies must be a list of byte vectors"))
  (let ((key (engine-payload-store-key block-hash)))
    (chain-store-journal-puthash
     (memory-chain-store-state-roots store) key root)
    (chain-store-journal-puthash
     (memory-chain-store-state-tries store) key (copy-list tries))
    (chain-store-journal-puthash
     (memory-chain-store-state-code-bodies store)
     key
     (mapcar #'copy-seq code-bodies))
    (when (chain-store-durable-state-provider-p store)
      (chain-store-journal-puthash
       (memory-chain-store-state-blocks store) key :trie)))
  root)

(defun chain-store-state-persistence-tries (store block-hash)
  (gethash (engine-payload-store-key block-hash)
           (memory-chain-store-state-tries
            (chain-store-require-memory-store store))))

(defun chain-store-state-persistence-code-bodies (store block-hash)
  (gethash (engine-payload-store-key block-hash)
           (memory-chain-store-state-code-bodies
            (chain-store-require-memory-store store))))

(defun chain-store-clear-state-persistence-pending (store block-hash)
  "Release dirty trie/code references only after their durable batch succeeds."
  (setf store (chain-store-require-memory-store store))
  (when (chain-store-durable-state-provider-p store)
    (let ((key (engine-payload-store-key block-hash)))
      (chain-store-journal-remhash
       (memory-chain-store-state-blocks store) key)
      (chain-store-journal-remhash
       (memory-chain-store-state-roots store) key)
      (chain-store-journal-remhash
       (memory-chain-store-state-tries store) key)
      (chain-store-journal-remhash
       (memory-chain-store-state-code-bodies store) key)))
  store)

(defgeneric chain-store-state-available-p (store hash))

(defmethod chain-store-state-available-p ((store t) hash)
  (engine-payload-store-state-available-p
   (chain-store-require-memory-store store)
   hash))

(defun engine-payload-store-string-prefix-p (prefix string)
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))
