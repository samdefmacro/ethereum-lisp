(in-package #:ethereum-lisp.evm.internal)

(defun bn254-fp6 (x y z)
  (list x y z))

(defun bn254-fp6-x (value) (first value))
(defun bn254-fp6-y (value) (second value))
(defun bn254-fp6-z (value) (third value))

(defun bn254-fp6-zero ()
  (bn254-fp6 (bn254-fp2-zero) (bn254-fp2-zero) (bn254-fp2-zero)))

(defun bn254-fp6-one ()
  (bn254-fp6 (bn254-fp2-zero) (bn254-fp2-zero) (bn254-fp2-one)))

(defun bn254-fp6-zero-p (value)
  (and (bn254-fp2-zero-p (bn254-fp6-x value))
       (bn254-fp2-zero-p (bn254-fp6-y value))
       (bn254-fp2-zero-p (bn254-fp6-z value))))

(defun bn254-fp6-one-p (value)
  (and (bn254-fp2-zero-p (bn254-fp6-x value))
       (bn254-fp2-zero-p (bn254-fp6-y value))
       (bn254-fp2-one-p (bn254-fp6-z value))))

(defun bn254-fp6-neg (value)
  (bn254-fp6 (bn254-fp2-neg (bn254-fp6-x value))
             (bn254-fp2-neg (bn254-fp6-y value))
             (bn254-fp2-neg (bn254-fp6-z value))))

(defun bn254-fp6-add (left right)
  (bn254-fp6 (bn254-fp2-add (bn254-fp6-x left) (bn254-fp6-x right))
             (bn254-fp2-add (bn254-fp6-y left) (bn254-fp6-y right))
             (bn254-fp2-add (bn254-fp6-z left) (bn254-fp6-z right))))

(defun bn254-fp6-sub (left right)
  (bn254-fp6 (bn254-fp2-sub (bn254-fp6-x left) (bn254-fp6-x right))
             (bn254-fp2-sub (bn254-fp6-y left) (bn254-fp6-y right))
             (bn254-fp2-sub (bn254-fp6-z left) (bn254-fp6-z right))))

(defun bn254-fp6-double (value)
  (bn254-fp6 (bn254-fp2-double (bn254-fp6-x value))
             (bn254-fp2-double (bn254-fp6-y value))
             (bn254-fp2-double (bn254-fp6-z value))))

(defun bn254-fp6-mul (left right)
  (let* ((v0 (bn254-fp2-mul (bn254-fp6-z left) (bn254-fp6-z right)))
         (v1 (bn254-fp2-mul (bn254-fp6-y left) (bn254-fp6-y right)))
         (v2 (bn254-fp2-mul (bn254-fp6-x left) (bn254-fp6-x right)))
         (tz (bn254-fp2-mul
              (bn254-fp2-add (bn254-fp6-x left) (bn254-fp6-y left))
              (bn254-fp2-add (bn254-fp6-x right) (bn254-fp6-y right))))
         (tz (bn254-fp2-add
              (bn254-fp2-mul-xi (bn254-fp2-sub (bn254-fp2-sub tz v1) v2))
              v0))
         (ty (bn254-fp2-mul
              (bn254-fp2-add (bn254-fp6-y left) (bn254-fp6-z left))
              (bn254-fp2-add (bn254-fp6-y right) (bn254-fp6-z right))))
         (ty (bn254-fp2-add
              (bn254-fp2-sub (bn254-fp2-sub ty v0) v1)
              (bn254-fp2-mul-xi v2)))
         (tx (bn254-fp2-mul
              (bn254-fp2-add (bn254-fp6-x left) (bn254-fp6-z left))
              (bn254-fp2-add (bn254-fp6-x right) (bn254-fp6-z right))))
         (tx (bn254-fp2-sub (bn254-fp2-add (bn254-fp2-sub tx v0) v1) v2)))
    (bn254-fp6 tx ty tz)))

(defun bn254-fp6-square (value)
  (let* ((v0 (bn254-fp2-square (bn254-fp6-z value)))
         (v1 (bn254-fp2-square (bn254-fp6-y value)))
         (v2 (bn254-fp2-square (bn254-fp6-x value)))
         (c0 (bn254-fp2-square
              (bn254-fp2-add (bn254-fp6-x value) (bn254-fp6-y value))))
         (c0 (bn254-fp2-add
              (bn254-fp2-mul-xi (bn254-fp2-sub (bn254-fp2-sub c0 v1) v2))
              v0))
         (c1 (bn254-fp2-square
              (bn254-fp2-add (bn254-fp6-y value) (bn254-fp6-z value))))
         (c1 (bn254-fp2-add
              (bn254-fp2-sub (bn254-fp2-sub c1 v0) v1)
              (bn254-fp2-mul-xi v2)))
         (c2 (bn254-fp2-square
              (bn254-fp2-add (bn254-fp6-x value) (bn254-fp6-z value))))
         (c2 (bn254-fp2-sub (bn254-fp2-add (bn254-fp2-sub c2 v0) v1) v2)))
    (bn254-fp6 c2 c1 c0)))

(defun bn254-fp6-mul-scalar-fp2 (value scalar)
  (bn254-fp6 (bn254-fp2-mul (bn254-fp6-x value) scalar)
             (bn254-fp2-mul (bn254-fp6-y value) scalar)
             (bn254-fp2-mul (bn254-fp6-z value) scalar)))

(defun bn254-fp6-mul-scalar-fp (value scalar)
  (bn254-fp6 (bn254-fp2-mul-scalar (bn254-fp6-x value) scalar)
             (bn254-fp2-mul-scalar (bn254-fp6-y value) scalar)
             (bn254-fp2-mul-scalar (bn254-fp6-z value) scalar)))

(defun bn254-fp6-mul-tau (value)
  (bn254-fp6 (bn254-fp6-y value)
             (bn254-fp6-z value)
             (bn254-fp2-mul-xi (bn254-fp6-x value))))

(defun bn254-fp6-inverse (value)
  (let* ((a (bn254-fp2-sub
             (bn254-fp2-square (bn254-fp6-z value))
             (bn254-fp2-mul-xi
              (bn254-fp2-mul (bn254-fp6-x value) (bn254-fp6-y value)))))
         (b (bn254-fp2-sub
             (bn254-fp2-mul-xi (bn254-fp2-square (bn254-fp6-x value)))
             (bn254-fp2-mul (bn254-fp6-y value) (bn254-fp6-z value))))
         (c (bn254-fp2-sub
             (bn254-fp2-square (bn254-fp6-y value))
             (bn254-fp2-mul (bn254-fp6-x value) (bn254-fp6-z value))))
         (f (bn254-fp2-add
             (bn254-fp2-add
              (bn254-fp2-mul-xi (bn254-fp2-mul c (bn254-fp6-y value)))
              (bn254-fp2-mul a (bn254-fp6-z value)))
             (bn254-fp2-mul-xi (bn254-fp2-mul b (bn254-fp6-x value)))))
         (f-inv (bn254-fp2-inverse f)))
    (bn254-fp6 (bn254-fp2-mul c f-inv)
               (bn254-fp2-mul b f-inv)
               (bn254-fp2-mul a f-inv))))

(defparameter +bn254-xi-to-p-minus-1-over-6+
  (bn254-fp2 8376118865763821496583973867626364092589906065868298776909617916018768340080
             16469823323077808223889137241176536799009286646108169935659301613961712198316))

(defparameter +bn254-xi-to-p-minus-1-over-3+
  (bn254-fp2 21575463638280843010398324269430826099269044274347216827212613867836435027261
             10307601595873709700152284273816112264069230130616436755625194854815875713954))

(defparameter +bn254-xi-to-p-minus-1-over-2+
  (bn254-fp2 2821565182194536844548159561693502659359617185244120367078079554186484126554
             3505843767911556378687030309984248845540243509899259641013678093033130930403))

(defparameter +bn254-xi-to-p-squared-minus-1-over-3+
  21888242871839275220042445260109153167277707414472061641714758635765020556616)

(defparameter +bn254-xi-to-2p-squared-minus-2-over-3+
  2203960485148121921418603742825762020974279258880205651966)

(defparameter +bn254-xi-to-p-squared-minus-1-over-6+
  21888242871839275220042445260109153167277707414472061641714758635765020556617)

(defparameter +bn254-xi-to-2p-minus-2-over-3+
  (bn254-fp2 2581911344467009335267311115468803099551665605076196740867805258568234346338
             19937756971775647987995932169929341994314640652964949448313374472400716661030))

(defun bn254-fp6-frobenius (value)
  (bn254-fp6
   (bn254-fp2-mul
    (bn254-fp2-conjugate (bn254-fp6-x value))
    +bn254-xi-to-2p-minus-2-over-3+)
   (bn254-fp2-mul
    (bn254-fp2-conjugate (bn254-fp6-y value))
    +bn254-xi-to-p-minus-1-over-3+)
   (bn254-fp2-conjugate (bn254-fp6-z value))))

(defun bn254-fp6-frobenius-p2 (value)
  (bn254-fp6
   (bn254-fp2-mul-scalar (bn254-fp6-x value)
                         +bn254-xi-to-2p-squared-minus-2-over-3+)
   (bn254-fp2-mul-scalar (bn254-fp6-y value)
                         +bn254-xi-to-p-squared-minus-1-over-3+)
   (bn254-fp6-z value)))

(defun bn254-fp12 (x y)
  (list x y))

(defun bn254-fp12-x (value) (first value))
(defun bn254-fp12-y (value) (second value))

(defun bn254-fp12-one ()
  (bn254-fp12 (bn254-fp6-zero) (bn254-fp6-one)))

(defun bn254-fp12-one-p (value)
  (and (bn254-fp6-zero-p (bn254-fp12-x value))
       (bn254-fp6-one-p (bn254-fp12-y value))))

(defun bn254-fp12-conjugate (value)
  (bn254-fp12 (bn254-fp6-neg (bn254-fp12-x value))
              (bn254-fp12-y value)))

(defun bn254-fp12-mul (left right)
  (let* ((tx (bn254-fp6-add
              (bn254-fp6-mul (bn254-fp12-x left) (bn254-fp12-y right))
              (bn254-fp6-mul (bn254-fp12-x right) (bn254-fp12-y left))))
         (ty (bn254-fp6-add
              (bn254-fp6-mul (bn254-fp12-y left) (bn254-fp12-y right))
              (bn254-fp6-mul-tau
               (bn254-fp6-mul (bn254-fp12-x left) (bn254-fp12-x right))))))
    (bn254-fp12 tx ty)))

(defun bn254-fp12-mul-scalar-fp6 (value scalar)
  (bn254-fp12 (bn254-fp6-mul (bn254-fp12-x value) scalar)
              (bn254-fp6-mul (bn254-fp12-y value) scalar)))

(defun bn254-fp12-square (value)
  (let* ((v0 (bn254-fp6-mul (bn254-fp12-x value) (bn254-fp12-y value)))
         (tau-term (bn254-fp6-add (bn254-fp6-mul-tau (bn254-fp12-x value))
                                  (bn254-fp12-y value)))
         (ty (bn254-fp6-mul
              (bn254-fp6-add (bn254-fp12-x value) (bn254-fp12-y value))
              tau-term))
         (ty (bn254-fp6-sub
              (bn254-fp6-sub ty v0)
              (bn254-fp6-mul-tau v0))))
    (bn254-fp12 (bn254-fp6-double v0) ty)))

(defun bn254-fp12-inverse (value)
  (let* ((t1 (bn254-fp6-mul-tau
              (bn254-fp6-square (bn254-fp12-x value))))
         (t2 (bn254-fp6-square (bn254-fp12-y value)))
         (inv (bn254-fp6-inverse (bn254-fp6-sub t2 t1))))
    (bn254-fp12-mul-scalar-fp6
     (bn254-fp12 (bn254-fp6-neg (bn254-fp12-x value))
                 (bn254-fp12-y value))
     inv)))

(defun bn254-fp12-exp (value power)
  (loop with result = (bn254-fp12-one)
        for i from (1- (integer-length power)) downto 0
        do (setf result (bn254-fp12-square result))
           (when (logbitp i power)
             (setf result (bn254-fp12-mul result value)))
        finally (return result)))

(defun bn254-fp12-frobenius (value)
  (bn254-fp12
   (bn254-fp6-mul-scalar-fp2
    (bn254-fp6-frobenius (bn254-fp12-x value))
    +bn254-xi-to-p-minus-1-over-6+)
   (bn254-fp6-frobenius (bn254-fp12-y value))))

(defun bn254-fp12-frobenius-p2 (value)
  (bn254-fp12
   (bn254-fp6-mul-scalar-fp
    (bn254-fp6-frobenius-p2 (bn254-fp12-x value))
    +bn254-xi-to-p-squared-minus-1-over-6+)
   (bn254-fp6-frobenius-p2 (bn254-fp12-y value))))
