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
                (&key stream)))
  stream
  #+sbcl
  (lock (sb-thread:make-mutex :name "telemetry stream sink")))

(defun make-stream-telemetry-sink (&key (stream *standard-output*))
  (unless (output-stream-p stream)
    (error "Telemetry stream sink requires an output stream"))
  (%make-stream-telemetry-sink :stream stream))

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
  (let ((stream (stream-telemetry-sink-stream sink)))
    #+sbcl
    (sb-thread:with-mutex ((stream-telemetry-sink-lock sink))
      (telemetry-write-event-record stream event))
    #-sbcl
    (telemetry-write-event-record stream event))
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
