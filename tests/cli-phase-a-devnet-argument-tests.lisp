(in-package #:ethereum-lisp.test)

(deftest devnet-cli-rejects-unimplemented-ipc-options
  ;; The --rpc.* limits used to be refused here too; they are wired now
  ;; (RPC-BUDGET-FLAGS-ARE-PARSED-AND-REACH-EVERY-LISTENER).
  (dolist (args '(("--ipcpath" "/tmp/geth.ipc")
                  ("--ipcapi" "eth,net")
                  ("--ipcdisable")))
    (handler-case
        (progn
          (ethereum-lisp.cli::devnet-cli-options args)
          (error "Option unexpectedly accepted: ~A" (first args)))
      (error (condition)
        (is (search "IPC is not implemented" (format nil "~A" condition)))))))

(deftest devnet-smoke-gate-script-rejects-malformed-boolean-assignment
  #-sbcl
  (skip-test "Devnet smoke gate script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/devnet-smoke-gate.lisp"
             "--"
             "--json=maybe")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "--json boolean value must be true or false" stderr))))

