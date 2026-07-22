(in-package #:ethereum-lisp.crypto)

(defun lane-index (x y)
  (+ x (* 5 y)))

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

;;; Incremental Keccak-256 sponge. RLPx keeps a running MAC keccak state that is
;;; updated with each frame's ciphertext and digested (peeked) between updates,
;;; so the sponge is exposed as init / update / digest as well as the one-shot
;;; KECCAK-256 built on top of it.

(defstruct (keccak-256-sponge (:constructor %make-keccak-256-sponge))
  (lanes (make-array 25 :initial-element 0))
  (block (make-byte-vector +keccak-256-rate+))
  (offset 0 :type fixnum))

(defun make-keccak-256 ()
  "Return a fresh incremental Keccak-256 sponge."
  (%make-keccak-256-sponge))

(defun keccak-256-update (sponge chunk)
  "Absorb CHUNK into SPONGE and return SPONGE."
  (let ((lanes (keccak-256-sponge-lanes sponge))
        (block (keccak-256-sponge-block sponge)))
    (loop for byte across (ensure-byte-vector chunk)
          do (setf (aref block (keccak-256-sponge-offset sponge)) byte)
             (incf (keccak-256-sponge-offset sponge))
             (when (= (keccak-256-sponge-offset sponge) +keccak-256-rate+)
               (absorb-block lanes block)
               (fill block 0)
               (setf (keccak-256-sponge-offset sponge) 0))))
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
