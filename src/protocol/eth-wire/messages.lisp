(in-package #:ethereum-lisp.eth-wire)

;;;; The "eth" wire protocol (eth/68) message codecs.
;;;;
;;;; These are the messages a peer uses to sync the chain. They ride the RLPx
;;;; frame codec as ordinary devp2p messages, at message ids offset past the
;;;; base "p2p" protocol: with a single negotiated "eth" capability the eth
;;;; message ids begin at 0x10, so Status is 0x10, GetBlockHeaders 0x13, and so
;;;; on. This file owns the message bodies; framing and offsetting belong to the
;;;; caller.

(defconstant +eth-protocol-version+ 68)

;; Message ids within the eth capability, before the base-protocol offset.
(defconstant +eth-message-status+ #x00)
(defconstant +eth-message-new-block-hashes+ #x01)
(defconstant +eth-message-transactions+ #x02)
(defconstant +eth-message-get-block-headers+ #x03)
(defconstant +eth-message-block-headers+ #x04)
(defconstant +eth-message-get-block-bodies+ #x05)
(defconstant +eth-message-block-bodies+ #x06)
(defconstant +eth-message-get-receipts+ #x0f)
(defconstant +eth-message-receipts+ #x10)

;; The base "p2p" protocol reserves ids 0x00-0x0f, so a capability's ids are
;; offset past it.
(defconstant +eth-base-protocol-offset+ #x10)

(defun eth-wire-message-id (eth-message)
  "Map an eth message id to its on-the-wire devp2p message id."
  (+ eth-message +eth-base-protocol-offset+))

;;; EIP-2124 fork id: a 4-byte hash of the genesis and passed forks, and the
;;; block or time of the next upcoming fork (0 if none). The hash value itself
;;; is computed elsewhere; this only carries and codes it.

(defstruct (eth-fork-id (:constructor make-eth-fork-id (hash next)))
  hash
  next)

(defun eth-fork-id-rlp-object (fork-id)
  (make-rlp-list (ensure-byte-vector (eth-fork-id-hash fork-id))
                 (integer-to-minimal-bytes (eth-fork-id-next fork-id))))

(defun eth-fork-id-from-rlp-object (value)
  (let ((items (rlp-list-items value)))
    (make-eth-fork-id (ensure-byte-vector (first items))
                      (bytes-to-integer (ensure-byte-vector (second items))))))

;;; Status: the eth handshake, exchanged once after the devp2p Hello.

(defstruct (eth-status
            (:constructor make-eth-status
                (&key (version +eth-protocol-version+) network-id
                      total-difficulty best-hash genesis-hash fork-id)))
  version
  network-id
  total-difficulty
  best-hash
  genesis-hash
  fork-id)

(defun encode-eth-status (status)
  (rlp-encode
   (make-rlp-list
    (integer-to-minimal-bytes (eth-status-version status))
    (integer-to-minimal-bytes (eth-status-network-id status))
    (integer-to-minimal-bytes (eth-status-total-difficulty status))
    (ensure-byte-vector (eth-status-best-hash status))
    (ensure-byte-vector (eth-status-genesis-hash status))
    (eth-fork-id-rlp-object (eth-status-fork-id status)))))

(defun decode-eth-status (bytes)
  (let ((items (rlp-list-items
                (rlp-decode (ensure-byte-vector bytes) :allow-trailing t))))
    (when (< (length items) 6)
      (error "eth Status must have at least six fields"))
    (make-eth-status
     :version (bytes-to-integer (ensure-byte-vector (first items)))
     :network-id (bytes-to-integer (ensure-byte-vector (second items)))
     :total-difficulty (bytes-to-integer (ensure-byte-vector (third items)))
     :best-hash (ensure-byte-vector (fourth items))
     :genesis-hash (ensure-byte-vector (fifth items))
     :fork-id (eth-fork-id-from-rlp-object (sixth items)))))

;;; GetBlockHeaders / BlockHeaders. eth/66 wraps every request and response in a
;;; request id so replies can be matched to requests.

(defstruct (eth-get-block-headers
            (:constructor make-eth-get-block-headers
                (&key request-id origin-number origin-hash
                      (amount 1) (skip 0) (reverse nil))))
  request-id
  origin-number
  origin-hash
  amount
  skip
  reverse)

(defun encode-eth-get-block-headers (request)
  "RLP-encode a GetBlockHeaders request. The origin is a hash if one is given,
otherwise a block number."
  (rlp-encode
   (make-rlp-list
    (integer-to-minimal-bytes (eth-get-block-headers-request-id request))
    (make-rlp-list
     (if (eth-get-block-headers-origin-hash request)
         (ensure-byte-vector (eth-get-block-headers-origin-hash request))
         (integer-to-minimal-bytes
          (eth-get-block-headers-origin-number request)))
     (integer-to-minimal-bytes (eth-get-block-headers-amount request))
     (integer-to-minimal-bytes (eth-get-block-headers-skip request))
     (integer-to-minimal-bytes
      (if (eth-get-block-headers-reverse request) 1 0))))))

(defun decode-eth-get-block-headers (bytes)
  (let ((items (rlp-list-items
                (rlp-decode (ensure-byte-vector bytes) :allow-trailing t))))
    (let* ((request-id (bytes-to-integer (ensure-byte-vector (first items))))
           (query (rlp-list-items (second items)))
           (origin (ensure-byte-vector (first query))))
      ;; A 32-byte origin is a block hash; anything else is a block number.
      (make-eth-get-block-headers
       :request-id request-id
       :origin-hash (when (= (length origin) 32) origin)
       :origin-number (when (/= (length origin) 32) (bytes-to-integer origin))
       :amount (bytes-to-integer (ensure-byte-vector (second query)))
       :skip (bytes-to-integer (ensure-byte-vector (third query)))
       :reverse (plusp (bytes-to-integer (ensure-byte-vector (fourth query))))))))

(defun encode-eth-block-headers (request-id headers)
  "RLP-encode a BlockHeaders reply carrying REQUEST-ID and a list of HEADERS."
  (rlp-encode
   (make-rlp-list
    (integer-to-minimal-bytes request-id)
    (apply #'make-rlp-list (mapcar #'block-header-rlp-object headers)))))

(defun decode-eth-block-headers (bytes)
  "Decode a BlockHeaders reply into (VALUES REQUEST-ID HEADERS)."
  (let ((items (rlp-list-items
                (rlp-decode (ensure-byte-vector bytes) :allow-trailing t))))
    (values (bytes-to-integer (ensure-byte-vector (first items)))
            (mapcar #'block-header-from-rlp-object
                    (rlp-list-items (second items))))))
