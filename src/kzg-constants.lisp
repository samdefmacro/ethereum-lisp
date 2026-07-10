(in-package #:ethereum-lisp.kzg)

(defconstant +blob-byte-size+ +blob-gas-per-blob+)
(defconstant +kzg-proof-size+ +kzg-commitment-size+)
(defconstant +kzg-field-element-size+ 32)
(defconstant +kzg-blob-field-elements-per-blob+ 4096)
(defconstant +kzg-field-modulus+
  #x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001)
(defconstant +cell-proofs-per-blob+ 128)
