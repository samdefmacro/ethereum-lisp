(in-package #:ethereum-lisp.test)

;;;; Native (glibc malloc) memory: reading its totals, returning free pages,
;;;; and pinning the mmap threshold.  See docs/evidence/sec5-resident-memory.txt.

(defparameter *native-malloc-info-fixture*
  ;; glibc 2.36 malloc_info(0, ...) shape, two arenas.  Every per-heap value
  ;; differs from the process totals after the last </heap>, so a reader that
  ;; takes the first match reports a heap, not the process.
  "<malloc version=\"1\">
<heap nr=\"0\">
<sizes>
  <size from=\"33\" to=\"48\" total=\"96\" count=\"2\"/>
  <unsorted from=\"65552\" to=\"65552\" total=\"65552\" count=\"1\"/>
</sizes>
<total type=\"fast\" count=\"2\" size=\"96\"/>
<total type=\"rest\" count=\"1\" size=\"65552\"/>
<system type=\"current\" size=\"1048576\"/>
<system type=\"max\" size=\"2097152\"/>
<aspace type=\"total\" size=\"1048576\"/>
<aspace type=\"mprotect\" size=\"1048576\"/>
</heap>
<heap nr=\"1\">
<sizes>
</sizes>
<total type=\"fast\" count=\"0\" size=\"0\"/>
<total type=\"rest\" count=\"3\" size=\"3000000\"/>
<system type=\"current\" size=\"4194304\"/>
<system type=\"max\" size=\"4194304\"/>
<aspace type=\"total\" size=\"4194304\"/>
<aspace type=\"mprotect\" size=\"4194304\"/>
<aspace type=\"subheaps\" size=\"1\"/>
</heap>
<total type=\"fast\" count=\"2\" size=\"96\"/>
<total type=\"rest\" count=\"4\" size=\"3065552\"/>
<total type=\"mmap\" count=\"3\" size=\"409600\"/>
<system type=\"current\" size=\"5242880\"/>
<system type=\"max\" size=\"6291456\"/>
<aspace type=\"total\" size=\"5242880\"/>
<aspace type=\"mprotect\" size=\"5242880\"/>
</malloc>
")

(deftest native-malloc-info-reads-the-process-totals-not-a-heap
  (let ((report (ethereum-lisp.telemetry:parse-native-malloc-info
                 *native-malloc-info-fixture*)))
    (is (= 2 (ethereum-lisp.telemetry:native-malloc-report-heaps report)))
    (is (= 5242880
           (ethereum-lisp.telemetry:native-malloc-report-system-bytes report)))
    (is (= (+ 96 3065552)
           (ethereum-lisp.telemetry:native-malloc-report-free-bytes report)))
    (is (= 409600
           (ethereum-lisp.telemetry:native-malloc-report-mmap-bytes report)))
    (is (= (+ (- 5242880 (+ 96 3065552)) 409600)
           (ethereum-lisp.telemetry:native-malloc-report-in-use-bytes report))))
  ;; Positive control: the fixture really does separate the two readings --
  ;; the first system/current in it is heap 0's, not the total.
  (let* ((needle "<system type=\"current\" size=\"")
         (first (search needle *native-malloc-info-fixture*)))
    (is (= 1048576
           (parse-integer *native-malloc-info-fixture*
                          :start (+ first (length needle))
                          :junk-allowed t))))
  ;; Output without process totals is refused, not read as zero.
  (signals error
    (ethereum-lisp.telemetry:parse-native-malloc-info
     "<malloc version=\"1\"><heap nr=\"0\"></heap></malloc>")))

(defun native-memory-test-anonymous-resident-bytes ()
  (getf (ethereum-lisp.telemetry:process-memory-status) :resident-anonymous))

(defun native-memory-test-touch (pointer bytes)
  "Write one byte per page so every page of the block is resident."
  (loop for offset from 0 below bytes by 4096
        do (setf (cffi:mem-aref pointer :uint8 offset) 1)))

(defun native-memory-test-fragment (count bytes)
  "Allocate COUNT blocks of BYTES, each followed by a small live pin, touch
them, free the blocks and return the pins.  The pins stop glibc from
coalescing the freed blocks into the top of the heap, which is the shape a
long-running allocator is in: free memory below live memory.

Runs on a thread of its own so the blocks come from a thread arena, as every
RocksDB and node worker's do.  Run on a child SBCL's main thread (the brk
arena), the unpinned 64 x 1 MiB probe kept only 132 KiB resident, so it would
not show the retention at all."
  (let ((result nil))
    (sb-thread:join-thread
     (sb-thread:make-thread
      (lambda ()
        (handler-case
            (let ((blocks '()) (pins '()))
              (loop repeat count
                    do (let ((block (cffi:foreign-alloc :uint8 :count bytes)))
                         (native-memory-test-touch block bytes)
                         (push block blocks)
                         (push (cffi:foreign-alloc :uint8 :count 64) pins)))
              (mapc #'cffi:foreign-free blocks)
              (setf result pins))
          (error (condition) (setf result condition))))
      :name "native-memory-test-fragment"))
    (when (typep result 'condition)
      (error result))
    result))

(deftest native-malloc-release-returns-freed-arena-pages
  (:layer :integration :module :native-memory)
  ;; The mechanism behind the Hoodi node's 7.9 GiB of arena pages, and the
  ;; release that returns them.  64-KiB blocks are below every mmap threshold
  ;; glibc can be in (its minimum is 128 KiB), so they always come from an
  ;; arena whatever this process configured earlier.
  (unless (ethereum-lisp.telemetry:native-malloc-available-p)
    (skip-test "glibc malloc_trim/malloc_info are unavailable"))
  ;; Start from no resident free chunks, so every page the probe frees is one
  ;; it faulted in.  Trimmed directly so that a broken NATIVE-MALLOC-RELEASE
  ;; fails the assertion below rather than this setup.
  (cffi:foreign-funcall "malloc_trim" :size 0 :int)
  (let* ((block-bytes (* 64 1024))
         (count 1024)                   ; 64 MiB
         (total (* count block-bytes))
         (pins (native-memory-test-fragment count block-bytes)))
    (unwind-protect
         (let* ((after-free (native-memory-test-anonymous-resident-bytes))
                (released-ms (ethereum-lisp.telemetry:native-malloc-release))
                (after-release (native-memory-test-anonymous-resident-bytes)))
           ;; Freeing alone left the blocks resident -- the retention -- and
           ;; the release gives at least 3/4 of them back.  Both at once: the
           ;; release cannot drop what free already returned.  (Measured:
           ;; 60 of 64 MiB still resident after free, 60 MiB returned, 4-5 ms.
           ;; A release that does nothing fails here.)
           (is (integerp released-ms))
           (is (>= (- after-free after-release) (* 3/4 total))))
      (mapc #'cffi:foreign-free pins))))

(defun native-memory-test-child-retained-bytes (pin-threshold-p)
  "Run the 1-MiB fragmentation probe in a fresh SBCL and return the anonymous
resident bytes still held after the blocks were freed.

A child, because the threshold is process-wide and one-way: glibc cannot turn
its dynamic threshold back on, so the unpinned control cannot run in a process
that has pinned it.  The child first frees one 4-MiB mmapped block, which
raises glibc's dynamic threshold above 1 MiB exactly as a freed memtable or
batch buffer does on a live node."
  (let* ((result-path
           (format nil "/tmp/ethereum-lisp-native-memory-~A-~A.sexp"
                   (if pin-threshold-p "pinned" "dynamic") (random 1000000000)))
         (form
           (format nil "(progn
  (when ~A (ethereum-lisp.telemetry:native-malloc-configure))
  (cffi:foreign-free (let ((p (cffi:foreign-alloc :uint8 :count ~D)))
                       (setf (cffi:mem-aref p :uint8 0) 1) p))
  (let* ((before (getf (ethereum-lisp.telemetry:process-memory-status)
                       :resident-anonymous))
         (pins (ethereum-lisp.test::native-memory-test-fragment 64 ~D))
         (after (getf (ethereum-lisp.telemetry:process-memory-status)
                      :resident-anonymous)))
    (declare (ignorable pins))
    (with-open-file (out ~S :direction :output :if-exists :supersede)
      (prin1 (- after before) out))))"
                   (if pin-threshold-p "t" "nil")
                   (* 4 1024 1024) (* 1024 1024) result-path)))
    (unwind-protect
         (multiple-value-bind (output error-output status)
             (uiop:run-program
              (list "sbcl" "--non-interactive" "--no-userinit"
                    "--eval" "(require :asdf)"
                    "--eval" "(asdf:load-asd #P\"/workspace/ethereum-lisp.asd\")"
                    "--eval" "(asdf:load-system :ethereum-lisp/test)"
                    "--eval" form)
              :output :string :error-output :string :ignore-error-status t)
           (unless (and (zerop status) (probe-file result-path))
             (error "native memory child failed (~A): ~A ~A"
                    status output error-output))
           (with-open-file (in result-path) (read in)))
      (when (probe-file result-path) (delete-file result-path)))))

(deftest native-malloc-pinned-mmap-threshold-returns-freed-megabyte-blocks
  (:layer :e2e :module :native-memory :launches-processes t
   :estimated-seconds 60)
  ;; The fix for the Hoodi arena growth.  With glibc's dynamic threshold, once
  ;; a large block has been freed, 1-MiB blocks (RocksDB's memtable arena
  ;; blocks) come from the arenas and stay resident when freed; with the
  ;; threshold pinned they are mmapped and go back to the kernel on free.
  (unless (ethereum-lisp.telemetry:native-malloc-available-p)
    (skip-test "glibc mallopt/malloc_info are unavailable"))
  (let ((total (* 64 1024 1024))
        (dynamic (native-memory-test-child-retained-bytes nil))
        (pinned (native-memory-test-child-retained-bytes t)))
    ;; RED control: the dynamic threshold keeps the freed blocks resident.
    (is (>= dynamic (* 3/4 total)))
    ;; GREEN: pinned, almost nothing stays.
    (is (<= pinned (* 1/4 total)))))
