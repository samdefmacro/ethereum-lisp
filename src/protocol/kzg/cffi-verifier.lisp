(in-package #:ethereum-lisp.kzg)

;;;; A KZG verifier backed by c-kzg-4844 through CFFI (libethckzg, built in the
;;;; Docker image from tools/ckzg-ffi/shim.c). This replaces the external
;;;; subprocess verifier on the default path.
;;;;
;;;; Loading is optional: a host without the shared library or its trusted
;;;; setup simply has no CFFI verifier, and KZG stays capability-gated exactly
;;;; as when the external helper binary is absent. The c-kzg settings are loaded
;;;; once and thereafter read-only, which is safe for concurrent verification
;;;; across the node's threads.

(cffi:define-foreign-library libethckzg
  (t (:default "libethckzg")))

(defvar *libethckzg-loaded-p*
  (handler-case (progn (cffi:use-foreign-library libethckzg) t)
    (error () nil))
  "True when libethckzg was found and loaded at image build time.")

(cffi:defcfun ("eth_ckzg_load_setup" %eth-ckzg-load-setup) :pointer
  (path :string) (precompute :uint64))
(cffi:defcfun ("eth_ckzg_verify_kzg_proof" %eth-ckzg-verify-kzg-proof) :int
  (settings :pointer) (commitment :pointer) (z :pointer) (y :pointer)
  (proof :pointer))
(cffi:defcfun ("eth_ckzg_verify_blob_kzg_proof" %eth-ckzg-verify-blob-kzg-proof) :int
  (settings :pointer) (blob :pointer) (commitment :pointer) (proof :pointer))

(defparameter *kzg-trusted-setup-path*
  #p"/usr/local/share/eth-kzg/trusted_setup.txt"
  "Where the Docker image stages c-kzg's mainnet trusted setup.")

(defvar *kzg-cffi-settings* nil
  "Cached c-kzg KZGSettings handle, or NIL until loaded.")

(defun kzg-cffi-settings ()
  "Load and cache the trusted setup, returning its handle or NIL."
  (cond
    ((not *libethckzg-loaded-p*) nil)
    (*kzg-cffi-settings* *kzg-cffi-settings*)
    ((not (probe-file *kzg-trusted-setup-path*)) nil)
    (t
     (let ((settings (%eth-ckzg-load-setup
                      (namestring *kzg-trusted-setup-path*) 0)))
       (unless (cffi:null-pointer-p settings)
         (setf *kzg-cffi-settings* settings))))))

(defun kzg-cffi-octets (bytes)
  (let ((bytes (ensure-byte-vector bytes)))
    (if (typep bytes '(simple-array (unsigned-byte 8) (*)))
        bytes
        (coerce bytes '(simple-array (unsigned-byte 8) (*))))))

(defun kzg-cffi-point-proof (commitment z y proof)
  "True when the EIP-4844 point proof verifies. Sizes are pre-validated by the
verify-kzg-point-proof wrapper."
  (let ((settings (kzg-cffi-settings)))
    (when settings
      (cffi:with-pointer-to-vector-data (cp (kzg-cffi-octets commitment))
        (cffi:with-pointer-to-vector-data (zp (kzg-cffi-octets z))
          (cffi:with-pointer-to-vector-data (yp (kzg-cffi-octets y))
            (cffi:with-pointer-to-vector-data (pp (kzg-cffi-octets proof))
              (= 1 (%eth-ckzg-verify-kzg-proof settings cp zp yp pp)))))))))

(defun kzg-cffi-blob-proof (blob commitment proof)
  "True when the EIP-4844 blob proof verifies. Sizes are pre-validated by the
verify-kzg-blob-proof wrapper."
  (let ((settings (kzg-cffi-settings)))
    (when settings
      (cffi:with-pointer-to-vector-data (bp (kzg-cffi-octets blob))
        (cffi:with-pointer-to-vector-data (cp (kzg-cffi-octets commitment))
          (cffi:with-pointer-to-vector-data (pp (kzg-cffi-octets proof))
            (= 1 (%eth-ckzg-verify-blob-kzg-proof settings bp cp pp))))))))

(defun kzg-cffi-verifier-available-p ()
  "True when the CFFI verifier can be built (library and setup both present)."
  (and *libethckzg-loaded-p* (kzg-cffi-settings) t))

(defun make-kzg-cffi-verifier ()
  "Return a KZG-VERIFIER backed by c-kzg-4844, or NIL when unavailable."
  (when (kzg-cffi-verifier-available-p)
    (make-kzg-verifier :point-proof-function #'kzg-cffi-point-proof
                       :blob-proof-function #'kzg-cffi-blob-proof)))
