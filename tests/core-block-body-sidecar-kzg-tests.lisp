(in-package #:ethereum-lisp.test)

(deftest kzg-package-boundary
  (let ((kzg (find-package '#:ethereum-lisp.kzg))
        (transactions (find-package '#:ethereum-lisp.transactions))
        (consensus (find-package '#:ethereum-lisp.consensus))
        (core (find-package '#:ethereum-lisp.core)))
    (is (not (member core (package-use-list kzg))))
    (is (member transactions (package-use-list kzg)))
    (is (member consensus (package-use-list kzg)))
    (dolist (name '("VERIFY-KZG-BLOB-PROOF"
                    "CONFIGURE-KZG-PROOF-COMMAND-VERIFIERS"
                    "VALIDATE-BLOB-SIDECAR-FIELDS"))
      (multiple-value-bind (kzg-symbol kzg-status)
          (find-symbol name kzg)
        (multiple-value-bind (core-symbol core-status)
            (find-symbol name core)
          (is (eq :external kzg-status))
          (is (eq :external core-status))
          (is (eq kzg-symbol core-symbol)))))
    (dolist (name '("EXECUTABLE-DATA" "CHAIN-STORE-CHECKPOINT"))
      (multiple-value-bind (symbol status)
          (find-symbol name kzg)
        (is (null symbol))
        (is (null status))))))

(deftest blob-sidecar-field-validation
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob (make-byte-vector +blob-byte-size+))
         (commitment (make-byte-vector +kzg-commitment-size+))
         (proof (make-byte-vector +kzg-proof-size+))
         (versioned-hash (kzg-commitment-to-versioned-hash commitment))
         (transaction (make-blob-transaction
                       :to address
                       :blob-versioned-hashes (list versioned-hash)))
         (sidecar (make-blob-sidecar :blobs (list blob)
                                     :commitments (list commitment)
                                     :proofs (list proof))))
    (is (validate-blob-sidecar-fields sidecar :transaction transaction))
    (is (bytes= (hash32-bytes versioned-hash)
                (hash32-bytes (first (blob-sidecar-versioned-hashes sidecar)))))
    (signals block-validation-error
      (validate-blob-sidecar-fields
       sidecar
       :transaction transaction
       :require-proof-verification t))
    (let ((observed nil))
      (let ((*kzg-blob-proof-verifier*
              (lambda (verified-blob verified-commitment verified-proof)
                (setf observed
                      (list verified-blob verified-commitment verified-proof))
                t)))
        (is (kzg-blob-proof-verification-available-p))
        (is (validate-blob-sidecar-fields
             sidecar
             :transaction transaction
             :require-proof-verification t)))
      (is (bytes= blob (first observed)))
      (is (bytes= commitment (second observed)))
      (is (bytes= proof (third observed))))
    (let ((*kzg-blob-proof-verifier*
            (lambda (verified-blob verified-commitment verified-proof)
              (declare (ignore verified-blob verified-commitment
                               verified-proof))
              nil)))
      (signals block-validation-error
        (validate-blob-sidecar-fields
         sidecar
         :transaction transaction
         :require-proof-verification t)))
    (signals block-validation-error
      (validate-blob-sidecar-fields
       (make-blob-sidecar :blobs (list blob)
                          :commitments (list commitment)
                          :proofs '())
       :transaction transaction))
    (signals block-validation-error
      (validate-blob-sidecar-fields
       (make-blob-sidecar :blobs (list #())
                          :commitments (list commitment)
                          :proofs (list proof))))
    (let ((invalid-blob (copy-seq blob))
          (called nil))
      (replace invalid-blob
               (ethereum-lisp.crypto::integer-to-fixed-bytes
                ethereum-lisp.kzg:+kzg-field-modulus+
                32)
               :start1 0)
      (let ((*kzg-blob-proof-verifier*
              (lambda (verified-blob verified-commitment verified-proof)
                (declare (ignore verified-blob verified-commitment
                                 verified-proof))
                (setf called t)
                t)))
        (signals block-validation-error
          (validate-blob-sidecar-fields
           (make-blob-sidecar :blobs (list invalid-blob)
                              :commitments (list commitment)
                              :proofs (list proof))
           :require-proof-verification t)))
      (is (null called)))
    (signals block-validation-error
      (validate-blob-sidecar-fields
       (make-blob-sidecar :blobs (list blob)
                          :commitments (list #())
                          :proofs (list proof))))
    (signals block-validation-error
      (validate-blob-sidecar-fields
       (make-blob-sidecar :blobs (list blob)
                          :commitments (list commitment)
                          :proofs (list #()))))
    (let ((other-commitment (copy-seq commitment)))
      (setf (aref other-commitment 0) 1)
      (signals block-validation-error
        (validate-blob-sidecar-fields
         (make-blob-sidecar :blobs (list blob)
                            :commitments (list other-commitment)
                            :proofs (list proof))
         :transaction transaction)))))

(deftest kzg-command-verifier-adapter
  (:layer :integration :module :kzg :launches-processes t)
  (let* ((suffix (format nil "~A-~A" (get-universal-time) (random 1000000)))
         (script-path
           (merge-pathnames
            (format nil "ethereum-lisp-kzg-verifier-~A.sh" suffix)
            (uiop:temporary-directory)))
         (sleep-script-path
           (merge-pathnames
            (format nil "ethereum-lisp-kzg-verifier-sleep-~A.sh" suffix)
            (uiop:temporary-directory)))
         (log-path
           (merge-pathnames
            (format nil "ethereum-lisp-kzg-verifier-~A.log" suffix)
            (uiop:temporary-directory)))
         (blob (make-byte-vector +blob-byte-size+))
         (commitment (make-byte-vector +kzg-commitment-size+))
         (proof (make-byte-vector +kzg-proof-size+))
         (z (make-byte-vector ethereum-lisp.kzg:+kzg-field-element-size+))
         (y (make-byte-vector ethereum-lisp.kzg:+kzg-field-element-size+))
         (old-point-verifier *kzg-point-proof-verifier*)
         (old-blob-verifier *kzg-blob-proof-verifier*))
    (labels ((file-contents (path)
               (with-open-file (stream path :direction :input)
                 (let ((contents (make-string (file-length stream))))
                   (read-sequence contents stream)
                   contents))))
      (unwind-protect
           (progn
             (with-open-file (stream script-path
                                     :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (format stream "#!/bin/sh~%")
               (format stream "log=\"$1\"~%")
               (format stream "verdict=\"$2\"~%")
               (format stream "shift 2~%")
               (format stream "case \"$1\" in~%")
               (format stream "  point) printf 'point %s %s %s %s\\n' \"${#2}\" \"${#3}\" \"${#4}\" \"${#5}\" > \"$log\" ;;~%")
               (format stream "  blob) printf 'blob %s %s %s\\n' \"${#2}\" \"${#3}\" \"${#4}\" > \"$log\" ;;~%")
               (format stream "  *) printf 'unknown\\n' > \"$log\" ;;~%")
               (format stream "esac~%")
               (format stream "if [ \"$verdict\" = accept ]; then echo true; else echo false; fi~%"))
             (with-open-file (stream sleep-script-path
                                     :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (format stream "#!/bin/sh~%")
               (format stream "sleep 2~%")
               (format stream "echo true~%"))
             (configure-kzg-proof-command-verifiers
              (list "sh" (namestring script-path)
                    (namestring log-path)
                    "accept"))
             (is (kzg-proof-verification-available-p))
             (is (verify-kzg-point-proof commitment z y proof))
             (is (string= (format nil "point 98 66 66 98~%")
                          (file-contents log-path)))
             (is (verify-kzg-blob-proof blob commitment proof))
             (is (string=
                  (format nil "blob ~D 98 98~%"
                          (+ 2 (* 2 +blob-byte-size+)))
                  (file-contents log-path)))
             (configure-kzg-proof-command-verifiers
              (list "sh" (namestring script-path)
                    (namestring log-path)
                    "reject"))
             (signals error
               (verify-kzg-point-proof commitment z y proof))
             (signals error
               (verify-kzg-blob-proof blob commitment proof))
             (let ((ethereum-lisp.kzg:*kzg-verifier-command-timeout-seconds*
                     0))
               (configure-kzg-proof-command-verifiers
                (list "sh" (namestring sleep-script-path)))
               (signals error
                 (verify-kzg-point-proof commitment z y proof)))
             (signals error
               (make-kzg-point-proof-command-verifier '())))
        (setf *kzg-point-proof-verifier* old-point-verifier
              *kzg-blob-proof-verifier* old-blob-verifier)
        (when (probe-file script-path)
          (delete-file script-path))
        (when (probe-file sleep-script-path)
          (delete-file sleep-script-path))
        (when (probe-file log-path)
          (delete-file log-path))))))

(deftest kzg-go-ethereum-command-verifier-replays-canonical-vectors
  (:layer :integration :module :kzg :launches-processes t)
  (let ((script (repo-kzg-verifier-command)))
    (let* ((valid-blob
             (let ((blob (make-byte-vector +blob-byte-size+))
                   (field-element
                     (ethereum-lisp.crypto::integer-to-fixed-bytes 2 32)))
               (loop for start below +blob-byte-size+ by 32
                     do (replace blob field-element :start1 start))
               blob))
           (valid-commitment
             (hex-to-bytes
              "0xa572cbea904d67468808c8eb50a9450c9721db309128012543902d0ac358a62ae28f75bb8f1c7c42c39a8c5529bf0f4e"))
           (valid-point-z
             (hex-to-bytes
              "0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000000"))
           (valid-point-y
             (hex-to-bytes
              "0x0000000000000000000000000000000000000000000000000000000000000002"))
           (valid-proof
             (hex-to-bytes
              "0xc00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"))
           (invalid-point-commitment
             (hex-to-bytes
              "0xb49d88afcd7f6c61a8ea69eff5f609d2432b47e7e4cd50b02cdddb4e0c1460517e8df02e4e64dc55e3d8ca192d57193a"))
           (invalid-point-z
             (hex-to-bytes
              "0x0000000000000000000000000000000000000000000000000000000000000001"))
           (invalid-point-y
             (hex-to-bytes
              "0x443e7af5274b52214ea6c775908c54519fea957eecd98069165a8b771082fd51"))
           (invalid-point-proof
             (hex-to-bytes
              "0xa7de1e32bb336b85e42ff5028167042188317299333f091dd88675e84a550577bfa564b2f57cd2498e2acf875e0aaa40"))
           (invalid-blob-proof
             (hex-to-bytes
              "0x97f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb"))
           (old-point-verifier *kzg-point-proof-verifier*)
           (old-blob-verifier *kzg-blob-proof-verifier*))
      (unwind-protect
           (progn
             ;; Sources: go-eth-kzg v1.5.0 kzg-mainnet
             ;; verify_kzg_proof_case_correct_proof_395cf6d697d1a743,
             ;; verify_kzg_proof_case_incorrect_proof_444b73ff54a19b44,
             ;; verify_blob_kzg_proof_case_correct_proof_a87a4e636e0f58fb,
             ;; verify_blob_kzg_proof_case_incorrect_proof_a87a4e636e0f58fb.
             (configure-kzg-proof-command-verifiers (namestring script))
             (is (verify-kzg-point-proof
                  valid-commitment
                  valid-point-z
                  valid-point-y
                  valid-proof))
             (signals error
               (verify-kzg-point-proof
                invalid-point-commitment
                invalid-point-z
                invalid-point-y
                invalid-point-proof))
             (is (verify-kzg-blob-proof
                  valid-blob
                  valid-commitment
                  valid-proof))
             (signals error
               (verify-kzg-blob-proof
                valid-blob
                valid-commitment
                invalid-blob-proof)))
        (setf *kzg-point-proof-verifier* old-point-verifier
              *kzg-blob-proof-verifier* old-blob-verifier)))))

(deftest blob-sidecar-field-validation-replays-real-kzg-vector
  (:layer :integration :module :kzg :launches-processes t)
  (let ((script (repo-kzg-verifier-command)))
    (let* ((blob
             (let ((blob (make-byte-vector +blob-byte-size+))
                   (field-element
                     (ethereum-lisp.crypto::integer-to-fixed-bytes 2 32)))
               (loop for start below +blob-byte-size+ by 32
                     do (replace blob field-element :start1 start))
               blob))
           (commitment
             (hex-to-bytes
              "0xa572cbea904d67468808c8eb50a9450c9721db309128012543902d0ac358a62ae28f75bb8f1c7c42c39a8c5529bf0f4e"))
           (valid-proof
             (hex-to-bytes
              "0xc00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"))
           (invalid-proof
             (hex-to-bytes
              "0x97f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb"))
           (versioned-hash
             (kzg-commitment-to-versioned-hash commitment))
           (transaction
             (make-blob-transaction
              :to (address-from-hex
                   "0x0000000000000000000000000000000000000001")
              :blob-versioned-hashes (list versioned-hash)))
           (old-point-verifier *kzg-point-proof-verifier*)
           (old-blob-verifier *kzg-blob-proof-verifier*))
      (unwind-protect
           (progn
             (configure-kzg-proof-command-verifiers (namestring script))
             (is (validate-blob-sidecar-fields
                  (make-blob-sidecar
                   :blobs (list blob)
                   :commitments (list commitment)
                   :proofs (list valid-proof))
                  :transaction transaction
                  :require-proof-verification t))
             (signals block-validation-error
               (validate-blob-sidecar-fields
                (make-blob-sidecar
                 :blobs (list blob)
                 :commitments (list commitment)
                 :proofs (list invalid-proof))
                :transaction transaction
                :require-proof-verification t)))
        (setf *kzg-point-proof-verifier* old-point-verifier
              *kzg-blob-proof-verifier* old-blob-verifier)))))
