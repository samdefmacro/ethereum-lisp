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

(defclass rocksdb-key-value-database (key-value-database)
  ((handle :initarg :handle :accessor rocksdb-handle)
   (read-options :initarg :read-options :reader rocksdb-read-options)
   (write-options :initarg :write-options :reader rocksdb-write-options)
   (buffered-write-options
    :initarg :buffered-write-options
    :reader rocksdb-buffered-write-options)
   (path :initarg :path :reader rocksdb-path)))

(defvar *rocksdb-library-loaded-p* nil)

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
  "Incremental background-file sync width; WAL cursor batches remain synced.")
(defconstant +rocksdb-block-cache-bytes+ (* 256 1024 1024)
  "Block-cache budget for the supported shared 16-GiB EL/CL node profile.

The 7-GiB EL cgroup also charges RocksDB memtables and filesystem cache.  Larger
caches exhausted that hard boundary or forced enough direct reclaim to make
the consensus client's Engine upcheck time out during sustained Hoodi range
import even though the live Lisp heap remained below two GiB.")
(defconstant +rocksdb-bloom-bits-per-key+ 10.0d0
  "Full-filter budget for random content-addressed state lookups.")

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

(defun make-rocksdb-key-value-database (path &key (create-if-missing-p t))
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
          ;; ring even without this option. ReadOptions nevertheless keeps
          ;; async_io disabled by default, which disables asynchronous
          ;; iterator prefetch and any coroutine-enabled cross-level MultiGet
          ;; scheduling. Enable it on every production read handle and verify
          ;; the exact library retained the setting before the handle becomes
          ;; observable.
          (%rocks-read-options-set-async-io read-options 1)
          (unless (= 1 (%rocks-read-options-get-async-io read-options))
            (error "RocksDB refused to enable asynchronous read I/O"))
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
          ;; The RocksDB 11 block-table default is only 32 MiB. SNAP account
          ;; ranges and final healing issue wide random content-addressed reads
          ;; over tens of gigabytes, so that fallback turns nearly every lookup
          ;; into device I/O. Keep a bounded cache and Bloom filters in
          ;; RocksDB's native table layer; neither changes WAL durability or
          ;; the bytes returned to verification.
          (rocksdb-configure-block-table options)
          (%rocks-write-options-sync write-options 1)
          ;; Only unpublished, content-addressed SNAP prerequisites use this
          ;; handle. Their following cursor batch uses WRITE-OPTIONS above;
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

(defun close-rocksdb-key-value-database (database)
  (unless (cffi:null-pointer-p (rocksdb-handle database))
    (%rocks-close (rocksdb-handle database))
    (%rocks-read-options-destroy (rocksdb-read-options database))
    (%rocks-write-options-destroy (rocksdb-write-options database))
    (%rocks-write-options-destroy
     (rocksdb-buffered-write-options database))
    (setf (rocksdb-handle database) (cffi:null-pointer)))
  nil)

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
               (%rocks-multi-get
                (rocksdb-handle database) (rocksdb-read-options database)
                count key-pointers key-lengths value-pointers value-lengths
                error-pointers)
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
             (%rocks-write (rocksdb-handle database)
                           write-options native error)))
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
