(in-package #:ethereum-lisp.blocks)

(defparameter +empty-ommers-hash+ (keccak-256-hash (rlp-encode '())))
