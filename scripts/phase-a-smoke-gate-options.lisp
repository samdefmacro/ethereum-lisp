(defparameter *ethereum-lisp-smoke-gate-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(require :asdf)

(defvar *smoke-gate-environment-lookup* #'uiop:getenv)

(defconstant +smoke-gate-pinned-v5.4.0-flag+ "--pinned-v5.4.0")
(defconstant +smoke-gate-devnet-flag+ "--devnet")
(defconstant +smoke-gate-drift-map-flag+ "--drift-map")
(defconstant +smoke-gate-json-flag+ "--json")
(defconstant +smoke-gate-root-option+ "--root")
(defconstant +smoke-gate-help-flag+ "--help")
(defconstant +smoke-gate-default-root+
  "tests/fixtures/execution-spec-tests-root/")
(defconstant +smoke-gate-eest-root-env+
  "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT")
(defconstant +smoke-gate-eest-repository+
  "ethereum/execution-spec-tests")
(defconstant +smoke-gate-eest-release+ "v5.4.0")
(defconstant +smoke-gate-eest-tag-target+ "88e9fb8")
(defconstant +smoke-gate-eest-archive+ "fixtures_stable.tar.gz")
(defconstant +smoke-gate-devnet-prune-state-before+ 42)
(defparameter +smoke-gate-devnet-side-reorg-fixture-cases+
  '("shanghai-one-transfer-with-withdrawal"
    "shanghai-two-legacy-transfers-with-withdrawal"
    "shanghai-log-contract-call-with-withdrawal"))

(defparameter *smoke-gate-boolean-options*
  (list +smoke-gate-pinned-v5.4.0-flag+
        +smoke-gate-devnet-flag+
        +smoke-gate-drift-map-flag+
        +smoke-gate-json-flag+))

(defun smoke-gate-option-token-p (value)
  (and (stringp value)
       (<= 2 (length value))
       (string= "--" value :end2 2)))

(defun smoke-gate-boolean-option-p (arg)
  (member arg *smoke-gate-boolean-options* :test #'string=))

(defun smoke-gate-parse-boolean-assignment (option value)
  (let ((normalized (and (stringp value) (string-downcase value))))
    (cond
      ((member normalized '("true" "1") :test #'string=) t)
      ((member normalized '("false" "0") :test #'string=) nil)
      (t (error "~A boolean value must be true or false" option)))))

(defun smoke-gate-normalize-option-args (args)
  (loop for arg in args
        for separator = (and (smoke-gate-option-token-p arg)
                             (position #\= arg :start 2))
        for option = (and separator (subseq arg 0 separator))
        for value = (and separator (subseq arg (1+ separator)))
        append
        (cond
          ((and separator (string= option +smoke-gate-root-option+))
           (list option value))
          ((and separator (smoke-gate-boolean-option-p option))
           (if (smoke-gate-parse-boolean-assignment option value)
               (list option)
               '()))
          (t
           (list arg)))))

(defun smoke-gate-arguments ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (cdr args)))
    (smoke-gate-normalize-option-args args))
  #-sbcl nil)

(defun smoke-gate-pinned-v5.4.0-p (args)
  (member +smoke-gate-pinned-v5.4.0-flag+ args :test #'string=))

(defun smoke-gate-devnet-p (args)
  (member +smoke-gate-devnet-flag+ args :test #'string=))

(defun smoke-gate-drift-map-p (args)
  (member +smoke-gate-drift-map-flag+ args :test #'string=))

(defun smoke-gate-json-p (args)
  (member +smoke-gate-json-flag+ args :test #'string=))

(defun smoke-gate-help-p (args)
  (member +smoke-gate-help-flag+ args :test #'string=))

(defun smoke-gate-option-like-p (value)
  (and (stringp value)
       (plusp (length value))
       (char= #\- (char value 0))))

(defun smoke-gate-set-argument-root (root value)
  (when root
    (error "Only one fixture root argument is supported"))
  value)

(defun smoke-gate-argument-root (args)
  (let ((root nil))
    (loop while args
          for arg = (pop args)
          do
      (cond
        ((string= arg +smoke-gate-pinned-v5.4.0-flag+))
        ((string= arg +smoke-gate-devnet-flag+))
        ((string= arg +smoke-gate-drift-map-flag+))
        ((string= arg +smoke-gate-json-flag+))
        ((string= arg +smoke-gate-help-flag+))
        ((string= arg +smoke-gate-root-option+)
         (unless args
           (error "~A requires a fixture root path" +smoke-gate-root-option+))
         (let ((value (pop args)))
           (when (smoke-gate-option-like-p value)
             (error "~A requires a fixture root path, got option ~A"
                    +smoke-gate-root-option+
                    value))
           (setf root (smoke-gate-set-argument-root root value))))
        ((smoke-gate-option-like-p arg)
         (error "Unsupported smoke gate option ~A" arg))
        (t
         (setf root (smoke-gate-set-argument-root root arg)))))
    root))

(defun smoke-gate-print-help ()
  (format t "~&Usage: sbcl --script scripts/phase-a-smoke-gate.lisp -- [options] [ROOT]~%")
  (format t "~%")
  (format t "Options:~%")
  (format t "  --root PATH        Fixture suite root. Equivalent to positional ROOT.~%")
  (format t "  --pinned-v5.4.0    Validate the pinned EEST v5.4.0 stable archive subset.~%")
  (format t "  --devnet           Also run the devnet listener-boundary all-fixtures gate.~%")
  (format t "  --drift-map        Also classify remaining unpinned selectors and require no materializable drift.~%")
  (format t "  --json             Print machine-readable JSON output.~%")
  (format t "  --help             Print this help without loading the test system.~%")
  (format t "~%")
  (format t "Default ROOT: ~A~%" +smoke-gate-default-root+)
  (format t "Pinned mode requires ROOT or ~A when ROOT is omitted.~%"
          +smoke-gate-eest-root-env+)
  (format t "Reference client roots: ETHEREUM_LISP_GETH_ROOT, ~
ETHEREUM_LISP_NETHERMIND_ROOT, ETHEREUM_LISP_RETH_ROOT override ~
references/ checkouts.~%"))
