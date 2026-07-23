(in-package #:ethereum-lisp.test)

(deftest memory-key-value-database-put-get-delete
  (let ((database (make-memory-key-value-database))
        (key #(1 2 3))
        (value (copy-seq #(4 5 6))))
    (multiple-value-bind (missing present-p)
        (kv-get database key :missing)
      (is (eq :missing missing))
      (is (not present-p)))
    (kv-put database key value)
    (setf (aref value 0) 9)
    (multiple-value-bind (stored present-p)
        (kv-get database key)
      (is present-p)
      (is (bytes= #(4 5 6) stored))
      (setf (aref stored 0) 9))
    (multiple-value-bind (stored present-p)
        (kv-get database key)
      (is present-p)
      (is (bytes= #(4 5 6) stored)))
    (is (kv-delete database key))
    (multiple-value-bind (missing present-p)
        (kv-get database key :missing)
      (is (eq :missing missing))
      (is (not present-p)))
    (is (not (kv-delete database key)))))

(deftest memory-key-value-database-applies-write-batches-in-order
  (let ((database (make-memory-key-value-database))
        (batch (make-kv-write-batch)))
    (kv-put database #(1) #(1))
    (kv-batch-put batch #(1) #(2))
    (kv-batch-put batch #(2) #(3))
    (kv-batch-delete batch #(1))
    (kv-apply-batch database batch)
    (multiple-value-bind (value present-p)
        (kv-get database #(1))
      (declare (ignore value))
      (is (not present-p)))
    (multiple-value-bind (value present-p)
        (kv-get database #(2))
      (is present-p)
      (is (bytes= #(3) value)))))

(deftest memory-key-value-database-failed-batch-restores-snapshot
  (let ((database (make-memory-key-value-database))
        (batch (make-kv-write-batch)))
    (kv-put database #(1) #(10))
    (setf (ethereum-lisp.database::kv-write-batch-operations batch)
          (list (list :invalid)
                (list :put #(1) #(11))))
    (signals error
      (kv-apply-batch database batch))
    (multiple-value-bind (value present-p)
        (kv-get database #(1))
      (is present-p)
      (is (bytes= #(10) value)))))

(deftest memory-key-value-database-iterates-sorted-ranges
  (let ((database (make-memory-key-value-database)))
    (kv-put database #(3) #(30))
    (kv-put database #(1) #(10))
    (kv-put database #(2) #(20))
    (let ((iterator (kv-iterator database :start #(2) :end #(4))))
      (multiple-value-bind (key value present-p)
          (funcall iterator)
        (is present-p)
        (is (bytes= #(2) key))
        (is (bytes= #(20) value)))
      (multiple-value-bind (key value present-p)
          (funcall iterator)
        (is present-p)
        (is (bytes= #(3) key))
        (is (bytes= #(30) value)))
      (multiple-value-bind (key value present-p)
          (funcall iterator)
        (declare (ignore key value))
        (is (not present-p))))
    (let ((iterator (kv-iterator database :reverse-p t)))
      (multiple-value-bind (key value present-p)
          (funcall iterator)
        (declare (ignore value))
        (is present-p)
        (is (bytes= #(3) key))))))

(deftest file-key-value-database-failed-batch-restores-memory-snapshot
  (:layer :integration :module :database)
  (let ((database
          (make-instance
           'file-key-value-database
           :path #P"/dev/null/ethereum-lisp-kv.sexp"))
        (batch (make-kv-write-batch)))
    (ethereum-lisp.database::kv-put-memory-entry
     database #(1) #(10))
    (kv-batch-put batch #(1) #(11))
    (kv-batch-put batch #(2) #(20))
    (signals error
      (kv-apply-batch database batch))
    (multiple-value-bind (value present-p)
        (kv-get database #(1))
      (is present-p)
      (is (bytes= #(10) value)))
    (multiple-value-bind (value present-p)
        (kv-get database #(2))
      (declare (ignore value))
      (is (not present-p)))))

(deftest file-key-value-database-persists-chain-records
  (:layer :integration :module :database)
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-kv-~A" (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (block-key #(1 0))
         (header-key #(2 0))
         (receipt-key #(3 0)))
    (unwind-protect
         (progn
           (let ((database (make-file-key-value-database path))
                 (batch (make-kv-write-batch)))
             (kv-put database block-key #(11 12 13))
             (kv-batch-put batch header-key #(21 22))
             (kv-batch-put batch receipt-key #(31 32 33))
             (kv-apply-batch database batch))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (value present-p)
                 (kv-get database block-key)
               (is present-p)
               (is (bytes= #(11 12 13) value)))
             (multiple-value-bind (value present-p)
                 (kv-get database header-key)
               (is present-p)
               (is (bytes= #(21 22) value)))
             (multiple-value-bind (value present-p)
                 (kv-get database receipt-key)
               (is present-p)
               (is (bytes= #(31 32 33) value)))
             (let ((iterator (kv-iterator database :start #(2) :end #(4))))
               (multiple-value-bind (key value present-p)
                   (funcall iterator)
                 (is present-p)
                 (is (bytes= header-key key))
                 (is (bytes= #(21 22) value)))
               (multiple-value-bind (key value present-p)
                   (funcall iterator)
                 (is present-p)
                 (is (bytes= receipt-key key))
                 (is (bytes= #(31 32 33) value))))
             (kv-delete database header-key))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (value present-p)
                 (kv-get database header-key)
               (declare (ignore value))
               (is (not present-p)))
             (multiple-value-bind (value present-p)
                 (kv-get database block-key)
               (is present-p)
               (is (bytes= #(11 12 13) value)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest file-key-value-database-replaces-through-temp-file
  (:layer :integration :module :database)
  (let* ((name (format nil "ethereum-lisp-kv-replace-~A" (gensym)))
         (path
           (merge-pathnames
            (make-pathname :name name :type "sexp")
            #P"/private/tmp/"))
         (temp-pattern
           (merge-pathnames
            (make-pathname
             :name (format nil ".~A.*" name)
             :type "sexp")
            #P"/private/tmp/")))
    (unwind-protect
         (progn
           (let ((database (make-file-key-value-database path))
                 (batch (make-kv-write-batch)))
             (kv-put database #(1) #(1))
             (kv-batch-put batch #(2) #(2))
             (kv-batch-put batch #(3) #(3))
             (kv-apply-batch database batch)
             (kv-put database #(1) #(9)))
           (is (null (directory temp-pattern)))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (value present-p)
                 (kv-get database #(1))
               (is present-p)
               (is (bytes= #(9) value)))
             (multiple-value-bind (value present-p)
                 (kv-get database #(2))
               (is present-p)
               (is (bytes= #(2) value)))))
      (when (probe-file path)
        (delete-file path))
      (dolist (temp-path (directory temp-pattern))
        (when (probe-file temp-path)
          (delete-file temp-path))))))

(deftest chain-record-keys-namespace-chain-data
  (let ((database (make-memory-key-value-database))
        (block-hash (make-byte-vector 32 :initial-element #xaa))
        (receipt-hash (make-byte-vector 32 :initial-element #xbb)))
    (kv-put-chain-record database :block block-hash #(1 2 3))
    (kv-put-chain-record database :receipt receipt-hash #(4 5 6))
    (kv-put-chain-record database :canonical-hash 10 #(10))
    (kv-put-chain-record database :canonical-hash 2 #(2))
    (multiple-value-bind (value present-p)
        (kv-get-chain-record database :block block-hash)
      (is present-p)
      (is (bytes= #(1 2 3) value)))
    (multiple-value-bind (value present-p)
        (kv-get-chain-record database :receipt receipt-hash)
      (is present-p)
      (is (bytes= #(4 5 6) value)))
    (multiple-value-bind (value present-p)
        (kv-get-chain-record database :header block-hash :missing)
      (is (eq :missing value))
      (is (not present-p)))
    (let ((canonical-records (kv-chain-records database :canonical-hash)))
      (is (= 2 (length canonical-records)))
      (is (bytes= (kv-chain-record-key :canonical-hash 2)
                  (caar canonical-records)))
      (is (bytes= #(2) (cdar canonical-records)))
      (is (bytes= (kv-chain-record-key :canonical-hash 10)
                  (caadr canonical-records)))
      (is (bytes= #(10) (cdadr canonical-records))))
    (is (kv-delete-chain-record database :block block-hash))
    (multiple-value-bind (value present-p)
        (kv-get-chain-record database :block block-hash :missing)
      (is (eq :missing value))
      (is (not present-p)))))

(deftest chain-record-typed-index-helpers-round-trip
  (let ((database (make-memory-key-value-database))
        (block-hash-a (make-byte-vector 32 :initial-element #x0a))
        (block-hash-b (make-byte-vector 32 :initial-element #x0b))
        (block-hash-c (make-byte-vector 32 :initial-element #x0c)))
    (kv-put-chain-canonical-hash database 10 block-hash-b)
    (kv-put-chain-canonical-hash database 2 block-hash-a)
    (kv-put-chain-checkpoint database :head block-hash-b)
    (kv-put-chain-checkpoint database "safe" block-hash-a)
    (multiple-value-bind (value present-p)
        (kv-get-chain-canonical-hash database 10)
      (is present-p)
      (is (bytes= block-hash-b value)))
    (multiple-value-bind (value present-p)
        (kv-get-chain-checkpoint database :head)
      (is present-p)
      (is (bytes= block-hash-b value)))
    (let ((canonical-hashes (kv-chain-canonical-hashes database)))
      (is (= 2 (length canonical-hashes)))
      (is (= 2 (caar canonical-hashes)))
      (is (bytes= block-hash-a (cdar canonical-hashes)))
      (is (= 10 (caadr canonical-hashes)))
      (is (bytes= block-hash-b (cdadr canonical-hashes))))
    (let ((batch (make-kv-write-batch)))
      (kv-batch-put-chain-canonical-hash batch 12 block-hash-c)
      (kv-batch-put-chain-checkpoint batch :finalized block-hash-a)
      (kv-batch-delete-chain-checkpoint batch :safe)
      (kv-apply-batch database batch))
    (let ((canonical-hashes (kv-chain-canonical-hashes database))
          (checkpoints (kv-chain-checkpoints database)))
      (is (= 3 (length canonical-hashes)))
      (is (= 12 (caaddr canonical-hashes)))
      (is (bytes= block-hash-c (cdaddr canonical-hashes)))
      (is (= 2 (length checkpoints)))
      (is (bytes= block-hash-b
                  (cdr (assoc :head checkpoints))))
      (is (bytes= block-hash-a
                  (cdr (assoc :finalized checkpoints))))
      (is (not (assoc :safe checkpoints))))
    (is (kv-delete-chain-canonical-hash database 2))
    (multiple-value-bind (value present-p)
        (kv-get-chain-canonical-hash database 2 :missing)
      (is (eq :missing value))
      (is (not present-p)))
    (signals error
      (kv-put-chain-checkpoint database :unsafe block-hash-a))))

(deftest file-key-value-database-persists-chain-record-namespace
  (:layer :integration :module :database)
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-records-~A" (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (hash (make-byte-vector 32 :initial-element #x44)))
    (unwind-protect
         (progn
           (let ((database (make-file-key-value-database path)))
             (kv-put-chain-record database :block hash #(1 1 1))
             (kv-put-chain-record database :canonical-hash 1 #(4 4))
             (kv-put-chain-record database :canonical-hash 3 #(6 6)))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :block hash)
               (is present-p)
               (is (bytes= #(1 1 1) value)))
             (let ((records (kv-chain-records database :canonical-hash)))
               (is (= 2 (length records)))
               (is (bytes= #(4 4) (cdar records)))
               (is (bytes= #(6 6) (cdadr records))))))
      (when (probe-file path)
        (delete-file path)))))

(deftest file-key-value-database-persists-typed-chain-indexes
  (:layer :integration :module :database)
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-indexes-~A" (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (head-hash (make-byte-vector 32 :initial-element #x31))
         (safe-hash (make-byte-vector 32 :initial-element #x32))
         (side-hash (make-byte-vector 32 :initial-element #x33)))
    (unwind-protect
         (progn
           (let ((database (make-file-key-value-database path))
                 (batch (make-kv-write-batch)))
             (kv-batch-put-chain-canonical-hash batch 1 safe-hash)
             (kv-batch-put-chain-canonical-hash batch 2 head-hash)
             (kv-batch-put-chain-checkpoint batch :head head-hash)
             (kv-batch-put-chain-checkpoint batch :safe safe-hash)
             (kv-batch-put-chain-checkpoint batch :finalized safe-hash)
             (kv-apply-batch database batch)
             (kv-put-chain-canonical-hash database 99 side-hash)
             (kv-delete-chain-canonical-hash database 99))
           (let ((database (make-file-key-value-database path)))
             (let ((canonical-hashes (kv-chain-canonical-hashes database))
                   (checkpoints (kv-chain-checkpoints database)))
               (is (= 2 (length canonical-hashes)))
               (is (= 1 (caar canonical-hashes)))
               (is (bytes= safe-hash (cdar canonical-hashes)))
               (is (= 2 (caadr canonical-hashes)))
               (is (bytes= head-hash (cdadr canonical-hashes)))
               (is (= 3 (length checkpoints)))
               (is (bytes= head-hash
                           (cdr (assoc :head checkpoints))))
               (is (bytes= safe-hash
                           (cdr (assoc :safe checkpoints))))
               (is (bytes= safe-hash
                           (cdr (assoc :finalized checkpoints)))))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-canonical-hash database 99 :missing)
               (is (eq :missing value))
               (is (not present-p)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-record-write-batches-apply-atomically
  (let ((database (make-memory-key-value-database))
        (batch (make-kv-write-batch))
        (block-hash (make-byte-vector 32 :initial-element #x11))
        (receipt-hash (make-byte-vector 32 :initial-element #x22)))
    (kv-put-chain-record database :receipt receipt-hash #(9 9))
    (kv-batch-put-chain-record batch :block block-hash #(1 2 3))
    (kv-batch-put-chain-record batch :header block-hash #(4 5 6))
    (kv-batch-put-chain-record batch :canonical-hash 7 block-hash)
    (kv-batch-delete-chain-record batch :receipt receipt-hash)
    (multiple-value-bind (value present-p)
        (kv-get-chain-record database :block block-hash :missing)
      (is (eq :missing value))
      (is (not present-p)))
    (kv-apply-batch database batch)
    (multiple-value-bind (value present-p)
        (kv-get-chain-record database :block block-hash)
      (is present-p)
      (is (bytes= #(1 2 3) value)))
    (multiple-value-bind (value present-p)
        (kv-get-chain-record database :header block-hash)
      (is present-p)
      (is (bytes= #(4 5 6) value)))
    (multiple-value-bind (value present-p)
        (kv-get-chain-record database :canonical-hash 7)
      (is present-p)
      (is (bytes= block-hash value)))
    (multiple-value-bind (value present-p)
        (kv-get-chain-record database :receipt receipt-hash :missing)
      (is (eq :missing value))
      (is (not present-p)))
    (let ((entries (kv-chain-record-entries database :canonical-hash)))
      (is (= 1 (length entries)))
      (is (bytes= #(0 0 0 0 0 0 0 7) (caar entries)))
      (is (bytes= block-hash (cdar entries))))))

(deftest file-key-value-database-persists-chain-record-batches
  (:layer :integration :module :database)
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-record-batch-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (block-hash-a (make-byte-vector 32 :initial-element #x0a))
         (block-hash-b (make-byte-vector 32 :initial-element #x0b))
         (receipt-hash (make-byte-vector 32 :initial-element #x0c)))
    (unwind-protect
         (progn
           (let ((database (make-file-key-value-database path))
                 (batch (make-kv-write-batch)))
             (kv-put-chain-record database :receipt receipt-hash #(8 8))
             (kv-batch-put-chain-record batch :block block-hash-a #(1))
             (kv-batch-put-chain-record batch :block block-hash-b #(2))
             (kv-batch-put-chain-record
              batch :canonical-hash 2 block-hash-b)
             (kv-batch-put-chain-record
              batch :canonical-hash 1 block-hash-a)
             (kv-batch-delete-chain-record batch :receipt receipt-hash)
             (kv-apply-batch database batch))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :block block-hash-a)
               (is present-p)
               (is (bytes= #(1) value)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :receipt receipt-hash :missing)
               (is (eq :missing value))
               (is (not present-p)))
             (let ((entries
                     (kv-chain-record-entries database :canonical-hash)))
               (is (= 2 (length entries)))
               (is (bytes= #(0 0 0 0 0 0 0 1) (caar entries)))
               (is (bytes= block-hash-a (cdar entries)))
               (is (bytes= #(0 0 0 0 0 0 0 2) (caadr entries)))
               (is (bytes= block-hash-b (cdadr entries))))))
      (when (probe-file path)
        (delete-file path)))))

(defun kv-log-test-path (prefix)
  (merge-pathnames
   (make-pathname
    :name (format nil "~A-~A" prefix (gensym))
    :type "sexp")
   #P"/private/tmp/"))

(defun kv-log-test-file-size (path)
  (with-open-file (stream path :element-type '(unsigned-byte 8))
    (file-length stream)))

(defun kv-log-test-file-bytes (path)
  (with-open-file (stream path :element-type '(unsigned-byte 8))
    (let ((buffer (make-byte-vector (file-length stream))))
      (read-sequence buffer stream)
      buffer)))

(defun kv-log-test-file-starts-with-magic-p (path)
  (with-open-file (stream path :element-type '(unsigned-byte 8))
    (let ((header (make-byte-vector 8)))
      (and (= 8 (read-sequence header stream))
           (bytes= header (ascii-to-bytes "ELKVLOG2"))))))

(defun kv-log-test-append-raw-bytes (path bytes)
  (with-open-file (stream path
                          :direction :output
                          :element-type '(unsigned-byte 8)
                          :if-exists :append)
    (write-sequence bytes stream)))

(defun kv-log-test-overwrite-byte (path offset function)
  (let ((buffer (kv-log-test-file-bytes path)))
    (setf (aref buffer offset) (funcall function (aref buffer offset)))
    (with-open-file (stream path
                            :direction :output
                            :element-type '(unsigned-byte 8)
                            :if-exists :supersede)
      (write-sequence buffer stream))))

(defun kv-log-test-leaked-temp-files (path)
  (let ((prefix (format nil ".~A." (pathname-name path))))
    (remove-if-not
     (lambda (candidate)
       (let ((name (pathname-name candidate)))
         (and (stringp name)
              (>= (length name) (length prefix))
              (string= prefix name :end2 (length prefix)))))
     (directory #P"/private/tmp/*.sexp"))))

(defun kv-log-test-write-v1-file (path records &key leading-whitespace)
  (with-open-file (stream path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (when leading-whitespace
      (write-string leading-whitespace stream))
    (let ((*print-readably* t)
          (*print-pretty* nil))
      (write (list :ethereum-lisp-kv-v1 records) :stream stream)
      (terpri stream))))

(deftest log-file-key-value-database-appends-frames-under-magic-header
  (:layer :integration :module :database)
  (let ((path (kv-log-test-path "ethereum-lisp-kv-log-append")))
    (unwind-protect
         (progn
           (let ((database (make-file-key-value-database path)))
             (kv-put database #(1) #(10)))
           (is (kv-log-test-file-starts-with-magic-p path))
           (let ((bytes-after-first (kv-log-test-file-bytes path)))
             (let ((database (make-file-key-value-database path)))
               (kv-put database #(2) #(20 21)))
             ;; The second write appends: the first write's bytes remain a
             ;; byte-identical prefix of the file.
             (let ((bytes-after-second (kv-log-test-file-bytes path)))
               (is (> (length bytes-after-second)
                      (length bytes-after-first)))
               (is (bytes= bytes-after-first
                           (subseq bytes-after-second
                                   0 (length bytes-after-first))))))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (value present-p)
                 (kv-get database #(1))
               (is present-p)
               (is (bytes= #(10) value)))
             (multiple-value-bind (value present-p)
                 (kv-get database #(2))
               (is present-p)
               (is (bytes= #(20 21) value)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest log-file-key-value-database-recovers-from-a-torn-tail
  (:layer :integration :module :database)
  (let ((path (kv-log-test-path "ethereum-lisp-kv-log-torn")))
    (unwind-protect
         (progn
           (let ((database (make-file-key-value-database path)))
             (kv-put database #(1) #(10))
             (kv-put database #(2) #(20)))
           (let ((durable-size (kv-log-test-file-size path)))
             ;; A crashed append leaves a partial frame header.
             (kv-log-test-append-raw-bytes path #(0 0))
             (let ((database
                     (handler-bind ((warning #'muffle-warning))
                       (make-file-key-value-database path))))
               (multiple-value-bind (value present-p)
                   (kv-get database #(1))
                 (is present-p)
                 (is (bytes= #(10) value)))
               (multiple-value-bind (value present-p)
                   (kv-get database #(2))
                 (is present-p)
                 (is (bytes= #(20) value)))
               ;; Opening is a pure read: the torn bytes are still there.
               (is (= (+ durable-size 2) (kv-log-test-file-size path)))
               ;; The first write truncates them before appending.
               (kv-put database #(3) #(30))))
           ;; The log is whole again: reopening neither warns nor errors.
           (let ((warned nil))
             (handler-bind ((warning (lambda (condition)
                                       (setf warned t)
                                       (muffle-warning condition))))
               (let ((database (make-file-key-value-database path)))
                 (multiple-value-bind (value present-p)
                     (kv-get database #(3))
                   (is present-p)
                   (is (bytes= #(30) value)))))
             (is (not warned)))
           ;; A crashed append can also leave a frame that claims more
           ;; payload than reached the disk.
           (kv-log-test-append-raw-bytes
            path #(0 0 4 0 1 2 3 4 9 9 9))
           (let ((database
                   (handler-bind ((warning #'muffle-warning))
                     (make-file-key-value-database path))))
             (multiple-value-bind (value present-p)
                 (kv-get database #(3))
               (is present-p)
               (is (bytes= #(30) value)))
             (multiple-value-bind (value present-p)
                 (kv-get database #(1))
               (is present-p)
               (is (bytes= #(10) value)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest log-file-key-value-database-recovers-from-a-zero-filled-torn-tail
  (:layer :integration :module :database)
  ;; Filesystems that commit the size before the data read a torn append
  ;; back as zeros; a zero pseudo-frame must never pass the checksum.
  (let ((path (kv-log-test-path "ethereum-lisp-kv-log-zero-tail")))
    (unwind-protect
         (progn
           (let ((database (make-file-key-value-database path)))
             (kv-put database #(1) #(10))
             (kv-put database #(2) #(20)))
           (kv-log-test-append-raw-bytes path (make-byte-vector 64))
           (let ((database
                   (handler-bind ((warning #'muffle-warning))
                     (make-file-key-value-database path))))
             (multiple-value-bind (value present-p)
                 (kv-get database #(1))
               (is present-p)
               (is (bytes= #(10) value)))
             (multiple-value-bind (value present-p)
                 (kv-get database #(2))
               (is present-p)
               (is (bytes= #(20) value)))
             (kv-put database #(3) #(30)))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (value present-p)
                 (kv-get database #(3))
               (is present-p)
               (is (bytes= #(30) value)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest log-file-key-value-database-treats-a-zero-filled-file-as-empty
  (:layer :integration :module :database)
  ;; A crash during the very first append can leave only zeros or a prefix
  ;; of the magic header; both mean "no record was ever durable".
  (let ((path (kv-log-test-path "ethereum-lisp-kv-log-zero-file")))
    (unwind-protect
         (dolist (content (list (make-byte-vector 24)
                                (ascii-to-bytes "ELKVL")))
           (with-open-file (stream path
                                   :direction :output
                                   :element-type '(unsigned-byte 8)
                                   :if-exists :supersede)
             (write-sequence content stream))
           (let ((database
                   (handler-bind ((warning #'muffle-warning))
                     (make-file-key-value-database path))))
             (multiple-value-bind (value present-p)
                 (kv-get database #(1) :missing)
               (is (eq :missing value))
               (is (not present-p)))
             (kv-put database #(1) #(10)))
           (is (kv-log-test-file-starts-with-magic-p path))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (value present-p)
                 (kv-get database #(1))
               (is present-p)
               (is (bytes= #(10) value)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest log-file-key-value-database-fail-stops-on-mid-log-corruption
  (:layer :integration :module :database)
  (let ((path (kv-log-test-path "ethereum-lisp-kv-log-corrupt")))
    (unwind-protect
         (progn
           (let ((database (make-file-key-value-database path)))
             (kv-put database #(1) #(10))
             (kv-put database #(2) #(20)))
           ;; Flip a payload byte of the FIRST frame: its checksum fails
           ;; while a valid record follows, which a torn write cannot cause.
           (kv-log-test-overwrite-byte
            path 17 (lambda (byte) (logxor byte #xff)))
           (signals ethereum-lisp.database:kv-log-corruption-error
             (make-file-key-value-database path)))
      (when (probe-file path)
        (delete-file path)))))

(deftest log-file-key-value-database-fail-stops-on-corrupted-record-length
  (:layer :integration :module :database)
  ;; A corrupted length field must not masquerade as a torn tail and
  ;; silently truncate the acknowledged records after it.
  (let ((path (kv-log-test-path "ethereum-lisp-kv-log-length")))
    (unwind-protect
         (progn
           (let ((database (make-file-key-value-database path)))
             (kv-put database #(1) #(10))
             (kv-put database #(2) #(20)))
           ;; Byte 12 is the high byte of the first frame's size field.
           (kv-log-test-overwrite-byte
            path 12 (lambda (byte) (logxor byte #xff)))
           (signals ethereum-lisp.database:kv-log-corruption-error
             (make-file-key-value-database path)))
      (when (probe-file path)
        (delete-file path)))))

(deftest log-file-key-value-database-rejects-an-unrecognized-header
  (:layer :integration :module :database)
  (let ((path (kv-log-test-path "ethereum-lisp-kv-log-header")))
    (unwind-protect
         (progn
           (with-open-file (stream path :direction :output)
             (write-string "not a database" stream))
           (signals ethereum-lisp.database:kv-log-corruption-error
             (make-file-key-value-database path)))
      (when (probe-file path)
        (delete-file path)))))

(deftest log-file-key-value-database-write-batches-are-atomic-on-disk
  (:layer :integration :module :database)
  (let ((path (kv-log-test-path "ethereum-lisp-kv-log-atomic")))
    (unwind-protect
         (progn
           (let ((database (make-file-key-value-database path))
                 (batch (make-kv-write-batch)))
             (kv-put database #(1) #(10))
             (kv-batch-put batch #(2) #(20))
             (kv-batch-put batch #(3) #(30))
             (kv-batch-delete batch #(1))
             (kv-apply-batch database batch))
           ;; Chop bytes off the batch frame, as a crash mid-append would.
           (let ((size (kv-log-test-file-size path)))
             (ethereum-lisp.database::kv-log-truncate-file path (- size 3)))
           (let ((database
                   (handler-bind ((warning #'muffle-warning))
                     (make-file-key-value-database path))))
             ;; The whole batch is gone: no partial write set survives.
             (multiple-value-bind (value present-p)
                 (kv-get database #(1))
               (is present-p)
               (is (bytes= #(10) value)))
             (multiple-value-bind (value present-p)
                 (kv-get database #(2))
               (declare (ignore value))
               (is (not present-p)))
             (multiple-value-bind (value present-p)
                 (kv-get database #(3))
               (declare (ignore value))
               (is (not present-p)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest log-file-key-value-database-compacts-a-bloated-log
  (:layer :integration :module :database)
  (let ((path (kv-log-test-path "ethereum-lisp-kv-log-compact")))
    (unwind-protect
         (progn
           (let ((database (make-file-key-value-database
                            path
                            :compaction-min-bytes 1
                            :compaction-ratio 2))
                 (value (make-byte-vector 32 :initial-element 7)))
             (dotimes (round 50)
               (kv-put database #(1) value))
             (kv-put database #(2) #(20)))
           ;; Fifty overwrites appended fifty records; compaction keeps the
           ;; file near the live size instead.
           (is (< (kv-log-test-file-size path) 300))
           (is (kv-log-test-file-starts-with-magic-p path))
           ;; Prove the leak detector can see leak-shaped files, then that
           ;; there are none.
           (let ((decoy
                   (merge-pathnames
                    (make-pathname
                     :name (format nil ".~A.DECOY" (pathname-name path))
                     :type "sexp")
                    #P"/private/tmp/")))
             (with-open-file (stream decoy :direction :output)
               (write-string "decoy" stream))
             (is (not (null (kv-log-test-leaked-temp-files path))))
             (delete-file decoy))
           (is (null (kv-log-test-leaked-temp-files path)))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (value present-p)
                 (kv-get database #(1))
               (is present-p)
               (is (bytes= (make-byte-vector 32 :initial-element 7) value)))
             (multiple-value-bind (value present-p)
                 (kv-get database #(2))
               (is present-p)
               (is (bytes= #(20) value)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest log-file-key-value-database-migrates-v1-files-on-first-write
  (:layer :integration :module :database)
  (let ((path (kv-log-test-path "ethereum-lisp-kv-log-migrate")))
    (unwind-protect
         (progn
           (kv-log-test-write-v1-file path '(("01" "0a0b") ("0203" "0c")))
           (let ((v1-bytes (kv-log-test-file-bytes path)))
             (let ((database (make-file-key-value-database path)))
               (multiple-value-bind (value present-p)
                   (kv-get database #(1))
                 (is present-p)
                 (is (bytes= #(10 11) value)))
               (multiple-value-bind (value present-p)
                   (kv-get database #(2 3))
                 (is present-p)
                 (is (bytes= #(12) value))))
             ;; A read-only open leaves the v1 artifact byte-identical.
             (is (bytes= v1-bytes (kv-log-test-file-bytes path))))
           (let ((database (make-file-key-value-database path)))
             (kv-put database #(4) #(40)))
           ;; The first write migrated the file to the log format.
           (is (kv-log-test-file-starts-with-magic-p path))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (value present-p)
                 (kv-get database #(1))
               (is present-p)
               (is (bytes= #(10 11) value)))
             (multiple-value-bind (value present-p)
                 (kv-get database #(4))
               (is present-p)
               (is (bytes= #(40) value)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest log-file-key-value-database-migrates-v1-files-with-leading-whitespace
  (:layer :integration :module :database)
  (let ((path (kv-log-test-path "ethereum-lisp-kv-log-migrate-ws")))
    (unwind-protect
         (progn
           (kv-log-test-write-v1-file path '(("01" "0a"))
                                      :leading-whitespace (format nil "~% "))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (value present-p)
                 (kv-get database #(1))
               (is present-p)
               (is (bytes= #(10) value)))
             (kv-put database #(2) #(20)))
           (is (kv-log-test-file-starts-with-magic-p path))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (value present-p)
                 (kv-get database #(2))
               (is present-p)
               (is (bytes= #(20) value)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest log-file-key-value-database-fsyncs-before-the-table-changes
  (:layer :integration :module :database)
  (let ((path (kv-log-test-path "ethereum-lisp-kv-log-fsync"))
        (sync-calls 0)
        (key-visible-at-first-sync :never-synced)
        (original (fdefinition 'ethereum-lisp.database::kv-log-sync-stream)))
    (unwind-protect
         (let ((database (make-file-key-value-database path))
               (batch (make-kv-write-batch)))
           (setf (fdefinition 'ethereum-lisp.database::kv-log-sync-stream)
                 (lambda (stream)
                   (incf sync-calls)
                   (when (= 1 sync-calls)
                     (setf key-visible-at-first-sync
                           (nth-value 1 (kv-get database #(1)))))
                   (funcall original stream)))
           (kv-put database #(1) #(10))
           (is (= 1 sync-calls))
           ;; The record is synced BEFORE the in-memory table mutates.
           (is (null key-visible-at-first-sync))
           (kv-batch-put batch #(2) #(20))
           (kv-batch-put batch #(3) #(30))
           (kv-apply-batch database batch)
           (is (= 2 sync-calls))
           (kv-delete database #(1))
           (is (= 3 sync-calls))
           ;; Deleting an absent key writes nothing, so it syncs nothing.
           (kv-delete database #(9))
           (is (= 3 sync-calls)))
      (setf (fdefinition 'ethereum-lisp.database::kv-log-sync-stream)
            original)
      (when (probe-file path)
        (delete-file path)))))

(deftest log-file-key-value-database-poisons-the-handle-after-a-failed-append
  (:layer :integration :module :database)
  (let ((path (kv-log-test-path "ethereum-lisp-kv-log-poison"))
        (original (fdefinition 'ethereum-lisp.database::kv-log-sync-stream)))
    (unwind-protect
         (let ((database (make-file-key-value-database path)))
           (kv-put database #(1) #(10))
           (setf (fdefinition 'ethereum-lisp.database::kv-log-sync-stream)
                 (lambda (stream)
                   (declare (ignore stream))
                   (error "simulated sync failure")))
           (signals error
             (kv-put database #(2) #(20)))
           (setf (fdefinition 'ethereum-lisp.database::kv-log-sync-stream)
                 original)
           ;; The failed append poisons the handle even though the sync
           ;; works again: the on-disk tail is no longer trusted.
           (signals ethereum-lisp.database:kv-log-corruption-error
             (kv-put database #(3) #(30)))
           ;; The failed write set never reached the in-memory view.
           (multiple-value-bind (value present-p)
               (kv-get database #(2) :missing)
             (is (eq :missing value))
             (is (not present-p)))
           ;; A fresh handle recovers the durable state.
           (let ((reopened
                   (handler-bind ((warning #'muffle-warning))
                     (make-file-key-value-database path))))
             (multiple-value-bind (value present-p)
                 (kv-get reopened #(1))
               (is present-p)
               (is (bytes= #(10) value)))))
      (setf (fdefinition 'ethereum-lisp.database::kv-log-sync-stream)
            original)
      (when (probe-file path)
        (delete-file path)))))

(deftest log-file-key-value-database-fail-stops-when-the-file-changes-underneath
  (:layer :integration :module :database)
  (let ((path (kv-log-test-path "ethereum-lisp-kv-log-underneath")))
    (unwind-protect
         (progn
           (let ((database (make-file-key-value-database path)))
             (kv-put database #(1) #(10))
             ;; Another writer appends behind this handle's back.
             (kv-log-test-append-raw-bytes path #(1 2 3))
             (signals ethereum-lisp.database:kv-log-corruption-error
               (kv-put database #(2) #(20))))
           (let ((database
                   (handler-bind ((warning #'muffle-warning))
                     (make-file-key-value-database path))))
             ;; The file vanishes underneath the handle.
             (delete-file path)
             (signals ethereum-lisp.database:kv-log-corruption-error
               (kv-put database #(3) #(30)))))
      (when (probe-file path)
        (delete-file path)))))
