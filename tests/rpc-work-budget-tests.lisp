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

;;;; The --rpc.* budget flags.
;;;;
;;;; geth's --rpc.gascap, --rpc.evmtimeout, --rpc.txfeecap,
;;;; --rpc.batch-request-limit and --rpc.batch-response-max-size were refused
;;;; as "not configurable": the node ran on fixed defaults. Each now reaches
;;;; every listener's RPC context and is checked before the work it bounds.

(defparameter *budget-test-contract*
  (address-from-hex "0x00000000000000000000000000000000000000aa"))

(defparameter *budget-test-sender-key* 1)

(defparameter *budget-test-genesis-path*
  "tests/fixtures/execution-spec-tests/phase-a-shanghai-genesis.json"
  "+DEVNET-CLI-GENESIS-FIXTURE+, which the CLI support files define only
after this file is compiled.")

(defun budget-test-state-context (code &rest context-options)
  "An RPC context over one Shanghai block whose state holds CODE at
*BUDGET-TEST-CONTRACT* and funds key 1's address."
  (let* ((store (make-engine-payload-memory-store))
         (config (make-chain-config
                  :chain-id *read-view-test-chain-id* :homestead-block 0
                  :eip150-block 0 :eip155-block 0 :eip158-block 0
                  :byzantium-block 0 :constantinople-block 0
                  :petersburg-block 0 :istanbul-block 0 :berlin-block 0
                  :london-block 0 :shanghai-time 0))
         (state (make-state-db))
         (block (make-block
                 :header (make-block-header
                          :number 1 :timestamp 12 :gas-limit 30000000
                          :base-fee-per-gas 7))))
    (state-db-set-account state (fixture-private-key-address
                                 *budget-test-sender-key*)
                          (make-state-account :nonce 0
                                              :balance (expt 10 22)))
    (state-db-set-code state *budget-test-contract* (hex-to-bytes code))
    (setf (block-header-state-root (block-header block)) (state-db-root state))
    (engine-payload-store-put-block store block :state-available-p t
                                                :canonicalize-p t)
    (commit-state-db-to-chain-store store (block-hash block) state)
    (apply #'ethereum-lisp.rpc:make-rpc-context store config context-options)))

(defun budget-test-call (context method params-json)
  (parse-json
   (ethereum-lisp.rpc:rpc-handle-request-json
    (format nil "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"~A\",\"params\":~A}"
            method params-json)
    context)))

(defun budget-test-gas-left (context &optional gas)
  "The GAS a call to the gas-reporting contract sees, as an integer."
  (let ((answer (budget-test-call
                 context "eth_call"
                 (format nil "[{\"to\":\"~A\"~@[,\"gas\":\"~A\"~]},\"latest\"]"
                         (address-to-hex *budget-test-contract*)
                         (and gas (quantity-to-hex gas))))))
    (hex-to-quantity (budget-test-field answer "result"))))

(deftest rpc-budget-flags-are-parsed-and-reach-every-listener
  ;; RED on 4b9f20b2: each of these options was refused with "is not
  ;; configurable in this client".
  (let* ((options (ethereum-lisp.cli::devnet-cli-options
                   (list "devnet" "--genesis" *budget-test-genesis-path*
                         "--rpc.gascap" "100000"
                         "--rpc.evmtimeout" "2s"
                         "--rpc.txfeecap" "0.5"
                         "--rpc.batch-request-limit" "2"
                         "--rpc.batch-response-max-size" "0")))
         (budgets (ethereum-lisp.cli::devnet-cli-rpc-budgets options)))
    (is (= 100000 (ethereum-lisp.rpc:rpc-budgets-gas-cap budgets)))
    (is (= 2 (ethereum-lisp.rpc:rpc-budgets-evm-timeout-seconds budgets)))
    (is (= (/ (expt 10 18) 2)
           (ethereum-lisp.rpc:rpc-budgets-tx-fee-cap-wei budgets)))
    (is (= 2 (ethereum-lisp.rpc:rpc-budgets-batch-request-limit budgets)))
    (is (= 0 (ethereum-lisp.rpc:rpc-budgets-batch-response-max-size budgets)))
    ;; No flag, no budgets: the defaults stay in force.
    (is (null (ethereum-lisp.cli::devnet-cli-rpc-budgets
               (ethereum-lisp.cli::devnet-cli-options
                (list "devnet" "--genesis" *budget-test-genesis-path*)))))
    (signals error (ethereum-lisp.cli::devnet-cli-options
                    (list "devnet" "--genesis" *budget-test-genesis-path*
                          "--rpc.txfeecap" "one")))
    ;; The Engine and public listeners, and a WebSocket connection, all serve
    ;; with them.
    (let ((node (ethereum-lisp.cli:make-devnet-node
                 :genesis-json *eth-sync-paris-genesis-json*
                 :port 0 :public-port 0 :rpc-budgets budgets)))
      (dolist (context
               (list (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                      (ethereum-lisp.cli:devnet-node-service node))
                     (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                      (ethereum-lisp.cli:devnet-node-public-service node))
                     (ethereum-lisp.cli::devnet-ws-connection-context
                      node (ethereum-lisp.public-api::make-eth-rpc-subscription-registry))))
        (is (eq budgets (ethereum-lisp.rpc:rpc-context-budgets context)))))))

(deftest rpc-gas-cap-budget-lowers-the-gas-a-call-gets
  ;; GAS PUSH1 0 MSTORE PUSH1 32 PUSH1 0 RETURN: the call returns the gas it
  ;; had, the call's gas less 21,000 intrinsic and 2 for GAS. geth's
  ;; CallDefaults (internal/ethapi/transaction_args.go at 38271784): a call
  ;; without gas gets the cap, and one asking for more is lowered to it.
  (let ((code "5a60005260206000f3"))
    ;; The default cap, 50,000,000.
    (is (= (- 50000000 21002)
           (budget-test-gas-left (budget-test-state-context code))))
    (let ((capped (budget-test-state-context
                   code :budgets (ethereum-lisp.rpc:make-rpc-budgets
                                  :gas-cap 100000))))
      (is (= (- 100000 21002) (budget-test-gas-left capped)))
      (is (= (- 100000 21002) (budget-test-gas-left capped 200000)))
      ;; Under the cap a call keeps what it asked for.
      (is (= (- 60000 21002) (budget-test-gas-left capped 60000))))
    ;; 0 is no cap: a call may ask for more than the default cap.
    (is (= (- 100000000 21002)
           (budget-test-gas-left
            (budget-test-state-context
             code :budgets (ethereum-lisp.rpc:make-rpc-budgets :gas-cap 0))
            100000000)))))

(deftest rpc-evm-timeout-budget-stops-a-call-that-runs-too-long
  ;; JUMPDEST PUSH1 0 JUMP: a loop that only gas ends. With ten billion gas
  ;; and no gas cap it would run for minutes; the one-second deadline ends it
  ;; with geth's -32000 "execution aborted (timeout = 1s)".
  (let* ((code "5b600056")
         (params (lambda (gas)
                   (format nil "[{\"to\":\"~A\",\"gas\":\"~A\"},\"latest\"]"
                           (address-to-hex *budget-test-contract*)
                           (quantity-to-hex gas))))
         (context (budget-test-state-context
                   code :budgets (ethereum-lisp.rpc:make-rpc-budgets
                                  :gas-cap 0 :evm-timeout-seconds 1)))
         (started (get-internal-real-time))
         (answer (budget-test-call context "eth_call"
                                   (funcall params 10000000000)))
         (seconds (/ (- (get-internal-real-time) started)
                     internal-time-units-per-second)))
    (is (eql -32000 (budget-test-field answer "error" "code")))
    (is (equal "execution aborted (timeout = 1s)"
               (budget-test-field answer "error" "message")))
    (is (< seconds 10))
    ;; Positive control: a call that ends on its own before the deadline
    ;; (out of gas after 200,000) answers as it always did, not as a timeout.
    (let ((answer (budget-test-call context "eth_call" (funcall params 200000))))
      (is (budget-test-field answer "error"))
      (is (not (search "timeout" (or (budget-test-field answer "error" "message")
                                     "")))))))

(deftest rpc-tx-fee-cap-budget-refuses-before-the-pool
  ;; geth's checkTxFee (internal/ethapi/api.go at 38271784): gas price times
  ;; gas above --rpc.txfeecap (default 1 ether) is refused before the pool.
  (let* ((transaction (fixture-sign-legacy-transaction
                       (make-legacy-transaction
                        :nonce 0 :gas-price (expt 10 14) :gas-limit 21000
                        :to *budget-test-contract* :value 1)
                       *budget-test-sender-key* *read-view-test-chain-id*))
         (params (format nil "[\"~A\"]"
                         (bytes-to-hex (transaction-encoding transaction)))))
    ;; 2.1 ether against the default 1 ether cap.
    (let* ((context (budget-test-state-context "00"))
           (answer (budget-test-call context "eth_sendRawTransaction" params)))
      (is (eql -32000 (budget-test-field answer "error" "code")))
      (is (equal "tx fee (2.10 ether) exceeds the configured cap (1.00 ether)"
                 (budget-test-field answer "error" "message")))
      (is (zerop (length (ethereum-lisp.txpool:engine-payload-store-pending-transactions
                          (ethereum-lisp.rpc:rpc-context-store context))))))
    ;; A lower configured cap refuses it too; 0 (no cap) and a 3 ether cap
    ;; pass it to the pool, which admits it.
    (let ((answer (budget-test-call
                   (budget-test-state-context
                    "00" :budgets (ethereum-lisp.rpc:make-rpc-budgets
                                   :tx-fee-cap-wei (expt 10 17)))
                   "eth_sendRawTransaction" params)))
      (is (search "exceeds the configured cap (0.10 ether)"
                  (budget-test-field answer "error" "message"))))
    (dolist (cap (list 0 (* 3 (expt 10 18))))
      (let ((answer (budget-test-call
                     (budget-test-state-context
                      "00" :budgets (ethereum-lisp.rpc:make-rpc-budgets
                                     :tx-fee-cap-wei cap))
                     "eth_sendRawTransaction" params)))
        (is (equal (hash32-to-hex (transaction-hash transaction))
                   (budget-test-field answer "result")))))))

(deftest rpc-batch-budgets-come-from-the-listener-context
  ;; --rpc.batch-request-limit and --rpc.batch-response-max-size through a
  ;; context's budgets, and 0 as geth reads it: no limit.
  (flet ((context (&rest budget-options)
           (let ((context (budget-test-context)))
             (setf (ethereum-lisp.rpc::rpc-context-budgets context)
                   (apply #'ethereum-lisp.rpc:make-rpc-budgets budget-options))
             context))
         (answer (context ids)
           (parse-json (ethereum-lisp.rpc:rpc-handle-request-json
                        (budget-test-batch ids) context))))
    (let ((refused (answer (context :batch-request-limit 2) '(1 2 3))))
      (is (= 1 (length refused)))
      (is (eql -32600 (budget-test-field (first refused) "error" "code"))))
    (is (= 2 (length (answer (context :batch-request-limit 2) '(1 2)))))
    ;; 0: a batch past the 1,000-item default runs whole.
    (let ((ids (loop for id from 1 to 1001 collect id)))
      (is (eql -32600 (budget-test-field (first (answer (context) ids))
                                         "error" "code")))
      (is (= 1001 (length (answer (context :batch-request-limit 0) ids)))))
    ;; A 1-byte response budget answers the first item and refuses the rest;
    ;; 0 answers them all.
    (let ((responses (answer (context :batch-response-max-size 1) '(1 2 3))))
      (is (budget-test-field (first responses) "result"))
      (is (every (lambda (response)
                   (eql -32003 (budget-test-field response "error" "code")))
                 (rest responses))))
    (is (every (lambda (response) (budget-test-field response "result"))
               (answer (context :batch-response-max-size 0) '(1 2 3))))))

#+sbcl
(deftest websocket-batch-honours-the-rpc-batch-request-limit
  (:layer :integration :module :devnet :requires-local-sockets t)
  ;; The budgets reach a live WebSocket connection, not only its context.
  (wsh-call-with-server
   (lambda (node port)
     (declare (ignore node))
     (multiple-value-bind (stream socket) (wsh-connect port)
       (unwind-protect
            (progn
              (wsh-send stream (budget-test-batch '(1 2)))
              (is (search "batch too large" (wsh-read-text stream)))
              ;; Positive control: a batch at the limit answers.
              (wsh-send stream (budget-test-batch '(3)))
              (let ((reply (wsh-read-text stream)))
                (is (search "\"id\":3" reply))
                (is (search "\"result\"" reply))))
         (ignore-errors (sb-bsd-sockets:socket-close socket)))))
   :rpc-budgets (ethereum-lisp.rpc:make-rpc-budgets :batch-request-limit 1)))
