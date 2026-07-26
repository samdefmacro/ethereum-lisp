(in-package #:ethereum-lisp.test)

;;;; The metrics endpoint.
;;;;
;;;; Nearly all of it is pure: what a request line means, and how a snapshot
;;;; renders. One test binds a socket and scrapes it for real, because the thing
;;;; most likely to be wrong is not the formatting but whether a client that
;;;; sends a request actually gets bytes back and the thread still stops.

(deftest telemetry-prometheus-text-renders-a-snapshot
  (let ((text (ethereum-lisp.telemetry:telemetry-prometheus-text
               (list (cons "peer.dial.connected" 3)
                     (cons "block.import" 12)))))
    (is (search "# TYPE ethereum_lisp_events_total counter" text))
    ;; The dotted name survives intact, because it is a label value and not
    ;; part of the metric name.
    (is (search "ethereum_lisp_events_total{event=\"peer.dial.connected\"} 3"
                text))
    (is (search "ethereum_lisp_events_total{event=\"block.import\"} 12" text))
    ;; Every exposition document ends with a newline.
    (is (char= #\Newline (char text (1- (length text))))))
  ;; An empty snapshot is a valid document, not an empty one: a scraper needs
  ;; the HELP and TYPE lines to know the metric exists at zero.
  (let ((text (ethereum-lisp.telemetry:telemetry-prometheus-text '())))
    (is (search "# HELP ethereum_lisp_events_total" text))
    (is (search "# TYPE ethereum_lisp_events_total counter" text))
    (is (null (search "{event=" text)))))

(deftest telemetry-prometheus-escapes-label-values
  ;; No event name we emit needs this today. One that did and was not escaped
  ;; would produce a document the scraper rejects wholesale.
  (is (equal "a\\\\b" (ethereum-lisp.telemetry:telemetry-prometheus-escape
                       "a\\b")))
  (is (equal "a\\\"b" (ethereum-lisp.telemetry:telemetry-prometheus-escape
                       "a\"b")))
  (is (equal "a\\nb" (ethereum-lisp.telemetry:telemetry-prometheus-escape
                      (format nil "a~Cb" #\Newline))))
  ;; The common case allocates nothing new.
  (is (equal "peer.dial.connected"
             (ethereum-lisp.telemetry:telemetry-prometheus-escape
              "peer.dial.connected"))))

(defun devnet-metrics-test-status-line (response)
  (subseq response 0 (position #\Return response)))

(deftest devnet-metrics-http-response-routes-requests
  (let ((snapshot (list (cons "a.b" 7))))
    ;; The path Prometheus scrapes, and the one a geth scrape config points at.
    (dolist (target '("/metrics" "/debug/metrics/prometheus"))
      (let ((response (ethereum-lisp.cli:devnet-metrics-http-response
                       (format nil "GET ~A HTTP/1.1" target) snapshot)))
        (is (equal "HTTP/1.1 200 OK"
                   (devnet-metrics-test-status-line response)))
        (is (search "ethereum_lisp_events_total{event=\"a.b\"} 7" response))))
    ;; A query string is not part of the path.
    (is (search "{event=\"a.b\"} 7"
                (ethereum-lisp.cli:devnet-metrics-http-response
                 "GET /metrics?debug=1 HTTP/1.1" snapshot)))
    ;; HTTP/1.0 is a question we can answer, so we answer it.
    (is (equal "HTTP/1.1 200 OK"
               (devnet-metrics-test-status-line
                (ethereum-lisp.cli:devnet-metrics-http-response
                 "GET /metrics HTTP/1.0" snapshot))))
    ;; HEAD gets the headers a GET would, length included, and no body.
    (let ((response (ethereum-lisp.cli:devnet-metrics-http-response
                     "HEAD /metrics HTTP/1.1" snapshot))
          (body (ethereum-lisp.telemetry:telemetry-prometheus-text snapshot)))
      (is (equal "HTTP/1.1 200 OK"
                 (devnet-metrics-test-status-line response)))
      (is (search (format nil "Content-Length: ~D"
                          (ethereum-lisp.cli::devnet-metrics-octet-length body))
                  response))
      (is (null (search "ethereum_lisp_events_total{" response))))
    ;; Anything that is not a read is refused, and told what is allowed.
    (let ((response (ethereum-lisp.cli:devnet-metrics-http-response
                     "POST /metrics HTTP/1.1" snapshot)))
      (is (equal "HTTP/1.1 405 Method Not Allowed"
                 (devnet-metrics-test-status-line response)))
      (is (search "Allow: GET, HEAD" response)))
    (is (equal "HTTP/1.1 404 Not Found"
               (devnet-metrics-test-status-line
                (ethereum-lisp.cli:devnet-metrics-http-response
                 "GET /nope HTTP/1.1" snapshot))))
    (is (equal "HTTP/1.1 400 Bad Request"
               (devnet-metrics-test-status-line
                (ethereum-lisp.cli:devnet-metrics-http-response
                 "GET" snapshot))))
    ;; Content-Length counts octets. A body with a multi-byte character would
    ;; be truncated by a length in characters, and the scrape would fail with
    ;; nothing in the log to explain it.
    ;; "aec" with an acute e: three characters, four octets.
    (is (= 4 (ethereum-lisp.cli::devnet-metrics-octet-length
              (format nil "a~Cc" (code-char #xE9)))))))

(deftest devnet-metrics-endpoint-is-off-unless-both-flags-are-given
  ;; --metrics.port without --metrics binds nothing, which is geth's rule. The
  ;; check must be "is metrics on", not "are there counts": a node that just
  ;; started with metrics on has counted nothing yet.
  (let ((counting (ethereum-lisp.cli:make-devnet-node
                   :genesis-json *eth-sync-paris-genesis-json*
                   :port 0 :public-port 0 :metrics t :metrics-port 9123))
        (uncounted (ethereum-lisp.cli:make-devnet-node
                    :genesis-json *eth-sync-paris-genesis-json*
                    :port 0 :public-port 0 :metrics-port 9123))
        (no-port (ethereum-lisp.cli:make-devnet-node
                  :genesis-json *eth-sync-paris-genesis-json*
                  :port 0 :public-port 0 :metrics t)))
    (is (ethereum-lisp.cli:devnet-node-metrics-enabled-p counting))
    (is (null (ethereum-lisp.cli:devnet-node-metrics counting)))
    (is (= 9123 (nth-value 1 (ethereum-lisp.cli:devnet-node-metrics-endpoint
                              counting))))
    ;; Loopback unless asked otherwise: metrics should not appear on a public
    ;; interface because someone turned counting on.
    (is (equal "127.0.0.1"
               (ethereum-lisp.cli:devnet-node-metrics-endpoint counting)))
    (is (null (ethereum-lisp.cli:devnet-node-metrics-endpoint uncounted)))
    (is (null (ethereum-lisp.cli:devnet-node-metrics-endpoint no-port)))))

(deftest devnet-metrics-options-are-parsed
  (let ((options (ethereum-lisp.cli::devnet-cli-options
                  (list "--genesis" "g.json" "--metrics"
                        "--metrics.addr" "0.0.0.0" "--metrics.port" "6060"))))
    (is (getf options :metrics))
    (is (equal "0.0.0.0" (getf options :metrics-host)))
    (is (= 6060 (getf options :metrics-port)))))

#+sbcl
(deftest devnet-metrics-endpoint-answers-a-scrape
  (:layer :integration :module :devnet :requires-local-sockets t)
  ;; The end-to-end property: a client that connects and sends a request line
  ;; gets a document back, and the thread still stops afterwards.
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0 :public-port 0
                :metrics t :metrics-host "127.0.0.1" :metrics-port 0))
         (controller (ethereum-lisp.cli::make-devnet-shutdown-controller))
         (thread-error nil)
         (thread nil))
    ;; Something to count, so the scrape has a line to show.
    (ethereum-lisp.telemetry:telemetry-log
     :info "metrics.test_event"
     :sink (ethereum-lisp.cli::devnet-node-telemetry-sink node))
    (unwind-protect
         (progn
           (setf thread (ethereum-lisp.cli:devnet-start-metrics-server-thread
                         node controller
                         (lambda (condition) (setf thread-error condition))))
           (is (not (null thread)))
           (let ((port (ethereum-lisp.cli:devnet-node-metrics-port node)))
             ;; Port 0 was replaced by the port actually bound, so a caller can
             ;; report where the endpoint landed.
             (is (plusp port))
             (let ((socket (make-instance 'sb-bsd-sockets:inet-socket
                                          :type :stream :protocol :tcp)))
               (unwind-protect
                    (let ((stream nil))
                      (sb-bsd-sockets:socket-connect
                       socket (sb-bsd-sockets:make-inet-address "127.0.0.1")
                       port)
                      (setf stream (sb-bsd-sockets:socket-make-stream
                                    socket :input t :output t
                                           :element-type 'character
                                           :external-format :utf-8
                                           :buffering :none))
                      (format stream "GET /metrics HTTP/1.1~C~CHost: x~C~C~C~C"
                              #\Return #\Newline #\Return #\Newline
                              #\Return #\Newline)
                      (finish-output stream)
                      (let ((response
                              (with-output-to-string (out)
                                (loop for char = (read-char stream nil nil)
                                      while char do (write-char char out)))))
                        (is (search "HTTP/1.1 200 OK" response))
                        (is (search "ethereum_lisp_events_total{event=\"metrics.test_event\"} 1"
                                    response))))
                 (ignore-errors (sb-bsd-sockets:socket-close socket)))))
           ;; And it stops. This is the assertion: it comes back.
           (ethereum-lisp.cli:devnet-shutdown-request controller)
           (is (not (eq :timeout
                        (sb-thread:join-thread thread :timeout 10
                                                      :default :timeout))))
           (is (null thread-error)))
      (ethereum-lisp.cli:devnet-shutdown-request controller)
      (when thread
        (ignore-errors (sb-thread:join-thread thread :timeout 5
                                                     :default :timeout))))))
