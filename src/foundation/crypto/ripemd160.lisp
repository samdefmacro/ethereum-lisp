(in-package #:ethereum-lisp.crypto)

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
