(in-package #:ethereum-lisp.test)

(deftest db-operator-options-are-explicit-and-rocksdb-first
  (let ((options
          (ethereum-lisp.cli::devnet-cli-db-options
           (list "db" "backup"
                 "--source" "/tmp/source"
                 "--target" "/tmp/target"
                 "--batch-size" "17"))))
    (is (string= "backup" (getf options :operation)))
    (is (string= "/tmp/source" (getf options :source-path)))
    (is (string= "/tmp/target" (getf options :target-path)))
    (is (eq :rocksdb (getf options :source-engine)))
    (is (eq :rocksdb (getf options :target-engine)))
    (is (= 17 (getf options :batch-size))))
  (let ((options
          (ethereum-lisp.cli::devnet-cli-db-options
           (list "db" "verify" "--source" "/tmp/source"
                 "--source.engine" "file"))))
    (is (string= "verify" (getf options :operation)))
    (is (eq :file (getf options :source-engine))))
  (signals error
    (ethereum-lisp.cli::devnet-cli-db-options
     (list "db" "backup" "--source" "/tmp/source")))
  (signals error
    (ethereum-lisp.cli::devnet-cli-db-options
     (list "db" "verify" "--source" "/tmp/source"
           "--batch-size" "0"))))

(deftest db-operator-cli-verifies-and-backs-up-the-file-oracle
  (let ((source-path (kv-log-test-path "ethereum-lisp-db-source"))
        (backup-path (kv-log-test-path "ethereum-lisp-db-backup")))
    (unwind-protect
         (let ((source (make-file-key-value-database source-path))
               (source-store (verify-test-database)))
           ;; Copy the memory oracle into the on-disk file source through the
           ;; same bounded operator primitive used across backend types.
           (node-store-backup-chain-database
            source-store source :batch-size 2)
           (let ((output (make-string-output-stream))
                 (errors (make-string-output-stream)))
             (is (= 0
                    (ethereum-lisp.cli:main
                     (list "db" "verify"
                           "--source" source-path
                           "--source.engine" "file")
                     :output-stream output
                     :error-stream errors)))
             (is (search "OK schema=" (get-output-stream-string output)))
             (is (string= "" (get-output-stream-string errors))))
           (let ((output (make-string-output-stream))
                 (errors (make-string-output-stream)))
             (is (= 0
                    (ethereum-lisp.cli:main
                     (list "db" "backup"
                           "--source" source-path
                           "--target" backup-path
                           "--source.engine" "file"
                           "--target.engine" "file"
                           "--batch-size" "1")
                     :output-stream output
                     :error-stream errors)))
             (is (search "backup complete:"
                         (get-output-stream-string output)))
             (is (string= "" (get-output-stream-string errors))))
           (let ((restored (make-file-key-value-database backup-path)))
             (is (code-store-test-databases-equal-p source restored))))
      (when (probe-file source-path)
        (delete-file source-path))
      (when (probe-file backup-path)
        (delete-file backup-path)))))
