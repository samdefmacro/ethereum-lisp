(in-package #:ethereum-lisp.cli)

;;;; Observability: the operator's health checks and the metrics that need more
;;;; than an event count.
;;;;
;;;; Two things live here. The OBSERVABILITY SINK is a telemetry sink layered
;;;; under the counting sink (like the RPC latency sink): it reads the numeric
;;;; fields of events the node already emits -- the Engine request log, the
;;;; store guard's long-hold line, peer session failures, the healer's progress
;;;; -- into histograms and bounded labelled counters. HEALTH turns lock-free
;;;; reads of the node into /health/live and /health/ready verdicts.
;;;;
;;;; NOTHING HERE TAKES THE STORE GUARD. Block import and the SNAP phases hold it
;;;; for seconds to hours, and an endpoint that waits for it reports a healthy
;;;; busy node as dead. Every input is the published sync view, the guard's
;;;; ledger (read racily), the peer table's own mutex, or a sink's own mutex.
;;;;
;;;; EVERY LABEL IS BOUNDED AND PAYLOAD-FREE. Label values come from fixed
;;;; vocabularies (Engine method names, fixed thread names, condition class
;;;; names, refusal verdicts); anything else is folded into "other", and each
;;;; labelled table is additionally capped, so a client choosing request method
;;;; names cannot grow the scrape or the heap.

(defparameter *devnet-observability-latency-buckets-ms*
  '(5 10 25 50 100 250 500 1000 2500 5000 8000 10000 30000)
  "Upper bounds, in milliseconds, of every latency histogram. 8000 is the
execution-apis Engine API timeout for newPayload and forkchoiceUpdated, and
30000 the HTTP request deadline (*ENGINE-RPC-HTTP-REQUEST-TIMEOUT-SECONDS*),
so both limits are bucket edges.")

(defparameter *devnet-observability-reorg-depth-buckets*
  '(1 2 3 4 8 16 32 64 128)
  "Upper bounds of the reorg depth histogram, in displaced blocks.")

(defparameter *devnet-observability-max-label-values* 64
  "How many distinct values one labelled counter keeps before it folds new
ones into \"other\". A backstop behind the fixed vocabularies below.")

(defparameter *devnet-observability-heal-gauges*
  '(("pivot" . "ethereum_lisp_snap_heal_pivot_number")
    ("processedNodes" . "ethereum_lisp_snap_heal_processed_nodes")
    ("fetchedNodes" . "ethereum_lisp_snap_heal_fetched_nodes")
    ("frontierWorks" . "ethereum_lisp_snap_heal_frontier_works")
    ("knownIncompleteNodes"
     . "ethereum_lisp_snap_heal_known_incomplete_nodes"))
  "peer.snap.heal_progress fields republished as gauges, from its latest event.")

(defparameter *devnet-store-guard-fixed-holder-labels*
  '("sync-gap-fill" "forward-batch-import"
    "ethereum-lisp-devnet-sync-coordinator"
    "ethereum-lisp-devnet-peer-session"
    "ethereum-lisp-devnet-dial-session"
    "ethereum-lisp-devnet-dial-scheduler"
    "ethereum-lisp-devnet-payload-improvement"
    "ethereum-lisp-devnet-txpool-maintenance"
    "ethereum-lisp-devnet-txpool-rejournal"
    "ethereum-lisp-devnet-dev-period"
    "ethereum-lisp-devnet-discovery"
    "ethereum-lisp-devnet-engine-rpc"
    "ethereum-lisp-devnet-ws-session"
    "ethereum-lisp-rpc-http-connection")
  "Store-guard holder labels reported by name: the activity labels bound
around long imports and the fixed names of the threads that take the guard.
Engine method names are also reported by name; public RPC methods fold into
\"rpc\" and anything else into \"other\". An exact list rather than a prefix,
because the public RPC names a hold after the request's method string.")

(defun %devnet-observability-prefix-p (prefix string)
  (and (stringp string)
       (>= (length string) (length prefix))
       (string= prefix string :end2 (length prefix))))

(defun devnet-observability-integer (value)
  "VALUE as an integer: itself, a decimal string, or NIL for anything else.
Some events carry numbers, others (DEVNET-PEER-MANAGER-LOG) their printed form."
  (cond ((integerp value) value)
        ((and (stringp value) (plusp (length value)) (< (length value) 40)
              (every (lambda (char) (or (digit-char-p char) (char= char #\-)))
                     value))
         (ignore-errors (parse-integer value)))
        (t nil)))

(defun devnet-store-guard-holder-class (label)
  "The metrics label for store-guard holder LABEL; see
*DEVNET-STORE-GUARD-FIXED-HOLDER-LABELS*."
  (cond ((not (stringp label)) "other")
        ((member label *devnet-store-guard-fixed-holder-labels*
                 :test #'string=)
         label)
        ((and (%devnet-observability-prefix-p "engine_" label)
              (ethereum-lisp.engine-api:engine-rpc-registered-method-p label))
         label)
        ((engine-rpc-public-method-p label) "rpc")
        (t "other")))

(defun devnet-observability-engine-method (fields)
  "The Engine method a request-log FIELDS names, when it was one answered
Engine call: a single method, known to the Engine API, answered with HTTP 200
and not refused as unknown (-32601, which the public endpoint answers for
Engine names). NIL otherwise."
  (let ((methods (cdr (assoc "rpcMethods" fields :test #'string=)))
        (status (cdr (assoc "status" fields :test #'string=)))
        (errors (cdr (assoc "rpcErrorCode" fields :test #'string=))))
    (and (stringp methods)
         (not (find #\, methods))
         (%devnet-observability-prefix-p "engine_" methods)
         (ethereum-lisp.engine-api:engine-rpc-registered-method-p methods)
         (equal status "200")
         (not (and (stringp errors) (search "-32601" errors)))
         methods)))

(defstruct (devnet-observability-sink
            (:constructor make-devnet-observability-sink (&key delegate)))
  "A telemetry sink that files what the metrics endpoint reports beyond event
counts, then passes every event on to DELEGATE."
  delegate
  #+sbcl (lock (sb-thread:make-mutex :name "devnet observability sink"))
  (engine-methods (make-hash-table :test #'equal))
  (handler-ms
   (let ((table (make-hash-table :test #'equal)))
     (dolist (family *devnet-rpc-latency-families* table)
       (setf (gethash family table)
             (make-telemetry-histogram
              *devnet-observability-latency-buckets-ms*)))))
  (guard-wait-ms
   (make-telemetry-histogram *devnet-observability-latency-buckets-ms*))
  (execute-ms
   (make-telemetry-histogram *devnet-observability-latency-buckets-ms*))
  (persist-ms
   (make-telemetry-histogram *devnet-observability-latency-buckets-ms*))
  (reorg-depth
   (make-telemetry-histogram *devnet-observability-reorg-depth-buckets*))
  (long-hold-ms
   (make-telemetry-histogram *devnet-observability-latency-buckets-ms*))
  (long-holds (make-hash-table :test #'equal))
  (session-failures (make-hash-table :test #'equal))
  (refusals (make-hash-table :test #'equal))
  (request-timeouts 0)
  (heal nil))

(defun devnet-node-metrics-sink-layer (node predicate)
  "The first sink under NODE's counting sink that satisfies PREDICATE, or NIL
when --metrics is off. The layers are counting, observability, latency, then
the node's own sink; each holds the next as its DELEGATE."
  (let ((sink (devnet-node-telemetry-sink node)))
    (when (counting-telemetry-sink-p sink)
      (loop for layer = (counting-telemetry-sink-delegate sink)
              then (cond ((devnet-rpc-latency-sink-p layer)
                          (devnet-rpc-latency-sink-delegate layer))
                         ((devnet-observability-sink-p layer)
                          (devnet-observability-sink-delegate layer))
                         (t nil))
            while layer
            when (funcall predicate layer)
              return layer))))

(defun devnet-node-rpc-latency-sink (node)
  "NODE's latency sink, or NIL when --metrics is off."
  (devnet-node-metrics-sink-layer node #'devnet-rpc-latency-sink-p))

(defun devnet-node-observability-sink (node)
  "NODE's observability sink, or NIL when --metrics is off."
  (devnet-node-metrics-sink-layer node #'devnet-observability-sink-p))

(defun call-with-devnet-observability-lock (sink thunk)
  #+sbcl (sb-thread:with-mutex ((devnet-observability-sink-lock sink))
           (funcall thunk))
  #-sbcl (progn sink (funcall thunk)))

(defun devnet-observability-count (sink table key)
  "Add one to KEY in TABLE, folding a new key into \"other\" once TABLE holds
*DEVNET-OBSERVABILITY-MAX-LABEL-VALUES* keys."
  (call-with-devnet-observability-lock
   sink
   (lambda ()
     (let ((key (if (or (nth-value 1 (gethash key table))
                        (< (hash-table-count table)
                           *devnet-observability-max-label-values*))
                    key
                    "other")))
       (incf (gethash key table 0))))))

(defun devnet-observability-record-request (sink fields)
  (let* ((methods (cdr (assoc "rpcMethods" fields :test #'string=)))
         (family (and (stringp methods) (devnet-rpc-latency-family methods)))
         (engine-method (devnet-observability-engine-method fields)))
    (flet ((field (name)
             (devnet-observability-integer
              (cdr (assoc name fields :test #'string=)))))
      (let ((handler-ms (field "handlerMs")))
        (when (and family handler-ms)
          (telemetry-histogram-observe
           (gethash family (devnet-observability-sink-handler-ms sink))
           handler-ms)))
      (when engine-method
        (devnet-observability-count
         sink (devnet-observability-sink-engine-methods sink) engine-method)
        ;; Zero when it did not wait: the histogram's count is then the number
        ;; of Engine requests, and its low buckets say how many never waited.
        (telemetry-histogram-observe
         (devnet-observability-sink-guard-wait-ms sink)
         (or (field "guardWaitMs") 0)))
      (let ((execute (field "npExecuteMs"))
            (persist (field "npPersistMs"))
            (reorg (field "fcuReorgDepth")))
        (when execute
          (telemetry-histogram-observe
           (devnet-observability-sink-execute-ms sink) execute))
        (when persist
          (telemetry-histogram-observe
           (devnet-observability-sink-persist-ms sink) persist))
        (when (and reorg (plusp reorg))
          (telemetry-histogram-observe
           (devnet-observability-sink-reorg-depth sink) reorg))))))

(defun devnet-observability-record-heal (sink fields)
  (let ((values
          (loop for (field . gauge) in *devnet-observability-heal-gauges*
                for value = (devnet-observability-integer
                             (cdr (assoc field fields :test #'string=)))
                when value collect (cons gauge value)))
        (completed (cdr (assoc "completed" fields :test #'string=))))
    (call-with-devnet-observability-lock
     sink
     (lambda ()
       (setf (devnet-observability-sink-heal sink)
             (append values
                     (list (cons "ethereum_lisp_snap_heal_completed"
                                 (if (member completed '("T" "true")
                                             :test #'equal)
                                     1 0)))))))))

(defmethod telemetry-emit
    ((sink devnet-observability-sink) (event telemetry-event))
  ;; Recording must never cost the caller its event: whatever fails here, the
  ;; delegate below still logs it.
  (ignore-errors
   (let ((name (telemetry-event-name event))
         (fields (telemetry-event-fields event)))
     (flet ((field (key) (cdr (assoc key fields :test #'string=))))
       (cond
         ((equal name "engine.rpc.http.request")
          (devnet-observability-record-request sink fields))
         ((equal name "engine.rpc.http.connection.error")
          (when (equal (field "reason") "request-deadline")
            (call-with-devnet-observability-lock
             sink
             (lambda ()
               (incf (devnet-observability-sink-request-timeouts sink))))))
         ((equal name "node.store_guard.long_hold")
          (devnet-observability-count
           sink (devnet-observability-sink-long-holds sink)
           (devnet-store-guard-holder-class (field "holder")))
          (let ((hold-ms (devnet-observability-integer (field "holdMs"))))
            (when hold-ms
              (telemetry-histogram-observe
               (devnet-observability-sink-long-hold-ms sink) hold-ms))))
         ((equal name "p2p.peer.session_failed")
          (devnet-observability-count
           sink (devnet-observability-sink-session-failures sink)
           (let ((reason (field "reason")))
             (if (stringp reason) reason "unknown"))))
         ((equal name "p2p.peer.refused")
          (devnet-observability-count
           sink (devnet-observability-sink-refusals sink)
           (let ((reason (field "reason")))
             (if (stringp reason) (string-downcase reason) "unknown"))))
         ((equal name "peer.snap.heal_progress")
          (devnet-observability-record-heal sink fields))))))
  (let ((delegate (devnet-observability-sink-delegate sink)))
    (when delegate (telemetry-emit delegate event)))
  event)

(defun devnet-observability-table-samples (sink table label)
  "TABLE's counts as (((LABEL . KEY)) . COUNT) samples, sorted by key."
  (sort (call-with-devnet-observability-lock
         sink
         (lambda ()
           (loop for key being the hash-keys of table using (hash-value count)
                 collect (cons (list (cons label key)) count))))
        #'string< :key (lambda (sample) (cdr (first (car sample))))))

(defun devnet-observability-gauges (sink)
  "SINK's unlabelled values, as (NAME . INTEGER) pairs."
  (call-with-devnet-observability-lock
   sink
   (lambda ()
     (append
      (list (cons "ethereum_lisp_rpc_request_timeouts_total"
                  (devnet-observability-sink-request-timeouts sink))
            (cons "ethereum_lisp_reorgs_total"
                  (getf (telemetry-histogram-snapshot
                         (devnet-observability-sink-reorg-depth sink))
                        :count)))
      (copy-list (devnet-observability-sink-heal sink))))))

(defun devnet-observability-families (sink)
  "SINK's labelled counters and histograms, as metric families for
TELEMETRY-PROMETHEUS-TEXT."
  (flet ((histogram (name help histogram)
           (list :name name :type :histogram :help help
                 :samples (list (cons nil (telemetry-histogram-snapshot
                                           histogram)))))
         (counter (name help table label)
           (list :name name :type :counter :help help
                 :samples (devnet-observability-table-samples
                           sink table label))))
    (list
     (counter "ethereum_lisp_engine_requests_total"
              "Answered Engine API requests by method."
              (devnet-observability-sink-engine-methods sink) "method")
     (list :name "ethereum_lisp_rpc_handler_ms" :type :histogram
           :help "RPC handler time (guard wait included) by method family."
           :samples
           (loop for family in *devnet-rpc-latency-families*
                 collect (cons (list (cons "family" family))
                               (telemetry-histogram-snapshot
                                (gethash family
                                         (devnet-observability-sink-handler-ms
                                          sink))))))
     (histogram "ethereum_lisp_engine_guard_wait_ms"
                "Store-guard wait per answered Engine request (0 when none)."
                (devnet-observability-sink-guard-wait-ms sink))
     (histogram "ethereum_lisp_import_execute_ms"
                "newPayload block execution time."
                (devnet-observability-sink-execute-ms sink))
     (histogram "ethereum_lisp_import_persist_ms"
                "newPayload durable persistence time."
                (devnet-observability-sink-persist-ms sink))
     (histogram "ethereum_lisp_reorg_depth_blocks"
                "Canonical blocks displaced per Engine forkchoice reorg."
                (devnet-observability-sink-reorg-depth sink))
     (counter "ethereum_lisp_store_guard_long_holds_total"
              "Store-guard holds of at least one second, by holder."
              (devnet-observability-sink-long-holds sink) "holder")
     (histogram "ethereum_lisp_store_guard_long_hold_ms"
                "Length of store-guard holds of at least one second."
                (devnet-observability-sink-long-hold-ms sink))
     (counter "ethereum_lisp_peer_session_failures_total"
              "Peer sessions that ended in a condition, by condition class."
              (devnet-observability-sink-session-failures sink) "reason")
     (counter "ethereum_lisp_peer_refusals_total"
              "Handshaken peers refused admission, by verdict."
              (devnet-observability-sink-refusals sink) "reason"))))

;;;; Health.
;;;;
;;;; /health/live answers whether the process should be restarted; it is
;;;; deliberately NOT tied to sync, peers or the store guard, because a node in
;;;; a long SNAP phase or a long import is busy, not dead, and restarting it
;;;; throws the work away. /health/ready answers whether it should be sent
;;;; traffic: peers, sync within a few blocks of the consensus target, no store
;;;; guard hold long enough to miss an Engine deadline, and a consensus client
;;;; that is actually calling.

(defparameter *devnet-health-ready-min-peers* 1
  "Readiness: at least this many connected peers.")

(defparameter *devnet-health-ready-max-lag-blocks* 2
  "Readiness: eth_syncing is false, or the head is at most this many blocks
behind the highest known target. Two matches the Section 10 shadow gate's
largest tolerated head lag.")

(defparameter *devnet-health-ready-max-guard-hold-ms* 8000
  "Readiness: no single store-guard hold older than this. 8 s is the
execution-apis timeout for engine_newPayload and engine_forkchoiceUpdated, so a
hold older than that has already made the consensus client's call time out.")

(defparameter *devnet-health-ready-max-engine-idle-ms* 60000
  "Readiness: the last Engine request arrived at most this long ago. A paired
consensus client calls forkchoiceUpdated every slot (12 s on Ethereum), so five
missed slots means it is not driving this node.")

(defun devnet-health-check (name ok-p value limit)
  (list :name name :ok (and ok-p t) :value value :limit limit))

(defun devnet-health-ready-checks
    (&key shutdown-p peers syncing-p head target guard-hold-ms engine-age-ms)
  "The readiness checks for these lock-free observations, in report order.
SYNCING-P is eth_syncing's verdict; HEAD and TARGET its current and highest
block. GUARD-HOLD-MS is the age of the current store-guard hold (0 when free),
ENGINE-AGE-MS the age of the last Engine request (NIL before the first)."
  (let ((lag (max 0 (- (or target head 0) (or head 0)))))
    (list
     (devnet-health-check "shutdown" (not shutdown-p) (if shutdown-p 1 0) 0)
     (devnet-health-check "peers" (>= (or peers 0) *devnet-health-ready-min-peers*)
                          (or peers 0) *devnet-health-ready-min-peers*)
     (devnet-health-check "sync"
                          (or (not syncing-p)
                              (<= lag *devnet-health-ready-max-lag-blocks*))
                          lag *devnet-health-ready-max-lag-blocks*)
     (devnet-health-check "storeGuard"
                          (<= (or guard-hold-ms 0)
                              *devnet-health-ready-max-guard-hold-ms*)
                          (or guard-hold-ms 0)
                          *devnet-health-ready-max-guard-hold-ms*)
     (devnet-health-check "engine"
                          (and engine-age-ms
                               (<= engine-age-ms
                                   *devnet-health-ready-max-engine-idle-ms*))
                          engine-age-ms
                          *devnet-health-ready-max-engine-idle-ms*))))

(defun devnet-health-live-checks (&key shutdown-p)
  "The liveness checks. Answering at all proves the process runs and schedules
the endpoint's own thread, which never waits for the store guard."
  (list (devnet-health-check "shutdown" (not shutdown-p) (if shutdown-p 1 0) 0)))

(defun devnet-health-json (checks)
  "(VALUES OK-P JSON) for CHECKS. The body names every check, its value and
limit, and lists the failed ones under \"failed\"; it carries only integers
and fixed names."
  (let ((failed (loop for check in checks
                      unless (getf check :ok) collect (getf check :name))))
    (values
     (null failed)
     (with-output-to-string (out)
       (format out "{\"status\":\"~:[fail~;ok~]\",\"failed\":[~{\"~A\"~^,~}],~
\"checks\":[" (null failed) failed)
       (loop for (check . more) on checks
             do (format out "{\"name\":\"~A\",\"ok\":~:[false~;true~],~
\"value\":~:[null~;~:*~D~],\"limit\":~D}~:[~;,~]"
                        (getf check :name) (getf check :ok)
                        (getf check :value) (getf check :limit) more))
       (format out "]}~%")))))

(defun devnet-store-guard-ledger-hold-age-ms (ledger now)
  "How long the current store-guard hold has lasted at internal time NOW, or 0
when the guard is free. A racy read by design; see the ledger."
  (let ((label (and ledger (devnet-store-guard-ledger-holder-label ledger)))
        (started-at (and ledger
                         (devnet-store-guard-ledger-holder-started-at ledger))))
    (if (and label started-at)
        (max 0 (devnet-internal-time-ms (- now started-at)))
        0)))

(defun devnet-store-guard-ledger-engine-age-ms (ledger now)
  "How long ago the last Engine request arrived (guard-free calls included), or
NIL before the first one."
  (let ((at (and ledger (devnet-store-guard-ledger-last-priority-at ledger))))
    (and at (max 0 (devnet-internal-time-ms (- now at))))))

(defun devnet-node-health-observations (node)
  "The lock-free inputs to readiness, as a plist for DEVNET-HEALTH-READY-CHECKS
(without :SHUTDOWN-P). The sync verdict is eth_syncing's, computed from the
view the last guard release published plus its two lock-free reads -- never by
trying the guard, unlike eth_syncing itself."
  (let* ((now (get-internal-real-time))
         (ledger (devnet-node-store-guard-ledger node))
         (view (devnet-node-sync-view node))
         (durable (handler-case (devnet-node-durable-snap-highest-block node)
                    (serious-condition () nil)))
         (answer (devnet-sync-view-answer
                  view
                  (handler-case (devnet-node-forkchoice-targets-pending-p node)
                    (serious-condition () nil))
                  durable))
         (head (or (getf view :current) 0))
         (target (reduce #'max (remove nil (list head (getf view :highest)
                                                 durable)))))
    (list :peers (call-with-devnet-peer-table
                  node
                  (lambda ()
                    (devnet-peer-table-count (devnet-node-peer-table node))))
          :syncing-p (not (eq answer :false))
          :head head
          :target target
          :guard-hold-ms (devnet-store-guard-ledger-hold-age-ms ledger now)
          :engine-age-ms (devnet-store-guard-ledger-engine-age-ms ledger now))))

(defun devnet-node-health (node kind &key shutdown-p)
  "(VALUES OK-P JSON) for NODE's KIND check, :LIVE or :READY."
  (devnet-health-json
   (ecase kind
     (:live (devnet-health-live-checks :shutdown-p shutdown-p))
     (:ready (apply #'devnet-health-ready-checks
                    :shutdown-p shutdown-p
                    (devnet-node-health-observations node))))))
