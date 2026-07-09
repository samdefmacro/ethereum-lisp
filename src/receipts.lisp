(in-package #:ethereum-lisp.core)

;;; Withdrawals, logs, bloom filters, receipts, and trie-list roots.

(defstruct (withdrawal (:constructor make-withdrawal
                         (&key (index 0)
                               (validator-index 0)
                               (address (zero-address))
                               (amount 0))))
  (index 0 :type (integer 0 *))
  (validator-index 0 :type (integer 0 *))
  address
  (amount 0 :type (integer 0 *)))

(defun withdrawal-rlp-object (withdrawal)
  (make-rlp-list
   (ensure-uint256 (withdrawal-index withdrawal) "Withdrawal index")
   (ensure-uint256 (withdrawal-validator-index withdrawal)
                   "Withdrawal validator index")
   (address-bytes (withdrawal-address withdrawal))
   (ensure-uint256 (withdrawal-amount withdrawal) "Withdrawal amount")))

(defun withdrawal-rlp (withdrawal)
  (rlp-encode (withdrawal-rlp-object withdrawal)))

(defstruct (log-entry (:constructor make-log-entry
                         (&key (address (zero-address))
                               (topics '())
                               (data #()))))
  address
  (topics '() :type list)
  data)

(defun topic-bytes (topic)
  (etypecase topic
    (hash32 (hash32-bytes topic))
    (byte-vector (optional-bytes topic 32 "Log topic"))
    (vector (optional-bytes topic 32 "Log topic"))))

(defun log-entry-rlp-object (log)
  (make-rlp-list
   (address-bytes (log-entry-address log))
   (mapcar #'topic-bytes (log-entry-topics log))
   (ensure-byte-vector (log-entry-data log))))

(defstruct (bloom (:constructor %make-bloom (bytes)))
  (bytes (make-byte-vector 256) :type byte-vector))

(defun make-bloom (&optional bytes)
  (%make-bloom (if bytes
                   (optional-bytes bytes 256 "Bloom")
                   (make-byte-vector 256))))

(defun bloom-values (data)
  (let ((hash (keccak-256 data)))
    (labels ((bit-index (offset)
               (logand #x7ff
                       (logior (ash (aref hash offset) 8)
                               (aref hash (1+ offset)))))
             (byte-index (bit-index)
               (- 256 (ash bit-index -3) 1))
             (byte-value (offset)
               (ash 1 (logand (aref hash (1+ offset)) #x7))))
      (list (byte-index (bit-index 0)) (byte-value 0)
            (byte-index (bit-index 2)) (byte-value 2)
            (byte-index (bit-index 4)) (byte-value 4)))))

(defun bloom-add (bloom data)
  (destructuring-bind (i1 v1 i2 v2 i3 v3) (bloom-values data)
    (let ((bytes (bloom-bytes bloom)))
      (setf (aref bytes i1) (logior (aref bytes i1) v1)
            (aref bytes i2) (logior (aref bytes i2) v2)
            (aref bytes i3) (logior (aref bytes i3) v3))))
  bloom)

(defun bloom-contains-p (bloom data)
  (destructuring-bind (i1 v1 i2 v2 i3 v3) (bloom-values data)
    (let ((bytes (bloom-bytes bloom)))
      (and (= v1 (logand v1 (aref bytes i1)))
           (= v2 (logand v2 (aref bytes i2)))
           (= v3 (logand v3 (aref bytes i3)))))))

(defun receipt-bloom (logs)
  (let ((bloom (make-bloom)))
    (dolist (log logs bloom)
      (bloom-add bloom (address-bytes (log-entry-address log)))
      (dolist (topic (log-entry-topics log))
        (bloom-add bloom (topic-bytes topic))))))

(defstruct (receipt (:constructor make-receipt
                       (&key post-state
                             (status 1)
                             (cumulative-gas-used 0)
                             (logs '()))))
  post-state
  (status 1 :type (integer 0 1))
  (cumulative-gas-used 0 :type (integer 0 *))
  (logs '() :type list))

(defun receipt-status-bytes (receipt)
  (if (receipt-post-state receipt)
      (ensure-byte-vector (receipt-post-state receipt))
      (if (= (receipt-status receipt) 1)
          (ensure-byte-vector #(1))
          (make-byte-vector 0))))

(defun receipt-rlp-object (receipt)
  (let ((logs (receipt-logs receipt)))
    (make-rlp-list
     (receipt-status-bytes receipt)
     (ensure-uint256 (receipt-cumulative-gas-used receipt)
                     "Receipt cumulative gas used")
     (bloom-bytes (receipt-bloom logs))
     (mapcar #'log-entry-rlp-object logs))))

(defun receipt-rlp (receipt)
  (rlp-encode (receipt-rlp-object receipt)))

(defun transaction-receipt-encoding (transaction receipt)
  (let ((type (transaction-type transaction))
        (receipt-rlp (receipt-rlp receipt)))
    (if (zerop type)
        receipt-rlp
        (concat-bytes (vector type) receipt-rlp))))

(defun derive-list-root (encoded-items)
  (let ((trie (make-mpt)))
    (loop for item in encoded-items
          for index from 0
          do (mpt-put trie (rlp-encode index) item))
    (make-hash32 (mpt-root-hash trie))))

(defun transaction-list-root (transactions)
  (derive-list-root (mapcar #'transaction-encoding transactions)))

(defun receipt-list-root (receipts)
  (derive-list-root (mapcar #'receipt-rlp receipts)))

(defun transaction-receipt-list-root (transactions receipts)
  (unless (= (length transactions) (length receipts))
    (block-validation-fail "Transaction and receipt count mismatch"))
  (derive-list-root
   (mapcar #'transaction-receipt-encoding transactions receipts)))

(defun withdrawal-list-root (withdrawals)
  (derive-list-root (mapcar #'withdrawal-rlp withdrawals)))
