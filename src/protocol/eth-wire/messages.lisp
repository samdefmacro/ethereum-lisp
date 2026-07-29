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
(defconstant +eth-protocol-version-69+ 69)

(defparameter +eth-supported-protocol-versions+ '(69 68)
  "eth wire versions we speak, highest first. eth/69 (EIP-7642) drops total
difficulty from Status and adds a block range; the header/body messages are
unchanged, so download works across both.")

;; Message ids within the eth capability, before the base-protocol offset.
(defconstant +eth-message-status+ #x00)
(defconstant +eth-message-new-block-hashes+ #x01)
(defconstant +eth-message-transactions+ #x02)
(defconstant +eth-message-get-block-headers+ #x03)
(defconstant +eth-message-block-headers+ #x04)
(defconstant +eth-message-get-block-bodies+ #x05)
(defconstant +eth-message-block-bodies+ #x06)
(defconstant +eth-message-new-pooled-transaction-hashes+ #x08)
(defconstant +eth-message-get-pooled-transactions+ #x09)
(defconstant +eth-message-pooled-transactions+ #x0a)
(defconstant +eth-message-get-receipts+ #x0f)
(defconstant +eth-message-receipts+ #x10)
;; eth/69 adds a block-range announcement past the eth/68 id space.
(defconstant +eth-message-block-range-update+ #x11)

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
                      total-difficulty best-hash genesis-hash fork-id
                      (earliest-block 0) latest-block latest-block-hash)))
  version
  network-id
  total-difficulty
  best-hash
  genesis-hash
  fork-id
  ;; eth/69 fields: the range of blocks we can serve and our head.
  earliest-block
  latest-block
  latest-block-hash)

(defun encode-eth-status (status)
  "Encode an eth/68 Status: [version, networkid, td, bestHash, genesis, forkid]."
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

(defun encode-eth-status-69 (status)
  "Encode an eth/69 Status (EIP-7642): total difficulty and best hash are gone;
the message carries the served block range and our head instead —
[version, networkid, genesis, forkid, earliestBlock, latestBlock, latestBlockHash]."
  (rlp-encode
   (make-rlp-list
    (integer-to-minimal-bytes (eth-status-version status))
    (integer-to-minimal-bytes (eth-status-network-id status))
    (ensure-byte-vector (eth-status-genesis-hash status))
    (eth-fork-id-rlp-object (eth-status-fork-id status))
    (integer-to-minimal-bytes (or (eth-status-earliest-block status) 0))
    (integer-to-minimal-bytes (or (eth-status-latest-block status) 0))
    (ensure-byte-vector (or (eth-status-latest-block-hash status)
                            (eth-status-genesis-hash status))))))

(defun decode-eth-status-69 (bytes)
  (let ((items (rlp-list-items
                (rlp-decode (ensure-byte-vector bytes) :allow-trailing t))))
    (when (< (length items) 7)
      (error "eth/69 Status must have at least seven fields"))
    (make-eth-status
     :version (bytes-to-integer (ensure-byte-vector (first items)))
     :network-id (bytes-to-integer (ensure-byte-vector (second items)))
     :genesis-hash (ensure-byte-vector (third items))
     :fork-id (eth-fork-id-from-rlp-object (fourth items))
     :earliest-block (bytes-to-integer (ensure-byte-vector (fifth items)))
     :latest-block (bytes-to-integer (ensure-byte-vector (sixth items)))
     :latest-block-hash (ensure-byte-vector (seventh items)))))

(defun encode-eth-status-for-version (status version)
  "Encode STATUS in the wire format for the negotiated eth VERSION."
  (if (>= version +eth-protocol-version-69+)
      (encode-eth-status-69 status)
      (encode-eth-status status)))

(defun decode-eth-status-for-version (bytes version)
  "Decode a Status message in the wire format for the negotiated eth VERSION."
  (if (>= version +eth-protocol-version-69+)
      (decode-eth-status-69 bytes)
      (decode-eth-status bytes)))

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

;;; GetBlockBodies / BlockBodies. A body is [transactions, uncles, withdrawals],
;;; withdrawals present for post-Shanghai blocks.

(defstruct (eth-block-body
            (:constructor make-eth-block-body
                (&key transactions ommers withdrawals withdrawals-present-p)))
  transactions
  ommers
  withdrawals
  withdrawals-present-p)

(defun eth-block-body-rlp-object (body)
  (let ((fields
          (list (block-transactions-rlp-object (eth-block-body-transactions body))
                (block-ommers-rlp-object (eth-block-body-ommers body)))))
    (when (eth-block-body-withdrawals-present-p body)
      (setf fields
            (append fields
                    (list (block-withdrawals-rlp-object
                           (eth-block-body-withdrawals body))))))
    (apply #'make-rlp-list fields)))

(defun eth-block-body-from-rlp-object (value)
  (let* ((items (rlp-list-items value))
         (has-withdrawals (>= (length items) 3)))
    (make-eth-block-body
     :transactions (block-transactions-from-rlp-object (first items))
     :ommers (block-ommers-from-rlp-object (second items))
     :withdrawals (when has-withdrawals
                    (block-withdrawals-from-rlp-object (third items)))
     :withdrawals-present-p has-withdrawals)))

(defun encode-eth-get-block-bodies (request-id hashes)
  (rlp-encode
   (make-rlp-list
    (integer-to-minimal-bytes request-id)
    (apply #'make-rlp-list (mapcar #'ensure-byte-vector hashes)))))

(defun decode-eth-get-block-bodies (bytes)
  "Decode a GetBlockBodies request into (VALUES REQUEST-ID HASHES)."
  (let ((items (rlp-list-items
                (rlp-decode (ensure-byte-vector bytes) :allow-trailing t))))
    (values (bytes-to-integer (ensure-byte-vector (first items)))
            (mapcar #'ensure-byte-vector (rlp-list-items (second items))))))

(defun encode-eth-block-bodies (request-id bodies)
  (rlp-encode
   (make-rlp-list
    (integer-to-minimal-bytes request-id)
    (apply #'make-rlp-list (mapcar #'eth-block-body-rlp-object bodies)))))

(defun block-eth-body (block)
  "The wire body of BLOCK: its transactions, ommers, and withdrawals."
  (make-eth-block-body
   :transactions (block-transactions block)
   :ommers (block-ommers block)
   :withdrawals (block-withdrawals block)
   :withdrawals-present-p (block-withdrawals-present-p block)))

(defun decode-eth-block-bodies (bytes)
  "Decode a BlockBodies reply into (VALUES REQUEST-ID BODIES)."
  (let ((items (rlp-list-items
                (rlp-decode (ensure-byte-vector bytes) :allow-trailing t))))
    (values (bytes-to-integer (ensure-byte-vector (first items)))
            (mapcar #'eth-block-body-from-rlp-object
                    (rlp-list-items (second items))))))

;;; Transaction gossip.
;;;
;;; Two paths carry a transaction between peers. Small ones are pushed whole in
;;; Transactions; everything else is announced by hash in
;;; NewPooledTransactionHashes and pulled with GetPooledTransactions, so a peer
;;; never receives the same large transaction from every neighbour at once. A
;;; Legacy transactions ride as RLP lists. Typed transactions are opaque byte
;;; strings; type 3 uses the EIP-4844 pooled wrapper so its sidecar follows it.

(defun eth-pooled-entry-transaction (entry)
  (if (and (consp entry)
           (typep (car entry) 'blob-transaction)
           (typep (cdr entry) 'blob-sidecar))
      (car entry)
      entry))

(defun eth-pooled-entry-sidecar (entry)
  (and (consp entry)
       (typep (car entry) 'blob-transaction)
       (typep (cdr entry) 'blob-sidecar)
       (cdr entry)))

(defun eth-pooled-transaction-rlp-object (entry)
  (let ((transaction (eth-pooled-entry-transaction entry))
        (sidecar (eth-pooled-entry-sidecar entry)))
    (cond
      (sidecar
       (blob-pooled-transaction-encoding transaction sidecar))
      (t
       (let ((encoding (transaction-encoding transaction)))
         (if (> (aref encoding 0) #x7f)
             (rlp-decode-one encoding)
             encoding))))))

(defun eth-pooled-transactions-rlp-object (entries)
  (apply #'make-rlp-list
         (mapcar #'eth-pooled-transaction-rlp-object entries)))

(defun eth-pooled-transactions-from-rlp-object (value)
  (unless (rlp-list-p value)
    (error "Pooled transactions must be an RLP list"))
  (mapcar
   (lambda (item)
     (if (rlp-list-p item)
         (transaction-from-encoding (rlp-encode item))
         (multiple-value-bind (transaction sidecar)
             (pooled-transaction-from-encoding
              (ensure-byte-vector item))
           (if sidecar (cons transaction sidecar) transaction))))
   (rlp-list-items value)))

(defun eth-network-transaction-rlp-object (transaction)
  (if (typep transaction 'blob-network-transaction)
      (blob-network-transaction-encoding transaction)
      (block-transaction-rlp-object transaction)))

(defun eth-network-transactions-rlp-object (transactions)
  (apply #'make-rlp-list
         (mapcar #'eth-network-transaction-rlp-object transactions)))

(defun eth-network-transaction-from-rlp-object (value)
  (if (rlp-list-p value)
      (transaction-from-encoding (rlp-encode value))
      (let ((bytes (ensure-byte-vector value)))
        (if (and (plusp (length bytes)) (= (aref bytes 0) 3))
            (blob-network-transaction-from-rlp (subseq bytes 1))
            (transaction-from-encoding bytes)))))

(defun eth-network-transactions-from-rlp-object (value)
  (mapcar #'eth-network-transaction-from-rlp-object
          (rlp-list-items value)))

(defun encode-eth-transactions (transactions)
  "Encode a Transactions message: the full transactions, with no request id."
  (rlp-encode (eth-network-transactions-rlp-object transactions)))

(defun decode-eth-transactions (bytes)
  (eth-network-transactions-from-rlp-object
   (rlp-decode (ensure-byte-vector bytes) :allow-trailing t)))

(defun encode-eth-new-pooled-transaction-hashes (transactions)
  "Encode an eth/68 announcement of TRANSACTIONS as three equal-length columns:
the types packed into one byte string, the consensus encoding sizes, and the
hashes. (eth/72 adds a fourth column of blob cell custody; we speak 68 and 69,
which do not have it.)"
  (let ((transactions
          (mapcar #'eth-pooled-entry-transaction transactions)))
    (rlp-encode
     (make-rlp-list
      (map 'byte-vector #'transaction-type transactions)
    (apply #'make-rlp-list
           (mapcar (lambda (transaction)
                     (integer-to-minimal-bytes
                      (length (transaction-encoding transaction))))
                   transactions))
    (apply #'make-rlp-list
           (mapcar (lambda (transaction)
                     (hash32-bytes (transaction-hash transaction)))
                   transactions))))))

(defun decode-eth-new-pooled-transaction-hashes (bytes)
  "Decode an announcement into (VALUES TYPES SIZES HASHES), three equal-length
lists. A message whose columns disagree is malformed and is rejected here rather
than leaving the caller to pair up mismatched columns."
  (let* ((items (rlp-list-items
                 (rlp-decode (ensure-byte-vector bytes) :allow-trailing t)))
         (types (coerce (ensure-byte-vector (first items)) 'list))
         (sizes (mapcar (lambda (size)
                          (bytes-to-integer (ensure-byte-vector size)))
                        (rlp-list-items (second items))))
         (hashes (mapcar #'ensure-byte-vector (rlp-list-items (third items)))))
    (unless (= (length types) (length sizes) (length hashes))
      (error "eth NewPooledTransactionHashes has ~D types, ~D sizes, and ~D ~
              hashes, which must be equal"
             (length types) (length sizes) (length hashes)))
    (values types sizes hashes)))

(defun encode-eth-get-pooled-transactions (request-id hashes)
  (rlp-encode
   (make-rlp-list
    (integer-to-minimal-bytes request-id)
    (apply #'make-rlp-list (mapcar #'ensure-byte-vector hashes)))))

(defun decode-eth-get-pooled-transactions (bytes)
  "Decode a GetPooledTransactions request into (VALUES REQUEST-ID HASHES)."
  (let ((items (rlp-list-items
                (rlp-decode (ensure-byte-vector bytes) :allow-trailing t))))
    (values (bytes-to-integer (ensure-byte-vector (first items)))
            (mapcar #'ensure-byte-vector (rlp-list-items (second items))))))

(defun encode-eth-pooled-transactions (request-id transactions)
  (rlp-encode
   (make-rlp-list
    (integer-to-minimal-bytes request-id)
    (eth-network-transactions-rlp-object transactions))))

(defun decode-eth-pooled-transactions (bytes)
  "Decode a PooledTransactions reply into (VALUES REQUEST-ID TRANSACTIONS).

The reply may be shorter than the request and in any order: a gap means the peer
no longer had that transaction, so the caller matches by hash, not by position."
  (let ((items (rlp-list-items
                (rlp-decode (ensure-byte-vector bytes) :allow-trailing t))))
    (values (bytes-to-integer (ensure-byte-vector (first items)))
            (eth-network-transactions-from-rlp-object (second items)))))

;;; GetReceipts / Receipts. The reply carries one list of receipts per block
;;; whose hash was asked for; a block we do not have is left out rather than
;;; held a place, so the reply is not positional.
;;;
;;; The receipt encoding depends on the negotiated version. eth/68 sends the
;;; consensus encoding, so a legacy receipt rides as the RLP list
;;; [status, cumulative-gas, bloom, logs] and a typed one as the opaque byte
;;; string type‖rlp(that list) — the same split block bodies use for
;;; transactions. eth/69 (EIP-7642) drops the bloom, which the receiver
;;; recomputes from the logs, and hoists the transaction type into a flat list:
;;; [type, status, cumulative-gas, logs], with legacy receipts carrying type 0.

(defun encode-eth-get-receipts (request-id hashes)
  (rlp-encode
   (make-rlp-list
    (integer-to-minimal-bytes request-id)
    (apply #'make-rlp-list (mapcar #'ensure-byte-vector hashes)))))

(defun decode-eth-get-receipts (bytes)
  "Decode a GetReceipts request into (VALUES REQUEST-ID HASHES)."
  (let ((items (rlp-list-items
                (rlp-decode (ensure-byte-vector bytes) :allow-trailing t))))
    (values (bytes-to-integer (ensure-byte-vector (first items)))
            (mapcar #'ensure-byte-vector (rlp-list-items (second items))))))

(defun eth-receipt-rlp-object (transaction receipt version)
  "RLP object for RECEIPT in the wire format of the negotiated eth VERSION.

TRANSACTION supplies the type, which the consensus encoding carries as a
prefix byte and eth/69 carries as the first field."
  (if (>= version +eth-protocol-version-69+)
      (make-rlp-list
       (integer-to-minimal-bytes (transaction-type transaction))
       (receipt-status-bytes receipt)
       (integer-to-minimal-bytes (receipt-cumulative-gas-used receipt))
       (mapcar #'log-entry-rlp-object (receipt-logs receipt)))
      (let ((encoded (transaction-receipt-encoding transaction receipt)))
        ;; A legacy receipt encodes as an RLP list, whose first byte is a list
        ;; header above #x7f; a typed one begins with its low type byte and
        ;; stays an opaque string.
        (if (> (aref encoded 0) #x7f)
            (rlp-decode-one encoded)
            encoded))))

(defun eth-block-receipts-rlp-object (block version)
  "RLP object for every receipt of BLOCK, in the negotiated VERSION's format."
  (let ((transactions (block-transactions block))
        (receipts (block-receipts block)))
    (unless (= (length transactions) (length receipts))
      (error "block has ~D transactions but ~D receipts, so its receipts ~
              cannot be served"
             (length transactions) (length receipts)))
    (apply #'make-rlp-list
           (mapcar (lambda (transaction receipt)
                     (eth-receipt-rlp-object transaction receipt version))
                   transactions receipts))))

(defun encode-eth-receipts (request-id blocks version)
  "Encode a Receipts reply carrying the receipts of each block in BLOCKS."
  (rlp-encode
   (make-rlp-list
    (integer-to-minimal-bytes request-id)
    (apply #'make-rlp-list
           (mapcar (lambda (block) (eth-block-receipts-rlp-object block version))
                   blocks)))))
