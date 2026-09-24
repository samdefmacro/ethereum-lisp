(in-package #:ethereum-lisp.telemetry)

;;;; Native (C heap) memory: what glibc malloc holds, and giving it back.
;;;;
;;;; The node's resident set has two owners.  The Lisp heap is SBCL's dynamic
;;;; space; SBCL 2.2.9 returns its free pages after every collection that
;;;; reaches generation 2 or older, so its resident size follows the live heap.
;;;; Everything else -- RocksDB's memtables, block cache, compaction and write
;;;; batch buffers, the KZG and BLS libraries -- lives in glibc malloc arenas.
;;;; glibc keeps freed arena memory resident: a free chunk below a live one
;;;; cannot be trimmed from the top of its heap, and once a large mmapped block
;;;; has been freed the dynamic mmap threshold rises (up to 32 MiB on 64-bit),
;;;; so later buffers of that size come from, and stay in, the arenas.  Every
;;;; thread that contends gets its own arena (up to eight per core), so a node
;;;; with ~100 threads multiplies that retention.  On the b5161312 Hoodi run
;;;; 146 arena heaps held 7.9 GiB resident while RocksDB's own accounting was
;;;; under 1 GiB (docs/evidence/sec5-resident-memory.txt).
;;;;
;;;; Everything here is glibc-specific and optional: on another libc the
;;;; symbols are absent and each function reports NIL instead of failing.

(defconstant +native-malloc-m-mmap-threshold+ -3
  "glibc mallopt parameter M_MMAP_THRESHOLD (malloc.h).")

(defconstant +native-malloc-default-mmap-threshold-bytes+ (* 128 1024)
  "glibc's own initial M_MMAP_THRESHOLD (DEFAULT_MMAP_THRESHOLD_MIN), pinned.

Pinning glibc's starting value changes one thing: the threshold no longer
climbs after a large free.  In a RocksDB churn of 32 writer threads (about
1.5 GB ingested, ~110 MiB live), the C side of the process held 407 MiB
resident with the dynamic threshold and 104 MiB with it pinned here (1 MiB
gave 109 MiB); see docs/evidence/sec5-resident-memory.txt.")

(defun native-malloc-available-p ()
  "True when the running libc exports the glibc malloc control interface."
  (and (cffi:foreign-symbol-pointer "malloc_trim")
       (cffi:foreign-symbol-pointer "malloc_info")
       (cffi:foreign-symbol-pointer "mallopt")
       (cffi:foreign-symbol-pointer "open_memstream")
       t))

(defun native-malloc-configure
    (&key (mmap-threshold-bytes +native-malloc-default-mmap-threshold-bytes+))
  "Pin glibc's mmap threshold process-wide.  Return the threshold now in force,
or NIL when the allocator is not glibc or refused the value.

A request of MMAP-THRESHOLD-BYTES or more is served by its own mmap and goes
back to the kernel on free.  Setting the threshold also switches off glibc's
dynamic threshold, which otherwise climbs (up to 32 MiB) after the first large
free and from then on places every memtable block, write-batch buffer and
compaction buffer below that size in the arenas, where freed memory stays
resident.  Affects allocations made after the call; call it before the
storage engine opens.  One-way for the life of the process: glibc has no call
that turns the dynamic threshold back on."
  (check-type mmap-threshold-bytes (integer 1 #.(* 32 1024 1024)))
  (when (and (native-malloc-available-p)
             (= 1 (cffi:foreign-funcall "mallopt"
                                        :int +native-malloc-m-mmap-threshold+
                                        :int mmap-threshold-bytes
                                        :int)))
    mmap-threshold-bytes))

(defun native-malloc-release ()
  "Return free malloc pages to the kernel (glibc malloc_trim(0)).

Walks every arena and madvises the whole free pages inside it, not only the
top of each heap.  Each arena is locked while it is trimmed, so a thread
allocating from that arena waits for it; measured at 15-17 ms for ~300 MiB of
free chunks over 46 arenas.  Returns the elapsed milliseconds, or NIL when the
allocator is not glibc."
  (when (native-malloc-available-p)
    (let ((start (get-internal-real-time)))
      (cffi:foreign-funcall "malloc_trim" :size 0 :int)
      (floor (* 1000 (- (get-internal-real-time) start))
             internal-time-units-per-second))))

(defstruct (native-malloc-report
            (:constructor make-native-malloc-report
                (&key heaps system-bytes free-bytes mmap-bytes)))
  "glibc's own totals over every arena, from malloc_info.

SYSTEM-BYTES is what the arenas have taken from the kernel, FREE-BYTES the part
of it sitting in free chunks (fast bins and the rest), MMAP-BYTES the live
blocks served by mmap outside the arenas, HEAPS the number of arena heaps
(the main arena counts as one).  After a trim FREE-BYTES is unchanged -- the
chunks are still free, their pages are just no longer resident -- so compare
it with the resident set, not with itself."
  (heaps 0 :type (integer 0))
  (system-bytes 0 :type (integer 0))
  (free-bytes 0 :type (integer 0))
  (mmap-bytes 0 :type (integer 0)))

(defun native-malloc-report-in-use-bytes (report)
  "Bytes of arena memory handed out and not yet freed, plus mmapped blocks."
  (+ (max 0 (- (native-malloc-report-system-bytes report)
               (native-malloc-report-free-bytes report)))
     (native-malloc-report-mmap-bytes report)))

(defun %native-malloc-info-size (xml tag type start)
  "The size attribute of the first <TAG type=\"TYPE\" .../> at or after START."
  (let* ((needle (concatenate 'string "<" tag " type=\"" type "\""))
         (at (search needle xml :start2 start)))
    (unless at
      (error "malloc_info output has no ~A of type ~A" tag type))
    (let* ((close (or (search "/>" xml :start2 at)
                      (error "malloc_info ~A element is not closed" tag)))
           (attribute (or (search "size=\"" xml :start2 at :end2 close)
                          (error "malloc_info ~A element has no size" tag)))
           (value-start (+ attribute 6))
           (value-end (position #\" xml :start value-start :end close)))
      (parse-integer xml :start value-start :end value-end))))

(defun parse-native-malloc-info (xml)
  "Read the process-wide totals out of glibc malloc_info XML.

The per-arena sections (<heap nr=...>) repeat the same element names; the
process totals are the ones after the last </heap>."
  (let* ((last-heap-end (search "</heap>" xml :from-end t))
         (totals-start (if last-heap-end (+ last-heap-end 7) 0)))
    (make-native-malloc-report
     :heaps (loop with start = 0
                  for at = (search "<heap nr=" xml :start2 start)
                  while at
                  count t
                  do (setf start (1+ at)))
     :system-bytes (%native-malloc-info-size xml "system" "current"
                                             totals-start)
     :free-bytes (+ (%native-malloc-info-size xml "total" "fast" totals-start)
                    (%native-malloc-info-size xml "total" "rest" totals-start))
     :mmap-bytes (%native-malloc-info-size xml "total" "mmap" totals-start))))

(defun native-malloc-info-xml ()
  "glibc malloc_info(0, ...) output as a string, or NIL off glibc."
  (when (native-malloc-available-p)
    (cffi:with-foreign-objects ((buffer :pointer) (size :size))
      (setf (cffi:mem-ref buffer :pointer) (cffi:null-pointer)
            (cffi:mem-ref size :size) 0)
      (let ((stream (cffi:foreign-funcall "open_memstream"
                                          :pointer buffer :pointer size
                                          :pointer)))
        (when (cffi:null-pointer-p stream)
          (error "open_memstream failed"))
        (unwind-protect
             (cffi:foreign-funcall "malloc_info" :int 0 :pointer stream :int)
          ;; fclose publishes BUFFER and SIZE; the buffer is ours to free.
          (cffi:foreign-funcall "fclose" :pointer stream :int))
        (let ((pointer (cffi:mem-ref buffer :pointer)))
          (unwind-protect
               (cffi:foreign-string-to-lisp pointer
                                            :count (cffi:mem-ref size :size))
            (cffi:foreign-funcall "free" :pointer pointer :void)))))))

(defun native-malloc-report ()
  "The current NATIVE-MALLOC-REPORT, or NIL off glibc.

malloc_info locks each arena in turn while it counts the free chunks; measured
at 1-2 ms over 46 arenas.  Take it at a sampling cadence, not per request."
  (let ((xml (native-malloc-info-xml)))
    (and xml (parse-native-malloc-info xml))))

(defun process-memory-status ()
  "Resident memory from /proc/self/status as a plist of byte counts:
:RESIDENT (VmRSS), :RESIDENT-ANONYMOUS (RssAnon) and :RESIDENT-PEAK (VmHWM).
NIL where /proc is not available."
  (with-open-file (in "/proc/self/status" :if-does-not-exist nil)
    (when in
      (let ((fields '(("VmRSS:" . :resident)
                      ("RssAnon:" . :resident-anonymous)
                      ("VmHWM:" . :resident-peak)))
            (result '()))
        (loop for line = (read-line in nil nil)
              while line
              do (loop for (prefix . key) in fields
                       when (and (> (length line) (length prefix))
                                 (string= prefix line :end2 (length prefix)))
                         do (setf (getf result key)
                                  (* 1024 (parse-integer
                                           line :start (length prefix)
                                                :junk-allowed t)))))
        result))))

(defun lisp-dynamic-space-resident-bytes ()
  "Anonymous resident bytes of SBCL's dynamic space, summed over the
Anonymous: lines of /proc/self/smaps.

Anonymous, not Rss: the saved core maps the heap it was saved with from the
executable file, and those pages are file-backed until written.  So the
anonymous resident set less this is what the C side of the process holds.
Reads the whole smaps file (about 1.5 MB on a live node), so it belongs to a
periodic sample.  NIL off SBCL or Linux."
  #-sbcl nil
  #+sbcl
  (let* ((low sb-vm:dynamic-space-start)
         (high (+ low (sb-ext:dynamic-space-size)))
         (inside-p nil)
         (total 0))
    (with-open-file (in "/proc/self/smaps" :if-does-not-exist nil)
      (unless in
        (return-from lisp-dynamic-space-resident-bytes nil))
      (loop for line = (read-line in nil nil)
            while line
            do (let ((dash (position #\- line))
                     (space (position #\Space line)))
                 (cond
                   ((and dash space (< 0 dash space)
                         (every (lambda (character)
                                  (or (digit-char-p character 16)
                                      (char= character #\-)))
                                (subseq line 0 space)))
                    (let ((start (parse-integer line :end dash :radix 16))
                          (end (parse-integer line :start (1+ dash)
                                                   :end space :radix 16)))
                      (setf inside-p (and (< start high) (> end low)))))
                   ((and inside-p (> (length line) 10)
                         (string= "Anonymous:" line :end2 10))
                    (incf total (* 1024 (parse-integer
                                         line :start 10
                                              :junk-allowed t))))))))
    total))
