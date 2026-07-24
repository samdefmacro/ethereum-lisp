(defpackage #:ethereum-lisp.bls12381
  (:use #:cl
        #:ethereum-lisp.bytes
        #:ethereum-lisp.hex
        #:ethereum-lisp.types)
  (:export
   #:*bls12381-backend*
   #:*bls12381-backend-timeout-seconds*
   #:bls12381-backend-available-p
   #:run-bls12381-operation
   #:bls12381-error
   #:bls12381-error-message
   #:bls12381-input-error
   #:bls12381-unavailable-error
   #:+bls12381-operations+
   #:bls12381-command-backend
   #:make-bls12381-command-backend
   #:configure-bls12381-command-backend
   #:shutdown-bls12381-command-backend
   #:make-bls12381-cffi-backend
   #:bls12381-cffi-backend-available-p))
