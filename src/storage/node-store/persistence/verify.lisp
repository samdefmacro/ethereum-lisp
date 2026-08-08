(in-package #:ethereum-lisp.node-store.persistence)

;;;; Offline, bounded-memory integrity audit of a chain database.
;;;;
;;;; The node import path fail-stops on the first defect. This audit instead
;;;; names every record-level defect it can establish without re-executing the
;;;; chain. Every namespace is streamed through an explicitly closed iterator;
;;;; cross-record checks use point lookups, so retained history does not become
;;;; a Lisp list or hash table merely because an operator asked for a report.

(defstruct (node-store-database-finding
            (:constructor make-node-store-database-finding
                (kind identifier message)))
  "One defect. KIND is the record kind it was found under (or :SCHEMA-VERSION
for the marker itself), IDENTIFIER the record's key bytes or NIL."
  kind
  identifier
  message)

(defun node-store-database-finding-description (finding)
  (format nil "~(~A~)~@[ ~A~]: ~A"
          (node-store-database-finding-kind finding)
          (let ((identifier (node-store-database-finding-identifier finding)))
            (and identifier (bytes-to-hex identifier)))
          (node-store-database-finding-message finding)))

(defmacro with-node-store-database-finding
    ((findings kind identifier) &body body)
  "Run BODY, turning a validation failure into one finding on FINDINGS."
  (let ((condition (gensym "CONDITION")))
    `(handler-case (progn ,@body)
       (block-validation-error (,condition)
         (push (make-node-store-database-finding
                ,kind ,identifier
                (block-validation-error-message ,condition))
               ,findings)
         nil)
       (rlp-error (,condition)
         (push (make-node-store-database-finding
                ,kind ,identifier
                (format nil "record is not valid RLP: ~A" ,condition))
               ,findings)
         nil))))

(defun node-store-call-with-chain-records (database kind function)
  "Call FUNCTION with IDENTIFIER and VALUE for each KIND record, in key order."
  (multiple-value-bind (iterator close-iterator)
      (kv-iterator
       database
       :start (kv-chain-record-kind-start-key kind)
       :end (kv-chain-record-kind-end-key kind))
    (unwind-protect
         (loop
           (multiple-value-bind (key value present-p)
               (funcall iterator)
             (unless present-p
               (return))
             (funcall function
                      (kv-chain-record-key-identifier kind key)
                      value)))
      (when close-iterator
        (funcall close-iterator)))))

(defun node-store-block-record-present-p (database identifier)
  (nth-value 1 (kv-get-chain-record database :block identifier)))

(defun node-store-verify-code-records (database findings)
  "Every :CODE record must be filed under the hash of its own body."
  (node-store-call-with-chain-records
   database :code
   (lambda (identifier code)
     (cond
       ((/= 32 (length identifier))
        (push (make-node-store-database-finding
               :code identifier "code record key is not a 32-byte hash")
              findings))
       ((not (bytes= identifier (node-store-code-reference code)))
        (push (make-node-store-database-finding
               :code identifier "code record does not hash to its key")
              findings)))))
  findings)

(declaim
 (ftype (function (t t t t) t) node-store-verify-trie-node-object))

(defun node-store-verify-trie-child-reference
    (database findings owner-identifier reference)
  (cond
    ((rlp-list-p reference)
     (node-store-verify-trie-node-object
      database findings owner-identifier reference))
    ((and (byte-vector-p reference) (zerop (length reference)))
     findings)
    ((and (byte-vector-p reference) (= 32 (length reference)))
     (unless (nth-value 1
                       (kv-get-chain-record database :trie-node reference))
       (push (make-node-store-database-finding
              :trie-node reference
              (format nil "trie node referenced by ~A is missing"
                      (bytes-to-hex owner-identifier)))
             findings))
     findings)
    (t
     (push (make-node-store-database-finding
            :trie-node owner-identifier
            "trie node contains a malformed child reference")
           findings)
     findings)))

(defun node-store-verify-trie-node-object
    (database findings owner-identifier object)
  "Validate one decoded trie node and its immediate content references."
  (unless (rlp-list-p object)
    (push (make-node-store-database-finding
           :trie-node owner-identifier "trie node is not an RLP list")
          findings)
    (return-from node-store-verify-trie-node-object findings))
  (let ((items (rlp-list-items object)))
    (case (length items)
      (17
       (dotimes (index 16)
         (setf findings
               (node-store-verify-trie-child-reference
                database findings owner-identifier (nth index items))))
       (unless (byte-vector-p (nth 16 items))
         (push (make-node-store-database-finding
                :trie-node owner-identifier
                "trie branch value is not bytes")
               findings)))
      (2
       (let ((path-field (first items)))
         (if (not (and (byte-vector-p path-field)
                       (plusp (length path-field))))
             (push (make-node-store-database-finding
                    :trie-node owner-identifier
                    "trie compact path is not non-empty bytes")
                   findings)
             (let ((flag (ash (aref path-field 0) -4)))
               (if (or (> flag 3)
                       (and (evenp flag)
                            (not (zerop (logand (aref path-field 0) #x0f)))))
                   (push (make-node-store-database-finding
                          :trie-node owner-identifier
                          "trie compact path has invalid flags or padding")
                         findings)
                   (multiple-value-bind (path leaf-p)
                       (hex-prefix-decode path-field)
                     (when (and (not leaf-p) (zerop (length path)))
                       (push (make-node-store-database-finding
                              :trie-node owner-identifier
                              "trie extension path is empty")
                             findings))
                     (if leaf-p
                         (unless (byte-vector-p (second items))
                           (push (make-node-store-database-finding
                                  :trie-node owner-identifier
                                  "trie leaf value is not bytes")
                                 findings))
                         (setf findings
                               (node-store-verify-trie-child-reference
                                database findings owner-identifier
                                (second items))))))))))
      (otherwise
       (push (make-node-store-database-finding
              :trie-node owner-identifier
              "trie node must contain 2 or 17 RLP fields")
             findings))))
  findings)

(defun node-store-verify-trie-node-records (database findings)
  "Check content addresses, node shape, and every hashed child reference."
  (node-store-call-with-chain-records
   database :trie-node
   (lambda (identifier encoded)
     (cond
       ((/= 32 (length identifier))
        (push (make-node-store-database-finding
               :trie-node identifier
               "trie node key is not a 32-byte hash")
              findings))
       ((not (bytes= identifier (keccak-256 encoded)))
        (push (make-node-store-database-finding
               :trie-node identifier
               "trie node does not hash to its key")
              findings))
       (t
        (handler-case
            (setf findings
                  (node-store-verify-trie-node-object
                   database findings identifier (rlp-decode-one encoded)))
          (rlp-error (condition)
            (push (make-node-store-database-finding
                   :trie-node identifier
                   (format nil "trie node is not valid RLP: ~A" condition))
                  findings)))))))
  findings)

(defun node-store-verify-state-history (database findings)
  "Check each block-to-state-root record and its persisted root node."
  (node-store-call-with-chain-records
   database :state-history
   (lambda (identifier root)
     (cond
       ((/= 32 (length identifier))
        (push (make-node-store-database-finding
               :state-history identifier
               "state-history key is not a block hash")
              findings))
       ((/= 32 (length root))
        (push (make-node-store-database-finding
               :state-history identifier
               "state-history value is not a trie root")
              findings))
       (t
        (multiple-value-bind (record present-p)
            (kv-get-chain-record database :block identifier)
          (if (not present-p)
              (push (make-node-store-database-finding
                     :state-history identifier
                     "state history references an unknown block")
                    findings)
              (with-node-store-database-finding
                  (findings :state-history identifier)
                (let ((block
                        (chain-store-decode-persisted-block-record
                         record "State-history block")))
                  (unless (bytes=
                           root
                           (hash32-bytes
                            (block-header-state-root (block-header block))))
                    (block-validation-fail
                     "state-history root does not match its block header"))))))
        (unless (or (bytes= root (hash32-bytes +empty-trie-hash+))
                    (nth-value 1
                               (kv-get-chain-record
                                database :trie-node root)))
          (push (make-node-store-database-finding
                 :state-history identifier
                 "state-history root trie node is missing")
                findings))))))
  findings)

(declaim
 (ftype (function (t t t t fixnum) t)
        node-store-verify-account-trie-reference))

(defun node-store-verify-account-leaf-references
    (database findings owner-identifier encoded-account)
  "Check storage/code content addresses embedded in one account-trie leaf."
  (with-node-store-database-finding
      (findings :state-history owner-identifier)
    (let ((fields
            (rlp-list-field (rlp-decode-one encoded-account)
                            "Persisted account trie leaf")))
      (unless (= 4 (length fields))
        (block-validation-fail
         "Persisted account trie leaf must contain four fields"))
      (destructuring-bind (nonce balance storage-root code-hash) fields
        (unless (and (byte-vector-p nonce) (byte-vector-p balance))
          (block-validation-fail
           "Persisted account nonce and balance must be byte strings"))
        (unless (and (byte-vector-p storage-root) (= 32 (length storage-root)))
          (block-validation-fail
           "Persisted account storage root must contain 32 bytes"))
        (unless (and (byte-vector-p code-hash) (= 32 (length code-hash)))
          (block-validation-fail
           "Persisted account code hash must contain 32 bytes"))
        ;; Storage roots and code hashes are leaf payload, not trie child
        ;; references.  The generic node-shape scan therefore cannot discover
        ;; these missing records after flat-state retention has removed the
        ;; redundant account snapshot.
        (unless (or (bytes= storage-root (hash32-bytes +empty-trie-hash+))
                    (nth-value
                     1
                     (kv-get-chain-record database :trie-node storage-root)))
          (push (make-node-store-database-finding
                 :trie-node storage-root
                 (format nil
                         "storage trie referenced by state root for block ~A is missing"
                         (bytes-to-hex owner-identifier)))
                findings))
        (unless (or (bytes= code-hash (hash32-bytes +empty-code-hash+))
                    (nth-value
                     1 (kv-get-chain-record database :code code-hash)))
          (push (make-node-store-database-finding
                 :code code-hash
                 (format nil
                         "code referenced by state root for block ~A is missing"
                         (bytes-to-hex owner-identifier)))
                findings)))))
  findings)

(defun node-store-verify-account-trie-object
    (database findings owner-identifier object depth)
  "Stream one retained account-trie node without accumulating its leaves."
  (when (> depth 128)
    (push (make-node-store-database-finding
           :state-history owner-identifier
           "account trie exceeds the maximum hashed-key path depth")
          findings)
    (return-from node-store-verify-account-trie-object findings))
  (unless (rlp-list-p object)
    (return-from node-store-verify-account-trie-object findings))
  (let ((items (rlp-list-items object)))
    (case (length items)
      (17
       (dotimes (index 16)
         (setf findings
               (node-store-verify-account-trie-reference
                database findings owner-identifier (nth index items)
                (1+ depth))))
       (let ((value (nth 16 items)))
         (when (and (byte-vector-p value) (plusp (length value)))
           (setf findings
                 (node-store-verify-account-leaf-references
                  database findings owner-identifier value)))))
      (2
       (let ((path-field (first items)))
         (when (and (byte-vector-p path-field) (plusp (length path-field)))
           (handler-case
               (multiple-value-bind (path leaf-p)
                   (hex-prefix-decode path-field)
                 (declare (ignore path))
                 (if leaf-p
                     (let ((value (second items)))
                       (when (byte-vector-p value)
                         (setf findings
                               (node-store-verify-account-leaf-references
                                database findings owner-identifier value))))
                     (setf findings
                           (node-store-verify-account-trie-reference
                            database findings owner-identifier (second items)
                            (1+ depth)))))
             (error () nil)))))))
  findings)

(defun node-store-verify-account-trie-reference
    (database findings owner-identifier reference depth)
  (cond
    ((rlp-list-p reference)
     (node-store-verify-account-trie-object
      database findings owner-identifier reference depth))
    ((and (byte-vector-p reference) (zerop (length reference)))
     findings)
    ((and (byte-vector-p reference) (= 32 (length reference)))
     (multiple-value-bind (encoded present-p)
         (kv-get-chain-record database :trie-node reference)
       (when present-p
         (handler-case
             (setf findings
                   (node-store-verify-account-trie-object
                    database findings owner-identifier
                    (rlp-decode-one encoded) depth))
           (rlp-error () nil)))
       findings))
    (t findings)))

(defun node-store-verify-account-trie-content-references
    (database findings schema-version)
  "Stream every retained v4 account root and check leaf content references.

No leaf list or visited-node set is retained, so audit memory is bounded by the
trie depth even when the state or retained history is larger than RAM."
  (when (>= schema-version +node-store-trie-state-schema-version+)
    (node-store-call-with-chain-records
     database :state-history
     (lambda (identifier root)
       (unless (bytes= root (hash32-bytes +empty-trie-hash+))
         (setf findings
               (node-store-verify-account-trie-reference
                database findings identifier root 0))))))
  findings)

(defun node-store-verify-state-history-coverage
    (database findings schema-version)
  "Require every v4 retained flat state and forkchoice anchor to have a root.

Flat state records remain as the file-oracle/recovery representation, but from
schema v4 the production provider must be able to open the same block through
:STATE-HISTORY.  Head, safe, and finalized are independently protected
retention anchors and therefore require roots even when no flat record remains."
  (when (>= schema-version +node-store-trie-state-schema-version+)
    (dolist (kind '(:state :state-diff))
      (node-store-call-with-chain-records
       database kind
       (lambda (identifier record)
         (declare (ignore record))
         (unless (nth-value
                  1 (kv-get-chain-record database :state-history identifier))
           (push (make-node-store-database-finding
                  :state-history identifier
                  (format nil "~(~A~) record has no persisted trie root" kind))
                 findings)))))
    (let ((seen (make-hash-table :test 'equal)))
      (dolist (label '(:head :safe :finalized))
        (multiple-value-bind (identifier present-p)
            (kv-get-chain-checkpoint database label)
          (when (and present-p
                     (not (gethash (bytes-to-hex identifier) seen)))
            (setf (gethash (bytes-to-hex identifier) seen) t)
            (unless (nth-value
                     1
                     (kv-get-chain-record
                      database :state-history identifier))
              (push (make-node-store-database-finding
                     :state-history identifier
                     (format nil
                             "~(~A~) checkpoint has no persisted trie root"
                             label))
                    findings)))))))
  findings)

(defun node-store-verify-exact-associated-record
    (database findings kind identifier expected missing-message mismatch-message)
  (multiple-value-bind (record present-p)
      (kv-get-chain-record database kind identifier)
    (cond
      ((not present-p)
       (push (make-node-store-database-finding
              kind identifier missing-message)
             findings))
      ((not (bytes= record expected))
       (push (make-node-store-database-finding
              kind identifier mismatch-message)
             findings))))
  findings)

(defun node-store-verified-receipts-for-block
    (database findings identifier block)
  "Return RECEIPTS, VALID-P, and updated FINDINGS for BLOCK's primary record."
  (multiple-value-bind (record present-p)
      (kv-get-chain-record database :receipt identifier)
    (if (not present-p)
        (values
         nil nil
         (cons (make-node-store-database-finding
                :receipt identifier "block is missing its receipt record")
               findings))
        (let ((receipts nil)
              (valid-p nil))
          (with-node-store-database-finding (findings :receipt identifier)
            (setf receipts (block-receipts-from-record block record)
                  valid-p t))
          (values receipts valid-p findings)))))

(defun node-store-verify-expected-transaction-locations
    (database findings identifier block receipts)
  (multiple-value-bind (canonical-hash canonical-p)
      (kv-get-chain-canonical-hash
       database (block-header-number (block-header block)))
    (when (and canonical-p (bytes= identifier canonical-hash))
      (loop with log-index-start = 0
            for transaction in (block-transactions block)
            for receipt in receipts
            for index from 0
            for transaction-identifier =
              (hash32-bytes (transaction-hash transaction))
            for expected =
              (transaction-location-record-rlp
               (make-engine-transaction-location
                :block block
                :index index
                :transaction transaction
                :receipt receipt
                :log-index-start log-index-start))
            do (multiple-value-bind (record present-p)
                   (kv-get-chain-record
                    database :transaction-location transaction-identifier)
                 (cond
                   ((not present-p)
                    (push (make-node-store-database-finding
                           :transaction-location transaction-identifier
                           "canonical transaction is missing its location")
                          findings))
                   ((not (bytes= record expected))
                    (push (make-node-store-database-finding
                           :transaction-location transaction-identifier
                           "canonical transaction location is inconsistent")
                          findings))))
               (incf log-index-start (length (receipt-logs receipt))))))
  findings)

(defun node-store-verify-block-associated-records
    (database findings schema-version identifier record block)
  (let* ((header-record (block-header-rlp (block-header block)))
         (number (block-header-number (block-header block)))
         (ordered-identifier
           (kv-chain-height-hash-identifier number identifier)))
    (setf findings
          (node-store-verify-exact-associated-record
           database findings :header identifier header-record
           "block is missing its header record"
           "header record does not match its block"))
    (multiple-value-bind (receipts receipt-valid-p receipt-findings)
        (node-store-verified-receipts-for-block
         database findings identifier block)
      (setf findings receipt-findings)
      (when (>= schema-version 2)
        (setf findings
              (node-store-verify-exact-associated-record
               database findings :ordered-block ordered-identifier record
               "block is missing its height-ordered mirror"
               "height-ordered block does not match its hash record"))
        (setf findings
              (node-store-verify-exact-associated-record
               database findings :ordered-header ordered-identifier header-record
               "header is missing its height-ordered mirror"
               "height-ordered header does not match its hash record"))
        (multiple-value-bind (receipt-record receipt-present-p)
            (kv-get-chain-record database :receipt identifier)
          (when receipt-present-p
            (setf findings
                  (node-store-verify-exact-associated-record
                   database findings :ordered-receipt ordered-identifier
                   receipt-record
                   "receipt is missing its height-ordered mirror"
                   "height-ordered receipt does not match its hash record"))))
        (when (>= schema-version +node-store-trie-state-schema-version+)
          (multiple-value-bind (root root-present-p)
              (kv-get-chain-record database :state-history identifier)
            (when root-present-p
              (setf findings
                    (node-store-verify-exact-associated-record
                     database findings :ordered-state-history
                     ordered-identifier root
                     "state history is missing its height-ordered mirror"
                     "height-ordered state history does not match its hash record"))))))
      (when receipt-valid-p
        (setf findings
              (node-store-verify-expected-transaction-locations
               database findings identifier block receipts))))
    findings))

(defun node-store-verify-block-records (database findings schema-version)
  (node-store-call-with-chain-records
   database :block
   (lambda (identifier record)
     (with-node-store-database-finding (findings :block identifier)
       (let ((block
               (chain-store-decode-persisted-block-record
                record "Block record")))
         (if (bytes= identifier (hash32-bytes (block-hash block)))
             (setf findings
                   (node-store-verify-block-associated-records
                    database findings schema-version identifier record block))
             (push (make-node-store-database-finding
                    :block identifier
                    "block record key does not match its encoded hash")
                   findings))))))
  findings)

(defun node-store-verify-block-references (database findings kind)
  (node-store-call-with-chain-records
   database kind
   (lambda (identifier record)
     (declare (ignore record))
     (unless (node-store-block-record-present-p database identifier)
       (push (make-node-store-database-finding
              kind identifier "record references an unknown block")
             findings))))
  findings)

(defun node-store-verify-height-ordered-references (database findings)
  (dolist (kind '(:ordered-block :ordered-header :ordered-receipt
                  :ordered-state-history)
                findings)
    (node-store-call-with-chain-records
     database kind
     (lambda (identifier record)
       (with-node-store-database-finding (findings kind identifier)
         (multiple-value-bind (number hash)
             (kv-chain-height-hash-identifier-values identifier)
           (let ((source-kind
                   (ecase kind
                     (:ordered-block :block)
                     (:ordered-header :header)
                     (:ordered-receipt :receipt)
                     (:ordered-state-history :state-history))))
             (multiple-value-bind (source-record present-p)
                 (kv-get-chain-record database source-kind hash)
               (cond
                 ((not present-p)
                  (push (make-node-store-database-finding
                         kind identifier
                         (format nil
                                 "height ~D record references an unknown block"
                                 number))
                        findings))
                 ((not (bytes= record source-record))
                  (push (make-node-store-database-finding
                         kind identifier
                         "height-ordered record does not match its hash record")
                        findings))
                 (t
                  (multiple-value-bind (block-record block-present-p)
                      (kv-get-chain-record database :block hash)
                    (if (not block-present-p)
                        (push (make-node-store-database-finding
                               kind identifier
                               (format nil
                                       "height ~D record references an unknown block"
                                       number))
                              findings)
                        (let ((block
                                (chain-store-decode-persisted-block-record
                                 block-record "Height-ordered block")))
                          (unless (= number
                                     (block-header-number (block-header block)))
                            (push (make-node-store-database-finding
                                   kind identifier
                                   "height-ordered key has the wrong block number")
                                  findings)))))))))))))))

(defun node-store-verify-canonical-index (database findings)
  (node-store-call-with-chain-records
   database :canonical-hash
   (lambda (identifier hash)
     (let ((number (kv-chain-record-uint64-identifier identifier)))
       (multiple-value-bind (record present-p)
           (kv-get-chain-record database :block hash)
         (if (not present-p)
             (push (make-node-store-database-finding
                    :canonical-hash identifier
                    (format nil
                            "canonical height ~D references an unknown block"
                            number))
                   findings)
             (with-node-store-database-finding
                 (findings :canonical-hash identifier)
               (let ((block
                       (chain-store-decode-persisted-block-record
                        record "Canonical block")))
                 (unless (= number
                            (block-header-number (block-header block)))
                   (block-validation-fail
                    "Canonical height does not match block number"))
                 (when (plusp number)
                   (multiple-value-bind (parent-hash parent-present-p)
                       (kv-get-chain-canonical-hash database (1- number))
                     (when (and parent-present-p
                                (not (bytes=
                                      parent-hash
                                      (hash32-bytes
                                       (block-header-parent-hash
                                        (block-header block))))))
                       (block-validation-fail
                        "Canonical block is not linked to the prior height")))))))))))
  findings)

(defun node-store-verify-checkpoints (database findings)
  (node-store-call-with-chain-records
   database :checkpoint
   (lambda (identifier hash)
     (unless (node-store-block-record-present-p database hash)
       (push (make-node-store-database-finding
              :checkpoint identifier
              "checkpoint references an unknown block")
             findings))))
  findings)

(defun node-store-verify-transaction-location-records (database findings)
  (node-store-call-with-chain-records
   database :transaction-location
   (lambda (identifier record)
     (with-node-store-database-finding
         (findings :transaction-location identifier)
       (unless (= 32 (length identifier))
         (block-validation-fail
          "Transaction location key is not a 32-byte hash"))
       (multiple-value-bind (block-hash index log-index-start)
           (transaction-location-record-values record)
         (multiple-value-bind (block-record block-present-p)
             (kv-get-chain-record database :block (hash32-bytes block-hash))
           (unless block-present-p
             (block-validation-fail
              "Transaction location references an unknown block"))
           (let* ((block
                    (chain-store-decode-persisted-block-record
                     block-record "Transaction location block"))
                  (transactions (block-transactions block))
                  (number (block-header-number (block-header block))))
             (unless (hash32= block-hash (block-hash block))
               (block-validation-fail
                "Transaction location block key does not match its body"))
             (multiple-value-bind (canonical-hash canonical-p)
                 (kv-get-chain-canonical-hash database number)
               (unless (and canonical-p
                            (bytes= canonical-hash (hash32-bytes block-hash)))
                 (block-validation-fail
                  "Transaction location references a non-canonical block")))
             (unless (< index (length transactions))
               (block-validation-fail
                "Transaction location index is outside the block body"))
             (let ((transaction (nth index transactions)))
               (unless (bytes= identifier
                               (hash32-bytes (transaction-hash transaction)))
                 (block-validation-fail
                  "Transaction location key does not match block transaction"))
               (multiple-value-bind (receipt-record receipt-present-p)
                   (kv-get-chain-record
                    database :receipt (hash32-bytes block-hash))
                 (unless receipt-present-p
                   (block-validation-fail
                    "Transaction location block has no receipt record"))
                 (let ((receipts
                         (block-receipts-from-record block receipt-record)))
                   (unless (= log-index-start
                              (chain-store-expected-log-index-start
                               receipts index))
                     (block-validation-fail
                      "Transaction location log index is inconsistent")))))))))))
  findings)

(defun node-store-verify-state-code-references (database findings resolver)
  (dolist (kind '(:state :staged-state))
    (node-store-call-with-chain-records
     database kind
     (lambda (identifier record)
       (with-node-store-database-finding (findings kind identifier)
         (dolist (account (rlp-list-field (rlp-decode-one record)
                                           "State snapshot"))
           (state-account-snapshot-from-rlp-object account resolver))))))
  (node-store-call-with-chain-records
   database :state-diff
   (lambda (identifier record)
     (with-node-store-database-finding (findings :state-diff identifier)
       (let ((fields (rlp-list-field (rlp-decode-one record)
                                     "State diff record")))
         (unless (= (length fields) 2)
           (block-validation-fail "State diff record must contain 2 fields"))
         (dolist (account (rlp-list-field (second fields)
                                           "State diff accounts"))
           (chain-store-import-state-diff-account
            account
            (make-hash-table :test 'equal)
            (make-hash-table :test 'equal)
            (make-hash-table :test 'equal)
            (make-hash-table :test 'equal)
            resolver))))))
  findings)

(defun node-store-audit-schema-version
    (database allow-incomplete-operation)
  (if allow-incomplete-operation
      (let ((other-operation
              (node-store-incomplete-database-operation
               database :except allow-incomplete-operation)))
        (when other-operation
          (block-validation-fail
           "Chain database operation ~A is incomplete" other-operation))
        (node-store-uninterrupted-chain-schema-version database))
      (node-store-chain-schema-version database)))

(defun node-store-verify-chain-database
    (database &key allow-incomplete-operation)
  "Audit DATABASE and return findings in discovery order.

The audit streams every namespace and holds only the current record plus point
lookup results. It validates record decoding, content addresses, redundant
block/header/receipt mirrors, canonical transaction locations, and cross-record
targets. It does not re-execute blocks, recompute state roots, or prove that a
state-diff chain resolves.

ALLOW-INCOMPLETE-OPERATION is an internal recovery seam used to audit a fresh
rebuild target before its refusal marker is removed. Ordinary callers must
leave it NIL."
  (unless (typep database 'key-value-database)
    (block-validation-fail
     "Chain database audit requires a key-value database"))
  (let ((findings '()))
    (let ((version
            (with-node-store-database-finding
                (findings :schema-version nil)
              (node-store-audit-schema-version
               database allow-incomplete-operation))))
      (unless version
        (return-from node-store-verify-chain-database (nreverse findings)))
      (setf findings (node-store-verify-code-records database findings))
      (setf findings
            (node-store-verify-trie-node-records database findings))
      (setf findings (node-store-verify-state-history database findings))
      (setf findings
            (node-store-verify-account-trie-content-references
             database findings version))
      (setf findings
            (node-store-verify-state-history-coverage
             database findings version))
      (setf findings
            (node-store-verify-block-records database findings version))
      (dolist (kind '(:header :receipt :state :state-diff :block-access-list))
        (setf findings
              (node-store-verify-block-references database findings kind)))
      (setf findings
            (node-store-verify-height-ordered-references database findings))
      (setf findings (node-store-verify-canonical-index database findings))
      (setf findings (node-store-verify-checkpoints database findings))
      (setf findings
            (node-store-verify-transaction-location-records
             database findings))
      (setf findings
            (node-store-verify-state-code-references
             database findings
             (when (node-store-content-addressed-code-p version)
               (node-store-database-code-resolver database)))))
    (nreverse findings)))
