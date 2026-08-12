(in-package #:ethereum-lisp.database)

;;;; RocksDB 11 C API backend. The dynamic library is optional at load time.

(cffi:define-foreign-library librocksdb
  ;; RocksDB 11.1.2 declares SONAME librocksdb.so.11.1.  Docker COPY follows
  ;; the build-stage symlinks into regular files, and ldconfig consequently
  ;; indexes only that SONAME in the minimal runtime image. Keep the exact
  ;; pinned SONAME first; the major and unversioned names retain compatibility
  ;; with distro/development installations.
  (:unix (:or "librocksdb.so.11.1" "librocksdb.so.11" "librocksdb.so"))
  (t (:default "librocksdb")))

(cffi:defcfun ("rocksdb_options_create" %rocks-options-create) :pointer)
(cffi:defcfun ("rocksdb_options_destroy" %rocks-options-destroy) :void
  (options :pointer))
(cffi:defcfun ("rocksdb_options_set_create_if_missing"
               %rocks-options-create-if-missing) :void
  (options :pointer) (enabled :uchar))
(cffi:defcfun ("rocksdb_readoptions_create" %rocks-read-options-create) :pointer)
(cffi:defcfun ("rocksdb_readoptions_destroy" %rocks-read-options-destroy) :void
  (options :pointer))
(cffi:defcfun ("rocksdb_writeoptions_create" %rocks-write-options-create) :pointer)
(cffi:defcfun ("rocksdb_writeoptions_destroy" %rocks-write-options-destroy) :void
  (options :pointer))
(cffi:defcfun ("rocksdb_writeoptions_set_sync" %rocks-write-options-sync) :void
  (options :pointer) (enabled :uchar))
(cffi:defcfun ("rocksdb_open" %rocks-open) :pointer
  (options :pointer) (name :string) (error :pointer))
(cffi:defcfun ("rocksdb_close" %rocks-close) :void (database :pointer))
(cffi:defcfun ("rocksdb_free" %rocks-free) :void (pointer :pointer))
(cffi:defcfun ("rocksdb_put" %rocks-put) :void
  (database :pointer) (options :pointer)
  (key :pointer) (key-length :size)
  (value :pointer) (value-length :size) (error :pointer))
(cffi:defcfun ("rocksdb_get" %rocks-get) :pointer
  (database :pointer) (options :pointer)
  (key :pointer) (key-length :size)
  (value-length :pointer) (error :pointer))
(cffi:defcfun ("rocksdb_delete" %rocks-delete) :void
  (database :pointer) (options :pointer)
  (key :pointer) (key-length :size) (error :pointer))
(cffi:defcfun ("rocksdb_writebatch_create" %rocks-batch-create) :pointer)
(cffi:defcfun ("rocksdb_writebatch_destroy" %rocks-batch-destroy) :void
  (batch :pointer))
(cffi:defcfun ("rocksdb_writebatch_put" %rocks-batch-put) :void
  (batch :pointer) (key :pointer) (key-length :size)
  (value :pointer) (value-length :size))
(cffi:defcfun ("rocksdb_writebatch_delete" %rocks-batch-delete) :void
  (batch :pointer) (key :pointer) (key-length :size))
(cffi:defcfun ("rocksdb_write" %rocks-write) :void
  (database :pointer) (options :pointer) (batch :pointer) (error :pointer))
(cffi:defcfun ("rocksdb_create_iterator" %rocks-iterator-create) :pointer
  (database :pointer) (options :pointer))
(cffi:defcfun ("rocksdb_iter_destroy" %rocks-iterator-destroy) :void
  (iterator :pointer))
(cffi:defcfun ("rocksdb_iter_valid" %rocks-iterator-valid) :uchar
  (iterator :pointer))
(cffi:defcfun ("rocksdb_iter_seek_to_first" %rocks-iterator-first) :void
  (iterator :pointer))
(cffi:defcfun ("rocksdb_iter_seek_to_last" %rocks-iterator-last) :void
  (iterator :pointer))
(cffi:defcfun ("rocksdb_iter_seek" %rocks-iterator-seek) :void
  (iterator :pointer) (key :pointer) (key-length :size))
(cffi:defcfun ("rocksdb_iter_next" %rocks-iterator-next) :void
  (iterator :pointer))
(cffi:defcfun ("rocksdb_iter_prev" %rocks-iterator-previous) :void
  (iterator :pointer))
(cffi:defcfun ("rocksdb_iter_key" %rocks-iterator-key) :pointer
  (iterator :pointer) (key-length :pointer))
(cffi:defcfun ("rocksdb_iter_value" %rocks-iterator-value) :pointer
  (iterator :pointer) (value-length :pointer))
(cffi:defcfun ("rocksdb_iter_get_error" %rocks-iterator-get-error) :void
  (iterator :pointer) (error :pointer))

(defclass rocksdb-key-value-database (key-value-database)
  ((handle :initarg :handle :accessor rocksdb-handle)
   (read-options :initarg :read-options :reader rocksdb-read-options)
   (write-options :initarg :write-options :reader rocksdb-write-options)
   (path :initarg :path :reader rocksdb-path)))

(defvar *rocksdb-library-loaded-p* nil)

(defun rocksdb-available-p ()
  (or *rocksdb-library-loaded-p*
      (handler-case
          (progn
            (cffi:use-foreign-library librocksdb)
            (setf *rocksdb-library-loaded-p* t))
        (error () nil))))

(defmacro with-rocks-bytes ((pointer length bytes) &body body)
  `(let* ((data (ensure-byte-vector ,bytes))
          (,length (length data))
          (,pointer (cffi:foreign-alloc :uint8 :count (max 1 ,length))))
     (unwind-protect
          (progn
            (dotimes (index ,length)
              (setf (cffi:mem-aref ,pointer :uint8 index)
                    (aref data index)))
            ,@body)
       (cffi:foreign-free ,pointer))))

(defun rocksdb-check-error (error)
  (let ((pointer (cffi:mem-ref error :pointer)))
    (unless (cffi:null-pointer-p pointer)
      (unwind-protect
           (error "RocksDB: ~A" (cffi:foreign-string-to-lisp pointer))
        (%rocks-free pointer)))))

(defmacro with-rocks-error ((error) &body body)
  `(cffi:with-foreign-object (,error :pointer)
     (setf (cffi:mem-ref ,error :pointer) (cffi:null-pointer))
     (multiple-value-prog1 (progn ,@body)
       (rocksdb-check-error ,error))))

(defun make-rocksdb-key-value-database (path &key (create-if-missing-p t))
  (unless (rocksdb-available-p)
    (error "RocksDB shared library is unavailable"))
  (let ((options (%rocks-options-create))
        (read-options (%rocks-read-options-create))
        (write-options (%rocks-write-options-create)))
    (%rocks-options-create-if-missing options (if create-if-missing-p 1 0))
    (%rocks-write-options-sync write-options 1)
    (handler-case
        (let ((handle
                (with-rocks-error (error)
                  (%rocks-open options (namestring path) error))))
          (%rocks-options-destroy options)
          (make-instance 'rocksdb-key-value-database
                         :handle handle :read-options read-options
                         :write-options write-options :path path))
      (error (condition)
        (%rocks-options-destroy options)
        (%rocks-read-options-destroy read-options)
        (%rocks-write-options-destroy write-options)
        (error condition)))))

(defun close-rocksdb-key-value-database (database)
  (unless (cffi:null-pointer-p (rocksdb-handle database))
    (%rocks-close (rocksdb-handle database))
    (%rocks-read-options-destroy (rocksdb-read-options database))
    (%rocks-write-options-destroy (rocksdb-write-options database))
    (setf (rocksdb-handle database) (cffi:null-pointer)))
  nil)

(defun rocksdb-copy-foreign-bytes (pointer length)
  (let ((result (make-byte-vector length)))
    (dotimes (index length result)
      (setf (aref result index) (cffi:mem-aref pointer :uint8 index)))))

(defmethod kv-get ((database rocksdb-key-value-database) key &optional default)
  (with-rocks-bytes (key-pointer key-length key)
    (cffi:with-foreign-object (value-length :size)
      (let ((value
              (with-rocks-error (error)
                (%rocks-get (rocksdb-handle database)
                            (rocksdb-read-options database)
                            key-pointer key-length value-length error))))
        (if (cffi:null-pointer-p value)
            (values default nil)
            (unwind-protect
                 (values
                  (rocksdb-copy-foreign-bytes
                   value (cffi:mem-ref value-length :size))
                  t)
              (%rocks-free value)))))))

(defmethod kv-put ((database rocksdb-key-value-database) key value)
  (with-rocks-bytes (key-pointer key-length key)
    (with-rocks-bytes (value-pointer value-length value)
      (with-rocks-error (error)
        (%rocks-put (rocksdb-handle database)
                    (rocksdb-write-options database)
                    key-pointer key-length value-pointer value-length error))))
  database)

(defmethod kv-delete ((database rocksdb-key-value-database) key)
  (multiple-value-bind (ignored present-p) (kv-get database key)
    (declare (ignore ignored))
    (with-rocks-bytes (key-pointer key-length key)
      (with-rocks-error (error)
        (%rocks-delete (rocksdb-handle database)
                       (rocksdb-write-options database)
                       key-pointer key-length error)))
    present-p))

(defmethod kv-apply-batch ((database rocksdb-key-value-database)
                           (batch kv-write-batch))
  (let ((native (%rocks-batch-create)))
    (unwind-protect
         (progn
           (dolist (operation (reverse (kv-write-batch-operations batch)))
             (ecase (first operation)
               (:put
                (with-rocks-bytes (key-pointer key-length (second operation))
                  (with-rocks-bytes
                      (value-pointer value-length (third operation))
                    (%rocks-batch-put native key-pointer key-length
                                      value-pointer value-length))))
               (:delete
                (with-rocks-bytes (key-pointer key-length (second operation))
                  (%rocks-batch-delete native key-pointer key-length)))))
           (with-rocks-error (error)
             (%rocks-write (rocksdb-handle database)
                           (rocksdb-write-options database) native error)))
      (%rocks-batch-destroy native)))
  database)

(defun rocksdb-iterator-check-error (iterator)
  "Signal if the iterator carries a non-OK status.
RocksDB surfaces IO and corruption errors through the iterator's status rather
than through a per-step return, so a caller that never checks it would treat a
faulted scan as a clean end of range."
  (cffi:with-foreign-object (error :pointer)
    (setf (cffi:mem-ref error :pointer) (cffi:null-pointer))
    (%rocks-iterator-get-error iterator error)
    (let ((pointer (cffi:mem-ref error :pointer)))
      (unless (cffi:null-pointer-p pointer)
        (unwind-protect
             (error "RocksDB iterator: ~A"
                    (cffi:foreign-string-to-lisp pointer))
          (%rocks-free pointer))))))

(defun rocksdb-iterator-finish (iterator)
  "Propagate any iterator error, then release the native iterator exactly once."
  (unwind-protect
       (rocksdb-iterator-check-error iterator)
    (%rocks-iterator-destroy iterator)))

(defmethod kv-iterator ((database rocksdb-key-value-database)
                        &key start end reverse-p)
  ;; The range is [START, END): START is the inclusive lower bound and END the
  ;; exclusive upper bound in BOTH directions, so a reverse scan yields exactly
  ;; the same keys as a forward scan of the same range, descending. This
  ;; matches the memory backend contract (KV-ENTRY-IN-RANGE-P), which the
  ;; height-ordered chain-record range scans depend on.
  (let ((iterator (%rocks-iterator-create
                   (rocksdb-handle database)
                   (rocksdb-read-options database)))
        (start-id (and start (kv-key-string start)))
        (end-id (and end (kv-key-string end))))
    (cond
      (reverse-p
       (cond
         (end
          ;; SEEK lands on the first key >= END; step back to the last key
          ;; strictly below the exclusive upper bound. When no key reaches END,
          ;; the largest key overall is in range, so fall back to SEEK-TO-LAST.
          (with-rocks-bytes (pointer length end)
            (%rocks-iterator-seek iterator pointer length))
          (if (zerop (%rocks-iterator-valid iterator))
              (%rocks-iterator-last iterator)
              (%rocks-iterator-previous iterator)))
         (t
          (%rocks-iterator-last iterator))))
      (start
       (with-rocks-bytes (pointer length start)
         (%rocks-iterator-seek iterator pointer length)))
      (t
       (%rocks-iterator-first iterator)))
    (flet ((finish ()
             ;; Null the handle before finishing so a later call is a safe
             ;; no-op even if error propagation unwinds through here.
             (let ((it iterator))
               (setf iterator (cffi:null-pointer))
               (rocksdb-iterator-finish it))
             (values nil nil nil)))
      (values
       (lambda ()
         (cond
           ((cffi:null-pointer-p iterator)
            (values nil nil nil))
           ((zerop (%rocks-iterator-valid iterator))
            (finish))
           (t
            (cffi:with-foreign-objects ((key-length :size)
                                        (value-length :size))
              (let* ((key-pointer (%rocks-iterator-key iterator key-length))
                     (key (rocksdb-copy-foreign-bytes
                           key-pointer (cffi:mem-ref key-length :size)))
                     (key-id (kv-key-string key)))
                (if (or (and reverse-p start-id (string< key-id start-id))
                        (and (not reverse-p) end-id
                             (not (string< key-id end-id))))
                    (finish)
                    (let* ((value-pointer
                             (%rocks-iterator-value iterator value-length))
                           (value (rocksdb-copy-foreign-bytes
                                   value-pointer
                                   (cffi:mem-ref value-length :size))))
                      (if reverse-p
                          (%rocks-iterator-previous iterator)
                          (%rocks-iterator-next iterator))
                      (values key value t))))))))
       (lambda ()
         (unless (cffi:null-pointer-p iterator)
           (finish))
         nil)))))
