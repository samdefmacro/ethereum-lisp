(defparameter *ethereum-lisp-script-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun ethereum-lisp-script-arguments ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (rest args)))
    args)
  #-sbcl
  nil)

(require :asdf)

(asdf:load-asd
 (merge-pathnames "ethereum-lisp.asd" *ethereum-lisp-script-root*))
(asdf:load-system :ethereum-lisp)

(let ((exit-code (ethereum-lisp.cli:main (ethereum-lisp-script-arguments))))
  #+sbcl
  (sb-ext:exit :code exit-code)
  #-sbcl
  (uiop:quit exit-code))
