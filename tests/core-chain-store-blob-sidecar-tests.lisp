(in-package #:ethereum-lisp.test)

(deftest chain-store-export-import-kv-restores-blob-sidecars
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-blob-sidecar-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (restored (make-engine-payload-memory-store))
         (blob (make-byte-vector +blob-byte-size+))
         (commitment (make-byte-vector +kzg-commitment-size+))
         (proofs
           (loop for index below +cell-proofs-per-blob+
                 collect
                 (let ((proof (make-byte-vector +kzg-proof-size+)))
                   (setf (aref proof 0) index)
                   proof)))
         sidecar
         versioned-hash
         versioned-hash-id)
    (setf (aref blob 0) #xaa
          (aref commitment 0) #xbb
          sidecar (make-blob-sidecar
                   :blobs (list blob)
                   :commitments (list commitment)
                   :proofs proofs)
          versioned-hash (first (blob-sidecar-versioned-hashes sidecar))
          versioned-hash-id (hash32-bytes versioned-hash))
    (unwind-protect
         (progn
           (ethereum-lisp.chain-store:engine-payload-store-put-blob-sidecar
            source sidecar)
           (let ((database (make-file-key-value-database path)))
             (node-store-export-to-kv source database))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record
                  database :blob-sidecar versioned-hash-id)
               (is present-p)
               (is (bytes= record
                           (ethereum-lisp.node-store.persistence::chain-store-blob-sidecar-record-rlp
                            (ethereum-lisp.chain-store:engine-payload-store-blob-and-proofs-v1
                             source versioned-hash))))))
           (let ((database (make-file-key-value-database path)))
             (is (eq restored
                     (node-store-import-from-kv restored database))))
           (let ((restored-blob
                   (ethereum-lisp.chain-store:engine-payload-store-blob-and-proofs-v2
                    restored
                    versioned-hash)))
             (is restored-blob)
             (is (bytes= blob
                         (ethereum-lisp.chain-store.model:engine-blob-and-proofs-blob
                          restored-blob)))
             (is (bytes= commitment
                         (ethereum-lisp.chain-store.model:engine-blob-and-proofs-commitment
                          restored-blob)))
             (is (bytes= (first proofs)
                         (ethereum-lisp.chain-store.model:engine-blob-and-proofs-proof
                          restored-blob)))
             (is (= +cell-proofs-per-blob+
                    (length
                     (ethereum-lisp.chain-store.model:engine-blob-and-proofs-cell-proofs
                      restored-blob))))
             (is (bytes= (car (last proofs))
                         (car
                          (last
                           (ethereum-lisp.chain-store.model:engine-blob-and-proofs-cell-proofs
                            restored-blob))))))
           (let ((database (make-file-key-value-database path)))
             (node-store-export-to-kv
              (make-engine-payload-memory-store)
              database))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record
                  database :blob-sidecar versioned-hash-id :missing)
               (is (eq :missing record))
               (is (not present-p)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest engine-payload-store-copies-blob-sidecar-lookups
  (let* ((store (make-engine-payload-memory-store))
         (blob (make-byte-vector +blob-byte-size+))
         (commitment (make-byte-vector +kzg-commitment-size+))
         (proofs
           (loop for index below +cell-proofs-per-blob+
                 collect
                 (let ((proof (make-byte-vector +kzg-proof-size+)))
                   (setf (aref proof 0) index)
                   proof)))
         (sidecar nil)
         (versioned-hash nil))
    (setf (aref blob 0) #xaa
          (aref commitment 0) #xbb
          sidecar (make-blob-sidecar
                   :blobs (list blob)
                   :commitments (list commitment)
                   :proofs proofs)
          versioned-hash (first (blob-sidecar-versioned-hashes sidecar)))
    (ethereum-lisp.chain-store:engine-payload-store-put-blob-sidecar store sidecar)
    (let ((lookup
            (ethereum-lisp.chain-store:engine-payload-store-blob-and-proofs-v2
             store
             versioned-hash)))
      (setf (aref (ethereum-lisp.chain-store.model:engine-blob-and-proofs-blob lookup) 0)
            #x11)
      (setf (aref (ethereum-lisp.chain-store.model:engine-blob-and-proofs-commitment
                   lookup)
                  0)
            #x22)
      (setf (aref (ethereum-lisp.chain-store.model:engine-blob-and-proofs-proof lookup)
                  0)
            #x33)
      (setf (aref
             (first
              (ethereum-lisp.chain-store.model:engine-blob-and-proofs-cell-proofs lookup))
             0)
            #x44))
    (let ((lookup
            (ethereum-lisp.chain-store:engine-payload-store-blob-and-proofs-v2
             store
             versioned-hash)))
      (is (= #xaa
             (aref (ethereum-lisp.chain-store.model:engine-blob-and-proofs-blob lookup)
                   0)))
      (is (= #xbb
             (aref (ethereum-lisp.chain-store.model:engine-blob-and-proofs-commitment
                    lookup)
                   0)))
      (is (= 0
             (aref (ethereum-lisp.chain-store.model:engine-blob-and-proofs-proof lookup)
                   0)))
      (is (= 0
             (aref
              (first
               (ethereum-lisp.chain-store.model:engine-blob-and-proofs-cell-proofs lookup))
              0))))))

(deftest node-store-import-from-kv-rejects-corrupt-blob-sidecar-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-blob-sidecar-corrupt-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (target-blob (make-byte-vector +blob-byte-size+))
         (target-commitment (make-byte-vector +kzg-commitment-size+))
         (target-proof (make-byte-vector +kzg-proof-size+))
         (source-blob (make-byte-vector +blob-byte-size+))
         (source-commitment (make-byte-vector +kzg-commitment-size+))
         (source-proof (make-byte-vector +kzg-proof-size+))
         target-sidecar
         target-versioned-hash
         source-sidecar
         source-versioned-hash)
    (setf (aref target-blob 0) #x11
          (aref target-commitment 0) #x22
          (aref target-proof 0) #x33
          (aref source-blob 0) #x44
          (aref source-commitment 0) #x55
          (aref source-proof 0) #x66
          target-sidecar (make-blob-sidecar
                          :blobs (list target-blob)
                          :commitments (list target-commitment)
                          :proofs (list target-proof))
          target-versioned-hash
          (first (blob-sidecar-versioned-hashes target-sidecar))
          source-sidecar (make-blob-sidecar
                          :blobs (list source-blob)
                          :commitments (list source-commitment)
                          :proofs (list source-proof))
          source-versioned-hash
          (first (blob-sidecar-versioned-hashes source-sidecar)))
    (unwind-protect
         (progn
           (ethereum-lisp.chain-store:engine-payload-store-put-blob-sidecar
            target target-sidecar)
           (ethereum-lisp.chain-store:engine-payload-store-put-blob-sidecar
            source source-sidecar)
           (let ((database (make-file-key-value-database path)))
             (node-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :blob-sidecar
              (hash32-bytes source-versioned-hash)
              (rlp-encode
               (make-rlp-list
                (make-byte-vector 3 :initial-element 1)
                source-proof
                (make-rlp-list)))))
           (signals block-validation-error
             (node-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (ethereum-lisp.chain-store:engine-payload-store-blob-and-proofs-v1
                target
                target-versioned-hash))
           (is (not
                (ethereum-lisp.chain-store:engine-payload-store-blob-and-proofs-v1
                 target
                 source-versioned-hash))))
      (when (probe-file path)
        (delete-file path)))))

(deftest node-store-import-from-kv-rejects-blob-sidecar-key-mismatch
  (let* ((database (make-memory-key-value-database))
         (target (make-engine-payload-memory-store))
         (target-blob (make-byte-vector +blob-byte-size+))
         (target-commitment (make-byte-vector +kzg-commitment-size+))
         (target-proof (make-byte-vector +kzg-proof-size+))
         (source-blob (make-byte-vector +blob-byte-size+))
         (source-commitment (make-byte-vector +kzg-commitment-size+))
         (source-proof (make-byte-vector +kzg-proof-size+))
         target-sidecar
         target-versioned-hash
         source-sidecar
         source-versioned-hash)
    (setf (aref target-blob 0) #x11
          (aref target-commitment 0) #x22
          (aref target-proof 0) #x33
          (aref source-blob 0) #x44
          (aref source-commitment 0) #x55
          (aref source-proof 0) #x66
          target-sidecar (make-blob-sidecar
                          :blobs (list target-blob)
                          :commitments (list target-commitment)
                          :proofs (list target-proof))
          target-versioned-hash
          (first (blob-sidecar-versioned-hashes target-sidecar))
          source-sidecar (make-blob-sidecar
                          :blobs (list source-blob)
                          :commitments (list source-commitment)
                          :proofs (list source-proof))
          source-versioned-hash
          (first (blob-sidecar-versioned-hashes source-sidecar)))
    (ethereum-lisp.chain-store:engine-payload-store-put-blob-sidecar
     target target-sidecar)
    (let ((source-cache (make-engine-payload-memory-store)))
      (ethereum-lisp.chain-store:engine-payload-store-put-blob-sidecar
       source-cache source-sidecar)
      (kv-put-chain-record
       database
       :blob-sidecar
       (hash32-bytes target-versioned-hash)
       (ethereum-lisp.node-store.persistence::chain-store-blob-sidecar-record-rlp
        (ethereum-lisp.chain-store:engine-payload-store-blob-and-proofs-v1
         source-cache source-versioned-hash))))
    (signals block-validation-error
      (node-store-import-from-kv target database))
    (let ((target-cache
            (ethereum-lisp.chain-store:engine-payload-store-blob-and-proofs-v1
             target target-versioned-hash)))
      (is target-cache)
      (is (bytes= target-blob
                  (ethereum-lisp.chain-store.model:engine-blob-and-proofs-blob
                   target-cache)))
      (is (bytes= target-commitment
                  (ethereum-lisp.chain-store.model:engine-blob-and-proofs-commitment
                   target-cache))))
    (is (not
         (ethereum-lisp.chain-store:engine-payload-store-blob-and-proofs-v1
          target source-versioned-hash)))))

