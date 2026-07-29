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

(defun eth-sync-validate-header-batch (headers origin-number previous-header)
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

(defun eth-sync-download-blocks
    (peer import-block
     &key (start-number 1)
          (batch-size +eth-sync-default-batch-size+)
          (max-blocks nil)
          (progress nil))
  "Download blocks forward from START-NUMBER, importing each in order.

Requests headers from PEER in batches, fetches their bodies, assembles each
block, and calls IMPORT-BLOCK on it. IMPORT-BLOCK receives one assembled block
and is expected to execute and commit it; an error it signals propagates and
stops the download. PROGRESS, if given, is called with each block after import.
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
          (eth-sync-validate-header-batch headers next previous-header)
          (let* ((hashes (mapcar (lambda (h) (hash32-bytes (block-header-hash h)))
                                 headers))
                 (bodies (eth-peer-get-block-bodies peer hashes)))
            (unless (= (length bodies) (length headers))
              (error "peer returned ~D bodies for ~D headers"
                     (length bodies) (length headers)))
            (loop for header in headers
                  for body in bodies
                  do (eth-sync-validate-body header body)
                     (let ((block (eth-sync-assemble-block header body)))
                       (funcall import-block block)
                       (incf imported)
                       (when progress (funcall progress block))))
            (setf previous-header (car (last headers)))
            (setf next (+ next (length headers)))
            ;; A short batch means the peer has no more blocks past its tip.
            (when (< (length headers) amount)
              (return imported))))))))

(define-condition eth-sync-malformed-delivery (error)
  ((detail :initarg :detail :reader eth-sync-malformed-delivery-detail))
  (:report (lambda (condition stream)
             (format stream "malformed sync delivery: ~A"
                     (eth-sync-malformed-delivery-detail condition)))))

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
  peer-source
  headers
  bodies
  receipts
  (started-at 0)
  (attempt 0))

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

(defun eth-sync-monotonic-seconds ()
  (/ (get-internal-real-time)
     (float internal-time-units-per-second 1d0)))

(defun eth-sync-malformed (control &rest arguments)
  (error 'eth-sync-malformed-delivery
         :detail (apply #'format nil control arguments)))

(defun eth-sync-validate-receipt-delivery
    (headers bodies receipt-groups incomplete-last-p)
  (when incomplete-last-p
    (eth-sync-malformed "receipt delivery ended in a partial receipt group"))
  (unless (= (length receipt-groups) (length headers))
    (eth-sync-malformed "peer returned ~D receipt groups for ~D headers"
                        (length receipt-groups) (length headers)))
  (loop for header in headers
        for body in bodies
        for receipts in receipt-groups
        for expected = (block-header-receipts-root header)
        when (and expected
                  (not (hash32=
                        expected
                        (ethereum-lisp.receipts:transaction-receipt-list-root
                         (eth-block-body-transactions body) receipts))))
          do (eth-sync-malformed
              "receipt root does not match header at block ~D"
              (block-header-number header)))
  t)

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
(defun eth-sync-fetch-delivery (state source delivery)
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
                (unless (= (length bodies) (length headers))
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
          (eth-sync-state-stage-delivery state delivery :bodies bodies)
          (multiple-value-bind (receipts incomplete-last-p)
              (funcall (eth-sync-peer-source-fetch-receipts source) headers)
            (handler-case
                (eth-sync-validate-receipt-delivery
                 headers bodies receipts incomplete-last-p)
              (serious-condition (condition)
                (unless (typep condition 'eth-sync-malformed-delivery)
                  (eth-sync-malformed "~A" condition))
                (error condition)))
            (setf (eth-sync-delivery-receipts delivery) receipts)
            (eth-sync-state-stage-delivery state delivery :receipts receipts)))
        (eth-sync-state-complete-delivery state source delivery))
    (eth-sync-malformed-delivery (condition)
      (eth-sync-state-fail-delivery state source delivery condition t))
    (serious-condition (condition)
      (eth-sync-state-fail-delivery state source delivery condition nil))))

#+sbcl
(defun eth-sync-worker-loop (state source)
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
      (eth-sync-fetch-delivery state source delivery))))

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
          progress
          consume-receipts)
  "Download and import a bounded range concurrently from PEER-SOURCES.

Each source has at most one request in flight. Header, body, and receipt
deliveries are independently queued by origin, but IMPORT-BLOCK is called only
in ascending block order. A timeout, request failure, or malformed delivery
disables and penalizes only its source and requeues the missing range.

PROGRESS receives a snapshot plist followed by an event plist. CONSUME-RECEIPTS,
when supplied, receives each imported BLOCK and its downloaded receipt group.
Returns the number of blocks imported."
  #-sbcl
  (declare (ignore peer-sources import-block start-number target-number max-blocks
                   batch-size request-timeout-seconds progress consume-receipts))
  #-sbcl
  (error "multi-peer synchronization requires SBCL threads")
  #+sbcl
  (let* ((target
           (or target-number
               (and max-blocks (+ start-number max-blocks -1))
               (loop for source in peer-sources
                     maximize (or (eth-sync-peer-source-head-number source) 0))))
         (pending
           (loop for origin from start-number to target by batch-size
                 collect (make-eth-sync-delivery
                          origin (min batch-size (1+ (- target origin))))))
         (state (make-eth-sync-multi-state pending))
         (threads '())
         (next start-number)
         (imported 0)
         (previous-header nil))
    (unless peer-sources
      (error "multi-peer synchronization requires at least one peer"))
    (unless (and (integerp batch-size) (plusp batch-size))
      (error "multi-peer synchronization BATCH-SIZE must be positive"))
    (unless (and (realp request-timeout-seconds)
                 (plusp request-timeout-seconds))
      (error "multi-peer synchronization REQUEST-TIMEOUT-SECONDS must be positive"))
    (unless (and target (>= target start-number))
      (error "multi-peer synchronization needs TARGET-NUMBER, MAX-BLOCKS, or peer heads"))
    (unwind-protect
         (progn
           (dolist (source peer-sources)
             (let ((worker-source source))
               (push
                (sb-thread:make-thread
                 (lambda ()
                   (handler-case
                       (eth-sync-worker-loop state worker-source)
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
                        (error "all sync peers failed with block ~D still pending"
                               next))
                      (when delivery
                        (handler-case
                            (eth-sync-validate-header-batch
                             (eth-sync-delivery-headers delivery)
                             next previous-header)
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
                          (loop for header in (eth-sync-delivery-headers delivery)
                                for body in (eth-sync-delivery-bodies delivery)
                                for receipts in
                                  (eth-sync-delivery-receipts delivery)
                                for block = (eth-sync-assemble-block header body)
                                do (funcall import-block block)
                                   (when consume-receipts
                                     (funcall consume-receipts block receipts))
                                   (setf previous-header header)
                                   (incf imported))
                          (sb-thread:with-mutex
                              ((eth-sync-multi-state-lock state))
                            (remhash next
                                     (eth-sync-multi-state-completed state))
                            (dolist
                                (queue
                                 (list (eth-sync-multi-state-header-queue state)
                                       (eth-sync-multi-state-body-queue state)
                                       (eth-sync-multi-state-receipt-queue state)))
                              (remhash next queue)))
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
