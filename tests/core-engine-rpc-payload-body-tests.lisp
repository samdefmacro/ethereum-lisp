(in-package #:ethereum-lisp.test)

(deftest engine-rpc-get-payload-bodies-by-hash-v1-returns-bodies
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
           (withdrawal-address
             (address-from-hex "0x0000000000000000000000000000000000000003"))
           (transaction
             (make-legacy-transaction :nonce 1
                                      :gas-price 2
                                      :gas-limit 21000
                                      :to recipient
                                      :value 4
                                      :v 27
                                      :r 6
                                      :s 7))
           (withdrawal
             (make-withdrawal :index 1
                              :validator-index 2
                              :address withdrawal-address
                              :amount 3))
           (block (make-block :transactions (list transaction)
                              :withdrawals (list withdrawal)))
           (empty-withdrawals-block (make-block :withdrawals '()))
           (unknown-hash
             (hash32-from-hex
              "0x2222222222222222222222222222222222222222222222222222222222222222"))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (engine-payload-store-put-block
       store empty-withdrawals-block :state-available-p t)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 28)
                      (cons "method" "engine_getPayloadBodiesByHashV1")
                      (cons "params"
                            (list
                             (list (hash32-to-hex (block-hash block))
                                   (hash32-to-hex unknown-hash)
                                   (hash32-to-hex
                                    (block-hash empty-withdrawals-block))))))
                store
                config))
             (bodies (field response "result"))
             (first-body (first bodies))
             (third-body (third bodies)))
        (is (= 28 (field response "id")))
        (is (= 3 (length bodies)))
        (is (string= (bytes-to-hex (transaction-encoding transaction))
                     (first (field first-body "transactions"))))
        (is (= 1 (length (field first-body "withdrawals"))))
        (is (not (second bodies)))
        (is (not (field third-body "transactions")))
        (is (listp (field third-body "withdrawals")))
        (is (= 0 (length (field third-body "withdrawals")))))
      (let* ((too-many-hashes
               (loop repeat 1025 collect (hash32-to-hex (block-hash block))))
             (response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 29)
                      (cons "method" "engine_getPayloadBodiesByHashV1")
                      (cons "params" (list too-many-hashes)))
                store
                config))
             (error (field response "error")))
        (is (= -38004 (field error "code")))
        (is (string= "The number of requested bodies must not exceed 1024"
                     (field error "message")))))))

(deftest engine-rpc-get-payload-bodies-by-hash-v2-returns-block-access-list
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((plain-block (make-block))
           (bal-block (make-block :block-access-list '()))
           (unknown-hash
             (hash32-from-hex
              "0x3333333333333333333333333333333333333333333333333333333333333333"))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-block store plain-block :state-available-p t)
      (engine-payload-store-put-block store bal-block :state-available-p t)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 33)
                      (cons "method" "engine_getPayloadBodiesByHashV2")
                      (cons "params"
                            (list
                             (list (hash32-to-hex (block-hash plain-block))
                                   (hash32-to-hex (block-hash bal-block))
                                   (hash32-to-hex unknown-hash)))))
                store
                config))
             (bodies (field response "result"))
             (plain-body (first bodies))
             (bal-body (second bodies)))
        (is (= 33 (field response "id")))
        (is (= 3 (length bodies)))
        (is (not (field plain-body "blockAccessList")))
        (is (string= (bytes-to-hex (block-encoded-block-access-list bal-block))
                     (field bal-body "blockAccessList")))
        (is (not (third bodies)))))
    (let* ((too-many-hashes
             (loop repeat 1025 collect (hash32-to-hex (zero-hash32))))
           (response
             (engine-rpc-handle-request
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 34)
                    (cons "method" "engine_getPayloadBodiesByHashV2")
                    (cons "params" (list too-many-hashes)))
              (make-engine-payload-memory-store)
              (make-chain-config)))
           (error (field response "error")))
      (is (= -38004 (field error "code")))
      (is (string= "The number of requested bodies must not exceed 1024"
                   (field error "message"))))))

(deftest engine-rpc-get-payload-bodies-by-range-v1-returns-bodies
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (numbered-block (number &key transactions withdrawals)
             (make-block
              :header (make-block-header :number number
                                         :timestamp number)
              :transactions transactions
              :withdrawals withdrawals)))
    (let* ((recipient
             (address-from-hex "0x0000000000000000000000000000000000000004"))
           (transaction
             (make-legacy-transaction :nonce 2
                                      :gas-price 3
                                      :gas-limit 21000
                                      :to recipient
                                      :value 5
                                      :v 27
                                      :r 8
                                      :s 9))
           (block-1 (numbered-block 1 :transactions (list transaction)))
           (block-2 (numbered-block 2 :withdrawals '()))
           (block-4 (numbered-block 4 :transactions '()))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block-1 :state-available-p t)
      (engine-payload-store-put-block store block-2 :state-available-p t)
      (engine-payload-store-put-block store block-4 :state-available-p t)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 30)
                      (cons "method" "engine_getPayloadBodiesByRangeV1")
                      (cons "params" (list "0x1" "0x4")))
                store
                config))
             (bodies (field response "result"))
             (first-body (first bodies))
             (second-body (second bodies))
             (fourth-body (fourth bodies)))
        (is (= 30 (field response "id")))
        (is (= 4 (length bodies)))
        (is (string= (bytes-to-hex (transaction-encoding transaction))
                     (first (field first-body "transactions"))))
        (is (not (field first-body "withdrawals")))
        (is (not (field second-body "transactions")))
        (is (listp (field second-body "withdrawals")))
        (is (not (third bodies)))
        (is (not (field fourth-body "transactions"))))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 31)
                      (cons "method" "engine_getPayloadBodiesByRangeV1")
                      (cons "params" (list "0x0" "0x1")))
                store
                config))
             (error (field response "error")))
        (is (= -32602 (field error "code"))))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 32)
                      (cons "method" "engine_getPayloadBodiesByRangeV1")
                      (cons "params" (list 1 1025)))
                store
                config))
             (error (field response "error")))
        (is (= -38004 (field error "code")))
        (is (string= "The number of requested bodies must not exceed 1024"
                     (field error "message")))))))

(deftest engine-rpc-get-payload-bodies-by-range-v2-returns-block-access-list
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (numbered-block
               (number &key (block-access-list nil block-access-list-p))
             (let ((header (make-block-header :number number
                                              :timestamp number)))
               (if block-access-list-p
                   (make-block :header header
                               :block-access-list block-access-list)
                   (make-block :header header)))))
    (let* ((plain-block (numbered-block 1))
           (bal-block (numbered-block 2 :block-access-list '()))
           (tail-block (numbered-block 4 :block-access-list '()))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-block store plain-block :state-available-p t)
      (engine-payload-store-put-block store bal-block :state-available-p t)
      (engine-payload-store-put-block store tail-block :state-available-p t)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 35)
                      (cons "method" "engine_getPayloadBodiesByRangeV2")
                      (cons "params" (list "0x1" "0x4")))
                store
                config))
             (bodies (field response "result"))
             (plain-body (first bodies))
             (bal-body (second bodies))
             (tail-body (fourth bodies)))
        (is (= 35 (field response "id")))
        (is (= 4 (length bodies)))
        (is (not (field plain-body "blockAccessList")))
        (is (string= (bytes-to-hex (block-encoded-block-access-list bal-block))
                     (field bal-body "blockAccessList")))
        (is (not (third bodies)))
        (is (string= (bytes-to-hex (block-encoded-block-access-list tail-block))
                     (field tail-body "blockAccessList"))))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 36)
                      (cons "method" "engine_getPayloadBodiesByRangeV2")
                      (cons "params" (list "0x1" "0x401")))
                store
                config))
             (error (field response "error")))
        (is (= -38004 (field error "code")))
        (is (string= "The number of requested bodies must not exceed 1024"
                     (field error "message")))))))

