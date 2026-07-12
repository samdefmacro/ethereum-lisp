(defparameter *ethereum-lisp-test-loader-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(require :asdf)

(asdf:load-asd
 (merge-pathnames "ethereum-lisp.asd" *ethereum-lisp-test-loader-root*))
(asdf:load-system '#:ethereum-lisp/test)
