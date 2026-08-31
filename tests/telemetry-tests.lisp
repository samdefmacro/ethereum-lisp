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

(deftest stream-telemetry-sink-batches-backing-stream-flushes
  (let* ((output (make-string-output-stream))
         (sink (ethereum-lisp.telemetry:make-stream-telemetry-sink
                :stream output :flush-batch-size 2)))
    (ethereum-lisp.telemetry:telemetry-log :info "batch.first" :sink sink)
    (is (string= "" (get-output-stream-string output)))
    (ethereum-lisp.telemetry:telemetry-log :info "batch.second" :sink sink)
    (let ((records (make-string-input-stream
                    (get-output-stream-string output))))
      (is (string= "batch.first" (getf (read records) :name)))
      (is (string= "batch.second" (getf (read records) :name)))
      (is (eq :eof (read records nil :eof))))))

(deftest stream-telemetry-sink-flushes-urgent-and-explicit-events
  (let* ((output (make-string-output-stream))
         (sink (ethereum-lisp.telemetry:make-stream-telemetry-sink
                :stream output :flush-batch-size 64)))
    (ethereum-lisp.telemetry:telemetry-log :info "before.warning" :sink sink)
    (is (string= "" (get-output-stream-string output)))
    (ethereum-lisp.telemetry:telemetry-log :warning "warning" :sink sink)
    (let ((flushed (get-output-stream-string output)))
      (is (search "before.warning" flushed))
      (is (search "warning" flushed)))
    (ethereum-lisp.telemetry:telemetry-metric "pending.metric" 1 :sink sink)
    (is (string= "" (get-output-stream-string output)))
    (ethereum-lisp.telemetry:flush-stream-telemetry-sink sink)
    (is (search "pending.metric" (get-output-stream-string output)))))

(deftest stream-telemetry-sink-rejects-invalid-flush-batch-size
  (signals error
    (ethereum-lisp.telemetry:make-stream-telemetry-sink
     :stream (make-string-output-stream) :flush-batch-size 0)))

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
