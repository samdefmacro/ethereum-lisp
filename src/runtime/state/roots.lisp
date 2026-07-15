(in-package #:ethereum-lisp.state)

(defun state-db-state-trie (state)
  (let ((trie (make-mpt)))
    (maphash (lambda (address object)
               (let* ((address-hash (keccak-256 (address-bytes (address-from-hex address))))
                      (account (account-with-storage-root object)))
                 (mpt-put trie address-hash (state-account-rlp account))))
             (state-db-objects state))
    trie))

(defun state-db-account-proof-key (address)
  (keccak-256 (address-bytes address)))

(defun state-db-get-account-proof (state address)
  (mpt-get-proof (state-db-state-trie state)
                 (state-db-account-proof-key address)))

(defun state-db-verify-account-proof (state-root address proof)
  (mpt-verify-proof state-root (state-db-account-proof-key address) proof))

(defun state-db-root (state)
  (make-hash32 (mpt-root-hash (state-db-state-trie state))))

(defun state-db-root-hex (state)
  (hash32-to-hex (state-db-root state)))
