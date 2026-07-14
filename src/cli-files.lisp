(in-package #:ethereum-lisp.cli)

(defun devnet-cli-ready-temp-path (path)
  (let* ((pathname (pathname path))
         (name (or (pathname-name pathname) "ready"))
         (type (or (pathname-type pathname) "json")))
    (make-pathname
     :name (format nil ".~A.~A" name (symbol-name (gensym "TMP")))
     :type type
     :defaults pathname)))

(defun devnet-cli-ensure-path-parent-directory (path)
  (ensure-directories-exist (pathname path))
  path)


(defun devnet-cli-read-file-string (path)
  (with-open-file (stream path :direction :input)
    (let ((string (make-string (file-length stream))))
      (read-sequence string stream)
      string)))

(defun devnet-cli-jwt-secret-file-error (path &optional condition)
  (error
   "--jwt-secret/--authrpc.jwtsecret must name a readable file containing a 32-byte hex secret: ~A~@[ (~A)~]"
   path
   condition))

(defun devnet-cli-read-jwt-secret (path)
  (let* ((text
           (handler-case
               (devnet-cli-read-file-string path)
             (error (condition)
               (devnet-cli-jwt-secret-file-error path condition))))
         (trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) text))
         (secret
           (handler-case
               (hex-to-bytes trimmed)
             (error (condition)
               (devnet-cli-jwt-secret-file-error path condition)))))
    (unless (= 32 (length secret))
      (devnet-cli-jwt-secret-file-error path))
    secret))

(defun devnet-cli-empty-file-p (path)
  (with-open-file (stream path :direction :input)
    (zerop (file-length stream))))

(defun devnet-cli-kv-chain-records-present-p (database)
  (some
   (lambda (kind)
     (not (null
           (ethereum-lisp.database:kv-chain-record-entries database kind))))
   '(:block :header :receipt :canonical-hash :checkpoint :state
     :transaction-location)))

(defun devnet-cli-kv-records-present-p (database)
  (multiple-value-bind (key value present-p)
      (funcall (ethereum-lisp.database:kv-iterator database))
    (declare (ignore key value))
    present-p))

(defun devnet-cli-kv-txpool-records-present-p (database)
  (not (null
        (ethereum-lisp.database:kv-chain-record-entries database :txpool))))

(defun devnet-cli-store-txpool-records-present-p (store)
  (not (null (engine-payload-store-pooled-transactions store))))

(defun devnet-cli-make-output-kv-database (path)
  (ensure-directories-exist (pathname path))
  (let ((existing-path (probe-file path)))
    (when (and existing-path (devnet-cli-empty-file-p existing-path))
      (delete-file existing-path)))
  (ethereum-lisp.database:make-file-key-value-database path))

(defun devnet-cli-datadir-database-path (datadir)
  (namestring
   (merge-pathnames
    +devnet-datadir-database-file+
    (uiop:ensure-directory-pathname datadir))))

(defun devnet-cli-datadir-genesis-path (datadir)
  (namestring
   (merge-pathnames
    +devnet-datadir-genesis-file+
    (uiop:ensure-directory-pathname datadir))))

(defun devnet-cli-datadir-jwt-secret-path (datadir)
  (namestring
   (merge-pathnames
    +devnet-datadir-jwt-secret-file+
    (uiop:ensure-directory-pathname datadir))))

(defun devnet-cli-datadir-geth-jwt-secret-path (datadir)
  (namestring
   (merge-pathnames
    +devnet-datadir-jwt-secret-file+
    (merge-pathnames
     +devnet-geth-datadir-directory+
     (uiop:ensure-directory-pathname datadir)))))

(defun devnet-cli-datadir-jwt-secret-paths (datadir)
  (list (devnet-cli-datadir-jwt-secret-path datadir)
        (devnet-cli-datadir-geth-jwt-secret-path datadir)))

(defun devnet-cli-existing-datadir-jwt-secret-path (datadir)
  (loop for path in (devnet-cli-datadir-jwt-secret-paths datadir)
        when (probe-file path)
          return path))

(defun devnet-cli-copy-file-string (source target)
  (let ((contents (devnet-cli-read-file-string source)))
    (with-open-file (stream (devnet-cli-ensure-path-parent-directory target)
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-string contents stream))))

(defun devnet-cli-random-bytes (length)
  (let ((bytes (make-array length :element-type '(unsigned-byte 8))))
    (handler-case
        (with-open-file (stream #P"/dev/urandom"
                                :direction :input
                                :element-type '(unsigned-byte 8))
          (unless (= length (read-sequence bytes stream))
            (error "Unable to read enough bytes from /dev/urandom"))
          bytes)
      (error ()
        (let ((state (make-random-state t)))
          (dotimes (index length bytes)
            (setf (aref bytes index) (random 256 state))))))))

(defun devnet-cli-ensure-datadir-jwt-secret (datadir &key source-path)
  (when datadir
    (if source-path
        (let ((path (devnet-cli-datadir-jwt-secret-path datadir))
              (secret (devnet-cli-read-jwt-secret source-path)))
          (with-open-file (stream (devnet-cli-ensure-path-parent-directory path)
                                  :direction :output
                                  :if-exists :supersede
                                  :if-does-not-exist :create)
            (write-string (bytes-to-hex secret :prefix nil) stream)
            (terpri stream))
          path)
        (or (devnet-cli-existing-datadir-jwt-secret-path datadir)
            (let ((path (devnet-cli-datadir-jwt-secret-path datadir)))
              (with-open-file
                  (stream (devnet-cli-ensure-path-parent-directory path)
                          :direction :output
                          :if-exists nil
                          :if-does-not-exist :create)
                (when stream
                  (write-string
                   (bytes-to-hex (devnet-cli-random-bytes 32) :prefix nil)
                   stream)
                  (terpri stream)))
              path)))))

(defun devnet-cli-validate-imported-genesis (store genesis-block database-path)
  (let* ((genesis-number
           (block-header-number (block-header genesis-block)))
         (restored-genesis
           (chain-store-block-by-number store genesis-number)))
    (unless restored-genesis
      (error
       "Devnet database is missing canonical genesis at block ~D (~A)"
       genesis-number
       database-path))
    (when (not (equalp (hash32-bytes (block-hash restored-genesis))
                       (hash32-bytes (block-hash genesis-block))))
      (error
       "Devnet database genesis does not match genesis file (~A): expected ~A, got ~A"
       database-path
       (hash32-to-hex (block-hash genesis-block))
       (hash32-to-hex (block-hash restored-genesis))))))
