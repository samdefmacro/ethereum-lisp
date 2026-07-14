(in-package #:ethereum-lisp.test)

(defparameter +payload-candidate-export-record-kinds+
  '(:block :header :receipt :state
    :canonical-hash :transaction-location :checkpoint :txpool))

(defun payload-candidate-export-fixture
    (&key (candidate-state-available-p t)
          (store-genesis-p t)
          (store-parent-p t))
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex
            "0x00000000000000000000000000000000000000aa"))
         (transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 2
             :gas-limit 21000
             :to recipient
             :value 3)
            1
            1))
         (receipt
           (make-receipt :status 1 :cumulative-gas-used 21000))
         (genesis
           (make-block
            :header
            (make-block-header
             :number 0
             :parent-hash (zero-hash32)
             :timestamp 1
             :gas-limit 30000000)))
         (parent
           (make-block
            :header
            (make-block-header
             :number 1
             :parent-hash (block-hash genesis)
             :timestamp 2
             :gas-limit 30000000)))
         (candidate
           (make-block
            :header
            (make-block-header
             :number 2
             :parent-hash (block-hash parent)
             :timestamp 3
             :gas-limit 30000000)
            :transactions (list transaction)
            :receipts (list receipt))))
    (when store-genesis-p
      (chain-store-put-block store genesis :state-available-p t)
      (chain-store-put-account-balance
       store (block-hash genesis) recipient 11))
    (when store-parent-p
      (chain-store-put-block store parent :state-available-p t)
      (chain-store-put-account-balance
       store (block-hash parent) recipient 22))
    (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
     store transaction)
    (engine-payload-store-put-block
     store candidate
     :state-available-p candidate-state-available-p
     :canonicalize-p nil)
    (when candidate-state-available-p
      (chain-store-put-account-balance
       store (block-hash candidate) recipient 33))
    (values store genesis parent candidate transaction recipient)))

(defun payload-candidate-export-expected-receipt-record (block)
  (rlp-encode
   (apply #'make-rlp-list
          (loop for transaction in (block-transactions block)
                for receipt in (ethereum-lisp.blocks:block-receipts block)
                collect
                (transaction-receipt-encoding transaction receipt)))))

(defun payload-candidate-export-assert-record
    (database kind identifier expected)
  (multiple-value-bind (value present-p)
      (kv-get-chain-record database kind identifier)
    (is present-p)
    (is (bytes= expected value))))

(defun payload-candidate-export-database-snapshot (database)
  (loop for kind in +payload-candidate-export-record-kinds+
        collect
        (cons kind
              (loop for entry in (kv-chain-record-entries database kind)
                    collect
                    (cons (copy-seq (car entry))
                          (copy-seq (cdr entry)))))))

(deftest node-store-payload-candidate-export-persists-only-candidate-records
  (multiple-value-bind
      (store genesis parent candidate transaction recipient)
      (payload-candidate-export-fixture)
    (declare (ignore recipient))
    (let ((database (make-memory-key-value-database)))
      (is (null (chain-store-canonical-hash store 2)))
      (is (null (chain-store-transaction-location
                 store (transaction-hash transaction))))
      (is (eq database
              (node-store-export-payload-candidate-to-kv
               store candidate database)))
      (dolist (block (list genesis parent candidate))
        (let ((identifier (hash32-bytes (block-hash block))))
          (payload-candidate-export-assert-record
           database :block identifier (block-rlp block))
          (payload-candidate-export-assert-record
           database :header identifier
           (block-header-rlp (block-header block)))
          (payload-candidate-export-assert-record
           database :receipt identifier
           (payload-candidate-export-expected-receipt-record block))))
      (let ((candidate-id (hash32-bytes (block-hash candidate))))
        (multiple-value-bind (state-record present-p)
            (kv-get-chain-record database :state candidate-id)
          (is present-p)
          (is (plusp (length state-record))))
        (multiple-value-bind (value present-p)
            (kv-get-chain-canonical-hash database 2 :missing)
          (is (eq :missing value))
          (is (not present-p)))
        (multiple-value-bind (value present-p)
            (kv-get-chain-record
             database
             :transaction-location
             (hash32-bytes (transaction-hash transaction))
             :missing)
          (is (eq :missing value))
          (is (not present-p))))
      (is (null (kv-chain-record-entries database :checkpoint)))
      (is (null (kv-chain-record-entries database :txpool))))))

(deftest node-store-payload-candidate-export-is-idempotent
  (multiple-value-bind (store genesis parent candidate transaction recipient)
      (payload-candidate-export-fixture)
    (declare (ignore genesis parent transaction recipient))
    (let ((database (make-memory-key-value-database)))
      (node-store-export-payload-candidate-to-kv store candidate database)
      (let ((before
              (payload-candidate-export-database-snapshot database)))
        (is (eq database
                (node-store-export-payload-candidate-to-kv
                 store candidate database)))
        (is (equalp before
                    (payload-candidate-export-database-snapshot
                     database)))))))

(deftest node-store-payload-candidate-export-conflict-is-atomic
  (multiple-value-bind (store genesis parent candidate transaction recipient)
      (payload-candidate-export-fixture)
    (declare (ignore genesis parent transaction recipient))
    (let* ((database (make-memory-key-value-database))
           (candidate-id (hash32-bytes (block-hash candidate)))
           (conflicting-state #(222)))
      (kv-put-chain-record
       database :state candidate-id conflicting-state)
      (signals block-validation-error
        (node-store-export-payload-candidate-to-kv
         store candidate database))
      (payload-candidate-export-assert-record
       database :state candidate-id conflicting-state)
      (is (null (kv-chain-record-entries database :block)))
      (is (null (kv-chain-record-entries database :header)))
      (is (null (kv-chain-record-entries database :receipt)))
      (is (= 1 (length (kv-chain-record-entries database :state)))))))

(deftest node-store-payload-candidate-export-requires-candidate-state
  (multiple-value-bind (store genesis parent candidate transaction recipient)
      (payload-candidate-export-fixture :candidate-state-available-p nil)
    (declare (ignore genesis parent transaction recipient))
    (let ((database (make-memory-key-value-database)))
      (signals block-validation-error
        (node-store-export-payload-candidate-to-kv
         store candidate database))
      (is (every
           (lambda (kind)
             (null (kv-chain-record-entries database kind)))
           +payload-candidate-export-record-kinds+)))))

(deftest node-store-payload-candidate-export-rejects-missing-ancestry-atomically
  (multiple-value-bind (store genesis parent candidate transaction recipient)
      (payload-candidate-export-fixture
       :store-genesis-p nil
       :store-parent-p nil)
    (declare (ignore genesis parent transaction recipient))
    (let ((database (make-memory-key-value-database)))
      (signals block-validation-error
        (node-store-export-payload-candidate-to-kv
         store candidate database))
      (is (every
           (lambda (kind)
             (null (kv-chain-record-entries database kind)))
           +payload-candidate-export-record-kinds+)))))
