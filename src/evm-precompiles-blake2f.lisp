(in-package #:ethereum-lisp.evm)

(defun blake2b-mix (v a b c d x y)
  (setf (aref v a) (u64 (+ (aref v a) (aref v b) x))
        (aref v d) (rotr64 (logxor (aref v d) (aref v a)) 32)
        (aref v c) (u64 (+ (aref v c) (aref v d)))
        (aref v b) (rotr64 (logxor (aref v b) (aref v c)) 24)
        (aref v a) (u64 (+ (aref v a) (aref v b) y))
        (aref v d) (rotr64 (logxor (aref v d) (aref v a)) 16)
        (aref v c) (u64 (+ (aref v c) (aref v d)))
        (aref v b) (rotr64 (logxor (aref v b) (aref v c)) 63)))

(defun run-blake2f-precompile (input)
  (let ((input (ensure-byte-vector input)))
    (unless (= (length input) +blake2f-input-size+)
      (fail-precompile +precompile-consume-all-child-gas+
                       "BLAKE2F invalid input length"))
    (let ((rounds (load-big-endian-u32 input 0))
          (h (make-array 8))
          (m (make-array 16))
          (v (make-array 16))
          (t0 (load-little-endian-u64 input 196))
          (t1 (load-little-endian-u64 input 204))
          (final-p (= (aref input 212) 1)))
      (unless (member (aref input 212) '(0 1) :test #'=)
        (fail-precompile +precompile-consume-all-child-gas+
                         "BLAKE2F invalid final flag"))
      (dotimes (i 8)
        (setf (aref h i) (load-little-endian-u64 input (+ 4 (* i 8)))
              (aref v i) (aref h i)
              (aref v (+ i 8)) (aref +blake2b-iv+ i)))
      (dotimes (i 16)
        (setf (aref m i) (load-little-endian-u64 input (+ 68 (* i 8)))))
      (setf (aref v 12) (logxor (aref v 12) t0)
            (aref v 13) (logxor (aref v 13) t1))
      (when final-p
        (setf (aref v 14) (logxor (aref v 14) +uint64-mask+)))
      (dotimes (round rounds)
        (let ((s (aref +blake2b-sigma+ (mod round 10))))
          (blake2b-mix v 0 4 8 12
                       (aref m (aref s 0)) (aref m (aref s 1)))
          (blake2b-mix v 1 5 9 13
                       (aref m (aref s 2)) (aref m (aref s 3)))
          (blake2b-mix v 2 6 10 14
                       (aref m (aref s 4)) (aref m (aref s 5)))
          (blake2b-mix v 3 7 11 15
                       (aref m (aref s 6)) (aref m (aref s 7)))
          (blake2b-mix v 0 5 10 15
                       (aref m (aref s 8)) (aref m (aref s 9)))
          (blake2b-mix v 1 6 11 12
                       (aref m (aref s 10)) (aref m (aref s 11)))
          (blake2b-mix v 2 7 8 13
                       (aref m (aref s 12)) (aref m (aref s 13)))
          (blake2b-mix v 3 4 9 14
                       (aref m (aref s 14)) (aref m (aref s 15)))))
      (let ((output (make-byte-vector 64)))
        (dotimes (i 8)
          (store-little-endian-u64
           (logxor (aref h i) (aref v i) (aref v (+ i 8)))
           output
           (* i 8)))
        (values output rounds)))))

(defun blake2f-precompile-required-gas (input)
  (let ((input (ensure-byte-vector input)))
    (when (and (= (length input) +blake2f-input-size+)
               (member (aref input 212) '(0 1) :test #'=))
      (load-big-endian-u32 input 0))))
