(in-package #:ethereum-lisp.telemetry)

(defvar *telemetry-sink* nil
  "Default telemetry sink. NIL disables telemetry emission.")

(defstruct (telemetry-event
            (:constructor make-telemetry-event
                (&key kind name value fields)))
  kind
  name
  value
  fields)

(defstruct (memory-telemetry-sink
            (:constructor make-memory-telemetry-sink
                (&key (events nil))))
  events)

(defstruct (stream-telemetry-sink
            (:constructor %make-stream-telemetry-sink
                (&key stream excluded-event-names)))
  stream
  (excluded-event-names nil :type list)
  #+sbcl
  (lock (sb-thread:make-mutex :name "telemetry stream sink")))

(defun make-stream-telemetry-sink
    (&key (stream *standard-output*) excluded-event-names)
  (unless (output-stream-p stream)
    (error "Telemetry stream sink requires an output stream"))
  (unless (and (listp excluded-event-names)
               (every #'stringp excluded-event-names))
    (error "Telemetry excluded event names must be a string list"))
  (%make-stream-telemetry-sink
   :stream stream :excluded-event-names (copy-list excluded-event-names)))

(defstruct (counting-telemetry-sink
            (:constructor %make-counting-telemetry-sink (counts lock delegate)))
  "A sink that counts events by name, and optionally passes them on.

Every subsystem already emits named telemetry events, so counting them is a
metrics feed that needs no new instrumentation and cannot fall out of step with
what the node actually does -- unlike a parallel set of hand-placed counters.

DELEGATE, when given, still receives every event, so counting can be layered
under logging rather than replacing it."
  counts
  lock
  delegate)

(defun make-counting-telemetry-sink (&key delegate)
  (%make-counting-telemetry-sink
   (make-hash-table :test #'equal)
   #+sbcl (sb-thread:make-mutex :name "telemetry counting sink")
   #-sbcl nil
   delegate))

(defun call-with-counting-sink-lock (sink thunk)
  #+sbcl
  (sb-thread:with-mutex ((counting-telemetry-sink-lock sink)) (funcall thunk))
  #-sbcl
  (progn sink (funcall thunk)))

(defun counting-telemetry-sink-snapshot (sink)
  "The counts so far, as an alist sorted by name.

Taken under the lock and copied, so a caller reporting them cannot see a table
being mutated by a worker thread underneath it."
  (sort (call-with-counting-sink-lock
         sink
         (lambda ()
           (let ((entries '()))
             (maphash (lambda (name count) (push (cons name count) entries))
                      (counting-telemetry-sink-counts sink))
             entries)))
        #'string< :key #'car))

(defgeneric telemetry-emit (sink event))

(defmethod telemetry-emit ((sink null) event)
  (declare (ignore event))
  nil)

(defmethod telemetry-emit
    ((sink memory-telemetry-sink) (event telemetry-event))
  (push event (memory-telemetry-sink-events sink))
  event)

(defmethod telemetry-emit
    ((sink counting-telemetry-sink) (event telemetry-event))
  (let ((name (telemetry-event-name event)))
    (when name
      (call-with-counting-sink-lock
       sink
       (lambda ()
         (incf (gethash name (counting-telemetry-sink-counts sink) 0))))))
  (let ((delegate (counting-telemetry-sink-delegate sink)))
    (when delegate (telemetry-emit delegate event)))
  event)

(defun telemetry-event-record (event)
  (list :kind (telemetry-event-kind event)
        :name (telemetry-event-name event)
        :value (telemetry-event-value event)
        :fields (telemetry-event-fields event)))

(defun telemetry-write-event-record (stream event)
  (write (telemetry-event-record event)
         :stream stream
         :pretty nil)
  (terpri stream)
  (finish-output stream))

(defmethod telemetry-emit
    ((sink stream-telemetry-sink) (event telemetry-event))
  (unless (member (telemetry-event-name event)
                  (stream-telemetry-sink-excluded-event-names sink)
                  :test #'string=)
    (let ((stream (stream-telemetry-sink-stream sink)))
      #+sbcl
      (sb-thread:with-mutex ((stream-telemetry-sink-lock sink))
        (telemetry-write-event-record stream event))
      #-sbcl
      (telemetry-write-event-record stream event)))
  event)

(defun telemetry-events (sink)
  (reverse (memory-telemetry-sink-events sink)))

(defun telemetry-event-fields-copy (fields)
  (when fields
    (unless (listp fields)
      (error "Telemetry event fields must be a list"))
    (copy-list fields)))

(defun telemetry-log (level message &key fields (sink *telemetry-sink*))
  (telemetry-emit
   sink
   (make-telemetry-event
    :kind :log
    :name message
    :value level
    :fields (telemetry-event-fields-copy fields))))

(defun telemetry-metric (name value &key fields (sink *telemetry-sink*))
  (telemetry-emit
   sink
   (make-telemetry-event
    :kind :metric
    :name name
    :value value
    :fields (telemetry-event-fields-copy fields))))

(defun telemetry-prometheus-escape (value)
  "VALUE escaped for use as a Prometheus label value.

None of the event names we emit today contain a backslash, a quote or a
newline, so this changes nothing -- but one that did would produce a document
no scraper can parse, and a scrape that silently drops every metric is worse
than one that never existed."
  (if (find-if (lambda (char) (member char '(#\\ #\" #\Newline))) value)
      (with-output-to-string (out)
        (loop for char across value
              do (case char
                   (#\\ (write-string "\\\\" out))
                   (#\" (write-string "\\\"" out))
                   (#\Newline (write-string "\\n" out))
                   (t (write-char char out)))))
      value))

(defun telemetry-prometheus-text
    (snapshot &key (metric "ethereum_lisp_events_total") gauges)
  "SNAPSHOT rendered in the Prometheus text exposition format.

SNAPSHOT is what COUNTING-TELEMETRY-SINK-SNAPSHOT returns: an alist of event
name to count, sorted by name.

THE EVENT NAME IS A LABEL, NOT PART OF THE METRIC NAME. Our event names contain
dots -- `peer.dial.connected` -- and a Prometheus metric name cannot, so turning
each one into its own metric would mean rewriting the dots as underscores. At
that point `peer.dial.connected` and `peer_dial.connected` are the same metric
and one silently overwrites the other. A label carries the name exactly as it
was emitted, and no mangling can collide."
  (with-output-to-string (out)
    (format out "# HELP ~A Telemetry events emitted since start, by event name.~%"
            metric)
    (format out "# TYPE ~A counter~%" metric)
    (dolist (entry snapshot)
      (format out "~A{event=\"~A\"} ~D~%"
              metric
              (telemetry-prometheus-escape (princ-to-string (car entry)))
              (cdr entry)))
    (dolist (entry gauges)
      (format out "# TYPE ~A gauge~%" (car entry))
      (format out "~A ~D~%" (car entry) (cdr entry)))))
