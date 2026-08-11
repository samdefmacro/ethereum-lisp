(in-package #:ethereum-lisp.eth-sync)

;;;; Driving a session: waiting for a reply, dispatching what else arrives, and
;;;; downloading blocks.
;;;;
;;;; Everything that sends a request and waits for its reply lives here,
;;;; together with the dispatcher that decides what to do with the messages
;;;; arriving in between — the request handlers in serve.lisp and the gossip
;;;; handlers in gossip.lisp — so that neither of those files depends on the
;;;; other or on the loop that drives them.
;;;;
;;;; eth/66 wraps every request and its reply in a request id, so a reply can be
;;;; matched to the request that asked for it. These helpers send a request and
;;;; then read eth messages until the reply with the matching id arrives,
;;;; handling whatever else the peer sends (and, thanks to the transport,
;;;; answering base-protocol keepalives) in between.

(defun eth-peer-handle-message (peer eth-id payload)
  "Handle one inbound eth message we did not ask for, returning T if it was
handled. The single entry point shared by the session loop and by every
request/reply helper, which serve and gossip while they wait for their reply."
  (or (eth-peer-serve-message peer eth-id payload)
      (eth-peer-gossip-message peer eth-id payload)))

(defun eth-peer-serve-loop (peer &key max-messages continue-p)
  "Read messages from PEER and handle them, returning the number handled.

Runs until the connection ends, until MAX-MESSAGES have been read, or until
CONTINUE-P returns false. CONTINUE-P is consulted between messages, so a read
already blocked is ended by closing the socket, not by this loop."
  (let ((handled 0))
    (loop
      (when (or (and max-messages (>= handled max-messages))
                (and continue-p (not (funcall continue-p))))
        (return handled))
      (multiple-value-bind (eth-id payload) (eth-peer-read peer)
        (eth-peer-handle-message peer eth-id payload)
        (incf handled)))))

(defconstant +eth-max-skipped-messages+ 256
  "How many unrelated eth messages to handle while awaiting a matching reply
before giving up. Requests we answer count against this too, so a peer that
floods us with requests eventually costs us our own reply rather than pinning
the connection open.")

(defun eth-peer-await (peer expected-eth-id request-id decoder)
  "Read eth messages from PEER until one of EXPECTED-ETH-ID whose DECODER result
matches REQUEST-ID, and return the decoded payload.

DECODER is applied to the message payload and must return (VALUES ID RESULT);
RESULT is returned once ID equals REQUEST-ID. Anything else the peer sends is
passed to ETH-PEER-HANDLE-MESSAGE first, so the peer's own requests are answered
while we wait rather than dropped — a connection is full duplex, and a peer that
gets nothing back stops talking to us."
  (dotimes (i +eth-max-skipped-messages+
              (error "no reply of eth id ~D for request id ~D after ~D messages"
                     expected-eth-id request-id +eth-max-skipped-messages+))
    (multiple-value-bind (eth-id payload) (eth-peer-read peer)
      (if (= eth-id expected-eth-id)
          (multiple-value-bind (id result) (funcall decoder payload)
            (when (= id request-id)
              (return result)))
          (eth-peer-handle-message peer eth-id payload)))))

(defun eth-peer-get-block-headers
    (peer &key origin-number origin-hash (amount 1) (skip 0) reverse
               (request-id (eth-peer-next-request-id peer)))
  "Request block headers from PEER and return the decoded header list.

The origin is a hash when ORIGIN-HASH is given, otherwise the block number
ORIGIN-NUMBER; AMOUNT, SKIP, and REVERSE follow the eth GetBlockHeaders
semantics."
  (eth-peer-send peer +eth-message-get-block-headers+
                 (encode-eth-get-block-headers
                  (make-eth-get-block-headers
                   :request-id request-id
                   :origin-number origin-number
                   :origin-hash origin-hash
                   :amount amount :skip skip :reverse reverse)))
  (eth-peer-await peer +eth-message-block-headers+ request-id
                  #'decode-eth-block-headers))

(defun eth-peer-get-block-bodies
    (peer hashes &key (request-id (eth-peer-next-request-id peer)))
  "Request the block bodies for HASHES from PEER and return the decoded bodies."
  (eth-peer-send peer +eth-message-get-block-bodies+
                 (encode-eth-get-block-bodies request-id hashes))
  (eth-peer-await peer +eth-message-block-bodies+ request-id
                  #'decode-eth-block-bodies))

(defun eth-peer-get-receipts
    (peer hashes &key (first-block-receipt-index 0)
                      (request-id (eth-peer-next-request-id peer)))
  "Request receipt groups, returning the groups and an incomplete-last flag."
  (let ((version (eth-peer-eth-version peer)))
    (eth-peer-send
     peer +eth-message-get-receipts+
     (encode-eth-get-receipts request-id hashes version
                              first-block-receipt-index))
    (let ((result
            (eth-peer-await
             peer +eth-message-receipts+ request-id
             (lambda (payload)
               (multiple-value-bind (id groups incomplete)
                   (decode-eth-receipts payload version)
                 (values id (list groups incomplete)))))))
      (values (first result) (second result)))))

(defun eth-peer-get-block-access-lists
    (peer hashes &key (request-id (eth-peer-next-request-id peer)))
  "Request eth/71 block access lists, preserving unavailable empty strings."
  (when (< (eth-peer-eth-version peer) +eth-protocol-version-71+)
    (error "GetBlockAccessLists requires eth/71 or later"))
  (eth-peer-send peer +eth-message-get-block-access-lists+
                 (encode-eth-get-block-access-lists request-id hashes))
  (eth-peer-await peer +eth-message-block-access-lists+ request-id
                  #'decode-eth-block-access-lists))

(defun eth-peer-get-cells
    (peer hashes custody-mask &key (request-id (eth-peer-next-request-id peer)))
  "Request eth/72 blob cells, returning hashes, cell groups, and custody mask."
  (when (< (eth-peer-eth-version peer) +eth-protocol-version-72+)
    (error "GetCells requires eth/72"))
  (eth-peer-send peer +eth-message-get-cells+
                 (encode-eth-get-cells request-id hashes custody-mask))
  (let ((result
          (eth-peer-await
           peer +eth-message-cells+ request-id
           (lambda (payload)
             (multiple-value-bind (id response-hashes groups response-mask)
                 (decode-eth-cells payload)
               (values id (list response-hashes groups response-mask)))))))
    (values (first result) (second result) (third result))))

(defun eth-peer-fetch-announced-block (peer)
  "Fetch and submit the oldest NewBlockHashes announcement from PEER.

Runs only as a top-level pump action, preserving the one-request-in-flight
contract. Returns true when a full block reached the backend."
  (let ((announcement (eth-peer-take-announced-block peer))
        (backend (eth-peer-serve-backend peer)))
    (when (and announcement backend
               (eth-serve-backend-accept-block backend))
      (let* ((hash (eth-new-block-hash-hash announcement))
             (headers (eth-peer-get-block-headers
                       peer :origin-hash hash :amount 1))
             (header (first headers)))
        (when (and header
                   (bytes= hash (hash32-bytes (block-header-hash header)))
                   (= (eth-new-block-hash-number announcement)
                      (block-header-number header)))
          (let ((body (first (eth-peer-get-block-bodies peer (list hash)))))
            (when body
              (eth-sync-validate-body header body)
              (eth-accept-propagated-block
               backend (eth-sync-assemble-block header body)))))))))

(defun eth-peer-fetch-announced-transactions (peer &key (limit 256))
  "Ask PEER for up to LIMIT of the transactions it announced and offer them to
the pool, returning how many the pool accepted.

Because this waits for a reply it must be called between messages, never from
inside a message handler: a handler can itself be running inside another
request's wait, and this nested wait would swallow that outer reply. That is why
announcements are queued as they arrive and drained only from here."
  (let ((backend (eth-peer-serve-backend peer))
        (wanted (eth-peer-take-announced-hashes peer limit)))
    (if (or (null backend) (null wanted))
        0
        (let ((request-id (eth-peer-next-request-id peer)))
          (eth-peer-send peer +eth-message-get-pooled-transactions+
                         (encode-eth-get-pooled-transactions request-id wanted))
          (eth-accept-transactions
           backend
           (eth-peer-await peer +eth-message-pooled-transactions+ request-id
                           #'decode-eth-pooled-transactions))))))
