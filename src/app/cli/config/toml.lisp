(in-package #:ethereum-lisp.cli)

;;;; Minimal TOML value helpers for geth-style devnet config files.

(defun devnet-cli-toml-strip-comment (line)
  (loop for index below (length line)
        for char = (char line index)
        with in-string-p = nil
        with escaped-p = nil
        do (cond
             (escaped-p
              (setf escaped-p nil))
             ((and in-string-p (char= char #\\))
              (setf escaped-p t))
             ((char= char #\")
              (setf in-string-p (not in-string-p)))
             ((and (not in-string-p) (char= char #\#))
              (return (subseq line 0 index))))
        finally (return line)))

(defun devnet-cli-toml-trim (value)
  (string-trim '(#\Space #\Tab #\Newline #\Return) value))

(defun devnet-cli-toml-parse-string-at (value start)
  (unless (and (< start (length value))
               (char= #\" (char value start)))
    (error "TOML string value must begin with a quote"))
  (let ((output (make-string-output-stream))
        (index (1+ start))
        (escaped-p nil))
    (loop while (< index (length value))
          for char = (char value index)
          do (cond
               (escaped-p
                (write-char
                 (case char
                   (#\" #\")
                   (#\\ #\\)
                   (#\/ #\/)
                   (#\b #\Backspace)
                   (#\t #\Tab)
                   (#\n #\Newline)
                   (#\f #\Page)
                   (#\r #\Return)
                   (t char))
                 output)
                (setf escaped-p nil))
               ((char= char #\\)
                (setf escaped-p t))
               ((char= char #\")
                (return (values (get-output-stream-string output)
                                (1+ index))))
               (t
                (write-char char output)))
          do (incf index)
          finally (error "Unterminated TOML string value"))))

(defun devnet-cli-toml-skip-space (value index)
  (loop while (and (< index (length value))
                   (member (char value index)
                           '(#\Space #\Tab #\Newline #\Return)))
        do (incf index)
        finally (return index)))

(defun devnet-cli-toml-parse-string-array (value)
  (let* ((value (devnet-cli-toml-trim value))
         (length (length value)))
    (unless (and (<= 2 length)
                 (char= #\[ (char value 0))
                 (char= #\] (char value (1- length))))
      (error "TOML array value must be bracketed"))
    (let ((index (devnet-cli-toml-skip-space value 1))
          (items nil))
      (loop
        (setf index (devnet-cli-toml-skip-space value index))
        (when (>= index (1- length))
          (return (nreverse items)))
        (multiple-value-bind (item next-index)
            (devnet-cli-toml-parse-string-at value index)
          (push item items)
          (setf index (devnet-cli-toml-skip-space value next-index))
          (cond
            ((and (< index (1- length))
                  (char= #\, (char value index)))
             (incf index))
            ((= index (1- length))
             (return (nreverse items)))
            (t
             (error "TOML string arrays must contain comma-separated strings"))))))))

(defun devnet-cli-toml-parse-value (value)
  (let ((value (devnet-cli-toml-trim value)))
    (cond
      ((zerop (length value))
       "")
      ((char= #\" (char value 0))
       (multiple-value-bind (parsed next-index)
           (devnet-cli-toml-parse-string-at value 0)
         (unless (zerop (length (devnet-cli-toml-trim
                                 (subseq value next-index))))
           (error "Unexpected text after TOML string value"))
         parsed))
      ((char= #\[ (char value 0))
       (devnet-cli-toml-parse-string-array value))
      (t
       value))))
