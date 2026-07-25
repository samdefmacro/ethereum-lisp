(in-package #:ethereum-lisp.eth-sync)

;;;; Answering a peer's eth requests.
;;;;
;;;; A node that only asks is not a peer. Header, body, and receipt queries
;;;; that go unanswered cost a client nothing to notice, and it eventually
;;;; drops the connection; serving them is what makes us useful to the network
;;;; rather than a leech on it. This is the responder half of the protocol,
;;;; matching go-ethereum's eth/protocols/eth/handlers.go traversal and serve
;;;; limits.
;;;;
;;;; The chain being served is reached through a backend of closures rather
;;;; than a store type, keeping this layer independent of storage exactly as
;;;; the download driver keeps import behind a callback. A node with no backend
;;;; installed simply does not answer, which is the old behavior.

;;; Serve limits, from go-ethereum. The count caps bound how much work one
;;; request can ask of us; the byte limit is soft — it stops the reply after
;;; the item that crossed it, so a single oversized item is still served.

(defconstant +eth-max-headers-serve+ 1024)
(defconstant +eth-max-bodies-serve+ 256)
(defconstant +eth-max-receipts-serve+ 1024)
(defconstant +eth-soft-response-limit+ (* 2 1024 1024))

(defstruct (eth-serve-backend
            (:constructor make-eth-serve-backend
                (&key block-by-number block-by-hash)))
  "Read-only access to the chain a peer's requests are answered from.

BLOCK-BY-NUMBER returns the canonical block at a block number; BLOCK-BY-HASH
returns any known block, canonical or not, by its 32-byte hash. Both return NIL
for a block we do not have."
  block-by-number
  block-by-hash)

(defun eth-serve-block-by-number (backend number)
  (let ((reader (eth-serve-backend-block-by-number backend)))
    (when (and reader (>= number 0))
      (funcall reader number))))

(defun eth-serve-block-by-hash (backend hash)
  (let ((reader (eth-serve-backend-block-by-hash backend)))
    (when (and reader (= (length hash) 32))
      (funcall reader hash))))

;;; GetBlockHeaders.
;;;
;;; The query walks from an origin — a block number, or a hash for a block that
;;; may be off the canonical chain — taking every SKIP+1'th header. Number-mode
;;; traversal is a plain arithmetic walk over canonical blocks. Hash mode has
;;; to stay on the origin's own branch: walking backwards follows parent links,
;;; and walking forwards checks that the canonical block it lands on really
;;; descends from the block just served, so a query anchored to a side chain is
;;; cut short rather than answered with canonical blocks.

(defun eth-serve-ancestor-hash (backend hash steps)
  "The hash STEPS parent links back from the block HASH, or NIL if the walk
leaves the blocks we hold or runs past genesis."
  (let ((current hash))
    (loop repeat steps
          do (let ((block (eth-serve-block-by-hash backend current)))
               (when (null block)
                 (return-from eth-serve-ancestor-hash nil))
               (let ((header (block-header block)))
                 (when (zerop (block-header-number header))
                   (return-from eth-serve-ancestor-hash nil))
                 (setf current (hash32-bytes
                                (block-header-parent-hash header))))))
    current))

(defun eth-serve-headers (backend request)
  "Resolve a GetBlockHeaders REQUEST against BACKEND and return the headers.

Stops at the first block we do not have, at the request's amount, at
+ETH-MAX-HEADERS-SERVE+, or once the reply has passed the soft size limit."
  (let* ((hash-mode (and (eth-get-block-headers-origin-hash request) t))
         (reverse (eth-get-block-headers-reverse request))
         (step (1+ (eth-get-block-headers-skip request)))
         (amount (min (eth-get-block-headers-amount request)
                      +eth-max-headers-serve+))
         (hash (eth-get-block-headers-origin-hash request))
         (number (or (eth-get-block-headers-origin-number request) 0))
         (headers '())
         (served 0)
         (bytes 0))
    (loop
      (when (or (>= served amount) (>= bytes +eth-soft-response-limit+))
        (return))
      (let ((block (if hash-mode
                       (eth-serve-block-by-hash backend hash)
                       (eth-serve-block-by-number backend number))))
        (when (null block)
          (return))
        (let ((header (block-header block)))
          (push header headers)
          (incf served)
          (incf bytes (length (rlp-encode (block-header-rlp-object header))))
          (setf number (block-header-number header))
          (cond
            ((and hash-mode reverse)
             (let ((ancestor (eth-serve-ancestor-hash backend hash step)))
               (when (null ancestor)
                 (return))
               (setf hash ancestor)
               (decf number step)))
            (hash-mode
             (let* ((next (+ number step))
                    (next-block (eth-serve-block-by-number backend next))
                    (next-hash (when next-block
                                 (hash32-bytes (block-hash next-block))))
                    (ancestor (when next-hash
                                (eth-serve-ancestor-hash backend next-hash step))))
               (unless (and ancestor (bytes= ancestor hash))
                 (return))
               (setf hash next-hash)
               (setf number next)))
            (reverse
             (when (< number step)
               (return))
             (decf number step))
            (t
             (incf number step))))))
    (nreverse headers)))

;;; GetBlockBodies and GetReceipts. Both walk the requested hashes in order,
;;; skipping blocks we do not have; the reply is a list of what we found, not a
;;; positional answer, so a gap simply means we could not serve that block.

(defun eth-serve-bodies (backend hashes)
  "The wire bodies of the blocks named by HASHES that we hold."
  (let ((bodies '())
        (bytes 0)
        (examined 0))
    (dolist (hash hashes)
      (when (or (>= examined +eth-max-bodies-serve+)
                (>= bytes +eth-soft-response-limit+))
        (return))
      (incf examined)
      (let ((block (eth-serve-block-by-hash backend hash)))
        (when block
          (let ((body (block-eth-body block)))
            (incf bytes (length (rlp-encode (eth-block-body-rlp-object body))))
            (push body bodies)))))
    (nreverse bodies)))

(defun eth-serve-receipts-available-p (block)
  "Whether BLOCK carries a receipt for every transaction, and so can be served.

A block whose receipts were never stored — one accepted as a header and body
without execution — is skipped rather than answered with a short list, which a
peer would read as a shorter transaction list."
  (= (length (block-transactions block))
     (length (block-receipts block))))

(defun eth-serve-receipt-blocks (backend hashes version)
  "The blocks named by HASHES whose receipts we can serve, in request order.

Blocks are returned rather than encoded receipts because the wire encoding
needs each receipt's transaction type, and VERSION decides the layout."
  (let ((blocks '())
        (bytes 0)
        (examined 0))
    (dolist (hash hashes)
      (when (or (>= examined +eth-max-receipts-serve+)
                (>= bytes +eth-soft-response-limit+))
        (return))
      (incf examined)
      (let ((block (eth-serve-block-by-hash backend hash)))
        (when (and block (eth-serve-receipts-available-p block))
          (incf bytes (length (rlp-encode
                               (eth-block-receipts-rlp-object block version))))
          (push block blocks))))
    (nreverse blocks)))

;;; Dispatch.

(defun eth-peer-serve-message (peer eth-id payload)
  "Answer PEER's message when it is a request we serve, and return T if so.

Returns NIL for anything else — including every message when the peer has no
serve backend — so the caller can handle it."
  (let ((backend (eth-peer-serve-backend peer)))
    (when backend
      (cond
        ((= eth-id +eth-message-get-block-headers+)
         (let ((request (decode-eth-get-block-headers payload)))
           (eth-peer-send peer +eth-message-block-headers+
                          (encode-eth-block-headers
                           (eth-get-block-headers-request-id request)
                           (eth-serve-headers backend request))))
         t)
        ((= eth-id +eth-message-get-block-bodies+)
         (multiple-value-bind (request-id hashes)
             (decode-eth-get-block-bodies payload)
           (eth-peer-send peer +eth-message-block-bodies+
                          (encode-eth-block-bodies
                           request-id (eth-serve-bodies backend hashes))))
         t)
        ((= eth-id +eth-message-get-receipts+)
         (multiple-value-bind (request-id hashes)
             (decode-eth-get-receipts payload)
           (let ((version (eth-peer-eth-version peer)))
             (eth-peer-send peer +eth-message-receipts+
                            (encode-eth-receipts
                             request-id
                             (eth-serve-receipt-blocks backend hashes version)
                             version))))
         t)
        (t nil)))))

(defun eth-peer-handle-message (peer eth-id payload)
  "Handle one inbound eth message that we did not ask for, returning T if it
was handled. This is the single entry point shared by the message pump and by
the request/reply helpers, which serve while they wait for their own reply."
  (eth-peer-serve-message peer eth-id payload))

(defun eth-peer-serve-loop (peer &key max-messages continue-p)
  "Read messages from PEER and handle them, returning the number handled.

Runs until the connection ends, until MAX-MESSAGES have been read, or until
CONTINUE-P returns false. CONTINUE-P is consulted between messages, so a
blocked read is interrupted by closing the socket rather than by this loop."
  (let ((handled 0))
    (loop
      (when (or (and max-messages (>= handled max-messages))
                (and continue-p (not (funcall continue-p))))
        (return handled))
      (multiple-value-bind (eth-id payload) (eth-peer-read peer)
        (eth-peer-handle-message peer eth-id payload)
        (incf handled)))))
