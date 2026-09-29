(in-package #:ethereum-lisp.cli)

;;;; When to execute again a block whose execution failed internally.
;;;;
;;;; A BLOCK-EXECUTION-INTERNAL-ERROR is a defect in this node, never a verdict
;;;; on the block (docs/evidence/sec5-evm-edge-audit.txt): the sync coordinator
;;;; contains it and a later pass executes the block again. Without a bound,
;;;; "later" is the next pass -- the coordinator wakes every second and on
;;;; every validated peer announcement -- so a deterministic defect turns into
;;;; a loop that re-downloads and re-executes the same block and writes an
;;;; :error line each time (docs/evidence/sec5-robustness-followups.txt).
;;;;
;;;; This table keeps one entry per failing block hash. Each failure doubles
;;;; the wait before the next attempt, from +DEVNET-EXECUTION-RETRY-BASE-
;;;; SECONDS+ up to +DEVNET-EXECUTION-RETRY-MAX-SECONDS+. The wait applies only
;;;; while the sync target the failure was seen under is still the target: a
;;;; new CL-authorized target retries at once, because the work it needs may
;;;; not include the failing block at all. It does not restart the doubling,
;;;; though -- on a live network the target moves every slot, and a block that
;;;; fails under every one of them is still the same defect. An entry leaves
;;;; the table when its block has been executed (by this retry, or by Engine
;;;; newPayload), which is the only reset of the count.
;;;;
;;;; Like the dial schedule, nothing here locks or reads a clock: NOW is an
;;;; argument, in Unix seconds, and the table belongs to the coordinator
;;;; thread, the only caller.

(defconstant +devnet-execution-retry-base-seconds+ 2
  "The wait after a block's first internal execution failure. Our policy: one
coordinator poll longer than the one-second fallback wake, so the first retry
is never the very next pass.")

(defconstant +devnet-execution-retry-max-seconds+ 300
  "The longest wait between two attempts at the same block. Our policy.")

(defconstant +devnet-execution-retry-max-entries+ 64
  "How many failing blocks the table remembers. The coordinator stops at the
first failing block of a pass, so more than a handful means the targets moved
across many of them; the entry failed longest ago is the one dropped.")

(defstruct (devnet-execution-retry
            (:constructor make-devnet-execution-retry (hash number)))
  "What the coordinator remembers about one block that failed internally."
  hash
  number
  (failures 0)
  first-at
  last-at
  next-at
  target
  ;; Passes that ended before the sync work because this entry was waiting.
  (deferred-passes 0))

(defun devnet-execution-retry-delay-seconds (failures)
  "The wait after the FAILURES-th consecutive failure of one block."
  (min +devnet-execution-retry-max-seconds+
       (* +devnet-execution-retry-base-seconds+
          (expt 2 (max 0 (1- failures))))))

(defun devnet-execution-retry-key (hash)
  (hash32-to-hex hash))

(defun devnet-execution-retry-note-failure (table hash number target now)
  "Record that block HASH (at NUMBER) failed internally at NOW while the sync
worked toward TARGET (a hash, or NIL), and return its entry."
  (let* ((key (devnet-execution-retry-key hash))
         (entry (gethash key table)))
    (unless entry
      (when (>= (hash-table-count table) +devnet-execution-retry-max-entries+)
        (let ((oldest nil))
          (maphash (lambda (other-key other)
                     (when (or (null oldest)
                               (< (devnet-execution-retry-last-at other)
                                  (devnet-execution-retry-last-at
                                   (cdr oldest))))
                       (setf oldest (cons other-key other))))
                   table)
          (remhash (car oldest) table)))
      (setf entry (make-devnet-execution-retry hash number)
            (gethash key table) entry
            (devnet-execution-retry-first-at entry) now))
    (let ((failures (incf (devnet-execution-retry-failures entry))))
      (setf (devnet-execution-retry-last-at entry) now
            (devnet-execution-retry-next-at entry)
            (+ now (devnet-execution-retry-delay-seconds failures))
            (devnet-execution-retry-target entry) target))
    entry))

(defun devnet-execution-retry-same-target-p (entry target)
  (let ((recorded (devnet-execution-retry-target entry)))
    (if (and recorded target)
        (hash32= recorded target)
        (and (null recorded) (null target)))))

(defun devnet-execution-retry-waiting (table target now)
  "The entry whose wait keeps the coordinator from syncing toward TARGET at
NOW, or NIL. An entry recorded under another target never waits."
  (let ((waiting nil))
    (maphash (lambda (key entry)
               (declare (ignore key))
               (when (and (null waiting)
                          (devnet-execution-retry-same-target-p entry target)
                          (> (devnet-execution-retry-next-at entry) now))
                 (setf waiting entry)))
             table)
    waiting))

(defun devnet-execution-retry-remove-executed (table executed-p)
  "Remove and return, oldest first, every entry whose block EXECUTED-P (a
function of the block hash) now says has been executed."
  (let ((recovered '()))
    (maphash (lambda (key entry)
               (when (funcall executed-p (devnet-execution-retry-hash entry))
                 (push (cons key entry) recovered)))
             table)
    (dolist (item recovered)
      (remhash (car item) table))
    (sort (mapcar #'cdr recovered) #'<
          :key #'devnet-execution-retry-first-at)))
