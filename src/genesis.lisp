(in-package #:ethereum-lisp.core)

(defconstant +genesis-gas-limit+ 4712388)
(defconstant +genesis-difficulty+ 131072)

(defstruct (genesis-account
            (:constructor make-genesis-account
                (&key address (balance 0) (nonce 0)
                      (code (make-byte-vector 0)) storage)))
  address
  (balance 0 :type (integer 0 *))
  (nonce 0 :type (integer 0 *))
  (code (make-byte-vector 0) :type byte-vector)
  (storage nil :type list))

(defun ensure-uint256 (value label)
  (unless (uint256-p value)
    (error "~A must be a uint256, got ~S" label value))
  value)

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

(defun parse-genesis-address-field (object name label &key default)
  (let ((value (if (listp name)
                   (genesis-object-field-any object name)
                   (genesis-object-field object name))))
    (cond
      ((null value) default)
      (t (parse-genesis-address value label)))))

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

(defun json-parse-number (text)
  (handler-case
      (multiple-value-bind (value end) (read-from-string text)
        (unless (and (= end (length text)) (realp value))
          (block-validation-fail "Invalid JSON number"))
        value)
    (error ()
      (block-validation-fail "Invalid JSON number"))))

(defun parse-json (string &key preserve-empty-arrays)
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
             (when (and (peek) (char= (peek) #\.))
               (incf position)
               (unless (and (peek) (digit-char-p (peek)))
                 (fail "expected fractional digit"))
               (loop while (and (peek) (digit-char-p (peek)))
                     do (incf position)))
             (when (and (peek) (member (peek) '(#\e #\E)))
               (incf position)
               (when (and (peek) (member (peek) '(#\+ #\-)))
                 (incf position))
               (unless (and (peek) (digit-char-p (peek)))
                 (fail "expected exponent digit"))
               (loop while (and (peek) (digit-char-p (peek)))
                     do (incf position)))
             (json-parse-number (subseq string start position))))
         (parse-array ()
           (expect #\[)
           (skip-whitespace)
           (let ((items '()))
             (when (and (peek) (char= (peek) #\]))
               (incf position)
               (return-from parse-array
                 (if preserve-empty-arrays
                     (make-array 0)
                     '())))
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

(defun json-object-p (value)
  (and (consp value)
       (every (lambda (entry)
                (and (consp entry)
                     (or (stringp (car entry))
                         (symbolp (car entry)))))
              value)))

(defun json-empty-array-p (value)
  (and (vectorp value)
       (not (stringp value))
       (zerop (length value))))

(defun json-array-p (value)
  (or (listp value)
      (json-empty-array-p value)))

(defun json-array-values (value)
  (if (json-empty-array-p value)
      '()
      value))

(defstruct (json-empty-object
            (:constructor make-json-empty-object ())))

(defparameter +json-empty-object+ (make-json-empty-object))

(defun write-json-string (string stream)
  (write-char #\" stream)
  (loop for char across string
        for code = (char-code char)
        do (case char
             (#\" (write-string "\\\"" stream))
             (#\\ (write-string "\\\\" stream))
             (#\Backspace (write-string "\\b" stream))
             (#\Page (write-string "\\f" stream))
             (#\Newline (write-string "\\n" stream))
             (#\Return (write-string "\\r" stream))
             (#\Tab (write-string "\\t" stream))
             (otherwise
              (if (< code #x20)
                  (format stream "\\u~4,'0x" code)
                  (write-char char stream)))))
  (write-char #\" stream))

(defun json-real-string (value)
  (let* ((text (format nil "~,12F" (coerce value 'double-float)))
         (dot (position #\. text)))
    (when dot
      (loop while (and (> (length text) (1+ dot))
                       (char= (char text (1- (length text))) #\0))
            do (setf text (subseq text 0 (1- (length text)))))
      (when (char= (char text (1- (length text))) #\.)
        (setf text (subseq text 0 (1- (length text))))))
    (if (string= text "-0") "0" text)))

(defun write-json-value (value stream)
  (cond
    ((null value) (write-string "null" stream))
    ((eq value t) (write-string "true" stream))
    ((eq value :false) (write-string "false" stream))
    ((json-empty-object-p value) (write-string "{}" stream))
    ((stringp value) (write-json-string value stream))
    ((integerp value) (write-string (write-to-string value :base 10) stream))
    ((realp value) (write-string (json-real-string value) stream))
    ((vectorp value)
     (write-char #\[ stream)
     (loop for index below (length value)
           for first-p = t then nil
           do (progn
                (unless first-p
                  (write-char #\, stream))
                (write-json-value (aref value index) stream)))
     (write-char #\] stream))
    ((json-object-p value)
     (write-char #\{ stream)
     (loop for (key . item) in value
           for first-p = t then nil
           do (progn
                (unless first-p
                  (write-char #\, stream))
                (write-json-string
                 (if (stringp key) key (string-downcase (symbol-name key)))
                 stream)
                (write-char #\: stream)
                (write-json-value item stream)))
     (write-char #\} stream))
    ((listp value)
     (write-char #\[ stream)
     (loop for item in value
           for first-p = t then nil
           do (progn
                (unless first-p
                  (write-char #\, stream))
                (write-json-value item stream)))
     (write-char #\] stream))
    (t (block-validation-fail "Cannot encode value as JSON"))))

(defun json-encode (value)
  (with-output-to-string (stream)
    (write-json-value value stream)))

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
