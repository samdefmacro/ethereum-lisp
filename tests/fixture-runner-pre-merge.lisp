(in-package #:ethereum-lisp.test)

;;;; Pre-Merge blockchain-fixture burn-down (readiness plan section 9).
;;;;
;;;; The pinned legacy corpus (EEST v5.4.0, `legacy-v5.4.0' in
;;;; scripts/fetch-eest-fixtures.sh) fills its blockchain_tests for every fork
;;;; from Frontier on, but the gates only ever replay its Shanghai-and-later
;;;; networks, and only through Engine payloads. This runner replays the
;;;; proof-of-work and Merge networks (Frontier through Paris) the way
;;;; go-ethereum v1.17.6 tests/block_test_util.go does:
;;;;
;;;; - the chain configuration is geth's tests/init.go Forks entry for the
;;;;   fixture's network, with TerminalTotalDifficulty set to MaxInt64 when the
;;;;   entry names none;
;;;; - the seal is not checked (every fixture is `sealEngine: NoProof', geth
;;;;   runs ethash.NewFaker), while difficulty, ommers and every other header
;;;;   rule are;
;;;; - each block is decoded from its `rlp', admitted through
;;;;   IMPORT-BLOCK-CANDIDATE and, when valid, made the head, as geth's
;;;;   InsertChain -> writeBlockAndSetHead does; a block with
;;;;   `expectException' must be refused with a verdict (a decoding failure, a
;;;;   block or transaction validation error), any other block must be
;;;;   accepted;
;;;; - the head must be `lastblockhash', and its state must be `postState'.
;;;;
;;;; It walks `blockchain_tests/<fork>/<directory>/', scores every case of a
;;;; pre-Merge network, and prints one line per directory with the pass count
;;;; per network and the first failure messages. Cases of later networks are
;;;; not counted.
;;;;
;;;; Selection, all optional and comma-separated:
;;;;   ETHEREUM_LISP_PRE_MERGE_EEST_DIRECTORIES  run only these (`fork/dir')
;;;;   ETHEREUM_LISP_PRE_MERGE_EEST_NETWORKS     score only these networks
;;;;   ETHEREUM_LISP_PRE_MERGE_EEST_REQUIRED     these directories must have
;;;;                                             cases and no failure
;;;; Without the fixture root, or with a root that has no
;;;; `blockchain_tests/frontier' tree (the stable v20.0.2 corpus has none), the
;;;; test is a counted skip.

(defconstant +pre-merge-eest-directories-env+
  "ETHEREUM_LISP_PRE_MERGE_EEST_DIRECTORIES")

(defconstant +pre-merge-eest-networks-env+
  "ETHEREUM_LISP_PRE_MERGE_EEST_NETWORKS")

(defconstant +pre-merge-eest-required-env+
  "ETHEREUM_LISP_PRE_MERGE_EEST_REQUIRED")

(defparameter *pre-merge-eest-failure-samples* 3
  "How many failure messages each directory reports verbatim.")

(defparameter *pre-merge-eest-max-file-bytes* (* 40 1024 1024)
  "Fixture files above this size are counted, not parsed (see
*AMSTERDAM-EEST-MAX-FILE-BYTES*).")

(defconstant +pre-merge-eest-max-int64+ (1- (ash 1 63))
  "go-ethereum's math.MaxInt64, the TTD BlockTest.Run gives a network whose
configuration names none.")

(defun remove-dao-fork-block (plist)
  "PLIST without its :DAO-FORK-BLOCK entry: geth's Forks table sets
DAOForkBlock 0 for Byzantium through Istanbul and for no later network."
  (loop for (key value) on plist by #'cddr
        unless (eq key :dao-fork-block)
          append (list key value)))

;;; go-ethereum v1.17.6 tests/init.go, the Forks entries up to Paris. Keys are
;;; MAKE-CHAIN-CONFIG arguments; a network without :terminal-total-difficulty
;;; gets MaxInt64, as BlockTest.Run does.
(defparameter +pre-merge-eest-networks+
  (let* ((homestead '(:homestead-block 0))
         (eip150 (append homestead '(:eip150-block 0)))
         (eip158 (append eip150 '(:eip155-block 0 :eip158-block 0)))
         (byzantium (append eip158 '(:dao-fork-block 0 :byzantium-block 0)))
         (petersburg (append byzantium
                             '(:constantinople-block 0 :petersburg-block 0)))
         (istanbul (append petersburg '(:istanbul-block 0)))
         (berlin (append (remove-dao-fork-block istanbul)
                         '(:muir-glacier-block 0 :berlin-block 0)))
         (london (append berlin '(:london-block 0)))
         (arrow-glacier (append london '(:arrow-glacier-block 0))))
    `(("Frontier")
      ("Homestead" ,@homestead)
      ("EIP150" ,@eip150)
      ("EIP158" ,@eip158)
      ("Byzantium" ,@byzantium)
      ("Constantinople" ,@byzantium
       :constantinople-block 0 :petersburg-block 10000000)
      ("ConstantinopleFix" ,@petersburg)
      ("Istanbul" ,@istanbul)
      ("MuirGlacier" ,@istanbul :muir-glacier-block 0)
      ("FrontierToHomesteadAt5" :homestead-block 5)
      ("HomesteadToEIP150At5" :homestead-block 0 :eip150-block 5)
      ("HomesteadToDaoAt5" :homestead-block 0 :dao-fork-block 5
       :dao-fork-support t)
      ("EIP158ToByzantiumAt5" ,@eip158 :byzantium-block 5)
      ("ByzantiumToConstantinopleAt5" ,@(remove-dao-fork-block byzantium)
       :constantinople-block 5)
      ("ByzantiumToConstantinopleFixAt5" ,@(remove-dao-fork-block byzantium)
       :constantinople-block 5 :petersburg-block 5)
      ("ConstantinopleFixToIstanbulAt5" ,@(remove-dao-fork-block petersburg)
       :istanbul-block 5)
      ("Berlin" ,@berlin)
      ("BerlinToLondonAt5" ,@berlin :london-block 5)
      ("London" ,@london)
      ("ArrowGlacier" ,@arrow-glacier)
      ("ArrowGlacierToParisAtDiffC0000" ,@arrow-glacier
       :gray-glacier-block 0 :merge-netsplit-block 0
       :terminal-total-difficulty #xC0000)
      ("GrayGlacier" ,@arrow-glacier :gray-glacier-block 0)
      ("Paris" ,@arrow-glacier :merge-netsplit-block 0
       :terminal-total-difficulty 0)
      ("Merge" ,@arrow-glacier :merge-netsplit-block 0
       :terminal-total-difficulty 0))))

(defun pre-merge-eest-network-p (network)
  (and (assoc network +pre-merge-eest-networks+ :test #'string=) t))

(defun pre-merge-eest-chain-config (fixture)
  "go-ethereum's tests/init.go configuration for FIXTURE's network."
  (let* ((network (fixture-required-field fixture "network"))
         (entry (assoc network +pre-merge-eest-networks+ :test #'string=))
         (chain-id (hex-to-quantity
                    (or (fixture-object-field
                         (fixture-object-field fixture "config") "chainid")
                        "0x1"))))
    (unless entry
      (error "Unsupported pre-Merge fixture network ~A" network))
    (apply #'make-chain-config
           :chain-id chain-id
           (append (rest entry)
                   (unless (getf (rest entry) :terminal-total-difficulty)
                     (list :terminal-total-difficulty
                           +pre-merge-eest-max-int64+))))))

(defun pre-merge-eest-verdict-condition-p (condition)
  "Whether CONDITION is a verdict on a block, as opposed to a harness or
internal failure: a decoding failure, or a block or transaction validation
error."
  (typep condition
         '(or rlp-error
              ethereum-lisp.validation:data-decoding-error
              block-validation-error
              ethereum-lisp.execution:transaction-validation-error)))

(defun pre-merge-eest-decode-block (block-case)
  "BLOCK-CASE's block, or NIL and the decoding condition."
  (handler-case
      (values (block-from-rlp
               (hex-to-bytes (fixture-required-field block-case "rlp")))
              nil)
    (error (condition)
      (values nil condition))))

(defun pre-merge-eest-import-block (store block config)
  "Admit BLOCK and make it the head; return NIL, or the verdict condition.

Any other condition escapes: it is a harness or internal failure, never a
verdict the fixture could have expected."
  (handler-case
      (progn
        (import-block-candidate store block config)
        (publish-canonical-block store block config
                                 :authority :local-dev
                                 :local-dev-authorized-p t)
        nil)
    (error (condition)
      (if (pre-merge-eest-verdict-condition-p condition)
          condition
          (error condition)))))

(defun pre-merge-eest-install-genesis (store fixture name)
  (let* ((label (format nil "pre-Merge EEST case ~A genesisBlockHeader" name))
         (header (eest-blockchain-engine-genesis-header fixture label))
         (genesis (make-block :header header))
         (pre-state (amsterdam-eest-pre-state fixture))
         (expected-hash (fixture-required-field
                         (fixture-required-field fixture "genesisBlockHeader")
                         "hash")))
    (unless (string= expected-hash (hash32-to-hex (block-hash genesis)))
      (error "~A genesis hashes to ~A, fixture says ~A"
             name (hash32-to-hex (block-hash genesis)) expected-hash))
    (unless (hash32= (state-db-root pre-state) (block-header-state-root header))
      (error "~A pre-state root ~A, genesis says ~A"
             name (hash32-to-hex (state-db-root pre-state))
             (hash32-to-hex (block-header-state-root header))))
    (engine-payload-store-put-block store genesis :state-available-p t)
    (commit-state-db-to-chain-store store (block-hash genesis) pre-state)
    genesis))

(defun pre-merge-eest-run-case (case)
  "Replay every block of CASE; signal on the first divergence."
  (let* ((name (fixture-required-field case "name"))
         (fixture (fixture-required-field case "fixture"))
         (config (pre-merge-eest-chain-config fixture))
         (store (make-engine-payload-memory-store))
         (*ethash-seal-verifier* (constantly t)))
    (pre-merge-eest-install-genesis store fixture name)
    (loop for block-case in (fixture-required-field fixture "blocks")
          for index from 0
          for expected = (fixture-field-present-p block-case "expectException")
          do (multiple-value-bind (block decode-condition)
                 (pre-merge-eest-decode-block block-case)
               (let ((verdict
                       (or decode-condition
                           (pre-merge-eest-import-block store block config))))
                 (cond
                   ((and verdict (not expected))
                    (error "~A block ~D refused: ~A"
                           name index
                           (amsterdam-eest-condition-summary verdict)))
                   ((and expected (not verdict))
                    (error "~A block ~D accepted, expected ~A"
                           name index
                           (fixture-object-field block-case
                                                 "expectException")))))))
    (let ((head (chain-store-latest-block store))
          (last-hash (fixture-required-field fixture "lastblockhash")))
      (unless (string= last-hash (hash32-to-hex (block-hash head)))
        (error "~A head ~A, lastblockhash ~A"
               name (hash32-to-hex (block-hash head)) last-hash))
      (assert-eest-blockchain-post-state
       (chain-store-state-db store (block-hash head)) case))
    t))

;;; Directory scoring

(defstruct (pre-merge-eest-tally (:constructor make-pre-merge-eest-tally
                                     (directory)))
  directory
  (passed 0)
  (failed 0)
  (oversize-files 0)
  (samples '())
  ;; (NETWORK PASSED . FAILED), in first-seen order
  (networks '()))

(defun pre-merge-eest-tally-network-entry (tally network)
  (or (assoc network (pre-merge-eest-tally-networks tally) :test #'string=)
      (let ((entry (list* network 0 0)))
        (setf (pre-merge-eest-tally-networks tally)
              (append (pre-merge-eest-tally-networks tally) (list entry)))
        entry)))

(defun pre-merge-eest-score-case (tally case)
  (let* ((network (fixture-required-field
                   (fixture-required-field case "fixture") "network"))
         (entry (pre-merge-eest-tally-network-entry tally network))
         (outcome
           (handler-case (progn (pre-merge-eest-run-case case) nil)
             (serious-condition (condition)
               (format nil "~A: ~A"
                       (fixture-required-field case "name")
                       (amsterdam-eest-condition-summary condition))))))
    (if outcome
        (progn
          (incf (pre-merge-eest-tally-failed tally))
          (incf (cddr entry))
          (when (< (length (pre-merge-eest-tally-samples tally))
                   *pre-merge-eest-failure-samples*)
            (push outcome (pre-merge-eest-tally-samples tally))))
        (progn
          (incf (pre-merge-eest-tally-passed tally))
          (incf (cadr entry))))))

(defun pre-merge-eest-selected-case-p (case networks)
  (let ((network (fixture-object-field
                  (fixture-required-field case "fixture") "network")))
    (and (stringp network)
         (pre-merge-eest-network-p network)
         (or (null networks)
             (member network networks :test #'string=)))))

(defun pre-merge-eest-score-directory (root directory &key networks)
  "Score every selected pre-Merge case under ROOT's DIRECTORY (`fork/dir')."
  (let ((tally (make-pre-merge-eest-tally directory))
        (directory-root
          (merge-pathnames
           (make-pathname :directory
                          (cons :relative
                                (eest-fixture-split-string directory #\/)))
           root)))
    (dolist (path (execution-spec-tests-json-paths directory-root))
      (if (> (eest-fixture-file-byte-size path) *pre-merge-eest-max-file-bytes*)
          (incf (pre-merge-eest-tally-oversize-files tally))
          (dolist (case (load-eest-blockchain-test-root-file-cases
                         directory-root path))
            (when (pre-merge-eest-selected-case-p case networks)
              (pre-merge-eest-score-case tally case)))))
    tally))

(defun pre-merge-eest-report-line (tally)
  (format nil "PRE-MERGE-EEST blockchain_tests ~A: cases=~D passed=~D failed=~D~@[ oversizeFilesSkipped=~D~]~@[ [~{~A~^ ~}]~]"
          (pre-merge-eest-tally-directory tally)
          (+ (pre-merge-eest-tally-passed tally)
             (pre-merge-eest-tally-failed tally))
          (pre-merge-eest-tally-passed tally)
          (pre-merge-eest-tally-failed tally)
          (let ((skipped (pre-merge-eest-tally-oversize-files tally)))
            (and (plusp skipped) skipped))
          (loop for (network passed . failed)
                  in (pre-merge-eest-tally-networks tally)
                collect (format nil "~A:~D/~D" network passed
                                (+ passed failed)))))

(defun pre-merge-eest-blockchain-root (root)
  "ROOT's blockchain_tests directory when it holds the legacy fork layout."
  (loop for prefix in '("" "fixtures/")
        for candidate = (probe-file
                         (merge-pathnames
                          (format nil "~Ablockchain_tests/frontier/" prefix)
                          (pathname root)))
        when candidate
          return (merge-pathnames "../" candidate)))

(defun pre-merge-eest-directories (blockchain-root)
  "Every `fork/dir' directory under BLOCKCHAIN-ROOT, sorted, except the
static tree (the ported legacy state tests, filled from Cancun on only)."
  (sort
   (loop for fork-path in (directory
                           (merge-pathnames
                            (make-pathname :directory '(:relative :wild))
                            blockchain-root))
         for fork = (car (last (pathname-directory fork-path)))
         unless (string= fork "static")
           append (mapcar (lambda (path)
                            (format nil "~A/~A"
                                    fork (car (last (pathname-directory path)))))
                          (directory
                           (merge-pathnames
                            (make-pathname :directory '(:relative :wild))
                            fork-path))))
   #'string<))

(defun pre-merge-eest-burn-down (root &key directories networks)
  "Score every selected pre-Merge directory under ROOT; return the tallies
and print one report line per directory that has pre-Merge cases."
  (let ((blockchain-root (pre-merge-eest-blockchain-root root))
        (tallies '()))
    (dolist (directory (pre-merge-eest-directories blockchain-root))
      (when (or (null directories)
                (member directory directories :test #'string=))
        (let ((tally (pre-merge-eest-score-directory
                      blockchain-root directory :networks networks)))
          (when (or (plusp (+ (pre-merge-eest-tally-passed tally)
                              (pre-merge-eest-tally-failed tally)))
                    (plusp (pre-merge-eest-tally-oversize-files tally))
                    directories)
            (format t "~&~A~%" (pre-merge-eest-report-line tally))
            (dolist (sample (reverse (pre-merge-eest-tally-samples tally)))
              (format t "~&PRE-MERGE-EEST   first-failure ~A~%" sample))
            (finish-output)
            (push tally tallies)))))
    (let ((passed (reduce #'+ tallies :key #'pre-merge-eest-tally-passed))
          (failed (reduce #'+ tallies :key #'pre-merge-eest-tally-failed)))
      (format t "~&PRE-MERGE-EEST total: directories=~D cases=~D passed=~D failed=~D~%"
              (length tallies) (+ passed failed) passed failed))
    (nreverse tallies)))

(defun pre-merge-eest-required-failures (tallies required)
  "The REQUIRED directories that did not pass in full, as report strings."
  (loop for directory in required
        for tally = (find directory tallies
                          :key #'pre-merge-eest-tally-directory
                          :test #'string=)
        unless (and tally
                    (zerop (pre-merge-eest-tally-failed tally))
                    (zerop (pre-merge-eest-tally-oversize-files tally))
                    (plusp (pre-merge-eest-tally-passed tally)))
          collect (if tally
                      (pre-merge-eest-report-line tally)
                      (format nil "~A: not run" directory))))

(deftest optional-legacy-eest-pre-merge-blockchain-burn-down
  (:layer :integration :module :eest)
  (with-execution-spec-tests-fixture-root (root)
    (unless (pre-merge-eest-blockchain-root root)
      (skip-test
       "The EEST fixture root has no blockchain_tests/frontier tree (legacy v5.4.0)"))
    (call-with-eest-cryptographic-backends
     (lambda ()
       (let* ((tallies (pre-merge-eest-burn-down
                        root
                        :directories (amsterdam-eest-env-list
                                      +pre-merge-eest-directories-env+)
                        :networks (amsterdam-eest-env-list
                                   +pre-merge-eest-networks-env+)))
              (failures (pre-merge-eest-required-failures
                         tallies
                         (amsterdam-eest-env-list
                          +pre-merge-eest-required-env+))))
         (is tallies)
         (when failures
           (error "Required pre-Merge EEST directories did not pass:~{ ~A;~}"
                  failures)))))))
