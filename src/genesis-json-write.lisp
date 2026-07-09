(in-package #:ethereum-lisp.core)

(defstruct (json-empty-object
            (:constructor make-json-empty-object ())))

(defparameter +json-empty-object+ (make-json-empty-object))

(defun write-json-string (string stream)
  (write-char #\" stream)
  (loop for char across string
        for code = (char-code char)
        do (case char
             (#\" (write-string "\\\"" stream))
             (#\\ (write-string "\\\\" stream))
             (#\Backspace (write-string "\\b" stream))
             (#\Page (write-string "\\f" stream))
             (#\Newline (write-string "\\n" stream))
             (#\Return (write-string "\\r" stream))
             (#\Tab (write-string "\\t" stream))
             (otherwise
              (if (< code #x20)
                  (format stream "\\u~4,'0x" code)
                  (write-char char stream)))))
  (write-char #\" stream))

(defun json-real-string (value)
  (let* ((text (format nil "~,12F" (coerce value 'double-float)))
         (dot (position #\. text)))
    (when dot
      (loop while (and (> (length text) (1+ dot))
                       (char= (char text (1- (length text))) #\0))
            do (setf text (subseq text 0 (1- (length text)))))
      (when (char= (char text (1- (length text))) #\.)
        (setf text (subseq text 0 (1- (length text))))))
    (if (string= text "-0") "0" text)))

(defun write-json-value (value stream)
  (cond
    ((null value) (write-string "null" stream))
    ((eq value t) (write-string "true" stream))
    ((eq value :false) (write-string "false" stream))
    ((json-empty-object-p value) (write-string "{}" stream))
    ((stringp value) (write-json-string value stream))
    ((integerp value) (write-string (write-to-string value :base 10) stream))
    ((realp value) (write-string (json-real-string value) stream))
    ((vectorp value)
     (write-char #\[ stream)
     (loop for index below (length value)
           for first-p = t then nil
           do (progn
                (unless first-p
                  (write-char #\, stream))
                (write-json-value (aref value index) stream)))
     (write-char #\] stream))
    ((json-object-p value)
     (write-char #\{ stream)
     (loop for (key . item) in value
           for first-p = t then nil
           do (progn
                (unless first-p
                  (write-char #\, stream))
                (write-json-string
                 (if (stringp key) key (string-downcase (symbol-name key)))
                 stream)
                (write-char #\: stream)
                (write-json-value item stream)))
     (write-char #\} stream))
    ((listp value)
     (write-char #\[ stream)
     (loop for item in value
           for first-p = t then nil
           do (progn
                (unless first-p
                  (write-char #\, stream))
                (write-json-value item stream)))
     (write-char #\] stream))
    (t (block-validation-fail "Cannot encode value as JSON"))))

(defun json-encode (value)
  (with-output-to-string (stream)
    (write-json-value value stream)))
