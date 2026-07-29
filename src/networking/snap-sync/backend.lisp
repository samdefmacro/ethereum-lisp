(in-package #:ethereum-lisp.snap-sync)

;;;; snap/1 service adapter over the runtime state and persistent trie store.

(defun snap-sync-root-trie (database state requested-root)
  (let* ((root (state-db-root state))
         (trie (state-db-state-trie state)))
    (unless (bytes= requested-root (hash32-bytes root))
      (error "snap request names a state root this backend does not serve"))
    (mpt-persist database trie)
    trie))

(defun snap-sync-unique-nodes (&rest proofs)
  (let ((seen (make-hash-table :test #'equal))
        (nodes '()))
    (dolist (proof proofs (nreverse nodes))
      (dolist (node proof)
        (let ((key (bytes-to-hex node :prefix nil)))
          (unless (gethash key seen)
            (setf (gethash key seen) t)
            (push node nodes)))))))

(defun snap-sync-account-response (database state request)
  (let* ((trie
           (snap-sync-root-trie
            database state (snap-get-account-range-root request)))
         (entries
           (state-db-account-range
            state
            :start (snap-get-account-range-origin request)
            :end (snap-get-account-range-limit request)))
         (remaining (snap-get-account-range-bytes request))
         (accounts '())
         (last-key nil))
    (dolist (entry entries)
      (when (>= (length accounts) +snap-max-list-items+) (return))
      (let* ((body
               (rlp-decode-one
                (state-account-rlp
                 (state-account-range-entry-account entry))))
             (wire
               (make-snap-account-data
                (state-account-range-entry-proof-key entry) body))
             (size
               (length
                (rlp-encode
                 (ethereum-lisp.snap::snap-account-data-object wire)))))
        (when (and accounts (> size remaining)) (return))
        (push wire accounts)
        (setf last-key (state-account-range-entry-proof-key entry))
        (decf remaining (min remaining size))))
    (make-snap-account-range
     (snap-get-account-range-id request)
     (nreverse accounts)
     (snap-sync-unique-nodes
      (mpt-get-proof trie (snap-get-account-range-origin request))
      (and last-key (mpt-get-proof trie last-key))))))

(defun snap-sync-find-account-entry (state proof-key)
  (find proof-key (state-db-account-range state)
        :key #'state-account-range-entry-proof-key :test #'bytes=))

(defun snap-sync-storage-trie (entry)
  (let ((trie (make-mpt)))
    (dolist (storage (state-account-range-entry-storage-entries entry) trie)
      (mpt-put trie
               (keccak-256 (hash32-bytes (car storage)))
               (integer-to-minimal-bytes (cdr storage))))))

(defun snap-sync-storage-response (database state request)
  (snap-sync-root-trie database state (snap-get-storage-ranges-root request))
  (let ((slot-groups '())
        (proofs '())
        (remaining (snap-get-storage-ranges-bytes request)))
    (dolist (account-hash (snap-get-storage-ranges-accounts request))
      (let ((account (snap-sync-find-account-entry state account-hash)))
        (unless account (return))
        (let* ((entries
                 (state-db-storage-range
                  state (state-account-range-entry-address account)
                  :start (snap-get-storage-ranges-origin request)
                  :end (snap-get-storage-ranges-limit request)))
               (slots '())
               (last-key nil)
               (trie (snap-sync-storage-trie account)))
          (mpt-persist database trie)
          (dolist (entry entries)
            (let* ((wire
                     (make-snap-storage-data
                      (state-storage-range-entry-proof-key entry)
                      (integer-to-minimal-bytes
                       (state-storage-range-entry-value entry))))
                   (size
                     (length
                      (rlp-encode
                       (ethereum-lisp.snap::snap-storage-data-object wire)))))
              (when (and slots (> size remaining)) (return))
              (push wire slots)
              (setf last-key (state-storage-range-entry-proof-key entry))
              (decf remaining (min remaining size))))
          (push (nreverse slots) slot-groups)
          (setf proofs
                (append proofs
                        (snap-sync-unique-nodes
                         (mpt-get-proof
                          trie (snap-get-storage-ranges-origin request))
                         (and last-key (mpt-get-proof trie last-key))))))))
    (make-snap-storage-ranges
     (snap-get-storage-ranges-id request)
     (nreverse slot-groups)
     (apply #'snap-sync-unique-nodes (list proofs)))))

(defun snap-sync-bytecode-response (state request)
  (let ((by-hash (make-hash-table :test #'equalp))
        (remaining (snap-get-bytecodes-bytes request))
        (codes '()))
    (dolist (entry (state-db-account-range state))
      (let ((code (state-account-range-entry-code entry)))
        (when (plusp (length code))
          (setf (gethash
                 (hash32-bytes
                  (state-account-code-hash
                   (state-account-range-entry-account entry)))
                 by-hash)
                code))))
    (dolist (hash (snap-get-bytecodes-hashes request))
      (let ((code (gethash hash by-hash)))
        (when code
          (when (and codes (> (length code) remaining)) (return))
          (push (copy-seq code) codes)
          (decf remaining (min remaining (length code))))))
    (make-snap-bytecodes (snap-get-bytecodes-id request) (nreverse codes))))

(defun snap-sync-trie-node-response (database request)
  (let ((remaining (snap-get-trie-nodes-bytes request))
        (nodes '()))
    (dolist (path-set (snap-get-trie-nodes-paths request))
      (let ((key (car (last path-set))))
        ;; A 32-byte path component is a content-addressed node reference. Other
        ;; compact trie paths require a loaded trie and are honestly omitted.
        (when (and key (= (length key) 32))
          (multiple-value-bind (node present-p)
              (trie-node-store-get database key)
            (when present-p
              (when (and nodes (> (length node) remaining)) (return))
              (push node nodes)
              (decf remaining (min remaining (length node))))))))
    (make-snap-trie-nodes (snap-get-trie-nodes-id request) (nreverse nodes))))

(defun make-persistent-snap-state-backend (database state)
  "Serve snap/1 from STATE while persisting every traversed trie node."
  (make-snap-state-backend
   :account-range
   (lambda (request) (snap-sync-account-response database state request))
   :storage-ranges
   (lambda (request) (snap-sync-storage-response database state request))
   :bytecodes
   (lambda (request) (snap-sync-bytecode-response state request))
   :trie-nodes
   (lambda (request) (snap-sync-trie-node-response database request))))
