(defparameter *ethereum-lisp-devnet-smoke-gate-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defconstant +devnet-smoke-gate-early-help-flag+ "--help")

(defun devnet-smoke-gate-early-arguments ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (cdr args)))
    args)
  #-sbcl nil)

(defun devnet-smoke-gate-early-help-p (args)
  (member +devnet-smoke-gate-early-help-flag+ args :test #'string=))

(defun devnet-smoke-gate-print-early-help ()
  (format t "~&Usage: sbcl --script scripts/devnet-smoke-gate.lisp -- [options] [FIXTURE-CASE]~%")
  (format t "~%")
  (format t "Options:~%")
  (format t "  --fixture-case NAME  Engine newPayloadV2 fixture case to import.~%")
  (format t "  --all-fixtures       Import every pinned Phase A newPayloadV2 smoke case.~%")
  (format t "  --engine-only-serve Run a focused serve-mode check with public HTTP disabled.~%")
  (format t "  --ready-file PATH    Write devnet readiness JSON and verify it.~%")
  (format t "  --log-file PATH      Write devnet telemetry events and verify them.~%")
  (format t "  --pid-file PATH      Write the devnet process id and verify it.~%")
  (format t "  --database PATH      Export and verify a file-backed KV chain snapshot.~%")
  (format t "  --prune-state-before NUMBER~%")
  (format t "                       Prune retained state before NUMBER when exporting --database.~%")
  (format t "  --override.terminaltotaldifficulty TTD~%")
  (format t "                       Configure the Engine transition total difficulty.~%")
  (format t "  --override.terminaltotaldifficultypassed~%")
  (format t "                       Mark terminal total difficulty as passed.~%")
  (format t "  --override.terminalblockhash HASH~%")
  (format t "                       Configure the Engine transition terminal block hash.~%")
  (format t "  --override.terminalblocknumber NUMBER~%")
  (format t "                       Configure the Engine transition terminal block number.~%")
  (format t "  --json               Print machine-readable JSON output.~%")
  (format t "  --help               Print this help.~%")
  (format t "~%")
  (format t "Reference client roots: ETHEREUM_LISP_GETH_ROOT, ~
ETHEREUM_LISP_NETHERMIND_ROOT, ETHEREUM_LISP_RETH_ROOT override ~
references/ checkouts.~%")
  (format t "~%"))

#+sbcl
(when (devnet-smoke-gate-early-help-p (devnet-smoke-gate-early-arguments))
  (devnet-smoke-gate-print-early-help)
  (sb-ext:exit :code 0))

(load (merge-pathnames "tests/load-tests.lisp"
                       *ethereum-lisp-devnet-smoke-gate-root*))

(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-devnet-smoke-gate-root*
  (symbol-value 'cl-user::*ethereum-lisp-devnet-smoke-gate-root*))

(defun devnet-smoke-gate-load-file (relative-path)
  (load (merge-pathnames relative-path
                         *ethereum-lisp-devnet-smoke-gate-root*)))

(dolist (relative-path
         '("scripts/devnet-smoke-gate-options.lisp"
           "scripts/devnet-smoke-gate-public-checks.lisp"
           "scripts/devnet-smoke-gate-runtime-helpers.lisp"
           "scripts/devnet-smoke-gate-engine-only.lisp"
           "scripts/devnet-smoke-gate-restored-rpc.lisp"
           "scripts/devnet-smoke-gate-database.lisp"
           "scripts/devnet-smoke-gate-run.lisp"
           "scripts/devnet-smoke-gate-output.lisp"))
  (devnet-smoke-gate-load-file relative-path))

(defun devnet-smoke-gate-main ()
  (let* ((args (devnet-smoke-gate-arguments))
         (help-p (devnet-smoke-gate-help-p args))
         (json-p (devnet-smoke-gate-json-p args))
         (all-fixtures-p (devnet-smoke-gate-all-fixtures-p args))
         (engine-only-serve-p
           (devnet-smoke-gate-engine-only-serve-p args))
         (ready-file
           (devnet-smoke-gate-path-option
            args +devnet-smoke-gate-ready-file-option+))
         (log-file
           (devnet-smoke-gate-path-option
            args +devnet-smoke-gate-log-file-option+))
         (pid-file
           (devnet-smoke-gate-path-option
            args +devnet-smoke-gate-pid-file-option+))
         (database-file
           (devnet-smoke-gate-path-option
            args +devnet-smoke-gate-database-option+))
         (state-prune-before
           (devnet-smoke-gate-non-negative-integer-option
            args +devnet-smoke-gate-prune-state-before-option+))
         (terminal-total-difficulty
           (devnet-smoke-gate-quantity-option
            args +devnet-smoke-gate-terminal-total-difficulty-option+))
         (terminal-total-difficulty-passed-p
           (not
            (null
             (member +devnet-smoke-gate-terminal-total-difficulty-passed-flag+
                     args
                     :test #'string=))))
         (terminal-block-hash
           (devnet-smoke-gate-hash32-option
            args +devnet-smoke-gate-terminal-block-hash-option+))
         (terminal-block-number
           (devnet-smoke-gate-quantity-option
            args +devnet-smoke-gate-terminal-block-number-option+))
         (case-name (devnet-smoke-gate-fixture-case-name args)))
    (if help-p
        (devnet-smoke-gate-print-help)
        (let ((report
                (cond
                  (engine-only-serve-p
                   (when all-fixtures-p
                     (error "~A cannot be combined with ~A"
                            +devnet-smoke-gate-engine-only-serve-flag+
                            +devnet-smoke-gate-all-fixtures-flag+))
                   (when (devnet-smoke-gate-fixture-case-specified-p args)
                     (error "~A cannot be combined with a fixture case"
                            +devnet-smoke-gate-engine-only-serve-flag+))
                   (devnet-smoke-gate-verify-engine-only-serve
                    :ready-file ready-file
                    :log-file log-file
                    :pid-file pid-file
                    :database-file database-file))
                  (all-fixtures-p
                   (when (devnet-smoke-gate-fixture-case-specified-p args)
                     (error "~A cannot be combined with a fixture case"
                            +devnet-smoke-gate-all-fixtures-flag+))
                   (devnet-smoke-gate-run-all
                    +engine-newpayload-v2-smoke-case-names+
                    :ready-file ready-file
                    :log-file log-file
                    :pid-file pid-file
                    :database-file database-file
                    :state-prune-before state-prune-before
                    :terminal-total-difficulty
                    terminal-total-difficulty
                    :terminal-total-difficulty-passed-p
                    terminal-total-difficulty-passed-p
                    :terminal-block-hash terminal-block-hash
                    :terminal-block-number terminal-block-number))
                  (t
                   (devnet-smoke-gate-run
                    case-name
                    :ready-file ready-file
                    :log-file log-file
                    :pid-file pid-file
                    :database-file database-file
                    :state-prune-before state-prune-before
                    :terminal-total-difficulty
                    terminal-total-difficulty
                    :terminal-total-difficulty-passed-p
                    terminal-total-difficulty-passed-p
                    :terminal-block-hash terminal-block-hash
                    :terminal-block-number terminal-block-number)))))
          (if json-p
              (format t "~&~A~%" (json-encode report))
              (devnet-smoke-gate-print-text report))))))

(devnet-smoke-gate-main)
