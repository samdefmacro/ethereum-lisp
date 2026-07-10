(in-package #:ethereum-lisp.evm.internal)

(defun kzg-point-evaluation-return-value ()
  (concat-bytes
   (integer-to-fixed-bytes +bls-field-elements-per-blob+ 32)
   (integer-to-fixed-bytes +bls-field-modulus+ 32)))

(defun run-kzg-point-evaluation-precompile (input)
  (let ((input (ensure-byte-vector input))
        (gas +kzg-point-evaluation-gas+))
    (unless (= (length input) +kzg-point-evaluation-input-size+)
      (fail-precompile gas "Invalid KZG point evaluation input length"))
    (let* ((versioned-hash (subseq input 0 32))
           (z (subseq input 32 64))
           (y (subseq input 64 96))
           (commitment (subseq input 96 144))
           (proof (subseq input 144 192))
           (computed-versioned-hash
             (hash32-bytes (kzg-commitment-to-versioned-hash commitment))))
      (unless (bytes= versioned-hash computed-versioned-hash)
        (fail-precompile gas "Mismatched KZG commitment versioned hash"))
      (handler-case
          (progn
            (verify-kzg-point-proof commitment z y proof)
            (values (kzg-point-evaluation-return-value) gas))
        (error (condition)
          (fail-precompile gas "~A" condition))))))
