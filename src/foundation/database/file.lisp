(in-package #:ethereum-lisp.database)

(defun kv-serialize-file-database (database)
  (list
   :ethereum-lisp-kv-v1
   (mapcar
    (lambda (entry)
      (list (kv-key-string (kv-memory-entry-key entry))
            (bytes-to-hex (kv-memory-entry-value entry))))
    (kv-database-sorted-entries database))))

(defun kv-file-records (object)
  (unless (and (consp object)
               (eq (first object) :ethereum-lisp-kv-v1)
               (listp (second object))
               (null (cddr object)))
    (error "Invalid key-value database file"))
  (second object))

(defun kv-file-database-temp-path (path)
  (let* ((pathname (pathname path))
         (name (or (pathname-name pathname) "kv"))
         (type (pathname-type pathname)))
    (make-pathname
     :name (format nil ".~A.~A" name (symbol-name (gensym "TMP")))
     :type type
     :defaults pathname)))

(defun kv-load-file-database (database)
  (let ((path (file-key-value-database-path database)))
    (when (probe-file path)
      (with-open-file (stream path :direction :input)
        (let ((*read-eval* nil))
          (dolist (record (kv-file-records (read stream nil nil)))
            (unless (and (consp record)
                         (stringp (first record))
                         (stringp (second record))
                         (null (cddr record)))
              (error "Invalid key-value database record"))
            (kv-put-memory-entry
             database
             (hex-to-bytes (first record))
             (hex-to-bytes (second record))))))))
  database)

(defun kv-persist-file-database (database)
  (let* ((path (file-key-value-database-path database))
         (temp-path (kv-file-database-temp-path path))
         (renamed-p nil))
    (ensure-directories-exist path)
    (unwind-protect
         (progn
           (with-open-file (stream temp-path
                                   :direction :output
                                   :if-exists :error
                                   :if-does-not-exist :create)
             (let ((*print-readably* t)
                   (*print-pretty* nil))
               (write (kv-serialize-file-database database) :stream stream)
               (terpri stream)))
           (uiop:rename-file-overwriting-target temp-path path)
           (setf renamed-p t))
      (unless renamed-p
        (when (probe-file temp-path)
          (ignore-errors (delete-file temp-path))))))
  database)

(defun make-file-key-value-database (path)
  (let ((database (make-instance 'file-key-value-database :path path)))
    (kv-load-file-database database)
    database))

(defmethod kv-put ((database file-key-value-database) key value)
  (kv-put-memory-entry database key value)
  (kv-persist-file-database database))

(defmethod kv-delete ((database file-key-value-database) key)
  (let ((deleted-p (kv-delete-memory-entry database key)))
    (when deleted-p
      (kv-persist-file-database database))
    deleted-p))
