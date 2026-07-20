(in-package #:ethereum-lisp.evm.internal)

(defun precompile-word-count (input)
  (ceiling (length (ensure-byte-vector input)) 32))

(defun precompile-required-gas (address input &optional rules)
  "Return the gas required by an active precompile without executing it.

NIL means the input has no computable up-front price (currently only a malformed
BLAKE2F input length); execution will report that input error without rounds."
  (let ((number (address-to-word address)))
    (when (active-precompile-address-p address rules)
      (case number
        (1 +ecrecover-gas+)
        (2 (+ +sha256-base-gas+
              (* +sha256-word-gas+ (precompile-word-count input))))
        (3 (+ +ripemd160-base-gas+
              (* +ripemd160-word-gas+ (precompile-word-count input))))
        (4 (+ +identity-base-gas+
              (* +identity-word-gas+ (precompile-word-count input))))
        (5 (modexp-precompile-required-gas input rules))
        (6 (bn254-add-gas rules))
        (7 (bn254-mul-gas rules))
        (8 (bn254-pairing-gas input rules))
        (9 (blake2f-precompile-required-gas input))
        (10 +kzg-point-evaluation-gas+)
        (256 +p256verify-gas+)
        (otherwise nil)))))

(defun run-p256verify-precompile (input)
  "EIP-7951 P256VERIFY. Input is exactly 160 bytes: h||r||s||qx||qy. Returns a
32-byte 1 for a valid signature and empty bytes otherwise, always at flat cost."
  (let ((input (ensure-byte-vector input)))
    (values
     (if (and (= (length input) 160)
              (secp256r1-verify
               (bytes-to-integer (subseq input 0 32))
               (bytes-to-integer (subseq input 32 64))
               (bytes-to-integer (subseq input 64 96))
               (bytes-to-integer (subseq input 96 128))
               (bytes-to-integer (subseq input 128 160))))
         (let ((output (make-byte-vector 32)))
           (setf (aref output 31) 1)
           output)
         (make-byte-vector 0))
     +p256verify-gas+)))

(defun ensure-precompile-upfront-gas (address input rules child-gas-limit)
  (let ((required-gas (precompile-required-gas address input rules)))
    (when (and required-gas (> required-gas child-gas-limit))
      (fail "Precompile out of gas"))))

(defun all-zero-bytes-p (bytes start end)
  (loop for i from start below end
        always (zerop (aref bytes i))))

(defun run-ecrecover-precompile (input)
  (let* ((padded (padded-data-slice input 0 128))
         (v-byte (aref padded 63))
         (v (- v-byte 27))
         (r (bytes-to-integer (subseq padded 64 96)))
         (s (bytes-to-integer (subseq padded 96 128))))
    (let ((address
            (and (all-zero-bytes-p padded 32 63)
                 (secp256k1-recover-address (subseq padded 0 32) v r s))))
      (if address
          (let ((output (make-byte-vector 32)))
            (replace output (address-bytes address) :start1 12)
            (values output +ecrecover-gas+))
          (values (make-byte-vector 0) +ecrecover-gas+)))))

(defun run-precompile (address input &optional rules)
  (let ((input (ensure-byte-vector input)))
    (case (address-to-word address)
      (1 (if (active-precompile-address-number-p 1 rules)
             (multiple-value-bind (output gas) (run-ecrecover-precompile input)
               (values output gas t))
             (values nil 0 nil)))
      (2 (if (active-precompile-address-number-p 2 rules)
             (values (sha256 input)
                     (+ +sha256-base-gas+
                        (* +sha256-word-gas+ (precompile-word-count input)))
                     t)
             (values nil 0 nil)))
      (3 (if (active-precompile-address-number-p 3 rules)
             (let ((output (make-byte-vector 32)))
               (replace output (ripemd160 input) :start1 12)
               (values output
                       (+ +ripemd160-base-gas+
                          (* +ripemd160-word-gas+
                             (precompile-word-count input)))
                       t))
             (values nil 0 nil)))
      (5 (if (active-precompile-address-number-p 5 rules)
             (multiple-value-bind (output gas)
                 (run-modexp-precompile input rules)
               (values output gas t))
             (values nil 0 nil)))
      (6 (if (active-precompile-address-number-p 6 rules)
             (multiple-value-bind (output gas)
                 (run-bn254-add-precompile input rules)
               (values output gas t))
             (values nil 0 nil)))
      (7 (if (active-precompile-address-number-p 7 rules)
             (multiple-value-bind (output gas)
                 (run-bn254-mul-precompile input rules)
               (values output gas t))
             (values nil 0 nil)))
      (8 (if (active-precompile-address-number-p 8 rules)
             (multiple-value-bind (output gas)
                 (run-bn254-pairing-precompile input rules)
               (values output gas t))
             (values nil 0 nil)))
      (9 (if (active-precompile-address-number-p 9 rules)
             (multiple-value-bind (output gas) (run-blake2f-precompile input)
               (values output gas t))
             (values nil 0 nil)))
      (10 (if (active-precompile-address-number-p 10 rules)
              (multiple-value-bind (output gas)
                  (run-kzg-point-evaluation-precompile input)
                (values output gas t))
              (values nil 0 nil)))
      (4 (if (active-precompile-address-number-p 4 rules)
             (values (subseq input 0)
                     (+ +identity-base-gas+
                        (* +identity-word-gas+ (precompile-word-count input)))
                     t)
             (values nil 0 nil)))
      (256 (if (active-precompile-address-number-p 256 rules)
               (multiple-value-bind (output gas)
                   (run-p256verify-precompile input)
                 (values output gas t))
               (values nil 0 nil)))
      (otherwise (values nil 0 nil)))))

(defun execute-precompile (address input rules gas-limit)
  (if (not (active-precompile-address-p address rules))
      (values nil 0 nil)
      (progn
        (ensure-precompile-upfront-gas address input rules gas-limit)
        (multiple-value-bind (output gas-used active-p)
            (run-precompile address input rules)
          (unless active-p
            (fail "Active precompile was not dispatched"))
          (when (> gas-used gas-limit)
            (fail "Precompile out of gas"))
          (values output gas-used t)))))
