(in-package #:ethereum-lisp.engine-payloads)

(defstruct (executable-data (:constructor make-executable-data
                              (&key parent-hash
                                    fee-recipient
                                    state-root
                                    receipts-root
                                    logs-bloom
                                    random
                                    number
                                    gas-limit
                                    gas-used
                                    timestamp
                                    extra-data
                                    base-fee-per-gas
                                    block-hash
                                    transactions
                                    withdrawals
                                    withdrawals-present-p
                                    blob-gas-used
                                    excess-blob-gas
                                    slot-number
                                    block-access-list)))
  parent-hash
  fee-recipient
  state-root
  receipts-root
  logs-bloom
  random
  number
  gas-limit
  gas-used
  timestamp
  extra-data
  base-fee-per-gas
  block-hash
  (transactions '() :type list)
  withdrawals
  withdrawals-present-p
  blob-gas-used
  excess-blob-gas
  slot-number
  block-access-list)

(defstruct (execution-payload-envelope
            (:constructor make-execution-payload-envelope
                (&key execution-payload
                      (block-value 0)
                      blobs-bundle
                      requests
                      override-p)))
  execution-payload
  (block-value 0 :type (integer 0 *))
  blobs-bundle
  requests
  override-p)

(defparameter +payload-status-valid+ "VALID")
(defparameter +payload-status-invalid+ "INVALID")
(defparameter +payload-status-syncing+ "SYNCING")
(defparameter +payload-status-accepted+ "ACCEPTED")
(defconstant +eth-protocol-version+ 70)

(defstruct (payload-status
            (:constructor make-payload-status
                (&key status latest-valid-hash validation-error witness)))
  status
  latest-valid-hash
  validation-error
  witness)

(defstruct (forkchoice-state
            (:constructor make-forkchoice-state
                (&key head-block-hash safe-block-hash finalized-block-hash)))
  head-block-hash
  safe-block-hash
  finalized-block-hash)

(defstruct (payload-attributes-v1
            (:constructor make-payload-attributes-v1
                (&key timestamp prev-randao suggested-fee-recipient
                      withdrawals withdrawals-present-p
                      parent-beacon-root parent-beacon-root-present-p
                      slot-number slot-number-present-p)))
  timestamp
  prev-randao
  suggested-fee-recipient
  withdrawals
  withdrawals-present-p
  parent-beacon-root
  parent-beacon-root-present-p
  slot-number
  slot-number-present-p)

(defstruct (engine-prepared-payload
            (:constructor make-engine-prepared-payload
                (&key payload-id version block blobs-bundle)))
  payload-id
  version
  block
  blobs-bundle)

(defun validate-engine-prepared-payload-blobs-bundle (bundle)
  (when bundle
    (unless (typep bundle 'blob-sidecar)
      (block-validation-fail
       "Engine prepared payload blobs bundle must be a blob-sidecar"))
    (handler-case
        (progn
          (mapcar #'ensure-byte-vector (blob-sidecar-blobs bundle))
          (mapcar #'ensure-byte-vector (blob-sidecar-commitments bundle))
          (mapcar #'ensure-byte-vector (blob-sidecar-proofs bundle)))
      (error ()
        (block-validation-fail
         "Engine prepared payload blobs bundle entries must be byte vectors"))))
  bundle)

(defun validate-engine-prepared-payload (prepared-payload)
  (unless (typep prepared-payload 'engine-prepared-payload)
    (block-validation-fail
     "Engine prepared payload must be an engine-prepared-payload"))
  (let ((payload-id
          (validate-sized-byte-vector
           (engine-prepared-payload-payload-id prepared-payload)
           8
           "Engine prepared payload id"))
        (version (engine-prepared-payload-version prepared-payload)))
    (unless (and (integerp version) (<= 1 version 6))
      (block-validation-fail
       "Engine prepared payload version must be between 1 and 6"))
    (unless (= version (aref payload-id 0))
      (block-validation-fail
       "Engine prepared payload id version does not match payload version"))
    (unless (typep (engine-prepared-payload-block prepared-payload)
                   'ethereum-block)
      (block-validation-fail
       "Engine prepared payload block must be an ethereum-block"))
    (validate-engine-prepared-payload-blobs-bundle
     (engine-prepared-payload-blobs-bundle prepared-payload))
    prepared-payload))
