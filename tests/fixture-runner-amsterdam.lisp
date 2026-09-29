(in-package #:ethereum-lisp.test)

;;;; Amsterdam feature-fixture burn-down (readiness plan section 8).
;;;;
;;;; The current-fork gates stop at Osaka. The Amsterdam feature corpus
;;;; (tests-glamsterdam-devnet@v7.2.1, pinned in scripts/fetch-eest-fixtures.sh
;;;; as `amsterdam-v7.2.1') is laid out per EIP under
;;;; `<family>/for_amsterdam/amsterdam/eipNNNN_*/', and the burn-down is measured
;;;; per EIP directory, so this runner walks those directories one fixture file
;;;; at a time and scores every case instead of stopping at the first failure.
;;;;
;;;; Two families are executed:
;;;;
;;;; - state_tests, through the same ASSERT-EEST-STATE-TEST-POST-ENTRY the
;;;;   current-fork state gate uses, under Amsterdam chain rules;
;;;; - blockchain_tests_engine, every engineNewPayloads entry in order, through
;;;;   the real newPayload handler. Amsterdam's engine_newPayloadV5 is still
;;;;   refused at the method router, because AMSTERDAM-EXECUTION-AVAILABLE-P is
;;;;   false; this runner calls the handler below that capability gate, so the
;;;;   gate stays closed for every real client while its execution is measured.
;;;;
;;;; blockchain_tests carries the same test ids as blockchain_tests_engine in
;;;; block-RLP form and is not executed a second time here.
;;;;
;;;; Selection, both optional, comma-separated EIP directory names:
;;;;   ETHEREUM_LISP_AMSTERDAM_EEST_DIRECTORIES  run only these directories
;;;;   ETHEREUM_LISP_AMSTERDAM_EEST_REQUIRED     these must have cases and no
;;;;                                             failure in every family run
;;;; Without the fixture root, or with a root that has no Amsterdam tree (the
;;;; stable v20.0.2 corpus has none), the test is a counted skip.

(defconstant +amsterdam-eest-directories-env+
  "ETHEREUM_LISP_AMSTERDAM_EEST_DIRECTORIES")

(defconstant +amsterdam-eest-required-env+
  "ETHEREUM_LISP_AMSTERDAM_EEST_REQUIRED")

(defparameter +amsterdam-eest-families+
  '("state_tests" "blockchain_tests_engine"))

(defparameter +amsterdam-eest-family-roots+
  '("" "fixtures/"))

(defparameter *amsterdam-eest-failure-samples* 3
  "How many failure messages each directory reports verbatim.")

(defun amsterdam-eest-env-list (name)
  (let ((value (funcall *fixture-root-environment-reader* name)))
    (unless (blank-string-p value)
      (remove-if #'blank-string-p
                 (mapcar #'eest-fixture-trim-string
                         (eest-fixture-split-string value #\,))))))

(defun amsterdam-eest-family-directory (root family)
  "ROOT's `FAMILY/for_amsterdam/amsterdam/' tree, or NIL when it is absent."
  (loop for prefix in +amsterdam-eest-family-roots+
        for candidate = (probe-file
                         (merge-pathnames
                          (format nil "~A~A/for_amsterdam/amsterdam/"
                                  prefix family)
                          (pathname root)))
        when candidate
          return candidate))

(defun amsterdam-eest-eip-directories (family-directory)
  "The EIP directory names under FAMILY-DIRECTORY, sorted."
  (sort (mapcar (lambda (path)
                  (car (last (pathname-directory path))))
                (directory
                 (merge-pathnames
                  (make-pathname :directory '(:relative :wild))
                  family-directory)))
        #'string<))

;;; State tests

(defun amsterdam-eest-run-state-case (case)
  "Run every Amsterdam post entry of CASE; signal on the first divergence."
  (dolist (post-entry (eest-state-test-post-entries case "Amsterdam"))
    (assert-eest-state-test-post-entry case post-entry :fork "Amsterdam"))
  t)

;;; Engine blockchain tests

(defun amsterdam-eest-chain-config (fixture)
  "Every fork through Amsterdam active at genesis, or at the fixture's
transition time for a `BPO2ToAmsterdamAtTime15k' network."
  (let* ((network (fixture-required-field fixture "network"))
         (config (fixture-object-field fixture "config"))
         (amsterdam-time
           (cond ((string= network "Amsterdam") 0)
                 ((string= network "BPO2ToAmsterdamAtTime15k") 15000)
                 (t (error "Unsupported Amsterdam fixture network ~A"
                           network)))))
    (make-chain-config
     :chain-id (hex-to-quantity
                (or (fixture-object-field config "chainid") "0x1"))
     :homestead-block 0 :eip150-block 0 :eip155-block 0 :eip158-block 0
     :byzantium-block 0 :constantinople-block 0 :petersburg-block 0
     :istanbul-block 0 :berlin-block 0 :london-block 0
     :shanghai-time 0 :cancun-time 0 :prague-time 0 :osaka-time 0
     :bpo1-time 0 :bpo2-time 0
     :amsterdam-time amsterdam-time
     :deposit-contract-address
     (address-from-hex +eest-deposit-contract-address+))))

(defun amsterdam-eest-genesis-header (fixture)
  (let ((header (fixture-required-field fixture "genesisBlockHeader"))
        (label "Amsterdam EEST genesisBlockHeader"))
    (let ((base (eest-blockchain-engine-genesis-header fixture label)))
      (flet ((optional-hash (name)
               (let ((value (fixture-object-field header name)))
                 (when value (hash32-from-hex value))))
             (optional-quantity (name)
               (let ((value (fixture-object-field header name)))
                 (when value (hex-to-quantity value)))))
        (setf (block-header-block-access-list-hash base)
              (optional-hash "blockAccessListHash")
              (block-header-slot-number base)
              (optional-quantity "slotNumber"))
        base))))

(defun amsterdam-eest-pre-state (fixture)
  (let ((state (make-state-db)))
    (dolist (entry (ethereum-lisp.json:json-object-entries
                    (fixture-required-field fixture "pre")
                    "Amsterdam EEST pre"))
      (let ((address (address-from-hex (car entry)))
            (account (cdr entry)))
        (state-db-set-account
         state address
         (make-state-account
          :nonce (hex-to-quantity (fixture-required-field account "nonce"))
          :balance (hex-to-quantity
                    (fixture-required-field account "balance"))))
        (let ((code (hex-to-bytes (fixture-required-field account "code"))))
          (when (plusp (length code))
            (state-db-set-code state address code)))
        (dolist (slot (ethereum-lisp.json:json-object-entries
                       (or (fixture-object-field account "storage") '())
                       "Amsterdam EEST pre storage"))
          (state-db-set-storage
           state address
           (hash32-from-hex
            (eest-blockchain-normalized-storage-slot
             (car slot) "Amsterdam EEST pre storage key"))
           (hex-to-quantity (cdr slot))))))
    state))

(defun amsterdam-eest-submit-payload (store config entry)
  "Submit ENTRY through the newPayload handler; return (VALUES result code).

RESULT is the payload-status object, or NIL when the handler answered a
JSON-RPC error, whose code is then CODE. The error mapping mirrors
RPC-HANDLE-REQUEST-WITHOUT-GUARD."
  (let ((version (parse-integer
                  (fixture-required-field entry "newPayloadVersion")))
        (params (ethereum-lisp.json:json-array-values
                 (fixture-required-field entry "params"))))
    (handler-case
        (values (ethereum-lisp.engine-api::engine-rpc-handle-new-payload
                 version params store config
                 :import-function #'execute-and-commit-engine-payload)
                nil)
      (ethereum-lisp.engine-api:engine-rpc-error (condition)
        (values nil (ethereum-lisp.engine-api:engine-rpc-error-code condition)))
      (block-validation-error ()
        (values nil -32602))
      (ethereum-lisp.validation:invalid-parameters-error ()
        (values nil -32602)))))

(defun amsterdam-eest-run-engine-case (case)
  "Replay every engineNewPayloads entry of CASE; signal on a divergence."
  (let* ((name (fixture-required-field case "name"))
         (fixture (fixture-required-field case "fixture"))
         (config (amsterdam-eest-chain-config fixture))
         (genesis (make-block :header (amsterdam-eest-genesis-header fixture)))
         (store (make-engine-payload-memory-store)))
    (let ((expected-genesis
            (fixture-required-field
             (fixture-required-field fixture "genesisBlockHeader") "hash"))
          (actual-genesis (hash32-to-hex (block-hash genesis))))
      (unless (string= expected-genesis actual-genesis)
        (error "~A genesis hashes to ~A, fixture says ~A"
               name actual-genesis expected-genesis)))
    (engine-payload-store-put-block store genesis :state-available-p t)
    (commit-state-db-to-chain-store store (block-hash genesis)
                                    (amsterdam-eest-pre-state fixture))
    (loop for entry in (fixture-required-field fixture "engineNewPayloads")
          for index from 0
          for block-hash = (fixture-required-field
                            (first (fixture-required-field entry "params"))
                            "blockHash")
          for expected-error = (fixture-object-field entry "validationError")
          for expected-code = (fixture-object-field entry "errorCode")
          do (multiple-value-bind (result code)
                 (amsterdam-eest-submit-payload store config entry)
               (let ((status (and result (fixture-object-field result "status")))
                     (reason (and result
                                  (fixture-object-field result
                                                        "validationError"))))
                 (cond
                   (expected-code
                    (unless (eql code (eest-engine-payload-error-code
                                       expected-code))
                      (error "~A payload ~D expected JSON-RPC error ~A, got ~
                              ~:[status ~A~;error ~:*~A~]"
                             name index expected-code code status)))
                   (expected-error
                    (unless (equal status "INVALID")
                      (error "~A payload ~D expected ~A, got ~
                              ~:[status ~A~;error ~:*~A~]"
                             name index expected-error code status)))
                   ((not (equal status "VALID"))
                    (error "~A payload ~D expected VALID, got ~
                            ~:[status ~A (~A)~;error ~:*~A~]"
                           name index code status reason))
                   ((not (equal block-hash
                                (fixture-object-field result
                                                      "latestValidHash")))
                    (error "~A payload ~D latestValidHash ~A, expected ~A"
                           name index
                           (fixture-object-field result "latestValidHash")
                           block-hash))))))
    (let ((last-hash (hash32-from-hex
                      (fixture-required-field fixture "lastblockhash"))))
      (unless (chain-store-state-available-p store last-hash)
        (error "~A lastblockhash ~A has no state"
               name (hash32-to-hex last-hash)))
      (assert-eest-blockchain-post-state
       (chain-store-state-db store last-hash) case))
    t))

;;; Directory scoring

(defstruct (amsterdam-eest-tally (:constructor make-amsterdam-eest-tally
                                     (family directory)))
  family directory (passed 0) (failed 0) (samples '()))

(defun amsterdam-eest-condition-summary (condition)
  "CONDITION's report on one line, runs of whitespace collapsed, bounded."
  (let ((text (handler-case (princ-to-string condition)
                (error () (format nil "~S" (type-of condition)))))
        (previous-space-p nil))
    (let ((collapsed
            (with-output-to-string (out)
              (loop for char across text
                    for space-p = (member char '(#\Space #\Tab #\Newline
                                                 #\Return))
                    do (unless (and space-p previous-space-p)
                         (write-char (if space-p #\Space char) out))
                       (setf previous-space-p space-p)))))
      (if (> (length collapsed) 500) (subseq collapsed 0 500) collapsed))))

(defun amsterdam-eest-score-case (tally runner case)
  (let ((outcome
          (handler-case (progn (funcall runner case) nil)
            (serious-condition (condition)
              (format nil "~A: ~A"
                      (fixture-required-field case "name")
                      (amsterdam-eest-condition-summary condition))))))
    (if outcome
        (progn
          (incf (amsterdam-eest-tally-failed tally))
          (when (< (length (amsterdam-eest-tally-samples tally))
                   *amsterdam-eest-failure-samples*)
            (push outcome (amsterdam-eest-tally-samples tally))))
        (incf (amsterdam-eest-tally-passed tally)))))

(defun amsterdam-eest-family-runner (family)
  (cond ((string= family "state_tests") #'amsterdam-eest-run-state-case)
        ((string= family "blockchain_tests_engine")
         #'amsterdam-eest-run-engine-case)
        (t (error "No Amsterdam runner for family ~A" family))))

(defun amsterdam-eest-load-file-cases (family root path)
  (if (string= family "state_tests")
      (load-eest-state-test-root-file-cases root path)
      (load-eest-blockchain-test-root-file-cases root path)))

(defun amsterdam-eest-score-directory (family family-directory directory)
  (let ((tally (make-amsterdam-eest-tally family directory))
        (runner (amsterdam-eest-family-runner family))
        (eip-root (merge-pathnames
                   (make-pathname :directory (list :relative directory))
                   family-directory)))
    (dolist (path (execution-spec-tests-json-paths eip-root))
      (dolist (case (amsterdam-eest-load-file-cases family eip-root path))
        (amsterdam-eest-score-case tally runner case)))
    tally))

(defun amsterdam-eest-report-line (tally)
  (format nil "AMSTERDAM-EEST ~A ~A: cases=~D passed=~D failed=~D"
          (amsterdam-eest-tally-family tally)
          (amsterdam-eest-tally-directory tally)
          (+ (amsterdam-eest-tally-passed tally)
             (amsterdam-eest-tally-failed tally))
          (amsterdam-eest-tally-passed tally)
          (amsterdam-eest-tally-failed tally)))

(defun amsterdam-eest-burn-down (root &key directories)
  "Score every selected Amsterdam EIP directory of every family under ROOT.

Returns the tallies, in family then directory order, and prints one report line
per tally plus its first failure messages."
  (let ((tallies '()))
    (dolist (family +amsterdam-eest-families+)
      (let ((family-directory (amsterdam-eest-family-directory root family)))
        (when family-directory
          (dolist (directory (amsterdam-eest-eip-directories family-directory))
            (when (or (null directories)
                      (member directory directories :test #'string=))
              (let ((tally (amsterdam-eest-score-directory
                            family family-directory directory)))
                (format t "~&~A~%" (amsterdam-eest-report-line tally))
                (dolist (sample (reverse (amsterdam-eest-tally-samples tally)))
                  (format t "~&AMSTERDAM-EEST   first-failure ~A~%" sample))
                (finish-output)
                (push tally tallies)))))))
    (nreverse tallies)))

(defun amsterdam-eest-required-failures (tallies required)
  "The REQUIRED directories that did not pass in full, as report strings."
  (loop for directory in required
        for own = (remove-if-not
                   (lambda (tally)
                     (string= directory (amsterdam-eest-tally-directory tally)))
                   tallies)
        nconc
        (cond
          ((null own)
           (list (format nil "~A: no family ran it" directory)))
          (t
           (loop for tally in own
                 unless (and (zerop (amsterdam-eest-tally-failed tally))
                             (plusp (amsterdam-eest-tally-passed tally)))
                   collect (amsterdam-eest-report-line tally))))))

(deftest optional-amsterdam-eest-feature-burn-down
  (:layer :integration :module :eest)
  (with-execution-spec-tests-fixture-root (root)
    (unless (some (lambda (family)
                    (amsterdam-eest-family-directory root family))
                  +amsterdam-eest-families+)
      (skip-test "The EEST fixture root has no for_amsterdam/amsterdam tree"))
    (call-with-eest-cryptographic-backends
     (lambda ()
       (let* ((tallies (amsterdam-eest-burn-down
                        root
                        :directories (amsterdam-eest-env-list
                                      +amsterdam-eest-directories-env+)))
              (failures (amsterdam-eest-required-failures
                         tallies
                         (amsterdam-eest-env-list
                          +amsterdam-eest-required-env+))))
         (is tallies)
         (when failures
           (error "Required Amsterdam EEST directories did not pass:~{ ~A;~}"
                  failures)))))))
