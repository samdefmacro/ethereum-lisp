(in-package #:ethereum-lisp.evm.internal)

;;;; The BN254 precompiles 0x06 (ECADD), 0x07 (ECMUL) and 0x08 (ECPAIRING)
;;;; (EIP-196, EIP-197; gas per EIP-1108 in bn254-base.lisp) over the
;;;; Montgomery-limb field and tower of bn254-montgomery.lisp and
;;;; bn254-tower.lisp.
;;;;
;;;; Input framing, validation order, failure messages, the dropping of pairs
;;;; with a point at infinity and the gas are those of the integer
;;;; implementation (RUN-BN254-*-PRECOMPILE-REFERENCE), which stays in the
;;;; tree as the differential oracle. The group arithmetic differs only in
;;;; coordinates: scalar multiplication and the G2 subgroup check run in
;;;; Jacobian coordinates, so they invert once or not at all, where the
;;;; oracle inverts once per affine addition. The Miller loop and the final
;;;; exponentiation are the oracle's schedules over the new field.
;;;;
;;;; Point layouts in word vectors (base field K = Fp or Fp2, K-size n words):
;;;;   affine    x at +0, y at +n
;;;;   Jacobian  X at +0, Y at +n, Z at +2n; (X/Z^2, Y/Z^3), Z = 0 is infinity
;;;;   twist     x, y, z, t at +0, +8, +16, +24 (the Miller loop's R)

;;; Jacobian doubling and mixed addition, generated for G1 (Fp) and the
;;; twist (Fp2). Doubling is dbl-2009-l (a = 0); the mixed addition is the
;;; textbook Jacobian sum with Z2 = 1 and handles R = infinity, R = P and
;;; R = -P explicitly.

(defmacro define-bnf-jacobian (double-name add-name size &key add sub mul square
                                                              double copy zero-p
                                                              set-one set-zero)
  (let ((y size) (z (* 2 size)))
    `(progn
       (defun ,double-name (r ro)
         "Double the Jacobian point at R/RO in place."
         (declare (type bnf-words r) (type bnf-index ro))
         (with-bnf-scratch (s (ca ,size) (cb ,size) (cc ,size) (cd ,size)
                              (ce ,size))
           (progn
             (,square s ca r ro)                    ; A = X^2
             (,square s cb r (+ ro ,y))             ; B = Y^2
             (,square s cc s cb)                    ; C = B^2
             (,add s cd r ro s cb)                  ; D = 2((X+B)^2 - A - C)
             (,square s cd s cd)
             (,sub s cd s cd s ca)
             (,sub s cd s cd s cc)
             (,double s cd s cd)
             (,double s ce s ca)                    ; E = 3A
             (,add s ce s ce s ca)
             (,mul r (+ ro ,z) r (+ ro ,y) r (+ ro ,z)) ; Z3 = 2 Y Z
             (,double r (+ ro ,z) r (+ ro ,z))
             (,square s ca s ce)                    ; F = E^2 (A is dead)
             (,sub r ro s ca s cd)                  ; X3 = F - 2D
             (,sub r ro r ro s cd)
             (,sub s cd s cd r ro)                  ; Y3 = E(D - X3) - 8C
             (,mul s cd s cd s ce)
             (,double s cc s cc)
             (,double s cc s cc)
             (,double s cc s cc)
             (,sub r (+ ro ,y) s cd s cc))))

       (defun ,add-name (r ro p po)
         "R := R + P for the Jacobian R at R/RO and the finite affine P."
         (declare (type bnf-words r p) (type bnf-index ro po))
         (when (,zero-p r (+ ro ,z))
           (,copy r ro p po)
           (,copy r (+ ro ,y) p (+ po ,y))
           (,set-one r (+ ro ,z))
           (return-from ,add-name nil))
         (with-bnf-scratch (s (z1z1 ,size) (u2 ,size) (s2 ,size) (h ,size)
                              (rr ,size) (hh ,size) (hhh ,size))
           (progn
             (,square s z1z1 r (+ ro ,z))
             (,mul s u2 p po s z1z1)                ; U2 = x2 Z1^2
             (,mul s s2 p (+ po ,y) r (+ ro ,z))    ; S2 = y2 Z1^3
             (,mul s s2 s s2 s z1z1)
             (,sub s h s u2 r ro)                   ; H = U2 - X1
             (,sub s rr s s2 r (+ ro ,y))           ; RR = S2 - Y1
             (when (,zero-p s h)
               (if (,zero-p s rr)
                   (,double-name r ro)
                   (,set-zero r (+ ro ,z)))
               (return-from ,add-name nil))
             (,square s hh s h)
             (,mul s hhh s h s hh)
             (,mul s u2 r ro s hh)                  ; V = X1 H^2 (U2 is dead)
             (,mul r (+ ro ,z) r (+ ro ,z) s h)     ; Z3 = Z1 H
             (,square s z1z1 s rr)                  ; X3 = RR^2 - H^3 - 2V
             (,sub s z1z1 s z1z1 s hhh)
             (,sub s z1z1 s z1z1 s u2)
             (,sub s z1z1 s z1z1 s u2)
             (,mul s hhh r (+ ro ,y) s hhh)         ; Y1 H^3
             (,sub s u2 s u2 s z1z1)                ; Y3 = RR(V - X3) - Y1 H^3
             (,mul s u2 s u2 s rr)
             (,sub r (+ ro ,y) s u2 s hhh)
             (,copy r ro s z1z1)))))))

(define-bnf-jacobian bnf-g1-double bnf-g1-add-affine 4
  :add bnf-fp-add :sub bnf-fp-sub :mul bnf-fp-mul :square bnf-fp-square
  :double bnf-fp-double :copy bnf-fp-copy :zero-p bnf-fp-zero-p
  :set-one bnf-fp-set-one :set-zero bnf-fp-set-zero)

(define-bnf-jacobian bnf-g2-double bnf-g2-add-affine 8
  :add bnf-fp2-add :sub bnf-fp2-sub :mul bnf-fp2-mul :square bnf-fp2-square
  :double bnf-fp2-double :copy bnf-fp2-copy :zero-p bnf-fp2-zero-p
  :set-one bnf-fp2-set-one :set-zero bnf-fp2-set-zero)

(defun bnf-g1-to-affine (jacobian)
  "Return a fresh affine G1 vector for JACOBIAN, or NIL for infinity."
  (declare (type bnf-words jacobian))
  (unless (bnf-fp-zero-p jacobian 8)
    (let ((affine (make-bnf-words 8)))
      (with-bnf-scratch (s (inverse 4) (power 4))
        (bnf-fp-inverse s inverse jacobian 8)
        (bnf-fp-square s power s inverse)
        (bnf-fp-mul affine 0 jacobian 0 s power)
        (bnf-fp-mul s power s power s inverse)
        (bnf-fp-mul affine 4 jacobian 4 s power))
      affine)))

(defun bnf-g1-jacobian (affine)
  (let ((jacobian (make-bnf-words 12)))
    (bnf-fp-copy jacobian 0 affine 0)
    (bnf-fp-copy jacobian 4 affine 4)
    (bnf-fp-set-one jacobian 8)
    jacobian))

(defun bnf-g1-add (left right)
  "Sum of two affine G1 points (NIL is infinity) as an affine point or NIL."
  (cond ((null left) right)
        ((null right) left)
        (t (let ((sum (bnf-g1-jacobian left)))
             (bnf-g1-add-affine sum 0 right 0)
             (bnf-g1-to-affine sum)))))

(defun bnf-g1-mul (point scalar-bytes)
  "SCALAR-BYTES (32, big-endian, not reduced) times the affine POINT."
  (declare (type (simple-array (unsigned-byte 8) (*)) scalar-bytes))
  (when point
    (let ((result (make-bnf-words 12)))
      ;; Z = 0: the accumulator starts at infinity.
      (dotimes (byte-index 32)
        (let ((byte (aref scalar-bytes byte-index)))
          (loop for bit from 7 downto 0
                do (bnf-g1-double result 0)
                   (when (logbitp bit byte)
                     (bnf-g1-add-affine result 0 point 0)))))
      (bnf-g1-to-affine result))))

(defun bnf-g2-subgroup-p (point)
  "Whether r times the affine twist POINT is infinity (the oracle's test)."
  (let ((result (make-bnf-words 24))
        (order +bn254-curve-order+))
    (loop for bit from (1- (integer-length order)) downto 0
          do (bnf-g2-double result 0)
             (when (logbitp bit order)
               (bnf-g2-add-affine result 0 point 0)))
    (bnf-fp2-zero-p result 16)))

(defun bnf-g1-on-curve-p (point)
  "y^2 = x^3 + 3."
  (with-bnf-scratch (s (left 4) (right 4))
    (bnf-fp-square s left point 4)
    (bnf-fp-square s right point 0)
    (bnf-fp-mul s right s right point 0)
    (bnf-fp-add s right s right (bnf-fp-constant 3) 0)
    (bnf-fp-equal-p s left s right)))

(defun bnf-g2-on-curve-p (point)
  "y^2 = x^3 + 3/(9+u) on the twist."
  (with-bnf-scratch (s (left 8) (right 8))
    (bnf-fp2-square s left point 8)
    (bnf-fp2-square s right point 0)
    (bnf-fp2-mul s right s right point 0)
    (bnf-fp2-add s right s right (bnf-fp2-constant (bn254-g2-curve-constant)) 0)
    (bnf-fp2-equal-p s left s right)))

;;; Decoding and encoding.

(defun bnf-all-zero-p (bytes start end)
  (loop for i from start below end
        always (zerop (aref bytes i))))

(defun parse-bnf-g1-point (bytes gas-used)
  "Decode the first 64 BYTES as an affine G1 point, NIL for infinity."
  (let ((bytes (padded-data-slice bytes 0 64)))
    (if (bnf-all-zero-p bytes 0 64)
        nil
        (let ((point (make-bnf-words 8)))
          (unless (and (bnf-read-canonical-fp point 0 bytes 0)
                       (bnf-read-canonical-fp point 4 bytes 32)
                       (bnf-g1-on-curve-p point))
            (fail-precompile gas-used "Invalid BN254 G1 point"))
          point))))

(defun parse-bnf-g2-point (bytes gas-used)
  "Decode the first 128 BYTES (x.imag x.real y.imag y.real) as a twist point."
  (let ((bytes (padded-data-slice bytes 0 128)))
    (if (bnf-all-zero-p bytes 0 128)
        nil
        (let ((point (make-bnf-words 16)))
          (unless (and (bnf-read-canonical-fp point 4 bytes 0)
                       (bnf-read-canonical-fp point 0 bytes 32)
                       (bnf-read-canonical-fp point 12 bytes 64)
                       (bnf-read-canonical-fp point 8 bytes 96))
            (fail-precompile gas-used "Invalid BN254 G2 coordinate"))
          (unless (bnf-g2-on-curve-p point)
            (fail-precompile gas-used "Invalid BN254 G2 point"))
          (unless (bnf-g2-subgroup-p point)
            (fail-precompile gas-used "Invalid BN254 G2 subgroup"))
          point))))

(defun serialize-bnf-g1-point (point)
  (let ((output (make-byte-vector 64)))
    (when point
      (bnf-write-fp output 0 point 0)
      (bnf-write-fp output 32 point 4))
    output))

;;; The optimal Ate pairing: BN254-MILLER and BN254-FINAL-EXPONENTIATION's
;;; schedules.

(defun bnf-line-function-add (r p q r2 line)
  "Add the twist point P (its x and y) to R in place; write the line.

Q is the affine G1 point, R2 the square of P's y. BN254-LINE-FUNCTION-ADD."
  (declare (type bnf-words r p q r2 line))
  (with-bnf-scratch (s (b 8) (d 8) (h 8) (i 8) (e 8) (j 8) (l1 8)
                       (v 8) (ox 8) (oy 8) (oz 8) (ot 8) (lt 8) (t2 8))
    (symbol-macrolet ((rx 0) (ry 8) (rz 16) (rt 24) (px 0) (py 8))
      (bnf-fp2-mul s b p px r rt)
      (bnf-fp2-add s d p py r rz)
      (bnf-fp2-square s d s d)
      (bnf-fp2-sub s d s d r2 0)
      (bnf-fp2-sub s d s d r rt)
      (bnf-fp2-mul s d s d r rt)
      (bnf-fp2-sub s h s b r rx)
      (bnf-fp2-square s i s h)
      (bnf-fp2-double s e s i)
      (bnf-fp2-double s e s e)
      (bnf-fp2-mul s j s h s e)
      (bnf-fp2-sub s l1 s d r ry)
      (bnf-fp2-sub s l1 s l1 r ry)
      (bnf-fp2-mul s v r rx s e)
      (bnf-fp2-square s ox s l1)
      (bnf-fp2-sub s ox s ox s j)
      (bnf-fp2-sub s ox s ox s v)
      (bnf-fp2-sub s ox s ox s v)
      (bnf-fp2-add s oz r rz s h)
      (bnf-fp2-square s oz s oz)
      (bnf-fp2-sub s oz s oz r rt)
      (bnf-fp2-sub s oz s oz s i)
      (bnf-fp2-sub s oy s v s ox)
      (bnf-fp2-mul s oy s l1 s oy)
      (bnf-fp2-mul s lt r ry s j)
      (bnf-fp2-double s lt s lt)
      (bnf-fp2-sub s oy s oy s lt)
      (bnf-fp2-square s ot s oz)
      (bnf-fp2-add s lt p py s oz)
      (bnf-fp2-square s lt s lt)
      (bnf-fp2-sub s lt s lt r2 0)
      (bnf-fp2-sub s lt s lt s ot)
      (bnf-fp2-mul s t2 s l1 p px)
      (bnf-fp2-double s t2 s t2)
      (bnf-fp2-sub line 0 s t2 s lt)             ; a
      (bnf-fp2-mul-fp line 16 s oz q 4)          ; c = 2 oz q.y
      (bnf-fp2-double line 16 line 16)
      (bnf-fp2-neg line 8 s l1)                  ; b = 2 (-l1) q.x
      (bnf-fp2-mul-fp line 8 line 8 q 0)
      (bnf-fp2-double line 8 line 8)
      (bnf-fp2-copy r rx s ox)
      (bnf-fp2-copy r ry s oy)
      (bnf-fp2-copy r rz s oz)
      (bnf-fp2-copy r rt s ot))))

(defun bnf-line-function-double (r q line)
  "Double the twist point R in place and write the tangent line.
BN254-LINE-FUNCTION-DOUBLE."
  (declare (type bnf-words r q line))
  (with-bnf-scratch (s (a0 8) (b0 8) (c0 8) (d 8) (e 8) (g 8)
                       (ox 8) (oy 8) (oz 8) (ot 8) (lt 8))
    (symbol-macrolet ((rx 0) (ry 8) (rz 16) (rt 24))
      (bnf-fp2-square s a0 r rx)
      (bnf-fp2-square s b0 r ry)
      (bnf-fp2-square s c0 s b0)
      (bnf-fp2-add s d r rx s b0)
      (bnf-fp2-square s d s d)
      (bnf-fp2-sub s d s d s a0)
      (bnf-fp2-sub s d s d s c0)
      (bnf-fp2-double s d s d)
      (bnf-fp2-double s e s a0)
      (bnf-fp2-add s e s e s a0)
      (bnf-fp2-square s g s e)
      (bnf-fp2-sub s ox s g s d)
      (bnf-fp2-sub s ox s ox s d)
      (bnf-fp2-add s oz r ry r rz)
      (bnf-fp2-square s oz s oz)
      (bnf-fp2-sub s oz s oz s b0)
      (bnf-fp2-sub s oz s oz r rt)
      (bnf-fp2-sub s oy s d s ox)
      (bnf-fp2-mul s oy s oy s e)
      (bnf-fp2-double s lt s c0)
      (bnf-fp2-double s lt s lt)
      (bnf-fp2-double s lt s lt)
      (bnf-fp2-sub s oy s oy s lt)
      (bnf-fp2-square s ot s oz)
      ;; b = -(2 e r.t) q.x
      (bnf-fp2-mul s lt s e r rt)
      (bnf-fp2-double s lt s lt)
      (bnf-fp2-neg line 8 s lt)
      (bnf-fp2-mul-fp line 8 line 8 q 0)
      ;; a = (r.x + e)^2 - a0 - g - 4 b0
      (bnf-fp2-add line 0 r rx s e)
      (bnf-fp2-square line 0 line 0)
      (bnf-fp2-sub line 0 line 0 s a0)
      (bnf-fp2-sub line 0 line 0 s g)
      (bnf-fp2-double s lt s b0)
      (bnf-fp2-double s lt s lt)
      (bnf-fp2-sub line 0 line 0 s lt)
      ;; c = 2 oz r.t q.y
      (bnf-fp2-mul line 16 s oz r rt)
      (bnf-fp2-double line 16 line 16)
      (bnf-fp2-mul-fp line 16 line 16 q 4)
      (bnf-fp2-copy r rx s ox)
      (bnf-fp2-copy r ry s oy)
      (bnf-fp2-copy r rz s oz)
      (bnf-fp2-copy r rt s ot))))

(defun bnf-twist-point (x xo y yo)
  "A fresh twist point (x, y, 1, 1)."
  (let ((point (make-bnf-words 32)))
    (bnf-fp2-copy point 0 x xo)
    (bnf-fp2-copy point 8 y yo)
    (bnf-fp2-set-one point 16)
    (bnf-fp2-set-one point 24)
    point))

(defun bnf-miller (g2 g1 accumulator)
  "Multiply ACCUMULATOR (Fp12) in place by the Miller loop of (G2, G1)."
  (let* ((a (bnf-twist-point g2 0 g2 8))
         (minus-a (bnf-twist-point g2 0 g2 8))
         (r (bnf-twist-point g2 0 g2 8))
         (r2 (make-bnf-words 8))
         (line (make-bnf-words 24))
         (ret (make-bnf-fp12))
         (naf +bn254-six-u-plus-2-naf+)
         (last-index (1- (length naf))))
    (bnf-fp2-neg minus-a 8 minus-a 8)
    (bnf-fp2-square r2 0 a 8)
    (bnf-fp12-set-one ret 0)
    (loop for i from last-index downto 1
          do (bnf-line-function-double r g1 line)
             (unless (= i last-index)
               (bnf-fp12-square ret 0 ret 0))
             (bnf-fp12-mul-line ret 0 line 0)
             (case (aref naf (1- i))
               (1 (bnf-line-function-add r a g1 r2 line)
                (bnf-fp12-mul-line ret 0 line 0))
               (-1 (bnf-line-function-add r minus-a g1 r2 line)
                (bnf-fp12-mul-line ret 0 line 0))))
    (let ((q1 (make-bnf-words 32))
          (minus-q2 (make-bnf-words 32)))
      (bnf-fp2-conjugate q1 0 a 0)
      (bnf-fp2-mul q1 0 q1 0 (bnf-fp2-constant +bn254-xi-to-p-minus-1-over-3+) 0)
      (bnf-fp2-conjugate q1 8 a 8)
      (bnf-fp2-mul q1 8 q1 8 (bnf-fp2-constant +bn254-xi-to-p-minus-1-over-2+) 0)
      (bnf-fp2-set-one q1 16)
      (bnf-fp2-set-one q1 24)
      (bnf-fp2-mul-fp minus-q2 0 a 0
                      (bnf-fp-constant +bn254-xi-to-p-squared-minus-1-over-3+) 0)
      (bnf-fp2-copy minus-q2 8 a 8)
      (bnf-fp2-set-one minus-q2 16)
      (bnf-fp2-set-one minus-q2 24)
      (bnf-fp2-square r2 0 q1 8)
      (bnf-line-function-add r q1 g1 r2 line)
      (bnf-fp12-mul-line ret 0 line 0)
      (bnf-fp2-square r2 0 minus-q2 8)
      (bnf-line-function-add r minus-q2 g1 r2 line)
      (bnf-fp12-mul-line ret 0 line 0))
    (bnf-fp12-mul accumulator 0 accumulator 0 ret 0)
    accumulator))

(defun bnf-final-exponentiation (value)
  "BN254-FINAL-EXPONENTIATION's schedule; returns a fresh Fp12 vector."
  (flet ((fresh () (make-bnf-fp12)))
    (let ((u 4965661367192848881)
          (t0 (fresh)) (t1 (fresh)) (t2 (fresh)) (inv (fresh))
          (fp (fresh)) (fp2 (fresh)) (fp3 (fresh))
          (fu (fresh)) (fu2 (fresh)) (fu3 (fresh))
          (y0 (fresh)) (y1 (fresh)) (y2 (fresh)) (y3 (fresh))
          (y4 (fresh)) (y5 (fresh)) (y6 (fresh))
          (fu2p (fresh)) (fu3p (fresh)))
      (bnf-fp12-conjugate t1 0 value 0)
      (bnf-fp12-inverse inv 0 value 0)
      (bnf-fp12-mul t1 0 t1 0 inv 0)
      (bnf-fp12-frobenius-p2 t2 0 t1 0)
      (bnf-fp12-mul t1 0 t1 0 t2 0)
      (bnf-fp12-frobenius fp 0 t1 0)
      (bnf-fp12-frobenius-p2 fp2 0 t1 0)
      (bnf-fp12-frobenius fp3 0 fp2 0)
      (bnf-fp12-exp fu 0 t1 0 u)
      (bnf-fp12-exp fu2 0 fu 0 u)
      (bnf-fp12-exp fu3 0 fu2 0 u)
      (bnf-fp12-frobenius y3 0 fu 0)
      (bnf-fp12-frobenius fu2p 0 fu2 0)
      (bnf-fp12-frobenius fu3p 0 fu3 0)
      (bnf-fp12-frobenius-p2 y2 0 fu2 0)
      (bnf-fp12-mul y0 0 fp 0 fp2 0)
      (bnf-fp12-mul y0 0 y0 0 fp3 0)
      (bnf-fp12-conjugate y1 0 t1 0)
      (bnf-fp12-conjugate y5 0 fu2 0)
      (bnf-fp12-conjugate y3 0 y3 0)
      (bnf-fp12-mul y4 0 fu 0 fu2p 0)
      (bnf-fp12-conjugate y4 0 y4 0)
      (bnf-fp12-mul y6 0 fu3 0 fu3p 0)
      (bnf-fp12-conjugate y6 0 y6 0)
      (bnf-fp12-square t0 0 y6 0)
      (bnf-fp12-mul t0 0 t0 0 y4 0)
      (bnf-fp12-mul t0 0 t0 0 y5 0)
      (bnf-fp12-mul t1 0 y3 0 y5 0)
      (bnf-fp12-mul t1 0 t1 0 t0 0)
      (bnf-fp12-mul t0 0 t0 0 y2 0)
      (bnf-fp12-square t1 0 t1 0)
      (bnf-fp12-mul t1 0 t1 0 t0 0)
      (bnf-fp12-square t1 0 t1 0)
      (bnf-fp12-mul t0 0 t1 0 y1 0)
      (bnf-fp12-mul t1 0 t1 0 y0 0)
      (bnf-fp12-square t0 0 t0 0)
      (bnf-fp12-mul t0 0 t0 0 t1 0)
      t0)))

(defun bnf-pairing-check (pairs)
  "Whether the product of the pairings of PAIRS, each (G1 G2) as decoded by
PARSE-BNF-G1-POINT and PARSE-BNF-G2-POINT, is one."
  (let ((accumulator (make-bnf-fp12)))
    (bnf-fp12-set-one accumulator 0)
    (dolist (pair pairs)
      (destructuring-bind (g1 g2) pair
        (bnf-miller g2 g1 accumulator)))
    (bnf-fp12-one-p (bnf-final-exponentiation accumulator) 0)))

(defvar *bn254-pairing-checker* #'bnf-pairing-check
  "Callable used for non-zero BN254 pairing products after point validation.
It receives the pairs PARSE-BNF-G1-POINT and PARSE-BNF-G2-POINT decoded.")

(defun bn254-pairing-check (pairs)
  (funcall *bn254-pairing-checker* pairs))

;;; The precompiles. Each binds its own workspace, so concurrent callers
;;; (block execution, eth_call) never share temporaries.

(defun run-bn254-add-precompile (input &optional rules)
  (with-bnf-workspace (+bnf-g1-workspace-words+)
    (let* ((gas (bn254-add-gas rules))
           (left (parse-bnf-g1-point (padded-data-slice input 0 64) gas))
           (right (parse-bnf-g1-point (padded-data-slice input 64 64) gas)))
      (values (serialize-bnf-g1-point (bnf-g1-add left right))
              gas))))

(defun run-bn254-mul-precompile (input &optional rules)
  (with-bnf-workspace (+bnf-g1-workspace-words+)
    (let* ((gas (bn254-mul-gas rules))
           (point (parse-bnf-g1-point (padded-data-slice input 0 64) gas))
           (scalar (padded-data-slice input 64 32)))
      (values (serialize-bnf-g1-point (bnf-g1-mul point scalar))
              gas))))

(defun run-bn254-pairing-precompile (input &optional rules)
  (let ((gas (bn254-pairing-gas input rules)))
    (cond
      ((not (zerop (mod (length input) 192)))
       (fail-precompile gas "Invalid BN254 pairing input size"))
      ((zerop (length input))
       (values (true32-byte-vector) gas))
      (t
       (with-bnf-workspace ()
         (let ((pairs
                 (loop for offset from 0 below (length input) by 192
                       for g1 = (parse-bnf-g1-point
                                 (subseq input offset (+ offset 64))
                                 gas)
                       for g2 = (parse-bnf-g2-point
                                 (subseq input (+ offset 64) (+ offset 192))
                                 gas)
                       when (and g1 g2)
                         collect (list g1 g2))))
           (values (if (bn254-pairing-check pairs)
                       (true32-byte-vector)
                       (false32-byte-vector))
                   gas)))))))
