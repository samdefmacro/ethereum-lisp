(in-package #:ethereum-lisp.bytes)

(deftype byte-vector ()
  '(simple-array (unsigned-byte 8) (*)))

(defun make-byte-vector (length &key (initial-element 0))
  (make-array length
              :element-type '(unsigned-byte 8)
              :initial-element initial-element))

(defun byte-vector-p (value)
  (typep value 'byte-vector))

(defun ensure-byte-vector (value)
  (etypecase value
    (byte-vector value)
    (vector
     (make-array (length value)
                 :element-type '(unsigned-byte 8)
                 :initial-contents value))
    (list
     (make-array (length value)
                 :element-type '(unsigned-byte 8)
                 :initial-contents value))))

(defun bytes= (left right)
  (let ((left (ensure-byte-vector left))
        (right (ensure-byte-vector right)))
    (and (= (length left) (length right))
         (loop for i below (length left)
               always (= (aref left i) (aref right i))))))

(defun concat-bytes (&rest byte-vectors)
  (let* ((parts (mapcar #'ensure-byte-vector byte-vectors))
         (total-length (reduce #'+ parts :key #'length :initial-value 0))
         (result (make-byte-vector total-length)))
    (loop with offset = 0
          for part in parts
          do (replace result part :start1 offset)
             (incf offset (length part)))
    result))

(defun integer-to-minimal-bytes (integer)
  (check-type integer (integer 0 *))
  (if (zerop integer)
      (make-byte-vector 0)
      (loop with octets = '()
            for value = integer then (ash value -8)
            until (zerop value)
            do (push (logand value #xff) octets)
            finally (return (ensure-byte-vector octets)))))

(defun bytes-to-integer (bytes)
  (loop for byte across (ensure-byte-vector bytes)
        for value = byte then (+ (ash value 8) byte)
        finally (return (or value 0))))

(defun ascii-to-bytes (string)
  (check-type string string)
  (let ((result (make-byte-vector (length string))))
    (loop for char across string
          for i from 0
          for code = (char-code char)
          do (unless (<= 0 code 127)
               (error "Not an ASCII character: ~S" char))
             (setf (aref result i) code))
    result))

(defun bytes-to-ascii (bytes)
  (coerce (loop for byte across (ensure-byte-vector bytes)
                collect (code-char byte))
          'string))

(defparameter +crc32-table+
  (let ((table (make-array 256 :element-type '(unsigned-byte 32))))
    (dotimes (n 256 table)
      (let ((c n))
        (dotimes (k 8)
          (setf c (if (logtest c 1)
                      (logxor #xedb88320 (ash c -1))
                      (ash c -1))))
        (setf (aref table n) c))))
  "IEEE 802.3 CRC-32 lookup table, reflected, polynomial 0xEDB88320.")

(defun crc32 (bytes &key (start 0) end)
  "Return the IEEE CRC-32 of BYTES, or of its [START, END) range, as an
\(unsigned-byte 32)."
  (let* ((octets (ensure-byte-vector bytes))
         (end (or end (length octets)))
         (crc #xffffffff))
    (loop for index from start below end
          do (setf crc (logxor (ash crc -8)
                               (aref +crc32-table+
                                     (logand (logxor crc (aref octets index))
                                             #xff)))))
    (logand (logxor crc #xffffffff) #xffffffff)))
