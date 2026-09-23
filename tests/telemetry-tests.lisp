(in-package #:ethereum-lisp.test)

(deftest telemetry-disabled-sink-drops-events
  (is (null (ethereum-lisp.telemetry:telemetry-log
             :info
             "rpc.start")))
  (is (null (ethereum-lisp.telemetry:telemetry-metric
             "rpc.requests"
             1))))

(deftest memory-telemetry-sink-records-structured-events
  (let ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink)))
    (is (typep
         (ethereum-lisp.telemetry:telemetry-log
          :info
          "rpc.start"
          :sink sink
          :fields '(("method" . "eth_chainId")))
         'ethereum-lisp.telemetry:telemetry-event))
    (ethereum-lisp.telemetry:telemetry-metric
     "rpc.requests"
     1
     :sink sink
     :fields '(("method" . "eth_chainId")
               ("status" . "ok")))
    (let ((events (ethereum-lisp.telemetry:telemetry-events sink)))
      (is (= 2 (length events)))
      (is (eq :log
              (ethereum-lisp.telemetry:telemetry-event-kind
               (first events))))
      (is (string= "rpc.start"
                   (ethereum-lisp.telemetry:telemetry-event-name
                    (first events))))
      (is (eq :info
              (ethereum-lisp.telemetry:telemetry-event-value
               (first events))))
      (is (equal '(("method" . "eth_chainId"))
                 (ethereum-lisp.telemetry:telemetry-event-fields
                  (first events))))
      (is (eq :metric
              (ethereum-lisp.telemetry:telemetry-event-kind
               (second events))))
      (is (string= "rpc.requests"
                   (ethereum-lisp.telemetry:telemetry-event-name
                    (second events))))
      (is (= 1
             (ethereum-lisp.telemetry:telemetry-event-value
              (second events)))))))

(deftest stream-telemetry-sink-writes-readable-events
  (let* ((output (make-string-output-stream))
         (sink (ethereum-lisp.telemetry:make-stream-telemetry-sink
                :stream output)))
    (is (typep
         (ethereum-lisp.telemetry:telemetry-metric
          "service.connections"
          2
          :sink sink
          :fields '(("endpoint" . "localhost:8551")))
         'ethereum-lisp.telemetry:telemetry-event))
    (let ((record (read-from-string (get-output-stream-string output))))
      (is (eq :metric (getf record :kind)))
      (is (string= "service.connections" (getf record :name)))
      (is (= 2 (getf record :value)))
      (is (equal '(("endpoint" . "localhost:8551"))
                 (getf record :fields))))))

#+sbcl
(deftest stream-telemetry-sink-serializes-concurrent-writes
  (let* ((output (make-string-output-stream))
         (sink (ethereum-lisp.telemetry:make-stream-telemetry-sink
                :stream output))
         (threads
           (loop for worker below 4
                 collect
                 (sb-thread:make-thread
                  (lambda ()
                    (loop for index below 25
                          do
                          (ethereum-lisp.telemetry:telemetry-log
                           :info
                           "worker.event"
                           :sink sink
                           :fields
                           `(("worker" . ,(write-to-string worker))
                             ("index" . ,(write-to-string index))))))
                  :name "ethereum-lisp-telemetry-writer"))))
    (dolist (thread threads)
      (sb-thread:join-thread thread))
    (let ((input (make-string-input-stream
                  (get-output-stream-string output)))
          (records nil))
      (loop for record = (read input nil :eof)
            until (eq record :eof)
            do (push record records))
      (is (= 100 (length records)))
      (dolist (record records)
        (is (eq :log (getf record :kind)))
        (is (string= "worker.event" (getf record :name)))
        (is (eq :info (getf record :value)))
        (is (assoc "worker" (getf record :fields) :test #'string=))
        (is (assoc "index" (getf record :fields) :test #'string=))))))

(deftest telemetry-dynamic-sink-provides-default-backend
  (let ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink)))
    (let ((ethereum-lisp.telemetry:*telemetry-sink* sink))
      (ethereum-lisp.telemetry:telemetry-log :debug "service.ready")
      (ethereum-lisp.telemetry:telemetry-metric "service.connections" 0))
    (let ((events (ethereum-lisp.telemetry:telemetry-events sink)))
      (is (= 2 (length events)))
      (is (string= "service.ready"
                   (ethereum-lisp.telemetry:telemetry-event-name
                    (first events))))
      (is (string= "service.connections"
                   (ethereum-lisp.telemetry:telemetry-event-name
                    (second events)))))))

(deftest telemetry-fields-must-be-a-list
  (signals error
    (ethereum-lisp.telemetry:telemetry-log
     :info
     "bad.fields"
     :fields "not-a-field-list")))

(deftest stream-telemetry-sink-requires-output-stream
  (signals error
    (ethereum-lisp.telemetry:make-stream-telemetry-sink
     :stream (make-string-input-stream ""))))

(deftest telemetry-runtime-fields-tell-gc-cpu-and-waiting-apart
  ;; The Engine request log splits a slow phase into collection, own CPU and
  ;; time off the CPU (npExecuteGcMs / npExecuteCpuMs against npExecuteMs).
  ;; Each branch has its own control: a forced collection shows up as GC and
  ;; not as waiting, a sleep as waiting and not as CPU, a busy loop as CPU.
  (flet ((fields-of (thunk)
           (let ((start (ethereum-lisp.telemetry:telemetry-runtime-sample)))
             (funcall thunk)
             (ethereum-lisp.telemetry:telemetry-runtime-fields "p" start)))
         (field (name fields) (cdr (assoc name fields :test #'string=))))
    (let ((gc (fields-of (lambda () #+sbcl (sb-ext:gc :full t))))
          (sleep (fields-of (lambda () (sleep 0.3))))
          (busy (fields-of
                 (lambda ()
                   (let ((deadline (+ (get-internal-real-time)
                                      (* 3/10 internal-time-units-per-second)))
                         (sink 0))
                     (loop while (< (get-internal-real-time) deadline)
                           do (setf sink (logxor sink (random 1000))))
                     sink)))))
      (is (equal '("pMs" "pGcMs" "pGcCount" "pCpuMs") (mapcar #'car gc)))
      #+sbcl (is (<= 1 (field "pGcCount" gc)))
      (is (<= 280 (field "pMs" sleep)))
      (is (< (field "pCpuMs" sleep) 100))
      (is (<= 100 (field "pCpuMs" busy)))
      (is (= 0 (field "pGcMs" sleep))))))

(deftest telemetry-wait-accounting-sums-kinds-and-names-what-was-waited-for
  (is (null (let ((ethereum-lisp.telemetry:*telemetry-wait-accounting* nil))
              (ethereum-lisp.telemetry:telemetry-note-wait "guard" 5000)
              (ethereum-lisp.telemetry:telemetry-wait-fields))))
  (ethereum-lisp.telemetry:telemetry-call-with-wait-accounting
   (lambda ()
     (ethereum-lisp.telemetry:telemetry-note-wait "guard" 1500 "a:1")
     (ethereum-lisp.telemetry:telemetry-note-wait "guard" 2500 "b:2")
     (ethereum-lisp.telemetry:telemetry-call-with-accounted-wait
      "peer" (lambda () (sleep 0.05)))
     (let ((fields (ethereum-lisp.telemetry:telemetry-wait-fields)))
       (is (equal '("guardWaitMs" "guardWaitedFor" "peerWaitMs")
                  (mapcar #'car fields)))
       (is (= 4 (cdr (first fields))))
       (is (string= "a:1 b:2" (cdr (second fields))))
       (is (<= 45 (cdr (third fields))))))))
