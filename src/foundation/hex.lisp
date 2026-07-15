(in-package #:ethereum-lisp.hex)

(defun hex-digit-value (char)
  (cond
    ((char<= #\0 char #\9) (- (char-code char) (char-code #\0)))
    ((char<= #\a char #\f) (+ 10 (- (char-code char) (char-code #\a))))
    ((char<= #\A char #\F) (+ 10 (- (char-code char) (char-code #\A))))
    (t (error "Invalid hexadecimal digit: ~S" char))))

(defun strip-hex-prefix (string)
  (if (and (>= (length string) 2)
           (char= (char string 0) #\0)
           (member (char string 1) '(#\x #\X)))
      (subseq string 2)
      string))

(defun bytes-to-hex (bytes &key (prefix t))
  (let* ((bytes (ensure-byte-vector bytes))
         (digits "0123456789abcdef")
         (result (make-string (+ (if prefix 2 0) (* 2 (length bytes))))))
    (when prefix
      (setf (aref result 0) #\0
            (aref result 1) #\x))
    (loop for byte across bytes
          for i from (if prefix 2 0) by 2
          do (setf (aref result i) (aref digits (ash byte -4))
                   (aref result (1+ i)) (aref digits (logand byte #x0f))))
    result))

(defun hex-to-bytes (string)
  (check-type string string)
  (let* ((hex (strip-hex-prefix string))
         (length (length hex)))
    (unless (evenp length)
      (error "Hex byte strings must have an even number of digits: ~S" string))
    (let ((result (make-byte-vector (/ length 2))))
      (loop for i below length by 2
            for out from 0
            do (setf (aref result out)
                     (+ (ash (hex-digit-value (aref hex i)) 4)
                        (hex-digit-value (aref hex (1+ i))))))
      result)))

(defun quantity-to-hex (integer)
  (check-type integer (integer 0 *))
  (string-downcase (format nil "0x~x" integer)))

(defun hex-to-quantity (string)
  (check-type string string)
  (let ((hex (strip-hex-prefix string)))
    (if (zerop (length hex))
        0
        (parse-integer hex :radix 16))))
