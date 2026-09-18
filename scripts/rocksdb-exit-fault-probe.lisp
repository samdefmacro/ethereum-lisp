;;;; RocksDB process-exit fault probe.
;;;;
;;;; Isolates the shutdown-time SBCL memory fault recorded in
;;;; docs/evidence/sec5-shutdown-memory-fault-trace.txt, seen on the Hoodi
;;;; runs 0c6b51bf, 646da589 and 5c8a39c0. Each mode leaves the store in one
;;;; specific state and then terminates the process exactly the way the shipped
;;;; runtime does: Dockerfile.runtime's RUNTIME-TOPLEVEL finishes both streams
;;;; and calls (SB-EXT:EXIT :CODE code :ABORT NIL). The parent test reads this
;;;; process's stderr and decides whether a fault was emitted.
;;;;
;;;; Two variables are crossed, because the live node holds the unsafe corner
;;;; of both: whether RocksDB reader threads are still running at the exit, and
;;;; whether CLOSE-ROCKSDB-KEY-VALUE-DATABASE runs before it. The serving node
;;;; never closes -- CLOSE-ROCKSDB-KEY-VALUE-DATABASE has exactly one caller,
;;;; src/app/cli/db.lisp:105-108, on the offline operator path.
;;;;
;;;; Usage: sbcl --script scripts/rocksdb-exit-fault-probe.lisp MODE DIR MIB READERS
;;;;
;;;; Modes:
;;;;   live-no-close   -- reader threads still scanning, NO close, unwinding exit
;;;;   live-close      -- reader threads still scanning, close, then exit
;;;;   quiet-no-close  -- readers joined first, NO close, unwinding exit
;;;;   quiet-close     -- readers joined first, close, then exit
;;;;
;;;; The probe writes one readable plist to stdout and nothing else. Every
;;;; diagnostic belongs on stderr, which is the channel under test.

(defparameter *root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(require :asdf)
(asdf:load-asd (merge-pathnames "ethereum-lisp.asd" *root*))
(asdf:load-system :ethereum-lisp)

(defparameter *probe-value-bytes* 4096
  "Value width, so one 4-KiB block table entry holds about one value and a
reused value pool still produces incompressible SST content.")

(defparameter *probe-pool-size* 256
  "Distinct values generated once and then cycled, so write volume is bounded
by RocksDB and the filesystem rather than by Lisp byte generation.")

(defparameter *probe-batch-records* 64
  "Records per write batch: about a quarter-megabyte of payload per batch.")

(defun probe-mix (state)
  (logand (+ (* state 6364136223846793005) 1442695040888963407)
          #xffffffffffffffff))

(defun probe-make-pool ()
  (let ((pool (make-array *probe-pool-size*))
        (state 1))
    (dotimes (index *probe-pool-size* pool)
      (let ((value (ethereum-lisp:make-byte-vector *probe-value-bytes*)))
        (dotimes (byte *probe-value-bytes*)
          (setf state (probe-mix state))
          (setf (aref value byte) (logand (ash state -33) #xff)))
        (setf (aref pool index) value)))))

(defun probe-key (index)
  (let ((key (ethereum-lisp:make-byte-vector 16))
        (state (probe-mix (1+ index))))
    (dotimes (byte 16 key)
      (setf state (probe-mix state))
      (setf (aref key byte) (logand (ash state -33) #xff)))))

(defun probe-fill (database pool megabytes)
  "Write MEGABYTES of payload through the buffered (sync=0) write handle.

Buffered batches are the SNAP import path's own handle, so this drives the same
memtable, flush and compaction cadence a healing node drives."
  (let* ((records (max 1 (floor (* megabytes 1024 1024) *probe-value-bytes*)))
         (written 0))
    (loop while (< written records)
          do (let ((batch (ethereum-lisp.database:make-kv-write-batch))
                   (count (min *probe-batch-records* (- records written))))
               (dotimes (offset count)
                 (let ((index (+ written offset)))
                   (ethereum-lisp.database:kv-batch-put
                    batch
                    (probe-key index)
                    (aref pool (mod index *probe-pool-size*)))))
               (ethereum-lisp.database:kv-apply-batch-buffered database batch)
               (incf written count)))
    written))

(defvar *probe-readers-stop* nil)
(defvar *probe-reader-scans* nil)

(defun probe-reader-loop (database slot)
  "Scan the store in bounded bursts until *PROBE-READERS-STOP* is set.

Every iterator is taken through the documented contract: UNWIND-PROTECT with an
explicit closer call, which is what every snap-sync call site does. The burst is
short and yields between bursts so the readers do not starve the writer that is
driving flush and compaction -- the point is to have a reader inside a RocksDB
call at the exit, not to maximise read throughput."
  ;; CLAUDE.md: every MAKE-THREAD body handles its own conditions, because the
  ;; suite and the node both run under sbcl --script (--disable-debugger), so an
  ;; unhandled condition in ANY thread exits the whole process with code 1 and
  ;; destroys the run rather than failing a test.
  (handler-case
      (loop until *probe-readers-stop*
            do (multiple-value-bind (iterator close-iterator)
                   (ethereum-lisp.database:kv-iterator database)
                 (unwind-protect
                      (loop repeat 256
                            do (multiple-value-bind (key value present-p)
                                   (funcall iterator)
                                 (declare (ignore key value))
                                 (unless present-p (return))
                                 (when *probe-readers-stop* (return))))
                   (when close-iterator (funcall close-iterator)))
                 (incf (aref *probe-reader-scans* slot))
                 (sleep 0.001d0)))
    (serious-condition (condition)
      (format *error-output* "probe reader ~D: ~A~%" slot condition)
      (finish-output *error-output*))))

(defun probe-start-readers (database count)
  (setf *probe-readers-stop* nil)
  (setf *probe-reader-scans* (make-array (max 1 count) :initial-element 0))
  (loop for slot below count
        collect (sb-thread:make-thread
                 (let ((slot slot))
                   (lambda () (probe-reader-loop database slot)))
                 :name (format nil "probe-reader-~D" slot))))

(defun probe-join-readers (threads)
  (setf *probe-readers-stop* t)
  (dolist (thread threads)
    (sb-thread:join-thread thread :timeout 30 :default :timeout)))

(defun probe-report (mode records closed-p readers scans)
  (let ((*print-readably* t))
    (write (list :mode mode :records records :closed closed-p
                 :readers readers :scans scans)
           :stream *standard-output*)
    (terpri *standard-output*)
    (finish-output *standard-output*)))

(defun probe-main ()
  (let* ((arguments (cdr sb-ext:*posix-argv*))
         (mode (first arguments))
         (directory (second arguments))
         (megabytes (parse-integer (or (third arguments) "384")))
         (reader-count (parse-integer (or (fourth arguments) "4")))
         (live-p (member mode '("live-no-close" "live-close") :test #'string=))
         (close-p (member mode '("live-close" "quiet-close") :test #'string=)))
    (unless (and mode directory
                 (member mode '("live-no-close" "live-close"
                                "quiet-no-close" "quiet-close")
                         :test #'string=))
      (format *error-output* "usage: MODE DIR MIB READERS~%")
      (sb-ext:exit :code 2 :abort t))
    (ensure-directories-exist (uiop:ensure-directory-pathname directory))
    (let* ((database
             (ethereum-lisp.database:make-rocksdb-key-value-database
              (uiop:ensure-directory-pathname directory)))
           (pool (probe-make-pool))
           (records 0)
           (readers '())
           (closed-p nil))
      ;; Seed first so the readers have something to scan, then keep writing
      ;; underneath them so flush and compaction stay in flight.
      (setf records (probe-fill database pool (max 1 (floor megabytes 4))))
      (setf readers (probe-start-readers database reader-count))
      (incf records (probe-fill database pool megabytes))
      (unless live-p
        (probe-join-readers readers))
      (when close-p
        ;; The step the serving node never performs. RocksDB's DB destructor
        ;; cancels and waits for its own background jobs; an unwinding
        ;; SB-EXT:EXIT cannot provide that ordering by itself.
        (ethereum-lisp.database:close-rocksdb-key-value-database database)
        (setf closed-p t))
      (probe-report mode records closed-p reader-count
                    (and *probe-reader-scans*
                         (coerce *probe-reader-scans* 'list)))
      ;; Byte-for-byte the shipped termination path.
      (finish-output *standard-output*)
      (finish-output *error-output*)
      (sb-ext:exit :code 0 :abort nil))))

(probe-main)
