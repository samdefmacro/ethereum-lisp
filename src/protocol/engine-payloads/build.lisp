(in-package #:ethereum-lisp.engine-payloads)

(defun engine-payload-id (version parent-hash attributes)
  (unless (and (integerp version) (<= 0 version 255))
    (block-validation-fail "Engine payload version must fit in one byte"))
  (let* ((digest
           (sha256
            (vector version)
            (hash32-bytes parent-hash)
            (integer-to-minimal-bytes
             (payload-attributes-v1-timestamp attributes))
            (hash32-bytes (payload-attributes-v1-prev-randao attributes))
            (address-bytes
             (payload-attributes-v1-suggested-fee-recipient attributes))
            (if (payload-attributes-v1-withdrawals-present-p attributes)
                (hash32-bytes
                 (withdrawal-list-root
                  (payload-attributes-v1-withdrawals attributes)))
                #())
            (if (payload-attributes-v1-parent-beacon-root-present-p attributes)
                (hash32-bytes
                 (payload-attributes-v1-parent-beacon-root attributes))
                #())
            (if (payload-attributes-v1-slot-number-present-p attributes)
                (integer-to-minimal-bytes
                 (payload-attributes-v1-slot-number attributes))
                #())))
         (payload-id (make-byte-vector 8)))
    (setf (aref payload-id 0) version)
    (replace payload-id digest :start1 1 :start2 0 :end2 7)
    payload-id))

(defun engine-payload-id-v1 (parent-hash attributes)
  (engine-payload-id 1 parent-hash attributes))

(defun engine-payload-id-with-transactions
    (version parent-hash attributes transactions)
  (if (null transactions)
      (engine-payload-id version parent-hash attributes)
      (let* ((digest
               (sha256
                (engine-payload-id version parent-hash attributes)
                (hash32-bytes (transaction-list-root transactions))))
             (payload-id (make-byte-vector 8)))
        (setf (aref payload-id 0) version)
        (replace payload-id digest :start1 1 :start2 0 :end2 7)
        payload-id)))

(defun build-payload-excess-blob-gas (parent-header config block-number timestamp)
  "Derive the excess blob gas for a block being built on PARENT-HEADER.

Without a chain config the schedule cannot be resolved, so this falls back to
zero; that path is only reachable for pre-Cancun attributes, which carry no
excess blob gas field at all."
  (if (null config)
      0
      (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
          (chain-config-blob-schedule config block-number timestamp)
        (multiple-value-bind (parent-target parent-max parent-update-fraction)
            (chain-config-blob-schedule config
                                        (block-header-number parent-header)
                                        (block-header-timestamp parent-header))
          (declare (ignore parent-target parent-max))
          (expected-excess-blob-gas
           parent-header
           :target-blob-gas target-blob-gas
           :max-blob-gas max-blob-gas
           :eip7918-p (chain-config-osaka-p config block-number timestamp)
           :update-fraction update-fraction
           :parent-update-fraction parent-update-fraction)))))

(defun engine-build-empty-payload (parent-block attributes &optional config)
  (unless (typep parent-block 'ethereum-block)
    (block-validation-fail "Payload parent must be a known block"))
  (unless (typep attributes 'payload-attributes-v1)
    (block-validation-fail "Payload attributes must be payload-attributes-v1"))
  (let* ((parent-header (block-header parent-block))
         (block-number (1+ (block-header-number parent-header)))
         (timestamp (payload-attributes-v1-timestamp attributes)))
    (unless (> timestamp (block-header-timestamp parent-header))
      (block-validation-fail
       "Payload attributes timestamp must be greater than parent timestamp"))
    (let ((header
            (make-block-header
             :parent-hash (block-hash parent-block)
             :beneficiary
             (payload-attributes-v1-suggested-fee-recipient attributes)
             :state-root (or (block-header-state-root parent-header)
                             +empty-trie-hash+)
             :mix-hash (payload-attributes-v1-prev-randao attributes)
             :number block-number
             :gas-limit (block-header-gas-limit parent-header)
             :gas-used 0
             :timestamp timestamp
             :base-fee-per-gas
             (if (block-header-base-fee-per-gas parent-header)
                 (expected-base-fee-per-gas parent-header)
                 0)
             :parent-beacon-root
             (when (payload-attributes-v1-parent-beacon-root-present-p
                    attributes)
               (payload-attributes-v1-parent-beacon-root attributes))
             :blob-gas-used
             (when (payload-attributes-v1-parent-beacon-root-present-p
                    attributes)
               0)
             ;; A payload whose excess blob gas is not derived from the parent
             ;; is rejected by every conforming client, including this node's
             ;; own header validation.
             :excess-blob-gas
             (when (payload-attributes-v1-parent-beacon-root-present-p
                    attributes)
               (build-payload-excess-blob-gas
                parent-header config block-number timestamp))
             :slot-number
             (when (payload-attributes-v1-slot-number-present-p attributes)
               (payload-attributes-v1-slot-number attributes)))))
      (if (payload-attributes-v1-withdrawals-present-p attributes)
          (make-block
           :header header
           :withdrawals (payload-attributes-v1-withdrawals attributes))
          (make-block :header header)))))

(defun engine-build-empty-payload-v1 (parent-block attributes)
  (engine-build-empty-payload parent-block attributes))
