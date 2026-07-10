(in-package #:ethereum-lisp.block-access-lists)

(defun block-access-list-hash (block-access-list)
  (validate-block-access-list-fields block-access-list)
  (keccak-256-hash (block-access-list-rlp block-access-list)))
