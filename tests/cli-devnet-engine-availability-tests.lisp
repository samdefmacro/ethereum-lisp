(in-package #:ethereum-lisp.test)

;;;; Engine availability while a background task holds the node's store guard.
;;;;
;;;; Hoodi (b5161312, 2026-09-24 01:27-02:25Z): peer-session threads held the
;;;; store guard for 20-133 s at a time, and from 01:50Z one hold never ended.
;;;; Every engine_newPayload and engine_forkchoiceUpdated waited for it until
;;;; the 30 s HTTP deadline, and Lighthouse's engine_exchangeCapabilities
;;;; timed out every second although it reads no store state: the Engine
;;;; service guarded every method except eth_syncing and engine_getBlobsV3.
;;;; A parked request also keeps its connection's worker slot, so once the 32
;;;; slots are parked a new connection is not even accepted.
;;;;
;;;; These tests drive the node's real Engine service over a loopback socket.
;;;; A thread holds the guard the way a peer session does; Engine requests are
;;;; sent on fresh connections, as a CL whose previous request timed out does.

(defparameter +devnet-engine-availability-hold-seconds+ 4
  "How long the simulated background holder keeps the store guard.")

#+sbcl
(defun devnet-engine-availability-http (port body)
  "POST BODY to 127.0.0.1:PORT on a new connection and read the whole reply.
Returns a plist: :MS (elapsed milliseconds), :RESPONSE (the parsed JSON-RPC
reply or NIL) and :ERROR (a description, or NIL)."
  (let ((started-at (get-internal-real-time))
        (socket (make-instance 'sb-bsd-sockets:inet-socket
                               :type :stream :protocol :tcp)))
    (flet ((elapsed-ms ()
             (round (* 1000 (- (get-internal-real-time) started-at))
                    internal-time-units-per-second)))
      (handler-case
          (unwind-protect
               (progn
                 (sb-bsd-sockets:socket-connect
                  socket (sb-bsd-sockets:make-inet-address "127.0.0.1") port)
                 (let ((stream (sb-bsd-sockets:socket-make-stream
                                socket :input t :output t
                                       :element-type 'character
                                       :external-format :utf-8
                                       :buffering :full
                                       :timeout 20)))
                   (format stream
                           "POST / HTTP/1.1~C~CHost: localhost~C~CContent-Type: application/json~C~CConnection: close~C~CContent-Length: ~D~C~C~C~C~A"
                           #\Return #\Newline #\Return #\Newline
                           #\Return #\Newline #\Return #\Newline
                           (length body)
                           #\Return #\Newline #\Return #\Newline
                           body)
                   (finish-output stream)
                   (let* ((reply (with-output-to-string (out)
                                   (loop for char = (read-char stream nil nil)
                                         while char
                                         do (write-char char out))))
                          (boundary (search (format nil "~C~C~C~C"
                                                    #\Return #\Newline
                                                    #\Return #\Newline)
                                            reply)))
                     (list :ms (elapsed-ms)
                           :response (and boundary
                                          (parse-json
                                           (subseq reply (+ boundary 4))))
                           :error (and (null boundary) "no HTTP reply")))))
            (ignore-errors (sb-bsd-sockets:socket-close socket)))
        (serious-condition (condition)
          (list :ms (elapsed-ms) :response nil
                :error (princ-to-string condition)))))))

#+sbcl
(defun devnet-engine-availability-send (port request)
  "Send REQUEST (a JSON-RPC object) on its own thread; return the thread."
  (let ((body (json-encode request)))
    (sb-thread:make-thread
     (lambda ()
       ;; A condition here must not kill the suite process.
       (handler-case (devnet-engine-availability-http port body)
         (serious-condition (condition)
           (list :ms nil :response nil :error (princ-to-string condition)))))
     :name "engine-availability-client")))

(defun devnet-engine-availability-call (id method params)
  (list (cons "jsonrpc" "2.0") (cons "id" id)
        (cons "method" method) (cons "params" params)))

(defun devnet-engine-availability-status (result)
  "The payload status of a newPayload or forkchoiceUpdated reply, or NIL."
  (let* ((response (getf result :response))
         (value (and response (fixture-object-field response "result"))))
    (and value
         (if (fixture-field-present-p value "payloadStatus")
             (fixture-object-field
              (fixture-object-field value "payloadStatus") "status")
             (fixture-object-field value "status")))))

(defun devnet-engine-availability-answered-p (result)
  "True when RESULT carries a JSON-RPC result, not an error or nothing."
  (let ((response (getf result :response)))
    (and response (fixture-field-present-p response "result"))))

(defun devnet-engine-availability-set-global (symbol value)
  "Set SYMBOL's global value and return a thunk that restores it. The Engine
service reads these on its own worker threads, so a LET would not reach it."
  (let ((bound-p (boundp symbol))
        (old (and (boundp symbol) (symbol-value symbol))))
    (setf (symbol-value symbol) value)
    (lambda ()
      (if bound-p
          (setf (symbol-value symbol) old)
          (makunbound symbol)))))

#+sbcl
(defun devnet-engine-availability-run (fixed-p genesis-json block)
  "Hold NODE's store guard for +DEVNET-ENGINE-AVAILABILITY-HOLD-SECONDS+ on a
background thread and send Engine requests over HTTP while it is held.

FIXED-P runs the shipped policy with a one-second Engine budget; otherwise the
b5161312 policy is restored (no budget, only eth_syncing and
engine_getBlobsV3 unguarded) as the positive control. Returns a plist of the
per-request results."
  (let* ((restores
           (cons
            (devnet-engine-availability-set-global
             'ethereum-lisp.cli::*devnet-engine-guard-busy-seconds*
             (and fixed-p 1))
            ;; The fixed run keeps the shipped method list.
            (unless fixed-p
              (list
               (devnet-engine-availability-set-global
                'ethereum-lisp.cli::*devnet-engine-guard-free-methods*
                (list "eth_syncing" "engine_getBlobsV3"))))))
         (node (ethereum-lisp.cli:make-devnet-node
                :genesis-json genesis-json :port 0))
         (service (ethereum-lisp.cli:devnet-node-service node))
         (genesis-hash
           (block-hash (ethereum-lisp.cli:devnet-node-genesis-block node)))
         (listener (make-engine-rpc-http-socket-listener service))
         (endpoint (engine-rpc-http-listener-endpoint listener))
         (port (parse-integer endpoint
                              :start (1+ (position #\: endpoint :from-end t))))
         (stop-p nil)
         (server
           (sb-thread:make-thread
            (lambda ()
              ;; A condition here must not kill the suite process.
              (handler-case
                  (engine-rpc-http-service-serve-listener
                   service listener :concurrency 4
                                    :stop-p (lambda () stop-p))
                (serious-condition (condition) condition)))
            :name "engine-availability-server"))
         (holding (sb-thread:make-semaphore))
         (holder
           (sb-thread:make-thread
            (lambda ()
              ;; A condition here must not kill the suite process.
              (handler-case
                  (let ((ethereum-lisp.telemetry:*telemetry-activity-label*
                          "snap-serve-account-range"))
                    (ethereum-lisp.cli::call-with-devnet-node-store-guard
                     node
                     (lambda ()
                       (sb-thread:signal-semaphore holding)
                       (sleep +devnet-engine-availability-hold-seconds+))))
                (serious-condition (condition) condition)))
            :name "engine-availability-background-holder"))
         (fcu (lambda (id)
                (engine-fixture-forkchoice-request id genesis-hash)))
         (new-payload
           (engine-fixture-payload-request
            2 (execution-payload-envelope-execution-payload
               (block-to-executable-data block))))
         (capabilities
           (lambda (id)
             (devnet-engine-availability-call
              id "engine_exchangeCapabilities"
              (list (list "engine_newPayloadV2"
                          "engine_forkchoiceUpdatedV1")))))
         (client-version
           (devnet-engine-availability-call
            4 "engine_getClientVersionV1"
            (list (list (cons "code" "LH") (cons "name" "lighthouse")
                        (cons "version" "v0") (cons "commit" "0x00000000")))))
         (results '()))
    (unwind-protect
         (progn
           (sb-thread:wait-on-semaphore holding)
           ;; Two Engine requests park behind the background hold.
           (let ((forkchoice (devnet-engine-availability-send
                              port (funcall fcu 1)))
                 (payload (devnet-engine-availability-send port new-payload)))
             (sleep 0.3)
             ;; Metadata calls while two of four worker slots are free.
             (let ((exchange (devnet-engine-availability-send
                              port (funcall capabilities 3)))
                   (version (devnet-engine-availability-send
                             port client-version)))
               (sleep 1.2)
               ;; Saturate every worker slot, then ask for capabilities again.
               (let ((parked (loop for id from 10 below 14
                                   collect (devnet-engine-availability-send
                                            port (funcall fcu id)))))
                 (sleep 0.2)
                 (let ((saturated (devnet-engine-availability-send
                                   port (funcall capabilities 20))))
                   (flet ((join (thread)
                            (sb-thread:join-thread
                             thread :timeout 30
                                    :default (list :error "client timed out"))))
                     (setf results
                           (list :forkchoice (join forkchoice)
                                 :new-payload (join payload)
                                 :exchange (join exchange)
                                 :version (join version)
                                 :parked (mapcar #'join parked)
                                 :saturated (join saturated)))
                     (sb-thread:join-thread holder :timeout 30 :default nil)
                     ;; Once the hold is over the ordinary path answers.
                     (setf (getf results :after)
                           (devnet-engine-availability-http
                            port (json-encode (funcall fcu 30))))))))))
      (setf stop-p t)
      (ignore-errors (engine-rpc-http-listener-close listener))
      (sb-thread:join-thread server :timeout 30 :default nil)
      (mapc #'funcall restores))
    results))

(deftest devnet-engine-availability-behind-a-long-background-hold
  (:layer :integration :requires-local-sockets t)
  ;; Hoodi b5161312: Engine calls timed out behind 20-133 s peer-session holds.
  ;; Fixed: engine_exchangeCapabilities and engine_getClientVersionV1 answer
  ;; without the guard; newPayload and forkchoiceUpdated give up after the
  ;; background budget (1 s here, 7 s shipped) and answer SYNCING, which also
  ;; frees their worker slots, so a capabilities call that finds all four
  ;; slots parked is served within one budget. Control (the b5161312 policy):
  ;; the same calls wait out the whole 4 s hold, and forkchoiceUpdated then
  ;; answers VALID.
  #-sbcl (skip-test "Engine availability requires SBCL threads and sockets")
  #+sbcl
  (let* ((sender-keys '(1 2))
         (genesis-json (devnet-np-latency-genesis-json sender-keys 8))
         (block (first (devnet-np-latency-build-blocks
                        genesis-json sender-keys 8 1))))
    (let ((fixed (devnet-engine-availability-run t genesis-json block))
          (old (devnet-engine-availability-run nil genesis-json block)))
      (flet ((ms (run key) (getf (getf run key) :ms)))
        ;; The measurements, as a TAP comment, for the evidence record.
        (dolist (run (list (cons "fixed" fixed) (cons "b5161312" old)))
          (format t "~&# engine availability ~A: ~{~A ~A ms ~A~^, ~}~%"
                  (car run)
                  (loop for key in '(:forkchoice :new-payload :exchange
                                     :version :saturated :after)
                        for result = (getf (cdr run) key)
                        append (list (string-downcase key)
                                     (getf result :ms)
                                     (or (devnet-engine-availability-status
                                          result)
                                         (if (devnet-engine-availability-answered-p
                                              result)
                                             "answered"
                                             (getf result :error)))))))
        ;; Every request got an HTTP reply in both runs.
        (dolist (run (list fixed old))
          (dolist (key '(:forkchoice :new-payload :exchange :version
                         :saturated :after))
            (is (null (getf (getf run key) :error))))
          (is (string= +payload-status-valid+
                       (devnet-engine-availability-status (getf run :after)))))
        ;; Fixed: the parked writes answer SYNCING after about one budget and
        ;; well before the hold ends.
        (is (equal +payload-status-syncing+
                   (devnet-engine-availability-status
                    (getf fixed :forkchoice))))
        (is (equal +payload-status-syncing+
                   (devnet-engine-availability-status
                    (getf fixed :new-payload))))
        (is (<= 900 (ms fixed :forkchoice) 2500))
        (is (<= 900 (ms fixed :new-payload) 2500))
        (dolist (parked (getf fixed :parked))
          (is (equal +payload-status-syncing+
                     (devnet-engine-availability-status parked))))
        ;; Fixed: metadata calls answer at once while slots are free ...
        (is (devnet-engine-availability-answered-p (getf fixed :exchange)))
        (is (devnet-engine-availability-answered-p (getf fixed :version)))
        (is (< (ms fixed :exchange) 500))
        (is (< (ms fixed :version) 500))
        ;; ... and within one budget when every slot is parked.
        (is (devnet-engine-availability-answered-p (getf fixed :saturated)))
        (is (< (ms fixed :saturated) 1800))
        ;; Control: the same calls wait for the whole hold.
        (is (>= (ms old :exchange) 3000))
        (is (>= (ms old :forkchoice) 3500))
        (is (string= +payload-status-valid+
                     (devnet-engine-availability-status (getf old :forkchoice))))
        (is (>= (ms old :saturated) 2000))))))

;;;; The forward batch importer holds the guard for one block once blocks are
;;;; slower than its budget.

#+sbcl
(defun devnet-forward-batch-blocks-per-hold (genesis-json blocks block-seconds)
  "Import BLOCKS through the forward batch importer with a 0.5 s hold budget,
each block slowed by BLOCK-SECONDS. Returns the number of blocks each store
guard hold executed, in order."
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json genesis-json :port 0))
         (holds 0)
         (current nil)
         (per-hold (make-hash-table))
         (guard 'ethereum-lisp.cli::call-with-devnet-node-store-guard)
         (import 'ethereum-lisp.cli::devnet-peer-sync-import-block-without-guard))
    (sb-int:encapsulate guard 'forward-batch-blocks-per-hold
                        (lambda (function node thunk)
                          (funcall function node
                                   (lambda ()
                                     (setf current (incf holds))
                                     (funcall thunk)))))
    (sb-int:encapsulate import 'forward-batch-blocks-per-hold
                        (lambda (function &rest arguments)
                          (sleep block-seconds)
                          (incf (gethash current per-hold 0))
                          (apply function arguments)))
    (unwind-protect
         (let ((ethereum-lisp.cli::*devnet-peer-sync-batch-guard-seconds* 0.5)
               (ethereum-lisp.cli::*devnet-peer-sync-last-block-ticks* 0))
           (ethereum-lisp.cli::devnet-peer-sync-import-batch node blocks nil))
      (sb-int:unencapsulate import 'forward-batch-blocks-per-hold)
      (sb-int:unencapsulate guard 'forward-batch-blocks-per-hold))
    (loop for hold from 1 to holds
          for count = (gethash hold per-hold 0)
          when (plusp count) collect count)))

(deftest devnet-forward-batch-import-holds-the-guard-for-one-slow-block
  (:layer :integration)
  ;; The importer decides before each block whether it ends the hold, and at
  ;; b5161312 it only looked at the time already spent: with blocks slower
  ;; than the 1 s budget every hold ran two of them (about 12 s on Hoodi)
  ;; whenever no Engine request happened to be waiting. It now also stops
  ;; when one more block at the latest block's cost would reach the budget.
  ;; Measured with 0.3 s blocks and a 0.5 s budget: b5161312 held three blocks
  ;; per hold; now the first hold (no cost measured yet) holds two and every
  ;; later hold one. Control: fast blocks still share a hold.
  #-sbcl (skip-test "forward batch timing requires SBCL")
  #+sbcl
  (let* ((sender-keys '(1 2))
         (genesis-json (devnet-np-latency-genesis-json sender-keys 8))
         (blocks (devnet-np-latency-build-blocks genesis-json sender-keys 8 6))
         (slow (devnet-forward-batch-blocks-per-hold genesis-json blocks 0.3))
         (fast (devnet-forward-batch-blocks-per-hold genesis-json blocks 0)))
    (format t "~&# forward batch blocks per hold: slow ~A, fast ~A~%" slow fast)
    (is (= 6 (reduce #'+ slow)))
    (is (<= (first slow) 2))
    (is (every (lambda (count) (= 1 count)) (rest slow)))
    ;; Control: blocks well inside the budget are still batched.
    (is (= 6 (reduce #'+ fast)))
    (is (< (length fast) 6))))
