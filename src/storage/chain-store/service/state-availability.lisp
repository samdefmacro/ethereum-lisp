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

(defun chain-store-find-pending-storage-trie (store block-hash predicate)
  "Return the first pending storage trie PREDICATE accepts, or NIL.

A block's pending set holds its account trie and only the storage tries that
block itself touched, while the account trie a child copies carries the dirty
account leaves of every unexported ancestor.  A storage root named by such a
leaf may therefore live only in an older pending block: forward peer sync
executes a whole response before exporting its last block, so a contract
written in block N and untouched in N+1 is unreadable from N+2 unless the
lookup walks the whole unexported chain.  Search BLOCK-HASH's pending storage
tries, then each pending ancestor's, stopping at the first block with no
pending set (its state, and everything older, is durable).  This is the storage
counterpart of the all-blocks pending-code lookup.

Callers match by root hash, and equal roots name identical content, so the
nearest match is as good as any; nearest-first keeps the common parent hit to
one step."
  (setf store (chain-store-require-memory-store store))
  (unless (functionp predicate)
    (block-validation-fail "Pending storage trie predicate must be a function"))
  (let ((seen (make-hash-table :test 'equal))
        (hash block-hash))
    (loop
      (unless hash
        (return nil))
      (let* ((key (engine-payload-store-key hash))
             (tries (and (not (gethash key seen))
                         (gethash key
                                  (memory-chain-store-state-tries store)))))
        (unless tries
          (return nil))
        (setf (gethash key seen) t)
        ;; The first pending trie is the account trie.
        (let ((found (find-if predicate (rest tries))))
          (when found
            (return found)))
        (let ((block (chain-store-known-block store hash)))
          (setf hash
                (and block
                     (block-header-parent-hash (block-header block)))))))))

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
