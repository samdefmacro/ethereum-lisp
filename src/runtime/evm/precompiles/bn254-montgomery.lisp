(in-package #:ethereum-lisp.evm.internal)

;;;; BN254 base-field arithmetic in Montgomery form over four 64-bit limbs.
;;;;
;;;; Every field element lives in a word vector (BNF-WORDS) at an offset:
;;;; four little-endian limbs holding x*R mod p, R = 2^256, always fully
;;;; reduced below p, so equal values have equal limbs. Operations write their
;;;; result into a destination (vector, offset) and read every input before the
;;;; first write, so a destination may alias an input. Nothing here allocates
;;;; a bignum: products and carries are 64-bit modular operations.
;;;;
;;;; The multiplication is CIOS Montgomery multiplication with the
;;;; "no-carry" shortcut, valid because p's top limb is below 2^63 - 1
;;;; (gnark-crypto uses the same schedule for this field). The integer
;;;; implementation in bn254-base.lisp is the oracle these routines are
;;;; tested against (tests/evm-bn254-fast-tests.lisp).
;;;;
;;;; The carry helpers are built from single-result operations (a modular
;;;; product, SB-KERNEL:%MULTIPLY-HIGH, modular sums and unsigned
;;;; comparisons) on purpose. SBCL 2.2.9's arm64 VOP for the four-argument
;;;; SB-BIGNUM:%MULTIPLY-AND-ADD writes its low result before it reads its
;;;; addends, so when the register allocator gives that result the register
;;;; of a dying addend the addend is lost (observed: (* 2 3) Montgomery
;;;; product wrong, the disassembly adding the product to itself).

(deftype bnf-words () '(simple-array (unsigned-byte 64) (*)))
(deftype bnf-index () '(integer 0 4096))

;;; The limb routines compile with SAFETY 0, which drops bounds checks: every
;;; offset they are given is a layout constant of the calling routine plus a
;;; base that routine owns, and the differential tests run each caller.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun bnf-limb (integer index)
    (ldb (byte 64 (* 64 index)) integer))

  (defun bnf-negated-inverse-word (modulus)
    "Return -MODULUS^-1 mod 2^64 by Newton iteration."
    (let ((inverse 1))
      (loop repeat 7
            do (setf inverse (ldb (byte 64 0)
                                  (* inverse (- 2 (* modulus inverse))))))
      (ldb (byte 64 0) (- inverse)))))

(defconstant +bnf-p0+ (bnf-limb +bn254-field-prime+ 0))
(defconstant +bnf-p1+ (bnf-limb +bn254-field-prime+ 1))
(defconstant +bnf-p2+ (bnf-limb +bn254-field-prime+ 2))
(defconstant +bnf-p3+ (bnf-limb +bn254-field-prime+ 3))
(defconstant +bnf-inverse-word+
  (bnf-negated-inverse-word +bn254-field-prime+))

(defun make-bnf-words (count)
  (make-array count :element-type '(unsigned-byte 64) :initial-element 0))

;;; Temporaries. SBCL 2.2.9 does not stack-allocate unboxed word vectors on
;;; arm64 (DYNAMIC-EXTENT is ignored with a note), and heap temporaries cost
;;; a pairing 2.7 MB of garbage. Each operation instead binds one workspace
;;; (thread-local, being a special binding) and every routine takes its
;;; temporaries from the region above the current top, restoring the top on
;;; exit.

(defconstant +bnf-workspace-words+ 512
  "Enough for the deepest nesting, the final exponentiation (under 300 words).")

(defconstant +bnf-g1-workspace-words+ 64
  "Enough for G1 decoding, addition and scalar multiplication (48 words).")

(defvar *bnf-workspace* nil
  "The word vector BN254 routines take temporaries from; see WITH-BNF-WORKSPACE.")

(defvar *bnf-workspace-top* 0
  "The first free word of *BNF-WORKSPACE*.")
(declaim (type bnf-index *bnf-workspace-top*))

(defmacro with-bnf-workspace ((&optional (words '+bnf-workspace-words+))
                              &body body)
  "Run BODY with a fresh workspace of WORDS words for the BN254 arithmetic it
calls. A routine that needs more than is left signals an error."
  `(let ((*bnf-workspace* (make-bnf-words ,words))
         (*bnf-workspace-top* 0))
     ,@body))

(defmacro with-bnf-scratch ((vector &rest slots) &body body)
  "Bind VECTOR to the workspace and each slot (NAME WORDS) to the offset of a
region of WORDS words above the current top, reserved for BODY's extent."
  (let ((base (gensym "BASE"))
        (total (reduce #'+ slots :key #'second))
        (offset 0))
    `(let ((,vector *bnf-workspace*)
           (,base *bnf-workspace-top*))
       (unless (and ,vector
                    (<= (+ ,base ,total) (length (the bnf-words ,vector))))
         (error "BN254 scratch needs ~D words above ~D in a WITH-BNF-WORKSPACE"
                ,total ,base))
       (let (,@(loop for (name words) in slots
                     collect `(,name (+ ,base ,offset))
                     do (incf offset words))
             (*bnf-workspace-top* (+ ,base ,total)))
         (declare (type bnf-words ,vector)
                  (type bnf-index ,@(mapcar #'first slots))
                  (ignorable ,@(mapcar #'first slots)))
         ,@body))))

(defun bnf-integer-words (value)
  "Return VALUE (below 2^256) as a fresh four-limb vector, not Montgomery."
  (let ((words (make-bnf-words 4)))
    (dotimes (i 4 words)
      (setf (aref words i) (bnf-limb value i)))))

(defun bnf-words-integer (words offset)
  "Return the integer the four limbs at OFFSET hold, read as they are."
  (loop for i below 4
        sum (ash (aref words (+ offset i)) (* 64 i))))

;;; Word arithmetic, inlined into its callers. Carries and borrows are
;;; computed from the operands' top bits rather than by comparison, and the
;;; conditional corrections below select with masks: on random field
;;; elements every such branch is a coin flip, and mispredicting them cost
;;; a factor of four (one Fp2 product 370 ns against 90 ns on repeated
;;; inputs, SBCL 2.2.9 arm64).

(declaim (inline %bnf-carry %bnf-borrow %bnf-mac %bnf-adc %bnf-sbb %bnf-select
                 %bnf-store4 %bnf-store-reduced))

(defun %bnf-carry (x y sum)
  "The carry out of the 64-bit sum X + Y = SUM (mod 2^64), as 0 or 1."
  (declare (type (unsigned-byte 64) x y sum))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (ash (logior (logand x y) (logandc2 (logior x y) sum)) -63))

(defun %bnf-borrow (x y difference)
  "The borrow out of X - Y = DIFFERENCE (mod 2^64), as 0 or 1."
  (declare (type (unsigned-byte 64) x y difference))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (ash (logior (logandc1 x y) (logandc1 (logxor x y) difference)) -63))

(defun %bnf-mac (a b c d)
  "Return (VALUES HIGH LOW) of A*B + C + D, which fits 128 bits."
  (declare (type (unsigned-byte 64) a b c d))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (let* ((low (ldb (byte 64 0) (* a b)))
         (high (sb-kernel:%multiply-high a b))
         (sum (ldb (byte 64 0) (+ low c)))
         (sum2 (ldb (byte 64 0) (+ sum d))))
    (declare (type (unsigned-byte 64) low high sum sum2))
    (values (ldb (byte 64 0) (+ high (%bnf-carry low c sum) (%bnf-carry sum d sum2)))
            sum2)))

(defun %bnf-adc (a b carry)
  "Return (VALUES SUM CARRY-OUT) of A + B + CARRY, CARRY being 0 or 1."
  (declare (type (unsigned-byte 64) a b) (type bit carry))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (let* ((sum (ldb (byte 64 0) (+ a b)))
         (sum2 (ldb (byte 64 0) (+ sum carry))))
    (declare (type (unsigned-byte 64) sum sum2))
    (values sum2 (logior (%bnf-carry a b sum) (%bnf-carry sum carry sum2)))))

(defun %bnf-sbb (a b borrow)
  "Return (VALUES DIFFERENCE BORROW-OUT) of A - B - BORROW mod 2^64."
  (declare (type (unsigned-byte 64) a b) (type bit borrow))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (let* ((difference (ldb (byte 64 0) (- a b)))
         (difference2 (ldb (byte 64 0) (- difference borrow))))
    (declare (type (unsigned-byte 64) difference difference2))
    (values difference2
            (logior (%bnf-borrow a b difference)
                    (%bnf-borrow difference borrow difference2)))))

(defun %bnf-select (flag when-set when-clear)
  "WHEN-SET if FLAG is 1, WHEN-CLEAR if it is 0, without a branch."
  (declare (type bit flag) (type (unsigned-byte 64) when-set when-clear))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (let ((mask (ldb (byte 64 0) (- flag))))
    (logxor when-clear (logand mask (logxor when-set when-clear)))))

(defun %bnf-store4 (r ro w0 w1 w2 w3)
  (declare (type bnf-words r) (type bnf-index ro)
           (type (unsigned-byte 64) w0 w1 w2 w3))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (setf (aref r ro) w0
        (aref r (+ ro 1)) w1
        (aref r (+ ro 2)) w2
        (aref r (+ ro 3)) w3)
  nil)

(defun %bnf-store-reduced (r ro s0 s1 s2 s3)
  "Store S (below 2p) at R/RO, subtracting p once when S >= p."
  (declare (type bnf-words r) (type bnf-index ro)
           (type (unsigned-byte 64) s0 s1 s2 s3))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (multiple-value-bind (d0 b0) (%bnf-sbb s0 +bnf-p0+ 0)
    (multiple-value-bind (d1 b1) (%bnf-sbb s1 +bnf-p1+ b0)
      (multiple-value-bind (d2 b2) (%bnf-sbb s2 +bnf-p2+ b1)
        (multiple-value-bind (d3 b3) (%bnf-sbb s3 +bnf-p3+ b2)
          ;; A final borrow means S < p: keep S.
          (%bnf-store4 r ro
                       (%bnf-select b3 s0 d0) (%bnf-select b3 s1 d1)
                       (%bnf-select b3 s2 d2) (%bnf-select b3 s3 d3)))))))

;;; Field operations.

(declaim (inline bnf-fp-add bnf-fp-sub bnf-fp-double bnf-fp-neg bnf-fp-copy
                 bnf-fp-set-zero bnf-fp-zero-p bnf-fp-equal-p))

(defun bnf-fp-add (r ro a ao b bo)
  (declare (type bnf-words r a b) (type bnf-index ro ao bo))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (multiple-value-bind (s0 c0) (%bnf-adc (aref a ao) (aref b bo) 0)
    (multiple-value-bind (s1 c1)
        (%bnf-adc (aref a (+ ao 1)) (aref b (+ bo 1)) c0)
      (multiple-value-bind (s2 c2)
          (%bnf-adc (aref a (+ ao 2)) (aref b (+ bo 2)) c1)
        ;; Both inputs are below p < 2^254, so the sum has no carry out.
        (%bnf-store-reduced r ro s0 s1 s2
                            (values (%bnf-adc (aref a (+ ao 3))
                                              (aref b (+ bo 3))
                                              c2)))))))

(defun bnf-fp-sub (r ro a ao b bo)
  (declare (type bnf-words r a b) (type bnf-index ro ao bo))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (multiple-value-bind (d0 b0) (%bnf-sbb (aref a ao) (aref b bo) 0)
    (multiple-value-bind (d1 b1)
        (%bnf-sbb (aref a (+ ao 1)) (aref b (+ bo 1)) b0)
      (multiple-value-bind (d2 b2)
          (%bnf-sbb (aref a (+ ao 2)) (aref b (+ bo 2)) b1)
        (multiple-value-bind (d3 b3)
            (%bnf-sbb (aref a (+ ao 3)) (aref b (+ bo 3)) b2)
          ;; A final borrow means A < B: the difference wrapped around
          ;; 2^256, so add p back (added as p AND the borrow mask).
          (let ((mask (ldb (byte 64 0) (- b3))))
            (multiple-value-bind (e0 c0) (%bnf-adc d0 (logand mask +bnf-p0+) 0)
              (multiple-value-bind (e1 c1) (%bnf-adc d1 (logand mask +bnf-p1+) c0)
                (multiple-value-bind (e2 c2)
                    (%bnf-adc d2 (logand mask +bnf-p2+) c1)
                  (%bnf-store4 r ro e0 e1 e2
                               (values (%bnf-adc d3 (logand mask +bnf-p3+)
                                                 c2))))))))))))

(defun bnf-fp-double (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (bnf-fp-add r ro a ao a ao))

(defun bnf-fp-zero-p (a ao)
  (declare (type bnf-words a) (type bnf-index ao))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (zerop (logior (aref a ao) (aref a (+ ao 1))
                 (aref a (+ ao 2)) (aref a (+ ao 3)))))

(defun bnf-fp-neg (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (if (bnf-fp-zero-p a ao)
      (%bnf-store4 r ro 0 0 0 0)
      (multiple-value-bind (d0 b0) (%bnf-sbb +bnf-p0+ (aref a ao) 0)
        (multiple-value-bind (d1 b1) (%bnf-sbb +bnf-p1+ (aref a (+ ao 1)) b0)
          (multiple-value-bind (d2 b2) (%bnf-sbb +bnf-p2+ (aref a (+ ao 2)) b1)
            (%bnf-store4 r ro d0 d1 d2
                         (values (%bnf-sbb +bnf-p3+ (aref a (+ ao 3)) b2))))))))

(defun bnf-fp-copy (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (%bnf-store4 r ro (aref a ao) (aref a (+ ao 1))
               (aref a (+ ao 2)) (aref a (+ ao 3))))

(defun bnf-fp-set-zero (r ro)
  (declare (type bnf-words r) (type bnf-index ro))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (%bnf-store4 r ro 0 0 0 0))

(defun bnf-fp-equal-p (a ao b bo)
  (declare (type bnf-words a b) (type bnf-index ao bo))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (and (= (aref a ao) (aref b bo))
       (= (aref a (+ ao 1)) (aref b (+ bo 1)))
       (= (aref a (+ ao 2)) (aref b (+ bo 2)))
       (= (aref a (+ ao 3)) (aref b (+ bo 3)))))

(defun bnf-fp-mul (r ro a ao b bo)
  "R := A*B*R^-1 mod p (Montgomery product), CIOS with the no-carry shortcut."
  (declare (type bnf-words r a b) (type bnf-index ro ao bo))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (let ((a0 (aref a ao)) (a1 (aref a (+ ao 1)))
        (a2 (aref a (+ ao 2))) (a3 (aref a (+ ao 3)))
        (t0 0) (t1 0) (t2 0) (t3 0))
    (declare (type (unsigned-byte 64) a0 a1 a2 a3 t0 t1 t2 t3))
    (macrolet ((cios-round (index)
                 `(let ((bi (aref b (+ bo ,index))))
                    (declare (type (unsigned-byte 64) bi))
                    ;; (C, t0) := t0 + a0*bi
                    (multiple-value-bind (c u0) (%bnf-mac a0 bi t0 0)
                      (let ((m (ldb (byte 64 0) (* u0 +bnf-inverse-word+))))
                        (declare (type (unsigned-byte 64) m))
                        ;; (C2, _) := t0 + m*p0; its low word is zero by
                        ;; the choice of m.
                        (let ((c2 (values (%bnf-mac m +bnf-p0+ u0 0))))
                          ;; j = 1..3: (C, tj) := tj + aj*bi + C;
                          ;;           (C2, t(j-1)) := tj + m*pj + C2
                          (multiple-value-bind (c u1) (%bnf-mac a1 bi t1 c)
                            (multiple-value-bind (c2 v0) (%bnf-mac m +bnf-p1+ u1 c2)
                              (multiple-value-bind (c u2) (%bnf-mac a2 bi t2 c)
                                (multiple-value-bind (c2 v1)
                                    (%bnf-mac m +bnf-p2+ u2 c2)
                                  (multiple-value-bind (c u3) (%bnf-mac a3 bi t3 c)
                                    (multiple-value-bind (c2 v2)
                                        (%bnf-mac m +bnf-p3+ u3 c2)
                                      (setf t0 v0
                                            t1 v1
                                            t2 v2
                                            t3 (ldb (byte 64 0)
                                                    (+ c c2)))))))))))))))
      (cios-round 0)
      (cios-round 1)
      (cios-round 2)
      (cios-round 3))
    (%bnf-store-reduced r ro t0 t1 t2 t3)))

(declaim (inline bnf-fp-square))
(defun bnf-fp-square (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (bnf-fp-mul r ro a ao a ao))

;;; Constants and conversions.

(defmacro bnf-constant-words (form)
  "A load-time four-limb vector holding the integer FORM evaluates to."
  `(load-time-value (the bnf-words (bnf-integer-words ,form)) t))

(defmacro bnf-montgomery-one ()
  `(bnf-constant-words (mod (expt 2 256) +bn254-field-prime+)))

(defmacro bnf-montgomery-r2 ()
  `(bnf-constant-words (mod (expt 2 512) +bn254-field-prime+)))

(defmacro bnf-montgomery-r3 ()
  `(bnf-constant-words (mod (expt 2 768) +bn254-field-prime+)))

(defmacro bnf-plain-one ()
  `(bnf-constant-words 1))

(defun bnf-fp-set-one (r ro)
  (declare (type bnf-words r) (type bnf-index ro))
  (bnf-fp-copy r ro (bnf-montgomery-one) 0))

(defun bnf-fp-one-p (a ao)
  (declare (type bnf-words a) (type bnf-index ao))
  (bnf-fp-equal-p a ao (bnf-montgomery-one) 0))

(defun bnf-fp-to-montgomery (r ro a ao)
  "R := A*R mod p for plain limbs A below p."
  (declare (type bnf-words r a) (type bnf-index ro ao))
  (bnf-fp-mul r ro a ao (bnf-montgomery-r2) 0))

(defun bnf-fp-from-montgomery (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao))
  (bnf-fp-mul r ro a ao (bnf-plain-one) 0))

(defun bnf-fp-set-integer (r ro value)
  "Store VALUE (reduced mod p) at R/RO in Montgomery form. Not for hot paths."
  (let ((plain (bnf-integer-words (mod value +bn254-field-prime+))))
    (bnf-fp-to-montgomery r ro plain 0)))

(defun bnf-fp-integer (a ao)
  "Return the field element at A/AO as an integer in [0, p)."
  (let ((plain (make-bnf-words 4)))
    (bnf-fp-from-montgomery plain 0 a ao)
    (bnf-words-integer plain 0)))

(defun bnf-read-canonical-fp (r ro bytes start)
  "Read 32 big-endian BYTES at START into R/RO in Montgomery form.

Return NIL, leaving R unspecified, when the integer is not below p, the
canonical-encoding rule go-ethereum's gnark SetBytesCanonical applies."
  (declare (type bnf-words r) (type bnf-index ro)
           (type (simple-array (unsigned-byte 8) (*)) bytes)
           (type fixnum start))
  (flet ((word (index)
           ;; Limb INDEX (little-endian) is bytes [24-8i, 32-8i) big-endian.
           (let ((base (+ start (- 24 (* 8 index))))
                 (value 0))
             (declare (type (unsigned-byte 64) value))
             (dotimes (i 8 value)
               (setf value (logior (ldb (byte 64 0) (ash value 8))
                                   (aref bytes (+ base i))))))))
    (let ((w0 (word 0)) (w1 (word 1)) (w2 (word 2)) (w3 (word 3)))
      (declare (type (unsigned-byte 64) w0 w1 w2 w3))
      (multiple-value-bind (d0 b0) (%bnf-sbb w0 +bnf-p0+ 0)
        (declare (ignore d0))
        (multiple-value-bind (d1 b1) (%bnf-sbb w1 +bnf-p1+ b0)
          (declare (ignore d1))
          (multiple-value-bind (d2 b2) (%bnf-sbb w2 +bnf-p2+ b1)
            (declare (ignore d2))
            (multiple-value-bind (d3 b3) (%bnf-sbb w3 +bnf-p3+ b2)
              (declare (ignore d3))
              ;; A final borrow means the value is below p.
              (when (= b3 1)
                (%bnf-store4 r ro w0 w1 w2 w3)
                (bnf-fp-to-montgomery r ro r ro)
                t))))))))

(defun bnf-write-fp (bytes start a ao)
  "Write the field element at A/AO as 32 big-endian bytes at START."
  (declare (type (simple-array (unsigned-byte 8) (*)) bytes)
           (type fixnum start) (type bnf-words a) (type bnf-index ao))
  (let ((plain (make-bnf-words 4)))
    (bnf-fp-from-montgomery plain 0 a ao)
    (dotimes (index 4 bytes)
      (let ((word (aref plain index))
            (base (+ start (- 24 (* 8 index)))))
        (dotimes (i 8)
          (setf (aref bytes (+ base i))
                (ldb (byte 8 (* 8 (- 7 i))) word)))))))

;;; Inversion: the binary extended Euclidean algorithm over plain limbs.

(declaim (inline %bnf-even-p %bnf-one-plain-p %bnf-shift-right
                 %bnf-greater-or-equal-p %bnf-subtract-in-place %bnf-halve-mod))

(defun %bnf-even-p (w o)
  (declare (type bnf-words w) (type bnf-index o))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (not (logbitp 0 (aref w o))))

(defun %bnf-one-plain-p (w o)
  (declare (type bnf-words w) (type bnf-index o))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (and (= 1 (aref w o))
       (zerop (logior (aref w (+ o 1)) (aref w (+ o 2)) (aref w (+ o 3))))))

(defun %bnf-shift-right (w o)
  (declare (type bnf-words w) (type bnf-index o))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (let ((w0 (aref w o)) (w1 (aref w (+ o 1)))
        (w2 (aref w (+ o 2))) (w3 (aref w (+ o 3))))
    (%bnf-store4 w o
                 (logior (ash w0 -1) (ash (logand w1 1) 63))
                 (logior (ash w1 -1) (ash (logand w2 1) 63))
                 (logior (ash w2 -1) (ash (logand w3 1) 63))
                 (ash w3 -1))))

(defun %bnf-greater-or-equal-p (w a b)
  (declare (type bnf-words w) (type bnf-index a b))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (let ((a3 (aref w (+ a 3))) (b3 (aref w (+ b 3))))
    (cond ((/= a3 b3) (> a3 b3))
          ((/= (aref w (+ a 2)) (aref w (+ b 2)))
           (> (aref w (+ a 2)) (aref w (+ b 2))))
          ((/= (aref w (+ a 1)) (aref w (+ b 1)))
           (> (aref w (+ a 1)) (aref w (+ b 1))))
          (t (>= (aref w a) (aref w b))))))

(defun %bnf-subtract-in-place (w a b)
  "W[A] := W[A] - W[B] for W[A] >= W[B] (plain limbs, no reduction)."
  (declare (type bnf-words w) (type bnf-index a b))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (multiple-value-bind (d0 b0) (%bnf-sbb (aref w a) (aref w b) 0)
    (multiple-value-bind (d1 b1) (%bnf-sbb (aref w (+ a 1)) (aref w (+ b 1)) b0)
      (multiple-value-bind (d2 b2)
          (%bnf-sbb (aref w (+ a 2)) (aref w (+ b 2)) b1)
        (%bnf-store4 w a d0 d1 d2
                     (values (%bnf-sbb (aref w (+ a 3)) (aref w (+ b 3)) b2)))))))

(defun %bnf-halve-mod (w o)
  "W[O] := W[O]/2 mod p for W[O] below p."
  (declare (type bnf-words w) (type bnf-index o))
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (if (%bnf-even-p w o)
      (%bnf-shift-right w o)
      ;; W + p < 2^255, so the sum fits the four limbs before the shift.
      (multiple-value-bind (s0 c0) (%bnf-adc (aref w o) +bnf-p0+ 0)
        (multiple-value-bind (s1 c1) (%bnf-adc (aref w (+ o 1)) +bnf-p1+ c0)
          (multiple-value-bind (s2 c2) (%bnf-adc (aref w (+ o 2)) +bnf-p2+ c1)
            (%bnf-store4 w o s0 s1 s2
                         (values (%bnf-adc (aref w (+ o 3)) +bnf-p3+ c2)))
            (%bnf-shift-right w o))))))

(defun bnf-fp-inverse (r ro a ao)
  "R := A^-1 in Montgomery form; signal when A is zero."
  (declare (type bnf-words r a) (type bnf-index ro ao))
  (when (bnf-fp-zero-p a ao)
    (fail "BN254 modular inverse does not exist"))
  ;; Scratch layout: u at 0, v at 4, x1 at 8, x2 at 12. With c the plain
  ;; integer the limbs of A hold (aR mod p), the loop keeps x1*c = u and
  ;; x2*c = v (mod p) from u = c, v = p, x1 = 1, x2 = 0; when u or v reaches
  ;; 1 its x is c^-1.
  (let ((w (make-bnf-words 16)))
    (declare (type bnf-words w) (optimize (speed 3) (safety 0) (debug 0)))
    (bnf-fp-copy w 0 a ao)
    (%bnf-store4 w 4 +bnf-p0+ +bnf-p1+ +bnf-p2+ +bnf-p3+)
    (%bnf-store4 w 8 1 0 0 0)
    (%bnf-store4 w 12 0 0 0 0)
    (loop until (or (%bnf-one-plain-p w 0) (%bnf-one-plain-p w 4))
          do (loop while (%bnf-even-p w 0)
                   do (%bnf-shift-right w 0)
                      (%bnf-halve-mod w 8))
             (loop while (%bnf-even-p w 4)
                   do (%bnf-shift-right w 4)
                      (%bnf-halve-mod w 12))
             (if (%bnf-greater-or-equal-p w 0 4)
                 (progn (%bnf-subtract-in-place w 0 4)
                        (bnf-fp-sub w 8 w 8 w 12))
                 (progn (%bnf-subtract-in-place w 4 0)
                        (bnf-fp-sub w 12 w 12 w 8))))
    ;; x = (aR)^-1; Montgomery-multiplying by R^3 gives a^-1 R.
    (bnf-fp-mul r ro w (if (%bnf-one-plain-p w 0) 8 12) (bnf-montgomery-r3) 0)))
