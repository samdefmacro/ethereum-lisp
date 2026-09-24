(in-package #:ethereum-lisp.cli)

;;;; The node's memory budget, and keeping the C heap inside it.
;;;;
;;;; One number, --memory.budget (MiB, default 7 GiB: the Hoodi gate's
;;;; container ceiling), sizes RocksDB's block cache and memtables
;;;; (MAKE-ROCKSDB-MEMORY-PROFILE).  The Lisp heap is bounded separately by the
;;;; executable's dynamic space.  What neither bound covers is glibc malloc's
;;;; retention of freed memory, which on the b5161312 Hoodi run held 7.9 GiB
;;;; of arena pages against RocksDB's < 1 GiB of live caches
;;;; (docs/evidence/sec5-resident-memory.txt).  So at start-up the CLI pins
;;;; glibc's mmap threshold, and while the node serves, a maintenance thread
;;;; returns free arena pages to the kernel and logs where resident memory
;;;; is.  The SNAP target completing -- the end of the heaviest allocation
;;;; phase -- releases at once rather than waiting for the next tick.
;;;;
;;;; None of this touches the WAL, fsync policy or any consensus path.

(defparameter *devnet-memory-release-interval-seconds* 60
  "How often the maintenance thread returns free malloc pages to the kernel.

malloc_trim locks each arena while it trims it (15-17 ms for ~300 MiB over 46
arenas, measured), so once a minute costs nothing measurable and keeps
retention to what one minute of churn can build.")

(defparameter *devnet-memory-sample-interval-seconds* 300
  "How often the maintenance thread logs node.memory.sample.

A sample reads /proc/self/smaps (about 1.5 MB on a live node) and malloc_info,
so it is kept to one line every five minutes; a release that returns 64 MiB or
more is logged whenever it happens.")

(defconstant +devnet-memory-release-log-threshold-bytes+ (* 64 1024 1024)
  "A periodic release that returns at least this much is logged at once.")

(defun devnet-cli-memory-budget-bytes (options)
  "The node memory budget OPTIONS select, in bytes."
  (let ((mebibytes (getf options :memory-budget-mebibytes)))
    (if mebibytes
        (* mebibytes 1024 1024)
        ethereum-lisp.database:+rocksdb-default-memory-budget-bytes+)))

(defun devnet-memory-mebibytes (bytes)
  (and bytes (round bytes (* 1024 1024))))

(defun devnet-memory-budget-fields (profile mmap-threshold)
  "Log fields that show how PROFILE divides the budget."
  (let* ((budget
           (ethereum-lisp.database:rocksdb-memory-profile-budget-bytes profile))
         (rocksdb
           (ethereum-lisp.database:rocksdb-memory-profile-limit-bytes profile))
         (block-cache
           (ethereum-lisp.database:rocksdb-memory-profile-block-cache-bytes
            profile))
         (write-buffers
           (ethereum-lisp.database:rocksdb-memory-profile-write-buffer-budget-bytes
            profile))
         (memtables
           (ethereum-lisp.database:rocksdb-memory-profile-memtable-limit-bytes
            profile))
         (dynamic-space #+sbcl (sb-ext:dynamic-space-size) #-sbcl nil))
    `(("budgetMb" . ,(devnet-memory-mebibytes budget))
      ("rocksdbBlockCacheMb" . ,(devnet-memory-mebibytes block-cache))
      ("rocksdbWriteBufferBudgetMb" . ,(devnet-memory-mebibytes write-buffers))
      ("rocksdbMemtableLimitMb" . ,(devnet-memory-mebibytes memtables))
      ("lispDynamicSpaceMb" . ,(devnet-memory-mebibytes dynamic-space))
      ;; What remains of the budget once RocksDB's bounded share and the whole
      ;; dynamic space are taken.  Negative means the Lisp heap is NOT bounded
      ;; by the budget and only the live heap keeps the node inside it.
      ("headroomMb"
       . ,(and dynamic-space
               (devnet-memory-mebibytes (- budget rocksdb dynamic-space))))
      ("mallocMmapThresholdBytes" . ,mmap-threshold))))

(defvar *devnet-malloc-mmap-threshold-bytes* nil
  "The mmap threshold the CLI pinned for this run, or NIL when it did not.")

(defun call-with-devnet-cli-memory-budget (options thunk)
  "Run THUNK with RocksDB sized from the memory budget in OPTIONS.

Assigned, not bound, for the reason CALL-WITH-DEVNET-CLI-HTTP-LIMITS gives:
the datadir may be opened on any thread.  Also pins glibc's mmap threshold
(NATIVE-MALLOC-CONFIGURE), which is process-wide and one-way, before the
storage engine allocates anything.  Nothing is logged here: stdout may be the
--json summary's; a serving node logs node.memory.budget when its maintenance
worker starts."
  (unless (functionp thunk)
    (error "Devnet memory budget thunk must be a function"))
  (let ((profile (ethereum-lisp.database:make-rocksdb-memory-profile
                  (devnet-cli-memory-budget-bytes options)))
        (previous ethereum-lisp.database:*rocksdb-memory-profile*)
        (previous-threshold *devnet-malloc-mmap-threshold-bytes*))
    (unwind-protect
         (progn
           (setf ethereum-lisp.database:*rocksdb-memory-profile* profile
                 *devnet-malloc-mmap-threshold-bytes* (native-malloc-configure))
           (funcall thunk))
      (setf ethereum-lisp.database:*rocksdb-memory-profile* previous
            *devnet-malloc-mmap-threshold-bytes* previous-threshold))))

(defun devnet-log-memory-budget (sink)
  "Log node.memory.budget for the profile and threshold now in force."
  (telemetry-log
   :info "node.memory.budget"
   :fields (devnet-memory-budget-fields
            ethereum-lisp.database:*rocksdb-memory-profile*
            *devnet-malloc-mmap-threshold-bytes*)
   :sink sink))

(defun devnet-memory-sample-fields (&key (lisp-resident-p t))
  "Where the process's resident memory is now, as log fields.

nativeResidentMb is the anonymous resident set less the dynamic space's
resident pages: the C heap, thread stacks and library data.  mallocInUseMb is
what malloc has handed out and not had back; mallocFreeMb what it holds free
in its arenas (still counted after a release, whose pages are gone)."
  (let* ((status (process-memory-status))
         (anonymous (getf status :resident-anonymous))
         (lisp-resident (and lisp-resident-p
                             (ignore-errors
                              (lisp-dynamic-space-resident-bytes))))
         (report (ignore-errors (native-malloc-report))))
    `(("rssMb" . ,(devnet-memory-mebibytes (getf status :resident)))
      ("rssAnonMb" . ,(devnet-memory-mebibytes anonymous))
      ("rssPeakMb" . ,(devnet-memory-mebibytes (getf status :resident-peak)))
      ("heapMb" . ,(devnet-memory-mebibytes (telemetry-dynamic-usage-bytes)))
      ,@(when lisp-resident
          `(("lispResidentMb" . ,(devnet-memory-mebibytes lisp-resident))
            ("nativeResidentMb"
             . ,(and anonymous
                     (devnet-memory-mebibytes (- anonymous lisp-resident))))))
      ,@(when report
          `(("mallocInUseMb"
             . ,(devnet-memory-mebibytes
                 (native-malloc-report-in-use-bytes report)))
            ("mallocFreeMb"
             . ,(devnet-memory-mebibytes
                 (native-malloc-report-free-bytes report)))
            ("mallocMmapMb"
             . ,(devnet-memory-mebibytes
                 (native-malloc-report-mmap-bytes report)))
            ("mallocHeaps" . ,(native-malloc-report-heaps report)))))))

(defun devnet-release-native-memory ()
  "Return free malloc pages to the kernel.  Return (VALUES RELEASED-BYTES
ELAPSED-MS), RELEASED-BYTES being the drop in the anonymous resident set; both
NIL off glibc."
  (let* ((before (getf (process-memory-status) :resident-anonymous))
         (elapsed-ms (native-malloc-release))
         (after (getf (process-memory-status) :resident-anonymous)))
    (values (and elapsed-ms before after (max 0 (- before after)))
            elapsed-ms)))

(defun devnet-log-memory-release (sink reason released-bytes elapsed-ms
                                  &key (lisp-resident-p t))
  (telemetry-log
   :info "node.memory.release"
   :fields `(("reason" . ,reason)
             ("releasedMb" . ,(devnet-memory-mebibytes released-bytes))
             ("releaseMs" . ,elapsed-ms)
             ,@(devnet-memory-sample-fields :lisp-resident-p lisp-resident-p))
   :sink sink))

(defun devnet-release-native-memory-and-log (sink reason)
  "Release free malloc pages now and log node.memory.release naming REASON,
with a full sample, to SINK.  Return the bytes released (NIL off glibc)."
  (multiple-value-bind (released-bytes elapsed-ms)
      (devnet-release-native-memory)
    (when elapsed-ms
      (devnet-log-memory-release sink reason released-bytes elapsed-ms))
    released-bytes))

(defun devnet-node-release-native-memory (node reason)
  "DEVNET-RELEASE-NATIVE-MEMORY-AND-LOG to NODE's telemetry sink."
  (devnet-release-native-memory-and-log (devnet-node-telemetry-sink node)
                                        reason))

(defun devnet-memory-maintenance-tick (sink elapsed-seconds)
  "One maintenance pass, ELAPSED-SECONDS after the thread started, logging to
SINK.

Releases on every release interval.  Logs node.memory.sample on every sample
interval, and between samples logs a release that returned
+DEVNET-MEMORY-RELEASE-LOG-THRESHOLD-BYTES+ or more."
  (let ((release-p (zerop (mod elapsed-seconds
                               *devnet-memory-release-interval-seconds*)))
        (sample-p (zerop (mod elapsed-seconds
                              *devnet-memory-sample-interval-seconds*))))
    (multiple-value-bind (released-bytes elapsed-ms)
        (if release-p (devnet-release-native-memory) (values nil nil))
      (cond
        (sample-p
         (telemetry-log
          :info "node.memory.sample"
          :fields `(,@(when elapsed-ms
                        `(("releasedMb"
                           . ,(devnet-memory-mebibytes released-bytes))
                          ("releaseMs" . ,elapsed-ms)))
                    ,@(devnet-memory-sample-fields))
          :sink sink))
        ((and released-bytes
              (>= released-bytes +devnet-memory-release-log-threshold-bytes+))
         (devnet-log-memory-release sink "periodic" released-bytes elapsed-ms
                                    :lisp-resident-p nil))))))

(defun devnet-start-memory-maintenance-thread
    (node shutdown-controller error-callback)
  "Log node.memory.budget, then start the thread that keeps freed C-heap
memory from staying resident.  Returns NIL (and starts nothing) when the
allocator is not glibc."
  #-sbcl
  (declare (ignore node shutdown-controller error-callback))
  #-sbcl
  nil
  #+sbcl
  (devnet-log-memory-budget (devnet-node-telemetry-sink node))
  #+sbcl
  (when (native-malloc-available-p)
    (let ((sink (devnet-node-telemetry-sink node)))
      (sb-thread:make-thread
       (lambda ()
         (handler-case
             (loop for elapsed-seconds from 1
                   until (devnet-shutdown-requested-p shutdown-controller)
                   do (sleep 1)
                      (unless (devnet-shutdown-requested-p shutdown-controller)
                        (devnet-memory-maintenance-tick sink elapsed-seconds)))
           ;; MANDATORY, not defensive: under `sbcl --script` an unhandled
           ;; condition in any thread exits the whole process.
           (serious-condition (condition)
             (funcall error-callback condition)
             (devnet-shutdown-request shutdown-controller))))
       :name "ethereum-lisp-devnet-memory-maintenance"))))
