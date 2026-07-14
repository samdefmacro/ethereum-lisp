(in-package #:ethereum-lisp.execution-service)

(defconstant +blockhash-history-limit+ 256)

(defun chain-store-block-hashes-for-header (store header)
  "Build HEADER's BLOCKHASH window by following its own parent branch.

Hashes derivable from child headers remain usable when an older ancestor record
is not retained. Entries beyond the first missing ancestor are marked unavailable
so execution only fails if EVM code actually queries unavailable history."
  (let* ((block-hashes (make-hash-table :test 'eql))
         (number (block-header-number header))
         (history-count (min +blockhash-history-limit+ number)))
    (when (plusp number)
      (labels ((mark-unavailable-from (offset)
                 (loop for missing-offset from offset below history-count
                       for missing-number = (- number 1 missing-offset)
                       do (setf (gethash missing-number block-hashes)
                                :unavailable))))
        (let ((expected-hash (block-header-parent-hash header)))
          (if (null expected-hash)
              (mark-unavailable-from 0)
              (dotimes (offset history-count)
                (unless expected-hash
                  (mark-unavailable-from offset)
                  (return))
                (let ((expected-number (- number 1 offset)))
                  (setf (gethash expected-number block-hashes) expected-hash)
                  (when (< (1+ offset) history-count)
                    (let ((ancestor
                            (chain-store-known-block store expected-hash)))
                      (unless ancestor
                        (mark-unavailable-from (1+ offset))
                        (return))
                      (let ((ancestor-header (block-header ancestor)))
                        (unless (= expected-number
                                   (block-header-number ancestor-header))
                          (error 'block-validation-error
                                 :message
                                 "BLOCKHASH ancestor number is inconsistent"))
                        (unless (hash32= expected-hash (block-hash ancestor))
                          (error 'block-validation-error
                                 :message
                                 "BLOCKHASH ancestor hash is inconsistent"))
                        (setf expected-hash
                              (block-header-parent-hash
                               ancestor-header)))))))))))
    block-hashes))

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
    (store state executor
     &key (state-available-p t) (canonicalize-p t))
  (execute-atomic-block-commit
   store
   state
   (lambda ()
     (multiple-value-bind (block receipts)
         (funcall executor)
       (engine-payload-store-put-block
        store block
        :state-available-p state-available-p
        :canonicalize-p canonicalize-p)
       (when state-available-p
         (commit-state-db-to-chain-store store (block-hash block) state))
       (values block receipts)))))

(defun execute-and-commit-signed-block
    (store state transactions
     &key expected-chain-id
          (header (make-block-header))
          chain-rules
          chain-config
          block-hashes
          (apply-block-rewards-p nil)
          (ommers '())
          (withdrawals nil withdrawals-supplied-p)
          (requests nil requests-supplied-p)
          (block-access-list nil block-access-list-supplied-p)
          (block-access-list-rlp nil block-access-list-rlp-supplied-p)
          (state-available-p t)
          (canonicalize-p t))
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
             :block-hashes
             (or block-hashes
                 (chain-store-block-hashes-for-header store header))
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
   :state-available-p state-available-p
   :canonicalize-p canonicalize-p))

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
            :state-available-p state-available-p
            ;; Engine imports are hash-addressed candidates. Consensus selects
            ;; the canonical view later through forkchoiceUpdated.
            :canonicalize-p nil)
      (when (block-withdrawals-present-p block)
        (list :withdrawals (block-withdrawals block)))
      (when (block-requests-present-p block)
        (list :requests (block-requests block)))
      (when (block-block-access-list-present-p block)
        (list :block-access-list (block-block-access-list block)))))))
