(in-package #:ethereum-lisp.eth-sync)

;;;; Transaction gossip.
;;;;
;;;; A transaction reaches a block because peers pass it around before anyone
;;;; builds on it. Without this a node only ever sees transactions submitted to
;;;; its own RPC: its pool cannot fill from the network, and nothing it accepts
;;;; ever reaches anyone else.
;;;;
;;;; Two paths carry one. Small transactions arrive whole in Transactions;
;;;; larger ones are announced by hash and pulled with GetPooledTransactions, so
;;;; the same payload does not arrive from every neighbour at once. Both ends
;;;; reach the pool through the same backend the request handlers use.
;;;;
;;;; Blob transactions are announced and pulled only when the backend can serve
;;;; their sidecar. The pooled form carries either the legacy blob proof wrapper
;;;; or the EIP-7594 version-1 cell-proof wrapper; every received sidecar is
;;;; cryptographically checked before either it or the transaction reaches live
;;;; storage.

(defconstant +eth-max-pooled-transactions-serve+ 256
  "How many hashes one GetPooledTransactions request is answered for, from
go-ethereum's soft limit on the asking side.")

(defconstant +eth-max-announced-transaction-hashes+ 4096
  "How many announced hashes stay queued for one peer. Past this the peer is
announcing faster than we fetch, and the excess is dropped rather than left to
grow without bound.")

(defconstant +eth-max-announced-block-hashes+ 256
  "How many block hashes one peer may queue before the excess is dropped.")

(defconstant +eth-max-pending-blob-cell-fetches+ 256
  "How many validated eth/72 blob fragments one peer may queue for GetCells.")

(defconstant +eth-max-pending-pooled-transaction-requests+ 64
  "How many unanswered async pooled-transaction requests one peer may retain.")

(defconstant +eth-pooled-transaction-request-timeout-seconds+ 5
  "How long async transaction fetch metadata remains live, matching geth.")

(defconstant +eth-full-transaction-broadcast-size+ 4096
  "Largest transaction pushed in full; larger transactions are hash-announced.")

(defconstant +eth-max-known-transaction-hashes+ 8192
  "How many transaction hashes one session remembers for its remote peer.")

(defun eth-gossipable-transaction-p (transaction)
  "Whether TRANSACTION may be announced or pushed to a peer."
  (cond
    ((typep transaction 'blob-network-transaction) t)
    ((and (consp transaction)
          (typep (car transaction) 'blob-transaction)
          (typep (cdr transaction) 'blob-sidecar))
     t)
    ((typep transaction 'blob-transaction) nil)
    (t t)))

;;; Sending.

(defun eth-peer-known-transaction-table (peer)
  (or (eth-peer-known-transaction-hashes peer)
      (setf (eth-peer-known-transaction-hashes peer)
            (make-hash-table :test #'equalp))))

(defun eth-peer-knows-transaction-p (peer transaction)
  (gethash (hash32-bytes (transaction-hash transaction))
           (eth-peer-known-transaction-table peer)))

(defun eth-peer-note-known-transaction-hashes (peer hashes)
  "Record that PEER knows HASHES, bounding memory for a long-lived session."
  (let ((known (eth-peer-known-transaction-table peer)))
    (dolist (hash hashes)
      (when (>= (hash-table-count known)
                +eth-max-known-transaction-hashes+)
        (clrhash known))
      (setf (gethash (ensure-byte-vector hash) known) t)))
  peer)

(defun eth-peer-note-known-transactions (peer transactions)
  (eth-peer-note-known-transaction-hashes
   peer
   (mapcar (lambda (transaction)
             (hash32-bytes
              (transaction-hash
               (eth-pooled-entry-transaction transaction))))
           transactions)))

(defun eth-peer-sendable-transactions (peer transactions size-predicate)
  (remove-if-not
   (lambda (transaction)
     (and (eth-gossipable-transaction-p transaction)
          (not (eth-peer-knows-transaction-p peer transaction))
          (funcall size-predicate (length (transaction-encoding transaction)))))
   transactions))

(defun eth-peer-broadcast-transactions (peer transactions)
  "Push TRANSACTIONS to PEER in full, and return how many were sent.

Sends nothing when none qualify: an empty Transactions message is wasted
bandwidth, and the protocol asks that it carry at least one transaction."
  (let ((sendable
          (eth-peer-sendable-transactions
           peer transactions
           (lambda (size)
             (<= size +eth-full-transaction-broadcast-size+)))))
    (when sendable
      (eth-peer-send peer +eth-message-transactions+
                     (encode-eth-transactions sendable))
      (eth-peer-note-known-transactions peer sendable))
    (length sendable)))

(defun eth-peer-announce-transactions (peer transactions)
  "Announce TRANSACTIONS to PEER by hash, and return how many were announced."
  (let* ((backend (eth-peer-serve-backend peer))
         (sidecar-reader
           (and backend
                (eth-pooled-blob-sidecar-reader
                 backend (eth-peer-eth-version peer))))
         (sendable
           (loop for transaction in transactions
                 for entry =
                   (unless (eth-peer-knows-transaction-p peer transaction)
                     (cond
                       ((eth-gossipable-transaction-p transaction)
                        transaction)
                       ((and sidecar-reader
                             (typep transaction 'blob-transaction))
                        (let ((sidecar
                                (funcall sidecar-reader transaction)))
                          (and sidecar
                               (make-blob-network-transaction
                                transaction sidecar))))))
                 when entry collect entry)))
    (when sendable
      (let ((custody-mask (make-byte-vector 16)))
        ;; geth encodes custody bits little-endian within each byte.  A full
        ;; local blob plus callable cell computation means we can answer every
        ;; one of the 128 cell indices; otherwise the honest announcement is
        ;; the all-zero mask.
        (when (and (>= (eth-peer-eth-version peer)
                       +eth-protocol-version-72+)
                   sidecar-reader
                   (kzg-cell-computation-available-p)
                   (some (lambda (entry)
                           (typep (eth-pooled-entry-transaction entry)
                                  'blob-transaction))
                         sendable))
          (fill custody-mask #xff))
        (eth-peer-send peer +eth-message-new-pooled-transaction-hashes+
                       (encode-eth-new-pooled-transaction-hashes
                        sendable :version (eth-peer-eth-version peer)
                                 :custody-mask custody-mask)))
      (eth-peer-note-known-transactions peer sendable))
    (length sendable)))

;;; Receiving.

(defun eth-validate-omitted-blob-payload (sidecar transaction)
  "Validate an eth/72 pooled blob wrapper whose blob list is intentionally empty.

ETH/72 keeps the commitments and version-1 cell proofs in PooledTransactions,
but retrieves the cells through GetCells.  This check authenticates the
commitments against the signed transaction and bounds the proof material.  It
does not turn the fragment into a full blob sidecar."
  (let* ((blobs (blob-sidecar-blobs sidecar))
         (commitments (blob-sidecar-commitments sidecar))
         (proofs (blob-sidecar-proofs sidecar))
         (commitment-count (length commitments)))
    (unless (and (null blobs) (plusp commitment-count))
      (ethereum-lisp.validation:block-validation-fail
       "eth/72 omitted blob wrapper must contain commitments but no blobs"))
    (unless (= commitment-count
               (ethereum-lisp.consensus:transaction-blob-count transaction))
      (ethereum-lisp.validation:block-validation-fail
       "eth/72 omitted blob wrapper commitment count does not match transaction"))
    (unless (= (length proofs)
               (* commitment-count +cell-proofs-per-blob+))
      (ethereum-lisp.validation:block-validation-fail
       "eth/72 omitted blob wrapper must carry cell proofs for every commitment"))
    (dolist (commitment commitments)
      (ethereum-lisp.consensus:validate-sized-byte-vector
       commitment ethereum-lisp.crypto:+kzg-commitment-size+ "KZG commitment"))
    (dolist (proof proofs)
      (ethereum-lisp.consensus:validate-sized-byte-vector
       proof +kzg-proof-size+ "KZG cell proof"))
    (loop for actual in (blob-sidecar-versioned-hashes sidecar)
          for expected across (transaction-blob-versioned-hashes transaction)
          unless (bytes= (hash32-bytes actual)
                         (blob-versioned-hash-bytes expected))
            do (ethereum-lisp.validation:block-validation-fail
                "eth/72 omitted blob wrapper commitment does not match transaction"))
    t))

(defun eth-accept-transactions
    (backend transactions
     &key allow-omitted-blob-payload-p omitted-blob-function)
  "Offer TRANSACTIONS to the backend's pool, and return how many it took.

A transaction the pool turns down — badly signed, underpriced, a nonce too far
ahead — is skipped rather than raised as a session error. Peers relay freely and
do not pre-filter for us, so one unusable transaction in a batch must not cost
us the connection.  A valid eth/72 pooled wrapper that intentionally omits blob
payloads is commitment-checked and passed to OMITTED-BLOB-FUNCTION, when given;
it remains out of the pool until the cell fetcher assembles and verifies its
full data."
  (let ((accept (eth-serve-backend-accept-transaction backend))
        (accept-batch (eth-serve-backend-accept-transactions backend))
        (accept-sidecar
          (eth-serve-backend-accept-blob-sidecar backend))
        (accepted 0))
    ;; The ordinary Transactions path has no sidecars. Let a production backend
    ;; amortize sender-state and contiguous-prefix work across the wire batch;
    ;; protocol-only backends retain the historical per-entry callback.
    (when (and accept-batch
               (every (lambda (entry)
                        (and (not (consp entry))
                             (not (typep entry 'blob-network-transaction))
                             (not (typep entry 'blob-transaction))))
                      transactions))
      (return-from eth-accept-transactions
        (funcall accept-batch transactions)))
    (when accept
      (dolist (entry transactions)
        (let ((transaction entry)
              (sidecar nil))
          (cond
            ((typep entry 'blob-network-transaction)
             (setf transaction (blob-network-transaction-transaction entry)
                   sidecar (blob-network-transaction-sidecar entry)))
            ((and (consp entry)
                  (typep (car entry) 'blob-transaction)
                  (typep (cdr entry) 'blob-sidecar))
             (setf transaction (car entry)
                   sidecar (cdr entry))))
          (when sidecar
            (if (and allow-omitted-blob-payload-p
                     (typep transaction 'blob-transaction)
                     (null (blob-sidecar-blobs sidecar))
                     (plusp (length (blob-sidecar-commitments sidecar))))
                (progn
                  (eth-validate-omitted-blob-payload sidecar transaction)
                  (when omitted-blob-function
                    (funcall omitted-blob-function transaction sidecar))
                  (setf sidecar nil))
                (progn
                  (validate-blob-sidecar-fields
                   sidecar :transaction transaction
                   :require-proof-verification t)
                  (unless accept-sidecar
                    (error "Received blob transaction but no sidecar store is configured"))
                  (funcall accept-sidecar sidecar))))
          (when (and (or (not (typep transaction 'blob-transaction)) sidecar)
                     (ignore-errors (funcall accept transaction) t))
            (incf accepted)))))
    accepted))

(defun eth-peer-pending-blob-cell-fetch-count (peer)
  "How many validated eth/72 pooled wrappers await GetCells from PEER."
  (length (eth-peer-pending-blob-cell-fetches peer)))

(defun eth-peer-queue-omitted-blob-transaction (peer transaction sidecar)
  "Queue one validated eth/72 TRANSACTION/SIDECAR fragment for top-level fetch."
  (let* ((hash (hash32-bytes (transaction-hash transaction)))
         (queued (eth-peer-pending-blob-cell-fetches peer)))
    (when (and (< (length queued) +eth-max-pending-blob-cell-fetches+)
               (not (find hash queued
                          :key (lambda (entry)
                                 (hash32-bytes
                                  (transaction-hash (car entry))))
                          :test #'bytes=)))
      (setf (eth-peer-pending-blob-cell-fetches peer)
            (append queued (list (cons transaction sidecar))))
      t)))

(defun eth-peer-take-omitted-blob-transaction (peer)
  "Remove and return the oldest eth/72 pooled wrapper awaiting GetCells."
  (let ((queued (eth-peer-pending-blob-cell-fetches peer)))
    (when queued
      (setf (eth-peer-pending-blob-cell-fetches peer) (rest queued))
      (first queued))))

(defun eth-peer-announced-hash-table (peer)
  (or (eth-peer-announced-hashes peer)
      (setf (eth-peer-announced-hashes peer)
            (make-hash-table :test #'equalp))))

(defun eth-peer-announced-hash-count (peer)
  "How many announced hashes are queued for PEER."
  (let ((table (eth-peer-announced-hashes peer)))
    (if table (hash-table-count table) 0)))

(defun eth-peer-announced-block-count (peer)
  (length (eth-peer-announced-block-hashes peer)))

(defun eth-peer-queue-announced-blocks (peer announcements)
  "Queue fresh block hash announcements in peer order, returning how many."
  (let ((queued (eth-peer-announced-block-hashes peer))
        (added 0))
    (dolist (announcement announcements)
      (when (>= (length queued) +eth-max-announced-block-hashes+)
        (return))
      (let ((hash (eth-new-block-hash-hash announcement)))
        (when (and (= (length hash) 32)
                   (not (find hash queued
                              :key #'eth-new-block-hash-hash
                              :test #'bytes=)))
          (setf queued (append queued (list announcement)))
          (incf added))))
    (setf (eth-peer-announced-block-hashes peer) queued)
    added))

(defun eth-peer-take-announced-block (peer)
  "Remove and return the oldest block-hash announcement from PEER."
  (let ((queued (eth-peer-announced-block-hashes peer)))
    (when queued
      (setf (eth-peer-announced-block-hashes peer) (rest queued))
      (first queued))))

(defun eth-accept-propagated-block (backend block)
  (let ((accept (eth-serve-backend-accept-block backend)))
    (when accept
      ;; Every signaled failure reaches the session supervisor. A malformed
      ;; bundle may disconnect one peer; a storage/capability/program failure
      ;; must never be converted into a false successful admission.
      (funcall accept block)
      t)))

(defstruct (eth-transaction-announcement
            (:constructor make-eth-transaction-announcement (hash type size)))
  hash
  type
  size)

(defstruct (eth-pooled-transaction-request
            (:constructor make-eth-pooled-transaction-request
                (announcements started-at)))
  announcements
  started-at)

(defun eth-peer-queue-announced-hashes
    (peer backend hashes &key types sizes)
  "Queue the announced HASHES worth asking PEER for, and return how many.

A hash we already hold is dropped here rather than at fetch time, so a peer
re-announcing what we have costs nothing. TYPES and SIZES, when supplied, are
retained so a fetched response must match what this peer advertised."
  (let ((known (eth-serve-backend-known-transaction-p backend))
        (table (eth-peer-announced-hash-table peer))
        (added 0))
    (loop for hash in hashes
          for index from 0
          do
      (when (>= (hash-table-count table) +eth-max-announced-transaction-hashes+)
        (return))
      (when (and (= (length hash) 32)
                 (not (gethash hash table))
                 (not (and known (funcall known hash))))
        (setf (gethash hash table)
              (make-eth-transaction-announcement
               hash (when types (nth index types))
               (when sizes (nth index sizes))))
        (incf added)))
    added))

(defun eth-pooled-blob-sidecar-reader (backend version)
  "Select the sidecar representation negotiated by eth VERSION.

ETH/68--71 serves the EIP-4844 wrapper with one blob proof per blob. ETH/72
serves the version-1 wrapper with cell proofs. The fallback in each direction
keeps protocol-only backends which expose one historical callback working, but
the production backend exposes both and therefore never changes wire shape by
accident."
  (if (>= version +eth-protocol-version-72+)
      (or (eth-serve-backend-pooled-blob-sidecar backend)
          (eth-serve-backend-pooled-transaction-sidecar backend))
      (or (eth-serve-backend-pooled-transaction-sidecar backend)
          (eth-serve-backend-pooled-blob-sidecar backend))))

(defun eth-serve-pooled-transactions
    (backend hashes &key (version +eth-protocol-version-71+))
  "The transactions from HASHES that we still hold, in request order.

Hashes we cannot serve are left out: the reply may be short and reordered, and
the peer matches it up by hash rather than by position."
  (let ((pooled (eth-serve-backend-pooled-transaction backend))
        (sidecar-reader
          (eth-pooled-blob-sidecar-reader backend version))
        (found '())
        (examined 0))
    (when pooled
      (dolist (hash hashes)
        (when (>= examined +eth-max-pooled-transactions-serve+)
          (return))
        (incf examined)
        (let ((transaction (when (= (length hash) 32) (funcall pooled hash))))
          (cond
            ((and (typep transaction 'blob-transaction) sidecar-reader)
             (let ((sidecar (funcall sidecar-reader transaction)))
               (when sidecar
                 (push (make-blob-network-transaction transaction sidecar)
                       found))))
            ((and transaction (eth-gossipable-transaction-p transaction))
             (push transaction found))))))
    (nreverse found)))

(defun eth-peer-take-announced-hashes (peer limit &key metadata-p)
  "Remove and return up to LIMIT of PEER's queued announced hashes.

They leave the queue before the request goes out, so a peer that never answers
does not leave the same hashes to be asked for again on every later fetch. With
METADATA-P, return the retained announcement records instead of bare hashes."
  (let ((table (eth-peer-announced-hashes peer))
        (taken '())
        (count 0))
    (when table
      (block collect
        (loop for hash being the hash-keys of table
              using (hash-value announcement)
              do (push (if metadata-p announcement hash) taken)
                 (incf count)
                 (when (>= count limit)
                   (return-from collect))))
      (dolist (item taken)
        (remhash (if metadata-p
                     (eth-transaction-announcement-hash item)
                     item)
                 table)))
    (nreverse taken)))

(defun eth-peer-pending-pooled-transaction-request-table (peer)
  (or (eth-peer-pending-pooled-transaction-requests peer)
      (setf (eth-peer-pending-pooled-transaction-requests peer)
            (make-hash-table :test #'eql))))

(defun eth-pooled-transaction-request-expired-p (request now)
  (>= (- now (eth-pooled-transaction-request-started-at request))
      +eth-pooled-transaction-request-timeout-seconds+))

(defun eth-peer-prune-expired-pooled-transaction-requests (peer now)
  (let ((table (eth-peer-pending-pooled-transaction-requests peer))
        (expired '()))
    (when table
      (maphash
       (lambda (request-id request)
         (when (eth-pooled-transaction-request-expired-p request now)
           (push request-id expired)))
       table)
      (dolist (request-id expired)
        (remhash request-id table)))
    (length expired)))

(defun eth-peer-can-request-announced-transactions-p (peer now)
  "Whether a new async transaction fetch fits after logical timeout expiry."
  (let ((table (eth-peer-pending-pooled-transaction-requests peer))
        (live 0))
    (when table
      (maphash
       (lambda (request-id request)
         (declare (ignore request-id))
         (unless (eth-pooled-transaction-request-expired-p request now)
           (incf live)))
       table))
    (< live +eth-max-pending-pooled-transaction-requests+)))

(defun eth-pooled-entry-announcement-size (entry)
  (let ((transaction (eth-pooled-entry-transaction entry))
        (sidecar (eth-pooled-entry-sidecar entry)))
    (length (if sidecar
                (blob-pooled-transaction-encoding transaction sidecar)
                (transaction-encoding transaction)))))

(defun eth-validate-pooled-transaction-response (announcements transactions)
  "Require every returned transaction to match one requested announcement."
  (let ((remaining (copy-list announcements)))
    (dolist (entry transactions)
      (let* ((transaction (eth-pooled-entry-transaction entry))
             (hash (hash32-bytes (transaction-hash transaction)))
             (announcement
               (find hash remaining
                     :key #'eth-transaction-announcement-hash
                     :test #'bytes=)))
        (unless announcement
          (eth-peer-protocol-fail
           "PooledTransactions returned an unrequested transaction ~A"
           (bytes-to-hex hash)))
        (let ((expected-type (eth-transaction-announcement-type announcement))
              (expected-size (eth-transaction-announcement-size announcement)))
          (when (and expected-type
                     (/= expected-type (transaction-type transaction)))
            (eth-peer-protocol-fail
             "PooledTransactions type ~D does not match announced type ~D"
             (transaction-type transaction) expected-type))
          (when (and expected-size
                     (/= expected-size
                         (eth-pooled-entry-announcement-size entry)))
            (eth-peer-protocol-fail
             "PooledTransactions size ~D does not match announced size ~D"
             (eth-pooled-entry-announcement-size entry) expected-size)))
        (setf remaining (remove announcement remaining :count 1 :test #'eq)))))
  t)

(defun eth-peer-validate-pending-pooled-transaction-response
    (peer request-id transactions)
  "Validate and retire REQUEST-ID when it belongs to our async fetch path."
  (let ((table (eth-peer-pending-pooled-transaction-requests peer)))
    (when table
      (multiple-value-bind (announcements present-p) (gethash request-id table)
        (when present-p
          (remhash request-id table)
          (eth-validate-pooled-transaction-response
           (eth-pooled-transaction-request-announcements announcements)
           transactions)))))
  t)

(defun eth-peer-request-announced-transactions
    (peer &key (limit +eth-max-pooled-transactions-serve+)
               (now (get-universal-time)))
  "Ask PEER for up to LIMIT of the transactions it announced, WITHOUT waiting.

Returns how many hashes were asked for. The reply is not awaited: it arrives as
an ordinary PooledTransactions message, where its request id selects the retained
announcement metadata before pool admission.

This is the version a session loop uses. Waiting here instead would hand a peer
the ability to pin the loop indefinitely by announcing one hash and going quiet,
which is a completely ordinary thing for a peer to do. The waiting version,
ETH-PEER-FETCH-ANNOUNCED-TRANSACTIONS, remains correct for a one-shot exchange
that has nothing else to do."
  (eth-peer-prune-expired-pooled-transaction-requests peer now)
  (let ((pending (eth-peer-pending-pooled-transaction-request-table peer)))
    (when (>= (hash-table-count pending)
              +eth-max-pending-pooled-transaction-requests+)
      (return-from eth-peer-request-announced-transactions 0))
    (let ((announcements
            (eth-peer-take-announced-hashes peer limit :metadata-p t)))
      (when announcements
        (let ((request-id (eth-peer-next-request-id peer)))
          (eth-peer-send
           peer +eth-message-get-pooled-transactions+
           (encode-eth-get-pooled-transactions
            request-id
            (mapcar #'eth-transaction-announcement-hash announcements)))
          (setf (gethash request-id pending)
                (make-eth-pooled-transaction-request announcements now))))
      (length announcements))))

;;; Dispatch, reached from ETH-PEER-HANDLE-MESSAGE.

(defun eth-accept-inbound-transactions-p (backend)
  "Whether BACKEND currently accepts inbound transaction gossip.

The predicate is evaluated before decoding the three transaction-delivery
messages, matching pinned geth's Backend.AcceptTxs gate. A backend which omits
the predicate retains the protocol library's historical accepting behavior."
  (let ((predicate
          (eth-serve-backend-accept-transactions-p backend)))
    (or (null predicate) (funcall predicate))))

(defun eth-peer-gossip-message (peer eth-id payload)
  "Handle one gossip message from PEER, returning T if it was one."
  (cond
    ((= eth-id +eth-message-block-range-update+)
     (when (< (eth-peer-eth-version peer) +eth-protocol-version-69+)
       (error "eth/68 peer sent an eth/69 BlockRangeUpdate"))
     (let ((range (decode-eth-block-range-update payload)))
       (eth-validate-block-range
        (eth-block-range-earliest-block range)
        (eth-block-range-latest-block range)
        (eth-block-range-latest-block-hash range))
       (let* ((status (eth-peer-remote-status peer))
              (changed-p
                (or (/= (eth-status-earliest-block status)
                        (eth-block-range-earliest-block range))
                    (/= (eth-status-latest-block status)
                        (eth-block-range-latest-block range))
                    (not
                     (bytes=
                      (eth-status-latest-block-hash status)
                      (eth-block-range-latest-block-hash range))))))
         (setf (eth-status-earliest-block status)
               (eth-block-range-earliest-block range)
               (eth-status-latest-block status)
               (eth-block-range-latest-block range)
               (eth-status-latest-block-hash status)
               (eth-block-range-latest-block-hash range))
         (when changed-p
           (eth-peer-notify-sync-announcement peer))))
     t)
    (t
     (let ((backend (eth-peer-serve-backend peer)))
       (when backend
         (cond
        ((= eth-id +eth-message-new-block-hashes+)
         (when (plusp
                (eth-peer-queue-announced-blocks
                 peer (decode-eth-new-block-hashes payload)))
           (eth-peer-notify-sync-announcement peer))
         t)
        ((= eth-id +eth-message-new-block+)
         (eth-accept-propagated-block
          backend
          (eth-new-block-block (decode-eth-new-block payload)))
         t)
        ((= eth-id +eth-message-transactions+)
         (when (eth-accept-inbound-transactions-p backend)
           (let ((transactions (decode-eth-transactions payload)))
             (eth-peer-note-known-transactions peer transactions)
             (eth-accept-transactions backend transactions)))
         t)
        ((= eth-id +eth-message-new-pooled-transaction-hashes+)
         (when (eth-accept-inbound-transactions-p backend)
           (multiple-value-bind (types sizes hashes custody-mask)
               (decode-eth-new-pooled-transaction-hashes
                payload (eth-peer-eth-version peer))
             (declare (ignore custody-mask))
             (eth-peer-note-known-transaction-hashes peer hashes)
             (eth-peer-queue-announced-hashes
              peer backend hashes :types types :sizes sizes)))
         t)
        ((= eth-id +eth-message-get-pooled-transactions+)
         (multiple-value-bind (request-id hashes)
             (decode-eth-get-pooled-transactions payload)
           (eth-peer-send peer +eth-message-pooled-transactions+
                          (encode-eth-pooled-transactions
                           request-id
                           (eth-serve-pooled-transactions
                            backend hashes
                            :version (eth-peer-eth-version peer)))))
         t)
        ((= eth-id +eth-message-pooled-transactions+)
         (when (eth-accept-inbound-transactions-p backend)
           ;; A reply nobody is waiting for, because the requester gave up or
           ;; the peer sent it unasked. Take it only after the same fresh-chain
           ;; gate as direct deliveries and announcements.
           (multiple-value-bind (request-id transactions)
               (decode-eth-pooled-transactions payload)
             (eth-peer-validate-pending-pooled-transaction-response
              peer request-id transactions)
             (eth-accept-transactions
              backend transactions
              :allow-omitted-blob-payload-p
              (>= (eth-peer-eth-version peer) +eth-protocol-version-72+)
              :omitted-blob-function
              (lambda (transaction sidecar)
                (eth-peer-queue-omitted-blob-transaction
                 peer transaction sidecar)))))
         t)
           (t nil)))))))
