(in-package #:ethereum-lisp.crypto)

;;;; Keccak-256.
;;;;
;;;; This file is compiled for speed, unlike the rest of the tree. Keccak is
;;;; the hottest primitive in the client -- every trie node, address, block and
;;;; transaction hash, receipt, and the SHA3 opcode go through it -- and the
;;;; generic-arithmetic version it replaces was ~45x slower. Two things made it
;;;; slow, both invisible without declarations: 64-bit lanes exceed a 62-bit
;;;; fixnum, so every LOGXOR consed a BIGNUM, and rotating via (ASH value count)
;;;; materialized a 127-bit intermediate before masking it back down.
;;;;
;;;; SAFETY stays at 1: array bounds are still checked, which costs about 3%
;;;; and is not worth trading away in consensus-critical code.

(declaim (optimize (speed 3) (safety 1) (debug 0)))

(deftype keccak-lane () '(unsigned-byte 64))
(deftype keccak-lanes () '(simple-array (unsigned-byte 64) (25)))

(defun make-keccak-lanes ()
  (make-array 25 :element-type '(unsigned-byte 64) :initial-element 0))

;;; Typed copies of the tables, so the inner loops index a specialized array
;;; rather than a T-vector of boxed values.
(defparameter +keccak-rotation-table+
  (coerce +keccak-rotation-offsets+ '(simple-array (unsigned-byte 8) (25))))

(defparameter +keccak-round-constant-table+
  (coerce +keccak-round-constants+ '(simple-array (unsigned-byte 64) (24))))

(declaim (inline keccak-rotl))
(defun keccak-rotl (value count)
  "Rotate VALUE left by COUNT bits within 64-bit modular arithmetic.

LDB over ASH is what lets SBCL select its modular-arithmetic transform, so the
oversized intermediate is never materialized as a bignum."
  (declare (type keccak-lane value) (type (integer 0 63) count))
  (if (zerop count)
      value
      (logior (ldb (byte 64 0) (ash value count))
              (ash value (- count 64)))))

(defun lane-index (x y)
  (+ x (* 5 y)))

(defun keccak-f1600 (state)
  (declare (type keccak-lanes state))
  ;; The scratch lanes are allocated once per permutation and stack-allocated,
  ;; where the previous version consed three fresh T-vectors on every one of
  ;; the 24 rounds.
  (let ((c (make-array 5 :element-type '(unsigned-byte 64)))
        (d (make-array 5 :element-type '(unsigned-byte 64)))
        (b (make-array 25 :element-type '(unsigned-byte 64)))
        (rotations +keccak-rotation-table+)
        (round-constants +keccak-round-constant-table+))
    (declare (type (simple-array (unsigned-byte 64) (5)) c d)
             (type keccak-lanes b)
             (type (simple-array (unsigned-byte 8) (25)) rotations)
             (type (simple-array (unsigned-byte 64) (24)) round-constants)
             (dynamic-extent c d b))
    (dotimes (round 24 state)
      (declare (type (integer 0 24) round))
      ;; theta
      (dotimes (x 5)
        (setf (aref c x)
              (logxor (aref state x)
                      (aref state (+ x 5))
                      (aref state (+ x 10))
                      (aref state (+ x 15))
                      (aref state (+ x 20)))))
      (dotimes (x 5)
        (setf (aref d x)
              (logxor (aref c (mod (+ x 4) 5))
                      (keccak-rotl (aref c (mod (1+ x) 5)) 1))))
      (dotimes (y 5)
        (dotimes (x 5)
          (let ((index (+ x (* 5 y))))
            (setf (aref state index) (logxor (aref state index) (aref d x))))))
      ;; rho + pi
      (dotimes (y 5)
        (dotimes (x 5)
          (let ((index (+ x (* 5 y))))
            (setf (aref b (+ y (* 5 (mod (+ (* 2 x) (* 3 y)) 5))))
                  (keccak-rotl (aref state index) (aref rotations index))))))
      ;; chi
      (dotimes (y 5)
        (dotimes (x 5)
          (let ((index (+ x (* 5 y))))
            (setf (aref state index)
                  (logxor (aref b index)
                          (logand (ldb (byte 64 0)
                                       (lognot (aref b (+ (mod (1+ x) 5)
                                                          (* 5 y)))))
                                  (aref b (+ (mod (+ x 2) 5) (* 5 y)))))))))
      ;; iota
      (setf (aref state 0)
            (logxor (aref state 0) (aref round-constants round))))))

(declaim (inline keccak-load-lane))
(defun keccak-load-lane (bytes start)
  "Little-endian 64-bit load, accumulating without leaving 64-bit arithmetic."
  (declare (type byte-vector bytes) (type fixnum start))
  (let ((value 0))
    (declare (type keccak-lane value))
    (dotimes (i 8 value)
      (setf value (logior value (ash (aref bytes (+ start i)) (* 8 i)))))))

(defun absorb-block (state block)
  (declare (type keccak-lanes state) (type byte-vector block))
  (dotimes (lane (floor +keccak-256-rate+ 8))
    (setf (aref state lane)
          (logxor (aref state lane) (keccak-load-lane block (* lane 8)))))
  (keccak-f1600 state))

;;; Incremental Keccak-256 sponge. RLPx keeps a running MAC keccak state that is
;;; updated with each frame's ciphertext and digested (peeked) between updates,
;;; so the sponge is exposed as init / update / digest as well as the one-shot
;;; KECCAK-256 built on top of it.

(defstruct (keccak-256-sponge (:constructor %make-keccak-256-sponge))
  (lanes (make-keccak-lanes) :type keccak-lanes)
  (block (make-byte-vector +keccak-256-rate+) :type byte-vector)
  (offset 0 :type fixnum))

(defun make-keccak-256 ()
  "Return a fresh incremental Keccak-256 sponge."
  (%make-keccak-256-sponge))

(defun keccak-256-update (sponge chunk)
  "Absorb CHUNK into SPONGE and return SPONGE."
  (let* ((lanes (keccak-256-sponge-lanes sponge))
         (block (keccak-256-sponge-block sponge))
         (input (ensure-byte-vector chunk))
         (length (length input))
         (start 0))
    (declare (type byte-vector input) (type fixnum length start))
    ;; Copied a block at a time rather than a byte at a time: REPLACE is a
    ;; block move, and the old loop paid a struct slot read and write per byte.
    (loop while (< start length)
          do (let* ((offset (keccak-256-sponge-offset sponge))
                    (take (min (- +keccak-256-rate+ offset) (- length start))))
               (declare (type fixnum offset take))
               (replace block input
                        :start1 offset
                        :start2 start
                        :end2 (+ start take))
               (incf start take)
               (setf (keccak-256-sponge-offset sponge) (+ offset take))
               (when (= (keccak-256-sponge-offset sponge) +keccak-256-rate+)
                 (absorb-block lanes block)
                 (fill block 0)
                 (setf (keccak-256-sponge-offset sponge) 0)))))
  sponge)

(defun keccak-256-digest (sponge)
  "Return the 32-byte digest of what SPONGE has absorbed, without mutating it.

The pad-and-squeeze runs on copies of the lanes and block, so SPONGE can keep
absorbing afterward — which is exactly how the RLPx running MAC is peeked."
  (let ((lanes (copy-seq (keccak-256-sponge-lanes sponge)))
        (block (copy-seq (keccak-256-sponge-block sponge)))
        (offset (keccak-256-sponge-offset sponge)))
    (setf (aref block offset) (logxor (aref block offset) #x01)
          (aref block (1- +keccak-256-rate+))
          (logxor (aref block (1- +keccak-256-rate+)) #x80))
    (absorb-block lanes block)
    (let ((out (make-byte-vector 32)))
      (dotimes (lane 4)
        (store-little-endian-u64 (aref lanes lane) out (* lane 8)))
      out)))

(defun keccak-256 (&rest chunks)
  "Return Ethereum legacy Keccak-256 of all byte CHUNKS concatenated."
  (let ((sponge (make-keccak-256)))
    (dolist (chunk chunks)
      (keccak-256-update sponge chunk))
    (keccak-256-digest sponge)))

(defun keccak-256-hash (&rest chunks)
  (make-hash32 (apply #'keccak-256 chunks)))

(defun keccak-256-hex (&rest chunks)
  (bytes-to-hex (apply #'keccak-256 chunks)))

(defparameter +empty-code-hash+ (keccak-256-hash #()))
(defparameter +empty-trie-hash+ (keccak-256-hash #(128)))
