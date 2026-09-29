(in-package #:ethereum-lisp.node-store)

;;;; An immutable view of the recent canonical chain, for public reads that
;;;; must not wait for the store guard.
;;;;
;;;; The live store is not safe to read without the guard: its read paths
;;;; populate read-through caches (canonical index, block table, transaction
;;;; locations) and its tables are ordinary, unsynchronized hash tables. On a
;;;; busy node the guard is held back to back by block execution, batch import
;;;; and Engine requests, so on the 8e95b990 Hoodi run a public eth_blockNumber
;;;; waited 10-30 s behind it.
;;;;
;;;; THE VIEW IS BUILT UNDER THE GUARD AND NEVER CHANGED AFTERWARDS. The node
;;;; publishes one at every guard release (the one point where the store is
;;;; both committed and readable), so a view is exactly what a guarded reader
;;;; would have seen immediately before the current hold began. A reader takes
;;;; the view once per request and sees one canonical chain, never a torn one.
;;;;
;;;; A VIEW ANSWERS ONLY WHAT IT HOLDS. Anything outside it -- a block older
;;;; than the window, a number above the head, an unknown hash, a txpool read,
;;;; state the view did not capture, any direct access to the memory store --
;;;; throws to NODE-STORE-READ-VIEW-ATTEMPT, whose caller then runs the request
;;;; under the guard against the live store as before. A miss therefore costs a
;;;; wait, and never a different answer.
;;;;
;;;; Blocks are shared with the live store only as read-only sources. Readers
;;;; work on a private copy made on first use, because transactions memoize
;;;; their hash and sender in place, and the guard owner may be computing those
;;;; same memo slots on the same objects.
;;;;
;;;; STATE IS READ BY ROOT, THROUGH THE PROVIDER'S GUARD-FREE READER. When the
;;;; store offers a CHAIN-STORE-GUARD-FREE-READER (the RocksDB direct provider
;;;; does; memory and file oracles do not), publication records, for each window
;;;; block within the provider's state retention whose state is durable, that
;;;; state's root. Balance, nonce, code, storage and eth_call reads at such a
;;;; block then open the trie at the recorded root and read committed,
;;;; content-addressed nodes and code: nothing a writer changes in place. A block
;;;; whose state was still pending (executed, not yet in its durable batch) is
;;;; retried at the next publication; one with no state stays a miss.
;;;;
;;;; eth_call also needs the BLOCKHASH window, 256 ancestors, which is more than
;;;; the block window. The view therefore records the canonical hashes of the
;;;; window plus 256 further ancestors, walked by parent hash exactly as
;;;; CHAIN-STORE-BLOCK-HASHES-FOR-HEADER walks them, and reused across
;;;; publications like the entries are.

(defconstant +node-store-read-view-window+ 128
  "How many canonical blocks, counting back from the head, a view carries. Our
policy: wide enough for explorers and wallets that follow the tip and for
recent receipt lookups; older blocks fall back to the guarded path.")

(defconstant +node-store-read-view-blockhash-depth+ 256
  "How many ancestors BLOCKHASH can name: the EVM's history limit.")

(defstruct (node-store-read-view-entry
            (:constructor %make-node-store-read-view-entry
                (number hash block)))
  "One canonical block of a view. BLOCK is the live store's object and is never
handed to a reader; COPY and TRANSACTION-KEYS are filled on first use by a
reader, with compare-and-swap, and are immutable once installed.

STATE-ROOT is written only by publication, under the guard: NIL before the
block's state was looked at, :PENDING while it was executed but not yet
durable (looked at again by the next publication), :ABSENT when there is none,
or the durable state root. A reader treats anything but a root as a miss."
  (number 0 :type (integer 0 *) :read-only t)
  (hash nil :read-only t)
  (block nil :read-only t)
  (copy nil)
  (transaction-keys nil)
  (state-root nil))

(defstruct (node-store-read-view
            (:constructor %make-node-store-read-view
                (source head-number head-hash safe-number finalized-number
                 entries hashes state-reader state-depth)))
  "What the public read path may answer without the store guard.

ENTRIES is a simple vector, head first: entry I holds canonical block
HEAD-NUMBER - I. It may be shorter than the window when ancestors are not
available (genesis, a SNAP pivot). SAFE-NUMBER and FINALIZED-NUMBER are what
the live tag lookup returned, or :UNAVAILABLE when it signalled.

HASHES is a simple vector, head first, of canonical hashes: element I is the
hash of block HEAD-NUMBER - I, for the window and up to 256 further ancestors.
It ends early where the walk met an unknown block, whose hash is its last
element, or genesis.

STATE-READER is the source's guard-free state reader, or NIL; STATE-DEPTH is
how many entries, from the head, may answer state (the window, capped by the
provider's state retention).

SOURCE is the store the view was built from. A caller answering for another
store object (a store that was swapped out, as test harnesses do) must not use
it; NODE-STORE-READ-VIEW-ATTEMPT enforces that."
  (source nil :read-only t)
  (head-number 0 :read-only t)
  (head-hash nil :read-only t)
  (safe-number nil :read-only t)
  (finalized-number nil :read-only t)
  (entries #() :type simple-vector :read-only t)
  (hashes #() :type simple-vector :read-only t)
  (state-reader nil :read-only t)
  (state-depth 0 :type (integer 0 *) :read-only t))

(defun node-store-read-view-miss ()
  "Leave the view: the request is answered under the guard instead."
  (throw 'node-store-read-view-miss :miss))

(defun node-store-read-view-attempt (function view store)
  "Call FUNCTION with VIEW as its store. Return (VALUES RESULT ANSWERED-P).

STORE is the live store the caller would otherwise read; a view built from any
other store does not answer for it. ANSWERED-P is false when the view could not
answer, in which case the caller must fall back to the guarded live store."
  (unless (eq store (node-store-read-view-source view))
    (return-from node-store-read-view-attempt (values nil nil)))
  (let ((answered-p nil))
    (let ((result (catch 'node-store-read-view-miss
                    (prog1 (funcall function view)
                      (setf answered-p t)))))
      (values (and answered-p result) answered-p))))

(defun %node-store-read-view-tag (store tag)
  (handler-case (chain-store-block-tag-number store tag)
    (error () :unavailable)))

(defun %node-store-read-view-entries (store head-block previous window)
  "The window ending at HEAD-BLOCK, reusing PREVIOUS's entries where they are
still the same canonical ancestry. Runs under the guard."
  (let ((fresh '())
        (reused #())
        (previous-entries (and previous (node-store-read-view-entries previous)))
        (block head-block))
    (loop while (and block (< (length fresh) window))
          do (let* ((number (block-header-number (block-header block)))
                    (hash (block-hash block))
                    (position
                      (and previous-entries
                           (plusp (length previous-entries))
                           (- (node-store-read-view-entry-number
                               (svref previous-entries 0))
                              number)))
                    (match
                      (and position
                           (< -1 position (length previous-entries))
                           (svref previous-entries position))))
               (when (and match
                          (hash32= hash (node-store-read-view-entry-hash match)))
                 ;; The rest of the old window is this block's own ancestry.
                 (setf reused (subseq previous-entries position))
                 (return))
               (push (%make-node-store-read-view-entry number hash block) fresh)
               (setf block
                     (and (plusp number)
                          (chain-store-known-block
                           store (block-header-parent-hash
                                  (block-header block)))))))
    (let ((entries (concatenate 'simple-vector (nreverse fresh) reused)))
      (if (> (length entries) window)
          (subseq entries 0 window)
          entries))))

(defun %node-store-read-view-hashes (store head-number entries previous limit)
  "The canonical hashes from HEAD-NUMBER back, at most LIMIT of them. Runs
under the guard.

Walks by parent hash, as CHAIN-STORE-BLOCK-HASHES-FOR-HEADER does: the hash of
block N-1 is block N's parent hash, and the walk continues only through blocks
the store knows. The part beyond ENTRIES is taken from PREVIOUS where it is the
same ancestry, so a new head costs one step; only a first publication, a
reorg deeper than the window or an ancestry the store has since learned walks."
  (let ((hashes (make-array limit :fill-pointer 0)))
    (loop for entry across entries
          while (< (fill-pointer hashes) limit)
          do (vector-push (node-store-read-view-entry-hash entry) hashes))
    (let ((oldest (and (plusp (length entries))
                       (svref entries (1- (length entries))))))
      (when (and oldest
                 (plusp (node-store-read-view-entry-number oldest))
                 (< (fill-pointer hashes) limit))
        (vector-push (block-header-parent-hash
                      (block-header (node-store-read-view-entry-block oldest)))
                     hashes)))
    (when (and previous (plusp (fill-pointer hashes)))
      (let* ((old (node-store-read-view-hashes previous))
             (last (1- (fill-pointer hashes)))
             (position (- (node-store-read-view-head-number previous)
                          (- head-number last))))
        (when (and (< -1 position (length old))
                   (hash32= (aref hashes last) (svref old position)))
          (loop for index from (1+ position) below (length old)
                while (< (fill-pointer hashes) limit)
                do (vector-push (svref old index) hashes)))))
    (loop while (< 0 (fill-pointer hashes) limit)
          do (let* ((last (1- (fill-pointer hashes)))
                    (block (and (plusp (- head-number last))
                                (chain-store-known-block
                                 store (aref hashes last)))))
               (unless block
                 (return))
               (vector-push (block-header-parent-hash (block-header block))
                            hashes)))
    (coerce hashes 'simple-vector)))

(defun %node-store-read-view-state-root-now (store component entry)
  "ENTRY's state as publication finds it: its durable root, :PENDING or
:ABSENT. Runs under the guard."
  (let ((hash (node-store-read-view-entry-hash entry)))
    (handler-case
        (if (chain-store-state-persistence-tries store hash)
            ;; Executed but not yet in its durable batch: the trie is still
            ;; the guard owner's mutable object. Look again next time.
            :pending
            (multiple-value-bind (root present-p)
                (chain-store-backing-state-root component hash)
              (if (and present-p (hash32-p root)) root :absent)))
      (error () :absent))))

(defun %node-store-read-view-capture-state (store view)
  "Record the state root of VIEW's entries within its state depth that have
none yet or were pending. Runs under the guard; readers see a slot change from
NIL or :PENDING to a root, and treat both as a miss."
  (when (node-store-read-view-state-reader view)
    (let ((component (chain-store-component store)))
      (loop for entry across (node-store-read-view-entries view)
            for position from 0 below (node-store-read-view-state-depth view)
            do (when (member (node-store-read-view-entry-state-root entry)
                             '(nil :pending))
                 (setf (node-store-read-view-entry-state-root entry)
                       (%node-store-read-view-state-root-now
                        store component entry))))))
  view)

(defun %node-store-read-view-state-source (store window)
  "(VALUES READER DEPTH) for STORE's committed state, or (VALUES NIL 0)."
  (let* ((component (chain-store-component store))
         (reader (and component (chain-store-guard-free-reader component))))
    (if reader
        (values reader
                (min window
                     (memory-chain-store-state-retention-depth component)))
        (values nil 0))))

(defun node-store-publish-read-view
    (store previous &key (window +node-store-read-view-window+))
  "Build the view of STORE's canonical chain. Call it with the guard held.

PREVIOUS is the last published view or NIL; when the head, safe and finalized
blocks are unchanged it is returned as it is, so the common release (a read, a
getPayload, a txpool change) costs two index lookups and no allocation beyond
looking again at any block whose state was still pending."
  (let* ((head-number (chain-store-head-number store))
         (head-block (chain-store-block-by-number store head-number))
         (head-hash (and head-block (block-hash head-block)))
         (safe (%node-store-read-view-tag store "safe"))
         (finalized (%node-store-read-view-tag store "finalized"))
         (same-source-previous
           (and previous (eq store (node-store-read-view-source previous))
                previous)))
    (if (and same-source-previous
             (eql head-number (node-store-read-view-head-number previous))
             (let ((old (node-store-read-view-head-hash previous)))
               (if head-hash (and old (hash32= head-hash old)) (null old)))
             (eql safe (node-store-read-view-safe-number previous))
             (eql finalized (node-store-read-view-finalized-number previous)))
        (%node-store-read-view-capture-state store previous)
        (let ((entries (if head-block
                           (%node-store-read-view-entries
                            store head-block same-source-previous window)
                           #())))
          (multiple-value-bind (reader depth)
              (%node-store-read-view-state-source store window)
            (%node-store-read-view-capture-state
             store
             (%make-node-store-read-view
              store head-number head-hash safe finalized entries
              ;; Only state reads (eth_call) use the hashes.
              (if reader
                  (%node-store-read-view-hashes
                   store head-number entries same-source-previous
                   (+ window +node-store-read-view-blockhash-depth+))
                  #())
              reader depth)))))))

(defun %node-store-read-view-entry-at (view number)
  "The window entry for canonical NUMBER, or a miss."
  (let* ((entries (node-store-read-view-entries view))
         (position (and (integerp number)
                        (plusp (length entries))
                        (- (node-store-read-view-head-number view) number))))
    (if (and position (< -1 position (length entries)))
        (svref entries position)
        (node-store-read-view-miss))))

(defun %node-store-read-view-entry-by-hash (view hash)
  (or (and (hash32-p hash)
           (find-if (lambda (entry)
                      (hash32= hash (node-store-read-view-entry-hash entry)))
                    (node-store-read-view-entries view)))
      (node-store-read-view-miss)))

(defun %node-store-read-view-entry-copy (entry)
  "ENTRY's private block copy, made by the first reader that needs it."
  (or (node-store-read-view-entry-copy entry)
      (let ((copy (engine-payload-store-copy-block
                   (node-store-read-view-entry-block entry))))
        (or #+sbcl (sb-ext:compare-and-swap
                    (node-store-read-view-entry-copy entry) nil copy)
            #-sbcl (shiftf (node-store-read-view-entry-copy entry) copy)
            copy))))

(defun %node-store-read-view-entry-transaction-keys (entry)
  "An EQUAL table from transaction hash hex to index in ENTRY's block.

String keys hash by content, so concurrent GETHASH on the installed table needs
no lock and no GC-triggered rehash."
  (or (node-store-read-view-entry-transaction-keys entry)
      (let ((table (make-hash-table :test 'equal)))
        (loop for transaction
                in (block-transactions (%node-store-read-view-entry-copy entry))
              for index from 0
              do (setf (gethash (engine-payload-store-key
                                 (transaction-hash transaction))
                                table)
                       index))
        (or #+sbcl (sb-ext:compare-and-swap
                    (node-store-read-view-entry-transaction-keys entry)
                    nil table)
            #-sbcl (shiftf (node-store-read-view-entry-transaction-keys entry)
                           table)
            table))))

;;; The chain-store read protocol, answered from the view.

(defmethod chain-store-component ((store node-store-read-view))
  ;; Any path that reaches for the mutable store itself is outside the view.
  (node-store-read-view-miss))

(defmethod txpool-component ((store node-store-read-view))
  (node-store-read-view-miss))

(defmethod chain-store-head-number ((store node-store-read-view))
  (node-store-read-view-head-number store))

(defmethod chain-store-block-tag-number ((store node-store-read-view) tag)
  (cond
    ((or (string= tag "latest") (string= tag "pending"))
     (node-store-read-view-head-number store))
    ((string= tag "safe")
     (let ((number (node-store-read-view-safe-number store)))
       (if (eq number :unavailable) (node-store-read-view-miss) number)))
    ((string= tag "finalized")
     (let ((number (node-store-read-view-finalized-number store)))
       (if (eq number :unavailable) (node-store-read-view-miss) number)))
    (t (node-store-read-view-miss))))

(defmethod chain-store-canonical-hash ((store node-store-read-view) number)
  (node-store-read-view-entry-hash
   (%node-store-read-view-entry-at store number)))

(defmethod chain-store-block-by-number ((store node-store-read-view) number)
  (%node-store-read-view-entry-copy
   (%node-store-read-view-entry-at store number)))

(defmethod chain-store-known-block ((store node-store-read-view) hash)
  ;; A hash outside the window may still be a known block (older, or on a
  ;; side branch), so it is a miss rather than NIL.
  (%node-store-read-view-entry-copy
   (%node-store-read-view-entry-by-hash store hash)))

(defmethod chain-store-canonical-block-p ((store node-store-read-view) block)
  (hash32= (block-hash block)
           (node-store-read-view-entry-hash
            (%node-store-read-view-entry-at
             store (block-header-number (block-header block))))))

(defmethod chain-store-transaction-location
    ((store node-store-read-view) hash)
  ;; Only a hit is an answer: an unknown hash may be older than the window.
  (let ((key (and (hash32-p hash) (engine-payload-store-key hash))))
    (unless key
      (node-store-read-view-miss))
    (loop for entry across (node-store-read-view-entries store)
          for index = (gethash key (%node-store-read-view-entry-transaction-keys
                                    entry))
          when index
            do (let* ((block (%node-store-read-view-entry-copy entry))
                      (receipts (block-receipts block)))
                 (return-from chain-store-transaction-location
                   (make-engine-transaction-location
                    :block block
                    :index index
                    :transaction (nth index (block-transactions block))
                    :receipt (nth index receipts)
                    :log-index-start
                    (loop for receipt in receipts
                          repeat index
                          sum (length (receipt-logs receipt)))))))
    (node-store-read-view-miss)))

;;; State, answered by root through the provider's guard-free reader.

(defun %node-store-read-view-state (view block-hash)
  "(VALUES ROOT READER) for BLOCK-HASH's captured state, or a miss."
  (let* ((reader (node-store-read-view-state-reader view))
         (entry (and reader
                     (%node-store-read-view-entry-by-hash view block-hash)))
         (root (and entry
                    (< (- (node-store-read-view-head-number view)
                          (node-store-read-view-entry-number entry))
                       (node-store-read-view-state-depth view))
                    (node-store-read-view-entry-state-root entry))))
    (if (hash32-p root)
        (values root reader)
        (node-store-read-view-miss))))

(defun %node-store-read-view-account (view block-hash address)
  "BALANCE, NONCE, CODE-HASH, STORAGE-ROOT, ACCOUNT-PRESENT-P and the reader."
  (multiple-value-bind (root reader) (%node-store-read-view-state view block-hash)
    (multiple-value-bind (balance nonce code-hash storage-root present-p)
        (funcall (chain-store-guard-free-state-reader-account-function reader)
                 block-hash root address)
      (values balance nonce code-hash storage-root present-p reader))))

(defun %node-store-read-view-code (reader present-p code-hash)
  "The account's code: empty when absent or code-less, a miss when the code
record is missing (the guarded path reports that as its own error)."
  (if (or (not present-p)
          (not (hash32-p code-hash))
          (hash32= code-hash ethereum-lisp.crypto:+empty-code-hash+))
      (ethereum-lisp.bytes:make-byte-vector 0)
      (multiple-value-bind (code code-present-p)
          (funcall (chain-store-guard-free-state-reader-code-function reader)
                   code-hash)
        (if code-present-p
            (copy-seq code)
            (node-store-read-view-miss)))))

(defmethod chain-store-state-available-p ((store node-store-read-view) hash)
  (%node-store-read-view-state store hash)
  t)

(defmethod chain-store-published-state ((store node-store-read-view) block-hash)
  (%node-store-read-view-state store block-hash))

(defmethod chain-store-account-balance
    ((store node-store-read-view) block-hash address)
  (multiple-value-bind (balance nonce code-hash storage-root present-p)
      (%node-store-read-view-account store block-hash address)
    (declare (ignore nonce code-hash storage-root))
    (values balance present-p)))

(defmethod chain-store-account-nonce
    ((store node-store-read-view) block-hash address)
  (multiple-value-bind (balance nonce code-hash storage-root present-p)
      (%node-store-read-view-account store block-hash address)
    (declare (ignore balance code-hash storage-root))
    (values nonce present-p)))

(defmethod chain-store-account-code
    ((store node-store-read-view) block-hash address)
  (multiple-value-bind (balance nonce code-hash storage-root present-p reader)
      (%node-store-read-view-account store block-hash address)
    (declare (ignore balance nonce storage-root))
    (%node-store-read-view-code reader present-p code-hash)))

(defmethod chain-store-account-state
    ((store node-store-read-view) block-hash address)
  (multiple-value-bind (balance nonce code-hash storage-root present-p reader)
      (%node-store-read-view-account store block-hash address)
    (declare (ignore storage-root))
    (values balance nonce
            (%node-store-read-view-code reader present-p code-hash)
            present-p t)))

(defmethod chain-store-account-storage
    ((store node-store-read-view) block-hash address slot)
  (multiple-value-bind (balance nonce code-hash storage-root present-p reader)
      (%node-store-read-view-account store block-hash address)
    (declare (ignore balance nonce code-hash))
    (if present-p
        (funcall (chain-store-guard-free-state-reader-storage-function reader)
                 storage-root slot)
        (values 0 nil))))

(defmethod chain-store-recorded-block-hashes
    ((store node-store-read-view) header)
  ;; The same table CHAIN-STORE-BLOCK-HASHES-FOR-HEADER builds by walking,
  ;; for a header that is canonical in this view.
  (let* ((number (block-header-number header))
         (entry (%node-store-read-view-entry-at store number))
         (hashes (node-store-read-view-hashes store))
         (position (- (node-store-read-view-head-number store) number))
         (table (make-hash-table :test 'eql)))
    (unless (and (plusp (length hashes))
                 (hash32= (block-header-hash header)
                          (node-store-read-view-entry-hash entry)))
      (node-store-read-view-miss))
    (loop for offset from 0 below (min +node-store-read-view-blockhash-depth+
                                       number)
          for index = (+ position 1 offset)
          do (setf (gethash (- number 1 offset) table)
                   (if (< index (length hashes))
                       (svref hashes index)
                       :unavailable)))
    table))
