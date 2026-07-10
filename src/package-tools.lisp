(defpackage #:ethereum-lisp.package-tools
  (:use #:cl)
  (:export
   #:define-api-package
   #:define-reexport-package
   #:reexport-symbols))

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

(defun reexport-symbols (target source names)
  "Re-export selected external symbols from SOURCE through TARGET."
  (let ((target-package (or (find-package target)
                            (error "Package ~A does not exist" target)))
        (source-package (or (find-package source)
                            (error "Package ~A does not exist" source))))
    (dolist (name names target-package)
      (multiple-value-bind (symbol status)
          (find-symbol (string name) source-package)
        (unless (eq :external status)
          (error "~A is not external in package ~A" name source))
        (shadowing-import symbol target-package)
        (export symbol target-package)))))

(in-package #:cl-user)
