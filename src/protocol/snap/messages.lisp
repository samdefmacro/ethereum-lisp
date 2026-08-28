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
(defconstant +snap-max-list-items+ 16384
  "Per-list decode ceiling for snap/1 messages.

This default applies to item-count-bounded messages. Account and storage ranges
have larger message-specific ceilings because their primary bound is the 10 MiB
snap frame and the request's geth-compatible two-MiB soft byte limit.")

(defconstant +snap-max-account-items-per-range+ 65536
  "AccountRange ceiling for a two-MiB request plus its one-item overshoot.")

(defconstant +snap-max-storage-slots-per-range+ 131072
  "Per-list ceiling used only while decoding StorageRanges.

Geth may serve up to 10 percent beyond a requested two-MiB storage budget to
avoid splitting a contract. The larger bound remains message-specific and is
still constrained by the 10 MiB snap frame limit.")

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

(defun snap-fields (bytes expected name &key
                                         (max-list-items
                                           +snap-max-list-items+))
  (let ((fields
          (rlp-list-items
           (rlp-decode (ensure-byte-vector bytes)
                       :max-list-items max-list-items))))
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

(defun snap-rlp-fail (control &rest arguments)
  "Signal the same typed failure as the generic canonical RLP decoder."
  (error 'rlp-error :message (apply #'format nil control arguments)))

(defun snap-rlp-read-long-length (bytes position length-size)
  "Read one canonical RLP long-form length without allocating a byte slice."
  (let ((end (+ position length-size)))
    (when (> end (length bytes))
      (snap-rlp-fail "RLP length overruns input at byte ~D" position))
    (when (zerop (aref bytes position))
      (snap-rlp-fail "RLP length has leading zero at byte ~D" position))
    (values
     (loop with value = 0
           for index from position below end
           do (setf value (+ (ash value 8) (aref bytes index)))
           finally (return value))
     end)))

(defun snap-rlp-item-bounds (bytes start)
  "Return KIND, payload start/end, and next position for one canonical item.

This cursor parser deliberately does not materialize an intermediate RLP tree.
StorageRanges can contain tens of thousands of two-field records, for which the
generic tree plus the later protocol-object map otherwise retain two complete
sets of list cells until decoding returns."
  (when (>= start (length bytes))
    (snap-rlp-fail "No RLP item at byte ~D" start))
  (let ((prefix (aref bytes start)))
    (labels ((bounded (kind payload-start payload-length)
               (let ((payload-end (+ payload-start payload-length)))
                 (when (> payload-end (length bytes))
                   (snap-rlp-fail "RLP item overruns input at byte ~D" start))
                 (values kind payload-start payload-end payload-end))))
      (cond
        ((< prefix #x80)
         (values :string start (1+ start) (1+ start)))
        ((<= prefix #xb7)
         (let ((payload-length (- prefix #x80))
               (payload-start (1+ start)))
           (when (and (= payload-length 1)
                      (< payload-start (length bytes))
                      (< (aref bytes payload-start) #x80))
             (snap-rlp-fail
              "RLP single byte string is not minimally encoded at byte ~D"
              start))
           (bounded :string payload-start payload-length)))
        ((<= prefix #xbf)
         (multiple-value-bind (payload-length payload-start)
             (snap-rlp-read-long-length bytes (1+ start) (- prefix #xb7))
           (when (<= payload-length 55)
             (snap-rlp-fail
              "RLP long string used for short payload at byte ~D" start))
           (bounded :string payload-start payload-length)))
        ((<= prefix #xf7)
         (bounded :list (1+ start) (- prefix #xc0)))
        (t
         (multiple-value-bind (payload-length payload-start)
             (snap-rlp-read-long-length bytes (1+ start) (- prefix #xf7))
           (when (<= payload-length 55)
             (snap-rlp-fail
              "RLP long list used for short payload at byte ~D" start))
           (bounded :list payload-start payload-length)))))))

(defun snap-rlp-list-bounds (bytes start name)
  (multiple-value-bind (kind payload-start payload-end next)
      (snap-rlp-item-bounds bytes start)
    (unless (eq kind :list)
      (snap-rlp-fail "~A must be an RLP list at byte ~D" name start))
    (values payload-start payload-end next)))

(defun snap-rlp-string-at (bytes start name)
  (multiple-value-bind (kind payload-start payload-end next)
      (snap-rlp-item-bounds bytes start)
    (unless (eq kind :string)
      (snap-rlp-fail "~A must be an RLP string at byte ~D" name start))
    (values (subseq bytes payload-start payload-end) next)))

(defun decode-snap-storage-data-at (bytes start)
  (multiple-value-bind (payload-start payload-end next)
      (snap-rlp-list-bounds bytes start "snap storage data")
    (multiple-value-bind (hash body-start)
        (snap-rlp-string-at bytes payload-start "snap storage hash")
      (multiple-value-bind (body body-end)
          (snap-rlp-string-at bytes body-start "snap storage value")
        (unless (= body-end payload-end)
          (snap-rlp-fail
           "snap storage data must contain exactly two fields at byte ~D"
           start))
        (values
         (make-snap-storage-data (snap-hash-field hash) body)
         next)))))

(defun decode-snap-storage-slot-set-at (bytes start)
  (multiple-value-bind (payload-start payload-end next)
      (snap-rlp-list-bounds bytes start "snap storage slot set")
    (loop with position = payload-start
          with count = 0
          with slots = '()
          while (< position payload-end)
          do (when (>= count +snap-max-storage-slots-per-range+)
               (snap-rlp-fail
                "RLP list contains more than ~D items at byte ~D"
                +snap-max-storage-slots-per-range+ payload-start))
             (multiple-value-bind (slot next-position)
                 (decode-snap-storage-data-at bytes position)
               (push slot slots)
               (incf count)
               (setf position next-position))
          finally
             (unless (= position payload-end)
               (snap-rlp-fail
                "snap storage slot set ended at ~D, expected ~D"
                position payload-end))
             (return (values (nreverse slots) next)))))

(defun decode-snap-storage-groups-at (bytes start)
  (multiple-value-bind (payload-start payload-end next)
      (snap-rlp-list-bounds bytes start "snap storage groups")
    (loop with position = payload-start
          with count = 0
          with groups = '()
          while (< position payload-end)
          do (when (>= count +snap-max-storage-slots-per-range+)
               (snap-rlp-fail
                "RLP list contains more than ~D items at byte ~D"
                +snap-max-storage-slots-per-range+ payload-start))
             (multiple-value-bind (group next-position)
                 (decode-snap-storage-slot-set-at bytes position)
               (push group groups)
               (incf count)
               (setf position next-position))
          finally
             (unless (= position payload-end)
               (snap-rlp-fail
                "snap storage groups ended at ~D, expected ~D"
                position payload-end))
             (return (values (nreverse groups) next)))))

(defun decode-snap-storage-proof-at (bytes start)
  (multiple-value-bind (payload-start payload-end next)
      (snap-rlp-list-bounds bytes start "snap storage proof")
    (loop with position = payload-start
          with count = 0
          with proof = '()
          while (< position payload-end)
          do (when (>= count +snap-max-storage-slots-per-range+)
               (snap-rlp-fail
                "RLP list contains more than ~D items at byte ~D"
                +snap-max-storage-slots-per-range+ payload-start))
             (multiple-value-bind (node next-position)
                 (snap-rlp-string-at bytes position "snap storage proof node")
               (push node proof)
               (incf count)
               (setf position next-position))
          finally
             (unless (= position payload-end)
               (snap-rlp-fail
                "snap storage proof ended at ~D, expected ~D"
                position payload-end))
             (return (values (nreverse proof) next)))))

(defun decode-snap-storage-ranges-direct (input)
  "Decode StorageRanges from one cursor, retaining only final protocol values."
  (let ((bytes (ensure-byte-vector input)))
    (multiple-value-bind (payload-start payload-end next)
        (snap-rlp-list-bounds bytes 0 "StorageRanges")
      (unless (= next (length bytes))
        (snap-rlp-fail "Trailing bytes after StorageRanges at byte ~D" next))
      (multiple-value-bind (id groups-start)
          (snap-rlp-string-at bytes payload-start "StorageRanges id")
        (multiple-value-bind (groups proof-start)
            (decode-snap-storage-groups-at bytes groups-start)
          (multiple-value-bind (proof fields-end)
              (decode-snap-storage-proof-at bytes proof-start)
            (unless (= fields-end payload-end)
              (snap-rlp-fail
               "StorageRanges must contain exactly three fields at byte ~D"
               fields-end))
            (make-snap-storage-ranges
             (snap-uint-field id) groups proof)))))))

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
         (snap-fields
          bytes 3 "AccountRange"
          :max-list-items +snap-max-account-items-per-range+)
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
     (decode-snap-storage-ranges-direct bytes))
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
