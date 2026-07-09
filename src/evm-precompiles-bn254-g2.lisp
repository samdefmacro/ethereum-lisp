(in-package #:ethereum-lisp.evm)

(defun bn254-g2-curve-constant ()
  (let ((inverse-82 (bn254-modular-inverse 82)))
    (bn254-fp2 (* 27 inverse-82)
               (- (* 3 inverse-82)))))

(defun bn254-g2-on-curve-p (x y)
  (let ((left (bn254-fp2-square y))
        (right (bn254-fp2-add
                (bn254-fp2-mul (bn254-fp2-square x) x)
                (bn254-g2-curve-constant))))
    (and (= (car left) (car right))
         (= (cdr left) (cdr right)))))

(defun bn254-g2-add (left right)
  (cond
    ((null left) right)
    ((null right) left)
    (t
     (destructuring-bind (x1 y1) left
       (destructuring-bind (x2 y2) right
         (cond
           ((and (bn254-fp2= x1 x2)
                 (bn254-fp2-negation-p y1 y2))
            nil)
           (t
            (let* ((slope
                     (if (and (bn254-fp2= x1 x2)
                              (bn254-fp2= y1 y2))
                         (bn254-fp2-mul
                          (bn254-fp2-mul (bn254-fp2 3 0)
                                         (bn254-fp2-square x1))
                          (bn254-fp2-inverse
                           (bn254-fp2-mul (bn254-fp2 2 0) y1)))
                         (bn254-fp2-mul
                          (bn254-fp2-sub y2 y1)
                          (bn254-fp2-inverse (bn254-fp2-sub x2 x1)))))
                   (x3 (bn254-fp2-sub
                        (bn254-fp2-sub (bn254-fp2-square slope) x1)
                        x2))
                   (y3 (bn254-fp2-sub
                        (bn254-fp2-mul slope (bn254-fp2-sub x1 x3))
                        y1)))
              (list x3 y3)))))))))

(defun bn254-g2-mul (point scalar)
  (loop with result = nil
        with addend = point
        for k = scalar then (ash k -1)
        while (plusp k)
        do (when (oddp k)
             (setf result (bn254-g2-add result addend)))
           (setf addend (bn254-g2-add addend addend))
        finally (return result)))

(defun bn254-g2-subgroup-p (point)
  (null (bn254-g2-mul point +bn254-curve-order+)))

(defun parse-bn254-g2-pairing-point (bytes gas-used)
  (let ((bytes (padded-data-slice bytes 0 128)))
    (cond
      ((loop for byte across bytes always (zerop byte)) nil)
      (t
       (let ((x-imaginary (bytes-to-integer (subseq bytes 0 32)))
             (x-real (bytes-to-integer (subseq bytes 32 64)))
             (y-imaginary (bytes-to-integer (subseq bytes 64 96)))
             (y-real (bytes-to-integer (subseq bytes 96 128))))
         (unless (and (bn254-valid-coordinate-p x-real)
                      (bn254-valid-coordinate-p x-imaginary)
                      (bn254-valid-coordinate-p y-real)
                      (bn254-valid-coordinate-p y-imaginary))
           (fail-precompile gas-used "Invalid BN254 G2 coordinate"))
         (let ((x (bn254-fp2 x-real x-imaginary))
               (y (bn254-fp2 y-real y-imaginary)))
           (unless (bn254-g2-on-curve-p x y)
             (fail-precompile gas-used "Invalid BN254 G2 point"))
           (let ((point (list x y)))
             (unless (bn254-g2-subgroup-p point)
               (fail-precompile gas-used "Invalid BN254 G2 subgroup"))
             point)))))))

(defun bn254-fp2= (left right)
  (and (= (car left) (car right))
       (= (cdr left) (cdr right))))

(defun bn254-fp2-negation-p (left right)
  (and (zerop (mod (+ (car left) (car right))
                   +bn254-field-prime+))
       (zerop (mod (+ (cdr left) (cdr right))
                   +bn254-field-prime+))))
