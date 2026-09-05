(in-package #:ethereum-lisp.test)

;;;; The WebSocket transport and eth_subscribe.
;;;;
;;;; The framing tests use RFC 6455's own worked examples, section 5.7, because
;;;; a frame codec that agrees with the spec's bytes agrees with every client.
;;;; One test opens a real socket and speaks the protocol end to end.

(defun ws (name)
  (find-symbol name "ETHEREUM-LISP.WEBSOCKET"))

(defun ws-bytes (&rest values)
  (ensure-byte-vector values))

(deftest websocket-decodes-the-rfc-6455-examples
  ;; A single-frame unmasked text message carrying "Hello".
  (multiple-value-bind (frame next)
      (funcall (ws "WEBSOCKET-DECODE-FRAME")
               (ws-bytes #x81 #x05 #x48 #x65 #x6c #x6c #x6f))
    (is (funcall (ws "WEBSOCKET-FRAME-FIN-P") frame))
    (is (= 1 (funcall (ws "WEBSOCKET-FRAME-OPCODE") frame)))
    (is (equal "Hello" (bytes-to-ascii
                        (funcall (ws "WEBSOCKET-FRAME-PAYLOAD") frame))))
    (is (= 7 next)))
  ;; The same message masked, as a client must send it. The key is in the
  ;; frame; unmasking is bookkeeping, not decryption.
  (let ((frame (funcall (ws "WEBSOCKET-DECODE-FRAME")
                        (ws-bytes #x81 #x85 #x37 #xfa #x21 #x3d
                                  #x7f #x9f #x4d #x51 #x58))))
    (is (equal "Hello" (bytes-to-ascii
                        (funcall (ws "WEBSOCKET-FRAME-PAYLOAD") frame)))))
  ;; A Ping carrying "Hello".
  (let ((frame (funcall (ws "WEBSOCKET-DECODE-FRAME")
                        (ws-bytes #x89 #x05 #x48 #x65 #x6c #x6c #x6f))))
    (is (= 9 (funcall (ws "WEBSOCKET-FRAME-OPCODE") frame))))
  ;; And what we produce for "Hello" is byte-for-byte the spec's example.
  (is (bytes= (ws-bytes #x81 #x05 #x48 #x65 #x6c #x6c #x6f)
              (funcall (ws "WEBSOCKET-ENCODE-FRAME") 1 (ascii-to-bytes "Hello")))))

(deftest websocket-decode-waits-for-a-whole-frame
  ;; A partial frame is not an error, it is "read more". Treating it as an
  ;; error would make every message that spans two TCP reads a failure.
  (is (null (funcall (ws "WEBSOCKET-DECODE-FRAME") (ws-bytes #x81))))
  (is (null (funcall (ws "WEBSOCKET-DECODE-FRAME") (ws-bytes #x81 #x05 #x48))))
  ;; Announced 126 but only two length bytes present.
  (is (null (funcall (ws "WEBSOCKET-DECODE-FRAME") (ws-bytes #x81 #x7e #x01))))
  ;; Masked, but the key has not all arrived.
  (is (null (funcall (ws "WEBSOCKET-DECODE-FRAME")
                     (ws-bytes #x81 #x85 #x37 #xfa)))))

(deftest websocket-rejects-frames-that-can-never-be-valid
  ;; A reserved bit with no negotiated extension.
  (signals error (funcall (ws "WEBSOCKET-DECODE-FRAME") (ws-bytes #xC1 #x00)))
  ;; A fragmented control frame. Control frames must be deliverable while a
  ;; message is mid-flight, which fragmenting them would prevent.
  (signals error (funcall (ws "WEBSOCKET-DECODE-FRAME") (ws-bytes #x09 #x00)))
  ;; A control frame with an oversized payload.
  (signals error (funcall (ws "WEBSOCKET-DECODE-FRAME")
                          (ws-bytes #x89 #x7e #x01 #x00)))
  ;; A short payload sent in the long form. Every length has exactly one
  ;; encoding, so accepting this would let two byte strings mean one message.
  (signals error (funcall (ws "WEBSOCKET-DECODE-FRAME")
                          (ws-bytes #x81 #x7e #x00 #x05
                                    #x48 #x65 #x6c #x6c #x6f)))
  ;; An announced payload past the limit is refused BEFORE anything is
  ;; allocated, which is the whole point of checking the announcement.
  (signals error
    (funcall (ws "WEBSOCKET-DECODE-FRAME")
             (ws-bytes #x81 #x7f #xff #xff #xff #xff #xff #xff #xff #xff)
             :max-payload-bytes 1024)))

(deftest websocket-encodes-each-length-in-its-shortest-form
  (let ((short (funcall (ws "WEBSOCKET-ENCODE-FRAME") 2
                        (make-byte-vector 125)))
        (medium (funcall (ws "WEBSOCKET-ENCODE-FRAME") 2
                         (make-byte-vector 126)))
        (long (funcall (ws "WEBSOCKET-ENCODE-FRAME") 2
                       (make-byte-vector 65536))))
    (is (= 125 (aref short 1)))
    (is (= 126 (aref medium 1)))
    (is (= 127 (aref long 1)))
    ;; And a server never masks: the mask bit must be clear in all of them.
    (dolist (frame (list short medium long))
      (is (zerop (logand (aref frame 1) #x80))))))

(deftest websocket-accept-token-matches-the-rfc
  ;; RFC 6455 section 1.3's worked example. Every client checks this literally,
  ;; so an alphabet or padding slip makes us reject-by-being-rejected.
  (is (equal "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
             (funcall (ws "WEBSOCKET-ACCEPT-TOKEN") "dGhlIHNhbXBsZSBub25jZQ=="))))

(defun ws-upgrade-headers (&rest overrides)
  (let ((headers (list (cons "Host" "localhost")
                       (cons "Upgrade" "websocket")
                       (cons "Connection" "keep-alive, Upgrade")
                       (cons "Sec-WebSocket-Key" "dGhlIHNhbXBsZSBub25jZQ==")
                       (cons "Sec-WebSocket-Version" "13"))))
    (loop for (name value) on overrides by #'cddr
          do (setf headers (remove name headers :key #'car :test #'string-equal))
             (when value (push (cons name value) headers)))
    headers))

(deftest websocket-handshake-accepts-and-refuses
  (multiple-value-bind (response accepted-p)
      (funcall (ws "WEBSOCKET-HANDSHAKE-RESPONSE") "GET" "/" (ws-upgrade-headers))
    (is accepted-p)
    (is (search "HTTP/1.1 101 Switching Protocols" response))
    (is (search "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" response)))
  ;; `Connection: keep-alive, Upgrade` is what real clients send, so matching
  ;; the whole header value against "Upgrade" would reject them.
  (is (funcall (ws "WEBSOCKET-HEADER-CONTAINS-TOKEN-P")
               "keep-alive, Upgrade" "Upgrade"))
  (is (not (funcall (ws "WEBSOCKET-HEADER-CONTAINS-TOKEN-P")
                    "keep-alive" "Upgrade")))
  ;; A plain GET to the same port gets an HTTP answer, not a protocol error:
  ;; the client is still speaking HTTP at this point.
  (multiple-value-bind (response accepted-p)
      (funcall (ws "WEBSOCKET-HANDSHAKE-RESPONSE") "GET" "/" '(("Host" . "x")))
    (is (not accepted-p))
    (is (search "400 Bad Request" response)))
  ;; Only version 13 exists, and the refusal names what we do support so an
  ;; older client can fall back rather than guess.
  (multiple-value-bind (response accepted-p)
      (funcall (ws "WEBSOCKET-HANDSHAKE-RESPONSE") "GET" "/"
               (ws-upgrade-headers "Sec-WebSocket-Version" "8"))
    (is (not accepted-p))
    (is (search "Sec-WebSocket-Version: 13" response)))
  (multiple-value-bind (response accepted-p)
      (funcall (ws "WEBSOCKET-HANDSHAKE-RESPONSE") "GET" "/"
               (ws-upgrade-headers "Sec-WebSocket-Key" nil))
    (is (not accepted-p))
    (is (search "400" response)))
  ;; A path that is not the configured prefix is a 404, as it would be on the
  ;; HTTP listener.
  (multiple-value-bind (response accepted-p)
      (funcall (ws "WEBSOCKET-HANDSHAKE-RESPONSE") "GET" "/nope"
               (ws-upgrade-headers))
    (is (not accepted-p))
    (is (search "404" response))))

(deftest websocket-origin-policy
  ;; No configured origins means no restriction.
  (is (funcall (ws "WEBSOCKET-ORIGIN-ALLOWED-P") "http://evil.example" nil))
  (is (funcall (ws "WEBSOCKET-ORIGIN-ALLOWED-P") "http://ok.example"
               '("http://ok.example")))
  (is (not (funcall (ws "WEBSOCKET-ORIGIN-ALLOWED-P") "http://evil.example"
                    '("http://ok.example"))))
  ;; A request with no Origin is not a browser, and the header's absence makes
  ;; no claim to check.
  (is (funcall (ws "WEBSOCKET-ORIGIN-ALLOWED-P") nil '("http://ok.example")))
  (is (funcall (ws "WEBSOCKET-ORIGIN-ALLOWED-P") "http://any.example" '("*"))))

(deftest websocket-handshake-request-is-parsed
  (multiple-value-bind (method target headers)
      (ethereum-lisp.cli:devnet-ws-parse-handshake
       (format nil "GET /ws HTTP/1.1~C~CHost: localhost:8546~C~C~
                    Upgrade: websocket~C~C~C~C"
               #\Return #\Newline #\Return #\Newline
               #\Return #\Newline #\Return #\Newline))
    (is (equal "GET" method))
    (is (equal "/ws" target))
    (is (equal "localhost:8546"
               (funcall (ws "WEBSOCKET-HEADER-VALUE") headers "host")))
    (is (equal "websocket"
               (funcall (ws "WEBSOCKET-HEADER-VALUE") headers "UPGRADE")))))

(deftest websocket-ws-options-are-parsed
  (let ((options (ethereum-lisp.cli::devnet-cli-options
                  (list "--genesis" "g.json" "--ws"
                        "--ws.addr" "127.0.0.1" "--ws.port" "8546"
                        "--ws.rpcprefix" "/ws"))))
    (is (getf options :ws-enabled-p))
    (is (equal "127.0.0.1" (getf options :ws-host)))
    (is (= 8546 (getf options :ws-port)))
    (is (equal "/ws" (getf options :ws-rpc-prefix))))
  ;; A geth-style optional boolean, so --ws=false turns it off rather than
  ;; being read as on with a stray argument left over.
  (let ((options (ethereum-lisp.cli::devnet-cli-options
                  (list "--genesis" "g.json" "--ws" "false"))))
    (is (not (getf options :ws-enabled-p)))))

(deftest eth-subscribe-registers-and-unsubscribes
  (let ((registry (ethereum-lisp.public-api:make-eth-rpc-subscription-registry)))
    (let ((heads (ethereum-lisp.public-api:eth-rpc-handle-eth-subscribe
                  '("newHeads") registry))
          (pending (ethereum-lisp.public-api:eth-rpc-handle-eth-subscribe
                    '("newPendingTransactions") registry)))
      (is (stringp heads))
      (is (= 34 (length heads)))          ; "0x" plus sixteen bytes
      (is (not (equal heads pending)))
      (is (= 2 (ethereum-lisp.public-api:eth-rpc-subscription-count registry)))
      (is (ethereum-lisp.public-api:eth-rpc-handle-eth-unsubscribe
           (list heads) registry))
      (is (= 1 (ethereum-lisp.public-api:eth-rpc-subscription-count registry)))
      ;; An unknown id is FALSE rather than an error: a client tearing down
      ;; after a reconnect should not have to tell "already gone" from "never
      ;; existed".
      (is (not (ethereum-lisp.public-api:eth-rpc-handle-eth-unsubscribe
                (list heads) registry)))
      (is (not (ethereum-lisp.public-api:eth-rpc-handle-eth-unsubscribe
                (list "0xdeadbeef") registry))))
    ;; A subscription we do not offer is named rather than lumped in with a
    ;; typo, and an unknown one is refused instead of silently never firing.
    (signals error (ethereum-lisp.public-api:eth-rpc-handle-eth-subscribe
                    '("syncing") registry))
    (signals error (ethereum-lisp.public-api:eth-rpc-handle-eth-subscribe
                    '("newHeadz") registry))
    (signals error (ethereum-lisp.public-api:eth-rpc-handle-eth-subscribe
                    '() registry))))

(deftest eth-subscribe-log-topics-enforce-shared-parser-limits
  (labels ((topic-json (count &key alternatives-p)
             (let ((topic
                     "\"0x0000000000000000000000000000000000000000000000000000000000000001\""))
               (format nil
                       (if alternatives-p
                           "{\"topics\":[[~{~A~^,~}]]}"
                           "{\"topics\":[~{~A~^,~}]}")
                       (loop repeat count collect topic))))
           (subscribe (count alternatives-p registry)
             (ethereum-lisp.public-api:eth-rpc-handle-eth-subscribe
              (list "logs"
                    (parse-json
                     (topic-json count :alternatives-p alternatives-p)))
              registry))
           (assert-limit (count alternatives-p registry)
             (handler-case
                 (progn
                   (subscribe count alternatives-p registry)
                   (is nil))
               (ethereum-lisp.engine-api:engine-rpc-error (condition)
                 (is (= -32000
                        (ethereum-lisp.engine-api:engine-rpc-error-code
                         condition)))
                 (is (string= "exceed max topics"
                              (ethereum-lisp.engine-api:engine-rpc-error-message
                               condition)))))))
    (let ((registry
            (ethereum-lisp.public-api:make-eth-rpc-subscription-registry)))
      (is (stringp (subscribe 4 nil registry)))
      (assert-limit 5 nil registry)
      (is (stringp (subscribe 1000 t registry)))
      (assert-limit 1001 t registry))))

(deftest eth-subscription-notification-shape
  (let ((json (ethereum-lisp.public-api:eth-rpc-subscription-notification-json
               "0xabc" "0xdef")))
    ;; A notification carries no id: it is not a reply, and a client that
    ;; answered it would be answering nothing.
    (is (search "\"method\":\"eth_subscription\"" json))
    (is (search "\"subscription\":\"0xabc\"" json))
    (is (search "\"result\":\"0xdef\"" json))
    (is (null (search "\"id\"" json)))))

(defun ws-client-frame (opcode payload)
  "A frame as a CLIENT must send it: masked, with the key in the frame.

Masking is not secrecy -- the key travels alongside -- so the test does the same
trivial thing a browser does. An unmasked client frame is a protocol error, so
this is the only shape the server will accept."
  (let* ((payload (ensure-byte-vector payload))
         (length (length payload))
         (key (ensure-byte-vector '(#x12 #x34 #x56 #x78)))
         (masked (make-byte-vector length)))
    (loop for index from 0 below length
          do (setf (aref masked index)
                   (logxor (aref payload index) (aref key (mod index 4)))))
    (concat-bytes
     (ensure-byte-vector
      (if (< length 126)
          (list (logior #x80 opcode) (logior #x80 length))
          (list (logior #x80 opcode) (logior #x80 126)
                (ldb (byte 8 8) length) (ldb (byte 8 0) length))))
     key masked)))

(defun ws-read-until (stream predicate &key (timeout 10))
  "Accumulate octets from STREAM until PREDICATE accepts them, or time out.

LISTEN comes BEFORE the descriptor wait, and getting that backwards is a trap
worth naming: the stream is buffered, so one READ-BYTE pulls a whole chunk into
userspace and WAIT-UNTIL-FD-USABLE then reports nothing to read -- correctly,
because the bytes are no longer at the descriptor. Gating on the fd alone
therefore reads exactly one byte of any response and then times out."
  (let ((buffer (make-array 0 :element-type '(unsigned-byte 8)
                              :adjustable t :fill-pointer 0))
        (deadline (+ (get-universal-time) timeout)))
    (loop
      (when (> (get-universal-time) deadline)
        (return nil))
      (when (or (listen stream)
                (sb-sys:wait-until-fd-usable
                 (sb-sys:fd-stream-fd stream) :input 1 nil))
        (let ((byte (read-byte stream nil nil)))
          (when (null byte) (return nil))
          (vector-push-extend byte buffer)
          (let ((result (funcall predicate (ensure-byte-vector buffer))))
            (when result (return result))))))))

#+sbcl
(deftest websocket-endpoint-answers-rpc-and-subscribes
  (:layer :integration :module :devnet :requires-local-sockets t)
  ;; End to end over a real socket: upgrade, call an ordinary RPC method, open
  ;; a subscription, and stop. The framing and the handshake are unit-tested
  ;; above; what this proves is that they are wired to the RPC surface at all.
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0 :public-port 0
                :ws-enabled-p t :ws-host "127.0.0.1" :ws-port 0))
         (controller (ethereum-lisp.cli::make-devnet-shutdown-controller))
         (thread-error nil)
         (thread nil))
    (unwind-protect
         (multiple-value-bind (server-thread sessions)
             (ethereum-lisp.cli:devnet-start-ws-server-thread
              node controller (lambda (c) (setf thread-error c)))
           (setf thread server-thread)
           (is (not (null thread)))
           (let ((port (ethereum-lisp.cli:devnet-node-ws-port node))
                 (socket (make-instance 'sb-bsd-sockets:inet-socket
                                        :type :stream :protocol :tcp)))
             (is (plusp port))
             (unwind-protect
                  (let ((stream nil))
                    (sb-bsd-sockets:socket-connect
                     socket (sb-bsd-sockets:make-inet-address "127.0.0.1") port)
                    (setf stream (sb-bsd-sockets:socket-make-stream
                                  socket :input t :output t
                                         :element-type '(unsigned-byte 8)
                                         :buffering :full))
                    (write-sequence
                     (coerce (ascii-to-bytes
                              (format nil "GET / HTTP/1.1~C~CHost: localhost~C~C~
                                           Upgrade: websocket~C~C~
                                           Connection: Upgrade~C~C~
                                           Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==~C~C~
                                           Sec-WebSocket-Version: 13~C~C~C~C"
                                      #\Return #\Newline #\Return #\Newline
                                      #\Return #\Newline #\Return #\Newline
                                      #\Return #\Newline #\Return #\Newline
                                      #\Return #\Newline))
                             '(vector (unsigned-byte 8)))
                     stream)
                    (finish-output stream)
                    ;; The upgrade is accepted, and with the accept token the
                    ;; RFC's example fixes.
                    (let ((response
                            (ws-read-until
                             stream
                             (lambda (bytes)
                               (let ((text (bytes-to-ascii bytes)))
                                 (when (search
                                        (format nil "~C~C~C~C" #\Return #\Newline
                                                #\Return #\Newline)
                                        text)
                                   text))))))
                      (is (not (null response)))
                      (is (search "101 Switching Protocols" response))
                      (is (search "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" response)))
                    ;; An ordinary public method, over the socket.
                    (write-sequence
                     (coerce (ws-client-frame
                              1 (ascii-to-bytes
                                 "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_chainId\",\"params\":[]}"))
                             '(vector (unsigned-byte 8)))
                     stream)
                    (finish-output stream)
                    (let ((reply (ws-read-until
                                  stream
                                  (lambda (bytes)
                                    (let ((frame (funcall (ws "WEBSOCKET-DECODE-FRAME")
                                                          bytes)))
                                      (when frame
                                        (bytes-to-ascii
                                         (funcall (ws "WEBSOCKET-FRAME-PAYLOAD")
                                                  frame))))))))
                      (is (not (null reply)))
                      (is (search "\"result\"" reply))
                      (is (search "\"id\":1" reply)))
                    ;; And a subscription, which only means anything on a
                    ;; connection that stays open.
                    (write-sequence
                     (coerce (ws-client-frame
                              1 (ascii-to-bytes
                                 "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"eth_subscribe\",\"params\":[\"newHeads\"]}"))
                             '(vector (unsigned-byte 8)))
                     stream)
                    (finish-output stream)
                    (let ((reply (ws-read-until
                                  stream
                                  (lambda (bytes)
                                    (let ((frame (funcall (ws "WEBSOCKET-DECODE-FRAME")
                                                          bytes)))
                                      (when frame
                                        (bytes-to-ascii
                                         (funcall (ws "WEBSOCKET-FRAME-PAYLOAD")
                                                  frame))))))))
                      (is (not (null reply)))
                      (is (search "\"id\":2" reply))
                      (is (search "\"result\":\"0x" reply))))
               (ignore-errors (sb-bsd-sockets:socket-close socket))))
           ;; And it all stops. This is the assertion: it comes back.
           (ethereum-lisp.cli:devnet-shutdown-request controller)
           (is (not (eq :timeout
                        (sb-thread:join-thread thread :timeout 15
                                                      :default :timeout))))
           (when sessions
             (ethereum-lisp.cli:devnet-join-peer-sessions sessions))
           (is (null thread-error)))
      (ethereum-lisp.cli:devnet-shutdown-request controller)
      (when thread
        (ignore-errors (sb-thread:join-thread thread :timeout 5
                                                     :default :timeout))))))
