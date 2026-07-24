(in-package #:ethereum-lisp.bls12381)

;;;; An EIP-2537 backend backed by blst through CFFI (libethbls, built in the
;;;; Docker image from tools/bls-ffi/shim.c). This replaces the external Go
;;;; subprocess backend on the default path.
;;;;
;;;; The shim is stateless -- every call marshals its input, runs blst, and
;;;; returns -- so the backend is safe to call concurrently from the node's
;;;; threads with no shared state. Loading is optional: a host without the
;;;; shared library simply has no CFFI backend and BLS stays capability-gated,
;;;; exactly as when the external helper is absent.

(cffi:define-foreign-library libethbls
  (t (:default "libethbls")))

(defvar *libethbls-loaded-p*
  (handler-case (progn (cffi:use-foreign-library libethbls) t)
    (error () nil))
  "True when libethbls was found and loaded at image build time.")

(macrolet ((defop (lisp-name c-name)
             `(cffi:defcfun (,c-name ,lisp-name) :int
                (input :pointer) (input-len :unsigned-long) (output :pointer))))
  (defop %bls-g1add "eth_bls_g1add")
  (defop %bls-g2add "eth_bls_g2add")
  (defop %bls-g1msm "eth_bls_g1msm")
  (defop %bls-g2msm "eth_bls_g2msm")
  (defop %bls-pairing "eth_bls_pairing")
  (defop %bls-mapfptog1 "eth_bls_mapfptog1")
  (defop %bls-mapfp2tog2 "eth_bls_mapfp2tog2"))

(defun bls12381-cffi-output-size (operation)
  (ecase operation
    ((:g1-add :g1-msm :map-fp-to-g1) 128)
    ((:g2-add :g2-msm :map-fp2-to-g2) 256)
    (:pairing-check 32)))

(defun bls12381-cffi-call (operation input-pointer input-length output-pointer)
  (ecase operation
    (:g1-add (%bls-g1add input-pointer input-length output-pointer))
    (:g2-add (%bls-g2add input-pointer input-length output-pointer))
    (:g1-msm (%bls-g1msm input-pointer input-length output-pointer))
    (:g2-msm (%bls-g2msm input-pointer input-length output-pointer))
    (:pairing-check (%bls-pairing input-pointer input-length output-pointer))
    (:map-fp-to-g1 (%bls-mapfptog1 input-pointer input-length output-pointer))
    (:map-fp2-to-g2 (%bls-mapfp2tog2 input-pointer input-length output-pointer))))

(defun bls12381-cffi-octets (bytes)
  (let ((bytes (ensure-byte-vector bytes)))
    (if (typep bytes '(simple-array (unsigned-byte 8) (*)))
        bytes
        (coerce bytes '(simple-array (unsigned-byte 8) (*))))))

(defun bls12381-cffi-backend-function (operation input)
  "Evaluate OPERATION over INPUT via blst, returning the output byte vector or
signalling BLS12381-INPUT-ERROR when the shim rejects the input.

The shim returns non-zero for every EIP-2537 validity failure -- wrong length,
non-canonical field element, off-curve point, wrong subgroup -- which is a
deterministic verdict every node shares, hence an input error rather than an
unavailability."
  (let ((input (bls12381-cffi-octets input)))
    ;; Every EIP-2537 operation rejects an empty input, and an empty vector has
    ;; no data pointer to pin, so treat it as an input error directly.
    (when (zerop (length input))
      (bls12381-input-error "empty EIP-2537 input"))
    (let ((output (make-byte-vector (bls12381-cffi-output-size operation))))
      (cffi:with-pointer-to-vector-data (input-pointer input)
        (cffi:with-pointer-to-vector-data (output-pointer output)
          (let ((code (bls12381-cffi-call operation input-pointer
                                          (length input) output-pointer)))
            (if (zerop code)
                output
                (bls12381-input-error "invalid EIP-2537 input"))))))))

(defun bls12381-cffi-backend-available-p ()
  "True when the blst CFFI backend can be used (the library loaded)."
  (and *libethbls-loaded-p* t))

(defun make-bls12381-cffi-backend ()
  "Return an EIP-2537 backend function backed by blst, or NIL when unavailable."
  (when (bls12381-cffi-backend-available-p)
    #'bls12381-cffi-backend-function))
