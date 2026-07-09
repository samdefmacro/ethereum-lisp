(in-package #:ethereum-lisp.core)

(defun validate-block-header-field-shapes
    (header &key require-parent-hash-p)
  (unless (block-header-p header)
    (block-validation-fail "Block header must be a block header"))
  (if require-parent-hash-p
      (unless (hash32-p (block-header-parent-hash header))
        (block-validation-fail "Header parent hash must be a hash32"))
      (validate-optional-hash32-field (block-header-parent-hash header)
                                      "Header parent hash"))
  (validate-optional-hash32-field (block-header-ommers-hash header)
                                  "Header ommers hash")
  (validate-optional-address-field (block-header-beneficiary header)
                                   "Header beneficiary")
  (validate-optional-hash32-field (block-header-state-root header)
                                  "Header state root")
  (validate-optional-hash32-field (block-header-transactions-root header)
                                  "Header transactions root")
  (validate-optional-hash32-field (block-header-receipts-root header)
                                  "Header receipts root")
  (when (block-header-logs-bloom header)
    (validate-byte-sequence-field (block-header-logs-bloom header)
                                  "Header logs bloom"
                                  :size 256))
  (unless (uint256-p (block-header-difficulty header))
    (block-validation-fail "Header difficulty must be uint256"))
  (unless (uint256-p (block-header-number header))
    (block-validation-fail "Header number must be uint256"))
  (unless (uint256-p (block-header-gas-limit header))
    (block-validation-fail "Header gas limit must be uint256"))
  (unless (uint256-p (block-header-gas-used header))
    (block-validation-fail "Header gas used must be uint256"))
  (unless (uint256-p (block-header-timestamp header))
    (block-validation-fail "Header timestamp must be uint256"))
  (validate-byte-sequence-field (block-header-extra-data header)
                                "Header extra data")
  (validate-optional-hash32-field (block-header-mix-hash header)
                                  "Header mix hash")
  (when (block-header-nonce header)
    (validate-byte-sequence-field (block-header-nonce header)
                                  "Header nonce"
                                  :size 8))
  (validate-optional-uint256-field (block-header-base-fee-per-gas header)
                                   "Header base fee")
  (validate-optional-hash32-field (block-header-withdrawals-root header)
                                  "Header withdrawals root")
  (validate-optional-uint256-field (block-header-blob-gas-used header)
                                   "Header blob gas used")
  (validate-optional-uint256-field (block-header-excess-blob-gas header)
                                   "Header excess blob gas")
  (validate-optional-hash32-field (block-header-parent-beacon-root header)
                                  "Header parent beacon root")
  (validate-optional-hash32-field (block-header-requests-hash header)
                                  "Header requests hash")
  (validate-optional-hash32-field (block-header-block-access-list-hash header)
                                  "Header block access list hash")
  (validate-optional-uint64-field (block-header-slot-number header)
                                  "Header slot number")
  t)

(defun validate-block-header-basics
    (parent-header header &key (validate-base-fee-p nil
                                validate-base-fee-p-supplied-p)
                         (london-parent-p t)
                         (withdrawals-enabled-p nil
                          withdrawals-enabled-p-supplied-p)
                         (cancun-enabled-p nil
                          cancun-enabled-p-supplied-p)
                         (requests-enabled-p nil
                          requests-enabled-p-supplied-p)
                         (amsterdam-enabled-p nil
                          amsterdam-enabled-p-supplied-p)
                         (osaka-enabled-p nil)
                         (expanded-blob-schedule-p nil
                          expanded-blob-schedule-p-supplied-p)
                         blob-schedule-target-gas
                         blob-schedule-max-gas
                         blob-schedule-update-fraction
                         (post-merge-p nil post-merge-p-supplied-p))
  (validate-block-header-field-shapes parent-header)
  (validate-block-header-field-shapes header :require-parent-hash-p t)
  (let ((validate-base-fee-p
          (if validate-base-fee-p-supplied-p
              validate-base-fee-p
              (block-header-base-fee-per-gas header)))
        (withdrawals-enabled-p
          (if withdrawals-enabled-p-supplied-p
              withdrawals-enabled-p
              (block-header-withdrawals-root header)))
        (cancun-enabled-p
          (if cancun-enabled-p-supplied-p
              cancun-enabled-p
              (block-header-cancun-fields-present-p header)))
        (requests-enabled-p
          (if requests-enabled-p-supplied-p
              requests-enabled-p
              (block-header-requests-hash header)))
        (amsterdam-enabled-p
          (if amsterdam-enabled-p-supplied-p
              amsterdam-enabled-p
              (block-header-amsterdam-fields-present-p header)))
        (expanded-blob-schedule-p
          (if expanded-blob-schedule-p-supplied-p
              expanded-blob-schedule-p
              osaka-enabled-p))
        (post-merge-p
          (if post-merge-p-supplied-p
              post-merge-p
              (block-header-post-merge-p header))))
    (unless (hash32= (block-header-parent-hash header)
                     (block-header-hash parent-header))
      (block-validation-fail "Parent hash mismatch"))
    (validate-block-merge-transition parent-header header)
    (validate-block-merge-fields header :post-merge-p post-merge-p)
    (unless (= (block-header-number header)
               (1+ (block-header-number parent-header)))
      (block-validation-fail "Block number is not parent plus one"))
    (unless (> (block-header-timestamp header)
               (block-header-timestamp parent-header))
      (block-validation-fail "Timestamp is not greater than parent timestamp"))
    (when (> (block-header-gas-used header)
             (block-header-gas-limit header))
      (block-validation-fail "Gas used exceeds gas limit"))
    (validate-gas-limit-delta (adjusted-parent-gas-limit-for-1559
                               parent-header
                               london-parent-p)
                              (block-header-gas-limit header))
    (when (> (length (ensure-byte-vector (block-header-extra-data header)))
             +maximum-extra-data-size+)
      (block-validation-fail "Extra data too long"))
    (if cancun-enabled-p
        (let ((target-blob-gas
                (or blob-schedule-target-gas
                    (* (if expanded-blob-schedule-p
                           +osaka-target-blobs-per-block+
                           +target-blobs-per-block+)
                       +blob-gas-per-blob+)))
              (max-blob-gas
                (or blob-schedule-max-gas
                    (* (if expanded-blob-schedule-p
                           +osaka-max-blobs-per-block+
                           +max-blobs-per-block+)
                       +blob-gas-per-blob+)))
              (update-fraction
                (or blob-schedule-update-fraction
                    (if expanded-blob-schedule-p
                        +osaka-blob-base-fee-update-fraction+
                        +blob-base-fee-update-fraction+))))
          (validate-block-cancun-fields header :cancun-enabled-p t)
          (validate-block-excess-blob-gas
           parent-header header
           :target-blob-gas target-blob-gas
           :max-blob-gas max-blob-gas
           :eip7918-p osaka-enabled-p
           :update-fraction update-fraction))
        (progn
          (validate-block-cancun-fields header :cancun-enabled-p nil)
          (validate-block-blob-gas-fields header)))
    (validate-block-withdrawals-field
     header :withdrawals-enabled-p withdrawals-enabled-p)
    (validate-block-requests-hash-field
     header :requests-enabled-p requests-enabled-p)
    (validate-block-amsterdam-fields
     header :amsterdam-enabled-p amsterdam-enabled-p)
    (when amsterdam-enabled-p
      (validate-block-amsterdam-slot-number parent-header header))
    (when validate-base-fee-p
      (validate-block-base-fee parent-header header
                               :london-parent-p london-parent-p)))
  t)

(defun validate-block-header-against-config (parent-header header config)
  (let ((number (block-header-number header))
        (timestamp (block-header-timestamp header)))
    (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
        (chain-config-blob-schedule config number timestamp)
      (validate-block-header-basics
       parent-header header
       :validate-base-fee-p (chain-config-london-p config number)
       :london-parent-p (chain-config-london-p
                         config (block-header-number parent-header))
       :withdrawals-enabled-p (chain-config-shanghai-p config number timestamp)
       :cancun-enabled-p (chain-config-cancun-p config number timestamp)
       :requests-enabled-p (chain-config-prague-p config number timestamp)
       :amsterdam-enabled-p (chain-config-amsterdam-p config number timestamp)
       :osaka-enabled-p (chain-config-osaka-p config number timestamp)
       :expanded-blob-schedule-p
       (chain-config-expanded-blob-schedule-p config number timestamp)
       :blob-schedule-target-gas target-blob-gas
       :blob-schedule-max-gas max-blob-gas
       :blob-schedule-update-fraction update-fraction
       :post-merge-p (block-header-post-merge-p header)))))
