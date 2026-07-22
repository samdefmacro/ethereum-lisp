(in-package #:ethereum-lisp.test)

;;;; RLPx frame codec: go-ethereum's golden frame vector (which uses a stub MAC)
;;;; and a real-Keccak-MAC write/read round-trip.

(deftest rlpx-frame-matches-go-ethereum-golden
  ;; go-ethereum p2p/rlpx TestFrameReadWrite: AES = MAC = Keccak256() and a stub
  ;; MAC that always digests to 0x01*32, writing msg code 8 with rlp([1,2,3,4]).
  (let* ((secret (keccak-256))
         (stub (make-byte-vector 32 :initial-element 1))
         (session (make-rlpx-session secret secret
                                     (rlpx-constant-mac stub)
                                     (rlpx-constant-mac stub)))
         (golden (hex-to-bytes
                  (concatenate 'string
                               "0x00828ddae471818bb0bfa6b551d1cb42"
                               "01010101010101010101010101010101"
                               "ba628a4ba590cb43f7848f41c4382885"
                               "01010101010101010101010101010101"))))
    (is (bytes= golden
                (rlpx-write-frame session 8 (hex-to-bytes "0xc401020304"))))
    ;; Reading the golden back yields the message code and payload.
    (let ((reader (make-rlpx-session secret secret
                                     (rlpx-constant-mac stub)
                                     (rlpx-constant-mac stub))))
      (multiple-value-bind (code data) (rlpx-read-frame reader golden)
        (is (= 8 code))
        (is (bytes= (hex-to-bytes "0xc401020304") data))))))

(deftest rlpx-frames-round-trip-with-real-macs
  ;; A writer's egress MAC and a reader's ingress MAC start from the same state,
  ;; exactly as the handshake initialises them, so successive frames stay in
  ;; sync across both the cipher stream and the running MAC.
  (let* ((aes-secret (keccak-256 (ascii-to-bytes "aes-secret")))
         (mac-secret (keccak-256 (ascii-to-bytes "mac-secret")))
         (seed (ascii-to-bytes "shared mac initialisation seed"))
         (writer-egress (make-keccak-256))
         (reader-ingress (make-keccak-256)))
    (keccak-256-update writer-egress seed)
    (keccak-256-update reader-ingress seed)
    (let ((writer (make-rlpx-session aes-secret mac-secret
                                     (rlpx-keccak-mac writer-egress)
                                     (rlpx-keccak-mac (make-keccak-256))))
          (reader (make-rlpx-session aes-secret mac-secret
                                     (rlpx-keccak-mac (make-keccak-256))
                                     (rlpx-keccak-mac reader-ingress))))
      ;; Several frames of varying size, in order, all round-trip.
      (dolist (message (list (list 0 (hex-to-bytes "0x80"))
                             (list 8 (hex-to-bytes "0xc401020304"))
                             (list 16 (make-byte-vector 40 :initial-element #x2a))))
        (let ((frame (rlpx-write-frame writer (first message) (second message))))
          (multiple-value-bind (code data) (rlpx-read-frame reader frame)
            (is (= (first message) code))
            (is (bytes= (second message) data))))))
    ;; A tampered frame fails the MAC rather than decoding to garbage.
    (let* ((w-egress (make-keccak-256))
           (r-ingress (make-keccak-256)))
      (keccak-256-update w-egress seed)
      (keccak-256-update r-ingress seed)
      (let* ((writer (make-rlpx-session aes-secret mac-secret
                                        (rlpx-keccak-mac w-egress)
                                        (rlpx-keccak-mac (make-keccak-256))))
             (reader (make-rlpx-session aes-secret mac-secret
                                        (rlpx-keccak-mac (make-keccak-256))
                                        (rlpx-keccak-mac r-ingress)))
             (frame (copy-seq (rlpx-write-frame writer 8 (hex-to-bytes "0xc401020304")))))
        (setf (aref frame 40) (logxor (aref frame 40) 1))
        (signals error (rlpx-read-frame reader frame))))))
