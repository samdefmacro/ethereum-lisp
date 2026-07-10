(in-package #:ethereum-lisp.core)

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
  (loop for line in lines
        unless (string= line "")
          collect
          (let ((colon (position #\: line)))
            (unless colon
              (block-validation-fail "HTTP header is malformed"))
            (let ((name (engine-rpc-http-trim (subseq line 0 colon))))
              (when (string= name "")
                (block-validation-fail "HTTP header is malformed"))
              (cons (string-downcase name)
                    (engine-rpc-http-trim (subseq line (1+ colon))))))))

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
