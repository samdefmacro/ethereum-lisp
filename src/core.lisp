(in-package #:ethereum-lisp.core)

(defparameter +empty-ommers-hash+ (keccak-256-hash (rlp-encode '())))
(defconstant +initial-base-fee+ 1000000000)
(defconstant +base-fee-elasticity-multiplier+ 2)
(defconstant +base-fee-change-denominator+ 8)
(defconstant +blob-gas-per-blob+ 131072)
(defconstant +blob-byte-size+ +blob-gas-per-blob+)
(defconstant +kzg-proof-size+ +kzg-commitment-size+)
(defconstant +target-blobs-per-block+ 3)
(defconstant +max-blobs-per-block+ 6)
(defconstant +osaka-target-blobs-per-block+ 6)
(defconstant +osaka-max-blobs-per-block+ 9)
(defconstant +bpo1-target-blobs-per-block+ 10)
(defconstant +bpo1-max-blobs-per-block+ 15)
(defconstant +bpo2-target-blobs-per-block+ 14)
(defconstant +bpo2-max-blobs-per-block+ 21)
(defconstant +bpo3-target-blobs-per-block+ 21)
(defconstant +bpo3-max-blobs-per-block+ 32)
(defconstant +bpo4-target-blobs-per-block+ 14)
(defconstant +bpo4-max-blobs-per-block+ 21)
(defconstant +min-blobs-per-transaction+ 1)
(defconstant +min-blob-gas-price+ 1)
(defconstant +blob-base-fee-update-fraction+ 3338477)
(defconstant +osaka-blob-base-fee-update-fraction+ 5007716)
(defconstant +bpo1-blob-base-fee-update-fraction+ 8346193)
(defconstant +bpo2-blob-base-fee-update-fraction+ 11684671)
(defconstant +bpo3-blob-base-fee-update-fraction+ 20609697)
(defconstant +bpo4-blob-base-fee-update-fraction+ 13739630)
(defconstant +blob-base-cost+ 8192)
(defconstant +maximum-extra-data-size+ 32)
(defconstant +gas-limit-bound-divisor+ 1024)
(defconstant +minimum-gas-limit+ 5000)
(defconstant +max-header-gas-limit+ #x7fffffffffffffff)
(defconstant +block-access-list-max-code-size+ 24576)
(defconstant +block-access-list-amsterdam-max-code-size+ 32768)
(defconstant +block-access-list-item-gas-cost+ 2000)
(defconstant +genesis-gas-limit+ 4712388)
(defconstant +genesis-difficulty+ 131072)

(defstruct (blob-schedule-entry
            (:constructor make-blob-schedule-entry
                (&key timestamp target-blobs max-blobs update-fraction)))
  timestamp
  target-blobs
  max-blobs
  update-fraction)

(defstruct (genesis-account
            (:constructor make-genesis-account
                (&key address (balance 0) (nonce 0)
                      (code (make-byte-vector 0)) storage)))
  address
  (balance 0 :type (integer 0 *))
  (nonce 0 :type (integer 0 *))
  (code (make-byte-vector 0) :type byte-vector)
  (storage nil :type list))

(defstruct (chain-config (:constructor make-chain-config
                             (&key (chain-id 1)
                                   homestead-block
                                   dao-fork-block
                                   dao-fork-support
                                   eip150-block
                                   eip155-block
                                   eip158-block
                                   byzantium-block
                                   constantinople-block
                                   petersburg-block
                                   istanbul-block
                                   muir-glacier-block
                                   berlin-block
                                   london-block
                                   arrow-glacier-block
                                   gray-glacier-block
                                   shanghai-time
                                   cancun-time
                                   prague-time
                                   osaka-time
                                   bpo1-time
                                   bpo2-time
                                   bpo3-time
                                   bpo4-time
                                   bpo5-time
                                   amsterdam-time
                                   ubt-time
                                   enable-ubt-at-genesis-p
                                   terminal-total-difficulty
                                   terminal-total-difficulty-passed
                                   merge-netsplit-block
                                   deposit-contract-address
                                   custom-blob-schedule)))
  (chain-id 1 :type (integer 0 *))
  homestead-block
  dao-fork-block
  dao-fork-support
  eip150-block
  eip155-block
  eip158-block
  byzantium-block
  constantinople-block
  petersburg-block
  istanbul-block
  muir-glacier-block
  berlin-block
  london-block
  arrow-glacier-block
  gray-glacier-block
  shanghai-time
  cancun-time
  prague-time
  osaka-time
  bpo1-time
  bpo2-time
  bpo3-time
  bpo4-time
  bpo5-time
  amsterdam-time
  ubt-time
  enable-ubt-at-genesis-p
  terminal-total-difficulty
  terminal-total-difficulty-passed
  merge-netsplit-block
  deposit-contract-address
  custom-blob-schedule)

(defstruct (chain-rules (:constructor make-chain-rules
                            (&key (chain-id 1)
                                  homestead-p
                                  eip150-p
                                  eip155-p
                                  eip158-p
                                  byzantium-p
                                  constantinople-p
                                  petersburg-p
                                  istanbul-p
                                  berlin-p
                                  london-p
                                  shanghai-p
                                  cancun-p
                                  prague-p
                                  osaka-p
                                  bpo1-p
                                  bpo2-p
                                  bpo3-p
                                  bpo4-p
                                  bpo5-p
                                  amsterdam-p
                                  ubt-p
                                  blob-schedule-target-gas
                                  blob-schedule-max-gas
                                  blob-schedule-update-fraction)))
  (chain-id 1 :type (integer 0 *))
  homestead-p
  eip150-p
  eip155-p
  eip158-p
  byzantium-p
  constantinople-p
  petersburg-p
  istanbul-p
  berlin-p
  london-p
  shanghai-p
  cancun-p
  prague-p
  osaka-p
  bpo1-p
  bpo2-p
  bpo3-p
  bpo4-p
  bpo5-p
  amsterdam-p
  ubt-p
  blob-schedule-target-gas
  blob-schedule-max-gas
  blob-schedule-update-fraction)

(defun fork-block-active-p (fork-block block-number)
  (and fork-block block-number (>= block-number fork-block)))

(defun fork-time-active-p (fork-time timestamp)
  (and fork-time timestamp (>= timestamp fork-time)))

(defun chain-config-homestead-p (config block-number)
  (fork-block-active-p (chain-config-homestead-block config) block-number))

(defun chain-config-dao-fork-p (config block-number)
  (fork-block-active-p (chain-config-dao-fork-block config) block-number))

(defun chain-config-eip150-p (config block-number)
  (fork-block-active-p (chain-config-eip150-block config) block-number))

(defun chain-config-eip155-p (config block-number)
  (fork-block-active-p (chain-config-eip155-block config) block-number))

(defun chain-config-eip158-p (config block-number)
  (fork-block-active-p (chain-config-eip158-block config) block-number))

(defun chain-config-byzantium-p (config block-number)
  (fork-block-active-p (chain-config-byzantium-block config) block-number))

(defun chain-config-constantinople-p (config block-number)
  (fork-block-active-p (chain-config-constantinople-block config)
                       block-number))

(defun chain-config-petersburg-p (config block-number)
  (or (fork-block-active-p (chain-config-petersburg-block config)
                           block-number)
      (and (null (chain-config-petersburg-block config))
           (chain-config-constantinople-p config block-number))))

(defun chain-config-istanbul-p (config block-number)
  (fork-block-active-p (chain-config-istanbul-block config) block-number))

(defun chain-config-berlin-p (config block-number)
  (fork-block-active-p (chain-config-berlin-block config) block-number))

(defun chain-config-london-p (config block-number)
  (fork-block-active-p (chain-config-london-block config) block-number))

(defun chain-config-shanghai-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-shanghai-time config) timestamp)))

(defun chain-config-cancun-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-cancun-time config) timestamp)))

(defun chain-config-prague-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-prague-time config) timestamp)))

(defun chain-config-osaka-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-osaka-time config) timestamp)))

(defun chain-config-bpo1-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-bpo1-time config) timestamp)))

(defun chain-config-bpo2-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-bpo2-time config) timestamp)))

(defun chain-config-bpo3-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-bpo3-time config) timestamp)))

(defun chain-config-bpo4-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-bpo4-time config) timestamp)))

(defun chain-config-bpo5-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-bpo5-time config) timestamp)))

(defun chain-config-amsterdam-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-amsterdam-time config) timestamp)))

(defun chain-config-ubt-p (config block-number timestamp)
  (and (chain-config-london-p config block-number)
       (fork-time-active-p (chain-config-ubt-time config) timestamp)))

(defun chain-config-ubt-genesis-p (config)
  (chain-config-enable-ubt-at-genesis-p config))

(defun chain-config-expanded-blob-schedule-p (config block-number timestamp)
  (or (chain-config-prague-p config block-number timestamp)
      (chain-config-osaka-p config block-number timestamp)
      (chain-config-bpo1-p config block-number timestamp)
      (chain-config-bpo2-p config block-number timestamp)
      (chain-config-bpo3-p config block-number timestamp)
      (chain-config-bpo4-p config block-number timestamp)))

(defun chain-rules-expanded-blob-schedule-p (rules)
  (or (chain-rules-prague-p rules)
      (chain-rules-osaka-p rules)
      (chain-rules-bpo1-p rules)
      (chain-rules-bpo2-p rules)
      (chain-rules-bpo3-p rules)
      (chain-rules-bpo4-p rules)))

(defun blob-schedule-values (target-blobs max-blobs update-fraction)
  (values (* target-blobs +blob-gas-per-blob+)
          (* max-blobs +blob-gas-per-blob+)
          update-fraction))

(defun validate-blob-schedule-entry (entry)
  (unless (typep entry 'blob-schedule-entry)
    (block-validation-fail "Blob schedule entry is malformed"))
  (unless (and (integerp (blob-schedule-entry-timestamp entry))
               (not (minusp (blob-schedule-entry-timestamp entry))))
    (block-validation-fail "Blob schedule timestamp must be a non-negative integer"))
  (unless (and (integerp (blob-schedule-entry-target-blobs entry))
               (not (minusp (blob-schedule-entry-target-blobs entry))))
    (block-validation-fail "Blob schedule target must be a non-negative integer"))
  (unless (and (integerp (blob-schedule-entry-max-blobs entry))
               (not (minusp (blob-schedule-entry-max-blobs entry))))
    (block-validation-fail "Blob schedule max must be a non-negative integer"))
  (unless (and (integerp (blob-schedule-entry-update-fraction entry))
               (plusp (blob-schedule-entry-update-fraction entry)))
    (block-validation-fail "Blob schedule update fraction must be positive"))
  t)

(defun active-custom-blob-schedule-entry (config timestamp)
  (let ((active-entry nil))
    (dolist (entry (chain-config-custom-blob-schedule config) active-entry)
      (validate-blob-schedule-entry entry)
      (when (and timestamp
                 (<= (blob-schedule-entry-timestamp entry) timestamp)
                 (or (null active-entry)
                     (> (blob-schedule-entry-timestamp entry)
                        (blob-schedule-entry-timestamp active-entry))))
        (setf active-entry entry)))))

(defun custom-blob-schedule-entry-values (entry)
  (blob-schedule-values (blob-schedule-entry-target-blobs entry)
                        (blob-schedule-entry-max-blobs entry)
                        (blob-schedule-entry-update-fraction entry)))

(defun genesis-key= (key name)
  (cond
    ((stringp key) (string= key name))
    ((symbolp key) (string-equal (symbol-name key) name))
    (t nil)))

(defun genesis-object-field (object name)
  (cond
    ((null object) nil)
    ((and (listp object) (every #'consp object))
     (cdr (find name object
                :key #'car
                :test (lambda (expected key)
                        (genesis-key= key expected)))))
    ((listp object)
     (loop for (key value) on object by #'cddr
           when (genesis-key= key name)
             return value))
    (t nil)))

(defun genesis-object-field-present-p (object name)
  (cond
    ((null object) nil)
    ((and (listp object) (every #'consp object))
     (not (null (find name object
                      :key #'car
                      :test (lambda (expected key)
                              (genesis-key= key expected))))))
    ((listp object)
     (loop for (key value) on object by #'cddr
           when (genesis-key= key name)
             return t))
    (t nil)))

(defun genesis-object-field-any (object names)
  (loop for name in names
        for value = (genesis-object-field object name)
        when value
          return value))

(defun genesis-hex-quantity-string-p (value)
  (and (stringp value)
       (>= (length value) 2)
       (char= (char value 0) #\0)
       (member (char value 1) '(#\x #\X))))

(defun parse-genesis-quantity (value label &key required-p)
  (cond
    ((null value)
     (when required-p
       (block-validation-fail "~A is missing" label))
     nil)
    ((and (integerp value) (not (minusp value))) value)
    ((stringp value)
     (handler-case
         (let ((quantity (if (genesis-hex-quantity-string-p value)
                             (hex-to-quantity value)
                             (parse-integer value :radix 10))))
           (if (and (integerp quantity) (not (minusp quantity)))
               quantity
               (block-validation-fail
                "~A must be a non-negative quantity" label)))
       (error ()
         (block-validation-fail "~A must be a non-negative quantity" label))))
    (t (block-validation-fail "~A must be a non-negative quantity" label))))

(defun parse-genesis-field (object name &key label required-p)
  (parse-genesis-quantity (if (listp name)
                              (genesis-object-field-any object name)
                              (genesis-object-field object name))
                          (or label name)
                          :required-p required-p))

(defun parse-genesis-boolean-field (object name label)
  (unless (genesis-object-field-present-p object name)
    (return-from parse-genesis-boolean-field nil))
  (let ((value (genesis-object-field object name)))
    (cond
      ((eq value t) t)
      ((null value) nil)
      (t (block-validation-fail "~A must be a boolean" label)))))

(defun genesis-blob-schedule-timestamp-field (fork-name)
  (cond
    ((string-equal fork-name "cancun") "cancunTime")
    ((string-equal fork-name "prague") "pragueTime")
    ((string-equal fork-name "osaka") "osakaTime")
    ((string-equal fork-name "bpo1") "bpo1Time")
    ((string-equal fork-name "bpo2") "bpo2Time")
    ((string-equal fork-name "bpo3") "bpo3Time")
    ((string-equal fork-name "bpo4") "bpo4Time")
    ((string-equal fork-name "bpo5") "bpo5Time")
    ((string-equal fork-name "amsterdam") "amsterdamTime")
    ((string-equal fork-name "ubt") "ubtTime")
    (t nil)))

(defun genesis-object-entries (object label)
  (unless (and (listp object) (every #'consp object))
    (block-validation-fail "~A must be an object" label))
  object)

(defun parse-genesis-blob-schedule-entry (timestamp entry-object fork-name)
  (make-blob-schedule-entry
   :timestamp timestamp
   :target-blobs (parse-genesis-field entry-object "target"
                                      :label (format nil "~A blob target" fork-name)
                                      :required-p t)
   :max-blobs (parse-genesis-field entry-object "max"
                                   :label (format nil "~A blob max" fork-name)
                                   :required-p t)
   :update-fraction
   (parse-genesis-field entry-object "baseFeeUpdateFraction"
                        :label (format nil "~A blob base fee update fraction"
                                       fork-name)
                        :required-p t)))

(defun parse-genesis-blob-schedule (object)
  (let ((schedule-object (genesis-object-field object "blobSchedule")))
    (when schedule-object
      (loop for (fork-name . entry-object)
              in (genesis-object-entries schedule-object "blobSchedule")
            for timestamp-field = (and (or (stringp fork-name) (symbolp fork-name))
                                       (genesis-blob-schedule-timestamp-field
                                        (if (stringp fork-name)
                                            fork-name
                                            (symbol-name fork-name))))
            for timestamp = (and timestamp-field
                                 (parse-genesis-field object timestamp-field))
            when timestamp
              collect (parse-genesis-blob-schedule-entry
                       timestamp entry-object fork-name)))))

(defun parse-genesis-uint256-field (object name label &key required-p)
  (let ((value (parse-genesis-field object name
                                    :label label
                                    :required-p required-p)))
    (when value
      (ensure-uint256 value label))))

(defun parse-genesis-address (value label)
  (unless (stringp value)
    (block-validation-fail "~A must be a hex address" label))
  (handler-case
      (address-from-hex value)
    (error ()
      (block-validation-fail "~A must be a 20-byte hex address" label))))

(defun parse-genesis-code (value label)
  (cond
    ((null value) (make-byte-vector 0))
    ((stringp value)
     (handler-case
         (hex-to-bytes value)
       (error ()
         (block-validation-fail "~A must be hex bytecode" label))))
    (t (block-validation-fail "~A must be hex bytecode" label))))

(defun parse-genesis-storage-hash32 (value label)
  (unless (stringp value)
    (block-validation-fail "~A must be hex storage data" label))
  (handler-case
      (let ((bytes (hex-to-bytes value)))
        (when (> (length bytes) 32)
          (block-validation-fail "~A must be at most 32 bytes" label))
        (let ((padded (make-byte-vector 32)))
          (replace padded bytes :start1 (- 32 (length bytes)))
          (make-hash32 padded)))
    (error ()
      (block-validation-fail "~A must be valid hex storage data" label))))

(defun parse-genesis-storage-slot (value label)
  (parse-genesis-storage-hash32 value label))

(defun parse-genesis-storage-value (value label)
  (cond
    ((stringp value)
     (bytes-to-integer
      (hash32-bytes (parse-genesis-storage-hash32 value label))))
    (t
     (let ((quantity (parse-genesis-quantity value label :required-p t)))
       (ensure-uint256 quantity label)))))

(defun parse-genesis-storage (object label)
  (when object
    (loop for (slot . value) in (genesis-object-entries object label)
          collect (cons (parse-genesis-storage-slot
                         slot (format nil "~A slot" label))
                        (parse-genesis-storage-value
                         value (format nil "~A value" label))))))

(defun genesis-account-from-entry (address-key account-object)
  (unless (and (listp account-object) (every #'consp account-object))
    (block-validation-fail "Genesis alloc account ~A must be an object"
                           address-key))
  (let ((label (format nil "Genesis alloc account ~A" address-key)))
    (make-genesis-account
     :address (parse-genesis-address address-key label)
     :balance (or (parse-genesis-uint256-field
                   account-object "balance"
                   (format nil "~A balance" label))
                  0)
     :nonce (or (parse-genesis-uint256-field
                 account-object "nonce"
                 (format nil "~A nonce" label))
                0)
     :code (parse-genesis-code
            (genesis-object-field account-object "code")
            (format nil "~A code" label))
     :storage (parse-genesis-storage
               (genesis-object-field account-object "storage")
               (format nil "~A storage" label)))))

(defun genesis-alloc-from-genesis-object (object)
  (let ((alloc-object (genesis-object-field object "alloc")))
    (when alloc-object
      (loop for (address-key . account-object)
              in (genesis-object-entries alloc-object "alloc")
            collect (genesis-account-from-entry address-key account-object)))))

(defun json-whitespace-p (char)
  (member char '(#\Space #\Tab #\Newline #\Return)))

(defun json-hex-value (char)
  (cond
    ((char<= #\0 char #\9) (- (char-code char) (char-code #\0)))
    ((char<= #\a char #\f) (+ 10 (- (char-code char) (char-code #\a))))
    ((char<= #\A char #\F) (+ 10 (- (char-code char) (char-code #\A))))
    (t nil)))

(defun parse-json (string)
  (check-type string string)
  (let ((position 0)
        (length (length string)))
    (labels
        ((fail (control &rest args)
           (apply #'block-validation-fail
                  (concatenate 'string "Invalid JSON at byte ~D: " control)
                  position args))
         (peek ()
           (when (< position length)
             (char string position)))
         (consume ()
           (prog1 (peek)
             (incf position)))
         (skip-whitespace ()
           (loop while (and (peek) (json-whitespace-p (peek)))
                 do (incf position)))
         (expect (char)
           (unless (and (peek) (char= (peek) char))
             (fail "expected ~S" char))
           (incf position))
         (parse-literal (literal value)
           (let ((end (+ position (length literal))))
             (unless (and (<= end length)
                          (string= string literal :start1 position :end1 end))
               (fail "expected ~A" literal))
             (setf position end)
             value))
         (parse-string ()
           (expect #\")
           (let ((chars '()))
             (loop
               (unless (peek)
                 (fail "unterminated string"))
               (let ((char (consume)))
                 (cond
                   ((char= char #\")
                    (return (coerce (nreverse chars) 'string)))
                   ((char= char #\\)
                    (unless (peek)
                      (fail "unterminated escape"))
                    (let ((escape (consume)))
                      (push
                       (case escape
                         (#\" #\")
                         (#\\ #\\)
                         (#\/ #\/)
                         (#\b #\Backspace)
                         (#\f #\Page)
                         (#\n #\Newline)
                         (#\r #\Return)
                         (#\t #\Tab)
                         (#\u
                          (let ((code 0))
                            (dotimes (i 4)
                              (let ((digit (and (peek)
                                                (json-hex-value (consume)))))
                                (unless digit
                                  (fail "invalid unicode escape"))
                                (setf code (+ (* code 16) digit))))
                            (or (code-char code)
                                (fail "invalid unicode code point"))))
                         (otherwise
                          (fail "invalid string escape ~S" escape)))
                       chars)))
                   ((< (char-code char) #x20)
                    (fail "control character in string"))
                   (t (push char chars)))))))
         (parse-number ()
           (let ((start position))
             (when (and (peek) (char= (peek) #\-))
               (incf position))
             (unless (and (peek) (digit-char-p (peek)))
               (fail "expected digit"))
             (if (char= (peek) #\0)
                 (incf position)
                 (loop while (and (peek) (digit-char-p (peek)))
                       do (incf position)))
             (when (and (peek) (member (peek) '(#\. #\e #\E)))
               (fail "only integer JSON numbers are supported"))
             (parse-integer string :start start :end position)))
         (parse-array ()
           (expect #\[)
           (skip-whitespace)
           (let ((items '()))
             (when (and (peek) (char= (peek) #\]))
               (incf position)
               (return-from parse-array '()))
             (loop
               (push (parse-value) items)
               (skip-whitespace)
               (cond
                 ((and (peek) (char= (peek) #\,))
                  (incf position)
                  (skip-whitespace))
                 ((and (peek) (char= (peek) #\]))
                  (incf position)
                  (return (nreverse items)))
                 (t (fail "expected comma or closing array"))))))
         (parse-object ()
           (expect #\{)
           (skip-whitespace)
           (let ((entries '()))
             (when (and (peek) (char= (peek) #\}))
               (incf position)
               (return-from parse-object '()))
             (loop
               (unless (and (peek) (char= (peek) #\"))
                 (fail "expected object key"))
               (let ((key (parse-string)))
                 (skip-whitespace)
                 (expect #\:)
                 (skip-whitespace)
                 (push (cons key (parse-value)) entries))
               (skip-whitespace)
               (cond
                 ((and (peek) (char= (peek) #\,))
                  (incf position)
                  (skip-whitespace))
                 ((and (peek) (char= (peek) #\}))
                  (incf position)
                  (return (nreverse entries)))
                 (t (fail "expected comma or closing object"))))))
         (parse-value ()
           (skip-whitespace)
           (case (peek)
             (#\{ (parse-object))
             (#\[ (parse-array))
             (#\" (parse-string))
             (#\t (parse-literal "true" t))
             (#\f (parse-literal "false" nil))
             (#\n (parse-literal "null" nil))
             ((#\- #\0 #\1 #\2 #\3 #\4 #\5 #\6 #\7 #\8 #\9)
              (parse-number))
             (otherwise (fail "unexpected character")))))
      (let ((value (parse-value)))
        (skip-whitespace)
        (when (peek)
          (fail "trailing data"))
        value))))

(defun chain-config-from-genesis-config (object)
  (make-chain-config
   :chain-id (or (parse-genesis-field object "chainId") 1)
   :homestead-block (parse-genesis-field object "homesteadBlock")
   :dao-fork-block (parse-genesis-field object "daoForkBlock")
   :dao-fork-support
   (parse-genesis-boolean-field object "daoForkSupport" "daoForkSupport")
   :eip150-block (parse-genesis-field
                  object '("eip150Block" "tangerineWhistleBlock")
                  :label "eip150Block")
   :eip155-block (parse-genesis-field
                  object '("eip155Block" "spuriousDragonBlock")
                  :label "eip155Block")
   :eip158-block (parse-genesis-field
                  object '("eip158Block" "spuriousDragonBlock")
                  :label "eip158Block")
   :byzantium-block (parse-genesis-field object "byzantiumBlock")
   :constantinople-block (parse-genesis-field object "constantinopleBlock")
   :petersburg-block (parse-genesis-field object "petersburgBlock")
   :istanbul-block (parse-genesis-field object "istanbulBlock")
   :muir-glacier-block (parse-genesis-field object "muirGlacierBlock")
   :berlin-block (parse-genesis-field object "berlinBlock")
   :london-block (parse-genesis-field object "londonBlock")
   :arrow-glacier-block (parse-genesis-field object "arrowGlacierBlock")
   :gray-glacier-block (parse-genesis-field object "grayGlacierBlock")
   :shanghai-time (parse-genesis-field object "shanghaiTime")
   :cancun-time (parse-genesis-field object "cancunTime")
   :prague-time (parse-genesis-field object "pragueTime")
   :osaka-time (parse-genesis-field object "osakaTime")
   :bpo1-time (parse-genesis-field object "bpo1Time")
   :bpo2-time (parse-genesis-field object "bpo2Time")
   :bpo3-time (parse-genesis-field object "bpo3Time")
   :bpo4-time (parse-genesis-field object "bpo4Time")
   :bpo5-time (parse-genesis-field object "bpo5Time")
   :amsterdam-time (parse-genesis-field object "amsterdamTime")
   :ubt-time (parse-genesis-field object "ubtTime")
   :enable-ubt-at-genesis-p
   (parse-genesis-boolean-field object "enableUBTAtGenesis"
                                "enableUBTAtGenesis")
   :terminal-total-difficulty
   (parse-genesis-field object "terminalTotalDifficulty")
   :terminal-total-difficulty-passed
   (parse-genesis-boolean-field object "terminalTotalDifficultyPassed"
                                "terminalTotalDifficultyPassed")
   :merge-netsplit-block (parse-genesis-field object "mergeNetsplitBlock")
   :deposit-contract-address
   (parse-genesis-address-field object "depositContractAddress"
                                "Genesis deposit contract address")
   :custom-blob-schedule (parse-genesis-blob-schedule object)))

(defun chain-config-from-genesis-json-string (string)
  (let* ((genesis-object (parse-json string))
         (config-object (or (genesis-object-field genesis-object "config")
                            genesis-object)))
    (chain-config-from-genesis-config config-object)))

(defun read-text-file (path)
  (with-open-file (stream path :direction :input)
    (let ((string (make-string (file-length stream))))
      (read-sequence string stream)
      string)))

(defun chain-config-from-genesis-json-file (path)
  (chain-config-from-genesis-json-string (read-text-file path)))

(defun genesis-alloc-from-genesis-json-string (string)
  (genesis-alloc-from-genesis-object (parse-json string)))

(defun genesis-alloc-from-genesis-json-file (path)
  (genesis-alloc-from-genesis-json-string (read-text-file path)))

(defun genesis-expected-state-root-from-genesis-object (object)
  (let ((state-root (genesis-object-field object "stateRoot")))
    (when state-root
      (unless (stringp state-root)
        (block-validation-fail "Genesis stateRoot must be a hash32"))
      (handler-case
          (hash32-from-hex state-root)
        (error ()
          (block-validation-fail "Genesis stateRoot must be a hash32"))))))

(defun genesis-expected-state-root-from-genesis-json-string (string)
  (genesis-expected-state-root-from-genesis-object (parse-json string)))

(defun genesis-expected-state-root-from-genesis-json-file (path)
  (genesis-expected-state-root-from-genesis-json-string (read-text-file path)))

(defun parse-genesis-hash32-field (object name label &key default)
  (let ((value (if (listp name)
                   (genesis-object-field-any object name)
                   (genesis-object-field object name))))
    (cond
      ((null value) default)
      ((stringp value)
       (handler-case
           (hash32-from-hex value)
         (error ()
           (block-validation-fail "~A must be a hash32" label))))
      (t (block-validation-fail "~A must be a hash32" label)))))

(defun parse-genesis-address-field (object name label &key default)
  (let ((value (if (listp name)
                   (genesis-object-field-any object name)
                   (genesis-object-field object name))))
    (cond
      ((null value) default)
      (t (parse-genesis-address value label)))))

(defun parse-genesis-bytes-field (object name label &key default)
  (let ((value (if (listp name)
                   (genesis-object-field-any object name)
                   (genesis-object-field object name))))
    (cond
      ((null value) default)
      ((stringp value)
       (handler-case
           (hex-to-bytes value)
         (error ()
           (block-validation-fail "~A must be hex bytes" label))))
      (t (block-validation-fail "~A must be hex bytes" label)))))

(defun genesis-uint64-field (object name label &key default)
  (let ((value (parse-genesis-field object name :label label)))
    (cond
      ((null value) default)
      ((< value (expt 2 64)) value)
      (t (block-validation-fail "~A must be uint64" label)))))

(defun uint64-to-8-byte-vector (value label)
  (unless (and (integerp value) (<= 0 value) (< value (expt 2 64)))
    (block-validation-fail "~A must be uint64" label))
  (let ((out (make-byte-vector 8)))
    (dotimes (index 8 out)
      (setf (aref out (- 7 index)) (logand value #xff)
            value (ash value -8)))))

(defun genesis-config-from-genesis-object (object &key config)
  (or config
      (let ((config-object (genesis-object-field object "config")))
        (and config-object (chain-config-from-genesis-config config-object)))))

(defun genesis-header-from-genesis-object (object &key state-root config)
  (let* ((config (genesis-config-from-genesis-object object :config config))
         (number (genesis-uint64-field object "number" "Genesis number"
                                       :default 0))
         (timestamp (genesis-uint64-field object "timestamp" "Genesis timestamp"
                                          :default 0))
         (raw-gas-limit (genesis-uint64-field object "gasLimit"
                                              "Genesis gas limit"
                                              :default +genesis-gas-limit+))
         (gas-limit (if (zerop raw-gas-limit)
                        +genesis-gas-limit+
                        raw-gas-limit))
         (gas-used (genesis-uint64-field object "gasUsed" "Genesis gas used"
                                         :default 0))
         (difficulty (or (parse-genesis-field object "difficulty"
                                              :label "Genesis difficulty")
                         (and config
                              (eql 0
                                   (chain-config-terminal-total-difficulty
                                    config))
                              0)
                         +genesis-difficulty+))
         (base-fee (parse-genesis-field object "baseFeePerGas"
                                        :label "Genesis base fee"))
         (parent-beacon-root (parse-genesis-hash32-field
                              object '("parentBeaconBlockRoot"
                                       "parentBeaconRoot")
                              "Genesis parent beacon block root"))
         (block-access-list-hash (parse-genesis-hash32-field
                                  object '("balHash"
                                           "blockAccessListHash")
                                  "Genesis block access list hash"))
         (slot-number (genesis-uint64-field object "slotNumber"
                                            "Genesis slot number"))
         (header
           (make-block-header
            :parent-hash (parse-genesis-hash32-field
                          object "parentHash" "Genesis parent hash"
                          :default (zero-hash32))
            :ommers-hash +empty-ommers-hash+
            :beneficiary (parse-genesis-address-field
                          object "coinbase" "Genesis coinbase"
                          :default (zero-address))
            :state-root (or state-root
                            (genesis-expected-state-root-from-genesis-object object)
                            +empty-trie-hash+)
            :transactions-root +empty-trie-hash+
            :receipts-root +empty-trie-hash+
            :logs-bloom (make-byte-vector 256)
            :difficulty difficulty
            :number number
            :gas-limit gas-limit
            :gas-used gas-used
            :timestamp timestamp
            :extra-data (parse-genesis-bytes-field
                         object "extraData" "Genesis extra data"
                         :default (make-byte-vector 0))
            :mix-hash (parse-genesis-hash32-field
                       object '("mixHash" "mixhash") "Genesis mix hash"
                       :default (zero-hash32))
            :nonce (uint64-to-8-byte-vector
                    (genesis-uint64-field object "nonce" "Genesis nonce"
                                          :default 0)
                    "Genesis nonce")
            :base-fee-per-gas base-fee
            :blob-gas-used (genesis-uint64-field
                            object "blobGasUsed" "Genesis blob gas used")
            :excess-blob-gas (genesis-uint64-field
                              object "excessBlobGas"
                              "Genesis excess blob gas")
            :block-access-list-hash block-access-list-hash
            :slot-number slot-number)))
    (when (and config
               (chain-config-london-p config number)
               (null (block-header-base-fee-per-gas header)))
      (setf (block-header-base-fee-per-gas header) +initial-base-fee+))
    (when (and config (chain-config-shanghai-p config number timestamp))
      (setf (block-header-withdrawals-root header) (withdrawal-list-root '())))
    (when (and config (chain-config-cancun-p config number timestamp))
      (setf (block-header-parent-beacon-root header)
            (or parent-beacon-root (zero-hash32)))
      (unless (block-header-excess-blob-gas header)
        (setf (block-header-excess-blob-gas header) 0))
      (unless (block-header-blob-gas-used header)
        (setf (block-header-blob-gas-used header) 0)))
    (when (and config (chain-config-prague-p config number timestamp))
      (setf (block-header-requests-hash header) (execution-requests-hash '())))
    (when (and config (chain-config-amsterdam-p config number timestamp))
      (unless (block-header-block-access-list-hash header)
        (setf (block-header-block-access-list-hash header) +empty-ommers-hash+))
      (unless (block-header-slot-number header)
        (setf (block-header-slot-number header) 0)))
    header))

(defun genesis-header-from-genesis-json-string (string &key state-root config)
  (genesis-header-from-genesis-object (parse-json string)
                                      :state-root state-root
                                      :config config))

(defun genesis-header-from-genesis-json-file (path &key state-root config)
  (genesis-header-from-genesis-json-string (read-text-file path)
                                           :state-root state-root
                                           :config config))

(defun genesis-block-from-genesis-header (header)
  (let ((args (list :header header)))
    (when (block-header-withdrawals-root header)
      (setf args (append args (list :withdrawals '()))))
    (when (block-header-requests-hash header)
      (setf args (append args (list :requests '()))))
    (when (block-header-block-access-list-hash header)
      (setf args (append args (list :block-access-list '()))))
    (apply #'make-block args)))

(defun genesis-block-from-genesis-object (object &key state-root config)
  (genesis-block-from-genesis-header
   (genesis-header-from-genesis-object object
                                       :state-root state-root
                                       :config config)))

(defun genesis-block-from-genesis-json-string (string &key state-root config)
  (genesis-block-from-genesis-object (parse-json string)
                                     :state-root state-root
                                     :config config))

(defun genesis-block-from-genesis-json-file (path &key state-root config)
  (genesis-block-from-genesis-json-string (read-text-file path)
                                          :state-root state-root
                                          :config config))

(defun chain-config-blob-schedule (config block-number timestamp)
  (let ((custom-entry (active-custom-blob-schedule-entry config timestamp)))
    (if custom-entry
        (custom-blob-schedule-entry-values custom-entry)
        (cond
          ((chain-config-bpo4-p config block-number timestamp)
           (blob-schedule-values +bpo4-target-blobs-per-block+
                                 +bpo4-max-blobs-per-block+
                                 +bpo4-blob-base-fee-update-fraction+))
          ((chain-config-bpo3-p config block-number timestamp)
           (blob-schedule-values +bpo3-target-blobs-per-block+
                                 +bpo3-max-blobs-per-block+
                                 +bpo3-blob-base-fee-update-fraction+))
          ((chain-config-bpo2-p config block-number timestamp)
           (blob-schedule-values +bpo2-target-blobs-per-block+
                                 +bpo2-max-blobs-per-block+
                                 +bpo2-blob-base-fee-update-fraction+))
          ((chain-config-bpo1-p config block-number timestamp)
           (blob-schedule-values +bpo1-target-blobs-per-block+
                                 +bpo1-max-blobs-per-block+
                                 +bpo1-blob-base-fee-update-fraction+))
          ((chain-config-expanded-blob-schedule-p config block-number timestamp)
           (blob-schedule-values +osaka-target-blobs-per-block+
                                 +osaka-max-blobs-per-block+
                                 +osaka-blob-base-fee-update-fraction+))
          (t
           (blob-schedule-values +target-blobs-per-block+
                                 +max-blobs-per-block+
                                 +blob-base-fee-update-fraction+))))))

(defun chain-rules-blob-schedule (rules)
  (if (and (chain-rules-blob-schedule-target-gas rules)
           (chain-rules-blob-schedule-max-gas rules)
           (chain-rules-blob-schedule-update-fraction rules))
      (values (chain-rules-blob-schedule-target-gas rules)
              (chain-rules-blob-schedule-max-gas rules)
              (chain-rules-blob-schedule-update-fraction rules))
      (cond
        ((chain-rules-bpo4-p rules)
         (blob-schedule-values +bpo4-target-blobs-per-block+
                               +bpo4-max-blobs-per-block+
                               +bpo4-blob-base-fee-update-fraction+))
        ((chain-rules-bpo3-p rules)
         (blob-schedule-values +bpo3-target-blobs-per-block+
                               +bpo3-max-blobs-per-block+
                               +bpo3-blob-base-fee-update-fraction+))
        ((chain-rules-bpo2-p rules)
         (blob-schedule-values +bpo2-target-blobs-per-block+
                               +bpo2-max-blobs-per-block+
                               +bpo2-blob-base-fee-update-fraction+))
        ((chain-rules-bpo1-p rules)
         (blob-schedule-values +bpo1-target-blobs-per-block+
                               +bpo1-max-blobs-per-block+
                               +bpo1-blob-base-fee-update-fraction+))
        ((chain-rules-expanded-blob-schedule-p rules)
         (blob-schedule-values +osaka-target-blobs-per-block+
                               +osaka-max-blobs-per-block+
                               +osaka-blob-base-fee-update-fraction+))
        (t
         (blob-schedule-values +target-blobs-per-block+
                               +max-blobs-per-block+
                               +blob-base-fee-update-fraction+)))))

(defun chain-config-rules (config block-number timestamp)
  (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
      (chain-config-blob-schedule config block-number timestamp)
    (make-chain-rules
     :chain-id (chain-config-chain-id config)
     :homestead-p (chain-config-homestead-p config block-number)
     :eip150-p (chain-config-eip150-p config block-number)
     :eip155-p (chain-config-eip155-p config block-number)
     :eip158-p (chain-config-eip158-p config block-number)
     :byzantium-p (chain-config-byzantium-p config block-number)
     :constantinople-p (chain-config-constantinople-p config block-number)
     :petersburg-p (chain-config-petersburg-p config block-number)
     :istanbul-p (chain-config-istanbul-p config block-number)
     :berlin-p (chain-config-berlin-p config block-number)
     :london-p (chain-config-london-p config block-number)
     :shanghai-p (chain-config-shanghai-p config block-number timestamp)
     :cancun-p (chain-config-cancun-p config block-number timestamp)
     :prague-p (chain-config-prague-p config block-number timestamp)
     :osaka-p (chain-config-osaka-p config block-number timestamp)
     :bpo1-p (chain-config-bpo1-p config block-number timestamp)
     :bpo2-p (chain-config-bpo2-p config block-number timestamp)
     :bpo3-p (chain-config-bpo3-p config block-number timestamp)
     :bpo4-p (chain-config-bpo4-p config block-number timestamp)
     :bpo5-p (chain-config-bpo5-p config block-number timestamp)
     :amsterdam-p (chain-config-amsterdam-p config block-number timestamp)
     :ubt-p (chain-config-ubt-p config block-number timestamp)
     :blob-schedule-target-gas target-blob-gas
     :blob-schedule-max-gas max-blob-gas
     :blob-schedule-update-fraction update-fraction)))

(defun chain-rules-transaction-type-supported-p (rules transaction)
  (case (transaction-type transaction)
    (0 t)
    (1 (chain-rules-berlin-p rules))
    (2 (chain-rules-london-p rules))
    (3 (chain-rules-cancun-p rules))
    (4 (chain-rules-prague-p rules))
    (otherwise nil)))

(defun ensure-uint256 (value label)
  (unless (uint256-p value)
    (error "~A must be a uint256, got ~S" label value))
  value)

(defun optional-bytes (value size label)
  (cond
    ((null value) (make-byte-vector 0))
    ((and size (= (length (ensure-byte-vector value)) size))
     (ensure-byte-vector value))
    (size (error "~A must be exactly ~D bytes" label size))
    (t (ensure-byte-vector value))))

(defstruct (state-account (:constructor make-state-account
                             (&key (nonce 0)
                                   (balance 0)
                                   (storage-root +empty-trie-hash+)
                                   (code-hash +empty-code-hash+))))
  (nonce 0 :type (integer 0 *))
  (balance 0 :type (integer 0 *))
  (storage-root +empty-trie-hash+ :type hash32)
  (code-hash +empty-code-hash+ :type hash32))

(defun state-account-rlp (account)
  (rlp-encode
   (make-rlp-list
    (ensure-uint256 (state-account-nonce account) "Account nonce")
    (ensure-uint256 (state-account-balance account) "Account balance")
    (hash32-bytes (state-account-storage-root account))
    (hash32-bytes (state-account-code-hash account)))))

(defun state-account-hash (account)
  (keccak-256-hash (state-account-rlp account)))

(defstruct (legacy-transaction (:constructor make-legacy-transaction
                                  (&key (nonce 0)
                                        (gas-price 0)
                                        (gas-limit 0)
                                        to
                                        (value 0)
                                        (data #())
                                        (v 0)
                                        (r 0)
                                        (s 0))))
  (nonce 0 :type (integer 0 *))
  (gas-price 0 :type (integer 0 *))
  (gas-limit 0 :type (integer 0 *))
  to
  (value 0 :type (integer 0 *))
  (data (make-byte-vector 0))
  (v 0 :type (integer 0 *))
  (r 0 :type (integer 0 *))
  (s 0 :type (integer 0 *)))

(defun transaction-to-bytes (to)
  (etypecase to
    (null (make-byte-vector 0))
    (address (address-bytes to))
    (byte-vector (optional-bytes to 20 "Transaction recipient"))
    (vector (optional-bytes to 20 "Transaction recipient"))))

(defun required-transaction-to-bytes (to label)
  (etypecase to
    (address (address-bytes to))
    (byte-vector (optional-bytes to 20 label))
    (vector (optional-bytes to 20 label))))

(defun legacy-transaction-rlp (transaction)
  (rlp-encode
   (make-rlp-list
    (ensure-uint256 (legacy-transaction-nonce transaction) "Transaction nonce")
    (ensure-uint256 (legacy-transaction-gas-price transaction) "Transaction gas price")
    (ensure-uint256 (legacy-transaction-gas-limit transaction) "Transaction gas limit")
    (transaction-to-bytes (legacy-transaction-to transaction))
    (ensure-uint256 (legacy-transaction-value transaction) "Transaction value")
    (ensure-byte-vector (legacy-transaction-data transaction))
    (ensure-uint256 (legacy-transaction-v transaction) "Transaction v")
    (ensure-uint256 (legacy-transaction-r transaction) "Transaction r")
    (ensure-uint256 (legacy-transaction-s transaction) "Transaction s"))))

(defun legacy-transaction-recipient-from-rlp (bytes)
  (let ((bytes (ensure-byte-vector bytes)))
    (cond
      ((zerop (length bytes)) nil)
      ((= (length bytes) 20) (make-address bytes))
      (t (block-validation-fail
          "Legacy transaction recipient must be empty or 20 bytes")))))

(defun rlp-uint-field (value label)
  (unless (byte-vector-p value)
    (block-validation-fail "~A must be RLP bytes" label))
  (bytes-to-integer value))

(defun rlp-bytes-field (value label)
  (unless (byte-vector-p value)
    (block-validation-fail "~A must be RLP bytes" label))
  (copy-seq value))

(defun legacy-transaction-from-rlp (bytes)
  (handler-case
      (let ((value (rlp-decode-one bytes)))
        (unless (rlp-list-p value)
          (block-validation-fail "Legacy transaction must be an RLP list"))
        (let ((fields (rlp-list-items value)))
          (unless (= (length fields) 9)
            (block-validation-fail
             "Legacy transaction must contain 9 fields"))
          (make-legacy-transaction
           :nonce (rlp-uint-field (first fields) "Transaction nonce")
           :gas-price (rlp-uint-field (second fields)
                                      "Transaction gas price")
           :gas-limit (rlp-uint-field (third fields)
                                      "Transaction gas limit")
           :to (legacy-transaction-recipient-from-rlp (fourth fields))
           :value (rlp-uint-field (fifth fields) "Transaction value")
           :data (rlp-bytes-field (sixth fields) "Transaction data")
           :v (rlp-uint-field (seventh fields) "Transaction v")
           :r (rlp-uint-field (eighth fields) "Transaction r")
           :s (rlp-uint-field (ninth fields) "Transaction s"))))
    (block-validation-error (condition)
      (error condition))
    (rlp-error (condition)
      (block-validation-fail "Invalid legacy transaction RLP: ~A"
                             condition))))

(defun legacy-transaction-hash (transaction)
  (keccak-256-hash (legacy-transaction-rlp transaction)))

(defun legacy-transaction-signing-payload
    (transaction &key (chain-id nil chain-id-provided-p))
  (let ((payload
          (list
           (ensure-uint256 (legacy-transaction-nonce transaction)
                           "Transaction nonce")
           (ensure-uint256 (legacy-transaction-gas-price transaction)
                           "Transaction gas price")
           (ensure-uint256 (legacy-transaction-gas-limit transaction)
                           "Transaction gas limit")
           (transaction-to-bytes (legacy-transaction-to transaction))
           (ensure-uint256 (legacy-transaction-value transaction)
                           "Transaction value")
           (ensure-byte-vector (legacy-transaction-data transaction)))))
    (when chain-id-provided-p
      (setf payload (append payload (list (ensure-uint256 chain-id
                                                          "Transaction chain id")
                                          0
                                          0))))
    (apply #'make-rlp-list payload)))

(defun legacy-transaction-signing-hash
    (transaction &key (chain-id nil chain-id-provided-p))
  (keccak-256-hash
   (rlp-encode
    (if chain-id-provided-p
        (legacy-transaction-signing-payload transaction :chain-id chain-id)
        (legacy-transaction-signing-payload transaction)))))

(defun legacy-transaction-protected-p (transaction)
  (>= (legacy-transaction-v transaction) 35))

(defun legacy-transaction-chain-id (transaction)
  (let ((v (legacy-transaction-v transaction)))
    (cond
      ((or (= v 27) (= v 28)) 0)
      ((>= v 35) (floor (- v 35) 2))
      (t nil))))

(defun legacy-transaction-y-parity (transaction)
  (let ((v (legacy-transaction-v transaction)))
    (cond
      ((or (= v 27) (= v 28)) (- v 27))
      ((>= v 35) (mod (- v 35) 2))
      (t nil))))

(defun legacy-transaction-sender
    (transaction &key expected-chain-id (homestead-p t))
  "Recover the sender address from a legacy transaction signature.
Returns NIL when V/R/S are invalid or the expected chain id does not match."
  (let* ((chain-id (legacy-transaction-chain-id transaction))
         (protected-p (legacy-transaction-protected-p transaction))
         (y-parity (legacy-transaction-y-parity transaction))
         (r (legacy-transaction-r transaction))
         (s (legacy-transaction-s transaction)))
    (when (and chain-id
               y-parity
               (or (not expected-chain-id)
                   (not protected-p)
                   (= expected-chain-id chain-id))
               (secp256k1-valid-signature-values-p
                y-parity r s :low-s-p homestead-p))
      (let ((hash (if protected-p
                      (legacy-transaction-signing-hash transaction
                                                       :chain-id chain-id)
                      (legacy-transaction-signing-hash transaction))))
        (secp256k1-recover-address (hash32-bytes hash) y-parity r s)))))

(defstruct (access-list-entry (:constructor make-access-list-entry
                                 (&key address (storage-keys '()))))
  address
  (storage-keys '() :type list))

(defun access-list-entry-rlp-object (entry)
  (make-rlp-list
   (address-bytes (access-list-entry-address entry))
   (mapcar #'hash32-bytes (access-list-entry-storage-keys entry))))

(defun access-list-rlp-object (access-list)
  (mapcar #'access-list-entry-rlp-object access-list))

(defun access-list-address-from-rlp (value label)
  (let ((bytes (rlp-bytes-field value label)))
    (unless (= (length bytes) 20)
      (block-validation-fail "~A must be exactly 20 bytes" label))
    (make-address bytes)))

(defun access-list-storage-key-from-rlp (value label)
  (let ((bytes (rlp-bytes-field value label)))
    (unless (= (length bytes) 32)
      (block-validation-fail "~A must be exactly 32 bytes" label))
    (make-hash32 bytes)))

(defun access-list-entry-from-rlp-object (value)
  (unless (rlp-list-p value)
    (block-validation-fail "Access list entry must be an RLP list"))
  (let ((fields (rlp-list-items value)))
    (unless (= (length fields) 2)
      (block-validation-fail "Access list entry must contain 2 fields"))
    (unless (rlp-list-p (second fields))
      (block-validation-fail "Access list storage keys must be an RLP list"))
    (make-access-list-entry
     :address (access-list-address-from-rlp
               (first fields)
               "Access list entry address")
     :storage-keys
     (mapcar (lambda (storage-key)
               (access-list-storage-key-from-rlp
                storage-key
                "Access list storage key"))
             (rlp-list-items (second fields))))))

(defun access-list-from-rlp-object (value)
  (unless (rlp-list-p value)
    (block-validation-fail "Access list must be an RLP list"))
  (mapcar #'access-list-entry-from-rlp-object
          (rlp-list-items value)))

(defstruct (access-list-transaction (:constructor make-access-list-transaction
                                      (&key (chain-id 0)
                                            (nonce 0)
                                            (gas-price 0)
                                            (gas-limit 0)
                                            to
                                            (value 0)
                                            (data #())
                                            (access-list '())
                                            (y-parity 0)
                                            (r 0)
                                            (s 0))))
  (chain-id 0 :type (integer 0 *))
  (nonce 0 :type (integer 0 *))
  (gas-price 0 :type (integer 0 *))
  (gas-limit 0 :type (integer 0 *))
  to
  (value 0 :type (integer 0 *))
  data
  (access-list '() :type list)
  (y-parity 0 :type (integer 0 *))
  (r 0 :type (integer 0 *))
  (s 0 :type (integer 0 *)))

(defun access-list-transaction-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (access-list-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (access-list-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (access-list-transaction-gas-price transaction) "Transaction gas price")
   (ensure-uint256 (access-list-transaction-gas-limit transaction) "Transaction gas limit")
   (transaction-to-bytes (access-list-transaction-to transaction))
   (ensure-uint256 (access-list-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (access-list-transaction-data transaction))
   (access-list-rlp-object (access-list-transaction-access-list transaction))
   (ensure-uint256 (access-list-transaction-y-parity transaction) "Transaction y parity")
   (ensure-uint256 (access-list-transaction-r transaction) "Transaction r")
   (ensure-uint256 (access-list-transaction-s transaction) "Transaction s")))

(defun access-list-transaction-encoding (transaction)
  (concat-bytes #(1) (rlp-encode (access-list-transaction-payload transaction))))

(defun access-list-transaction-from-rlp (bytes)
  (handler-case
      (let ((value (rlp-decode-one bytes)))
        (unless (rlp-list-p value)
          (block-validation-fail
           "Access-list transaction payload must be an RLP list"))
        (let ((fields (rlp-list-items value)))
          (unless (= (length fields) 11)
            (block-validation-fail
             "Access-list transaction payload must contain 11 fields"))
          (make-access-list-transaction
           :chain-id (rlp-uint-field (first fields)
                                     "Transaction chain id")
           :nonce (rlp-uint-field (second fields) "Transaction nonce")
           :gas-price (rlp-uint-field (third fields)
                                      "Transaction gas price")
           :gas-limit (rlp-uint-field (fourth fields)
                                      "Transaction gas limit")
           :to (legacy-transaction-recipient-from-rlp (fifth fields))
           :value (rlp-uint-field (sixth fields) "Transaction value")
           :data (rlp-bytes-field (seventh fields) "Transaction data")
           :access-list (access-list-from-rlp-object (eighth fields))
           :y-parity (rlp-uint-field (ninth fields) "Transaction y parity")
           :r (rlp-uint-field (tenth fields) "Transaction r")
           :s (rlp-uint-field (nth 10 fields) "Transaction s"))))
    (block-validation-error (condition)
      (error condition))
    (rlp-error (condition)
      (block-validation-fail "Invalid access-list transaction RLP: ~A"
                             condition))))

(defun access-list-transaction-signing-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (access-list-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (access-list-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (access-list-transaction-gas-price transaction) "Transaction gas price")
   (ensure-uint256 (access-list-transaction-gas-limit transaction) "Transaction gas limit")
   (transaction-to-bytes (access-list-transaction-to transaction))
   (ensure-uint256 (access-list-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (access-list-transaction-data transaction))
   (access-list-rlp-object (access-list-transaction-access-list transaction))))

(defun access-list-transaction-signing-hash (transaction)
  (keccak-256-hash
   (concat-bytes #(1)
                 (rlp-encode
                  (access-list-transaction-signing-payload transaction)))))

(defun access-list-transaction-hash (transaction)
  (keccak-256-hash (access-list-transaction-encoding transaction)))

(defstruct (dynamic-fee-transaction (:constructor make-dynamic-fee-transaction
                                     (&key (chain-id 0)
                                           (nonce 0)
                                           (max-priority-fee-per-gas 0)
                                           (max-fee-per-gas 0)
                                           (gas-limit 0)
                                           to
                                           (value 0)
                                           (data #())
                                           (access-list '())
                                           (y-parity 0)
                                           (r 0)
                                           (s 0))))
  (chain-id 0 :type (integer 0 *))
  (nonce 0 :type (integer 0 *))
  (max-priority-fee-per-gas 0 :type (integer 0 *))
  (max-fee-per-gas 0 :type (integer 0 *))
  (gas-limit 0 :type (integer 0 *))
  to
  (value 0 :type (integer 0 *))
  data
  (access-list '() :type list)
  (y-parity 0 :type (integer 0 *))
  (r 0 :type (integer 0 *))
  (s 0 :type (integer 0 *)))

(defun dynamic-fee-transaction-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (dynamic-fee-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (dynamic-fee-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (dynamic-fee-transaction-max-priority-fee-per-gas transaction)
                   "Transaction max priority fee")
   (ensure-uint256 (dynamic-fee-transaction-max-fee-per-gas transaction)
                   "Transaction max fee")
   (ensure-uint256 (dynamic-fee-transaction-gas-limit transaction) "Transaction gas limit")
   (transaction-to-bytes (dynamic-fee-transaction-to transaction))
   (ensure-uint256 (dynamic-fee-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (dynamic-fee-transaction-data transaction))
   (access-list-rlp-object (dynamic-fee-transaction-access-list transaction))
   (ensure-uint256 (dynamic-fee-transaction-y-parity transaction) "Transaction y parity")
   (ensure-uint256 (dynamic-fee-transaction-r transaction) "Transaction r")
   (ensure-uint256 (dynamic-fee-transaction-s transaction) "Transaction s")))

(defun dynamic-fee-transaction-encoding (transaction)
  (concat-bytes #(2) (rlp-encode (dynamic-fee-transaction-payload transaction))))

(defun dynamic-fee-transaction-from-rlp (bytes)
  (handler-case
      (let ((value (rlp-decode-one bytes)))
        (unless (rlp-list-p value)
          (block-validation-fail
           "Dynamic-fee transaction payload must be an RLP list"))
        (let ((fields (rlp-list-items value)))
          (unless (= (length fields) 12)
            (block-validation-fail
             "Dynamic-fee transaction payload must contain 12 fields"))
          (make-dynamic-fee-transaction
           :chain-id (rlp-uint-field (first fields)
                                     "Transaction chain id")
           :nonce (rlp-uint-field (second fields) "Transaction nonce")
           :max-priority-fee-per-gas
           (rlp-uint-field (third fields)
                           "Transaction max priority fee")
           :max-fee-per-gas
           (rlp-uint-field (fourth fields) "Transaction max fee")
           :gas-limit (rlp-uint-field (fifth fields)
                                      "Transaction gas limit")
           :to (legacy-transaction-recipient-from-rlp (sixth fields))
           :value (rlp-uint-field (seventh fields) "Transaction value")
           :data (rlp-bytes-field (eighth fields) "Transaction data")
           :access-list (access-list-from-rlp-object (ninth fields))
           :y-parity (rlp-uint-field (tenth fields) "Transaction y parity")
           :r (rlp-uint-field (nth 10 fields) "Transaction r")
           :s (rlp-uint-field (nth 11 fields) "Transaction s"))))
    (block-validation-error (condition)
      (error condition))
    (rlp-error (condition)
      (block-validation-fail "Invalid dynamic-fee transaction RLP: ~A"
                             condition))))

(defun dynamic-fee-transaction-signing-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (dynamic-fee-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (dynamic-fee-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (dynamic-fee-transaction-max-priority-fee-per-gas transaction)
                   "Transaction max priority fee")
   (ensure-uint256 (dynamic-fee-transaction-max-fee-per-gas transaction)
                   "Transaction max fee")
   (ensure-uint256 (dynamic-fee-transaction-gas-limit transaction) "Transaction gas limit")
   (transaction-to-bytes (dynamic-fee-transaction-to transaction))
   (ensure-uint256 (dynamic-fee-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (dynamic-fee-transaction-data transaction))
   (access-list-rlp-object (dynamic-fee-transaction-access-list transaction))))

(defun dynamic-fee-transaction-signing-hash (transaction)
  (keccak-256-hash
   (concat-bytes #(2)
                 (rlp-encode
                  (dynamic-fee-transaction-signing-payload transaction)))))

(defun dynamic-fee-transaction-hash (transaction)
  (keccak-256-hash (dynamic-fee-transaction-encoding transaction)))

(defstruct (blob-transaction (:constructor make-blob-transaction
                               (&key (chain-id 0)
                                     (nonce 0)
                                     (max-priority-fee-per-gas 0)
                                     (max-fee-per-gas 0)
                                     (gas-limit 0)
                                     to
                                     (value 0)
                                     (data #())
                                     (access-list '())
                                     (max-fee-per-blob-gas 0)
                                     (blob-versioned-hashes '())
                                     (y-parity 0)
                                     (r 0)
                                     (s 0))))
  (chain-id 0 :type (integer 0 *))
  (nonce 0 :type (integer 0 *))
  (max-priority-fee-per-gas 0 :type (integer 0 *))
  (max-fee-per-gas 0 :type (integer 0 *))
  (gas-limit 0 :type (integer 0 *))
  to
  (value 0 :type (integer 0 *))
  data
  (access-list '() :type list)
  (max-fee-per-blob-gas 0 :type (integer 0 *))
  (blob-versioned-hashes '() :type list)
  (y-parity 0 :type (integer 0 *))
  (r 0 :type (integer 0 *))
  (s 0 :type (integer 0 *)))

(defun blob-versioned-hash-bytes (hash)
  (etypecase hash
    (hash32 (hash32-bytes hash))
    (byte-vector (optional-bytes hash 32 "Blob versioned hash"))
    (vector (optional-bytes hash 32 "Blob versioned hash"))))

(defun required-transaction-recipient-from-rlp (value label)
  (let ((recipient (legacy-transaction-recipient-from-rlp value)))
    (unless recipient
      (block-validation-fail "~A must be exactly 20 bytes" label))
    recipient))

(defun blob-versioned-hash-from-rlp (value)
  (let ((bytes (rlp-bytes-field value "Blob versioned hash")))
    (unless (= (length bytes) 32)
      (block-validation-fail "Blob versioned hash must be exactly 32 bytes"))
    (make-hash32 bytes)))

(defun blob-versioned-hashes-from-rlp-object (value)
  (unless (rlp-list-p value)
    (block-validation-fail "Blob versioned hashes must be an RLP list"))
  (mapcar #'blob-versioned-hash-from-rlp
          (rlp-list-items value)))

(defun blob-transaction-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (blob-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (blob-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (blob-transaction-max-priority-fee-per-gas transaction)
                   "Transaction max priority fee")
   (ensure-uint256 (blob-transaction-max-fee-per-gas transaction)
                   "Transaction max fee")
   (ensure-uint256 (blob-transaction-gas-limit transaction) "Transaction gas limit")
   (required-transaction-to-bytes (blob-transaction-to transaction)
                                  "Blob transaction recipient")
   (ensure-uint256 (blob-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (blob-transaction-data transaction))
   (access-list-rlp-object (blob-transaction-access-list transaction))
   (ensure-uint256 (blob-transaction-max-fee-per-blob-gas transaction)
                   "Transaction max blob fee")
   (mapcar #'blob-versioned-hash-bytes
           (blob-transaction-blob-versioned-hashes transaction))
   (ensure-uint256 (blob-transaction-y-parity transaction) "Transaction y parity")
   (ensure-uint256 (blob-transaction-r transaction) "Transaction r")
   (ensure-uint256 (blob-transaction-s transaction) "Transaction s")))

(defun blob-transaction-signing-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (blob-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (blob-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (blob-transaction-max-priority-fee-per-gas transaction)
                   "Transaction max priority fee")
   (ensure-uint256 (blob-transaction-max-fee-per-gas transaction)
                   "Transaction max fee")
   (ensure-uint256 (blob-transaction-gas-limit transaction) "Transaction gas limit")
   (required-transaction-to-bytes (blob-transaction-to transaction)
                                  "Blob transaction recipient")
   (ensure-uint256 (blob-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (blob-transaction-data transaction))
   (access-list-rlp-object (blob-transaction-access-list transaction))
   (ensure-uint256 (blob-transaction-max-fee-per-blob-gas transaction)
                   "Transaction max blob fee")
   (mapcar #'blob-versioned-hash-bytes
           (blob-transaction-blob-versioned-hashes transaction))))

(defun blob-transaction-encoding (transaction)
  (concat-bytes #(3) (rlp-encode (blob-transaction-payload transaction))))

(defun blob-transaction-from-rlp (bytes)
  (handler-case
      (let ((value (rlp-decode-one bytes)))
        (unless (rlp-list-p value)
          (block-validation-fail
           "Blob transaction payload must be an RLP list"))
        (let ((fields (rlp-list-items value)))
          (unless (= (length fields) 14)
            (block-validation-fail
             "Blob transaction payload must contain 14 fields"))
          (make-blob-transaction
           :chain-id (rlp-uint-field (first fields)
                                     "Transaction chain id")
           :nonce (rlp-uint-field (second fields) "Transaction nonce")
           :max-priority-fee-per-gas
           (rlp-uint-field (third fields)
                           "Transaction max priority fee")
           :max-fee-per-gas
           (rlp-uint-field (fourth fields) "Transaction max fee")
           :gas-limit (rlp-uint-field (fifth fields)
                                      "Transaction gas limit")
           :to (required-transaction-recipient-from-rlp
                (sixth fields)
                "Blob transaction recipient")
           :value (rlp-uint-field (seventh fields) "Transaction value")
           :data (rlp-bytes-field (eighth fields) "Transaction data")
           :access-list (access-list-from-rlp-object (ninth fields))
           :max-fee-per-blob-gas
           (rlp-uint-field (nth 9 fields) "Transaction max blob fee")
           :blob-versioned-hashes
           (blob-versioned-hashes-from-rlp-object (nth 10 fields))
           :y-parity (rlp-uint-field (nth 11 fields)
                                     "Transaction y parity")
           :r (rlp-uint-field (nth 12 fields) "Transaction r")
           :s (rlp-uint-field (nth 13 fields) "Transaction s"))))
    (block-validation-error (condition)
      (error condition))
    (rlp-error (condition)
      (block-validation-fail "Invalid blob transaction RLP: ~A"
                             condition))))

(defun blob-transaction-signing-hash (transaction)
  (keccak-256-hash
   (concat-bytes #(3)
                 (rlp-encode
                  (blob-transaction-signing-payload transaction)))))

(defun blob-transaction-hash (transaction)
  (keccak-256-hash (blob-transaction-encoding transaction)))

(defstruct (blob-sidecar (:constructor make-blob-sidecar
                            (&key (blobs '())
                                  (commitments '())
                                  (proofs '()))))
  (blobs '() :type list)
  (commitments '() :type list)
  (proofs '() :type list))

(defun blob-sidecar-versioned-hashes (sidecar)
  (mapcar #'kzg-commitment-to-versioned-hash
          (blob-sidecar-commitments sidecar)))

(defstruct (set-code-authorization (:constructor make-set-code-authorization
                                     (&key (chain-id 0)
                                           address
                                           (nonce 0)
                                           (y-parity 0)
                                           (r 0)
                                           (s 0))))
  (chain-id 0 :type (integer 0 *))
  address
  (nonce 0 :type (integer 0 *))
  (y-parity 0 :type (integer 0 *))
  (r 0 :type (integer 0 *))
  (s 0 :type (integer 0 *)))

(defun set-code-authorization-rlp-object (authorization)
  (make-rlp-list
   (ensure-uint256 (set-code-authorization-chain-id authorization)
                   "Authorization chain id")
   (required-transaction-to-bytes (set-code-authorization-address authorization)
                                  "Authorization address")
   (ensure-uint256 (set-code-authorization-nonce authorization)
                   "Authorization nonce")
   (ensure-uint256 (set-code-authorization-y-parity authorization)
                   "Authorization y parity")
   (ensure-uint256 (set-code-authorization-r authorization)
                   "Authorization r")
   (ensure-uint256 (set-code-authorization-s authorization)
                   "Authorization s")))

(defun set-code-authorization-from-rlp-object (value)
  (unless (rlp-list-p value)
    (block-validation-fail "Set-code authorization must be an RLP list"))
  (let ((fields (rlp-list-items value)))
    (unless (= (length fields) 6)
      (block-validation-fail
       "Set-code authorization must contain 6 fields"))
    (make-set-code-authorization
     :chain-id (rlp-uint-field (first fields) "Authorization chain id")
     :address (required-transaction-recipient-from-rlp
               (second fields)
               "Authorization address")
     :nonce (rlp-uint-field (third fields) "Authorization nonce")
     :y-parity (rlp-uint-field (fourth fields)
                               "Authorization y parity")
     :r (rlp-uint-field (fifth fields) "Authorization r")
     :s (rlp-uint-field (sixth fields) "Authorization s"))))

(defun set-code-authorization-signing-hash (authorization)
  (keccak-256-hash
   (concat-bytes
    #(5)
    (rlp-encode
     (make-rlp-list
      (ensure-uint256 (set-code-authorization-chain-id authorization)
                      "Authorization chain id")
      (required-transaction-to-bytes (set-code-authorization-address authorization)
                                     "Authorization address")
      (ensure-uint256 (set-code-authorization-nonce authorization)
                      "Authorization nonce"))))))

(defun set-code-authorization-authority (authorization)
  "Recover the authority address from an EIP-7702 authorization tuple."
  (let ((y-parity (set-code-authorization-y-parity authorization))
        (r (set-code-authorization-r authorization))
        (s (set-code-authorization-s authorization)))
    (when (secp256k1-valid-signature-values-p y-parity r s :low-s-p t)
      (secp256k1-recover-address
       (hash32-bytes (set-code-authorization-signing-hash authorization))
       y-parity
       r
       s))))

(defconstant +set-code-delegation-prefix+ #(#xef #x01 #x00))

(defun set-code-delegation-code (address)
  (concat-bytes +set-code-delegation-prefix+ (address-bytes address)))

(defun set-code-delegation-target (code)
  (let ((code (ensure-byte-vector code)))
    (when (and (= 23 (length code))
               (loop for i below (length +set-code-delegation-prefix+)
                     always (= (aref code i)
                               (aref +set-code-delegation-prefix+ i))))
      (make-address (subseq code (length +set-code-delegation-prefix+))))))

(defstruct (set-code-transaction (:constructor make-set-code-transaction
                                   (&key (chain-id 0)
                                         (nonce 0)
                                         (max-priority-fee-per-gas 0)
                                         (max-fee-per-gas 0)
                                         (gas-limit 0)
                                         to
                                         (value 0)
                                         (data #())
                                         (access-list '())
                                         (authorization-list '())
                                         (y-parity 0)
                                         (r 0)
                                         (s 0))))
  (chain-id 0 :type (integer 0 *))
  (nonce 0 :type (integer 0 *))
  (max-priority-fee-per-gas 0 :type (integer 0 *))
  (max-fee-per-gas 0 :type (integer 0 *))
  (gas-limit 0 :type (integer 0 *))
  to
  (value 0 :type (integer 0 *))
  data
  (access-list '() :type list)
  (authorization-list '() :type list)
  (y-parity 0 :type (integer 0 *))
  (r 0 :type (integer 0 *))
  (s 0 :type (integer 0 *)))

(defun set-code-authorization-list-rlp-object (authorization-list)
  (mapcar #'set-code-authorization-rlp-object authorization-list))

(defun set-code-authorization-list-from-rlp-object (value)
  (unless (rlp-list-p value)
    (block-validation-fail "Set-code authorization list must be an RLP list"))
  (mapcar #'set-code-authorization-from-rlp-object
          (rlp-list-items value)))

(defun set-code-transaction-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (set-code-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (set-code-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (set-code-transaction-max-priority-fee-per-gas transaction)
                   "Transaction max priority fee")
   (ensure-uint256 (set-code-transaction-max-fee-per-gas transaction)
                   "Transaction max fee")
   (ensure-uint256 (set-code-transaction-gas-limit transaction) "Transaction gas limit")
   (required-transaction-to-bytes (set-code-transaction-to transaction)
                                  "Set-code transaction recipient")
   (ensure-uint256 (set-code-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (set-code-transaction-data transaction))
   (access-list-rlp-object (set-code-transaction-access-list transaction))
   (set-code-authorization-list-rlp-object
    (set-code-transaction-authorization-list transaction))
   (ensure-uint256 (set-code-transaction-y-parity transaction) "Transaction y parity")
   (ensure-uint256 (set-code-transaction-r transaction) "Transaction r")
   (ensure-uint256 (set-code-transaction-s transaction) "Transaction s")))

(defun set-code-transaction-signing-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (set-code-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (set-code-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (set-code-transaction-max-priority-fee-per-gas transaction)
                   "Transaction max priority fee")
   (ensure-uint256 (set-code-transaction-max-fee-per-gas transaction)
                   "Transaction max fee")
   (ensure-uint256 (set-code-transaction-gas-limit transaction) "Transaction gas limit")
   (required-transaction-to-bytes (set-code-transaction-to transaction)
                                  "Set-code transaction recipient")
   (ensure-uint256 (set-code-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (set-code-transaction-data transaction))
   (access-list-rlp-object (set-code-transaction-access-list transaction))
   (set-code-authorization-list-rlp-object
    (set-code-transaction-authorization-list transaction))))

(defun set-code-transaction-encoding (transaction)
  (concat-bytes #(4) (rlp-encode (set-code-transaction-payload transaction))))

(defun set-code-transaction-from-rlp (bytes)
  (handler-case
      (let ((value (rlp-decode-one bytes)))
        (unless (rlp-list-p value)
          (block-validation-fail
           "Set-code transaction payload must be an RLP list"))
        (let ((fields (rlp-list-items value)))
          (unless (= (length fields) 13)
            (block-validation-fail
             "Set-code transaction payload must contain 13 fields"))
          (make-set-code-transaction
           :chain-id (rlp-uint-field (first fields)
                                     "Transaction chain id")
           :nonce (rlp-uint-field (second fields) "Transaction nonce")
           :max-priority-fee-per-gas
           (rlp-uint-field (third fields)
                           "Transaction max priority fee")
           :max-fee-per-gas
           (rlp-uint-field (fourth fields) "Transaction max fee")
           :gas-limit (rlp-uint-field (fifth fields)
                                      "Transaction gas limit")
           :to (required-transaction-recipient-from-rlp
                (sixth fields)
                "Set-code transaction recipient")
           :value (rlp-uint-field (seventh fields) "Transaction value")
           :data (rlp-bytes-field (eighth fields) "Transaction data")
           :access-list (access-list-from-rlp-object (ninth fields))
           :authorization-list
           (set-code-authorization-list-from-rlp-object (nth 9 fields))
           :y-parity (rlp-uint-field (nth 10 fields)
                                     "Transaction y parity")
           :r (rlp-uint-field (nth 11 fields) "Transaction r")
           :s (rlp-uint-field (nth 12 fields) "Transaction s"))))
    (block-validation-error (condition)
      (error condition))
    (rlp-error (condition)
      (block-validation-fail "Invalid set-code transaction RLP: ~A"
                             condition))))

(defun set-code-transaction-signing-hash (transaction)
  (keccak-256-hash
   (concat-bytes
    #(4)
    (rlp-encode (set-code-transaction-signing-payload transaction)))))

(defun set-code-transaction-hash (transaction)
  (keccak-256-hash (set-code-transaction-encoding transaction)))

(defun transaction-nonce (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-nonce transaction))
    (access-list-transaction (access-list-transaction-nonce transaction))
    (dynamic-fee-transaction (dynamic-fee-transaction-nonce transaction))
    (blob-transaction (blob-transaction-nonce transaction))
    (set-code-transaction (set-code-transaction-nonce transaction))))

(defun transaction-gas-limit (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-gas-limit transaction))
    (access-list-transaction (access-list-transaction-gas-limit transaction))
    (dynamic-fee-transaction (dynamic-fee-transaction-gas-limit transaction))
    (blob-transaction (blob-transaction-gas-limit transaction))
    (set-code-transaction (set-code-transaction-gas-limit transaction))))

(defun transaction-to (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-to transaction))
    (access-list-transaction (access-list-transaction-to transaction))
    (dynamic-fee-transaction (dynamic-fee-transaction-to transaction))
    (blob-transaction (blob-transaction-to transaction))
    (set-code-transaction (set-code-transaction-to transaction))))

(defun transaction-value (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-value transaction))
    (access-list-transaction (access-list-transaction-value transaction))
    (dynamic-fee-transaction (dynamic-fee-transaction-value transaction))
    (blob-transaction (blob-transaction-value transaction))
    (set-code-transaction (set-code-transaction-value transaction))))

(defun transaction-data (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-data transaction))
    (access-list-transaction (access-list-transaction-data transaction))
    (dynamic-fee-transaction (dynamic-fee-transaction-data transaction))
    (blob-transaction (blob-transaction-data transaction))
    (set-code-transaction (set-code-transaction-data transaction))))

(defun transaction-access-list (transaction)
  (etypecase transaction
    (legacy-transaction '())
    (access-list-transaction (access-list-transaction-access-list transaction))
    (dynamic-fee-transaction (dynamic-fee-transaction-access-list transaction))
    (blob-transaction (blob-transaction-access-list transaction))
    (set-code-transaction (set-code-transaction-access-list transaction))))

(defun transaction-authorization-list (transaction)
  (etypecase transaction
    ((or legacy-transaction
         access-list-transaction
         dynamic-fee-transaction
         blob-transaction)
     '())
    (set-code-transaction
     (set-code-transaction-authorization-list transaction))))

(defun transaction-type (transaction)
  (etypecase transaction
    (legacy-transaction 0)
    (access-list-transaction 1)
    (dynamic-fee-transaction 2)
    (blob-transaction 3)
    (set-code-transaction 4)))

(defun validate-transaction-type-for-config
    (transaction config block-number timestamp)
  (let* ((rules (chain-config-rules config block-number timestamp))
         (type (transaction-type transaction)))
    (when (chain-rules-transaction-type-supported-p rules transaction)
      (return-from validate-transaction-type-for-config t))
    (cond
      ((= type 1)
       (block-validation-fail "Access-list transaction before Berlin"))
      ((= type 2)
       (block-validation-fail "Dynamic-fee transaction before London"))
      ((= type 3)
       (block-validation-fail "Blob transaction before Cancun"))
      ((= type 4)
       (block-validation-fail "Set-code transaction before Prague"))
      (t
       (block-validation-fail "Unsupported transaction type"))))
  t)

(defun transaction-blob-versioned-hashes (transaction)
  (etypecase transaction
    ((or legacy-transaction
         access-list-transaction
         dynamic-fee-transaction
         set-code-transaction)
     #())
    (blob-transaction
     (coerce (blob-transaction-blob-versioned-hashes transaction) 'vector))))

(defun transaction-blob-gas-used (transaction)
  (* (length (transaction-blob-versioned-hashes transaction))
     +blob-gas-per-blob+))

(defun access-list-storage-key-count (access-list)
  (loop for entry in access-list
        sum (length (access-list-entry-storage-keys entry))))

(defun transaction-max-priority-fee-per-gas (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-gas-price transaction))
    (access-list-transaction (access-list-transaction-gas-price transaction))
    (dynamic-fee-transaction
     (dynamic-fee-transaction-max-priority-fee-per-gas transaction))
    (blob-transaction
     (blob-transaction-max-priority-fee-per-gas transaction))
    (set-code-transaction
     (set-code-transaction-max-priority-fee-per-gas transaction))))

(defun transaction-max-fee-per-gas (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-gas-price transaction))
    (access-list-transaction (access-list-transaction-gas-price transaction))
    (dynamic-fee-transaction
     (dynamic-fee-transaction-max-fee-per-gas transaction))
    (blob-transaction
     (blob-transaction-max-fee-per-gas transaction))
    (set-code-transaction
     (set-code-transaction-max-fee-per-gas transaction))))

(defun validate-1559-transaction-fees (transaction base-fee)
  (let ((max-priority-fee (transaction-max-priority-fee-per-gas transaction))
        (max-fee (transaction-max-fee-per-gas transaction)))
    (unless (uint256-p max-priority-fee)
      (block-validation-fail "Max priority fee must be uint256"))
    (unless (uint256-p max-fee)
      (block-validation-fail "Max fee per gas must be uint256"))
    (when (< max-fee max-priority-fee)
      (block-validation-fail "Max priority fee exceeds max fee"))
    (when (< max-fee base-fee)
      (block-validation-fail "Max fee per gas below base fee"))
    t))

(defun transaction-effective-gas-price
    (transaction &key (base-fee 0) (eip1559-enabled-p t))
  (if (not eip1559-enabled-p)
      (transaction-max-priority-fee-per-gas transaction)
      (progn
        (validate-1559-transaction-fees transaction base-fee)
        (if (or (typep transaction 'legacy-transaction)
                (typep transaction 'access-list-transaction))
            (transaction-max-fee-per-gas transaction)
            (+ base-fee
               (min (transaction-max-priority-fee-per-gas transaction)
                    (- (transaction-max-fee-per-gas transaction)
                       base-fee)))))))

(defun transaction-priority-fee-per-gas
    (transaction &key (base-fee 0) (eip1559-enabled-p t))
  (if (not eip1559-enabled-p)
      (transaction-max-priority-fee-per-gas transaction)
      (max 0 (- (transaction-effective-gas-price transaction
                                                 :base-fee base-fee)
                base-fee))))

(defun transaction-encoding (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-rlp transaction))
    (access-list-transaction (access-list-transaction-encoding transaction))
    (dynamic-fee-transaction (dynamic-fee-transaction-encoding transaction))
    (blob-transaction (blob-transaction-encoding transaction))
    (set-code-transaction (set-code-transaction-encoding transaction))))

(defun transaction-from-encoding (bytes)
  (let ((bytes (ensure-byte-vector bytes)))
    (when (zerop (length bytes))
      (block-validation-fail "Transaction encoding is empty"))
    (if (> (aref bytes 0) #x7f)
        (legacy-transaction-from-rlp bytes)
        (case (aref bytes 0)
          (1 (access-list-transaction-from-rlp (subseq bytes 1)))
          (2 (dynamic-fee-transaction-from-rlp (subseq bytes 1)))
          (3 (blob-transaction-from-rlp (subseq bytes 1)))
          (4 (set-code-transaction-from-rlp (subseq bytes 1)))
          (otherwise
           (block-validation-fail
            "Typed transaction decoding is not implemented yet"))))))

(defun transaction-hash (transaction)
  (keccak-256-hash (transaction-encoding transaction)))

(defun typed-transaction-sender
    (chain-id y-parity r s signing-hash &key expected-chain-id)
  (when (and (or (not expected-chain-id)
                 (= expected-chain-id chain-id))
             (secp256k1-valid-signature-values-p y-parity r s :low-s-p t))
    (secp256k1-recover-address (hash32-bytes signing-hash) y-parity r s)))

(defun access-list-transaction-sender (transaction &key expected-chain-id)
  "Recover the sender address from an EIP-2930 transaction signature."
  (typed-transaction-sender
   (access-list-transaction-chain-id transaction)
   (access-list-transaction-y-parity transaction)
   (access-list-transaction-r transaction)
   (access-list-transaction-s transaction)
   (access-list-transaction-signing-hash transaction)
   :expected-chain-id expected-chain-id))

(defun dynamic-fee-transaction-sender (transaction &key expected-chain-id)
  "Recover the sender address from an EIP-1559 transaction signature."
  (typed-transaction-sender
   (dynamic-fee-transaction-chain-id transaction)
   (dynamic-fee-transaction-y-parity transaction)
   (dynamic-fee-transaction-r transaction)
   (dynamic-fee-transaction-s transaction)
   (dynamic-fee-transaction-signing-hash transaction)
   :expected-chain-id expected-chain-id))

(defun blob-transaction-sender (transaction &key expected-chain-id)
  "Recover the sender address from an EIP-4844 transaction signature."
  (typed-transaction-sender
   (blob-transaction-chain-id transaction)
   (blob-transaction-y-parity transaction)
   (blob-transaction-r transaction)
   (blob-transaction-s transaction)
   (blob-transaction-signing-hash transaction)
   :expected-chain-id expected-chain-id))

(defun set-code-transaction-sender (transaction &key expected-chain-id)
  "Recover the sender address from an EIP-7702 set-code transaction signature."
  (typed-transaction-sender
   (set-code-transaction-chain-id transaction)
   (set-code-transaction-y-parity transaction)
   (set-code-transaction-r transaction)
   (set-code-transaction-s transaction)
   (set-code-transaction-signing-hash transaction)
   :expected-chain-id expected-chain-id))

(defun transaction-sender (transaction &key expected-chain-id)
  (etypecase transaction
    (legacy-transaction
     (legacy-transaction-sender transaction
                                :expected-chain-id expected-chain-id))
    (access-list-transaction
     (access-list-transaction-sender transaction
                                     :expected-chain-id expected-chain-id))
    (dynamic-fee-transaction
     (dynamic-fee-transaction-sender transaction
                                     :expected-chain-id expected-chain-id))
    (blob-transaction
     (blob-transaction-sender transaction
                              :expected-chain-id expected-chain-id))
    (set-code-transaction
     (set-code-transaction-sender transaction
                                  :expected-chain-id expected-chain-id))))

(defstruct (block-header (:constructor make-block-header
                            (&key parent-hash
                                  ommers-hash
                                  beneficiary
                                  state-root
                                  transactions-root
                                  receipts-root
                                  logs-bloom
                                  (difficulty 0)
                                  (number 0)
                                  (gas-limit 0)
                                  (gas-used 0)
                                  (timestamp 0)
                                  (extra-data #())
                                  mix-hash
                                  nonce
                                  base-fee-per-gas
                                  withdrawals-root
                                  blob-gas-used
                                  excess-blob-gas
                                  parent-beacon-root
                                  requests-hash
                                  block-access-list-hash
                                  slot-number)))
  parent-hash
  ommers-hash
  beneficiary
  state-root
  transactions-root
  receipts-root
  logs-bloom
  (difficulty 0 :type (integer 0 *))
  (number 0 :type (integer 0 *))
  (gas-limit 0 :type (integer 0 *))
  (gas-used 0 :type (integer 0 *))
  (timestamp 0 :type (integer 0 *))
  (extra-data (make-byte-vector 0))
  mix-hash
  nonce
  base-fee-per-gas
  withdrawals-root
  blob-gas-used
  excess-blob-gas
  parent-beacon-root
  requests-hash
  block-access-list-hash
  slot-number)

(defun hash-or-zero (hash)
  (hash32-bytes (or hash (zero-hash32))))

(defun address-or-zero (address)
  (address-bytes (or address (zero-address))))

(defun header-fields (header)
  (let ((fields
          (list
           (hash-or-zero (block-header-parent-hash header))
           (hash32-bytes (or (block-header-ommers-hash header) +empty-ommers-hash+))
           (address-or-zero (block-header-beneficiary header))
           (hash32-bytes (or (block-header-state-root header) +empty-trie-hash+))
           (hash32-bytes (or (block-header-transactions-root header) +empty-trie-hash+))
           (hash32-bytes (or (block-header-receipts-root header) +empty-trie-hash+))
           (optional-bytes (or (block-header-logs-bloom header) (make-byte-vector 256))
                           256 "Logs bloom")
           (ensure-uint256 (block-header-difficulty header) "Header difficulty")
           (ensure-uint256 (block-header-number header) "Header number")
           (ensure-uint256 (block-header-gas-limit header) "Header gas limit")
           (ensure-uint256 (block-header-gas-used header) "Header gas used")
           (ensure-uint256 (block-header-timestamp header) "Header timestamp")
           (ensure-byte-vector (block-header-extra-data header))
           (hash-or-zero (block-header-mix-hash header))
           (optional-bytes (or (block-header-nonce header) (make-byte-vector 8))
                           8 "Header nonce"))))
    (when (block-header-base-fee-per-gas header)
      (setf fields (append fields
                           (list (ensure-uint256
                                  (block-header-base-fee-per-gas header)
                                  "Header base fee")))))
    (when (block-header-withdrawals-root header)
      (setf fields (append fields
                           (list (hash32-bytes
                                  (block-header-withdrawals-root header))))))
    (when (block-header-blob-gas-used header)
      (setf fields (append fields
                           (list (ensure-uint256
                                  (block-header-blob-gas-used header)
                                  "Header blob gas used")
                                 (ensure-uint256
                                  (or (block-header-excess-blob-gas header) 0)
                                  "Header excess blob gas")))))
    (when (block-header-parent-beacon-root header)
      (setf fields (append fields
                           (list (hash32-bytes
                                  (block-header-parent-beacon-root header))))))
    (when (block-header-requests-hash header)
      (setf fields (append fields
                           (list (hash32-bytes
                                  (block-header-requests-hash header))))))
    (when (or (block-header-block-access-list-hash header)
              (block-header-slot-number header))
      (setf fields (append fields
                           (list (if (block-header-block-access-list-hash
                                      header)
                                     (hash32-bytes
                                      (block-header-block-access-list-hash
                                       header))
                                     (make-byte-vector 0))))))
    (when (block-header-slot-number header)
      (setf fields (append fields
                           (list (ensure-uint256
                                  (block-header-slot-number header)
                                  "Header slot number")))))
    fields))

(defun block-header-rlp (header)
  (rlp-encode (apply #'make-rlp-list (header-fields header))))

(defun block-header-hash (header)
  (keccak-256-hash (block-header-rlp header)))

(defun ommers-hash (ommers)
  (keccak-256-hash
   (rlp-encode
    (mapcar (lambda (header)
              (apply #'make-rlp-list (header-fields header)))
            ommers))))

(defun receipts-logs-bloom (receipts)
  (receipt-bloom
   (loop for receipt in receipts
         append (receipt-logs receipt))))

(defstruct (ethereum-block (:constructor %make-block
                             (&key header
                                   (transactions '())
                                   (ommers '())
                                   withdrawals
                                   withdrawals-present-p
                                   requests
                                   requests-present-p
                                   block-access-list
                                   block-access-list-present-p
                                   encoded-block-access-list))
                           (:conc-name block-))
  header
  (transactions '() :type list)
  (ommers '() :type list)
  withdrawals
  withdrawals-present-p
  requests
  requests-present-p
  block-access-list
  block-access-list-present-p
  encoded-block-access-list)

(defun make-block (&key (header (make-block-header))
                        (transactions '())
                        (receipts '())
                        (ommers '())
                        (withdrawals nil withdrawals-supplied-p)
                        (requests nil requests-supplied-p)
                        (block-access-list nil block-access-list-supplied-p)
                        (block-access-list-rlp nil
                         block-access-list-rlp-supplied-p))
  (let ((encoded-block-access-list nil))
    (when (and block-access-list-supplied-p
               block-access-list-rlp-supplied-p)
      (block-validation-fail
       "Block access list cannot be supplied as both typed data and RLP"))
    (when block-access-list-rlp-supplied-p
      (setf encoded-block-access-list
            (block-access-list-rlp-input-bytes block-access-list-rlp)
            block-access-list
            (block-access-list-from-rlp encoded-block-access-list)
            block-access-list-supplied-p t))
    (setf (block-header-transactions-root header)
          (transaction-list-root transactions)
          (block-header-receipts-root header)
          (if (= (length transactions) (length receipts))
              (transaction-receipt-list-root transactions receipts)
              (receipt-list-root receipts))
          (block-header-logs-bloom header)
          (bloom-bytes (receipts-logs-bloom receipts))
          (block-header-ommers-hash header)
          (ommers-hash ommers))
    (when withdrawals-supplied-p
      (setf (block-header-withdrawals-root header)
            (withdrawal-list-root withdrawals)))
    (when requests-supplied-p
      (setf (block-header-requests-hash header)
            (execution-requests-hash requests)))
    (when block-access-list-supplied-p
      (unless encoded-block-access-list
        (validate-block-access-list-fields block-access-list)
        (setf encoded-block-access-list
              (block-access-list-rlp block-access-list)))
      (setf (block-header-block-access-list-hash header)
            (keccak-256-hash encoded-block-access-list)))
    (%make-block :header header
                 :transactions transactions
                 :ommers ommers
                 :withdrawals withdrawals
                 :withdrawals-present-p withdrawals-supplied-p
                 :requests requests
                 :requests-present-p requests-supplied-p
                 :block-access-list block-access-list
                 :block-access-list-present-p block-access-list-supplied-p
                 :encoded-block-access-list encoded-block-access-list)))

(defun block-hash (block)
  (block-header-hash (block-header block)))

(defstruct (executable-data (:constructor make-executable-data
                              (&key parent-hash
                                    fee-recipient
                                    state-root
                                    receipts-root
                                    logs-bloom
                                    random
                                    number
                                    gas-limit
                                    gas-used
                                    timestamp
                                    extra-data
                                    base-fee-per-gas
                                    block-hash
                                    transactions
                                    withdrawals
                                    blob-gas-used
                                    excess-blob-gas
                                    slot-number)))
  parent-hash
  fee-recipient
  state-root
  receipts-root
  logs-bloom
  random
  number
  gas-limit
  gas-used
  timestamp
  extra-data
  base-fee-per-gas
  block-hash
  (transactions '() :type list)
  withdrawals
  blob-gas-used
  excess-blob-gas
  slot-number)

(defstruct (execution-payload-envelope
            (:constructor make-execution-payload-envelope
                (&key execution-payload
                      (block-value 0)
                      blobs-bundle
                      requests
                      override-p)))
  execution-payload
  (block-value 0 :type (integer 0 *))
  blobs-bundle
  requests
  override-p)

(defun maybe-copy-bytes (bytes)
  (when bytes
    (copy-seq (ensure-byte-vector bytes))))

(defun maybe-copy-withdrawals (withdrawals)
  (when withdrawals
    (mapcar #'copy-withdrawal withdrawals)))

(defun maybe-copy-requests (requests)
  (when requests
    (mapcar #'maybe-copy-bytes requests)))

(defun block-to-executable-data (block &key (block-value 0) requests)
  (let* ((header (block-header block))
         (payload
           (make-executable-data
            :block-hash (block-hash block)
            :parent-hash (or (block-header-parent-hash header) (zero-hash32))
            :fee-recipient (or (block-header-beneficiary header)
                               (zero-address))
            :state-root (or (block-header-state-root header) +empty-trie-hash+)
            :receipts-root (or (block-header-receipts-root header)
                               +empty-trie-hash+)
            :logs-bloom (maybe-copy-bytes
                         (or (block-header-logs-bloom header)
                             (make-byte-vector 256)))
            :random (or (block-header-mix-hash header) (zero-hash32))
            :number (block-header-number header)
            :gas-limit (block-header-gas-limit header)
            :gas-used (block-header-gas-used header)
            :timestamp (block-header-timestamp header)
            :extra-data (maybe-copy-bytes (block-header-extra-data header))
            :base-fee-per-gas (or (block-header-base-fee-per-gas header) 0)
            :transactions (mapcar (lambda (transaction)
                                    (copy-seq
                                     (transaction-encoding transaction)))
                                  (block-transactions block))
            :withdrawals (when (block-withdrawals-present-p block)
                           (maybe-copy-withdrawals
                            (block-withdrawals block)))
            :blob-gas-used (block-header-blob-gas-used header)
            :excess-blob-gas (block-header-excess-blob-gas header)
            :slot-number (block-header-slot-number header)))
         (payload-requests
           (cond
             (requests (maybe-copy-requests requests))
             ((block-requests-present-p block)
              (maybe-copy-requests (block-requests block)))
             (t nil))))
    (make-execution-payload-envelope
     :execution-payload payload
     :block-value block-value
     :requests payload-requests
     :override-p nil)))

(defun executable-data-decoded-transactions (payload)
  (unless (typep payload 'executable-data)
    (block-validation-fail "Executable data payload must be executable-data"))
  (let ((transactions (executable-data-transactions payload)))
    (unless (listp transactions)
      (block-validation-fail "Executable data transactions must be a list"))
    (loop for encoded in transactions
          for index from 0
          collect
          (handler-case
              (transaction-from-encoding
               (validate-byte-sequence-field
                encoded
                (format nil "Executable data transaction ~D" index)))
            (block-validation-error (condition)
              (block-validation-fail
               "Invalid executable data transaction ~D: ~A"
               index condition))))))

(defun executable-data-blob-versioned-hashes (transactions)
  (loop for transaction in transactions
        append (coerce (transaction-blob-versioned-hashes transaction)
                       'list)))

(defun validate-executable-data-versioned-hashes
    (transactions versioned-hashes)
  (unless (listp versioned-hashes)
    (block-validation-fail "Executable data versioned hashes must be a list"))
  (let ((blob-hashes (executable-data-blob-versioned-hashes transactions)))
    (unless (= (length blob-hashes) (length versioned-hashes))
      (block-validation-fail
       "Executable data versioned hash count mismatch"))
    (loop for blob-hash in blob-hashes
          for versioned-hash in versioned-hashes
          for index from 0
          do (unless (hash32-p versioned-hash)
               (block-validation-fail
                "Executable data versioned hash ~D must be a hash32"
                index))
             (unless (hash32= blob-hash versioned-hash)
               (block-validation-fail
                "Executable data versioned hash ~D mismatch"
                index))))
  t)

(defun executable-data-required-hash32 (value label)
  (unless (hash32-p value)
    (block-validation-fail "~A must be a hash32" label))
  value)

(defun executable-data-required-address (value label)
  (unless (address-p value)
    (block-validation-fail "~A must be an address" label))
  value)

(defun executable-data-required-uint256 (value label)
  (unless (uint256-p value)
    (block-validation-fail "~A must be uint256" label))
  value)

(defun executable-data-to-block-no-hash
    (payload &key parent-beacon-root (versioned-hashes nil)
               (requests nil requests-supplied-p))
  (unless (typep payload 'executable-data)
    (block-validation-fail "Executable data payload must be executable-data"))
  (let* ((transactions (executable-data-decoded-transactions payload))
         (withdrawals (executable-data-withdrawals payload))
         (extra-data (validate-byte-sequence-field
                      (executable-data-extra-data payload)
                      "Executable data extra data"))
         (logs-bloom (validate-byte-sequence-field
                      (executable-data-logs-bloom payload)
                      "Executable data logs bloom"
                      :size 256)))
    (when (> (length extra-data) +maximum-extra-data-size+)
      (block-validation-fail "Executable data extra data too long"))
    (when withdrawals
      (validate-withdrawal-list-fields withdrawals))
    (validate-executable-data-versioned-hashes transactions versioned-hashes)
    (validate-optional-hash32-field parent-beacon-root
                                    "Executable data parent beacon root")
    (when requests-supplied-p
      (validate-execution-request-list-fields requests))
    (let ((header
            (make-block-header
             :parent-hash
             (executable-data-required-hash32
              (executable-data-parent-hash payload)
              "Executable data parent hash")
             :ommers-hash +empty-ommers-hash+
             :beneficiary
             (executable-data-required-address
              (executable-data-fee-recipient payload)
              "Executable data fee recipient")
             :state-root
             (executable-data-required-hash32
              (executable-data-state-root payload)
              "Executable data state root")
             :transactions-root (transaction-list-root transactions)
             :receipts-root
             (executable-data-required-hash32
              (executable-data-receipts-root payload)
              "Executable data receipts root")
             :logs-bloom (copy-seq logs-bloom)
             :difficulty 0
             :number
             (executable-data-required-uint256
              (executable-data-number payload)
              "Executable data block number")
             :gas-limit
             (executable-data-required-uint256
              (executable-data-gas-limit payload)
              "Executable data gas limit")
             :gas-used
             (executable-data-required-uint256
              (executable-data-gas-used payload)
              "Executable data gas used")
             :timestamp
             (executable-data-required-uint256
              (executable-data-timestamp payload)
              "Executable data timestamp")
             :extra-data (copy-seq extra-data)
             :mix-hash
             (executable-data-required-hash32
              (executable-data-random payload)
              "Executable data random")
             :base-fee-per-gas
             (executable-data-required-uint256
              (executable-data-base-fee-per-gas payload)
              "Executable data base fee")
             :withdrawals-root (when withdrawals
                                 (withdrawal-list-root withdrawals))
             :blob-gas-used (executable-data-blob-gas-used payload)
             :excess-blob-gas (executable-data-excess-blob-gas payload)
             :parent-beacon-root parent-beacon-root
             :requests-hash (when requests-supplied-p
                              (execution-requests-hash requests))
             :slot-number (executable-data-slot-number payload))))
      (validate-optional-uint256-field (block-header-blob-gas-used header)
                                       "Executable data blob gas used")
      (validate-optional-uint256-field (block-header-excess-blob-gas header)
                                       "Executable data excess blob gas")
      (validate-optional-uint256-field (block-header-slot-number header)
                                       "Executable data slot number")
      (%make-block :header header
                   :transactions transactions
                   :ommers '()
                   :withdrawals withdrawals
                   :withdrawals-present-p (not (null withdrawals))
                   :requests requests
                   :requests-present-p requests-supplied-p))))

(defun executable-data-to-block
    (payload &key parent-beacon-root (versioned-hashes nil)
               (requests nil requests-supplied-p))
  (let* ((block (if requests-supplied-p
                    (executable-data-to-block-no-hash
                     payload
                     :parent-beacon-root parent-beacon-root
                     :versioned-hashes versioned-hashes
                     :requests requests)
                    (executable-data-to-block-no-hash
                     payload
                     :parent-beacon-root parent-beacon-root
                     :versioned-hashes versioned-hashes)))
         (expected-hash
           (executable-data-required-hash32
            (executable-data-block-hash payload)
            "Executable data block hash")))
    (unless (hash32= (block-hash block) expected-hash)
      (block-validation-fail "Executable data block hash mismatch"))
    block))

(defun execution-requests-hash (requests)
  (sha256-hash
   (apply #'concat-bytes
          (loop for request in requests
                for bytes = (validate-execution-request-fields request)
                when (> (length bytes) 1)
                  collect (sha256 bytes)))))

(defstruct (block-access-account (:constructor make-block-access-account
                                      (&key address
                                            (storage-writes '())
                                            (storage-reads '())
                                            (balance-changes '())
                                            (nonce-changes '())
                                            (code-changes '()))))
  address
  (storage-writes '() :type list)
  (storage-reads '() :type list)
  (balance-changes '() :type list)
  (nonce-changes '() :type list)
  (code-changes '() :type list))

(defstruct (block-access-storage-write
            (:constructor make-block-access-storage-write
                (&key tx-index value-after)))
  tx-index
  value-after)

(defstruct (block-access-slot-writes
            (:constructor make-block-access-slot-writes
                (&key slot (accesses '()))))
  slot
  (accesses '() :type list))

(defstruct (block-access-balance-change
            (:constructor make-block-access-balance-change
                (&key tx-index balance)))
  tx-index
  balance)

(defstruct (block-access-nonce-change
            (:constructor make-block-access-nonce-change
                (&key tx-index nonce)))
  tx-index
  nonce)

(defstruct (block-access-code-change
            (:constructor make-block-access-code-change
                (&key tx-index code)))
  tx-index
  code)

(defun hash32-uint256 (hash)
  (bytes-to-integer (hash32-bytes hash)))

(defun block-access-storage-write-rlp-object (write)
  (make-rlp-list
   (block-access-storage-write-tx-index write)
   (block-access-storage-write-value-after write)))

(defun block-access-slot-writes-rlp-object (slot-writes)
  (make-rlp-list
   (hash32-uint256 (block-access-slot-writes-slot slot-writes))
   (apply #'make-rlp-list
          (mapcar #'block-access-storage-write-rlp-object
                  (block-access-slot-writes-accesses slot-writes)))))

(defun block-access-balance-change-rlp-object (change)
  (make-rlp-list
   (block-access-balance-change-tx-index change)
   (block-access-balance-change-balance change)))

(defun block-access-nonce-change-rlp-object (change)
  (make-rlp-list
   (block-access-nonce-change-tx-index change)
   (block-access-nonce-change-nonce change)))

(defun block-access-code-change-rlp-object (change)
  (make-rlp-list
   (block-access-code-change-tx-index change)
   (ensure-byte-vector (block-access-code-change-code change))))

(defun block-access-account-rlp-object (account)
  (make-rlp-list
   (address-bytes (block-access-account-address account))
   (mapcar #'block-access-slot-writes-rlp-object
           (block-access-account-storage-writes account))
   (mapcar #'hash32-uint256 (block-access-account-storage-reads account))
   (mapcar #'block-access-balance-change-rlp-object
           (block-access-account-balance-changes account))
   (mapcar #'block-access-nonce-change-rlp-object
           (block-access-account-nonce-changes account))
   (mapcar #'block-access-code-change-rlp-object
           (block-access-account-code-changes account))))

(defun block-access-account-rlp (account)
  (rlp-encode (block-access-account-rlp-object account)))

(defun block-access-list-rlp (block-access-list)
  (rlp-encode
   (apply #'make-rlp-list
          (mapcar #'block-access-account-rlp-object block-access-list))))

(defun require-block-access-rlp-list (value label)
  (unless (rlp-list-p value)
    (block-validation-fail "Block access list ~A must be an RLP list" label))
  (rlp-list-items value))

(defun require-block-access-rlp-list-fields (value count label)
  (let ((items (require-block-access-rlp-list value label)))
    (unless (= (length items) count)
      (block-validation-fail "Block access list ~A must contain ~D fields"
                             label count))
    items))

(defun require-block-access-rlp-bytes (value label)
  (unless (byte-vector-p value)
    (block-validation-fail "Block access list ~A must be RLP bytes" label))
  value)

(defun block-access-address-from-rlp-bytes (value label)
  (let ((bytes (require-block-access-rlp-bytes value label)))
    (unless (= (length bytes) 20)
      (block-validation-fail "Block access list ~A must be exactly 20 bytes"
                             label))
    (make-address bytes)))

(defun block-access-rlp-uint (value label)
  (bytes-to-integer (require-block-access-rlp-bytes value label)))

(defun uint256-to-hash32 (value label)
  (unless (uint256-p value)
    (block-validation-fail "Block access list ~A must be uint256" label))
  (let* ((bytes (integer-to-minimal-bytes value))
         (out (make-byte-vector 32)))
    (replace out bytes :start1 (- 32 (length bytes)))
    (make-hash32 out)))

(defun decode-block-access-storage-write-rlp-object (value)
  (let ((items (require-block-access-rlp-list-fields value 2
                                                     "storage write")))
    (make-block-access-storage-write
     :tx-index (block-access-rlp-uint (first items) "storage write tx index")
     :value-after (block-access-rlp-uint (second items)
                                         "storage write value-after"))))

(defun decode-block-access-slot-writes-rlp-object (value)
  (let ((items (require-block-access-rlp-list-fields value 2
                                                     "storage writes entry")))
    (make-block-access-slot-writes
     :slot (uint256-to-hash32
            (block-access-rlp-uint (first items) "storage write slot")
            "storage write slot")
     :accesses
     (mapcar #'decode-block-access-storage-write-rlp-object
             (require-block-access-rlp-list (second items)
                                            "storage write accesses")))))

(defun decode-block-access-balance-change-rlp-object (value)
  (let ((items (require-block-access-rlp-list-fields value 2
                                                     "balance change")))
    (make-block-access-balance-change
     :tx-index (block-access-rlp-uint (first items) "balance change tx index")
     :balance (block-access-rlp-uint (second items)
                                     "balance change balance"))))

(defun decode-block-access-nonce-change-rlp-object (value)
  (let ((items (require-block-access-rlp-list-fields value 2
                                                     "nonce change")))
    (make-block-access-nonce-change
     :tx-index (block-access-rlp-uint (first items) "nonce change tx index")
     :nonce (block-access-rlp-uint (second items) "nonce change nonce"))))

(defun decode-block-access-code-change-rlp-object (value)
  (let ((items (require-block-access-rlp-list-fields value 2
                                                     "code change")))
    (make-block-access-code-change
     :tx-index (block-access-rlp-uint (first items) "code change tx index")
     :code (require-block-access-rlp-bytes (second items)
                                           "code change code"))))

(defun decode-block-access-account-rlp-object (value)
  (let ((items (require-block-access-rlp-list-fields value 6 "account")))
    (make-block-access-account
     :address (block-access-address-from-rlp-bytes (first items)
                                                   "account address")
     :storage-writes
     (mapcar #'decode-block-access-slot-writes-rlp-object
             (require-block-access-rlp-list (second items)
                                            "storage writes"))
     :storage-reads
     (mapcar (lambda (slot)
               (uint256-to-hash32
                (block-access-rlp-uint slot "storage read")
                "storage read"))
             (require-block-access-rlp-list (third items)
                                            "storage reads"))
     :balance-changes
     (mapcar #'decode-block-access-balance-change-rlp-object
             (require-block-access-rlp-list (fourth items)
                                            "balance changes"))
     :nonce-changes
     (mapcar #'decode-block-access-nonce-change-rlp-object
             (require-block-access-rlp-list (fifth items)
                                            "nonce changes"))
     :code-changes
     (mapcar #'decode-block-access-code-change-rlp-object
             (require-block-access-rlp-list (sixth items)
                                            "code changes")))))

(defun decode-block-access-list-rlp-object (value)
  (mapcar #'decode-block-access-account-rlp-object
          (require-block-access-rlp-list value "root")))

(defun block-access-list-hash (block-access-list)
  (validate-block-access-list-fields block-access-list)
  (keccak-256-hash (block-access-list-rlp block-access-list)))

(define-condition block-validation-error (error)
  ((message :initarg :message :reader block-validation-error-message))
  (:report (lambda (condition stream)
             (format stream "~A" (block-validation-error-message condition)))))

(defun block-validation-fail (control &rest args)
  (error 'block-validation-error
         :message (apply #'format nil control args)))

(defun block-access-list-rlp-input-bytes (bytes)
  (handler-case
      (ensure-byte-vector bytes)
    (error ()
      (block-validation-fail
       "Block access list RLP must be a byte sequence"))))

(defun block-access-list-from-rlp
    (bytes &key max-code-size max-items)
  (let ((bytes (block-access-list-rlp-input-bytes bytes)))
    (handler-case
        (let ((access-list (decode-block-access-list-rlp-object
                            (rlp-decode-one bytes))))
          (validate-block-access-list-fields access-list
                                             :max-code-size max-code-size
                                             :max-items max-items)
          access-list)
      (block-validation-error (condition)
        (error condition))
      (rlp-error (condition)
        (block-validation-fail "Invalid block access list RLP: ~A" condition)))))

(defun block-access-list-rlp-hash
    (bytes &key max-code-size max-items)
  (let ((bytes (block-access-list-rlp-input-bytes bytes)))
    (block-access-list-from-rlp bytes
                                :max-code-size max-code-size
                                :max-items max-items)
    (keccak-256-hash bytes)))

(defun validated-block-access-list-commitment
    (block &key max-code-size max-items)
  (let ((access-list (block-block-access-list block))
        (encoded (block-encoded-block-access-list block)))
    (validate-block-access-list-fields access-list
                                       :max-code-size max-code-size
                                       :max-items max-items)
    (if encoded
        (let ((decoded (block-access-list-from-rlp
                        encoded
                        :max-code-size max-code-size
                        :max-items max-items)))
          (unless (bytes= (block-access-list-rlp decoded)
                          (block-access-list-rlp access-list))
            (block-validation-fail
             "Encoded block access list does not match block access list body"))
          (keccak-256-hash encoded))
        (block-access-list-hash access-list))))

(defun validate-byte-sequence-field (value label &key size)
  (let ((bytes (handler-case
                   (ensure-byte-vector value)
                 (error ()
                   (block-validation-fail "~A must be a byte sequence"
                                          label)))))
    (when (and size (/= size (length bytes)))
      (block-validation-fail "~A must be exactly ~D bytes" label size))
    bytes))

(defun validate-optional-hash32-field (value label)
  (when (and value (not (hash32-p value)))
    (block-validation-fail "~A must be a hash32" label))
  t)

(defun validate-optional-address-field (value label)
  (when (and value (not (address-p value)))
    (block-validation-fail "~A must be an address" label))
  t)

(defun validate-optional-uint256-field (value label)
  (when (and value (not (uint256-p value)))
    (block-validation-fail "~A must be uint256" label))
  t)

(defun validate-optional-uint64-field (value label)
  (when (and value
             (not (and (integerp value)
                       (<= 0 value)
                       (< value (expt 2 64)))))
    (block-validation-fail "~A must be uint64" label))
  t)

(defun validate-execution-request-fields (request)
  (let ((bytes (handler-case
                   (ensure-byte-vector request)
                 (error ()
                   (block-validation-fail
                    "Execution request must be a byte vector")))))
    (when (zerop (length bytes))
      (block-validation-fail "Execution request is missing request type"))
    bytes))

(defun validate-execution-request-list-fields (requests)
  (unless (listp requests)
    (block-validation-fail "Execution requests must be a list"))
  (loop with previous-type = nil
        for request in requests
        for bytes = (validate-execution-request-fields request)
        for request-type = (aref bytes 0)
        do (when (< (length bytes) 2)
             (block-validation-fail
              "Execution request must contain request type and payload"))
           (when (and previous-type
                      (<= request-type previous-type))
             (block-validation-fail
              "Execution requests must be ordered by unique request type"))
           (setf previous-type request-type)
        finally (return t)))

(defun byte-vector-lexicographic< (left right)
  (let ((left (ensure-byte-vector left))
        (right (ensure-byte-vector right)))
    (loop for index below (min (length left) (length right))
          for left-byte = (aref left index)
          for right-byte = (aref right index)
          when (< left-byte right-byte)
            do (return t)
          when (> left-byte right-byte)
            do (return nil)
          finally (return (< (length left) (length right))))))

(defun uint32-value-p (value)
  (and (integerp value)
       (<= 0 value)
       (< value (expt 2 32))))

(defun validate-block-access-storage-write-fields (write)
  (unless (block-access-storage-write-p write)
    (block-validation-fail
     "Block access list storage write must be a storage write"))
  (unless (uint32-value-p (block-access-storage-write-tx-index write))
    (block-validation-fail "Block access list storage write tx index must be uint32"))
  (unless (uint256-p (block-access-storage-write-value-after write))
    (block-validation-fail
     "Block access list storage write value-after must be uint256"))
  t)

(defun validate-block-access-slot-writes-fields (slot-writes)
  (unless (block-access-slot-writes-p slot-writes)
    (block-validation-fail
     "Block access list storage writes entry must be slot writes"))
  (unless (hash32-p (block-access-slot-writes-slot slot-writes))
    (block-validation-fail "Block access list storage write slot must be a hash32"))
  (unless (listp (block-access-slot-writes-accesses slot-writes))
    (block-validation-fail
     "Block access list storage write accesses must be a list"))
  (when (null (block-access-slot-writes-accesses slot-writes))
    (block-validation-fail
     "Block access list storage write slot must contain at least one access"))
  (let ((previous-tx-index nil))
    (dolist (write (block-access-slot-writes-accesses slot-writes))
      (validate-block-access-storage-write-fields write)
      (let ((tx-index (block-access-storage-write-tx-index write)))
        (when (and previous-tx-index
                   (<= tx-index previous-tx-index))
          (block-validation-fail
           "Block access list storage write tx indices must be sorted"))
        (setf previous-tx-index tx-index))))
  t)

(defun validate-block-access-balance-change-fields (change)
  (unless (block-access-balance-change-p change)
    (block-validation-fail
     "Block access list balance change must be a balance change"))
  (unless (uint32-value-p (block-access-balance-change-tx-index change))
    (block-validation-fail
     "Block access list balance change tx index must be uint32"))
  (unless (uint256-p (block-access-balance-change-balance change))
    (block-validation-fail
     "Block access list balance change balance must be uint256"))
  t)

(defun validate-block-access-nonce-change-fields (change)
  (unless (block-access-nonce-change-p change)
    (block-validation-fail
     "Block access list nonce change must be a nonce change"))
  (unless (uint32-value-p (block-access-nonce-change-tx-index change))
    (block-validation-fail
     "Block access list nonce change tx index must be uint32"))
  (unless (uint64-value-p (block-access-nonce-change-nonce change))
    (block-validation-fail
     "Block access list nonce change nonce must be uint64"))
  t)

(defun validate-block-access-code-change-fields (change &key max-code-size)
  (unless (block-access-code-change-p change)
    (block-validation-fail
     "Block access list code change must be a code change"))
  (unless (uint32-value-p (block-access-code-change-tx-index change))
    (block-validation-fail
     "Block access list code change tx index must be uint32"))
  (let ((code (validate-byte-sequence-field
               (block-access-code-change-code change)
               "Block access list code change code")))
    (when (and max-code-size
               (> (length code) max-code-size))
      (block-validation-fail
       "Block access list code change exceeds maximum code size")))
  t)

(defun validate-block-access-indexed-change-list
    (changes validate-change tx-index-fn label)
  (unless (listp changes)
    (block-validation-fail "Block access list ~A must be a list" label))
  (let ((previous-tx-index nil))
    (dolist (change changes)
      (funcall validate-change change)
      (let ((tx-index (funcall tx-index-fn change)))
        (when (and previous-tx-index
                   (<= tx-index previous-tx-index))
          (block-validation-fail
           "Block access list ~A tx indices must be sorted" label))
        (setf previous-tx-index tx-index))))
  t)

(defun validate-block-access-account-fields (account &key max-code-size)
  (unless (block-access-account-p account)
    (block-validation-fail
     "Block access list account must be a block access account"))
  (unless (address-p (block-access-account-address account))
    (block-validation-fail "Block access list account address must be an address"))
  (unless (listp (block-access-account-storage-writes account))
    (block-validation-fail "Block access list storage writes must be a list"))
  (unless (listp (block-access-account-storage-reads account))
    (block-validation-fail "Block access list storage reads must be a list"))
  (validate-block-access-indexed-change-list
   (block-access-account-balance-changes account)
   #'validate-block-access-balance-change-fields
   #'block-access-balance-change-tx-index
   "balance changes")
  (validate-block-access-indexed-change-list
   (block-access-account-nonce-changes account)
   #'validate-block-access-nonce-change-fields
   #'block-access-nonce-change-tx-index
   "nonce changes")
  (validate-block-access-indexed-change-list
   (block-access-account-code-changes account)
   (lambda (change)
     (validate-block-access-code-change-fields
      change
      :max-code-size max-code-size))
   #'block-access-code-change-tx-index
   "code changes")
  (let ((previous-slot-bytes nil)
        (write-slot-table (make-hash-table :test #'equal)))
    (dolist (slot-writes (block-access-account-storage-writes account))
      (validate-block-access-slot-writes-fields slot-writes)
      (let* ((slot (block-access-slot-writes-slot slot-writes))
             (slot-bytes (hash32-bytes slot)))
        (when (and previous-slot-bytes
                   (not (byte-vector-lexicographic< previous-slot-bytes
                                                    slot-bytes)))
          (block-validation-fail
           "Block access list storage write slots must be sorted"))
        (setf (gethash (bytes-to-hex slot-bytes :prefix nil) write-slot-table)
              t)
        (setf previous-slot-bytes slot-bytes)))
    (setf previous-slot-bytes nil)
    (dolist (slot (block-access-account-storage-reads account))
      (unless (hash32-p slot)
        (block-validation-fail "Block access list storage read must be a hash32"))
      (let ((slot-bytes (hash32-bytes slot)))
        (when (and previous-slot-bytes
                   (not (byte-vector-lexicographic< previous-slot-bytes
                                                    slot-bytes)))
          (block-validation-fail
           "Block access list storage reads must be sorted"))
        (when (gethash (bytes-to-hex slot-bytes :prefix nil) write-slot-table)
          (block-validation-fail
           "Block access list storage read duplicates a storage write slot"))
        (setf previous-slot-bytes slot-bytes))))
  t)

(defun block-access-list-item-count (block-access-list)
  (unless (listp block-access-list)
    (block-validation-fail "Block access list must be a list"))
  (loop for account in block-access-list
        do (unless (block-access-account-p account)
             (block-validation-fail
              "Block access list account must be a block access account"))
        sum (+ 1
               (length (block-access-account-storage-writes account))
               (length (block-access-account-storage-reads account)))))

(defun validate-block-access-list-fields
    (block-access-list &key max-code-size max-items)
  (unless (listp block-access-list)
    (block-validation-fail "Block access list must be a list"))
  (let ((previous-address-bytes nil)
        (item-count 0))
    (dolist (account block-access-list)
      (validate-block-access-account-fields account
                                            :max-code-size max-code-size)
      (incf item-count
            (+ 1
               (length (block-access-account-storage-writes account))
               (length (block-access-account-storage-reads account))))
      (let ((address-bytes (address-bytes
                            (block-access-account-address account))))
        (when (and previous-address-bytes
                   (not (byte-vector-lexicographic< previous-address-bytes
                                                    address-bytes)))
          (block-validation-fail
           "Block access list account addresses must be sorted"))
        (setf previous-address-bytes address-bytes)))
    (when (and max-items
               (> item-count max-items))
      (block-validation-fail
       "Block access list item count exceeds gas limit")))
  t)

(defun expected-base-fee-per-gas
    (parent-header &key (london-parent-p t)
                        (elasticity-multiplier
                         +base-fee-elasticity-multiplier+)
                        (change-denominator
                         +base-fee-change-denominator+))
  (if (not london-parent-p)
      +initial-base-fee+
      (let* ((parent-base-fee (block-header-base-fee-per-gas parent-header))
             (parent-gas-limit (block-header-gas-limit parent-header))
             (parent-gas-used (block-header-gas-used parent-header))
             (parent-gas-target (floor parent-gas-limit
                                       elasticity-multiplier)))
        (unless parent-base-fee
          (block-validation-fail "Parent header is missing base fee"))
        (cond
          ((or (zerop parent-gas-target) (zerop change-denominator))
           parent-base-fee)
          ((= parent-gas-used parent-gas-target)
           parent-base-fee)
          ((> parent-gas-used parent-gas-target)
           (let* ((gas-delta (- parent-gas-used parent-gas-target))
                  (fee-delta (floor (* parent-base-fee gas-delta)
                                    (* parent-gas-target
                                       change-denominator))))
             (+ parent-base-fee (max 1 fee-delta))))
          (t
           (let* ((gas-delta (- parent-gas-target parent-gas-used))
                  (fee-delta (floor (* parent-base-fee gas-delta)
                                    (* parent-gas-target
                                       change-denominator))))
             (max 0 (- parent-base-fee fee-delta))))))))

(defun validate-block-base-fee (parent-header header &key (london-parent-p t))
  (unless (block-header-base-fee-per-gas header)
    (block-validation-fail "Header is missing base fee"))
  (let ((expected (expected-base-fee-per-gas
                   parent-header :london-parent-p london-parent-p)))
    (unless (= expected (block-header-base-fee-per-gas header))
      (block-validation-fail "Base fee mismatch"))
    t))

(defun validate-gas-limit-delta
    (parent-gas-limit header-gas-limit
     &key (bound-divisor +gas-limit-bound-divisor+)
          (minimum-gas-limit +minimum-gas-limit+))
  (let ((limit (floor parent-gas-limit bound-divisor))
        (diff (abs (- parent-gas-limit header-gas-limit))))
    (when (>= diff limit)
      (block-validation-fail "Gas limit changed too much"))
    (when (< header-gas-limit minimum-gas-limit)
      (block-validation-fail "Gas limit below minimum"))
    t))

(defun adjusted-parent-gas-limit-for-1559 (parent-header london-parent-p)
  (let ((parent-gas-limit (block-header-gas-limit parent-header)))
    (if london-parent-p
        parent-gas-limit
        (* parent-gas-limit +base-fee-elasticity-multiplier+))))

(defun validate-block-blob-gas-fields
    (header &key (blob-gas-enabled-p
                  (or (block-header-blob-gas-used header)
                      (block-header-excess-blob-gas header)))
                 (max-blob-gas (* +max-blobs-per-block+
                                  +blob-gas-per-blob+)))
  (cond
    (blob-gas-enabled-p
     (unless (block-header-blob-gas-used header)
       (block-validation-fail "Header is missing blob gas used"))
     (unless (block-header-excess-blob-gas header)
       (block-validation-fail "Header is missing excess blob gas"))
     (when (and max-blob-gas
                (> (block-header-blob-gas-used header) max-blob-gas))
       (block-validation-fail "Blob gas used exceeds maximum"))
     (unless (zerop (mod (block-header-blob-gas-used header)
                         +blob-gas-per-blob+))
       (block-validation-fail "Blob gas used is not a blob-sized multiple")))
    ((or (block-header-blob-gas-used header)
         (block-header-excess-blob-gas header))
     (block-validation-fail "Blob gas fields present before Cancun")))
  t)

(defun expected-excess-blob-gas
    (parent-header &key (target-blob-gas
                         (* +target-blobs-per-block+
                            +blob-gas-per-blob+))
                        (max-blob-gas
                         (* +max-blobs-per-block+
                            +blob-gas-per-blob+))
                        eip7918-p
                        (update-fraction
                         +blob-base-fee-update-fraction+))
  (let* ((parent-excess (or (block-header-excess-blob-gas parent-header) 0))
         (parent-used (or (block-header-blob-gas-used parent-header) 0))
         (parent-blob-gas (+ parent-excess parent-used)))
    (cond
      ((< parent-blob-gas target-blob-gas) 0)
      ((and eip7918-p
            (block-header-base-fee-per-gas parent-header)
            (> (* +blob-base-cost+
                  (block-header-base-fee-per-gas parent-header))
               (* +blob-gas-per-blob+
                  (blob-base-fee parent-excess
                                 :update-fraction update-fraction))))
       (+ parent-excess
          (floor (* parent-used (- max-blob-gas target-blob-gas))
                 max-blob-gas)))
      (t (- parent-blob-gas target-blob-gas)))))

(defun fake-exponential (factor numerator denominator)
  (let ((output 0)
        (accumulator (* factor denominator)))
    (loop for i from 1
          while (plusp accumulator)
          do (incf output accumulator)
             (setf accumulator
                   (floor (* accumulator numerator)
                          (* denominator i))))
    (floor output denominator)))

(defun blob-base-fee
    (excess-blob-gas &key (min-blob-gas-price +min-blob-gas-price+)
                          (update-fraction
                           +blob-base-fee-update-fraction+))
  (fake-exponential min-blob-gas-price
                    excess-blob-gas
                    update-fraction))

(defun block-header-blob-base-fee
    (header &key (update-fraction +blob-base-fee-update-fraction+))
  (unless (block-header-excess-blob-gas header)
    (block-validation-fail "Header is missing excess blob gas"))
  (blob-base-fee (block-header-excess-blob-gas header)
                 :update-fraction update-fraction))

(defun validate-block-excess-blob-gas
    (parent-header header &key (target-blob-gas
                                (* +target-blobs-per-block+
                                   +blob-gas-per-blob+))
                              (max-blob-gas
                               (* +max-blobs-per-block+
                                  +blob-gas-per-blob+))
                              eip7918-p
                              (update-fraction
                               +blob-base-fee-update-fraction+))
  (validate-block-blob-gas-fields header :max-blob-gas max-blob-gas)
  (let ((expected (expected-excess-blob-gas
                   parent-header
                   :target-blob-gas target-blob-gas
                   :max-blob-gas max-blob-gas
                   :eip7918-p eip7918-p
                   :update-fraction update-fraction)))
    (unless (= expected (block-header-excess-blob-gas header))
      (block-validation-fail "Excess blob gas mismatch"))
    t))

(defun block-header-cancun-fields-present-p (header)
  (or (block-header-blob-gas-used header)
      (block-header-excess-blob-gas header)))

(defun validate-block-cancun-fields (header &key (cancun-enabled-p
                                                  (block-header-cancun-fields-present-p
                                                   header)))
  (if cancun-enabled-p
      (unless (block-header-parent-beacon-root header)
        (block-validation-fail "Header is missing parent beacon root"))
      (when (block-header-parent-beacon-root header)
        (block-validation-fail "Parent beacon root present before Cancun")))
  t)

(defun validate-block-withdrawals-field
    (header &key (withdrawals-enabled-p (block-header-withdrawals-root header)))
  (if withdrawals-enabled-p
      (unless (block-header-withdrawals-root header)
        (block-validation-fail "Header is missing withdrawals root"))
      (when (block-header-withdrawals-root header)
        (block-validation-fail "Withdrawals root present before Shanghai")))
  t)

(defun validate-block-requests-hash-field
    (header &key (requests-enabled-p (block-header-requests-hash header)))
  (if requests-enabled-p
      (unless (block-header-requests-hash header)
        (block-validation-fail "Header is missing requests hash"))
      (when (block-header-requests-hash header)
        (block-validation-fail "Requests hash present before Prague")))
  t)

(defun block-header-amsterdam-fields-present-p (header)
  (or (block-header-block-access-list-hash header)
      (block-header-slot-number header)))

(defun validate-block-amsterdam-fields
    (header &key (amsterdam-enabled-p
                  (block-header-amsterdam-fields-present-p header)))
  (if amsterdam-enabled-p
      (progn
        (unless (block-header-block-access-list-hash header)
          (block-validation-fail
           "Header is missing block access list hash"))
        (unless (block-header-slot-number header)
          (block-validation-fail "Header is missing slot number")))
      (progn
        (when (block-header-block-access-list-hash header)
          (block-validation-fail
           "Block access list hash present before Amsterdam"))
        (when (block-header-slot-number header)
          (block-validation-fail "Slot number present before Amsterdam"))))
  t)

(defun validate-block-amsterdam-slot-number (parent-header header)
  (let ((parent-slot-number (block-header-slot-number parent-header))
        (slot-number (block-header-slot-number header)))
    (when (and parent-slot-number
               slot-number
               (<= slot-number parent-slot-number))
      (block-validation-fail
       "Amsterdam header slot number must exceed parent slot number")))
  t)

(defun block-header-post-merge-p (header)
  (and (plusp (block-header-number header))
       (zerop (block-header-difficulty header))))

(defun block-header-zero-nonce-p (header)
  (let ((nonce (block-header-nonce header)))
    (or (null nonce)
        (let ((bytes (ensure-byte-vector nonce)))
          (and (= 8 (length bytes))
               (every #'zerop bytes))))))

(defun validate-block-merge-transition (parent-header header)
  (when (and (block-header-post-merge-p parent-header)
             (plusp (block-header-difficulty header)))
    (block-validation-fail "Cannot revert from post-Merge to PoW difficulty"))
  t)

(defun validate-block-merge-fields
    (header &key (post-merge-p (block-header-post-merge-p header)))
  (when post-merge-p
    (unless (zerop (block-header-difficulty header))
      (block-validation-fail "Post-Merge header difficulty must be zero"))
    (unless (block-header-zero-nonce-p header)
      (block-validation-fail "Post-Merge header nonce must be zero"))
    (unless (hash32= (or (block-header-ommers-hash header) +empty-ommers-hash+)
                     +empty-ommers-hash+)
      (block-validation-fail "Post-Merge header ommers hash must be empty"))
    (when (> (block-header-gas-limit header) +max-header-gas-limit+)
      (block-validation-fail "Post-Merge header gas limit exceeds maximum")))
  t)

(defun validate-block-header-field-shapes
    (header &key require-parent-hash-p)
  (unless (block-header-p header)
    (block-validation-fail "Block header must be a block header"))
  (if require-parent-hash-p
      (unless (hash32-p (block-header-parent-hash header))
        (block-validation-fail "Header parent hash must be a hash32"))
      (validate-optional-hash32-field (block-header-parent-hash header)
                                      "Header parent hash"))
  (validate-optional-hash32-field (block-header-ommers-hash header)
                                  "Header ommers hash")
  (validate-optional-address-field (block-header-beneficiary header)
                                   "Header beneficiary")
  (validate-optional-hash32-field (block-header-state-root header)
                                  "Header state root")
  (validate-optional-hash32-field (block-header-transactions-root header)
                                  "Header transactions root")
  (validate-optional-hash32-field (block-header-receipts-root header)
                                  "Header receipts root")
  (when (block-header-logs-bloom header)
    (validate-byte-sequence-field (block-header-logs-bloom header)
                                  "Header logs bloom"
                                  :size 256))
  (unless (uint256-p (block-header-difficulty header))
    (block-validation-fail "Header difficulty must be uint256"))
  (unless (uint256-p (block-header-number header))
    (block-validation-fail "Header number must be uint256"))
  (unless (uint256-p (block-header-gas-limit header))
    (block-validation-fail "Header gas limit must be uint256"))
  (unless (uint256-p (block-header-gas-used header))
    (block-validation-fail "Header gas used must be uint256"))
  (unless (uint256-p (block-header-timestamp header))
    (block-validation-fail "Header timestamp must be uint256"))
  (validate-byte-sequence-field (block-header-extra-data header)
                                "Header extra data")
  (validate-optional-hash32-field (block-header-mix-hash header)
                                  "Header mix hash")
  (when (block-header-nonce header)
    (validate-byte-sequence-field (block-header-nonce header)
                                  "Header nonce"
                                  :size 8))
  (validate-optional-uint256-field (block-header-base-fee-per-gas header)
                                   "Header base fee")
  (validate-optional-hash32-field (block-header-withdrawals-root header)
                                  "Header withdrawals root")
  (validate-optional-uint256-field (block-header-blob-gas-used header)
                                   "Header blob gas used")
  (validate-optional-uint256-field (block-header-excess-blob-gas header)
                                   "Header excess blob gas")
  (validate-optional-hash32-field (block-header-parent-beacon-root header)
                                  "Header parent beacon root")
  (validate-optional-hash32-field (block-header-requests-hash header)
                                  "Header requests hash")
  (validate-optional-hash32-field (block-header-block-access-list-hash header)
                                  "Header block access list hash")
  (validate-optional-uint64-field (block-header-slot-number header)
                                  "Header slot number")
  t)

(defun validate-block-header-basics
    (parent-header header &key (validate-base-fee-p nil
                                validate-base-fee-p-supplied-p)
                         (london-parent-p t)
                         (withdrawals-enabled-p nil
                          withdrawals-enabled-p-supplied-p)
                         (cancun-enabled-p nil
                          cancun-enabled-p-supplied-p)
                         (requests-enabled-p nil
                          requests-enabled-p-supplied-p)
                         (amsterdam-enabled-p nil
                          amsterdam-enabled-p-supplied-p)
                         (osaka-enabled-p nil)
                         (expanded-blob-schedule-p nil
                          expanded-blob-schedule-p-supplied-p)
                         blob-schedule-target-gas
                         blob-schedule-max-gas
                         blob-schedule-update-fraction
                         (post-merge-p nil post-merge-p-supplied-p))
  (validate-block-header-field-shapes parent-header)
  (validate-block-header-field-shapes header :require-parent-hash-p t)
  (let ((validate-base-fee-p
          (if validate-base-fee-p-supplied-p
              validate-base-fee-p
              (block-header-base-fee-per-gas header)))
        (withdrawals-enabled-p
          (if withdrawals-enabled-p-supplied-p
              withdrawals-enabled-p
              (block-header-withdrawals-root header)))
        (cancun-enabled-p
          (if cancun-enabled-p-supplied-p
              cancun-enabled-p
              (block-header-cancun-fields-present-p header)))
        (requests-enabled-p
          (if requests-enabled-p-supplied-p
              requests-enabled-p
              (block-header-requests-hash header)))
        (amsterdam-enabled-p
          (if amsterdam-enabled-p-supplied-p
              amsterdam-enabled-p
              (block-header-amsterdam-fields-present-p header)))
        (expanded-blob-schedule-p
          (if expanded-blob-schedule-p-supplied-p
              expanded-blob-schedule-p
              osaka-enabled-p))
        (post-merge-p
          (if post-merge-p-supplied-p
              post-merge-p
              (block-header-post-merge-p header))))
    (unless (hash32= (block-header-parent-hash header)
                     (block-header-hash parent-header))
      (block-validation-fail "Parent hash mismatch"))
    (validate-block-merge-transition parent-header header)
    (validate-block-merge-fields header :post-merge-p post-merge-p)
    (unless (= (block-header-number header)
               (1+ (block-header-number parent-header)))
      (block-validation-fail "Block number is not parent plus one"))
    (unless (> (block-header-timestamp header)
               (block-header-timestamp parent-header))
      (block-validation-fail "Timestamp is not greater than parent timestamp"))
    (when (> (block-header-gas-used header)
             (block-header-gas-limit header))
      (block-validation-fail "Gas used exceeds gas limit"))
    (validate-gas-limit-delta (adjusted-parent-gas-limit-for-1559
                               parent-header
                               london-parent-p)
                              (block-header-gas-limit header))
    (when (> (length (ensure-byte-vector (block-header-extra-data header)))
             +maximum-extra-data-size+)
      (block-validation-fail "Extra data too long"))
    (if cancun-enabled-p
        (let ((target-blob-gas
                (or blob-schedule-target-gas
                    (* (if expanded-blob-schedule-p
                           +osaka-target-blobs-per-block+
                           +target-blobs-per-block+)
                       +blob-gas-per-blob+)))
              (max-blob-gas
                (or blob-schedule-max-gas
                    (* (if expanded-blob-schedule-p
                           +osaka-max-blobs-per-block+
                           +max-blobs-per-block+)
                       +blob-gas-per-blob+)))
              (update-fraction
                (or blob-schedule-update-fraction
                    (if expanded-blob-schedule-p
                        +osaka-blob-base-fee-update-fraction+
                        +blob-base-fee-update-fraction+))))
          (validate-block-cancun-fields header :cancun-enabled-p t)
          (validate-block-excess-blob-gas
           parent-header header
           :target-blob-gas target-blob-gas
           :max-blob-gas max-blob-gas
           :eip7918-p osaka-enabled-p
           :update-fraction update-fraction))
        (progn
          (validate-block-cancun-fields header :cancun-enabled-p nil)
          (validate-block-blob-gas-fields header)))
    (validate-block-withdrawals-field
     header :withdrawals-enabled-p withdrawals-enabled-p)
    (validate-block-requests-hash-field
     header :requests-enabled-p requests-enabled-p)
    (validate-block-amsterdam-fields
     header :amsterdam-enabled-p amsterdam-enabled-p)
    (when amsterdam-enabled-p
      (validate-block-amsterdam-slot-number parent-header header))
    (when validate-base-fee-p
      (validate-block-base-fee parent-header header
                               :london-parent-p london-parent-p)))
  t)

(defun validate-block-header-against-config (parent-header header config)
  (let ((number (block-header-number header))
        (timestamp (block-header-timestamp header)))
    (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
        (chain-config-blob-schedule config number timestamp)
      (validate-block-header-basics
       parent-header header
       :validate-base-fee-p (chain-config-london-p config number)
       :london-parent-p (chain-config-london-p
                         config (block-header-number parent-header))
       :withdrawals-enabled-p (chain-config-shanghai-p config number timestamp)
       :cancun-enabled-p (chain-config-cancun-p config number timestamp)
       :requests-enabled-p (chain-config-prague-p config number timestamp)
       :amsterdam-enabled-p (chain-config-amsterdam-p config number timestamp)
       :osaka-enabled-p (chain-config-osaka-p config number timestamp)
       :expanded-blob-schedule-p
       (chain-config-expanded-blob-schedule-p config number timestamp)
       :blob-schedule-target-gas target-blob-gas
       :blob-schedule-max-gas max-blob-gas
       :blob-schedule-update-fraction update-fraction
       :post-merge-p (block-header-post-merge-p header)))))

(defun hash32= (left right)
  (and left
       right
       (bytes= (hash32-bytes left) (hash32-bytes right))))

(defun validate-blob-versioned-hash (hash)
  (when (null hash)
    (block-validation-fail "Missing blob versioned hash"))
  (let ((bytes (handler-case
                   (etypecase hash
                     (hash32 (hash32-bytes hash))
                     (byte-vector (ensure-byte-vector hash))
                     (vector (ensure-byte-vector hash)))
                 (error ()
                   (block-validation-fail "Invalid blob versioned hash")))))
    (unless (= 32 (length bytes))
      (block-validation-fail "Invalid blob versioned hash size"))
    (unless (= +kzg-commitment-version+ (aref bytes 0))
      (block-validation-fail "Invalid blob versioned hash version"))
    t))

(defun validate-blob-transaction-fields
    (transaction &key (min-blobs +min-blobs-per-transaction+)
                      (max-blobs +max-blobs-per-block+))
  (let* ((hashes (blob-transaction-blob-versioned-hashes transaction))
         (count (length hashes)))
    (unless (blob-transaction-to transaction)
      (block-validation-fail "Blob transaction cannot create contracts"))
    (when (< count min-blobs)
      (block-validation-fail "Blob transaction missing blob hashes"))
    (when (and max-blobs (> count max-blobs))
      (block-validation-fail "Blob transaction has too many blob hashes"))
    (dolist (hash hashes t)
      (validate-blob-versioned-hash hash))))

(defun validate-blob-transaction-fee-cap (transaction blob-base-fee)
  (unless (uint256-p (blob-transaction-max-fee-per-blob-gas transaction))
    (block-validation-fail "Max fee per blob gas must be uint256"))
  (when (< (blob-transaction-max-fee-per-blob-gas transaction)
           blob-base-fee)
    (block-validation-fail "Max fee per blob gas below blob base fee"))
  t)

(defun validate-transaction-data-field (transaction)
  (handler-case
      (progn
        (ensure-byte-vector (transaction-data transaction))
        t)
    (error ()
      (block-validation-fail "Transaction data must be a byte sequence"))))

(defun validate-transaction-recipient-field (transaction)
  (handler-case
      (progn
        (transaction-to-bytes (transaction-to transaction))
        t)
    (error ()
      (block-validation-fail
       "Transaction recipient must be nil or a 20-byte value"))))

(defun uint64-value-p (value)
  (and (integerp value)
       (<= 0 value (1- (ash 1 64)))))

(defun validate-transaction-scalar-fields (transaction)
  (unless (uint64-value-p (transaction-nonce transaction))
    (block-validation-fail "Transaction nonce must be uint64"))
  (unless (uint64-value-p (transaction-gas-limit transaction))
    (block-validation-fail "Transaction gas limit must be uint64"))
  (unless (uint256-p (transaction-value transaction))
    (block-validation-fail "Transaction value must be uint256"))
  (let ((max-priority-fee (transaction-max-priority-fee-per-gas transaction))
        (max-fee (transaction-max-fee-per-gas transaction)))
    (unless (uint256-p max-priority-fee)
      (block-validation-fail "Max priority fee must be uint256"))
    (unless (uint256-p max-fee)
      (block-validation-fail "Max fee per gas must be uint256"))
    (when (< max-fee max-priority-fee)
      (block-validation-fail "Max priority fee exceeds max fee")))
  (when (typep transaction 'blob-transaction)
    (unless (uint256-p (blob-transaction-max-fee-per-blob-gas transaction))
      (block-validation-fail "Max fee per blob gas must be uint256")))
  t)

(defun validate-transaction-signature-fields (transaction)
  (etypecase transaction
    (legacy-transaction
     (unless (uint256-p (legacy-transaction-v transaction))
       (block-validation-fail "Transaction v must be uint256"))
     (unless (uint256-p (legacy-transaction-r transaction))
       (block-validation-fail "Transaction r must be uint256"))
     (unless (uint256-p (legacy-transaction-s transaction))
       (block-validation-fail "Transaction s must be uint256")))
    ((or access-list-transaction
         dynamic-fee-transaction
         blob-transaction
         set-code-transaction)
     (unless (uint256-p
              (etypecase transaction
                (access-list-transaction
                 (access-list-transaction-chain-id transaction))
                (dynamic-fee-transaction
                 (dynamic-fee-transaction-chain-id transaction))
                (blob-transaction
                 (blob-transaction-chain-id transaction))
                (set-code-transaction
                 (set-code-transaction-chain-id transaction))))
       (block-validation-fail "Transaction chain id must be uint256"))
     (unless (uint256-p
              (etypecase transaction
                (access-list-transaction
                 (access-list-transaction-y-parity transaction))
                (dynamic-fee-transaction
                 (dynamic-fee-transaction-y-parity transaction))
                (blob-transaction
                 (blob-transaction-y-parity transaction))
                (set-code-transaction
                 (set-code-transaction-y-parity transaction))))
       (block-validation-fail "Transaction y parity must be uint256"))
     (unless (uint256-p
              (etypecase transaction
                (access-list-transaction
                 (access-list-transaction-r transaction))
                (dynamic-fee-transaction
                 (dynamic-fee-transaction-r transaction))
                (blob-transaction
                 (blob-transaction-r transaction))
                (set-code-transaction
                 (set-code-transaction-r transaction))))
       (block-validation-fail "Transaction r must be uint256"))
     (unless (uint256-p
              (etypecase transaction
                (access-list-transaction
                 (access-list-transaction-s transaction))
                (dynamic-fee-transaction
                 (dynamic-fee-transaction-s transaction))
                (blob-transaction
                 (blob-transaction-s transaction))
                (set-code-transaction
                 (set-code-transaction-s transaction))))
       (block-validation-fail "Transaction s must be uint256"))))
  t)

(defun validate-access-list-fields (transaction)
  (dolist (entry (transaction-access-list transaction) t)
    (unless (typep entry 'access-list-entry)
      (block-validation-fail
       "Access list entry must be an access-list entry"))
    (unless (address-p (access-list-entry-address entry))
      (block-validation-fail "Access list entry address must be an address"))
    (unless (listp (access-list-entry-storage-keys entry))
      (block-validation-fail "Access list storage keys must be a list"))
    (dolist (slot (access-list-entry-storage-keys entry))
      (unless (hash32-p slot)
        (block-validation-fail "Access list storage key must be a hash32")))))

(defun validate-set-code-authorization-fields (authorization)
  (unless (typep authorization 'set-code-authorization)
    (block-validation-fail
     "Set-code authorization must be a set-code authorization"))
  (unless (uint256-p (set-code-authorization-chain-id authorization))
    (block-validation-fail "Authorization chain id must be uint256"))
  (unless (address-p (set-code-authorization-address authorization))
    (block-validation-fail "Authorization address must be an address"))
  (unless (and (integerp (set-code-authorization-nonce authorization))
               (<= 0 (set-code-authorization-nonce authorization)
                   (1- (ash 1 64))))
    (block-validation-fail "Authorization nonce must be uint64"))
  (unless (uint256-p (set-code-authorization-y-parity authorization))
    (block-validation-fail "Authorization y parity must be uint256"))
  (unless (uint256-p (set-code-authorization-r authorization))
    (block-validation-fail "Authorization r must be uint256"))
  (unless (uint256-p (set-code-authorization-s authorization))
    (block-validation-fail "Authorization s must be uint256"))
  t)

(defun validate-set-code-transaction-fields (transaction)
  (when (typep transaction 'set-code-transaction)
    (unless (transaction-to transaction)
      (block-validation-fail "Set-code transaction cannot create contracts"))
    (when (null (transaction-authorization-list transaction))
      (block-validation-fail
       "Set-code transaction requires an authorization list"))
    (dolist (authorization (transaction-authorization-list transaction))
      (validate-set-code-authorization-fields authorization)))
  t)

(defun validate-sized-byte-vector (value size label)
  (let ((bytes (handler-case
                   (ensure-byte-vector value)
                 (error ()
                   (block-validation-fail
                    (format nil "~A must be exactly ~D bytes" label size))))))
    (unless (= (length bytes) size)
      (block-validation-fail
       (format nil "~A must be exactly ~D bytes" label size)))
    bytes))

(defun validate-blob-sidecar-fields (sidecar &key transaction)
  (let* ((blobs (blob-sidecar-blobs sidecar))
         (commitments (blob-sidecar-commitments sidecar))
         (proofs (blob-sidecar-proofs sidecar))
         (blob-count (length blobs))
         (commitment-count (length commitments))
         (proof-count (length proofs)))
    (unless (= blob-count commitment-count proof-count)
      (block-validation-fail
       "Blob sidecar blob, commitment, and proof counts must match"))
    (dolist (blob blobs)
      (validate-sized-byte-vector blob +blob-byte-size+ "Blob"))
    (dolist (commitment commitments)
      (validate-sized-byte-vector commitment +kzg-commitment-size+
                                  "KZG commitment"))
    (dolist (proof proofs)
      (validate-sized-byte-vector proof +kzg-proof-size+ "KZG proof"))
    (when transaction
      (unless (= blob-count (transaction-blob-count transaction))
        (block-validation-fail
         "Blob sidecar count does not match transaction blob hash count"))
      (loop for actual in (blob-sidecar-versioned-hashes sidecar)
            for expected across (transaction-blob-versioned-hashes transaction)
            unless (bytes= (hash32-bytes actual)
                           (blob-versioned-hash-bytes expected))
              do (block-validation-fail
                  "Blob sidecar commitment does not match transaction blob hash")))
    t))

(defun validate-withdrawal-fields (withdrawal)
  (unless (uint256-p (withdrawal-index withdrawal))
    (block-validation-fail "Withdrawal index must be uint256"))
  (unless (uint256-p (withdrawal-validator-index withdrawal))
    (block-validation-fail "Withdrawal validator index must be uint256"))
  (unless (address-p (withdrawal-address withdrawal))
    (block-validation-fail "Withdrawal address must be an address"))
  (unless (uint256-p (withdrawal-amount withdrawal))
    (block-validation-fail "Withdrawal amount must be uint256"))
  t)

(defun validate-withdrawal-list-fields (withdrawals)
  (unless (listp withdrawals)
    (block-validation-fail "Withdrawals must be a list"))
  (dolist (withdrawal withdrawals t)
    (validate-withdrawal-fields withdrawal)))

(defun transaction-object-p (value)
  (typep value
         '(or legacy-transaction
              access-list-transaction
              dynamic-fee-transaction
              blob-transaction
              set-code-transaction)))

(defun validate-block-transaction-list-fields (transactions)
  (unless (listp transactions)
    (block-validation-fail "Block transactions must be a list"))
  (dolist (transaction transactions t)
    (unless (transaction-object-p transaction)
      (block-validation-fail "Block transaction must be a transaction"))))

(defun validate-block-ommer-list-fields (ommers)
  (unless (listp ommers)
    (block-validation-fail "Block ommers must be a list"))
  (dolist (ommer ommers t)
    (unless (block-header-p ommer)
      (block-validation-fail "Block ommer must be a block header"))))

(defun validate-block-body-commitment-fields (header)
  (unless (hash32-p (block-header-ommers-hash header))
    (block-validation-fail "Header ommers hash must be a hash32"))
  (unless (hash32-p (block-header-transactions-root header))
    (block-validation-fail "Header transactions root must be a hash32"))
  (when (block-header-withdrawals-root header)
    (unless (hash32-p (block-header-withdrawals-root header))
      (block-validation-fail "Header withdrawals root must be a hash32")))
  (when (block-header-requests-hash header)
    (unless (hash32-p (block-header-requests-hash header))
      (block-validation-fail "Header requests hash must be a hash32")))
  (when (block-header-block-access-list-hash header)
    (unless (hash32-p (block-header-block-access-list-hash header))
      (block-validation-fail
       "Header block access list hash must be a hash32")))
  t)

(defun transaction-blob-count (transaction)
  (typecase transaction
    (blob-transaction
     (length (blob-transaction-blob-versioned-hashes transaction)))
    (t 0)))

(defun blob-gas-used (transactions)
  (* +blob-gas-per-blob+
     (loop for transaction in transactions
           sum (transaction-blob-count transaction))))

(defun validate-block-transactions-against-config (block config)
  (let ((header (block-header block)))
    (validate-block-transaction-list-fields (block-transactions block))
    (dolist (transaction (block-transactions block) t)
      (validate-transaction-type-for-config
       transaction config
       (block-header-number header)
       (block-header-timestamp header)))))

(defun validate-block-body-against-config (block config)
  (let* ((header (block-header block))
         (number (block-header-number header))
         (timestamp (block-header-timestamp header))
         (block-access-list-max-code-size
           (if (chain-config-amsterdam-p config number timestamp)
               +block-access-list-amsterdam-max-code-size+
               +block-access-list-max-code-size+)))
    (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
        (chain-config-blob-schedule config number timestamp)
      (declare (ignore target-blob-gas))
      (validate-block-transactions-against-config block config)
      (validate-block-body-roots block
                                 :blob-base-fee-update-fraction
                                 update-fraction
                                 :max-blob-gas max-blob-gas
                                 :block-access-list-max-code-size
                                 block-access-list-max-code-size))))

(defun validate-block-against-config (parent-header block config)
  (validate-block-header-against-config parent-header (block-header block)
                                        config)
  (validate-block-body-against-config block config))

(defun validate-block-body-roots
    (block &key (blob-base-fee-update-fraction
                 +blob-base-fee-update-fraction+)
                (max-blob-gas
                 (* +max-blobs-per-block+ +blob-gas-per-blob+))
                block-access-list-max-code-size)
  (let* ((header (block-header block))
         (ommers (block-ommers block))
         (ommers-root nil)
         (transactions (block-transactions block))
         (transactions-root nil)
         (blob-gas-used nil)
         (base-fee (block-header-base-fee-per-gas header))
         (blob-base-fee (when (block-header-excess-blob-gas header)
                          (block-header-blob-base-fee
                           header
                           :update-fraction
                           blob-base-fee-update-fraction))))
    (validate-block-body-commitment-fields header)
    (validate-block-ommer-list-fields ommers)
    (setf ommers-root (ommers-hash ommers))
    (validate-block-transaction-list-fields transactions)
    (setf blob-gas-used (blob-gas-used transactions))
    (dolist (transaction transactions)
      (validate-transaction-recipient-field transaction)
      (validate-transaction-data-field transaction)
      (validate-transaction-scalar-fields transaction)
      (validate-transaction-signature-fields transaction)
      (validate-access-list-fields transaction)
      (validate-set-code-transaction-fields transaction)
      (when base-fee
        (validate-1559-transaction-fees transaction base-fee))
      (when (typep transaction 'blob-transaction)
        (validate-blob-transaction-fields transaction)
        (when blob-base-fee
          (validate-blob-transaction-fee-cap transaction blob-base-fee))))
    (setf transactions-root (transaction-list-root transactions))
    (when (block-withdrawals-present-p block)
      (validate-withdrawal-list-fields (block-withdrawals block)))
    (when (block-requests-present-p block)
      (validate-execution-request-list-fields (block-requests block)))
    (when (block-block-access-list-present-p block)
      (validated-block-access-list-commitment
       block
       :max-code-size block-access-list-max-code-size
       :max-items (when (plusp (block-header-gas-limit header))
                    (floor (block-header-gas-limit header)
                           +block-access-list-item-gas-cost+))))
    (unless (hash32= ommers-root (block-header-ommers-hash header))
      (block-validation-fail "Ommers root hash mismatch"))
    (when (and (block-header-post-merge-p header)
               ommers)
      (block-validation-fail "Post-Merge blocks cannot contain ommers"))
    (unless (hash32= transactions-root
                     (block-header-transactions-root header))
      (block-validation-fail "Transaction root hash mismatch"))
    (cond
      ((block-header-withdrawals-root header)
       (unless (block-withdrawals-present-p block)
         (block-validation-fail "Missing withdrawals in block body"))
       (unless (hash32= (withdrawal-list-root (block-withdrawals block))
                        (block-header-withdrawals-root header))
         (block-validation-fail "Withdrawals root hash mismatch")))
      ((block-withdrawals-present-p block)
       (block-validation-fail "Withdrawals present before withdrawals root")))
    (cond
      ((block-header-requests-hash header)
       (unless (block-requests-present-p block)
         (block-validation-fail "Missing execution requests in block body"))
       (unless (hash32= (execution-requests-hash (block-requests block))
                        (block-header-requests-hash header))
         (block-validation-fail "Execution requests hash mismatch")))
      ((block-requests-present-p block)
       (block-validation-fail "Execution requests present before requests hash")))
    (cond
      ((block-header-block-access-list-hash header)
       (unless (block-block-access-list-present-p block)
         (block-validation-fail "Missing block access list in block body"))
       (unless (hash32= (validated-block-access-list-commitment
                         block
                         :max-code-size block-access-list-max-code-size
                         :max-items
                         (when (plusp (block-header-gas-limit header))
                           (floor (block-header-gas-limit header)
                                  +block-access-list-item-gas-cost+)))
                        (block-header-block-access-list-hash header))
         (block-validation-fail "Block access list hash mismatch")))
      ((block-block-access-list-present-p block)
       (block-validation-fail
        "Block access list present before block access list hash")))
    (cond
      ((block-header-blob-gas-used header)
       (unless (= blob-gas-used (block-header-blob-gas-used header))
         (block-validation-fail "Blob gas used mismatch")))
      ((plusp blob-gas-used)
       (block-validation-fail "Blob transactions present before blob gas header")))
    (when (> blob-gas-used max-blob-gas)
      (block-validation-fail "Blob gas used exceeds maximum"))
    t))

(defun receipts-gas-used (receipts)
  (if receipts
      (receipt-cumulative-gas-used (car (last receipts)))
      0))

(defun validate-block-execution-commitment-fields (header state-root)
  (unless (uint256-p (block-header-gas-used header))
    (block-validation-fail "Header gas used must be uint256"))
  (validate-sized-byte-vector (block-header-logs-bloom header)
                              256
                              "Header logs bloom")
  (unless (hash32-p (block-header-receipts-root header))
    (block-validation-fail "Header receipts root must be a hash32"))
  (unless (hash32-p (block-header-state-root header))
    (block-validation-fail "Header state root must be a hash32"))
  (unless (hash32-p state-root)
    (block-validation-fail "Computed state root must be a hash32"))
  t)

(defun validate-log-topic-field (topic)
  (handler-case
      (progn
        (topic-bytes topic)
        t)
    (error ()
      (block-validation-fail "Log topic must be a hash32 or 32-byte value"))))

(defun validate-log-entry-fields (log)
  (unless (log-entry-p log)
    (block-validation-fail "Receipt log must be a log entry"))
  (unless (address-p (log-entry-address log))
    (block-validation-fail "Receipt log address must be an address"))
  (unless (listp (log-entry-topics log))
    (block-validation-fail "Receipt log topics must be a list"))
  (dolist (topic (log-entry-topics log))
    (validate-log-topic-field topic))
  (handler-case
      (progn
        (ensure-byte-vector (log-entry-data log))
        t)
    (error ()
      (block-validation-fail "Receipt log data must be a byte sequence"))))

(defun validate-receipt-fields (receipt)
  (unless (receipt-p receipt)
    (block-validation-fail "Block receipt must be a receipt"))
  (if (receipt-post-state receipt)
      (validate-sized-byte-vector (receipt-post-state receipt)
                                  32
                                  "Receipt post-state")
      (unless (member (receipt-status receipt) '(0 1))
        (block-validation-fail "Receipt status must be 0 or 1")))
  (unless (uint64-value-p (receipt-cumulative-gas-used receipt))
    (block-validation-fail "Receipt cumulative gas used must be uint64"))
  (unless (listp (receipt-logs receipt))
    (block-validation-fail "Receipt logs must be a list"))
  (dolist (log (receipt-logs receipt) t)
    (validate-log-entry-fields log)))

(defun validate-receipt-list-fields (receipts)
  (unless (listp receipts)
    (block-validation-fail "Block receipts must be a list"))
  (let ((previous-gas-used nil))
    (dolist (receipt receipts t)
      (validate-receipt-fields receipt)
      (let ((gas-used (receipt-cumulative-gas-used receipt)))
        (when (and previous-gas-used (<= gas-used previous-gas-used))
          (block-validation-fail
           "Receipt cumulative gas used must increase"))
        (setf previous-gas-used gas-used)))))

(defun validate-block-execution-roots
    (block receipts state-root &key (transactions nil transactions-supplied-p))
  (let ((header (block-header block)))
    (validate-block-execution-commitment-fields header state-root)
    (validate-receipt-list-fields receipts)
    (when transactions-supplied-p
      (validate-block-transaction-list-fields transactions))
    (let* ((gas-used (receipts-gas-used receipts))
           (logs-bloom (bloom-bytes (receipts-logs-bloom receipts)))
           (receipts-root (if transactions-supplied-p
                              (transaction-receipt-list-root transactions
                                                             receipts)
                              (receipt-list-root receipts))))
      (unless (= gas-used (block-header-gas-used header))
        (block-validation-fail "Gas used mismatch"))
      (unless (and (block-header-logs-bloom header)
                   (bytes= logs-bloom (block-header-logs-bloom header)))
        (block-validation-fail "Logs bloom mismatch"))
      (unless (hash32= receipts-root (block-header-receipts-root header))
        (block-validation-fail "Receipts root mismatch"))
      (unless (hash32= state-root (block-header-state-root header))
        (block-validation-fail "State root mismatch")))
    t))

(defstruct (withdrawal (:constructor make-withdrawal
                         (&key (index 0)
                               (validator-index 0)
                               (address (zero-address))
                               (amount 0))))
  (index 0 :type (integer 0 *))
  (validator-index 0 :type (integer 0 *))
  address
  (amount 0 :type (integer 0 *)))

(defun withdrawal-rlp-object (withdrawal)
  (make-rlp-list
   (ensure-uint256 (withdrawal-index withdrawal) "Withdrawal index")
   (ensure-uint256 (withdrawal-validator-index withdrawal)
                   "Withdrawal validator index")
   (address-bytes (withdrawal-address withdrawal))
   (ensure-uint256 (withdrawal-amount withdrawal) "Withdrawal amount")))

(defun withdrawal-rlp (withdrawal)
  (rlp-encode (withdrawal-rlp-object withdrawal)))

(defstruct (log-entry (:constructor make-log-entry
                         (&key (address (zero-address))
                               (topics '())
                               (data #()))))
  address
  (topics '() :type list)
  data)

(defun topic-bytes (topic)
  (etypecase topic
    (hash32 (hash32-bytes topic))
    (byte-vector (optional-bytes topic 32 "Log topic"))
    (vector (optional-bytes topic 32 "Log topic"))))

(defun log-entry-rlp-object (log)
  (make-rlp-list
   (address-bytes (log-entry-address log))
   (mapcar #'topic-bytes (log-entry-topics log))
   (ensure-byte-vector (log-entry-data log))))

(defstruct (bloom (:constructor %make-bloom (bytes)))
  (bytes (make-byte-vector 256) :type byte-vector))

(defun make-bloom (&optional bytes)
  (%make-bloom (if bytes
                   (optional-bytes bytes 256 "Bloom")
                   (make-byte-vector 256))))

(defun bloom-values (data)
  (let ((hash (keccak-256 data)))
    (labels ((bit-index (offset)
               (logand #x7ff
                       (logior (ash (aref hash offset) 8)
                               (aref hash (1+ offset)))))
             (byte-index (bit-index)
               (- 256 (ash bit-index -3) 1))
             (byte-value (offset)
               (ash 1 (logand (aref hash (1+ offset)) #x7))))
      (list (byte-index (bit-index 0)) (byte-value 0)
            (byte-index (bit-index 2)) (byte-value 2)
            (byte-index (bit-index 4)) (byte-value 4)))))

(defun bloom-add (bloom data)
  (destructuring-bind (i1 v1 i2 v2 i3 v3) (bloom-values data)
    (let ((bytes (bloom-bytes bloom)))
      (setf (aref bytes i1) (logior (aref bytes i1) v1)
            (aref bytes i2) (logior (aref bytes i2) v2)
            (aref bytes i3) (logior (aref bytes i3) v3))))
  bloom)

(defun bloom-contains-p (bloom data)
  (destructuring-bind (i1 v1 i2 v2 i3 v3) (bloom-values data)
    (let ((bytes (bloom-bytes bloom)))
      (and (= v1 (logand v1 (aref bytes i1)))
           (= v2 (logand v2 (aref bytes i2)))
           (= v3 (logand v3 (aref bytes i3)))))))

(defun receipt-bloom (logs)
  (let ((bloom (make-bloom)))
    (dolist (log logs bloom)
      (bloom-add bloom (address-bytes (log-entry-address log)))
      (dolist (topic (log-entry-topics log))
        (bloom-add bloom (topic-bytes topic))))))

(defstruct (receipt (:constructor make-receipt
                       (&key post-state
                             (status 1)
                             (cumulative-gas-used 0)
                             (logs '()))))
  post-state
  (status 1 :type (integer 0 1))
  (cumulative-gas-used 0 :type (integer 0 *))
  (logs '() :type list))

(defun receipt-status-bytes (receipt)
  (if (receipt-post-state receipt)
      (ensure-byte-vector (receipt-post-state receipt))
      (if (= (receipt-status receipt) 1)
          (ensure-byte-vector #(1))
          (make-byte-vector 0))))

(defun receipt-rlp-object (receipt)
  (let ((logs (receipt-logs receipt)))
    (make-rlp-list
     (receipt-status-bytes receipt)
     (ensure-uint256 (receipt-cumulative-gas-used receipt)
                     "Receipt cumulative gas used")
     (bloom-bytes (receipt-bloom logs))
     (mapcar #'log-entry-rlp-object logs))))

(defun receipt-rlp (receipt)
  (rlp-encode (receipt-rlp-object receipt)))

(defun transaction-receipt-encoding (transaction receipt)
  (let ((type (transaction-type transaction))
        (receipt-rlp (receipt-rlp receipt)))
    (if (zerop type)
        receipt-rlp
        (concat-bytes (vector type) receipt-rlp))))

(defun derive-list-root (encoded-items)
  (let ((trie (make-mpt)))
    (loop for item in encoded-items
          for index from 0
          do (mpt-put trie (rlp-encode index) item))
    (make-hash32 (mpt-root-hash trie))))

(defun transaction-list-root (transactions)
  (derive-list-root (mapcar #'transaction-encoding transactions)))

(defun receipt-list-root (receipts)
  (derive-list-root (mapcar #'receipt-rlp receipts)))

(defun transaction-receipt-list-root (transactions receipts)
  (unless (= (length transactions) (length receipts))
    (block-validation-fail "Transaction and receipt count mismatch"))
  (derive-list-root
   (mapcar #'transaction-receipt-encoding transactions receipts)))

(defun withdrawal-list-root (withdrawals)
  (derive-list-root (mapcar #'withdrawal-rlp withdrawals)))
