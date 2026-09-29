(in-package #:ethereum-lisp.test)

;;;; Legacy ethereum/tests blockchain fixtures for rules no pinned corpus
;;;; exercises: ommer rewards and the DAO transition.
;;;;
;;;; Neither EEST v5.4.0 nor tests@v20.0.2 carries a block with an ommer or a
;;;; `HomesteadToDaoAt5' network (docs/gap-analysis/mainnet-inventory.md). The
;;;; ethereum/tests filler did, until those networks were retired; six files
;;;; are vendored verbatim from tag v6.0.0-beta.3 (commit
;;;; 725dbc73a54649e22a00330bd0f4d6699a5060e5) under
;;;; tests/fixtures/ethereum-tests-v6.0.0-beta.3/, at their upstream paths,
;;;; and each is checked against the SHA-256 below before it is read. They
;;;; replay through PRE-MERGE-EEST-RUN-CASE, go-ethereum v1.17.6 BlockTest.Run's
;;;; procedure: every block admitted through IMPORT-BLOCK-CANDIDATE (its state
;;;; root derived), `lastblockhash' the head, `postState' the head's state.

(defparameter *premerge-legacy-fixture-root*
  (merge-pathnames "tests/fixtures/ethereum-tests-v6.0.0-beta.3/"
                   *repository-root*))

(defparameter *premerge-legacy-fixtures*
  ;; (path sha256 cases): the case count each file must yield.
  '(("BlockchainTests/bcUncleTest/oneUncle.json"
     "84142ab9955508f5c649f30f34f835a6540206cc60b5efff5a3bd0d262bcf476" 6)
    ("BlockchainTests/bcUncleTest/twoUncle.json"
     "423f8d7c1c824b8fa56c993923112850f66d17eb2d7b5ec2d011bad46b68110d" 6)
    ("BlockchainTests/TransitionTests/bcHomesteadToDao/DaoTransactions.json"
     "8c2df0b6c66a0c440be43c22a3822cca36c7ecda2ed730ce8ddd0ef893f79873" 1)
    ("BlockchainTests/TransitionTests/bcHomesteadToDao/DaoTransactions_EmptyTransactionAndForkBlocksAhead.json"
     "167b61a093806d7eb73ca7f704ef198bd111d35d1160b184c421e19c55ac90b1" 1)
    ("BlockchainTests/TransitionTests/bcHomesteadToDao/DaoTransactions_UncleExtradata.json"
     "4d25f3946917f507723516f9b578ebd6b01823ff05ef45b548e3aecb3555f6ab" 1)
    ("BlockchainTests/TransitionTests/bcHomesteadToDao/DaoTransactions_XBlockm1.json"
     "b580e32f434d297645cb2d23135ab610a00ad07f6a6cf84a9eceb7883c4ed3b7" 1)))

(defun premerge-legacy-file-sha256 (path)
  (with-open-file (in path :element-type '(unsigned-byte 8))
    (let ((bytes (make-array (file-length in) :element-type '(unsigned-byte 8))))
      (read-sequence bytes in)
      (subseq (sha256-hex bytes) 2))))

(defun premerge-legacy-run-file (relative-path sha256)
  "Replay every case of the vendored RELATIVE-PATH; return the case names that
passed and the failure reports."
  (let ((path (merge-pathnames relative-path *premerge-legacy-fixture-root*))
        (passed '())
        (failed '()))
    (unless (string= sha256 (premerge-legacy-file-sha256 path))
      (error "Vendored fixture ~A does not hash to ~A" relative-path sha256))
    (dolist (case (load-eest-blockchain-test-root-file-cases
                   *premerge-legacy-fixture-root* path))
      (let ((name (fixture-required-field case "name")))
        (handler-case (progn (pre-merge-eest-run-case case)
                             (push name passed))
          (serious-condition (condition)
            (push (format nil "~A: ~A" name
                          (amsterdam-eest-condition-summary condition))
                  failed)))))
    (values (nreverse passed) (nreverse failed))))

(deftest premerge-legacy-ommer-and-dao-fixtures-replay
  (:layer :integration :module :eest)
  ;; Frontier, Homestead, EIP150, EIP158, Byzantium and Constantinople blocks
  ;; carrying one and two ommers, and the HomesteadToDaoAt5 transition: the
  ;; drain at block 5, the dao-hard-fork extra data for ten blocks (and its
  ;; refusal on a block and on an ommer), and a fork across the transition.
  (let ((total 0))
    (dolist (entry *premerge-legacy-fixtures*)
      (destructuring-bind (relative-path sha256 cases) entry
        (multiple-value-bind (passed failed)
            (premerge-legacy-run-file relative-path sha256)
          (format t "~&PRE-MERGE-LEGACY ~A: cases=~D passed=~D failed=~D~{~%PRE-MERGE-LEGACY   failure ~A~}~%"
                  relative-path (+ (length passed) (length failed))
                  (length passed) (length failed) failed)
          (incf total (length passed))
          (is (null failed))
          (is (= cases (length passed))))))
    (is (= 16 total))))
