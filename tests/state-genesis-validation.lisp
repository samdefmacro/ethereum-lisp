(in-package #:ethereum-lisp.test)

(defparameter +phase-a-shanghai-genesis-fixture-path+
  "tests/fixtures/execution-spec-tests/phase-a-shanghai-genesis.json")

(defparameter +phase-a-shanghai-genesis-fixture-format+
  "ethereum-lisp/phase-a-shanghai-genesis-fixture-v1")

(defparameter +phase-a-shanghai-genesis-top-level-fields+
  '("format"
    "source"
    "executionSpecTests"
    "config"
    "nonce"
    "timestamp"
    "extraData"
    "gasLimit"
    "difficulty"
    "mixHash"
    "coinbase"
    "stateRoot"
    "alloc"))

(defparameter +phase-a-shanghai-genesis-config-fields+
  '("chainId"
    "terminalTotalDifficulty"
    "londonBlock"
    "shanghaiTime"))

(defparameter +phase-a-shanghai-genesis-account-fields+
  '("balance" "nonce" "code" "storage"))

(defun validate-phase-a-shanghai-genesis-object-fields
    (object allowed-fields label)
  (unless (listp object)
    (error "~A must be a JSON object" label))
  (let ((seen-fields (make-hash-table :test 'equal)))
    (dolist (field object)
      (let ((name (car field)))
        (unless (stringp name)
          (error "~A field name must be a string" label))
        (when (gethash name seen-fields)
          (error "~A has duplicate field ~A" label name))
        (setf (gethash name seen-fields) t)
        (unless (member name allowed-fields :test #'string=)
          (error "~A has unknown field ~A" label name))))))

(defun validate-phase-a-shanghai-genesis-non-empty-string (value label)
  (unless (stringp value)
    (error "~A must be a string" label))
  (when (blank-string-p value)
    (error "~A must be present" label))
  value)

(defun validate-phase-a-shanghai-genesis-hex-string (value label)
  (unless (stringp value)
    (error "~A must be a hex string" label))
  (let ((bytes (hex-to-bytes value)))
    (unless (string= value (bytes-to-hex bytes))
      (error "~A must be canonical lowercase 0x-prefixed hex" label))
    bytes))

(defun validate-phase-a-shanghai-genesis-hash-string (value label)
  (unless (stringp value)
    (error "~A must be a hash hex string" label))
  (let ((hash (hash32-from-hex value)))
    (unless (string= value (hash32-to-hex hash))
      (error "~A must be canonical lowercase 0x-prefixed hash hex" label))
    hash))

(defun validate-phase-a-shanghai-genesis-address-string (value label)
  (unless (stringp value)
    (error "~A must be an address hex string" label))
  (let ((address (address-from-hex value)))
    (unless (string= value (address-to-hex address))
      (error "~A must be canonical lowercase 0x-prefixed address hex" label))
    address))

(defun validate-phase-a-shanghai-genesis-non-negative-value
    (object field label &key required-p)
  (let ((present-p (fixture-field-present-p object field))
        (value (fixture-object-field object field)))
    (when (or present-p required-p)
      (unless (or (and (integerp value) (not (minusp value)))
                  (and (stringp value)
                       (let ((quantity (hex-to-quantity value)))
                         (and (not (minusp quantity))
                              (string= value
                                       (string-downcase
                                        (quantity-to-hex quantity)))))))
        (error "~A field ~A must be a non-negative integer or hex quantity"
               label
               field)))))

(defun validate-phase-a-shanghai-genesis-config-shape (config)
  (validate-phase-a-shanghai-genesis-object-fields
   config
   +phase-a-shanghai-genesis-config-fields+
   "Phase A Shanghai genesis config")
  (dolist (field +phase-a-shanghai-genesis-config-fields+)
    (validate-phase-a-shanghai-genesis-non-negative-value
     config
     field
     "Phase A Shanghai genesis config"
     :required-p t)))

(defun validate-phase-a-shanghai-genesis-storage-shape (storage address)
  (unless (listp storage)
    (error "Phase A Shanghai genesis account ~A storage must be a JSON object"
           address))
  (let ((seen-slots (make-hash-table :test 'equal)))
    (dolist (entry storage)
      (let ((slot (car entry)))
        (unless (stringp slot)
          (error "Phase A Shanghai genesis account ~A has malformed storage slot ~A"
                 address
                 slot))
        (let ((slot-id (quantity-to-hex (hex-to-quantity slot))))
          (when (gethash slot-id seen-slots)
            (error "Phase A Shanghai genesis account ~A storage has duplicate slot ~A"
                   address
                   slot))
          (setf (gethash slot-id seen-slots) t))
        (let ((value (cdr entry)))
          (unless (or (and (integerp value) (not (minusp value)))
                      (and (stringp value)
                           (not (minusp (hex-to-quantity value)))))
            (error "Phase A Shanghai genesis account ~A storage slot ~A has malformed value ~A"
                   address
                   slot
                   value)))))))

(defun validate-phase-a-shanghai-genesis-account-shape (address account)
  (validate-phase-a-shanghai-genesis-address-string
   address
   "Phase A Shanghai genesis account address")
  (validate-phase-a-shanghai-genesis-object-fields
   account
   +phase-a-shanghai-genesis-account-fields+
   (format nil "Phase A Shanghai genesis account ~A" address))
  (validate-phase-a-shanghai-genesis-non-negative-value
   account
   "balance"
   (format nil "Phase A Shanghai genesis account ~A" address)
   :required-p t)
  (validate-phase-a-shanghai-genesis-non-negative-value
   account
   "nonce"
   (format nil "Phase A Shanghai genesis account ~A" address))
  (when (fixture-field-present-p account "code")
    (validate-phase-a-shanghai-genesis-hex-string
     (fixture-required-field account "code")
     (format nil "Phase A Shanghai genesis account ~A code" address)))
  (when (fixture-field-present-p account "storage")
    (validate-phase-a-shanghai-genesis-storage-shape
     (fixture-object-field account "storage")
     address)))

(defun validate-phase-a-shanghai-genesis-alloc-shape (alloc)
  (unless (and (listp alloc) alloc)
    (error "Phase A Shanghai genesis alloc must be a non-empty JSON object"))
  (let ((seen-addresses (make-hash-table :test 'equal)))
    (dolist (entry alloc)
      (let ((address (car entry)))
        (unless (stringp address)
          (error "Phase A Shanghai genesis alloc address must be a string"))
        (let ((address-id
                (address-to-hex
                 (validate-phase-a-shanghai-genesis-address-string
                  address
                  "Phase A Shanghai genesis alloc address"))))
          (when (gethash address-id seen-addresses)
            (error "Phase A Shanghai genesis alloc has duplicate address ~A"
                   address))
          (setf (gethash address-id seen-addresses) t))
        (validate-phase-a-shanghai-genesis-account-shape
         address
         (cdr entry))))))

(defun validate-phase-a-shanghai-genesis-fixture-shape (fixture)
  (validate-phase-a-shanghai-genesis-object-fields
   fixture
   +phase-a-shanghai-genesis-top-level-fields+
   "Phase A Shanghai genesis fixture")
  (dolist (field +phase-a-shanghai-genesis-top-level-fields+)
    (fixture-required-field fixture field))
  (validate-fixture-format fixture +phase-a-shanghai-genesis-fixture-format+)
  (validate-phase-a-shanghai-genesis-non-empty-string
   (fixture-required-field fixture "source")
   "Phase A Shanghai genesis fixture source")
  (validate-fixture-pinned-eest-source fixture)
  (validate-phase-a-shanghai-genesis-config-shape
   (fixture-required-field fixture "config"))
  (dolist (field '("nonce" "timestamp" "gasLimit" "difficulty"))
    (validate-phase-a-shanghai-genesis-non-negative-value
     fixture
     field
     "Phase A Shanghai genesis fixture"
     :required-p t))
  (validate-phase-a-shanghai-genesis-hex-string
   (fixture-required-field fixture "extraData")
   "Phase A Shanghai genesis fixture extraData")
  (validate-phase-a-shanghai-genesis-hash-string
   (fixture-required-field fixture "mixHash")
   "Phase A Shanghai genesis fixture mixHash")
  (validate-phase-a-shanghai-genesis-address-string
   (fixture-required-field fixture "coinbase")
   "Phase A Shanghai genesis fixture coinbase")
  (validate-phase-a-shanghai-genesis-hash-string
   (fixture-required-field fixture "stateRoot")
   "Phase A Shanghai genesis fixture stateRoot")
  (validate-phase-a-shanghai-genesis-alloc-shape
   (fixture-required-field fixture "alloc")))

