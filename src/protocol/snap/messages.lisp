(in-package #:ethereum-lisp.snap)

;;;; snap/1 wire objects and the storage-facing service boundary.
;;;;
;;;; This layer deliberately knows nothing about StateDB, trie persistence, or
;;;; range-proof verification. A state implementation supplies four callbacks
;;;; through SNAP-STATE-BACKEND; the protocol owns only bounded wire values and
;;;; request dispatch.

(defconstant +snap-protocol-version+ 1)
(defconstant +snap-message-count+ 8)
(defconstant +snap-max-message-size+ (* 10 1024 1024))
(defconstant +snap-max-list-items+ 4096)

(defconstant +snap-message-get-account-range+ #x00)
(defconstant +snap-message-account-range+ #x01)
(defconstant +snap-message-get-storage-ranges+ #x02)
(defconstant +snap-message-storage-ranges+ #x03)
(defconstant +snap-message-get-bytecodes+ #x04)
(defconstant +snap-message-bytecodes+ #x05)
(defconstant +snap-message-get-trie-nodes+ #x06)
(defconstant +snap-message-trie-nodes+ #x07)

(defstruct (snap-account-data
            (:constructor make-snap-account-data (hash body)))
  hash
  body)

(defstruct (snap-storage-data
            (:constructor make-snap-storage-data (hash body)))
  hash
  body)

(defstruct (snap-get-account-range
            (:constructor make-snap-get-account-range
                (id root origin limit bytes)))
  id root origin limit bytes)

(defstruct (snap-account-range
            (:constructor make-snap-account-range (id accounts proof)))
  id accounts proof)

(defstruct (snap-get-storage-ranges
            (:constructor make-snap-get-storage-ranges
                (id root accounts origin limit bytes)))
  id root accounts origin limit bytes)

(defstruct (snap-storage-ranges
            (:constructor make-snap-storage-ranges (id slots proof)))
  id slots proof)

(defstruct (snap-get-bytecodes
            (:constructor make-snap-get-bytecodes (id hashes bytes)))
  id hashes bytes)

(defstruct (snap-bytecodes
            (:constructor make-snap-bytecodes (id codes)))
  id codes)

(defstruct (snap-get-trie-nodes
            (:constructor make-snap-get-trie-nodes (id root paths bytes)))
  id root paths bytes)

(defstruct (snap-trie-nodes
            (:constructor make-snap-trie-nodes (id nodes)))
  id nodes)

(defstruct (snap-state-backend
            (:constructor make-snap-state-backend
                (&key account-range storage-ranges bytecodes trie-nodes)))
  "Callbacks implementing snap reads against a state node store.

Each callback receives the decoded request object and returns its corresponding
response object. This is the only dependency snap serving has on state storage."
  account-range
  storage-ranges
  bytecodes
  trie-nodes)

(defun snap-uint-object (value)
  (unless (and (integerp value) (<= 0 value #xffffffffffffffff))
    (error "snap integer is outside uint64: ~S" value))
  (integer-to-minimal-bytes value))

(defun snap-bytes-object (value)
  (ensure-byte-vector value))

(defun snap-hash-object (value)
  (let ((bytes (ensure-byte-vector value)))
    (unless (= (length bytes) 32)
      (error "snap hash must contain 32 bytes"))
    bytes))

(defun snap-list-object (items mapper)
  (apply #'make-rlp-list (mapcar mapper items)))

(defun snap-fields (bytes expected name)
  (let ((fields
          (rlp-list-items
           (rlp-decode (ensure-byte-vector bytes)
                       :max-list-items +snap-max-list-items+))))
    (unless (= (length fields) expected)
      (error "~A must contain ~D fields" name expected))
    fields))

(defun snap-uint-field (value)
  (let ((bytes (ensure-byte-vector value)))
    (unless (<= (length bytes) 8)
      (error "snap uint64 contains more than 8 bytes"))
    (when (and (plusp (length bytes)) (zerop (aref bytes 0)))
      (error "snap uint64 is not minimally encoded"))
    (bytes-to-integer bytes)))

(defun snap-bytes-field (value)
  (ensure-byte-vector value))

(defun snap-hash-field (value)
  (snap-hash-object (ensure-byte-vector value)))

(defun snap-list-field (value mapper)
  (mapcar mapper (rlp-list-items value)))

(defun snap-account-data-object (account)
  (make-rlp-list
   (snap-hash-object (snap-account-data-hash account))
   (snap-account-data-body account)))

(defun snap-account-data-field (value)
  (let ((fields (rlp-list-items value)))
    (unless (= (length fields) 2)
      (error "snap account data must contain two fields"))
    (make-snap-account-data
     (snap-hash-field (first fields))
     (second fields))))

(defun snap-storage-data-object (slot)
  (make-rlp-list
   (snap-hash-object (snap-storage-data-hash slot))
   (snap-bytes-object (snap-storage-data-body slot))))

(defun snap-storage-data-field (value)
  (let ((fields (rlp-list-items value)))
    (unless (= (length fields) 2)
      (error "snap storage data must contain two fields"))
    (make-snap-storage-data
     (snap-hash-field (first fields))
     (snap-bytes-field (second fields)))))

(defun encode-snap-message (message-id packet)
  "Encode PACKET as the snap/1 body for MESSAGE-ID."
  (rlp-encode
   (case message-id
     (#x00
      (make-rlp-list
       (snap-uint-object (snap-get-account-range-id packet))
       (snap-hash-object (snap-get-account-range-root packet))
       (snap-hash-object (snap-get-account-range-origin packet))
       (snap-hash-object (snap-get-account-range-limit packet))
       (snap-uint-object (snap-get-account-range-bytes packet))))
     (#x01
      (make-rlp-list
       (snap-uint-object (snap-account-range-id packet))
       (snap-list-object (snap-account-range-accounts packet)
                         #'snap-account-data-object)
       (snap-list-object (snap-account-range-proof packet)
                         #'snap-bytes-object)))
     (#x02
      (make-rlp-list
       (snap-uint-object (snap-get-storage-ranges-id packet))
       (snap-hash-object (snap-get-storage-ranges-root packet))
       (snap-list-object (snap-get-storage-ranges-accounts packet)
                         #'snap-hash-object)
       (snap-bytes-object (snap-get-storage-ranges-origin packet))
       (snap-bytes-object (snap-get-storage-ranges-limit packet))
       (snap-uint-object (snap-get-storage-ranges-bytes packet))))
     (#x03
      (make-rlp-list
       (snap-uint-object (snap-storage-ranges-id packet))
       (snap-list-object
        (snap-storage-ranges-slots packet)
        (lambda (slots)
          (snap-list-object slots #'snap-storage-data-object)))
       (snap-list-object (snap-storage-ranges-proof packet)
                         #'snap-bytes-object)))
     (#x04
      (make-rlp-list
       (snap-uint-object (snap-get-bytecodes-id packet))
       (snap-list-object (snap-get-bytecodes-hashes packet)
                         #'snap-hash-object)
       (snap-uint-object (snap-get-bytecodes-bytes packet))))
     (#x05
      (make-rlp-list
       (snap-uint-object (snap-bytecodes-id packet))
       (snap-list-object (snap-bytecodes-codes packet)
                         #'snap-bytes-object)))
     (#x06
      (make-rlp-list
       (snap-uint-object (snap-get-trie-nodes-id packet))
       (snap-hash-object (snap-get-trie-nodes-root packet))
       (snap-list-object
        (snap-get-trie-nodes-paths packet)
        (lambda (path-set)
          (snap-list-object path-set #'snap-bytes-object)))
       (snap-uint-object (snap-get-trie-nodes-bytes packet))))
     (#x07
      (make-rlp-list
       (snap-uint-object (snap-trie-nodes-id packet))
       (snap-list-object (snap-trie-nodes-nodes packet)
                         #'snap-bytes-object)))
     (otherwise
      (error "unknown snap/1 message id ~D" message-id)))))

(defun decode-snap-message (message-id bytes)
  "Decode one snap/1 message body."
  (case message-id
    (#x00
     (destructuring-bind (id root origin limit byte-limit)
         (snap-fields bytes 5 "GetAccountRange")
       (make-snap-get-account-range
        (snap-uint-field id)
        (snap-hash-field root)
        (snap-hash-field origin)
        (snap-hash-field limit)
        (snap-uint-field byte-limit))))
    (#x01
     (destructuring-bind (id accounts proof)
         (snap-fields bytes 3 "AccountRange")
       (make-snap-account-range
        (snap-uint-field id)
        (snap-list-field accounts #'snap-account-data-field)
        (snap-list-field proof #'snap-bytes-field))))
    (#x02
     (destructuring-bind (id root accounts origin limit byte-limit)
         (snap-fields bytes 6 "GetStorageRanges")
       (make-snap-get-storage-ranges
        (snap-uint-field id)
        (snap-hash-field root)
        (snap-list-field accounts #'snap-hash-field)
        (snap-bytes-field origin)
        (snap-bytes-field limit)
        (snap-uint-field byte-limit))))
    (#x03
     (destructuring-bind (id slots proof)
         (snap-fields bytes 3 "StorageRanges")
       (make-snap-storage-ranges
        (snap-uint-field id)
        (snap-list-field
         slots
         (lambda (slot-set)
           (snap-list-field slot-set #'snap-storage-data-field)))
        (snap-list-field proof #'snap-bytes-field))))
    (#x04
     (destructuring-bind (id hashes byte-limit)
         (snap-fields bytes 3 "GetByteCodes")
       (make-snap-get-bytecodes
        (snap-uint-field id)
        (snap-list-field hashes #'snap-hash-field)
        (snap-uint-field byte-limit))))
    (#x05
     (destructuring-bind (id codes)
         (snap-fields bytes 2 "ByteCodes")
       (make-snap-bytecodes
        (snap-uint-field id)
        (snap-list-field codes #'snap-bytes-field))))
    (#x06
     (destructuring-bind (id root paths byte-limit)
         (snap-fields bytes 4 "GetTrieNodes")
       (make-snap-get-trie-nodes
        (snap-uint-field id)
        (snap-hash-field root)
        (snap-list-field
         paths
         (lambda (path-set)
           (snap-list-field path-set #'snap-bytes-field)))
        (snap-uint-field byte-limit))))
    (#x07
     (destructuring-bind (id nodes)
         (snap-fields bytes 2 "TrieNodes")
       (make-snap-trie-nodes
        (snap-uint-field id)
        (snap-list-field nodes #'snap-bytes-field))))
    (otherwise
     (error "unknown snap/1 message id ~D" message-id))))

(defun snap-request-id (message-id request)
  (case message-id
    (#x00 (snap-get-account-range-id request))
    (#x02 (snap-get-storage-ranges-id request))
    (#x04 (snap-get-bytecodes-id request))
    (#x06 (snap-get-trie-nodes-id request))))

(defun snap-response-id (message-id response)
  (case message-id
    (#x01 (snap-account-range-id response))
    (#x03 (snap-storage-ranges-id response))
    (#x05 (snap-bytecodes-id response))
    (#x07 (snap-trie-nodes-id response))))

(defun snap-serve-request (backend message-id payload)
  "Dispatch a snap request without coupling this layer to a state database.

Returns (VALUES RESPONSE-MESSAGE-ID ENCODED-RESPONSE)."
  (let* ((request (decode-snap-message message-id payload))
         (response-id
           (case message-id
             (#x00
              +snap-message-account-range+)
             (#x02
              +snap-message-storage-ranges+)
             (#x04
              +snap-message-bytecodes+)
             (#x06
              +snap-message-trie-nodes+)
             (otherwise
              (error "snap message ~D is not a request" message-id))))
         (callback
           (case message-id
             (#x00
              (snap-state-backend-account-range backend))
             (#x02
              (snap-state-backend-storage-ranges backend))
             (#x04
              (snap-state-backend-bytecodes backend))
             (#x06
              (snap-state-backend-trie-nodes backend)))))
    (unless callback
      (error "snap state backend does not implement message ~D" message-id))
    (let ((response (funcall callback request)))
      (unless (= (snap-request-id message-id request)
                 (snap-response-id response-id response))
        (error "snap backend response id does not match its request"))
      (values response-id (encode-snap-message response-id response)))))
