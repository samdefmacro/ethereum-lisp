(in-package #:ethereum-lisp.engine-api)

;;;; Testing-only payload construction. This namespace remains opt-in at HTTP.

(defun testing-rpc-build-block-transactions (value method)
  (cond
    ((json-null-p value) (values nil t))
    ((json-array-p value)
     (values
      (mapcar
       (lambda (encoded)
         (transaction-from-encoding
          (json-rpc-bytes encoded (format nil "~A transaction" method))))
       (json-array-values value))
      nil))
    (t
     (block-validation-fail
      "~A transactions must be an array or null" method))))

(defun engine-rpc-handle-testing-build-block-v1
    (params store config &key gas-limit-target)
  "Build the execution-apis testing payload without publishing chain state."
  (let ((method "testing_buildBlockV1"))
    (unless (<= 3 (length params) 4)
      (block-validation-fail
       "~A params must contain parent hash, attributes, transactions, and optional extraData"
       method))
    (let* ((parent-hash (json-rpc-hash32 (first params) "parentBlockHash"))
           (parent (chain-store-known-block store parent-hash)))
      (unless parent
        (engine-rpc-fail -32000 "parent block not found"))
      (unless (chain-store-state-available-p store parent-hash)
        (engine-rpc-fail -32000 "parent state not found"))
      (let* ((attributes
               (engine-rpc-validate-payload-attributes-v3
                (second params) :method method))
             (extra-data-value (and (= 4 (length params)) (fourth params)))
             (extra-data
               (if (or (null extra-data-value)
                       (json-null-p extra-data-value))
                   (make-byte-vector 0)
                   (json-rpc-bytes extra-data-value
                                   "testing_buildBlockV1 extraData"))))
        (multiple-value-bind (transactions pool-request-p)
            (testing-rpc-build-block-transactions (third params) method)
          (when pool-request-p
            (setf transactions
                  (engine-rpc-pending-build-transactions
                   store config (block-header parent))))
          (handler-case
              (multiple-value-bind (block selected execution-state)
                  (if pool-request-p
                      (engine-rpc-build-viable-prepared-payload
                       store parent attributes config transactions
                       :gas-limit-target gas-limit-target
                       :extra-data extra-data)
                      (multiple-value-bind (exact-block receipts exact-state)
                          (engine-rpc-build-prepared-payload
                           store parent attributes config transactions
                           :gas-limit-target gas-limit-target
                           :extra-data extra-data)
                        (declare (ignore receipts))
                        (values exact-block transactions exact-state)))
                (declare (ignore execution-state))
                (engine-rpc-execution-payload-envelope-object
                 (engine-rpc-prepared-payload-envelope
                  (make-engine-prepared-payload
                   :block block
                   :blobs-bundle
                   (engine-rpc-blobs-bundle-for-transactions store selected)))
                 :include-blobs-bundle-p t
                 :include-override-p t
                 :include-requests-p t))
            (transaction-validation-error (condition)
              (engine-rpc-fail -32000 (princ-to-string condition)))))))))
