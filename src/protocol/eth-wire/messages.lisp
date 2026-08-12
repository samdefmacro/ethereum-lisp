(in-package #:ethereum-lisp.eth-wire)

;;;; The "eth" wire protocol (eth/68 through eth/72) message codecs.
;;;;
;;;; These are the messages a peer uses to sync the chain. They ride the RLPx
;;;; frame codec as ordinary devp2p messages, at message ids offset past the
;;;; base "p2p" protocol: with a single negotiated "eth" capability the eth
;;;; message ids begin at 0x10, so Status is 0x10, GetBlockHeaders 0x13, and so
;;;; on. This file owns the message bodies; framing and offsetting belong to the
;;;; caller.

(defconstant +eth-protocol-version+ 68)
(defconstant +eth-protocol-version-69+ 69)
(defconstant +eth-protocol-version-70+ 70)
(defconstant +eth-protocol-version-71+ 71)
(defconstant +eth-protocol-version-72+ 72)

(defparameter +eth-supported-protocol-versions+ '(72 71 70 69 68)
  "eth wire versions we speak, highest first.")

(defconstant +eth-max-message-size+ (* 10 1024 1024)
  "Maximum decoded eth message size, matching go-ethereum 1.17.6.")

(defconstant +eth-max-transaction-announcements+ 5000
  "Maximum hashes accepted in one NewPooledTransactionHashes message.")

(defconstant +eth-max-transactions-per-message+ 5000
  "Resource bound on full transactions accepted in one gossip message.")

(defconstant +eth-max-rlp-list-items+ 262144
  "Per-list allocation bound for every eth wire decoder.

The message-specific decoders below enforce much smaller request and batch
limits where the protocol has one.  This outer safety ceiling remains large
enough for a valid gas-bounded block with many logs, while preventing a 10 MiB
message made from one-byte list elements from allocating millions of conses.")

(defconstant +eth-max-request-hashes+ 4096)
(defconstant +eth-max-block-announcements+ 256)
(defconstant +eth-max-header-items+ 1024)
(defconstant +eth-max-body-items+ 256)
(defconstant +eth-max-receipt-groups+ 1024)
(defconstant +eth-max-cells-per-transaction+ (* 6 128)
  "Pinned geth parity: BlobTxMaxBlobs (6) times CellsPerBlob (128).")

(defun eth-wire-decode (bytes &key allow-trailing max-list-items)
  "Decode untrusted eth RLP under a mandatory per-list item ceiling."
  (rlp-decode (ensure-byte-vector bytes)
              :allow-trailing allow-trailing
              :max-list-items (or max-list-items +eth-max-rlp-list-items+)))

(defun eth-wire-list-items (value context &key exact maximum)
  (unless (rlp-list-p value)
    (error "~A must be an RLP list" context))
  (let ((items (rlp-list-items value)))
    (when (and exact (/= exact (length items)))
      (error "~A must contain exactly ~D items" context exact))
    (when (and maximum (> (length items) maximum))
      (error "~A contains ~D items, exceeding the ~D-item limit"
             context (length items) maximum))
    items))

(defun eth-wire-hash32-field (value context)
  (let ((bytes (ensure-byte-vector value)))
    (unless (= 32 (length bytes))
      (error "~A must contain 32 bytes" context))
    bytes))

;; Message ids within the eth capability, before the base-protocol offset.
(defconstant +eth-message-status+ #x00)
(defconstant +eth-message-new-block-hashes+ #x01)
(defconstant +eth-message-transactions+ #x02)
(defconstant +eth-message-get-block-headers+ #x03)
(defconstant +eth-message-block-headers+ #x04)
(defconstant +eth-message-get-block-bodies+ #x05)
(defconstant +eth-message-block-bodies+ #x06)
(defconstant +eth-message-new-block+ #x07)
(defconstant +eth-message-new-pooled-transaction-hashes+ #x08)
(defconstant +eth-message-get-pooled-transactions+ #x09)
(defconstant +eth-message-pooled-transactions+ #x0a)
(defconstant +eth-message-get-receipts+ #x0f)
(defconstant +eth-message-receipts+ #x10)
;; eth/69 adds a block-range announcement past the eth/68 id space.
(defconstant +eth-message-block-range-update+ #x11)
(defconstant +eth-message-get-block-access-lists+ #x12)
(defconstant +eth-message-block-access-lists+ #x13)
(defconstant +eth-message-get-cells+ #x14)
(defconstant +eth-message-cells+ #x15)

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
  (let* ((items (eth-wire-list-items value "eth fork id" :exact 2))
         (hash (ensure-byte-vector (first items)))
         (next (ensure-byte-vector (second items))))
    (unless (= 4 (length hash))
      (error "eth fork hash must contain four bytes"))
    (unless (<= (length next) 8)
      (error "eth fork next value exceeds uint64"))
    (make-eth-fork-id hash (bytes-to-integer next))))

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
  (let ((items (eth-wire-list-items
                (eth-wire-decode bytes :allow-trailing t)
                "eth Status" :exact 6)))
    (make-eth-status
     :version (bytes-to-integer (ensure-byte-vector (first items)))
     :network-id (bytes-to-integer (ensure-byte-vector (second items)))
     :total-difficulty (bytes-to-integer (ensure-byte-vector (third items)))
     :best-hash (eth-wire-hash32-field (fourth items) "eth Status best hash")
     :genesis-hash
     (eth-wire-hash32-field (fifth items) "eth Status genesis hash")
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
  (let ((items (eth-wire-list-items
                (eth-wire-decode bytes :allow-trailing t)
                "eth/69 Status" :exact 7)))
    (make-eth-status
     :version (bytes-to-integer (ensure-byte-vector (first items)))
     :network-id (bytes-to-integer (ensure-byte-vector (second items)))
     :genesis-hash
     (eth-wire-hash32-field (third items) "eth/69 Status genesis hash")
     :fork-id (eth-fork-id-from-rlp-object (fourth items))
     :earliest-block (bytes-to-integer (ensure-byte-vector (fifth items)))
     :latest-block (bytes-to-integer (ensure-byte-vector (sixth items)))
     :latest-block-hash
     (eth-wire-hash32-field
      (seventh items) "eth/69 Status latest block hash"))))

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

(defstruct (eth-block-range
            (:constructor make-eth-block-range
                (earliest-block latest-block latest-block-hash)))
  earliest-block
  latest-block
  latest-block-hash)

(defun encode-eth-block-range-update (range)
  (rlp-encode
   (make-rlp-list
    (integer-to-minimal-bytes (eth-block-range-earliest-block range))
    (integer-to-minimal-bytes (eth-block-range-latest-block range))
    (ensure-byte-vector (eth-block-range-latest-block-hash range)))))

(defun decode-eth-block-range-update (bytes)
  (let ((items
          (eth-wire-list-items
           (eth-wire-decode bytes :allow-trailing t)
           "eth BlockRangeUpdate" :exact 3)))
    (make-eth-block-range
     (bytes-to-integer (ensure-byte-vector (first items)))
     (bytes-to-integer (ensure-byte-vector (second items)))
     (eth-wire-hash32-field
      (third items) "eth BlockRangeUpdate latest block hash"))))

;;; NewBlockHashes / NewBlock propagation.

(defstruct (eth-new-block-hash
            (:constructor make-eth-new-block-hash (hash number)))
  hash
  number)

(defun encode-eth-new-block-hashes (announcements)
  (rlp-encode
   (apply #'make-rlp-list
          (mapcar
           (lambda (announcement)
             (make-rlp-list
              (ensure-byte-vector (eth-new-block-hash-hash announcement))
              (integer-to-minimal-bytes
               (eth-new-block-hash-number announcement))))
           announcements))))

(defun decode-eth-new-block-hashes (bytes)
  (mapcar
   (lambda (value)
     (let ((items (eth-wire-list-items
                   value "eth NewBlockHashes entry" :exact 2)))
       (make-eth-new-block-hash
        (eth-wire-hash32-field (first items) "eth NewBlockHashes hash")
        (bytes-to-integer (ensure-byte-vector (second items))))))
   (eth-wire-list-items
    (eth-wire-decode bytes :allow-trailing t)
    "eth NewBlockHashes" :maximum +eth-max-block-announcements+)))

(defstruct (eth-new-block
            (:constructor make-eth-new-block (block total-difficulty)))
  block
  total-difficulty)

(defun encode-eth-new-block (announcement)
  (rlp-encode
   (make-rlp-list
    (rlp-decode-one (block-rlp (eth-new-block-block announcement)))
    (integer-to-minimal-bytes
     (eth-new-block-total-difficulty announcement)))))

(defun decode-eth-new-block (bytes)
  (let ((items
          (eth-wire-list-items
           (eth-wire-decode bytes :allow-trailing t)
           "eth NewBlock" :exact 2)))
    (make-eth-new-block
     (block-from-rlp (rlp-encode (first items)))
     (bytes-to-integer (ensure-byte-vector (second items))))))

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
  (let ((items (eth-wire-list-items
                (eth-wire-decode bytes :allow-trailing t)
                "eth GetBlockHeaders" :exact 2)))
    (let* ((request-id (bytes-to-integer (ensure-byte-vector (first items))))
           (query (eth-wire-list-items
                   (second items) "eth GetBlockHeaders query" :exact 4))
           (origin (ensure-byte-vector (first query))))
      (unless (or (= (length origin) 32) (<= (length origin) 8))
        (error "eth GetBlockHeaders origin must be a hash32 or uint64"))
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
  (let ((items (eth-wire-list-items
                (eth-wire-decode bytes :allow-trailing t)
                "eth BlockHeaders" :exact 2)))
    (values (bytes-to-integer (ensure-byte-vector (first items)))
            (mapcar #'block-header-from-rlp-object
                    (eth-wire-list-items
                     (second items) "eth BlockHeaders list"
                     :maximum +eth-max-header-items+)))))

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
  (let* ((items (eth-wire-list-items
                 value "eth block body" :maximum 3))
         (has-withdrawals (>= (length items) 3)))
    (unless (member (length items) '(2 3))
      (error "eth block body must contain two or three fields"))
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
  (let ((items (eth-wire-list-items
                (eth-wire-decode bytes :allow-trailing t)
                "eth GetBlockBodies" :exact 2)))
    (values (bytes-to-integer (ensure-byte-vector (first items)))
            (mapcar (lambda (hash)
                      (eth-wire-hash32-field hash "eth GetBlockBodies hash"))
                    (eth-wire-list-items
                     (second items) "eth GetBlockBodies hashes"
                     :maximum +eth-max-request-hashes+)))))

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
  (let ((items (eth-wire-list-items
                (eth-wire-decode bytes :allow-trailing t)
                "eth BlockBodies" :exact 2)))
    (values (bytes-to-integer (ensure-byte-vector (first items)))
            (mapcar #'eth-block-body-from-rlp-object
                    (eth-wire-list-items
                     (second items) "eth BlockBodies list"
                     :maximum +eth-max-body-items+)))))

;;; Transaction gossip.
;;;
;;; Two paths carry a transaction between peers. Small ones are pushed whole in
;;; Transactions; everything else is announced by hash in
;;; NewPooledTransactionHashes and pulled with GetPooledTransactions, so a peer
;;; never receives the same large transaction from every neighbour at once. A
;;; Legacy transactions ride as RLP lists. Typed transactions are opaque byte
;;; strings; type 3 uses the EIP-4844 pooled wrapper so its sidecar follows it.

(defun eth-pooled-entry-transaction (entry)
  (cond
    ((typep entry 'blob-network-transaction)
     (blob-network-transaction-transaction entry))
    ((and (consp entry)
          (typep (car entry) 'blob-transaction)
          (typep (cdr entry) 'blob-sidecar))
     (car entry))
    (t entry)))

(defun eth-pooled-entry-sidecar (entry)
  (cond
    ((typep entry 'blob-network-transaction)
     (blob-network-transaction-sidecar entry))
    ((and (consp entry)
          (typep (car entry) 'blob-transaction)
          (typep (cdr entry) 'blob-sidecar))
     (cdr entry))))

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
  (mapcar
   (lambda (item)
     (if (rlp-list-p item)
         (transaction-from-encoding (rlp-encode item))
         (multiple-value-bind (transaction sidecar)
             (pooled-transaction-from-encoding
              (ensure-byte-vector item))
           (if sidecar (cons transaction sidecar) transaction))))
   (eth-wire-list-items
    value "eth pooled transactions"
    :maximum +eth-max-transactions-per-message+)))

(defun eth-network-transaction-rlp-object (transaction)
  (if (typep transaction 'blob-network-transaction)
      (blob-network-transaction-encoding transaction)
      (eth-pooled-transaction-rlp-object transaction)))

(defun eth-network-transactions-rlp-object (transactions)
  (apply #'make-rlp-list
         (mapcar #'eth-network-transaction-rlp-object transactions)))

(defun eth-network-transaction-from-rlp-object (value)
  (if (rlp-list-p value)
      (transaction-from-encoding (rlp-encode value))
      (let ((bytes (ensure-byte-vector value)))
        (if (and (plusp (length bytes)) (= (aref bytes 0) 3))
            (let ((network-transaction
                    (blob-network-transaction-from-rlp (subseq bytes 1))))
              (if (typep network-transaction 'blob-network-transaction)
                  network-transaction
                  (multiple-value-bind (transaction sidecar)
                      (pooled-transaction-from-encoding bytes)
                    (if sidecar
                        (cons transaction sidecar)
                        network-transaction))))
            (transaction-from-encoding bytes)))))

(defun eth-network-transactions-from-rlp-object (value)
  (mapcar #'eth-network-transaction-from-rlp-object
          (eth-wire-list-items
           value "eth transactions"
           :maximum +eth-max-transactions-per-message+)))

(defun encode-eth-transactions (transactions)
  "Encode a Transactions message: the full transactions, with no request id."
  (rlp-encode (eth-network-transactions-rlp-object transactions)))

(defun decode-eth-transactions (bytes)
  (eth-network-transactions-from-rlp-object
   (eth-wire-decode
    bytes :allow-trailing t
    :max-list-items +eth-max-transactions-per-message+)))

(defun encode-eth-new-pooled-transaction-hashes
    (transactions &key (version +eth-protocol-version-71+)
                       (custody-mask (make-byte-vector 16)))
  "Encode a transaction announcement. eth/72 appends its 16-byte custody mask."
  (let ((transactions
          (mapcar #'eth-pooled-entry-transaction transactions)))
    (let ((fields
            (list
             (map 'byte-vector #'transaction-type transactions)
             (apply #'make-rlp-list
                    (mapcar (lambda (transaction)
                              (integer-to-minimal-bytes
                               (length (transaction-encoding transaction))))
                            transactions))
             (apply #'make-rlp-list
                    (mapcar (lambda (transaction)
                              (hash32-bytes (transaction-hash transaction)))
                            transactions)))))
      (when (>= version +eth-protocol-version-72+)
        (let ((mask (ensure-byte-vector custody-mask)))
          (unless (= (length mask) 16)
            (error "eth/72 custody mask must contain 16 bytes"))
          (setf fields (append fields (list mask)))))
      (rlp-encode (apply #'make-rlp-list fields)))))

(defun decode-eth-new-pooled-transaction-hashes
    (bytes &optional (version +eth-protocol-version-71+))
  "Decode an announcement into (VALUES TYPES SIZES HASHES CUSTODY-MASK)."
  (let* ((items (eth-wire-list-items
                 (eth-wire-decode
                  bytes :allow-trailing t
                  :max-list-items +eth-max-transaction-announcements+)
                 "eth NewPooledTransactionHashes"
                 :exact (if (>= version +eth-protocol-version-72+) 4 3)))
         (type-bytes (ensure-byte-vector (first items))))
    (when (> (length type-bytes) +eth-max-transaction-announcements+)
      (error "eth NewPooledTransactionHashes announces ~D transactions, ~
              exceeding the ~D-item limit"
             (length type-bytes) +eth-max-transaction-announcements+))
    (let* ((types (coerce type-bytes 'list))
         (sizes (mapcar (lambda (size)
                          (bytes-to-integer (ensure-byte-vector size)))
                        (eth-wire-list-items
                         (second items) "eth transaction announcement sizes"
                         :maximum +eth-max-transaction-announcements+)))
           (hashes
             (mapcar
              #'ensure-byte-vector
              (eth-wire-list-items
               (third items) "eth transaction announcement hashes"
               :maximum +eth-max-transaction-announcements+)))
           (mask
             (when (>= version +eth-protocol-version-72+)
               (unless (= (length items) 4)
                 (error "eth/72 NewPooledTransactionHashes needs four fields"))
               (let ((value (ensure-byte-vector (fourth items))))
                 (unless (= (length value) 16)
                   (error "eth/72 custody mask must contain 16 bytes"))
                 value))))
      (when (and (< version +eth-protocol-version-72+) (/= (length items) 3))
        (error "pre-eth/72 NewPooledTransactionHashes needs three fields"))
      (dolist (hash hashes)
        (unless (= (length hash) 32)
          (error "eth transaction announcement hash must contain 32 bytes")))
      (unless (= (length types) (length sizes) (length hashes))
        (error "eth NewPooledTransactionHashes has ~D types, ~D sizes, and ~D ~
              hashes, which must be equal"
               (length types) (length sizes) (length hashes)))
      (values types sizes hashes mask))))

(defun encode-eth-get-pooled-transactions (request-id hashes)
  (rlp-encode
   (make-rlp-list
    (integer-to-minimal-bytes request-id)
    (apply #'make-rlp-list (mapcar #'ensure-byte-vector hashes)))))

(defun decode-eth-get-pooled-transactions (bytes)
  "Decode a GetPooledTransactions request into (VALUES REQUEST-ID HASHES)."
  (let ((items (eth-wire-list-items
                (eth-wire-decode bytes :allow-trailing t)
                "eth GetPooledTransactions" :exact 2)))
    (values (bytes-to-integer (ensure-byte-vector (first items)))
            (mapcar (lambda (hash)
                      (eth-wire-hash32-field
                       hash "eth GetPooledTransactions hash"))
                    (eth-wire-list-items
                     (second items) "eth GetPooledTransactions hashes"
                     :maximum +eth-max-request-hashes+)))))

(defun encode-eth-pooled-transactions (request-id transactions)
  (rlp-encode
   (make-rlp-list
    (integer-to-minimal-bytes request-id)
    (eth-network-transactions-rlp-object transactions))))

(defun decode-eth-pooled-transactions (bytes)
  "Decode a PooledTransactions reply into (VALUES REQUEST-ID TRANSACTIONS).

The reply may be shorter than the request and in any order: a gap means the peer
  no longer had that transaction, so the caller matches by hash, not by position."
  (let ((items (eth-wire-list-items
                (eth-wire-decode bytes :allow-trailing t)
                "eth PooledTransactions" :exact 2)))
    (values (bytes-to-integer (ensure-byte-vector (first items)))
            (eth-network-transactions-from-rlp-object (second items)))))

;;; eth/71 block access lists and eth/72 blob cells. BAL values stay as RLP
;;; objects because an empty byte string means unavailable while an empty list
;;; is a valid access list.

(defun eth-wire-hashes (value context)
  (let ((hashes
          (mapcar #'ensure-byte-vector
                  (eth-wire-list-items
                   value context :maximum +eth-max-request-hashes+))))
    (dolist (hash hashes)
      (unless (= (length hash) 32)
        (error "~A hash must contain 32 bytes" context)))
    hashes))

(defun encode-eth-get-block-access-lists (request-id hashes)
  (rlp-encode
   (make-rlp-list
    (integer-to-minimal-bytes request-id)
    (apply #'make-rlp-list (mapcar #'ensure-byte-vector hashes)))))

(defun decode-eth-get-block-access-lists (bytes)
  (let ((items
          (eth-wire-list-items
           (eth-wire-decode bytes)
           "eth/71 GetBlockAccessLists" :exact 2)))
    (values (bytes-to-integer (ensure-byte-vector (first items)))
            (eth-wire-hashes (second items) "GetBlockAccessLists"))))

(defun encode-eth-block-access-lists (request-id access-lists)
  (rlp-encode
   (make-rlp-list
    (integer-to-minimal-bytes request-id)
    (apply #'make-rlp-list access-lists))))

(defun decode-eth-block-access-lists (bytes)
  (let ((items
          (eth-wire-list-items
           (eth-wire-decode bytes)
           "eth/71 BlockAccessLists" :exact 2)))
    (values (bytes-to-integer (ensure-byte-vector (first items)))
            (eth-wire-list-items
             (second items) "eth/71 BlockAccessLists list"
             :maximum +eth-max-request-hashes+))))

(defun eth-custody-mask (value context)
  (let ((mask (ensure-byte-vector value)))
    (unless (= (length mask) 16)
      (error "~A custody mask must contain 16 bytes" context))
    mask))

(defun encode-eth-get-cells (request-id hashes custody-mask)
  (rlp-encode
   (make-rlp-list
    (integer-to-minimal-bytes request-id)
    (apply #'make-rlp-list (mapcar #'ensure-byte-vector hashes))
    (eth-custody-mask custody-mask "GetCells"))))

(defun decode-eth-get-cells (bytes)
  (let ((items
          (eth-wire-list-items
           (eth-wire-decode bytes) "eth/72 GetCells" :exact 3)))
    (values (bytes-to-integer (ensure-byte-vector (first items)))
            (eth-wire-hashes (second items) "GetCells")
            (eth-custody-mask (third items) "GetCells"))))

(defun encode-eth-cells (request-id hashes cell-groups custody-mask)
  (unless (= (length hashes) (length cell-groups))
    (error "eth/72 Cells hashes and cell groups must have equal lengths"))
  (rlp-encode
   (make-rlp-list
    (integer-to-minimal-bytes request-id)
    (apply #'make-rlp-list (mapcar #'ensure-byte-vector hashes))
    (apply #'make-rlp-list
           (mapcar (lambda (group)
                     (apply #'make-rlp-list
                            (mapcar #'ensure-byte-vector group)))
                   cell-groups))
    (eth-custody-mask custody-mask "Cells"))))

(defun decode-eth-cells (bytes)
  (let ((items
          (eth-wire-list-items
           (eth-wire-decode bytes) "eth/72 Cells" :exact 4)))
    (let ((hashes (eth-wire-hashes (second items) "Cells"))
          (groups
            (mapcar
             (lambda (group)
               (mapcar
                (lambda (cell)
                  (let ((bytes (ensure-byte-vector cell)))
                    (unless (= (length bytes) 2048)
                      (error "eth/72 blob cell must contain 2048 bytes"))
                    bytes))
                (eth-wire-list-items
                 group "eth/72 Cells transaction group"
                 :maximum +eth-max-cells-per-transaction+)))
             (eth-wire-list-items
              (third items) "eth/72 Cells groups"
              :maximum +eth-max-request-hashes+))))
      (unless (= (length hashes) (length groups))
        (error "eth/72 Cells hashes and cell groups must have equal lengths"))
      (values (bytes-to-integer (ensure-byte-vector (first items)))
              hashes groups (eth-custody-mask (fourth items) "Cells")))))

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

(defun encode-eth-get-receipts
    (request-id hashes &optional (version +eth-protocol-version-69+)
                                 (first-block-receipt-index 0))
  (rlp-encode
   (if (>= version +eth-protocol-version-70+)
       (make-rlp-list
        (integer-to-minimal-bytes request-id)
        (integer-to-minimal-bytes first-block-receipt-index)
        (apply #'make-rlp-list (mapcar #'ensure-byte-vector hashes)))
       (make-rlp-list
        (integer-to-minimal-bytes request-id)
        (apply #'make-rlp-list (mapcar #'ensure-byte-vector hashes))))))

(defun decode-eth-get-receipts
    (bytes &optional (version +eth-protocol-version-69+))
  "Decode GetReceipts into REQUEST-ID, HASHES, and FIRST-RECEIPT-INDEX."
  (let ((items
          (eth-wire-list-items
           (eth-wire-decode bytes :allow-trailing t)
           "eth GetReceipts"
           :exact (if (>= version +eth-protocol-version-70+) 3 2))))
    (if (>= version +eth-protocol-version-70+)
        (progn
          (unless (= (length items) 3)
            (error "eth/70 GetReceipts must contain three fields"))
          (values
           (bytes-to-integer (ensure-byte-vector (first items)))
           (mapcar
            (lambda (hash)
              (eth-wire-hash32-field hash "eth/70 GetReceipts hash"))
            (eth-wire-list-items
             (third items) "eth/70 GetReceipts hashes"
             :maximum +eth-max-request-hashes+))
           (bytes-to-integer (ensure-byte-vector (second items)))))
        (progn
          (unless (= (length items) 2)
            (error "eth/69 GetReceipts must contain two fields"))
          (values (bytes-to-integer (ensure-byte-vector (first items)))
                  (mapcar
                   (lambda (hash)
                     (eth-wire-hash32-field hash "eth/69 GetReceipts hash"))
                   (eth-wire-list-items
                    (second items) "eth/69 GetReceipts hashes"
                    :maximum +eth-max-request-hashes+))
                  0)))))

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

(defun eth-block-receipts-rlp-object (block version &optional (start 0))
  "RLP object for every receipt of BLOCK, in the negotiated VERSION's format."
  (let ((transactions (block-transactions block))
        (receipts (block-receipts block)))
    (unless (= (length transactions) (length receipts))
      (error "block has ~D transactions but ~D receipts, so its receipts ~
              cannot be served"
             (length transactions) (length receipts)))
    (when (> start (length receipts))
      (error "receipt start index ~D exceeds block receipt count ~D"
             start (length receipts)))
    (apply #'make-rlp-list
           (mapcar (lambda (transaction receipt)
                     (eth-receipt-rlp-object transaction receipt version))
                   (nthcdr start transactions)
                   (nthcdr start receipts)))))

(defun encode-eth-receipts
    (request-id blocks version &key (first-block-receipt-index 0)
                                    last-block-incomplete)
  "Encode a Receipts reply carrying the receipts of each block in BLOCKS."
  (let ((groups
          (loop for block in blocks
                for first = t then nil
                collect (eth-block-receipts-rlp-object
                         block version
                         (if first first-block-receipt-index 0)))))
    (rlp-encode
     (if (>= version +eth-protocol-version-70+)
         (make-rlp-list
          (integer-to-minimal-bytes request-id)
          (if last-block-incomplete #(1) (make-byte-vector 0))
          (apply #'make-rlp-list groups))
         (make-rlp-list
          (integer-to-minimal-bytes request-id)
          (apply #'make-rlp-list groups))))))

(defstruct (eth-wire-receipt
            (:constructor make-eth-wire-receipt (transaction-type receipt)))
  transaction-type
  receipt)

(defun eth-log-entry-from-wire-object (value)
  (let ((items
          (eth-wire-list-items value "eth receipt log" :exact 3)))
    (make-log-entry
     :address (make-address (ensure-byte-vector (first items)))
     :topics (mapcar (lambda (topic)
                       (make-hash32 (ensure-byte-vector topic)))
                     (eth-wire-list-items
                      (second items) "eth receipt log topics" :maximum 4))
     :data (ensure-byte-vector (third items)))))

(defun eth-receipt-status-values (value)
  (let ((bytes (ensure-byte-vector value)))
    (cond
      ((= (length bytes) 32) (values bytes 1))
      ((zerop (length bytes)) (values nil 0))
      ((and (= (length bytes) 1) (= (aref bytes 0) 1))
       (values nil 1))
      (t (error "invalid eth receipt status field")))))

(defun eth-wire-receipt-from-fields (type fields)
  (multiple-value-bind (post-state status)
      (eth-receipt-status-values (first fields))
    (let ((logs
            (mapcar #'eth-log-entry-from-wire-object
                    (eth-wire-list-items
                     (car (last fields)) "eth receipt logs"
                     :maximum +eth-max-rlp-list-items+))))
      (when (= (length fields) 4)
        (let ((expected-bloom (ensure-byte-vector (third fields)))
              (actual-bloom (bloom-bytes (receipt-bloom logs))))
          (unless (and (= (length expected-bloom) 256)
                       (bytes= expected-bloom actual-bloom))
            (error "eth/68 receipt bloom does not match its logs"))))
      (make-eth-wire-receipt
       type
       (make-receipt
        :post-state post-state
        :status status
        :cumulative-gas-used
        (bytes-to-integer (ensure-byte-vector (second fields)))
        :logs logs)))))

(defun eth-wire-receipt-from-object (value version)
  (if (>= version +eth-protocol-version-69+)
      (let ((fields
              (eth-wire-list-items value "eth/69 receipt" :exact 4)))
        (eth-wire-receipt-from-fields
         (bytes-to-integer (ensure-byte-vector (first fields)))
         (rest fields)))
      (let* ((typed (not (rlp-list-p value)))
             (bytes (when typed (ensure-byte-vector value)))
             (type (if typed (aref bytes 0) 0))
             (fields
               (eth-wire-list-items
                (if typed
                    (eth-wire-decode (subseq bytes 1))
                    value)
                "eth/68 receipt" :exact 4)))
        (eth-wire-receipt-from-fields type fields))))

(defun decode-eth-receipts (bytes version)
  "Decode into REQUEST-ID, BLOCK-RECEIPT-GROUPS, and LAST-BLOCK-INCOMPLETE.

Each item is an ETH-WIRE-RECEIPT pairing the transaction type carried by the
wire format with its decoded receipt."
  (let ((items
          (eth-wire-list-items
           (eth-wire-decode bytes :allow-trailing t)
           "eth Receipts"
           :exact (if (>= version +eth-protocol-version-70+) 3 2))))
    (let* ((version-70-p (>= version +eth-protocol-version-70+))
           (groups (if version-70-p (third items) (second items)))
           (incomplete
             (and version-70-p
                  (not (zerop
                        (bytes-to-integer
                         (ensure-byte-vector (second items))))))))
      (unless (= (length items) (if version-70-p 3 2))
        (error "eth Receipts has the wrong field count for version ~D" version))
      (values
       (bytes-to-integer (ensure-byte-vector (first items)))
       (mapcar
        (lambda (group)
          (mapcar (lambda (value)
                    (eth-wire-receipt-from-object value version))
                  (eth-wire-list-items
                   group "eth block receipt group"
                   :maximum +eth-max-rlp-list-items+)))
        (eth-wire-list-items
         groups "eth receipt groups"
         :maximum +eth-max-receipt-groups+))
       incomplete))))
