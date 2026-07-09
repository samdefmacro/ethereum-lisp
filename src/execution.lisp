(in-package #:ethereum-lisp.execution)

(defun execute-legacy-block (state sender transactions
                             &key (header (make-block-header))
                                  chain-rules
                                  chain-config
                                  (apply-block-rewards-p nil)
                                  (ommers '())
                                  (withdrawals nil withdrawals-supplied-p)
                                  (requests nil requests-supplied-p)
                                  (block-access-list nil
                                   block-access-list-supplied-p)
                                  (block-access-list-rlp nil
                                   block-access-list-rlp-supplied-p))
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
          (multiple-value-bind (receipts gas-used)
              (apply-message-list
               state sender transactions
               :base-fee (or (block-header-base-fee-per-gas header) 0)
               :blob-base-fee
               (execution-block-blob-base-fee header chain-rules chain-config)
               :chain-rules chain-rules
               :chain-config chain-config
               :coinbase (or (block-header-beneficiary header) (zero-address))
               :timestamp (block-header-timestamp header)
               :block-number (block-header-number header)
               :prev-randao (or (block-header-mix-hash header) (zero-hash32))
               :difficulty (block-header-difficulty header)
               :random-p (block-header-post-merge-p header)
               :context-gas-limit (block-header-gas-limit header)
               :block-gas-limit
               (when (plusp (block-header-gas-limit header))
                 (block-header-gas-limit header)))
            (when withdrawals-supplied-p
              (apply-withdrawals state withdrawals))
            (when apply-block-rewards-p
              (let ((rules (execution-chain-rules chain-rules chain-config
                                                  (block-header-number header)
                                                  (block-header-timestamp
                                                   header))))
                (apply-block-rewards-for-header state header ommers rules)))
            (when (or (plusp actual-blob-gas-used)
                      (block-header-blob-gas-used header)
                      (block-header-excess-blob-gas header))
              (setf (block-header-blob-gas-used header) actual-blob-gas-used)
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
                                  (list :block-access-list block-access-list)))))
             receipts))
        (error (condition)
          (state-db-restore state snapshot)
          (restore-block-header-for-execution header header-snapshot)
          (error condition)))))))

(defun execute-and-commit-signed-block
    (store state transactions
     &key expected-chain-id
          (header (make-block-header))
          chain-rules
          chain-config
          (apply-block-rewards-p nil)
          (ommers '())
          (withdrawals nil withdrawals-supplied-p)
          (requests nil requests-supplied-p)
          (block-access-list nil block-access-list-supplied-p)
          (block-access-list-rlp nil block-access-list-rlp-supplied-p)
          (state-available-p t))
  (execute-and-commit-block
   store
   state
   (lambda ()
     (apply
      #'execute-signed-block
      state
      transactions
      (append
       (list :expected-chain-id expected-chain-id
             :header header
             :chain-rules chain-rules
             :chain-config chain-config
             :apply-block-rewards-p apply-block-rewards-p
             :ommers ommers)
       (when withdrawals-supplied-p
         (list :withdrawals withdrawals))
       (when requests-supplied-p
         (list :requests requests))
       (when block-access-list-supplied-p
         (list :block-access-list block-access-list))
       (when block-access-list-rlp-supplied-p
         (list :block-access-list-rlp block-access-list-rlp)))))
   :state-available-p state-available-p))

(defun execute-atomic-block-commit (store state thunk)
  (let ((state-snapshot (state-db-copy state)))
    (chain-store-atomic-commit
     store
     (lambda ()
       (handler-case
           (funcall thunk)
         (error (condition)
           (state-db-restore state state-snapshot)
           (error condition)))))))

(defun commit-state-db-to-chain-store (store block-hash state)
  (state-db-for-each-account
   state
   (lambda (address account code storage-entries)
     (chain-store-put-account-balance
      store block-hash address (state-account-balance account))
     (chain-store-put-account-nonce
      store block-hash address (state-account-nonce account))
     (chain-store-put-account-code store block-hash address code)
     (dolist (entry storage-entries)
        (chain-store-put-account-storage
         store block-hash address (car entry) (cdr entry)))))
  store)

(defun chain-store-state-db (store block-hash)
  (when (chain-store-state-available-p store block-hash)
    (let ((state (make-state-db)))
      (chain-store-for-each-account
       store
       block-hash
       (lambda (address balance nonce code storage-entries)
         (state-db-set-account
          state address
          (make-state-account :nonce nonce :balance balance))
         (when (plusp (length code))
           (state-db-set-code state address code))
         (dolist (entry storage-entries)
           (state-db-set-storage state address (car entry) (cdr entry)))))
      state)))

(defun execute-and-commit-engine-payload
    (store block config &key (state-available-p t))
  (let* ((header (block-header block))
         (number (block-header-number header))
         (parent-hash (block-header-parent-hash header))
         (state (if (plusp number)
                    (chain-store-state-db store parent-hash)
                    (make-state-db))))
    (unless state
      (error 'block-validation-error
             :message "Engine payload parent state is unavailable"))
    (apply
     #'execute-and-commit-signed-block
     store
     state
     (block-transactions block)
     (append
      (list :expected-chain-id (chain-config-chain-id config)
            :header header
            :chain-config config
            :ommers (block-ommers block)
            :state-available-p state-available-p)
      (when (block-withdrawals-present-p block)
        (list :withdrawals (block-withdrawals block)))
      (when (block-requests-present-p block)
        (list :requests (block-requests block)))
      (when (block-block-access-list-present-p block)
        (list :block-access-list (block-block-access-list block)))))))

(defun execute-and-commit-block
    (store state executor &key (state-available-p t))
  (execute-atomic-block-commit
   store
   state
   (lambda ()
     (multiple-value-bind (block receipts)
         (funcall executor)
       (chain-store-put-block store block
                              :state-available-p state-available-p)
       (when state-available-p
         (commit-state-db-to-chain-store store (block-hash block) state))
       (values block receipts)))))

(defun execute-signed-block (state transactions
                             &key expected-chain-id
                                  (header (make-block-header))
                                  chain-rules
                                  chain-config
                                  (apply-block-rewards-p nil)
                                  (ommers '())
                                  (withdrawals nil withdrawals-supplied-p)
                                  (requests nil requests-supplied-p)
                                  (block-access-list nil
                                   block-access-list-supplied-p)
                                  (block-access-list-rlp nil
                                   block-access-list-rlp-supplied-p))
  "Execute a block by recovering each transaction sender from its signature."
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
          (multiple-value-bind (receipts gas-used)
              (apply-signed-message-list
               state transactions
               :expected-chain-id expected-chain-id
               :base-fee (or (block-header-base-fee-per-gas header) 0)
               :blob-base-fee
               (execution-block-blob-base-fee header chain-rules chain-config)
               :chain-rules chain-rules
               :chain-config chain-config
               :coinbase (or (block-header-beneficiary header) (zero-address))
               :timestamp (block-header-timestamp header)
               :block-number (block-header-number header)
               :prev-randao (or (block-header-mix-hash header) (zero-hash32))
               :difficulty (block-header-difficulty header)
               :random-p (block-header-post-merge-p header)
               :context-gas-limit (block-header-gas-limit header)
               :block-gas-limit
               (when (plusp (block-header-gas-limit header))
                 (block-header-gas-limit header)))
            (when withdrawals-supplied-p
              (apply-withdrawals state withdrawals))
            (when apply-block-rewards-p
              (let ((rules (execution-chain-rules chain-rules chain-config
                                                  (block-header-number header)
                                                  (block-header-timestamp
                                                   header))))
                (apply-block-rewards-for-header state header ommers rules)))
            (when (or (plusp actual-blob-gas-used)
                      (block-header-blob-gas-used header)
                      (block-header-excess-blob-gas header))
              (setf (block-header-blob-gas-used header) actual-blob-gas-used)
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
                                  (list :block-access-list block-access-list)))))
             receipts))
        (error (condition)
          (state-db-restore state snapshot)
          (restore-block-header-for-execution header header-snapshot)
          (error condition)))))))
