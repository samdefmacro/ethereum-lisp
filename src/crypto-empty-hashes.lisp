(in-package #:ethereum-lisp.crypto)

(defparameter +empty-code-hash+ (keccak-256-hash #()))

(defparameter +empty-trie-hash+ (keccak-256-hash #(128)))
