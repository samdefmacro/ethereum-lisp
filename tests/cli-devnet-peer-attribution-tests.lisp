(in-package #:ethereum-lisp.test)

;;;; Who is charged for a sync failure.
;;;;
;;;; A peer is scored or disconnected for what it did on the wire, never for a
;;;; verdict the node reached about the content it delivered, and never for a
;;;; condition of the whole source pool. The reference is geth v1.17.6:
;;;; eth/downloader/downloader.go importBlockResults reports an execution
;;;; failure through the badBlock callback and aborts the cycle with
;;;; errInvalidChain, while fetchers_concurrent.go hands only errInvalidBody /
;;;; errInvalidReceipt (validityErrorOfRequest) back to the peer's handler, so
;;;; only a wire-level mismatch ends the delivering peer's session. The record
;;;; is docs/evidence/sec5-peer-attribution.txt.

(defun peer-attribution-invalid-copy (block)
  "BLOCK with a state root no execution can produce. Its body still matches the
header (the state root is not a body commitment), so every wire-level check
passes and only execution can reject it."
  (let ((header (copy-structure (block-header block)))
        (copy (copy-structure block)))
    (setf (block-header-state-root header)
          (make-hash32 (make-byte-vector 32 :initial-element #x5a))
          (block-header copy) header)
    copy))

(defun peer-attribution-serve (peer blocks)
  "Answer GetBlockHeaders (by number or by hash, either direction) and
GetBlockBodies from BLOCKS until the connection ends. Other messages are read
and ignored. Returns how the loop ended."
  (let ((by-hash (make-hash-table :test #'equalp))
        (by-number (make-hash-table)))
    (dolist (block blocks)
      (setf (gethash (hash32-bytes (block-hash block)) by-hash) block
            (gethash (block-header-number (block-header block)) by-number)
            block))
    (handler-case
        (loop
          (multiple-value-bind (eth-id payload) (eth-peer-read peer)
            (cond
              ((= eth-id ethereum-lisp.eth-wire:+eth-message-get-block-headers+)
               (let* ((request
                        (ethereum-lisp.eth-wire:decode-eth-get-block-headers
                         payload))
                      (origin-hash
                        (ethereum-lisp.eth-wire:eth-get-block-headers-origin-hash
                         request))
                      (origin
                        (if origin-hash
                            (let ((block (gethash origin-hash by-hash)))
                              (and block
                                   (block-header-number (block-header block))))
                            (ethereum-lisp.eth-wire:eth-get-block-headers-origin-number
                             request)))
                      (step
                        (* (if (ethereum-lisp.eth-wire:eth-get-block-headers-reverse
                                request)
                               -1
                               1)
                           (1+ (ethereum-lisp.eth-wire:eth-get-block-headers-skip
                                request))))
                      (headers
                        (and origin
                             (loop for count
                                     below (ethereum-lisp.eth-wire:eth-get-block-headers-amount
                                            request)
                                   for number = (+ origin (* count step))
                                   for block = (gethash number by-number)
                                   while block
                                   collect (block-header block)))))
                 (eth-peer-send
                  peer ethereum-lisp.eth-wire:+eth-message-block-headers+
                  (ethereum-lisp.eth-wire:encode-eth-block-headers
                   (ethereum-lisp.eth-wire:eth-get-block-headers-request-id
                    request)
                   headers))))
              ((= eth-id ethereum-lisp.eth-wire:+eth-message-get-block-bodies+)
               (multiple-value-bind (request-id hashes)
                   (ethereum-lisp.eth-wire:decode-eth-get-block-bodies payload)
                 (eth-peer-send
                  peer ethereum-lisp.eth-wire:+eth-message-block-bodies+
                  (ethereum-lisp.eth-wire:encode-eth-block-bodies
                   request-id
                   (loop for hash in hashes
                         for block = (gethash hash by-hash)
                         while block
                         collect (ethereum-lisp.eth-wire:block-eth-body
                                  block)))))))))
      (rlpx-disconnect () :disconnected)
      (serious-condition (condition) condition))))

(defun peer-attribution-entry (node)
  "NODE's one live peer entry, or NIL."
  (first (ethereum-lisp.cli::devnet-node-live-sync-entries node)))

(deftest devnet-peer-session-outlives-an-invalid-verdict-from-its-gap-fill
  (:layer :integration :module :p2p :requires-local-sockets t)
  ;; Hoodi, 1a7b9059 log 07:14:25Z-07:14:34Z: the coordinator's hash gap fill
  ;; ran on a peer's session writer, block 3685491 executed INVALID (our own
  ;; gas bug, d7a28c6c), and the verdict ended that peer's session:
  ;; peer.dial.failed "Peer range block 0x154fcffe... was invalid", a -25
  ;; score, and a snap source lost. Here a real dialed session gap-fills a
  ;; chain whose second block is well-formed on the wire and INVALID by
  ;; execution. The verdict must reach the coordinator, and the session, its
  ;; score and its queue must survive it.
  #+sbcl
  (let* ((server-key
           #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (client
           nil)
         (listener (make-instance 'sb-bsd-sockets:inet-socket
                                  :type :stream :protocol :tcp))
         (controller (ethereum-lisp.cli::make-devnet-shutdown-controller))
         (logs '())
         (logs-lock (sb-thread:make-mutex :name "peer-attribution-logs"))
         (server-outcome nil)
         (server-thread nil)
         (dial-thread nil)
         (client-sessions nil)
         (client-error nil))
    (setf (sb-bsd-sockets:sockopt-reuse-address listener) t)
    (sb-bsd-sockets:socket-bind
     listener (sb-bsd-sockets:make-inet-address "127.0.0.1") 0)
    (sb-bsd-sockets:socket-listen listener 1)
    (let* ((port (nth-value 1 (sb-bsd-sockets:socket-name listener)))
           (enode (enode-url (node-id-from-private-key server-key)
                             "127.0.0.1" port)))
      (setf client (ethereum-lisp.cli:make-devnet-node
                    :genesis-json *eth-sync-paris-genesis-json*
                    :port 0 :public-port 0 :max-peers 4
                    :peers (list enode)))
      (let* ((config (ethereum-lisp.cli::devnet-node-config client))
             (genesis (ethereum-lisp.cli::devnet-node-genesis-block client))
             (genesis-hash (hash32-bytes (block-hash genesis)))
             (produced (eth-sync-produce-empty-blocks genesis config 2))
             (valid (first produced))
             (invalid (peer-attribution-invalid-copy (second produced)))
             (target
               (make-block
                :header
                (make-block-header
                 :parent-hash (block-hash invalid)
                 :number 3 :gas-limit 30000000
                 :timestamp (+ 12 (block-header-timestamp
                                   (block-header invalid)))))))
        (unwind-protect
             (progn
               (setf server-thread
                     (sb-thread:make-thread
                      (lambda ()
                        (handler-case
                            (let* ((socket (sb-bsd-sockets:socket-accept
                                            listener))
                                   (peer
                                     (eth-peer-connect
                                      (rlpx-accept-stream
                                       (p2p-binary-socket-stream socket)
                                       server-key)
                                      (make-devp2p-hello
                                       :client-id "attribution-server"
                                       :capabilities
                                       (list (make-devp2p-capability "eth" 68))
                                       :node-id (secp256k1-private-key-public-key
                                                 server-key))
                                      (eth-build-status config genesis-hash
                                                        2 0 genesis-hash 0))))
                              (setf server-outcome
                                    (peer-attribution-serve
                                     peer (list valid invalid))))
                          (serious-condition (condition)
                            (setf server-outcome condition))))
                      :name "peer-attribution-server"))
               (devnet-peer-sync-call-with-function-overrides
                (list
                 (cons 'ethereum-lisp.cli::devnet-peer-manager-log
                       (lambda (seen-node name &rest fields)
                         (declare (ignore seen-node))
                         (sb-thread:with-mutex (logs-lock)
                           (push (cons name
                                       (mapcar #'princ-to-string fields))
                                 logs))))
                 (cons 'ethereum-lisp.cli::devnet-node-sync-targets
                       (lambda (seen-node)
                         (declare (ignore seen-node))
                         (list target)))
                 (cons 'ethereum-lisp.cli::devnet-node-forkchoice-sync-targets
                       (lambda (seen-node)
                         (declare (ignore seen-node))
                         nil)))
                (lambda ()
                  (multiple-value-setq (dial-thread client-sessions)
                    (ethereum-lisp.cli:devnet-start-dial-scheduler-thread
                     client controller
                     (lambda (condition) (setf client-error condition))))
                  (wait-for-test-condition
                   "dialed session admitted" 15d0
                   (lambda () (peer-attribution-entry client)))
                  (let* ((entry (peer-attribution-entry client))
                         (id-hex (ethereum-lisp.cli::devnet-peer-entry-id-hex
                                  entry))
                         (queue (ethereum-lisp.cli::devnet-peer-entry-request-queue
                                 entry))
                         (peer (ethereum-lisp.cli::devnet-peer-entry-peer entry))
                         (table (ethereum-lisp.cli:devnet-node-peer-table client))
                         (outcome
                           (handler-case
                               (list :returned
                                     (ethereum-lisp.cli::devnet-node-fill-sync-gaps-with-live-peer
                                      client))
                             (serious-condition (condition)
                               (list :signalled condition)))))
                    ;; The verdict reaches the coordinator as the typed phase
                    ;; outcome it already contains (peer.sync.invalid_ancestor).
                    (is (eq :signalled (first outcome)))
                    (is (typep (second outcome)
                               'ethereum-lisp.cli::devnet-peer-sync-invalid))
                    (is (search "was invalid"
                                (princ-to-string (second outcome))))
                    ;; The block before the bad one executed and was kept.
                    (is (chain-store-state-available-p
                         (ethereum-lisp.cli::devnet-node-store client)
                         (block-hash valid)))
                    ;; Give a torn-down session time to show it.
                    (sleep 0.5)
                    (is (eq entry (peer-attribution-entry client)))
                    (is (not (ethereum-lisp.cli::devnet-peer-request-queue-closed-p
                              queue)))
                    (is (= 0 (ethereum-lisp.cli::devnet-peer-score table id-hex)))
                    (is (null (find "peer.dial.failed" logs
                                    :key #'first :test #'string=)))
                    ;; The same session still carries requests.
                    (let ((headers
                            (handler-case
                                (ethereum-lisp.cli::devnet-peer-request-queue-submit
                                 queue
                                 (lambda ()
                                   (ethereum-lisp.eth-sync:eth-peer-get-block-headers
                                    peer :origin-number 1 :amount 1)))
                              (serious-condition (condition) condition))))
                      (is (listp headers))
                      (is (and (listp headers)
                               (hash32= (block-hash valid)
                                        (block-header-hash (first headers))))))
                    ;; Positive control: a peer protocol violation raised in a
                    ;; job on the same queue still ends the session and is
                    ;; scored, so the assertions above can fail.
                    (handler-case
                        (ethereum-lisp.cli::devnet-peer-request-queue-submit
                         queue
                         (lambda ()
                           (ethereum-lisp.eth-sync::eth-peer-protocol-fail
                            "injected peer protocol violation")))
                      (serious-condition () nil))
                    (wait-for-test-condition
                     "session teardown after a protocol violation" 5d0
                     (lambda () (null (peer-attribution-entry client))))
                    (is (ethereum-lisp.cli::devnet-peer-request-queue-closed-p
                         queue))
                    (is (= -25
                           (ethereum-lisp.cli::devnet-peer-score table id-hex)))
                    (is (find "peer.dial.failed" logs
                              :key #'first :test #'string=))))))
          (ethereum-lisp.cli:devnet-shutdown-request controller)
          (when dial-thread
            (sb-thread:join-thread dial-thread :timeout 15 :default :timeout))
          (when client-sessions
            (ethereum-lisp.cli:devnet-join-peer-sessions client-sessions
                                                         :timeout 10))
          (ignore-errors (sb-bsd-sockets:socket-close listener))
          (when server-thread
            (sb-thread:join-thread server-thread :timeout 10 :default :timeout))))
      (is (null client-error))
      ;; The server answered until the positive control's Disconnect.
      (is (not (null server-outcome)))))
  #-sbcl
  (is t))

(defun peer-attribution-pool-case (mode)
  "Drive one pooled StorageRanges dependency through the shipped import
callback and return (VALUES LOGS ACCOUNT-SCORE CONDITION).

MODE :EMPTY has no live SNAP peer when the dependency is scheduled. MODE
:LAST-FAILED has one dependency peer, which fails the request and then leaves
the pool."
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (database (make-memory-key-value-database))
         (pivot-header
           (block-header (ethereum-lisp.cli::devnet-node-genesis-block node)))
         (target-hash
           (make-hash32 (make-byte-vector 32 :initial-element 95)))
         (account-entry
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "account-page-source"))
         (dependency-entry
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "failing-dependency-source"))
         (phase :sources)
         (account-source (devnet-snap-test-source))
         (dependency-source
           (devnet-snap-test-source
            :storage-ranges
            (lambda (request)
              (declare (ignore request))
              (setf phase :gone)
              (error "injected malformed StorageRanges response"))))
         (seen-condition nil)
         (logs '()))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (seen-node &key snap-only-p)
              (declare (ignore seen-node snap-only-p))
              (ecase phase
                (:sources (list account-entry))
                (:dependency (list dependency-entry))
                (:gone '()))))
      (cons 'ethereum-lisp.cli::devnet-peer-queued-snap-source
            (lambda (seen-entry)
              (cond
                ((eq account-entry seen-entry) account-source)
                ((eq dependency-entry seen-entry) dependency-source)
                (t (error "unexpected SNAP entry")))))
      (cons 'ethereum-lisp.snap-sync:snap-sync-import-state-multi
            (lambda (seen-database sources &rest arguments)
              (declare (ignore seen-database))
              (let ((callback (getf arguments :on-source-error)))
                (setf phase (ecase mode
                              (:empty :gone)
                              (:last-failed :dependency)))
                (handler-case
                    (funcall
                     (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
                      (first sources))
                     :request)
                  (serious-condition (condition)
                    (setf seen-condition condition)
                    ;; What the multi-source importer does with a dependency
                    ;; failure: it reaches the account page's source.
                    (funcall callback (first sources) condition))))
              :callback-driven))
      (cons 'ethereum-lisp.cli::devnet-peer-manager-log
            (lambda (seen-node name &rest fields)
              (declare (ignore seen-node))
              (push (cons name (mapcar #'princ-to-string fields)) logs))))
     (lambda ()
       (ethereum-lisp.cli::devnet-node-snap-import-with-failover
        node database pivot-header target-hash)))
    (values logs
            (ethereum-lisp.cli::devnet-peer-score
             (ethereum-lisp.cli:devnet-node-peer-table node)
             "account-page-source")
            seen-condition)))

(deftest devnet-snap-source-pool-exhaustion-scores-no-single-peer
  (:layer :unit :module :p2p)
  ;; "no live SNAP peer can serve" is a fact about the pool. Before the fix it
  ;; was a SIMPLE-ERROR, so the import callback charged the account page's
  ;; peer -50 (peer.snap.import_failed) for a dependency no peer was asked.
  ;; The same happened when the last dependency peer failed and left: the
  ;; account page's peer was charged for another transport's response, which
  ;; the pool had already cooled down. geth v1.17.6 eth/protocols/snap/sync.go
  ;; simply waits for an idle peer; nothing is charged for an empty pool.
  (dolist (mode '(:empty :last-failed))
    (multiple-value-bind (logs account-score condition)
        (peer-attribution-pool-case mode)
      (is (= 0 account-score))
      (is (= 0 (count "peer.snap.import_failed" logs
                      :key #'first :test #'string=)))
      (is (= 1 (count "peer.snap.dependencies_exhausted" logs
                      :key #'first :test #'string=)))
      (is (search "no live SNAP peer can serve storage ranges"
                  (princ-to-string condition)))
      (when (eq mode :last-failed)
        ;; The failing transport was charged where it failed.
        (is (= 1 (count "peer.snap.dependency_failed" logs
                        :key #'first :test #'string=)))
        (is (search "injected malformed StorageRanges response"
                    (princ-to-string condition))))
      (is (typep condition 'ethereum-lisp.cli::devnet-snap-source-pool-exhausted))))
  ;; Positive control: an ordinary error from the account page's own source
  ;; is still that peer's import failure.
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (entry (ethereum-lisp.cli::make-devnet-peer-entry
                 :id-hex "account-page-source"))
         (logs '()))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (seen-node &key snap-only-p)
              (declare (ignore seen-node snap-only-p))
              (list entry)))
      (cons 'ethereum-lisp.cli::devnet-peer-queued-snap-source
            (lambda (seen-entry)
              (declare (ignore seen-entry))
              (devnet-snap-test-source)))
      (cons 'ethereum-lisp.snap-sync:snap-sync-import-state-multi
            (lambda (seen-database sources &rest arguments)
              (declare (ignore seen-database))
              (funcall (getf arguments :on-source-error)
                       (first sources)
                       (make-condition 'simple-error
                                       :format-control "injected page error"
                                       :format-arguments nil))
              :callback-driven))
      (cons 'ethereum-lisp.cli::devnet-peer-manager-log
            (lambda (seen-node name &rest fields)
              (declare (ignore seen-node fields))
              (push (list name) logs))))
     (lambda ()
       (ethereum-lisp.cli::devnet-node-snap-import-with-failover
        node (make-memory-key-value-database)
        (block-header (ethereum-lisp.cli::devnet-node-genesis-block node))
        (make-hash32 (make-byte-vector 32 :initial-element 96)))))
    (is (= 1 (count "peer.snap.import_failed" logs
                    :key #'first :test #'string=)))
    (is (= -50 (ethereum-lisp.cli::devnet-peer-score
                (ethereum-lisp.cli:devnet-node-peer-table node)
                "account-page-source")))))

(deftest devnet-sync-coordinator-contains-snap-workers-stopped-without-evidence
  (:layer :unit :module :p2p)
  ;; sec5-sync-outcomes-nonfatal.txt O1: "Snap workers stopped without
  ;; source-failure evidence" was a plain ERROR, so if the range workers ever
  ;; all left without a reported failure the coordinator's outer boundary
  ;; would stop the node. It is a typed outcome now, contained like
  ;; source exhaustion and logged as its own event.
  (let ((node
          (ethereum-lisp.cli:make-devnet-node
           :genesis-json *eth-sync-paris-genesis-json*
           :port 0 :public-port 0))
        (logs '())
        (outcome nil))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::devnet-node-multi-sync-pass
            (lambda (seen-node)
              (declare (ignore seen-node))
              (ethereum-lisp.snap-sync::snap-sync-signal-sources-exhausted
               :account-ranges '())))
      (cons 'ethereum-lisp.cli::devnet-peer-manager-log
            (lambda (seen-node name &rest fields)
              (declare (ignore seen-node))
              (push (cons name (mapcar #'princ-to-string fields)) logs))))
     (lambda ()
       (setf outcome
             (handler-case
                 (list :returned
                       (ethereum-lisp.cli::devnet-node-sync-coordinator-pass
                        node))
               (serious-condition (condition)
                 (list :escaped condition))))))
    (is (equal '(:returned nil) outcome))
    (is (= 1 (count "peer.snap.workers_stopped" logs
                    :key #'first :test #'string=)))
    (is (= 0 (count "peer.snap.sources_retry" logs
                    :key #'first :test #'string=)))
    (let ((event (find "peer.snap.workers_stopped" logs
                       :key #'first :test #'string=)))
      (is (equal "ACCOUNT-RANGES"
                 (second (member "phase" (rest event) :test #'equal))))))
  ;; A failure list still signals ordinary source exhaustion.
  (let ((condition
          (handler-case
              (ethereum-lisp.snap-sync::snap-sync-signal-sources-exhausted
               :healing (list (make-condition 'simple-error
                                              :format-control "x"
                                              :format-arguments nil)))
            (serious-condition (condition) condition))))
    (is (typep condition 'ethereum-lisp.snap-sync:snap-sync-sources-exhausted))
    (is (not (typep condition
                    'ethereum-lisp.snap-sync:snap-sync-workers-stopped))))
  (is (typep (handler-case
                 (ethereum-lisp.snap-sync::snap-sync-signal-sources-exhausted
                  :account-ranges '())
               (serious-condition (condition) condition))
             'ethereum-lisp.snap-sync:snap-sync-workers-stopped)))

(defun peer-attribution-session-score (condition)
  "End one admitted session with CONDITION and return the peer's score."
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (shutdown (ethereum-lisp.cli:make-devnet-shutdown-controller))
         (peer
           (ethereum-lisp.eth-sync::%make-eth-peer
            :connection :established-connection :eth-version 69))
         (entry
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "session-end-peer" :peer peer)))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::devnet-peer-session-readable-function
            (lambda (seen-peer)
              (declare (ignore seen-peer))
              (lambda (timeout) (declare (ignore timeout)) nil)))
      (cons 'ethereum-lisp.eth-sync:eth-peer-run-session
            (lambda (seen-peer &rest arguments)
              (declare (ignore seen-peer arguments))
              (error condition)))
      (cons 'ethereum-lisp.eth-sync:eth-sync-send-goodbye
            (lambda (connection reason &key compressed)
              (declare (ignore connection reason compressed))
              t)))
     (lambda ()
       (signals error
         (ethereum-lisp.cli::devnet-peer-run-session
          node nil shutdown
          (lambda (socket)
            (declare (ignore socket))
            (values peer entry nil))))))
    (ethereum-lisp.cli::devnet-peer-score
     (ethereum-lisp.cli:devnet-node-peer-table node) "session-end-peer")))

(deftest devnet-peer-session-end-charges-only-what-the-peer-sent
  (:layer :unit :module :p2p)
  ;; Every serious condition that ended a session used to cost the peer 25,
  ;; and four ban it for the life of the process. On Hoodi (1a7b9059, 33
  ;; minutes) twelve peer ids were refused as USELESS-PEER, nine of them
  ;; SNAP-capable (the SNAP-quality refusal only ever applies to ETH-only
  ;; peers), after sessions that ended in broken pipes, remote Disconnects
  ;; (reasons 2, 3 and 4), our own INVALID verdict and our own eth/72 GetCells
  ;; decoder. A peer leaving is not a peer fault; geth v1.17.6 keeps no score.
  (let ((broken-pipe
          (make-condition
           'sb-int:simple-stream-error
           :stream *standard-output*
           :format-control "Couldn't write to ~A: Broken pipe"
           :format-arguments (list "socket"))))
    (is (= 0 (peer-attribution-session-score
              (make-condition 'rlpx-disconnect :reason 2))))
    (is (= 0 (peer-attribution-session-score
              (make-condition 'rlpx-disconnect :reason 4))))
    (is (= 0 (peer-attribution-session-score broken-pipe)))
    (is (= 0 (peer-attribution-session-score
              (make-condition
               'ethereum-lisp.eth-sync:eth-sync-peer-transport-error
               :operation "backfill GetBlockHeaders" :cause broken-pipe))))
    ;; Positive controls: what the peer sent and we could not accept is still
    ;; charged, whether typed as a protocol violation or not.
    (is (= -25 (peer-attribution-session-score
                (make-condition
                 'ethereum-lisp.eth-sync:eth-peer-protocol-error
                 :format-control "injected protocol violation"
                 :format-arguments nil))))
    (is (= -25 (peer-attribution-session-score
                (make-condition
                 'simple-error
                 :format-control "eth/72 GetCells must contain exactly 3 items"
                 :format-arguments nil))))
    (is (= -25 (peer-attribution-session-score
                (make-condition
                 'ethereum-lisp.eth-sync:eth-sync-peer-transport-error
                 :operation "backfill GetBlockHeaders"
                 :cause (make-condition
                         'ethereum-lisp.eth-sync:eth-peer-protocol-error
                         :format-control "injected protocol violation"
                         :format-arguments nil)))))))

;;;; A real dialed session that the node gap-fills over: the fixture of the
;;;; tests below (docs/evidence/sec5-robustness-followups.txt).

(defvar *peer-attribution-number-request-hook* nil
  "NIL, or a function the serving side calls with the origin of each
number-origin GetBlockHeaders before answering it (it runs on the server's
thread, so a test sets it globally).")

(defun peer-attribution-serve-by-hash (peer blocks)
  "Answer GetBlockHeaders and GetBlockBodies from BLOCKS until the connection
ends, and return how the loop ended: (:DISCONNECTED reason) for a devp2p
Disconnect, else the condition. A hash-origin request walks parent hashes
(every one the node sends is a reverse backfill walk), so BLOCKS may hold two
branches at the same heights; a number-origin request answers from the first
block listed at each height."
  (let ((by-hash (make-hash-table :test #'equalp))
        (by-number (make-hash-table)))
    (dolist (block blocks)
      (setf (gethash (hash32-bytes (block-hash block)) by-hash) block)
      (let ((number (block-header-number (block-header block))))
        (unless (gethash number by-number)
          (setf (gethash number by-number) block))))
    (handler-case
        (loop
          (multiple-value-bind (eth-id payload) (eth-peer-read peer)
            (cond
              ((= eth-id ethereum-lisp.eth-wire:+eth-message-get-block-headers+)
               (let* ((request
                        (ethereum-lisp.eth-wire:decode-eth-get-block-headers
                         payload))
                      (amount
                        (ethereum-lisp.eth-wire:eth-get-block-headers-amount
                         request))
                      (origin-hash
                        (ethereum-lisp.eth-wire:eth-get-block-headers-origin-hash
                         request))
                      (headers
                        (if origin-hash
                            (loop repeat amount
                                  for block = (gethash origin-hash by-hash)
                                    then (gethash
                                          (hash32-bytes
                                           (block-header-parent-hash
                                            (block-header block)))
                                          by-hash)
                                  while block
                                  collect (block-header block))
                            (let ((origin
                                    (ethereum-lisp.eth-wire:eth-get-block-headers-origin-number
                                     request)))
                              (when *peer-attribution-number-request-hook*
                                (funcall *peer-attribution-number-request-hook*
                                         origin))
                              (loop for number from origin
                                    repeat amount
                                    for block = (gethash number by-number)
                                    while block
                                    collect (block-header block))))))
                 (eth-peer-send
                  peer ethereum-lisp.eth-wire:+eth-message-block-headers+
                  (ethereum-lisp.eth-wire:encode-eth-block-headers
                   (ethereum-lisp.eth-wire:eth-get-block-headers-request-id
                    request)
                   headers))))
              ((= eth-id ethereum-lisp.eth-wire:+eth-message-get-block-bodies+)
               (multiple-value-bind (request-id hashes)
                   (ethereum-lisp.eth-wire:decode-eth-get-block-bodies payload)
                 (eth-peer-send
                  peer ethereum-lisp.eth-wire:+eth-message-block-bodies+
                  (ethereum-lisp.eth-wire:encode-eth-block-bodies
                   request-id
                   (loop for hash in hashes
                         for block = (gethash hash by-hash)
                         while block
                         collect (ethereum-lisp.eth-wire:block-eth-body
                                  block)))))))))
      (rlpx-disconnect (condition)
        (list :disconnected (rlpx-disconnect-reason condition)))
      (serious-condition (condition) condition))))

(defun call-with-peer-attribution-session (build thunk)
  "Run THUNK against a live dialed session and return how the serving side's
loop ended (see PEER-ATTRIBUTION-SERVE-BY-HASH).

A fresh devnet node dials a loopback eth/68 peer. BUILD is called with the
node's genesis block and chain config and returns the blocks the peer serves.
Once the session is admitted, THUNK is called with the node, its peer entry
and a function of no arguments that returns the node's log events so far,
oldest first, as (NAME . FIELDS) with every field printed. The dial scheduler
and the session are shut down afterwards, and a session condition that
reached the scheduler's error callback fails the test."
  #+sbcl
  (let* ((server-key
           #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (listener (make-instance 'sb-bsd-sockets:inet-socket
                                  :type :stream :protocol :tcp))
         (controller (ethereum-lisp.cli::make-devnet-shutdown-controller))
         (logs '())
         (logs-lock (sb-thread:make-mutex :name "peer-attribution-logs"))
         (server-outcome nil)
         (server-thread nil)
         (dial-thread nil)
         (client-sessions nil)
         (client-error nil))
    (setf (sb-bsd-sockets:sockopt-reuse-address listener) t)
    (sb-bsd-sockets:socket-bind
     listener (sb-bsd-sockets:make-inet-address "127.0.0.1") 0)
    (sb-bsd-sockets:socket-listen listener 1)
    (let* ((port (nth-value 1 (sb-bsd-sockets:socket-name listener)))
           (client (ethereum-lisp.cli:make-devnet-node
                    :genesis-json *eth-sync-paris-genesis-json*
                    :port 0 :public-port 0 :max-peers 4
                    :peers (list (enode-url
                                  (node-id-from-private-key server-key)
                                  "127.0.0.1" port))))
           (config (ethereum-lisp.cli::devnet-node-config client))
           (genesis (ethereum-lisp.cli::devnet-node-genesis-block client))
           (genesis-hash (hash32-bytes (block-hash genesis)))
           (served (funcall build genesis config)))
      (unwind-protect
           (progn
             (setf server-thread
                   (sb-thread:make-thread
                    (lambda ()
                      (handler-case
                          (let* ((socket (sb-bsd-sockets:socket-accept
                                          listener))
                                 (peer
                                   (eth-peer-connect
                                    (rlpx-accept-stream
                                     (p2p-binary-socket-stream socket)
                                     server-key)
                                    (make-devp2p-hello
                                     :client-id "attribution-server"
                                     :capabilities
                                     (list (make-devp2p-capability "eth" 68))
                                     :node-id (secp256k1-private-key-public-key
                                               server-key))
                                    (eth-build-status config genesis-hash
                                                      2 0 genesis-hash 0))))
                            (setf server-outcome
                                  (peer-attribution-serve-by-hash
                                   peer served)))
                        (serious-condition (condition)
                          (setf server-outcome condition))))
                    :name "peer-attribution-server"))
             (devnet-peer-sync-call-with-function-overrides
              (list
               (cons 'ethereum-lisp.cli::devnet-peer-manager-log
                     (lambda (seen-node name &rest fields)
                       (declare (ignore seen-node))
                       (sb-thread:with-mutex (logs-lock)
                         (push (cons name
                                     (mapcar #'princ-to-string fields))
                               logs)))))
              (lambda ()
                (multiple-value-setq (dial-thread client-sessions)
                  (ethereum-lisp.cli:devnet-start-dial-scheduler-thread
                   client controller
                   (lambda (condition) (setf client-error condition))))
                (wait-for-test-condition
                 "dialed session admitted" 15d0
                 (lambda () (peer-attribution-entry client)))
                (funcall thunk client (peer-attribution-entry client)
                         (lambda ()
                           (sb-thread:with-mutex (logs-lock)
                             (reverse logs)))))))
        (ethereum-lisp.cli:devnet-shutdown-request controller)
        (when dial-thread
          (sb-thread:join-thread dial-thread :timeout 15 :default :timeout))
        (when client-sessions
          (ethereum-lisp.cli:devnet-join-peer-sessions client-sessions
                                                       :timeout 10))
        (ignore-errors (sb-bsd-sockets:socket-close listener))
        (when server-thread
          (sb-thread:join-thread server-thread :timeout 10
                                               :default :timeout))))
    (is (null client-error))
    server-outcome)
  #-sbcl
  (declare (ignore build thunk)))

(defun peer-attribution-fill-gap (client target)
  "Run the coordinator's hash gap fill toward TARGET on CLIENT's live session
and return (:RETURNED value) or (:SIGNALLED condition)."
  (devnet-peer-sync-call-with-function-overrides
   (list
    (cons 'ethereum-lisp.cli::devnet-node-sync-targets
          (lambda (seen-node)
            (declare (ignore seen-node))
            (list target)))
    (cons 'ethereum-lisp.cli::devnet-node-forkchoice-sync-targets
          (lambda (seen-node)
            (declare (ignore seen-node))
            nil)))
   (lambda ()
     (handler-case
         (list :returned
               (ethereum-lisp.cli::devnet-node-fill-sync-gaps-with-live-peer
                client))
       (serious-condition (condition)
         (list :signalled condition))))))

(defun peer-attribution-session-intact-p (client entry)
  "Whether ENTRY is still CLIENT's live session, with an open queue and a zero
score, and that queue still carries a GetBlockHeaders exchange."
  (let ((queue (ethereum-lisp.cli::devnet-peer-entry-request-queue entry))
        (peer (ethereum-lisp.cli::devnet-peer-entry-peer entry)))
    (and (eq entry (peer-attribution-entry client))
         (not (ethereum-lisp.cli::devnet-peer-request-queue-closed-p queue))
         (= 0 (ethereum-lisp.cli::devnet-peer-score
               (ethereum-lisp.cli:devnet-node-peer-table client)
               (ethereum-lisp.cli::devnet-peer-entry-id-hex entry)))
         (consp
          (handler-case
              (ethereum-lisp.cli::devnet-peer-request-queue-submit
               queue
               (lambda ()
                 (ethereum-lisp.eth-sync:eth-peer-get-block-headers
                  peer :origin-number 1 :amount 1)))
            (serious-condition () nil))))))

(defun peer-attribution-end-with-protocol-violation (client entry)
  "Positive control: a peer protocol violation raised in a job on ENTRY's queue
ends the session and costs 25. Returns true when both hold."
  (let ((queue (ethereum-lisp.cli::devnet-peer-entry-request-queue entry)))
    (handler-case
        (ethereum-lisp.cli::devnet-peer-request-queue-submit
         queue
         (lambda ()
           (ethereum-lisp.eth-sync::eth-peer-protocol-fail
            "injected peer protocol violation")))
      (serious-condition () nil))
    (wait-for-test-condition
     "session teardown after a protocol violation" 5d0
     (lambda () (null (peer-attribution-entry client))))
    (and (ethereum-lisp.cli::devnet-peer-request-queue-closed-p queue)
         (= -25 (ethereum-lisp.cli::devnet-peer-score
                 (ethereum-lisp.cli:devnet-node-peer-table client)
                 (ethereum-lisp.cli::devnet-peer-entry-id-hex entry))))))

(defun peer-attribution-execution-type-error (hash)
  "An override of EXECUTE-AND-COMMIT-ENGINE-PAYLOAD that raises the host
TYPE-ERROR Hoodi 3685491 raised before d7a28c6c when it executes block HASH."
  (let ((original
          (fdefinition
           'ethereum-lisp.execution-service:execute-and-commit-engine-payload)))
    (cons 'ethereum-lisp.execution-service:execute-and-commit-engine-payload
          (lambda (store block config &rest arguments)
            (if (hash32= hash (block-hash block))
                (error 'type-error :datum (expt 2 256)
                                   :expected-type '(mod 4611686018427387901))
                (apply original store block config arguments))))))

(deftest devnet-peer-session-outlives-an-internal-execution-error-from-its-gap-fill
  (:layer :integration :module :p2p :requires-local-sockets t)
  ;; sec5-evm-edge-audit.txt, Not verified: a block that failed INTERNALLY
  ;; in a gap fill on a peer's session thread ended that session
  ;; (peer.dial.failed) and cost the peer 25: our defect charged to the peer
  ;; that delivered the block. The failure must reach the coordinator, which
  ;; contains it and retries later, while the session, its queue and its
  ;; score survive. RED at c677bdf0: the session was gone.
  #+sbcl
  (let ((blocks nil))
    (call-with-peer-attribution-session
     (lambda (genesis config)
       ;; The peer serves blocks 1 and 2; block 3 is the buffered target.
       (setf blocks (eth-sync-produce-empty-blocks genesis config 3))
       (subseq blocks 0 2))
     (lambda (client entry logs)
       (let ((outcome
               (devnet-peer-sync-call-with-function-overrides
                (list (peer-attribution-execution-type-error
                       (block-hash (second blocks))))
                (lambda ()
                  (peer-attribution-fill-gap client (third blocks))))))
         ;; The coordinator gets the typed internal error, naming block 2.
         (is (eq :signalled (first outcome)))
         (is (typep (second outcome) 'block-execution-internal-error))
         (is (hash32= (block-hash (second blocks))
                      (block-execution-internal-error-block-hash
                       (second outcome))))
         ;; Block 1 executed and was kept.
         (is (chain-store-state-available-p
              (ethereum-lisp.cli::devnet-node-store client)
              (block-hash (first blocks))))
         ;; Give a torn-down session time to show it.
         (sleep 0.5)
         (is (peer-attribution-session-intact-p client entry))
         (is (null (find "peer.dial.failed" (funcall logs)
                         :key #'first :test #'string=)))
         ;; The retry, now that the defect is gone, executes blocks 2 and 3
         ;; over the same session.
         (is (equal '(:returned 2)
                    (peer-attribution-fill-gap client (third blocks))))
         (is (chain-store-state-available-p
              (ethereum-lisp.cli::devnet-node-store client)
              (block-hash (third blocks))))
         (is (peer-attribution-end-with-protocol-violation client entry))))))
  #-sbcl
  (is t))

(deftest devnet-gossiped-block-internal-execution-error-stays-on-the-session
  (:layer :unit :module :p2p)
  ;; The same defect met by a propagated block runs inside the session's
  ;; message handler, where an escaping condition ends the session. The
  ;; backend's block admission contains it and logs it instead.
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0 :public-port 0))
         (store (ethereum-lisp.cli::devnet-node-store node))
         (blocks (eth-sync-produce-empty-blocks
                  (ethereum-lisp.cli::devnet-node-genesis-block node)
                  (ethereum-lisp.cli::devnet-node-config node)
                  2))
         (backend (ethereum-lisp.cli::devnet-peer-serve-backend node))
         (logs '()))
    (devnet-peer-sync-call-with-function-overrides
     (list (peer-attribution-execution-type-error (block-hash (second blocks)))
           (cons 'ethereum-lisp.cli::devnet-peer-manager-log
                 (lambda (seen-node name &rest fields)
                   (declare (ignore seen-node))
                   (push (cons name fields) logs))))
     (lambda ()
       ;; Control: an ordinary propagated block imports.
       (is (eq t (ethereum-lisp.eth-sync::eth-accept-propagated-block
                  backend (first blocks))))
       (is (chain-store-state-available-p store (block-hash (first blocks))))
       (is (eq t (ethereum-lisp.eth-sync::eth-accept-propagated-block
                  backend (second blocks))))
       (is (not (chain-store-state-available-p
                 store (block-hash (second blocks)))))
       (let ((event (find "peer.sync.execution_internal_error" logs
                          :key #'first :test #'string=)))
         (is event)
         (is (equal "gossip" (second (member "source" (rest event)
                                             :test #'equal))))
         (is (eql 2 (second (member "block" (rest event) :test #'equal)))))))
    (is (null (engine-payload-store-invalid-block
               store (block-hash (second blocks)))))))

(deftest devnet-peer-session-end-does-not-charge-our-execution-defect
  (:layer :unit :module :p2p)
  ;; Should an internal execution failure ever end a session, it is ours and
  ;; costs the peer nothing; a peer protocol violation still costs 25.
  (is (= 0 (peer-attribution-session-score
            (make-condition
             'block-execution-internal-error
             :block-number 2
             :block-hash (make-hash32 (make-byte-vector 32 :initial-element 2))
             :cause (make-condition 'type-error :datum -1
                                                :expected-type 'unsigned-byte)))))
  (is (= -25 (peer-attribution-session-score
              (make-condition
               'ethereum-lisp.eth-sync:eth-peer-protocol-error
               :format-control "injected protocol violation"
               :format-arguments nil)))))

;;;; Parity with go-ethereum v1.17.6 where we were more lenient: a peer that
;;;; answers with data contradicting its request is disconnected (geth
;;;; errInvalidBody / errInvalidReceipt, eth/downloader/fetchers_concurrent.go
;;;; validityErrorOfRequest; a snap handler's returned error,
;;;; eth/protocols/snap/handler.go HandleMessage). A well-formed block that
;;;; executes INVALID still disconnects nobody.

(defun peer-attribution-body-mismatch-copy (block)
  "BLOCK with a header that commits to a transactions root its (empty) body
does not have: the wire-level fault geth answers errInvalidBody."
  (let ((header (copy-structure (block-header block)))
        (copy (copy-structure block)))
    (setf (block-header-transactions-root header)
          (make-hash32 (make-byte-vector 32 :initial-element #x5b))
          (block-header copy) header)
    copy))

(defun peer-attribution-child-of (parent)
  "A block the CL could have buffered on PARENT: a gap-fill target."
  (make-block
   :header
   (make-block-header
    :parent-hash (block-hash parent)
    :number (1+ (block-header-number (block-header parent)))
    :gas-limit 30000000
    :timestamp (+ 12 (block-header-timestamp (block-header parent))))))

(deftest devnet-peer-session-ends-on-a-gap-fill-body-that-contradicts-its-header
  (:layer :integration :module :p2p :requires-local-sockets t)
  ;; sec5-peer-attribution.txt D5: a backfilled body whose commitments do not
  ;; match its header was logged as peer.sync.gap_failed and the session
  ;; kept. geth drops the peer (errInvalidBody). Control first, on the same
  ;; session: a well-formed block that executes INVALID keeps it (H2's rule,
  ;; DEVNET-PEER-SESSION-OUTLIVES-AN-INVALID-VERDICT-FROM-ITS-GAP-FILL). RED
  ;; at c677bdf0: the session survived the contradicting body.
  #+sbcl
  (let* ((blocks nil)
         (executes-invalid nil)
         (contradicting nil)
         (server-outcome
           (call-with-peer-attribution-session
            (lambda (genesis config)
              (setf blocks (eth-sync-produce-empty-blocks genesis config 2)
                    executes-invalid (peer-attribution-invalid-copy
                                      (second blocks))
                    contradicting (peer-attribution-body-mismatch-copy
                                   (second blocks)))
              (list (first blocks) executes-invalid contradicting))
            (lambda (client entry logs)
              (let ((queue (ethereum-lisp.cli::devnet-peer-entry-request-queue
                            entry))
                    (table (ethereum-lisp.cli:devnet-node-peer-table client))
                    (id-hex (ethereum-lisp.cli::devnet-peer-entry-id-hex entry)))
                ;; Control: INVALID by execution.
                (let ((outcome (peer-attribution-fill-gap
                                client (peer-attribution-child-of
                                        executes-invalid))))
                  (is (typep (second outcome)
                             'ethereum-lisp.cli::devnet-peer-sync-invalid)))
                (sleep 0.5)
                (is (peer-attribution-session-intact-p client entry))
                ;; A body its header does not commit to.
                (let ((outcome (peer-attribution-fill-gap
                                client (peer-attribution-child-of
                                        contradicting))))
                  ;; The coordinator moved on: no other live peer to ask.
                  (is (typep (second outcome)
                             'ethereum-lisp.eth-sync:eth-sync-multi-peer-error)))
                (wait-for-test-condition
                 "session teardown after a contradicting body" 5d0
                 (lambda () (null (peer-attribution-entry client))))
                (is (ethereum-lisp.cli::devnet-peer-request-queue-closed-p
                     queue))
                (is (= -25 (ethereum-lisp.cli::devnet-peer-score table id-hex)))
                ;; The dial thread logs after the session's own teardown.
                (wait-for-test-condition
                 "peer.dial.failed after the teardown" 5d0
                 (lambda ()
                   (find "peer.dial.failed" (funcall logs)
                         :key #'first :test #'string=)))
                (let ((events (funcall logs)))
                  (is (= 1 (count "peer.sync.gap_invalid_body" events
                                  :key #'first :test #'string=)))
                  (is (find "peer.sync.gap_peer_failed" events
                            :key #'first :test #'string=))))))))
    ;; The peer was told why: a devp2p Disconnect, subprotocol error.
    (is (equal (list :disconnected
                     ethereum-lisp.p2p:+devp2p-disconnect-subprotocol-error+)
               server-outcome)))
  #-sbcl
  (is t))

(deftest devnet-peer-session-ends-on-a-downloaded-body-that-contradicts-its-header
  (:layer :integration :module :p2p :requires-local-sockets t)
  ;; The same fault met by the multi-peer forward downloader: the delivery
  ;; is refused and scored as malformed (-50) as before, and now the session
  ;; ends too, without a second charge. RED at c677bdf0: the session
  ;; survived.
  #+sbcl
  (let* ((contradicting nil)
         (server-outcome
           (call-with-peer-attribution-session
            (lambda (genesis config)
              (setf contradicting
                    (peer-attribution-body-mismatch-copy
                     (first (eth-sync-produce-empty-blocks genesis config 1))))
              (list contradicting))
            (lambda (client entry logs)
              (let ((table (ethereum-lisp.cli:devnet-node-peer-table client))
                    (id-hex (ethereum-lisp.cli::devnet-peer-entry-id-hex entry)))
                (is (typep (handler-case
                               (eth-sync-download-blocks-multi
                                (ethereum-lisp.cli::devnet-node-sync-peer-sources
                                 client)
                                (lambda (block) (declare (ignore block)))
                                :start-number 1 :target-number 1
                                :fetch-receipts-p nil
                                :request-timeout-seconds 10)
                             (serious-condition (condition) condition))
                           'ethereum-lisp.eth-sync:eth-sync-multi-peer-error))
                (wait-for-test-condition
                 "session teardown after a contradicting downloaded body" 5d0
                 (lambda () (null (peer-attribution-entry client))))
                (is (= -50 (ethereum-lisp.cli::devnet-peer-score table id-hex)))
                (is (= 1 (count "peer.session.invalid_delivery" (funcall logs)
                                :key #'first :test #'string=))))))))
    (is (equal (list :disconnected
                     ethereum-lisp.p2p:+devp2p-disconnect-subprotocol-error+)
               server-outcome)))
  #-sbcl
  (is t))

(deftest devnet-snap-source-pool-ends-the-session-of-an-invalid-dependency-response
  (:layer :unit :module :p2p)
  ;; sec5-peer-attribution.txt D5: a pooled dependency whose proof failed
  ;; cooled the peer down for 30 s and kept its session; geth disconnects
  ;; it. Only that failure ends the session: an empty answer (state
  ;; unavailable), a request timeout and a transport failure do not.
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0 :public-port 0))
         (bad (ethereum-lisp.cli::make-devnet-peer-entry :id-hex "bad-peer"))
         (good (ethereum-lisp.cli::make-devnet-peer-entry :id-hex "good-peer"))
         (ended '()))
    (flet ((call-with-first-failing (failure)
             ;; FAILURE is the bad peer's first answer; a retry that returns
             ;; to it (a timeout does not cool a peer down) is answered.
             (setf ended '())
             (let ((pool (ethereum-lisp.cli::make-devnet-snap-source-pool
                          node))
                   (bad-calls 0))
               (devnet-peer-sync-call-with-function-overrides
                (list
                 (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
                       (lambda (seen-node &key snap-only-p)
                         (declare (ignore seen-node snap-only-p))
                         (list bad good)))
                 (cons 'ethereum-lisp.cli::devnet-peer-queued-snap-source
                       (lambda (entry)
                         (devnet-snap-test-source
                          :storage-ranges
                          (lambda (request)
                            (declare (ignore request))
                            (if (and (eq entry bad) (= 1 (incf bad-calls)))
                                (funcall failure)
                                :good-response)))))
                 (cons 'ethereum-lisp.cli::devnet-peer-end-session-for-invalid-delivery
                       (lambda (seen-node entry reason &key charged-p)
                         (declare (ignore seen-node charged-p))
                         (push (cons entry reason) ended)
                         t))
                 (cons 'ethereum-lisp.cli::devnet-peer-manager-log
                       (lambda (&rest arguments)
                         (declare (ignore arguments)))))
                (lambda ()
                  (ethereum-lisp.cli::devnet-snap-source-pool-call
                   pool ethereum-lisp.snap:+snap-message-storage-ranges+
                   #'ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
                   :request "storage ranges"))))))
      ;; The failing peer is tried first and its session ends; the request
      ;; completes on the other peer.
      (is (eq :good-response
              (call-with-first-failing
               (lambda ()
                 (error 'ethereum-lisp.snap-sync::snap-sync-invalid-response
                        :kind "storage-range"
                        :cause (make-condition
                                'simple-error
                                :format-control "range proof does not verify"
                                :format-arguments nil))))))
      (is (= 1 (length ended)))
      (is (eq bad (car (first ended))))
      (is (typep (cdr (first ended))
                 'ethereum-lisp.snap-sync::snap-sync-invalid-response))
      ;; Controls: none of these is a contradicting answer.
      (dolist (failure
               (list
                (lambda ()
                  (ethereum-lisp.snap-sync::snap-sync-state-unavailable
                   "storage-range"))
                (lambda ()
                  (error (make-condition
                          'ethereum-lisp.cli::devnet-snap-request-timeout
                          :request-id 1 :response-id 1 :timeout-seconds 1)))
                (lambda ()
                  (error 'ethereum-lisp.eth-sync:eth-sync-peer-transport-error
                         :operation "GetStorageRanges"
                         :cause (make-condition 'end-of-file
                                                :stream *standard-input*)))))
        (is (eq :good-response (call-with-first-failing failure)))
        (is (null ended))))))

(deftest devnet-peer-invalid-delivery-is-charged-once
  (:layer :unit :module :p2p)
  ;; A session ended for a contradicting answer is charged at its end,
  ;; unless the requester already charged it (the downloader's -50).
  (is (= -25 (peer-attribution-session-score
              (make-condition 'ethereum-lisp.cli::devnet-peer-invalid-delivery
                              :charged-p nil
                              :format-control "x" :format-arguments nil))))
  (is (= 0 (peer-attribution-session-score
            (make-condition 'ethereum-lisp.cli::devnet-peer-invalid-delivery
                            :charged-p t
                            :format-control "x" :format-arguments nil)))))

(deftest devnet-peer-session-outlives-a-download-aborted-with-its-request-in-flight
  (:layer :integration :module :p2p :requires-local-sockets t)
  ;; sec5-peer-attribution.txt D6: when the multi-peer downloader aborted (an
  ;; INVALID verdict included) it closed the stream of every source with a
  ;; request in flight, ending those sessions; geth v1.17.6 cancels the
  ;; requests and keeps the peers. Here the import of block 1 refuses it
  ;; while the same session is still serving the request for block 2. RED
  ;; at c677bdf0: the session was gone.
  #+sbcl
  (let ((serving-2 nil))
    (unwind-protect
         (progn
           (setf *peer-attribution-number-request-hook*
                 (lambda (origin)
                   (when (= origin 2)
                     (setf serving-2 t)
                     ;; Still in flight when the download aborts.
                     (sleep 2))))
           (call-with-peer-attribution-session
            (lambda (genesis config)
              (eth-sync-produce-empty-blocks genesis config 2))
            (lambda (client entry logs)
              (let ((outcome
                      (handler-case
                          (eth-sync-download-blocks-multi
                           (ethereum-lisp.cli::devnet-node-sync-peer-sources
                            client)
                           (lambda (block)
                             (when (= 1 (block-header-number
                                         (block-header block)))
                               (loop repeat 1000 until serving-2
                                     do (sleep 0.005))
                               (error 'ethereum-lisp.cli::devnet-peer-sync-invalid
                                      :message "injected INVALID verdict")))
                           :start-number 1 :target-number 2 :batch-size 1
                           :fetch-receipts-p nil
                           :request-timeout-seconds 10)
                        (serious-condition (condition) condition))))
                (is (typep outcome
                           'ethereum-lisp.cli::devnet-peer-sync-invalid))
                (is serving-2)
                ;; Give a torn-down session time to show it.
                (sleep 0.5)
                (is (peer-attribution-session-intact-p client entry))
                (is (null (find "peer.dial.failed" (funcall logs)
                                :key #'first :test #'string=)))
                (is (peer-attribution-end-with-protocol-violation
                     client entry))))))
      (setf *peer-attribution-number-request-hook* nil)))
  #-sbcl
  (is t))
