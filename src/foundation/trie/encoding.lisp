(in-package #:ethereum-lisp.trie.encoding)

(defconstant +terminator-nibble+ 16)

(defun has-terminator-p (nibbles)
  (let ((nibbles (ensure-byte-vector nibbles)))
    (and (> (length nibbles) 0)
         (= (aref nibbles (1- (length nibbles))) +terminator-nibble+))))

(defun validate-nibbles (nibbles &key allow-terminator)
  (let ((nibbles (ensure-byte-vector nibbles)))
    (loop for nibble across nibbles
          for i from 0
          do (unless (or (< nibble 16)
                         (and allow-terminator
                              (= nibble +terminator-nibble+)
                              (= i (1- (length nibbles)))))
               (error "Invalid trie nibble ~D at position ~D" nibble i)))
    nibbles))

(defun keybytes-to-nibbles (bytes &key (terminator t))
  (let* ((bytes (ensure-byte-vector bytes))
         (extra (if terminator 1 0))
         (result (make-byte-vector (+ (* 2 (length bytes)) extra))))
    (loop for byte across bytes
          for i from 0 by 2
          do (setf (aref result i) (ash byte -4)
                   (aref result (1+ i)) (logand byte #x0f)))
    (when terminator
      (setf (aref result (1- (length result))) +terminator-nibble+))
    result))

(defun nibbles-to-keybytes (nibbles)
  (let ((nibbles (validate-nibbles nibbles :allow-terminator t)))
    (when (has-terminator-p nibbles)
      (setf nibbles (subseq nibbles 0 (1- (length nibbles)))))
    (unless (evenp (length nibbles))
      (error "Cannot pack odd nibble count into bytes: ~D" (length nibbles)))
    (let ((result (make-byte-vector (/ (length nibbles) 2))))
      (loop for i below (length nibbles) by 2
            for out from 0
            do (setf (aref result out)
                     (logior (ash (aref nibbles i) 4)
                             (aref nibbles (1+ i)))))
      result)))

(defun pack-nibbles (nibbles)
  (let ((result (make-byte-vector (/ (length nibbles) 2))))
    (loop for i below (length nibbles) by 2
          for out from 0
          do (setf (aref result out)
                   (logior (ash (aref nibbles i) 4)
                           (aref nibbles (1+ i)))))
    result))

(defun hex-prefix-encode (nibbles &key terminator)
  (let* ((nibbles (validate-nibbles nibbles :allow-terminator t))
         (leaf (or terminator (has-terminator-p nibbles))))
    (when (has-terminator-p nibbles)
      (setf nibbles (subseq nibbles 0 (1- (length nibbles)))))
    (let* ((oddp (oddp (length nibbles)))
           (flags (+ (if leaf 2 0) (if oddp 1 0)))
           (prefixed (if oddp
                         (concatenate 'vector (vector flags) nibbles)
                         (concatenate 'vector (vector flags 0) nibbles))))
      (pack-nibbles prefixed))))

(defun hex-prefix-decode (bytes)
  (let* ((base (keybytes-to-nibbles bytes :terminator nil))
         (flag (aref base 0))
         (leaf (>= flag 2))
         (oddp (oddp flag))
         (start (if oddp 1 2))
         (path (subseq base start)))
    (values (if leaf
                (concatenate 'vector path (vector +terminator-nibble+))
                path)
            leaf)))

(defun common-prefix-length (left right)
  (let* ((left (ensure-byte-vector left))
         (right (ensure-byte-vector right))
         (limit (min (length left) (length right))))
    (loop for i below limit
          while (= (aref left i) (aref right i))
          finally (return i))))
