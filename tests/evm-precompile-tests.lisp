(in-package #:ethereum-lisp.test)

(deftest evm-call-and-staticcall-identity-precompile
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address caller))
         (setup #(96 1 95 83 96 2 96 1 83 96 3 96 2 83))
         (call-code #(96 3 95 96 3 95 95 96 4 96 100 241 96 3 95 243))
         (staticcall-code #(96 3 95 96 3 95 96 4 96 100 250 96 3 95 243))
         (oog-call-code #(96 3 95 96 3 95 95 96 4 96 17 241 96 3 95 243))
         (call-result (execute-bytecode (concat-bytes setup call-code)
                                        :context context))
         (static-result (execute-bytecode (concat-bytes setup staticcall-code)
                                          :context context))
         (oog-result (execute-bytecode (concat-bytes setup oog-call-code)
                                       :context context)))
    (is (= 1 (first (evm-result-stack call-result))))
    (is (bytes= #(1 2 3) (evm-result-return-data call-result)))
    (is (= 1 (first (evm-result-stack static-result))))
    (is (bytes= #(1 2 3) (evm-result-return-data static-result)))
    (is (= 0 (first (evm-result-stack oog-result))))
    (is (bytes= #(1 2 3) (evm-result-return-data oog-result)))))

(deftest evm-call-output-copy-keeps-bytes-beyond-return-data
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address caller))
         (code #(96 1 96 0 82
                 96 32 96 0 96 0 96 0 96 0 96 4 97 39 16 241
                 96 0 81 96 0 82
                 96 32 96 0 243))
         (result (execute-bytecode code :context context)))
    (is (= 1 (first (evm-result-stack result))))
    (is (= 1 (bytes-to-integer (evm-result-return-data result))))))

(deftest evm-call-ecrecover-precompile
  (labels ((program (input gas-high gas-low)
             (let ((copy-code #(96 128 96 23 95 57))
                   (call-code (vector 96 32 95 96 128 95 95 96 1
                                      97 gas-high gas-low
                                      241 96 32 95 243)))
               (concat-bytes copy-code call-code input))))
    (let* ((state (make-state-db))
           (caller (address-from-hex
                    "0x00000000000000000000000000000000000000aa"))
           (context (make-evm-context :state state :address caller))
           (valid-input
             (hex-to-bytes
              "0x18c547e4f7b0f325ad1e56f57e26c745b09a3e503d86e00e5255ff7f715d3d1c000000000000000000000000000000000000000000000000000000000000001c73b1693892219d736caba55bdb67216e485557ea6b6af75f37096c9aa6a5a75feeb940b1d03b21e36b0e47e79769f095fe2ab855bd91e3a38756b7d75a9c4549"))
           (invalid-v-input (copy-seq valid-input))
           (result (execute-bytecode (program valid-input 11 184)
                                     :context context))
           (invalid-result
             (progn
               (setf (aref invalid-v-input 32) 1)
               (execute-bytecode (program invalid-v-input 11 184)
                                 :context context)))
           (oog-result (execute-bytecode (program valid-input 11 183)
                                         :context context)))
      (is (= 1 (first (evm-result-stack result))))
      (is (string= "0x000000000000000000000000a94f5374fce5edbc8e2a8697c15331677e6ebf0b"
                   (bytes-to-hex (evm-result-return-data result))))
      (is (= 1 (first (evm-result-stack invalid-result))))
      (is (bytes= (byte-prefix-padded invalid-v-input 32)
                  (evm-result-return-data invalid-result)))
      (is (= 0 (first (evm-result-stack oog-result))))
      (is (bytes= (byte-prefix-padded valid-input 32)
                  (evm-result-return-data oog-result))))))

(deftest evm-call-sha256-precompile
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address caller))
         (setup #(96 97 95 83 96 98 96 1 83 96 99 96 2 83))
         (call-code #(96 32 95 96 3 95 95 96 2 96 100 241 96 32 95 243))
         (oog-call-code #(96 32 95 96 3 95 95 96 2 96 71 241 96 32 95 243))
         (result (execute-bytecode (concat-bytes setup call-code)
                                   :context context))
         (oog-result (execute-bytecode (concat-bytes setup oog-call-code)
                                       :context context)))
    (is (= 1 (first (evm-result-stack result))))
    (is (= 224 (evm-result-gas-used result)))
    (is (string= "0xba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                 (bytes-to-hex (evm-result-return-data result))))
    (is (= 0 (first (evm-result-stack oog-result))))
    (is (= 223 (evm-result-gas-used oog-result)))
    (is (bytes= (byte-prefix-padded #(97 98 99) 32)
                (evm-result-return-data oog-result)))))

(deftest evm-call-ripemd160-precompile
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address caller))
         (setup #(96 97 95 83 96 98 96 1 83 96 99 96 2 83))
         (call-code #(96 32 95 96 3 95 95 96 3 97 2 208 241
                      96 32 95 243))
         (oog-call-code #(96 32 95 96 3 95 95 96 3 97 2 207 241
                          96 32 95 243))
         (result (execute-bytecode (concat-bytes setup call-code)
                                   :context context))
         (oog-result (execute-bytecode (concat-bytes setup oog-call-code)
                                       :context context)))
    (is (= 1 (first (evm-result-stack result))))
    (is (= 872 (evm-result-gas-used result)))
    (is (string= "0x0000000000000000000000008eb208f7e05d987a9b044a8e98c6b087f15a0bfc"
                 (bytes-to-hex (evm-result-return-data result))))
    (is (= 0 (first (evm-result-stack oog-result))))
    (is (= 871 (evm-result-gas-used oog-result)))
    (is (bytes= (byte-prefix-padded #(97 98 99) 32)
                (evm-result-return-data oog-result)))))

(deftest evm-call-modexp-precompile
  (labels ((fixed32 (value)
             (let ((bytes (make-byte-vector 32)))
               (setf (aref bytes 31) value)
               bytes))
           (program (call-gas-high call-gas-low)
             (let* ((input (concat-bytes (fixed32 1)
                                         (fixed32 1)
                                         (fixed32 1)
                                         #(2 5 13)))
                    (copy-code #(96 99 96 23 95 57))
                    (call-code (vector 96 1 95 96 99 95 95 96 5
                                       97 call-gas-high call-gas-low
                                       241 96 1 95 243)))
               (concat-bytes copy-code call-code input))))
    (let* ((state (make-state-db))
           (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
           (context (make-evm-context :state state :address caller))
           (result (execute-bytecode (program 3 132) :context context))
           (oog-result (execute-bytecode (program 0 199) :context context)))
      (is (= 1 (first (evm-result-stack result))))
      (is (= 358 (evm-result-gas-used result)))
      (is (bytes= #(6) (evm-result-return-data result)))
      (is (= 0 (first (evm-result-stack oog-result))))
      (is (= 357 (evm-result-gas-used oog-result)))
      (is (bytes= #(0) (evm-result-return-data oog-result))))))

(deftest evm-modexp-precompile-checks-gas-before-large-allocation
  (labels ((fixed32-integer (value)
             (let ((bytes (make-byte-vector 32)))
               (loop for index downfrom 31
                     for current = value then (ash current -8)
                     while (and (>= index 0) (plusp current))
                     do (setf (aref bytes index) (logand current #xff)))
               bytes)))
    (let ((input
            (concat-bytes
             (fixed32-integer 0)
             (fixed32-integer #x100000000)
             (fixed32-integer 1))))
      (signals ethereum-lisp.evm.internal::evm-error
        (ethereum-lisp.evm.internal::ensure-precompile-upfront-gas
         (ethereum-lisp.evm:precompile-address 5)
         input
         (make-chain-rules :byzantium-p t)
         500000)))))

(deftest evm-call-bn254-add-and-mul-precompiles
  (labels ((bn254-add-program (input)
             (concat-bytes
              #(96 128 96 22 95 57
                96 64 95 96 128 95 95 96 6 96 150 241
                96 64 95 243)
              input))
           (bn254-mul-program (input)
             (concat-bytes
              #(96 96 96 23 95 57
                96 64 95 96 96 95 95 96 7 97 23 112 241
                96 64 95 243)
              input))
           (fixed32 (value)
             (let ((bytes (make-byte-vector 32)))
               (setf (aref bytes 31) value)
               bytes)))
    (let* ((state (make-state-db))
           (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
           (context (make-evm-context :state state :address caller))
           (g (hex-to-bytes
               "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002"))
           (two-g (hex-to-bytes
                   "0x030644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd315ed738c0e0a7c92e7845f96b2ae9c0a68a6a449e3538fc7ff3ebf7a5a18a2c4"))
           (three-g (hex-to-bytes
                     "0x0769bf9ac56bea3ff40232bcb1b6bd159315d84715b8e679f2d355961915abf02ab799bee0489429554fdb7c8d086475319e63b40b9c5b57cdf1ff3dd9fe2261"))
           (add-result
             (execute-bytecode (bn254-add-program (concat-bytes g two-g))
                               :context context))
           (mul-result
             (execute-bytecode (bn254-mul-program
                                (concat-bytes g (fixed32 3)))
                               :context context))
           (zero-mul-result
             (execute-bytecode (bn254-mul-program
                                (concat-bytes g (make-byte-vector 32)))
                               :context context)))
      (is (= 1 (first (evm-result-stack add-result))))
      (is (bytes= three-g (evm-result-return-data add-result)))
      (is (= 1 (first (evm-result-stack mul-result))))
      (is (bytes= three-g (evm-result-return-data mul-result)))
      (is (= 1 (first (evm-result-stack zero-mul-result))))
      (is (bytes= (make-byte-vector 64)
                  (evm-result-return-data zero-mul-result))))))

(deftest evm-call-bn254-add-invalid-point-fails
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address caller))
         (field-prime-and-y (hex-to-bytes
                             "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd470000000000000000000000000000000000000000000000000000000000000002"))
         (g (hex-to-bytes
             "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002"))
         (program
           (concat-bytes
            #(96 128 96 22 95 57
              96 64 95 96 128 95 95 96 6 96 150 241
              96 64 95 243)
            (concat-bytes field-prime-and-y g)))
         (result (execute-bytecode program :context context)))
    (is (= 0 (first (evm-result-stack result))))
    (is (bytes= (byte-prefix-padded field-prime-and-y 64)
                (evm-result-return-data result)))))

(defconstant +bn254-pairing-vector-fixture-path+
  "tests/fixtures/execution-spec-tests/bn254-pairing-vectors.json")

(defparameter +bn254-pairing-vector-fixture-fields+
  '("format" "source" "referenceClients" "cases"))

(defparameter +bn254-pairing-vector-case-fields+
  '("name" "input" "expected" "gas"))

(defun bn254-pairing-vector-hex-bytes (value label)
  (unless (and (stringp value)
               (<= 2 (length value))
               (string= "0x" value :end2 2)
               (string= value (string-downcase value)))
    (error "~A must be a lowercase 0x-prefixed hex string" label))
  (hex-to-bytes value))

(defun validate-bn254-pairing-vector-case (case seen-names)
  (validate-fixture-object-fields
   case
   +bn254-pairing-vector-case-fields+
   "BN254 pairing vector case")
  (let ((name (fixture-required-field case "name")))
    (unless (and (stringp name) (plusp (length name)))
      (error "BN254 pairing vector case name must be a non-empty string"))
    (when (gethash name seen-names)
      (error "Duplicate BN254 pairing vector case ~A" name))
    (setf (gethash name seen-names) t))
  (let* ((input (bn254-pairing-vector-hex-bytes
                 (fixture-required-field case "input")
                 "BN254 pairing vector input"))
         (expected (bn254-pairing-vector-hex-bytes
                    (fixture-required-field case "expected")
                    "BN254 pairing vector expected output"))
         (gas (fixture-required-field case "gas")))
    (unless (zerop (mod (length input) 192))
      (error "BN254 pairing vector input length must be a multiple of 192"))
    (unless (= 32 (length expected))
      (error "BN254 pairing vector expected output must be 32 bytes"))
    (unless (and (integerp gas) (<= 0 gas))
      (error "BN254 pairing vector gas must be a non-negative integer"))
    (unless (= gas
               (+ 45000 (* 34000 (floor (length input) 192))))
      (error "BN254 pairing vector gas does not match EIP-1108 schedule"))
    (list :name (fixture-required-field case "name")
          :input input
          :expected expected
          :gas gas)))

(defun load-bn254-pairing-vector-cases
    (&optional (path +bn254-pairing-vector-fixture-path+))
  (let ((fixture (load-handwritten-fixture-file path)))
    (validate-fixture-object-fields
     fixture
     +bn254-pairing-vector-fixture-fields+
     "BN254 pairing vector fixture")
    (validate-fixture-format fixture "ethereum-lisp-bn254-pairing-vectors-v1")
    (unless (string= "go-ethereum core/vm/testdata/precompiles/bn256Pairing.json"
                     (validate-fixture-required-string-field
                      fixture "source" "BN254 pairing vector fixture"))
      (error "BN254 pairing vector fixture source is not the geth vector file"))
    (let ((references (fixture-required-field fixture "referenceClients")))
      (validate-fixture-object-fields
       references
       '("geth" "nethermind")
       "BN254 pairing vector reference clients")
      (unless (string= "8a0223e"
                       (validate-fixture-required-string-field
                        references "geth" "BN254 pairing vector geth pin"))
        (error "BN254 pairing vector geth pin drifted"))
      (unless (string= "1c72a72"
                       (validate-fixture-required-string-field
                        references
                        "nethermind"
                        "BN254 pairing vector Nethermind pin"))
        (error "BN254 pairing vector Nethermind pin drifted")))
    (let ((cases (fixture-required-field fixture "cases")))
      (unless (and (listp cases) (plusp (length cases)))
        (error "BN254 pairing vector fixture cases must be a non-empty list"))
      (let ((seen-names (make-hash-table :test 'equal)))
        (mapcar (lambda (case)
                  (validate-bn254-pairing-vector-case case seen-names))
                cases)))))

(deftest bn254-pairing-reference-fixture-vectors
  (let ((cases (load-bn254-pairing-vector-cases))
        (seen-true-p nil)
        (seen-false-p nil))
    (dolist (case cases)
      (multiple-value-bind (output gas)
          (ethereum-lisp.evm.internal::run-bn254-pairing-precompile
           (getf case :input))
        (is (= (getf case :gas) gas))
        (is (bytes= (getf case :expected) output))
        (if (= 1 (aref output 31))
            (setf seen-true-p t)
            (setf seen-false-p t))))
    (is seen-true-p)
    (is seen-false-p)))

(deftest evm-call-bn254-pairing-empty-zero-element-and-malformed-input
  (labels ((pairing-code (input)
             (concat-bytes
              #(96 192 96 24 95 57
                96 32 95 96 192 95 95 96 8 98 1 52 152 241
                96 32 95 243)
              input))
           (pairing-code-sized (input)
             (let* ((input (ensure-byte-vector input))
                    (size (length input))
                    (size-bytes (ethereum-lisp.evm.internal::integer-to-fixed-bytes
                                 size 2))
                    (gas (+ 45000 (* 34000 (floor size 192))))
                    (gas-bytes (ethereum-lisp.evm.internal::integer-to-fixed-bytes
                                gas 3)))
               (concat-bytes
                (vector 97 (aref size-bytes 0) (aref size-bytes 1)
                        96 26 95 57
                        96 32 95
                        97 (aref size-bytes 0) (aref size-bytes 1)
                        95 95 96 8
                        98 (aref gas-bytes 0) (aref gas-bytes 1)
                        (aref gas-bytes 2)
                        241 96 32 95 243)
                input)))
           (fixed32 (value)
             (ethereum-lisp.evm.internal::integer-to-fixed-bytes value 32))
           (bn254-negate-field (bytes)
             (mod (- ethereum-lisp.evm.internal::+bn254-field-prime+
                     (bytes-to-integer bytes))
                  ethereum-lisp.evm.internal::+bn254-field-prime+))
           (negate-g2 (point)
             (concat-bytes
              (subseq point 0 64)
              (fixed32 (bn254-negate-field (subseq point 64 96)))
              (fixed32 (bn254-negate-field (subseq point 96 128))))))
    (let* ((state (make-state-db))
           (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
           (context (make-evm-context :state state :address caller))
           (empty-code #(96 32 95 95 95 95 96 8 97 175 200 241
                         96 32 95 243))
           (malformed-code #(96 1 95 83
                             96 32 95 96 1 95 95 96 8 97 175 200 241
                             96 32 95 243))
           (g (hex-to-bytes
               "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002"))
           (negative-g
             (hex-to-bytes
              "0x000000000000000000000000000000000000000000000000000000000000000130644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd45"))
           (field-prime
             (hex-to-bytes
              "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47"))
           (g2 (hex-to-bytes
                "0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c21800deef121f1e76426a00665e5c4479674322d4f75edadd46debd5cd992f6ed090689d0585ff075ec9e99ad690c3395bc4b313370b38ef355acdadcd122975b12c85ea5db8c6deb4aab71808dcb408fe3d1e7690c43d37b4ce6cc0166fa7daa"))
           (negative-g2 (negate-g2 g2))
           (g2-coordinate-too-large
             (concat-bytes field-prime (subseq g2 32 128)))
           (g2-off-curve
             (concat-bytes (subseq g2 0 127) #(171)))
           (g2-invalid-subgroup
             (hex-to-bytes
              "0x0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000007bca656753ef8cbee60335acbffe3def91636952d4ab9eb0b839c7f3566c0e20cf32d3c49a2cb8a092f24ec3201e68dc299b6216e6321ee60573e3a7f596ea8"))
           (geth-jeff6-false
             (hex-to-bytes
              "0x1c76476f4def4bb94541d57ebba1193381ffa7aa76ada664dd31c16024c43f593034dd2920f673e204fee2811c678745fc819b55d3e9d294e45c9b03a76aef41209dd15ebff5d46c4bd888e51a93cf99a7329636c63514396b4a452003a35bf704bf11ca01483bfa8b34b43561848d28905960114c8ac04049af4b6315a416782bb8324af6cfc93537a2ad1a445cfd0ca2a71acd7ac41fadbf933c2a51be344d120a2a4cf30c1bf9845f20c6fe39e07ea2cce61f0c9bb048165fe5e4de877550111e129f1cf1097710d41c4ac70fcdfa5ba2023c6ff1cbeac322de49d1b6df7c103188585e2364128fe25c70558f1560f4f9350baf3959e603cc91486e110936198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c21800deef121f1e76426a00665e5c4479674322d4f75edadd46debd5cd992f6ed090689d0585ff075ec9e99ad690c3395bc4b313370b38ef355acdadcd122975b12c85ea5db8c6deb4aab71808dcb408fe3d1e7690c43d37b4ce6cc0166fa7daa"))
           (g1-coordinate-too-large
             (concat-bytes field-prime (subseq g 32 64)))
           (g1-off-curve
             (hex-to-bytes
              "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000003"))
           (empty-result (execute-bytecode empty-code :context context))
           (zero-g2-result
             (execute-bytecode
              (pairing-code (concat-bytes g (make-byte-vector 128)))
              :context context))
           (zero-g1-result
             (execute-bytecode
              (pairing-code (concat-bytes (make-byte-vector 64) g2))
              :context context))
           (invalid-g2-coordinate-result
             (execute-bytecode
              (pairing-code (concat-bytes (make-byte-vector 64)
                                          g2-coordinate-too-large))
              :context context))
           (invalid-g2-curve-result
             (execute-bytecode
              (pairing-code (concat-bytes (make-byte-vector 64)
                                          g2-off-curve))
              :context context))
           (invalid-g2-subgroup-result
             (execute-bytecode
              (pairing-code (concat-bytes (make-byte-vector 64)
                                          g2-invalid-subgroup))
              :context context))
           (invalid-g1-coordinate-result
             (execute-bytecode
              (pairing-code (concat-bytes g1-coordinate-too-large g2))
              :context context))
           (invalid-g1-curve-result
             (execute-bytecode
              (pairing-code (concat-bytes g1-off-curve g2))
              :context context))
           (nonempty-true-result
             (execute-bytecode
              (pairing-code-sized (concat-bytes g g2 negative-g g2))
              :context context))
           (nonempty-g2-negation-true-result
             (execute-bytecode
              (pairing-code-sized (concat-bytes g g2 g negative-g2))
              :context context))
           (nonempty-false-result
             (execute-bytecode
              (pairing-code-sized (concat-bytes g g2))
              :context context))
           (mixed-zero-noncancel-result
             (execute-bytecode
              (pairing-code-sized
               (concat-bytes g (make-byte-vector 128) g g2))
              :context context))
           (mixed-zero-cancel-result
             (execute-bytecode
              (pairing-code-sized
               (concat-bytes g (make-byte-vector 128) g g2 negative-g g2))
              :context context))
           (nonadjacent-double-cancel-result
             (execute-bytecode
              (pairing-code-sized
               (concat-bytes g g2 g g2 negative-g g2 negative-g g2))
              :context context))
           (mixed-zero-g2-nonadjacent-cancel-result
             (execute-bytecode
              (pairing-code-sized
               (concat-bytes g g2
                             (make-byte-vector 64) g2
                             g negative-g2))
              :context context))
           (unbalanced-duplicate-result
             (execute-bytecode
              (pairing-code-sized
               (concat-bytes g g2 negative-g g2 g g2))
              :context context))
           (g2-negation-unbalanced-duplicate-result
             (execute-bytecode
              (pairing-code-sized
               (concat-bytes g g2 g negative-g2 g negative-g2))
              :context context))
           (malformed-result (execute-bytecode malformed-code :context context)))
      (is (= 1 (first (evm-result-stack empty-result))))
      (is (= 1 (aref (evm-result-return-data empty-result) 31)))
      (is (= 1 (first (evm-result-stack zero-g2-result))))
      (is (= 1 (aref (evm-result-return-data zero-g2-result) 31)))
      (is (= 1 (first (evm-result-stack zero-g1-result))))
      (is (= 1 (aref (evm-result-return-data zero-g1-result) 31)))
      (is (= 1 (first (evm-result-stack nonempty-true-result))))
      (is (= 1 (aref (evm-result-return-data nonempty-true-result) 31)))
      (is (= 1 (first (evm-result-stack nonempty-g2-negation-true-result))))
      (is (= 1 (aref (evm-result-return-data
                      nonempty-g2-negation-true-result)
                     31)))
      (is (= 1 (first (evm-result-stack nonempty-false-result))))
      (is (bytes= (make-byte-vector 32)
                  (evm-result-return-data nonempty-false-result)))
      (is (= 1 (first (evm-result-stack mixed-zero-noncancel-result))))
      (is (bytes= (make-byte-vector 32)
                  (evm-result-return-data mixed-zero-noncancel-result)))
      (is (= 1 (first (evm-result-stack mixed-zero-cancel-result))))
      (is (= 1 (aref (evm-result-return-data mixed-zero-cancel-result)
                     31)))
      (is (= 1 (first (evm-result-stack
                       nonadjacent-double-cancel-result))))
      (is (= 1 (aref (evm-result-return-data
                      nonadjacent-double-cancel-result)
                     31)))
      (is (= 1 (first (evm-result-stack
                       mixed-zero-g2-nonadjacent-cancel-result))))
      (is (= 1 (aref (evm-result-return-data
                      mixed-zero-g2-nonadjacent-cancel-result)
                     31)))
      (is (= 1 (first (evm-result-stack unbalanced-duplicate-result))))
      (is (bytes= (make-byte-vector 32)
                  (evm-result-return-data unbalanced-duplicate-result)))
      (is (= 1 (first (evm-result-stack
                       g2-negation-unbalanced-duplicate-result))))
      (is (bytes= (make-byte-vector 32)
                  (evm-result-return-data
                   g2-negation-unbalanced-duplicate-result)))
      (multiple-value-bind (output gas)
          (ethereum-lisp.evm.internal::run-bn254-pairing-precompile
           (concat-bytes g g2))
        (is (bytes= (make-byte-vector 32) output))
        (is (= (+ 45000 34000) gas)))
      (multiple-value-bind (output gas)
          (ethereum-lisp.evm.internal::run-bn254-pairing-precompile
           geth-jeff6-false)
        (is (bytes= (make-byte-vector 32) output))
        (is (= (+ 45000 (* 34000 2)) gas)))
      (let ((backend-pairs nil))
        (let ((ethereum-lisp.evm.internal::*bn254-pairing-checker*
                (lambda (pairs)
                  (setf backend-pairs pairs)
                  t)))
          (multiple-value-bind (output gas)
              (ethereum-lisp.evm.internal::run-bn254-pairing-precompile
               (concat-bytes g (make-byte-vector 128) g g2))
            (is (= 1 (aref output 31)))
            (is (= (+ 45000 (* 34000 2)) gas))
            (is (= 1 (length backend-pairs))))))
      (is (= 0 (first (evm-result-stack invalid-g2-coordinate-result))))
      (is (bytes= (make-byte-vector 32)
                  (evm-result-return-data invalid-g2-coordinate-result)))
      (is (= 0 (first (evm-result-stack invalid-g2-curve-result))))
      (is (bytes= (make-byte-vector 32)
                  (evm-result-return-data invalid-g2-curve-result)))
      (is (= 0 (first (evm-result-stack invalid-g2-subgroup-result))))
      (is (bytes= (make-byte-vector 32)
                  (evm-result-return-data invalid-g2-subgroup-result)))
      (is (= 0 (first (evm-result-stack invalid-g1-coordinate-result))))
      (is (bytes= (byte-prefix-padded g1-coordinate-too-large 32)
                  (evm-result-return-data invalid-g1-coordinate-result)))
      (is (= 0 (first (evm-result-stack invalid-g1-curve-result))))
      (is (bytes= (byte-prefix-padded g1-off-curve 32)
                  (evm-result-return-data invalid-g1-curve-result)))
      (is (= 0 (first (evm-result-stack malformed-result))))
      (is (bytes= (byte-prefix-padded #(1) 32)
                  (evm-result-return-data malformed-result))))))

(deftest evm-call-kzg-point-evaluation-rejects-malformed-inputs
  (labels ((program (input)
             (let* ((input (ensure-byte-vector input))
                    (size (length input))
                    (code (vector 96 size 96 23 95 57
                                  96 32 95 96 size 95 95 96 10
                                  97 #xc3 #x50 241
                                  96 32 95 243)))
               (concat-bytes code input)))
           (matched-version-input (&key z y)
             (let* ((commitment (make-byte-vector +kzg-commitment-size+))
                    (proof (make-byte-vector +kzg-proof-size+))
                    (versioned-hash
                      (hash32-bytes
                       (kzg-commitment-to-versioned-hash commitment)))
                    (input
                      (make-byte-vector
                       ethereum-lisp.evm.internal::+kzg-point-evaluation-input-size+)))
               (replace input versioned-hash :start1 0)
               (when z
                 (replace input z :start1 32))
               (when y
                 (replace input y :start1 64))
               (replace input commitment :start1 96)
               (replace input proof :start1 144)
               input)))
    (let* ((state (make-state-db))
           (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
           (context (make-evm-context :state state :address caller))
           (short-input #(1))
           (mismatched-version-input (make-byte-vector 192))
           (unverified-proof-input (matched-version-input))
           (short-result
             (execute-bytecode (program short-input) :context context))
           (mismatch-result
             (execute-bytecode (program mismatched-version-input)
                               :context context))
           (unverified-proof-result
             (execute-bytecode (program unverified-proof-input)
                               :context context))
           (unverified-proof-error
             (handler-case
                 (progn
                   (ethereum-lisp.evm.internal::run-kzg-point-evaluation-precompile
                    unverified-proof-input)
                   nil)
               (ethereum-lisp.evm.internal::evm-precompile-error (condition)
                 condition))))
      (is (= 0 (first (evm-result-stack short-result))))
      (is (bytes= (byte-prefix-padded short-input 32)
                  (evm-result-return-data short-result)))
      (is (= 0 (first (evm-result-stack mismatch-result))))
      (is (bytes= (make-byte-vector 32)
                  (evm-result-return-data mismatch-result)))
      (is (= 0 (first (evm-result-stack unverified-proof-result))))
      (is (bytes= (byte-prefix-padded unverified-proof-input 32)
                  (evm-result-return-data unverified-proof-result)))
      (is unverified-proof-error)
      (is (= ethereum-lisp.evm.internal::+kzg-point-evaluation-gas+
             (ethereum-lisp.evm.internal::evm-precompile-error-gas-used
              unverified-proof-error)))
      (is (search "KZG point proof verification is not available"
                  (princ-to-string unverified-proof-error)
                  :test #'char=))
      (let ((observed nil))
        (let ((*kzg-point-proof-verifier*
                (lambda (commitment z y proof)
                  (setf observed (list commitment z y proof))
                  t)))
          (multiple-value-bind (output gas)
              (ethereum-lisp.evm.internal::run-kzg-point-evaluation-precompile
               unverified-proof-input)
            (is (= ethereum-lisp.evm.internal::+kzg-point-evaluation-gas+ gas))
            (is (bytes= (ethereum-lisp.evm.internal::kzg-point-evaluation-return-value)
                        output))))
        (is (bytes= (subseq unverified-proof-input 96 144)
                    (first observed)))
        (is (bytes= (subseq unverified-proof-input 32 64)
                    (second observed)))
        (is (bytes= (subseq unverified-proof-input 64 96)
                    (third observed)))
        (is (bytes= (subseq unverified-proof-input 144 192)
                    (fourth observed))))
      (let ((*kzg-point-proof-verifier*
              (lambda (commitment z y proof)
                (declare (ignore commitment z y proof))
                nil)))
        (signals ethereum-lisp.evm.internal::evm-precompile-error
          (ethereum-lisp.evm.internal::run-kzg-point-evaluation-precompile
           unverified-proof-input)))
      (let* ((called nil)
             (invalid-z-input
               (matched-version-input
                :z (ethereum-lisp.evm.internal::integer-to-fixed-bytes
                    ethereum-lisp.evm.internal::+bls-field-modulus+
                    32))))
        (let ((*kzg-point-proof-verifier*
                (lambda (commitment z y proof)
                  (declare (ignore commitment z y proof))
                  (setf called t)
                  t)))
          (signals ethereum-lisp.evm.internal::evm-precompile-error
            (ethereum-lisp.evm.internal::run-kzg-point-evaluation-precompile
             invalid-z-input)))
        (is (null called))))))

(deftest evm-call-kzg-point-evaluation-replays-real-kzg-vector
  (let ((script (repo-kzg-verifier-command)))
    (labels ((point-input (commitment z y proof)
               (let* ((versioned-hash
                        (hash32-bytes
                         (kzg-commitment-to-versioned-hash commitment)))
                      (input
                        (make-byte-vector
                         ethereum-lisp.evm.internal::+kzg-point-evaluation-input-size+)))
                 (replace input versioned-hash :start1 0)
                 (replace input z :start1 32)
                 (replace input y :start1 64)
                 (replace input commitment :start1 96)
                 (replace input proof :start1 144)
                 input)))
      (let* ((valid-commitment
               (hex-to-bytes
                "0xa572cbea904d67468808c8eb50a9450c9721db309128012543902d0ac358a62ae28f75bb8f1c7c42c39a8c5529bf0f4e"))
             (valid-z
               (hex-to-bytes
                "0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000000"))
             (valid-y
               (hex-to-bytes
                "0x0000000000000000000000000000000000000000000000000000000000000002"))
             (valid-proof
               (hex-to-bytes
                "0xc00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"))
             (invalid-proof
               (hex-to-bytes
                "0xa7de1e32bb336b85e42ff5028167042188317299333f091dd88675e84a550577bfa564b2f57cd2498e2acf875e0aaa40"))
             (valid-input
               (point-input valid-commitment valid-z valid-y valid-proof))
             (invalid-input
               (point-input valid-commitment valid-z valid-y invalid-proof))
             (old-point-verifier *kzg-point-proof-verifier*)
             (old-blob-verifier *kzg-blob-proof-verifier*))
        (unwind-protect
             (progn
               (configure-kzg-proof-command-verifiers (namestring script))
               (multiple-value-bind (output gas)
                   (ethereum-lisp.evm.internal::run-kzg-point-evaluation-precompile
                    valid-input)
                 (is (= ethereum-lisp.evm.internal::+kzg-point-evaluation-gas+ gas))
                 (is (bytes=
                      (ethereum-lisp.evm.internal::kzg-point-evaluation-return-value)
                      output)))
               (signals ethereum-lisp.evm.internal::evm-precompile-error
                 (ethereum-lisp.evm.internal::run-kzg-point-evaluation-precompile
                  invalid-input)))
          (setf *kzg-point-proof-verifier* old-point-verifier
                *kzg-blob-proof-verifier* old-blob-verifier))))))

(deftest evm-call-blake2f-precompile
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address caller))
         (input
           (hex-to-bytes
            "0x0000000c48c9bdf267e6096a3ba7ca8485ae67bb2bf894fe72f36e3cf1361d5f3af54fa5d182e6ad7f520e511f6c3e2b8c68059b6bbd41fbabd9831f79217e1319cde05b61626300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000001"))
         (huge-rounds-input
           (let ((copy (copy-seq input)))
             (replace copy #(255 255 255 255) :start1 0)
             copy))
         (copy-code #(97 0 213 96 24 95 57))
         (call-code #(96 64 95 97 0 213 95 95 96 9 96 12 241
                      96 64 95 243))
         (oog-call-code #(96 64 95 97 0 213 95 95 96 9 96 11 241
                          96 64 95 243))
         (result (execute-bytecode (concat-bytes copy-code call-code input)
                                   :context context))
         (oog-result (execute-bytecode
                      (concat-bytes copy-code oog-call-code input)
                      :context context))
         (huge-oog-result (execute-bytecode
                            (concat-bytes copy-code oog-call-code
                                          huge-rounds-input)
                            :context context)))
    (is (= 1 (first (evm-result-stack result))))
    (is (= 188 (evm-result-gas-used result)))
    (is (string= "0xba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923"
                 (bytes-to-hex (evm-result-return-data result))))
    (is (= 0 (first (evm-result-stack oog-result))))
    (is (= 187 (evm-result-gas-used oog-result)))
    (is (bytes= (byte-prefix-padded input 64)
                (evm-result-return-data oog-result)))
    (is (= 0 (first (evm-result-stack huge-oog-result))))
    (is (= (evm-result-gas-used oog-result)
           (evm-result-gas-used huge-oog-result)))
    (is (bytes= (byte-prefix-padded huge-rounds-input 64)
                (evm-result-return-data huge-oog-result)))))

(deftest evm-call-blake2f-malformed-input-fails
  (let* ((state (make-state-db))
         (caller (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (context (make-evm-context :state state :address caller))
         (bad-flag-input
           (hex-to-bytes
            "0x0000000c48c9bdf267e6096a3ba7ca8485ae67bb2bf894fe72f36e3cf1361d5f3af54fa5d182e6ad7f520e511f6c3e2b8c68059b6bbd41fbabd9831f79217e1319cde05b61626300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000002"))
         (short-input
           (hex-to-bytes
            "0x00000c48c9bdf267e6096a3ba7ca8485ae67bb2bf894fe72f36e3cf1361d5f3af54fa5d182e6ad7f520e511f6c3e2b8c68059b6bbd41fbabd9831f79217e1319cde05b61626300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000001"))
         (bad-flag-code #(97 0 213 96 24 95 57
                          96 64 95 97 0 213 95 95 96 9 96 12 241
                          96 64 95 243))
         (short-code #(96 212 96 23 95 57
                       96 64 95 96 212 95 95 96 9 96 100 241
                       96 64 95 243))
         (bad-flag-result
           (execute-bytecode (concat-bytes bad-flag-code bad-flag-input)
                             :context context))
         (short-result
           (execute-bytecode (concat-bytes short-code short-input)
                             :context context)))
    (let ((bad-flag-error
            (handler-case
                (progn
                  (ethereum-lisp.evm.internal::run-blake2f-precompile bad-flag-input)
                  nil)
              (ethereum-lisp.evm.internal::evm-precompile-error (condition)
                condition)))
          (short-error
            (handler-case
                (progn
                  (ethereum-lisp.evm.internal::run-blake2f-precompile short-input)
                  nil)
              (ethereum-lisp.evm.internal::evm-precompile-error (condition)
                condition))))
      (is bad-flag-error)
      (is (= ethereum-lisp.evm.internal::+precompile-consume-all-child-gas+
             (ethereum-lisp.evm.internal::evm-precompile-error-gas-used
              bad-flag-error)))
      (is short-error)
      (is (= ethereum-lisp.evm.internal::+precompile-consume-all-child-gas+
             (ethereum-lisp.evm.internal::evm-precompile-error-gas-used short-error))))
    (is (= 0 (first (evm-result-stack bad-flag-result))))
    (is (= 188 (evm-result-gas-used bad-flag-result)))
    (is (bytes= (byte-prefix-padded bad-flag-input 64)
                (evm-result-return-data bad-flag-result)))
    (is (= 0 (first (evm-result-stack short-result))))
    (is (> (evm-result-gas-used short-result)
           (evm-result-gas-used bad-flag-result)))
    (is (bytes= (byte-prefix-padded (subseq short-input 1) 64)
                (evm-result-return-data short-result)))))
