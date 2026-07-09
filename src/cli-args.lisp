(in-package #:ethereum-lisp.cli)

(defun devnet-cli-option-token-p (value)
  (and (stringp value)
       (<= 2 (length value))
       (string= "--" value :end2 2)))

(defun devnet-cli-normalize-option-args (args)
  (loop for arg in args
        for separator = (and (devnet-cli-option-token-p arg)
                             (position #\= arg :start 2))
        append (if separator
                   (list (subseq arg 0 separator)
                         (subseq arg (1+ separator)))
                   (list arg))))

(defun devnet-cli-parse-boolean-token (value option)
  (let ((normalized (and (stringp value) (string-downcase value))))
    (cond
      ((member normalized '("true" "1") :test #'string=) t)
      ((member normalized '("false" "0") :test #'string=) nil)
      (t (error "~A boolean value must be true or false" option)))))

(defun devnet-cli-boolean-token-p (value)
  (and (stringp value)
       (member (string-downcase value)
               '("true" "false" "1" "0")
               :test #'string=)))

(defun devnet-cli-command-position (args command)
  (let ((args (devnet-cli-normalize-option-args args))
        (position 0))
    (loop while args
          for token = (pop args)
          do (cond
               ((devnet-cli-option-token-p token)
                (incf position)
                (cond
                  ((member token *devnet-cli-value-options* :test #'string=)
                   (when args
                     (pop args)
                     (incf position)))
                  ((member token
                           *devnet-cli-optional-boolean-options*
                           :test #'string=)
                   (when (and args
                              (not (devnet-cli-option-token-p (first args)))
                              (devnet-cli-boolean-token-p (first args)))
                     (pop args)
                     (incf position)))
                  (t
                   (when (and args
                              (not (devnet-cli-option-token-p (first args))))
                     (pop args)
                     (incf position)))))
               (t
                (return (and (string= token command) position))))
          finally (return nil))))

(defun devnet-cli-remove-command-token (args command)
  (let* ((args (devnet-cli-normalize-option-args args))
         (position (devnet-cli-command-position args command)))
    (if position
        (loop for arg in args
              for index from 0
              unless (= index position)
                collect arg)
        args)))

(defun devnet-cli-init-command-p (args)
  (devnet-cli-command-position args "init"))

(defun devnet-cli-optional-boolean-value (args option)
  (if (and args
           (not (devnet-cli-option-token-p (first args))))
      (values (devnet-cli-parse-boolean-token (first args) option)
              (rest args))
      (values t args)))

(defun devnet-cli-consume-optional-boolean-value (args option)
  (multiple-value-bind (enabled-p rest)
      (devnet-cli-optional-boolean-value args option)
    (declare (ignore enabled-p))
    rest))

(defun devnet-cli-next-value (args option)
  (unless (and args
               (not (devnet-cli-option-token-p (first args))))
    (error "~A requires a value" option))
  (values (first args) (rest args)))

(defun devnet-cli-consume-value-option (args option)
  (multiple-value-bind (value rest)
      (devnet-cli-next-value args option)
    (declare (ignore value))
    rest))
