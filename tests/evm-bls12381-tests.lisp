(in-package #:ethereum-lisp.test)

;;;; EIP-2537 BLS12-381 precompile tests.
;;;;
;;;; The unit tests cover everything the Lisp layer owns — activation, gas, and
;;;; input framing — and run without a backend. The reference-vector tests are
;;;; integration tests because they launch the real helper process.

(defparameter +bls12381-precompile-numbers+ '(11 12 13 14 15 16 17))

(defun bls12381-prague-rules ()
  (make-chain-rules :chain-id 1 :shanghai-p t :cancun-p t :prague-p t))

(defun bls12381-pre-prague-rules ()
  (make-chain-rules :chain-id 1 :shanghai-p t :cancun-p t))

(deftest bls12381-precompiles-are-prague-gated
  (let ((prague (bls12381-prague-rules))
        (pre-prague (bls12381-pre-prague-rules)))
    (dolist (number +bls12381-precompile-numbers+)
      (let ((address (precompile-address number)))
        (is (= number (bytes-to-integer (address-bytes address))))
        (is (ethereum-lisp.evm.internal::active-precompile-address-p
             address prague))
        (is (not (ethereum-lisp.evm.internal::active-precompile-address-p
                  address pre-prague)))))
    ;; Addresses immediately outside the range must stay inactive.
    (is (not (ethereum-lisp.evm.internal::active-precompile-address-p
              (precompile-address 18) prague)))))

(deftest bls12381-precompiles-are-prewarmed-from-prague
  (let ((prague-warm (ethereum-lisp.evm.internal::make-initial-accessed-addresses
                      (bls12381-prague-rules)))
        (pre-prague-warm (ethereum-lisp.evm.internal::make-initial-accessed-addresses
                          (bls12381-pre-prague-rules))))
    (dolist (number +bls12381-precompile-numbers+)
      (let ((key (address-bytes (precompile-address number))))
        (is (gethash key prague-warm))
        (is (not (gethash key pre-prague-warm)))))))

;;; Gas.

(deftest bls12381-flat-gas-matches-eip2537
  (is (= 375 ethereum-lisp.evm.internal::+bls12381-g1-add-gas+))
  (is (= 600 ethereum-lisp.evm.internal::+bls12381-g2-add-gas+))
  (is (= 5500 ethereum-lisp.evm.internal::+bls12381-map-fp-to-g1-gas+))
  (is (= 23800 ethereum-lisp.evm.internal::+bls12381-map-fp2-to-g2-gas+)))

(deftest bls12381-msm-gas-follows-the-discount-table
  (let ((g1-discounts ethereum-lisp.evm.internal::+bls12381-g1-msm-discounts+)
        (g2-discounts ethereum-lisp.evm.internal::+bls12381-g2-msm-discounts+))
    (is (= 128 (length g1-discounts)))
    (is (= 128 (length g2-discounts)))
    (is (= 1000 (aref g1-discounts 0)))
    (is (= 519 (aref g1-discounts 127)))
    (is (= 1000 (aref g2-discounts 0)))
    (is (= 524 (aref g2-discounts 127)))
    ;; Recompute the schedule independently of the implementation.
    (dolist (pair-count '(1 2 17 127 128))
      (let ((g1-input (make-byte-vector (* pair-count 160)))
            (g2-input (make-byte-vector (* pair-count 288))))
        (is (= (floor (* pair-count 12000 (aref g1-discounts (1- pair-count)))
                      1000)
               (ethereum-lisp.evm.internal::bls12381-g1-msm-gas g1-input)))
        (is (= (floor (* pair-count 22500 (aref g2-discounts (1- pair-count)))
                      1000)
               (ethereum-lisp.evm.internal::bls12381-g2-msm-gas g2-input)))))
    ;; Above the table both curves hold the final discount.
    (is (= (floor (* 200 12000 519) 1000)
           (ethereum-lisp.evm.internal::bls12381-g1-msm-gas
            (make-byte-vector (* 200 160)))))
    (is (= (floor (* 200 22500 524) 1000)
           (ethereum-lisp.evm.internal::bls12381-g2-msm-gas
            (make-byte-vector (* 200 288)))))))

(deftest bls12381-pairing-gas-follows-eip2537
  (dolist (pair-count '(1 2 5 20))
    (is (= (+ 37700 (* 32600 pair-count))
           (ethereum-lisp.evm.internal::bls12381-pairing-gas
            (make-byte-vector (* pair-count 384)))))))

;;; Input framing. These run before the backend is consulted, so they hold
;;; whether or not one is installed.

(deftest bls12381-precompiles-reject-malformed-input-lengths
  (let ((*bls12381-backend* nil))
    (labels ((rejects (function size)
               (signals ethereum-lisp.evm.internal::evm-precompile-error
                 (funcall function (make-byte-vector size)))))
      ;; Fixed-length operations reject anything but their exact size.
      (rejects #'ethereum-lisp.evm.internal::run-bls12381-g1-add-precompile 255)
      (rejects #'ethereum-lisp.evm.internal::run-bls12381-g1-add-precompile 257)
      (rejects #'ethereum-lisp.evm.internal::run-bls12381-g2-add-precompile 511)
      (rejects #'ethereum-lisp.evm.internal::run-bls12381-map-fp-to-g1-precompile 63)
      (rejects #'ethereum-lisp.evm.internal::run-bls12381-map-fp2-to-g2-precompile 127)
      ;; Variable-length operations reject empty input and partial blocks.
      (rejects #'ethereum-lisp.evm.internal::run-bls12381-g1-msm-precompile 0)
      (rejects #'ethereum-lisp.evm.internal::run-bls12381-g1-msm-precompile 159)
      (rejects #'ethereum-lisp.evm.internal::run-bls12381-g2-msm-precompile 0)
      (rejects #'ethereum-lisp.evm.internal::run-bls12381-g2-msm-precompile 287)
      (rejects #'ethereum-lisp.evm.internal::run-bls12381-pairing-check-precompile 0)
      (rejects #'ethereum-lisp.evm.internal::run-bls12381-pairing-check-precompile 383))))

;;; Capability gating.

(deftest bls12381-operations-require-an-installed-backend
  (let ((*bls12381-backend* nil))
    (is (not (bls12381-backend-available-p)))
    (let ((condition (handler-case
                         (progn (run-bls12381-operation
                                 :g1-add (make-byte-vector 256))
                                nil)
                       (error (condition) condition))))
      (is condition)
      (is (search "not available" (princ-to-string condition))))
    ;; A well-formed input must make the node REFUSE, not fabricate a
    ;; precompile failure a node with a working backend would not produce.
    ;; The unavailable condition is not an evm-precompile-error, so it
    ;; propagates past the EVM's precompile handling to abort validation.
    (signals bls12381-unavailable-error
      (ethereum-lisp.evm.internal::run-bls12381-g1-add-precompile
       (make-byte-vector 256)))
    (let ((converted-to-precompile-failure nil))
      (handler-case
          (ethereum-lisp.evm.internal::run-bls12381-g1-add-precompile
           (make-byte-vector 256))
        (ethereum-lisp.evm.internal::evm-precompile-error ()
          (setf converted-to-precompile-failure t))
        (bls12381-unavailable-error () nil))
      (is (not converted-to-precompile-failure)))))

(deftest bls12381-unknown-operations-are-refused
  (let ((*bls12381-backend* (lambda (operation input)
                              (declare (ignore operation input))
                              (make-byte-vector 128))))
    (signals error (run-bls12381-operation :not-an-operation (make-byte-vector 8)))))

;;; Dispatch plumbing, exercised with a recording stub backend.

(deftest bls12381-precompiles-dispatch-to-the-installed-backend
  (let* ((calls '())
         (outputs (list (cons :g1-add 128) (cons :g1-msm 128)
                        (cons :g2-add 256) (cons :g2-msm 256)
                        (cons :pairing-check 32) (cons :map-fp-to-g1 128)
                        (cons :map-fp2-to-g2 256)))
         (*bls12381-backend*
           (lambda (operation input)
             (push (cons operation (length input)) calls)
             (make-byte-vector (cdr (assoc operation outputs)))))
         (rules (bls12381-prague-rules))
         (inputs (list (cons 11 256) (cons 12 160) (cons 13 512) (cons 14 288)
                       (cons 15 384) (cons 16 64) (cons 17 128))))
    (dolist (entry inputs)
      (let ((number (car entry))
            (size (cdr entry)))
        (multiple-value-bind (output gas active-p)
            (execute-precompile (precompile-address number)
                                (make-byte-vector size)
                                rules
                                10000000)
          (declare (ignore output))
          (is active-p)
          (is (plusp gas)))))
    ;; Every address reached the backend exactly once, with the input intact.
    (is (= 7 (length calls)))
    (is (equal (list 128 64 384 288 512 160 256)
               (mapcar #'cdr calls)))))

(deftest bls12381-backend-output-size-is-validated
  ;; A wrong-sized OK reply is a backend defect, not an input verdict, so it
  ;; must refuse rather than become a deterministic precompile failure.
  (let ((*bls12381-backend* (lambda (operation input)
                              (declare (ignore operation input))
                              (make-byte-vector 7))))
    (signals bls12381-unavailable-error
      (ethereum-lisp.evm.internal::run-bls12381-g1-add-precompile
       (make-byte-vector 256)))))

(deftest bls12381-input-verdict-fails-precompile-but-transport-refuses
  ;; The consensus-critical distinction: a backend verdict that the input is
  ;; invalid is deterministic and burns gas as a precompile failure; a backend
  ;; that cannot answer must not be turned into that same deterministic failure.
  (let ((*bls12381-backend*
          (lambda (operation input)
            (declare (ignore operation input))
            (bls12381-input-error "point is not on the curve"))))
    (let ((condition (handler-case
                         (progn
                           (ethereum-lisp.evm.internal::run-bls12381-g1-add-precompile
                            (make-byte-vector 256))
                           nil)
                       (ethereum-lisp.evm.internal::evm-precompile-error
                         (condition) condition))))
      (is condition)
      (is (= ethereum-lisp.evm.internal::+bls12381-g1-add-gas+
             (ethereum-lisp.evm.internal::evm-precompile-error-gas-used
              condition)))))
  (let ((*bls12381-backend*
          (lambda (operation input)
            (declare (ignore operation input))
            (bls12381-unavailable-error "helper process crashed"))))
    (signals bls12381-unavailable-error
      (ethereum-lisp.evm.internal::run-bls12381-g1-add-precompile
       (make-byte-vector 256)))))

;;; Reference vectors, replayed through the real helper process.

(defconstant +bls12381-vector-fixture-path+
  "tests/fixtures/execution-spec-tests/bls12381-vectors.json")

(defparameter +bls12381-vector-fixture-fields+
  '("format" "source" "referenceClients" "operations" "failures"))

(defparameter +bls12381-vector-operations+
  '(("g1add" . :g1-add)
    ("g1msm" . :g1-msm)
    ("g2add" . :g2-add)
    ("g2msm" . :g2-msm)
    ("pairing" . :pairing-check)
    ("mapfptog1" . :map-fp-to-g1)
    ("mapfp2tog2" . :map-fp2-to-g2)))

(defun bls12381-vector-hex-bytes (value label)
  (unless (and (stringp value)
               (<= 2 (length value))
               (string= "0x" value :end2 2)
               (string= value (string-downcase value)))
    (error "~A must be a lowercase 0x-prefixed hex string" label))
  (hex-to-bytes value))

(defun load-bls12381-vector-fixture
    (&optional (path +bls12381-vector-fixture-path+))
  (let ((fixture (load-handwritten-fixture-file path)))
    (validate-fixture-object-fields
     fixture
     +bls12381-vector-fixture-fields+
     "BLS12-381 vector fixture")
    (validate-fixture-format fixture "ethereum-lisp-bls12381-vectors-v1")
    (unless (string= "go-ethereum core/vm/testdata/precompiles/bls*.json"
                     (validate-fixture-required-string-field
                      fixture "source" "BLS12-381 vector fixture"))
      (error "BLS12-381 vector fixture source is not the geth vector files"))
    (let ((references (fixture-required-field fixture "referenceClients")))
      (validate-fixture-object-fields
       references '("geth") "BLS12-381 vector reference clients")
      (unless (string= "3003a13440e801174f0035037a7c83462d67a8ea"
                       (validate-fixture-required-string-field
                        references "geth" "BLS12-381 vector geth pin"))
        (error "BLS12-381 vector geth pin drifted")))
    fixture))

(defun bls12381-fixture-success-cases (fixture)
  (let ((operations (fixture-required-field fixture "operations"))
        (cases '()))
    (dolist (entry +bls12381-vector-operations+ (nreverse cases))
      (let* ((group (fixture-required-field operations (car entry)))
             (vectors (fixture-required-field group "vectors")))
        (unless (and (listp vectors) (plusp (length vectors)))
          (error "BLS12-381 fixture group ~A has no vectors" (car entry)))
        (dolist (vector vectors)
          (push (list :operation (cdr entry)
                      :precompile (fixture-required-field group "precompile")
                      :name (fixture-required-field vector "name")
                      :input (bls12381-vector-hex-bytes
                              (fixture-required-field vector "input")
                              "BLS12-381 vector input")
                      :expected (bls12381-vector-hex-bytes
                                 (fixture-required-field vector "expected")
                                 "BLS12-381 vector expected output"))
                cases))))))

(defun bls12381-fixture-failure-cases (fixture)
  (let ((failures (fixture-required-field fixture "failures"))
        (cases '()))
    (dolist (entry +bls12381-vector-operations+ (nreverse cases))
      (dolist (vector (fixture-required-field failures (car entry)))
        (push (list :operation (cdr entry)
                    :name (fixture-required-field vector "name")
                    :input (bls12381-vector-hex-bytes
                            (fixture-required-field vector "input")
                            "BLS12-381 failure vector input"))
              cases)))))

(defun call-with-bls12381-repo-backend (thunk)
  "Run THUNK with the in-process blst CFFI backend installed."
  (let ((backend (make-bls12381-cffi-backend)))
    (unless backend
      (skip-test "blst CFFI backend (libethbls) is unavailable"))
    (let ((*bls12381-backend* backend))
      (funcall thunk))))

(deftest bls12381-reference-fixture-vectors
  (:layer :integration :module :bls12381)
  (let ((cases (bls12381-fixture-success-cases (load-bls12381-vector-fixture))))
    (is (plusp (length cases)))
    (call-with-bls12381-repo-backend
     (lambda ()
       (dolist (case cases)
         (let ((output (run-bls12381-operation (getf case :operation)
                                               (getf case :input))))
           (unless (bytes= (getf case :expected) output)
             (error "BLS12-381 vector ~A diverged from the reference output"
                    (getf case :name)))
           (is (bytes= (getf case :expected) output))))))))

(deftest bls12381-reference-fixture-failures-are-rejected
  (:layer :integration :module :bls12381)
  (let ((cases (bls12381-fixture-failure-cases (load-bls12381-vector-fixture))))
    (is (plusp (length cases)))
    (call-with-bls12381-repo-backend
     (lambda ()
       (dolist (case cases)
         (let ((accepted (handler-case
                             (progn (run-bls12381-operation
                                     (getf case :operation)
                                     (getf case :input))
                                    t)
                           (error () nil))))
           (when accepted
             (error "BLS12-381 failure vector ~A was accepted"
                    (getf case :name)))
           (is (not accepted))))))))
