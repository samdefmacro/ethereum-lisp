(in-package #:ethereum-lisp.block-access-lists)

(defstruct (block-access-account (:constructor make-block-access-account
                                      (&key address
                                            (storage-writes '())
                                            (storage-reads '())
                                            (balance-changes '())
                                            (nonce-changes '())
                                            (code-changes '()))))
  address
  (storage-writes '() :type list)
  (storage-reads '() :type list)
  (balance-changes '() :type list)
  (nonce-changes '() :type list)
  (code-changes '() :type list))

(defstruct (block-access-storage-write
            (:constructor make-block-access-storage-write
                (&key tx-index value-after)))
  tx-index
  value-after)

(defstruct (block-access-slot-writes
            (:constructor make-block-access-slot-writes
                (&key slot (accesses '()))))
  slot
  (accesses '() :type list))

(defstruct (block-access-balance-change
            (:constructor make-block-access-balance-change
                (&key tx-index balance)))
  tx-index
  balance)

(defstruct (block-access-nonce-change
            (:constructor make-block-access-nonce-change
                (&key tx-index nonce)))
  tx-index
  nonce)

(defstruct (block-access-code-change
            (:constructor make-block-access-code-change
                (&key tx-index code)))
  tx-index
  code)
