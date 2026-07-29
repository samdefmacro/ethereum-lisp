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
             (hash32-bytes (transaction-hash transaction)))
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
           (and backend (eth-serve-backend-pooled-blob-sidecar backend)))
         (sendable
           (remove-if-not
            (lambda (transaction)
              (and (not (eth-peer-knows-transaction-p peer transaction))
                   (or (eth-gossipable-transaction-p transaction)
                       (and sidecar-reader
                            (funcall sidecar-reader transaction)))))
            transactions)))
    (when sendable
      (eth-peer-send peer +eth-message-new-pooled-transaction-hashes+
                     (encode-eth-new-pooled-transaction-hashes
                      sendable :version (eth-peer-eth-version peer)))
      (eth-peer-note-known-transactions peer sendable))
    (length sendable)))

;;; Receiving.

(defun eth-accept-transactions (backend transactions)
  "Offer TRANSACTIONS to the backend's pool, and return how many it took.

A transaction the pool turns down — badly signed, underpriced, a nonce too far
ahead — is skipped rather than raised as a session error. Peers relay freely and
do not pre-filter for us, so one unusable transaction in a batch must not cost
us the connection."
  (let ((accept (eth-serve-backend-accept-transaction backend))
        (accept-sidecar
          (eth-serve-backend-accept-blob-sidecar backend))
        (accepted 0))
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
            (validate-blob-sidecar-fields
             sidecar :transaction transaction :require-proof-verification t)
            (unless accept-sidecar
              (error "Received blob transaction but no sidecar store is configured"))
            (funcall accept-sidecar sidecar))
          (when (and (or (not (typep transaction 'blob-transaction)) sidecar)
                     (ignore-errors (funcall accept transaction) t))
            (incf accepted)))))
    accepted))

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
      ;; Invalid propagation is a peer-quality event, not a session-fatal
      ;; protocol error. The backend performs all consensus validation.
      (ignore-errors (funcall accept block) t))))

(defun eth-peer-queue-announced-hashes (peer backend hashes)
  "Queue the announced HASHES worth asking PEER for, and return how many.

A hash we already hold is dropped here rather than at fetch time, so a peer
re-announcing what we have costs nothing."
  (let ((known (eth-serve-backend-known-transaction-p backend))
        (table (eth-peer-announced-hash-table peer))
        (added 0))
    (dolist (hash hashes added)
      (when (>= (hash-table-count table) +eth-max-announced-transaction-hashes+)
        (return added))
      (when (and (= (length hash) 32)
                 (not (gethash hash table))
                 (not (and known (funcall known hash))))
        (setf (gethash hash table) t)
        (incf added)))))

(defun eth-serve-pooled-transactions (backend hashes)
  "The transactions from HASHES that we still hold, in request order.

Hashes we cannot serve are left out: the reply may be short and reordered, and
the peer matches it up by hash rather than by position."
  (let ((pooled (eth-serve-backend-pooled-transaction backend))
        (sidecar-reader
          (or (eth-serve-backend-pooled-blob-sidecar backend)
              (eth-serve-backend-pooled-transaction-sidecar backend)))
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

(defun eth-peer-take-announced-hashes (peer limit)
  "Remove and return up to LIMIT of PEER's queued announced hashes.

They leave the queue before the request goes out, so a peer that never answers
does not leave the same hashes to be asked for again on every later fetch."
  (let ((table (eth-peer-announced-hashes peer))
        (taken '())
        (count 0))
    (when table
      (block collect
        (loop for hash being the hash-keys of table
              do (push hash taken)
                 (incf count)
                 (when (>= count limit)
                   (return-from collect))))
      (dolist (hash taken)
        (remhash hash table)))
    (nreverse taken)))

(defun eth-peer-request-announced-transactions
    (peer &key (limit +eth-max-pooled-transactions-serve+))
  "Ask PEER for up to LIMIT of the transactions it announced, WITHOUT waiting.

Returns how many hashes were asked for. The reply is not awaited: it arrives as
an ordinary PooledTransactions message and is absorbed by the unsolicited branch
of ETH-PEER-GOSSIP-MESSAGE, which pools it like any other.

This is the version a session loop uses. Waiting here instead would hand a peer
the ability to pin the loop indefinitely by announcing one hash and going quiet,
which is a completely ordinary thing for a peer to do. The waiting version,
ETH-PEER-FETCH-ANNOUNCED-TRANSACTIONS, remains correct for a one-shot exchange
that has nothing else to do."
  (let ((wanted (eth-peer-take-announced-hashes peer limit)))
    (when wanted
      (eth-peer-send peer +eth-message-get-pooled-transactions+
                     (encode-eth-get-pooled-transactions
                      (eth-peer-next-request-id peer) wanted)))
    (length wanted)))

;;; Dispatch, reached from ETH-PEER-HANDLE-MESSAGE.

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
       (let ((status (eth-peer-remote-status peer)))
         (setf (eth-status-earliest-block status)
               (eth-block-range-earliest-block range)
               (eth-status-latest-block status)
               (eth-block-range-latest-block range)
               (eth-status-latest-block-hash status)
               (eth-block-range-latest-block-hash range))))
     t)
    (t
     (let ((backend (eth-peer-serve-backend peer)))
       (when backend
         (cond
        ((= eth-id +eth-message-new-block-hashes+)
         (eth-peer-queue-announced-blocks
          peer (decode-eth-new-block-hashes payload))
         t)
        ((= eth-id +eth-message-new-block+)
         (eth-accept-propagated-block
          backend
          (eth-new-block-block (decode-eth-new-block payload)))
         t)
        ((= eth-id +eth-message-transactions+)
         (let ((transactions (decode-eth-transactions payload)))
           (eth-peer-note-known-transactions peer transactions)
           (eth-accept-transactions backend transactions))
         t)
        ((= eth-id +eth-message-new-pooled-transaction-hashes+)
         (multiple-value-bind (types sizes hashes custody-mask)
             (decode-eth-new-pooled-transaction-hashes
              payload (eth-peer-eth-version peer))
           ;; The type and size columns only help a fetcher decide what to ask
           ;; for first; we fetch in announcement order and ignore them.
           (declare (ignore types sizes custody-mask))
           (eth-peer-note-known-transaction-hashes peer hashes)
           (eth-peer-queue-announced-hashes peer backend hashes))
         t)
        ((= eth-id +eth-message-get-pooled-transactions+)
         (multiple-value-bind (request-id hashes)
             (decode-eth-get-pooled-transactions payload)
           (eth-peer-send peer +eth-message-pooled-transactions+
                          (encode-eth-pooled-transactions
                           request-id
                           (eth-serve-pooled-transactions backend hashes))))
         t)
        ((= eth-id +eth-message-pooled-transactions+)
         ;; A reply nobody is waiting for, because the requester gave up or the
         ;; peer sent it unasked. The transactions are still good, so take them.
         (multiple-value-bind (request-id transactions)
             (decode-eth-pooled-transactions payload)
           (declare (ignore request-id))
           (eth-accept-transactions backend transactions))
         t)
           (t nil)))))))
