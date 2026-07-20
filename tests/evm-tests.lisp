(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-evm-tests-root*
  *repository-root*)

(defun load-evm-test-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-evm-tests-root*)))

;; This loop is deliberately just over the historical implicit 100,000-step
;; interpreter ceiling while remaining cheap enough for regression tests.
;;
;;   PUSH2 iterations                         1 step,  3 gas
;;   JUMPDEST/PUSH1/SWAP1/SUB/DUP1/PUSH1/JUMPI
;;                                            7 steps, 26 gas per iteration
;;   POP/STOP                                 2 steps,  2 gas
(defconstant +evm-long-loop-iterations+ 15000)
(defconstant +evm-long-loop-steps+ 105003)
(defconstant +evm-long-loop-gas+ 390005)

;; Replacing POP/STOP with POP/PUSH1/PUSH1/RETURN makes the same loop useful
;; as initcode that deploys empty runtime code.
(defconstant +evm-long-loop-initcode-steps+ 105005)
(defconstant +evm-long-loop-initcode-gas+ 390011)

(defun evm-long-loop-code ()
  "Return fresh finite bytecode that executes 105,003 EVM instructions."
  (concat-bytes
   #(#x61 #x3a #x98              ; PUSH2 15000
     #x5b                        ; loop: JUMPDEST
     #x60 #x01 #x90 #x03 #x80   ; counter := counter - 1; DUP1
     #x60 #x03 #x57)             ; PUSH1 loop; JUMPI
   #(#x50 #x00)))                ; POP; STOP

(defun evm-long-loop-initcode ()
  "Return fresh 105,005-step initcode that deploys empty runtime code."
  (concat-bytes
   #(#x61 #x3a #x98
     #x5b
     #x60 #x01 #x90 #x03 #x80
     #x60 #x03 #x57)
   #(#x50 #x60 #x00 #x60 #x00 #xf3)))

(defun capture-evm-error-message (thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (evm-error (condition)
      (princ-to-string condition))))

(defun capture-evm-step-limit-error (thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (evm-step-limit-error (condition)
      condition)))

(dolist (relative-path
         '("tests/evm-core-tests.lisp"
           "tests/evm-memory-control-tests.lisp"
           "tests/evm-storage-access-tests.lisp"
           "tests/evm-context-environment-tests.lisp"
           "tests/evm-call-tests.lisp"
           "tests/evm-precompile-tests.lisp"
           "tests/evm-call-family-tests.lisp"
           "tests/evm-create-tests.lisp"
           "tests/evm-osaka-tests.lisp"))
  (load-evm-test-file relative-path))
