(in-package #:ethereum-lisp.crypto)

;;;; RIPEMD-160, backed by Ironclad.
;;;;
;;;; A thin adapter over Ironclad's :RIPEMD-160 (see keccak.lisp for the
;;;; project's mature-crypto policy). Used by the RIPEMD-160 precompile. The
;;;; package's RIPEMD160 API is unchanged.

(defun ripemd160 (&rest chunks)
  "Return RIPEMD-160 of all byte CHUNKS concatenated."
  (let ((digest (ironclad:make-digest :ripemd-160)))
    (dolist (chunk chunks)
      (ironclad:update-digest digest (ironclad-digest-input chunk)))
    (ironclad:produce-digest digest)))

(defun ripemd160-hex (&rest chunks)
  (bytes-to-hex (apply #'ripemd160 chunks)))
