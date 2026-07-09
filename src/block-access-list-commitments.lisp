(in-package #:ethereum-lisp.core)

(defun block-access-list-hash (block-access-list)
  (validate-block-access-list-fields block-access-list)
  (keccak-256-hash (block-access-list-rlp block-access-list)))

(defun validated-block-access-list-commitment
    (block &key max-code-size max-items)
  (let ((access-list (block-block-access-list block))
        (encoded (block-encoded-block-access-list block)))
    (validate-block-access-list-fields access-list
                                       :max-code-size max-code-size
                                       :max-items max-items)
    (if encoded
        (let ((decoded (block-access-list-from-rlp
                        encoded
                        :max-code-size max-code-size
                        :max-items max-items)))
          (unless (bytes= (block-access-list-rlp decoded)
                          (block-access-list-rlp access-list))
            (block-validation-fail
             "Encoded block access list does not match block access list body"))
          (keccak-256-hash encoded))
        (block-access-list-hash access-list))))
