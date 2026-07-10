(in-package #:ethereum-lisp.blocks)

(defstruct (block-header (:constructor make-block-header
                            (&key parent-hash
                                  ommers-hash
                                  beneficiary
                                  state-root
                                  transactions-root
                                  receipts-root
                                  logs-bloom
                                  (difficulty 0)
                                  (number 0)
                                  (gas-limit 0)
                                  (gas-used 0)
                                  (timestamp 0)
                                  (extra-data #())
                                  mix-hash
                                  nonce
                                  base-fee-per-gas
                                  withdrawals-root
                                  blob-gas-used
                                  excess-blob-gas
                                  parent-beacon-root
                                  requests-hash
                                  block-access-list-hash
                                  slot-number)))
  parent-hash
  ommers-hash
  beneficiary
  state-root
  transactions-root
  receipts-root
  logs-bloom
  (difficulty 0 :type (integer 0 *))
  (number 0 :type (integer 0 *))
  (gas-limit 0 :type (integer 0 *))
  (gas-used 0 :type (integer 0 *))
  (timestamp 0 :type (integer 0 *))
  (extra-data (make-byte-vector 0))
  mix-hash
  nonce
  base-fee-per-gas
  withdrawals-root
  blob-gas-used
  excess-blob-gas
  parent-beacon-root
  requests-hash
  block-access-list-hash
  slot-number)

(defstruct (ethereum-block (:constructor %make-block
                             (&key header
                                   (transactions '())
                                   (receipts '())
                                   (ommers '())
                                   withdrawals
                                   withdrawals-present-p
                                   requests
                                   requests-present-p
                                   block-access-list
                                   block-access-list-present-p
                                   encoded-block-access-list))
                           (:conc-name block-))
  header
  (transactions '() :type list)
  (receipts '() :type list)
  (ommers '() :type list)
  withdrawals
  withdrawals-present-p
  requests
  requests-present-p
  block-access-list
  block-access-list-present-p
  encoded-block-access-list)
