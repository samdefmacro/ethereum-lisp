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

(defun validate-eest-blockchain-selector-list (names)
  (validate-execution-spec-tests-selector-list
   names
   "EEST blockchain"
   :allow-nested-case-name t))

(defun validate-eest-state-selector-list (names)
  (validate-execution-spec-tests-selector-list
   names
   "EEST state"
   :allow-nested-case-name t))

(defun eest-blockchain-selector-source-style-p (name)
  (execution-spec-tests-source-style-name-p
   name
   :allow-nested-case-name t))

(defun eest-state-selector-source-style-p (name)
  (execution-spec-tests-source-style-name-p
   name
   :allow-nested-case-name t))

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

(defun execution-spec-tests-discovery-path-p
    (root path feature-directories max-file-bytes)
  (let* ((relative (enough-namestring (truename path) (truename root)))
         (slash (position #\/ relative))
         (feature-directory (if slash
                                (subseq relative 0 slash)
                                relative)))
    (and (member (string-downcase feature-directory)
                 feature-directories
                 :test #'string=)
         (<= (eest-fixture-file-byte-size path) max-file-bytes))))

(defun phase-a-eest-blockchain-replay-discovery-path-p (root path)
  (execution-spec-tests-discovery-path-p
   root
   path
   +phase-a-eest-blockchain-replay-discovery-feature-directories+
   +phase-a-eest-blockchain-replay-discovery-max-file-bytes+))

(defun phase-a-eest-state-test-discovery-path-p (root path)
  (execution-spec-tests-discovery-path-p
   root
   path
   +phase-a-eest-state-test-discovery-feature-directories+
   +phase-a-eest-state-test-discovery-max-file-bytes+))

(defun eest-fixture-file-byte-size (path)
  (with-open-file (stream path :direction :input
                               :element-type '(unsigned-byte 8))
    (file-length stream)))

(defun load-phase-a-eest-blockchain-discovery-cases (root)
  (loop for path in (eest-blockchain-test-root-json-paths root)
        when (phase-a-eest-blockchain-replay-discovery-path-p root path)
          append (load-eest-blockchain-test-root-file-cases root path)))

(defun load-phase-a-eest-state-discovery-cases (root)
  (loop for path in (eest-state-test-root-json-paths root)
        when (phase-a-eest-state-test-discovery-path-p root path)
          append (load-eest-state-test-root-file-cases root path)))

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
      (and (intersection +phase-a-eest-state-test-supported-forks+
                         (eest-state-test-case-fork-names case)
                         :test #'string=)
           (plusp (eest-state-test-transaction-combination-count case)))
    (error () nil)))

(defun discover-phase-a-eest-state-test-selectors (root)
  (loop for case in (load-phase-a-eest-state-discovery-cases root)
        when (phase-a-eest-state-materializable-case-p case)
          collect (fixture-required-field case "name")))

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
      (unless (intersection +phase-a-eest-state-test-supported-forks+
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

(defun eest-blockchain-replay-materialization-kind (case)
  (let ((fixture (fixture-required-field case "fixture")))
    (cond
      ((fixture-field-present-p fixture "engineNewPayloadV2")
       "engineNewPayloadV2")
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

(defun phase-a-eest-blockchain-replay-materializable-kind (case)
  (handler-case
      (let* ((fixture (fixture-required-field case "fixture"))
             (network (fixture-object-field fixture "network"))
             (kind (eest-blockchain-replay-materialization-kind case)))
        (when (and (stringp network)
                   (string= "Shanghai" network))
          (cond
            ((string= "engineNewPayloadV2" kind)
             (if (fixture-field-present-p fixture "engineNewPayloadV2")
                 (validate-eest-blockchain-engine-newpayload-v2-case case)
                 (validate-eest-blockchain-engine-newpayloads-v2-case case))
             kind)
            ((string= "blockRlp" kind)
             (validate-eest-blockchain-standard-newpayload-v2-case case)
             kind)
            (t nil))))
    (error () nil)))

(defun discover-phase-a-eest-blockchain-replay-selectors (root)
  (loop for case in (load-phase-a-eest-blockchain-discovery-cases root)
        for kind = (phase-a-eest-blockchain-replay-materializable-kind case)
        when kind
          collect (cons (fixture-required-field case "name") kind)))

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
    (unless (= count (or (fixture-object-field network-counts "Shanghai") 0))
      (error "Phase A EEST blockchain replay must load only Shanghai cases"))
    (unless (plusp (or (fixture-object-field kind-counts "engineNewPayloadV2")
                       0))
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

