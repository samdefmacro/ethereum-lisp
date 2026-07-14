(in-package #:ethereum-lisp.execution)

(defun execution-block-hashes-for-header (header block-hashes)
  (unless (hash-table-p block-hashes)
    (error 'block-validation-error
           :message "Block hash history must be a hash table"))
  (let ((number (block-header-number header))
        (parent-hash (block-header-parent-hash header)))
    (loop for ancestor-number from (max 0 (- number 256)) below (1- number)
          do (multiple-value-bind (hash present-p)
                 (gethash ancestor-number block-hashes)
               (unless (and present-p hash)
                 (setf (gethash ancestor-number block-hashes)
                       :unavailable))))
    (when (plusp number)
      (if parent-hash
          (multiple-value-bind (known-parent present-p)
              (gethash (1- number) block-hashes)
            (when (and present-p
                       (not (eq known-parent :unavailable))
                       (not (hash32= known-parent parent-hash)))
              (error 'block-validation-error
                     :message
                     "Block hash history conflicts with header parent"))
            (setf (gethash (1- number) block-hashes) parent-hash))
          (setf (gethash (1- number) block-hashes) :unavailable))))
  block-hashes)

(defun execute-block-with-message-applier
    (state transactions apply-transactions
     &key (header (make-block-header))
          chain-rules
          chain-config
          (block-hashes (make-hash-table))
          (apply-block-rewards-p nil)
          (ommers '())
          (withdrawals nil)
          (withdrawals-supplied-p nil)
          (requests nil)
          (requests-supplied-p nil)
          (block-access-list nil)
          (block-access-list-supplied-p nil)
          (block-access-list-rlp nil)
          (block-access-list-rlp-supplied-p nil))
  (multiple-value-bind (block-access-list block-access-list-supplied-p
                        encoded-block-access-list)
      (normalize-execution-block-access-list-input
       block-access-list block-access-list-supplied-p
       block-access-list-rlp block-access-list-rlp-supplied-p)
    (let* ((max-blob-gas
             (execution-max-blob-gas chain-rules
                                     chain-config
                                     (block-header-number header)
                                     (block-header-timestamp header)))
           (effective-chain-rules
             (execution-chain-rules chain-rules
                                    chain-config
                                    (block-header-number header)
                                    (block-header-timestamp header)))
           (block-blob-base-fee
             (execution-block-blob-base-fee header chain-rules chain-config))
           (block-hashes
             (execution-block-hashes-for-header header block-hashes))
           (block-access-list-max-code-size
             (execution-block-access-list-max-code-size
              chain-rules
              chain-config
              (block-header-number header)
              (block-header-timestamp header)))
           (actual-blob-gas-used
            (validate-block-body-commitments-before-execution
             transactions header
             :ommers ommers
             :withdrawals withdrawals
             :withdrawals-supplied-p withdrawals-supplied-p
             :requests requests
             :requests-supplied-p requests-supplied-p
             :block-access-list block-access-list
             :block-access-list-supplied-p block-access-list-supplied-p
             :encoded-block-access-list encoded-block-access-list
             :max-blob-gas max-blob-gas
             :block-access-list-max-code-size
             block-access-list-max-code-size)))
    (validate-block-fork-body-shape-before-execution
     header chain-config
     :withdrawals-supplied-p withdrawals-supplied-p
     :requests-supplied-p requests-supplied-p
     :block-access-list-supplied-p block-access-list-supplied-p
     :max-blob-gas max-blob-gas)
    (let ((snapshot (state-db-copy state))
          (header-snapshot (copy-block-header-for-execution header)))
      (handler-case
          (progn
            (process-parent-beacon-block-root
             state header effective-chain-rules
             :blob-base-fee block-blob-base-fee
             :block-hashes block-hashes)
            (process-parent-block-hash-history
             state header effective-chain-rules
             :blob-base-fee block-blob-base-fee
             :block-hashes block-hashes)
            (multiple-value-bind (receipts gas-used)
                (funcall
                 apply-transactions
                 state
                 transactions
                 :base-fee (or (block-header-base-fee-per-gas header) 0)
                 :blob-base-fee block-blob-base-fee
                 :chain-rules effective-chain-rules
                 :chain-config chain-config
                 :coinbase (or (block-header-beneficiary header) (zero-address))
                 :timestamp (block-header-timestamp header)
                 :block-number (block-header-number header)
                 :prev-randao (or (block-header-mix-hash header) (zero-hash32))
                 :difficulty (block-header-difficulty header)
                 :random-p (block-header-post-merge-p header)
                 :context-gas-limit (block-header-gas-limit header)
                 :block-hashes block-hashes
                 :block-gas-limit
                 (when (plusp (block-header-gas-limit header))
                   (block-header-gas-limit header)))
              (when withdrawals-supplied-p
                (apply-withdrawals state withdrawals))
              (when apply-block-rewards-p
                (apply-block-rewards-for-header
                 state header ommers effective-chain-rules))
              (when (or (plusp actual-blob-gas-used)
                        (block-header-blob-gas-used header)
                        (block-header-excess-blob-gas header))
                (setf (block-header-blob-gas-used header)
                      actual-blob-gas-used)
                (unless (block-header-excess-blob-gas header)
                  (setf (block-header-excess-blob-gas header) 0)))
              (validate-supplied-block-execution-roots
               header transactions receipts (state-db-root state))
              (setf (block-header-state-root header) (state-db-root state)
                    (block-header-gas-used header) gas-used)
              (values
               (apply #'make-block
                      (append (list :header header
                                    :transactions transactions
                                    :ommers ommers
                                    :receipts receipts)
                              (when withdrawals-supplied-p
                                (list :withdrawals withdrawals))
                              (when requests-supplied-p
                                (list :requests requests))
                              (when block-access-list-supplied-p
                                (if encoded-block-access-list
                                    (list :block-access-list-rlp
                                          encoded-block-access-list)
                                    (list :block-access-list
                                          block-access-list)))))
               receipts)))
        (error (condition)
          (state-db-restore state snapshot)
          (restore-block-header-for-execution header header-snapshot)
          (error condition)))))))

(defun execute-legacy-block (state sender transactions
                             &key (header (make-block-header))
                                  chain-rules
                                  chain-config
                                  (block-hashes (make-hash-table))
                                  (apply-block-rewards-p nil)
                                  (ommers '())
                                  (withdrawals nil withdrawals-supplied-p)
                                  (requests nil requests-supplied-p)
                                  (block-access-list nil
                                   block-access-list-supplied-p)
                                  (block-access-list-rlp nil
                                   block-access-list-rlp-supplied-p))
  (execute-block-with-message-applier
   state
   transactions
   (lambda (state transactions &rest options)
     (apply #'apply-message-list state sender transactions options))
   :header header
   :chain-rules chain-rules
   :chain-config chain-config
   :block-hashes block-hashes
   :apply-block-rewards-p apply-block-rewards-p
   :ommers ommers
   :withdrawals withdrawals
   :withdrawals-supplied-p withdrawals-supplied-p
   :requests requests
   :requests-supplied-p requests-supplied-p
   :block-access-list block-access-list
   :block-access-list-supplied-p block-access-list-supplied-p
   :block-access-list-rlp block-access-list-rlp
   :block-access-list-rlp-supplied-p block-access-list-rlp-supplied-p))

(defun execute-signed-block (state transactions
                             &key expected-chain-id
                                  (header (make-block-header))
                                  chain-rules
                                  chain-config
                                  (block-hashes (make-hash-table))
                                  (apply-block-rewards-p nil)
                                  (ommers '())
                                  (withdrawals nil withdrawals-supplied-p)
                                  (requests nil requests-supplied-p)
                                  (block-access-list nil
                                   block-access-list-supplied-p)
                                  (block-access-list-rlp nil
                                   block-access-list-rlp-supplied-p))
  "Execute a block by recovering each transaction sender from its signature."
  (execute-block-with-message-applier
   state
   transactions
   (lambda (state transactions &rest options)
     (apply #'apply-signed-message-list
            state transactions :expected-chain-id expected-chain-id options))
   :header header
   :chain-rules chain-rules
   :chain-config chain-config
   :block-hashes block-hashes
   :apply-block-rewards-p apply-block-rewards-p
   :ommers ommers
   :withdrawals withdrawals
   :withdrawals-supplied-p withdrawals-supplied-p
   :requests requests
   :requests-supplied-p requests-supplied-p
   :block-access-list block-access-list
   :block-access-list-supplied-p block-access-list-supplied-p
   :block-access-list-rlp block-access-list-rlp
   :block-access-list-rlp-supplied-p block-access-list-rlp-supplied-p))
