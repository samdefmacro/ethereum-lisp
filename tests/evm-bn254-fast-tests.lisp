(in-package #:ethereum-lisp.test)

;;;; The Montgomery-limb BN254 precompiles (src/runtime/evm/precompiles/
;;;; bn254-montgomery.lisp, bn254-tower.lisp, bn254-fast.lisp) against the
;;;; integer implementation they replaced, which stays in the tree as the
;;;; oracle (RUN-BN254-*-PRECOMPILE-REFERENCE), and against go-ethereum's
;;;; ECADD/ECMUL vectors (the ECPAIRING vectors are
;;;; BN254-PAIRING-REFERENCE-FIXTURE-VECTORS in evm-precompile-tests.lisp).

(defun bn254-test-prime ()
  ethereum-lisp.evm.internal::+bn254-field-prime+)

(defun bn254-test-order ()
  ethereum-lisp.evm.internal::+bn254-curve-order+)

(defun bn254-test-random-state ()
  (sb-ext:seed-random-state 20260930))

;;; Moving values between the two representations.

(defun bn254-test-fp-words (value)
  (let ((words (ethereum-lisp.evm.internal::make-bnf-words 4)))
    (ethereum-lisp.evm.internal::bnf-fp-set-integer words 0 value)
    words))

(defun bn254-test-fp2-into (words offset pair)
  (ethereum-lisp.evm.internal::bnf-fp-set-integer words offset (car pair))
  (ethereum-lisp.evm.internal::bnf-fp-set-integer words (+ offset 4) (cdr pair)))

(defun bn254-test-fp2-from (words offset)
  (cons (ethereum-lisp.evm.internal::bnf-fp-integer words offset)
        (ethereum-lisp.evm.internal::bnf-fp-integer words (+ offset 4))))

(defun bn254-test-fp6-into (words offset value)
  (loop for component in value
        for position from offset by 8
        do (bn254-test-fp2-into words position component)))

(defun bn254-test-fp6-from (words offset)
  (loop for position from offset below (+ offset 24) by 8
        collect (bn254-test-fp2-from words position)))

(defun bn254-test-fp12-words (value)
  (let ((words (ethereum-lisp.evm.internal::make-bnf-fp12)))
    (bn254-test-fp6-into words 0 (first value))
    (bn254-test-fp6-into words 24 (second value))
    words))

(defun bn254-test-fp12-from (words)
  (list (bn254-test-fp6-from words 0) (bn254-test-fp6-from words 24)))

(defun bn254-test-random-fp2 (state)
  (ethereum-lisp.evm.internal::bn254-fp2 (random (bn254-test-prime) state)
                                         (random (bn254-test-prime) state)))

(defun bn254-test-random-fp6 (state)
  (list (bn254-test-random-fp2 state) (bn254-test-random-fp2 state)
        (bn254-test-random-fp2 state)))

(defun bn254-test-random-fp12 (state)
  (list (bn254-test-random-fp6 state) (bn254-test-random-fp6 state)))

;;; Points.

(defun bn254-test-g1-bytes (x y)
  (concat-bytes (ethereum-lisp.evm.internal::integer-to-fixed-bytes x 32)
                (ethereum-lisp.evm.internal::integer-to-fixed-bytes y 32)))

(defun bn254-test-g2-bytes (x y)
  "The EVM encoding of the twist point (X, Y), each an (real . imaginary) pair."
  (concat-bytes (ethereum-lisp.evm.internal::integer-to-fixed-bytes (cdr x) 32)
                (ethereum-lisp.evm.internal::integer-to-fixed-bytes (car x) 32)
                (ethereum-lisp.evm.internal::integer-to-fixed-bytes (cdr y) 32)
                (ethereum-lisp.evm.internal::integer-to-fixed-bytes (car y) 32)))

(defparameter +bn254-test-g1+
  (bn254-test-g1-bytes 1 2))

(defparameter +bn254-test-g2+
  (hex-to-bytes
   "0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c21800deef121f1e76426a00665e5c4479674322d4f75edadd46debd5cd992f6ed090689d0585ff075ec9e99ad690c3395bc4b313370b38ef355acdadcd122975b12c85ea5db8c6deb4aab71808dcb408fe3d1e7690c43d37b4ce6cc0166fa7daa"))

;; On the twist, not in the order-r subgroup (the same point
;; EVM-CALL-BN254-PAIRING-EMPTY-ZERO-ELEMENT-AND-MALFORMED-INPUT rejects).
(defparameter +bn254-test-g2-outside-subgroup+
  (hex-to-bytes
   "0x0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000007bca656753ef8cbee60335acbffe3def91636952d4ab9eb0b839c7f3566c0e20cf32d3c49a2cb8a092f24ec3201e68dc299b6216e6321ee60573e3a7f596ea8"))

(defun bn254-test-g1-multiple (scalar)
  "SCALAR times the G1 generator, encoded (64 zero bytes for infinity)."
  (ethereum-lisp.evm.internal::run-bn254-mul-precompile
   (concat-bytes +bn254-test-g1+
                 (ethereum-lisp.evm.internal::integer-to-fixed-bytes scalar 32))))

(defun bn254-test-g2-multiple (point-bytes scalar)
  "SCALAR times the twist point encoded in POINT-BYTES, encoded; the point
need not lie in the subgroup. Jacobian arithmetic from bn254-fast.lisp."
  (ethereum-lisp.evm.internal::with-bnf-workspace ()
    (let* ((words (ethereum-lisp.evm.internal::make-bnf-words 16))
           (result (ethereum-lisp.evm.internal::make-bnf-words 24))
           (affine (ethereum-lisp.evm.internal::make-bnf-words 16))
           (inverse (ethereum-lisp.evm.internal::make-bnf-words 16))
           (bytes (ensure-byte-vector point-bytes)))
      (ethereum-lisp.evm.internal::bnf-read-canonical-fp words 4 bytes 0)
      (ethereum-lisp.evm.internal::bnf-read-canonical-fp words 0 bytes 32)
      (ethereum-lisp.evm.internal::bnf-read-canonical-fp words 12 bytes 64)
      (ethereum-lisp.evm.internal::bnf-read-canonical-fp words 8 bytes 96)
      (loop for bit from (1- (integer-length scalar)) downto 0
            do (ethereum-lisp.evm.internal::bnf-g2-double result 0)
               (when (logbitp bit scalar)
                 (ethereum-lisp.evm.internal::bnf-g2-add-affine result 0 words 0)))
      (if (ethereum-lisp.evm.internal::bnf-fp2-zero-p result 16)
          (make-byte-vector 128)
          (progn
            (ethereum-lisp.evm.internal::bnf-fp2-inverse inverse 0 result 16)
            (ethereum-lisp.evm.internal::bnf-fp2-square inverse 8 inverse 0)
            (ethereum-lisp.evm.internal::bnf-fp2-mul affine 0 result 0 inverse 8)
            (ethereum-lisp.evm.internal::bnf-fp2-mul inverse 8 inverse 8 inverse 0)
            (ethereum-lisp.evm.internal::bnf-fp2-mul affine 8 result 8 inverse 8)
            (bn254-test-g2-bytes (bn254-test-fp2-from affine 0)
                                 (bn254-test-fp2-from affine 8)))))))

(defun bn254-test-negate-g1 (bytes)
  "The encoded negation of the encoded finite G1 point BYTES."
  (let ((y (bytes-to-integer (subseq bytes 32 64))))
    (concat-bytes (subseq bytes 0 32)
                  (ethereum-lisp.evm.internal::integer-to-fixed-bytes
                   (mod (- y) (bn254-test-prime)) 32))))

;;; Field and tower routines against the integer ones.

(deftest bn254-fast-field-matches-integer-arithmetic
  (:layer :unit :module :evm)
  (let* ((p (bn254-test-prime))
         (state (bn254-test-random-state))
         (w (ethereum-lisp.evm.internal::make-bnf-words 24))
         (bytes (make-byte-vector 32))
         (cases 0))
    (flet ((random-element ()
             (case (random 8 state)
               (0 0) (1 1) (2 (1- p)) (3 (- p 2))
               (4 (random (expt 2 64) state))
               (5 (- p 1 (random (expt 2 64) state)))
               (t (random p state)))))
      (dotimes (i 5000)
        (let ((a (random-element)) (b (random-element)))
          (incf cases)
          (ethereum-lisp.evm.internal::bnf-fp-set-integer w 0 a)
          (ethereum-lisp.evm.internal::bnf-fp-set-integer w 4 b)
          (is (= a (ethereum-lisp.evm.internal::bnf-fp-integer w 0)))
          (ethereum-lisp.evm.internal::bnf-fp-mul w 8 w 0 w 4)
          (is (= (mod (* a b) p) (ethereum-lisp.evm.internal::bnf-fp-integer w 8)))
          (ethereum-lisp.evm.internal::bnf-fp-add w 8 w 0 w 4)
          (is (= (mod (+ a b) p) (ethereum-lisp.evm.internal::bnf-fp-integer w 8)))
          (ethereum-lisp.evm.internal::bnf-fp-sub w 8 w 0 w 4)
          (is (= (mod (- a b) p) (ethereum-lisp.evm.internal::bnf-fp-integer w 8)))
          (ethereum-lisp.evm.internal::bnf-fp-neg w 8 w 0)
          (is (= (mod (- a) p) (ethereum-lisp.evm.internal::bnf-fp-integer w 8)))
          ;; A destination equal to both inputs.
          (ethereum-lisp.evm.internal::bnf-fp-copy w 12 w 0)
          (ethereum-lisp.evm.internal::bnf-fp-mul w 12 w 12 w 12)
          (is (= (mod (* a a) p) (ethereum-lisp.evm.internal::bnf-fp-integer w 12)))
          (unless (zerop a)
            (ethereum-lisp.evm.internal::bnf-fp-inverse w 8 w 0)
            (is (= (ethereum-lisp.evm.internal::bn254-modular-inverse a)
                   (ethereum-lisp.evm.internal::bnf-fp-integer w 8))))))
      ;; Canonical decoding: every value below p reads back, none at or above.
      (dolist (value (list 0 1 (1- p) p (1+ p) (1- (expt 2 256))
                           (+ p (expt 2 200))))
        (replace bytes (ethereum-lisp.evm.internal::integer-to-fixed-bytes value 32))
        (let ((read-p (ethereum-lisp.evm.internal::bnf-read-canonical-fp w 0 bytes 0)))
          (is (eq (and read-p t) (< value p)))
          (when read-p
            (is (= value (ethereum-lisp.evm.internal::bnf-fp-integer w 0)))
            (let ((out (make-byte-vector 32 :initial-element 7)))
              (ethereum-lisp.evm.internal::bnf-write-fp out 0 w 0)
              (is (bytes= bytes out))))))
      (signals ethereum-lisp.evm.internal::evm-error
        (progn (ethereum-lisp.evm.internal::bnf-fp-set-zero w 0)
               (ethereum-lisp.evm.internal::bnf-fp-inverse w 4 w 0))))
    (is (= 5000 cases))))

(deftest bn254-fast-tower-matches-integer-tower
  (:layer :unit :module :evm)
  (let ((state (bn254-test-random-state)))
    (ethereum-lisp.evm.internal::with-bnf-workspace ()
      (dotimes (i 60)
        (let* ((a (bn254-test-random-fp12 state))
               (b (bn254-test-random-fp12 state))
               (wa (bn254-test-fp12-words a))
               (wb (bn254-test-fp12-words b))
               (r (ethereum-lisp.evm.internal::make-bnf-fp12))
               (fa (first a)) (fb (first b))
               (a2 (first fa)) (b2 (second fa)))
          ;; Fp2
          (ethereum-lisp.evm.internal::bnf-fp2-mul r 0 wa 0 wa 8)
          (is (equal (ethereum-lisp.evm.internal::bn254-fp2-mul a2 b2)
                     (bn254-test-fp2-from r 0)))
          (ethereum-lisp.evm.internal::bnf-fp2-square r 0 wa 0)
          (is (equal (ethereum-lisp.evm.internal::bn254-fp2-square a2)
                     (bn254-test-fp2-from r 0)))
          (ethereum-lisp.evm.internal::bnf-fp2-mul-xi r 0 wa 0)
          (is (equal (ethereum-lisp.evm.internal::bn254-fp2-mul-xi a2)
                     (bn254-test-fp2-from r 0)))
          (ethereum-lisp.evm.internal::bnf-fp2-inverse r 0 wa 0)
          (is (equal (ethereum-lisp.evm.internal::bn254-fp2-inverse a2)
                     (bn254-test-fp2-from r 0)))
          ;; Fp6
          (ethereum-lisp.evm.internal::bnf-fp6-mul r 0 wa 0 wb 0)
          (is (equal (ethereum-lisp.evm.internal::bn254-fp6-mul fa fb)
                     (bn254-test-fp6-from r 0)))
          (ethereum-lisp.evm.internal::bnf-fp6-square r 0 wa 0)
          (is (equal (ethereum-lisp.evm.internal::bn254-fp6-square fa)
                     (bn254-test-fp6-from r 0)))
          (ethereum-lisp.evm.internal::bnf-fp6-inverse r 0 wa 0)
          (is (equal (ethereum-lisp.evm.internal::bn254-fp6-inverse fa)
                     (bn254-test-fp6-from r 0)))
          (ethereum-lisp.evm.internal::bnf-fp6-mul-tau r 0 wa 0)
          (is (equal (ethereum-lisp.evm.internal::bn254-fp6-mul-tau fa)
                     (bn254-test-fp6-from r 0)))
          ;; Fp12, a destination equal to the input included.
          (ethereum-lisp.evm.internal::bnf-fp12-mul r 0 wa 0 wb 0)
          (is (equal (ethereum-lisp.evm.internal::bn254-fp12-mul a b)
                     (bn254-test-fp12-from r)))
          (ethereum-lisp.evm.internal::bnf-fp12-copy r 0 wa 0)
          (ethereum-lisp.evm.internal::bnf-fp12-square r 0 r 0)
          (is (equal (ethereum-lisp.evm.internal::bn254-fp12-square a)
                     (bn254-test-fp12-from r)))
          (ethereum-lisp.evm.internal::bnf-fp12-inverse r 0 wa 0)
          (is (equal (ethereum-lisp.evm.internal::bn254-fp12-inverse a)
                     (bn254-test-fp12-from r)))
          (ethereum-lisp.evm.internal::bnf-fp12-frobenius r 0 wa 0)
          (is (equal (ethereum-lisp.evm.internal::bn254-fp12-frobenius a)
                     (bn254-test-fp12-from r)))
          (ethereum-lisp.evm.internal::bnf-fp12-frobenius-p2 r 0 wa 0)
          (is (equal (ethereum-lisp.evm.internal::bn254-fp12-frobenius-p2 a)
                     (bn254-test-fp12-from r)))
          (let ((line (ethereum-lisp.evm.internal::make-bnf-words 24)))
            (bn254-test-fp2-into line 0 a2)
            (bn254-test-fp2-into line 8 b2)
            (bn254-test-fp2-into line 16 (third fa))
            (ethereum-lisp.evm.internal::bnf-fp12-copy r 0 wa 0)
            (ethereum-lisp.evm.internal::bnf-fp12-mul-line r 0 line 0)
            (is (equal (ethereum-lisp.evm.internal::bn254-fp12-mul-line
                        a a2 b2 (third fa))
                       (bn254-test-fp12-from r)))))))))

(deftest bn254-fast-workspace-is-required-and-bounded
  (:layer :unit :module :evm)
  (let ((w (ethereum-lisp.evm.internal::make-bnf-words 48)))
    ;; Outside WITH-BNF-WORKSPACE a routine that takes scratch refuses to
    ;; run rather than writing through a missing vector.
    (is (null ethereum-lisp.evm.internal::*bnf-workspace*))
    (signals error (ethereum-lisp.evm.internal::bnf-fp2-mul w 0 w 8 w 16))
    (signals error (ethereum-lisp.evm.internal::bnf-fp12-square w 0 w 0))
    ;; A workspace too small for the routine is refused, not overrun.
    (ethereum-lisp.evm.internal::with-bnf-workspace (16)
      (signals error (ethereum-lisp.evm.internal::bnf-fp6-mul w 0 w 0 w 24))
      (ethereum-lisp.evm.internal::bnf-fp2-mul w 0 w 8 w 16))))

;;; go-ethereum's ECADD and ECMUL vectors.

(defparameter *bn254-add-mul-vector-fixture-path*
  "tests/fixtures/execution-spec-tests/bn254-add-mul-vectors.json")

(defun load-bn254-add-mul-vector-cases (family)
  (let ((fixture (load-handwritten-fixture-file *bn254-add-mul-vector-fixture-path*)))
    (validate-fixture-object-fields
     fixture '("format" "source" "referenceClients" "add" "mul")
     "BN254 add/mul vector fixture")
    (validate-fixture-format fixture "ethereum-lisp-bn254-add-mul-vectors-v1")
    (unless (string= "38271784"
                     (fixture-required-field
                      (fixture-required-field fixture "referenceClients") "geth"))
      (error "BN254 add/mul vector geth pin drifted"))
    (mapcar (lambda (case)
              (validate-fixture-object-fields
               case '("name" "input" "expected" "gas") "BN254 add/mul vector")
              (list :name (fixture-required-field case "name")
                    :input (hex-to-bytes (fixture-required-field case "input"))
                    :expected (hex-to-bytes (fixture-required-field case "expected"))
                    :gas (fixture-required-field case "gas")))
            (fixture-required-field fixture family))))

(deftest bn254-add-and-mul-reference-fixture-vectors
  (:layer :unit :module :evm)
  (loop for (family fast reference count)
          in (list (list "add"
                         #'ethereum-lisp.evm.internal::run-bn254-add-precompile
                         #'ethereum-lisp.evm.internal::run-bn254-add-precompile-reference
                         16)
                   (list "mul"
                         #'ethereum-lisp.evm.internal::run-bn254-mul-precompile
                         #'ethereum-lisp.evm.internal::run-bn254-mul-precompile-reference
                         19))
        do (let ((cases (load-bn254-add-mul-vector-cases family)))
             (is (= count (length cases)))
             (dolist (case cases)
               (dolist (runner (list fast reference))
                 (multiple-value-bind (output gas) (funcall runner (getf case :input))
                   (is (bytes= (getf case :expected) output))
                   (is (= (getf case :gas) gas))))))))

(deftest bn254-pairing-reference-fixture-vectors-hold-for-the-oracle-too
  (:layer :unit :module :evm :estimated-seconds 5)
  (let ((cases (load-bn254-pairing-vector-cases)))
    (is (= 14 (length cases)))
    (dolist (case cases)
      (multiple-value-bind (output gas)
          (ethereum-lisp.evm.internal::run-bn254-pairing-precompile-reference
           (getf case :input))
        (is (= (getf case :gas) gas))
        (is (bytes= (getf case :expected) output))))))

;;; The differential run.

(defun bn254-differential-outcome (runner input rules)
  "What RUNNER does with INPUT: (:OK OUTPUT GAS), or (:FAIL GAS MESSAGE) for a
precompile failure, or (:ERROR TYPE MESSAGE) for any other condition."
  (handler-case (multiple-value-bind (output gas) (funcall runner input rules)
                  (list :ok output gas))
    (ethereum-lisp.evm.internal::evm-precompile-error (condition)
      (list :fail
            (ethereum-lisp.evm.internal::evm-precompile-error-gas-used condition)
            (princ-to-string condition)))
    (error (condition)
      (list :error (type-of condition) (princ-to-string condition)))))

(defun bn254-differential-mismatches (cases)
  "The CASES, each (LABEL FAST REFERENCE INPUT RULES), whose two runners
disagree on output, gas, failure or failure message."
  (loop for (label fast reference input rules) in cases
        for fast-outcome = (bn254-differential-outcome fast input rules)
        for reference-outcome = (bn254-differential-outcome reference input rules)
        unless (equalp fast-outcome reference-outcome)
          collect (list label input fast-outcome reference-outcome)))

(defun bn254-differential-cases (state)
  "10,000 labelled inputs for 0x06, 0x07 and 0x08: valid and invalid points,
points outside the subgroup, infinity, 1-4 pairs, true and false products,
short, long and malformed lengths, under Istanbul and Byzantium gas."
  (let* ((p (bn254-test-prime))
         (r (bn254-test-order))
         (byzantium (make-chain-rules :byzantium-p t))
         (add (list #'ethereum-lisp.evm.internal::run-bn254-add-precompile
                    #'ethereum-lisp.evm.internal::run-bn254-add-precompile-reference))
         (mul (list #'ethereum-lisp.evm.internal::run-bn254-mul-precompile
                    #'ethereum-lisp.evm.internal::run-bn254-mul-precompile-reference))
         (pairing
           (list #'ethereum-lisp.evm.internal::run-bn254-pairing-precompile
                 #'ethereum-lisp.evm.internal::run-bn254-pairing-precompile-reference))
         (scalars (loop repeat 24 collect (1+ (random (1- r) state))))
         (g1-pool (mapcar #'bn254-test-g1-multiple scalars))
         (g2-scalars (loop repeat 6 collect (1+ (random (1- r) state))))
         (g2-pool (mapcar (lambda (k) (bn254-test-g2-multiple +bn254-test-g2+ k))
                          g2-scalars))
         (g2-outside (loop repeat 4
                           collect (bn254-test-g2-multiple
                                    +bn254-test-g2-outside-subgroup+
                                    (1+ (random (1- r) state)))))
         (cases nil))
    (labels ((pick (list) (nth (random (length list) state) list))
             (rules () (if (zerop (random 10 state)) byzantium nil))
             (emit (label runners input)
               (push (list label (first runners) (second runners) input (rules))
                     cases))
             (g1 () (pick g1-pool))
             (bad-g1 ()
               (let ((point (copy-seq (g1))))
                 (ecase (random 4 state)
                   (0 (replace point (ethereum-lisp.evm.internal::integer-to-fixed-bytes
                                      (+ p (random (- (expt 2 256) p) state)) 32)))
                   (1 (replace point (ethereum-lisp.evm.internal::integer-to-fixed-bytes
                                      (+ p (random (- (expt 2 256) p) state)) 32)
                               :start1 32))
                   (2 (replace point (ethereum-lisp.evm.internal::integer-to-fixed-bytes
                                      (mod (1+ (bytes-to-integer (subseq point 32)))
                                           p)
                                      32)
                               :start1 32))
                   (3 (replace point (ethereum-lisp.evm.internal::integer-to-fixed-bytes
                                      (random p state) 32))))
                 point))
             (any-g1 ()
               (case (random 10 state)
                 (0 (make-byte-vector 64))
                 (1 (bad-g1))
                 (t (g1))))
             (random-bytes (n)
               (let ((bytes (make-byte-vector n)))
                 (dotimes (i n bytes)
                   (setf (aref bytes i) (random 256 state)))))
             (resize (input)
               ;; Truncated inputs are zero-padded and longer ones ignore
               ;; the tail, for ECADD and ECMUL.
               (case (random 8 state)
                 (0 (subseq input 0 (random (length input) state)))
                 (1 (concat-bytes input (random-bytes (1+ (random 40 state)))))
                 (t input)))
             (scalar ()
               (ethereum-lisp.evm.internal::integer-to-fixed-bytes
                (case (random 12 state)
                  (0 0) (1 1) (2 2) (3 (1- r)) (4 r) (5 (1+ r))
                  (6 (1- (expt 2 256))) (7 (random 65536 state))
                  (t (random (expt 2 256) state)))
                32))
             (bad-g2 ()
               (let ((point (copy-seq (pick g2-pool))))
                 (ecase (random 3 state)
                   (0 (replace point (ethereum-lisp.evm.internal::integer-to-fixed-bytes
                                      (+ p (random (- (expt 2 256) p) state)) 32)
                               :start1 (* 32 (random 4 state))))
                   (1 (setf (aref point 127) (logxor (aref point 127) 1)))
                   (2 (replace point (random-bytes 32) :start1 (* 32 (random 4 state)))))
                 point))
             (pair-element ()
               (case (random 20 state)
                 (0 (concat-bytes (make-byte-vector 64) (pick g2-pool)))
                 (1 (concat-bytes (g1) (make-byte-vector 128)))
                 (t (concat-bytes (g1) (pick g2-pool)))))
             (bilinear-product (off-by)
               ;; e(aG1, bG2) e(cG1, dG2) e(-(ab + cd + OFF-BY) G1, G2): one
               ;; exactly when OFF-BY is zero, by bilinearity alone. (A
               ;; product like e(P, Q) e(-P, Q) would not do: its Miller
               ;; values are conjugates, so the easy part of the final
               ;; exponentiation already yields one.)
               (let* ((i (random (length g1-pool) state))
                      (j (random (length g2-pool) state))
                      (terms (list (list (nth i scalars) (nth j g2-scalars)
                                         (nth i g1-pool) (nth j g2-pool))))
                      (pairs nil))
                 (when (zerop (random 2 state))
                   (let ((k (random (length g1-pool) state))
                         (l (random (length g2-pool) state)))
                     (push (list (nth k scalars) (nth l g2-scalars)
                                 (nth k g1-pool) (nth l g2-pool))
                           terms)))
                 (dolist (term terms)
                   (push (concat-bytes (third term) (fourth term)) pairs))
                 (push (concat-bytes
                        (bn254-test-g1-multiple
                         (mod (- (+ off-by
                                    (loop for (a b) in terms sum (* a b))))
                              r))
                        +bn254-test-g2+)
                       pairs)
                 pairs))
             (true-product ()
               ;; A bilinear product of one, sometimes with a pair holding
               ;; infinity, shuffled; up to four pairs.
               (let ((pairs (bilinear-product
                             (if (zerop (random 4 state)) (1+ (random 5 state)) 0))))
                 (when (and (< (length pairs) 4) (zerop (random 3 state)))
                   (push (if (zerop (random 2 state))
                             (concat-bytes (make-byte-vector 64) (pick g2-pool))
                             (concat-bytes (g1) (make-byte-vector 128)))
                         pairs))
                 (let ((pairs (coerce pairs 'vector)))
                   ;; Fisher-Yates, so the cancelling pair is not always
                   ;; adjacent or first.
                   (loop for i from (1- (length pairs)) downto 1
                         do (rotatef (aref pairs i)
                                     (aref pairs (random (1+ i) state))))
                   (apply #'concat-bytes (coerce pairs 'list))))))
      ;; ECADD: 5,000.
      (dotimes (i 5000)
        (let ((left (any-g1)) (right (any-g1)))
          (case (random 10 state)
            (0 (setf right left))
            (1 (unless (every #'zerop left)
                 (setf right (bn254-test-negate-g1 left)))))
          (emit :add add (resize (concat-bytes left right)))))
      ;; ECMUL: 2,500, a third with full-width scalars (the oracle's cost).
      (dotimes (i 2500)
        (let ((point (any-g1))
              (scalar (if (< i 800)
                          (ethereum-lisp.evm.internal::integer-to-fixed-bytes
                           (random (expt 2 256) state) 32)
                          (scalar))))
          (unless (< i 800)
            (when (zerop (random 3 state))
              ;; Small scalars keep most of the oracle's runs short.
              (setf scalar (ethereum-lisp.evm.internal::integer-to-fixed-bytes
                            (random 1024 state) 32))))
          (emit :mul mul (resize (concat-bytes point scalar)))))
      ;; ECPAIRING: 2,500.
      (dotimes (i 2500)
        (emit :pairing pairing
              (cond
                ((< i 150)
                 (apply #'concat-bytes
                        (loop repeat (1+ (random 4 state)) collect (pair-element))))
                ((< i 300) (true-product))
                ((< i 380)
                 (concat-bytes (g1) (pick g2-outside)))
                ((< i 1200)
                 (concat-bytes (if (zerop (random 3 state)) (bad-g1) (g1))
                               (bad-g2)))
                ((< i 1900)
                 (concat-bytes (bad-g1) (pick g2-pool)))
                ((< i 2200)
                 (random-bytes (let ((n (random 600 state)))
                                 (if (zerop (mod n 192)) (1+ n) n))))
                ((< i 2300)
                 (apply #'concat-bytes
                        (loop repeat (1+ (random 4 state))
                              collect (concat-bytes (make-byte-vector 64)
                                                    (make-byte-vector 128)))))
                (t
                 (concat-bytes (make-byte-vector 64) (pick g2-pool)
                               (concat-bytes (g1) (make-byte-vector 128))))))))
    (nreverse cases)))

(deftest bn254-fast-precompiles-match-the-integer-oracle
  (:layer :unit :module :evm :estimated-seconds 90)
  (let* ((cases (bn254-differential-cases (bn254-test-random-state)))
         (mismatches (bn254-differential-mismatches cases))
         (outcomes (make-hash-table :test 'equal)))
    (is (= 10000 (length cases)))
    ;; Non-vacuity: the families the brief names all occur, and the oracle
    ;; answers them with successes, failures, true and false products.
    (loop for (label nil reference input rules) in cases
          for outcome = (bn254-differential-outcome reference input rules)
          do (incf (gethash (list label
                                  (first outcome)
                                  (and (eq label :pairing)
                                       (eq (first outcome) :ok)
                                       (= 1 (aref (second outcome) 31))))
                            outcomes
                            0)))
    (dolist (key '((:add :ok nil) (:add :fail nil) (:mul :ok nil) (:mul :fail nil)
                   (:pairing :ok t) (:pairing :ok nil) (:pairing :fail nil)))
      (is (< 20 (gethash key outcomes 0))))
    (when mismatches
      (format t "~&BN254 differential: ~D mismatches, first ~S~%"
              (length mismatches) (first mismatches)))
    (is (null mismatches))))

(deftest bn254-differential-comparison-can-fail
  (:layer :unit :module :evm)
  ;; Positive control for BN254-FAST-PRECOMPILES-MATCH-THE-INTEGER-ORACLE:
  ;; a runner that differs in output, in gas or in failing must be reported.
  (let* ((input (concat-bytes +bn254-test-g1+ (bn254-test-g1-multiple 2)))
         (reference #'ethereum-lisp.evm.internal::run-bn254-add-precompile-reference)
         (wrong-output (lambda (input rules)
                         (multiple-value-bind (output gas)
                             (ethereum-lisp.evm.internal::run-bn254-add-precompile
                              input rules)
                           (let ((copy (copy-seq output)))
                             (setf (aref copy 63) (logxor 1 (aref copy 63)))
                             (values copy gas)))))
         (wrong-gas (lambda (input rules)
                      (multiple-value-bind (output gas)
                          (ethereum-lisp.evm.internal::run-bn254-add-precompile
                           input rules)
                        (values output (1+ gas)))))
         (wrongly-failing (lambda (input rules)
                            (declare (ignore input))
                            (ethereum-lisp.evm.internal::fail-precompile
                             (ethereum-lisp.evm.internal::bn254-add-gas rules)
                             "Invalid BN254 G1 point"))))
    (is (null (bn254-differential-mismatches
               (list (list :add #'ethereum-lisp.evm.internal::run-bn254-add-precompile
                           reference input nil)))))
    (dolist (runner (list wrong-output wrong-gas wrongly-failing))
      (is (= 1 (length (bn254-differential-mismatches
                        (list (list :add runner reference input nil)))))))))
