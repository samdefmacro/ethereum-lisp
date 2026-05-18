(in-package #:ethereum-lisp.test)

(deftest trie-hex-prefix-examples
  (dolist (case '((#() . #(0))
                  (#(16) . #(32))
                  (#(1 2 3 4 5) . #(17 35 69))
                  (#(0 1 2 3 4 5) . #(0 1 35 69))
                  (#(15 1 12 11 8 16) . #(63 28 184))
                  (#(0 15 1 12 11 8 16) . #(32 15 28 184))))
    (let ((encoded (hex-prefix-encode (car case))))
      (is (bytes= (cdr case) encoded))
      (multiple-value-bind (decoded leafp)
          (hex-prefix-decode encoded)
        (declare (ignore leafp))
        (is (bytes= (car case) decoded))))))

(deftest trie-keybytes-nibbles-roundtrip
  (is (bytes= #(1 2 3 4 5 6 16)
              (keybytes-to-nibbles #(18 52 86))))
  (is (bytes= #(18 52 86)
              (nibbles-to-keybytes #(1 2 3 4 5 6 16)))))
