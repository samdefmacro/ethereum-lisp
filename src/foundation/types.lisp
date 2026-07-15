(in-package #:ethereum-lisp.types)

(defconstant +uint256-max+ (1- (expt 2 256)))

(defun uint256-p (value)
  (and (integerp value)
       (<= 0 value +uint256-max+)))

(defun require-sized-bytes (bytes size label)
  (let ((bytes (ensure-byte-vector bytes)))
    (unless (= (length bytes) size)
      (error "~A must be exactly ~D bytes, got ~D"
             label size (length bytes)))
    bytes))

(defstruct (address
            (:constructor %make-address (bytes))
            (:conc-name %address-))
  (bytes (make-byte-vector 20) :type byte-vector :read-only t))

(defun make-address (bytes)
  (%make-address (copy-seq (require-sized-bytes bytes 20 "Address"))))

(defun address-bytes (address)
  (copy-seq (%address-bytes address)))

(defun address-from-hex (string)
  (make-address (hex-to-bytes string)))

(defun address-to-hex (address)
  (bytes-to-hex (%address-bytes address)))

(defun zero-address ()
  (make-address (make-byte-vector 20)))

(defstruct (hash32
            (:constructor %make-hash32 (bytes))
            (:conc-name %hash32-))
  (bytes (make-byte-vector 32) :type byte-vector :read-only t))

(defun make-hash32 (bytes)
  (%make-hash32 (copy-seq (require-sized-bytes bytes 32 "Hash32"))))

(defun hash32-bytes (hash)
  (copy-seq (%hash32-bytes hash)))

(defun hash32-from-hex (string)
  (make-hash32 (hex-to-bytes string)))

(defun hash32-to-hex (hash)
  (bytes-to-hex (%hash32-bytes hash)))

(defun hash32= (left right)
  (and left
       right
       (bytes= (%hash32-bytes left) (%hash32-bytes right))))

(defun zero-hash32 ()
  (make-hash32 (make-byte-vector 32)))
