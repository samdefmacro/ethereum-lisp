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

(defstruct (address (:constructor %make-address (bytes)))
  (bytes (make-byte-vector 20) :type byte-vector :read-only t))

(defun make-address (bytes)
  (%make-address (require-sized-bytes bytes 20 "Address")))

(defun address-from-hex (string)
  (make-address (hex-to-bytes string)))

(defun address-to-hex (address)
  (bytes-to-hex (address-bytes address)))

(defun zero-address ()
  (make-address (make-byte-vector 20)))

(defstruct (hash32 (:constructor %make-hash32 (bytes)))
  (bytes (make-byte-vector 32) :type byte-vector :read-only t))

(defun make-hash32 (bytes)
  (%make-hash32 (require-sized-bytes bytes 32 "Hash32")))

(defun hash32-from-hex (string)
  (make-hash32 (hex-to-bytes string)))

(defun hash32-to-hex (hash)
  (bytes-to-hex (hash32-bytes hash)))

(defun zero-hash32 ()
  (make-hash32 (make-byte-vector 32)))
