(in-package #:ethereum-lisp.cli)

(defun devnet-cli-parse-integer (value option)
  (handler-case
      (parse-integer value :junk-allowed nil)
    (error ()
      (error "~A requires an integer value" option))))

(defun devnet-cli-parse-port (value option)
  (let ((port (devnet-cli-parse-integer value option)))
    (unless (<= 0 port 65535)
      (error "~A must be between 0 and 65535" option))
    port))

(defun devnet-cli-parse-non-negative-integer (value option)
  (let ((integer (devnet-cli-parse-integer value option)))
    (when (minusp integer)
      (error "~A must be non-negative" option))
    integer))

(defun devnet-cli-parse-positive-integer (value option)
  (let ((integer (devnet-cli-parse-integer value option)))
    (unless (plusp integer)
      (error "~A must be positive" option))
    integer))

(defun devnet-cli-duration-unit-seconds (unit option)
  (cond
    ((or (null unit) (string= unit "") (string= unit "s")) 1)
    ((string= unit "m") 60)
    ((string= unit "h") 3600)
    ((string= unit "d") 86400)
    (t
     (error "~A duration unit must be one of s, m, h, or d" option))))

(defun devnet-cli-parse-duration-seconds (value option)
  (unless (and (stringp value) (plusp (length value)))
    (error "~A requires a duration value" option))
  (let ((length (length value))
        (position 0)
        (total 0))
    (loop
      (when (>= position length)
        (return total))
      (let* ((number-start position)
             (unit-start
               (or (position-if-not #'digit-char-p value :start position)
                   length))
             (number-token (subseq value number-start unit-start)))
        (when (zerop (length number-token))
          (error "~A requires a non-negative duration" option))
        (when (and (= unit-start length) (/= number-start 0))
          (error "~A duration unit must be one of s, m, h, or d" option))
        (let* ((next-position
                 (if (< unit-start length)
                     (1+ unit-start)
                     unit-start))
               (unit-token
                 (if (< unit-start length)
                     (string-downcase (subseq value unit-start next-position))
                     ""))
               (seconds
                 (* (devnet-cli-parse-non-negative-integer
                     number-token
                     option)
                    (devnet-cli-duration-unit-seconds unit-token option))))
          (incf total seconds)
          (setf position next-position))))))

(defun devnet-cli-hex-quantity-token-p (value)
  (and (stringp value)
       (<= 2 (length value))
       (char= #\0 (char value 0))
       (char= #\x (char-downcase (char value 1)))))

(defun devnet-cli-parse-non-negative-quantity (value option)
  (let ((quantity
          (handler-case
              (if (devnet-cli-hex-quantity-token-p value)
                  (hex-to-quantity value)
                  (parse-integer value :junk-allowed nil))
            (error ()
              (error "~A requires a non-negative integer or hex quantity"
                     option)))))
    (when (minusp quantity)
      (error "~A must be non-negative" option))
    quantity))

(defun devnet-cli-parse-uint64-quantity (value option)
  (let ((quantity (devnet-cli-parse-non-negative-quantity value option)))
    (unless (< quantity (expt 2 64))
      (error "~A must be less than 2^64" option))
    quantity))

(defun devnet-cli-parse-hash32 (value option)
  (handler-case
      (hash32-from-hex value)
    (error ()
      (error "~A requires a 32-byte hex hash" option))))

(defun devnet-cli-parse-address (value option)
  (handler-case
      (address-from-hex value)
    (error ()
      (error "~A requires a 20-byte hex address" option))))

(defun devnet-cli-parse-address-list (value option)
  (let ((addresses
          (loop for raw in (uiop:split-string value :separator ",")
                for token = (string-trim
                             '(#\Space #\Tab #\Newline #\Return)
                             raw)
                unless (zerop (length token))
                  collect (devnet-cli-parse-address token option))))
    (unless addresses
      (error "~A requires at least one 20-byte hex address" option))
    addresses))

(defun devnet-cli-parse-enode (value option)
  "Validate VALUE as an enode:// URL and keep it as a string for later dialing."
  (handler-case
      (progn (parse-enode-url value) value)
    (error ()
      (error "~A requires an enode:// URL" option))))

(defun devnet-cli-parse-enode-list (value option)
  "Parse VALUE as one or more comma-separated enode:// URLs (go-ethereum syntax),
returning the list of validated enode strings."
  (let ((enodes (loop for raw in (uiop:split-string value :separator ",")
                      for token = (string-trim '(#\Space #\Tab #\Newline #\Return)
                                               raw)
                      unless (zerop (length token))
                        collect (devnet-cli-parse-enode token option))))
    (unless enodes
      (error "~A requires at least one enode:// URL" option))
    enodes))

(defun devnet-cli-parse-http-api-list (value option)
  (let ((modules
          (loop for raw in (uiop:split-string value :separator ",")
                for module = (string-downcase
                              (string-trim '(#\Space #\Tab #\Newline #\Return)
                                           raw))
                unless (zerop (length module))
                  collect module)))
    (unless modules
      (error "~A requires at least one API module" option))
    modules))

(defun devnet-cli-parse-cors-origin-list (value)
  (loop for raw in (uiop:split-string value :separator ",")
        for origin = (string-trim '(#\Space #\Tab #\Newline #\Return) raw)
        unless (zerop (length origin))
          collect origin))

(defun devnet-cli-parse-vhost-list (value)
  (loop for raw in (uiop:split-string value :separator ",")
        for host = (string-trim '(#\Space #\Tab #\Newline #\Return) raw)
        unless (zerop (length host))
          collect host))

(defun devnet-cli-parse-rpc-prefix (value option)
  (unless (and (stringp value)
               (plusp (length value))
               (char= #\/ (char value 0)))
    (error "~A requires a path beginning with /" option))
  value)

(defun devnet-cli-rpc-method-module (method)
  (let ((separator (and (stringp method) (position #\_ method))))
    (and separator
         (subseq method 0 separator))))

(defun devnet-cli-public-api-method-filter (modules)
  (if (null modules)
      #'engine-rpc-public-method-p
      (let ((modules (copy-list modules)))
        (lambda (method)
          (and (engine-rpc-public-method-p method)
               (or (string= method "rpc_modules")
                   (let ((module (devnet-cli-rpc-method-module method)))
                     (and module
                          (member module modules :test #'string=)))))))))
