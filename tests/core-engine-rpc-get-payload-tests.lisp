(in-package #:ethereum-lisp.test)

(deftest engine-rpc-get-payload-v3-returns-cancun-envelope
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((payload-id #(3 0 0 0 0 0 0 1))
           (block
             (make-block
              :header
              (make-block-header :number 7
                                 :timestamp 12
                                 :blob-gas-used 0
                                 :excess-blob-gas 0)))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-prepared-payload
       store
       (make-engine-prepared-payload
        :payload-id payload-id
        :version 3
        :block block))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 37)
                      (cons "method" "engine_getPayloadV3")
                      (cons "params" (list (bytes-to-hex payload-id))))
                store
                config))
             (envelope (field response "result"))
             (payload (field envelope "executionPayload"))
             (bundle (field envelope "blobsBundle")))
        (is (= 37 (field response "id")))
        (is (string= "0x0" (field envelope "blockValue")))
        (is (eq :false (field envelope "shouldOverrideBuilder")))
        (is (string= "0x0" (field payload "blobGasUsed")))
        (is (string= "0x0" (field payload "excessBlobGas")))
        (is (listp (field bundle "commitments")))
        (is (listp (field bundle "proofs")))
        (is (listp (field bundle "blobs")))
        (is (= 0 (length (field bundle "commitments")))))
      (let* ((response-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":38,\"method\":\"engine_getPayloadV3\",\"params\":[\"0x0300000000000001\"]}"
                store
                config)))
        (is (search "\"shouldOverrideBuilder\":false" response-json))))))

(deftest engine-rpc-get-payload-v4-returns-prague-execution-requests
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((payload-id #(4 0 0 0 0 0 0 1))
           (requests (list #(#x00 #xaa) #(#x01 #xbb)))
           (block
             (make-block
              :header
              (make-block-header :number 8
                                 :timestamp 13
                                 :blob-gas-used 0
                                 :excess-blob-gas 0)
              :requests requests))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-prepared-payload
       store
       (make-engine-prepared-payload
        :payload-id payload-id
        :version 4
        :block block))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 39)
                      (cons "method" "engine_getPayloadV4")
                      (cons "params" (list (bytes-to-hex payload-id))))
                store
                config))
             (envelope (field response "result"))
             (payload (field envelope "executionPayload"))
             (bundle (field envelope "blobsBundle"))
             (encoded-requests (field envelope "executionRequests")))
        (is (= 39 (field response "id")))
        (is (eq :false (field envelope "shouldOverrideBuilder")))
        (is (string= "0x0" (field payload "blobGasUsed")))
        (is (string= "0x0" (field payload "excessBlobGas")))
        (is (= 0 (length (field bundle "blobs"))))
        (is (= 2 (length encoded-requests)))
        (is (string= "0x00aa" (first encoded-requests)))
        (is (string= "0x01bb" (second encoded-requests)))))))

(deftest engine-rpc-get-payload-v5-returns-osaka-blobs-bundle
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((payload-id #(5 0 0 0 0 0 0 1))
           (requests (list #(#x02 #xcc)))
           (sidecar
             (make-blob-sidecar
              :blobs (list #(#x03 #xdd))
              :commitments (list #(#x04 #xee))
              :proofs (list #(#x05 #xff) #(#x06 #x11))))
           (block
             (make-block
              :header
              (make-block-header :number 9
                                 :timestamp 14
                                 :blob-gas-used 0
                                 :excess-blob-gas 0)
              :requests requests))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-prepared-payload
       store
       (make-engine-prepared-payload
        :payload-id payload-id
        :version 5
        :block block
        :blobs-bundle sidecar))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 40)
                      (cons "method" "engine_getPayloadV5")
                      (cons "params" (list (bytes-to-hex payload-id))))
                store
                config))
             (envelope (field response "result"))
             (bundle (field envelope "blobsBundle")))
        (is (= 40 (field response "id")))
        (is (eq :false (field envelope "shouldOverrideBuilder")))
        (is (string= "0x02cc"
                     (first (field envelope "executionRequests"))))
        (is (string= "0x04ee" (first (field bundle "commitments"))))
        (is (string= "0x05ff" (first (field bundle "proofs"))))
        (is (string= "0x0611" (second (field bundle "proofs"))))
        (is (string= "0x03dd" (first (field bundle "blobs"))))))))

(deftest engine-rpc-get-payload-v6-returns-amsterdam-fields
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((payload-id #(6 0 0 0 0 0 0 1))
           (sidecar
             (make-blob-sidecar
              :blobs (list #(#x07 #xaa))
              :commitments (list #(#x08 #xbb))
              :proofs (list #(#x09 #xcc))))
           (block
             (make-block
              :header
              (make-block-header :number 10
                                 :timestamp 15
                                 :blob-gas-used 0
                                 :excess-blob-gas 0
                                 :slot-number 42)
              :requests (list #(#x03 #xdd))
              :block-access-list '()))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-prepared-payload
       store
       (make-engine-prepared-payload
        :payload-id payload-id
        :version 6
        :block block
        :blobs-bundle sidecar))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 41)
                      (cons "method" "engine_getPayloadV6")
                      (cons "params" (list (bytes-to-hex payload-id))))
                store
                config))
             (envelope (field response "result"))
             (payload (field envelope "executionPayload"))
             (bundle (field envelope "blobsBundle")))
        (is (= 41 (field response "id")))
        (is (string= (quantity-to-hex 42) (field payload "slotNumber")))
        (is (string= (bytes-to-hex (block-encoded-block-access-list block))
                     (field payload "blockAccessList")))
        (is (string= "0x03dd"
                     (first (field envelope "executionRequests"))))
        (is (string= "0x08bb" (first (field bundle "commitments"))))
        (is (string= "0x09cc" (first (field bundle "proofs"))))
        (is (string= "0x07aa" (first (field bundle "blobs"))))))))

(deftest engine-rpc-get-blobs-v1-returns-blobs-and-proofs
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((blob (make-byte-vector +blob-byte-size+))
           (commitment (make-byte-vector +kzg-commitment-size+))
           (proof (make-byte-vector +kzg-proof-size+))
           (unknown-hash
             (make-hash32 (make-byte-vector 32 :initial-element #x11)))
           (sidecar nil)
           (versioned-hash nil)
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (setf (aref blob 0) #xaa
            (aref commitment 0) #xbb
            (aref proof 0) #xcc
            sidecar (make-blob-sidecar
                     :blobs (list blob)
                     :commitments (list commitment)
                     :proofs (list proof))
            versioned-hash (first (blob-sidecar-versioned-hashes sidecar)))
      (engine-payload-store-put-blob-sidecar store sidecar)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 42)
                      (cons "method" "engine_getBlobsV1")
                      (cons "params"
                            (list (list (hash32-to-hex versioned-hash)
                                        (hash32-to-hex unknown-hash)))))
                store
                config))
             (result (field response "result"))
             (first-blob (first result)))
        (is (= 42 (field response "id")))
        (is (= 2 (length result)))
        (is (string= (bytes-to-hex blob) (field first-blob "blob")))
        (is (string= (bytes-to-hex proof) (field first-blob "proof")))
        (is (null (second result))))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 43)
                      (cons "method" "engine_getBlobsV1")
                      (cons "params"
                            (list
                             (loop repeat 129
                                   collect (hash32-to-hex unknown-hash)))))
                store
                config))
             (error (field response "error")))
        (is (= -38004 (field error "code")))
        (is (string= "The number of requested blobs must not exceed 128"
                     (field error "message")))))))

(deftest engine-rpc-get-blobs-v2-v3-return-cell-proofs
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((blob (make-byte-vector +blob-byte-size+))
           (commitment (make-byte-vector +kzg-commitment-size+))
           (proofs
             (loop for i below +cell-proofs-per-blob+
                   collect
                   (let ((proof (make-byte-vector +kzg-proof-size+)))
                     (setf (aref proof 0) i)
                     proof)))
           (unknown-hash
             (make-hash32 (make-byte-vector 32 :initial-element #x22)))
           (sidecar nil)
           (versioned-hash nil)
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (setf (aref blob 0) #xaa
            (aref commitment 0) #xbb
            sidecar (make-blob-sidecar
                     :blobs (list blob)
                     :commitments (list commitment)
                     :proofs proofs)
            versioned-hash (first (blob-sidecar-versioned-hashes sidecar)))
      (engine-payload-store-put-blob-sidecar store sidecar)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 44)
                      (cons "method" "engine_getBlobsV2")
                      (cons "params"
                            (list (list (hash32-to-hex versioned-hash)))))
                store
                config))
             (result (field response "result"))
             (first-blob (first result))
             (encoded-proofs (field first-blob "proofs")))
        (is (= 44 (field response "id")))
        (is (= 1 (length result)))
        (is (string= (bytes-to-hex blob) (field first-blob "blob")))
        (is (= +cell-proofs-per-blob+ (length encoded-proofs)))
        (is (string= (bytes-to-hex (first proofs)) (first encoded-proofs)))
        (is (string= (bytes-to-hex (car (last proofs)))
                     (car (last encoded-proofs)))))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 45)
                      (cons "method" "engine_getBlobsV2")
                      (cons "params"
                            (list (list (hash32-to-hex versioned-hash)
                                        (hash32-to-hex unknown-hash)))))
                store
                config)))
        (is (= 45 (field response "id")))
        (is (null (field response "result"))))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 46)
                      (cons "method" "engine_getBlobsV3")
                      (cons "params"
                            (list (list (hash32-to-hex versioned-hash)
                                        (hash32-to-hex unknown-hash)))))
                store
                config))
             (result (field response "result"))
             (first-blob (first result)))
        (is (= 46 (field response "id")))
        (is (= 2 (length result)))
        (is (string= (bytes-to-hex blob) (field first-blob "blob")))
        (is (string= (bytes-to-hex (first proofs))
                     (first (field first-blob "proofs"))))
        (is (null (second result)))))))

