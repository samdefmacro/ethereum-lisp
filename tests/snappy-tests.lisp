(in-package #:ethereum-lisp.test)

;;;; Snappy against the golang/snappy decode vectors, plus round-trip.

(deftest snappy-decompress-matches-golang-vectors
  (labels ((dec (hex) (bytes-to-hex (snappy-decompress (hex-to-bytes hex)))))
    ;; decodedLen=0.
    (is (string= "0x" (dec "0x00")))
    ;; literal, 0-byte length, length=3.
    (is (string= "0xffffff" (dec "0x0308ffffff")))
    ;; literal, 1-byte length; length=3.
    (is (string= "0xffffff" (dec "0x03f002ffffff")))
    ;; literal, 2-byte length; length=3.
    (is (string= "0xffffff" (dec "0x03f40200ffffff")))
    ;; tagCopy1: "abcd" then copy length=9 offset=4 -> "abcdabcdabcda".
    (is (string= (bytes-to-hex (ascii-to-bytes "abcdabcdabcda"))
                 (dec (concatenate 'string "0x0d0c"
                                   (subseq (bytes-to-hex (ascii-to-bytes "abcd")) 2)
                                   "1504"))))
    ;; tagCopy1 overlapping copies of various offsets.
    (is (string= (bytes-to-hex (ascii-to-bytes "abcdabcd"))
                 (dec (concatenate 'string "0x080c" (subseq (bytes-to-hex (ascii-to-bytes "abcd")) 2) "0104"))))
    (is (string= (bytes-to-hex (ascii-to-bytes "abcdcdcd"))
                 (dec (concatenate 'string "0x080c" (subseq (bytes-to-hex (ascii-to-bytes "abcd")) 2) "0102"))))
    (is (string= (bytes-to-hex (ascii-to-bytes "abcddddd"))
                 (dec (concatenate 'string "0x080c" (subseq (bytes-to-hex (ascii-to-bytes "abcd")) 2) "0101"))))
    ;; tagCopy2: length=2 offset=3 -> "abcd" + "bc" = "abcdbc".
    (is (string= (bytes-to-hex (ascii-to-bytes "abcdbc"))
                 (dec (concatenate 'string "0x060c" (subseq (bytes-to-hex (ascii-to-bytes "abcd")) 2) "060300"))))))

(deftest snappy-decompress-rejects-corrupt-input
  ;; Not enough dst bytes (decodedLen too small for the literal).
  (signals error (snappy-decompress (hex-to-bytes "0x0208ffffff")))
  ;; Not enough src bytes.
  (signals error (snappy-decompress (hex-to-bytes "0x0308ffff")))
  ;; Zero copy offset.
  (signals error (snappy-decompress
                  (hex-to-bytes (concatenate 'string "0x080c"
                                             (subseq (bytes-to-hex (ascii-to-bytes "abcd")) 2) "0100"))))
  ;; Copy offset too large.
  (signals error (snappy-decompress
                  (hex-to-bytes (concatenate 'string "0x080c"
                                             (subseq (bytes-to-hex (ascii-to-bytes "abcd")) 2) "0105"))))
  ;; Copy length overruns the declared length.
  (signals error (snappy-decompress
                  (hex-to-bytes (concatenate 'string "0x070c"
                                             (subseq (bytes-to-hex (ascii-to-bytes "abcd")) 2) "0104"))))
  ;; Output shorter than the declared length.
  (signals error (snappy-decompress
                  (hex-to-bytes (concatenate 'string "0x090c"
                                             (subseq (bytes-to-hex (ascii-to-bytes "abcd")) 2) "0104")))))

(deftest snappy-compress-round-trips
  (dolist (case (list (make-byte-vector 0)
                      (ascii-to-bytes "a")
                      (ascii-to-bytes "hello, world")
                      (make-byte-vector 60 :initial-element #x41)
                      (make-byte-vector 300 :initial-element #x42)
                      (make-byte-vector 70000 :initial-element #x7a)))
    (let ((compressed (snappy-compress case)))
      (is (bytes= case (snappy-decompress compressed)))))
  ;; The compressor's own output is a valid block a decoder reads back.
  (let* ((data (ascii-to-bytes "the quick brown fox jumps over the lazy dog"))
         (compressed (snappy-compress data)))
    (is (bytes= data (snappy-decompress compressed)))))
