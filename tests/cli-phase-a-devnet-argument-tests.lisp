(in-package #:ethereum-lisp.test)

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

