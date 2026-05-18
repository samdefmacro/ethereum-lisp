(in-package #:ethereum-lisp.crypto)

(defconstant +uint64-mask+ #xffffffffffffffff)
(defconstant +uint32-mask+ #xffffffff)
(defconstant +keccak-256-rate+ 136)
(defconstant +kzg-commitment-size+ 48)
(defconstant +kzg-commitment-version+ #x01)
(defconstant +secp256k1-p+
  #xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f)
(defconstant +secp256k1-n+
  #xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141)
(defconstant +secp256k1-half-n+
  (floor +secp256k1-n+ 2))
(defconstant +secp256k1-gx+
  #x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798)
(defconstant +secp256k1-gy+
  #x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8)

(defparameter +ripemd160-initial-hash+
  #(#x67452301 #xefcdab89 #x98badcfe #x10325476 #xc3d2e1f0))

(defparameter +ripemd160-left-words+
  #(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15
    7 4 13 1 10 6 15 3 12 0 9 5 2 14 11 8
    3 10 14 4 9 15 8 1 2 7 0 6 13 11 5 12
    1 9 11 10 0 8 12 4 13 3 7 15 14 5 6 2
    4 0 5 9 7 12 2 10 14 1 3 8 11 6 15 13))

(defparameter +ripemd160-right-words+
  #(5 14 7 0 9 2 11 4 13 6 15 8 1 10 3 12
    6 11 3 7 0 13 5 10 14 15 8 12 4 9 1 2
    15 5 1 3 7 14 6 9 11 8 12 2 10 0 4 13
    8 6 4 1 3 11 15 0 5 12 2 13 9 7 10 14
    12 15 10 4 1 5 8 7 6 2 13 14 0 3 9 11))

(defparameter +ripemd160-left-shifts+
  #(11 14 15 12 5 8 7 9 11 13 14 15 6 7 9 8
    7 6 8 13 11 9 7 15 7 12 15 9 11 7 13 12
    11 13 6 7 14 9 13 15 14 8 13 6 5 12 7 5
    11 12 14 15 14 15 9 8 9 14 5 6 8 6 5 12
    9 15 5 11 6 8 13 12 5 12 13 14 11 8 5 6))

(defparameter +ripemd160-right-shifts+
  #(8 9 9 11 13 15 15 5 7 7 8 11 14 14 12 6
    9 13 15 7 12 8 9 11 7 7 12 7 6 15 13 11
    9 7 15 11 8 6 6 14 12 13 5 14 13 13 7 5
    15 5 8 11 14 14 6 14 6 9 12 9 12 5 15 8
    8 5 12 9 12 5 14 6 8 13 6 5 15 13 11 11))

(defparameter +keccak-round-constants+
  #(#x0000000000000001 #x0000000000008082 #x800000000000808a
    #x8000000080008000 #x000000000000808b #x0000000080000001
    #x8000000080008081 #x8000000000008009 #x000000000000008a
    #x0000000000000088 #x0000000080008009 #x000000008000000a
    #x000000008000808b #x800000000000008b #x8000000000008089
    #x8000000000008003 #x8000000000008002 #x8000000000000080
    #x000000000000800a #x800000008000000a #x8000000080008081
    #x8000000000008080 #x0000000080000001 #x8000000080008008))

(defparameter +keccak-rotation-offsets+
  #(0 1 62 28 27
    36 44 6 55 20
    3 10 43 25 39
    41 45 15 21 8
    18 2 61 56 14))

(defparameter +sha256-initial-hash+
  #(#x6a09e667 #xbb67ae85 #x3c6ef372 #xa54ff53a
    #x510e527f #x9b05688c #x1f83d9ab #x5be0cd19))

(defparameter +sha256-round-constants+
  #(#x428a2f98 #x71374491 #xb5c0fbcf #xe9b5dba5
    #x3956c25b #x59f111f1 #x923f82a4 #xab1c5ed5
    #xd807aa98 #x12835b01 #x243185be #x550c7dc3
    #x72be5d74 #x80deb1fe #x9bdc06a7 #xc19bf174
    #xe49b69c1 #xefbe4786 #x0fc19dc6 #x240ca1cc
    #x2de92c6f #x4a7484aa #x5cb0a9dc #x76f988da
    #x983e5152 #xa831c66d #xb00327c8 #xbf597fc7
    #xc6e00bf3 #xd5a79147 #x06ca6351 #x14292967
    #x27b70a85 #x2e1b2138 #x4d2c6dfc #x53380d13
    #x650a7354 #x766a0abb #x81c2c92e #x92722c85
    #xa2bfe8a1 #xa81a664b #xc24b8b70 #xc76c51a3
    #xd192e819 #xd6990624 #xf40e3585 #x106aa070
    #x19a4c116 #x1e376c08 #x2748774c #x34b0bcb5
    #x391c0cb3 #x4ed8aa4a #x5b9cca4f #x682e6ff3
    #x748f82ee #x78a5636f #x84c87814 #x8cc70208
    #x90befffa #xa4506ceb #xbef9a3f7 #xc67178f2))

(defun u32 (value)
  (logand value +uint32-mask+))

(defun u64 (value)
  (logand value +uint64-mask+))

(defun rotl64 (value count)
  (let ((count (mod count 64))
        (value (u64 value)))
    (if (zerop count)
        value
        (u64 (logior (ash value count)
                     (ash value (- count 64)))))))

(defun lane-index (x y)
  (+ x (* 5 y)))

(defun load-little-endian-u64 (bytes start)
  (loop for i below 8
        sum (ash (aref bytes (+ start i)) (* 8 i))))

(defun store-little-endian-u64 (value bytes start)
  (loop for i below 8
        do (setf (aref bytes (+ start i))
                 (logand #xff (ash value (* -8 i)))))
  bytes)

(defun rotr32 (value count)
  (let ((count (mod count 32))
        (value (u32 value)))
    (if (zerop count)
        value
        (u32 (logior (ash value (- count))
                     (ash value (- 32 count)))))))

(defun rotl32 (value count)
  (let ((count (mod count 32))
        (value (u32 value)))
    (if (zerop count)
        value
        (u32 (logior (ash value count)
                     (ash value (- count 32)))))))

(defun load-big-endian-u32 (bytes start)
  (loop for i below 4
        sum (ash (aref bytes (+ start i)) (* 8 (- 3 i)))))

(defun store-big-endian-u32 (value bytes start)
  (loop for i below 4
        do (setf (aref bytes (+ start i))
                 (logand #xff (ash value (* -8 (- 3 i))))))
  bytes)

(defun load-little-endian-u32 (bytes start)
  (loop for i below 4
        sum (ash (aref bytes (+ start i)) (* 8 i))))

(defun store-little-endian-u32 (value bytes start)
  (loop for i below 4
        do (setf (aref bytes (+ start i))
                 (logand #xff (ash value (* -8 i)))))
  bytes)

(defun keccak-f1600 (state)
  (dotimes (round 24 state)
    (let ((c (make-array 5))
          (d (make-array 5))
          (b (make-array 25)))
      (dotimes (x 5)
        (setf (aref c x)
              (u64 (logxor (aref state (lane-index x 0))
                           (aref state (lane-index x 1))
                           (aref state (lane-index x 2))
                           (aref state (lane-index x 3))
                           (aref state (lane-index x 4))))))
      (dotimes (x 5)
        (setf (aref d x)
              (u64 (logxor (aref c (mod (1- x) 5))
                           (rotl64 (aref c (mod (1+ x) 5)) 1)))))
      (dotimes (x 5)
        (dotimes (y 5)
          (let ((index (lane-index x y)))
            (setf (aref state index)
                  (u64 (logxor (aref state index) (aref d x)))))))
      (dotimes (x 5)
        (dotimes (y 5)
          (let* ((index (lane-index x y))
                 (new-x y)
                 (new-y (mod (+ (* 2 x) (* 3 y)) 5)))
            (setf (aref b (lane-index new-x new-y))
                  (rotl64 (aref state index)
                          (aref +keccak-rotation-offsets+ index))))))
      (dotimes (x 5)
        (dotimes (y 5)
          (setf (aref state (lane-index x y))
                (u64 (logxor (aref b (lane-index x y))
                             (logand (lognot (aref b (lane-index (mod (1+ x) 5) y)))
                                     (aref b (lane-index (mod (+ x 2) 5) y))))))))
      (setf (aref state 0)
            (u64 (logxor (aref state 0)
                         (aref +keccak-round-constants+ round)))))))

(defun absorb-block (state block)
  (dotimes (lane (/ +keccak-256-rate+ 8))
    (let ((offset (* lane 8)))
      (setf (aref state lane)
            (u64 (logxor (aref state lane)
                         (load-little-endian-u64 block offset))))))
  (keccak-f1600 state))

(defun keccak-256 (&rest chunks)
  "Return Ethereum legacy Keccak-256 of all byte CHUNKS concatenated."
  (let ((state (make-array 25 :initial-element 0))
        (block (make-byte-vector +keccak-256-rate+))
        (offset 0))
    (labels ((absorb-byte (byte)
               (setf (aref block offset) byte)
               (incf offset)
               (when (= offset +keccak-256-rate+)
                 (absorb-block state block)
                 (fill block 0)
                 (setf offset 0))))
      (dolist (chunk chunks)
        (loop for byte across (ensure-byte-vector chunk)
              do (absorb-byte byte)))
      (setf (aref block offset) (logxor (aref block offset) #x01)
            (aref block (1- +keccak-256-rate+))
            (logxor (aref block (1- +keccak-256-rate+)) #x80))
      (absorb-block state block))
    (let ((out (make-byte-vector 32)))
      (dotimes (lane 4)
        (store-little-endian-u64 (aref state lane) out (* lane 8)))
      out)))

(defun keccak-256-hash (&rest chunks)
  (make-hash32 (apply #'keccak-256 chunks)))

(defun keccak-256-hex (&rest chunks)
  (bytes-to-hex (apply #'keccak-256 chunks)))

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

(defun ripemd160-f (round x y z)
  (cond
    ((< round 16) (logxor x y z))
    ((< round 32) (logior (logand x y)
                          (logand (lognot x) z)))
    ((< round 48) (logxor (logior x (lognot y)) z))
    ((< round 64) (logior (logand x z)
                          (logand y (lognot z))))
    (t (logxor x (logior y (lognot z))))))

(defun ripemd160-left-constant (round)
  (cond
    ((< round 16) #x00000000)
    ((< round 32) #x5a827999)
    ((< round 48) #x6ed9eba1)
    ((< round 64) #x8f1bbcdc)
    (t #xa953fd4e)))

(defun ripemd160-right-constant (round)
  (cond
    ((< round 16) #x50a28be6)
    ((< round 32) #x5c4dd124)
    ((< round 48) #x6d703ef3)
    ((< round 64) #x7a6d76e9)
    (t #x00000000)))

(defun ripemd160-pad (message)
  (let* ((length (length message))
         (bit-length (* length 8))
         (padded-length
           (* 64 (ceiling (+ length 1 8) 64)))
         (padded (make-byte-vector padded-length)))
    (replace padded message)
    (setf (aref padded length) #x80)
    (loop for i below 8
          do (setf (aref padded (+ (- padded-length 8) i))
                   (logand #xff (ash bit-length (* -8 i)))))
    padded))

(defun ripemd160-compress-block (hash block start)
  (let ((words (make-array 16)))
    (dotimes (i 16)
      (setf (aref words i)
            (load-little-endian-u32 block (+ start (* i 4)))))
    (let ((a (aref hash 0))
          (b (aref hash 1))
          (c (aref hash 2))
          (d (aref hash 3))
          (e (aref hash 4))
          (aa (aref hash 0))
          (bb (aref hash 1))
          (cc (aref hash 2))
          (dd (aref hash 3))
          (ee (aref hash 4)))
      (dotimes (round 80)
        (let ((temp (u32 (+ (rotl32
                             (u32 (+ a
                                     (ripemd160-f round b c d)
                                     (aref words
                                           (aref +ripemd160-left-words+ round))
                                     (ripemd160-left-constant round)))
                             (aref +ripemd160-left-shifts+ round))
                            e))))
          (setf a e
                e d
                d (rotl32 c 10)
                c b
                b temp))
        (let* ((right-round (- 79 round))
               (temp (u32 (+ (rotl32
                              (u32 (+ aa
                                      (ripemd160-f right-round bb cc dd)
                                      (aref words
                                            (aref +ripemd160-right-words+ round))
                                      (ripemd160-right-constant round)))
                              (aref +ripemd160-right-shifts+ round))
                             ee))))
          (setf aa ee
                ee dd
                dd (rotl32 cc 10)
                cc bb
                bb temp)))
      (let ((temp (u32 (+ (aref hash 1) c dd))))
        (setf (aref hash 1) (u32 (+ (aref hash 2) d ee))
              (aref hash 2) (u32 (+ (aref hash 3) e aa))
              (aref hash 3) (u32 (+ (aref hash 4) a bb))
              (aref hash 4) (u32 (+ (aref hash 0) b cc))
              (aref hash 0) temp))))
  hash)

(defun ripemd160 (&rest chunks)
  "Return RIPEMD-160 of all byte CHUNKS concatenated."
  (let* ((message (apply #'concat-bytes
                         (mapcar #'ensure-byte-vector chunks)))
         (padded (ripemd160-pad message))
         (hash (copy-seq +ripemd160-initial-hash+)))
    (loop for start from 0 below (length padded) by 64
          do (ripemd160-compress-block hash padded start))
    (let ((out (make-byte-vector 20)))
      (dotimes (i 5)
        (store-little-endian-u32 (aref hash i) out (* i 4)))
      out)))

(defun ripemd160-hex (&rest chunks)
  (bytes-to-hex (apply #'ripemd160 chunks)))

(defun require-sized-byte-vector (value size label)
  (let ((bytes (ensure-byte-vector value)))
    (unless (= size (length bytes))
      (error "~A must be exactly ~D bytes" label size))
    bytes))

(defun kzg-commitment-to-versioned-hash (commitment)
  "Return the EIP-4844 versioned hash for a 48-byte KZG COMMITMENT."
  (let ((hash (sha256 (require-sized-byte-vector
                       commitment
                       +kzg-commitment-size+
                       "KZG commitment"))))
    (setf (aref hash 0) +kzg-commitment-version+)
    (make-hash32 hash)))

(defun integer-to-fixed-bytes (value size)
  (let* ((minimal (integer-to-minimal-bytes value))
         (result (make-byte-vector size))
         (copy-size (min size (length minimal))))
    (replace result
             minimal
             :start1 (- size copy-size)
             :start2 (- (length minimal) copy-size))
    result))

(defun modular-inverse (value modulus)
  (labels ((egcd (a b)
             (if (zerop b)
                 (values a 1 0)
                 (multiple-value-bind (g x y) (egcd b (mod a b))
                   (values g y (- x (* y (floor a b))))))))
    (multiple-value-bind (g x ignored) (egcd (mod value modulus) modulus)
      (declare (ignore ignored))
      (and (= g 1) (mod x modulus)))))

(defun modular-expt (base exponent modulus)
  (cond
    ((zerop modulus) 0)
    ((zerop exponent) (mod 1 modulus))
    (t
     (loop with result = 1
           with factor = (mod base modulus)
           for exp = exponent then (ash exp -1)
           while (plusp exp)
           do (when (oddp exp)
                (setf result (mod (* result factor) modulus)))
              (setf factor (mod (* factor factor) modulus))
           finally (return result)))))

(defun secp256k1-point (x y)
  (cons x y))

(defun secp256k1-point-x (point)
  (car point))

(defun secp256k1-point-y (point)
  (cdr point))

(defun secp256k1-point-on-curve-p (point)
  (or (null point)
      (let ((x (secp256k1-point-x point))
            (y (secp256k1-point-y point)))
        (= (mod (* y y) +secp256k1-p+)
           (mod (+ (* x x x) 7) +secp256k1-p+)))))

(defun secp256k1-point-negate (point)
  (and point
       (secp256k1-point
        (secp256k1-point-x point)
        (mod (- (secp256k1-point-y point)) +secp256k1-p+))))

(defun secp256k1-point-add (a b)
  (cond
    ((null a) b)
    ((null b) a)
    (t
     (let ((x1 (secp256k1-point-x a))
           (y1 (secp256k1-point-y a))
           (x2 (secp256k1-point-x b))
           (y2 (secp256k1-point-y b)))
       (cond
         ((and (= x1 x2) (= (mod (+ y1 y2) +secp256k1-p+) 0))
          nil)
         (t
          (let* ((slope
                   (if (and (= x1 x2) (= y1 y2))
                       (let ((denominator (modular-inverse
                                           (* 2 y1)
                                           +secp256k1-p+)))
                         (unless denominator
                           (return-from secp256k1-point-add nil))
                         (mod (* 3 x1 x1 denominator) +secp256k1-p+))
                       (let ((denominator (modular-inverse
                                           (- x2 x1)
                                           +secp256k1-p+)))
                         (unless denominator
                           (return-from secp256k1-point-add nil))
                         (mod (* (- y2 y1) denominator)
                              +secp256k1-p+))))
                 (x3 (mod (- (* slope slope) x1 x2) +secp256k1-p+))
                 (y3 (mod (- (* slope (- x1 x3)) y1) +secp256k1-p+)))
            (secp256k1-point x3 y3))))))))

(defun secp256k1-scalar-multiply (scalar point)
  (loop with result = nil
        with addend = point
        for n = scalar then (ash n -1)
        while (plusp n)
        do (when (oddp n)
             (setf result (secp256k1-point-add result addend)))
           (setf addend (secp256k1-point-add addend addend))
        finally (return result)))

(defun secp256k1-decompress-point (x odd-y-p)
  (when (< x +secp256k1-p+)
    (let* ((alpha (mod (+ (* x x x) 7) +secp256k1-p+))
           (beta (modular-expt alpha
                               (floor (1+ +secp256k1-p+) 4)
                               +secp256k1-p+)))
      (when (= (mod (* beta beta) +secp256k1-p+) alpha)
        (let ((y (if (eql (oddp beta) odd-y-p)
                     beta
                     (- +secp256k1-p+ beta))))
          (secp256k1-point x y))))))

(defun secp256k1-valid-signature-values-p (v r s &key low-s-p)
  (and (or (= v 0) (= v 1))
       (<= 1 r)
       (< r +secp256k1-n+)
       (<= 1 s)
       (< s +secp256k1-n+)
       (or (not low-s-p)
           (<= s +secp256k1-half-n+))))

(defun secp256k1-recover-public-key (hash v r s)
  "Recover a 64-byte uncompressed secp256k1 public key body from HASH/V/R/S.
Returns NIL when the signature is invalid or unrecoverable."
  (let ((hash (require-sized-byte-vector hash 32 "secp256k1 hash")))
    (when (secp256k1-valid-signature-values-p v r s)
      (let* ((r-point (secp256k1-decompress-point r (= v 1)))
             (generator (secp256k1-point +secp256k1-gx+ +secp256k1-gy+)))
        (when (and r-point
                   (secp256k1-point-on-curve-p r-point)
                   (null (secp256k1-scalar-multiply +secp256k1-n+ r-point)))
          (let* ((r-inverse (modular-inverse r +secp256k1-n+))
                 (message (bytes-to-integer hash))
                 (u1 (mod (* (- message) r-inverse) +secp256k1-n+))
                 (u2 (mod (* s r-inverse) +secp256k1-n+))
                 (public-point
                   (secp256k1-point-add
                    (secp256k1-scalar-multiply u1 generator)
                    (secp256k1-scalar-multiply u2 r-point))))
            (when (secp256k1-point-on-curve-p public-point)
              (concat-bytes
               (integer-to-fixed-bytes (secp256k1-point-x public-point) 32)
               (integer-to-fixed-bytes (secp256k1-point-y public-point)
                                       32)))))))))

(defun secp256k1-recover-address (hash v r s)
  "Recover the Ethereum address for HASH/V/R/S, or NIL if unrecoverable."
  (let ((public-key (secp256k1-recover-public-key hash v r s)))
    (when public-key
      (let ((address (make-byte-vector 20))
            (hashed (keccak-256 public-key)))
        (replace address hashed :start2 12)
        (make-address address)))))

(defparameter +empty-code-hash+ (keccak-256-hash #()))
(defparameter +empty-trie-hash+ (keccak-256-hash #(128)))
