(in-package #:ethereum-lisp.crypto)

;;;; libsecp256k1 binding.
;;;;
;;;; Per the project contract's crypto policy, the elliptic-curve operations use
;;;; libsecp256k1 -- the bitcoin-core reference library geth also uses -- rather
;;;; than bespoke Lisp point arithmetic. It is constant-time and audited, and
;;;; it is the only maintained option that provides ECDSA public-key recovery
;;;; (ecrecover), which Ironclad does not. This file is the raw FFI layer;
;;;; secp256k1.lisp holds the package's public API on top of it.
;;;;
;;;; Everything is marshalled through stack foreign objects; no foreign memory
;;;; outlives a call. The one shared piece of state is the context, created and
;;;; randomised once at load and thereafter used read-only, which libsecp256k1
;;;; documents as safe for concurrent signing/verification across threads.

(cffi:define-foreign-library libsecp256k1
  (:unix (:or "libsecp256k1.so" "libsecp256k1.so.1" "libsecp256k1.so.5"))
  (t (:default "libsecp256k1")))

(cffi:use-foreign-library libsecp256k1)

(defconstant +secp256k1-context-none+ 1)
(defconstant +secp256k1-ec-uncompressed+ 2)
(defconstant +secp256k1-ec-compressed+ #x102)
(defconstant +secp256k1-pubkey-size+ 64
  "sizeof(secp256k1_pubkey): an opaque 64-byte struct.")
(defconstant +secp256k1-signature-size+ 64
  "sizeof(secp256k1_ecdsa_signature).")
(defconstant +secp256k1-recoverable-signature-size+ 65
  "sizeof(secp256k1_ecdsa_recoverable_signature).")

;; size_t arguments are pointer-width; passing them as :uint truncates the
;; output-length out-parameter and corrupts the stack on LP64.
(cffi:defcfun ("secp256k1_context_create" %secp256k1-context-create) :pointer
  (flags :uint))
(cffi:defcfun ("secp256k1_context_randomize" %secp256k1-context-randomize) :int
  (ctx :pointer) (seed32 :pointer))
(cffi:defcfun ("secp256k1_ec_pubkey_create" %secp256k1-ec-pubkey-create) :int
  (ctx :pointer) (pubkey :pointer) (seckey32 :pointer))
(cffi:defcfun ("secp256k1_ec_pubkey_serialize" %secp256k1-ec-pubkey-serialize) :int
  (ctx :pointer) (output :pointer) (output-len :pointer) (pubkey :pointer)
  (flags :uint))
(cffi:defcfun ("secp256k1_ec_pubkey_parse" %secp256k1-ec-pubkey-parse) :int
  (ctx :pointer) (pubkey :pointer) (input :pointer) (input-len :unsigned-long))
(cffi:defcfun ("secp256k1_ecdsa_recoverable_signature_parse_compact"
               %secp256k1-recoverable-parse) :int
  (ctx :pointer) (sig :pointer) (input64 :pointer) (recid :int))
(cffi:defcfun ("secp256k1_ecdsa_recoverable_signature_serialize_compact"
               %secp256k1-recoverable-serialize) :int
  (ctx :pointer) (output64 :pointer) (recid :pointer) (sig :pointer))
(cffi:defcfun ("secp256k1_ecdsa_recover" %secp256k1-ecdsa-recover) :int
  (ctx :pointer) (pubkey :pointer) (sig :pointer) (msg32 :pointer))
(cffi:defcfun ("secp256k1_ecdsa_sign_recoverable" %secp256k1-sign-recoverable) :int
  (ctx :pointer) (sig :pointer) (msg32 :pointer) (seckey32 :pointer)
  (noncefp :pointer) (ndata :pointer))
(cffi:defcfun ("secp256k1_ecdsa_signature_parse_compact"
               %secp256k1-signature-parse) :int
  (ctx :pointer) (sig :pointer) (input64 :pointer))
(cffi:defcfun ("secp256k1_ecdsa_signature_normalize"
               %secp256k1-signature-normalize) :int
  (ctx :pointer) (out :pointer) (in :pointer))
(cffi:defcfun ("secp256k1_ecdsa_verify" %secp256k1-ecdsa-verify) :int
  (ctx :pointer) (sig :pointer) (msg32 :pointer) (pubkey :pointer))
(cffi:defcfun ("secp256k1_ecdh" %secp256k1-ecdh) :int
  (ctx :pointer) (output32 :pointer) (pubkey :pointer) (seckey32 :pointer)
  (hashfp :pointer) (data :pointer))

;;; ECDH returning the raw X coordinate, the agreement devp2p ECIES uses; the
;;; library default instead hashes the compressed point with SHA-256.
(cffi:defcallback secp256k1-ecdh-raw-x :int
    ((output :pointer) (x :pointer) (y :pointer) (data :pointer))
  (declare (ignore y data))
  (dotimes (i 32)
    (setf (cffi:mem-aref output :uint8 i) (cffi:mem-aref x :uint8 i)))
  1)

;;; Nonce override so a caller (a test) can pin k. The value is read from a
;;; dynamic variable, which is thread-local under SBCL, so a pinned signature
;;; on one thread never disturbs default signing on another.
(defvar *secp256k1-pinned-nonce* nil
  "A 32-byte big-endian nonce to force, or NIL for the RFC 6979 default.")
(cffi:defcallback secp256k1-pinned-nonce :int
    ((nonce32 :pointer) (msg32 :pointer) (key32 :pointer) (algo16 :pointer)
     (data :pointer) (attempt :uint))
  (declare (ignore msg32 key32 algo16 data))
  (if (and *secp256k1-pinned-nonce* (zerop attempt))
      (progn
        (dotimes (i 32)
          (setf (cffi:mem-aref nonce32 :uint8 i)
                (aref *secp256k1-pinned-nonce* i)))
        1)
      0))

(defvar *secp256k1-context* nil)

(defun secp256k1-context ()
  (or *secp256k1-context*
      (let ((ctx (%secp256k1-context-create +secp256k1-context-none+)))
        (when (cffi:null-pointer-p ctx)
          (error "libsecp256k1 context creation failed"))
        ;; Randomise against side-channel leakage during signing. Failure to
        ;; randomise is not fatal; the context is still correct.
        (cffi:with-foreign-object (seed :uint8 32)
          (let ((bytes (secure-random-bytes 32)))
            (dotimes (i 32) (setf (cffi:mem-aref seed :uint8 i) (aref bytes i))))
          (%secp256k1-context-randomize ctx seed))
        (setf *secp256k1-context* ctx))))

;;; --- marshalling helpers -------------------------------------------------

(defun secp256k1-scalar-to-foreign (scalar buffer)
  "Write the 32-byte big-endian encoding of SCALAR into foreign BUFFER."
  (dotimes (i 32)
    (setf (cffi:mem-aref buffer :uint8 (- 31 i)) (ldb (byte 8 (* 8 i)) scalar)))
  buffer)

(defmacro secp256k1-with-input ((pointer bytes) &body body)
  "Bind POINTER to a fresh foreign copy of the octet vector BYTES."
  (let ((source (gensym "BYTES")) (index (gensym "I")))
    `(let ((,source ,bytes))
       (cffi:with-foreign-object (,pointer :uint8 (length ,source))
         (dotimes (,index (length ,source))
           (setf (cffi:mem-aref ,pointer :uint8 ,index) (aref ,source ,index)))
         ,@body))))

(defun secp256k1-foreign-to-bytes (pointer length)
  (let ((out (make-byte-vector length)))
    (dotimes (i length out) (setf (aref out i) (cffi:mem-aref pointer :uint8 i)))))

(defun secp256k1-serialize-pubkey-body (ctx pubkey)
  "Serialise a parsed PUBKEY to the 64-byte X||Y body (0x04 prefix stripped)."
  (cffi:with-foreign-object (out :uint8 65)
    (cffi:with-foreign-object (out-len :unsigned-long)
      (setf (cffi:mem-ref out-len :unsigned-long) 65)
      (%secp256k1-ec-pubkey-serialize ctx out out-len pubkey
                                      +secp256k1-ec-uncompressed+)
      (subseq (secp256k1-foreign-to-bytes out 65) 1))))

(defun secp256k1-parse-pubkey-body (ctx pubkey-body pubkey)
  "Parse the 64-byte X||Y PUBKEY-BODY into foreign PUBKEY; T on success."
  (let ((prefixed (concat-bytes (make-array 1 :element-type '(unsigned-byte 8)
                                              :initial-element 4)
                                pubkey-body)))
    (secp256k1-with-input (input prefixed)
      (= 1 (%secp256k1-ec-pubkey-parse ctx pubkey input 65)))))

;;; --- operations (raw byte in / byte out; the API layer adds validation) --

(defun secp256k1-ffi-derive-public-key (scalar)
  "64-byte X||Y public-key body for the private SCALAR, or NIL if invalid."
  (let ((ctx (secp256k1-context)))
    (cffi:with-foreign-object (seckey :uint8 32)
      (secp256k1-scalar-to-foreign scalar seckey)
      (cffi:with-foreign-object (pubkey :uint8 +secp256k1-pubkey-size+)
        (when (= 1 (%secp256k1-ec-pubkey-create ctx pubkey seckey))
          (secp256k1-serialize-pubkey-body ctx pubkey))))))

(defun secp256k1-ffi-recover (hash32 v r s)
  "Recover the 64-byte public-key body from HASH32 and signature V/R/S, or NIL."
  (let ((ctx (secp256k1-context))
        (compact (concat-bytes (integer-to-fixed-bytes r 32)
                               (integer-to-fixed-bytes s 32))))
    (secp256k1-with-input (msg hash32)
      (secp256k1-with-input (comp compact)
        (cffi:with-foreign-object (sig :uint8 +secp256k1-recoverable-signature-size+)
          (when (= 1 (%secp256k1-recoverable-parse ctx sig comp v))
            (cffi:with-foreign-object (pubkey :uint8 +secp256k1-pubkey-size+)
              (when (= 1 (%secp256k1-ecdsa-recover ctx pubkey sig msg))
                (secp256k1-serialize-pubkey-body ctx pubkey)))))))))

(defun secp256k1-ffi-sign (hash32 scalar &key pinned-nonce)
  "Sign HASH32 with private SCALAR, returning 65-byte r||s||recid, or NIL.
PINNED-NONCE, when supplied, is the 32-byte big-endian nonce to force."
  (let ((ctx (secp256k1-context)))
    (secp256k1-with-input (msg hash32)
      (cffi:with-foreign-object (seckey :uint8 32)
        (secp256k1-scalar-to-foreign scalar seckey)
        (cffi:with-foreign-object (sig :uint8 +secp256k1-recoverable-signature-size+)
          (let* ((*secp256k1-pinned-nonce* pinned-nonce)
                 (noncefp (if pinned-nonce
                              (cffi:callback secp256k1-pinned-nonce)
                              (cffi:null-pointer))))
            (when (= 1 (%secp256k1-sign-recoverable ctx sig msg seckey noncefp
                                                    (cffi:null-pointer)))
              (cffi:with-foreign-object (out :uint8 64)
                (cffi:with-foreign-object (recid :int)
                  (%secp256k1-recoverable-serialize ctx out recid sig)
                  (concat-bytes (secp256k1-foreign-to-bytes out 64)
                                (make-array 1 :element-type '(unsigned-byte 8)
                                              :initial-element
                                              (cffi:mem-ref recid :int))))))))))))

(defun secp256k1-ffi-verify (hash32 r s pubkey-body)
  "True when signature (R, S) verifies against PUBKEY-BODY over HASH32.
S is normalised first, so a high-S signature is accepted, matching the earlier
in-tree behaviour."
  (let ((ctx (secp256k1-context))
        (compact (concat-bytes (integer-to-fixed-bytes r 32)
                               (integer-to-fixed-bytes s 32))))
    (secp256k1-with-input (msg hash32)
      (secp256k1-with-input (comp compact)
        (cffi:with-foreign-object (pubkey :uint8 +secp256k1-pubkey-size+)
          (cffi:with-foreign-object (sig :uint8 +secp256k1-signature-size+)
            (and (secp256k1-parse-pubkey-body ctx pubkey-body pubkey)
                 (= 1 (%secp256k1-signature-parse ctx sig comp))
                 (progn (%secp256k1-signature-normalize ctx sig sig)
                        (= 1 (%secp256k1-ecdsa-verify ctx sig msg pubkey))))))))))

(defun secp256k1-ffi-ecdh (scalar pubkey-body)
  "32-byte raw-X ECDH secret of SCALAR and PUBKEY-BODY, or NIL if the key is bad."
  (let ((ctx (secp256k1-context)))
    (cffi:with-foreign-object (seckey :uint8 32)
      (secp256k1-scalar-to-foreign scalar seckey)
      (cffi:with-foreign-object (pubkey :uint8 +secp256k1-pubkey-size+)
        (when (secp256k1-parse-pubkey-body ctx pubkey-body pubkey)
          (cffi:with-foreign-object (out :uint8 32)
            (when (= 1 (%secp256k1-ecdh ctx out pubkey seckey
                                        (cffi:callback secp256k1-ecdh-raw-x)
                                        (cffi:null-pointer)))
              (secp256k1-foreign-to-bytes out 32))))))))

(defun secp256k1-ffi-parse-public-key-valid-p (pubkey-body)
  "True when the 64-byte PUBKEY-BODY is a valid curve point."
  (let ((ctx (secp256k1-context)))
    (cffi:with-foreign-object (pubkey :uint8 +secp256k1-pubkey-size+)
      (secp256k1-parse-pubkey-body ctx pubkey-body pubkey))))

(defun secp256k1-ffi-decompress (compressed)
  "Expand a 33-byte compressed key to the 64-byte X||Y body, or NIL if invalid."
  (let ((ctx (secp256k1-context)))
    (secp256k1-with-input (input compressed)
      (cffi:with-foreign-object (pubkey :uint8 +secp256k1-pubkey-size+)
        (when (= 1 (%secp256k1-ec-pubkey-parse ctx pubkey input 33))
          (secp256k1-serialize-pubkey-body ctx pubkey))))))
