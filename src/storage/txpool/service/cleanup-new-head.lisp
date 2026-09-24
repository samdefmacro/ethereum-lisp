(in-package #:ethereum-lisp.txpool)

(defun engine-payload-store-sender-code-invalid-p
    (store head sender sender-code-admissible)
  "True when SENDER has code at HEAD that is not a delegation.
SENDER-CODE-ADMISSIBLE is the pass's sender memo."
  (not (engine-payload-store-sender-memo-value
        sender-code-admissible sender
        (lambda ()
          (engine-payload-store-sender-code-admissible-p
           store
           head
           sender)))))

(defun engine-payload-store-over-gas-limit-txpool-transaction-p
    (head transaction)
  (> (transaction-gas-limit transaction)
     (block-header-gas-limit (block-header head))))

(defun engine-payload-store-remove-invalid-sender-txpool-transactions
    (store &key expected-chain-id)
  (when expected-chain-id
    (engine-payload-store-remove-txpool-transactions-if
     store
     (lambda (transaction)
       (null (transaction-sender
              transaction
              :expected-chain-id expected-chain-id))))))

(defun engine-payload-store-chain-config-expected-chain-id
    (expected-chain-id chain-config)
  (or expected-chain-id
      (and chain-config
           (chain-config-chain-id chain-config))))

(defun engine-payload-store-new-head-invalid-reason
    (store head state-available-p transaction txpool-chain-id
     account-nonces sender-code-admissible)
  "Why TRANSACTION cannot stay pooled under HEAD, or NIL.

The reasons are checked in the order the separate passes used to run: the
sender does not recover for this chain, the nonce is already used, the gas
limit exceeds the head's, the sender has code that is not a delegation. The
first that applies names the removal, as the first pass that removed a
transaction did. None of them depends on the rest of the pool, so one walk
removes what four did."
  (let ((sender (transaction-sender
                 transaction
                 :expected-chain-id txpool-chain-id)))
    (cond
      ((and txpool-chain-id (null sender)) :invalid-sender)
      ((and sender
            state-available-p
            (engine-payload-store-stale-txpool-transaction-p
             store head transaction sender account-nonces))
       :stale)
      ((and head
            (engine-payload-store-over-gas-limit-txpool-transaction-p
             head transaction))
       :over-gas-limit)
      ;; Blob base fee is dynamic.  A transaction that is temporarily below it
      ;; must remain parked so an empty block can lower the fee and make the
      ;; transaction executable again.  Payload construction validates the
      ;; current fee and skips it while it is ineligible; canonical cleanup
      ;; must not turn that temporary condition into permanent eviction.
      ((and sender
            state-available-p
            (engine-payload-store-sender-code-invalid-p
             store head sender sender-code-admissible))
       :sender-code))))

(defun engine-payload-store-remove-new-head-invalid-txpool-transactions
    (store &key expected-chain-id chain-config)
  "Remove every pooled transaction the new head makes invalid, and return them.

One walk over the pool: one sender lookup per transaction, and one head-state
read per sender for each question. This runs inside every forkchoiceUpdated
that moves the head, where four whole-pool passes reading the state once per
transaction made its cost grow with the pool (Hoodi b5161312: fcuCanonicalMs
1.2 s rising to 3.3 s as the pool filled). The result keeps the old order:
the invalid-sender removals, then the stale, the over-gas-limit and the
sender-code ones, each in pool order."
  (let* ((txpool-chain-id
           (engine-payload-store-chain-config-expected-chain-id
            expected-chain-id
            chain-config))
         (head (chain-store-latest-block store))
         (state-available-p
           (and head
                (chain-store-state-available-p store (block-hash head))))
         (account-nonces (make-hash-table :test 'equal))
         (sender-code-admissible (make-hash-table :test 'equal))
         (reasons '(:invalid-sender :stale :over-gas-limit :sender-code))
         (removed (mapcar #'list reasons)))
    (engine-payload-store-remove-txpool-transactions-if
     store
     (lambda (transaction)
       (let ((reason (engine-payload-store-new-head-invalid-reason
                      store head state-available-p transaction
                      txpool-chain-id account-nonces
                      sender-code-admissible)))
         (when reason
           (push transaction (cdr (assoc reason removed)))
           t))))
    (loop for reason in reasons
          nconc (nreverse (cdr (assoc reason removed))))))
