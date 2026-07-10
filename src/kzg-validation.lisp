(in-package #:ethereum-lisp.kzg)

(defconstant +blob-byte-size+ +blob-gas-per-blob+)
(defconstant +kzg-proof-size+ +kzg-commitment-size+)
(defconstant +kzg-field-element-size+ 32)
(defconstant +kzg-blob-field-elements-per-blob+ 4096)
(defconstant +kzg-field-modulus+
  #x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001)
(defconstant +cell-proofs-per-blob+ 128)

(defun validate-kzg-field-element (bytes label)
  (let ((bytes (ensure-byte-vector bytes)))
    (unless (= +kzg-field-element-size+ (length bytes))
      (error "~A must be exactly ~D bytes" label +kzg-field-element-size+))
    (unless (< (bytes-to-integer bytes) +kzg-field-modulus+)
      (error "~A must be less than BLS field modulus" label))
    bytes))

(defun validate-kzg-blob-field-elements (blob)
  (let ((blob (ensure-byte-vector blob)))
    (unless (= +blob-byte-size+ (length blob))
      (error "Blob must be exactly ~D bytes" +blob-byte-size+))
    (unless (= +kzg-blob-field-elements-per-blob+
               (/ (length blob) +kzg-field-element-size+))
      (error "Blob must contain exactly ~D field elements"
             +kzg-blob-field-elements-per-blob+))
    (loop for start below (length blob) by +kzg-field-element-size+
          for index from 0
          do (validate-kzg-field-element
              (subseq blob start (+ start +kzg-field-element-size+))
              (format nil "Blob field element ~D" index))))
  t)

(defun verify-kzg-point-proof (commitment z y proof)
  (unless (kzg-point-proof-verification-available-p)
    (error "KZG point proof verification is not available"))
  (let ((commitment (ensure-byte-vector commitment))
        (z (ensure-byte-vector z))
        (y (ensure-byte-vector y))
        (proof (ensure-byte-vector proof)))
    (unless (= +kzg-commitment-size+ (length commitment))
      (error "KZG commitment must be exactly ~D bytes" +kzg-commitment-size+))
    (validate-kzg-field-element z "KZG point z")
    (validate-kzg-field-element y "KZG point y")
    (unless (= +kzg-proof-size+ (length proof))
      (error "KZG proof must be exactly ~D bytes" +kzg-proof-size+))
    (unless (funcall *kzg-point-proof-verifier* commitment z y proof)
      (error "KZG point proof verification failed")))
  t)

(defun verify-kzg-blob-proof (blob commitment proof)
  (unless (kzg-blob-proof-verification-available-p)
    (error "KZG blob proof verification is not available"))
  (let ((blob (ensure-byte-vector blob))
        (commitment (ensure-byte-vector commitment))
        (proof (ensure-byte-vector proof)))
    (validate-kzg-blob-field-elements blob)
    (unless (= +kzg-commitment-size+ (length commitment))
      (error "KZG commitment must be exactly ~D bytes" +kzg-commitment-size+))
    (unless (= +kzg-proof-size+ (length proof))
      (error "KZG proof must be exactly ~D bytes" +kzg-proof-size+))
    (unless (funcall *kzg-blob-proof-verifier* blob commitment proof)
      (error "KZG blob proof verification failed")))
  t)

(defun validate-blob-sidecar-kzg-proofs (sidecar)
  (unless (kzg-blob-proof-verification-available-p)
    (block-validation-fail
     "KZG proof verification is not available; blob sidecars are shape-checked only"))
  (let ((blobs (blob-sidecar-blobs sidecar))
        (commitments (blob-sidecar-commitments sidecar))
        (proofs (blob-sidecar-proofs sidecar)))
    (unless (= (length proofs) (length blobs))
      (block-validation-fail
       "KZG cell proof verification is not available; blob proof verification requires one proof per blob"))
    (handler-case
        (loop for blob in blobs
              for commitment in commitments
              for proof in proofs
              do (verify-kzg-blob-proof blob commitment proof))
      (error (condition)
        (block-validation-fail "~A" condition))))
  t)

(defun validate-blob-sidecar-fields
    (sidecar &key transaction require-proof-verification)
  (let* ((blobs (blob-sidecar-blobs sidecar))
         (commitments (blob-sidecar-commitments sidecar))
         (proofs (blob-sidecar-proofs sidecar))
         (blob-count (length blobs))
         (commitment-count (length commitments))
         (proof-count (length proofs)))
    (unless (= blob-count commitment-count)
      (block-validation-fail
       "Blob sidecar blob and commitment counts must match"))
    (unless (or (= proof-count blob-count)
                (= proof-count (* blob-count +cell-proofs-per-blob+)))
      (block-validation-fail
       "Blob sidecar proof count must match blobs or cell proofs per blob"))
    (dolist (blob blobs)
      (validate-sized-byte-vector blob +blob-byte-size+ "Blob")
      (handler-case
          (validate-kzg-blob-field-elements blob)
        (error (condition)
          (block-validation-fail "~A" condition))))
    (dolist (commitment commitments)
      (validate-sized-byte-vector commitment +kzg-commitment-size+
                                  "KZG commitment"))
    (dolist (proof proofs)
      (validate-sized-byte-vector proof +kzg-proof-size+ "KZG proof"))
    (when transaction
      (unless (= blob-count (transaction-blob-count transaction))
        (block-validation-fail
         "Blob sidecar count does not match transaction blob hash count"))
      (loop for actual in (blob-sidecar-versioned-hashes sidecar)
            for expected across (transaction-blob-versioned-hashes transaction)
            unless (bytes= (hash32-bytes actual)
                           (blob-versioned-hash-bytes expected))
              do (block-validation-fail
                  "Blob sidecar commitment does not match transaction blob hash")))
    (when require-proof-verification
      (validate-blob-sidecar-kzg-proofs sidecar))
    t))
