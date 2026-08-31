(in-package #:ethereum-lisp.eth-sync)

;;;; The block-download driver (initial block download).
;;;;
;;;; Given a peer, download blocks forward from a starting number: request
;;;; headers in batches, fetch the matching bodies, assemble each block, and
;;;; hand it to an import callback in order. Keeping the import behind a callback
;;;; leaves this layer independent of the chain store — the node supplies a
;;;; callback that executes and commits each block.
;;;;
;;;; ETH-SYNC-DOWNLOAD-BLOCKS-MULTI is the bounded, multi-peer counterpart.
;;;; One worker owns each connection, preserving the RLPx single-writer and
;;;; one-request-per-peer contracts, while the coordinator keeps header, body,
;;;; and receipt deliveries in height-keyed queues and imports only the next
;;;; contiguous batch. A failed worker never imports; its range goes back to
;;;; the shared pending queue for another peer.

(defconstant +eth-sync-default-batch-size+ 192
  "How many block headers to request at once during download.")

(define-condition eth-sync-anchor-mismatch (error)
  ((number :initarg :number :reader eth-sync-anchor-mismatch-number)
   (expected-parent-hash
    :initarg :expected-parent-hash
    :reader eth-sync-anchor-mismatch-expected-parent-hash)
   (actual-parent-hash
    :initarg :actual-parent-hash
    :reader eth-sync-anchor-mismatch-actual-parent-hash))
  (:report
   (lambda (condition stream)
     (format stream
             "Peer block ~D does not extend durable sync cursor ~A (got ~A)"
             (eth-sync-anchor-mismatch-number condition)
             (hash32-to-hex
              (eth-sync-anchor-mismatch-expected-parent-hash condition))
             (hash32-to-hex
              (eth-sync-anchor-mismatch-actual-parent-hash condition))))))

(defun eth-sync-validate-header-batch
    (headers origin-number previous-header &key expected-parent-hash)
  "Reject a header reply that does not answer the requested contiguous range."
  (loop with parent = previous-header
        for header in headers
        for expected from origin-number
        do (unless (= expected (block-header-number header))
             (error "peer returned header ~D where block ~D was requested"
                    (block-header-number header) expected))
           (when parent
             (unless (hash32= (block-header-parent-hash header)
                              (block-header-hash parent))
               (error "peer returned a non-contiguous header at block ~D"
                      expected)))
           (when (and (null parent) expected-parent-hash)
             (let ((expected-parent
                     (if (hash32-p expected-parent-hash)
                         expected-parent-hash
                         (make-hash32 expected-parent-hash))))
               (unless (hash32= (block-header-parent-hash header)
                                expected-parent)
                 (error 'eth-sync-anchor-mismatch
                        :number expected
                        :expected-parent-hash expected-parent
                        :actual-parent-hash
                        (block-header-parent-hash header)))))
           (setf parent header))
  t)

(defun eth-sync-validate-body (header body)
  "Reject a body whose commitments do not match HEADER before import."
  (ethereum-lisp.execution:validate-block-body-commitments-before-execution
   (eth-block-body-transactions body)
   header
   :ommers (eth-block-body-ommers body)
   :withdrawals (eth-block-body-withdrawals body)
   :withdrawals-supplied-p
   (eth-block-body-withdrawals-present-p body))
  t)

(defun eth-sync-assemble-block (header body)
  "Assemble a block from a downloaded HEADER and its BODY.

Uses make-block-from-parts, which trusts the header's committed roots rather
than recomputing them, since the header was received rather than built here."
  (make-block-from-parts
   :header header
   :transactions (eth-block-body-transactions body)
   :ommers (eth-block-body-ommers body)
   :withdrawals (eth-block-body-withdrawals body)
   :withdrawals-present-p (eth-block-body-withdrawals-present-p body)))

(defun eth-sync-assemble-block-with-receipts (header body receipts)
  "Assemble a verified wire block while retaining its downloaded receipts."
  (make-block-from-parts
   :header header
   :transactions (eth-block-body-transactions body)
   :receipts receipts
   :ommers (eth-block-body-ommers body)
   :withdrawals (eth-block-body-withdrawals body)
   :withdrawals-present-p (eth-block-body-withdrawals-present-p body)))

(defun eth-sync-download-blocks
    (peer import-block
     &key (start-number 1)
          (batch-size +eth-sync-default-batch-size+)
          (max-blocks nil)
          (expected-parent-hash nil)
          (import-batch nil)
          (progress nil))
  "Download blocks forward from START-NUMBER, importing each in order.

Requests headers from PEER in batches, fetches their bodies, assembles each
block, and calls IMPORT-BLOCK on it. IMPORT-BLOCK receives one assembled block
and is expected to execute and commit it; an error it signals propagates and
stops the download. When IMPORT-BATCH is supplied, each verified response
prefix is instead handed to it oldest-first as one list. This lets a durable
consumer preserve the network batch as its rollback and WAL boundary.
EXPECTED-PARENT-HASH anchors the first returned header to a durable local
cursor, so restart cannot silently continue on another branch. PROGRESS, if
given, is called with each block only after its containing import finishes.
Stops when the peer returns no further headers, or after MAX-BLOCKS blocks.
Returns the number of blocks imported."
  (let ((next start-number)
        (imported 0)
        (previous-header nil))
    (loop
      (let ((amount (if max-blocks
                        (min batch-size (- max-blocks imported))
                        batch-size)))
        (when (<= amount 0)
          (return imported))
        (let ((headers (eth-peer-get-block-headers
                        peer :origin-number next :amount amount)))
          (when (null headers)
            (return imported))
          (eth-sync-validate-header-batch
           headers next previous-header
           :expected-parent-hash (and (null previous-header)
                                      expected-parent-hash))
          (let* ((hashes (mapcar (lambda (h) (hash32-bytes (block-header-hash h)))
                                 headers))
                 (bodies (eth-peer-get-block-bodies peer hashes)))
            ;; GetBlockBodies is soft-byte-limited.  An honest peer may answer
            ;; only a prefix of the requested hashes (geth commonly does this
            ;; for transaction-heavy ranges), so continue from that prefix on
            ;; the next round.  A zero or overlong response cannot make
            ;; progress and is not a valid prefix.
            (when (or (null bodies) (> (length bodies) (length headers)))
              (error "peer returned ~D bodies for ~D headers"
                     (length bodies) (length headers)))
            (let* ((served-headers (subseq headers 0 (length bodies)))
                   (blocks
                     (loop for header in served-headers
                           for body in bodies
                           do (eth-sync-validate-body header body)
                           collect (eth-sync-assemble-block header body))))
              (if import-batch
                  (funcall import-batch blocks)
                  (dolist (block blocks)
                    (funcall import-block block)))
              (incf imported (length blocks))
              (when progress
                (dolist (block blocks)
                  (funcall progress block)))
              (setf previous-header (car (last served-headers)))
              (incf next (length served-headers))
              ;; Only a short HEADER batch proves the peer reached its tip.
              ;; A short body prefix is a response-size boundary and must be
              ;; resumed instead of being mistaken for end-of-chain.
              (when (and (= (length bodies) (length headers))
                         (< (length headers) amount))
                (return imported)))))))))

(define-condition eth-sync-malformed-delivery (error)
  ((detail :initarg :detail :reader eth-sync-malformed-delivery-detail))
  (:report (lambda (condition stream)
             (format stream "malformed sync delivery: ~A"
                     (eth-sync-malformed-delivery-detail condition)))))

(define-condition eth-sync-multi-peer-error (simple-error) ()
  (:documentation
   "A bounded multi-peer attempt exhausted or contradicted its target."))

(defun eth-sync-multi-peer-fail (control &rest arguments)
  (error 'eth-sync-multi-peer-error
         :format-control control :format-arguments arguments))

(defstruct (eth-sync-peer-source
            (:constructor %make-eth-sync-peer-source))
  "One independently driven sync peer.

The fetch closures are deliberately injectable: production wraps ETH-PEER,
while integration tests can script latency and bad responses without sockets."
  id
  peer
  head-number
  fetch-headers
  fetch-bodies
  fetch-receipts
  penalty
  cancel)

(defun make-eth-sync-peer-source
    (peer &key id head-number fetch-headers fetch-bodies fetch-receipts
               penalty cancel)
  "Wrap PEER for a multi-peer download.

FETCH-HEADERS receives ORIGIN and AMOUNT. FETCH-BODIES and FETCH-RECEIPTS
receive the validated header list. PENALTY receives REASON, SCORE, and DETAIL.
CANCEL should interrupt a blocked request (normally by closing that peer's
socket); it is invoked after a timeout."
  (%make-eth-sync-peer-source
   :id (or id (and peer (eth-peer-remote-client-id peer)) peer)
   :peer peer
   :head-number
   (or head-number
       (and peer
            (>= (eth-peer-eth-version peer) +eth-protocol-version-69+)
            (eth-status-latest-block (eth-peer-remote-status peer))))
   :fetch-headers
   (or fetch-headers
       (lambda (origin amount)
         (eth-peer-get-block-headers peer :origin-number origin :amount amount)))
   :fetch-bodies
   (or fetch-bodies
       (lambda (headers)
         (eth-peer-get-block-bodies
          peer
          (mapcar (lambda (header)
                    (hash32-bytes (block-header-hash header)))
                  headers))))
   :fetch-receipts
   (or fetch-receipts
       (lambda (headers)
         (eth-peer-get-receipts
          peer
          (mapcar (lambda (header)
                    (hash32-bytes (block-header-hash header)))
                  headers))))
   :penalty penalty
   :cancel
   (or cancel
       (and peer
            (lambda ()
              ;; Closing the stream is the only safe way to interrupt a peer
              ;; stopped mid-frame; unwinding the frame read would leave the
              ;; ingress cipher and MAC advanced only halfway.
              (ignore-errors
               (close
                (rlpx-connection-stream (eth-peer-connection peer))
                :abort t)))))))

(defstruct (eth-sync-delivery
            (:constructor make-eth-sync-delivery (origin amount)))
  origin
  amount
  remainder-origin
  remainder-amount
  peer-source
  headers
  bodies
  receipts
  (started-at 0)
  (attempt 0))

(defun eth-sync-delivery-retain-prefix (delivery count)
  "Keep COUNT leading blocks and remember one unscheduled remainder.

Soft byte limits may shorten both body and receipt responses.  Repeated
truncation composes into one contiguous remainder, allowing the coordinator to
replace (rather than add to) the resident delivery and preserve its
target-height-independent window bound."
  (let ((amount (eth-sync-delivery-amount delivery)))
    (unless (and (integerp count) (plusp count) (<= count amount))
      (error 'eth-sync-malformed-delivery
             :detail (format nil
                             "peer retained invalid delivery prefix ~S of ~D"
                             count amount)))
    (when (< count amount)
      (setf (eth-sync-delivery-remainder-origin delivery)
            (+ (eth-sync-delivery-origin delivery) count)
            (eth-sync-delivery-remainder-amount delivery)
            (+ (- amount count)
               (or (eth-sync-delivery-remainder-amount delivery) 0))
            (eth-sync-delivery-amount delivery) count)
      (when (eth-sync-delivery-headers delivery)
        (setf (eth-sync-delivery-headers delivery)
              (subseq (eth-sync-delivery-headers delivery) 0 count)))
      (when (eth-sync-delivery-bodies delivery)
        (setf (eth-sync-delivery-bodies delivery)
              (subseq (eth-sync-delivery-bodies delivery) 0 count)))
      (when (eth-sync-delivery-receipts delivery)
        (setf (eth-sync-delivery-receipts delivery)
              (subseq (eth-sync-delivery-receipts delivery) 0 count)))))
  delivery)

#+sbcl
(defstruct (eth-sync-multi-state
            (:constructor make-eth-sync-multi-state (pending)))
  (lock (sb-thread:make-mutex :name "eth-sync-multi"))
  (changed (sb-thread:make-waitqueue :name "eth-sync-multi-changed"))
  pending
  (in-flight (make-hash-table :test #'eq))
  (header-queue (make-hash-table))
  (body-queue (make-hash-table))
  (receipt-queue (make-hash-table))
  (completed (make-hash-table))
  (disabled-peers (make-hash-table :test #'eq))
  (events '())
  error
  stopped-p)

#+sbcl
(defun eth-sync-refill-delivery-window
    (state next-origin target batch-size window-batches)
  "Keep at most WINDOW-BATCHES deliveries resident across every queue.

NEXT-ORIGIN is the first range not constructed yet.  The returned value is the
next unscheduled origin after refilling.  Counting pending, in-flight, and
completed deliveries together is important: a fast peer must not be able to
buffer the rest of a long chain behind one slow first batch."
  (sb-thread:with-mutex ((eth-sync-multi-state-lock state))
    (let ((resident (+ (length (eth-sync-multi-state-pending state))
                       (hash-table-count
                        (eth-sync-multi-state-in-flight state))
                       (hash-table-count
                        (eth-sync-multi-state-completed state)))))
      (loop while (and (<= next-origin target)
                       (< resident window-batches))
            do (setf (eth-sync-multi-state-pending state)
                     (nconc
                      (eth-sync-multi-state-pending state)
                      (list
                       (make-eth-sync-delivery
                        next-origin
                        (min batch-size (1+ (- target next-origin)))))))
               (incf next-origin batch-size)
               (incf resident))
      (sb-thread:condition-broadcast
       (eth-sync-multi-state-changed state))
      next-origin)))

(defun eth-sync-monotonic-seconds ()
  (/ (get-internal-real-time)
     (float internal-time-units-per-second 1d0)))

(defun eth-sync-malformed (control &rest arguments)
  (error 'eth-sync-malformed-delivery
         :detail (apply #'format nil control arguments)))

(defun eth-sync-validate-receipt-delivery
    (headers bodies receipt-groups incomplete-last-p)
  "Validate wire receipt groups and return canonical receipt groups.

eth/69 and later carry the transaction type beside each receipt.  The wire
decoder deliberately preserves that pair as ETH-WIRE-RECEIPT; execution and
persistence consume the enclosed RECEIPT.  Verify the redundant type against
the committed block body before unwrapping it.  Scripted tests may still
provide canonical RECEIPT values directly."
  (when incomplete-last-p
    (eth-sync-malformed "receipt delivery ended in a partial receipt group"))
  (unless (= (length receipt-groups) (length headers))
    (eth-sync-malformed "peer returned ~D receipt groups for ~D headers"
                        (length receipt-groups) (length headers)))
  (loop for header in headers
        for body in bodies
        for wire-receipts in receipt-groups
        for transactions = (eth-block-body-transactions body)
        for receipts =
          (progn
            (unless (= (length transactions) (length wire-receipts))
              (eth-sync-malformed
               "peer returned ~D receipts for ~D transactions at block ~D"
               (length wire-receipts) (length transactions)
               (block-header-number header)))
            (loop for transaction in transactions
                  for wire-receipt in wire-receipts
                  collect
                  (cond
                    ((typep wire-receipt
                            'ethereum-lisp.eth-wire:eth-wire-receipt)
                     (unless
                         (= (transaction-type transaction)
                            (ethereum-lisp.eth-wire:eth-wire-receipt-transaction-type
                             wire-receipt))
                       (eth-sync-malformed
                        "receipt transaction type does not match block body at block ~D"
                        (block-header-number header)))
                     (ethereum-lisp.eth-wire:eth-wire-receipt-receipt
                      wire-receipt))
                    ((typep wire-receipt 'ethereum-lisp.receipts:receipt)
                     wire-receipt)
                    (t
                     (eth-sync-malformed
                      "peer returned a non-receipt value at block ~D"
                      (block-header-number header))))))
        for expected = (block-header-receipts-root header)
        do (when (and expected
                      (not
                       (hash32=
                        expected
                        (ethereum-lisp.receipts:transaction-receipt-list-root
                         transactions receipts))))
             (eth-sync-malformed
              "receipt root does not match header at block ~D"
              (block-header-number header)))
        collect receipts))

#+sbcl
(defun eth-sync-state-notify (state event)
  (push event (eth-sync-multi-state-events state))
  (sb-thread:condition-broadcast (eth-sync-multi-state-changed state)))

#+sbcl
(defun eth-sync-state-stage-delivery (state delivery stage value)
  (sb-thread:with-mutex ((eth-sync-multi-state-lock state))
    (when (eq delivery
              (gethash (eth-sync-delivery-peer-source delivery)
                       (eth-sync-multi-state-in-flight state)))
      (setf (gethash (eth-sync-delivery-origin delivery)
                     (ecase stage
                       (:headers (eth-sync-multi-state-header-queue state))
                       (:bodies (eth-sync-multi-state-body-queue state))
                       (:receipts (eth-sync-multi-state-receipt-queue state))))
            value)
      (setf (eth-sync-delivery-started-at delivery)
            (eth-sync-monotonic-seconds))
      (eth-sync-state-notify
       state
       (list :event :delivered :stage stage
             :origin (eth-sync-delivery-origin delivery)
             :peer (eth-sync-peer-source-id
                    (eth-sync-delivery-peer-source delivery)))))))

#+sbcl
(defun eth-sync-state-complete-delivery (state source delivery)
  (sb-thread:with-mutex ((eth-sync-multi-state-lock state))
    (when (eq delivery
              (gethash source (eth-sync-multi-state-in-flight state)))
      (remhash source (eth-sync-multi-state-in-flight state))
      (setf (gethash (eth-sync-delivery-origin delivery)
                     (eth-sync-multi-state-completed state))
            delivery)
      (eth-sync-state-notify
       state (list :event :batch-ready
                   :origin (eth-sync-delivery-origin delivery)
                   :peer (eth-sync-peer-source-id source))))))

#+sbcl
(defun eth-sync-state-fail-delivery (state source delivery condition malformed-p)
  (sb-thread:with-mutex ((eth-sync-multi-state-lock state))
    (when (eq delivery
              (gethash source (eth-sync-multi-state-in-flight state)))
      (remhash source (eth-sync-multi-state-in-flight state))
      (setf (gethash source (eth-sync-multi-state-disabled-peers state)) t)
      (dolist (queue (list (eth-sync-multi-state-header-queue state)
                           (eth-sync-multi-state-body-queue state)
                           (eth-sync-multi-state-receipt-queue state)))
        (remhash (eth-sync-delivery-origin delivery) queue))
      (incf (eth-sync-delivery-attempt delivery))
      (setf (eth-sync-delivery-peer-source delivery) nil)
      (setf (eth-sync-multi-state-pending state)
            (nconc (eth-sync-multi-state-pending state) (list delivery)))
      (eth-sync-state-notify
       state
       (list :event (if malformed-p :malformed :failed)
             :origin (eth-sync-delivery-origin delivery)
             :peer (eth-sync-peer-source-id source)
             :detail (princ-to-string condition))))))

#+sbcl
(defun eth-sync-fetch-delivery
    (state source delivery fetch-receipts-p)
  (handler-case
      (let ((headers
              (funcall (eth-sync-peer-source-fetch-headers source)
                       (eth-sync-delivery-origin delivery)
                       (eth-sync-delivery-amount delivery))))
        (handler-case
            (progn
              (unless (= (length headers) (eth-sync-delivery-amount delivery))
                (eth-sync-malformed "peer returned ~D headers for requested ~D"
                                    (length headers)
                                    (eth-sync-delivery-amount delivery)))
              (eth-sync-validate-header-batch
               headers (eth-sync-delivery-origin delivery) nil))
          (serious-condition (condition)
            (unless (typep condition 'eth-sync-malformed-delivery)
              (eth-sync-malformed "~A" condition))
            (error condition)))
        (setf (eth-sync-delivery-headers delivery) headers)
        (eth-sync-state-stage-delivery state delivery :headers headers)
        (let ((bodies
                (funcall (eth-sync-peer-source-fetch-bodies source) headers)))
          (handler-case
              (progn
                (when (or (null bodies) (> (length bodies) (length headers)))
                  (eth-sync-malformed "peer returned ~D bodies for ~D headers"
                                      (length bodies) (length headers)))
                (loop for header in headers
                      for body in bodies
                      do (eth-sync-validate-body header body)))
            (serious-condition (condition)
              (unless (typep condition 'eth-sync-malformed-delivery)
                (eth-sync-malformed "~A" condition))
              (error condition)))
          (setf (eth-sync-delivery-bodies delivery) bodies)
          (eth-sync-delivery-retain-prefix delivery (length bodies))
          (setf headers (eth-sync-delivery-headers delivery)
                bodies (eth-sync-delivery-bodies delivery))
          (eth-sync-state-stage-delivery state delivery :bodies bodies)
          (if fetch-receipts-p
              (multiple-value-bind (receipts incomplete-last-p)
                  (funcall (eth-sync-peer-source-fetch-receipts source) headers)
                (let ((complete-receipts
                        (if incomplete-last-p
                            (butlast receipts)
                            receipts)))
                  (handler-case
                      (progn
                        (when (or (null complete-receipts)
                                  (> (length complete-receipts)
                                     (length headers)))
                          (eth-sync-malformed
                           "peer returned ~D complete receipt groups for ~D headers"
                           (length complete-receipts) (length headers)))
                        (setf complete-receipts
                              (eth-sync-validate-receipt-delivery
                               (subseq headers 0 (length complete-receipts))
                               (subseq bodies 0 (length complete-receipts))
                               complete-receipts nil)))
                    (serious-condition (condition)
                      (unless (typep condition 'eth-sync-malformed-delivery)
                        (eth-sync-malformed "~A" condition))
                      (error condition)))
                  (setf (eth-sync-delivery-receipts delivery)
                        complete-receipts)
                  (eth-sync-delivery-retain-prefix
                   delivery (length complete-receipts))
                  (setf headers (eth-sync-delivery-headers delivery)
                        bodies (eth-sync-delivery-bodies delivery)
                        receipts (eth-sync-delivery-receipts delivery)))
                (eth-sync-state-stage-delivery
                 state delivery :receipts receipts))
              ;; Engine ancestor recovery validates and executes every block
              ;; locally, producing canonical receipts itself.  Do not wait
              ;; for a secondary peer to serve receipt groups for an invalid
              ;; noncanonical branch; preserve one empty attachment per block
              ;; so the common ordered assembly path remains unchanged.
              (let ((receipts
                      (loop repeat (length headers) collect nil)))
                (setf (eth-sync-delivery-receipts delivery) receipts)
                (eth-sync-state-stage-delivery
                 state delivery :receipts receipts))))
        (eth-sync-state-complete-delivery state source delivery))
    (eth-sync-malformed-delivery (condition)
      (eth-sync-state-fail-delivery state source delivery condition t))
    (serious-condition (condition)
      (eth-sync-state-fail-delivery state source delivery condition nil))))

#+sbcl
(defun eth-sync-worker-loop (state source fetch-receipts-p)
  (loop
    (let ((delivery
            (sb-thread:with-mutex ((eth-sync-multi-state-lock state))
              (loop
                (when (eth-sync-multi-state-stopped-p state)
                  (return-from eth-sync-worker-loop nil))
                (unless (or (gethash source
                                     (eth-sync-multi-state-disabled-peers state))
                            (null (eth-sync-multi-state-pending state)))
                  (let ((next (pop (eth-sync-multi-state-pending state))))
                    (setf (eth-sync-delivery-peer-source next) source
                          (eth-sync-delivery-started-at next)
                          (eth-sync-monotonic-seconds)
                          (gethash source
                                   (eth-sync-multi-state-in-flight state))
                          next)
                    (eth-sync-state-notify
                     state (list :event :assigned
                                 :origin (eth-sync-delivery-origin next)
                                 :peer (eth-sync-peer-source-id source)
                                 :in-flight
                                 (hash-table-count
                                  (eth-sync-multi-state-in-flight state))))
                    (return next)))
                (when (gethash source
                               (eth-sync-multi-state-disabled-peers state))
                  (return-from eth-sync-worker-loop nil))
                (sb-thread:condition-wait
                 (eth-sync-multi-state-changed state)
                 (eth-sync-multi-state-lock state))))))
      (eth-sync-fetch-delivery
       state source delivery fetch-receipts-p))))

#+sbcl
(defun eth-sync-record-worker-crash (state source condition)
  (let ((delivery
          (sb-thread:with-mutex ((eth-sync-multi-state-lock state))
            (gethash source (eth-sync-multi-state-in-flight state)))))
    (if delivery
        (eth-sync-state-fail-delivery state source delivery condition nil)
        (sb-thread:with-mutex ((eth-sync-multi-state-lock state))
          (unless (eth-sync-multi-state-stopped-p state)
            (setf (gethash source (eth-sync-multi-state-disabled-peers state)) t)
            (eth-sync-state-notify
             state (list :event :worker-failed
                         :peer (eth-sync-peer-source-id source)
                         :detail (princ-to-string condition))))))))

#+sbcl
(defun eth-sync-progress-snapshot (state start target imported)
  (sb-thread:with-mutex ((eth-sync-multi-state-lock state))
    (labels ((size (table) (hash-table-count table)))
      (list :start start
            :current (+ start imported)
            :target target
            :pivot target
            :imported imported
            :pending (length (eth-sync-multi-state-pending state))
            :in-flight (size (eth-sync-multi-state-in-flight state))
            :queued-headers (size (eth-sync-multi-state-header-queue state))
            :queued-bodies (size (eth-sync-multi-state-body-queue state))
            :queued-receipts
            (size (eth-sync-multi-state-receipt-queue state))))))

#+sbcl
(defun eth-sync-penalize (source reason detail)
  (let ((score (ecase reason
                 (:timeout -10)
                 (:failed -25)
                 (:malformed -50))))
    (when (eth-sync-peer-source-penalty source)
      (funcall (eth-sync-peer-source-penalty source) reason score detail))
    score))

#+sbcl
(defun eth-sync-expire-deliveries (state timeout-seconds)
  (let ((now (eth-sync-monotonic-seconds))
        (expired '()))
    (sb-thread:with-mutex ((eth-sync-multi-state-lock state))
      (maphash
       (lambda (source delivery)
         (when (>= (- now (eth-sync-delivery-started-at delivery))
                   timeout-seconds)
           (push (cons source delivery) expired)))
       (eth-sync-multi-state-in-flight state))
      (dolist (entry expired)
        (let ((source (car entry))
              (delivery (cdr entry)))
          (remhash source (eth-sync-multi-state-in-flight state))
          (setf (gethash source (eth-sync-multi-state-disabled-peers state)) t)
          (dolist (queue (list (eth-sync-multi-state-header-queue state)
                               (eth-sync-multi-state-body-queue state)
                               (eth-sync-multi-state-receipt-queue state)))
            (remhash (eth-sync-delivery-origin delivery) queue))
          (incf (eth-sync-delivery-attempt delivery))
          (setf (eth-sync-delivery-peer-source delivery) nil
                (eth-sync-multi-state-pending state)
                (nconc (eth-sync-multi-state-pending state) (list delivery)))
          (eth-sync-state-notify
           state (list :event :timeout
                       :origin (eth-sync-delivery-origin delivery)
                       :peer (eth-sync-peer-source-id source))))))
    expired))

(defun eth-sync-download-blocks-multi
    (peer-sources import-block
     &key (start-number 1)
          target-number
          max-blocks
          (batch-size +eth-sync-default-batch-size+)
          (request-timeout-seconds 10)
          expected-parent-hash
          expected-target-hash
          import-batch
          progress
          consume-receipts
          (fetch-receipts-p t))
  "Download and import a bounded range concurrently from PEER-SOURCES.

Each source has at most one request in flight. Header, body, and receipt
deliveries are independently queued by origin, but IMPORT-BLOCK is called only
in ascending block order. A timeout, request failure, or malformed delivery
disables and penalizes only its source and requeues the missing range.

EXPECTED-PARENT-HASH anchors the first imported header to durable local state.
EXPECTED-TARGET-HASH, when supplied by the consensus-driven caller, must name
the final header. Neither value is inferred from an untrusted peer head.

PROGRESS receives a snapshot plist followed by an event plist. CONSUME-RECEIPTS,
when supplied, receives each imported BLOCK and its downloaded receipt group.
FETCH-RECEIPTS-P may be false only when the importer executes blocks locally
and does not consume peer receipt groups; the default preserves full delivery.
IMPORT-BATCH, when supplied, receives each contiguous list with verified
receipts attached and replaces the per-block IMPORT-BLOCK calls. It is the
durable skeleton seam used to commit one downloader batch per WAL batch.
Returns the number of blocks imported."
  #-sbcl
  (declare (ignore peer-sources import-block start-number target-number max-blocks
                   batch-size request-timeout-seconds progress consume-receipts
                   fetch-receipts-p))
  #-sbcl
  (error "multi-peer synchronization requires SBCL threads")
  #+sbcl
  (let* ((target
           (or target-number
               (and max-blocks (+ start-number max-blocks -1))
               (loop for source in peer-sources
                     maximize (or (eth-sync-peer-source-head-number source) 0))))
         (state (make-eth-sync-multi-state nil))
         (threads '())
         (next start-number)
         (next-unscheduled start-number)
         ;; Two windows per peer permit useful overlap while bounding every
         ;; staged header/body/receipt group independently of target height.
         (window-batches (max 2 (* 2 (length peer-sources))))
         (imported 0)
         (previous-header nil))
    (unless peer-sources
      (eth-sync-multi-peer-fail
       "multi-peer synchronization requires at least one peer"))
    (unless (and (integerp batch-size) (plusp batch-size))
      (error "multi-peer synchronization BATCH-SIZE must be positive"))
    (unless (and (realp request-timeout-seconds)
                 (plusp request-timeout-seconds))
      (error "multi-peer synchronization REQUEST-TIMEOUT-SECONDS must be positive"))
    (when (and consume-receipts (not fetch-receipts-p))
      (error "CONSUME-RECEIPTS requires FETCH-RECEIPTS-P"))
    (unless (and target (>= target start-number))
      (error "multi-peer synchronization needs TARGET-NUMBER, MAX-BLOCKS, or peer heads"))
    (setf next-unscheduled
          (eth-sync-refill-delivery-window
           state next-unscheduled target batch-size window-batches))
    (unwind-protect
         (progn
           (dolist (source peer-sources)
             (let ((worker-source source))
               (push
                (sb-thread:make-thread
                 (lambda ()
                   (handler-case
                       (eth-sync-worker-loop
                        state worker-source fetch-receipts-p)
                     (serious-condition (condition)
                       (eth-sync-record-worker-crash
                        state worker-source condition))))
                 :name (format nil "eth-sync-~A"
                               (eth-sync-peer-source-id worker-source)))
                threads)))
           (loop while (<= next target)
                 do
                    (dolist (entry
                             (eth-sync-expire-deliveries
                              state request-timeout-seconds))
                      (let ((source (car entry)))
                        (eth-sync-penalize source :timeout "request timed out")
                        (when (eth-sync-peer-source-cancel source)
                          (funcall (eth-sync-peer-source-cancel source)))))
                    (let ((events nil)
                          (delivery nil)
                          (dead-p nil))
                      (sb-thread:with-mutex ((eth-sync-multi-state-lock state))
                        (setf events
                              (nreverse
                               (prog1 (eth-sync-multi-state-events state)
                                 (setf (eth-sync-multi-state-events state) nil)))
                              delivery
                              (gethash next
                                       (eth-sync-multi-state-completed state))
                              dead-p
                              (and (null delivery)
                                   (plusp (length
                                           (eth-sync-multi-state-pending state)))
                                   (= (hash-table-count
                                       (eth-sync-multi-state-disabled-peers state))
                                      (length peer-sources))
                                   (zerop (hash-table-count
                                           (eth-sync-multi-state-in-flight state)))))
                        (unless (or delivery dead-p)
                          (sb-thread:condition-wait
                           (eth-sync-multi-state-changed state)
                           (eth-sync-multi-state-lock state)
                           :timeout (min 0.05 request-timeout-seconds))))
                      (dolist (event events)
                        (let* ((source
                                 (find (getf event :peer) peer-sources
                                       :key #'eth-sync-peer-source-id
                                       :test #'equal))
                               (kind (getf event :event)))
                          (when (and source (member kind '(:failed :malformed)))
                            (eth-sync-penalize
                             source kind (getf event :detail))))
                        (when progress
                          (funcall progress
                                   (eth-sync-progress-snapshot
                                    state start-number target imported)
                                   event)))
                      (when dead-p
                        (eth-sync-multi-peer-fail
                         "all sync peers failed with block ~D still pending"
                         next))
                      (when delivery
                        (handler-case
                            (progn
                              (eth-sync-validate-header-batch
                               (eth-sync-delivery-headers delivery)
                               next previous-header
                               :expected-parent-hash
                               (and (= next start-number)
                                    expected-parent-hash))
                              ;; Reject a peer's divergent terminal header
                              ;; before IMPORT-BATCH can durably expose it.
                              (when (and expected-target-hash
                                         (= (+ next
                                               (eth-sync-delivery-amount delivery)
                                               -1)
                                            target)
                                         (not
                                          (hash32=
                                           (block-header-hash
                                            (car
                                             (last
                                              (eth-sync-delivery-headers
                                               delivery))))
                                           (if (hash32-p expected-target-hash)
                                               expected-target-hash
                                               (make-hash32
                                                expected-target-hash)))))
                                (eth-sync-malformed
                                 "terminal header does not match the consensus target")))
                          (serious-condition (condition)
                            (let ((source
                                    (eth-sync-delivery-peer-source delivery)))
                              (sb-thread:with-mutex
                                  ((eth-sync-multi-state-lock state))
                                (remhash next
                                         (eth-sync-multi-state-completed state))
                                (dolist
                                    (queue
                                     (list
                                      (eth-sync-multi-state-header-queue state)
                                      (eth-sync-multi-state-body-queue state)
                                      (eth-sync-multi-state-receipt-queue state)))
                                  (remhash next queue))
                                (setf (gethash
                                       source
                                       (eth-sync-multi-state-disabled-peers state))
                                      t
                                      (eth-sync-delivery-peer-source delivery) nil
                                      (eth-sync-multi-state-pending state)
                                      (nconc
                                       (eth-sync-multi-state-pending state)
                                       (list delivery)))
                                (eth-sync-state-notify
                                 state (list :event :malformed
                                             :origin next
                                             :peer
                                             (eth-sync-peer-source-id source)
                                             :detail
                                             (princ-to-string condition)))))
                            (setf delivery nil)))
                      (when delivery
                          (let ((blocks
                                  (loop
                                    for header in
                                      (eth-sync-delivery-headers delivery)
                                    for body in
                                      (eth-sync-delivery-bodies delivery)
                                    for receipts in
                                      (eth-sync-delivery-receipts delivery)
                                    collect
                                    (eth-sync-assemble-block-with-receipts
                                     header body receipts))))
                            (if import-batch
                                (funcall import-batch blocks)
                                (dolist (block blocks)
                                  (funcall import-block block)))
                            (when consume-receipts
                              (dolist (block blocks)
                                (funcall consume-receipts
                                         block (block-receipts block))))
                            (setf previous-header
                                  (block-header (car (last blocks))))
                            (incf imported (length blocks)))
                          (sb-thread:with-mutex
                              ((eth-sync-multi-state-lock state))
                            (remhash next
                                     (eth-sync-multi-state-completed state))
                            (dolist
                                (queue
                                 (list (eth-sync-multi-state-header-queue state)
                                       (eth-sync-multi-state-body-queue state)
                                       (eth-sync-multi-state-receipt-queue state)))
                              (remhash next queue))
                            ;; A soft-limited response replaces this completed
                            ;; delivery with its unscheduled suffix.  It does
                            ;; not add another resident batch, so the two-per-
                            ;; peer delivery-window bound remains exact.
                            (when (eth-sync-delivery-remainder-amount delivery)
                              (push
                               (make-eth-sync-delivery
                                (eth-sync-delivery-remainder-origin delivery)
                                (eth-sync-delivery-remainder-amount delivery))
                               (eth-sync-multi-state-pending state)))
                            (sb-thread:condition-broadcast
                             (eth-sync-multi-state-changed state)))
                          (setf next-unscheduled
                                (eth-sync-refill-delivery-window
                                 state next-unscheduled target batch-size
                                 window-batches))
                          (when progress
                            (funcall
                             progress
                             (eth-sync-progress-snapshot
                              state start-number target imported)
                             (list :event :imported
                                   :from next
                                   :through
                                   (block-header-number previous-header))))
                          (incf next
                                (eth-sync-delivery-amount delivery))))))
           (when (and expected-target-hash
                      (or (null previous-header)
                          (not
                           (hash32=
                            (block-header-hash previous-header)
                            (if (hash32-p expected-target-hash)
                                expected-target-hash
                                (make-hash32 expected-target-hash))))))
             (eth-sync-multi-peer-fail
              "downloaded target block ~D does not match the consensus target"
              target))
           imported)
      (let ((cancel
              (sb-thread:with-mutex ((eth-sync-multi-state-lock state))
                (setf (eth-sync-multi-state-stopped-p state) t)
                (sb-thread:condition-broadcast
                 (eth-sync-multi-state-changed state))
                (loop for source in peer-sources
                      when (and
                            (gethash
                             source (eth-sync-multi-state-in-flight state))
                            (eth-sync-peer-source-cancel source))
                        collect source))))
        (dolist (source cancel)
          (funcall (eth-sync-peer-source-cancel source))))
      (dolist (thread threads)
        (sb-thread:join-thread thread :timeout 5 :default nil)))))
