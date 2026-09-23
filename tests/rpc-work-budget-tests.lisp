(in-package #:ethereum-lisp.test)

;;;; Work budgets that refuse a request before its work is done.
;;;;
;;;; Each budget is asserted from both sides: the over-budget request is refused
;;;; without running the work (counted through the request guard, which every
;;;; executed batch item passes), and an in-budget request of the same shape
;;;; still succeeds, so a budget that refused everything could not pass.

(defun budget-test-context (&key (counter (list 0)))
  "An RPC context over a small canonical chain whose block 3 carries two logs.
COUNTER's car counts the batch items that actually ran."
  (let* ((store (make-engine-payload-memory-store))
         (genesis (make-block
                   :header (make-block-header :number 0 :timestamp 0
                                              :gas-limit 30000000
                                              :base-fee-per-gas 7))))
    (engine-payload-store-put-block store genesis :state-available-p t)
    (read-view-test-extend store genesis 4 :transactions-at 3)
    (ethereum-lisp.rpc:make-rpc-context
     store (make-chain-config :chain-id *read-view-test-chain-id*)
     :request-guard-function (lambda (thunk)
                               (incf (car counter))
                               (funcall thunk)))))

(defun budget-test-batch (ids &key notification-at)
  "A JSON batch of web3_clientVersion calls with IDS; the item at index
NOTIFICATION-AT carries no id."
  (format nil "[~{~A~^,~}]"
          (loop for id in ids
                for index from 0
                collect (if (eql index notification-at)
                            "{\"jsonrpc\":\"2.0\",\"method\":\"web3_clientVersion\",\"params\":[]}"
                            (format nil "{\"jsonrpc\":\"2.0\",\"id\":~D,\"method\":\"web3_clientVersion\",\"params\":[]}"
                                    id)))))

(defun budget-test-field (object &rest path)
  (loop for name in path
        do (setf object (cdr (assoc name object :test #'string=))))
  object)

(deftest rpc-oversized-batch-is-refused-whole-before-any-item-runs
  ;; geth 38271784 rpc/handler.go:209 and :284-296: one -32600 "batch too
  ;; large" inside a one-element batch, carrying the FIRST CALL's id (the
  ;; leading notification has none), and no item runs.
  (let* ((counter (list 0))
         (context (budget-test-context :counter counter))
         (ethereum-lisp.rpc::*rpc-batch-request-limit* 3)
         (refused (parse-json (ethereum-lisp.rpc:rpc-handle-request-json
                               (budget-test-batch '(10 11 12 13)
                                                  :notification-at 0)
                               context))))
    (is (listp refused))
    (is (= 1 (length refused)))
    (is (eql 11 (budget-test-field (first refused) "id")))
    (is (eql -32600 (budget-test-field (first refused) "error" "code")))
    (is (equal "batch too large"
               (budget-test-field (first refused) "error" "message")))
    (is (zerop (car counter)))
    ;; Positive control: at the limit every item runs and answers.
    (let ((answered (parse-json (ethereum-lisp.rpc:rpc-handle-request-json
                                 (budget-test-batch '(20 21 22)) context))))
      (is (= 3 (length answered)))
      (is (every (lambda (response) (budget-test-field response "result"))
                 answered))
      (is (= 3 (car counter))))))

(deftest rpc-batch-response-budget-stops-running-items-once-spent
  ;; geth rpc/handler.go:262-268: responses are counted as they are produced;
  ;; the one that crosses the limit is still sent, and every later call is
  ;; answered -32003 "response too large" with its own id, WITHOUT running.
  ;; A later notification gets no response at all.
  (let* ((counter (list 0))
         (context (budget-test-context :counter counter))
         (one (length (ethereum-lisp.rpc:rpc-handle-request-json
                       (format nil "{\"jsonrpc\":\"2.0\",\"id\":30,\"method\":\"web3_clientVersion\",\"params\":[]}")
                       context))))
    (setf (car counter) 0)
    (let* ((ethereum-lisp.rpc::*rpc-batch-response-max-size* (+ (* 2 one) 1))
           (responses (parse-json (ethereum-lisp.rpc:rpc-handle-request-json
                                   (budget-test-batch '(30 31 32 33 34 35)
                                                      :notification-at 4)
                                   context))))
      (is (= 5 (length responses)))
      (is (equal '(30 31 32 33 35)
                 (mapcar (lambda (response) (budget-test-field response "id"))
                         responses)))
      (is (every (lambda (response) (budget-test-field response "result"))
                 (subseq responses 0 3)))
      (is (every (lambda (response)
                   (and (eql -32003 (budget-test-field response "error" "code"))
                        (equal "response too large"
                               (budget-test-field response "error" "message"))))
                 (subseq responses 3)))
      (is (= 3 (car counter))))
    ;; Positive control: with room for all of them, every item runs.
    (setf (car counter) 0)
    (let ((responses (parse-json (ethereum-lisp.rpc:rpc-handle-request-json
                                  (budget-test-batch '(40 41 42 43 44))
                                  context))))
      (is (= 5 (length responses)))
      (is (every (lambda (response) (budget-test-field response "result"))
                 responses))
      (is (= 5 (car counter))))))

(defun budget-test-get-logs (context filter-json)
  (parse-json
   (ethereum-lisp.rpc:rpc-handle-request-json
    (format nil "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"eth_getLogs\",\"params\":[~A]}"
            filter-json)
    context)))

(deftest eth-get-logs-result-budget-refuses-before-answering
  ;; Our policy (geth has no result bound): more logs than
  ;; *ETH-RPC-MAX-LOG-RESULTS* is EIP-1474's -32005 limit exceeded.
  (let ((context (budget-test-context))
        (filter "{\"fromBlock\":\"0x0\",\"toBlock\":\"latest\"}"))
    (let* ((ethereum-lisp.public-api::*eth-rpc-max-log-results* 1)
           (refused (budget-test-get-logs context filter)))
      (is (eql -32005 (budget-test-field refused "error" "code")))
      (is (equal "query returned more than 1 results"
                 (budget-test-field refused "error" "message"))))
    ;; Positive control: at the bound the same query answers both logs.
    (let* ((ethereum-lisp.public-api::*eth-rpc-max-log-results* 2)
           (answered (budget-test-get-logs context filter)))
      (is (= 2 (length (budget-test-field answered "result")))))))

(deftest eth-log-filters-refuse-more-addresses-than-geth-log-query-limit
  ;; geth 38271784 eth/filters/api.go:451-454 (eth_getLogs) and
  ;; filter_system.go:301-304 (filters, subscriptions): LogQueryLimit 1000.
  (let* ((context (budget-test-context))
         (addresses
           (lambda (count)
             (format nil "[~{\"0x~40,'0X\"~^,~}]"
                     (loop for index from 1 to count collect index))))
         (over (format nil "{\"fromBlock\":\"0x0\",\"toBlock\":\"latest\",\"address\":~A}"
                       (funcall addresses 1001)))
         (at (format nil "{\"fromBlock\":\"0x0\",\"toBlock\":\"latest\",\"address\":~A}"
                     (funcall addresses 1000))))
    (let ((refused (budget-test-get-logs context over)))
      (is (eql -32000 (budget-test-field refused "error" "code")))
      (is (equal "exceed max addresses or topics per search position"
                 (budget-test-field refused "error" "message"))))
    (let ((refused (parse-json
                    (ethereum-lisp.rpc:rpc-handle-request-json
                     (format nil "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"eth_newFilter\",\"params\":[~A]}"
                             over)
                     context))))
      (is (eql -32000 (budget-test-field refused "error" "code"))))
    ;; Positive control: exactly the limit is an ordinary (empty) answer.
    (let ((answered (budget-test-get-logs context at)))
      (is (null (budget-test-field answered "error")))
      (is (assoc "result" answered :test #'string=)))))
