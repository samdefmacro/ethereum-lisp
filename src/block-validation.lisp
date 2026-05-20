(in-package #:ethereum-lisp.core)

(defun validate-block-base-fee (parent-header header &key (london-parent-p t))
  (unless (block-header-base-fee-per-gas header)
    (block-validation-fail "Header is missing base fee"))
  (let ((expected (expected-base-fee-per-gas
                   parent-header :london-parent-p london-parent-p)))
    (unless (= expected (block-header-base-fee-per-gas header))
      (block-validation-fail "Base fee mismatch"))
    t))

(defun validate-gas-limit-delta
    (parent-gas-limit header-gas-limit
     &key (bound-divisor +gas-limit-bound-divisor+)
          (minimum-gas-limit +minimum-gas-limit+))
  (let ((limit (floor parent-gas-limit bound-divisor))
        (diff (abs (- parent-gas-limit header-gas-limit))))
    (when (>= diff limit)
      (block-validation-fail "Gas limit changed too much"))
    (when (< header-gas-limit minimum-gas-limit)
      (block-validation-fail "Gas limit below minimum"))
    t))

(defun adjusted-parent-gas-limit-for-1559 (parent-header london-parent-p)
  (let ((parent-gas-limit (block-header-gas-limit parent-header)))
    (if london-parent-p
        parent-gas-limit
        (* parent-gas-limit +base-fee-elasticity-multiplier+))))

(defun validate-block-blob-gas-fields
    (header &key (blob-gas-enabled-p
                  (or (block-header-blob-gas-used header)
                      (block-header-excess-blob-gas header)))
                 (max-blob-gas (* +max-blobs-per-block+
                                  +blob-gas-per-blob+)))
  (cond
    (blob-gas-enabled-p
     (unless (block-header-blob-gas-used header)
       (block-validation-fail "Header is missing blob gas used"))
     (unless (block-header-excess-blob-gas header)
       (block-validation-fail "Header is missing excess blob gas"))
     (when (and max-blob-gas
                (> (block-header-blob-gas-used header) max-blob-gas))
       (block-validation-fail "Blob gas used exceeds maximum"))
     (unless (zerop (mod (block-header-blob-gas-used header)
                         +blob-gas-per-blob+))
       (block-validation-fail "Blob gas used is not a blob-sized multiple")))
    ((or (block-header-blob-gas-used header)
         (block-header-excess-blob-gas header))
     (block-validation-fail "Blob gas fields present before Cancun")))
  t)

(defun expected-excess-blob-gas
    (parent-header &key (target-blob-gas
                         (* +target-blobs-per-block+
                            +blob-gas-per-blob+))
                        (max-blob-gas
                         (* +max-blobs-per-block+
                            +blob-gas-per-blob+))
                        eip7918-p
                        (update-fraction
                         +blob-base-fee-update-fraction+))
  (let* ((parent-excess (or (block-header-excess-blob-gas parent-header) 0))
         (parent-used (or (block-header-blob-gas-used parent-header) 0))
         (parent-blob-gas (+ parent-excess parent-used)))
    (cond
      ((< parent-blob-gas target-blob-gas) 0)
      ((and eip7918-p
            (block-header-base-fee-per-gas parent-header)
            (> (* +blob-base-cost+
                  (block-header-base-fee-per-gas parent-header))
               (* +blob-gas-per-blob+
                  (blob-base-fee parent-excess
                                 :update-fraction update-fraction))))
       (+ parent-excess
          (floor (* parent-used (- max-blob-gas target-blob-gas))
                 max-blob-gas)))
      (t (- parent-blob-gas target-blob-gas)))))

(defun fake-exponential (factor numerator denominator)
  (let ((output 0)
        (accumulator (* factor denominator)))
    (loop for i from 1
          while (plusp accumulator)
          do (incf output accumulator)
             (setf accumulator
                   (floor (* accumulator numerator)
                          (* denominator i))))
    (floor output denominator)))

(defun blob-base-fee
    (excess-blob-gas &key (min-blob-gas-price +min-blob-gas-price+)
                          (update-fraction
                           +blob-base-fee-update-fraction+))
  (fake-exponential min-blob-gas-price
                    excess-blob-gas
                    update-fraction))

(defun block-header-blob-base-fee
    (header &key (update-fraction +blob-base-fee-update-fraction+))
  (unless (block-header-excess-blob-gas header)
    (block-validation-fail "Header is missing excess blob gas"))
  (blob-base-fee (block-header-excess-blob-gas header)
                 :update-fraction update-fraction))

(defun validate-block-excess-blob-gas
    (parent-header header &key (target-blob-gas
                                (* +target-blobs-per-block+
                                   +blob-gas-per-blob+))
                              (max-blob-gas
                               (* +max-blobs-per-block+
                                  +blob-gas-per-blob+))
                              eip7918-p
                              (update-fraction
                               +blob-base-fee-update-fraction+))
  (validate-block-blob-gas-fields header :max-blob-gas max-blob-gas)
  (let ((expected (expected-excess-blob-gas
                   parent-header
                   :target-blob-gas target-blob-gas
                   :max-blob-gas max-blob-gas
                   :eip7918-p eip7918-p
                   :update-fraction update-fraction)))
    (unless (= expected (block-header-excess-blob-gas header))
      (block-validation-fail "Excess blob gas mismatch"))
    t))

(defun block-header-cancun-fields-present-p (header)
  (or (block-header-blob-gas-used header)
      (block-header-excess-blob-gas header)))

(defun validate-block-cancun-fields
    (header &key (cancun-enabled-p
                  (block-header-cancun-fields-present-p header)))
  (if cancun-enabled-p
      (unless (block-header-parent-beacon-root header)
        (block-validation-fail "Header is missing parent beacon root"))
      (when (block-header-parent-beacon-root header)
        (block-validation-fail "Parent beacon root present before Cancun")))
  t)

(defun validate-block-withdrawals-field
    (header &key (withdrawals-enabled-p (block-header-withdrawals-root header)))
  (if withdrawals-enabled-p
      (unless (block-header-withdrawals-root header)
        (block-validation-fail "Header is missing withdrawals root"))
      (when (block-header-withdrawals-root header)
        (block-validation-fail "Withdrawals root present before Shanghai")))
  t)

(defun validate-block-requests-hash-field
    (header &key (requests-enabled-p (block-header-requests-hash header)))
  (if requests-enabled-p
      (unless (block-header-requests-hash header)
        (block-validation-fail "Header is missing requests hash"))
      (when (block-header-requests-hash header)
        (block-validation-fail "Requests hash present before Prague")))
  t)

(defun block-header-amsterdam-fields-present-p (header)
  (or (block-header-block-access-list-hash header)
      (block-header-slot-number header)))

(defun validate-block-amsterdam-fields
    (header &key (amsterdam-enabled-p
                  (block-header-amsterdam-fields-present-p header)))
  (if amsterdam-enabled-p
      (progn
        (unless (block-header-block-access-list-hash header)
          (block-validation-fail
           "Header is missing block access list hash"))
        (unless (block-header-slot-number header)
          (block-validation-fail "Header is missing slot number")))
      (progn
        (when (block-header-block-access-list-hash header)
          (block-validation-fail
           "Block access list hash present before Amsterdam"))
        (when (block-header-slot-number header)
          (block-validation-fail "Slot number present before Amsterdam"))))
  t)

(defun validate-block-amsterdam-slot-number (parent-header header)
  (let ((parent-slot-number (block-header-slot-number parent-header))
        (slot-number (block-header-slot-number header)))
    (when (and parent-slot-number
               slot-number
               (<= slot-number parent-slot-number))
      (block-validation-fail
       "Amsterdam header slot number must exceed parent slot number")))
  t)

(defun block-header-post-merge-p (header)
  (and (plusp (block-header-number header))
       (zerop (block-header-difficulty header))))

(defun block-header-zero-nonce-p (header)
  (let ((nonce (block-header-nonce header)))
    (or (null nonce)
        (let ((bytes (ensure-byte-vector nonce)))
          (and (= 8 (length bytes))
               (every #'zerop bytes))))))

(defun validate-block-merge-transition (parent-header header)
  (when (and (block-header-post-merge-p parent-header)
             (plusp (block-header-difficulty header)))
    (block-validation-fail "Cannot revert from post-Merge to PoW difficulty"))
  t)

(defun validate-block-merge-fields
    (header &key (post-merge-p (block-header-post-merge-p header)))
  (when post-merge-p
    (unless (zerop (block-header-difficulty header))
      (block-validation-fail "Post-Merge header difficulty must be zero"))
    (unless (block-header-zero-nonce-p header)
      (block-validation-fail "Post-Merge header nonce must be zero"))
    (unless (hash32= (or (block-header-ommers-hash header) +empty-ommers-hash+)
                     +empty-ommers-hash+)
      (block-validation-fail "Post-Merge header ommers hash must be empty"))
    (when (> (block-header-gas-limit header) +max-header-gas-limit+)
      (block-validation-fail "Post-Merge header gas limit exceeds maximum")))
  t)

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

(defun validate-withdrawal-fields (withdrawal)
  (unless (uint256-p (withdrawal-index withdrawal))
    (block-validation-fail "Withdrawal index must be uint256"))
  (unless (uint256-p (withdrawal-validator-index withdrawal))
    (block-validation-fail "Withdrawal validator index must be uint256"))
  (unless (address-p (withdrawal-address withdrawal))
    (block-validation-fail "Withdrawal address must be an address"))
  (unless (uint256-p (withdrawal-amount withdrawal))
    (block-validation-fail "Withdrawal amount must be uint256"))
  t)

(defun validate-withdrawal-list-fields (withdrawals)
  (unless (listp withdrawals)
    (block-validation-fail "Withdrawals must be a list"))
  (dolist (withdrawal withdrawals t)
    (validate-withdrawal-fields withdrawal)))

(defun transaction-object-p (value)
  (typep value
         '(or legacy-transaction
              access-list-transaction
              dynamic-fee-transaction
              blob-transaction
              set-code-transaction)))

(defun validate-block-transaction-list-fields (transactions)
  (unless (listp transactions)
    (block-validation-fail "Block transactions must be a list"))
  (dolist (transaction transactions t)
    (unless (transaction-object-p transaction)
      (block-validation-fail "Block transaction must be a transaction"))))

(defun validate-block-ommer-list-fields (ommers)
  (unless (listp ommers)
    (block-validation-fail "Block ommers must be a list"))
  (dolist (ommer ommers t)
    (unless (block-header-p ommer)
      (block-validation-fail "Block ommer must be a block header"))))

(defun validate-block-body-commitment-fields (header)
  (unless (hash32-p (block-header-ommers-hash header))
    (block-validation-fail "Header ommers hash must be a hash32"))
  (unless (hash32-p (block-header-transactions-root header))
    (block-validation-fail "Header transactions root must be a hash32"))
  (when (block-header-withdrawals-root header)
    (unless (hash32-p (block-header-withdrawals-root header))
      (block-validation-fail "Header withdrawals root must be a hash32")))
  (when (block-header-requests-hash header)
    (unless (hash32-p (block-header-requests-hash header))
      (block-validation-fail "Header requests hash must be a hash32")))
  (when (block-header-block-access-list-hash header)
    (unless (hash32-p (block-header-block-access-list-hash header))
      (block-validation-fail
       "Header block access list hash must be a hash32")))
  t)

(defun transaction-blob-count (transaction)
  (typecase transaction
    (blob-transaction
     (length (blob-transaction-blob-versioned-hashes transaction)))
    (t 0)))

(defun blob-gas-used (transactions)
  (* +blob-gas-per-blob+
     (loop for transaction in transactions
           sum (transaction-blob-count transaction))))

(defun validate-block-transactions-against-config (block config)
  (let ((header (block-header block)))
    (validate-block-transaction-list-fields (block-transactions block))
    (dolist (transaction (block-transactions block) t)
      (validate-transaction-type-for-config
       transaction config
       (block-header-number header)
       (block-header-timestamp header)))))

(defun validate-block-body-against-config (block config)
  (let* ((header (block-header block))
         (number (block-header-number header))
         (timestamp (block-header-timestamp header))
         (block-access-list-max-code-size
           (if (chain-config-amsterdam-p config number timestamp)
               +block-access-list-amsterdam-max-code-size+
               +block-access-list-max-code-size+)))
    (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
        (chain-config-blob-schedule config number timestamp)
      (declare (ignore target-blob-gas))
      (validate-block-transactions-against-config block config)
      (validate-block-body-roots block
                                 :blob-base-fee-update-fraction
                                 update-fraction
                                 :max-blob-gas max-blob-gas
                                 :block-access-list-max-code-size
                                 block-access-list-max-code-size))))

(defun validate-block-against-config (parent-header block config)
  (validate-block-header-against-config parent-header (block-header block)
                                        config)
  (validate-block-body-against-config block config))

(defun validate-block-body-roots
    (block &key (blob-base-fee-update-fraction
                 +blob-base-fee-update-fraction+)
                (max-blob-gas
                 (* +max-blobs-per-block+ +blob-gas-per-blob+))
                block-access-list-max-code-size)
  (let* ((header (block-header block))
         (ommers (block-ommers block))
         (ommers-root nil)
         (transactions (block-transactions block))
         (transactions-root nil)
         (blob-gas-used nil)
         (base-fee (block-header-base-fee-per-gas header))
         (blob-base-fee (when (block-header-excess-blob-gas header)
                          (block-header-blob-base-fee
                           header
                           :update-fraction
                           blob-base-fee-update-fraction))))
    (validate-block-body-commitment-fields header)
    (validate-block-ommer-list-fields ommers)
    (setf ommers-root (ommers-hash ommers))
    (validate-block-transaction-list-fields transactions)
    (setf blob-gas-used (blob-gas-used transactions))
    (dolist (transaction transactions)
      (validate-transaction-recipient-field transaction)
      (validate-transaction-data-field transaction)
      (validate-transaction-scalar-fields transaction)
      (validate-transaction-signature-fields transaction)
      (validate-access-list-fields transaction)
      (validate-set-code-transaction-fields transaction)
      (when base-fee
        (validate-1559-transaction-fees transaction base-fee))
      (when (typep transaction 'blob-transaction)
        (validate-blob-transaction-fields transaction)
        (when blob-base-fee
          (validate-blob-transaction-fee-cap transaction blob-base-fee))))
    (setf transactions-root (transaction-list-root transactions))
    (when (block-withdrawals-present-p block)
      (validate-withdrawal-list-fields (block-withdrawals block)))
    (when (block-requests-present-p block)
      (validate-execution-request-list-fields (block-requests block)))
    (when (block-block-access-list-present-p block)
      (validated-block-access-list-commitment
       block
       :max-code-size block-access-list-max-code-size
       :max-items (when (plusp (block-header-gas-limit header))
                    (floor (block-header-gas-limit header)
                           +block-access-list-item-gas-cost+))))
    (unless (hash32= ommers-root (block-header-ommers-hash header))
      (block-validation-fail "Ommers root hash mismatch"))
    (when (and (block-header-post-merge-p header)
               ommers)
      (block-validation-fail "Post-Merge blocks cannot contain ommers"))
    (unless (hash32= transactions-root
                     (block-header-transactions-root header))
      (block-validation-fail "Transaction root hash mismatch"))
    (cond
      ((block-header-withdrawals-root header)
       (unless (block-withdrawals-present-p block)
         (block-validation-fail "Missing withdrawals in block body"))
       (unless (hash32= (withdrawal-list-root (block-withdrawals block))
                        (block-header-withdrawals-root header))
         (block-validation-fail "Withdrawals root hash mismatch")))
      ((block-withdrawals-present-p block)
       (block-validation-fail "Withdrawals present before withdrawals root")))
    (cond
      ((block-header-requests-hash header)
       (unless (block-requests-present-p block)
         (block-validation-fail "Missing execution requests in block body"))
       (unless (hash32= (execution-requests-hash (block-requests block))
                        (block-header-requests-hash header))
         (block-validation-fail "Execution requests hash mismatch")))
      ((block-requests-present-p block)
       (block-validation-fail "Execution requests present before requests hash")))
    (cond
      ((block-header-block-access-list-hash header)
       (unless (block-block-access-list-present-p block)
         (block-validation-fail "Missing block access list in block body"))
       (unless (hash32= (validated-block-access-list-commitment
                         block
                         :max-code-size block-access-list-max-code-size
                         :max-items
                         (when (plusp (block-header-gas-limit header))
                           (floor (block-header-gas-limit header)
                                  +block-access-list-item-gas-cost+)))
                        (block-header-block-access-list-hash header))
         (block-validation-fail "Block access list hash mismatch")))
      ((block-block-access-list-present-p block)
       (block-validation-fail
        "Block access list present before block access list hash")))
    (cond
      ((block-header-blob-gas-used header)
       (unless (= blob-gas-used (block-header-blob-gas-used header))
         (block-validation-fail "Blob gas used mismatch")))
      ((plusp blob-gas-used)
       (block-validation-fail "Blob transactions present before blob gas header")))
    (when (> blob-gas-used max-blob-gas)
      (block-validation-fail "Blob gas used exceeds maximum"))
    t))
