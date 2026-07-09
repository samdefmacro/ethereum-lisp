(in-package #:ethereum-lisp.evm)

(defun read-push-immediate (code pc size)
  (let ((value 0))
    (dotimes (i size value)
      (let ((index (+ pc 1 i)))
        (setf value
              (+ (ash value 8)
                 (if (< index (length code)) (aref code index) 0)))))))

(defun byte-op (index value)
  (if (>= index 32)
      0
      (logand #xff (ash value (* -8 (- 31 index))))))

(defun exp-byte-count (exponent)
  (if (zerop exponent)
      0
      (ceiling (integer-length exponent) 8)))

(defun exp-byte-gas (rules)
  (if (or (null rules) (chain-rules-eip158-p rules))
      +exp-byte-gas-eip160+
      +exp-byte-gas+))

(defun code-position-p (code position)
  (loop with pc = 0
        while (< pc (length code))
        do (let ((op (aref code pc)))
             (when (= pc position)
               (return t))
             (if (<= #x60 op #x7f)
                 (incf pc (+ 1 (- op #x5f)))
                 (incf pc)))
        finally (return nil)))

(defun valid-jump-destination-p (code destination)
  (and (< destination (length code))
       (= (aref code destination) #x5b)
       (code-position-p code destination)))

(defun opcode-base-gas (op)
  (cond
    ((= op #x00) 0)
    ((member op '(#x01 #x03 #x10 #x11 #x12 #x13 #x14 #x15 #x16 #x17 #x18 #x19
                  #x1a #x1b #x1c #x1d #x35 #x51 #x52 #x53 #x5e)
             :test #'=)
     3)
    ((member op '(#x02 #x04 #x05 #x06 #x07) :test #'=) 5)
    ((member op '(#x08 #x09) :test #'=) 8)
    ((= op #x0a) 10)
    ((= op #x0b) 5)
    ((= op #x20) 30)
    ((member op '(#x30 #x32 #x33 #x34 #x36 #x38 #x3a #x3d
                  #x41 #x42 #x43 #x44 #x45 #x46 #x48
                  #x4a #x58 #x59 #x5a)
             :test #'=)
     2)
    ((= op #x47) 5)
    ((= op #x49) 3)
    ((= op #x31) 100)
    ((member op '(#x3b #x3c #x3f) :test #'=) 100)
    ((= op #x3e) 3)
    ((= op #x40) 20)
    ((member op '(#x37 #x39) :test #'=) 3)
    ((= op #x50) 2)
    ((= op #x54) 0)
    ((= op #x55) 0)
    ((= op #x56) 8)
    ((= op #x57) 10)
    ((member op '(#x5c #x5d) :test #'=) 100)
    ((= op #x5b) 1)
    ((= op #x5f) 2)
    ((<= #x60 op #x7f) 3)
    ((<= #x80 op #x9f) 3)
    ((<= #xa0 op #xa4) 375)
    ((member op '(#xf0 #xf5) :test #'=) 32000)
    ((member op '(#xf1 #xf2 #xf4 #xfa) :test #'=) 100)
    ((member op '(#xf3 #xfd) :test #'=) 0)
    ((= op #xff) 5000)
    (t 0)))
