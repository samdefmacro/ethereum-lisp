(in-package #:ethereum-lisp.crypto)

;;;; AES-128 and AES-256 forward cipher with CTR mode.
;;;;
;;;; Ethereum consensus never uses AES; this exists for the devp2p/RLPx
;;;; transport, where ECIES uses AES-128-CTR and the framing layer uses
;;;; AES-256-CTR. CTR needs only the forward cipher for both directions, so the
;;;; inverse cipher is deliberately omitted until something needs it.

(defparameter +aes-sbox+
  (make-array
   256 :element-type '(unsigned-byte 8) :initial-contents
   '(#x63 #x7c #x77 #x7b #xf2 #x6b #x6f #xc5 #x30 #x01 #x67 #x2b #xfe #xd7 #xab #x76
     #xca #x82 #xc9 #x7d #xfa #x59 #x47 #xf0 #xad #xd4 #xa2 #xaf #x9c #xa4 #x72 #xc0
     #xb7 #xfd #x93 #x26 #x36 #x3f #xf7 #xcc #x34 #xa5 #xe5 #xf1 #x71 #xd8 #x31 #x15
     #x04 #xc7 #x23 #xc3 #x18 #x96 #x05 #x9a #x07 #x12 #x80 #xe2 #xeb #x27 #xb2 #x75
     #x09 #x83 #x2c #x1a #x1b #x6e #x5a #xa0 #x52 #x3b #xd6 #xb3 #x29 #xe3 #x2f #x84
     #x53 #xd1 #x00 #xed #x20 #xfc #xb1 #x5b #x6a #xcb #xbe #x39 #x4a #x4c #x58 #xcf
     #xd0 #xef #xaa #xfb #x43 #x4d #x33 #x85 #x45 #xf9 #x02 #x7f #x50 #x3c #x9f #xa8
     #x51 #xa3 #x40 #x8f #x92 #x9d #x38 #xf5 #xbc #xb6 #xda #x21 #x10 #xff #xf3 #xd2
     #xcd #x0c #x13 #xec #x5f #x97 #x44 #x17 #xc4 #xa7 #x7e #x3d #x64 #x5d #x19 #x73
     #x60 #x81 #x4f #xdc #x22 #x2a #x90 #x88 #x46 #xee #xb8 #x14 #xde #x5e #x0b #xdb
     #xe0 #x32 #x3a #x0a #x49 #x06 #x24 #x5c #xc2 #xd3 #xac #x62 #x91 #x95 #xe4 #x79
     #xe7 #xc8 #x37 #x6d #x8d #xd5 #x4e #xa9 #x6c #x56 #xf4 #xea #x65 #x7a #xae #x08
     #xba #x78 #x25 #x2e #x1c #xa6 #xb4 #xc6 #xe8 #xdd #x74 #x1f #x4b #xbd #x8b #x8a
     #x70 #x3e #xb5 #x66 #x48 #x03 #xf6 #x0e #x61 #x35 #x57 #xb9 #x86 #xc1 #x1d #x9e
     #xe1 #xf8 #x98 #x11 #x69 #xd9 #x8e #x94 #x9b #x1e #x87 #xe9 #xce #x55 #x28 #xdf
     #x8c #xa1 #x89 #x0d #xbf #xe6 #x42 #x68 #x41 #x99 #x2d #x0f #xb0 #x54 #xbb #x16))
  "The AES substitution box, FIPS-197 Figure 7.")

(defparameter +aes-rcon+
  (make-array 11 :element-type '(unsigned-byte 8) :initial-contents
              '(#x00 #x01 #x02 #x04 #x08 #x10 #x20 #x40 #x80 #x1b #x36))
  "Round constants; index i is the leading byte of Rcon[i].")

(defconstant +aes-block-size+ 16)

(declaim (inline aes-xtime))
(defun aes-xtime (byte)
  "Multiply BYTE by x in GF(2^8) modulo the AES polynomial."
  (let ((shifted (ash byte 1)))
    (logand (if (logtest byte #x80)
                (logxor shifted #x1b)
                shifted)
            #xff)))

(defun aes-expand-key (key)
  "Expand a 16- or 32-byte KEY into the AES round key schedule.

Returns (values round-key-bytes round-count). ROUND-KEY-BYTES is a flat byte
vector holding round-count+1 sixteen-byte round keys."
  (let ((key (ensure-byte-vector key)))
    (let* ((nk (ecase (length key) (16 4) (32 8)))
           (rounds (if (= nk 4) 10 14))
           (total-words (* 4 (1+ rounds)))
           (schedule (make-byte-vector (* 4 total-words))))
      (replace schedule key)
      (loop for i from nk below total-words
            for base = (* 4 i)
            for prev = (- base 4)
            for t0 = (aref schedule prev)
            for t1 = (aref schedule (+ prev 1))
            for t2 = (aref schedule (+ prev 2))
            for t3 = (aref schedule (+ prev 3))
            do (cond
                 ((zerop (mod i nk))
                  ;; RotWord then SubWord then XOR the round constant.
                  (psetf t0 (logxor (aref +aes-sbox+ t1) (aref +aes-rcon+ (floor i nk)))
                         t1 (aref +aes-sbox+ t2)
                         t2 (aref +aes-sbox+ t3)
                         t3 (aref +aes-sbox+ t0)))
                 ((and (> nk 6) (= (mod i nk) 4))
                  (setf t0 (aref +aes-sbox+ t0)
                        t1 (aref +aes-sbox+ t1)
                        t2 (aref +aes-sbox+ t2)
                        t3 (aref +aes-sbox+ t3))))
               (let ((w (- base (* 4 nk))))
                 (setf (aref schedule base) (logxor (aref schedule w) t0)
                       (aref schedule (+ base 1)) (logxor (aref schedule (+ w 1)) t1)
                       (aref schedule (+ base 2)) (logxor (aref schedule (+ w 2)) t2)
                       (aref schedule (+ base 3)) (logxor (aref schedule (+ w 3)) t3))))
      (values schedule rounds))))

(defun aes-add-round-key (state schedule round)
  (let ((offset (* round +aes-block-size+)))
    (dotimes (i +aes-block-size+)
      (setf (aref state i) (logxor (aref state i) (aref schedule (+ offset i)))))))

(defun aes-sub-bytes (state)
  (dotimes (i +aes-block-size+)
    (setf (aref state i) (aref +aes-sbox+ (aref state i)))))

(defun aes-shift-rows (state)
  ;; State byte index is row + 4*column, so each row is indices r, r+4, r+8,
  ;; r+12, and row r rotates left by r.
  (loop for row from 1 below 4
        for a = (aref state row)
        for b = (aref state (+ row 4))
        for c = (aref state (+ row 8))
        for d = (aref state (+ row 12))
        do (ecase row
             (1 (setf (aref state row) b (aref state (+ row 4)) c
                      (aref state (+ row 8)) d (aref state (+ row 12)) a))
             (2 (setf (aref state row) c (aref state (+ row 4)) d
                      (aref state (+ row 8)) a (aref state (+ row 12)) b))
             (3 (setf (aref state row) d (aref state (+ row 4)) a
                      (aref state (+ row 8)) b (aref state (+ row 12)) c)))))

(defun aes-mix-columns (state)
  (dotimes (column 4)
    (let* ((base (* column 4))
           (s0 (aref state base))
           (s1 (aref state (+ base 1)))
           (s2 (aref state (+ base 2)))
           (s3 (aref state (+ base 3)))
           (all (logxor s0 s1 s2 s3)))
      (setf (aref state base)
            (logxor s0 all (aes-xtime (logxor s0 s1)))
            (aref state (+ base 1))
            (logxor s1 all (aes-xtime (logxor s1 s2)))
            (aref state (+ base 2))
            (logxor s2 all (aes-xtime (logxor s2 s3)))
            (aref state (+ base 3))
            (logxor s3 all (aes-xtime (logxor s3 s0)))))))

(defun aes-encrypt-block (schedule rounds block &optional (start 0))
  "Return the AES encryption of the 16 bytes of BLOCK starting at START."
  (let ((state (make-byte-vector +aes-block-size+)))
    (replace state block :start2 start :end2 (+ start +aes-block-size+))
    (aes-add-round-key state schedule 0)
    (loop for round from 1 below rounds
          do (aes-sub-bytes state)
             (aes-shift-rows state)
             (aes-mix-columns state)
             (aes-add-round-key state schedule round))
    (aes-sub-bytes state)
    (aes-shift-rows state)
    (aes-add-round-key state schedule rounds)
    state))

;;; Stateful AES-CTR stream. RLPx encrypts every frame in a direction with one
;;; continuous CTR keystream rather than restarting the counter per frame, so
;;; the cipher must carry its counter and partial keystream block across calls.

(defstruct (aes-ctr-stream (:constructor %make-aes-ctr-stream))
  schedule
  rounds
  counter
  keystream
  (position +aes-block-size+ :type fixnum))

(defun make-aes-ctr-stream (key &optional iv)
  "Return an AES-CTR stream over KEY starting at the 16-byte IV (default zero)."
  (let ((iv (if iv (ensure-byte-vector iv) (make-byte-vector +aes-block-size+))))
    (unless (= (length iv) +aes-block-size+)
      (error "AES-CTR IV must be ~D bytes" +aes-block-size+))
    (multiple-value-bind (schedule rounds) (aes-expand-key key)
      (%make-aes-ctr-stream :schedule schedule
                            :rounds rounds
                            :counter (copy-seq iv)
                            :keystream (make-byte-vector +aes-block-size+)))))

(defun aes-ctr-stream-apply (stream data)
  "XOR DATA against STREAM's continuing keystream, advancing STREAM.

Successive calls share one keystream, so applying it in pieces equals one CTR
pass over the concatenation."
  (let* ((data (ensure-byte-vector data))
         (output (make-byte-vector (length data))))
    (dotimes (i (length data))
      (when (= (aes-ctr-stream-position stream) +aes-block-size+)
        (setf (aes-ctr-stream-keystream stream)
              (aes-encrypt-block (aes-ctr-stream-schedule stream)
                                 (aes-ctr-stream-rounds stream)
                                 (aes-ctr-stream-counter stream)))
        (aes-increment-counter (aes-ctr-stream-counter stream))
        (setf (aes-ctr-stream-position stream) 0))
      (setf (aref output i)
            (logxor (aref data i)
                    (aref (aes-ctr-stream-keystream stream)
                          (aes-ctr-stream-position stream))))
      (incf (aes-ctr-stream-position stream)))
    output))

(defun aes-encrypt-ecb-block (key block)
  "Return the single-block AES encryption of BLOCK under KEY.

The RLPx framing MAC encrypts a 16-byte seed with the MAC key this way; it is
raw ECB on one block, not a general-purpose mode."
  (let ((key (ensure-byte-vector key))
        (block (ensure-byte-vector block)))
    (unless (= (length block) +aes-block-size+)
      (error "AES block must be ~D bytes" +aes-block-size+))
    (multiple-value-bind (schedule rounds) (aes-expand-key key)
      (aes-encrypt-block schedule rounds block))))

(defun aes-increment-counter (counter)
  "Increment the 16-byte COUNTER as a big-endian 128-bit integer, in place."
  (loop for i from (1- +aes-block-size+) downto 0
        do (let ((incremented (1+ (aref counter i))))
             (setf (aref counter i) (logand incremented #xff))
             (when (<= incremented #xff)
               (return)))))

(defun aes-ctr (key iv data)
  "Encrypt or decrypt DATA under AES-CTR with KEY and the 16-byte IV.

CTR is its own inverse, so one function serves both directions. The counter is
the whole IV incremented as a big-endian integer, matching Go's crypto/cipher."
  (let ((key (ensure-byte-vector key))
        (iv (ensure-byte-vector iv))
        (data (ensure-byte-vector data)))
    (unless (= (length iv) +aes-block-size+)
      (error "AES-CTR IV must be ~D bytes" +aes-block-size+))
    (multiple-value-bind (schedule rounds) (aes-expand-key key)
      (let ((counter (copy-seq iv))
            (output (make-byte-vector (length data))))
        (loop for offset from 0 below (length data) by +aes-block-size+
              for keystream = (aes-encrypt-block schedule rounds counter)
              do (loop for i from 0
                       below (min +aes-block-size+ (- (length data) offset))
                       do (setf (aref output (+ offset i))
                                (logxor (aref data (+ offset i)) (aref keystream i))))
                 (aes-increment-counter counter))
        output))))
