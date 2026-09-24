(in-package #:ethereum-lisp.cli)

;;;; Observability: the operator's health checks.
;;;;
;;;; HEALTH turns lock-free reads of the node into /health/live and
;;;; /health/ready verdicts, which the metrics endpoint serves.
;;;;
;;;; NOTHING HERE TAKES THE STORE GUARD. Block import and the SNAP phases hold it
;;;; for seconds to hours, and an endpoint that waits for it reports a healthy
;;;; busy node as dead. Every input is the published sync view, the guard's
;;;; ledger (read racily), or the peer table's own mutex.

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
  "How long ago the last Engine request asked for the store guard, or NIL."
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
