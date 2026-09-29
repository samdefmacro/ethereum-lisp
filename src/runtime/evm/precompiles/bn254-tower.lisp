(in-package #:ethereum-lisp.evm.internal)

;;;; The BN254 extension tower over the Montgomery limbs of
;;;; bn254-montgomery.lisp: Fp2 = Fp[u]/(u^2+1), Fp6 = Fp2[tau]/(tau^3-xi)
;;;; with xi = 9+u, Fp12 = Fp6[w]/(w^2-tau).
;;;;
;;;; Layouts inside a word vector, every element at a caller-chosen offset:
;;;;   Fp2   8 words  real part at +0, imaginary part at +4
;;;;   Fp6  24 words  x at +0, y at +8, z at +16   (x*tau^2 + y*tau + z)
;;;;   Fp12 48 words  x at +0, y at +24            (x*w + y)
;;;; These are the representations of the integer implementation in
;;;; bn254-base.lisp and bn254-fields.lisp, and every routine here computes
;;;; the same element that routine computes (Fp12 multiplication uses
;;;; Karatsuba, an identity). A destination may equal an input exactly;
;;;; partial overlaps are not supported. Temporaries come from the
;;;; workspace (WITH-BNF-SCRATCH, bn254-montgomery.lisp).

(defmacro with-bnf-leaf-scratch ((vector &rest slots) &body body)
  "WITH-BNF-SCRATCH for a BODY that calls no routine taking scratch itself:
the slots lie above the current top, which is left where it is."
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
                     do (incf offset words)))
         (declare (type bnf-words ,vector)
                  (type bnf-index ,@(mapcar #'first slots))
                  (ignorable ,@(mapcar #'first slots)))
         ,@body))))

;;; Fp2

(defun bnf-fp2-add (r ro a ao b bo)
  (declare (type bnf-words r a b) (type bnf-index ro ao bo)
           (optimize (speed 3) (safety 0) (debug 0)))
  (bnf-fp-add r ro a ao b bo)
  (bnf-fp-add r (+ ro 4) a (+ ao 4) b (+ bo 4)))

(defun bnf-fp2-sub (r ro a ao b bo)
  (declare (type bnf-words r a b) (type bnf-index ro ao bo)
           (optimize (speed 3) (safety 0) (debug 0)))
  (bnf-fp-sub r ro a ao b bo)
  (bnf-fp-sub r (+ ro 4) a (+ ao 4) b (+ bo 4)))

(defun bnf-fp2-double (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao)
           (optimize (speed 3) (safety 0) (debug 0)))
  (bnf-fp-double r ro a ao)
  (bnf-fp-double r (+ ro 4) a (+ ao 4)))

(defun bnf-fp2-neg (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao)
           (optimize (speed 3) (safety 0) (debug 0)))
  (bnf-fp-neg r ro a ao)
  (bnf-fp-neg r (+ ro 4) a (+ ao 4)))

(defun bnf-fp2-conjugate (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao)
           (optimize (speed 3) (safety 0) (debug 0)))
  (bnf-fp-copy r ro a ao)
  (bnf-fp-neg r (+ ro 4) a (+ ao 4)))

(defun bnf-fp2-copy (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao)
           (optimize (speed 3) (safety 0) (debug 0)))
  (bnf-fp-copy r ro a ao)
  (bnf-fp-copy r (+ ro 4) a (+ ao 4)))

(defun bnf-fp2-set-zero (r ro)
  (declare (type bnf-words r) (type bnf-index ro))
  (bnf-fp-set-zero r ro)
  (bnf-fp-set-zero r (+ ro 4)))

(defun bnf-fp2-set-one (r ro)
  (declare (type bnf-words r) (type bnf-index ro))
  (bnf-fp-set-one r ro)
  (bnf-fp-set-zero r (+ ro 4)))

(defun bnf-fp2-zero-p (a ao)
  (declare (type bnf-words a) (type bnf-index ao))
  (and (bnf-fp-zero-p a ao) (bnf-fp-zero-p a (+ ao 4))))

(defun bnf-fp2-one-p (a ao)
  (declare (type bnf-words a) (type bnf-index ao))
  (and (bnf-fp-one-p a ao) (bnf-fp-zero-p a (+ ao 4))))

(defun bnf-fp2-equal-p (a ao b bo)
  (declare (type bnf-words a b) (type bnf-index ao bo))
  (and (bnf-fp-equal-p a ao b bo)
       (bnf-fp-equal-p a (+ ao 4) b (+ bo 4))))

(defun bnf-fp2-mul (r ro a ao b bo)
  "(a0 + a1 u)(b0 + b1 u) with three base multiplications (Karatsuba)."
  (declare (type bnf-words r a b) (type bnf-index ro ao bo)
           (optimize (speed 3) (safety 0) (debug 0)))
  (with-bnf-leaf-scratch (s (m0 4) (m1 4) (sa 4) (sb 4))
    (bnf-fp-mul s m0 a ao b bo)                      ; a0 b0
    (bnf-fp-mul s m1 a (+ ao 4) b (+ bo 4))          ; a1 b1
    (bnf-fp-add s sa a ao a (+ ao 4))                ; a0 + a1
    (bnf-fp-add s sb b bo b (+ bo 4))                ; b0 + b1
    (bnf-fp-mul s sa s sa s sb)                      ; (a0+a1)(b0+b1)
    (bnf-fp-sub r ro s m0 s m1)
    (bnf-fp-sub s sa s sa s m0)
    (bnf-fp-sub r (+ ro 4) s sa s m1)))

(defun bnf-fp2-square (r ro a ao)
  "(a0 + a1 u)^2 = (a0+a1)(a0-a1) + 2 a0 a1 u."
  (declare (type bnf-words r a) (type bnf-index ro ao)
           (optimize (speed 3) (safety 0) (debug 0)))
  (with-bnf-leaf-scratch (s (sum 4) (difference 4) (product 4))
    (bnf-fp-add s sum a ao a (+ ao 4))
    (bnf-fp-sub s difference a ao a (+ ao 4))
    (bnf-fp-mul s product a ao a (+ ao 4))
    (bnf-fp-mul r ro s sum s difference)
    (bnf-fp-double r (+ ro 4) s product)))

(defun bnf-fp2-mul-fp (r ro a ao s so)
  "Multiply the Fp2 element A by the base-field element S."
  (declare (type bnf-words r a s) (type bnf-index ro ao so)
           (optimize (speed 3) (safety 0) (debug 0)))
  (bnf-fp-mul r ro a ao s so)
  (bnf-fp-mul r (+ ro 4) a (+ ao 4) s so))

(defun bnf-fp2-mul-xi (r ro a ao)
  "(a0 + a1 u)(9 + u) = (9 a0 - a1) + (a0 + 9 a1) u."
  (declare (type bnf-words r a) (type bnf-index ro ao)
           (optimize (speed 3) (safety 0) (debug 0)))
  (with-bnf-leaf-scratch (s (v 8))
    (bnf-fp-double s v a ao)
    (bnf-fp-double s v s v)
    (bnf-fp-double s v s v)
    (bnf-fp-add s v s v a ao)                        ; 9 a0
    (bnf-fp-sub s v s v a (+ ao 4))                  ; 9 a0 - a1
    (bnf-fp-double s (+ v 4) a (+ ao 4))
    (bnf-fp-double s (+ v 4) s (+ v 4))
    (bnf-fp-double s (+ v 4) s (+ v 4))
    (bnf-fp-add s (+ v 4) s (+ v 4) a (+ ao 4))      ; 9 a1
    (bnf-fp-add s (+ v 4) s (+ v 4) a ao)            ; a0 + 9 a1
    (bnf-fp2-copy r ro s v)))

(defun bnf-fp2-inverse (r ro a ao)
  "(a0 - a1 u) / (a0^2 + a1^2); signal on zero."
  (declare (type bnf-words r a) (type bnf-index ro ao))
  ;; A leaf: BNF-FP-INVERSE takes no workspace scratch.
  (with-bnf-leaf-scratch (s (norm 4) (square 4) (imaginary 4))
    (bnf-fp-square s norm a ao)
    (bnf-fp-square s square a (+ ao 4))
    (bnf-fp-add s norm s norm s square)
    (when (bnf-fp-zero-p s norm)
      (fail "BN254 Fp2 inverse does not exist"))
    (bnf-fp-inverse s norm s norm)
    (bnf-fp-mul s imaginary a (+ ao 4) s norm)
    (bnf-fp-mul r ro a ao s norm)
    (bnf-fp-neg r (+ ro 4) s imaginary)))

;;; Fp6

(defmacro bnf-do-fp6-components ((offset) &body body)
  "Run BODY with OFFSET bound to each of the six base-field positions."
  `(loop for ,offset of-type (integer 0 24) from 0 below 24 by 4
         do (progn ,@body)))

(defun bnf-fp6-add (r ro a ao b bo)
  (declare (type bnf-words r a b) (type bnf-index ro ao bo)
           (optimize (speed 3) (safety 0) (debug 0)))
  (bnf-do-fp6-components (i)
    (bnf-fp-add r (+ ro i) a (+ ao i) b (+ bo i))))

(defun bnf-fp6-sub (r ro a ao b bo)
  (declare (type bnf-words r a b) (type bnf-index ro ao bo)
           (optimize (speed 3) (safety 0) (debug 0)))
  (bnf-do-fp6-components (i)
    (bnf-fp-sub r (+ ro i) a (+ ao i) b (+ bo i))))

(defun bnf-fp6-double (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao)
           (optimize (speed 3) (safety 0) (debug 0)))
  (bnf-do-fp6-components (i)
    (bnf-fp-double r (+ ro i) a (+ ao i))))

(defun bnf-fp6-neg (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao)
           (optimize (speed 3) (safety 0) (debug 0)))
  (bnf-do-fp6-components (i)
    (bnf-fp-neg r (+ ro i) a (+ ao i))))

(defun bnf-fp6-copy (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao)
           (optimize (speed 3) (safety 0) (debug 0)))
  (bnf-do-fp6-components (i)
    (bnf-fp-copy r (+ ro i) a (+ ao i))))

(defun bnf-fp6-set-zero (r ro)
  (declare (type bnf-words r) (type bnf-index ro))
  (bnf-do-fp6-components (i)
    (bnf-fp-set-zero r (+ ro i))))

(defun bnf-fp6-set-one (r ro)
  (declare (type bnf-words r) (type bnf-index ro))
  (bnf-fp6-set-zero r ro)
  (bnf-fp-set-one r (+ ro 16)))

(defun bnf-fp6-zero-p (a ao)
  (declare (type bnf-words a) (type bnf-index ao))
  (bnf-do-fp6-components (i)
    (unless (bnf-fp-zero-p a (+ ao i))
      (return-from bnf-fp6-zero-p nil)))
  t)

(defun bnf-fp6-one-p (a ao)
  (declare (type bnf-words a) (type bnf-index ao))
  (and (bnf-fp2-zero-p a ao)
       (bnf-fp2-zero-p a (+ ao 8))
       (bnf-fp2-one-p a (+ ao 16))))

(defun bnf-fp6-mul (r ro a ao b bo)
  (declare (type bnf-words r a b) (type bnf-index ro ao bo)
           (optimize (speed 3) (safety 0) (debug 0)))
  (with-bnf-scratch (s (v0 8) (v1 8) (v2 8) (tl 8) (tr 8) (tz 8) (ty 8) (tx 8))
    (progn
      (bnf-fp2-mul s v0 a (+ ao 16) b (+ bo 16))
      (bnf-fp2-mul s v1 a (+ ao 8) b (+ bo 8))
      (bnf-fp2-mul s v2 a ao b bo)
      ;; tz = xi((ax+ay)(bx+by) - v1 - v2) + v0
      (bnf-fp2-add s tl a ao a (+ ao 8))
      (bnf-fp2-add s tr b bo b (+ bo 8))
      (bnf-fp2-mul s tz s tl s tr)
      (bnf-fp2-sub s tz s tz s v1)
      (bnf-fp2-sub s tz s tz s v2)
      (bnf-fp2-mul-xi s tz s tz)
      (bnf-fp2-add s tz s tz s v0)
      ;; ty = (ay+az)(by+bz) - v0 - v1 + xi(v2)
      (bnf-fp2-add s tl a (+ ao 8) a (+ ao 16))
      (bnf-fp2-add s tr b (+ bo 8) b (+ bo 16))
      (bnf-fp2-mul s ty s tl s tr)
      (bnf-fp2-sub s ty s ty s v0)
      (bnf-fp2-sub s ty s ty s v1)
      (bnf-fp2-mul-xi s tl s v2)
      (bnf-fp2-add s ty s ty s tl)
      ;; tx = (ax+az)(bx+bz) - v0 + v1 - v2
      (bnf-fp2-add s tl a ao a (+ ao 16))
      (bnf-fp2-add s tr b bo b (+ bo 16))
      (bnf-fp2-mul s tx s tl s tr)
      (bnf-fp2-sub s tx s tx s v0)
      (bnf-fp2-add s tx s tx s v1)
      (bnf-fp2-sub s tx s tx s v2)
      (bnf-fp2-copy r ro s tx)
      (bnf-fp2-copy r (+ ro 8) s ty)
      (bnf-fp2-copy r (+ ro 16) s tz))))

(defun bnf-fp6-square (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao)
           (optimize (speed 3) (safety 0) (debug 0)))
  (with-bnf-scratch (s (v0 8) (v1 8) (v2 8) (tl 8) (c0 8) (c1 8) (c2 8))
    (progn
      (bnf-fp2-square s v0 a (+ ao 16))
      (bnf-fp2-square s v1 a (+ ao 8))
      (bnf-fp2-square s v2 a ao)
      (bnf-fp2-add s tl a ao a (+ ao 8))
      (bnf-fp2-square s c0 s tl)
      (bnf-fp2-sub s c0 s c0 s v1)
      (bnf-fp2-sub s c0 s c0 s v2)
      (bnf-fp2-mul-xi s c0 s c0)
      (bnf-fp2-add s c0 s c0 s v0)
      (bnf-fp2-add s tl a (+ ao 8) a (+ ao 16))
      (bnf-fp2-square s c1 s tl)
      (bnf-fp2-sub s c1 s c1 s v0)
      (bnf-fp2-sub s c1 s c1 s v1)
      (bnf-fp2-mul-xi s tl s v2)
      (bnf-fp2-add s c1 s c1 s tl)
      (bnf-fp2-add s tl a ao a (+ ao 16))
      (bnf-fp2-square s c2 s tl)
      (bnf-fp2-sub s c2 s c2 s v0)
      (bnf-fp2-add s c2 s c2 s v1)
      (bnf-fp2-sub s c2 s c2 s v2)
      (bnf-fp2-copy r ro s c2)
      (bnf-fp2-copy r (+ ro 8) s c1)
      (bnf-fp2-copy r (+ ro 16) s c0))))

(defun bnf-fp6-mul-fp2 (r ro a ao s so)
  "Multiply each Fp2 component of A by the Fp2 element S (not inside R)."
  (declare (type bnf-words r a s) (type bnf-index ro ao so))
  (bnf-fp2-mul r ro a ao s so)
  (bnf-fp2-mul r (+ ro 8) a (+ ao 8) s so)
  (bnf-fp2-mul r (+ ro 16) a (+ ao 16) s so))

(defun bnf-fp6-mul-fp (r ro a ao s so)
  "Multiply each component of A by the base-field element S (not inside R)."
  (declare (type bnf-words r a s) (type bnf-index ro ao so))
  (bnf-fp2-mul-fp r ro a ao s so)
  (bnf-fp2-mul-fp r (+ ro 8) a (+ ao 8) s so)
  (bnf-fp2-mul-fp r (+ ro 16) a (+ ao 16) s so))

(defun bnf-fp6-mul-tau (r ro a ao)
  "(x, y, z) * tau = (y, z, xi x)."
  (declare (type bnf-words r a) (type bnf-index ro ao))
  (with-bnf-scratch (s (v 8))
    (bnf-fp2-mul-xi s v a ao)
    (bnf-fp2-copy r ro a (+ ao 8))
    (bnf-fp2-copy r (+ ro 8) a (+ ao 16))
    (bnf-fp2-copy r (+ ro 16) s v)))

(defun bnf-fp6-inverse (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao))
  (with-bnf-scratch (s (ca 8) (cb 8) (cc 8) (f 8) (tmp 8))
    (symbol-macrolet ((x ao) (y (+ ao 8)) (z (+ ao 16)))
      ;; A = z^2 - xi(x y)
      (bnf-fp2-square s ca a z)
      (bnf-fp2-mul s tmp a x a y)
      (bnf-fp2-mul-xi s tmp s tmp)
      (bnf-fp2-sub s ca s ca s tmp)
      ;; B = xi(x^2) - y z
      (bnf-fp2-square s cb a x)
      (bnf-fp2-mul-xi s cb s cb)
      (bnf-fp2-mul s tmp a y a z)
      (bnf-fp2-sub s cb s cb s tmp)
      ;; C = y^2 - x z
      (bnf-fp2-square s cc a y)
      (bnf-fp2-mul s tmp a x a z)
      (bnf-fp2-sub s cc s cc s tmp)
      ;; F = xi(C y) + A z + xi(B x)
      (bnf-fp2-mul s f s cc a y)
      (bnf-fp2-mul-xi s f s f)
      (bnf-fp2-mul s tmp s ca a z)
      (bnf-fp2-add s f s f s tmp)
      (bnf-fp2-mul s tmp s cb a x)
      (bnf-fp2-mul-xi s tmp s tmp)
      (bnf-fp2-add s f s f s tmp)
      (bnf-fp2-inverse s f s f)
      (bnf-fp2-mul r ro s cc s f)
      (bnf-fp2-mul r (+ ro 8) s cb s f)
      (bnf-fp2-mul r (+ ro 16) s ca s f))))

;;; Frobenius constants, converted once from the integer implementation's.

(defun bnf-fp2-constant-words (pair)
  "A fresh Montgomery Fp2 vector for the integer (REAL . IMAGINARY) PAIR."
  (let ((words (make-bnf-words 8)))
    (bnf-fp-set-integer words 0 (car pair))
    (bnf-fp-set-integer words 4 (cdr pair))
    words))

(defun bnf-fp-constant-words (value)
  (let ((words (make-bnf-words 4)))
    (bnf-fp-set-integer words 0 value)
    words))

(defmacro bnf-fp2-constant (form)
  `(load-time-value (the bnf-words (bnf-fp2-constant-words ,form)) t))

(defmacro bnf-fp-constant (form)
  `(load-time-value (the bnf-words (bnf-fp-constant-words ,form)) t))

(defun bnf-fp6-frobenius (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao))
  (bnf-fp2-conjugate r ro a ao)
  (bnf-fp2-mul r ro r ro (bnf-fp2-constant +bn254-xi-to-2p-minus-2-over-3+) 0)
  (bnf-fp2-conjugate r (+ ro 8) a (+ ao 8))
  (bnf-fp2-mul r (+ ro 8) r (+ ro 8)
               (bnf-fp2-constant +bn254-xi-to-p-minus-1-over-3+) 0)
  (bnf-fp2-conjugate r (+ ro 16) a (+ ao 16)))

(defun bnf-fp6-frobenius-p2 (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao))
  (bnf-fp2-mul-fp r ro a ao
                  (bnf-fp-constant +bn254-xi-to-2p-squared-minus-2-over-3+) 0)
  (bnf-fp2-mul-fp r (+ ro 8) a (+ ao 8)
                  (bnf-fp-constant +bn254-xi-to-p-squared-minus-1-over-3+) 0)
  (bnf-fp2-copy r (+ ro 16) a (+ ao 16)))

;;; Fp12

(defun make-bnf-fp12 ()
  (make-bnf-words 48))

(defun bnf-fp12-copy (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao))
  (bnf-fp6-copy r ro a ao)
  (bnf-fp6-copy r (+ ro 24) a (+ ao 24)))

(defun bnf-fp12-set-one (r ro)
  (declare (type bnf-words r) (type bnf-index ro))
  (bnf-fp6-set-zero r ro)
  (bnf-fp6-set-one r (+ ro 24)))

(defun bnf-fp12-one-p (a ao)
  (declare (type bnf-words a) (type bnf-index ao))
  (and (bnf-fp6-zero-p a ao) (bnf-fp6-one-p a (+ ao 24))))

(defun bnf-fp12-conjugate (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao))
  (bnf-fp6-neg r ro a ao)
  (bnf-fp6-copy r (+ ro 24) a (+ ao 24)))

(defun bnf-fp12-mul (r ro a ao b bo)
  "x = xa yb + xb ya, y = ya yb + tau xa xb, with three Fp6 products."
  (declare (type bnf-words r a b) (type bnf-index ro ao bo))
  (with-bnf-scratch (s (xx 24) (yy 24) (sa 24) (sb 24))
    (progn
      (bnf-fp6-mul s xx a ao b bo)
      (bnf-fp6-mul s yy a (+ ao 24) b (+ bo 24))
      (bnf-fp6-add s sa a ao a (+ ao 24))
      (bnf-fp6-add s sb b bo b (+ bo 24))
      (bnf-fp6-mul s sa s sa s sb)
      (bnf-fp6-sub s sa s sa s xx)
      (bnf-fp6-sub s sa s sa s yy)
      (bnf-fp6-mul-tau s xx s xx)
      (bnf-fp6-add r (+ ro 24) s yy s xx)
      (bnf-fp6-copy r ro s sa))))

(defun bnf-fp12-square (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao))
  (with-bnf-scratch (s (v0 24) (tt 24) (ty 24))
    (progn
      (bnf-fp6-mul s v0 a ao a (+ ao 24))
      (bnf-fp6-mul-tau s tt a ao)
      (bnf-fp6-add s tt s tt a (+ ao 24))
      (bnf-fp6-add s ty a ao a (+ ao 24))
      (bnf-fp6-mul s ty s ty s tt)
      (bnf-fp6-sub s ty s ty s v0)
      (bnf-fp6-mul-tau s tt s v0)
      (bnf-fp6-sub r (+ ro 24) s ty s tt)
      (bnf-fp6-double r ro s v0))))

(defun bnf-fp12-inverse (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao))
  (with-bnf-scratch (s (d 24) (e 24))
    (bnf-fp6-square s d a ao)
    (bnf-fp6-mul-tau s d s d)
    (bnf-fp6-square s e a (+ ao 24))
    (bnf-fp6-sub s d s e s d)
    (bnf-fp6-inverse s d s d)
    (bnf-fp6-neg s e a ao)
    (bnf-fp6-mul r ro s e s d)
    (bnf-fp6-mul r (+ ro 24) a (+ ao 24) s d)))

(defun bnf-fp12-exp (r ro a ao power)
  "R := A^POWER for a non-negative integer POWER (square and multiply)."
  (declare (type bnf-words r a) (type bnf-index ro ao)
           (type (integer 0) power))
  (with-bnf-scratch (s (result 48) (base 48))
    (bnf-fp12-copy s base a ao)
    (bnf-fp12-set-one s result)
    (loop for i from (1- (integer-length power)) downto 0
          do (bnf-fp12-square s result s result)
             (when (logbitp i power)
               (bnf-fp12-mul s result s result s base)))
    (bnf-fp12-copy r ro s result)))

(defun bnf-fp12-frobenius (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao))
  (bnf-fp6-frobenius r ro a ao)
  (bnf-fp6-mul-fp2 r ro r ro (bnf-fp2-constant +bn254-xi-to-p-minus-1-over-6+) 0)
  (bnf-fp6-frobenius r (+ ro 24) a (+ ao 24)))

(defun bnf-fp12-frobenius-p2 (r ro a ao)
  (declare (type bnf-words r a) (type bnf-index ro ao))
  (bnf-fp6-frobenius-p2 r ro a ao)
  (bnf-fp6-mul-fp r ro r ro
                  (bnf-fp-constant +bn254-xi-to-p-squared-minus-1-over-6+) 0)
  (bnf-fp6-frobenius-p2 r (+ ro 24) a (+ ao 24)))

(defun bnf-fp12-mul-line (r ro line lo)
  "Multiply the Fp12 element R in place by the line (a, b, c) at LINE/LO.

The line is the sparse element (0, a, b) w + (0, 0, c); this is
BN254-FP12-MUL-LINE's schedule."
  (declare (type bnf-words r line) (type bnf-index ro lo))
  (with-bnf-scratch (s (a2 24) (t3 24) (t2 24) (sum 24))
    (progn
      ;; a2 = (0, a, b) * x
      (bnf-fp2-set-zero s a2)
      (bnf-fp2-copy s (+ a2 8) line lo)
      (bnf-fp2-copy s (+ a2 16) line (+ lo 8))
      (bnf-fp6-mul s a2 s a2 r ro)
      ;; t3 = y * c
      (bnf-fp6-mul-fp2 s t3 r (+ ro 24) line (+ lo 16))
      ;; t2 = (0, a, b + c)
      (bnf-fp2-set-zero s t2)
      (bnf-fp2-copy s (+ t2 8) line lo)
      (bnf-fp2-add s (+ t2 16) line (+ lo 8) line (+ lo 16))
      ;; x' = (x + y) t2 - a2 - t3; y' = t3 + tau a2
      (bnf-fp6-add s sum r ro r (+ ro 24))
      (bnf-fp6-mul s sum s sum s t2)
      (bnf-fp6-sub s sum s sum s a2)
      (bnf-fp6-sub r ro s sum s t3)
      (bnf-fp6-mul-tau s a2 s a2)
      (bnf-fp6-add r (+ ro 24) s t3 s a2))))
