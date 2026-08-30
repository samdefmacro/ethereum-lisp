(in-package #:ethereum-lisp.test)

;;;; Osaka (Fusaka) EVM and consensus additions: CLZ opcode, the EIP-7594
;;;; per-transaction blob cap, and the EIP-7825/7934 limits.

(deftest evm-clz-counts-leading-zeros
  ;; PUSH1 <x>; CLZ; PUSH1 0; MSTORE; PUSH1 32; PUSH1 0; RETURN
  (let ((one (execute-bytecode #(96 1 30 96 0 82 96 32 96 0 243)))
        (zero (execute-bytecode #(96 0 30 96 0 82 96 32 96 0 243)))
        (high-bit
          ;; PUSH1 1; PUSH1 255; SHL; CLZ; store; return  => CLZ = 0
          (execute-bytecode #(96 1 96 255 27 30 96 0 82 96 32 96 0 243))))
    (is (eq :returned (evm-result-status one)))
    ;; CLZ(1) = 255 leading zeros in a 256-bit word.
    (is (= 255 (aref (evm-result-return-data one) 31)))
    ;; CLZ(0) = 256, encoded big-endian as 0x0100.
    (is (= 1 (aref (evm-result-return-data zero) 30)))
    (is (= 0 (aref (evm-result-return-data zero) 31)))
    ;; CLZ of a value with the top bit set = 0.
    (is (= 0 (aref (evm-result-return-data high-bit) 31)))))

(deftest evm-clz-requires-osaka
  ;; Under a pre-Osaka (Cancun) rule set, CLZ is an invalid opcode.
  (signals evm-error
    (execute-bytecode
     #(96 1 30 0)
     :context (make-evm-context
               :chain-rules (make-chain-rules :chain-id 1
                                              :shanghai-p t
                                              :cancun-p t)))))

(deftest chain-rules-per-transaction-blob-cap-is-fork-aware
  ;; Prague: a single transaction may use the full per-block blob limit (9).
  (is (= 9 (chain-rules-max-blobs-per-transaction
            (make-chain-rules :chain-id 1
                              :prague-p t
                              :blob-schedule-max-gas
                              (* 9 +blob-gas-per-blob+)))))
  ;; Osaka: EIP-7594 caps a single transaction at 6 blobs regardless of the
  ;; larger per-block limit.
  (is (= +max-blobs-per-transaction-eip7594+
         (chain-rules-max-blobs-per-transaction
          (make-chain-rules :chain-id 1
                            :prague-p t
                            :osaka-p t
                            :blob-schedule-max-gas
                            (* 9 +blob-gas-per-blob+))))))

(deftest osaka-consensus-limits-have-expected-values
  (is (= 16777216 +transaction-gas-limit-cap-eip7825+))
  (is (= 8388608 +max-rlp-block-size-eip7934+))
  (is (= 6 +max-blobs-per-transaction-eip7594+)))

;;;; EIP-7951 P256VERIFY. Signature is RFC 6979 A.2.5 (P-256 / SHA-256,
;;;; message "sample").

(defparameter +p256-sample-hash+
  #xaf2bdbe1aa9b6ec1e2ade1d694f41fc71a831d0268e9891562113d8a62add1bf)
(defparameter +p256-sample-r+
  #xefd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716)
(defparameter +p256-sample-s+
  #xf7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8)
(defparameter +p256-sample-qx+
  #x60fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb6)
(defparameter +p256-sample-qy+
  #x7903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299)

(deftest secp256r1-verify-accepts-and-rejects-p256-vector
  (is (secp256r1-verify +p256-sample-hash+ +p256-sample-r+ +p256-sample-s+
                        +p256-sample-qx+ +p256-sample-qy+))
  ;; A tampered s must not verify.
  (is (not (secp256r1-verify +p256-sample-hash+ +p256-sample-r+
                             (1+ +p256-sample-s+)
                             +p256-sample-qx+ +p256-sample-qy+)))
  ;; A public key off the curve must not verify.
  (is (not (secp256r1-verify +p256-sample-hash+ +p256-sample-r+ +p256-sample-s+
                             +p256-sample-qx+ (1+ +p256-sample-qy+))))
  ;; The point at infinity (0, 0) is rejected.
  (is (not (secp256r1-verify +p256-sample-hash+ +p256-sample-r+ +p256-sample-s+
                             0 0)))
  ;; An otherwise in-range ECDSA input whose verification recurrence produces
  ;; the point at infinity is an invalid signature, not an execution error.
  ;; Vector: execution-spec-tests v20.0.2, R_at_infinity_v1.
  (is (not (secp256r1-verify
            #x2ba3a8be6b94d5ec80a6d9d1190a436effe50d85a1eee859b8cc6af9bd5c2e18
            #x2ba3a8be6b94d5ec80a6d9d1190a436effe50d85a1eee859b8cc6af9bd5c2e18
            #x4cd60b855d442f5b3c7b11eb6c4e0ae7525fe710fab9aa7c77a67f79e6fadd76
            #x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296
            #xb01cbd1c01e58065711814b583f061e9d431cca994cea1313449bf97c840ae0a))))

(defun p256-sample-precompile-input ()
  (concat-bytes
   (hex-to-bytes "0xaf2bdbe1aa9b6ec1e2ade1d694f41fc71a831d0268e9891562113d8a62add1bf")
   (hex-to-bytes "0xefd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716")
   (hex-to-bytes "0xf7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8")
   (hex-to-bytes "0x60fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb6")
   (hex-to-bytes "0x7903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299")))

(deftest evm-p256verify-precompile-is-osaka-gated
  (let ((osaka (make-chain-rules :chain-id 1 :shanghai-p t :cancun-p t
                                 :prague-p t :osaka-p t))
        (pre-osaka (make-chain-rules :chain-id 1 :shanghai-p t :cancun-p t
                                     :prague-p t))
        (address (precompile-address 256))
        (input (p256-sample-precompile-input)))
    ;; The address is 0x0...0100, exercising multi-byte precompile encoding.
    (is (= 256 (bytes-to-integer (address-bytes address))))
    ;; Under Osaka a valid signature returns a 32-byte 1 at flat 6900 gas.
    (multiple-value-bind (output gas active-p)
        (execute-precompile address input osaka 100000)
      (is active-p)
      (is (= 6900 gas))
      (is (= 32 (length output)))
      (is (= 1 (bytes-to-integer output))))
    ;; Malformed (short) input returns empty output but still costs 6900 gas.
    (multiple-value-bind (output gas active-p)
        (execute-precompile address (subseq input 0 159) osaka 100000)
      (is active-p)
      (is (= 6900 gas))
      (is (= 0 (length output))))
    ;; Before Osaka the address is not an active precompile.
    (multiple-value-bind (output gas active-p)
        (execute-precompile address input pre-osaka 100000)
      (declare (ignore output gas))
      (is (not active-p)))))
