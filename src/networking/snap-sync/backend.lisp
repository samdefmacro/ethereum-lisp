(in-package #:ethereum-lisp.snap-sync)

;;;; snap/1 service adapter over the runtime state and persistent trie store.
;;;;
;;;; Every request's work is bounded by the request, never by the state: range
;;;; walks start at the origin and stop at the limit key, the byte budget, the
;;;; per-request time budget, or when the caller asks the server to yield.
;;;; snap/1 lets a server answer any proved prefix of a range, so stopping early
;;;; costs the requester one more round trip, not correctness. The limits are
;;;; geth's (v1.17 eth/protocols/snap/handler.go: softResponseLimit,
;;;; maxCodeLookups, maxTrieNodeLookups, maxTrieNodeTimeSpent); geth's range
;;;; handlers read a flat snapshot, so only TrieNodes needs a clock there.

(defconstant +snap-sync-trie-node-lookups-per-request+ 1024
  "Maximum trie-node disk lookups served for one snap/1 request.

This matches pinned geth's lookup cap.  The wire decoder has a larger structural
limit, but an authenticated peer must not turn one small request into unbounded
state-store work.")

(defconstant +snap-sync-code-lookups-per-request+ 1024
  "Maximum bytecode hashes served for one GetByteCodes request (geth's
maxCodeLookups); the rest of a longer request is left unanswered, as geth does.")

(defconstant +snap-sync-soft-response-limit+ (* 2 1024 1024)
  "Maximum uncompressed payload budget for one snap/1 response.")

(defun snap-sync-response-byte-limit (requested)
  (min requested +snap-sync-soft-response-limit+))

(defparameter *snap-sync-serve-seconds* 1
  "Time budget of one served snap/1 request, in seconds, or NIL for none.

Our policy. A node serves a request under its store guard, and every Engine API
request waits behind that hold; on Hoodi (b5161312) serving holds lasted
20-134 s and one never ended. Once the budget is spent the server answers what
it has -- at least one item, so the requester always progresses -- with the
proof a partial range needs. geth bounds only TrieNodes by time (5 s,
maxTrieNodeTimeSpent) because its range handlers iterate a flat snapshot; ours
walk the trie, so one second is the budget for every kind.")

(defun snap-sync-serve-stop-function (yield-predicate)
  "Return a function of no arguments that is true once the request being served
should end: its *SNAP-SYNC-SERVE-SECONDS* spent, or YIELD-PREDICATE true."
  (let ((deadline
          (and *snap-sync-serve-seconds*
               (+ (get-internal-real-time)
                  (round (* *snap-sync-serve-seconds*
                            internal-time-units-per-second))))))
    (lambda ()
      (or (and deadline (>= (get-internal-real-time) deadline))
          (and yield-predicate (funcall yield-predicate) t)))))

(defun snap-sync-call-serving (yield-predicate function)
  "Call FUNCTION with the stop function of one served request.

Trie nodes are resolved transiently for the request (*TRIE-TRANSIENT-
RESOLUTIONS*): the served state's node graph is shared with the node's head
and with every later state derived from it, and memoizing a peer's reads there
would keep every node any peer ever asked for in the heap."
  (let ((*trie-transient-resolutions* (make-hash-table :test #'equalp)))
    (funcall function (snap-sync-serve-stop-function yield-predicate))))

(defun snap-sync-root-trie (state requested-root)
  "Return the requested live state trie, or NIL when this backend lacks ROOT.

An unavailable state root is a normal snap/1 availability result, not a peer
protocol fault.  Pinned geth responds with an empty AccountRange,
StorageRanges, or TrieNodes packet so the requester can fail over without
tearing down the shared eth+snap session.

Serving is a read: the trie is returned as STATE holds it and nothing is
written.  Geth's handlers open the requested root read-only and answer empty
when it is absent (eth/protocols/snap/handlers.go at
38271784c2b31926563806da9a2e023b88f5e7a8).  This server used to persist the
ACCOUNT trie it was about to serve -- one batch of that trie's dirty nodes,
without the storage tries or the code its leaves name, and it is live while we
are ourselves syncing into the same store.  Under the account closure contract
(docs/snap-account-closure.md, I1) such a record claims that everything below
it and everything it names is durable, so that write could plant a present
account node above absent dependencies."
  (when state
    (when (bytes= requested-root (hash32-bytes (state-db-root state)))
      (state-db-state-trie state))))

(defun snap-sync-state-for-root (state state-provider requested-root)
  "Resolve REQUESTED-ROOT without pinning a long-lived peer to one head state.

STATE preserves the historical two-argument backend contract and remains the
fast path when it already has the requested root.  STATE-PROVIDER, when given,
is responsible for resolving another still-retained state from the owning
chain store.  An unavailable root returns NIL and is encoded as snap/1's normal
empty availability response by the request handlers below."
  (if (and state
           (bytes= requested-root (hash32-bytes (state-db-root state))))
      state
      (and state-provider (funcall state-provider requested-root))))

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

(defun snap-sync-slim-account-body (encoded)
  "Return ENCODED's account body in snap's canonical slim representation."
  (let* ((body (rlp-decode-one encoded))
         (fields (rlp-list-items body)))
    (unless (= 4 (length fields))
      (error "snap account trie value must contain four fields"))
    (destructuring-bind (nonce balance storage-root code-hash) fields
      (make-rlp-list
       nonce balance
       (if (bytes= storage-root (hash32-bytes +empty-trie-hash+))
           (make-byte-vector 0)
           storage-root)
       (if (bytes= code-hash (hash32-bytes +empty-code-hash+))
           (make-byte-vector 0)
           code-hash)))))

(defun snap-sync-account-response
    (database state request &optional (stop-p (constantly nil)))
  ;; DATABASE keeps the handlers' common signature.  An account range is
  ;; answered from STATE's trie alone and nothing is written to DATABASE.
  ;; STOP-P, asked after each account, ends the range early (time budget or a
  ;; waiting Engine request); the origin and last-key proofs still cover it.
  (declare (ignore database))
  (let* ((trie
           (snap-sync-root-trie
            state (snap-get-account-range-root request))))
    (unless trie
      (return-from snap-sync-account-response
        (make-snap-account-range
         (snap-get-account-range-id request) '() '())))
    (let* ((limit (snap-get-account-range-limit request))
           (byte-limit
             (snap-sync-response-byte-limit
              (snap-get-account-range-bytes request)))
           (response-bytes 0)
           (accounts '())
           (last-key nil))
      ;; Walk from the origin and stop as soon as the response is complete:
      ;; the work is the response's, as with geth's snapshot iterator.
      (mpt-map-entries-from
       trie (snap-get-account-range-origin request)
       (lambda (key value)
         (let* ((body (snap-sync-slim-account-body value))
                (size (+ 32 (length (rlp-encode body)))))
           (push (make-snap-account-data key body) accounts)
           (setf last-key key)
           (incf response-bytes size)
           ;; Pinned geth includes the item that reaches (or is the first one
           ;; beyond) Limit, then stops. Filtering with an exclusive iterator
           ;; end would omit the exact boundary and is observably incompatible.
           (or (snap-sync-key-at-or-past-limit-p key limit)
               (> response-bytes byte-limit)
               (funcall stop-p)))))
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
           ;; Only a flat (non-lazy) state holds whole storage in memory. A
           ;; lazy state's objects are whatever execution touched, with partial
           ;; storage, and indexing them costs O(objects) per requested account.
           (flat-entry (and (not (state-db-lazy-p state))
                            (snap-sync-find-account-entry state account-hash))))
      (cond
        (flat-entry
         (let ((trie (snap-sync-storage-trie flat-entry)))
           (unless (hash32= root (make-hash32 (mpt-root-hash trie)))
             (error "snap storage trie does not match its account commitment"))
           ;; Served from memory and never persisted: a storage node the
           ;; server wrote would be a closure claim it has no business making.
           trie))
        ((hash32= root +empty-trie-hash+) (make-mpt))
        (t
         (make-persisted-mpt root (snap-sync-trie-node-loader database)))))))

(defun snap-sync-storage-response
    (database state request &optional (stop-p (constantly nil)))
  ;; STOP-P, asked after each slot, ends the response like an exhausted byte
  ;; budget: the account in progress is cut, proved, and is the last one.
  (let* ((account-trie
           (snap-sync-root-trie
            state (snap-get-storage-ranges-root request))))
    (unless account-trie
      (return-from snap-sync-storage-response
        (make-snap-storage-ranges
         (snap-get-storage-ranges-id request) '() '())))
    (let* ((slot-groups '())
           (proofs '())
           (remaining
             (snap-sync-response-byte-limit
              (snap-get-storage-ranges-bytes request)))
           (first-account-p t))
      (dolist (account-hash (snap-get-storage-ranges-accounts request))
        ;; geth stops before opening another account's range once the byte
        ;; budget is spent; so do we, and once the time budget is.
        (when (and (not first-account-p)
                   (or (<= remaining 0) (funcall stop-p)))
          (return))
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
                 (slots '())
                 (last-key nil)
                 (truncated-p nil))
            (setf first-account-p nil)
            (mpt-map-entries-from
             trie origin
             (lambda (key value)
               (let* ((wire
                        (make-snap-storage-data
                         key (snap-sync-storage-trie-value value)))
                      (size
                        (length
                         (rlp-encode
                          (ethereum-lisp.snap::snap-storage-data-object wire)))))
                 (cond
                   ((and slots (> size remaining))
                    (setf truncated-p t))
                   (t
                    (push wire slots)
                    (setf last-key key)
                    (decf remaining (min remaining size))
                    (cond
                      ((snap-sync-key-at-or-past-limit-p key limit) t)
                      ((funcall stop-p) (setf truncated-p t))
                      (t nil)))))))
            (push (nreverse slots) slot-groups)
            ;; A proof terminates a storage response: it means this account
            ;; began at a non-zero origin or the byte budget cut its trie short.
            ;; Either bound makes this a partial trie range.  In particular a
            ;; zero-origin request with a non-empty limit still needs an edge
            ;; proof; without it a receiver could only validate the response
            ;; as a (false) proofless complete trie.
            (when (or origin limit truncated-p)
              (setf proofs
                    (snap-sync-unique-nodes
                     (mpt-get-proof trie (or origin (make-byte-vector 32)))
                     (and last-key (mpt-get-proof trie last-key))))
              (return)))))
      (make-snap-storage-ranges
       (snap-get-storage-ranges-id request)
       (nreverse slot-groups)
       proofs))))

(defun snap-sync-state-code-table (state)
  "Index the code of STATE's in-memory accounts by code hash."
  (let ((by-hash (make-hash-table :test #'equalp)))
    (dolist (entry (state-db-account-range state) by-hash)
      (let ((code (state-account-range-entry-code entry)))
        (when (plusp (length code))
          (setf (gethash
                 (hash32-bytes
                  (state-account-code-hash
                   (state-account-range-entry-account entry)))
                 by-hash)
                code))))))

(defun snap-sync-bytecode-response
    (database state request &optional (stop-p (constantly nil)))
  ;; geth serves at most maxCodeLookups hashes, caps Bytes at the soft
  ;; response limit, and stops once the response passes it. STATE's own code
  ;; is indexed only when a hash is not durable.
  (let ((hashes (snap-get-bytecodes-hashes request))
        (by-hash nil)
        (byte-limit
          (snap-sync-response-byte-limit (snap-get-bytecodes-bytes request)))
        (response-bytes 0)
        (codes '()))
    (when (> (length hashes) +snap-sync-code-lookups-per-request+)
      (setf hashes (subseq hashes 0 +snap-sync-code-lookups-per-request+)))
    (dolist (hash hashes)
      (let ((code
              (if (bytes= hash (hash32-bytes +empty-code-hash+))
                  (make-byte-vector 0)
                  (multiple-value-bind (durable-code present-p)
                      (kv-get-chain-record database :code hash)
                    (if present-p
                        durable-code
                        (gethash hash
                                 (or by-hash
                                     (setf by-hash
                                           (snap-sync-state-code-table
                                            state)))))))))
        (when code
          (unless (bytes= hash (keccak-256 code))
            (error "snap bytecode record does not match its content hash"))
          (push (copy-seq code) codes)
          (incf response-bytes (length code))
          (when (or (> response-bytes byte-limit) (funcall stop-p))
            (return)))))
    (make-snap-bytecodes (snap-get-bytecodes-id request) (nreverse codes))))

(defun snap-sync-trie-account-hash (bytes)
  "Normalize a storage path-set account key like geth's common.BytesToHash.

snap/1 carries this key as unconstrained bytes.  Short values are left-padded
and overlong values retain their rightmost 32 bytes; an unavailable normalized
account is an ordinary path miss, not a malformed request that closes the
shared eth+snap session."
  (let* ((bytes (ensure-byte-vector bytes))
         (count (min 32 (length bytes)))
         (result (make-byte-vector 32)))
    (replace result bytes
             :start1 (- 32 count)
             :start2 (- (length bytes) count))
    result))


(defun snap-sync-trie-node-response
    (database state request &optional (stop-p (constantly nil)))
  ;; geth caps Bytes at the soft response limit and stops after
  ;; maxTrieNodeLookups lookups or maxTrieNodeTimeSpent; STOP-P, asked after
  ;; each node, is our time budget and the Engine yield.
  (let* ((account-trie
           (snap-sync-root-trie
            state (snap-get-trie-nodes-root request))))
    (unless account-trie
      (return-from snap-sync-trie-node-response
        (make-snap-trie-nodes (snap-get-trie-nodes-id request) '())))
    (let* ((byte-limit
             (snap-sync-response-byte-limit (snap-get-trie-nodes-bytes request)))
           (response-bytes 0)
           (nodes '())
           (lookups 0))
      (block serve
        (flet ((serve-node (trie compact-path)
                 (when (>= lookups +snap-sync-trie-node-lookups-per-request+)
                   (return-from serve))
                 (incf lookups)
                 (multiple-value-bind (node present-p)
                     (mpt-get-node-by-compact-path trie compact-path)
                   (let ((node (if present-p node (make-byte-vector 0))))
                     (push node nodes)
                     (incf response-bytes (length node))
                     (when (or (> response-bytes byte-limit) (funcall stop-p))
                       (return-from serve))))))
          (dolist (path-set (snap-get-trie-nodes-paths request))
            (when (null path-set)
              (error "snap trie node request contains an empty path set"))
            (if (= 1 (length path-set))
                (serve-node account-trie (first path-set))
                (let* ((account-hash
                         (snap-sync-trie-account-hash (first path-set)))
                       (storage-trie
                         (snap-sync-account-storage-trie
                          database state account-trie account-hash)))
                  (when storage-trie
                    (dolist (compact-path (rest path-set))
                      (serve-node storage-trie compact-path))))))))
      (make-snap-trie-nodes
       (snap-get-trie-nodes-id request) (nreverse nodes)))))

(defun make-persistent-snap-state-backend
    (database state &key state-provider yield-predicate)
  "Serve snap/1 from retained states without writing to DATABASE.

DATABASE is read for code and for storage tries the state does not hold in
memory; the server never persists what it serves (see SNAP-SYNC-ROOT-TRIE).

STATE is the current-state fast path.  STATE-PROVIDER receives a requested
32-byte state root when a peer asks for a different historical root.  This is
essential for a server whose canonical head advances after the peer handshake:
snap pivots are deliberately historical, so capturing one state for the whole
connection would advertise snap/1 while rejecting every later target-64 root.

Each request ends within *SNAP-SYNC-SERVE-SECONDS*, or as soon as
YIELD-PREDICATE (a function of no arguments, asked between items) returns true,
with the partial answer snap/1 allows. A node that serves under a lock others
wait for passes a predicate that is true while such a waiter has priority."
  (flet ((serving (function)
           (lambda (request)
             (snap-sync-call-serving
              yield-predicate
              (lambda (stop-p) (funcall function request stop-p))))))
    (make-snap-state-backend
     :account-range
     (serving
      (lambda (request stop-p)
        (let ((root (snap-get-account-range-root request)))
          (snap-sync-account-response
           database
           (snap-sync-state-for-root state state-provider root)
           request stop-p))))
     :storage-ranges
     (serving
      (lambda (request stop-p)
        (let ((root (snap-get-storage-ranges-root request)))
          (snap-sync-storage-response
           database
           (snap-sync-state-for-root state state-provider root)
           request stop-p))))
     :bytecodes
     (serving
      (lambda (request stop-p)
        (snap-sync-bytecode-response database state request stop-p)))
     :trie-nodes
     (serving
      (lambda (request stop-p)
        (let ((root (snap-get-trie-nodes-root request)))
          (snap-sync-trie-node-response
           database
           (snap-sync-state-for-root state state-provider root)
           request stop-p)))))))
