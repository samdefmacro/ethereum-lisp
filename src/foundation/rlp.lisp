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
  ;; Encode each child once, then copy it directly into the final list.  The
  ;; old CONCAT-BYTES pair first allocated a complete payload and immediately
  ;; copied that payload into an equally large prefixed result.  SNAP proof
  ;; verification encodes millions of trie lists, so that temporary doubled
  ;; the dominant allocation without contributing any retained value.
  (let* ((encoded-items (mapcar #'rlp-encode items))
         (payload-length
           (reduce #'+ encoded-items :key #'length :initial-value 0))
         (prefix (encode-length #xc0 payload-length))
         (result (make-byte-vector (+ (length prefix) payload-length))))
    (replace result prefix)
    (loop with offset = (length prefix)
          for encoded in encoded-items
          do (replace result encoded :start1 offset)
             (incf offset (length encoded)))
    result))

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

(defun decode-string-payload
    (bytes payload-start length max-string-bytes)
  (when (and max-string-bytes (> length max-string-bytes))
    (fail "RLP string contains more than ~D bytes at byte ~D"
          max-string-bytes payload-start))
  (require-available bytes payload-start length)
  (subseq bytes payload-start (+ payload-start length)))

(defun consume-rlp-item-budget (item-budget position)
  "Charge one object before decoding it from untrusted input."
  (when item-budget
    (when (zerop (car item-budget))
      (fail "RLP item count exceeds maximum ~D at byte ~D"
            (cdr item-budget) position))
    (decf (car item-budget))))

(defun decode-list-payload
    (bytes payload-start payload-end depth maximum-depth max-list-items
     max-string-bytes item-budget)
  (loop with items = '()
        with position = payload-start
        with item-count = 0
        while (< position payload-end)
        do (when (and max-list-items (>= item-count max-list-items))
             (fail "RLP list contains more than ~D items at byte ~D"
                   max-list-items payload-start))
           ;; Check both budgets before descending into the next child.  A
           ;; rejected cap+1 child may itself be a large nested tree, so
           ;; charging after %RLP-DECODE would make the cap too late.
           (consume-rlp-item-budget item-budget position)
           (multiple-value-bind (item next-position)
               (%rlp-decode bytes position t (1+ depth) maximum-depth
                            max-list-items max-string-bytes item-budget)
             (incf item-count)
             (push item items)
             (setf position next-position))
        finally
           (unless (= position payload-end)
             (fail "RLP list payload ended at ~D, expected ~D"
                   position payload-end))
           (return (apply #'make-rlp-list (nreverse items)))))

(defun %rlp-decode
    (bytes start allow-trailing depth maximum-depth max-list-items
     max-string-bytes item-budget)
  (when (> depth maximum-depth)
    (fail "RLP nesting depth exceeds maximum ~D" maximum-depth))
  (let ((input-length (length bytes)))
    (when (>= start input-length)
      (fail "No RLP item at byte ~D" start))
    (let ((prefix (aref bytes start)))
      (multiple-value-bind (value next-position)
          (cond
            ((< prefix #x80)
             (when (and max-string-bytes (zerop max-string-bytes))
               (fail "RLP string contains more than 0 bytes at byte ~D" start))
             (values (ensure-byte-vector (list prefix)) (1+ start)))
            ((<= prefix #xb7)
             (let* ((length (- prefix #x80))
                    (payload-start (1+ start))
                    (payload (decode-string-payload
                              bytes payload-start length max-string-bytes)))
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
                 (values (decode-string-payload
                          bytes payload-start length max-string-bytes)
                         (+ payload-start length)))))
            ((<= prefix #xf7)
             (let* ((length (- prefix #xc0))
                    (payload-start (1+ start))
                    (payload-end (+ payload-start length)))
               (require-available bytes payload-start length)
               (values (decode-list-payload bytes payload-start payload-end
                                            depth maximum-depth max-list-items
                                            max-string-bytes item-budget)
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
                                                max-list-items max-string-bytes
                                                item-budget)
                           payload-end))))))
        (unless (or allow-trailing (= next-position input-length))
          (fail "Trailing bytes after RLP item at byte ~D" next-position))
        (values value next-position)))))

(defun rlp-decode
    (bytes &key (start 0) (allow-trailing nil)
                (max-depth +rlp-max-depth+) maximum-depth max-list-items
                max-total-items max-string-bytes)
  "Decode one RLP item with nesting, collection, and byte resource bounds.

MAXIMUM-DEPTH is the compatibility spelling of MAX-DEPTH. When supplied it
takes precedence. MAX-LIST-ITEMS applies to each list. MAX-TOTAL-ITEMS counts
the root and every nested RLP object under one shared budget. MAX-STRING-BYTES
is checked before copying a string payload."
  (let ((maximum-depth (or maximum-depth max-depth)))
    (unless (and (integerp maximum-depth) (not (minusp maximum-depth)))
      (fail "RLP maximum depth must be a non-negative integer"))
    (unless (or (null max-list-items)
                (and (integerp max-list-items) (not (minusp max-list-items))))
      (fail "RLP maximum list item count must be a non-negative integer or NIL"))
    (unless (or (null max-total-items)
                (and (integerp max-total-items)
                     (not (minusp max-total-items))))
      (fail "RLP maximum total item count must be a non-negative integer or NIL"))
    (unless (or (null max-string-bytes)
                (and (integerp max-string-bytes)
                     (not (minusp max-string-bytes))))
      (fail "RLP maximum string byte count must be a non-negative integer or NIL"))
    (let ((item-budget (and max-total-items
                            (cons max-total-items max-total-items))))
      (consume-rlp-item-budget item-budget start)
      (%rlp-decode (ensure-byte-vector bytes)
                   start allow-trailing 0 maximum-depth max-list-items
                   max-string-bytes item-budget))))

(defun rlp-decode-one
    (bytes &key (max-depth +rlp-max-depth+) maximum-depth max-list-items
                max-total-items max-string-bytes)
  "Decode exactly one RLP object, optionally applying the generic resource caps."
  (rlp-decode bytes :max-depth max-depth :maximum-depth maximum-depth
                    :max-list-items max-list-items
                    :max-total-items max-total-items
                    :max-string-bytes max-string-bytes))
