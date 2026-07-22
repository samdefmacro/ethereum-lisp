(in-package #:ethereum-lisp.p2p)

;;;; RLPx frame codec.
;;;;
;;;; After the handshake, every message is carried in a frame:
;;;;
;;;;   frame = header-ciphertext(16) || header-mac(16)
;;;;        || frame-ciphertext || frame-mac(16)
;;;;
;;;; Each direction has one continuous AES-CTR keystream (key = aes-secret,
;;;; IV = 0) and one running Keccak-256 MAC. The MAC advances by absorbing a
;;;; seed derived from the ciphertext and the MAC's own digest, so the header
;;;; and frame MACs interleave with the data as the spec's MAC section requires.
;;;; The reuse of aes-secret and mac-secret in both directions is the known,
;;;; intended weakness of this scheme.

(defconstant +rlpx-frame-block+ 16 "RLPx frames are aligned to the cipher block.")

(defstruct (rlpx-mac (:constructor %make-rlpx-mac))
  update
  digest)

(defun rlpx-keccak-mac (sponge)
  "A running MAC backed by a Keccak-256 SPONGE."
  (%make-rlpx-mac
   :update (lambda (bytes) (keccak-256-update sponge bytes))
   :digest (lambda () (keccak-256-digest sponge))))

(defun rlpx-constant-mac (value)
  "A MAC that ignores updates and always digests to VALUE.

Exists to reproduce go-ethereum's frame test vector, whose MAC is a stub."
  (let ((value (ensure-byte-vector value)))
    (%make-rlpx-mac
     :update (lambda (bytes) (declare (ignore bytes)) nil)
     :digest (lambda () (copy-seq value)))))

(defstruct (rlpx-session (:constructor %make-rlpx-session))
  mac-secret
  egress-cipher
  ingress-cipher
  egress-mac
  ingress-mac)

(defun make-rlpx-session (aes-secret mac-secret egress-mac ingress-mac)
  "Build an RLPx frame session from the handshake secrets and MAC states."
  (%make-rlpx-session
   :mac-secret (ensure-byte-vector mac-secret)
   :egress-cipher (make-aes-ctr-stream aes-secret)
   :ingress-cipher (make-aes-ctr-stream aes-secret)
   :egress-mac egress-mac
   :ingress-mac ingress-mac))

(defparameter +rlpx-header-data+
  (hex-to-bytes "0xc28080")
  "RLP of the header's [capability-id, context-id], both always zero.")

(defun rlpx-mac-header (session mac header-ciphertext)
  "Advance MAC with a header ciphertext and return the 16-byte header MAC.

The seed is the MAC key applied to the MAC's current digest, XORed with the
header ciphertext."
  (let ((seed (aes-encrypt-ecb-block
               (rlpx-session-mac-secret session)
               (subseq (funcall (rlpx-mac-digest mac)) 0 16))))
    (dotimes (i 16)
      (setf (aref seed i) (logxor (aref seed i) (aref header-ciphertext i))))
    (funcall (rlpx-mac-update mac) seed)
    (subseq (funcall (rlpx-mac-digest mac)) 0 16)))

(defun rlpx-mac-frame (session mac frame-ciphertext)
  "Advance MAC with a frame ciphertext and return the 16-byte frame MAC.

Unlike the header MAC, the frame ciphertext is absorbed first, and the seed is
XORed with the digest itself rather than the ciphertext."
  (funcall (rlpx-mac-update mac) frame-ciphertext)
  (let* ((digest (subseq (funcall (rlpx-mac-digest mac)) 0 16))
         (seed (aes-encrypt-ecb-block (rlpx-session-mac-secret session) digest)))
    (dotimes (i 16)
      (setf (aref seed i) (logxor (aref seed i) (aref digest i))))
    (funcall (rlpx-mac-update mac) seed)
    (subseq (funcall (rlpx-mac-digest mac)) 0 16)))

(defun rlpx-pad-to-block (bytes)
  "Zero-fill BYTES up to a 16-byte boundary."
  (let ((padded (* +rlpx-frame-block+ (ceiling (length bytes) +rlpx-frame-block+))))
    (if (= padded (length bytes))
        bytes
        (let ((out (make-byte-vector padded)))
          (replace out bytes)
          out))))

(defun rlpx-write-frame (session message-code message-data)
  "Encode and MAC one frame carrying MESSAGE-CODE and MESSAGE-DATA."
  (let* ((frame-data (concat-bytes
                      (rlp-encode (integer-to-minimal-bytes message-code))
                      (ensure-byte-vector message-data)))
         (frame-size (length frame-data))
         (header (make-byte-vector +rlpx-frame-block+)))
    (setf (aref header 0) (ldb (byte 8 16) frame-size)
          (aref header 1) (ldb (byte 8 8) frame-size)
          (aref header 2) (ldb (byte 8 0) frame-size))
    (replace header +rlpx-header-data+ :start1 3)
    (let* ((header-ciphertext
             (aes-ctr-stream-apply (rlpx-session-egress-cipher session) header))
           (header-mac
             (rlpx-mac-header session (rlpx-session-egress-mac session)
                              header-ciphertext))
           (frame-ciphertext
             (aes-ctr-stream-apply (rlpx-session-egress-cipher session)
                                   (rlpx-pad-to-block frame-data)))
           (frame-mac
             (rlpx-mac-frame session (rlpx-session-egress-mac session)
                             frame-ciphertext)))
      (concat-bytes header-ciphertext header-mac
                    frame-ciphertext frame-mac))))

(defun rlpx-read-frame (session frame)
  "Verify and decrypt one FRAME, returning (VALUES MESSAGE-CODE MESSAGE-DATA)."
  (let ((frame (ensure-byte-vector frame)))
    (when (< (length frame) (* 2 +rlpx-frame-block+))
      (error "RLPx frame is too short for a header"))
    (let* ((header-ciphertext (subseq frame 0 +rlpx-frame-block+))
           (header-mac (subseq frame +rlpx-frame-block+ (* 2 +rlpx-frame-block+)))
           (expected (rlpx-mac-header session (rlpx-session-ingress-mac session)
                                      header-ciphertext)))
      (unless (constant-time-bytes= header-mac expected)
        (error "RLPx header MAC does not authenticate the frame"))
      (let* ((header (aes-ctr-stream-apply (rlpx-session-ingress-cipher session)
                                           header-ciphertext))
             (frame-size (logior (ash (aref header 0) 16)
                                 (ash (aref header 1) 8)
                                 (aref header 2)))
             (padded (* +rlpx-frame-block+
                        (ceiling frame-size +rlpx-frame-block+)))
             (start (* 2 +rlpx-frame-block+))
             (end (+ start padded)))
        (when (< (length frame) (+ end +rlpx-frame-block+))
          (error "RLPx frame is shorter than its declared size"))
        (let* ((frame-ciphertext (subseq frame start end))
               (frame-mac (subseq frame end (+ end +rlpx-frame-block+)))
               (expected-frame-mac
                 (rlpx-mac-frame session (rlpx-session-ingress-mac session)
                                 frame-ciphertext)))
          (unless (constant-time-bytes= frame-mac expected-frame-mac)
            (error "RLPx frame MAC does not authenticate the frame"))
          (let ((frame-data
                  (subseq (aes-ctr-stream-apply
                           (rlpx-session-ingress-cipher session) frame-ciphertext)
                          0 frame-size)))
            (multiple-value-bind (code next)
                (rlp-decode frame-data :allow-trailing t)
              (values (bytes-to-integer (ensure-byte-vector code))
                      (subseq frame-data next)))))))))
