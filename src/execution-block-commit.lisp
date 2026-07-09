(in-package #:ethereum-lisp.execution)

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
