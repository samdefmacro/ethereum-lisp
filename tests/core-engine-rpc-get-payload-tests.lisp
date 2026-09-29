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
        (is (ethereum-lisp.json:json-empty-array-p
             (field bundle "commitments")))
        (is (ethereum-lisp.json:json-empty-array-p
             (field bundle "proofs")))
        (is (ethereum-lisp.json:json-empty-array-p
             (field bundle "blobs"))))
      (let* ((response-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":38,\"method\":\"engine_getPayloadV3\",\"params\":[\"0x0300000000000001\"]}"
                store
                config)))
        (is (search "\"shouldOverrideBuilder\":false" response-json))))))

(deftest engine-get-blobs-v3-snapshot-falls-back-without-waiting
  (let* ((source (make-engine-payload-memory-store))
         (database (make-memory-key-value-database))
         (blob (make-byte-vector +blob-byte-size+))
         (commitment (make-byte-vector +kzg-commitment-size+))
         (blob-proof (make-byte-vector +kzg-proof-size+))
         (proofs
           (loop for index below +cell-proofs-per-blob+
                 collect
                 (let ((proof (make-byte-vector +kzg-proof-size+)))
                   (setf (aref proof 0) index)
                   proof)))
         (sidecar nil)
         (versioned-hash nil)
         (unknown-hash
           "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
         (config (make-chain-config :london-block 0 :osaka-time 0))
         (acquire-p nil)
         (guard-probes 0)
         (guard-entries 0)
         (store nil)
         (reader nil)
         (params nil))
    (setf (aref blob (1- (length blob))) #x5a
          (aref commitment 0) #xbb
          sidecar (make-blob-sidecar
                   :blobs (list blob)
                   :commitments (list commitment)
                   :proofs proofs)
          versioned-hash (first (blob-sidecar-versioned-hashes sidecar)))
    (let ((*kzg-cell-proof-verifier*
            (lambda (verified-blob verified-commitment verified-proofs)
              (declare
               (ignore verified-blob verified-commitment verified-proofs))
              t)))
      (ethereum-lisp.chain-store:engine-payload-store-put-blob-sidecar
       source sidecar
       :blob-proof-function
       (lambda (actual-blob actual-commitment)
         (is (bytes= blob actual-blob))
         (is (bytes= commitment actual-commitment))
         blob-proof))
      (node-store-export-to-kv source database)
      (setf store (make-database-engine-payload-store database)
            reader
            (ethereum-lisp.engine-api:make-engine-rpc-get-blobs-v3-snapshot-function
             store config
             (lambda (thunk)
               (incf guard-probes)
               (if acquire-p
                   (progn
                     (incf guard-entries)
                     (values (funcall thunk) t))
                   (values nil nil))))
            params
            (list (list (hash32-to-hex versioned-hash) unknown-hash)))
      (let ((fallback (funcall reader params)))
        (is (= 2 (length fallback)))
        (is (assoc "blob" (first fallback) :test #'string=))
        (is (null (second fallback)))
        (is (= 1 guard-probes))
        (is (= 0 guard-entries))
        (setf acquire-p t)
        (let ((ordinary (funcall reader params)))
          (is (equal fallback ordinary))
          (is (= 2 guard-probes))
          (is (= 1 guard-entries)))))))

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

(deftest engine-rpc-blob-methods-reject-invalid-positional-arity
  ;; Pinned geth 38271784 exposes one []common.Hash argument for getBlobsV1-V3
  ;; and hasBlobs, while getBlobsV4 adds one custody bitmap argument.  JSON-RPC
  ;; must reject trailing values rather than silently ignoring them.
  (let ((pre-osaka-config (make-chain-config))
        (osaka-config (make-chain-config :london-block 0 :osaka-time 0))
        (store (make-engine-payload-memory-store))
        (bitmap (bytes-to-hex (make-byte-vector 16))))
    (dolist (request
             (list
              (list "engine_getBlobsV1" pre-osaka-config (list '() nil))
              (list "engine_getBlobsV2" osaka-config (list '() nil))
              (list "engine_getBlobsV3" osaka-config (list '() nil))
              (list "engine_getBlobsV4" osaka-config
                    (list '() bitmap nil))
              (list "engine_hasBlobs" osaka-config (list '() nil))))
      (destructuring-bind (method config params) request
        (let* ((response
                 (engine-rpc-handle-request
                  (list (cons "jsonrpc" "2.0")
                        (cons "id" 41)
                        (cons "method" method)
                        (cons "params" params))
                  store config))
               (error (cdr (assoc "error" response :test #'string=))))
          (is (= -32602 (cdr (assoc "code" error :test #'string=)))))))))

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
      (setf (aref commitment 0) #xbb
            (aref proof 0) #xcc
            sidecar (make-blob-sidecar
                     :blobs (list blob)
                     :commitments (list commitment)
                     :proofs (list proof))
            versioned-hash (first (blob-sidecar-versioned-hashes sidecar)))
      (signals block-validation-error
        (engine-payload-store-put-blob-sidecar store sidecar))
      (let ((*kzg-blob-proof-verifier*
              (lambda (verified-blob verified-commitment verified-proof)
                (and (bytes= blob verified-blob)
                     (bytes= commitment verified-commitment)
                     (bytes= proof verified-proof)))))
        (engine-payload-store-put-blob-sidecar store sidecar))
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
           (blob-proof (make-byte-vector +kzg-proof-size+))
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
           (config (make-chain-config :london-block 0
                                      :cancun-time 0
                                      :prague-time 0
                                      :osaka-time 0)))
      (setf (aref blob 31) #x02
            (aref commitment 0) #xbb
            sidecar (make-blob-sidecar
                     :blobs (list blob)
                     :commitments (list commitment)
                     :proofs proofs)
            versioned-hash (first (blob-sidecar-versioned-hashes sidecar)))
      (signals block-validation-error
        (engine-payload-store-put-blob-sidecar store sidecar))
      (let ((*kzg-cell-proof-verifier*
              (lambda (verified-blob verified-commitment verified-proofs)
                (and (bytes= blob verified-blob)
                     (bytes= commitment verified-commitment)
                     (= +cell-proofs-per-blob+
                        (length verified-proofs))))))
        (engine-payload-store-put-blob-sidecar
         store sidecar
         :blob-proof-function
         (lambda (actual-blob actual-commitment)
           (is (bytes= blob actual-blob))
           (is (bytes= commitment actual-commitment))
           blob-proof)))
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

(deftest engine-rpc-get-blobs-v4-and-has-blobs
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :london-block 0 :osaka-time 0))
           (blob (make-byte-vector +blob-byte-size+))
           (commitment (make-byte-vector 48 :initial-element #x11))
           (proof (make-byte-vector 48 :initial-element #x22))
           (sidecar
             (make-blob-sidecar
              :blobs (list blob)
              :commitments (list commitment)
              :proofs (list proof)))
           (versioned-hash (first (blob-sidecar-versioned-hashes sidecar)))
           (unknown-hash
             (make-hash32 (make-byte-vector 32 :initial-element #x33)))
           (bitmap (make-byte-vector 16)))
      (setf (aref bitmap 0) #x01
            (aref bitmap 15) #x80)
      (let ((*kzg-blob-proof-verifier*
              (lambda (verified-blob verified-commitment verified-proof)
                (and (bytes= blob verified-blob)
                     (bytes= commitment verified-commitment)
                     (bytes= proof verified-proof)))))
        (engine-payload-store-put-blob-sidecar store sidecar))
      (let* ((response
               (engine-rpc-handle-request
                (list
                 (cons "jsonrpc" "2.0")
                 (cons "id" 47)
                 (cons "method" "engine_getBlobsV4")
                 (cons
                  "params"
                  (list
                   (list (hash32-to-hex versioned-hash))
                   (bytes-to-hex bitmap))))
                store config))
             (result (field response "result"))
             (blob-result (first result)))
        (is (= 1 (length result)))
        (is (= 2 (length (field blob-result "blob_cells"))))
        (is (= 2 (length (field blob-result "proofs"))))
        (is (= (+ 2 (* 2 +bytes-per-cell+))
               (length (first (field blob-result "blob_cells"))))))
      (let* ((response
               (engine-rpc-handle-request
                (list
                 (cons "jsonrpc" "2.0")
                 (cons "id" 48)
                 (cons "method" "engine_hasBlobs")
                 (cons
                  "params"
                  (list
                   (list (hash32-to-hex versioned-hash)
                         (hash32-to-hex unknown-hash)))))
                store config))
             (result (field response "result")))
        (is (eq t (first result)))
        (is (eq :false (second result)))))))

;;; engine_getBlobsV4: one read batch, stored cell proofs, per-position nulls.

(defun get-blobs-v4-test-cell-proof (blob-index cell-index)
  "A stand-in cell proof naming its blob and its cell, so that a proof derived
by c-kzg can never pass for the stored one."
  (let ((proof (make-byte-vector +kzg-proof-size+ :initial-element #xa0)))
    (setf (aref proof 0) blob-index
          (aref proof 1) cell-index)
    proof))

(defun get-blobs-v4-test-blob (blob-index)
  "A distinct, canonical blob: its first field element is 1 + BLOB-INDEX."
  (let ((blob (make-byte-vector +blob-byte-size+)))
    (setf (aref blob 31) (1+ blob-index))
    blob))

(defun get-blobs-v4-test-sidecar (first-index count &key cell-proofs-p)
  "A sidecar of COUNT distinct blobs numbered from FIRST-INDEX, carrying the
stand-in cell proofs when CELL-PROOFS-P and one EIP-4844 proof per blob
otherwise."
  (let ((indices (loop for index from first-index repeat count
                       collect index)))
    (make-blob-sidecar
     :blobs (mapcar #'get-blobs-v4-test-blob indices)
     :commitments
     (mapcar (lambda (index)
               (let ((commitment
                       (make-byte-vector +kzg-commitment-size+
                                         :initial-element #xc0)))
                 (setf (aref commitment 1) index)
                 commitment))
             indices)
     :proofs
     (if cell-proofs-p
         (loop for index in indices
               append (loop for cell below +cell-proofs-per-blob+
                            collect (get-blobs-v4-test-cell-proof index cell)))
         (loop repeat count
               collect (make-byte-vector +kzg-proof-size+
                                         :initial-element #x22))))))

(defun get-blobs-v4-test-put (store sidecar)
  "Publish SIDECAR in STORE as the pool does, its proofs already verified."
  (engine-payload-store-put-blob-sidecar
   store sidecar
   :proofs-verified-p t
   :blob-proof-function
   (lambda (blob commitment)
     (declare (ignore blob commitment))
     (make-byte-vector +kzg-proof-size+ :initial-element #x33))))

(defun get-blobs-v4-test-bitmap (indices)
  "The 16-byte little-endian custody bitmap selecting cell INDICES."
  (let ((bitmap (make-byte-vector 16)))
    (dolist (index indices bitmap)
      (setf (aref bitmap (floor index 8))
            (logior (aref bitmap (floor index 8))
                    (ash 1 (mod index 8)))))))

(defun get-blobs-v4-test-call (store config id hashes bitmap)
  "The engine_getBlobsV4 response to HASHES and BITMAP."
  (engine-rpc-handle-request
   (list (cons "jsonrpc" "2.0")
         (cons "id" id)
         (cons "method" "engine_getBlobsV4")
         (cons "params"
               (list (mapcar #'hash32-to-hex hashes)
                     (bytes-to-hex bitmap))))
   store config))

(defun get-blobs-v4-test-field (object name)
  (cdr (assoc name object :test #'string=)))

(defun get-blobs-v4-test-counting-calls (symbols thunk)
  "Call THUNK with every function named in SYMBOLS counting its calls, and
restore every definition after. THUNK receives a function of one symbol that
answers that function's count so far."
  (let ((originals (mapcar (lambda (symbol)
                             (cons symbol (fdefinition symbol)))
                           symbols))
        (counts (make-hash-table :test #'eq)))
    (unwind-protect
         (progn
           (dolist (entry originals)
             (let ((symbol (car entry))
                   (original (cdr entry)))
               (setf (fdefinition symbol)
                     (lambda (&rest arguments)
                       (incf (gethash symbol counts 0))
                       (apply original arguments)))))
           (funcall thunk (lambda (symbol) (gethash symbol counts 0))))
      (dolist (entry originals)
        (setf (fdefinition (car entry)) (cdr entry))))))

(defun get-blobs-v4-test-expected-object (cells blob-index indices)
  "The blob_cells and proofs hex lists engine_getBlobsV4 must answer for the
blob numbered BLOB-INDEX, whose 128 cells are CELLS."
  (values
   (mapcar (lambda (index) (bytes-to-hex (nth index cells))) indices)
   (mapcar (lambda (index)
             (bytes-to-hex (get-blobs-v4-test-cell-proof blob-index index)))
           indices)))

(deftest engine-rpc-get-blobs-v4-reads-each-blob-once-and-serves-stored-cell-proofs
  ;; E1 (wave 6, out of scope there): the V4 handler read every requested blob
  ;; through a call that enforced the blob cache bounds -- a walk and two sorts
  ;; of the whole cache -- once per blob, the per-read cost 68c2f376 removed
  ;; from V1-V3 and hasBlobs; and it ran c-kzg's full cell AND proof derivation
  ;; for every blob (about 0.12 s each in the warm image) although the store
  ;; holds the 128 cell proofs. go-ethereum v1.17.6 GetBlobsV4 answers from
  ;; blobpool Cache.GetCells / BlobPool.GetBlobCells, which serve the stored
  ;; proofs as they are. For six blobs: six enforcements become one, six
  ;; derivations none, and the proofs answered are the stored ones.
  (unless (kzg-cell-computation-available-p)
    (skip-test "c-kzg cell computation (libethckzg) is unavailable"))
  (let* ((store (make-engine-payload-memory-store))
         (config (make-chain-config :london-block 0 :osaka-time 0))
         (sidecar (get-blobs-v4-test-sidecar 0 6 :cell-proofs-p t))
         (legacy (get-blobs-v4-test-sidecar 6 1))
         (indices '(0 9 127))
         (bitmap (get-blobs-v4-test-bitmap indices))
         (oracle-cells
           (mapcar (lambda (blob)
                     (values (kzg-compute-cells-and-proofs blob)))
                   (blob-sidecar-blobs sidecar)))
         (enforce
           'ethereum-lisp.chain-store::engine-payload-store-enforce-cache-bounds)
         (derive 'ethereum-lisp.kzg::kzg-compute-cells-and-proofs))
    (get-blobs-v4-test-put store sidecar)
    (get-blobs-v4-test-put store legacy)
    (get-blobs-v4-test-counting-calls
     (list enforce derive)
     (lambda (count)
       (let ((result
               (get-blobs-v4-test-field
                (get-blobs-v4-test-call
                 store config 50 (blob-sidecar-versioned-hashes sidecar)
                 bitmap)
                "result")))
         (is (= 6 (length result)))
         (loop for object in result
               for cells in oracle-cells
               for blob-index from 0
               do (multiple-value-bind (expected-cells expected-proofs)
                      (get-blobs-v4-test-expected-object
                       cells blob-index indices)
                    (is (equal expected-cells
                               (get-blobs-v4-test-field object "blob_cells")))
                    (is (equal expected-proofs
                               (get-blobs-v4-test-field object "proofs")))))
         (is (= 1 (funcall count enforce)))
         (is (= 0 (funcall count derive))))
       ;; Positive control: a blob stored before Osaka with its one EIP-4844
       ;; proof has no cell proofs to serve, so its cells and proofs are
       ;; derived, and the counters see both the read and the derivation.
       (let* ((result
                (get-blobs-v4-test-field
                 (get-blobs-v4-test-call
                  store config 51 (blob-sidecar-versioned-hashes legacy)
                  bitmap)
                 "result"))
              (object (first result)))
         (is (= 1 (length result)))
         (is (= 3 (length (get-blobs-v4-test-field object "proofs"))))
         (is (= 2 (funcall count enforce)))
         (is (= 1 (funcall count derive))))))))

(deftest engine-rpc-get-blobs-v4-answers-each-position-and-bounds-the-request
  ;; Parity with go-ethereum v1.17.6 GetBlobsV4 and execution-apis
  ;; src/engine/amsterdam.md: one entry per requested hash in request order,
  ;; null where the blob is unknown (never an error, never a null response
  ;; for a partial hit); a repeated hash answers the same blob, its cells
  ;; computed once; more than 128 hashes is -38004 (geth's len(hashes) > 128,
  ;; and 128 itself is served); before Osaka the result is null; the bitmap
  ;; is 16 bytes.
  (unless (kzg-cell-computation-available-p)
    (skip-test "c-kzg cell computation (libethckzg) is unavailable"))
  (let* ((store (make-engine-payload-memory-store))
         (config (make-chain-config :london-block 0 :osaka-time 0))
         (sidecar (get-blobs-v4-test-sidecar 0 2 :cell-proofs-p t))
         (hashes (blob-sidecar-versioned-hashes sidecar))
         (a (first hashes))
         (b (second hashes))
         (unknown (make-hash32 (make-byte-vector 32 :initial-element #x44)))
         (other-unknown
           (make-hash32 (make-byte-vector 32 :initial-element #x45)))
         (indices '(0 9 127))
         (bitmap (get-blobs-v4-test-bitmap indices))
         (cells-of-b
           (values (kzg-compute-cells-and-proofs
                    (second (blob-sidecar-blobs sidecar)))))
         (compute-cells 'ethereum-lisp.kzg::kzg-compute-cells)
         (derive 'ethereum-lisp.kzg::kzg-compute-cells-and-proofs))
    (get-blobs-v4-test-put store sidecar)
    ;; The cells alone are the cells of the full derivation.
    (is (equalp cells-of-b
                (ethereum-lisp.kzg::kzg-compute-cells
                 (second (blob-sidecar-blobs sidecar)))))
    (get-blobs-v4-test-counting-calls
     (list compute-cells derive)
     (lambda (count)
       (let ((result
               (get-blobs-v4-test-field
                (get-blobs-v4-test-call store config 60
                                        (list a unknown a b) bitmap)
                "result")))
         (is (= 4 (length result)))
         (is (null (second result)))
         (is (equal (first result) (third result)))
         (multiple-value-bind (expected-cells expected-proofs)
             (get-blobs-v4-test-expected-object cells-of-b 1 indices)
           (is (equal expected-cells
                      (get-blobs-v4-test-field (fourth result) "blob_cells")))
           (is (equal expected-proofs
                      (get-blobs-v4-test-field (fourth result) "proofs"))))
         (is (= 2 (funcall count compute-cells)))
         (is (= 0 (funcall count derive))))
       ;; A mask selecting no cell answers empty arrays and computes nothing.
       (let ((object
               (first
                (get-blobs-v4-test-field
                 (get-blobs-v4-test-call store config 61 (list a)
                                         (make-byte-vector 16))
                 "result"))))
         (is (ethereum-lisp.json:json-empty-array-p
              (get-blobs-v4-test-field object "blob_cells")))
         (is (ethereum-lisp.json:json-empty-array-p
              (get-blobs-v4-test-field object "proofs")))
         (is (= 2 (funcall count compute-cells))))))
    ;; Nothing known: a null per position, not a null response or an error.
    (let ((response (get-blobs-v4-test-call store config 62
                                            (list unknown other-unknown)
                                            bitmap)))
      (is (null (get-blobs-v4-test-field response "error")))
      (is (equal '(nil nil) (get-blobs-v4-test-field response "result"))))
    ;; 128 hashes are served; 129 are too large a request.
    (let ((response (get-blobs-v4-test-call
                     store config 63
                     (loop repeat 128 collect unknown) bitmap)))
      (is (null (get-blobs-v4-test-field response "error")))
      (is (= 128 (length (get-blobs-v4-test-field response "result")))))
    (let ((error (get-blobs-v4-test-field
                  (get-blobs-v4-test-call
                   store config 64 (loop repeat 129 collect a) bitmap)
                  "error")))
      (is (= -38004 (get-blobs-v4-test-field error "code")))
      (is (string= "The number of requested blobs must not exceed 128"
                   (get-blobs-v4-test-field error "message"))))
    ;; Before Osaka the method answers null.
    (let ((response (get-blobs-v4-test-call store (make-chain-config) 65
                                            (list a) bitmap)))
      (is (null (get-blobs-v4-test-field response "error")))
      (is (assoc "result" response :test #'string=))
      (is (null (get-blobs-v4-test-field response "result"))))
    ;; The custody bitmap is 16 bytes.
    (let ((error (get-blobs-v4-test-field
                  (get-blobs-v4-test-call store config 66 (list a)
                                          (make-byte-vector 15))
                  "error")))
      (is (= -32602 (get-blobs-v4-test-field error "code"))))))
