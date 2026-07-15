(in-package #:ethereum-lisp.crypto)

(defun sha256-ch (x y z)
  (logxor (logand x y) (logand (lognot x) z)))

(defun sha256-maj (x y z)
  (logxor (logand x y) (logand x z) (logand y z)))

(defun sha256-big-sigma-0 (x)
  (logxor (rotr32 x 2) (rotr32 x 13) (rotr32 x 22)))

(defun sha256-big-sigma-1 (x)
  (logxor (rotr32 x 6) (rotr32 x 11) (rotr32 x 25)))

(defun sha256-small-sigma-0 (x)
  (logxor (rotr32 x 7) (rotr32 x 18) (ash (u32 x) -3)))

(defun sha256-small-sigma-1 (x)
  (logxor (rotr32 x 17) (rotr32 x 19) (ash (u32 x) -10)))

(defun sha256-pad (message)
  (let* ((length (length message))
         (bit-length (* length 8))
         (padded-length
           (* 64 (ceiling (+ length 1 8) 64)))
         (padded (make-byte-vector padded-length)))
    (replace padded message)
    (setf (aref padded length) #x80)
    (loop for i below 8
          do (setf (aref padded (- padded-length 1 i))
                   (logand #xff (ash bit-length (* -8 i)))))
    padded))

(defun sha256-compress-block (hash block start)
  (let ((w (make-array 64)))
    (dotimes (i 16)
      (setf (aref w i)
            (load-big-endian-u32 block (+ start (* i 4)))))
    (loop for i from 16 below 64
          do (setf (aref w i)
                   (u32 (+ (sha256-small-sigma-1 (aref w (- i 2)))
                           (aref w (- i 7))
                           (sha256-small-sigma-0 (aref w (- i 15)))
                           (aref w (- i 16))))))
    (let ((a (aref hash 0))
          (b (aref hash 1))
          (c (aref hash 2))
          (d (aref hash 3))
          (e (aref hash 4))
          (f (aref hash 5))
          (g (aref hash 6))
          (h (aref hash 7)))
      (dotimes (i 64)
        (let ((temp1 (u32 (+ h
                             (sha256-big-sigma-1 e)
                             (sha256-ch e f g)
                             (aref +sha256-round-constants+ i)
                             (aref w i))))
              (temp2 (u32 (+ (sha256-big-sigma-0 a)
                             (sha256-maj a b c)))))
          (setf h g
                g f
                f e
                e (u32 (+ d temp1))
                d c
                c b
                b a
                a (u32 (+ temp1 temp2)))))
      (setf (aref hash 0) (u32 (+ (aref hash 0) a))
            (aref hash 1) (u32 (+ (aref hash 1) b))
            (aref hash 2) (u32 (+ (aref hash 2) c))
            (aref hash 3) (u32 (+ (aref hash 3) d))
            (aref hash 4) (u32 (+ (aref hash 4) e))
            (aref hash 5) (u32 (+ (aref hash 5) f))
            (aref hash 6) (u32 (+ (aref hash 6) g))
            (aref hash 7) (u32 (+ (aref hash 7) h))))
    hash))

(defun sha256 (&rest chunks)
  "Return SHA-256 of all byte CHUNKS concatenated."
  (let* ((message (apply #'concat-bytes
                         (mapcar #'ensure-byte-vector chunks)))
         (padded (sha256-pad message))
         (hash (copy-seq +sha256-initial-hash+)))
    (loop for start from 0 below (length padded) by 64
          do (sha256-compress-block hash padded start))
    (let ((out (make-byte-vector 32)))
      (dotimes (i 8)
        (store-big-endian-u32 (aref hash i) out (* i 4)))
      out)))

(defun sha256-hash (&rest chunks)
  (make-hash32 (apply #'sha256 chunks)))

(defun sha256-hex (&rest chunks)
  (bytes-to-hex (apply #'sha256 chunks)))
