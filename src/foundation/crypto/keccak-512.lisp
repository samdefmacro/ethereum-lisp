(in-package #:ethereum-lisp.crypto)

;;;; Ironclad 0.61 exposes Ethereum's Keccak-256 but not Keccak-512. Ethash
;;;; needs the latter for cache and Hashimoto expansion, so this is the same
;;;; small typed Keccak-f[1600] sponge construction with a 72-byte rate.

(deftype keccak-512-lanes () '(simple-array (unsigned-byte 64) (25)))

(defparameter +keccak-512-rotation-table+
  (coerce +keccak-rotation-offsets+
          '(simple-array (unsigned-byte 8) (25))))
(defparameter +keccak-512-round-constant-table+
  (coerce +keccak-round-constants+
          '(simple-array (unsigned-byte 64) (24))))

(declaim (inline keccak-512-rotl))
(defun keccak-512-rotl (value count)
  (declare (type (unsigned-byte 64) value)
           (type (integer 0 63) count)
           (optimize (speed 3) (safety 1) (debug 0)))
  (if (zerop count)
      value
      (logior (ldb (byte 64 0) (ash value count))
              (ash value (- count 64)))))

(defun keccak-512-f1600 (state)
  (declare (type keccak-512-lanes state)
           (optimize (speed 3) (safety 1) (debug 0)))
  (let ((c (make-array 5 :element-type '(unsigned-byte 64)))
        (d (make-array 5 :element-type '(unsigned-byte 64)))
        (b (make-array 25 :element-type '(unsigned-byte 64)))
        (rotations +keccak-512-rotation-table+)
        (round-constants +keccak-512-round-constant-table+))
    (declare (type (simple-array (unsigned-byte 64) (5)) c d)
             (type keccak-512-lanes b)
             (dynamic-extent c d b))
    (dotimes (round 24 state)
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
                      (keccak-512-rotl
                       (aref c (mod (1+ x) 5)) 1))))
      (dotimes (y 5)
        (dotimes (x 5)
          (let ((index (+ x (* 5 y))))
            (setf (aref state index)
                  (logxor (aref state index) (aref d x))))))
      (dotimes (y 5)
        (dotimes (x 5)
          (let ((index (+ x (* 5 y))))
            (setf (aref b
                        (+ y (* 5 (mod (+ (* 2 x) (* 3 y)) 5))))
                  (keccak-512-rotl
                   (aref state index) (aref rotations index))))))
      (dotimes (y 5)
        (dotimes (x 5)
          (let ((index (+ x (* 5 y))))
            (setf (aref state index)
                  (logxor
                   (aref b index)
                   (logand
                    (ldb (byte 64 0)
                         (lognot
                          (aref b (+ (mod (1+ x) 5) (* 5 y)))))
                    (aref b (+ (mod (+ x 2) 5) (* 5 y)))))))))
      (setf (aref state 0)
            (logxor (aref state 0)
                    (aref round-constants round))))))

(defun keccak-512-load-lane (bytes start)
  (declare (type byte-vector bytes)
           (type fixnum start)
           (optimize (speed 3) (safety 1) (debug 0)))
  (let ((value 0))
    (declare (type (unsigned-byte 64) value))
    (dotimes (i 8 value)
      (setf value
            (logior value (ash (aref bytes (+ start i)) (* 8 i)))))))

(defun keccak-512-absorb-block (state block)
  (declare (type keccak-512-lanes state)
           (type byte-vector block)
           (optimize (speed 3) (safety 1) (debug 0)))
  (dotimes (lane 9)
    (setf (aref state lane)
          (logxor (aref state lane)
                  (keccak-512-load-lane block (* lane 8)))))
  (keccak-512-f1600 state))

(defun keccak-512 (&rest chunks)
  "Return legacy Keccak-512 of all byte CHUNKS concatenated."
  (let* ((input (apply #'concat-bytes chunks))
         (length (length input))
         (state (make-array 25
                            :element-type '(unsigned-byte 64)
                            :initial-element 0))
         (offset 0))
    (declare (type byte-vector input)
             (type keccak-512-lanes state)
             (type fixnum length offset))
    (loop while (<= (+ offset 72) length)
          do (keccak-512-absorb-block state (subseq input offset (+ offset 72)))
             (incf offset 72))
    (let ((block (make-byte-vector 72)))
      (replace block input :start2 offset)
      (let ((remaining (- length offset)))
        (setf (aref block remaining)
              (logxor (aref block remaining) #x01)
              (aref block 71)
              (logxor (aref block 71) #x80)))
      (keccak-512-absorb-block state block))
    (let ((output (make-byte-vector 64)))
      (dotimes (lane 8 output)
        (store-little-endian-u64
         (aref state lane) output (* lane 8))))))

