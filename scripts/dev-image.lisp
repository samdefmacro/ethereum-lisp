(defpackage #:ethereum-lisp.dev-image
  (:use #:cl))

(in-package #:ethereum-lisp.dev-image)

;; Required up front so the ASDF package exists when the SWANK loader below is
;; READ, not merely when it runs.
(require :asdf)

(defparameter *project-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun getenv (name)
  #+sbcl (sb-ext:posix-getenv name)
  #-sbcl (declare (ignore name))
  #-sbcl nil)

(defun true-env-p (name)
  (let ((value (getenv name)))
    (and value
         (not (member (string-downcase value) '("" "0" "false" "no")
                      :test #'string=)))))

(defun maybe-load-quicklisp ()
  (let ((setup (merge-pathnames "quicklisp/setup.lisp"
                                (user-homedir-pathname))))
    (when (probe-file setup)
      (load setup))))

(defun maybe-quickload (system)
  ;; FIND-SYMBOL signals when the package is missing, and it is missing
  ;; whenever Quicklisp was not loaded — the normal case in the Docker image.
  (let* ((package (find-package "QL"))
         (quickload (and package (find-symbol "QUICKLOAD" package))))
    (when quickload
      (handler-case
          (funcall quickload system :silent t)
        (error (condition)
          (format *error-output* "~&Could not quickload ~A: ~A~%"
                  system condition)
          nil)))))

(defun ensure-swank ()
  "Make the SWANK package available, or return NIL.

Quicklisp supplies it on a workstation; the Docker dev image has no Quicklisp
and installs Debian's cl-swank instead, which registers an ASDF system. REQUIRE
is the last resort for implementations that bundle it."
  (or (find-package "SWANK")
      (progn (maybe-quickload :swank) (find-package "SWANK"))
      (progn (ignore-errors (asdf:load-system :swank)) (find-package "SWANK"))
      (progn (ignore-errors (require :swank)) (find-package "SWANK"))))

(defun maybe-start-swank ()
  (let ((port (parse-integer (or (getenv "ETHEREUM_LISP_SWANK_PORT") "")
                             :junk-allowed t)))
    (when port
      (unless (ensure-swank)
        (error "ETHEREUM_LISP_SWANK_PORT was set, but SWANK could not be loaded."))
      (let ((create-server (find-symbol "CREATE-SERVER" "SWANK")))
        (unless create-server
          (error "SWANK:CREATE-SERVER is unavailable."))
        (funcall create-server :port port :dont-close t)
        (format t "~&Swank listening on localhost:~D.~%" port)))))

(defun load-project-tests ()
  (load (merge-pathnames "tests/load-tests.lisp" *project-root*)))

(defun find-test-symbol (name)
  (etypecase name
    (symbol name)
    (string (find-symbol (string-upcase name) "ETHEREUM-LISP.TEST"))))

(defun run-one-test (name)
  (let ((test (find-test-symbol name)))
    (unless (and test (fboundp test))
      (error "Unknown test ~S" name))
    (time (funcall test))))

(defun run-all-tests ()
  (time (funcall (find-symbol "RUN-ALL-TESTS" "ETHEREUM-LISP.TEST"))))

(maybe-load-quicklisp)
(load-project-tests)
(maybe-start-swank)

(setf (symbol-function 'cl-user::run-ethereum-lisp-test) #'run-one-test)
(setf (symbol-function 'cl-user::run-ethereum-lisp-tests) #'run-all-tests)

(format t "~&Ethereum Lisp dev image loaded.~%")
(format t "Use (run-ethereum-lisp-test \"trie-fixture-vectors\") for one test.~%")
(format t "Use (run-ethereum-lisp-tests) for the full suite.~%")

(when (true-env-p "ETHEREUM_LISP_DEV_IMAGE_WAIT")
  (format t "Waiting forever because ETHEREUM_LISP_DEV_IMAGE_WAIT is set.~%")
  (loop (sleep 3600)))
