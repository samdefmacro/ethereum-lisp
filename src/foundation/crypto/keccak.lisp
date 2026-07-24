(in-package #:ethereum-lisp.crypto)

;;;; Ethereum legacy Keccak-256, backed by Ironclad.
;;;;
;;;; Per the project contract (PROJECT.md, "Dependencies and Cryptography"),
;;;; cryptographic primitives prefer a mature, well-reviewed implementation over
;;;; bespoke code. Ironclad's :KECCAK/256 is the original Keccak padding (0x01)
;;;; Ethereum uses, NOT NIST SHA3-256 (0x06) -- the two are distinct digests in
;;;; Ironclad and only :KECCAK/256 reproduces Ethereum's hashes. This module is
;;;; a thin adapter that keeps the crypto package's existing API stable while
;;;; delegating the permutation and sponge to Ironclad.

(defconstant +keccak-256-digest+ :keccak/256)

(defun keccak-input (chunk)
  "Coerce CHUNK to the simple octet vector Ironclad's digest functions expect."
  (let ((bytes (ensure-byte-vector chunk)))
    (if (typep bytes '(simple-array (unsigned-byte 8) (*)))
        bytes
        (coerce bytes '(simple-array (unsigned-byte 8) (*))))))

;;; Incremental sponge. Exposed as make / update / digest because the RLPx
;;; running MAC keeps a Keccak state alive, feeds it each frame, and reads it
;;; between updates. An Ironclad digest object stands in for the old sponge
;;; struct; callers treat it as opaque.

(defun make-keccak-256 ()
  "Return a fresh incremental Keccak-256 sponge."
  (ironclad:make-digest +keccak-256-digest+))

(defun keccak-256-update (sponge chunk)
  "Absorb CHUNK into SPONGE and return SPONGE."
  (ironclad:update-digest sponge (keccak-input chunk))
  sponge)

(defun keccak-256-digest (sponge)
  "Return the 32-byte digest of what SPONGE has absorbed, without mutating it.

PRODUCE-DIGEST finalizes (pads) the state it is given, so it runs on a COPY;
SPONGE keeps absorbing afterward, which is exactly how the RLPx running MAC is
peeked between frames."
  (ironclad:produce-digest (ironclad:copy-digest sponge)))

(defun keccak-256 (&rest chunks)
  "Return Ethereum legacy Keccak-256 of all byte CHUNKS concatenated."
  (let ((digest (ironclad:make-digest +keccak-256-digest+)))
    (dolist (chunk chunks)
      (ironclad:update-digest digest (keccak-input chunk)))
    (ironclad:produce-digest digest)))

(defun keccak-256-hash (&rest chunks)
  (make-hash32 (apply #'keccak-256 chunks)))

(defun keccak-256-hex (&rest chunks)
  (bytes-to-hex (apply #'keccak-256 chunks)))

(defparameter +empty-code-hash+ (keccak-256-hash #()))
(defparameter +empty-trie-hash+ (keccak-256-hash #(128)))
