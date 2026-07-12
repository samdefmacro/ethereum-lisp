(defparameter *ethereum-lisp-selector-script-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(require :asdf)
(load (merge-pathnames "scripts/selector-application.lisp"
                       *ethereum-lisp-selector-script-root*))

(ethereum-lisp.selector-application:run-selector-application
 :transaction
 (uiop:command-line-arguments)
 :repository-root *ethereum-lisp-selector-script-root*)
