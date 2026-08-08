(in-package #:ethereum-lisp.database)

(defconstant +kv-chain-schema-version+ 4)

(defparameter +kv-chain-schema-version-identifier+ "chain"
  "The single :SCHEMA-VERSION record identifier. One marker names the on-disk
schema of the whole chain database, written in the same batch as the block
records so a version bump is all-or-nothing.")

(defparameter +kv-chain-record-kind-prefixes+
  '((:block . #x01)
    (:header . #x02)
    (:receipt . #x03)
    (:canonical-hash . #x04)
    (:checkpoint . #x05)
    (:state . #x06)
    (:transaction-location . #x07)
    (:txpool . #x08)
    (:invalid-tipset . #x09)
    (:remote-block . #x0a)
    (:blob-sidecar . #x0b)
    (:prepared-payload . #x0c)
    (:metadata . #x0d)
    (:staged-header . #x0e)
    (:staged-block . #x0f)
    (:staged-state . #x10)
    (:staged-receipt . #x11)
    (:staged-transaction-index . #x12)
    (:stage-progress . #x13)
    (:block-access-list . #x14)
    (:state-diff . #x15)
    (:ordered-block . #x16)
    (:ordered-header . #x17)
    (:ordered-receipt . #x18)
    (:trie-node . #x19)
    (:code . #x1a)
    (:state-history . #x1b)
    (:schema-version . #x1c)
    (:ordered-state-history . #x1d)))

(defparameter +kv-chain-checkpoint-labels+
  '((:head . "head")
    (:safe . "safe")
    (:finalized . "finalized")))

(defun kv-chain-record-kind-prefix (kind)
  (or (cdr (assoc kind +kv-chain-record-kind-prefixes+))
      (error "Unknown chain record kind: ~S" kind)))

(defun kv-chain-record-uint64-bytes (number)
  (unless (and (integerp number)
               (<= 0 number)
               (< number (ash 1 64)))
    (error "Chain record numeric identifier must be a uint64"))
  (let ((bytes (make-byte-vector 8)))
    (dotimes (index 8 bytes)
      (setf (aref bytes (- 7 index))
            (ldb (byte 8 (* index 8)) number)))))

(defun kv-chain-record-identifier-bytes (identifier)
  (cond
    ((integerp identifier)
     (kv-chain-record-uint64-bytes identifier))
    ((stringp identifier)
     (ascii-to-bytes identifier))
    ((or (byte-vector-p identifier) (vectorp identifier))
     (kv-copy-bytes identifier))
    (t
     (error "Unsupported chain record identifier: ~S" identifier))))

(defun kv-chain-record-uint64-identifier (identifier)
  (let ((bytes (ensure-byte-vector identifier)))
    (unless (= 8 (length bytes))
      (error "Chain record identifier is not a uint64 key"))
    (bytes-to-integer bytes)))

(defun kv-chain-checkpoint-identifier (label)
  (let ((name
          (cond
            ((symbolp label)
             (cdr (assoc label +kv-chain-checkpoint-labels+)))
            ((stringp label)
             (and (rassoc label +kv-chain-checkpoint-labels+
                          :test #'string=)
                  label))
            (t nil))))
    (unless name
      (error "Unknown chain checkpoint label: ~S" label))
    name))

(defun kv-chain-checkpoint-label (identifier)
  (let* ((name (bytes-to-ascii (ensure-byte-vector identifier)))
         (entry (rassoc name +kv-chain-checkpoint-labels+
                        :test #'string=)))
    (unless entry
      (error "Unknown chain checkpoint identifier: ~S" name))
    (car entry)))

(defun kv-chain-record-key (kind identifier)
  (concat-bytes
   (vector (kv-chain-record-kind-prefix kind))
   (kv-chain-record-identifier-bytes identifier)))

(defun kv-chain-height-hash-identifier (number hash)
  "Encode NUMBER then HASH so byte ordering is height ordering."
  (let ((hash (ensure-byte-vector hash)))
    (unless (= 32 (length hash))
      (error "Height-ordered chain record hash must contain 32 bytes"))
    (concat-bytes (kv-chain-record-uint64-bytes number) hash)))

(defun kv-chain-height-hash-identifier-values (identifier)
  (let ((identifier (ensure-byte-vector identifier)))
    (unless (= 40 (length identifier))
      (error "Height-ordered chain identifier must contain 40 bytes"))
    (values (kv-chain-record-uint64-identifier (subseq identifier 0 8))
            (subseq identifier 8))))

(defun kv-chain-record-key-identifier (kind key)
  (let ((bytes (ensure-byte-vector key))
        (prefix (kv-chain-record-kind-prefix kind)))
    (unless (and (> (length bytes) 0)
                 (= (aref bytes 0) prefix))
      (error "Chain record key does not match kind ~S" kind))
    (subseq bytes 1)))

(defun kv-chain-record-key-kind (key)
  "Return the chain record kind named by KEY's one-byte namespace prefix."
  (let* ((bytes (ensure-byte-vector key))
         (prefix (and (plusp (length bytes)) (aref bytes 0)))
         (entry (and prefix
                     (rassoc prefix +kv-chain-record-kind-prefixes+))))
    (unless entry
      (error "Unknown chain record key prefix: ~S" prefix))
    (car entry)))

(defun kv-chain-record-kind-start-key (kind)
  (vector (kv-chain-record-kind-prefix kind)))

(defun kv-chain-record-kind-end-key (kind)
  (let ((prefix (kv-chain-record-kind-prefix kind)))
    (when (= prefix #xff)
      (error "Chain record kind prefix cannot form an exclusive end key"))
    (vector (1+ prefix))))
