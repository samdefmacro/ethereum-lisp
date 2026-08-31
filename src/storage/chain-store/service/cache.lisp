(in-package #:ethereum-lisp.chain-store)

;;;; Bounded Engine/P2P side caches.
;;;;
;;;; Cache byte budgets count the exact protocol bytes retained by each value:
;;;; canonical block RLP plus its retained receipt/private side-data encodings,
;;;; or the byte-vector fields of a blob entry.  This is deterministic across
;;;; Common Lisp implementations; implementation-specific heap measurements
;;;; are deliberately not part of admission or eviction.

(defconstant +engine-remote-block-cache-count-limit+ 96)
(defconstant +engine-remote-block-cache-byte-limit+ (* 64 1024 1024))
(defconstant +engine-remote-block-cache-max-age-seconds+ (* 30 60))

(defconstant +engine-forkchoice-target-cache-count-limit+ 96)
(defconstant +engine-forkchoice-target-cache-byte-limit+ (* 96 32))
(defconstant +engine-forkchoice-target-cache-max-age-seconds+ (* 30 60))

(defconstant +engine-invalid-block-hit-eviction+ 128
  "Reconsider an invalid block after this many repeated references.")
(defconstant +engine-invalid-tipsets-cap+ 512
  "Maximum invalid descendant hashes retained in memory.")
(defconstant +engine-invalid-tipsets-byte-limit+ (* 64 1024 1024))
(defconstant +engine-invalid-tipsets-max-age-seconds+ (* 60 60))

(defconstant +engine-prepared-payload-cache-count-limit+ 10)
(defconstant +engine-prepared-payload-cache-byte-limit+ (* 128 1024 1024))
(defconstant +engine-prepared-payload-cache-max-age-seconds+ (* 5 60))

(defconstant +engine-blob-sidecar-cache-count-limit+ 512)
(defconstant +engine-blob-sidecar-cache-byte-limit+ (* 64 1024 1024))
(defconstant +engine-blob-sidecar-cache-max-age-seconds+ (* 3 60 60))

(defvar *engine-payload-store-track-durable-cache-deletions-p* nil
  "When true, durable remote/invalid cache evictions leave changed-key tombstones.")

(defvar *engine-payload-store-suppress-durable-cache-deletions-p* nil
  "Internal recovery scope that suppresses tombstones for records it deletes itself.")

(defun engine-payload-store-enable-durable-cache-change-tracking (store)
  (setf store (chain-store-require-memory-store store)
        (memory-chain-store-durable-cache-change-tracking-enabled-p store) t)
  store)

(defun engine-payload-store-durable-cache-change-tracking-enabled-p (store)
  (memory-chain-store-durable-cache-change-tracking-enabled-p
   (chain-store-require-memory-store store)))

(defun engine-payload-store-cache-kind (kind)
  (case kind
    ((:remote :remote-block) :remote-block)
    ((:forkchoice :forkchoice-target :forkchoice-sync-target)
     :forkchoice-target)
    ((:invalid :invalid-tipset) :invalid)
    ((:prepared :prepared-payload) :prepared-payload)
    ((:blob :blob-sidecar :sidecar) :sidecar)
    (otherwise
     (block-validation-fail "Unknown chain-store cache kind ~S" kind))))

(defun engine-payload-store-cache-tables (store kind)
  (setf store (chain-store-require-memory-store store)
        kind (engine-payload-store-cache-kind kind))
  (ecase kind
    (:remote-block
     (values (memory-chain-store-remote-blocks store)
             (memory-chain-store-remote-block-metadata store)))
    (:forkchoice-target
     (values (memory-chain-store-forkchoice-sync-targets store)
             (memory-chain-store-forkchoice-sync-target-metadata store)))
    (:invalid
     (values (memory-chain-store-invalid-tipsets store)
             (memory-chain-store-invalid-tipset-metadata store)))
    (:prepared-payload
     (values (memory-chain-store-prepared-payloads store)
             (memory-chain-store-prepared-payload-metadata store)))
    (:sidecar
     (values (memory-chain-store-blob-sidecars store)
             (memory-chain-store-blob-sidecar-metadata store)))))

(defun engine-payload-store-cache-policy (kind)
  (ecase (engine-payload-store-cache-kind kind)
    (:remote-block
     (values +engine-remote-block-cache-count-limit+
             +engine-remote-block-cache-byte-limit+
             +engine-remote-block-cache-max-age-seconds+))
    (:forkchoice-target
     (values +engine-forkchoice-target-cache-count-limit+
             +engine-forkchoice-target-cache-byte-limit+
             +engine-forkchoice-target-cache-max-age-seconds+))
    (:invalid
     (values +engine-invalid-tipsets-cap+
             +engine-invalid-tipsets-byte-limit+
             +engine-invalid-tipsets-max-age-seconds+))
    (:prepared-payload
     (values +engine-prepared-payload-cache-count-limit+
             +engine-prepared-payload-cache-byte-limit+
             +engine-prepared-payload-cache-max-age-seconds+))
    (:sidecar
     (values +engine-blob-sidecar-cache-count-limit+
             +engine-blob-sidecar-cache-byte-limit+
             +engine-blob-sidecar-cache-max-age-seconds+))))

(defun engine-payload-store-cache-time (now)
  (unless (and (integerp now) (not (minusp now)))
    (block-validation-fail "Chain-store cache time must be non-negative"))
  now)

(defun engine-payload-store-cache-block-number (block-number)
  (unless (or (null block-number)
              (and (integerp block-number) (not (minusp block-number))))
    (block-validation-fail
     "Chain-store cache block number must be non-negative or NIL"))
  block-number)

(defun engine-payload-store-byte-vector-list-size (values)
  (loop for value in values
        sum (length (ensure-byte-vector value))))

(defun engine-payload-store-block-encoded-bytes (block)
  "Return the exact retained protocol-byte accounting size of BLOCK."
  (+ (length (block-rlp block))
     (loop for receipt in (block-receipts block)
           sum (length (receipt-encoding receipt)))
     (engine-payload-store-byte-vector-list-size
      (or (block-requests block) '()))
     (let ((encoded (block-encoded-block-access-list block)))
       (if encoded (length (ensure-byte-vector encoded)) 0))))

(defun engine-payload-store-blob-and-proofs-encoded-bytes (value)
  ;; This is byte-for-byte the storage record encoding, defined here to keep
  ;; storage-core independent of the persistence-adapter layer.
  (length
   (rlp-encode
    (make-rlp-list
     (ensure-byte-vector (engine-blob-and-proofs-blob value))
     (ensure-byte-vector (engine-blob-and-proofs-commitment value))
     (ensure-byte-vector (engine-blob-and-proofs-proof value))
     (apply #'make-rlp-list
            (mapcar #'ensure-byte-vector
                    (or (engine-blob-and-proofs-cell-proofs value) '())))))))

(defun engine-payload-store-blob-sidecar-encoded-bytes (sidecar)
  (if sidecar
      (length
       (rlp-encode
        (make-rlp-list
         (apply #'make-rlp-list
                (mapcar #'ensure-byte-vector (blob-sidecar-blobs sidecar)))
         (apply #'make-rlp-list
                (mapcar #'ensure-byte-vector
                        (blob-sidecar-commitments sidecar)))
         (apply #'make-rlp-list
                (mapcar #'ensure-byte-vector (blob-sidecar-proofs sidecar))))))
      0))

(defun engine-payload-store-optional-hash-size (hash)
  (if hash (length (hash32-bytes hash)) 0))

(defun engine-payload-store-optional-address-size (address)
  (if address (length (address-bytes address)) 0))

(defun engine-payload-store-optional-rlp-integer-size (value)
  (if (null value) 0 (length (rlp-encode value))))

(defun engine-payload-store-payload-attributes-encoded-bytes (attributes)
  (if (null attributes)
      0
      (+ (engine-payload-store-optional-rlp-integer-size
          (payload-attributes-v1-timestamp attributes))
         (engine-payload-store-optional-hash-size
          (payload-attributes-v1-prev-randao attributes))
         (engine-payload-store-optional-address-size
          (payload-attributes-v1-suggested-fee-recipient attributes))
         (if (payload-attributes-v1-withdrawals-present-p attributes)
             (length
              (rlp-encode
               (apply #'make-rlp-list
                      (mapcar #'withdrawal-rlp-object
                              (or (payload-attributes-v1-withdrawals attributes)
                                  '())))))
             0)
         (engine-payload-store-optional-hash-size
          (and (payload-attributes-v1-parent-beacon-root-present-p attributes)
               (payload-attributes-v1-parent-beacon-root attributes)))
         (engine-payload-store-optional-rlp-integer-size
          (and (payload-attributes-v1-slot-number-present-p attributes)
               (payload-attributes-v1-slot-number attributes)))
         (engine-payload-store-optional-rlp-integer-size
          (and (payload-attributes-v1-target-gas-limit-present-p attributes)
               (payload-attributes-v1-target-gas-limit attributes)))
         ;; Presence flags are retained state even when their value is absent.
         4)))

(defun engine-payload-store-prepared-payload-encoded-bytes (prepared-payload)
  (+ (length
      (ensure-byte-vector
       (engine-prepared-payload-payload-id prepared-payload)))
     (engine-payload-store-optional-rlp-integer-size
      (engine-prepared-payload-version prepared-payload))
     (engine-payload-store-block-encoded-bytes
      (engine-prepared-payload-block prepared-payload))
     (engine-payload-store-blob-sidecar-encoded-bytes
      (engine-prepared-payload-blobs-bundle prepared-payload))
     (engine-payload-store-optional-hash-size
      (engine-prepared-payload-parent-hash prepared-payload))
     (engine-payload-store-payload-attributes-encoded-bytes
      (engine-prepared-payload-payload-attributes prepared-payload))
     (engine-payload-store-optional-rlp-integer-size
      (engine-prepared-payload-gas-limit-target prepared-payload))
     (engine-payload-store-optional-hash-size
      (engine-prepared-payload-candidate-transactions-root prepared-payload))
     1))

(defun engine-payload-store-cache-value-encoded-bytes (kind value)
  (ecase (engine-payload-store-cache-kind kind)
    ((:remote-block :invalid)
     (engine-payload-store-block-encoded-bytes value))
    (:forkchoice-target
     (length (hash32-bytes value)))
    (:prepared-payload
     (engine-payload-store-prepared-payload-encoded-bytes value))
    (:sidecar
     (engine-payload-store-blob-and-proofs-encoded-bytes value))))

(defun engine-payload-store-cache-value-block-number (kind value)
  (ecase (engine-payload-store-cache-kind kind)
    ((:remote-block :invalid)
     (block-header-number (block-header value)))
    (:prepared-payload
     (block-header-number
      (block-header (engine-prepared-payload-block value))))
    ((:forkchoice-target :sidecar) nil)))

(defun engine-payload-store-cache-durable-deletion-table (store kind)
  (ecase (engine-payload-store-cache-kind kind)
    (:remote-block
     (memory-chain-store-remote-block-durable-deletions store))
    (:invalid
     (memory-chain-store-invalid-tipset-durable-deletions store))
    ((:forkchoice-target :prepared-payload :sidecar) nil)))

(defun engine-payload-store-cache-durable-owner-key-p (kind key value)
  (ecase (engine-payload-store-cache-kind kind)
    (:remote-block t)
    (:invalid
     (and (typep value 'ethereum-block)
          (string= key (engine-payload-store-key (block-hash value)))))
    ((:forkchoice-target :prepared-payload :sidecar) nil)))

(defun engine-payload-store-cache-cancel-durable-deletion
    (store kind key value)
  (let ((table
          (engine-payload-store-cache-durable-deletion-table store kind)))
    (when (and table
               (engine-payload-store-cache-durable-owner-key-p
                kind key value))
      (chain-store-journal-remhash table key))))

(defun engine-payload-store-cache-note-durable-deletion
    (store kind key value)
  (let ((table
          (engine-payload-store-cache-durable-deletion-table store kind)))
    (when (and (not *engine-payload-store-suppress-durable-cache-deletions-p*)
               (or *engine-payload-store-track-durable-cache-deletions-p*
                   (memory-chain-store-durable-cache-change-tracking-enabled-p
                    store))
               table
               (engine-payload-store-cache-durable-owner-key-p
                kind key value))
      (chain-store-journal-puthash table key t))))

(defun engine-payload-store-cache-put
    (store kind key value now &optional block-number)
  (setf store (chain-store-require-memory-store store)
        kind (engine-payload-store-cache-kind kind)
        now (engine-payload-store-cache-time now)
        block-number
        (engine-payload-store-cache-block-number block-number))
  (multiple-value-bind (values metadata)
      (engine-payload-store-cache-tables store kind)
    (let* ((prior (gethash key metadata))
           (inserted-at
             (if (typep prior 'chain-store-cache-entry-metadata)
                 (chain-store-cache-entry-metadata-inserted-at prior)
                 now))
           (effective-block-number
             (or block-number
                 (engine-payload-store-cache-value-block-number kind value)
                 (and (typep prior 'chain-store-cache-entry-metadata)
                      (chain-store-cache-entry-metadata-block-number prior)))))
      ;; The timestamp is intentionally retained on replacement. Replaying a
      ;; duplicate cache entry cannot keep it alive indefinitely.
      (chain-store-journal-puthash values key value)
      (chain-store-journal-puthash
       metadata key
       (make-chain-store-cache-entry-metadata
        :inserted-at inserted-at
        :encoded-bytes
        (engine-payload-store-cache-value-encoded-bytes kind value)
        :block-number effective-block-number))))
  (engine-payload-store-cache-cancel-durable-deletion
   store kind key value)
  value)

(defun engine-payload-store-cache-invalid-block-still-referenced-p
    (table invalid-key)
  (loop for candidate being the hash-values of table
        thereis
        (and (typep candidate 'ethereum-block)
             (string= invalid-key
                      (engine-payload-store-key (block-hash candidate))))))

(defun engine-payload-store-cache-remove-key (store kind key)
  (setf store (chain-store-require-memory-store store)
        kind (engine-payload-store-cache-kind kind))
  (multiple-value-bind (values metadata)
      (engine-payload-store-cache-tables store kind)
    (multiple-value-bind (old present-p) (gethash key values)
      (when present-p
        (engine-payload-store-cache-note-durable-deletion
         store kind key old))
      (chain-store-journal-remhash values key)
      (chain-store-journal-remhash metadata key)
      (when (and present-p (eq kind :invalid)
                 (typep old 'ethereum-block))
        (let ((invalid-key
                (engine-payload-store-key (block-hash old))))
          (unless
              (engine-payload-store-cache-invalid-block-still-referenced-p
               values invalid-key)
            (chain-store-journal-remhash
             (memory-chain-store-invalid-block-hits store)
             invalid-key))))
      present-p)))

(defun engine-payload-store-synchronize-cache-metadata (store kind now)
  "Reconcile metadata for legacy/imported raw table entries before pruning."
  (setf store (chain-store-require-memory-store store)
        kind (engine-payload-store-cache-kind kind)
        now (engine-payload-store-cache-time now))
  (multiple-value-bind (values metadata)
      (engine-payload-store-cache-tables store kind)
    (let ((orphaned-metadata nil))
      (maphash (lambda (key entry)
                 (declare (ignore entry))
                 (unless (nth-value 1 (gethash key values))
                   (push key orphaned-metadata)))
               metadata)
      (dolist (key orphaned-metadata)
        (chain-store-journal-remhash metadata key)))
    (maphash
     (lambda (key value)
       (let ((prior (gethash key metadata)))
         ;; Cache values are immutable and every supported replacement goes
         ;; through CACHE-PUT, which recomputes its size. Only legacy/raw
         ;; imports lack metadata; do not re-encode every bounded entry on
         ;; every read merely to rediscover the same byte count.
         (unless (typep prior 'chain-store-cache-entry-metadata)
           (chain-store-journal-puthash
            metadata key
            (make-chain-store-cache-entry-metadata
             :inserted-at now
             :encoded-bytes
             (engine-payload-store-cache-value-encoded-bytes kind value)
             :block-number
             (engine-payload-store-cache-value-block-number kind value))))))
     values))
  store)

(defun engine-payload-store-cache-key< (left right metadata)
  (let* ((left-metadata (gethash left metadata))
         (right-metadata (gethash right metadata))
         (left-time
           (chain-store-cache-entry-metadata-inserted-at left-metadata))
         (right-time
           (chain-store-cache-entry-metadata-inserted-at right-metadata)))
    (or (< left-time right-time)
        (and (= left-time right-time)
             (string< left right)))))

(defun engine-payload-store-cache-ordered-keys (values metadata)
  (sort (loop for key being the hash-keys of values collect key)
        (lambda (left right)
          (engine-payload-store-cache-key< left right metadata))))

(defun engine-payload-store-cache-entry-expired-p (metadata now max-age)
  (and max-age
       (>= now
           (+ (chain-store-cache-entry-metadata-inserted-at metadata)
              max-age))))

(defun engine-payload-store-cache-entry-finalized-p
    (metadata finalized-number)
  (let ((block-number
          (chain-store-cache-entry-metadata-block-number metadata)))
    (and finalized-number block-number
         (<= block-number finalized-number))))

(defun engine-payload-store-cache-byte-count (metadata)
  (loop for entry being the hash-values of metadata
        sum (chain-store-cache-entry-metadata-encoded-bytes entry)))

(defun engine-payload-store-enforce-cache-bounds
    (store kind now finalized-number
     &key count-limit byte-limit max-age)
  "Prune one cache deterministically.

Finalized and expired entries are removed unconditionally. If count or byte
budgets are still exceeded, the oldest `(inserted-at, key)` entries go first.
The explicit limits are an internal test seam; omitted values use the public
production policy."
  (setf store (chain-store-require-memory-store store)
        kind (engine-payload-store-cache-kind kind)
        now (engine-payload-store-cache-time now)
        finalized-number
        (engine-payload-store-cache-block-number finalized-number))
  (multiple-value-bind (default-count default-bytes default-age)
      (engine-payload-store-cache-policy kind)
    (setf count-limit (if (null count-limit) default-count count-limit)
          byte-limit (if (null byte-limit) default-bytes byte-limit)
          max-age (if (null max-age) default-age max-age)))
  (unless (and (integerp count-limit) (not (minusp count-limit))
               (integerp byte-limit) (not (minusp byte-limit))
               (integerp max-age) (not (minusp max-age)))
    (block-validation-fail
     "Chain-store cache limits must be non-negative integers"))
  (engine-payload-store-synchronize-cache-metadata store kind now)
  (multiple-value-bind (values metadata)
      (engine-payload-store-cache-tables store kind)
    ;; Staleness is semantic rather than pressure-dependent: an expired or
    ;; finalized object never remains merely because the cache is below cap.
    (dolist (key (engine-payload-store-cache-ordered-keys values metadata))
      (let ((entry (gethash key metadata)))
        (when (or (engine-payload-store-cache-entry-finalized-p
                   entry finalized-number)
                  (engine-payload-store-cache-entry-expired-p
                   entry now max-age))
          (engine-payload-store-cache-remove-key store kind key))))
    (loop while (or (> (hash-table-count values) count-limit)
                    (> (engine-payload-store-cache-byte-count metadata)
                       byte-limit))
          do (let ((key
                     (first
                      (engine-payload-store-cache-ordered-keys
                       values metadata))))
               (unless key (return))
               (engine-payload-store-cache-remove-key store kind key))))
  store)

(defun engine-payload-store-prune-caches
    (store &key (now (unix-time)) finalized-number)
  "Apply count, exact-byte, age and optional finality bounds to all caches.

FINALIZED-NUMBER is explicit so the forkchoice transition can pass the height
it durably accepted; cache code never guesses finality from an uncommitted
head. Sidecars/forkchoice targets participate in finality pruning when their
put call supplied BLOCK-NUMBER."
  (setf store (chain-store-require-memory-store store)
        now (engine-payload-store-cache-time now)
        finalized-number
        (engine-payload-store-cache-block-number finalized-number))
  (dolist (kind '(:remote-block :forkchoice-target :invalid
                  :prepared-payload :sidecar))
    (engine-payload-store-enforce-cache-bounds
     store kind now finalized-number))
  store)

(defun engine-payload-store-cache-statistics
    (store kind &key (now (unix-time)))
  "Enforce CACHE-KIND's current non-finality bounds, then return count/bytes."
  (setf store (chain-store-require-memory-store store)
        kind (engine-payload-store-cache-kind kind))
  (engine-payload-store-enforce-cache-bounds store kind now nil)
  (multiple-value-bind (values metadata)
      (engine-payload-store-cache-tables store kind)
    (values (hash-table-count values)
            (engine-payload-store-cache-byte-count metadata))))

(defun engine-payload-store-remote-block (store hash &key (now (unix-time)))
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-enforce-cache-bounds
   store :remote-block now nil)
  (engine-payload-store-copy-block
   (gethash (engine-payload-store-key hash)
            (memory-chain-store-remote-blocks store))))

(defun engine-payload-store-remote-block-list
    (store &key (now (unix-time)))
  "Return copied remote blocks after enforcing count/byte/age bounds."
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-enforce-cache-bounds
   store :remote-block now nil)
  (loop for block being the hash-values
          of (memory-chain-store-remote-blocks store)
        collect (engine-payload-store-copy-block block)))

(defun engine-payload-store-put-remote-block
    (store block &key (now (unix-time)))
  (setf store (chain-store-require-memory-store store))
  (unless (typep block 'ethereum-block)
    (block-validation-fail "Engine remote block cache value must be a block"))
  (engine-payload-store-synchronize-cache-metadata store :remote-block now)
  (engine-payload-store-cache-put
   store :remote-block
   (engine-payload-store-key (block-hash block))
   (engine-payload-store-copy-block block)
   now)
  (engine-payload-store-enforce-cache-bounds
   store :remote-block now nil)
  block)

(defun engine-payload-store-remove-remote-block (store hash)
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-cache-remove-key
   store :remote-block (engine-payload-store-key hash)))

(defun engine-payload-store-put-forkchoice-sync-target
    (store hash &key (now (unix-time)) block-number)
  (setf store (chain-store-require-memory-store store))
  (unless (typep hash 'hash32)
    (block-validation-fail
     "Engine forkchoice sync target must be a 32-byte hash"))
  (engine-payload-store-synchronize-cache-metadata
   store :forkchoice-target now)
  (engine-payload-store-cache-put
   store :forkchoice-target
   (engine-payload-store-key hash)
   (make-hash32 (copy-seq (hash32-bytes hash)))
   now block-number)
  (engine-payload-store-enforce-cache-bounds
   store :forkchoice-target now nil)
  hash)

(defun engine-payload-store-remove-forkchoice-sync-target (store hash)
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-cache-remove-key
   store :forkchoice-target (engine-payload-store-key hash)))

(defun engine-payload-store-forkchoice-sync-targets
    (store &key (now (unix-time)))
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-enforce-cache-bounds
   store :forkchoice-target now nil)
  (loop for hash being the hash-values
          of (memory-chain-store-forkchoice-sync-targets store)
        collect (make-hash32 (copy-seq (hash32-bytes hash)))))

(defun engine-payload-store-prune-prepared-payloads-for-block
    (store block-key &key (now (unix-time)))
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-synchronize-cache-metadata
   store :prepared-payload now)
  (let ((stale-payload-id-keys nil))
    (maphash
     (lambda (payload-id-key prepared-payload)
       (when (string= block-key
                      (engine-payload-store-key
                       (block-hash
                        (engine-prepared-payload-block prepared-payload))))
         (push payload-id-key stale-payload-id-keys)))
     (memory-chain-store-prepared-payloads store))
    (dolist (payload-id-key stale-payload-id-keys)
      (engine-payload-store-cache-remove-key
       store :prepared-payload payload-id-key))))

(defun engine-payload-store-mark-invalid
    (store invalid-block &key head-hash (now (unix-time)))
  (setf store (chain-store-require-memory-store store))
  (unless (typep invalid-block 'ethereum-block)
    (block-validation-fail "Engine payload invalid marker must be a block"))
  (let* ((invalid-hash (block-hash invalid-block))
         (invalid-key (engine-payload-store-key invalid-hash))
         (key (engine-payload-store-key (or head-hash invalid-hash)))
         (tipsets (memory-chain-store-invalid-tipsets store))
         (hits (memory-chain-store-invalid-block-hits store)))
    (engine-payload-store-remove-remote-block store invalid-hash)
    (engine-payload-store-prune-prepared-payloads-for-block
     store invalid-key :now now)
    (when head-hash
      (engine-payload-store-remove-remote-block store head-hash)
      (engine-payload-store-prune-prepared-payloads-for-block
       store key :now now))
    (engine-payload-store-synchronize-cache-metadata store :invalid now)
    (engine-payload-store-cache-put
     store :invalid key
     (engine-payload-store-copy-block invalid-block)
     now)
    (engine-payload-store-enforce-cache-bounds store :invalid now nil)
    (when (and (string= key invalid-key) (gethash key tipsets))
      (chain-store-journal-puthash
       hits invalid-key (1+ (gethash invalid-key hits 0))))
    invalid-block))

(defun engine-payload-store-invalid-block
    (store hash &key (now (unix-time)))
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-enforce-cache-bounds store :invalid now nil)
  (engine-payload-store-copy-block
   (gethash (engine-payload-store-key hash)
            (memory-chain-store-invalid-tipsets store))))

(defun engine-payload-store-invalid-ancestor
    (store hash &key (now (unix-time)) (walk-remote-p t))
  "Return HASH's invalid ancestor, evicting a repeatedly hit verdict.

Eviction removes every descendant that points at the same rejected block so a
transient or raced verdict can be retried without restarting the node."
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-enforce-cache-bounds store :invalid now nil)
  (let ((tipsets (memory-chain-store-invalid-tipsets store))
        (hits (memory-chain-store-invalid-block-hits store)))
    (labels ((return-invalid (invalid-block)
               (let* ((invalid-key
                        (engine-payload-store-key (block-hash invalid-block)))
                      (hit-count (1+ (gethash invalid-key hits 0))))
                 (chain-store-journal-puthash hits invalid-key hit-count)
                 (when (>= hit-count +engine-invalid-block-hit-eviction+)
                   (let ((stale-keys nil))
                     (maphash
                      (lambda (descendant-key candidate)
                        (when (string= invalid-key
                                       (engine-payload-store-key
                                        (block-hash candidate)))
                          (push descendant-key stale-keys)))
                      tipsets)
                     (dolist (stale-key (sort stale-keys #'string<))
                       (engine-payload-store-cache-remove-key
                        store :invalid stale-key)))
                   (chain-store-journal-remhash hits invalid-key)
                   (return-from engine-payload-store-invalid-ancestor nil))
                 (engine-payload-store-copy-block invalid-block))))
      ;; A syncing Engine caller may know only a descendant while the P2P
      ;; downloader has already retained its unexecuted parents.  Walking that
      ;; bounded remote cache makes the previously verified INVALID verdict
      ;; visible to newPayload/forkchoice instead of answering SYNCING until a
      ;; peer happens to resend every intervening body.  The walk is bounded by
      ;; the cache's own entry limit and rejects cycles defensively.
      (let ((current hash)
            (seen (make-hash-table :test 'equal)))
        (loop repeat (if walk-remote-p
                         (1+ +engine-remote-block-cache-count-limit+)
                         1)
              for key = (engine-payload-store-key current)
              do (when (gethash key seen)
                   (return nil))
                 (setf (gethash key seen) t)
                 (let ((invalid-block (gethash key tipsets)))
                   (when invalid-block
                     (return (return-invalid invalid-block))))
                 (unless walk-remote-p
                   (return nil))
                 (let ((block
                         (or (chain-store-known-block store current)
                             (engine-payload-store-remote-block
                              store current :now now))))
                   (unless block
                     (return nil))
                   (let ((parent-hash
                           (block-header-parent-hash (block-header block))))
                     (unless (hash32-p parent-hash)
                       (return nil))
                     (setf current parent-hash))))))))

(defun engine-payload-id-key (payload-id)
  (let ((bytes (ensure-byte-vector payload-id)))
    (unless (= 8 (length bytes))
      (block-validation-fail "Engine payload id must be 8 bytes"))
    (bytes-to-hex bytes)))

(defun engine-payload-id-to-hex (payload-id)
  (engine-payload-id-key payload-id))

(defun engine-payload-store-put-prepared-payload
    (store prepared-payload &key (now (unix-time)))
  (setf store (chain-store-require-memory-store store))
  (validate-engine-prepared-payload prepared-payload)
  (engine-payload-store-synchronize-cache-metadata
   store :prepared-payload now)
  ;; A post-state can be much larger than the encoded payload whose byte
  ;; budget protects this cache.  Retain an execution shortcut for only the
  ;; newest payload environment; older payload ids remain fully usable and
  ;; safely fall back to ordinary newPayload execution.
  (when (engine-prepared-payload-execution-state prepared-payload)
    (loop for existing
            being the hash-values of
              (memory-chain-store-prepared-payloads store)
          do (setf (engine-prepared-payload-execution-state existing) nil)))
  (let ((stored-payload
          (engine-payload-store-copy-prepared-payload prepared-payload)))
    (engine-payload-store-cache-put
     store :prepared-payload
     (engine-payload-id-key
      (engine-prepared-payload-payload-id stored-payload))
     stored-payload now))
  (engine-payload-store-enforce-cache-bounds
   store :prepared-payload now nil)
  prepared-payload)

(defun engine-payload-store-prepared-payload
    (store payload-id &key (now (unix-time)))
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-enforce-cache-bounds
   store :prepared-payload now nil)
  (engine-payload-store-copy-prepared-payload
   (gethash (engine-payload-id-key payload-id)
            (memory-chain-store-prepared-payloads store))))

(defun engine-payload-store-prepared-payload-list
    (store &key (now (unix-time)))
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-enforce-cache-bounds
   store :prepared-payload now nil)
  (loop for prepared-payload
          being the hash-values of
            (memory-chain-store-prepared-payloads store)
        collect
        (engine-payload-store-copy-prepared-payload prepared-payload)))

(defun chain-store-put-prepared-payload (store prepared-payload)
  (engine-payload-store-put-prepared-payload
   (chain-store-require-memory-store store)
   prepared-payload))

(defun chain-store-prepared-payload (store payload-id)
  (engine-payload-store-prepared-payload
   (chain-store-require-memory-store store)
   payload-id))

(defun chain-store-prepared-payloads (store)
  (engine-payload-store-prepared-payload-list
   (chain-store-require-memory-store store)))

(defun engine-payload-store-put-blob-sidecar
    (store sidecar &key (now (unix-time)) block-number)
  (setf store (chain-store-require-memory-store store))
  (unless (typep sidecar 'blob-sidecar)
    (block-validation-fail
     "Engine blob sidecar store value must be a blob sidecar"))
  (engine-payload-store-cache-block-number block-number)
  (when (blob-sidecar-blobs sidecar)
    ;; A sidecar entering the live store is trusted by getBlobs and devp2p
    ;; callers. Verify either the EIP-4844 blob proof or every EIP-7594 cell
    ;; proof before making it visible.
    (validate-blob-sidecar-fields
     sidecar :require-proof-verification t))
  (let ((hashes (blob-sidecar-versioned-hashes sidecar))
        (blobs (blob-sidecar-blobs sidecar))
        (proofs (blob-sidecar-proofs sidecar)))
    (unless (= (length hashes) (length blobs))
      (block-validation-fail
       "Engine blob sidecar blobs and commitments must have matching lengths"))
    (unless (or (= (length proofs) (length blobs))
                (= (length proofs)
                   (* (length blobs) +cell-proofs-per-blob+)))
      (block-validation-fail
       "Engine blob sidecar proofs must be one per blob or cell proofs per blob"))
    (engine-payload-store-synchronize-cache-metadata store :sidecar now)
    (loop for versioned-hash in hashes
          for blob in blobs
          for index from 0
          for proof = (if (= (length proofs) (length blobs))
                          (nth index proofs)
                          (nth (* index +cell-proofs-per-blob+) proofs))
          for cell-proofs = (when (= (length proofs)
                                     (* (length blobs)
                                        +cell-proofs-per-blob+))
                              (subseq proofs
                                      (* index +cell-proofs-per-blob+)
                                      (* (1+ index)
                                         +cell-proofs-per-blob+)))
          for stored =
            (make-engine-blob-and-proofs
             :blob (maybe-copy-bytes blob)
             :commitment
             (maybe-copy-bytes
              (nth index (blob-sidecar-commitments sidecar)))
             :proof (maybe-copy-bytes proof)
             :cell-proofs (mapcar #'maybe-copy-bytes cell-proofs))
          do (engine-payload-store-cache-put
              store :sidecar
              (engine-payload-store-key versioned-hash)
              stored now block-number))
    (engine-payload-store-enforce-cache-bounds store :sidecar now nil))
  sidecar)

(defun engine-payload-store-remove-blob-sidecar (store versioned-hash)
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-cache-remove-key
   store :sidecar (engine-payload-store-key versioned-hash)))

(defun engine-payload-store-blob-and-proofs-v1
    (store versioned-hash &key (now (unix-time)))
  (setf store (chain-store-require-memory-store store))
  (engine-payload-store-enforce-cache-bounds store :sidecar now nil)
  (let ((cached
          (gethash (engine-payload-store-key versioned-hash)
                   (memory-chain-store-blob-sidecars store))))
    (if cached
        (engine-payload-store-copy-blob-and-proofs cached)
        (multiple-value-bind (persisted present-p)
            (chain-store-backing-blob-sidecar store versioned-hash)
          (and present-p
               (engine-payload-store-copy-blob-and-proofs persisted))))))

(defun engine-payload-store-blob-and-proofs-v2
    (store versioned-hash &key (now (unix-time)))
  (let ((blob-and-proofs
          (engine-payload-store-blob-and-proofs-v1
           store versioned-hash :now now)))
    (when (and blob-and-proofs
               (= +cell-proofs-per-blob+
                  (length
                   (engine-blob-and-proofs-cell-proofs blob-and-proofs))))
      blob-and-proofs)))

(defun engine-payload-store-durable-blob-and-proofs-v2
    (store versioned-hash)
  "Read one cell-proof blob directly from STORE's durable backing.

Unlike ENGINE-PAYLOAD-STORE-BLOB-AND-PROOFS-V2, this does not inspect or
advance the mutable sidecar cache. It is therefore suitable for a best-effort
Engine read while the node's ordinary store guard is owned by long-running
state synchronization."
  (setf store (chain-store-require-memory-store store))
  (multiple-value-bind (blob-and-proofs present-p)
      (chain-store-backing-blob-sidecar store versioned-hash)
    (when (and present-p
               (= +cell-proofs-per-blob+
                  (length
                   (engine-blob-and-proofs-cell-proofs blob-and-proofs))))
      (engine-payload-store-copy-blob-and-proofs blob-and-proofs))))
