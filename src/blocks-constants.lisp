(in-package #:ethereum-lisp.blocks)

(defparameter +empty-ommers-hash+ (keccak-256-hash (rlp-encode '())))
(defconstant +initial-base-fee+ 1000000000)
(defconstant +maximum-extra-data-size+ 32)
(defconstant +max-header-gas-limit+ #x7fffffffffffffff)
