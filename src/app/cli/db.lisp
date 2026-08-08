(in-package #:ethereum-lisp.cli)

;;;; Offline chain-database operator commands.

(defparameter +devnet-cli-db-operations+
  '("verify" "backup" "restore" "repair" "rebuild"))

(defun devnet-cli-db-command-p (args)
  (devnet-cli-command-position args "db"))

(defun devnet-cli-print-db-usage (stream)
  (format stream
          "Usage: ethereum-lisp db OPERATION --source PATH [--target PATH] [--source.engine file|rocksdb] [--target.engine file|rocksdb] [--batch-size N]~%")
  (format stream "~%Operations:~%")
  (format stream "  verify   Audit SOURCE without modifying it.~%")
  (format stream "  backup   Copy offline SOURCE byte-for-byte to fresh TARGET.~%")
  (format stream "  restore  Restore backup SOURCE into fresh TARGET.~%")
  (format stream "  repair   Repair only safely derivable records into fresh TARGET.~%")
  (format stream "  rebuild  Regenerate derived records into fresh TARGET.~%")
  (format stream "~%The default engine is rocksdb. Use file explicitly for the CRC-log oracle.~%"))

(defun devnet-cli-db-options (arguments)
  (let ((args (devnet-cli-remove-command-token arguments "db"))
        (operation nil)
        (source-path nil)
        (target-path nil)
        (source-engine :rocksdb)
        (target-engine :rocksdb)
        (batch-size 1024)
        (help-p nil))
    (when (and args (not (devnet-cli-option-token-p (first args))))
      (setf operation (string-downcase (pop args))))
    (loop while args
          for option = (pop args)
          do (cond
               ((member option '("--help" "-h") :test #'string=)
                (setf help-p t))
               ((string= option "--source")
                (multiple-value-setq (source-path args)
                  (devnet-cli-next-value args option)))
               ((string= option "--target")
                (multiple-value-setq (target-path args)
                  (devnet-cli-next-value args option)))
               ((string= option "--source.engine")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf source-engine (devnet-cli-parse-db-engine value)
                        args rest)))
               ((string= option "--target.engine")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf target-engine (devnet-cli-parse-db-engine value)
                        args rest)))
               ((string= option "--batch-size")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf batch-size
                        (devnet-cli-parse-positive-integer value option)
                        args rest)))
               ((devnet-cli-option-token-p option)
                (error "Unknown db option ~A" option))
               (t
                (error "Unexpected db argument ~A" option))))
    (unless (or help-p
                (member operation +devnet-cli-db-operations+
                        :test #'string=))
      (error "db operation must be verify, backup, restore, repair, or rebuild"))
    (unless (or help-p source-path)
      (error "db ~A requires --source PATH" operation))
    (unless (or help-p
                (string= operation "verify")
                target-path)
      (error "db ~A requires --target PATH" operation))
    (list :operation operation
          :source-path source-path
          :target-path target-path
          :source-engine source-engine
          :target-engine target-engine
          :batch-size batch-size
          :help-p help-p)))

(defun devnet-cli-open-db-source (path engine)
  (ecase engine
    (:file
     (let ((existing (probe-file path)))
       (unless (and existing (not (devnet-cli-empty-file-p existing)))
         (error "Database source does not exist or is empty: ~A" path))
       (make-file-key-value-database existing)))
    (:rocksdb
     (unless (devnet-cli-rocksdb-directory-initialized-p path)
       (error "RocksDB source is not initialized: ~A" path))
     (make-rocksdb-key-value-database path :create-if-missing-p nil))))

(defun devnet-cli-open-db-target (path engine)
  (ecase engine
    (:file
     (ensure-directories-exist (pathname path))
     (let ((existing (probe-file path)))
       (when (and existing (devnet-cli-empty-file-p existing))
         (delete-file existing)))
     (make-file-key-value-database path))
    (:rocksdb
     (ensure-directories-exist (uiop:ensure-directory-pathname path))
     (make-rocksdb-key-value-database path))))

(defun devnet-cli-close-db-operator-database (database)
  (when (typep database 'rocksdb-key-value-database)
    (close-rocksdb-key-value-database database)))

(defun devnet-cli-call-with-db-source (path engine function)
  (let ((database (devnet-cli-open-db-source path engine)))
    (unwind-protect
         (funcall function database)
      (devnet-cli-close-db-operator-database database))))

(defun devnet-cli-call-with-db-source-and-target
    (options function)
  (let ((source-path (getf options :source-path))
        (target-path (getf options :target-path)))
    (when (devnet-cli-same-output-path-p source-path target-path)
      (error "Database source and target paths must be different"))
    (devnet-cli-call-with-db-source
     source-path
     (getf options :source-engine)
     (lambda (source)
       (let ((target
               (devnet-cli-open-db-target
                target-path (getf options :target-engine))))
         (unwind-protect
              (funcall function source target)
           (devnet-cli-close-db-operator-database target)))))))

(defun devnet-cli-run-db-verify (options output-stream)
  (devnet-cli-call-with-db-source
   (getf options :source-path)
   (getf options :source-engine)
   (lambda (source)
     (let ((findings (node-store-verify-chain-database source)))
       (if findings
           (progn
             (dolist (finding findings)
               (format output-stream "~A~%"
                       (node-store-database-finding-description finding)))
             1)
           (progn
             (format output-stream "OK schema=~D~%"
                     (node-store-chain-schema-version source))
             0))))))

(defun devnet-cli-run-db-copy-operation (options output-stream function)
  (devnet-cli-call-with-db-source-and-target
   options
   (lambda (source target)
     (multiple-value-bind (record-count changed-p)
         (funcall function
                  source target :batch-size (getf options :batch-size))
       (declare (ignore changed-p))
       (format output-stream "~A complete: ~D source records~%"
               (getf options :operation) record-count)
       0))))

(defun devnet-cli-run-db (options output-stream)
  (let ((operation (getf options :operation)))
    (cond
      ((string= operation "verify")
       (devnet-cli-run-db-verify options output-stream))
      ((string= operation "backup")
       (devnet-cli-run-db-copy-operation
        options output-stream #'node-store-backup-chain-database))
      ((string= operation "restore")
       (devnet-cli-run-db-copy-operation
        options output-stream #'node-store-restore-chain-database))
      ((string= operation "repair")
       (devnet-cli-run-db-copy-operation
        options output-stream #'node-store-repair-chain-database))
      ((string= operation "rebuild")
       (devnet-cli-run-db-copy-operation
        options output-stream #'node-store-rebuild-chain-database))
      (t
       (error "Unknown db operation: ~A" operation)))))
