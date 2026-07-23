(in-package #:ethereum-lisp.database)

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

;;;; Log-structured durable file backend.
;;;;
;;;; The database file is an append-only write log: an 8-byte magic header
;;;; followed by CRC-framed records, each holding one atomic write set. Every
;;;; write appends a single record and fsyncs it before the in-memory table
;;;; changes, so a crash never exposes a partial batch.
;;;;
;;;; Opening never mutates the file. Replay classifies an invalid record by
;;;; whether any valid record follows it: none can (appends are sequential),
;;;; so a followed invalid record is corruption of acknowledged data and
;;;; fail-stops, while an unfollowed one is the torn tail of an interrupted
;;;; append — replay drops it and the FIRST DURABLE WRITE truncates it. That
;;;; first write likewise rewrites files still in the v1 whole-file
;;;; s-expression format before appending. Residual risks, both erring in
;;;; the conservative direction: a stored value crafted to contain a valid
;;;; frame image inside a torn tail turns recovery into a fail-stop, and a
;;;; torn append directly after an unverifiable final record drops both.
;;;;
;;;; A handle that fails partway through an append no longer trusts the
;;;; on-disk tail and poisons itself; writes also fail-stop if the file size
;;;; changed underneath the handle. When the log grows past a bloat threshold
;;;; after a write, the live entries are compacted into a fresh log through a
;;;; temp-file rename.

(defparameter +kv-log-magic+ (ascii-to-bytes "ELKVLOG2"))

(defconstant +kv-log-frame-header-size+ 8)
(defconstant +kv-log-record-write-set+ 1)
(defconstant +kv-log-op-put+ 1)
(defconstant +kv-log-op-delete+ 2)
(defconstant +kv-log-max-field-size+ (ash 1 32))
(defconstant +kv-log-compaction-ops-per-frame+ 1000)

(define-condition kv-log-corruption-error (error)
  ((path :initarg :path :reader kv-log-corruption-error-path)
   (detail :initarg :detail :reader kv-log-corruption-error-detail))
  (:report
   (lambda (condition stream)
     (format stream "Key-value log ~A is corrupt: ~A"
             (kv-log-corruption-error-path condition)
             (kv-log-corruption-error-detail condition)))))

(defun kv-log-corruption (path detail &rest arguments)
  (error 'kv-log-corruption-error
         :path path
         :detail (apply #'format nil detail arguments)))

;;; Frame encoding.
;;;
;;; frame   := crc:u32be payload-size:u32be payload
;;; payload := record-type:u8 op*
;;; op      := 1:u8 key-size:u32be key value-size:u32be value   ; put
;;;          | 2:u8 key-size:u32be key                          ; delete
;;;
;;; The CRC covers the size field AND the payload, so a corrupted length
;;; cannot masquerade as a frame boundary; in particular an all-zero region
;;; (the canonical torn-write artifact on a zero-filling filesystem) always
;;; fails the CRC, because the CRC of the four zero size bytes is non-zero.
;;; Operations use the write-batch list shape: (:put key value) or
;;; (:delete key), with the byte vectors already copied.

(defun kv-log-store-u32 (buffer offset value)
  (setf (aref buffer offset) (ldb (byte 8 24) value)
        (aref buffer (+ offset 1)) (ldb (byte 8 16) value)
        (aref buffer (+ offset 2)) (ldb (byte 8 8) value)
        (aref buffer (+ offset 3)) (ldb (byte 8 0) value))
  (+ offset 4))

(defun kv-log-load-u32 (buffer offset)
  (logior (ash (aref buffer offset) 24)
          (ash (aref buffer (+ offset 1)) 16)
          (ash (aref buffer (+ offset 2)) 8)
          (aref buffer (+ offset 3))))

(defun kv-log-checked-field-size (bytes)
  (let ((size (length bytes)))
    (unless (< size +kv-log-max-field-size+)
      (error "Key-value log field is too large: ~D bytes" size))
    size))

(defun kv-log-op-encoded-size (operation)
  (ecase (first operation)
    (:put
     (+ 1 4 (kv-log-checked-field-size (second operation))
        4 (kv-log-checked-field-size (third operation))))
    (:delete
     (+ 1 4 (kv-log-checked-field-size (second operation))))))

(defun kv-log-store-field (buffer offset bytes)
  (let ((size (length bytes)))
    (setf offset (kv-log-store-u32 buffer offset size))
    (replace buffer bytes :start1 offset)
    (+ offset size)))

(defun kv-log-encode-frame (operations)
  "Encode OPERATIONS as one CRC-framed record. Validates every operation
before any byte is written, so an invalid write set fails without side
effects."
  (let* ((payload-size
           (1+ (reduce #'+ operations :key #'kv-log-op-encoded-size)))
         (frame
           (progn
             (unless (< payload-size +kv-log-max-field-size+)
               (error "Key-value log write set is too large: ~D bytes"
                      payload-size))
             (make-byte-vector (+ +kv-log-frame-header-size+ payload-size))))
         (offset +kv-log-frame-header-size+))
    (setf (aref frame offset) +kv-log-record-write-set+)
    (incf offset)
    (dolist (operation operations)
      (ecase (first operation)
        (:put
         (setf (aref frame offset) +kv-log-op-put+)
         (setf offset (kv-log-store-field frame (1+ offset)
                                          (second operation)))
         (setf offset (kv-log-store-field frame offset (third operation))))
        (:delete
         (setf (aref frame offset) +kv-log-op-delete+)
         (setf offset (kv-log-store-field frame (1+ offset)
                                          (second operation))))))
    (kv-log-store-u32 frame 4 payload-size)
    (kv-log-store-u32 frame 0 (crc32 frame :start 4))
    frame))

(defun kv-log-parse-frame-payload (buffer start end path)
  "Decode the operations of one record payload in BUFFER between START and
END. The CRC already matched, so any structural fault is corruption, not a
torn write."
  (when (>= start end)
    (kv-log-corruption path "record payload is empty"))
  (unless (= (aref buffer start) +kv-log-record-write-set+)
    (kv-log-corruption path "unknown record type ~D" (aref buffer start)))
  (let ((offset (1+ start))
        (operations '()))
    (flet ((read-field ()
             (unless (<= (+ offset 4) end)
               (kv-log-corruption path "record field size is truncated"))
             (let ((size (kv-log-load-u32 buffer offset)))
               (incf offset 4)
               (unless (<= (+ offset size) end)
                 (kv-log-corruption path "record field overruns the record"))
               (prog1 (subseq buffer offset (+ offset size))
                 (incf offset size)))))
      (loop while (< offset end)
            do (let ((code (aref buffer offset)))
                 (incf offset)
                 (cond
                   ((= code +kv-log-op-put+)
                    (let* ((key (read-field))
                           (value (read-field)))
                      (push (list :put key value) operations)))
                   ((= code +kv-log-op-delete+)
                    (push (list :delete (read-field)) operations))
                   (t
                    (kv-log-corruption path "unknown operation code ~D"
                                       code))))))
    (nreverse operations)))

;;; Durable writes.

(defun kv-log-sync-stream (stream)
  "Force STREAM's written bytes to durable storage."
  #+sbcl (sb-posix:fsync (sb-sys:fd-stream-fd stream))
  #-sbcl (declare (ignore stream))
  nil)

(defun kv-log-sync-directory (path)
  "Make the directory entry for PATH durable after a rename. Best effort:
some platforms refuse directory fsync."
  #+sbcl
  (let ((fd (handler-case
                (sb-posix:open
                 (sb-ext:native-namestring
                  (make-pathname :name nil :type nil :version nil
                                 :defaults (pathname path)))
                 sb-posix:o-rdonly)
              (error () nil))))
    (when fd
      (unwind-protect
           (handler-case (sb-posix:fsync fd)
             (error () nil))
        (sb-posix:close fd))))
  #-sbcl (declare (ignore path))
  nil)

(defun kv-log-truncate-file (path size)
  #+sbcl (sb-posix:truncate (sb-ext:native-namestring (pathname path)) size)
  #-sbcl (error "Truncating ~A to ~D bytes is not supported" path size)
  nil)

(defun kv-log-append-frame (database frame)
  "Append FRAME to the log and fsync it. The in-memory table must only be
updated after this returns."
  (let ((path (file-key-value-database-path database)))
    (ensure-directories-exist path)
    (with-open-file (stream path
                            :direction :output
                            :element-type '(unsigned-byte 8)
                            :if-exists :append
                            :if-does-not-exist :create)
      (let ((position (file-position stream))
            (tracked (file-key-value-database-log-bytes database)))
        (cond
          ((and (zerop position) (zerop tracked))
           (write-sequence +kv-log-magic+ stream))
          ((/= position tracked)
           ;; Appending after unknown bytes would bury them mid-log, turning
           ;; them into unrecoverable corruption on the next open.
           (kv-log-corruption
            path
            "file size changed underneath the open database (~D, expected ~D)"
            position tracked))))
      (write-sequence frame stream)
      (finish-output stream)
      (kv-log-sync-stream stream)
      (setf (file-key-value-database-log-bytes database)
            (file-position stream))))
  database)

;;; In-memory application with live-size accounting.

(defun kv-log-live-entry-size (key value)
  (+ 1 4 (length key) 4 (length value)))

(defun kv-log-apply-operations (database operations)
  (dolist (operation operations database)
    (let* ((key (second operation))
           (existing (gethash (kv-key-string key)
                              (memory-key-value-database-entries database))))
      (when existing
        (decf (file-key-value-database-live-bytes database)
              (kv-log-live-entry-size (kv-memory-entry-key existing)
                                      (kv-memory-entry-value existing))))
      (ecase (first operation)
        (:put
         (incf (file-key-value-database-live-bytes database)
               (kv-log-live-entry-size key (third operation)))
         (kv-put-memory-entry database key (third operation)))
        (:delete
         (kv-delete-memory-entry database key))))))

(defun kv-log-prepare-for-append (database)
  "Perform the file mutations deferred from open: truncate a torn tail and
rewrite a v1-format file as a log. Both retry cleanly on failure."
  (let ((truncation (file-key-value-database-pending-truncation database)))
    (when (and (or truncation
                   (file-key-value-database-needs-migration-p database))
               (not (probe-file (file-key-value-database-path database))))
      (kv-log-corruption
       (file-key-value-database-path database)
       "the file vanished underneath the open database"))
    (when truncation
      (kv-log-truncate-file (file-key-value-database-path database)
                            truncation)
      (setf (file-key-value-database-log-bytes database) truncation
            (file-key-value-database-pending-truncation database) nil)))
  (when (file-key-value-database-needs-migration-p database)
    (kv-log-rewrite-file database)
    (setf (file-key-value-database-needs-migration-p database) nil))
  database)

(defun kv-log-write-durable-set (database operations)
  "Make OPERATIONS durable as one atomic record, then apply them to the
in-memory table and compact the log if it has bloated."
  (when operations
    (when (file-key-value-database-write-failed-p database)
      (kv-log-corruption
       (file-key-value-database-path database)
       "an earlier write failed and the on-disk tail is untrusted; reopen"))
    (let ((frame (kv-log-encode-frame operations))
          (appended-p nil))
      (kv-log-prepare-for-append database)
      (unwind-protect
           (progn
             (kv-log-append-frame database frame)
             (setf appended-p t))
        (unless appended-p
          (setf (file-key-value-database-write-failed-p database) t)))
      (kv-log-apply-operations database operations)
      (kv-log-maybe-compact database)))
  database)

;;; Compaction.

(defun kv-file-database-temp-path (path)
  (let* ((pathname (pathname path))
         (name (or (pathname-name pathname) "kv"))
         (type (pathname-type pathname)))
    (make-pathname
     :name (format nil ".~A.~A" name (symbol-name (gensym "TMP")))
     :type type
     :defaults pathname)))

(defun kv-log-write-compact-file (database target-path)
  "Write every live entry as a fresh log at TARGET-PATH and fsync it.
Returns the file size in bytes."
  (with-open-file (stream target-path
                          :direction :output
                          :element-type '(unsigned-byte 8)
                          :if-exists :error
                          :if-does-not-exist :create)
    (write-sequence +kv-log-magic+ stream)
    (let ((pending '())
          (count 0))
      (flet ((flush-pending ()
               (when pending
                 (write-sequence (kv-log-encode-frame (nreverse pending))
                                 stream)
                 (setf pending '()
                       count 0))))
        (dolist (entry (kv-database-sorted-entries database))
          (push (list :put
                      (kv-memory-entry-key entry)
                      (kv-memory-entry-value entry))
                pending)
          (when (>= (incf count) +kv-log-compaction-ops-per-frame+)
            (flush-pending)))
        (flush-pending)))
    (finish-output stream)
    (kv-log-sync-stream stream)
    (file-position stream)))

(defun kv-log-rewrite-file (database)
  "Atomically replace the log with a compacted snapshot of the live entries."
  (let* ((path (file-key-value-database-path database))
         (temp-path (kv-file-database-temp-path path))
         (renamed-p nil))
    (ensure-directories-exist path)
    (unwind-protect
         (let ((size (kv-log-write-compact-file database temp-path)))
           (uiop:rename-file-overwriting-target temp-path path)
           (setf renamed-p t)
           (kv-log-sync-directory path)
           (setf (file-key-value-database-log-bytes database) size))
      (unless renamed-p
        (when (probe-file temp-path)
          (ignore-errors (delete-file temp-path))))))
  database)

(defun kv-log-maybe-compact (database)
  (let ((log-bytes (file-key-value-database-log-bytes database))
        (live-bytes (+ (length +kv-log-magic+)
                       (file-key-value-database-live-bytes database))))
    (when (and (>= log-bytes
                   (file-key-value-database-compaction-min-bytes database))
               (> log-bytes
                  (* (file-key-value-database-compaction-ratio database)
                     live-bytes)))
      (kv-log-rewrite-file database)))
  database)

;;; Loading: log replay, torn-tail recovery, and v1 migration.

(defun kv-log-read-file-bytes (path)
  (with-open-file (stream path
                          :direction :input
                          :element-type '(unsigned-byte 8))
    (let ((buffer (make-byte-vector (file-length stream))))
      (read-sequence buffer stream)
      buffer)))

(defun kv-log-magic-file-p (buffer)
  (let ((magic-size (length +kv-log-magic+)))
    (and (>= (length buffer) magic-size)
         (loop for index below magic-size
               always (= (aref buffer index)
                         (aref +kv-log-magic+ index))))))

(defun kv-log-frame-extent (buffer offset size)
  "Return the end offset of the frame starting at OFFSET when a valid one is
there: the header fits, the declared payload lies within SIZE, and the CRC
over the size field and payload matches. Otherwise return NIL."
  (when (<= (+ offset +kv-log-frame-header-size+) size)
    (let* ((payload-size (kv-log-load-u32 buffer (+ offset 4)))
           (payload-end
             (+ offset +kv-log-frame-header-size+ payload-size)))
      (when (and (<= payload-end size)
                 (= (kv-log-load-u32 buffer offset)
                    (crc32 buffer :start (+ offset 4) :end payload-end)))
        payload-end))))

(defun kv-log-valid-frame-follows-p (buffer start size)
  "True when a valid frame starts at ANY offset in [START, SIZE). Sequential
appends mean nothing valid can follow a torn tail, so a hit proves the
invalid bytes before it are corruption of acknowledged data, not a tear."
  (loop for offset from start below size
        thereis (and (kv-log-frame-extent buffer offset size) t)))

(defun kv-log-replay (database buffer path)
  "Replay the framed records in BUFFER. An invalid frame followed by any
valid frame is corruption and fail-stops; an invalid frame with nothing
valid after it is the torn tail of a crashed append — its bytes are dropped
and recorded for truncation by the first durable write. Opening mutates
nothing."
  (let ((size (length buffer))
        (offset (length +kv-log-magic+)))
    (loop
      (when (= offset size)
        (return))
      (let ((payload-end (kv-log-frame-extent buffer offset size)))
        (cond
          (payload-end
           (kv-log-apply-operations
            database
            (kv-log-parse-frame-payload
             buffer (+ offset +kv-log-frame-header-size+) payload-end path))
           (setf offset payload-end))
          ((kv-log-valid-frame-follows-p buffer (1+ offset) size)
           (kv-log-corruption
            path "invalid record at offset ~D with valid records after it"
            offset))
          (t
           (warn "Key-value log ~A has a torn tail; dropping ~D trailing ~
                  byte~:P until the next write truncates them"
                 path (- size offset))
           (setf (file-key-value-database-pending-truncation database)
                 offset)
           (return)))))
    (setf (file-key-value-database-log-bytes database)
          (or (file-key-value-database-pending-truncation database) size)))
  database)

(defun kv-file-records (object)
  (unless (and (consp object)
               (eq (first object) :ethereum-lisp-kv-v1)
               (listp (second object))
               (null (cddr object)))
    (error "Invalid key-value database file"))
  (second object))

(defun kv-log-load-v1-database (database path)
  "Load a v1 whole-file s-expression database into the table and mark the
handle for migration: the first durable write rewrites the file as a log
through a temp-file rename, so a rejected or read-only artifact stays
byte-identical and a crash mid-migration leaves the v1 file intact."
  (with-open-file (stream path :direction :input)
    (let ((*read-eval* nil))
      (dolist (record (kv-file-records (read stream nil nil)))
        (unless (and (consp record)
                     (stringp (first record))
                     (stringp (second record))
                     (null (cddr record)))
          (error "Invalid key-value database record"))
        (kv-log-apply-operations
         database
         (list (list :put
                     (hex-to-bytes (first record))
                     (hex-to-bytes (second record))))))))
  (setf (file-key-value-database-needs-migration-p database) t)
  database)

(defun kv-log-v1-file-p (buffer)
  "True when BUFFER starts a v1 s-expression database: its first byte past
any whitespace opens a list."
  (loop for byte across buffer
        do (case byte
             ((9 10 13 32))
             (40 (return t))
             (t (return nil)))))

(defun kv-log-torn-first-append-p (buffer)
  "True when BUFFER can only be the torn first append of a new log: a strict
prefix of the magic header, or all zeros (no valid file starts with either)."
  (or (and (< (length buffer) (length +kv-log-magic+))
           (loop for index below (length buffer)
                 always (= (aref buffer index)
                           (aref +kv-log-magic+ index))))
      (every #'zerop buffer)))

(defun kv-load-file-database (database)
  (let ((path (file-key-value-database-path database)))
    (when (probe-file path)
      (let ((buffer (kv-log-read-file-bytes path)))
        (cond
          ((zerop (length buffer)))
          ((kv-log-magic-file-p buffer)
           (kv-log-replay database buffer path))
          ((kv-log-v1-file-p buffer)
           (kv-log-load-v1-database database path))
          ((kv-log-torn-first-append-p buffer)
           (warn "Key-value log ~A holds only a torn first append; treating ~
                  it as empty"
                 path)
           (setf (file-key-value-database-pending-truncation database) 0))
          (t
           (kv-log-corruption path "unrecognized file header"))))))
  database)

(defun make-file-key-value-database
    (path &key (compaction-min-bytes +kv-log-default-compaction-min-bytes+)
            (compaction-ratio +kv-log-default-compaction-ratio+))
  (let ((database (make-instance 'file-key-value-database
                                 :path path
                                 :compaction-min-bytes compaction-min-bytes
                                 :compaction-ratio compaction-ratio)))
    (kv-load-file-database database)
    database))

(defmethod kv-put ((database file-key-value-database) key value)
  (kv-log-write-durable-set
   database
   (list (list :put (kv-copy-bytes key) (kv-copy-bytes value)))))

(defmethod kv-delete ((database file-key-value-database) key)
  (when (gethash (kv-key-string key)
                 (memory-key-value-database-entries database))
    (kv-log-write-durable-set
     database
     (list (list :delete (kv-copy-bytes key))))
    t))
