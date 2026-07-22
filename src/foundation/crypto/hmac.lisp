(in-package #:ethereum-lisp.crypto)

;;;; HMAC-SHA-256 (RFC 2104).
;;;;
;;;; Used by the Engine RPC JWT auth and by the devp2p/RLPx ECIES tag. Both had
;;;; no shared home, so the JWT layer carried its own copy; this is the single
;;;; foundation implementation.

(defconstant +hmac-sha256-block-size+ 64)

(defun hmac-sha256 (key message)
  "Return the 32-byte HMAC-SHA-256 of MESSAGE under KEY."
  (let* ((key (ensure-byte-vector key))
         (message (ensure-byte-vector message))
         ;; A key longer than the block size is replaced by its hash.
         (short-key (if (> (length key) +hmac-sha256-block-size+)
                        (sha256 key)
                        key))
         (inner-pad (make-byte-vector +hmac-sha256-block-size+ :initial-element #x36))
         (outer-pad (make-byte-vector +hmac-sha256-block-size+ :initial-element #x5c)))
    (dotimes (i (length short-key))
      (setf (aref inner-pad i) (logxor (aref inner-pad i) (aref short-key i))
            (aref outer-pad i) (logxor (aref outer-pad i) (aref short-key i))))
    (sha256 outer-pad (sha256 inner-pad message))))

(defun constant-time-bytes= (left right)
  "Compare LEFT and RIGHT without an early exit on the first differing byte."
  (let ((left (ensure-byte-vector left))
        (right (ensure-byte-vector right)))
    (and (= (length left) (length right))
         (let ((difference 0))
           (dotimes (i (length left))
             (setf difference (logior difference
                                      (logxor (aref left i) (aref right i)))))
           (zerop difference)))))
