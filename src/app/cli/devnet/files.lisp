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

(defun devnet-cli-node-key-hex (scalar)
  "Render a secp256k1 private-key SCALAR as 64 lowercase hex characters (no 0x),
the go-ethereum nodekey file format."
  (let ((bytes (make-byte-vector 32)))
    (dotimes (i 32)
      (setf (aref bytes (- 31 i)) (ldb (byte 8 (* 8 i)) scalar)))
    (subseq (bytes-to-hex bytes) 2)))

(defun devnet-cli-parse-node-key-hex (value option)
  "Parse VALUE as a 32-byte secp256k1 private key in hex, returning the scalar.
The public-key derivation validates the [1, n-1] range."
  (handler-case
      (let ((bytes (hex-to-bytes value)))
        (unless (= 32 (length bytes))
          (error "node key must be 32 bytes"))
        (let ((scalar (bytes-to-integer bytes)))
          (secp256k1-private-key-public-key scalar)
          scalar))
    (error ()
      (error "~A requires a 32-byte hex secp256k1 private key" option))))

(defun devnet-cli-read-node-key (path)
  "Load the node's secp256k1 private key from PATH, or generate and persist a
fresh one when the file does not exist (go-ethereum --nodekey semantics)."
  (if (probe-file path)
      (devnet-cli-parse-node-key-hex
       (string-trim '(#\Space #\Tab #\Newline #\Return)
                    (devnet-cli-read-file-string path))
       "--nodekey")
      (let ((scalar (secp256k1-random-private-key)))
        (with-open-file (out (devnet-cli-ensure-path-parent-directory path)
                             :direction :output
                             :if-does-not-exist :create :if-exists :error)
          (write-string (devnet-cli-node-key-hex scalar) out))
        scalar)))

(defun devnet-cli-empty-file-p (path)
  (with-open-file (stream path :direction :input)
    (zerop (file-length stream))))

(defun devnet-cli-kv-chain-records-present-p (database)
  (some
   (lambda (kind)
     (not (null
           (ethereum-lisp.database:kv-chain-record-entries database kind))))
   '(:block :header :receipt :canonical-hash :checkpoint :state
     :state-diff :transaction-location)))

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

(defun devnet-cli-normalize-absolute-directory-components (components)
  (let ((normalized (list (first components))))
    (dolist (component (rest components) normalized)
      (cond
        ((or (eq component :current)
             (and (stringp component) (string= component "."))))
        ((or (member component '(:up :back))
             (and (stringp component) (string= component "..")))
         (when (> (length normalized) 1)
           (setf normalized (butlast normalized))))
        (t
         (setf normalized (append normalized (list component))))))))

(defun devnet-cli-existing-directory-prefix (absolute-path)
  (let ((directory (pathname-directory absolute-path)))
    (loop for end from (length directory) downto 1
          for prefix =
            (make-pathname
             :directory (subseq directory 0 end)
             :name nil
             :type nil
             :version nil
             :defaults absolute-path)
          for existing-prefix = (ignore-errors (probe-file prefix))
          when existing-prefix
            return (values (truename existing-prefix)
                           (subseq directory end)))))

(defun devnet-cli-canonical-output-pathname-once (absolute-path)
  (let ((existing-path (probe-file absolute-path)))
    (if existing-path
        (truename existing-path)
        (multiple-value-bind (existing-prefix remaining-components)
            (devnet-cli-existing-directory-prefix absolute-path)
          (make-pathname
           :directory
           (devnet-cli-normalize-absolute-directory-components
            (append (pathname-directory existing-prefix)
                    remaining-components))
           :name (pathname-name absolute-path)
           :type (pathname-type absolute-path)
           :version (pathname-version absolute-path)
           :defaults existing-prefix)))))

(defun devnet-cli-canonical-output-pathname (path)
  (loop with current =
          (merge-pathnames (pathname path) *default-pathname-defaults*)
        for canonical =
          (devnet-cli-canonical-output-pathname-once current)
        when (string= (namestring current) (namestring canonical))
          return canonical
        do (setf current canonical)))

(defun devnet-cli-same-output-path-p (left right)
  ;; Conservatively reject case-only differences as well: the usual macOS
  ;; filesystem treats them as the same file, while Linux may not.
  (string-equal
   (namestring (devnet-cli-canonical-output-pathname left))
   (namestring (devnet-cli-canonical-output-pathname right))))

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
