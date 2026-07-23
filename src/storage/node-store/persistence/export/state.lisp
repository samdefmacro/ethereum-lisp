(in-package #:ethereum-lisp.node-store.persistence)

(defun state-storage-entry-rlp-object (entry)
  (make-rlp-list
   (hash32-bytes (car entry))
   (cdr entry)))

(defun state-account-snapshot-rlp-object
    (address balance nonce code storage-entries)
  (make-rlp-list
   (address-bytes address)
   balance
   nonce
   code
   (apply #'make-rlp-list
          (mapcar #'state-storage-entry-rlp-object storage-entries))))

(defun chain-store-state-record-rlp (store block-hash)
  (let ((accounts '()))
    (chain-store-for-each-account
     store
     block-hash
     (lambda (address balance nonce code storage-entries)
       (push
        (state-account-snapshot-rlp-object
         address balance nonce code storage-entries)
        accounts)))
    (rlp-encode (apply #'make-rlp-list (nreverse accounts)))))

(defun chain-store-export-state-record-to-kv
    (store batch block-key)
  (let ((block-hash (hash32-from-hex block-key)))
    (kv-batch-put-chain-record
     batch
     :state
     (hash32-bytes block-hash)
     (chain-store-state-record-rlp store block-hash))))

(defun chain-store-state-record-kind (store block-key)
  "Return :BASELINE, :DIFF, or NIL for BLOCK-KEY. Legacy stores marked
availability with T, which denotes a baseline."
  (let ((kind (gethash block-key
                       (memory-chain-store-state-blocks store))))
    (case kind
      ((:baseline :diff nil) kind)
      (t :baseline))))

(defun state-diff-field-rlp (value empty)
  "Encode one diff field as (VALUES TAG VALUE): 0 carries no change, 1 a new
value, 2 an account tombstone."
  (cond
    ((null value) (values 0 empty))
    ((eq value :absent) (values 2 empty))
    (t (values 1 value))))

(defun state-diff-account-rlp-object (address-hex diff)
  (let ((address (address-from-hex address-hex))
        (account-prefix (format nil "~A:" address-hex))
        (storage-entries '()))
    (maphash
     (lambda (suffix value)
       (when (and (<= (length account-prefix) (length suffix))
                  (string= account-prefix suffix
                           :end2 (length account-prefix)))
         (push (cons (subseq suffix (length account-prefix)) value)
               storage-entries)))
     (chain-state-diff-storage diff))
    (multiple-value-bind (balance-tag balance)
        (state-diff-field-rlp
         (gethash address-hex (chain-state-diff-balances diff)) 0)
      (multiple-value-bind (nonce-tag nonce)
          (state-diff-field-rlp
           (gethash address-hex (chain-state-diff-nonces diff)) 0)
        (multiple-value-bind (code-tag code)
            (state-diff-field-rlp
             (gethash address-hex (chain-state-diff-codes diff))
             (make-byte-vector 0))
          (make-rlp-list
           (address-bytes address)
           balance-tag balance
           nonce-tag nonce
           code-tag code
           (apply #'make-rlp-list
                  (mapcar
                   (lambda (entry)
                     (make-rlp-list
                      (hash32-bytes (hash32-from-hex (car entry)))
                      (cdr entry)))
                   (sort storage-entries #'string< :key #'car)))))))))

(defun state-diff-addresses (diff)
  (let ((addresses (make-hash-table :test 'equal)))
    (flet ((remember (table)
             (maphash (lambda (suffix value)
                        (declare (ignore value))
                        (setf (gethash suffix addresses) t))
                      table)))
      (remember (chain-state-diff-balances diff))
      (remember (chain-state-diff-nonces diff))
      (remember (chain-state-diff-codes diff)))
    (maphash (lambda (suffix value)
               (declare (ignore value))
               (let ((separator (position #\: suffix)))
                 (when separator
                   (setf (gethash (subseq suffix 0 separator) addresses)
                         t))))
             (chain-state-diff-storage diff))
    (sort (loop for address being the hash-keys of addresses
                collect address)
          #'string<)))

(defun chain-store-state-diff-record-rlp (store block-key)
  (let ((diff (gethash block-key
                       (memory-chain-store-state-diffs store))))
    (unless diff
      (block-validation-fail
       "State diff block ~A has no diff to export" block-key))
    (rlp-encode
     (make-rlp-list
      (hash32-bytes (hash32-from-hex (chain-state-diff-parent-key diff)))
      (apply #'make-rlp-list
             (mapcar
              (lambda (address-hex)
                (state-diff-account-rlp-object address-hex diff))
              (state-diff-addresses diff)))))))

(defun chain-store-export-state-diff-record-to-kv
    (store batch block-key)
  (kv-batch-put-chain-record
   batch
   :state-diff
   (hash32-bytes (hash32-from-hex block-key))
   (chain-store-state-diff-record-rlp store block-key)))

(defun chain-store-populate-state-record-export-batch
    (store database batch)
  (setf store (chain-store-require-memory-store store))
  (dolist (entry (kv-chain-record-entries database :state))
    (unless (eq :baseline
                (chain-store-state-record-kind
                 store (bytes-to-hex (car entry))))
      (kv-batch-delete-chain-record batch :state (car entry))))
  (dolist (entry (kv-chain-record-entries database :state-diff))
    (unless (eq :diff
                (chain-store-state-record-kind
                 store (bytes-to-hex (car entry))))
      (kv-batch-delete-chain-record batch :state-diff (car entry))))
  (maphash
   (lambda (block-key state-available-p)
     (when state-available-p
       (ecase (chain-store-state-record-kind store block-key)
         (:baseline
          (chain-store-export-state-record-to-kv store batch block-key))
         (:diff
          (chain-store-export-state-diff-record-to-kv
           store batch block-key)))))
   (memory-chain-store-state-blocks store)))

(defun chain-store-export-state-records-to-kv (store database)
  (chain-store-apply-export-batch
   store database "state record"
   #'chain-store-populate-state-record-export-batch))
