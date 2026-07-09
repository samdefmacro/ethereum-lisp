(in-package #:ethereum-lisp.test)

(defun devnet-smoke-gate-launch-json-process ()
  (uiop:launch-program
   (list "sbcl"
         "--script"
         "scripts/devnet-smoke-gate.lisp"
         "--"
         "--json")
   :output :stream
   :error-output :stream))

(defun devnet-smoke-gate-finish-json-process (process)
  (let ((status (uiop:wait-process process))
        (stdout
          (devnet-cli-read-stream-string (uiop:process-info-output process)))
        (stderr
          (devnet-cli-read-stream-string
           (uiop:process-info-error-output process))))
    (values stdout stderr status)))

(deftest devnet-smoke-gate-script-help-prints-without-loading-errors
  #-sbcl
  (skip-test "Devnet smoke gate script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/devnet-smoke-gate.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/devnet-smoke-gate.lisp"
                stdout))
    (is (search "--all-fixtures" stdout))
    (is (search "--engine-only-serve" stdout))
    (is (search "--ready-file PATH" stdout))
    (is (search "--log-file PATH" stdout))
    (is (search "--pid-file PATH" stdout))
    (is (search "--database PATH" stdout))
    (is (search "--prune-state-before NUMBER" stdout))
    (is (search "--override.terminaltotaldifficulty TTD" stdout))
    (is (search "--override.terminaltotaldifficultypassed" stdout))
    (is (search "--override.terminalblockhash HASH" stdout))
    (is (search "--override.terminalblocknumber NUMBER" stdout))
    (is (search "ETHEREUM_LISP_GETH_ROOT" stdout))
    (is (search "ETHEREUM_LISP_NETHERMIND_ROOT" stdout))
    (is (search "ETHEREUM_LISP_RETH_ROOT" stdout))))

