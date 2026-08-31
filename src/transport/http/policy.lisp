(in-package #:ethereum-lisp.rpc-http)

(defparameter *engine-rpc-http-response-connection* "close"
  "Connection header emitted by the response helpers.

The request-stream adapter binds this to KEEP-ALIVE only while serving a valid
persistent HTTP/1.1 request.  Direct request-string callers retain the historic
single-request CLOSE behaviour.")

(defun engine-rpc-http-cors-wildcard-p (origins)
  (member "*" origins :test #'string=))

(defun engine-rpc-http-cors-response-headers (headers origins)
  (let ((origin (engine-rpc-http-header headers "origin")))
    (cond
      ((null origins)
       (values nil t))
      ((engine-rpc-http-cors-wildcard-p origins)
       (values
        '(("Access-Control-Allow-Origin" . "*")
          ("Access-Control-Allow-Methods" . "GET, POST, OPTIONS")
          ("Access-Control-Allow-Headers" . "Authorization, Content-Type"))
        t))
      ((and origin (member origin origins :test #'string=))
       (values
        `(("Access-Control-Allow-Origin" . ,origin)
          ("Access-Control-Allow-Methods" . "GET, POST, OPTIONS")
          ("Access-Control-Allow-Headers" . "Authorization, Content-Type")
          ("Vary" . "Origin"))
        t))
      (origin
       (values nil nil))
      (t
       (values
        '(("Access-Control-Allow-Methods" . "GET, POST, OPTIONS")
          ("Access-Control-Allow-Headers" . "Authorization, Content-Type"))
        t)))))

(defun engine-rpc-http-host-wildcard-p (hosts)
  (member "*" hosts :test #'string=))

(defun engine-rpc-http-host-name (host)
  (let ((host (and host (engine-rpc-http-trim host))))
    (cond
      ((or (null host) (zerop (length host)))
       nil)
      ((and (char= #\[ (char host 0))
            (position #\] host))
       (subseq host 0 (1+ (position #\] host))))
      (t
       (let ((colon (position #\: host :from-end t)))
         (if colon
             (subseq host 0 colon)
             host))))))

(defun engine-rpc-http-ipv4-literal-p (host)
  "True when HOST is a dotted-decimal IPv4 literal: four 0-255 octets."
  (and (plusp (length host))
       (loop with start = 0
             with octets = 0
             for dot = (position #\. host :start start)
             for end = (or dot (length host))
             for field = (subseq host start end)
             do (unless (and (plusp (length field))
                             (<= (length field) 3)
                             (every #'digit-char-p field)
                             (<= (parse-integer field) 255))
                  (return nil))
                (incf octets)
                (if dot
                    (setf start (1+ dot))
                    (return (= octets 4))))))

(defun engine-rpc-http-bracketed-ipv6-literal-p (host)
  "True when HOST is a bracketed IPv6 literal such as \"[::1]\". ENGINE-RPC-HTTP-
HOST-NAME preserves the brackets, so an IPv6 Host header arrives in this form."
  (let ((length (length host)))
    (and (>= length 4)
         (char= #\[ (char host 0))
         (char= #\] (char host (1- length)))
         (let ((inner (subseq host 1 (1- length))))
           (and (find #\: inner)
                (every (lambda (character)
                         (or (digit-char-p character 16)
                             (char= character #\:)
                             (char= character #\.)
                             (char= character #\%)))
                       inner))))))

(defun engine-rpc-http-ip-literal-host-p (host)
  "True when HOST is a raw IP literal -- an IPv4 address or a bracketed IPv6
address. geth's virtualHostHandler accepts a parsed IP regardless of the
configured virtual hosts, because an IP in the Host header is not a DNS-rebinding
vector. Mirror that, so the default IP-literal Engine URL http://127.0.0.1:PORT
is not answered with 403 when vhosts default to (\"localhost\")."
  (and host
       (or (engine-rpc-http-ipv4-literal-p host)
           (engine-rpc-http-bracketed-ipv6-literal-p host))))

(defun engine-rpc-http-host-allowed-p (headers allowed-hosts)
  (or (null allowed-hosts)
      (engine-rpc-http-host-wildcard-p allowed-hosts)
      (let ((host (engine-rpc-http-host-name
                   (engine-rpc-http-header headers "host"))))
        (and host
             (or (engine-rpc-http-ip-literal-host-p host)
                 (member host allowed-hosts :test #'string-equal))))))

(defun engine-rpc-http-response-string (status-code reason body
                                        &key
                                          (content-type "application/json")
                                          extra-headers)
  (with-output-to-string (stream)
    (format stream "HTTP/1.1 ~D ~A~C~C" status-code reason
            #\Return #\Newline)
    (when content-type
      (format stream "Content-Type: ~A~C~C"
              content-type #\Return #\Newline))
    (dolist (header extra-headers)
      (format stream "~A: ~A~C~C"
              (car header)
              (cdr header)
              #\Return #\Newline))
    (format stream "Connection: ~A~C~C"
            *engine-rpc-http-response-connection* #\Return #\Newline)
    ;; Content-Length counts octets, and the socket stream encodes the body as
    ;; UTF-8, so a body with any non-ASCII character (a revert reason, say) has
    ;; more octets than characters and a character count would truncate it.
    (format stream "Content-Length: ~D~C~C"
            (engine-rpc-http-octet-length body) #\Return #\Newline)
    (format stream "~C~C" #\Return #\Newline)
    (write-string body stream)))

(defun engine-rpc-http-error-response
    (status-code reason message &key extra-headers)
  (engine-rpc-http-response-string
   status-code reason message
   :content-type "text/plain"
   :extra-headers extra-headers))
