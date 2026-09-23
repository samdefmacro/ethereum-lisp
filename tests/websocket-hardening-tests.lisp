(in-package #:ethereum-lisp.test)

;;;; WebSocket hardening: origins, masking, --ws.api, batch and notification
;;;; semantics, connection and subscription caps, and deadlines.
;;;;
;;;; The end-to-end cases run the shipped server (DEVNET-START-WS-SERVER-THREAD)
;;;; on a loopback port and speak raw RFC 6455 to it, as websocket-tests.lisp
;;;; does. Reference behaviour is geth 38271784 (1.17.6-unstable).

(defun wsh-origin-cases ()
  "geth node/rpcstack_test.go TestWebsocketOrigins (38271784), as
(SPEC ALLOWED FORBIDDEN)."
  '(("*" ("" "http://test" "https://test" "http://test:8540" "https://test:8540"
          "http://test.com" "https://foo.test" "http://testa" "http://atestb:8540"
          "https://atestb:8540")
     ())
    ("test" ("http://test" "https://test" "http://test:8540" "https://test:8540")
     ("http://test.com" "https://foo.test" "http://testa" "http://atestb:8540"
      "https://atestb:8540"))
    ("https://test" ("https://test" "https://test:9999")
     ("test" "http://test" "http://test.foo" "https://a.test.x"
      "http://testx:8540" "https://xtest:8540"))
    ("https://12.34.56.78" ("https://12.34.56.78" "https://12.34.56.78:8540")
     ("http://12.34.56.78" "http://12.34.56.78:443" "http://1.12.34.56.78"
      "http://12.34.56.78.a" "https://87.65.43.21" "http://87.65.43.21:8540"
      "https://87.65.43.21:8540"))
    ("test:8540" ("http://test:8540" "https://test:8540")
     ("http://test" "https://test" "http://test:8541" "https://test:8541"
      "http://bad" "https://bad" "http://bad:8540" "https://bad:8540"))
    ("https://test:8540" ("https://test:8540")
     ("https://test" "http://test" "http://test:8540" "http://test:8541"
      "https://test:8541" "http://bad" "https://bad" "http://bad:8540"
      "https://bad:8540"))
    ("localhost,http://127.0.0.1"
     ("localhost" "http://localhost" "https://localhost:8443" "http://127.0.0.1"
      "http://127.0.0.1:8080")
     ("https://127.0.0.1" "http://bad" "https://bad" "http://bad:8540"
      "https://bad:8540"))))

(deftest websocket-origins-follow-geth-rules
  ;; RED before: any configured origin matched only by exact string, so
  ;; "test" refused http://test:8540, and no configuration admitted every page.
  (loop for (spec allowed forbidden) in (wsh-origin-cases)
        for rules = (uiop:split-string spec :separator ",")
        do (dolist (origin allowed)
             (unless (ethereum-lisp.websocket:websocket-origin-allowed-p
                      origin rules)
               (error "spec ~S refused ~S" spec origin)))
           (dolist (origin forbidden)
             (when (ethereum-lisp.websocket:websocket-origin-allowed-p
                    origin rules)
               (error "spec ~S admitted ~S" spec origin))))
  ;; Nothing configured: geth's default list, http://localhost and this host.
  (is (ethereum-lisp.websocket:websocket-origin-allowed-p "http://localhost" nil))
  (is (ethereum-lisp.websocket:websocket-origin-allowed-p
       "http://localhost:3000" nil))
  (is (not (ethereum-lisp.websocket:websocket-origin-allowed-p
            "https://localhost" nil)))
  (is (not (ethereum-lisp.websocket:websocket-origin-allowed-p
            "http://evil.example" nil)))
  ;; No Origin header is not a browser and passes; an EMPTY header is checked.
  (is (ethereum-lisp.websocket:websocket-origin-allowed-p nil nil))
  (is (not (ethereum-lisp.websocket:websocket-origin-allowed-p "" nil))))

(deftest websocket-server-decoder-refuses-unmasked-client-frames
  ;; RFC 6455 5.1: a server MUST close on an unmasked client frame. The codec
  ;; stays symmetric; the server side asks for masking.
  (let ((unmasked (ensure-byte-vector '(#x81 #x05 #x48 #x65 #x6c #x6c #x6f))))
    (is (ethereum-lisp.websocket:websocket-decode-frame unmasked))
    (handler-case
        (progn (ethereum-lisp.websocket:websocket-decode-frame
                unmasked :require-masked-p t)
               (error "an unmasked frame decoded on the server side"))
      (ethereum-lisp.websocket:websocket-protocol-error (condition)
        (is (= 1002 (ethereum-lisp.websocket:websocket-protocol-error-status
                     condition)))))
    ;; Positive control: the RFC's masked "Hello" still decodes.
    (is (ethereum-lisp.websocket:websocket-decode-frame
         (ensure-byte-vector '(#x81 #x85 #x37 #xfa #x21 #x3d
                               #x7f #x9f #x4d #x51 #x58))
         :require-masked-p t))))

(deftest eth-subscribe-refuses-past-the-per-connection-cap
  (let ((registry (ethereum-lisp.public-api:make-eth-rpc-subscription-registry))
        (cap ethereum-lisp.public-api::+eth-rpc-max-subscriptions-per-connection+))
    (loop repeat cap
          do (ethereum-lisp.public-api:eth-rpc-handle-eth-subscribe
              '("newHeads") registry))
    (is (= cap (ethereum-lisp.public-api:eth-rpc-subscription-count registry)))
    (handler-case
        (progn (ethereum-lisp.public-api:eth-rpc-handle-eth-subscribe
                '("newHeads") registry)
               (error "subscription past the cap was accepted"))
      (ethereum-lisp.engine-api:engine-rpc-error (condition)
        (is (= -32000 (ethereum-lisp.engine-api:engine-rpc-error-code condition)))))
    ;; Positive control: freeing one makes room for one.
    (ethereum-lisp.public-api:eth-rpc-handle-eth-unsubscribe
     (list (ethereum-lisp.public-api::eth-rpc-subscription-id
            (first (ethereum-lisp.public-api::eth-rpc-subscription-registry-subscriptions
                    registry))))
     registry)
    (is (stringp (ethereum-lisp.public-api:eth-rpc-handle-eth-subscribe
                  '("newHeads") registry)))))

(deftest websocket-ws-api-option-is-parsed
  (let ((options (ethereum-lisp.cli::devnet-cli-options
                  (list "--genesis" "g.json" "--ws" "--ws.api" "net,web3"))))
    (is (equal '("net" "web3") (getf options :ws-api-modules)))
    (is (not (member "--ws.api" (getf options :ignored-options)
                     :test #'string=)))))

;;; The shipped server over loopback.

#+sbcl
(defun wsh-call-with-server (function &rest node-arguments)
  "Start NODE's WebSocket server on an ephemeral loopback port, call FUNCTION
with the node and port, and always shut the server down."
  (let* ((node (apply #'ethereum-lisp.cli:make-devnet-node
                      :genesis-json *eth-sync-paris-genesis-json*
                      :port 0 :public-port 0
                      :ws-enabled-p t :ws-host "127.0.0.1" :ws-port 0
                      node-arguments))
         (controller (ethereum-lisp.cli::make-devnet-shutdown-controller))
         (thread nil))
    (unwind-protect
         (multiple-value-bind (server-thread sessions)
             (ethereum-lisp.cli:devnet-start-ws-server-thread
              node controller (lambda (condition) condition))
           (declare (ignore sessions))
           (setf thread server-thread)
           (funcall function node (ethereum-lisp.cli:devnet-node-ws-port node)))
      (ethereum-lisp.cli:devnet-shutdown-request controller)
      (when thread
        (sb-thread:join-thread thread :timeout 15 :default :timeout)))))

#+sbcl
(defun wsh-connect (port &key origin)
  "A connected client stream after its upgrade request; returns (VALUES STREAM
SOCKET RESPONSE-HEAD)."
  (let ((socket (make-instance 'sb-bsd-sockets:inet-socket
                               :type :stream :protocol :tcp)))
    (sb-bsd-sockets:socket-connect
     socket (sb-bsd-sockets:make-inet-address "127.0.0.1") port)
    (let ((stream (sb-bsd-sockets:socket-make-stream
                   socket :input t :output t
                          :element-type '(unsigned-byte 8) :buffering :full)))
      (write-sequence
       (coerce (ascii-to-bytes
                (format nil "GET / HTTP/1.1~C~CHost: localhost~C~C~
                             Upgrade: websocket~C~CConnection: Upgrade~C~C~
                             Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==~C~C~
                             Sec-WebSocket-Version: 13~C~C~@[Origin: ~A~C~C~]~C~C"
                        #\Return #\Newline #\Return #\Newline
                        #\Return #\Newline #\Return #\Newline
                        #\Return #\Newline #\Return #\Newline
                        origin #\Return #\Newline
                        #\Return #\Newline))
               '(vector (unsigned-byte 8)))
       stream)
      (finish-output stream)
      (values stream socket
              (ws-read-until
               stream
               (lambda (bytes)
                 (let ((text (bytes-to-ascii bytes)))
                   (when (search (format nil "~C~C~C~C" #\Return #\Newline
                                         #\Return #\Newline)
                                 text)
                     text)))
               :timeout 5)))))

#+sbcl
(defun wsh-send (stream text &key (masked-p t))
  (write-sequence
   (coerce (if masked-p
               (ws-client-frame 1 (ascii-to-bytes text))
               (let ((payload (ascii-to-bytes text)))
                 (concat-bytes (ensure-byte-vector
                                (list #x81 (length payload)))
                               payload)))
           '(vector (unsigned-byte 8)))
   stream)
  (finish-output stream))

#+sbcl
(defun wsh-read-frame (stream &key (timeout 5))
  "The next frame the server sends, as (OPCODE . PAYLOAD-BYTES), or NIL."
  (ws-read-until
   stream
   (lambda (bytes)
     (let ((frame (ignore-errors
                   (ethereum-lisp.websocket:websocket-decode-frame bytes))))
       (when frame
         (cons (ethereum-lisp.websocket:websocket-frame-opcode frame)
               (ethereum-lisp.websocket:websocket-frame-payload frame)))))
   :timeout timeout))

#+sbcl
(defun wsh-read-text (stream &key (timeout 5))
  (let ((frame (wsh-read-frame stream :timeout timeout)))
    (and frame (= 1 (car frame)) (bytes-to-ascii (cdr frame)))))

#+sbcl
(deftest websocket-server-refuses-foreign-origins-by-default
  (:layer :integration :module :devnet :requires-local-sockets t)
  (wsh-call-with-server
   (lambda (node port)
     (declare (ignore node))
     (flet ((head-for (origin)
              (multiple-value-bind (stream socket head) (wsh-connect port :origin origin)
                (declare (ignore stream))
                (ignore-errors (sb-bsd-sockets:socket-close socket))
                head)))
       (is (search "403" (head-for "http://evil.example")))
       ;; Positive controls: a local page, and a non-browser client.
       (is (search "101" (head-for "http://localhost:8080")))
       (is (search "101" (head-for nil)))))))

#+sbcl
(deftest websocket-server-closes-on-an-unmasked-frame
  (:layer :integration :module :devnet :requires-local-sockets t)
  (wsh-call-with-server
   (lambda (node port)
     (declare (ignore node))
     (multiple-value-bind (stream socket) (wsh-connect port)
       (unwind-protect
            (progn
              ;; Positive control on the same connection first.
              (wsh-send stream "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"net_version\",\"params\":[]}")
              (is (search "\"id\":1" (wsh-read-text stream)))
              (wsh-send stream "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"net_version\",\"params\":[]}"
                        :masked-p nil)
              (let ((frame (wsh-read-frame stream)))
                (is (eql 8 (car frame)))
                (is (= 1002 (+ (* 256 (aref (cdr frame) 0))
                               (aref (cdr frame) 1)))))
              ;; And the server hangs up.
              (is (null (wsh-read-frame stream :timeout 3))))
         (ignore-errors (sb-bsd-sockets:socket-close socket)))))))

#+sbcl
(deftest websocket-ws-api-filters-methods-and-subscriptions
  (:layer :integration :module :devnet :requires-local-sockets t)
  ;; RED before: the WebSocket answered with --http.api's filter, so --ws.api
  ;; changed nothing.
  (wsh-call-with-server
   (lambda (node port)
     (declare (ignore node))
     (multiple-value-bind (stream socket) (wsh-connect port)
       (unwind-protect
            (progn
              (wsh-send stream "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_chainId\",\"params\":[]}")
              (is (search "-32601" (wsh-read-text stream)))
              (wsh-send stream "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"eth_subscribe\",\"params\":[\"newHeads\"]}")
              (is (search "-32601" (wsh-read-text stream)))
              ;; Positive control: the enabled namespace answers.
              (wsh-send stream "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"net_version\",\"params\":[]}")
              (let ((reply (wsh-read-text stream)))
                (is (search "\"id\":3" reply))
                (is (search "\"result\"" reply))))
         (ignore-errors (sb-bsd-sockets:socket-close socket)))))
   :ws-allowed-method-p
   (ethereum-lisp.cli::devnet-cli-public-api-method-filter '("net"))))

#+sbcl
(deftest websocket-subscribe-works-in-batches-and-notifications-get-no-reply
  (:layer :integration :module :devnet :requires-local-sockets t)
  ;; RED before: eth_subscribe inside a batch was "Method not found", and a
  ;; subscribe sent as a notification (no id) still got a response.
  (wsh-call-with-server
   (lambda (node port)
     (declare (ignore node))
     (multiple-value-bind (stream socket) (wsh-connect port)
       (unwind-protect
            (progn
              (wsh-send stream "[{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_subscribe\",\"params\":[\"newHeads\"]},{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"eth_chainId\",\"params\":[]}]")
              (let ((batch (parse-json (wsh-read-text stream))))
                (is (= 2 (length batch)))
                (is (every (lambda (response)
                             (assoc "result" response :test #'string=))
                           batch))
                (is (stringp (cdr (assoc "result" (first batch)
                                         :test #'string=)))))
              (wsh-send stream "{\"jsonrpc\":\"2.0\",\"method\":\"eth_subscribe\",\"params\":[\"newHeads\"]}")
              (wsh-send stream "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"eth_chainId\",\"params\":[]}")
              ;; The next frame answers id 9: the notification got nothing.
              (is (search "\"id\":9" (wsh-read-text stream))))
         (ignore-errors (sb-bsd-sockets:socket-close socket)))))))

#+sbcl
(deftest websocket-server-refuses-connections-past-the-cap
  (:layer :integration :module :devnet :requires-local-sockets t)
  (let ((old ethereum-lisp.cli::*devnet-ws-max-connections*))
    (unwind-protect
         (progn
           ;; SETF, not LET: the accept thread reads the global value.
           (setf ethereum-lisp.cli::*devnet-ws-max-connections* 1)
           (wsh-call-with-server
            (lambda (node port)
              (declare (ignore node))
              (multiple-value-bind (first-stream first-socket first-head)
                  (wsh-connect port)
                (declare (ignore first-stream))
                (is (search "101" first-head))
                (multiple-value-bind (stream socket head) (wsh-connect port)
                  (declare (ignore stream))
                  (ignore-errors (sb-bsd-sockets:socket-close socket))
                  (is (search "503" head)))
                ;; Positive control: once the first client leaves, its slot is
                ;; free again.
                (sb-bsd-sockets:socket-close first-socket)
                (let ((head nil))
                  (loop repeat 50
                        until (and head (search "101" head))
                        do (sleep 0.1)
                           (multiple-value-bind (stream socket next-head)
                               (wsh-connect port)
                             (declare (ignore stream))
                             (setf head next-head)
                             (ignore-errors
                              (sb-bsd-sockets:socket-close socket))))
                  (is (search "101" head)))))))
      (setf ethereum-lisp.cli::*devnet-ws-max-connections* old))))

#+sbcl
(deftest websocket-server-drops-a-client-that-stops-answering-pings
  (:layer :integration :module :devnet :requires-local-sockets t)
  (let ((old-interval ethereum-lisp.cli::*devnet-ws-ping-interval-seconds*)
        (old-timeout ethereum-lisp.cli::*devnet-ws-pong-timeout-seconds*))
    (unwind-protect
         (progn
           (setf ethereum-lisp.cli::*devnet-ws-ping-interval-seconds* 1
                 ethereum-lisp.cli::*devnet-ws-pong-timeout-seconds* 1)
           (wsh-call-with-server
            (lambda (node port)
              (declare (ignore node))
              ;; A client that answers every ping stays connected past
              ;; several deadlines (the positive control) ...
              (multiple-value-bind (stream socket) (wsh-connect port)
                (unwind-protect
                     (progn
                       (loop repeat 3
                             do (let ((frame (wsh-read-frame stream :timeout 5)))
                                  (is (eql 9 (car frame)))
                                  (write-sequence
                                   (coerce (ws-client-frame #xA (cdr frame))
                                           '(vector (unsigned-byte 8)))
                                   stream)
                                  (finish-output stream)))
                       (wsh-send stream "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"net_version\",\"params\":[]}")
                       (is (search "\"id\":5" (wsh-read-text stream))))
                  (ignore-errors (sb-bsd-sockets:socket-close socket))))
              ;; ... and one that ignores them is closed after the timeout.
              (multiple-value-bind (stream socket) (wsh-connect port)
                (unwind-protect
                     (let ((ping (wsh-read-frame stream :timeout 5)))
                       (is (eql 9 (car ping)))
                       (let ((close (wsh-read-frame stream :timeout 5)))
                         (is (eql 8 (car close))))
                       (is (null (wsh-read-frame stream :timeout 3))))
                  (ignore-errors (sb-bsd-sockets:socket-close socket)))))))
      (setf ethereum-lisp.cli::*devnet-ws-ping-interval-seconds* old-interval
            ethereum-lisp.cli::*devnet-ws-pong-timeout-seconds* old-timeout))))

#+sbcl
(deftest websocket-frame-writes-give-up-on-a-client-that-stops-reading
  ;; A blocking write to a peer that reads nothing never returns; the session
  ;; thread (and its connection slot) would be pinned for good. The deadline
  ;; write gives up; the positive control drains the peer and completes.
  (let* ((listener (make-instance 'sb-bsd-sockets:inet-socket
                                  :type :stream :protocol :tcp))
         (client (make-instance 'sb-bsd-sockets:inet-socket
                                :type :stream :protocol :tcp))
         (server nil)
         (payload (make-array (* 32 1024 1024) :element-type '(unsigned-byte 8)
                                               :initial-element 7)))
    (unwind-protect
         (progn
           (sb-bsd-sockets:socket-bind
            listener (sb-bsd-sockets:make-inet-address "127.0.0.1") 0)
           (sb-bsd-sockets:socket-listen listener 1)
           (sb-bsd-sockets:socket-connect
            client (sb-bsd-sockets:make-inet-address "127.0.0.1")
            (nth-value 1 (sb-bsd-sockets:socket-name listener)))
           (setf server (sb-bsd-sockets:socket-accept listener))
           (setf (sb-bsd-sockets:non-blocking-mode server) t)
           (let ((stream (sb-bsd-sockets:socket-make-stream
                          server :input t :output t
                                 :element-type '(unsigned-byte 8)))
                 (start (get-internal-real-time)))
             (handler-case
                 (progn
                   (ethereum-lisp.websocket::websocket-write-octets-with-deadline
                    stream payload 1)
                   (error "a 32 MiB write to a silent peer completed"))
               (ethereum-lisp.websocket::websocket-write-timeout () nil))
             (is (< (- (get-internal-real-time) start)
                    (* 5 internal-time-units-per-second)))
             ;; Positive control: a peer that reads lets the same write finish.
             (let* ((client-stream (sb-bsd-sockets:socket-make-stream
                                    client :input t
                                           :element-type '(unsigned-byte 8)))
                    (drain (sb-thread:make-thread
                            (lambda ()
                              (handler-case
                                  (loop for byte = (read-byte client-stream nil nil)
                                        while byte)
                                (serious-condition () nil)))
                            :name "wsh-drain")))
               (ethereum-lisp.websocket::websocket-write-octets-with-deadline
                stream (subseq payload 0 (* 4 1024 1024)) 10)
               (sb-bsd-sockets:socket-close server)
               (setf server nil)
               (sb-thread:join-thread drain :timeout 10 :default nil))))
      (ignore-errors (sb-bsd-sockets:socket-close client))
      (when server (ignore-errors (sb-bsd-sockets:socket-close server)))
      (ignore-errors (sb-bsd-sockets:socket-close listener)))))
