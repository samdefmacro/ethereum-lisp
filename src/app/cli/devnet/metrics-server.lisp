(in-package #:ethereum-lisp.cli)

;;;; The metrics endpoint.
;;;;
;;;; --metrics already counts every telemetry event the node emits. This is the
;;;; other half that --metrics.addr and --metrics.port promised: a scraper can
;;;; read those counts over HTTP instead of parsing the log stream or waiting
;;;; for the shutdown summary.
;;;;
;;;; IT IS NOT THE JSON-RPC SERVER, AND DELIBERATELY SO. The RPC stack next door
;;;; speaks one shape -- POST a JSON-RPC envelope -- and enforces JWT, vhosts
;;;; and CORS on the way in. A Prometheus scrape is a plain GET with no body and
;;;; no credentials, so routing it through that stack would mean loosening every
;;;; one of those checks for one path. A separate socket keeps the authenticated
;;;; surface exactly as small as it already was.
;;;;
;;;; IT SERVES COUNTS AND NOTHING ELSE. Event names and their totals say what the
;;;; node has been doing; they carry no addresses, no hashes, no payload data.
;;;; That is what makes it safe to expose to an unauthenticated scraper -- and
;;;; the reason to keep it that way if it ever grows.

(defconstant +devnet-metrics-accept-timeout-seconds+ 1
  "How long the metrics accept gate waits before returning to its loop. Our
policy: also the upper bound on how long the endpoint takes to notice shutdown.")

(defconstant +devnet-metrics-read-timeout-seconds+ 5
  "How long one scrape may take to send its request line and headers. Our
policy. The endpoint serves one connection at a time, so a client that connects
and then says nothing would otherwise stall every later scrape; five seconds is
far above any real request and far below a scrape interval.")

(defconstant +devnet-metrics-request-line-limit+ 8192
  "The longest request or header line accepted, in characters. Our policy, and a
bound rather than a target: a client that sends an endless line with no newline
must not be able to grow our heap.")

(defconstant +devnet-metrics-header-limit+ 64
  "How many header lines are drained before the rest are ignored. Our policy.")

(defun devnet-metrics-octet-length (string)
  "How many octets STRING occupies in UTF-8.

Content-Length counts octets, not characters. Every body this file produces is
ASCII today, so this only matters the first time one is not -- at which point a
length in characters would truncate the response and the scrape would fail with
no clue why."
  (loop for char across string
        sum (let ((code (char-code char)))
              (cond ((< code #x80) 1)
                    ((< code #x800) 2)
                    ((< code #x10000) 3)
                    (t 4)))))

(defun devnet-metrics-target-path (target)
  "TARGET without its query string.

Scrapers append parameters often enough that ignoring them is the difference
between working and 404."
  (if (stringp target)
      (subseq target 0 (or (position #\? target) (length target)))
      ""))

(defun devnet-metrics-request-method-and-target (request-line)
  "(VALUES METHOD TARGET) from REQUEST-LINE, or (VALUES NIL NIL) if malformed.

Deliberately more forgiving than the JSON-RPC parser next door: any HTTP version
is accepted, because a scraper speaking HTTP/1.0 is asking a question we can
answer and refusing it would be pedantry rather than safety."
  (let* ((line (string-trim '(#\Space #\Tab #\Return #\Newline) request-line))
         (first-space (position #\Space line))
         (method (and first-space (subseq line 0 first-space)))
         (remainder (and first-space (subseq line (1+ first-space))))
         (second-space (and remainder (position #\Space remainder)))
         (target (and remainder
                      (subseq remainder 0
                              (or second-space (length remainder))))))
    (if (and method target (plusp (length method)) (plusp (length target)))
        (values method target)
        (values nil nil))))

(defun devnet-metrics-http-reply
    (status reason body
     &key (content-type "text/plain; charset=utf-8") head-p extra-headers)
  "One complete HTTP response, as a string.

Every response says `Connection: close` and the endpoint then closes: with no
keep-alive there is no chance of a half-consumed body desynchronising whatever
arrives next on the same socket."
  (with-output-to-string (out)
    (format out "HTTP/1.1 ~D ~A~C~C" status reason #\Return #\Newline)
    (format out "Content-Type: ~A~C~C" content-type #\Return #\Newline)
    (format out "Content-Length: ~D~C~C"
            (devnet-metrics-octet-length body) #\Return #\Newline)
    (dolist (header extra-headers)
      (format out "~A~C~C" header #\Return #\Newline))
    (format out "Connection: close~C~C" #\Return #\Newline)
    (format out "~C~C" #\Return #\Newline)
    ;; A HEAD reply carries exactly the headers a GET would, length included,
    ;; and no body.
    (unless head-p
      (write-string body out))))

(defun devnet-metrics-http-response (request-line snapshot)
  "The whole HTTP response to REQUEST-LINE, as a string.

Pure, so which paths answer and what a wrong method gets are testable without
binding a socket. SNAPSHOT is what COUNTING-TELEMETRY-SINK-SNAPSHOT returns.

Both `/metrics` and geth's `/debug/metrics/prometheus` are served: the first is
the Prometheus convention, the second is where a scrape config written for geth
already points, and answering both costs one clause."
  (multiple-value-bind (method target)
      (devnet-metrics-request-method-and-target request-line)
    (let ((path (devnet-metrics-target-path target)))
      (cond
        ((null method)
         (devnet-metrics-http-reply 400 "Bad Request" "malformed request line"))
        ((not (or (string= method "GET") (string= method "HEAD")))
         (devnet-metrics-http-reply 405 "Method Not Allowed"
                                    "only GET and HEAD are served"
                                    :extra-headers '("Allow: GET, HEAD")))
        ((or (string= path "/metrics")
             (string= path "/debug/metrics/prometheus"))
         (devnet-metrics-http-reply
          200 "OK"
          (telemetry-prometheus-text snapshot)
          :content-type "text/plain; version=0.0.4; charset=utf-8"
          :head-p (string= method "HEAD")))
        (t
         (devnet-metrics-http-reply 404 "Not Found" "try /metrics"
                                    :head-p (string= method "HEAD")))))))

(defun devnet-metrics-read-line (stream timeout-seconds)
  "One line from STREAM without its CRLF, or NIL on timeout, EOF or overlong input.

Reads what is already available and only then waits on the descriptor, for the
same reason the RLPx accept loop is readiness-gated: a blocking read on a socket
nobody is writing to cannot be interrupted, and this thread has a shutdown to
notice."
  #-sbcl
  (declare (ignore stream timeout-seconds))
  #-sbcl
  nil
  #+sbcl
  (let ((line (make-array 0 :element-type 'character
                            :adjustable t :fill-pointer 0))
        (fd (sb-sys:fd-stream-fd stream)))
    (loop
      (let ((char (read-char-no-hang stream nil :eof)))
        (cond
          ((eq char :eof) (return nil))
          ;; Nothing decodable yet -- either no bytes at all, or the leading
          ;; bytes of a character whose tail has not arrived. Waiting on the
          ;; descriptor is what keeps this from spinning.
          ((null char)
           (unless (sb-sys:wait-until-fd-usable fd :input timeout-seconds nil)
             (return nil)))
          ((char= char #\Newline)
           (return (string-right-trim '(#\Return) (coerce line 'string))))
          ((>= (fill-pointer line) +devnet-metrics-request-line-limit+)
           (return nil))
          (t (vector-push-extend char line)))))))

(defun devnet-metrics-serve-connection (stream snapshot-function)
  "Answer one scrape on STREAM.

The headers are drained even though nothing reads them: a client that has not
finished writing its request will not reliably see the response, and a scraper
that gets a connection reset reports the target as down rather than as answered."
  (let ((request-line (devnet-metrics-read-line
                       stream +devnet-metrics-read-timeout-seconds+)))
    (when request-line
      (loop repeat +devnet-metrics-header-limit+
            for header = (devnet-metrics-read-line
                          stream +devnet-metrics-read-timeout-seconds+)
            until (or (null header) (string= header "")))
      (write-string (devnet-metrics-http-response
                     request-line (funcall snapshot-function))
                    stream)
      (finish-output stream))))

(defun devnet-cli-log-metrics-error (node condition)
  (ethereum-lisp.telemetry:telemetry-log
   :warn "metrics.request_failed"
   :sink (devnet-node-telemetry-sink node)
   :fields `(("error" . ,(princ-to-string condition)))))

(defun devnet-node-metrics-endpoint (node)
  "(VALUES HOST PORT) for the metrics endpoint, or NIL when it is off.

Off unless --metrics is on AND a port was given, which is geth's rule too. A
counting sink with nowhere to publish is still useful -- the shutdown summary
reports it -- but binding a port nobody asked for is not something a flag named
--metrics should do on its own."
  (let ((port (devnet-node-metrics-port node)))
    (when (and port (devnet-node-metrics-enabled-p node))
      (values (or (devnet-node-metrics-host node) "127.0.0.1") port))))

(defun devnet-start-metrics-server-thread (node shutdown-controller error-callback)
  "Start the metrics endpoint, returning its thread or NIL when it is off.

Returns NIL rather than erroring when no port was configured, so a node that
does not ask for metrics pays nothing for them."
  #-sbcl
  (declare (ignore node shutdown-controller error-callback))
  #-sbcl
  nil
  #+sbcl
  (multiple-value-bind (host port) (devnet-node-metrics-endpoint node)
    (when port
      (let ((listener (make-eth-sync-socket-listener :host host :port port)))
        ;; Read the bound port back, so a caller that asked for port 0 can
        ;; report where the endpoint actually landed.
        (setf (devnet-node-metrics-port node) (eth-sync-listener-port listener))
        (devnet-shutdown-controller-add-closeable
         shutdown-controller
         (lambda () (eth-sync-listener-close listener)))
        (sb-thread:make-thread
         (lambda ()
           ;; Mandatory, not defensive: an unhandled condition in ANY thread
           ;; exits the whole process under `sbcl --script`, and a scraper
           ;; hanging up mid-request is an ordinary event.
           (handler-case
               (loop
                 (when (devnet-shutdown-requested-p shutdown-controller)
                   (return))
                 (let ((socket (eth-sync-listener-accept
                                listener
                                :timeout-seconds
                                +devnet-metrics-accept-timeout-seconds+)))
                   (when socket
                     (let ((stream nil))
                       (unwind-protect
                            (handler-case
                                (progn
                                  (setf stream
                                        (sb-bsd-sockets:socket-make-stream
                                         socket :input t :output t
                                                :element-type 'character
                                                :external-format :utf-8
                                                :buffering :none))
                                  (devnet-metrics-serve-connection
                                   stream
                                   (lambda () (devnet-node-metrics node))))
                              ;; One bad scrape ends that connection, not the
                              ;; endpoint.
                              (error (condition)
                                (devnet-cli-log-metrics-error node condition)))
                         (if stream
                             (ignore-errors (close stream))
                             (ignore-errors
                              (sb-bsd-sockets:socket-close socket))))))))
             (error (condition)
               (funcall error-callback condition)
               (devnet-shutdown-request shutdown-controller))))
         :name "ethereum-lisp-devnet-metrics")))))
