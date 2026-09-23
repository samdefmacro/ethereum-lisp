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
    ;; A GAUGES entry named `..._total` only ever grows, so it is declared a
    ;; counter: Prometheus then treats a drop as a restart rather than as data.
    (dolist (entry gauges)
      (format out "# TYPE ~A ~A~%" (car entry)
              (let ((name (car entry)))
                (if (and (> (length name) 6)
                         (string= "_total" name :start2 (- (length name) 6)))
                    "counter"
                    "gauge")))
      (format out "~A ~D~%" (car entry) (cdr entry)))))

;;;; Runtime accounting: where one thread's wall time went.
;;;;
;;;; A slow operation spent its wall time in one of three places: stopped for
;;;; a garbage collection (SBCL stops every thread), running on its own CPU,
;;;; or off the CPU -- blocked on a lock, a condition variable, a peer, a disk
;;;; read, or a host that did not schedule it. A RUNTIME SAMPLE taken before
;;;; and after tells the three apart without a profiler:
;;;;
;;;;   GcMs     the collector's run time inside the window (process-wide:
;;;;            whichever thread triggered it, every thread was stopped)
;;;;   GcCount  collections that completed inside the window
;;;;   CpuMs    this thread's own CPU time (it includes a collection that
;;;;            this thread itself triggered and ran)
;;;;
;;;; so wall - max(CpuMs, GcMs) is time off the CPU. Blocking waits that know
;;;; what they wait for add themselves through TELEMETRY-NOTE-WAIT.

(defvar *telemetry-activity-label* nil
  "A short name for what the current thread is doing, or NIL.

Bound around long-running work that other threads may wait for (an Engine
method, a sync import) so a wait can be attributed to it. NIL means the
thread's own name is the best available label.")

(defun telemetry-activity-label ()
  "The current thread's activity label, falling back to its thread name."
  (or *telemetry-activity-label*
      #+sbcl (sb-thread:thread-name sb-thread:*current-thread*)
      "unknown"))

#+sbcl
(sb-ext:defglobal **telemetry-gc-count** (list 0)
  "Completed collections since the image started, as a cons so its CAR can be
updated with SB-EXT:ATOMIC-INCF.")

#+sbcl
(defun telemetry-note-gc ()
  (sb-ext:atomic-incf (car **telemetry-gc-count**)))

#+sbcl
(pushnew 'telemetry-note-gc sb-ext:*after-gc-hooks*)

(defun telemetry-gc-count ()
  #+sbcl (car **telemetry-gc-count**)
  #-sbcl 0)

(defun telemetry-gc-run-microseconds ()
  "Total collector run time so far, in microseconds."
  #+sbcl (floor (* sb-ext:*gc-run-time* 1000000)
                internal-time-units-per-second)
  #-sbcl 0)

(defun telemetry-thread-cpu-microseconds ()
  "The calling thread's CPU time so far, in microseconds."
  #+sbcl
  (multiple-value-bind (seconds nanoseconds)
      ;; SB-UNIX::CLOCK-GETTIME is internal but has been stable since SBCL
      ;; 1.4; the exported clock id selects CLOCK_THREAD_CPUTIME_ID.
      (sb-unix::clock-gettime sb-unix:clock-thread-cputime-id)
    (+ (* seconds 1000000) (floor nanoseconds 1000)))
  #-sbcl 0)

(defun telemetry-dynamic-usage-bytes ()
  "Bytes currently allocated in the Lisp heap (live plus not yet collected)."
  #+sbcl (sb-kernel:dynamic-usage)
  #-sbcl 0)

(defstruct (telemetry-runtime-sample
            (:constructor %make-telemetry-runtime-sample
                (real gc-run gc-count cpu)))
  (real 0 :read-only t)
  (gc-run 0 :read-only t)
  (gc-count 0 :read-only t)
  (cpu 0 :read-only t))

(defun telemetry-runtime-sample ()
  "The calling thread's clocks now; see TELEMETRY-RUNTIME-FIELDS."
  (%make-telemetry-runtime-sample
   (get-internal-real-time)
   (telemetry-gc-run-microseconds)
   (telemetry-gc-count)
   (telemetry-thread-cpu-microseconds)))

(defun telemetry-runtime-fields (prefix start &key (wall-p t))
  "Fields describing the window since START, a TELEMETRY-RUNTIME-SAMPLE taken
on the calling thread: PREFIXMs (wall, unless WALL-P is false), PREFIXGcMs,
PREFIXGcCount and PREFIXCpuMs, in whole milliseconds."
  (let ((now (telemetry-runtime-sample)))
    (flet ((name (suffix) (concatenate 'string prefix suffix))
           (ms (microseconds) (round microseconds 1000)))
      (append
       (when wall-p
         (list (cons (name "Ms")
                     (round (* 1000 (- (telemetry-runtime-sample-real now)
                                       (telemetry-runtime-sample-real start)))
                            internal-time-units-per-second))))
       (list (cons (name "GcMs")
                   (ms (- (telemetry-runtime-sample-gc-run now)
                          (telemetry-runtime-sample-gc-run start))))
             (cons (name "GcCount")
                   (- (telemetry-runtime-sample-gc-count now)
                      (telemetry-runtime-sample-gc-count start)))
             (cons (name "CpuMs")
                   (ms (- (telemetry-runtime-sample-cpu now)
                          (telemetry-runtime-sample-cpu start)))))))))

(defvar *telemetry-wait-accounting* nil
  "NIL, or an alist cell list (KIND . MICROSECONDS) the current thread's
attributed blocking waits accumulate into; see TELEMETRY-CALL-WITH-WAIT-ACCOUNTING.")

(defun telemetry-note-wait (kind microseconds &optional waited-for)
  "Add MICROSECONDS of blocking wait of KIND (a string) to the current
thread's accounting, when one is active. WAITED-FOR, a string, names what
the wait was for (who held the lock); it is reported in KINDWaitedFor. Returns
NIL."
  (let ((accounting *telemetry-wait-accounting*))
    (when accounting
      (let ((entry (assoc kind (cdr accounting) :test #'string=)))
        (unless entry
          (setf entry (list kind 0 '()))
          (push entry (cdr accounting)))
        (incf (second entry) microseconds)
        (when waited-for
          (push waited-for (third entry))))))
  nil)

(defun telemetry-call-with-accounted-wait (kind thunk)
  "Call THUNK and add its wall time to the current accounting under KIND."
  (if *telemetry-wait-accounting*
      (let ((start (get-internal-real-time)))
        (unwind-protect (funcall thunk)
          (telemetry-note-wait
           kind
           (floor (* 1000000 (- (get-internal-real-time) start))
                  internal-time-units-per-second))))
      (funcall thunk)))

(defun telemetry-call-with-wait-accounting (thunk)
  "Call THUNK with fresh wait accounting and return its values. Read the waits
with TELEMETRY-WAIT-FIELDS before THUNK returns."
  (let ((*telemetry-wait-accounting* (list :waits)))
    (funcall thunk)))

(defun telemetry-wait-fields ()
  "The current accounting as fields: KINDWaitMs for every kind that waited, and
KINDWaitedFor (the WAITED-FOR strings, oldest first, joined by spaces) when
any were given."
  (let ((accounting *telemetry-wait-accounting*))
    (when accounting
      (loop for (kind microseconds waited-for) in (reverse (cdr accounting))
            collect (cons (concatenate 'string kind "WaitMs")
                          (round microseconds 1000))
            when waited-for
              collect (cons (concatenate 'string kind "WaitedFor")
                            (format nil "~{~A~^ ~}" (reverse waited-for)))))))
