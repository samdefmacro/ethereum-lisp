(in-package #:ethereum-lisp.test)

;;;; Health endpoints, histograms and the observability sink.
;;;;
;;;; The exposition format is pinned by one golden document, because a scraper
;;;; rejects a whole scrape over one malformed line. The sink and the readiness
;;;; verdicts are pure and tested as tables. One integration test starts a real
;;;; node and requires /health/live, /health/ready and /metrics to answer while
;;;; another thread holds the store guard -- with a guarded public RPC call in
;;;; the same window as the positive control that the guard really was held.

(deftest telemetry-prometheus-text-renders-histograms-and-labelled-families
  (:layer :unit :module :cli)
  (let ((histogram (ethereum-lisp.telemetry:make-telemetry-histogram '(10 100))))
    ;; A bound is inclusive (`le`), a negative value counts as zero, and a
    ;; value past the last bound lands only in +Inf.
    (dolist (value '(-4 10 11 500))
      (ethereum-lisp.telemetry:telemetry-histogram-observe histogram value))
    (is (equal '(:bounds (10 100) :cumulative (2 3 4) :sum 521 :count 4)
               (ethereum-lisp.telemetry:telemetry-histogram-snapshot histogram)))
    (let ((text (ethereum-lisp.telemetry:telemetry-prometheus-text
                 (list (cons "a.b" 2))
                 :gauges '(("ethereum_lisp_x_age_ms" . 7))
                 :families
                 (list
                  (list :name "ethereum_lisp_engine_requests_total"
                        :type :counter :help "Answered."
                        :samples '(((("method" . "engine_forkchoiceUpdatedV3"))
                                    . 3)))
                  (list :name "ethereum_lisp_t_ms" :type :histogram
                        :help "Time."
                        :samples
                        (list (cons '(("family" . "rpc"))
                                    (ethereum-lisp.telemetry:telemetry-histogram-snapshot
                                     histogram))))
                  (list :name "ethereum_lisp_u_ms" :type :histogram
                        :samples
                        (list (cons nil
                                    (ethereum-lisp.telemetry:telemetry-histogram-snapshot
                                     (ethereum-lisp.telemetry:make-telemetry-histogram
                                      '(1))))))
                  ;; No samples yet: the series is still declared.
                  (list :name "ethereum_lisp_empty_total" :type :counter)))))
      (is (string=
           (format nil "~
# HELP ethereum_lisp_events_total Telemetry events emitted since start, by event name.
# TYPE ethereum_lisp_events_total counter
ethereum_lisp_events_total{event=\"a.b\"} 2
# TYPE ethereum_lisp_x_age_ms gauge
ethereum_lisp_x_age_ms 7
# HELP ethereum_lisp_engine_requests_total Answered.
# TYPE ethereum_lisp_engine_requests_total counter
ethereum_lisp_engine_requests_total{method=\"engine_forkchoiceUpdatedV3\"} 3
# HELP ethereum_lisp_t_ms Time.
# TYPE ethereum_lisp_t_ms histogram
ethereum_lisp_t_ms_bucket{family=\"rpc\",le=\"10\"} 2
ethereum_lisp_t_ms_bucket{family=\"rpc\",le=\"100\"} 3
ethereum_lisp_t_ms_bucket{family=\"rpc\",le=\"+Inf\"} 4
ethereum_lisp_t_ms_sum{family=\"rpc\"} 521
ethereum_lisp_t_ms_count{family=\"rpc\"} 4
# TYPE ethereum_lisp_u_ms histogram
ethereum_lisp_u_ms_bucket{le=\"1\"} 0
ethereum_lisp_u_ms_bucket{le=\"+Inf\"} 0
ethereum_lisp_u_ms_sum 0
ethereum_lisp_u_ms_count 0
# TYPE ethereum_lisp_empty_total counter
")
           text))))
  ;; Bounds that are not ascending non-negative integers are refused.
  (dolist (bounds '(() (10 5) (1 1) (-1 3) (1.5)))
    (is (signals error
          (ethereum-lisp.telemetry:make-telemetry-histogram bounds)))))

(defun observability-test-emit (sink name &rest fields)
  (ethereum-lisp.telemetry:telemetry-log
   :info name :sink sink
   :fields (loop for (key value) on fields by #'cddr collect (cons key value))))

(defun observability-test-sample (families name labels)
  "The value of NAME's sample with exactly LABELS, or NIL."
  (let ((family (find name families
                      :key (lambda (family) (getf family :name))
                      :test #'string=)))
    (cdr (assoc labels (getf family :samples) :test #'equal))))

(deftest devnet-observability-sink-files-engine-guard-peer-and-heal-events
  (:layer :unit :module :cli)
  (let* ((memory (ethereum-lisp.telemetry:make-memory-telemetry-sink))
         (sink (ethereum-lisp.cli::make-devnet-observability-sink
                :delegate memory))
         (emitted 0))
    (flet ((emit (name &rest fields)
             (incf emitted)
             (apply #'observability-test-emit sink name fields)))
      ;; Answered Engine requests are counted by method...
      (emit "engine.rpc.http.request" "rpcMethods" "engine_forkchoiceUpdatedV3"
            "status" "200" "handlerMs" 30 "guardWaitMs" 12 "fcuReorgDepth" 3)
      (emit "engine.rpc.http.request" "rpcMethods" "engine_exchangeCapabilities"
            "status" "200" "handlerMs" 2)
      (emit "engine.rpc.http.request" "rpcMethods" "engine_newPayloadV1"
            "status" "200" "handlerMs" 90 "npExecuteMs" 60 "npPersistMs" 20)
      ;; ...but not a refusal on the public port, an unauthenticated call, an
      ;; unknown name a client made up, or a batch.
      (emit "engine.rpc.http.request" "rpcMethods" "engine_forkchoiceUpdatedV3"
            "status" "200" "rpcErrorCode" "-32601" "handlerMs" 1)
      (emit "engine.rpc.http.request" "rpcMethods" "engine_forkchoiceUpdatedV3"
            "status" "401" "handlerMs" 1)
      (emit "engine.rpc.http.request" "rpcMethods" "engine_madeUpV9"
            "status" "200" "handlerMs" 1)
      (emit "engine.rpc.http.request"
            "rpcMethods" "engine_exchangeCapabilities,eth_chainId"
            "status" "200" "handlerMs" 4)
      (emit "engine.rpc.http.request" "rpcMethods" "eth_blockNumber"
            "status" "200" "handlerMs" 3)
      ;; A request deadline is a timeout; a peer hanging up is not.
      (emit "engine.rpc.http.connection.error" "error" "x"
            "reason" "request-deadline")
      (emit "engine.rpc.http.connection.error" "error" "reset")
      ;; Long holds by holder class: fixed labels and Engine methods by name,
      ;; public methods as rpc, anything else as other.
      (emit "node.store_guard.long_hold" "holder" "sync-gap-fill"
            "holdMs" "1500")
      (emit "node.store_guard.long_hold" "holder" "engine_forkchoiceUpdatedV3"
            "holdMs" "2000")
      (emit "node.store_guard.long_hold" "holder" "eth_getBalance"
            "holdMs" "1200")
      (emit "node.store_guard.long_hold" "holder" "ethereum-lisp-made-up"
            "holdMs" "9999")
      (emit "p2p.peer.session_failed" "error" "free text"
            "reason" "end-of-file")
      (emit "p2p.peer.session_failed" "error" "free text"
            "reason" "end-of-file")
      (emit "p2p.peer.refused" "reason" "TOO-MANY-PEERS")
      (emit "peer.snap.heal_progress" "pivot" "6090" "processedNodes" "25874"
            "fetchedNodes" "26050" "frontierWorks" "35179"
            "knownIncompleteNodes" "12" "completed" "NIL")
      (emit "block.import"))
    (let ((families (ethereum-lisp.cli::devnet-observability-families sink))
          (gauges (ethereum-lisp.cli::devnet-observability-gauges sink)))
      (flet ((gauge (name) (cdr (assoc name gauges :test #'string=)))
             (sample (name labels)
               (observability-test-sample families name labels)))
        (is (eql 1 (sample "ethereum_lisp_engine_requests_total"
                           '(("method" . "engine_forkchoiceUpdatedV3")))))
        (is (eql 1 (sample "ethereum_lisp_engine_requests_total"
                           '(("method" . "engine_exchangeCapabilities")))))
        (is (eql 1 (sample "ethereum_lisp_engine_requests_total"
                           '(("method" . "engine_newPayloadV1")))))
        (is (= 3 (length (getf (find "ethereum_lisp_engine_requests_total"
                                     families
                                     :key (lambda (f) (getf f :name))
                                     :test #'string=)
                               :samples))))
        ;; Every request with a handler time lands in its family.
        ;; Latency is recorded for refused calls too: they cost handler time.
        (is (= 3 (getf (sample "ethereum_lisp_rpc_handler_ms"
                               '(("family" . "engine_forkchoice_updated")))
                       :count)))
        (is (= 2 (getf (sample "ethereum_lisp_rpc_handler_ms"
                               '(("family" . "engine_other")))
                       :count)))
        (is (= 1 (getf (sample "ethereum_lisp_rpc_handler_ms"
                               '(("family" . "rpc_batch")))
                       :count)))
        (is (= 1 (getf (sample "ethereum_lisp_rpc_handler_ms"
                               '(("family" . "rpc")))
                       :count)))
        ;; Guard wait per answered Engine request, zero when absent.
        (is (equal '(:count 3 :sum 12)
                   (let ((wait (sample "ethereum_lisp_engine_guard_wait_ms" nil)))
                     (list :count (getf wait :count) :sum (getf wait :sum)))))
        (is (= 60 (getf (sample "ethereum_lisp_import_execute_ms" nil) :sum)))
        (is (= 20 (getf (sample "ethereum_lisp_import_persist_ms" nil) :sum)))
        (is (= 3 (getf (sample "ethereum_lisp_reorg_depth_blocks" nil) :sum)))
        (is (eql 1 (gauge "ethereum_lisp_reorgs_total")))
        (is (eql 1 (gauge "ethereum_lisp_rpc_request_timeouts_total")))
        (dolist (case '(("sync-gap-fill" 1) ("engine_forkchoiceUpdatedV3" 1)
                        ("rpc" 1) ("other" 1)))
          (is (eql (second case)
                   (sample "ethereum_lisp_store_guard_long_holds_total"
                           (list (cons "holder" (first case)))))))
        (is (= 14699 (getf (sample "ethereum_lisp_store_guard_long_hold_ms" nil)
                           :sum)))
        (is (eql 2 (sample "ethereum_lisp_peer_session_failures_total"
                           '(("reason" . "end-of-file")))))
        (is (eql 1 (sample "ethereum_lisp_peer_refusals_total"
                           '(("reason" . "too-many-peers")))))
        (is (eql 6090 (gauge "ethereum_lisp_snap_heal_pivot_number")))
        (is (eql 25874 (gauge "ethereum_lisp_snap_heal_processed_nodes")))
        (is (eql 35179 (gauge "ethereum_lisp_snap_heal_frontier_works")))
        (is (eql 12 (gauge "ethereum_lisp_snap_heal_known_incomplete_nodes")))
        (is (eql 0 (gauge "ethereum_lisp_snap_heal_completed")))))
    ;; Every event still reaches the delegate.
    (is (= emitted (length (ethereum-lisp.telemetry:telemetry-events memory)))))
  ;; A labelled table stops growing at its cap; the rest is "other".
  (let ((sink (ethereum-lisp.cli::make-devnet-observability-sink))
        (ethereum-lisp.cli::*devnet-observability-max-label-values* 2))
    (dolist (reason '("a" "b" "c" "d" "a"))
      (observability-test-emit sink "p2p.peer.session_failed" "reason" reason))
    (let ((families (ethereum-lisp.cli::devnet-observability-families sink)))
      (is (equal '(2 1 2)
                 (loop for reason in '("a" "b" "other")
                       collect (observability-test-sample
                                families "ethereum_lisp_peer_session_failures_total"
                                (list (cons "reason" reason)))))))))

(defun observability-test-ready (&rest overrides)
  "The readiness verdict for a healthy baseline with OVERRIDES applied."
  (multiple-value-bind (ok-p json)
      (ethereum-lisp.cli::devnet-health-json
       (apply #'ethereum-lisp.cli::devnet-health-ready-checks
              (append overrides
                      (list :shutdown-p nil :peers 3 :syncing-p nil :head 100
                            :target 100 :guard-hold-ms 0 :engine-age-ms 4000))))
    (values ok-p json)))

(deftest devnet-health-ready-names-each-failed-check
  (:layer :unit :module :cli)
  ;; The healthy baseline is the positive control for every row below.
  (multiple-value-bind (ok-p json) (observability-test-ready)
    (is ok-p)
    (is (string=
         (format nil "{\"status\":\"ok\",\"failed\":[],\"checks\":[~
{\"name\":\"shutdown\",\"ok\":true,\"value\":0,\"limit\":0},~
{\"name\":\"peers\",\"ok\":true,\"value\":3,\"limit\":1},~
{\"name\":\"sync\",\"ok\":true,\"value\":0,\"limit\":2},~
{\"name\":\"storeGuard\",\"ok\":true,\"value\":0,\"limit\":8000},~
{\"name\":\"engine\",\"ok\":true,\"value\":4000,\"limit\":60000}]}~%")
         json)))
  (dolist (case '(((:peers 0) "peers")
                  ((:syncing-p t :head 100 :target 103) "sync")
                  ((:guard-hold-ms 8001) "storeGuard")
                  ((:engine-age-ms nil) "engine")
                  ((:engine-age-ms 60001) "engine")
                  ((:shutdown-p t) "shutdown")))
    (multiple-value-bind (ok-p json) (apply #'observability-test-ready
                                            (first case))
      (is (not ok-p))
      (is (search (format nil "\"failed\":[\"~A\"]" (second case)) json))))
  ;; Inside the tolerance is ready: two blocks behind while syncing, a hold at
  ;; exactly the limit, and a target known while eth_syncing is false.
  (is (observability-test-ready :syncing-p t :head 100 :target 102))
  (is (observability-test-ready :guard-hold-ms 8000))
  (is (observability-test-ready :syncing-p nil :head 100 :target 500))
  ;; A missing Engine age is JSON null, not a number.
  (is (search "\"value\":null"
              (nth-value 1 (observability-test-ready :engine-age-ms nil))))
  ;; Liveness does not look at sync, peers or the guard at all.
  (is (ethereum-lisp.cli::devnet-health-json
       (ethereum-lisp.cli::devnet-health-live-checks :shutdown-p nil)))
  (is (not (ethereum-lisp.cli::devnet-health-json
            (ethereum-lisp.cli::devnet-health-live-checks :shutdown-p t)))))

(deftest devnet-observability-http-response-routes-health-and-metrics
  (:layer :unit :module :cli)
  (let* ((metrics-calls 0)
         (health-calls '())
         (metrics (lambda ()
                    (incf metrics-calls)
                    (values (list (cons "a.b" 1)) nil nil)))
         (health (lambda (kind)
                   (push kind health-calls)
                   (if (eq kind :live)
                       (values t "{\"status\":\"ok\"}")
                       (values nil "{\"status\":\"fail\"}")))))
    (flet ((respond (line)
             (ethereum-lisp.cli::devnet-observability-http-response
              line metrics health)))
      (let ((live (respond "GET /health/live HTTP/1.1"))
            (ready (respond "GET /health/ready?verbose=1 HTTP/1.1"))
            (head (respond "HEAD /health/ready HTTP/1.1")))
        (is (equal "HTTP/1.1 200 OK" (devnet-metrics-test-status-line live)))
        (is (search "Content-Type: application/json" live))
        (is (search "{\"status\":\"ok\"}" live))
        (is (equal "HTTP/1.1 503 Service Unavailable"
                   (devnet-metrics-test-status-line ready)))
        (is (search "{\"status\":\"fail\"}" ready))
        (is (equal "HTTP/1.1 503 Service Unavailable"
                   (devnet-metrics-test-status-line head)))
        (is (null (search "{\"status\"" head))))
      (is (equal '(:ready :ready :live) health-calls))
      ;; A probe never pays for a scrape.
      (is (= 0 metrics-calls))
      (is (search "ethereum_lisp_events_total{event=\"a.b\"} 1"
                  (respond "GET /metrics HTTP/1.1")))
      (is (= 1 metrics-calls))
      ;; Only reads: a POST to a health path gets the endpoint's 405.
      (is (equal "HTTP/1.1 405 Method Not Allowed"
                 (devnet-metrics-test-status-line
                  (respond "POST /health/ready HTTP/1.1"))))
      (is (equal "HTTP/1.1 404 Not Found"
                 (devnet-metrics-test-status-line
                  (respond "GET /health HTTP/1.1"))))
      (is (= 3 (length health-calls))))))

(deftest engine-forkchoice-records-reorg-depth-only-for-a-reorg
  (:layer :unit :module :engine)
  ;; fcuReorgDepth feeds the reorg count and depth histogram. A forkchoice that
  ;; extends or repeats the head displaces nothing and must not report one.
  (labels ((forkchoice (store config id head)
             (let ((ethereum-lisp.engine-api:*engine-rpc-phase-timings* nil))
               (let ((response
                       (parse-json
                        (engine-rpc-handle-request-json
                         (concatenate
                          'string
                          "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
                          ",\"method\":\"engine_forkchoiceUpdatedV1\","
                          "\"params\":[{\"headBlockHash\":\"" (hash32-to-hex head)
                          "\",\"safeBlockHash\":\"" (hash32-to-hex (zero-hash32))
                          "\",\"finalizedBlockHash\":\"" (hash32-to-hex (zero-hash32))
                          "\"}]}")
                         store config))))
                 (values
                  (cdr (assoc "status"
                              (cdr (assoc "payloadStatus"
                                          (cdr (assoc "result" response
                                                      :test #'string=))
                                          :test #'string=))
                              :test #'string=))
                  (cdr (assoc "fcuReorgDepth"
                              ethereum-lisp.engine-api:*engine-rpc-phase-timings*
                              :test #'string=))))))
           (child (parent number extra)
             (make-block
              :header
              (make-block-header :number number
                                 :parent-hash (block-hash parent)
                                 :gas-limit 30000000
                                 :timestamp (* 12 number)
                                 :extra-data (vector extra)))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1))
           (genesis (make-block
                     :header (make-block-header :number 0
                                                :parent-hash (zero-hash32)
                                                :gas-limit 30000000
                                                :timestamp 0
                                                :extra-data #(0))))
           (a1 (child genesis 1 1))
           (a2 (child a1 2 1))
           (b1 (child genesis 1 2)))
      (dolist (block (list genesis a1 a2 b1))
        (engine-payload-store-put-block store block :state-available-p t))
      (multiple-value-bind (status depth) (forkchoice store config 1
                                                      (block-hash a2))
        (is (string= +payload-status-valid+ status))
        (is (null depth)))
      ;; Repeating the head is not a reorg either.
      (is (null (nth-value 1 (forkchoice store config 2 (block-hash a2)))))
      ;; Moving to the sibling branch displaces a1 and a2.
      (multiple-value-bind (status depth) (forkchoice store config 3
                                                      (block-hash b1))
        (is (string= +payload-status-valid+ status))
        (is (eql 2 depth)))
      ;; And back: b1 is displaced.
      (is (eql 1 (nth-value 1 (forkchoice store config 4 (block-hash a2))))))))

;;;; The endpoint against a live node, with the store guard held.

#+sbcl
(defun observability-test-http-get (port path)
  "GET PATH from 127.0.0.1:PORT; return (VALUES STATUS BODY SECONDS)."
  (let ((socket (make-instance 'sb-bsd-sockets:inet-socket
                               :type :stream :protocol :tcp))
        (started (monotonic-seconds)))
    (unwind-protect
         (progn
           (sb-bsd-sockets:socket-connect
            socket (sb-bsd-sockets:make-inet-address "127.0.0.1") port)
           (let ((stream (sb-bsd-sockets:socket-make-stream
                          socket :input t :output t :element-type 'character
                                 :external-format :utf-8 :buffering :none)))
             (format stream "GET ~A HTTP/1.1~C~CHost: x~C~C~C~C" path
                     #\Return #\Newline #\Return #\Newline #\Return #\Newline)
             (finish-output stream)
             (let* ((text (with-output-to-string (out)
                            (loop for char = (read-char stream nil nil)
                                  while char do (write-char char out))))
                    (boundary (search (format nil "~C~C~C~C" #\Return #\Newline
                                              #\Return #\Newline)
                                      text)))
               (values (parse-integer text :start 9 :end 12)
                       (if boundary (subseq text (+ boundary 4)) "")
                       (- (monotonic-seconds) started)))))
      (ignore-errors (sb-bsd-sockets:socket-close socket)))))

#+sbcl
(defun observability-test-gauge (text name)
  "The integer value of unlabelled metric NAME in exposition TEXT, or NIL."
  (loop for line in (uiop:split-string text :separator '(#\Newline))
        when (and (> (length line) (length name))
                  (string= name line :end2 (length name))
                  (char= #\Space (char line (length name))))
          return (parse-integer line :start (1+ (length name)))))

#+sbcl
(deftest devnet-health-and-metrics-answer-while-the-store-guard-is-held
  (:layer :integration :module :cli :requires-local-sockets t
   :estimated-seconds 15d0)
  ;; A real node with --metrics. One thread holds the node's store guard for
  ;; several seconds, as a long import does. /health/live, /health/ready and
  ;; /metrics must all answer inside a second during that hold, and readiness
  ;; must name the hold. The positive control is a guarded public RPC call
  ;; sent in the same window: it has to wait for the guard, which proves the
  ;; guard really was held while the endpoints answered.
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0 :public-port 0
                :metrics t :metrics-host "127.0.0.1" :metrics-port 0))
         (controller (ethereum-lisp.cli::make-devnet-shutdown-controller))
         (previous-limit ethereum-lisp.cli::*devnet-health-ready-max-guard-hold-ms*)
         (engine nil) (public nil) (server nil) (server-error nil)
         (holder nil) (holder-error nil) (released nil)
         (idle-ready nil) (held-live nil) (held-ready nil) (held-metrics nil)
         (guarded-seconds nil) (guarded-response nil))
    (unwind-protect
         (progn
           ;; A global, not a binding: the endpoint answers on its own thread.
           (setf ethereum-lisp.cli::*devnet-health-ready-max-guard-hold-ms* 1000)
           (setf server
                 (sb-thread:make-thread
                  (lambda ()
                    (handler-case
                        (ethereum-lisp.cli:start-devnet-node
                         node :shutdown-controller controller
                         :on-listeners-ready
                         (lambda (engine-listener public-listener)
                           (setf engine (engine-rpc-http-listener-endpoint
                                         engine-listener)
                                 public (engine-rpc-http-listener-endpoint
                                         public-listener))))
                      (serious-condition (condition)
                        (setf server-error condition))))
                  :name "observability-test-node"))
           (wait-for-test-condition "the node's listeners" 30
                                    (lambda () (and engine public)))
           (let ((port (ethereum-lisp.cli:devnet-node-metrics-port node)))
             ;; The consensus client's upcheck, so the engine check has an age.
             (devnet-cli-http-endpoint-request
              engine
              (devnet-cli-json-rpc-http-request
               "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"engine_exchangeCapabilities\",\"params\":[[]]}"))
             ;; One peer, owning no socket.
             (ethereum-lisp.cli::call-with-devnet-peer-table
              node
              (lambda ()
                (ethereum-lisp.cli:devnet-peer-table-admit
                 (ethereum-lisp.cli::devnet-node-peer-table node)
                 (ethereum-lisp.cli:make-devnet-peer-entry
                  :id-hex "aa" :direction :inbound :eth-version 69)
                 0)))
             ;; Idle: the healthy node is ready. Positive control for the
             ;; not-ready verdict below.
             (setf idle-ready (multiple-value-list
                               (observability-test-http-get port "/health/ready")))
             (setf holder
                   (sb-thread:make-thread
                    (lambda ()
                      (handler-case
                          (ethereum-lisp.cli::call-with-devnet-node-store-guard
                           node (lambda () (sleep 4)))
                        (serious-condition (condition)
                          (setf holder-error condition)))
                      (setf released (monotonic-seconds)))
                    :name "observability-test-guard-holder"))
             (wait-for-test-condition
              "the guard holder" 10
              (lambda ()
                (ethereum-lisp.cli::devnet-store-guard-ledger-holder-label
                 (ethereum-lisp.cli::devnet-node-store-guard-ledger node))))
             (sleep 1.5d0)
             (setf held-live (multiple-value-list
                              (observability-test-http-get port "/health/live"))
                   held-ready (multiple-value-list
                               (observability-test-http-get port "/health/ready"))
                   held-metrics (multiple-value-list
                                 (observability-test-http-get port "/metrics")))
             ;; The positive control: eth_getBalance takes the guard, so it
             ;; cannot be answered until the holder lets go.
             (let ((started (monotonic-seconds)))
               (setf guarded-response
                     (devnet-cli-http-endpoint-request
                      public
                      (devnet-cli-json-rpc-http-request
                       "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"eth_getBalance\",\"params\":[\"0x0000000000000000000000000000000000000001\",\"latest\"]}"))
                     guarded-seconds (- (monotonic-seconds) started)))
             (sb-thread:join-thread holder :timeout 10 :default nil)
             (ethereum-lisp.cli::call-with-devnet-peer-table
              node
              (lambda ()
                (ethereum-lisp.cli::devnet-peer-table-remove
                 (ethereum-lisp.cli::devnet-node-peer-table node) "aa")))))
      (setf ethereum-lisp.cli::*devnet-health-ready-max-guard-hold-ms*
            previous-limit)
      (ethereum-lisp.cli:devnet-shutdown-request controller)
      (when server
        (sb-thread:join-thread server :timeout 60 :default nil)))
    (format t "~&;; idle ready ~S~%;; held live ~S~%;; held ready ~S~%~
;; held metrics ~,3Fs~%;; guarded call ~,3Fs~%"
            idle-ready held-live held-ready (third held-metrics) guarded-seconds)
    (is (null server-error))
    (is (null holder-error))
    ;; Idle and healthy: ready.
    (is (eql 200 (first idle-ready)))
    (is (search "\"failed\":[]" (second idle-ready)))
    ;; Held: every endpoint answered, fast, and readiness named the guard.
    (is (eql 200 (first held-live)))
    (is (< (third held-live) 1))
    (is (eql 503 (first held-ready)))
    (is (search "\"failed\":[\"storeGuard\"]" (second held-ready)))
    (is (< (third held-ready) 1))
    (is (eql 200 (first held-metrics)))
    (is (< (third held-metrics) 1))
    (is (<= 1000 (observability-test-gauge
                  (second held-metrics) "ethereum_lisp_store_guard_hold_age_ms")))
    (is (integerp (observability-test-gauge
                   (second held-metrics)
                   "ethereum_lisp_engine_last_request_age_ms")))
    (is (search "# TYPE ethereum_lisp_rpc_handler_ms histogram"
                (second held-metrics)))
    ;; The control: the guarded call waited for the rest of the hold.
    (is (search "\"result\"" guarded-response))
    (is (>= guarded-seconds 1))))
