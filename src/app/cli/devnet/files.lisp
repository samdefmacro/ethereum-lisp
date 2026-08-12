#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(in-package #:ethereum-lisp.cli)

(defun call-with-devnet-cli-datadir-lock (datadir-path thunk)
  "Run THUNK while this process exclusively owns DATADIR-PATH."
  (unless (functionp thunk)
    (error "Datadir lock requires a function"))
  (if (null datadir-path)
      (funcall thunk)
      #+sbcl
      (let* ((directory
               (uiop:ensure-directory-pathname (pathname datadir-path)))
             (lock-path (merge-pathnames "LOCK" directory))
             (fd nil))
        (ensure-directories-exist lock-path)
        (unwind-protect
             (progn
               (setf fd
                     (sb-posix:open
                      (sb-ext:native-namestring lock-path)
                      (logior sb-posix:o-rdwr sb-posix:o-creat)
                      #o644))
               (handler-case
                   (sb-posix:fcntl
                    fd sb-posix:f-setlk
                    (make-instance
                     'sb-posix:flock
                     :type sb-posix:f-wrlck
                     :whence sb-posix:seek-set
                     :start 0
                     :len 0))
                 (sb-posix:syscall-error ()
                   (error "Data directory is already in use: ~A"
                          datadir-path)))
               (funcall thunk))
          (when fd
            (ignore-errors (sb-posix:close fd)))))
      #-sbcl
      (error "Data directory locking requires SBCL")))

(defun devnet-cli-ready-temp-path (path)
  (let* ((pathname (pathname path))
         (name (or (pathname-name pathname) "ready"))
         (type (or (pathname-type pathname) "json")))
    (make-pathname
     :name (format nil ".~A.~A" name (symbol-name (gensym "TMP")))
     :type type
     :defaults pathname)))

(defun devnet-cli-sibling-temp-path (path)
  "Return a unique sibling of PATH without inventing a filename extension."
  (let ((pathname (pathname path)))
    (make-pathname
     :name (format nil ".~A.~A"
                   (or (pathname-name pathname) "artifact")
                   (symbol-name (gensym "TMP")))
     :type (pathname-type pathname)
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

(defun devnet-cli-write-private-file (path writer)
  "Create PATH as a private, mode-0600 regular file and write its contents with
WRITER, a function of one character output stream.

WITH-OPEN-FILE cannot create a secret file: it has no mode argument, so a new
file is 0666 & ~umask (group- or world-readable under the usual umask), and its
:IF-EXISTS behaviour follows symlinks and truncates an existing inode -- a
planted file or a symlink at PATH would then receive the secret. Open PATH
directly with O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW and mode #o600 instead, so the
descriptor is private from open(2) and a pre-existing file or symlink at PATH is
refused (fail closed) rather than followed or truncated. Every caller only
reaches this on the create branch of a not-present check, so O_EXCL refusing an
existing PATH is the intended fail-closed outcome.

CLOSE on an fd-stream closes the underlying fd, so close the stream OR the fd,
never both -- a double close can land on an unrelated recycled descriptor."
  #-sbcl
  (declare (ignore path writer))
  #-sbcl
  (error "Creating a private file requires SBCL")
  #+sbcl
  (let ((namestring
          (sb-ext:native-namestring
           (devnet-cli-ensure-path-parent-directory path)))
        (fd nil)
        (stream nil)
        (stream-open-p nil))
    (unwind-protect
         (progn
           (setf fd
                 (sb-posix:open
                  namestring
                  (logior sb-posix:o-wronly sb-posix:o-creat
                          sb-posix:o-excl sb-posix:o-nofollow)
                  #o600))
           (setf stream
                 (sb-sys:make-fd-stream
                  fd
                  :output t
                  :element-type 'character
                  :external-format :utf-8))
           ;; The stream now owns the descriptor: null FD so cleanup never
           ;; closes it a second time behind the stream's own CLOSE.
           (setf fd nil
                 stream-open-p t)
           (funcall writer stream)
           (finish-output stream)
           (close stream)
           (setf stream-open-p nil))
      (when stream-open-p
        (ignore-errors (close stream)))
      (when fd
        (ignore-errors (sb-posix:close fd))))
    path))

(defun devnet-cli-read-node-key (path)
  "Load the node's secp256k1 private key from PATH, or generate and persist a
fresh one when the file does not exist (go-ethereum --nodekey semantics).

The fresh key is written through DEVNET-CLI-WRITE-PRIVATE-FILE so the nodekey
lands as a mode-0600 file the operator's process alone can read, rather than the
world-readable file WITH-OPEN-FILE would have produced."
  (if (probe-file path)
      (devnet-cli-parse-node-key-hex
       (string-trim '(#\Space #\Tab #\Newline #\Return)
                    (devnet-cli-read-file-string path))
       "--nodekey")
      (let ((scalar (secp256k1-random-private-key)))
        (devnet-cli-write-private-file
         path
         (lambda (out)
           (write-string (devnet-cli-node-key-hex scalar) out)))
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

(defun devnet-cli-parse-db-engine (value)
  "Parse a --db.engine VALUE into a backend keyword.

Accepts the backends this client actually implements -- \"file\" (the
CRC-framed log, the default) and \"rocksdb\" -- and rejects any other value,
including geth's \"pebble\"/\"leveldb\", because selecting a backend we do not
have would silently run a different one than the operator asked for."
  (cond
    ((string-equal value "file") :file)
    ((string-equal value "rocksdb") :rocksdb)
    (t
     (error
      "--db.engine ~A is not supported: this client implements only \"file\" (the default CRC-framed log) and \"rocksdb\""
      value))))

(defun devnet-cli-rocksdb-directory-initialized-p (path)
  "True when PATH is a directory holding an initialized RocksDB database.

RocksDB writes a CURRENT file naming the live MANIFEST as soon as a database
exists, so its presence distinguishes an already-opened datadir (which the
hydration path must import from) from a fresh datadir (nothing to import)."
  (let ((directory (uiop:ensure-directory-pathname path)))
    (and (probe-file directory)
         (probe-file (merge-pathnames "CURRENT" directory))
         t)))

(defun devnet-cli-make-output-kv-database (path &optional (engine :file))
  "Open (or return the cached handle for) the key-value database at PATH.

ENGINE selects the on-disk backend, defaulting to :FILE so every existing
caller keeps the CRC-framed log backend unchanged. :ROCKSDB opens PATH as a
RocksDB directory instead: it owns a directory of SST/WAL files, so there is no
single-file emptiness probe -- an empty RocksDB directory is a valid, openable
database that RocksDB populates create-if-missing."
  (or (devnet-cli-cached-kv-database path)
      (ecase engine
        (:file
         (ensure-directories-exist (pathname path))
         (let ((existing-path (probe-file path)))
           (when (and existing-path (devnet-cli-empty-file-p existing-path))
             (delete-file existing-path)))
         (devnet-cli-cache-kv-database
          path
          (ethereum-lisp.database:make-file-key-value-database path)))
        (:rocksdb
         (ensure-directories-exist (uiop:ensure-directory-pathname path))
         (devnet-cli-cache-kv-database
          path
          (ethereum-lisp.database:make-rocksdb-key-value-database path))))))

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

;;; Node-lifetime key-value database handles.
;;;
;;; Opening a log-structured database replays the whole file, so reopening one
;;; per write made every forkchoice and every payload candidate O(file). The
;;; cache below keeps one handle per output path for as long as the node runs.
;;;
;;; This is behaviour-preserving rather than merely faster: a reopen
;;; reconstructs exactly the map the live handle already holds, because the
;;; devnet is the single writer of these paths and every write path runs under
;;; the node store guard (rpc-handle-request funnels all requests through it).
;;;
;;; One accepted difference, in the conservative direction: if the file is
;;; deleted or replaced underneath a running node, the held handle fail-stops
;;; on the store's size check, where reopening every write would silently have
;;; started over. Nothing in the devnet does that, and losing the artifact
;;; mid-run is worth a loud failure.

(defvar *devnet-cli-kv-database-cache* nil
  "Open key-value database handles keyed by canonical output path, or NIL when
handle caching is disabled. NIL is the default so anything constructing
databases outside a node's lifetime keeps the old open-per-write behaviour.")

(defun devnet-cli-kv-database-cache-key (path)
  (namestring (devnet-cli-canonical-output-pathname path)))

(defun devnet-cli-cached-kv-database (path)
  "Return the live cached handle for PATH, or NIL.

A poisoned handle is dropped rather than returned: reopening is exactly what
it demands, and doing it here preserves the recovery behaviour that fell out
of reopening on every write."
  (let ((cache *devnet-cli-kv-database-cache*))
    (when cache
      (let* ((key (devnet-cli-kv-database-cache-key path))
             (database (gethash key cache)))
        (cond
          ((null database) nil)
          ((ethereum-lisp.database:kv-database-reopen-required-p database)
           (remhash key cache)
           nil)
          (t database))))))

(defun devnet-cli-cache-kv-database (path database)
  (let ((cache *devnet-cli-kv-database-cache*))
    (when (and cache database)
      (setf (gethash (devnet-cli-kv-database-cache-key path) cache) database)))
  database)

(defun devnet-cli-reread-kv-database (path &optional (engine :file))
  "Open PATH fresh, bypassing the node-lifetime handle cache.

For the :FILE backend, whose whole point is that the bytes reached the disk: a
fresh handle replays the CRC-framed log, a stronger claim than a cached table
that just wrote them, so those callers must not share the live handle.

For :ROCKSDB the claim already holds through the live handle -- a batch is
WAL-synced before the write returns, and RocksDB holds an exclusive directory
lock, so a second handle cannot be opened while the node owns the first. Reusing
the cached handle reads the committed, durable state rather than deadlocking on
the lock."
  (ecase engine
    (:file (ethereum-lisp.database:make-file-key-value-database path))
    (:rocksdb
     (or (devnet-cli-cached-kv-database path)
         (ethereum-lisp.database:make-rocksdb-key-value-database
          path :create-if-missing-p nil)))))

(defun call-with-devnet-cli-kv-database-cache (thunk)
  "Run THUNK with node-lifetime caching of open key-value database handles."
  (unless (functionp thunk)
    (error "Devnet key-value database cache thunk must be a function"))
  ;; Assigned rather than dynamically bound, for the reason spelled out in
  ;; CALL-WITH-DEVNET-CLI-HTTP-LIMITS: the node persists from its listener
  ;; threads, and a LET binding is thread-local in SBCL, so those threads would
  ;; read the global NIL and silently reopen the log on every write. The
  ;; previous value is restored so callers stay scoped.
  (let ((previous *devnet-cli-kv-database-cache*))
    (setf *devnet-cli-kv-database-cache* (make-hash-table :test 'equal))
    (unwind-protect
         (funcall thunk)
      (setf *devnet-cli-kv-database-cache* previous))))

(defun devnet-cli-same-output-path-p (left right)
  ;; Conservatively reject case-only differences as well: the usual macOS
  ;; filesystem treats them as the same file, while Linux may not.
  (string-equal
   (namestring (devnet-cli-canonical-output-pathname left))
   (namestring (devnet-cli-canonical-output-pathname right))))

(defun devnet-cli-datadir-database-path (datadir &optional (engine :file))
  "The chain database path inside DATADIR for the selected backend ENGINE.

:FILE (the default) names the single CRC-framed log file; :ROCKSDB names the
RocksDB directory. Both are datadir-relative so a datadir stays self-contained."
  (namestring
   (merge-pathnames
    (ecase engine
      (:file +devnet-datadir-database-file+)
      (:rocksdb +devnet-datadir-rocksdb-directory+))
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

(defun devnet-cli-datadir-node-key-path (datadir)
  (namestring
   (merge-pathnames
    +devnet-datadir-node-key-file+
    (merge-pathnames
     +devnet-geth-datadir-directory+
     (uiop:ensure-directory-pathname datadir)))))

(defun devnet-cli-datadir-enr-seq-path (datadir)
  (namestring
   (merge-pathnames
    +devnet-datadir-enr-seq-file+
    (merge-pathnames
     +devnet-geth-datadir-directory+
     (uiop:ensure-directory-pathname datadir)))))

(defun devnet-cli-write-enr-seq (path sequence)
  "Atomically replace PATH with a private decimal EIP-778 sequence file."
  (unless (and (integerp sequence) (plusp sequence))
    (error "ENR sequence must be a positive integer"))
  (let ((temporary (devnet-cli-sibling-temp-path path))
        (renamed-p nil))
    (unwind-protect
         (progn
           (devnet-cli-write-private-file
            temporary
            (lambda (stream)
              (format stream "~D~%" sequence)))
           (uiop:rename-file-overwriting-target temporary path)
           (setf renamed-p t))
      (unless renamed-p
        (when (probe-file temporary)
          (ignore-errors (delete-file temporary))))))
  sequence)

(defun devnet-cli-load-next-enr-seq (path)
  "Load PATH's EIP-778 sequence and persist this startup's next value.

Every restart advances the sequence. That is conservative when the endpoint and
fork-id are unchanged, and necessary when they changed while the process was
down because only the sequence, not a stale signed record, is durable state."
  (let ((next
          (if (probe-file path)
              (handler-case
                  (1+ (parse-integer
                       (string-trim '(#\Space #\Tab #\Newline #\Return)
                                    (devnet-cli-read-file-string path))
                       :junk-allowed nil))
                (error ()
                  (error "Persisted ENR sequence is malformed: ~A" path)))
              1)))
    (devnet-cli-write-enr-seq path next)))

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
  "LENGTH cryptographically secure random bytes from the OS CSPRNG, failing
closed when it is unavailable.

Formerly fell back to CL:RANDOM on any /dev/urandom failure. CL:RANDOM is not a
cryptographic generator, and *RANDOM-STATE* is seeded deterministically at image
build time, so that fallback would silently mint a guessable JWT secret or node
identity -- worse than refusing to start. SECURE-RANDOM-BYTES already errors when
the OS CSPRNG cannot be read, which is the behaviour we want here."
  (secure-random-bytes length))

(defun devnet-cli-ensure-datadir-jwt-secret (datadir &key source-path)
  (when datadir
    (if source-path
        (let ((path (devnet-cli-datadir-jwt-secret-path datadir))
              (secret (devnet-cli-read-jwt-secret source-path)))
          ;; Copying an operator-provided secret into the datadir is still a
          ;; secret-file creation, so write it privately (mode 0600, O_NOFOLLOW)
          ;; rather than through WITH-OPEN-FILE's world-readable,
          ;; symlink-following :SUPERSEDE. Re-initialising an existing datadir
          ;; replaces the previous secret, so drop any current file before the
          ;; O_EXCL create.
          (when (probe-file path)
            (ignore-errors (delete-file path)))
          (devnet-cli-write-private-file
           path
           (lambda (stream)
             (write-string (bytes-to-hex secret :prefix nil) stream)
             (terpri stream)))
          path)
        (or (devnet-cli-existing-datadir-jwt-secret-path datadir)
            (let ((path (devnet-cli-datadir-jwt-secret-path datadir)))
              ;; No existing secret was found above, so create one privately.
              ;; DEVNET-CLI-WRITE-PRIVATE-FILE opens with O_EXCL|O_NOFOLLOW and
              ;; mode 0600: a JWT secret must never be world-readable, and a
              ;; file or symlink that appeared since the check must fail the
              ;; write rather than be followed or clobbered.
              (devnet-cli-write-private-file
               path
               (lambda (stream)
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
