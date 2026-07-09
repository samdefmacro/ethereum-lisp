(in-package #:ethereum-lisp.test)

(deftest chain-store-export-import-kv-restores-prepared-payloads
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((path
             (merge-pathnames
              (make-pathname
               :name (format nil "ethereum-lisp-chain-prepared-payload-~A"
                             (gensym))
               :type "sexp")
              #P"/private/tmp/"))
           (source (make-engine-payload-memory-store))
           (restored (make-engine-payload-memory-store))
           (payload-id #(5 0 0 0 0 0 0 1))
           (block
             (make-block
              :header
              (make-block-header :number 9
                                 :timestamp 14
                                 :withdrawals-root
                                 (withdrawal-list-root '()))
              :withdrawals '()))
           (sidecar
             (make-blob-sidecar
              :blobs (list #(#x03 #xdd))
              :commitments (list #(#x04 #xee))
              :proofs (list #(#x05 #xff) #(#x06 #x11))))
           (prepared-payload
             (make-engine-prepared-payload
              :payload-id payload-id
              :version 5
              :block block
              :blobs-bundle sidecar))
           (payload-id-bytes (ensure-byte-vector payload-id)))
      (unwind-protect
           (progn
             (chain-store-put-prepared-payload source prepared-payload)
             (let ((database (make-file-key-value-database path)))
               (chain-store-export-to-kv source database))
             (let ((database (make-file-key-value-database path)))
               (multiple-value-bind (record present-p)
                   (kv-get-chain-record
                    database :prepared-payload payload-id-bytes)
                 (is present-p)
                 (is (bytes= record
                             (ethereum-lisp.core::chain-store-prepared-payload-record-rlp
                              prepared-payload)))))
             (let ((database (make-file-key-value-database path)))
               (is (eq restored
                       (chain-store-import-from-kv restored database))))
             (let ((restored-payload
                     (chain-store-prepared-payload restored payload-id)))
               (is restored-payload)
               (is (= 5
                      (ethereum-lisp.core::engine-prepared-payload-version
                       restored-payload)))
               (is (bytes= (block-rlp block)
                           (block-rlp
                            (ethereum-lisp.core::engine-prepared-payload-block
                             restored-payload)))))
             (let* ((response
                      (engine-rpc-handle-request
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 40)
                             (cons "method" "engine_getPayloadV5")
                             (cons "params" (list (bytes-to-hex payload-id))))
                       restored
                       (make-chain-config)))
                    (envelope (field response "result"))
                    (bundle (field envelope "blobsBundle")))
               (is (= 40 (field response "id")))
               (is (string= "0x04ee" (first (field bundle "commitments"))))
               (is (string= "0x05ff" (first (field bundle "proofs"))))
               (is (string= "0x0611" (second (field bundle "proofs"))))
               (is (string= "0x03dd" (first (field bundle "blobs")))))
             (let ((database (make-file-key-value-database path)))
               (chain-store-export-to-kv
                (make-engine-payload-memory-store)
                database))
             (let ((database (make-file-key-value-database path)))
               (multiple-value-bind (record present-p)
                   (kv-get-chain-record
                    database :prepared-payload payload-id-bytes :missing)
                 (is (eq :missing record))
                 (is (not present-p)))))
        (when (probe-file path)
          (delete-file path))))))

(deftest chain-store-put-block-prunes-prepared-payload-cache
  (let* ((store (make-engine-payload-memory-store))
         (payload-id #(2 0 0 0 0 0 0 1))
         (block
           (make-block
            :header
            (make-block-header :number 9
                               :timestamp 14
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (prepared-payload
           (make-engine-prepared-payload
            :payload-id payload-id
            :version 2
            :block block)))
    (chain-store-put-prepared-payload store prepared-payload)
    (is (chain-store-prepared-payload store payload-id))
    (chain-store-put-block store block)
    (is (not (chain-store-prepared-payload store payload-id)))))

(deftest engine-payload-store-mark-invalid-prunes-prepared-payload-cache
  (let* ((store (make-engine-payload-memory-store))
         (invalid-payload-id #(2 0 0 0 0 0 0 1))
         (descendant-payload-id #(2 0 0 0 0 0 0 2))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (invalid-block
           (make-block
            :header
            (make-block-header :number 9
                               :timestamp 14
                               :beneficiary address
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (descendant-block
           (make-block
            :header
            (make-block-header :number 10
                               :parent-hash (block-hash invalid-block)
                               :timestamp 15
                               :beneficiary address
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (invalid-prepared-payload
           (make-engine-prepared-payload
            :payload-id invalid-payload-id
            :version 2
            :block invalid-block))
         (descendant-prepared-payload
           (make-engine-prepared-payload
            :payload-id descendant-payload-id
            :version 2
            :block descendant-block)))
    (chain-store-put-prepared-payload store invalid-prepared-payload)
    (chain-store-put-prepared-payload store descendant-prepared-payload)
    (is (chain-store-prepared-payload store invalid-payload-id))
    (is (chain-store-prepared-payload store descendant-payload-id))
    (ethereum-lisp.core::engine-payload-store-mark-invalid
     store invalid-block :head-hash (block-hash descendant-block))
    (is (not (chain-store-prepared-payload store invalid-payload-id)))
    (is (not (chain-store-prepared-payload store descendant-payload-id)))))

(deftest chain-store-export-to-kv-prunes-known-prepared-payload-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-known-prepared-export-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (store (make-engine-payload-memory-store))
         (payload-id #(2 0 0 0 0 0 0 1))
         (block
           (make-block
            :header
            (make-block-header :number 9
                               :timestamp 14
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (prepared-payload
           (make-engine-prepared-payload
            :payload-id payload-id
            :version 2
            :block block))
         (payload-id-bytes (ensure-byte-vector payload-id))
         (block-id (hash32-bytes (block-hash block))))
    (unwind-protect
         (progn
           (chain-store-put-block store block)
           (chain-store-put-prepared-payload store prepared-payload)
           (let ((database (make-file-key-value-database path)))
             (kv-put-chain-record
              database
              :prepared-payload
              payload-id-bytes
              (ethereum-lisp.core::chain-store-prepared-payload-record-rlp
               prepared-payload))
             (chain-store-export-to-kv store database))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record
                  database :prepared-payload payload-id-bytes :missing)
               (is (eq :missing record))
               (is (not present-p)))
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record database :block block-id)
               (is present-p)
               (is (bytes= (block-rlp block) record)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-retains-matching-known-prepared-payload-record
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((path
             (merge-pathnames
              (make-pathname
               :name (format nil "ethereum-lisp-known-prepared-import-~A"
                             (gensym))
               :type "sexp")
              #P"/private/tmp/"))
           (target (make-engine-payload-memory-store))
           (payload-id #(6 0 0 0 0 0 0 1))
           (target-payload-id #(2 0 0 0 0 0 0 2))
           (account
             (make-block-access-account
              :address
              (address-from-hex
               "0x0000000000000000000000000000000000000001")))
           (known-block
             (make-block
              :header
              (make-block-header :parent-hash (zero-hash32)
                                 :beneficiary (zero-address)
                                 :state-root +empty-trie-hash+
                                 :mix-hash (zero-hash32)
                                 :number 10
                                 :gas-limit 50000
                                 :gas-used 21000
                                 :timestamp 15
                                 :base-fee-per-gas 100
                                 :blob-gas-used 0
                                 :excess-blob-gas 0
                                 :parent-beacon-root (zero-hash32)
                                 :slot-number 42
                                 :withdrawals-root
                                 (withdrawal-list-root '()))
              :withdrawals '()
              :requests (list #(#x82 #x06 #xaa))
              :block-access-list (list account)))
           (sidecar
             (make-blob-sidecar
              :blobs (list #(#x03 #xdd))
              :commitments (list #(#x04 #xee))
              :proofs (list #(#x05 #xff) #(#x06 #x11))))
           (prepared-payload
             (make-engine-prepared-payload
              :payload-id payload-id
              :version 6
              :block known-block
              :blobs-bundle sidecar))
           (target-block
             (make-block
              :header
              (make-block-header :number 11
                                 :timestamp 16
                                 :withdrawals-root
                                 (withdrawal-list-root '()))
              :withdrawals '()))
           (target-payload
             (make-engine-prepared-payload
              :payload-id target-payload-id
              :version 2
              :block target-block))
           (config (make-chain-config)))
      (unwind-protect
           (progn
             (chain-store-put-prepared-payload target target-payload)
             (let ((database (make-file-key-value-database path)))
               (kv-put-chain-record
                database
                :block
                (hash32-bytes (block-hash known-block))
                (block-rlp known-block))
               (kv-put-chain-record
                database
                :prepared-payload
                (ensure-byte-vector payload-id)
                (ethereum-lisp.core::chain-store-prepared-payload-record-rlp
                 prepared-payload)))
             (let ((database (make-file-key-value-database path)))
               (is (eq target
                       (chain-store-import-from-kv target database))))
             (is (chain-store-known-block target (block-hash known-block)))
             (is (chain-store-prepared-payload target payload-id))
             (is (not
                  (chain-store-prepared-payload target target-payload-id)))
             (let* ((payload-response
                      (engine-rpc-handle-request
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 40)
                             (cons "method" "engine_getPayloadV6")
                             (cons "params" (list (bytes-to-hex payload-id))))
                       target
                       config))
                    (envelope (field payload-response "result"))
                    (payload (field envelope "executionPayload"))
                    (bundle (field envelope "blobsBundle"))
                    (body-response
                      (engine-rpc-handle-request
                       (list
                        (cons "jsonrpc" "2.0")
                        (cons "id" 41)
                        (cons "method" "engine_getPayloadBodiesByHashV2")
                        (cons "params"
                              (list
                               (list
                                (hash32-to-hex
                                 (block-hash known-block))))))
                       target
                       config))
                    (body (first (field body-response "result"))))
               (is (= 40 (field payload-response "id")))
               (is (string= (bytes-to-hex
                             (block-encoded-block-access-list known-block))
                            (field payload "blockAccessList")))
               (is (string= "0x8206aa"
                            (first (field envelope "executionRequests"))))
               (is (string= "0x04ee"
                            (first (field bundle "commitments"))))
               (is (= 41 (field body-response "id")))
               (is body)
               (is (listp (field body "transactions")))
               (is (null (field body "transactions")))
               (is (listp (field body "withdrawals")))
               (is (null (field body "withdrawals")))
               (is (string= (bytes-to-hex
                             (block-encoded-block-access-list known-block))
                            (field body "blockAccessList")))))
        (when (probe-file path)
          (delete-file path))))))

(deftest chain-store-import-from-kv-drops-mismatched-known-prepared-payload-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-known-prepared-mismatch-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (target (make-engine-payload-memory-store))
         (payload-id #(2 0 0 0 0 0 0 1))
         (target-payload-id #(2 0 0 0 0 0 0 2))
         (header
           (make-block-header :number 9
                              :timestamp 14
                              :withdrawals-root
                              (withdrawal-list-root '())))
         (transaction
           (make-legacy-transaction :nonce 2
                                    :gas-price 3
                                    :gas-limit 21000
                                    :to (address-from-hex
                                         "0x0000000000000000000000000000000000000004")
                                    :value 5
                                    :v 27
                                    :r 8
                                    :s 9))
         (known-block (make-block :header header :withdrawals '()))
         (prepared-block
           (make-block
            :header header
            :transactions (list transaction)
            :withdrawals '()))
         (prepared-payload
           (make-engine-prepared-payload
            :payload-id payload-id
            :version 2
            :block prepared-block))
         (target-block
           (make-block
            :header
            (make-block-header :number 10
                               :timestamp 15
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (target-payload
           (make-engine-prepared-payload
            :payload-id target-payload-id
            :version 2
            :block target-block)))
    (unwind-protect
         (progn
           (chain-store-put-prepared-payload target target-payload)
           (let ((database (make-file-key-value-database path)))
             (kv-put-chain-record
              database
              :block
              (hash32-bytes (block-hash known-block))
              (block-rlp known-block))
             (kv-put-chain-record
              database
              :prepared-payload
              (ensure-byte-vector payload-id)
              (ethereum-lisp.core::chain-store-prepared-payload-record-rlp
               prepared-payload)))
           (let ((database (make-file-key-value-database path)))
             (is (eq target
                     (chain-store-import-from-kv target database))))
           (is (chain-store-known-block target (block-hash known-block)))
           (is (not (chain-store-prepared-payload target payload-id)))
           (is (not
                (chain-store-prepared-payload target target-payload-id))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-drops-invalid-prepared-payload-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-invalid-prepared-import-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (payload-id #(2 0 0 0 0 0 0 1))
         (invalid-block
           (make-block
            :header
            (make-block-header :number 9
                               :timestamp 14
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (prepared-payload
           (make-engine-prepared-payload
            :payload-id payload-id
            :version 2
            :block invalid-block)))
    (unwind-protect
         (progn
           (ethereum-lisp.core::engine-payload-store-mark-invalid
            source invalid-block)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :prepared-payload
              (ensure-byte-vector payload-id)
              (ethereum-lisp.core::chain-store-prepared-payload-record-rlp
               prepared-payload)))
           (let ((database (make-file-key-value-database path)))
             (is (eq target
                     (chain-store-import-from-kv target database))))
           (is (ethereum-lisp.core::engine-payload-store-invalid-block
                target
                (block-hash invalid-block)))
           (is (not (chain-store-prepared-payload target payload-id))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-put-prepared-payload-rejects-version-id-mismatch
  (let* ((store (make-engine-payload-memory-store))
         (block
           (make-block
            :header
            (make-block-header :number 9
                               :timestamp 14
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (valid-payload
           (make-engine-prepared-payload
            :payload-id #(3 0 0 0 0 0 0 1)
            :version 3
            :block block))
         (mismatched-payload
           (make-engine-prepared-payload
            :payload-id #(5 0 0 0 0 0 0 2)
            :version 3
            :block block)))
    (is (eq valid-payload
            (chain-store-put-prepared-payload store valid-payload)))
    (signals block-validation-error
      (chain-store-put-prepared-payload store mismatched-payload))
    (is (chain-store-prepared-payload store #(3 0 0 0 0 0 0 1)))
    (is (not (chain-store-prepared-payload store #(5 0 0 0 0 0 0 2))))))

(deftest chain-store-put-prepared-payload-validates-blobs-bundle
  (let* ((store (make-engine-payload-memory-store))
         (block
           (make-block
            :header
            (make-block-header :number 9
                               :timestamp 14
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (valid-payload-id #(5 0 0 0 0 0 0 1))
         (non-sidecar-payload-id #(5 0 0 0 0 0 0 2))
         (non-byte-payload-id #(5 0 0 0 0 0 0 3))
         (valid-payload
           (make-engine-prepared-payload
            :payload-id valid-payload-id
            :version 5
            :block block
            :blobs-bundle
            (make-blob-sidecar
             :blobs (list #(#x01 #x02))
             :commitments (list #(#x03))
             :proofs (list #(#x04)))))
         (non-sidecar-payload
           (make-engine-prepared-payload
            :payload-id non-sidecar-payload-id
            :version 5
            :block block
            :blobs-bundle "not-a-sidecar"))
         (non-byte-payload
           (make-engine-prepared-payload
            :payload-id non-byte-payload-id
            :version 5
            :block block
            :blobs-bundle
            (make-blob-sidecar
             :blobs (list (vector :not-a-byte))
             :commitments '()
             :proofs '()))))
    (is (eq valid-payload
            (chain-store-put-prepared-payload store valid-payload)))
    (signals block-validation-error
      (chain-store-put-prepared-payload store non-sidecar-payload))
    (signals block-validation-error
      (chain-store-put-prepared-payload store non-byte-payload))
    (is (chain-store-prepared-payload store valid-payload-id))
    (is (not (chain-store-prepared-payload store non-sidecar-payload-id)))
    (is (not (chain-store-prepared-payload store non-byte-payload-id)))))

(deftest chain-store-put-prepared-payload-copies-cache-entry
  (let* ((store (make-engine-payload-memory-store))
         (payload-id #(5 0 0 0 0 0 0 1))
         (original-extra-data #(#x01 #x02))
         (blob (ensure-byte-vector '(#x03 #x04)))
         (commitment (ensure-byte-vector '(#x05 #x06)))
         (proof (ensure-byte-vector '(#x07 #x08)))
         (block
           (make-block
            :header
            (make-block-header :number 9
                               :timestamp 14
                               :extra-data original-extra-data
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (sidecar
           (make-blob-sidecar
            :blobs (list blob)
            :commitments (list commitment)
            :proofs (list proof)))
         (prepared-payload
           (make-engine-prepared-payload
            :payload-id payload-id
            :version 5
            :block block
            :blobs-bundle sidecar)))
    (chain-store-put-prepared-payload store prepared-payload)
    (setf (block-header-extra-data (block-header block)) #(#xff)
          (aref blob 0) #xaa
          (aref commitment 0) #xbb
          (aref proof 0) #xcc)
    (let* ((stored
             (chain-store-prepared-payload store payload-id))
           (stored-block
             (ethereum-lisp.core::engine-prepared-payload-block stored))
           (stored-bundle
             (ethereum-lisp.core::engine-prepared-payload-blobs-bundle stored)))
      (is stored)
      (is (not (eq prepared-payload stored)))
      (is (not (eq block stored-block)))
      (is (bytes= original-extra-data
                  (block-header-extra-data (block-header stored-block))))
      (is (bytes= #(#x03 #x04)
                  (first (blob-sidecar-blobs stored-bundle))))
      (is (bytes= #(#x05 #x06)
                  (first (blob-sidecar-commitments stored-bundle))))
      (is (bytes= #(#x07 #x08)
                  (first (blob-sidecar-proofs stored-bundle))))
      (setf (block-header-extra-data (block-header stored-block)) #(#xee)
            (aref (first (blob-sidecar-blobs stored-bundle)) 0) #xdd
            (aref (first (blob-sidecar-commitments stored-bundle)) 0) #xee
            (aref (first (blob-sidecar-proofs stored-bundle)) 0) #xff))
    (let* ((stored
             (chain-store-prepared-payload store payload-id))
           (stored-block
             (ethereum-lisp.core::engine-prepared-payload-block stored))
           (stored-bundle
             (ethereum-lisp.core::engine-prepared-payload-blobs-bundle stored)))
      (is stored)
      (is (bytes= original-extra-data
                  (block-header-extra-data (block-header stored-block))))
      (is (bytes= #(#x03 #x04)
                  (first (blob-sidecar-blobs stored-bundle))))
      (is (bytes= #(#x05 #x06)
                  (first (blob-sidecar-commitments stored-bundle))))
      (is (bytes= #(#x07 #x08)
                  (first (blob-sidecar-proofs stored-bundle)))))))

(deftest chain-store-import-from-kv-rejects-corrupt-prepared-payload-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-prepared-payload-corrupt-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (source-payload-id #(5 0 0 0 0 0 0 1))
         (replacement-payload-id #(5 0 0 0 0 0 0 2))
         (target-payload-id #(5 0 0 0 0 0 0 3))
         (source-block
           (make-block
            :header
            (make-block-header :number 9
                               :timestamp 14
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (target-block
           (make-block
            :header
            (make-block-header :number 10
                               :timestamp 15
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (source-payload
           (make-engine-prepared-payload
            :payload-id source-payload-id
            :version 5
            :block source-block))
         (replacement-payload
           (make-engine-prepared-payload
            :payload-id replacement-payload-id
            :version 5
            :block source-block))
         (target-payload
           (make-engine-prepared-payload
            :payload-id target-payload-id
            :version 5
            :block target-block)))
    (unwind-protect
         (progn
           (chain-store-put-prepared-payload target target-payload)
           (chain-store-put-prepared-payload source source-payload)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :prepared-payload
              (ensure-byte-vector source-payload-id)
              (ethereum-lisp.core::chain-store-prepared-payload-record-rlp
               replacement-payload)))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (chain-store-prepared-payload target target-payload-id))
           (is (not
                (chain-store-prepared-payload target source-payload-id))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-rejects-prepared-payload-version-id-mismatch
  (let* ((database (make-memory-key-value-database))
         (target (make-engine-payload-memory-store))
         (target-payload-id #(5 0 0 0 0 0 0 3))
         (mismatched-payload-id #(5 0 0 0 0 0 0 4))
         (block
           (make-block
            :header
            (make-block-header :number 9
                               :timestamp 14
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (target-payload
           (make-engine-prepared-payload
            :payload-id target-payload-id
            :version 5
            :block block))
         (mismatched-payload
           (make-engine-prepared-payload
            :payload-id mismatched-payload-id
            :version 3
            :block block)))
    (chain-store-put-prepared-payload target target-payload)
    (kv-put-chain-record
     database
     :prepared-payload
     (ensure-byte-vector mismatched-payload-id)
     (ethereum-lisp.core::chain-store-prepared-payload-record-rlp
      mismatched-payload))
    (signals block-validation-error
      (chain-store-import-from-kv target database))
    (is (chain-store-prepared-payload target target-payload-id))
    (is (not
         (chain-store-prepared-payload target mismatched-payload-id)))))

