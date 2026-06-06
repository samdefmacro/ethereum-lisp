(in-package #:ethereum-lisp.database)

(defclass key-value-database () ())

(defclass memory-key-value-database (key-value-database)
  ((entries :initform (make-hash-table :test 'equal)
            :accessor memory-key-value-database-entries)))

(defclass file-key-value-database (memory-key-value-database)
  ((path :initarg :path :reader file-key-value-database-path)))

(defstruct kv-memory-entry
  key
  value)

(defstruct (kv-write-batch (:constructor %make-kv-write-batch))
  operations)

(defgeneric kv-get (database key &optional default))
(defgeneric kv-put (database key value))
(defgeneric kv-delete (database key))
(defgeneric kv-apply-batch (database batch))
(defgeneric kv-iterator (database &key start end reverse-p))

(defparameter +kv-chain-record-kind-prefixes+
  '((:block . #x01)
    (:header . #x02)
    (:receipt . #x03)
    (:canonical-hash . #x04)
    (:checkpoint . #x05)
    (:state . #x06)
    (:transaction-location . #x07)))

(defun make-memory-key-value-database ()
  (make-instance 'memory-key-value-database))

(defun make-file-key-value-database (path)
  (let ((database (make-instance 'file-key-value-database :path path)))
    (kv-load-file-database database)
    database))

(defun make-kv-write-batch ()
  (%make-kv-write-batch :operations nil))

(defun kv-copy-bytes (bytes)
  (copy-seq (ensure-byte-vector bytes)))

(defun kv-key-string (key)
  (bytes-to-hex (ensure-byte-vector key)))

(defun kv-entry< (left right)
  (string< (kv-key-string (kv-memory-entry-key left))
           (kv-key-string (kv-memory-entry-key right))))

(defun kv-entry-in-range-p (entry start end)
  (let ((key (kv-key-string (kv-memory-entry-key entry)))
        (start-key (and start (kv-key-string start)))
        (end-key (and end (kv-key-string end))))
    (and (or (null start-key)
             (not (string< key start-key)))
         (or (null end-key)
             (string< key end-key)))))

(defun kv-chain-record-kind-prefix (kind)
  (or (cdr (assoc kind +kv-chain-record-kind-prefixes+))
      (error "Unknown chain record kind: ~S" kind)))

(defun kv-chain-record-uint64-bytes (number)
  (unless (and (integerp number)
               (<= 0 number)
               (< number (ash 1 64)))
    (error "Chain record numeric identifier must be a uint64"))
  (let ((bytes (make-byte-vector 8)))
    (dotimes (index 8 bytes)
      (setf (aref bytes (- 7 index))
            (ldb (byte 8 (* index 8)) number)))))

(defun kv-chain-record-identifier-bytes (identifier)
  (cond
    ((integerp identifier)
     (kv-chain-record-uint64-bytes identifier))
    ((stringp identifier)
     (ascii-to-bytes identifier))
    ((or (byte-vector-p identifier) (vectorp identifier))
     (kv-copy-bytes identifier))
    (t
     (error "Unsupported chain record identifier: ~S" identifier))))

(defun kv-chain-record-key (kind identifier)
  (concat-bytes
   (vector (kv-chain-record-kind-prefix kind))
   (kv-chain-record-identifier-bytes identifier)))

(defun kv-chain-record-key-identifier (kind key)
  (let ((bytes (ensure-byte-vector key))
        (prefix (kv-chain-record-kind-prefix kind)))
    (unless (and (> (length bytes) 0)
                 (= (aref bytes 0) prefix))
      (error "Chain record key does not match kind ~S" kind))
    (subseq bytes 1)))

(defun kv-chain-record-kind-start-key (kind)
  (vector (kv-chain-record-kind-prefix kind)))

(defun kv-chain-record-kind-end-key (kind)
  (let ((prefix (kv-chain-record-kind-prefix kind)))
    (when (= prefix #xff)
      (error "Chain record kind prefix cannot form an exclusive end key"))
    (vector (1+ prefix))))

(defun kv-put-chain-record (database kind identifier value)
  (kv-put database (kv-chain-record-key kind identifier) value))

(defun kv-get-chain-record (database kind identifier &optional default)
  (kv-get database (kv-chain-record-key kind identifier) default))

(defun kv-delete-chain-record (database kind identifier)
  (kv-delete database (kv-chain-record-key kind identifier)))

(defun kv-batch-put-chain-record (batch kind identifier value)
  (kv-batch-put batch (kv-chain-record-key kind identifier) value))

(defun kv-batch-delete-chain-record (batch kind identifier)
  (kv-batch-delete batch (kv-chain-record-key kind identifier)))

(defun kv-chain-records (database kind)
  (let ((iterator
          (kv-iterator database
                       :start (kv-chain-record-kind-start-key kind)
                       :end (kv-chain-record-kind-end-key kind))))
    (loop with records = nil
          do (multiple-value-bind (key value present-p)
                 (funcall iterator)
               (unless present-p
                 (return (nreverse records)))
               (push (cons key value) records)))))

(defun kv-chain-record-entries (database kind)
  (mapcar
   (lambda (record)
     (cons (kv-chain-record-key-identifier kind (car record))
           (cdr record)))
   (kv-chain-records database kind)))

(defun kv-put-memory-entry (database key value)
  (let ((entry (make-kv-memory-entry :key (kv-copy-bytes key)
                                     :value (kv-copy-bytes value))))
    (setf (gethash (kv-key-string key)
                   (memory-key-value-database-entries database))
          entry))
  database)

(defun kv-delete-memory-entry (database key)
  (remhash (kv-key-string key)
           (memory-key-value-database-entries database)))

(defun kv-database-sorted-entries (database)
  (sort
   (loop for entry being the hash-values of
           (memory-key-value-database-entries database)
         collect entry)
   #'kv-entry<))

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

(defmethod kv-get ((database memory-key-value-database) key &optional default)
  (let ((entry (gethash (kv-key-string key)
                        (memory-key-value-database-entries database))))
    (if entry
        (values (kv-copy-bytes (kv-memory-entry-value entry)) t)
        (values default nil))))

(defmethod kv-put ((database memory-key-value-database) key value)
  (kv-put-memory-entry database key value))

(defmethod kv-delete ((database memory-key-value-database) key)
  (kv-delete-memory-entry database key))

(defmethod kv-put ((database file-key-value-database) key value)
  (kv-put-memory-entry database key value)
  (kv-persist-file-database database))

(defmethod kv-delete ((database file-key-value-database) key)
  (let ((deleted-p (kv-delete-memory-entry database key)))
    (when deleted-p
      (kv-persist-file-database database))
    deleted-p))

(defun kv-batch-put (batch key value)
  (push (list :put (kv-copy-bytes key) (kv-copy-bytes value))
        (kv-write-batch-operations batch))
  batch)

(defun kv-batch-delete (batch key)
  (push (list :delete (kv-copy-bytes key))
        (kv-write-batch-operations batch))
  batch)

(defmethod kv-apply-batch ((database memory-key-value-database)
                           (batch kv-write-batch))
  (dolist (operation (reverse (kv-write-batch-operations batch)) database)
    (ecase (first operation)
      (:put (kv-put database (second operation) (third operation)))
      (:delete (kv-delete database (second operation))))))

(defmethod kv-apply-batch ((database file-key-value-database)
                           (batch kv-write-batch))
  (dolist (operation (reverse (kv-write-batch-operations batch)) database)
    (ecase (first operation)
      (:put (kv-put-memory-entry
             database (second operation) (third operation)))
      (:delete (kv-delete-memory-entry database (second operation)))))
  (kv-persist-file-database database))

(defmethod kv-iterator ((database memory-key-value-database)
                        &key start end reverse-p)
  (let* ((entries
           (loop for entry being the hash-values of
                   (memory-key-value-database-entries database)
                 when (kv-entry-in-range-p entry start end)
                   collect entry))
         (sorted
           (sort entries
                 (if reverse-p
                     (lambda (left right)
                       (kv-entry< right left))
                     #'kv-entry<)))
         (remaining sorted))
    (lambda ()
      (let ((entry (pop remaining)))
        (if entry
            (values (kv-copy-bytes (kv-memory-entry-key entry))
                    (kv-copy-bytes (kv-memory-entry-value entry))
                    t)
            (values nil nil nil))))))
