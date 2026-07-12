(defun smoke-gate-call (name &rest args)
  (let ((symbol (find-symbol (string-upcase name) "ETHEREUM-LISP.TEST")))
    (unless (and symbol (fboundp symbol))
      (error "Fixture helper ~A is unavailable" name))
    (apply (symbol-function symbol) args)))

(defun smoke-gate-variable (name)
  (let ((symbol (find-symbol (string-upcase name) "ETHEREUM-LISP.TEST")))
    (unless (and symbol (boundp symbol))
      (error "Fixture variable ~A is unavailable" name))
    (symbol-value symbol)))

(defun smoke-gate-reject-empty-selected-root (root label)
  (when (and root
             (not (smoke-gate-call "execution-spec-tests-json-paths" root)))
    (error "Configured EEST ~A fixture root contains no JSON files: ~A"
           label
           root)))

(defun smoke-gate-pinned-default-root ()
  (let ((root (funcall *smoke-gate-environment-lookup*
                       +smoke-gate-eest-root-env+)))
    (when (or (null root)
              (zerop (length
                      (string-trim '(#\Space #\Tab #\Newline #\Return)
                                   root))))
      (error "Pinned Phase A smoke gate requires an EEST fixture root via ~A or ~A"
             +smoke-gate-root-option+
             +smoke-gate-eest-root-env+))
    (let ((resolved-root (probe-file root)))
      (unless resolved-root
        (error "Pinned Phase A smoke gate root from ~A does not exist: ~A"
               +smoke-gate-eest-root-env+
               root))
      (namestring resolved-root))))

(defun smoke-gate-suite-root (root-argument pinned-p)
  (or root-argument
      (if pinned-p
          (smoke-gate-pinned-default-root)
          +smoke-gate-default-root+)))

(defun smoke-gate-json-encode (object)
  (let ((symbol (find-symbol "JSON-ENCODE" "ETHEREUM-LISP")))
    (unless (and symbol (fboundp symbol))
      (error "JSON encoder is unavailable"))
    (funcall (symbol-function symbol) object)))

(defun smoke-gate-json-decode (string)
  (let ((symbol (find-symbol "PARSE-JSON" "ETHEREUM-LISP")))
    (unless (and symbol (fboundp symbol))
      (error "JSON parser is unavailable"))
    (funcall (symbol-function symbol) string)))

(defun smoke-gate-field (object name)
  (cdr (assoc name object :test #'string=)))

(defun smoke-gate-script-path (relative-path)
  (namestring (merge-pathnames relative-path *ethereum-lisp-smoke-gate-root*)))

(defun smoke-gate-false-p (value)
  (or (null value) (eq value :false)))

(defun smoke-gate-http-endpoint-p (value)
  (and (stringp value)
       (uiop:string-prefix-p "http://127.0.0.1:" value)))

(defun smoke-gate-root-directory ()
  (make-pathname :name nil
                 :type nil
                 :defaults *ethereum-lisp-smoke-gate-root*))

(defun smoke-gate-reference-path (relative-path)
  (merge-pathnames relative-path (smoke-gate-root-directory)))

(defun smoke-gate-reference-client-path (relative-path env-var)
  (let ((override (and env-var
                       (funcall *smoke-gate-environment-lookup* env-var))))
    (if (and override (plusp (length override)))
        (uiop:ensure-directory-pathname
         (merge-pathnames override (smoke-gate-root-directory)))
        (smoke-gate-reference-path relative-path))))

(defun smoke-gate-temp-token ()
  (format nil "~A-~A"
          #+sbcl (sb-unix:unix-getpid)
          #-sbcl "nopid"
          (gensym)))

(defun smoke-gate-temp-path (name type)
  (merge-pathnames
   (make-pathname :name (format nil "~A-~A" name (smoke-gate-temp-token))
                  :type type)
   #P"/private/tmp/"))

(defun smoke-gate-delete-file-if-present (path)
  (when (and path (probe-file path))
    (delete-file path)))

(defun smoke-gate-reference-client-object (name env-var relative-path)
  (let ((path (smoke-gate-reference-client-path relative-path env-var)))
    (cond
      ((not (probe-file path))
       (list
        (cons "name" name)
        (cons "status" "missing")
        (cons "path" (namestring path))
        (cons "commit" nil)))
      (t
       (multiple-value-bind (stdout stderr status)
           (uiop:run-program
            (list "git" "-C" (namestring path) "rev-parse" "HEAD")
            :output :string
            :error-output :string
            :ignore-error-status t)
         (declare (ignore stderr))
         (if (= 0 status)
             (list
              (cons "name" name)
              (cons "status" "ok")
              (cons "path" (namestring path))
              (cons "commit" (string-trim '(#\Space #\Tab #\Newline #\Return)
                                          stdout)))
             (list
              (cons "name" name)
              (cons "status" "unavailable")
              (cons "path" (namestring path))
              (cons "commit" nil))))))))

(defun smoke-gate-reference-clients ()
  (list
   (smoke-gate-reference-client-object
    "geth" "ETHEREUM_LISP_GETH_ROOT" "references/go-ethereum/")
   (smoke-gate-reference-client-object
    "nethermind" "ETHEREUM_LISP_NETHERMIND_ROOT" "references/nethermind/")
   (smoke-gate-reference-client-object
    "reth" "ETHEREUM_LISP_RETH_ROOT" "references/reth/")))

(defun smoke-gate-execution-spec-tests-source ()
  (list
   (cons "repository" +smoke-gate-eest-repository+)
   (cons "release" +smoke-gate-eest-release+)
   (cons "tagTarget" +smoke-gate-eest-tag-target+)
   (cons "archive" +smoke-gate-eest-archive+)))

(defun smoke-gate-kind-count (summary kind)
  (or (smoke-gate-field
       (smoke-gate-field summary "materializationKindCounts")
       kind)
      0))

(defun smoke-gate-require-positive-field (summary field label)
  (let ((value (smoke-gate-field summary field)))
    (unless (and (integerp value) (plusp value))
      (error "~A must be positive, got ~S" label value))
    value))

(defun smoke-gate-execute-state-cases (cases)
  (dolist (case cases)
    (smoke-gate-call "assert-eest-state-test-case" case))
  (length cases))

(defun smoke-gate-execute-transaction-vectors (vectors)
  (smoke-gate-call "assert-transaction-fixture-vectors-replay" vectors)
  (length vectors))

(defun smoke-gate-execute-blockchain-cases (cases)
  (dolist (source-case cases)
    (smoke-gate-call
     "assert-eest-blockchain-engine-newpayload-v2-replay"
     (smoke-gate-call
      "materialize-eest-blockchain-engine-newpayload-v2-case"
      source-case)
     :source-case source-case))
  (length cases))
