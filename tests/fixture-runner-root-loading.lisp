(in-package #:ethereum-lisp.test)

(defun eest-blockchain-test-root-json-paths (root)
  (execution-spec-tests-root-json-paths root "EEST blockchain test"))

(defun eest-blockchain-test-root-file-names (root)
  (execution-spec-tests-root-file-names root "EEST blockchain test"))

(defun eest-state-test-root-json-paths (root)
  (execution-spec-tests-root-json-paths root "EEST state test"))

(defun eest-state-test-root-file-names (root)
  (execution-spec-tests-root-file-names root "EEST state test"))

(defun validate-eest-blockchain-test-file-entries (cases source)
  (unless (listp cases)
    (error "EEST blockchain test file must be a JSON object"))
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (entry cases)
      (let ((name (car entry))
            (case (cdr entry)))
        (unless (stringp name)
          (error "EEST blockchain test case name in ~A must be a string"
                 source))
        (when (blank-string-p name)
          (error "EEST blockchain test case name in ~A must be present"
                 source))
        (when (gethash name seen)
          (error "EEST blockchain test file ~A has duplicate case name ~A"
                 source name))
        (unless (listp case)
          (error "EEST blockchain test case ~A must be a JSON object"
                 name))
        (setf (gethash name seen) t)))))

(defun validate-eest-state-test-file-entries (cases source)
  (unless (listp cases)
    (error "EEST state test file must be a JSON object"))
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (entry cases)
      (let ((name (car entry))
            (case (cdr entry)))
        (unless (stringp name)
          (error "EEST state test case name in ~A must be a string" source))
        (when (blank-string-p name)
          (error "EEST state test case name in ~A must be present" source))
        (when (gethash name seen)
          (error "EEST state test file ~A has duplicate case name ~A"
                 source
                 name))
        (unless (listp case)
          (error "EEST state test case ~A must be a JSON object" name))
        (validate-fixture-object-fields
         case
         +eest-state-test-case-fields+
         (format nil "EEST state test case ~A" name))
        (dolist (field '("env" "pre" "transaction" "post"))
          (fixture-required-field case field))
        (setf (gethash name seen) t)))))

(defun normalize-eest-blockchain-test-case (name case)
  (list (cons "name" name)
        (cons "fixture" case)))

(defun normalize-eest-state-test-case (name case)
  (list (cons "name" name)
        (cons "fixture" case)))

(defun eest-blockchain-root-case-name (root path key singleton-p)
  (execution-spec-tests-root-case-name root path key singleton-p))

(defun eest-state-root-case-name (root path key singleton-p)
  (execution-spec-tests-root-case-name root path key singleton-p))

(defun load-eest-blockchain-test-root-file-cases (root path)
  (let* ((cases (load-handwritten-fixture-file path))
         (source (enough-namestring (truename path) (truename root))))
    (validate-eest-blockchain-test-file-entries cases source)
    (let* ((entries (sort (copy-list cases) #'string< :key #'car))
           (singleton-p (= 1 (length entries))))
      (mapcar
       (lambda (entry)
         (let ((source-name
                 (eest-blockchain-root-case-name
                  root
                  path
                  (car entry)
                  singleton-p)))
           (unless (eest-blockchain-selector-source-style-p source-name)
             (error "EEST blockchain source name ~A must be source-style"
                    source-name))
           (normalize-eest-blockchain-test-case source-name (cdr entry))))
       entries))))

(defun load-eest-state-test-root-file-cases (root path)
  (let* ((cases (load-handwritten-fixture-file path))
         (source (enough-namestring (truename path) (truename root))))
    (validate-eest-state-test-file-entries cases source)
    (let* ((entries (sort (copy-list cases) #'string< :key #'car))
           (singleton-p (= 1 (length entries))))
      (mapcar
       (lambda (entry)
         (let ((source-name
                 (eest-state-root-case-name root path (car entry) singleton-p)))
           (unless (eest-state-selector-source-style-p source-name)
             (error "EEST state source name ~A must be source-style"
                    source-name))
           (normalize-eest-state-test-case source-name (cdr entry))))
       entries))))

(defun eest-selector-relative-json-path (name label)
  (let ((json-position (search ".json" name :test #'char-equal)))
    (unless json-position
      (error "~A selector ~A must include a JSON file" label name))
    (subseq name 0 (+ json-position 5))))

(defun eest-selector-root-paths (root names label)
  (let ((seen (make-hash-table :test 'equal))
        (paths nil))
    (dolist (name names (nreverse paths))
      (let* ((relative (eest-selector-relative-json-path name label))
             (path (merge-pathnames relative root)))
        (unless (probe-file path)
          (error "~A selector ~A references missing fixture file ~A"
                 label name relative))
        (unless (gethash relative seen)
          (setf (gethash relative seen) t)
          (push path paths))))))

(defun eest-selector-source-style-name-p (name)
  "Whether NAME is a usable EEST selector: <relative>.json[/<case id>].

The traversal guards apply to the path PREFIX and only to it, because that is
the only part MERGE-PATHNAMES ever sees -- EEST-SELECTOR-RELATIVE-JSON-PATH cuts
the name at its first `.json'. The case id after that is a pytest node id, i.e.
arbitrary parametrization text, and real fixtures contain ids like
`test_bad_v_r_s[...-s=SECP256K1N//2+1]'. Refusing those for containing `//'
would drop genuine vectors out of discovery with no trace, which is the silent
gap this whole selector layer exists to prevent."
  (and (stringp name)
       (not (blank-string-p name))
       (let* ((json-position (search ".json" name :test #'char-equal))
              (after-json (and json-position (+ json-position 5))))
         (and json-position
              (plusp json-position)
              (not (char= (char name (1- json-position)) #\/))
              (let ((path (subseq name 0 after-json)))
                (and (not (char= (char path 0) #\/))
                     (null (search ".." path))
                     (null (search "//" path))))
              (or (= after-json (length name))
                  (and (< after-json (length name))
                       (char= (char name after-json) #\/)
                       (< (1+ after-json) (length name))))))))

(defun validate-eest-selector-list (names label)
  (unless (listp names)
    (error "~A selector list must be a list" label))
  (unless names
    (error "~A selector list must not be empty" label))
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (name names)
      (unless (stringp name)
        (error "~A selector name must be a string" label))
      (when (blank-string-p name)
        (error "~A selector name must be present" label))
      (unless (eest-selector-source-style-name-p name)
        (error "~A selector ~A must be a source-style JSON case name"
               label name))
      (when (gethash name seen)
        (error "~A selector list has duplicate name ~A" label name))
      (setf (gethash name seen) t))))

(defun validate-eest-blockchain-selector-list (names)
  (validate-eest-selector-list names "EEST blockchain"))

(defun validate-eest-state-selector-list (names)
  (validate-eest-selector-list names "EEST state"))

(defun eest-blockchain-selector-source-style-p (name)
  (eest-selector-source-style-name-p name))

(defun eest-state-selector-source-style-p (name)
  (eest-selector-source-style-name-p name))

(defun load-eest-blockchain-test-root-cases (root &key names)
  (when names
    (validate-eest-blockchain-selector-list names))
  (filter-execution-spec-tests-root-cases
   (loop for path in (if names
                         (eest-selector-root-paths
                          root names "EEST blockchain test")
                         (eest-blockchain-test-root-json-paths root))
         append (load-eest-blockchain-test-root-file-cases root path))
   names
   "EEST blockchain test"))

(defun load-eest-state-test-root-cases (root &key names)
  (when names
    (validate-eest-state-selector-list names))
  (filter-execution-spec-tests-root-cases
   (loop for path in (if names
                         (eest-selector-root-paths root names "EEST state test")
                         (eest-state-test-root-json-paths root))
         append (load-eest-state-test-root-file-cases root path))
   names
   "EEST state test"))

(defun eest-fixture-discovery-directories (root path)
  "Split PATH's position under ROOT into (VALUES network-directory feature).

A `for_<network>/' first component is the stable corpus stating the fork in the
path; NETWORK-DIRECTORY is then the bare network name and FEATURE is the tree
below it. The legacy layout has no such prefix, so NETWORK-DIRECTORY is NIL and
the fork is only knowable from the fixture body."
  (let* ((relative (enough-namestring (truename path) (truename root)))
         (slash (position #\/ relative))
         (first-directory (if slash (subseq relative 0 slash) relative))
         (prefix-length (length +eest-fixture-network-directory-prefix+)))
    (if (and slash
             (eql 0 (search +eest-fixture-network-directory-prefix+
                            first-directory))
             (> (length first-directory) prefix-length))
        (let* ((remainder (subseq relative (1+ slash)))
               (next (position #\/ remainder)))
          (values (subseq first-directory prefix-length)
                  (if next (subseq remainder 0 next) remainder)))
        (values nil first-directory))))

(defun execution-spec-tests-discovery-path-p
    (root path feature-directories max-file-bytes networks)
  "Whether PATH is a fixture file this run should open at all.

On a `for_<network>/' corpus the fork gate applies to the path, so a run
configured for Shanghai never descends into a Cancun tree and never parses a
byte of it. On the legacy layout there is no fork in the path and the gate stays
where it always was, on the loaded case's network field."
  (multiple-value-bind (network-directory feature-directory)
      (eest-fixture-discovery-directories root path)
    (and (member (string-downcase feature-directory)
                 feature-directories
                 :test #'string=)
         (or (null network-directory)
             (member network-directory networks :test #'string-equal))
         (<= (eest-fixture-file-byte-size path) max-file-bytes))))

(defun phase-a-eest-blockchain-replay-discovery-path-p (root path)
  (execution-spec-tests-discovery-path-p
   root
   path
   (phase-a-eest-blockchain-replay-active-feature-directories)
   +phase-a-eest-blockchain-replay-discovery-max-file-bytes+
   (phase-a-eest-blockchain-replay-supported-networks)))

(defun phase-a-eest-state-test-discovery-path-p (root path)
  (execution-spec-tests-discovery-path-p
   root
   path
   +phase-a-eest-state-test-discovery-feature-directories+
   +phase-a-eest-state-test-discovery-max-file-bytes+
   (phase-a-eest-state-test-supported-forks)))

(defun eest-fixture-file-byte-size (path)
  (with-open-file (stream path :direction :input
                               :element-type '(unsigned-byte 8))
    (file-length stream)))

;;; Discovery streams. One active fork's engine tree is a few thousand cases and
;;; each carries a full pre-state and payload, so materializing the whole
;;; discovered set at once exhausts the heap the moment
;;; ETHEREUM_LISP_PHASE_A_BLOCKCHAIN_REPLAY_FORKS names more than one network --
;;; and it dies without a manifest, which is the report that was supposed to
;;; explain what ran. Every caller here only needs a small summary per case, so
;;; the file's cases are handed over and dropped one file at a time.

(defun map-phase-a-eest-blockchain-discovery-cases (function root)
  (loop for path in (eest-blockchain-test-root-json-paths root)
        when (phase-a-eest-blockchain-replay-discovery-path-p root path)
          do (dolist (case (load-eest-blockchain-test-root-file-cases
                            root path))
               (funcall function case))))

(defun load-phase-a-eest-blockchain-discovery-cases (root)
  (let ((cases '()))
    (map-phase-a-eest-blockchain-discovery-cases
     (lambda (case) (push case cases))
     root)
    (nreverse cases)))

(defun map-phase-a-eest-state-discovery-cases (function root)
  (loop for path in (eest-state-test-root-json-paths root)
        when (and
              (phase-a-eest-state-test-discovery-path-p root path)
              ;; On the legacy layout the top directory doubles as the fork
              ;; name, and reading it that way is the only fork signal a path
              ;; carries. A `for_<fork>/' corpus states it outright and the
              ;; discovery predicate has already applied the same gate.
              (multiple-value-bind (network-directory feature-directory)
                  (eest-fixture-discovery-directories root path)
                (or network-directory
                    (member feature-directory
                            (phase-a-eest-state-test-supported-forks)
                            :test #'string-equal))))
          do (dolist (case (load-eest-state-test-root-file-cases root path))
               (funcall function case))))

(defun load-phase-a-eest-state-discovery-cases (root)
  (let ((cases '()))
    (map-phase-a-eest-state-discovery-cases
     (lambda (case) (push case cases))
     root)
    (nreverse cases)))

(defun eest-state-test-case-fork-names (case)
  (let ((post (fixture-required-field
               (fixture-required-field case "fixture")
               "post")))
    (unless (listp post)
      (error "EEST state test case ~A post must be a JSON object"
             (fixture-required-field case "name")))
    (sort (mapcar #'car post) #'string<)))

(defun eest-state-test-transaction-combination-count (case)
  (let ((transaction (fixture-required-field
                      (fixture-required-field case "fixture")
                      "transaction")))
    (validate-fixture-object-fields
     transaction
     +eest-state-test-transaction-fields+
     (format nil "EEST state test case ~A transaction"
             (fixture-required-field case "name")))
    (dolist (field '("data" "gasLimit" "value"))
      (let ((values (fixture-required-field transaction field)))
        (unless (and (listp values) values)
          (error "EEST state test case ~A transaction ~A must be a non-empty JSON array"
                 (fixture-required-field case "name")
                 field))))
    (let ((access-lists (fixture-object-field transaction "accessLists")))
      (when (fixture-field-present-p transaction "accessLists")
        (unless (and (listp access-lists) access-lists)
          (error "EEST state test case ~A transaction accessLists must be a non-empty JSON array"
                 (fixture-required-field case "name"))))
      (* (length (fixture-required-field transaction "data"))
         (length (fixture-required-field transaction "gasLimit"))
         (length (fixture-required-field transaction "value"))
         (if (fixture-field-present-p transaction "accessLists")
             (length access-lists)
             1)))))

(defun phase-a-eest-state-materializable-case-p (case)
  (handler-case
      (and (intersection (phase-a-eest-state-test-supported-forks)
                         (eest-state-test-case-fork-names case)
                         :test #'string=)
           (plusp (eest-state-test-transaction-combination-count case)))
    (error () nil)))

(defun discover-phase-a-eest-state-test-selectors (root)
  (let ((selectors '()))
    (map-phase-a-eest-state-discovery-cases
     (lambda (case)
       (when (phase-a-eest-state-materializable-case-p case)
         (push (fixture-required-field case "name") selectors)))
     root)
    (nreverse selectors)))

(defun eest-state-test-root-summary (cases)
  (let ((fork-counts (make-hash-table :test 'equal))
        (combination-count 0))
    (dolist (case cases)
      (dolist (fork (eest-state-test-case-fork-names case))
        (incf (gethash fork fork-counts 0)))
      (incf combination-count
            (eest-state-test-transaction-combination-count case)))
    (list
     (cons "count" (length cases))
     (cons "names" (mapcar (lambda (case)
                             (fixture-required-field case "name"))
                           cases))
     (cons "forkCounts"
           (sort
            (loop for key being the hash-keys of fork-counts
                  using (hash-value count)
                  collect (cons key count))
            #'string<
            :key #'car))
     (cons "transactionCombinationCount" combination-count))))

(defun report-eest-state-test-root-case (case)
  (list (cons "name" (fixture-required-field case "name"))
        (cons "forks" (eest-state-test-case-fork-names case))
        (cons "transactionCombinations"
              (eest-state-test-transaction-combination-count case))))

(defun eest-fixture-trim-string (value)
  (string-trim '(#\Space #\Tab #\Newline #\Return) value))

(defun eest-fixture-split-string (value delimiter)
  (let ((parts '())
        (start 0))
    (loop
      for position = (position delimiter value :start start)
      do (push (subseq value start position) parts)
      if position
        do (setf start (1+ position))
      else
        do (return (nreverse parts)))))

(defun phase-a-eest-state-test-supported-forks ()
  (let ((value
          (funcall *fixture-root-environment-reader*
                   +phase-a-eest-state-test-forks-env+)))
    (if (or (null value) (blank-string-p value))
        (copy-list +phase-a-eest-state-test-supported-forks+)
        (let ((forks
                (remove-if
                 #'blank-string-p
                 (mapcar #'eest-fixture-trim-string
                         (eest-fixture-split-string value #\,)))))
          (unless forks
            (error "~A must name at least one fork"
                   +phase-a-eest-state-test-forks-env+))
          forks))))

(defun phase-a-eest-blockchain-replay-supported-networks ()
  "The networks a materialized replay case may carry, from the fork env var or
the Shanghai default. This gates both discovery (which late-fork trees to open)
and validation (which networks a loaded case may report)."
  (let ((value
          (funcall *fixture-root-environment-reader*
                   +phase-a-eest-blockchain-replay-forks-env+)))
    (if (or (null value) (blank-string-p value))
        (copy-list +phase-a-eest-blockchain-replay-supported-networks+)
        (let ((networks
                (remove-if
                 #'blank-string-p
                 (mapcar #'eest-fixture-trim-string
                         (eest-fixture-split-string value #\,)))))
          (unless networks
            (error "~A must name at least one network"
                   +phase-a-eest-blockchain-replay-forks-env+))
          networks))))

(defun phase-a-eest-blockchain-replay-active-feature-directories ()
  "The pre-Shanghai..Shanghai feature trees plus one late-fork tree per active
network. With the Shanghai default this is exactly the base set, so discovery
never descends into an unsupported-fork directory."
  (let ((networks (phase-a-eest-blockchain-replay-supported-networks)))
    (append
     +phase-a-eest-blockchain-replay-discovery-feature-directories+
     (loop for (network . directory)
             in +phase-a-eest-blockchain-replay-late-fork-directories+
           when (member network networks :test #'string=)
             collect directory))))

(defun parse-phase-a-eest-state-test-selectors (value)
  (unless (stringp value)
    (error "Phase A EEST state test selectors must be a string"))
  (when (blank-string-p value)
    (return-from parse-phase-a-eest-state-test-selectors nil))
  (let ((selectors
          (mapcar #'eest-fixture-trim-string
                  (eest-fixture-split-string value #\,))))
    (validate-eest-state-selector-list selectors)
    selectors))

(defun phase-a-eest-state-test-env-selectors (&optional root)
  (let ((value (funcall *fixture-root-environment-reader*
                        +phase-a-eest-state-test-selectors-env+)))
    (cond
      ((null value) nil)
      ((not (stringp value))
       (error "~A must be a string" +phase-a-eest-state-test-selectors-env+))
      ((blank-string-p value) nil)
      ((string= +phase-a-eest-state-test-auto-selector+
                (string-downcase (eest-fixture-trim-string value)))
       (unless root
         (error "~A=auto requires an EEST state_tests root"
                +phase-a-eest-state-test-selectors-env+))
       (let ((selectors (discover-phase-a-eest-state-test-selectors root)))
         (unless selectors
           (error "~A=auto found no materializable Phase A state_tests selectors"
                  +phase-a-eest-state-test-selectors-env+))
         selectors))
      (t
       (parse-phase-a-eest-state-test-selectors value)))))

(defun phase-a-eest-state-test-selector-string (selectors &key limit)
  (validate-eest-state-selector-list selectors)
  (let ((bounded-selectors
          (if (and limit (> (length selectors) limit))
              (subseq selectors 0 limit)
              selectors)))
    (format nil "~{~A~^,~}" bounded-selectors)))

(defun validate-phase-a-eest-state-test-summary
    (cases &key (expected-names +phase-a-eest-state-test-case-names+))
  (validate-eest-state-selector-list expected-names)
  (unless (and (listp cases) cases)
    (error "Phase A EEST state_tests cases must be a non-empty list"))
  (let* ((summary (eest-state-test-root-summary cases))
         (count (fixture-required-field summary "count"))
         (names (fixture-required-field summary "names"))
         (combination-count
           (fixture-required-field summary "transactionCombinationCount")))
    (unless (= count (length expected-names))
      (error "Phase A EEST state_tests selector count ~A loaded ~A cases"
             (length expected-names)
             count))
    (unless (equal names expected-names)
      (error "Phase A EEST state_tests names ~S do not match selectors ~S"
             names
             expected-names))
    (dolist (case cases)
      (unless (intersection (phase-a-eest-state-test-supported-forks)
                            (eest-state-test-case-fork-names case)
                            :test #'string=)
        (error "Phase A EEST state_tests case ~A has no supported fork"
               (fixture-required-field case "name"))))
    (unless (plusp combination-count)
      (error "Phase A EEST state_tests replay must include transaction combinations"))
    summary))

(defun load-phase-a-eest-state-test-root-cases
    (root &key (expected-names +phase-a-eest-state-test-case-names+))
  (let ((cases (load-eest-state-test-root-cases
                root
                :names expected-names)))
    (validate-phase-a-eest-state-test-summary
     cases
     :expected-names expected-names)
    cases))

(defun load-optional-phase-a-eest-state-test-root-cases ()
  (with-execution-spec-tests-state-test-root (root)
    (let ((expected-names (phase-a-eest-state-test-env-selectors root)))
      (unless expected-names
        (let ((candidates (discover-phase-a-eest-state-test-selectors root)))
          (skip-test
           (if candidates
               (format nil
                       "Set ~A to auto or comma-separated selectors such as ~A to run Phase A state_tests replay against this external root"
                       +phase-a-eest-state-test-selectors-env+
                       (phase-a-eest-state-test-selector-string
                        candidates
                        :limit 10))
               (format nil
                       "Set ~A to comma-separated selectors to run Phase A state_tests replay against an external root"
                       +phase-a-eest-state-test-selectors-env+)))))
      (load-phase-a-eest-state-test-root-cases
       root
       :expected-names expected-names))))

(defun parse-phase-a-eest-blockchain-replay-selector (value)
  (let* ((selector (eest-fixture-trim-string value))
         (separator (position #\= selector)))
    (unless separator
      (error "Phase A EEST blockchain replay selector ~A must use name=kind"
             selector))
    (let ((name (eest-fixture-trim-string
                 (subseq selector 0 separator)))
          (kind (eest-fixture-trim-string
                 (subseq selector (1+ separator)))))
      (validate-eest-blockchain-selector-list (list name))
      (unless (member kind
                      +phase-a-eest-blockchain-replay-materialization-kind-names+
                      :test #'string=)
        (error "Phase A EEST blockchain replay selector ~A has unsupported materialization kind ~A"
               name
               kind))
      (cons name kind))))

(defun parse-phase-a-eest-blockchain-replay-selectors (value)
  (unless (stringp value)
    (error "Phase A EEST blockchain replay selectors must be a string"))
  (when (blank-string-p value)
    (return-from parse-phase-a-eest-blockchain-replay-selectors nil))
  (let ((selectors
          (mapcar #'parse-phase-a-eest-blockchain-replay-selector
                  (eest-fixture-split-string value #\,))))
    (validate-eest-blockchain-selector-list (mapcar #'car selectors))
    selectors))

(defun phase-a-eest-blockchain-replay-env-materialization-kinds
    (&optional root)
  (let ((value (funcall *fixture-root-environment-reader*
                        +phase-a-eest-blockchain-replay-selectors-env+)))
    (cond
      ((null value) nil)
      ((not (stringp value))
       (error "~A must be a string"
              +phase-a-eest-blockchain-replay-selectors-env+))
      ((blank-string-p value) nil)
      ((string= +phase-a-eest-blockchain-replay-auto-selector+
                (string-downcase (eest-fixture-trim-string value)))
       (unless root
         (error "~A=auto requires an EEST blockchain root"
                +phase-a-eest-blockchain-replay-selectors-env+))
       (let ((selectors
               (discover-phase-a-eest-blockchain-replay-selectors root)))
         (unless selectors
           (error "~A=auto found no materializable Phase A blockchain replay selectors"
                  +phase-a-eest-blockchain-replay-selectors-env+))
         selectors))
      ((string= +phase-a-eest-blockchain-replay-pinned-selector+
                (string-downcase (eest-fixture-trim-string value)))
       (unless root
         (error "~A=~A requires an EEST blockchain root"
                +phase-a-eest-blockchain-replay-selectors-env+
                +phase-a-eest-blockchain-replay-pinned-selector+))
       (phase-a-eest-blockchain-pinned-v5.4.0-replay-materialization-kinds
        root))
      (t
       (parse-phase-a-eest-blockchain-replay-selectors value)))))

(defun phase-a-eest-blockchain-replay-selector-string
    (selectors &key limit)
  (validate-eest-blockchain-selector-list (mapcar #'car selectors))
  (let* ((bounded-selectors
           (if (and limit (> (length selectors) limit))
               (subseq selectors 0 limit)
               selectors))
         (entries
           (mapcar (lambda (selector)
                     (format nil "~A=~A" (car selector) (cdr selector)))
                   bounded-selectors)))
    (format nil "~{~A~^,~}" entries)))

(defun eest-transition-network-p (network)
  "Whether NETWORK names a fork TRANSITION rather than one ruleset.

EEST spells these `<From>To<To>AtTime<N>' (ShanghaiToCancunAtTime15k,
OsakaToBPO1AtTime15k). They are not a fork the replay path can run: the whole
point of the vector is a chain that crosses an activation boundary, so it has no
single ruleset and, in this corpus, almost always more than one payload."
  (and (stringp network)
       (search "To" network)
       (some (lambda (infix) (search infix network))
             +eest-transition-network-infixes+)
       t))

(defun eest-blockchain-engine-newpayloads-entries (case)
  (let ((entries (fixture-object-field
                  (fixture-required-field case "fixture")
                  "engineNewPayloads")))
    (when (listp entries)
      entries)))

(defun eest-blockchain-engine-newpayloads-single-entry (case)
  "CASE's only engineNewPayloads entry, or NIL when the chain is not one block.

The replay harness builds one child on top of the fixture genesis, so a vector
that feeds several payloads has no representation here. Returning NIL rather
than the first entry is what keeps a multi-block chain from being scored as if
its first block were the whole test."
  (let ((entries (eest-blockchain-engine-newpayloads-entries case)))
    (when (and entries (null (rest entries)) (listp (first entries)))
      (first entries))))

(defun eest-blockchain-engine-newpayload-version (entry)
  (and (listp entry)
       (fixture-object-field entry "newPayloadVersion")))

(defun eest-blockchain-engine-newpayload-kind-name (version)
  (let ((kind (format nil "engineNewPayloadV~A" version)))
    (when (member kind
                  +phase-a-eest-blockchain-replay-materialization-kind-names+
                  :test #'string=)
      kind)))

(defun eest-blockchain-case-rejection-expectation (case)
  "The refusal CASE demands, or NIL when it expects the payload to be accepted.

A validationError is the spec exception the payload must be rejected for; an
errorCode is a JSON-RPC error the Engine method itself must return (an
unsupported-fork payload, for instance). Either makes this an invalid-payload
vector, which the replay path cannot express because it derives its expectation
by executing the block."
  (let ((entry (eest-blockchain-engine-newpayloads-single-entry case)))
    (when entry
      (let ((validation-error (fixture-object-field entry "validationError"))
            (error-code (fixture-object-field entry "errorCode")))
        (when (or validation-error error-code)
          (list (cons "validationError" validation-error)
                (cons "errorCode" error-code)))))))

(defun eest-blockchain-case-invalid-p (case)
  "Whether CASE is an invalid vector, whatever shape it takes.

Broader than EEST-BLOCKCHAIN-CASE-REJECTION-EXPECTATION, which only speaks for
single-payload vectors this build can submit: a multi-payload chain whose third
payload must be refused is still an invalid vector and has to be counted on the
validity axis even though nothing executes it."
  (or (and (eest-blockchain-case-exception case) t)
      (and (some (lambda (entry)
                   (and (listp entry)
                        (or (fixture-object-field entry "validationError")
                            (fixture-object-field entry "errorCode"))))
                 (eest-blockchain-engine-newpayloads-entries case))
           t)))

(defun eest-blockchain-replay-materialization-kind (case)
  (let ((fixture (fixture-required-field case "fixture"))
        (entry (eest-blockchain-engine-newpayloads-single-entry case)))
    (cond
      ((fixture-field-present-p fixture "engineNewPayloadV2")
       "engineNewPayloadV2")
      (entry
       (or (eest-blockchain-engine-newpayload-kind-name
            (eest-blockchain-engine-newpayload-version entry))
           "unsupported"))
      ((and (fixture-field-present-p fixture "engineNewPayloads")
            (eest-blockchain-engine-newpayloads-v2-entry case))
       "engineNewPayloadV2")
      ((let ((blocks (fixture-object-field fixture "blocks")))
         (and (listp blocks)
              blocks
              (fixture-field-present-p (first blocks) "rlp")))
       "blockRlp")
      (t
       "unsupported"))))

(defun phase-a-eest-blockchain-late-payload-case-p (case)
  "Whether CASE is a Cancun-or-later payload the late-payload test submits.

The two replay tests partition the selector list on this predicate -- the
late-payload test takes these, the V2 replay test takes the complement -- so
neither can double-cover a case and neither can drop one."
  (and (member (eest-blockchain-replay-materialization-kind case)
               +phase-a-eest-blockchain-late-payload-kind-names+
               :test #'string=)
       t))

(defun phase-a-eest-blockchain-late-payload-cases (cases)
  (remove-if-not #'phase-a-eest-blockchain-late-payload-case-p cases))

(defun phase-a-eest-blockchain-non-late-payload-cases (cases)
  (remove-if #'phase-a-eest-blockchain-late-payload-case-p cases))

(defun phase-a-eest-blockchain-replay-skip-category (case)
  "Why CASE is not in the replay set, as a name the count manifest can report.

Every discovered case that does not execute must land in one of these buckets.
An unnamed skip is the failure mode plan section 2 exists to remove: a corpus
mounted, a fork claimed, and nothing run."
  (handler-case
      (let* ((fixture (fixture-required-field case "fixture"))
             (network (fixture-object-field fixture "network"))
             (entries (eest-blockchain-engine-newpayloads-entries case)))
        (cond
          ((not (stringp network)) "missingNetwork")
          ((eest-transition-network-p network) "transitionNetwork")
          ((not (member network
                        (phase-a-eest-blockchain-replay-supported-networks)
                        :test #'string=))
           "unsupportedNetwork")
          ((eest-blockchain-case-rejection-expectation case) "invalidPayload")
          ((and entries (rest entries)) "multiPayloadChain")
          ((string= "unsupported"
                    (eest-blockchain-replay-materialization-kind case))
           "unsupportedPayloadVersion")
          (t "unmaterializableShape")))
    (error () "unreadableFixture")))

(defun phase-a-eest-blockchain-replay-materializable-kind (case)
  "CASE's replay kind, or NIL, plus the skip category when it is NIL.

Only vectors that expect ACCEPTANCE belong here: the replay harness derives what
it asserts by executing the block, so a payload the node is supposed to refuse
has no expectation it could produce. Those go to the rejection set instead,
where the refusal itself is the assertion."
  (let ((kind
          (handler-case
              (let* ((fixture (fixture-required-field case "fixture"))
                     (network (fixture-object-field fixture "network"))
                     (kind (eest-blockchain-replay-materialization-kind case)))
                (when (and (stringp network)
                           (member
                            network
                            (phase-a-eest-blockchain-replay-supported-networks)
                            :test #'string=)
                           (not (eest-blockchain-case-rejection-expectation
                                 case)))
                  (cond
                    ((string= "engineNewPayloadV2" kind)
                     (if (fixture-field-present-p fixture "engineNewPayloadV2")
                         (validate-eest-blockchain-engine-newpayload-v2-case
                          case)
                         (validate-eest-blockchain-engine-newpayloads-v2-case
                          case))
                     kind)
                    ((or (string= "engineNewPayloadV3" kind)
                         (string= "engineNewPayloadV4" kind))
                     (validate-eest-blockchain-engine-newpayloads-late-case
                      case)
                     kind)
                    ((string= "blockRlp" kind)
                     (validate-eest-blockchain-standard-newpayload-v2-case case)
                     kind)
                    (t nil))))
            (error () nil))))
    (values kind
            (unless kind
              (phase-a-eest-blockchain-replay-skip-category case)))))

(defun phase-a-eest-blockchain-rejection-kind (case)
  "CASE's kind when it is an invalid-payload vector this build can submit.

Same network gate as the replay set, so widening the fork env is still the only
way new execution appears; the difference is what gets asserted."
  (handler-case
      (let* ((fixture (fixture-required-field case "fixture"))
             (network (fixture-object-field fixture "network")))
        (when (and (stringp network)
                   (member network
                           (phase-a-eest-blockchain-replay-supported-networks)
                           :test #'string=)
                   (eest-blockchain-case-rejection-expectation case))
          (let ((kind (eest-blockchain-engine-newpayload-kind-name
                       (eest-blockchain-engine-newpayload-version
                        (eest-blockchain-engine-newpayloads-single-entry
                         case)))))
            (when (and kind
                       (member kind +phase-a-eest-blockchain-rejection-kind-names+
                               :test #'string=))
              (validate-eest-blockchain-engine-newpayloads-rejection-case case)
              kind))))
    (error () nil)))

;;; Standard RLP blocks.
;;;
;;; The engine tree and the standard tree hold the SAME test ids filled in two
;;; formats, so their relative case names collide and they cannot be merged into
;;; one selector namespace. They are therefore a second family, resolved against
;;; their own root and counted separately -- which is also what lets the format
;;; axis report a real blockchain_test number instead of only what the in-tree
;;; fixture root happens to contain.

(defun phase-a-eest-blockchain-rlp-test-root ()
  "The standard blockchain_tests/ root, or NIL when the replay family owns it.

A corpus that ships only one blockchain tree resolves both families to the same
directory; running the standard family over it as well would count and execute
every case twice."
  (let ((rlp-root (execution-spec-tests-blockchain-rlp-test-root))
        (replay-root (execution-spec-tests-blockchain-test-root)))
    (when (and rlp-root
               (or (null replay-root)
                   (not (equal (namestring (truename rlp-root))
                               (namestring (truename replay-root))))))
      rlp-root)))

(defun eest-blockchain-standard-newpayload-version (network)
  "The Engine method a block from NETWORK must be submitted through, or NIL.

Prague and Osaka answer NIL unless the caller can show the block carries no
execution requests: newPayloadV4 takes them as a parameter and a block RLP does
not contain them, only their hash. Guessing an empty list for a block that had
requests would submit a call the fixture never described and score whatever came
back, so those cases are refused here and counted as a named skip instead."
  (cond
    ((string= "Shanghai" network) "2")
    ((string= "Cancun" network) "3")
    ((member network '("Prague" "Osaka") :test #'string=) "4")
    (t nil)))

(defun phase-a-eest-blockchain-rlp-supported-networks ()
  "The configured networks whose standard blocks this build can submit at all.

Transitions drop out because they have no single Engine version. Prague and
Osaka stay: whether a block is submittable there is a per-case fact about
whether it carries execution requests, and the ones that do are counted by name
rather than removed from the fork the run claims."
  (remove-if-not #'eest-blockchain-standard-newpayload-version
                 (phase-a-eest-blockchain-replay-supported-networks)))

(defun eest-blockchain-standard-requests-recoverable-p (block)
  (let ((requests-hash (block-header-requests-hash (block-header block))))
    (or (null requests-hash)
        (equalp (hash32-bytes requests-hash)
                (hash32-bytes (execution-requests-hash '()))))))

(defun phase-a-eest-blockchain-rlp-submittable-p (case)
  "Whether this build can submit CASE's block as an Engine payload at all."
  (handler-case
      (let* ((fixture (fixture-required-field case "fixture"))
             (network (fixture-object-field fixture "network"))
             (version (and (stringp network)
                           (member network
                                   (phase-a-eest-blockchain-replay-supported-networks)
                                   :test #'string=)
                           (eest-blockchain-standard-newpayload-version
                            network))))
        (and version
             (let ((block (validate-eest-blockchain-standard-newpayload-v2-case
                           case)))
               (or (not (string= "4" version))
                   (eest-blockchain-standard-requests-recoverable-p block)))))
    (error () nil)))

(defun phase-a-eest-blockchain-rlp-acceptance-kind (case)
  (when (and (not (eest-blockchain-case-invalid-p case))
             (phase-a-eest-blockchain-rlp-submittable-p case))
    "blockRlp"))

(defun phase-a-eest-blockchain-rlp-rejection-kind (case)
  (when (and (eest-blockchain-case-invalid-p case)
             (phase-a-eest-blockchain-rlp-submittable-p case))
    "blockRlp"))

(defun phase-a-eest-blockchain-rlp-skip-category (case)
  (handler-case
      (let* ((fixture (fixture-required-field case "fixture"))
             (network (fixture-object-field fixture "network"))
             (blocks (fixture-object-field fixture "blocks")))
        (cond
          ((not (stringp network)) "missingNetwork")
          ((eest-transition-network-p network) "transitionNetwork")
          ((not (member network
                        (phase-a-eest-blockchain-replay-supported-networks)
                        :test #'string=))
           "unsupportedNetwork")
          ((not (and (listp blocks) (= 1 (length blocks)))) "multiBlockChain")
          ((null (eest-blockchain-standard-newpayload-version network))
           "unsupportedPayloadVersion")
          ((not (phase-a-eest-blockchain-rlp-submittable-p case))
           "requestsNotInBlockRlp")
          (t "unmaterializableShape")))
    (error () "unreadableFixture")))

(defun discover-phase-a-eest-blockchain-rlp-selectors (root)
  (let ((selectors '()))
    (map-phase-a-eest-blockchain-discovery-cases
     (lambda (case)
       (let ((kind (or (phase-a-eest-blockchain-rlp-acceptance-kind case)
                       (phase-a-eest-blockchain-rlp-rejection-kind case))))
         (when kind
           (push (cons (fixture-required-field case "name") kind) selectors))))
     root)
    (nreverse selectors)))

(defun load-optional-phase-a-eest-blockchain-rlp-cases ()
  "The standard RLP vectors this run should submit, or a skip.

Keyed on the replay selector env's `auto' setting, like the rejection set: an
explicit selector list names engine cases and cannot say which standard blocks
to run."
  (let ((root (phase-a-eest-blockchain-rlp-test-root)))
    (unless root
      (skip-test
       (format nil
               "Set ~A to a fixture root whose blockchain_tests tree is distinct from its engine tree to run Phase A standard RLP replay"
               +execution-spec-tests-fixture-root-env+)))
    (let ((value (funcall *fixture-root-environment-reader*
                          +phase-a-eest-blockchain-replay-selectors-env+)))
      (unless (and (stringp value)
                   (string= +phase-a-eest-blockchain-replay-auto-selector+
                            (string-downcase
                             (eest-fixture-trim-string value))))
        (skip-test
         (format nil
                 "Set ~A to ~A to run Phase A standard RLP replay against this external root"
                 +phase-a-eest-blockchain-replay-selectors-env+
                 +phase-a-eest-blockchain-replay-auto-selector+)))
      (let ((selectors (discover-phase-a-eest-blockchain-rlp-selectors root)))
        (unless selectors
          (skip-test
           (format nil
                   "This EEST blockchain_tests root carries no submittable standard RLP blocks for the networks ~A selects"
                   +phase-a-eest-blockchain-replay-forks-env+)))
        (load-eest-blockchain-test-root-cases
         root
         :names (mapcar #'car selectors))))))

(defun discover-phase-a-eest-blockchain-rejection-selectors (root)
  (let ((selectors '()))
    (map-phase-a-eest-blockchain-discovery-cases
     (lambda (case)
       (let ((kind (phase-a-eest-blockchain-rejection-kind case)))
         (when kind
           (push (cons (fixture-required-field case "name") kind) selectors))))
     root)
    (nreverse selectors)))

(defun discover-phase-a-eest-blockchain-replay-selectors (root)
  (let ((selectors '()))
    (map-phase-a-eest-blockchain-discovery-cases
     (lambda (case)
       (let ((kind (phase-a-eest-blockchain-replay-materializable-kind case)))
         (when kind
           (push (cons (fixture-required-field case "name") kind) selectors))))
     root)
    (nreverse selectors)))

(defun validate-phase-a-eest-blockchain-discovered-replay-selectors
    (root expected-kinds)
  (validate-eest-blockchain-selector-list (mapcar #'car expected-kinds))
  (let ((discovered (discover-phase-a-eest-blockchain-replay-selectors root)))
    (unless (equal discovered expected-kinds)
      (error "Discovered Phase A EEST blockchain replay selectors ~S do not match pinned selectors ~S"
             discovered
             expected-kinds))
    discovered))

(defun phase-a-eest-blockchain-pinned-v5.4.0-replay-materialization-kinds
    (root)
  (declare (ignore root))
  (validate-eest-blockchain-selector-list
   (mapcar #'car +phase-a-eest-blockchain-v5.4.0-replay-materialization-kinds+))
  +phase-a-eest-blockchain-v5.4.0-replay-materialization-kinds+)

(defun eest-blockchain-count-by-string (values)
  (let ((counts (make-hash-table :test 'equal)))
    (dolist (value values)
      (unless (stringp value)
        (error "EEST blockchain replay summary value must be a string"))
      (incf (gethash value counts 0)))
    (sort
     (loop for key being the hash-keys of counts
           using (hash-value count)
           collect (cons key count))
     #'string<
     :key #'car)))

(defun eest-blockchain-replay-block-count (case)
  (let ((blocks (fixture-object-field
                 (fixture-required-field case "fixture")
                 "blocks")))
    (unless (or (null blocks) (listp blocks))
      (error "EEST blockchain replay case ~A blocks must be a JSON array"
             (fixture-required-field case "name")))
    (length blocks)))

(defun eest-blockchain-replay-case-summary (cases)
  (list (cons "count" (length cases))
        (cons "names" (mapcar (lambda (case)
                                (fixture-required-field case "name"))
                              cases))
        (cons "networkCounts"
              (eest-blockchain-count-by-string
               (mapcar (lambda (case)
                         (fixture-required-field
                          (fixture-required-field case "fixture")
                          "network"))
                       cases)))
        (cons "materializationKindCounts"
              (eest-blockchain-count-by-string
               (mapcar #'eest-blockchain-replay-materialization-kind cases)))
        (cons "blockCount"
              (loop for case in cases
                    sum (eest-blockchain-replay-block-count case)))))

(defun validate-phase-a-eest-blockchain-replay-summary
    (cases &key
           (expected-kinds
            +phase-a-eest-blockchain-replay-materialization-kinds+))
  (validate-eest-blockchain-selector-list (mapcar #'car expected-kinds))
  (unless (and (listp cases) cases)
    (error "Phase A EEST blockchain replay cases must be a non-empty list"))
  (let* ((summary (eest-blockchain-replay-case-summary cases))
         (count (fixture-required-field summary "count"))
         (names (fixture-required-field summary "names"))
         (network-counts (fixture-required-field summary "networkCounts"))
         (kind-counts
           (fixture-required-field summary "materializationKindCounts"))
         (block-count (fixture-required-field summary "blockCount")))
    (unless (= count (length expected-kinds))
      (error "Phase A EEST blockchain replay selector count ~A loaded ~A cases"
             (length expected-kinds)
             count))
    (unless (equal names (mapcar #'car expected-kinds))
      (error "Phase A EEST blockchain replay names ~S do not match selectors ~S"
             names
             (mapcar #'car expected-kinds)))
    (dolist (expected expected-kinds)
      (let* ((name (car expected))
             (kind (cdr expected))
             (case (find name cases
                         :key (lambda (entry)
                                (fixture-required-field entry "name"))
                         :test #'string=)))
        (unless case
          (error "Phase A EEST blockchain replay selector ~A was not loaded"
                 name))
        (unless (string= kind (eest-blockchain-replay-materialization-kind case))
          (error "Phase A EEST blockchain replay selector ~A expected ~A but found ~A"
                 name
                 kind
                 (eest-blockchain-replay-materialization-kind case)))))
    ;; Every loaded case must carry a network this build gates on. Default that
    ;; is Shanghai only, so the original "only Shanghai" guarantee is unchanged;
    ;; ..._BLOCKCHAIN_REPLAY_FORKS widens it to the late forks. A network outside
    ;; the set means discovery opened a directory it should not have -- fail
    ;; rather than silently count it.
    (let ((supported (phase-a-eest-blockchain-replay-supported-networks)))
      (dolist (entry network-counts)
        (unless (member (car entry) supported :test #'string=)
          (error "Phase A EEST blockchain replay loaded unsupported network ~A; set ~A to include it"
                 (car entry)
                 +phase-a-eest-blockchain-replay-forks-env+))))
    ;; Engine coverage means SOME newPayload version ran, not V2 specifically: a
    ;; selector set confined to Cancun or Prague carries no V2 payload at all
    ;; and would fail a V2-only check while being fully covered.
    (unless (plusp (loop for kind in '("engineNewPayloadV2"
                                       "engineNewPayloadV3"
                                       "engineNewPayloadV4")
                         sum (or (fixture-object-field kind-counts kind) 0)))
      (error "Phase A EEST blockchain replay is missing embedded Engine coverage"))
    (when (find "blockRlp" expected-kinds :key #'cdr :test #'string=)
      (unless (plusp (or (fixture-object-field kind-counts "blockRlp") 0))
        (error "Phase A EEST blockchain replay is missing standard block RLP coverage"))
      (unless (plusp block-count)
        (error "Phase A EEST blockchain replay is missing decoded block coverage")))
    summary))

(defun load-phase-a-eest-blockchain-replay-cases
    (root &key
          (expected-kinds
           +phase-a-eest-blockchain-replay-materialization-kinds+))
  (let ((cases (load-eest-blockchain-test-root-cases
                root
                :names (mapcar #'car expected-kinds))))
    (validate-phase-a-eest-blockchain-replay-summary
     cases
     :expected-kinds expected-kinds)
    cases))

(defun load-optional-phase-a-eest-blockchain-replay-cases ()
  (with-execution-spec-tests-blockchain-test-root (root)
    (let ((expected-kinds
            (phase-a-eest-blockchain-replay-env-materialization-kinds
             root)))
      (unless expected-kinds
        (let ((candidates
                (discover-phase-a-eest-blockchain-replay-selectors root)))
          (skip-test
           (if candidates
               (format nil
                       "Set ~A to ~A, auto, or comma-separated selector=kind pairs such as ~A to run Phase A blockchain replay against this external root"
                       +phase-a-eest-blockchain-replay-selectors-env+
                       +phase-a-eest-blockchain-replay-pinned-selector+
                       (phase-a-eest-blockchain-replay-selector-string
                        candidates
                        :limit 10))
               (format nil
                       "Set ~A to comma-separated selector=kind pairs to run Phase A blockchain replay against an external root"
                       +phase-a-eest-blockchain-replay-selectors-env+)))))
      (load-phase-a-eest-blockchain-replay-cases
       root
       :expected-kinds expected-kinds))))

(defun load-optional-phase-a-eest-blockchain-rejection-cases ()
  "The invalid-payload vectors this run should submit, or a skip.

Keyed on the same selector env as the replay set, but only its `auto' setting:
an explicit selector list names replay cases and a pinned list is a replay pin,
so neither can say which refusals to run. The count manifest reports invalid
cases discovered against invalid cases executed, which is what keeps this
narrower switch from becoming another silent gap."
  (with-execution-spec-tests-blockchain-test-root (root)
    (let ((value (funcall *fixture-root-environment-reader*
                          +phase-a-eest-blockchain-replay-selectors-env+)))
      (unless (and (stringp value)
                   (string= +phase-a-eest-blockchain-replay-auto-selector+
                            (string-downcase
                             (eest-fixture-trim-string value))))
        (skip-test
         (format nil
                 "Set ~A to ~A to run Phase A blockchain invalid-payload refusal against this external root"
                 +phase-a-eest-blockchain-replay-selectors-env+
                 +phase-a-eest-blockchain-replay-auto-selector+)))
      (let ((selectors
              (discover-phase-a-eest-blockchain-rejection-selectors root)))
        (unless selectors
          (skip-test
           (format nil
                   "This EEST blockchain root carries no invalid-payload vectors for the networks ~A selects"
                   +phase-a-eest-blockchain-replay-forks-env+)))
        (load-eest-blockchain-test-root-cases
         root
         :names (mapcar #'car selectors))))))

