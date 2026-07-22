(in-package #:ethereum-lisp.rpc-http)

;;;; Request intake limits.
;;;;
;;;; Without these a single connection can hold an endpoint open indefinitely or
;;;; make the node allocate from an attacker-supplied Content-Length. Requests
;;;; are served one at a time, so an unbounded read stalls every other client.

(defparameter *engine-rpc-http-max-body-bytes* (* 5 1024 1024)
  "Largest accepted request body. Matches go-ethereum's RPC content limit.")

(defparameter *engine-rpc-http-max-header-bytes* (* 1024 1024)
  "Largest accepted header block, matching Go's default MaxHeaderBytes.")

(defparameter *engine-rpc-http-max-header-lines* 200
  "Largest accepted number of header lines, including the request line.")

(defparameter *engine-rpc-http-request-timeout-seconds* 30
  "Wall-clock seconds allowed for reading and answering one request.

NIL disables the deadline. A peer that connects and then sends nothing would
otherwise block the listener forever.")

(defparameter *engine-rpc-http-max-concurrent-connections* nil
  "Connections served at once. NIL, the default, serves them one at a time.

Concurrency here covers socket I/O, so one slow or silent peer stops starving
every other caller. It is opt-in because request handling is only serialised
when the service was given a request guard: the node supplies one, but a service
constructed without it would run handlers against shared state concurrently.
Enable this only alongside a request guard.")

(defmacro engine-rpc-http-with-request-deadline (&body body)
  "Run BODY under the configured request deadline, when one is set.

A deadline that expires is re-signalled as a plain error. SBCL's
DEADLINE-TIMEOUT inherits SERIOUS-CONDITION, not ERROR, so it passes straight
through every (error (condition) ...) handler containing a connection — the
expiry would tear down the listener instead of the one stalled request."
  #+sbcl
  `(let ((timeout *engine-rpc-http-request-timeout-seconds*))
     (if timeout
         (handler-case (sb-sys:with-deadline (:seconds timeout) ,@body)
           (sb-sys:deadline-timeout ()
             (error "HTTP request exceeded the ~A second deadline" timeout)))
         (progn ,@body)))
  #-sbcl
  `(progn ,@body))

(defparameter +engine-rpc-http-accepted-content-types+
  '("application/json" "application/json-rpc" "application/jsonrequest"))

(defun engine-rpc-http-trim (string)
  (string-trim '(#\Space #\Tab #\Return #\Newline) string))

(defun engine-rpc-http-split-lines (string)
  (loop with start = 0
        for end = (position #\Newline string :start start)
        collect (engine-rpc-http-trim
                 (subseq string start (or end (length string))))
        while end
        do (setf start (1+ end))))

(defun engine-rpc-http-request-target (request-line)
  (let* ((first-space (position #\Space request-line))
         (second-space
           (and first-space
                (position #\Space request-line :start (1+ first-space))))
         (third-space
           (and second-space
                (position #\Space request-line :start (1+ second-space)))))
    (unless (and first-space second-space (not third-space))
      (block-validation-fail "HTTP request line is malformed"))
    (let ((version (subseq request-line (1+ second-space))))
      (unless (string= version "HTTP/1.1")
        (block-validation-fail "HTTP request line is malformed"))
      (values (subseq request-line 0 first-space)
              (subseq request-line (1+ first-space) second-space)))))

(defun engine-rpc-http-target-path (target)
  (if (and (stringp target)
           (plusp (length target))
           (char= #\/ (char target 0)))
      (subseq target 0 (or (position #\? target)
                           (length target)))
      target))

(defun engine-rpc-http-target-allowed-p (target rpc-prefix)
  (let ((path (engine-rpc-http-target-path target)))
    (or (string= path rpc-prefix)
        (and (< (length rpc-prefix) (length path))
             (not (string= rpc-prefix "/"))
             (string-prefix-p rpc-prefix path)
             (char= #\/ (char path (length rpc-prefix)))))))

(defun engine-rpc-http-headers (lines)
  ;; Lines read from a socket keep their carriage return, so the blank line
  ;; separating headers from the body arrives as a lone CR rather than an empty
  ;; string. Comparing untrimmed rejected every CRLF request — that is, every
  ;; standards-compliant client — as a malformed header.
  (loop for line in lines
        for trimmed = (engine-rpc-http-trim line)
        unless (string= trimmed "")
          collect
          (let ((colon (position #\: trimmed)))
            (unless colon
              (block-validation-fail "HTTP header is malformed"))
            (let ((name (engine-rpc-http-trim (subseq trimmed 0 colon))))
              (when (string= name "")
                (block-validation-fail "HTTP header is malformed"))
              (cons (string-downcase name)
                    (engine-rpc-http-trim (subseq trimmed (1+ colon))))))))

(defun engine-rpc-http-header (headers name)
  (cdr (assoc (string-downcase name) headers :test #'string=)))

(defun engine-rpc-http-header-values (headers name)
  (loop with normalized = (string-downcase name)
        for (header-name . value) in headers
        when (string= normalized header-name)
          collect value))

(defun engine-rpc-http-single-header (headers name)
  (let ((values (engine-rpc-http-header-values headers name)))
    (when (rest values)
      (block-validation-fail "HTTP ~A header is duplicated" name))
    (first values)))

(defun engine-rpc-http-media-type (content-type)
  (when content-type
    (string-downcase
     (engine-rpc-http-trim
      (subseq content-type
              0
              (or (position #\; content-type)
                  (length content-type)))))))

(defun engine-rpc-http-accepted-content-type-p (content-type)
  (let ((media-type (engine-rpc-http-media-type content-type)))
    (and media-type
         (member media-type
                 +engine-rpc-http-accepted-content-types+
                 :test #'string=))))

(defun engine-rpc-http-decimal-digits-p (string)
  (and (< 0 (length string))
       (every #'digit-char-p string)))

(defun engine-rpc-http-parse-content-length (content-length)
  (let ((content-length (engine-rpc-http-trim content-length)))
    (unless (engine-rpc-http-decimal-digits-p content-length)
      (block-validation-fail "HTTP content length is invalid"))
    (parse-integer content-length :junk-allowed nil)))

(defun engine-rpc-http-header-boundary (request)
  (let ((crlf-boundary
          (search (format nil "~C~C~C~C"
                          #\Return #\Newline #\Return #\Newline)
                  request))
        (lf-boundary (search (format nil "~C~C" #\Newline #\Newline)
                             request)))
    (cond
      (crlf-boundary (values crlf-boundary 4))
      (lf-boundary (values lf-boundary 2))
      (t (block-validation-fail "HTTP request is missing header boundary")))))

(defun engine-rpc-http-body (body headers)
  (let ((content-lengths (engine-rpc-http-header-values headers "content-length")))
    (cond
      ((null content-lengths)
       body)
      ((rest content-lengths)
       (block-validation-fail "HTTP content length is duplicated"))
      (t
        (let ((length
                (engine-rpc-http-parse-content-length
                 (first content-lengths))))
          (unless (<= length (length body))
            (block-validation-fail "HTTP content length is invalid"))
          (subseq body 0 length))))))

(defun engine-rpc-http-content-length (headers)
  (let ((content-lengths (engine-rpc-http-header-values headers "content-length")))
    (cond
      ((null content-lengths)
       0)
      ((rest content-lengths)
       (block-validation-fail "HTTP content length is duplicated"))
      (t
       (engine-rpc-http-parse-content-length (first content-lengths))))))

(defun engine-rpc-read-http-request-string (input-stream)
  (let ((lines '())
        (header-bytes 0)
        (header-lines 0))
    (loop for line = (read-line input-stream nil nil)
          while line
          do (incf header-lines)
             (incf header-bytes (1+ (length line)))
             (when (> header-lines *engine-rpc-http-max-header-lines*)
               (block-validation-fail "HTTP request has too many header lines"))
             (when (> header-bytes *engine-rpc-http-max-header-bytes*)
               (block-validation-fail "HTTP request headers are too large"))
             (push line lines)
             (when (string= "" (engine-rpc-http-trim line))
               (return)))
    (unless (and lines (string= "" (engine-rpc-http-trim (first lines))))
      (block-validation-fail "HTTP request is missing header boundary"))
    (let* ((lines (nreverse lines))
           (headers (engine-rpc-http-headers (rest lines)))
           (content-length (engine-rpc-http-content-length headers))
           ;; Check the declared length before allocating for it.
           (content-length
             (if (> content-length *engine-rpc-http-max-body-bytes*)
                 (block-validation-fail "HTTP request body is too large")
                 content-length))
           (body (make-string content-length))
           (read-count (read-sequence body input-stream)))
      (unless (= read-count content-length)
        (block-validation-fail
         "HTTP request body is shorter than content length"))
      (with-output-to-string (request)
        (dolist (line lines)
          (write-string (engine-rpc-http-trim line) request)
          (format request "~C~C" #\Return #\Newline))
        (write-string body request)))))
