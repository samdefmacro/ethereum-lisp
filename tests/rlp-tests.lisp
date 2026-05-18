(in-package #:ethereum-lisp.test)

(defun rlp-hex (value)
  (bytes-to-hex (rlp-encode value)))

(deftest rlp-ethereum-examples
  (is (string= "0x83646f67" (rlp-hex "dog")))
  (is (string= "0xc88363617483646f67" (rlp-hex '("cat" "dog"))))
  (is (string= "0x80" (rlp-hex "")))
  (is (string= "0xc0" (rlp-hex '())))
  (is (string= "0x0f" (rlp-hex 15)))
  (is (string= "0x820400" (rlp-hex 1024)))
  (is (string= "0xc7c0c1c0c3c0c1c0"
               (rlp-hex (list '() (list '()) (list '() (list '())))))))

(deftest rlp-long-string-example
  (let ((text "Lorem ipsum dolor sit amet, consectetur adipisicing elit"))
    (is (string= "0xb8384c6f72656d20697073756d20646f6c6f722073697420616d65742c20636f6e7365637465747572206164697069736963696e6720656c6974"
                 (rlp-hex text)))))

(deftest rlp-decode-examples
  (is (string= "dog" (bytes-to-ascii (rlp-decode-one (hex-to-bytes "0x83646f67")))))
  (let ((decoded (rlp-decode-one (hex-to-bytes "0xc88363617483646f67"))))
    (is (rlp-list-p decoded))
    (is (string= "cat" (bytes-to-ascii (first (rlp-list-items decoded)))))
    (is (string= "dog" (bytes-to-ascii (second (rlp-list-items decoded)))))))

(deftest rlp-rejects-non-canonical-forms
  (signals rlp-error (rlp-decode-one (hex-to-bytes "0x8101")))
  (signals rlp-error (rlp-decode-one (hex-to-bytes "0xb80100")))
  (signals rlp-error (rlp-decode-one (hex-to-bytes "0xf801c0"))))
