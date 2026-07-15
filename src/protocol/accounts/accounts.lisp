(in-package #:ethereum-lisp.accounts)

;;; Account payload encoding used by state, genesis, and trie commitments.

(defstruct (state-account (:constructor make-state-account
                             (&key (nonce 0)
                                   (balance 0)
                                   (storage-root +empty-trie-hash+)
                                   (code-hash +empty-code-hash+))))
  (nonce 0 :type (integer 0 *))
  (balance 0 :type (integer 0 *))
  (storage-root +empty-trie-hash+ :type hash32)
  (code-hash +empty-code-hash+ :type hash32))

(defun state-account-rlp (account)
  (rlp-encode
   (make-rlp-list
    (ensure-uint256 (state-account-nonce account) "Account nonce")
    (ensure-uint256 (state-account-balance account) "Account balance")
    (hash32-bytes (state-account-storage-root account))
    (hash32-bytes (state-account-code-hash account)))))

(defun state-account-hash (account)
  (keccak-256-hash (state-account-rlp account)))
