(in-package #:ethereum-lisp.crypto)

;;;; SHA-256, backed by Ironclad.
;;;;
;;;; A thin adapter over Ironclad's :SHA256 (see keccak.lisp for the project's
;;;; mature-crypto policy). The package's SHA256 API is unchanged: each takes
;;;; any number of byte chunks and hashes their concatenation.

(defun sha256 (&rest chunks)
  "Return SHA-256 of all byte CHUNKS concatenated."
  (let ((digest (ironclad:make-digest :sha256)))
    (dolist (chunk chunks)
      (ironclad:update-digest digest (ironclad-digest-input chunk)))
    (ironclad:produce-digest digest)))

(defun sha256-hash (&rest chunks)
  (make-hash32 (apply #'sha256 chunks)))

(defun sha256-hex (&rest chunks)
  (bytes-to-hex (apply #'sha256 chunks)))
