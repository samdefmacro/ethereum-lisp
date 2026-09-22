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
(cffi:defcfun ("rocksdb_options_optimize_level_style_compaction"
               %rocks-options-optimize-level-style-compaction) :void
  (options :pointer) (memtable-memory-budget :uint64))
(cffi:defcfun ("rocksdb_options_increase_parallelism"
               %rocks-options-increase-parallelism) :void
  (options :pointer) (total-threads :int))
(cffi:defcfun ("rocksdb_options_set_max_subcompactions"
               %rocks-options-set-max-subcompactions) :void
  (options :pointer) (count :uint32))
(cffi:defcfun ("rocksdb_options_get_max_subcompactions"
               %rocks-options-get-max-subcompactions) :uint32
  (options :pointer))
(cffi:defcfun ("rocksdb_options_set_level_compaction_dynamic_level_bytes"
               %rocks-options-dynamic-level-bytes) :void
  (options :pointer) (enabled :uchar))
(cffi:defcfun ("rocksdb_options_set_bytes_per_sync"
               %rocks-options-bytes-per-sync) :void
  (options :pointer) (bytes :uint64))
(cffi:defcfun ("rocksdb_options_set_wal_bytes_per_sync"
               %rocks-options-wal-bytes-per-sync) :void
  (options :pointer) (bytes :uint64))
(cffi:defcfun ("rocksdb_options_get_wal_bytes_per_sync"
               %rocks-options-get-wal-bytes-per-sync) :uint64
  (options :pointer))
(cffi:defcfun ("rocksdb_block_based_options_create"
               %rocks-block-options-create) :pointer)
(cffi:defcfun ("rocksdb_block_based_options_destroy"
               %rocks-block-options-destroy) :void
  (options :pointer))
(cffi:defcfun ("rocksdb_block_based_options_set_filter_policy"
               %rocks-block-options-set-filter-policy) :void
  (options :pointer) (filter-policy :pointer))
(cffi:defcfun ("rocksdb_block_based_options_set_block_cache"
               %rocks-block-options-set-block-cache) :void
  (options :pointer) (cache :pointer))
(cffi:defcfun ("rocksdb_block_based_options_set_cache_index_and_filter_blocks"
               %rocks-block-options-cache-index-and-filter-blocks) :void
  (options :pointer) (enabled :uchar))
(cffi:defcfun ("rocksdb_block_based_options_set_cache_index_and_filter_blocks_with_high_priority"
               %rocks-block-options-cache-index-and-filter-high-priority) :void
  (options :pointer) (enabled :uchar))
(cffi:defcfun ("rocksdb_block_based_options_set_pin_l0_filter_and_index_blocks_in_cache"
               %rocks-block-options-pin-l0-filter-and-index) :void
  (options :pointer) (enabled :uchar))
(cffi:defcfun ("rocksdb_options_set_block_based_table_factory"
               %rocks-options-set-block-table-factory) :void
  (options :pointer) (block-options :pointer))
(cffi:defcfun ("rocksdb_filterpolicy_create_bloom_full"
               %rocks-filter-policy-create-bloom-full) :pointer
  (bits-per-key :double))
(cffi:defcfun ("rocksdb_filterpolicy_destroy"
               %rocks-filter-policy-destroy) :void
  (filter-policy :pointer))
(cffi:defcfun ("rocksdb_cache_create_lru" %rocks-cache-create-lru) :pointer
  (capacity :size))
(cffi:defcfun ("rocksdb_cache_destroy" %rocks-cache-destroy) :void
  (cache :pointer))
(cffi:defcfun ("rocksdb_readoptions_create" %rocks-read-options-create) :pointer)
(cffi:defcfun ("rocksdb_readoptions_set_async_io"
               %rocks-read-options-set-async-io) :void
  (options :pointer) (enabled :uchar))
(cffi:defcfun ("rocksdb_readoptions_get_async_io"
               %rocks-read-options-get-async-io) :uchar
  (options :pointer))
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
;; The process-wide default Env owns the background thread pools, not the DB.
;; rocksdb_create_default_env wraps Env::Default() without owning it, so
;; rocksdb_env_destroy frees only the wrapper (db/c.cc:6662, 6733).
(cffi:defcfun ("rocksdb_create_default_env" %rocks-create-default-env) :pointer)
(cffi:defcfun ("rocksdb_env_destroy" %rocks-env-destroy) :void (env :pointer))
(cffi:defcfun ("rocksdb_env_set_low_priority_background_threads"
               %rocks-env-set-low-priority-threads)
    :void
  (env :pointer) (count :int))
(cffi:defcfun ("rocksdb_env_set_high_priority_background_threads"
               %rocks-env-set-high-priority-threads)
    :void
  (env :pointer) (count :int))
(cffi:defcfun ("rocksdb_env_set_bottom_priority_background_threads"
               %rocks-env-set-bottom-priority-threads)
    :void
  (env :pointer) (count :int))
(cffi:defcfun ("rocksdb_free" %rocks-free) :void (pointer :pointer))
(cffi:defcfun ("memcpy" %rocks-memory-copy) :pointer
  (destination :pointer) (source :pointer) (bytes :size))
(cffi:defcfun ("rocksdb_put" %rocks-put) :void
  (database :pointer) (options :pointer)
  (key :pointer) (key-length :size)
  (value :pointer) (value-length :size) (error :pointer))
(cffi:defcfun ("rocksdb_get" %rocks-get) :pointer
  (database :pointer) (options :pointer)
  (key :pointer) (key-length :size)
  (value-length :pointer) (error :pointer))
(cffi:defcfun ("rocksdb_multi_get" %rocks-multi-get) :void
  (database :pointer) (options :pointer) (key-count :size)
  (keys :pointer) (key-lengths :pointer)
  (values :pointer) (value-lengths :pointer) (errors :pointer))
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

(defstruct (rocksdb-usage (:constructor make-rocksdb-usage ()))
  "The in-flight accounting that makes closing a shared handle safe.

USERS counts native calls and live iterators currently holding the handle.
CLOSING-P is claimed once, by the first closer. A user increments USERS and
then reads CLOSING-P; a closer claims CLOSING-P and then reads USERS. With a
full barrier between each write and the following read, at least one side sees
the other, so a user either backs out with ROCKSDB-DATABASE-CLOSED-ERROR or is
counted and waited for -- it can never be inside the C API while rocksdb_close
frees the DB underneath it."
  (users 0 :type sb-ext:word)
  (closing-p nil))

(defclass rocksdb-key-value-database (key-value-database)
  ((handle :initarg :handle :accessor rocksdb-handle)
   ;; The option objects are accessors rather than readers because
   ;; CLOSE-ROCKSDB-KEY-VALUE-DATABASE destroys them and must null the slots in
   ;; the same step: a reader that survived the destroy would hand a caller a
   ;; freed pointer, which is a fault rather than an error.
   (read-options :initarg :read-options :accessor rocksdb-read-options)
   (write-options :initarg :write-options :accessor rocksdb-write-options)
   (buffered-write-options
    :initarg :buffered-write-options
    :accessor rocksdb-buffered-write-options)
   (usage :initform (make-rocksdb-usage) :reader rocksdb-usage)
   (path :initarg :path :reader rocksdb-path)))

(defvar *rocksdb-library-loaded-p* nil)

(defvar *rocksdb-lifecycle-lock*
  (sb-thread:make-mutex :name "ethereum-lisp-rocksdb-lifecycle")
  "Serialises opening, closing and releasing the shared background pools.

Opening configures the process-wide default Env (INCREASE-PARALLELISM sizes its
pools), and releasing those pools must not interleave with an open that is
about to rely on them.")

(defvar *rocksdb-open-database-count* 0
  "RocksDB databases this process has opened and not yet closed, under
*ROCKSDB-LIFECYCLE-LOCK*. The shared background pools may be released only
when it is zero.")

(defconstant +rocksdb-level-compaction-memory-budget+ (* 384 1024 1024)
  "Level-compaction preset budget for the shared public-node profile.

RocksDB divides this value into four 96-MiB write buffers and permits six in
the worst case, bounding live memtables at 576 MiB while retaining two-way
flush merging during bulk sync.")
(defconstant +rocksdb-background-job-count+ 8
  "One bounded flush/compaction job per supported public-node vCPU.")
(defconstant +rocksdb-max-subcompactions+ 4
  "Maximum key-range slices used by one large public-node compaction.

The supported host has eight vCPUs. Four slices let a single level compaction
use otherwise idle cores while retaining capacity for SNAP proof verification,
RLPx, the consensus-client Engine endpoint, and independent flush jobs. This
changes only background SST construction; WAL and cursor durability are
unchanged.")
(defconstant +rocksdb-background-bytes-per-sync+ (* 1024 1024)
  "Incremental background-file sync width for SST construction.")
(defconstant +rocksdb-wal-bytes-per-sync+ (* 5 100 1024)
  "Background WAL sync width matching geth's five ideal 100-KiB batches.")
(defconstant +rocksdb-block-cache-bytes+ (* 256 1024 1024)
  "Block-cache budget for the supported shared 16-GiB EL/CL node profile.

The 7-GiB EL cgroup also charges RocksDB memtables and filesystem cache.  Larger
caches exhausted that hard boundary or forced enough direct reclaim to make
the consensus client's Engine upcheck time out during sustained Hoodi range
import even though the live Lisp heap remained below two GiB.")
(defconstant +rocksdb-bloom-bits-per-key+ 10.0d0
  "Full-filter budget for random content-addressed state lookups.")

(defparameter +rocksdb-async-read-io-environment+
  "ETHEREUM_LISP_ROCKSDB_ASYNC_READ_IO"
  "Optional runtime override for RocksDB asynchronous read scheduling.")

(defun rocksdb-async-read-io-enabled-p
    (&optional (environment-lookup #'uiop:getenv))
  "Return whether new RocksDB read handles enable asynchronous scheduling.

The default remains enabled for the public-node profile.  Operators can set
ETHEREUM_LISP_ROCKSDB_ASYNC_READ_IO to 0, false, or no when isolating a native
async-I/O failure on a specific kernel; invalid values fail closed rather than
silently changing the storage profile."
  (let ((value (funcall environment-lookup +rocksdb-async-read-io-environment+)))
    (cond
      ((or (null value) (string= value "")
           (member value '("1" "true" "yes") :test #'string-equal))
       t)
      ((member value '("0" "false" "no") :test #'string-equal)
       nil)
      (t
       (error "~A must be one of 1, true, yes, 0, false, or no"
              +rocksdb-async-read-io-environment+)))))

(defun rocksdb-available-p ()
  (or *rocksdb-library-loaded-p*
      (handler-case
          (progn
            (cffi:use-foreign-library librocksdb)
            (setf *rocksdb-library-loaded-p* t))
        (error () nil))))

(defmacro with-rocks-bytes ((pointer length bytes) &body body)
  `(let* ((data (ensure-byte-vector ,bytes))
          (,length (length data)))
     ;; RocksDB copies every key/value before the native call returns. Pin the
     ;; specialized Lisp vector for that bounded call instead of allocating an
     ;; intermediate foreign buffer and crossing CFFI once per octet. CFFI
     ;; provides a valid pointer for a zero-length specialized vector too.
     (cffi:with-pointer-to-vector-data (,pointer data)
       ,@body)))

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

(defun rocksdb-configure-block-table (options)
  "Install the bounded public-node cache and whole-key Bloom filter."
  (let ((block-options (%rocks-block-options-create))
        (cache (%rocks-cache-create-lru +rocksdb-block-cache-bytes+))
        (filter-policy
          (%rocks-filter-policy-create-bloom-full
           +rocksdb-bloom-bits-per-key+)))
    (when (or (cffi:null-pointer-p block-options)
              (cffi:null-pointer-p cache)
              (cffi:null-pointer-p filter-policy))
      (unless (cffi:null-pointer-p filter-policy)
        (%rocks-filter-policy-destroy filter-policy))
      (unless (cffi:null-pointer-p cache)
        (%rocks-cache-destroy cache))
      (unless (cffi:null-pointer-p block-options)
        (%rocks-block-options-destroy block-options))
      (error "RocksDB block-table cache allocation failed"))
    (unwind-protect
         (progn
           ;; SET-FILTER-POLICY transfers the wrapper into BLOCK-OPTIONS.
           ;; The table factory copies that shared policy before BLOCK-OPTIONS
           ;; is released. SET-BLOCK-CACHE instead copies CACHE's shared
           ;; object, so its C wrapper remains ours to destroy below.
           (%rocks-block-options-set-filter-policy
            block-options filter-policy)
           (setf filter-policy (cffi:null-pointer))
           (%rocks-block-options-set-block-cache block-options cache)
           (%rocks-block-options-cache-index-and-filter-blocks block-options 1)
           (%rocks-block-options-cache-index-and-filter-high-priority
            block-options 1)
           (%rocks-block-options-pin-l0-filter-and-index block-options 1)
           (%rocks-options-set-block-table-factory options block-options))
      (unless (cffi:null-pointer-p filter-policy)
        (%rocks-filter-policy-destroy filter-policy))
      (%rocks-cache-destroy cache)
      (%rocks-block-options-destroy block-options)))
  options)

(defun %make-rocksdb-key-value-database
    (path &key (create-if-missing-p t)
               (async-read-io-p (rocksdb-async-read-io-enabled-p)))
  (unless (rocksdb-available-p)
    (error "RocksDB shared library is unavailable"))
  (let ((options (%rocks-options-create))
        (read-options (%rocks-read-options-create))
        (write-options (%rocks-write-options-create))
        (buffered-write-options (%rocks-write-options-create))
        (handle (cffi:null-pointer)))
    (handler-case
        (progn
          (%rocks-options-create-if-missing
           options (if create-if-missing-p 1 0))
          ;; ROCKSDB_USE_IO_URING makes the POSIX MultiRead backend use the
          ;; ring even without this option. ReadOptions nevertheless controls
          ;; asynchronous iterator prefetch and coroutine-enabled cross-level
          ;; MultiGet scheduling. The public-node default enables it, while a
          ;; host with a diagnosed native async-I/O fault can explicitly turn
          ;; off that extra scheduling without weakening durability.
          (%rocks-read-options-set-async-io read-options
                                            (if async-read-io-p 1 0))
          (unless (= (if async-read-io-p 1 0)
                     (%rocks-read-options-get-async-io read-options))
            (error "RocksDB refused the configured asynchronous read I/O setting"))
          ;; Ethereum bootstrap is a sustained batched insert workload.
          ;; RocksDB's default 64 MiB/one-memtable flush cadence produced
          ;; roughly 8x physical writes on the Hoodi gate. Keep leveled
          ;; compaction and every durability check, but use RocksDB's own
          ;; bounded bulk-write preset: 96 MiB memtables, two-way flush
          ;; merging, and a matching 384 MiB base level. Eight background jobs
          ;; let the supported 8-vCPU/16-GiB node drain compaction debt without
          ;; increasing the fixed level-compaction preset.
          (%rocks-options-optimize-level-style-compaction
           options +rocksdb-level-compaction-memory-budget+)
          (%rocks-options-increase-parallelism
           options +rocksdb-background-job-count+)
          ;; INCREASE-PARALLELISM permits independent background jobs, but one
          ;; large compaction still defaults to a single worker. Hoodi storage
          ;; range import measured that shape directly: one compaction core and
          ;; sustained device bandwidth while SNAP lanes waited. Split that
          ;; compaction into bounded key ranges, then read the option back before
          ;; opening the database so a mismatched native library fails closed.
          (%rocks-options-set-max-subcompactions
           options +rocksdb-max-subcompactions+)
          (unless
              (= +rocksdb-max-subcompactions+
                 (%rocks-options-get-max-subcompactions options))
            (error "RocksDB refused the configured subcompaction bound"))
          (%rocks-options-dynamic-level-bytes options 1)
          (%rocks-options-bytes-per-sync
           options +rocksdb-background-bytes-per-sync+)
          ;; Match geth's Pebble durability cadence for recoverable head
          ;; progress: ordinary batches may avoid a foreground fsync, while
          ;; RocksDB incrementally syncs each roughly 500-KiB WAL prefix in the
          ;; background. Safe/finalized/reorg/pivot publication still uses the
          ;; explicit sync=1 handle below.
          (%rocks-options-wal-bytes-per-sync
           options +rocksdb-wal-bytes-per-sync+)
          (unless
              (= +rocksdb-wal-bytes-per-sync+
                 (%rocks-options-get-wal-bytes-per-sync options))
            (error "RocksDB refused the configured WAL sync width"))
          ;; The RocksDB 11 block-table default is only 32 MiB. SNAP account
          ;; ranges and final healing issue wide random content-addressed reads
          ;; over tens of gigabytes, so that fallback turns nearly every lookup
          ;; into device I/O. Keep a bounded cache and Bloom filters in
          ;; RocksDB's native table layer; neither changes WAL durability or
          ;; the bytes returned to verification.
          (rocksdb-configure-block-table options)
          (%rocks-write-options-sync write-options 1)
          ;; Recoverable prerequisites and straight Engine head extensions use
          ;; this handle. A following explicit seam uses WRITE-OPTIONS above;
          ;; RocksDB's synced write flushes the preceding WAL prefix too.
          (%rocks-write-options-sync buffered-write-options 0)
          (setf handle
                (with-rocks-error (error)
                  (%rocks-open options (namestring path) error)))
          (%rocks-options-destroy options)
          (setf options (cffi:null-pointer))
          (prog1
              (make-instance 'rocksdb-key-value-database
                             :handle handle :read-options read-options
                             :write-options write-options
                             :buffered-write-options buffered-write-options
                             :path path)
            ;; The returned adapter now owns all three surviving handles.
            (setf handle (cffi:null-pointer))))
      (error (condition)
        (unless (cffi:null-pointer-p handle)
          (%rocks-close handle))
        (unless (cffi:null-pointer-p options)
          (%rocks-options-destroy options))
        (%rocks-read-options-destroy read-options)
        (%rocks-write-options-destroy write-options)
        (%rocks-write-options-destroy buffered-write-options)
        (error condition)))))

(defun make-rocksdb-key-value-database
    (path &key (create-if-missing-p t)
               (async-read-io-p (rocksdb-async-read-io-enabled-p)))
  "Open the RocksDB database at PATH and count it as open.

Serialised with CLOSE-ROCKSDB-KEY-VALUE-DATABASE and
RELEASE-ROCKSDB-BACKGROUND-THREADS: opening sizes the process-wide background
pools, so it must not interleave with a release that empties them."
  (sb-thread:with-recursive-lock (*rocksdb-lifecycle-lock*)
    (prog1 (%make-rocksdb-key-value-database
            path
            :create-if-missing-p create-if-missing-p
            :async-read-io-p async-read-io-p)
      (incf *rocksdb-open-database-count*))))

(define-condition rocksdb-database-closed-error (error)
  ((path :initarg :path :reader rocksdb-database-closed-error-path))
  (:report
   (lambda (condition stream)
     (format stream "RocksDB database ~A is closed"
             (rocksdb-database-closed-error-path condition))))
  (:documentation
   "Signalled when an operation reaches a database that is closing or closed.

Without this the operation would pass a freed rocksdb_t* to the C API, which
is a memory fault and not a condition. Closing the store on the shutdown path
makes a use-after-close reachable from any thread the shutdown failed to join,
so it must be reported rather than executed."))

(defun rocksdb-usage-enter (database)
  "Count one user of DATABASE's native handle, or signal if it is closing."
  (let ((usage (rocksdb-usage database)))
    (sb-ext:atomic-incf (rocksdb-usage-users usage))
    (sb-thread:barrier (:memory))
    (when (rocksdb-usage-closing-p usage)
      (sb-ext:atomic-decf (rocksdb-usage-users usage))
      (error 'rocksdb-database-closed-error :path (rocksdb-path database)))
    (rocksdb-handle database)))

(defun rocksdb-usage-leave (database)
  (sb-ext:atomic-decf (rocksdb-usage-users (rocksdb-usage database)))
  nil)

(defmacro with-rocksdb-live-handle ((handle database) &body body)
  "Run BODY with HANDLE bound to DATABASE's native handle, counted as in use.

Every native call that takes the rocksdb_t* goes through here, so a close
waits for it and a call that starts after the close began signals instead."
  (let ((db (gensym "DATABASE")))
    `(let* ((,db ,database)
            (,handle (rocksdb-usage-enter ,db)))
       (unwind-protect (progn ,@body)
         (rocksdb-usage-leave ,db)))))

(defconstant +rocksdb-close-drain-seconds+ 5
  "How long a close waits for in-flight callers to leave the native handle.

Callers are single C calls and short iterator scans, so a healthy shutdown
drains in microseconds. The bound exists for the caller the shutdown could not
join; past it the close is refused rather than freeing memory under that
caller, and the store is left to the process exit exactly as before.")

(defun close-rocksdb-key-value-database
    (database &key (drain-seconds +rocksdb-close-drain-seconds+))
  "Release every native resource DATABASE holds. Return :CLOSED when this call
closed it, NIL when it was already closing or closed, and :BUSY when callers
still held the handle after DRAIN-SECONDS.

Exactly once: the first caller claims CLOSING-P by compare-and-swap, so a
second or concurrent call returns NIL without touching a native pointer. From
the claim on, every new operation signals ROCKSDB-DATABASE-CLOSED-ERROR. The
close then waits for the callers already inside to leave (see ROCKSDB-USAGE)
and only then frees anything. :BUSY leaves the handle open and unusable: a
leaked handle is the pre-existing exit behaviour, a freed one under a live
caller is a fault.

What rocksdb_close does, from the pinned source: it is `delete db->rep`
(db/c.cc:1557), which runs DBImpl::CloseHelper (db/db_impl/db_impl.cc:527). That
sets the shutdown marker (CancelAllBackgroundWork(false)), unschedules this
DB's queued tasks on all three priority pools, WAITS without a timeout for the
running flush/compaction/purge jobs to drain, releases the directory LOCK and
writes \"Shutdown complete\" to the info LOG (db_impl.cc:705). The pool threads
themselves belong to Env::Default() and survive the close; see
RELEASE-ROCKSDB-BACKGROUND-THREADS.

Durability is unchanged by closing. CancelAllBackgroundWork flushes memtables
at shutdown only when has_unpersisted_data_ is set (db_impl.cc:489), which
requires writes that bypass the WAL; this tree has no binding that can disable
the WAL, so every acknowledged write is already in it. A synced write
(WRITE-OPTIONS, sync=1) was fsynced before it returned; a buffered write
(BUFFERED-WRITE-OPTIONS, sync=0) is in the WAL file and is replayed on the next
open."
  (let ((usage (rocksdb-usage database)))
    (unless (sb-ext:compare-and-swap (rocksdb-usage-closing-p usage) nil t)
      (sb-thread:barrier (:memory))
      (let ((deadline (+ (get-internal-real-time)
                         (* drain-seconds internal-time-units-per-second))))
        (loop until (zerop (rocksdb-usage-users usage))
              do (when (> (get-internal-real-time) deadline)
                   (return-from close-rocksdb-key-value-database :busy))
                 (sleep 0.005)))
      (let ((handle (rocksdb-handle database))
            (read-options (rocksdb-read-options database))
            (write-options (rocksdb-write-options database))
            (buffered-write-options (rocksdb-buffered-write-options database)))
        (setf (rocksdb-handle database) (cffi:null-pointer)
              (rocksdb-read-options database) (cffi:null-pointer)
              (rocksdb-write-options database) (cffi:null-pointer)
              (rocksdb-buffered-write-options database) (cffi:null-pointer))
        (sb-thread:with-recursive-lock (*rocksdb-lifecycle-lock*)
          (unwind-protect (%rocks-close handle)
            (%rocks-read-options-destroy read-options)
            (%rocks-write-options-destroy write-options)
            (%rocks-write-options-destroy buffered-write-options)
            (decf *rocksdb-open-database-count*))))
      :closed)))

(defmethod kv-close ((database rocksdb-key-value-database))
  (close-rocksdb-key-value-database database))

(defun rocksdb-background-thread-count ()
  "Count this process's threads RocksDB named \"rocksdb:*\", or NIL when the
platform does not expose per-thread names.

The pinned thread pool names each worker it starts with pthread_setname_np
(util/threadpool_imp.cc, StartBGThreads) on glibc; Linux publishes the name in
/proc/self/task/<tid>/comm."
  (let ((tasks (ignore-errors (directory #P"/proc/self/task/*/"))))
    (when tasks
      (count-if (lambda (task)
                  (let ((name (ignore-errors
                               (with-open-file
                                   (stream (merge-pathnames "comm" task))
                                 (read-line stream nil "")))))
                    (and name (<= 8 (length name))
                         (string= "rocksdb:" name :end2 8))))
                tasks))))

(defun release-rocksdb-background-threads (&key (wait-seconds 2))
  "Empty the default Env's background pools when no database is open.

Return :RELEASED, :OPEN when a database is still open (nothing is changed),
or NIL when the library was never loaded (there are no pools).

Why this exists. The pools are Env::Default()'s, not the database's, so
closing every database leaves their threads parked. At exit(3) the static
JoinThreadsOnExit (env/env_posix.cc:220) joins each pool and clears its
std::thread vector -- the exit-time teardown the Section 5 fault trace names.
Setting a pool to zero threads instead makes each worker detach itself and
leave the vector while the process is alive (threadpool_imp.cc, the
IsLastExcessiveThread branch of BGThread), so the exit-time join finds empty
pools. A later open sizes them again (INCREASE-PARALLELISM), which is why this
runs under *ROCKSDB-LIFECYCLE-LOCK* and only at a zero open count.

The workers exit asynchronously. Where thread names are visible this waits up
to WAIT-SECONDS for the last \"rocksdb:*\" thread to go."
  (unless *rocksdb-library-loaded-p*
    (return-from release-rocksdb-background-threads nil))
  (progn
    (sb-thread:with-recursive-lock (*rocksdb-lifecycle-lock*)
      (unless (zerop *rocksdb-open-database-count*)
        (return-from release-rocksdb-background-threads :open))
      (let ((env (%rocks-create-default-env)))
        (unwind-protect
             (progn
               (%rocks-env-set-low-priority-threads env 0)
               (%rocks-env-set-high-priority-threads env 0)
               (%rocks-env-set-bottom-priority-threads env 0))
          (%rocks-env-destroy env))))
    (let ((deadline (+ (get-internal-real-time)
                       (* wait-seconds internal-time-units-per-second))))
      (loop for count = (rocksdb-background-thread-count)
            while (and count (plusp count)
                       (< (get-internal-real-time) deadline))
            do (sleep 0.01))))
  :released)

(defun rocksdb-copy-foreign-bytes (pointer length)
  (let ((result (make-byte-vector length)))
    (when (plusp length)
      (cffi:with-pointer-to-vector-data (result-pointer result)
        (%rocks-memory-copy result-pointer pointer length)))
    result))

(defmethod kv-get ((database rocksdb-key-value-database) key &optional default)
  (with-rocks-bytes (key-pointer key-length key)
    (cffi:with-foreign-object (value-length :size)
      (let ((value
              (with-rocks-error (error)
                (with-rocksdb-live-handle (handle database)
                  (%rocks-get handle
                              (rocksdb-read-options database)
                              key-pointer key-length value-length error)))))
        (if (cffi:null-pointer-p value)
            (values default nil)
            (unwind-protect
                 (values
                  (rocksdb-copy-foreign-bytes
                   value (cffi:mem-ref value-length :size))
                  t)
              (%rocks-free value)))))))

(defmethod kv-get-many
    ((database rocksdb-key-value-database) keys &optional default)
  (let* ((normalized-keys (kv-get-many-keys keys))
         (count (length normalized-keys))
         (results (make-array count :initial-element default))
         (present (make-array count :element-type 'bit :initial-element 0))
         (key-bytes
           (loop for key across normalized-keys sum (length key)))
         (first-error nil))
    (when (zerop count)
      (return-from kv-get-many (values results present)))
    (cffi:with-foreign-pointer (key-buffer (max 1 key-bytes))
      (cffi:with-foreign-objects
          ((key-pointers :pointer count)
           (key-lengths :size count)
           (value-pointers :pointer count)
           (value-lengths :size count)
           (error-pointers :pointer count))
        (unwind-protect
             (progn
               ;; Cleanup examines every output slot even when input copying
               ;; unwinds, so initialize the complete native result surface
               ;; before any later operation can signal.
               (dotimes (index count)
                 (setf
                  (cffi:mem-aref value-pointers :pointer index)
                  (cffi:null-pointer)
                  (cffi:mem-aref value-lengths :size index) 0
                  (cffi:mem-aref error-pointers :pointer index)
                  (cffi:null-pointer)))
               (loop with key-offset = 0
                     for index below count
                     for key = (aref normalized-keys index)
                     for key-length = (length key)
                     for key-pointer =
                       (cffi:inc-pointer key-buffer key-offset)
                     do (when (plusp key-length)
                          (cffi:with-pointer-to-vector-data
                              (source-pointer key)
                            (%rocks-memory-copy
                             key-pointer source-pointer key-length)))
                        (setf
                         (cffi:mem-aref key-pointers :pointer index)
                         key-pointer
                         (cffi:mem-aref key-lengths :size index) key-length)
                        (incf key-offset key-length))
               (with-rocksdb-live-handle (handle database)
                 (%rocks-multi-get
                  handle (rocksdb-read-options database)
                  count key-pointers key-lengths value-pointers value-lengths
                  error-pointers))
               (dotimes (index count)
                 (let ((error (cffi:mem-aref error-pointers :pointer index))
                       (value (cffi:mem-aref value-pointers :pointer index)))
                   (unless (cffi:null-pointer-p error)
                     (unless first-error
                       (setf first-error
                             (cffi:foreign-string-to-lisp error)))
                     (%rocks-free error)
                     (setf (cffi:mem-aref error-pointers :pointer index)
                           (cffi:null-pointer)))
                   (unless (cffi:null-pointer-p value)
                     (setf (aref results index)
                           (rocksdb-copy-foreign-bytes
                            value
                            (cffi:mem-aref value-lengths :size index))
                           (aref present index) 1)
                     (%rocks-free value)
                     (setf (cffi:mem-aref value-pointers :pointer index)
                           (cffi:null-pointer)))))
               (when first-error
                 (error "RocksDB multi-get: ~A" first-error)))
          ;; Protect error unwinds during result copying as well as native
          ;; calls. WITH-FOREIGN-POINTER owns the contiguous input buffer.
          (dotimes (index count)
            (let ((error (cffi:mem-aref error-pointers :pointer index))
                  (value (cffi:mem-aref value-pointers :pointer index)))
              (unless (cffi:null-pointer-p error)
                (%rocks-free error))
              (unless (cffi:null-pointer-p value)
                (%rocks-free value)))))))
    (values results present)))

(defmethod kv-put ((database rocksdb-key-value-database) key value)
  (with-rocks-bytes (key-pointer key-length key)
    (with-rocks-bytes (value-pointer value-length value)
      (with-rocks-error (error)
        (with-rocksdb-live-handle (handle database)
          (%rocks-put handle
                      (rocksdb-write-options database)
                      key-pointer key-length value-pointer value-length
                      error)))))
  database)

(defmethod kv-delete ((database rocksdb-key-value-database) key)
  (multiple-value-bind (ignored present-p) (kv-get database key)
    (declare (ignore ignored))
    (with-rocks-bytes (key-pointer key-length key)
      (with-rocks-error (error)
        (with-rocksdb-live-handle (handle database)
          (%rocks-delete handle
                         (rocksdb-write-options database)
                         key-pointer key-length error))))
    present-p))

(defun rocksdb-apply-batch-with-options (database batch write-options)
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
             (with-rocksdb-live-handle (handle database)
               (%rocks-write handle write-options native error))))
      (%rocks-batch-destroy native)))
  database)

(defmethod kv-apply-batch ((database rocksdb-key-value-database)
                           (batch kv-write-batch))
  (rocksdb-apply-batch-with-options
   database batch (rocksdb-write-options database)))

(defmethod kv-apply-batch-buffered
    ((database rocksdb-key-value-database) (batch kv-write-batch))
  (rocksdb-apply-batch-with-options
   database batch (rocksdb-buffered-write-options database)))

(defmethod kv-buffered-batch-supported-p
    ((database rocksdb-key-value-database))
  (declare (ignore database))
  t)

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
  ;;
  ;; A live iterator pins the DB (rocksdb_close must not run under it), so it
  ;; counts as one user of the handle from creation until FINISH, and a close
  ;; waits for it the same way it waits for a single native call.
  (let ((handle (rocksdb-usage-enter database))
        (iterator (cffi:null-pointer))
        (returned-p nil))
    (unwind-protect
         (let (;; Copy range boundaries once. Comparing native iterator keys as
               ;; raw bytes avoids allocating a hex string per visited record.
               (start-key (and start (kv-copy-bytes start)))
               (end-key (and end (kv-copy-bytes end))))
           (setf iterator (%rocks-iterator-create
                           handle (rocksdb-read-options database)))
           (cond
             (reverse-p
              (cond
                (end
                 ;; SEEK lands on the first key >= END; step back to the last
                 ;; key strictly below the exclusive upper bound. When no key
                 ;; reaches END, the largest key overall is in range, so fall
                 ;; back to SEEK-TO-LAST.
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
                    ;; Null the handle before finishing so a later call is a
                    ;; safe no-op even if error propagation unwinds through
                    ;; here; release the usage count exactly once, after the
                    ;; native iterator is gone.
                    (let ((it iterator))
                      (setf iterator (cffi:null-pointer))
                      (unwind-protect (rocksdb-iterator-finish it)
                        (rocksdb-usage-leave database)))
                    (values nil nil nil)))
             (multiple-value-prog1
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
                         (let* ((key-pointer
                                  (%rocks-iterator-key iterator key-length))
                                (key (rocksdb-copy-foreign-bytes
                                      key-pointer
                                      (cffi:mem-ref key-length :size))))
                           (if (or (and reverse-p start-key
                                        (kv-key< key start-key))
                                   (and (not reverse-p) end-key
                                        (not (kv-key< key end-key))))
                               (finish)
                               (let* ((value-pointer
                                        (%rocks-iterator-value
                                         iterator value-length))
                                      (value (rocksdb-copy-foreign-bytes
                                              value-pointer
                                              (cffi:mem-ref value-length
                                                            :size))))
                                 (if reverse-p
                                     (%rocks-iterator-previous iterator)
                                     (%rocks-iterator-next iterator))
                                 (values key value t))))))))
                  (lambda ()
                    (unless (cffi:null-pointer-p iterator)
                      (finish))
                    nil))
               (setf returned-p t))))
      (unless returned-p
        (unless (cffi:null-pointer-p iterator)
          (%rocks-iterator-destroy iterator))
        (rocksdb-usage-leave database)))))
