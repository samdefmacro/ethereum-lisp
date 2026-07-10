(defpackage #:ethereum-lisp.package-tools
  (:use #:cl)
  (:export
   #:define-api-package
   #:define-reexport-package))

(in-package #:ethereum-lisp.package-tools)

(defmacro define-api-package (name &body imports)
  "Define NAME from owner-grouped imports and export every imported symbol."
  (let ((exports
          (remove-duplicates
           (loop for import in imports
                 append (rest import))
           :test #'string=
           :key #'symbol-name)))
    `(defpackage ,name
       (:use #:cl)
       ,@(loop for (package . symbols) in imports
               collect `(:import-from ,package ,@symbols))
       (:export ,@exports))))

(defmacro define-reexport-package (name source)
  "Define NAME as a compatibility facade over SOURCE's external symbols."
  (let* ((source-package (or (find-package source)
                             (error "Package ~A does not exist" source)))
         (exports
           (sort
            (loop for symbol being the external-symbols of source-package
                  collect (make-symbol (symbol-name symbol)))
            #'string<
            :key #'symbol-name)))
    `(defpackage ,name
       (:use #:cl ,source)
       (:export ,@exports))))

(in-package #:cl-user)
