;;;; RocksDB crash-injection helper.
;;;;
;;;; Writes a WAL-synced batch into the RocksDB directory named by the first
;;;; argument, records a marker file named by the second, and then blocks
;;;; forever. It deliberately never closes the database: the parent test
;;;; SIGKILLs this process so the reopen it performs is a crash recovery, not a
;;;; clean shutdown. The marker appears only after kv-apply-batch returns, and
;;;; because make-rocksdb-key-value-database opens with write-options sync=1 that
;;;; return means the batch is durable in the WAL. See the crash test in
;;;; tests/database-tests.lisp.

(defparameter *root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(require :asdf)
(asdf:load-asd (merge-pathnames "ethereum-lisp.asd" *root*))
(asdf:load-system :ethereum-lisp)

(let* ((args (cdr sb-ext:*posix-argv*))
       (path (or (first args)
                 (error "usage: rocksdb-crash-writer.lisp DIRECTORY MARKER")))
       (marker (or (second args)
                   (error "usage: rocksdb-crash-writer.lisp DIRECTORY MARKER")))
       (database (ethereum-lisp.database:make-rocksdb-key-value-database path))
       (batch (ethereum-lisp.database:make-kv-write-batch)))
  (dotimes (i 16)
    (ethereum-lisp.database:kv-batch-put batch (vector i) (vector (+ 100 i))))
  ;; write-options sync=1, so this returns only once the batch is WAL-synced.
  (ethereum-lisp.database:kv-apply-batch database batch)
  (with-open-file (out marker :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
    (write-string "committed" out))
  (finish-output)
  ;; Block so the parent can SIGKILL us with no clean close. The database is
  ;; left open on purpose: a crash does not get to flush or release it.
  (loop (sleep 3600)))
