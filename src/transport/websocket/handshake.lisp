(in-package #:ethereum-lisp.websocket)

;;;; The opening handshake (RFC 6455 section 4).
;;;;
;;;; A WebSocket connection begins as an ordinary HTTP GET carrying an Upgrade.
;;;; The server proves it understood by returning SHA-1 of the client's key
;;;; concatenated with a fixed GUID -- which is not authentication and was never
;;;; meant to be. It exists so that a cache or a proxy that replays a canned
;;;; 101 cannot accidentally look like a WebSocket endpoint. SHA-1 is fine here
;;;; for the same reason: nothing about the exchange is secret.

(defparameter +websocket-guid+ "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  "The magic value RFC 6455 section 1.3 fixes. Every implementation uses it.

DEFPARAMETER rather than DEFCONSTANT, like the alphabet below: a DEFCONSTANT
whose value is a string breaks on reload, because the reloaded literal is not
EQL to the old one and the standard says that is a redefinition.")

(defparameter +websocket-base64-alphabet+
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

(defun websocket-base64-encode (bytes)
  "BYTES in standard base64, padded.

Not the base64url next door in the JWT code: that one uses -/_ and drops the
padding, and Sec-WebSocket-Accept is compared literally by every client, so the
+/ alphabet and the = padding are both load-bearing."
  (let ((bytes (ensure-byte-vector bytes)))
    (with-output-to-string (out)
      (loop for index from 0 below (length bytes) by 3
            for remaining = (- (length bytes) index)
            for b0 = (aref bytes index)
            for b1 = (if (>= remaining 2) (aref bytes (+ index 1)) 0)
            for b2 = (if (>= remaining 3) (aref bytes (+ index 2)) 0)
            for value = (logior (ash b0 16) (ash b1 8) b2)
            do (write-char (aref +websocket-base64-alphabet+
                                 (ldb (byte 6 18) value))
                           out)
               (write-char (aref +websocket-base64-alphabet+
                                 (ldb (byte 6 12) value))
                           out)
               (if (>= remaining 2)
                   (write-char (aref +websocket-base64-alphabet+
                                     (ldb (byte 6 6) value))
                               out)
                   (write-char #\= out))
               (if (>= remaining 3)
                   (write-char (aref +websocket-base64-alphabet+
                                     (ldb (byte 6 0) value))
                               out)
                   (write-char #\= out))))))

(defun websocket-accept-token (key)
  "The Sec-WebSocket-Accept value for the client's Sec-WebSocket-KEY."
  (websocket-base64-encode
   (ironclad:digest-sequence
    :sha1
    (coerce (ascii-to-bytes (concatenate 'string key +websocket-guid+))
            '(vector (unsigned-byte 8))))))

(defun websocket-header-value (headers name)
  "The value of header NAME, matched case-insensitively as HTTP requires."
  (cdr (assoc name headers :test #'string-equal)))

(defun websocket-header-contains-token-p (value token)
  "Whether the comma-separated header VALUE lists TOKEN.

`Connection: keep-alive, Upgrade` is a legitimate thing for a client to send, so
matching the whole value against \"Upgrade\" rejects real clients."
  (when value
    (let ((start 0))
      (loop
        (let* ((comma (position #\, value :start start))
               (item (string-trim '(#\Space #\Tab)
                                  (subseq value start (or comma (length value))))))
          (when (string-equal item token)
            (return t))
          (unless comma (return nil))
          (setf start (1+ comma)))))))

(defun websocket-upgrade-request-p (method headers)
  "Whether METHOD and HEADERS are a WebSocket upgrade rather than plain HTTP.

Checked before the handshake is validated, so a normal GET to the same port can
still be answered with an ordinary HTTP response instead of a protocol error."
  (and (stringp method)
       (string-equal method "GET")
       (websocket-header-contains-token-p
        (websocket-header-value headers "Upgrade") "websocket")
       (websocket-header-contains-token-p
        (websocket-header-value headers "Connection") "Upgrade")))

(defun websocket-origin-scheme-p (text)
  "Whether TEXT is a URL scheme as Go's url.Parse accepts one."
  (and (plusp (length text))
       (alpha-char-p (char text 0))
       (every (lambda (char)
                (or (alphanumericp char) (find char "+-.")))
              text)))

(defun websocket-split-host-port (host-port)
  "(VALUES HOSTNAME PORT) the way Go's URL.Hostname and URL.Port split them."
  (let ((host-port (subseq host-port (1+ (or (position #\@ host-port) -1)))))
    (if (and (plusp (length host-port)) (char= #\[ (char host-port 0)))
        (let ((close (position #\] host-port)))
          (if close
              (values (subseq host-port 1 close)
                      (if (and (< (1+ close) (length host-port))
                               (char= #\: (char host-port (1+ close))))
                          (subseq host-port (+ 2 close))
                          ""))
              (values host-port "")))
        (let ((colon (position #\: host-port :from-end t)))
          (if (and colon
                   (every #'digit-char-p (subseq host-port (1+ colon))))
              (values (subseq host-port 0 colon) (subseq host-port (1+ colon)))
              (values host-port ""))))))

(defun websocket-parse-origin (origin)
  "(VALUES SCHEME HOSTNAME PORT) of ORIGIN, or NIL when it does not parse.

A port of geth's parseOriginURL (rpc/websocket.go:167-190 at 38271784): with
\"://\" the parts are the URL's scheme, hostname and port; without it, Go reads
\"host:port\" as scheme and opaque, which geth then uses as hostname and port,
and anything else as a bare hostname. Go refuses a first segment that has a
colon but is not a scheme (\"12.34.56.78:80\"), so that is NIL here too."
  (let* ((origin (string-downcase origin))
         (separator (search "://" origin)))
    (if separator
        (let* ((rest (subseq origin (+ 3 separator)))
               (host-port (subseq rest 0 (or (position-if (lambda (char)
                                                            (find char "/?#"))
                                                          rest)
                                             (length rest)))))
          (multiple-value-bind (hostname port)
              (websocket-split-host-port host-port)
            (values (subseq origin 0 separator) hostname port)))
        (let ((colon (position #\: origin)))
          (cond
            ((null colon) (values "" origin ""))
            ((websocket-origin-scheme-p (subseq origin 0 colon))
             (values "" (subseq origin 0 colon) (subseq origin (1+ colon))))
            (t nil))))))

(defun websocket-origin-rule-allows-p (rule origin)
  "Whether allowed-origin RULE admits the browser ORIGIN (geth's
ruleAllowsOrigin, rpc/websocket.go:139-165): every part the rule names --
scheme, hostname, port -- must match exactly; a part it leaves out matches
anything."
  (multiple-value-bind (rule-scheme rule-host rule-port)
      (websocket-parse-origin rule)
    (multiple-value-bind (scheme host port) (websocket-parse-origin origin)
      (and rule-host host
           (or (string= rule-scheme "") (string= rule-scheme scheme))
           (or (string= rule-host "") (string= rule-host host))
           (or (string= rule-port "") (string= rule-port port))))))

(defun websocket-default-allowed-origins ()
  "What geth allows when no origin is configured (rpc/websocket.go:84-89):
http://localhost and http://HOSTNAME."
  (let ((hostname (ignore-errors (machine-instance))))
    (if (and hostname (plusp (length hostname)))
        (list "http://localhost"
              (concatenate 'string "http://" (string-downcase hostname)))
        (list "http://localhost"))))

(defun websocket-origin-allowed-p (origin allowed-origins)
  "Whether ORIGIN may open a connection, as geth's wsHandshakeValidator decides
(rpc/websocket.go:71-113 at 38271784).

ORIGIN is NIL when the request carried no Origin header: that is not a browser,
the header's absence makes no claim to check, and it is allowed. A present
header, even an empty one, is checked. \"*\" allows every origin. With no
configured origin the allow list is geth's default, http://localhost and
http://HOSTNAME -- not \"anything\", which is what this used to mean."
  (cond
    ((null origin) t)
    ((member "*" allowed-origins :test #'string=) t)
    (t
     (let ((rules (or (remove "" allowed-origins :test #'string=)
                      (websocket-default-allowed-origins))))
       (and (some (lambda (rule) (websocket-origin-rule-allows-p rule origin))
                  rules)
            t)))))


(defun websocket-handshake-response (method target headers
                                     &key allowed-origins (rpc-prefix "/"))
  "The HTTP response to an upgrade attempt, as a string.

Returns (VALUES RESPONSE ACCEPTED-P). A refusal is a normal HTTP error response
rather than a signalled condition, because the client is still speaking HTTP at
this point and an HTTP client deserves an HTTP answer."
  (let ((key (websocket-header-value headers "Sec-WebSocket-Key"))
        (version (websocket-header-value headers "Sec-WebSocket-Version"))
        (origin (websocket-header-value headers "Origin"))
        (path (websocket-request-path target)))
    (cond
      ((not (websocket-upgrade-request-p method headers))
       (values (websocket-http-error 400 "Bad Request"
                                     "expected a WebSocket upgrade")
               nil))
      ((not (string= path rpc-prefix))
       (values (websocket-http-error 404 "Not Found" "no endpoint at that path")
               nil))
      ;; 13 is the only version RFC 6455 defines. The reply names what we do
      ;; support, which is what lets an older client fall back rather than guess.
      ((not (equal version "13"))
       (values (websocket-http-error 400 "Bad Request"
                                     "unsupported WebSocket version"
                                     :extra-headers '("Sec-WebSocket-Version: 13"))
               nil))
      ((or (null key) (string= key ""))
       (values (websocket-http-error 400 "Bad Request"
                                     "missing Sec-WebSocket-Key")
               nil))
      ((not (websocket-origin-allowed-p origin allowed-origins))
       (values (websocket-http-error 403 "Forbidden" "origin not allowed") nil))
      (t
       (values
        (format nil
                "HTTP/1.1 101 Switching Protocols~C~C~
                 Upgrade: websocket~C~C~
                 Connection: Upgrade~C~C~
                 Sec-WebSocket-Accept: ~A~C~C~C~C"
                #\Return #\Newline #\Return #\Newline #\Return #\Newline
                (websocket-accept-token key)
                #\Return #\Newline #\Return #\Newline)
        t)))))

(defun websocket-request-path (target)
  "TARGET without its query string."
  (if (stringp target)
      (subseq target 0 (or (position #\? target) (length target)))
      ""))

(defun websocket-http-error (status reason body &key extra-headers)
  "A plain HTTP error response, for a client that has not become a WebSocket."
  (with-output-to-string (out)
    (format out "HTTP/1.1 ~D ~A~C~C" status reason #\Return #\Newline)
    (format out "Content-Type: text/plain; charset=utf-8~C~C" #\Return #\Newline)
    (format out "Content-Length: ~D~C~C"
            (length (string-to-utf8-bytes body)) #\Return #\Newline)
    (dolist (header extra-headers)
      (format out "~A~C~C" header #\Return #\Newline))
    (format out "Connection: close~C~C" #\Return #\Newline)
    (format out "~C~C" #\Return #\Newline)
    (write-string body out)))
