(in-package #:ethereum-lisp.execution)

;;;; Prague execution requests derived from transaction logs and system queues.

(defparameter +withdrawal-request-predeploy-address+
  (address-from-hex "0x00000961ef480eb55e80d19ad83579a64c007002"))

(defparameter +consolidation-request-predeploy-address+
  (address-from-hex "0x0000bbddc7ce488642fb579f8b00f3a590007251"))

(defparameter +deposit-event-signature-hash+
  (hash32-from-hex
   "0x649bbc62d0e31342afea4e5cd82d4049e7e1ee912fc0889aa790803be39038c5"))

(defconstant +deposit-request-type+ #x00)
(defconstant +withdrawal-request-type+ #x01)
(defconstant +consolidation-request-type+ #x02)

(defconstant +deposit-event-data-length+ 576)
(defconstant +deposit-pubkey-offset+ 160)
(defconstant +deposit-withdrawal-credentials-offset+ 256)
(defconstant +deposit-amount-offset+ 320)
(defconstant +deposit-signature-offset+ 384)
(defconstant +deposit-index-offset+ 512)

(defun prague-execution-requests-active-p (header chain-rules)
  (if chain-rules
      (chain-rules-prague-p chain-rules)
      (not (null (block-header-requests-hash header)))))

(defun deposit-event-word (data offset)
  (bytes-to-integer (subseq data offset (+ offset 32))))

(defun validate-deposit-event-field (data offset size label)
  (unless (= size (deposit-event-word data offset))
    (block-validation-fail "Invalid deposit event ~A size" label))
  (subseq data (+ offset 32) (+ offset 32 size)))

(defun extract-deposit-request-data (data)
  "Decode one EIP-6110 DepositEvent payload into its 192-byte request data."
  (let ((data
          (handler-case
              (ensure-byte-vector data)
            (error ()
              (block-validation-fail
               "Deposit event data must be a byte vector")))))
    (unless (= +deposit-event-data-length+ (length data))
      (block-validation-fail "Invalid deposit event data length"))
    (loop for (offset expected label)
            in `((0 ,+deposit-pubkey-offset+ "pubkey")
                 (32 ,+deposit-withdrawal-credentials-offset+
                     "withdrawal credentials")
                 (64 ,+deposit-amount-offset+ "amount")
                 (96 ,+deposit-signature-offset+ "signature")
                 (128 ,+deposit-index-offset+ "index"))
          unless (= expected (deposit-event-word data offset))
            do (block-validation-fail
                "Invalid deposit event ~A offset" label))
    (concat-bytes
     (validate-deposit-event-field
      data +deposit-pubkey-offset+ 48 "pubkey")
     (validate-deposit-event-field
      data +deposit-withdrawal-credentials-offset+ 32
      "withdrawal credentials")
     (validate-deposit-event-field
      data +deposit-amount-offset+ 8 "amount")
     (validate-deposit-event-field
      data +deposit-signature-offset+ 96 "signature")
     (validate-deposit-event-field
      data +deposit-index-offset+ 8 "index"))))

(defun deposit-request-log-p (log deposit-contract-address)
  (let ((topics (log-entry-topics log)))
    (and deposit-contract-address
         (bytes= (address-bytes (log-entry-address log))
                 (address-bytes deposit-contract-address))
         topics
         (bytes= (topic-bytes (first topics))
                 (hash32-bytes +deposit-event-signature-hash+)))))

(defun deposit-request-data-from-receipts
    (receipts deposit-contract-address)
  (let ((requests '()))
    (dolist (receipt receipts)
      (dolist (log (receipt-logs receipt))
        (when (deposit-request-log-p log deposit-contract-address)
          (push (extract-deposit-request-data (log-entry-data log))
                requests))))
    (apply #'concat-bytes (nreverse requests))))

(defun checked-request-system-call-data
    (state target header chain-rules blob-base-fee block-hashes)
  (let ((result
          (execute-protocol-system-call
           state target #() header chain-rules
           :blob-base-fee blob-base-fee
           :block-hashes block-hashes
           :require-code-p t
           :require-success-p t)))
    (copy-seq (evm-result-return-data result))))

(defun derive-prague-execution-requests
    (state receipts header chain-rules chain-config
     &key (blob-base-fee 0) (block-hashes (make-hash-table)))
  "Execute Prague post-block transitions and return requests plus active flag."
  (unless (prague-execution-requests-active-p header chain-rules)
    (return-from derive-prague-execution-requests (values nil nil)))
  (let ((requests '())
        (deposit-data
          (deposit-request-data-from-receipts
           receipts
           (when chain-config
             (chain-config-deposit-contract-address chain-config)))))
    (when (plusp (length deposit-data))
      (push (concat-bytes (vector +deposit-request-type+) deposit-data)
            requests))
    (let ((withdrawal-data
            (checked-request-system-call-data
             state +withdrawal-request-predeploy-address+
             header chain-rules blob-base-fee block-hashes)))
      (when (plusp (length withdrawal-data))
        (push (concat-bytes (vector +withdrawal-request-type+)
                            withdrawal-data)
              requests)))
    (let ((consolidation-data
            (checked-request-system-call-data
             state +consolidation-request-predeploy-address+
             header chain-rules blob-base-fee block-hashes)))
      (when (plusp (length consolidation-data))
        (push (concat-bytes (vector +consolidation-request-type+)
                            consolidation-data)
              requests)))
    (values (nreverse requests) t)))

(defun validate-derived-execution-requests (header requests)
  (let ((expected-hash (block-header-requests-hash header))
        (actual-hash (execution-requests-hash requests)))
    (when (and expected-hash (not (hash32= expected-hash actual-hash)))
      (block-validation-fail
       "Execution requests do not match block execution")))
  t)
