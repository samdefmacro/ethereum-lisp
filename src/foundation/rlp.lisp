(in-package #:ethereum-lisp.rlp)

(define-condition rlp-error (error)
  ((message :initarg :message :reader rlp-error-message))
  (:report (lambda (condition stream)
             (format stream "~A" (rlp-error-message condition)))))

(defconstant +rlp-max-depth+ 64
  "Maximum list nesting accepted by the generic RLP decoder.

This is a resource bound, not an Ethereum consensus limit. Protocol objects in
this client are shallower by orders of magnitude; the bound prevents hostile
network input from consuming the Lisp control stack.")

(defstruct (rlp-list (:constructor make-rlp-list (&rest items)))
  (items '() :type list))

(defconstant +maximum-rlp-nesting-depth+ +rlp-max-depth+)

(defun fail (control &rest args)
  (error 'rlp-error :message (apply #'format nil control args)))

(defun encode-length (offset length)
  (if (<= length 55)
      (ensure-byte-vector (list (+ offset length)))
      (let ((length-bytes (integer-to-minimal-bytes length)))
        (concat-bytes (ensure-byte-vector
                       (list (+ offset 55 (length length-bytes))))
                      length-bytes))))

(defun rlp-encode-bytes (bytes)
  (let ((bytes (ensure-byte-vector bytes)))
    (if (and (= (length bytes) 1)
             (< (aref bytes 0) #x80))
        bytes
        (concat-bytes (encode-length #x80 (length bytes)) bytes))))

(defun rlp-encode-list-items (items)
  (let ((payload (apply #'concat-bytes (mapcar #'rlp-encode items))))
    (concat-bytes (encode-length #xc0 (length payload)) payload)))

(defun rlp-encode (value)
  (etypecase value
    ((integer 0 *) (rlp-encode-bytes (integer-to-minimal-bytes value)))
    (string (rlp-encode-bytes (ascii-to-bytes value)))
    (byte-vector (rlp-encode-bytes value))
    (rlp-list (rlp-encode-list-items (rlp-list-items value)))
    (list (rlp-encode-list-items value))))

(defun require-available (bytes position needed)
  (when (> (+ position needed) (length bytes))
    (fail "RLP item overruns input at byte ~D" position)))

(defun read-length (bytes position length-of-length)
  (require-available bytes position length-of-length)
  (let ((length-bytes (subseq bytes position (+ position length-of-length))))
    (when (and (> length-of-length 1)
               (zerop (aref length-bytes 0)))
      (fail "RLP length has leading zero at byte ~D" position))
    (values (bytes-to-integer length-bytes)
            (+ position length-of-length))))

(defun decode-string-payload (bytes payload-start length)
  (require-available bytes payload-start length)
  (subseq bytes payload-start (+ payload-start length)))

(defun decode-list-payload
    (bytes payload-start payload-end depth maximum-depth max-list-items)
  (loop with items = '()
        with position = payload-start
        with item-count = 0
        while (< position payload-end)
        do (multiple-value-bind (item next-position)
               (%rlp-decode bytes position t (1+ depth) maximum-depth
                            max-list-items)
             (incf item-count)
             (when (and max-list-items (> item-count max-list-items))
               (fail "RLP list contains more than ~D items at byte ~D"
                     max-list-items payload-start))
             (push item items)
             (setf position next-position))
        finally
           (unless (= position payload-end)
             (fail "RLP list payload ended at ~D, expected ~D"
                   position payload-end))
           (return (apply #'make-rlp-list (nreverse items)))))

(defun %rlp-decode
    (bytes start allow-trailing depth maximum-depth max-list-items)
  (when (> depth maximum-depth)
    (fail "RLP nesting depth exceeds maximum ~D" maximum-depth))
  (let ((input-length (length bytes)))
    (when (>= start input-length)
      (fail "No RLP item at byte ~D" start))
    (let ((prefix (aref bytes start)))
      (multiple-value-bind (value next-position)
          (cond
            ((< prefix #x80)
             (values (ensure-byte-vector (list prefix)) (1+ start)))
            ((<= prefix #xb7)
             (let* ((length (- prefix #x80))
                    (payload-start (1+ start))
                    (payload (decode-string-payload bytes payload-start length)))
               (when (and (= length 1) (< (aref payload 0) #x80))
                 (fail "RLP single byte string is not minimally encoded at byte ~D"
                       start))
               (values payload (+ payload-start length))))
            ((<= prefix #xbf)
             (let ((length-of-length (- prefix #xb7)))
               (multiple-value-bind (length payload-start)
                   (read-length bytes (1+ start) length-of-length)
                 (when (<= length 55)
                   (fail "RLP long string used for short payload at byte ~D"
                         start))
                 (values (decode-string-payload bytes payload-start length)
                         (+ payload-start length)))))
            ((<= prefix #xf7)
             (let* ((length (- prefix #xc0))
                    (payload-start (1+ start))
                    (payload-end (+ payload-start length)))
               (require-available bytes payload-start length)
               (values (decode-list-payload bytes payload-start payload-end
                                            depth maximum-depth max-list-items)
                       payload-end)))
            (t
             (let ((length-of-length (- prefix #xf7)))
               (multiple-value-bind (length payload-start)
                   (read-length bytes (1+ start) length-of-length)
                 (when (<= length 55)
                   (fail "RLP long list used for short payload at byte ~D"
                         start))
                 (let ((payload-end (+ payload-start length)))
                   (require-available bytes payload-start length)
                   (values (decode-list-payload bytes payload-start payload-end
                                                depth maximum-depth
                                                max-list-items)
                           payload-end))))))
        (unless (or allow-trailing (= next-position input-length))
          (fail "Trailing bytes after RLP item at byte ~D" next-position))
        (values value next-position)))))

(defun rlp-decode
    (bytes &key (start 0) (allow-trailing nil)
                (max-depth +rlp-max-depth+) maximum-depth max-list-items)
  "Decode one RLP item with nesting and per-list item resource bounds.

MAXIMUM-DEPTH is the compatibility spelling of MAX-DEPTH. When supplied it
takes precedence."
  (let ((maximum-depth (or maximum-depth max-depth)))
    (unless (and (integerp maximum-depth) (not (minusp maximum-depth)))
    (fail "RLP maximum depth must be a non-negative integer"))
    (unless (or (null max-list-items)
                (and (integerp max-list-items) (not (minusp max-list-items))))
      (fail "RLP maximum list item count must be a non-negative integer or NIL"))
    (%rlp-decode (ensure-byte-vector bytes)
                 start allow-trailing 0 maximum-depth max-list-items)))

(defun rlp-decode-one (bytes)
  (rlp-decode bytes))
