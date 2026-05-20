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

(defgeneric telemetry-emit (sink event))

(defmethod telemetry-emit ((sink null) event)
  (declare (ignore event))
  nil)

(defmethod telemetry-emit
    ((sink memory-telemetry-sink) (event telemetry-event))
  (push event (memory-telemetry-sink-events sink))
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
