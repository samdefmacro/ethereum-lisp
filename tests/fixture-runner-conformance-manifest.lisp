(in-package #:ethereum-lisp.test)

;;;; Non-vacuity guard for EEST conformance.
;;;;
;;;; The failure this file exists to catch is silent: a run mounts the corpus,
;;;; discovers zero materializable cases for a fork it CLAIMS to cover, reports
;;;; every case skipped, and goes green -- indistinguishable, in CI, from having
;;;; verified something. A skip is the right answer when no corpus is present;
;;;; it is the WRONG answer when the corpus is right there and simply was not
;;;; exercised. So the guards below run only when the corpus is mounted (they
;;;; skip otherwise, exactly like the replay tests) and then FAIL if the
;;;; executed count for any fork/network the run is configured to cover is zero.
;;;;
;;;; "Configured to cover" is the supported set the selectors already key on:
;;;; PHASE-A-EEST-STATE-TEST-SUPPORTED-FORKS for state_tests and
;;;; PHASE-A-EEST-BLOCKCHAIN-REPLAY-SUPPORTED-NETWORKS for replay. With the
;;;; defaults that is London/Shanghai and Shanghai, so the existing blocking
;;;; gate asserts those are non-empty. When CI widens the set to the late forks
;;;; (Cancun/Prague/Osaka) the guard extends to them too -- which is why that
;;;; job is non-blocking until plan Phase 7 lands their execution.
;;;;
;;;; A per-fork count alone still hides two whole dimensions, so the manifest
;;;; also reports and asserts:
;;;;
;;;;   FORMAT   -- state_test / blockchain_test / blockchain_test_engine. One
;;;;               fork's cases arrive in several shapes and a materializer can
;;;;               cover one shape while silently dropping another.
;;;;   VALIDITY -- valid / invalid. Executing only the vectors a node is meant
;;;;               to ACCEPT proves nothing about the ones it must REFUSE, and
;;;;               that half is where consensus failures actually live.
;;;;
;;;; Both axes are keyed on what the mounted corpus offers IN SCOPE, not on a
;;;; hardcoded list: a format or validity carried by a case whose fork this run
;;;; is configured to cover, and executed zero times, is a failure; one the
;;;; corpus does not contain, or carries only on a fork outside the configured
;;;; set, is not. Scoping matters -- a Cancun invalid vector is no evidence
;;;; about a run that claims only Shanghai, and counting it would turn the
;;;; blocking London/Shanghai gate red for a gap that belongs to a fork it never
;;;; promised. Out-of-scope cases are still counted, by name, on the fork axis
;;;; and in the outcome categories.
;;;;
;;;; Finally the manifest counts the files the discovery filter never OPENED --
;;;; wrong fork tree, feature tree outside the covered set, over the size cap.
;;;; Those never become cases, so selected/skipped cannot see them; leaving them
;;;; uncounted would be the same invisible skip one level up.

(defun eest-conformance-field (record name)
  (cdr (assoc name record :test #'string=)))

(defun eest-fixture-inferred-format (fixture)
  (cond
    ((or (fixture-field-present-p fixture "engineNewPayloads")
         (fixture-field-present-p fixture "engineNewPayloadV2"))
     "blockchain_test_engine")
    ((fixture-field-present-p fixture "blocks") "blockchain_test")
    ((fixture-field-present-p fixture "transaction") "state_test")
    (t "unknown")))

(defun eest-fixture-case-format (case)
  "The EEST format CASE was filled as.

Read from the fixture, not from the directory it was found under: the axis has
to mean `this shape executed', and a path only says where a file sits. Fixtures
predating the _info block are classified by shape so they still land on one of
the three real formats instead of an `unknown' bucket nothing can assert on."
  (let ((fixture (fixture-required-field case "fixture")))
    (or (fixture-object-field
         (fixture-object-field fixture "_info")
         "fixture-format")
        (fixture-object-field fixture "fixture-format")
        (eest-fixture-inferred-format fixture))))

(defun eest-state-test-case-validity (case)
  (let ((post (fixture-object-field
               (fixture-required-field case "fixture")
               "post")))
    (if (loop for fork-entry in post
              thereis (loop for entry in (cdr fork-entry)
                            thereis (and (listp entry)
                                         (fixture-field-present-p
                                          entry "expectException"))))
        "invalid"
        "valid")))

(defun phase-a-eest-state-skip-category (case)
  "Why CASE is not in the state_tests set, as a name the manifest can report."
  (handler-case
      (cond
        ((null (intersection (phase-a-eest-state-test-supported-forks)
                             (eest-state-test-case-fork-names case)
                             :test #'string=))
         "unsupportedFork")
        ((zerop (eest-state-test-transaction-combination-count case))
         "noTransactionCombinations")
        (t "unmaterializableShape"))
    (error () "unreadableFixture")))

(defun eest-conformance-record-covers-p (record field key)
  (let ((value (eest-conformance-field record field)))
    (if (listp value)
        (and (member key value :test #'string=) t)
        (and (stringp value) (string= key value) t))))

(defun eest-conformance-executed-counts (records field keys)
  "Executed counts for KEYS in the order given, zeros included.

Counting only the keys that happen to appear would let a fork that executed
nothing vanish from the manifest, which is exactly the report this guard reads."
  (mapcar
   (lambda (key)
     (cons key
           (count-if (lambda (record)
                       (and (eest-conformance-field record "executed")
                            (eest-conformance-record-covers-p record field key)))
                     records)))
   keys))

(defun eest-conformance-discovered-keys (records field)
  "The distinct FIELD values the mounted corpus offers, sorted.

The assertion keys off this rather than a fixed list, so a format or validity
the corpus does not contain is not demanded, while one it does contain and this
build never ran is a failure."
  (let ((seen '()))
    (dolist (record records)
      (let ((value (eest-conformance-field record field)))
        (dolist (key (if (listp value) value (list value)))
          (when (and (stringp key) (not (member key seen :test #'string=)))
            (push key seen)))))
    (sort seen #'string<)))

(defun eest-conformance-category-counts (records)
  (let ((counts '()))
    (dolist (record records)
      (let* ((category (or (eest-conformance-field record "category")
                           "unclassified"))
             (entry (assoc category counts :test #'string=)))
        (if entry
            (incf (cdr entry))
            (push (cons category 1) counts))))
    (sort counts #'string< :key #'car)))

(defun eest-conformance-discovery-exclusions
    (root paths feature-directories max-file-bytes networks)
  "Counts of fixture FILES the discovery filter never opened, by reason.

Uncovered fork trees are named one by one rather than summed, because the names
are the finding. `ShanghaiToCancunAtTime15k' and the four BPO transitions are
whole categories of vector this build cannot replay -- they cross an activation
boundary, so they have no single ruleset and, here, almost always more than one
payload -- and a single `not covered: 190' would hide which ones and how many."
  (let ((counts (list (cons "featureTreeNotCovered" 0)
                      (cons "fileTooLarge" 0))))
    (flet ((tally (reason)
             (let ((entry (assoc reason counts :test #'string=)))
               (if entry
                   (incf (cdr entry))
                   (push (cons reason 1) counts)))))
      (dolist (path paths)
        (multiple-value-bind (network-directory feature-directory)
            (eest-fixture-discovery-directories root path)
          (cond
            ((and network-directory
                  (not (member network-directory networks :test #'string-equal)))
             (tally (format nil "~A~A"
                            +eest-fixture-network-directory-prefix+
                            network-directory)))
            ((not (member (string-downcase feature-directory)
                          feature-directories
                          :test #'string=))
             (tally "featureTreeNotCovered"))
            ((> (eest-fixture-file-byte-size path) max-file-bytes)
             (tally "fileTooLarge"))))))
    (sort counts #'string< :key #'car)))

(defun phase-a-eest-state-conformance-records (root)
  "One record per discovered state_tests case, executed or not.

Built by streaming discovery so the manifest survives a widened fork set: the
whole discovered corpus does not fit in memory, and a heap exhaustion here would
destroy the very report that explains what ran."
  (let ((supported (phase-a-eest-state-test-supported-forks))
        (records '()))
    (map-phase-a-eest-state-discovery-cases
     (lambda (case)
       (let* ((materializable (phase-a-eest-state-materializable-case-p case))
              (forks (handler-case
                         (remove-if-not
                          (lambda (fork)
                            (member fork (eest-state-test-case-fork-names case)
                                    :test #'string=))
                          supported)
                       (error () '()))))
         (push
          (list (cons "name" (fixture-required-field case "name"))
                (cons "forks" forks)
                (cons "inScope" (and forks t))
                (cons "format" (eest-fixture-case-format case))
                (cons "validity" (eest-state-test-case-validity case))
                (cons "executed" (and materializable t))
                (cons "category"
                      (if materializable
                          "executed"
                          (phase-a-eest-state-skip-category case))))
          records)))
     root)
    (nreverse records)))

(defun phase-a-eest-blockchain-conformance-records (root)
  "One record per discovered blockchain case, executed or not.

A case executes on one of two paths. The replay path builds the block and
compares roots, and only accepts vectors expecting acceptance -- it derives what
it asserts by executing, so it has nothing to say about a payload that must be
refused. The rejection path submits the fixture's own payload verbatim and
asserts the refusal. Both count as executed; the validity axis is what tells
them apart.

Built by streaming discovery so the manifest survives a widened fork set: the
whole discovered corpus does not fit in memory, and a heap exhaustion here would
destroy the very report that explains what ran."
  (let ((records '()))
    (map-phase-a-eest-blockchain-discovery-cases
     (lambda (case)
       (multiple-value-bind (kind category)
           (phase-a-eest-blockchain-replay-materializable-kind case)
         (let ((rejection-kind
                 (unless kind (phase-a-eest-blockchain-rejection-kind case)))
               (network (fixture-object-field
                         (fixture-required-field case "fixture")
                         "network")))
           (push
            (list (cons "name" (fixture-required-field case "name"))
                  (cons "network" network)
                  (cons "inScope"
                        (and (stringp network)
                             (member network
                                     (phase-a-eest-blockchain-replay-supported-networks)
                                     :test #'string=)
                             t))
                  (cons "format" (eest-fixture-case-format case))
                  (cons "validity"
                        (if (eest-blockchain-case-invalid-p case)
                            "invalid"
                            "valid"))
                  (cons "kind" (or kind rejection-kind))
                  (cons "executed" (and (or kind rejection-kind) t))
                  (cons "category"
                        (cond (kind "executed")
                              (rejection-kind "executedRejection")
                              (t category))))
            records))))
     root)
    (nreverse records)))

(defun phase-a-eest-conformance-family-report
    (family records fork-field forks exclusions)
  (let ((selected (count-if (lambda (record)
                              (eest-conformance-field record "executed"))
                            records))
        (in-scope (remove-if-not
                   (lambda (record)
                     (eest-conformance-field record "inScope"))
                   records)))
    (list
     (cons "family" family)
     (cons "discovered" (length records))
     (cons "inScope" (length in-scope))
     (cons "selected" selected)
     (cons "skipped" (- (length records) selected))
     (cons "executedByFork"
           (eest-conformance-executed-counts records fork-field forks))
     (cons "executedByFormat"
           (eest-conformance-executed-counts
            in-scope "format"
            (eest-conformance-discovered-keys in-scope "format")))
     (cons "executedByValidity"
           (eest-conformance-executed-counts
            in-scope "validity"
            (eest-conformance-discovered-keys in-scope "validity")))
     (cons "categories" (eest-conformance-category-counts records))
     (cons "unopenedFiles" exclusions))))

(defun phase-a-eest-format-count-entries (entries)
  (mapcar (lambda (entry) (format nil "~A:~D" (car entry) (cdr entry)))
          entries))

(defun phase-a-eest-report-conformance-family
    (report &optional (stream *standard-output*))
  "Emit the manifest lines for one family so the CI log records what ran."
  (format stream
          "~&EEST-CONFORMANCE ~A: discovered=~D inScope=~D selected=~D ~
           skipped=~D forks=[~{~A~^ ~}] formats=[~{~A~^ ~}] validity=[~{~A~^ ~}]~%"
          (eest-conformance-field report "family")
          (eest-conformance-field report "discovered")
          (eest-conformance-field report "inScope")
          (eest-conformance-field report "selected")
          (eest-conformance-field report "skipped")
          (phase-a-eest-format-count-entries
           (eest-conformance-field report "executedByFork"))
          (phase-a-eest-format-count-entries
           (eest-conformance-field report "executedByFormat"))
          (phase-a-eest-format-count-entries
           (eest-conformance-field report "executedByValidity")))
  (format stream
          "~&EEST-CONFORMANCE ~A: outcomes=[~{~A~^ ~}] unopenedFiles=[~{~A~^ ~}]~%"
          (eest-conformance-field report "family")
          (phase-a-eest-format-count-entries
           (eest-conformance-field report "categories"))
          (phase-a-eest-format-count-entries
           (eest-conformance-field report "unopenedFiles")))
  report)

(defun phase-a-eest-assert-family-non-vacuous (family executed)
  "Signal an error naming every fork/network in EXECUTED whose count is zero.
Returns NIL when all are positive. Kept separate from the corpus-mounted tests
so its logic is exercised without a corpus."
  (let ((vacuous (remove-if #'plusp executed :key #'cdr)))
    (when vacuous
      (error "~A conformance is vacuous: the corpus is mounted but executed ~
              zero cases for ~{~A~^, ~}; a green skip would have hidden this"
             family (mapcar #'car vacuous)))))

(defun phase-a-eest-assert-conformance-report-non-vacuous (report)
  "Apply the non-vacuity guard to every axis of REPORT.

The same assertion on all three axes is the point: a build can cover every fork
it names and still never run an invalid vector, or never run one of the fixture
formats that fork ships in, and per-fork counts alone call that a pass."
  (let ((family (eest-conformance-field report "family")))
    (phase-a-eest-assert-family-non-vacuous
     (format nil "~A forks" family)
     (eest-conformance-field report "executedByFork"))
    (phase-a-eest-assert-family-non-vacuous
     (format nil "~A formats" family)
     (eest-conformance-field report "executedByFormat"))
    (phase-a-eest-assert-family-non-vacuous
     (format nil "~A validity" family)
     (eest-conformance-field report "executedByValidity"))))

(defun phase-a-eest-state-conformance-report (root)
  (phase-a-eest-conformance-family-report
   "state_tests"
   (phase-a-eest-state-conformance-records root)
   "forks"
   (phase-a-eest-state-test-supported-forks)
   (eest-conformance-discovery-exclusions
    root
    (eest-state-test-root-json-paths root)
    +phase-a-eest-state-test-discovery-feature-directories+
    +phase-a-eest-state-test-discovery-max-file-bytes+
    (phase-a-eest-state-test-supported-forks))))

(defun phase-a-eest-blockchain-conformance-report (root)
  (phase-a-eest-conformance-family-report
   "blockchain_replay"
   (phase-a-eest-blockchain-conformance-records root)
   "network"
   (phase-a-eest-blockchain-replay-supported-networks)
   (eest-conformance-discovery-exclusions
    root
    (eest-blockchain-test-root-json-paths root)
    (phase-a-eest-blockchain-replay-active-feature-directories)
    +phase-a-eest-blockchain-replay-discovery-max-file-bytes+
    (phase-a-eest-blockchain-replay-supported-networks))))

(deftest phase-a-eest-non-vacuity-guard-rejects-zero-executed
  ;; The guard's entire value is failing LOUD when a required family ran
  ;; nothing. Prove it fires on a zero and stays quiet when every family ran at
  ;; least one case -- this needs no corpus, so it runs on every build and keeps
  ;; the check honest even where the fixtures are absent.
  (signals error
    (phase-a-eest-assert-family-non-vacuous
     "state_tests" '(("London" . 3) ("Shanghai" . 0))))
  (is (null (phase-a-eest-assert-family-non-vacuous
             "state_tests" '(("London" . 3) ("Shanghai" . 1))))))

(deftest phase-a-eest-non-vacuity-guard-covers-format-and-validity-axes
  ;; Per-fork counts pass while a whole format or the entire invalid half sits
  ;; at zero, so each axis has to fail on its own. Corpus-free, like the guard
  ;; above, so a build with no fixtures still proves the three checks are wired.
  (let ((covered
          (list (cons "family" "blockchain_replay")
                (cons "executedByFork" '(("Shanghai" . 4)))
                (cons "executedByFormat" '(("blockchain_test_engine" . 4)))
                (cons "executedByValidity" '(("valid" . 3) ("invalid" . 1))))))
    (is (null (phase-a-eest-assert-conformance-report-non-vacuous covered))))
  (signals error
    (phase-a-eest-assert-conformance-report-non-vacuous
     (list (cons "family" "blockchain_replay")
           (cons "executedByFork" '(("Shanghai" . 4)))
           (cons "executedByFormat" '(("blockchain_test_engine" . 4)
                                      ("blockchain_test" . 0)))
           (cons "executedByValidity" '(("valid" . 4))))))
  (signals error
    (phase-a-eest-assert-conformance-report-non-vacuous
     (list (cons "family" "blockchain_replay")
           (cons "executedByFork" '(("Shanghai" . 4)))
           (cons "executedByFormat" '(("blockchain_test_engine" . 4)))
           (cons "executedByValidity" '(("valid" . 4) ("invalid" . 0)))))))

(deftest phase-a-eest-conformance-axes-are-keyed-on-the-mounted-corpus
  ;; A format or validity the corpus does not ship must not be demanded, and one
  ;; it does ship must appear even when nothing executed it. Both directions
  ;; matter: the first turns the guard into a false alarm, the second is the
  ;; silent pass it exists to stop.
  (let ((records
          (list (list (cons "format" "blockchain_test_engine")
                      (cons "validity" "valid")
                      (cons "executed" t))
                (list (cons "format" "blockchain_test_engine")
                      (cons "validity" "invalid")
                      (cons "executed" nil)))))
    (is (equal '("blockchain_test_engine")
               (eest-conformance-discovered-keys records "format")))
    (is (equal '("invalid" "valid")
               (eest-conformance-discovered-keys records "validity")))
    (is (equal '(("invalid" . 0) ("valid" . 1))
               (eest-conformance-executed-counts
                records "validity"
                (eest-conformance-discovered-keys records "validity"))))))

(deftest phase-a-eest-conformance-axes-ignore-out-of-scope-forks
  ;; The format and validity axes speak only for the forks a run claims. An
  ;; invalid Cancun vector says nothing about a Shanghai-only build, and letting
  ;; it demand an executed invalid case would fail the blocking London/Shanghai
  ;; gate over a fork it never promised to cover. The fork axis and the outcome
  ;; categories still count the out-of-scope case, so it is skipped, not hidden.
  (let* ((records
           (list (list (cons "network" "Shanghai") (cons "inScope" t)
                       (cons "format" "blockchain_test_engine")
                       (cons "validity" "valid") (cons "executed" t)
                       (cons "category" "executed"))
                 (list (cons "network" "Cancun") (cons "inScope" nil)
                       (cons "format" "blockchain_test_engine")
                       (cons "validity" "invalid") (cons "executed" nil)
                       (cons "category" "unsupportedNetwork"))))
         (report (phase-a-eest-conformance-family-report
                  "blockchain_replay" records "network" '("Shanghai") '())))
    (is (equal '(("valid" . 1))
               (eest-conformance-field report "executedByValidity")))
    (is (equal '(("Shanghai" . 1))
               (eest-conformance-field report "executedByFork")))
    (is (equal '(("executed" . 1) ("unsupportedNetwork" . 1))
               (eest-conformance-field report "categories")))
    (is (= 2 (eest-conformance-field report "discovered")))
    (is (= 1 (eest-conformance-field report "inScope")))
    (is (null (phase-a-eest-assert-conformance-report-non-vacuous report)))))

(deftest phase-a-eest-state-conformance-is-non-vacuous
  (with-execution-spec-tests-state-test-root (root)
    (let ((report (phase-a-eest-state-conformance-report root)))
      (phase-a-eest-report-conformance-family report)
      (phase-a-eest-assert-conformance-report-non-vacuous report))))

(deftest phase-a-eest-blockchain-conformance-is-non-vacuous
  (with-execution-spec-tests-blockchain-test-root (root)
    (let ((report (phase-a-eest-blockchain-conformance-report root)))
      (phase-a-eest-report-conformance-family report)
      (phase-a-eest-assert-conformance-report-non-vacuous report))))
