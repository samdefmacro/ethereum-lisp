(in-package #:ethereum-lisp.snap-sync)

;;;; snap/1 service adapter over the runtime state and persistent trie store.

(defun snap-sync-root-trie (database state requested-root)
  "Return the requested live state trie, or NIL when this backend lacks ROOT.

An unavailable state root is a normal snap/1 availability result, not a peer
protocol fault.  Pinned geth responds with an empty AccountRange,
StorageRanges, or TrieNodes packet so the requester can fail over without
tearing down the shared eth+snap session."
  (let* ((root (state-db-root state))
         (trie (state-db-state-trie state)))
    (when (bytes= requested-root (hash32-bytes root))
      (mpt-persist database trie)
      trie)))

(defun snap-sync-trie-node-loader (database)
  (lambda (hash) (trie-node-store-get database hash)))

(defun snap-sync-unique-nodes (&rest proofs)
  (let ((seen (make-hash-table :test #'equal))
        (nodes '()))
    (dolist (proof proofs (nreverse nodes))
      (dolist (node proof)
        (let ((key (bytes-to-hex node :prefix nil)))
          (unless (gethash key seen)
            (setf (gethash key seen) t)
            (push node nodes)))))))

(defun snap-sync-key-at-or-past-limit-p (key limit)
  "True when KEY reaches snap's inclusive response boundary LIMIT."
  (and limit
       (not (ethereum-lisp.validation:byte-vector-lexicographic< key limit))))

(defun snap-sync-storage-bound (bytes label)
  "Normalize snap's optional big-endian storage bound to a 32-byte hash."
  (let ((bytes (ensure-byte-vector bytes)))
    (when (> (length bytes) 32)
      (error "~A contains more than 32 bytes" label))
    (when (plusp (length bytes))
      (let ((result (make-byte-vector 32)))
        (replace result bytes :start1 (- 32 (length bytes)))
        result))))

(defun snap-sync-storage-trie-value (value)
  "Validate and return one canonical storage-trie leaf value.

snap/1 StorageData.Body carries the trie value itself: RLP(minimal uint256
bytes). It is not the decoded integer bytes. Geth passes this byte string
unchanged from its storage iterator to the wire and from the wire into range
proof verification (pinned commit 3827178, snap handlers.go and sync.go)."
  (let* ((encoded (copy-seq (ensure-byte-vector value)))
         (decoded (rlp-decode-one encoded)))
    (unless (byte-vector-p decoded)
      (error "snap storage trie value must encode RLP bytes"))
    (when (> (length decoded) 32)
      (error "snap storage trie value exceeds uint256"))
    (when (zerop
           (ethereum-lisp.validation:rlp-uint-field
            decoded "Snap storage trie value"))
      (error "snap storage trie value must be non-zero"))
    encoded))

(defun snap-sync-account-response (database state request)
  (let* ((trie
           (snap-sync-root-trie
            database state (snap-get-account-range-root request))))
    (unless trie
      (return-from snap-sync-account-response
        (make-snap-account-range
         (snap-get-account-range-id request) '() '())))
    (let* ((entries
             (mpt-entry-range
              trie
              :start (snap-get-account-range-origin request)))
           (limit (snap-get-account-range-limit request))
           (remaining (snap-get-account-range-bytes request))
           (accounts '())
           (last-key nil))
      (dolist (entry entries)
        (when (>= (length accounts) +snap-max-list-items+) (return))
        (let* ((body
                 (rlp-decode-one (cdr entry)))
               (wire
                 (make-snap-account-data
                  (car entry) body))
               (size
                 (length
                  (rlp-encode
                   (ethereum-lisp.snap::snap-account-data-object wire)))))
          (when (and accounts (> size remaining)) (return))
          (push wire accounts)
          (setf last-key (car entry))
          (decf remaining (min remaining size))
          ;; Pinned geth includes the item that reaches (or is the first one
          ;; beyond) Limit, then stops. Filtering with an exclusive iterator
          ;; end would omit the exact boundary and is observably incompatible.
          (when (snap-sync-key-at-or-past-limit-p (car entry) limit)
            (return))))
      (make-snap-account-range
       (snap-get-account-range-id request)
       (nreverse accounts)
       (snap-sync-unique-nodes
        (mpt-get-proof trie (snap-get-account-range-origin request))
        (and last-key (mpt-get-proof trie last-key)))))))

(defun snap-sync-find-account-entry (state proof-key)
  (find proof-key (state-db-account-range state)
        :key #'state-account-range-entry-proof-key :test #'bytes=))

(defun snap-sync-storage-trie (entry)
  (let ((trie (make-mpt)))
    (dolist (storage (state-account-range-entry-storage-entries entry) trie)
      (mpt-put trie
               (keccak-256 (hash32-bytes (car storage)))
               ;; The storage trie and snap/1 both carry the same canonical
               ;; RLP(value) bytes. STATE's flat representation is an integer,
               ;; so only this trie construction step performs the encoding.
               (rlp-encode (cdr storage))))))

(defun snap-sync-account-storage-trie
    (database state account-trie account-hash)
  (multiple-value-bind (account-record present-p)
      (mpt-get account-trie account-hash)
    (unless present-p
      (return-from snap-sync-account-storage-trie nil))
    (let* ((account (decode-state-account-rlp account-record))
           (root (state-account-storage-root account))
           (flat-entry (snap-sync-find-account-entry state account-hash)))
      (cond
        (flat-entry
         (let ((trie (snap-sync-storage-trie flat-entry)))
           (unless (hash32= root (make-hash32 (mpt-root-hash trie)))
             (error "snap storage trie does not match its account commitment"))
           (mpt-persist database trie)
           trie))
        ((hash32= root +empty-trie-hash+) (make-mpt))
        (t
         (make-persisted-mpt root (snap-sync-trie-node-loader database)))))))

(defun snap-sync-storage-response (database state request)
  (let* ((account-trie
           (snap-sync-root-trie
            database state (snap-get-storage-ranges-root request))))
    (unless account-trie
      (return-from snap-sync-storage-response
        (make-snap-storage-ranges
         (snap-get-storage-ranges-id request) '() '())))
    (let* ((slot-groups '())
           (proofs '())
           (remaining (snap-get-storage-ranges-bytes request))
           (first-account-p t))
      (dolist (account-hash (snap-get-storage-ranges-accounts request))
        (let ((trie (snap-sync-account-storage-trie
                     database state account-trie account-hash)))
          (unless trie (return))
          (let* ((origin
                   (and first-account-p
                        (snap-sync-storage-bound
                         (snap-get-storage-ranges-origin request)
                         "Snap storage origin")))
                 (limit
                   (and first-account-p
                        (snap-sync-storage-bound
                         (snap-get-storage-ranges-limit request)
                         "Snap storage limit")))
                 (entries (mpt-entry-range trie :start origin))
                 (slots '())
                 (last-key nil)
                 (truncated-p nil))
            (setf first-account-p nil)
            (dolist (entry entries)
              (let* ((wire
                       (make-snap-storage-data
                        (car entry)
                        (snap-sync-storage-trie-value (cdr entry))))
                     (size
                       (length
                        (rlp-encode
                         (ethereum-lisp.snap::snap-storage-data-object wire)))))
                (when (and slots (> size remaining))
                  (setf truncated-p t)
                  (return))
                (push wire slots)
                (setf last-key (car entry))
                (decf remaining (min remaining size))
                (when (snap-sync-key-at-or-past-limit-p (car entry) limit)
                  (return))))
            (push (nreverse slots) slot-groups)
            ;; A proof terminates a storage response: it means this account
            ;; began at a non-zero origin or the byte budget cut its trie short.
            (when (or origin truncated-p)
              (setf proofs
                    (snap-sync-unique-nodes
                     (mpt-get-proof trie (or origin (make-byte-vector 32)))
                     (and last-key (mpt-get-proof trie last-key))))
              (return)))))
      (make-snap-storage-ranges
       (snap-get-storage-ranges-id request)
       (nreverse slot-groups)
       proofs))))

(defun snap-sync-bytecode-response (database state request)
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
      (multiple-value-bind (durable-code present-p)
          (kv-get-chain-record database :code hash)
        (let ((code (or (and present-p durable-code) (gethash hash by-hash))))
        (when code
          (unless (bytes= hash (keccak-256 code))
            (error "snap bytecode record does not match its content hash"))
          (when (and codes (> (length code) remaining)) (return))
          (push (copy-seq code) codes)
          (decf remaining (min remaining (length code)))))))
    (make-snap-bytecodes (snap-get-bytecodes-id request) (nreverse codes))))

(defun snap-sync-trie-node-response (database state request)
  (let* ((account-trie
           (snap-sync-root-trie
            database state (snap-get-trie-nodes-root request))))
    (unless account-trie
      (return-from snap-sync-trie-node-response
        (make-snap-trie-nodes (snap-get-trie-nodes-id request) '())))
    (let* ((remaining (snap-get-trie-nodes-bytes request))
           (nodes '()))
      (dolist (path-set (snap-get-trie-nodes-paths request))
        (when (null path-set)
          (error "snap trie node request contains an empty path set"))
        (if (= 1 (length path-set))
            (multiple-value-bind (node present-p)
                (mpt-get-node-by-compact-path account-trie (first path-set))
              (when present-p
                (when (and nodes (> (length node) remaining)) (return))
                (push node nodes)
                (decf remaining (min remaining (length node)))))
            (let ((account-hash (first path-set)))
              (unless (= 32 (length account-hash))
                (error
                 "snap storage trie path set requires a 32-byte account hash"))
              (let ((storage-trie
                      (snap-sync-account-storage-trie
                       database state account-trie account-hash)))
                (when storage-trie
                  (dolist (compact-path (rest path-set))
                    (multiple-value-bind (node present-p)
                        (mpt-get-node-by-compact-path storage-trie compact-path)
                      (when present-p
                        (when (and nodes (> (length node) remaining))
                          (return))
                        (push node nodes)
                        (decf remaining (min remaining (length node)))))))))))
      (make-snap-trie-nodes
       (snap-get-trie-nodes-id request) (nreverse nodes)))))

(defun make-persistent-snap-state-backend (database state)
  "Serve snap/1 from STATE while persisting every traversed trie node."
  (make-snap-state-backend
   :account-range
   (lambda (request) (snap-sync-account-response database state request))
   :storage-ranges
   (lambda (request) (snap-sync-storage-response database state request))
   :bytecodes
   (lambda (request) (snap-sync-bytecode-response database state request))
   :trie-nodes
   (lambda (request) (snap-sync-trie-node-response database state request))))
