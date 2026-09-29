(in-package #:ethereum-lisp.test)

;;;; Differential replay of real Hoodi blocks against a reference client.
;;;
;;; EEST preloads every slot into an in-memory state and contains none of
;;; today's Hoodi traffic, so two consensus divergences reached the live node
;;; while it passed 8/8 (docs/evidence/sec5-hoodi-gas-mismatch.txt,
;;; docs/evidence/sec5-hoodi-differential-replay.txt).  This replays blocks
;;; fetched by scripts/fetch-hoodi-replay-corpus.sh the way the node executes
;;; them, and compares with the chain and with the client that served them.
;;;
;;; The pre-state is the parent's state served the way the direct RocksDB
;;; provider serves it (CHAIN-STORE-STATE-DB): the account trie opened lazily at
;;; the parent's state root, each storage trie opened lazily at its root, nodes
;;; and code read by hash.  The bytes come from the block's execution witness
;;; instead of RocksDB.  Every node is hash-checked on first read and the root
;;; is the parent header's, whose hash is the block's parent hash, so the
;;; pre-state is authenticated by the block hash, not trusted from the server.
;;;
;;; Each block runs twice, each time from a fresh pre-state:
;;;
;;;  1. strict: the candidate validator's check of the block against its
;;;     parent (VALIDATE-BLOCK-AGAINST-CONFIG), then EXECUTE-SIGNED-BLOCK with
;;;     the block's own header and hash, as EXECUTE-AND-COMMIT-ENGINE-PAYLOAD
;;;     calls it (system calls, withdrawals, derived requests, blob gas,
;;;     rewards), minus the store commit.  Success means the header is valid
;;;     on its parent and every commitment matched: gas used, state root,
;;;     receipts root, logs bloom, requests hash, blob gas used, block hash.
;;;  2. localizing: the same executor with the post-execution commitments
;;;     cleared from the header, so it runs to the end, and with the node's own
;;;     transaction applier wrapped to read the state once the transactions are
;;;     done.  Its receipts are compared per transaction with the reference's,
;;;     its state per account and slot with the reference's diffMode post-state,
;;;     and its header commitments with the block's.  The strict run never
;;;     observes the state, so the observation's reads cannot change what the
;;;     strict run measures.
;;;
;;; The reference's receipts are authenticated: they must rebuild the header's
;;; receipts root.  Its diffMode post-state is not; it only locates a
;;; divergence that the header commitments establish, and a block whose strict
;;; run passes must show no state difference either, which checks the
;;; comparator.  Its prestateTracer output is checked against the witness
;;; state, which checks the lazily backed reads.

(defparameter +hoodi-replay-root-env+ "ETHEREUM_LISP_HOODI_REPLAY_ROOT")
(defparameter +hoodi-replay-blocks-env+ "ETHEREUM_LISP_HOODI_REPLAY_BLOCKS")

(defvar *hoodi-replay-gaps* nil
  "Trie nodes and code a replay needed that its corpus does not hold.")

(define-condition hoodi-replay-corpus-error (error)
  ((message :initarg :message :reader hoodi-replay-corpus-error-message))
  (:report (lambda (condition stream)
             (write-string (hoodi-replay-corpus-error-message condition)
                           stream))))

(defun hoodi-replay-corpus-fail (control &rest arguments)
  (error 'hoodi-replay-corpus-error
         :message (apply #'format nil control arguments)))

;;; Corpus selection

(defun hoodi-replay-corpus-root ()
  (let ((root (funcall *fixture-root-environment-reader*
                       +hoodi-replay-root-env+)))
    (unless (blank-string-p root)
      (uiop:ensure-directory-pathname root))))

(defun hoodi-replay-parse-selection (text)
  "Block numbers named by TEXT: comma-separated numbers and FROM-TO ranges."
  (loop for part in (uiop:split-string text :separator ",")
        for trimmed = (string-trim " " part)
        for dash = (position #\- trimmed)
        unless (blank-string-p trimmed)
          append (handler-case
                     (if dash
                         (loop for n from (parse-integer trimmed :end dash)
                                 to (parse-integer trimmed :start (1+ dash))
                               collect n)
                         (list (parse-integer trimmed)))
                   (error ()
                     (hoodi-replay-corpus-fail
                      "~A has a malformed entry ~S" +hoodi-replay-blocks-env+
                      trimmed)))))

(defun hoodi-replay-corpus-blocks (root &optional selection)
  "Block numbers under ROOT that have a manifest, ascending, restricted to
SELECTION (a list of numbers) when one is given."
  (let ((numbers
          (sort (loop for directory in (uiop:subdirectories root)
                      for name = (car (last (pathname-directory directory)))
                      when (and (stringp name)
                                (plusp (length name))
                                (every #'digit-char-p name)
                                (probe-file (merge-pathnames "manifest.json"
                                                             directory)))
                        collect (parse-integer name))
                #'<)))
    (if selection
        (remove-if-not (lambda (n) (member n selection)) numbers)
        numbers)))

;;; Reading a block directory

(defun hoodi-replay-json (directory name)
  (let ((path (merge-pathnames name directory)))
    (unless (probe-file path)
      (hoodi-replay-corpus-fail "~A is missing" (namestring path)))
    (ethereum-lisp.json:parse-json (fixture-file-string path))))

(defun hoodi-replay-quantity (value)
  (cond ((null value) 0)
        ((integerp value) value)
        (t (hex-to-quantity value))))

(defun hoodi-replay-field (object name)
  (fixture-object-field object name))

(defun hoodi-replay-entries (object label)
  (and object (ethereum-lisp.json:json-object-entries object label)))

(defun hoodi-replay-array (value)
  (ethereum-lisp.json:json-array-values value))

(defun hoodi-replay-address-key (text)
  (ethereum-lisp.state::address-key (address-from-hex text)))

(defun hoodi-replay-slot-key (text)
  (ethereum-lisp.state::storage-key (hash32-from-hex text)))

(defun hoodi-replay-hex-list (strings)
  (mapcar #'hex-to-bytes (hoodi-replay-array strings)))

;;; The execution witness: trie nodes and code by hash, ancestors by number

(defstruct (hoodi-replay-witness (:constructor %make-hoodi-replay-witness))
  (nodes (make-hash-table :test #'equalp))
  (codes (make-hash-table :test #'equalp))
  headers)

(defun hoodi-replay-add-code (witness code)
  (setf (gethash (keccak-256 code) (hoodi-replay-witness-codes witness)) code))

(defun hoodi-replay-extra-codes (directory)
  "codes.json: the code of the block's withdrawal recipients, which a witness
omits because crediting a balance runs no code (absent in older corpora)."
  (when (probe-file (merge-pathnames "codes.json" directory))
    (hoodi-replay-hex-list (hoodi-replay-json directory "codes.json"))))

(defun hoodi-replay-read-witness (directory)
  (let* ((json (hoodi-replay-json directory "witness.json"))
         (witness (%make-hoodi-replay-witness))
         (empty-trie (rlp-encode (make-byte-vector 0))))
    (dolist (node (hoodi-replay-hex-list (hoodi-replay-field json "state")))
      (setf (gethash (keccak-256 node) (hoodi-replay-witness-nodes witness))
            node))
    ;; The empty trie, which an account without storage opens.
    (setf (gethash (keccak-256 empty-trie) (hoodi-replay-witness-nodes witness))
          empty-trie)
    (dolist (code (append (hoodi-replay-hex-list (hoodi-replay-field json "codes"))
                          (hoodi-replay-extra-codes directory)))
      (hoodi-replay-add-code witness code))
    (setf (hoodi-replay-witness-headers witness)
          (mapcar #'block-header-from-rlp
                  (hoodi-replay-hex-list (hoodi-replay-field json "headers"))))
    witness))

(defun hoodi-replay-add-trace-codes (witness traces diff-p)
  "Add the code the reference's traces show.  A witness carries only the code
execution ran, while the node's account loader reads every loaded account's
code; each blob is keyed by its own hash, so a wrong one is never served."
  (dolist (trace (hoodi-replay-array traces))
    (let ((result (hoodi-replay-field trace "result")))
      (dolist (side (if diff-p
                        (list (hoodi-replay-field result "pre")
                              (hoodi-replay-field result "post"))
                        (list result)))
        (dolist (entry (hoodi-replay-entries side "trace accounts"))
          (let ((code (hoodi-replay-field (cdr entry) "code")))
            (when code
              (hoodi-replay-add-code witness (hex-to-bytes code)))))))))

(defun hoodi-replay-backed-state (witness state-root)
  "STATE-ROOT's state as CHAIN-STORE-STATE-DB opens it on the direct provider.
A node the witness lacks is a gap, not a divergence: reth v2.6.0's witness can
omit the surviving sibling when a storage deletion collapses a branch, which
this trie (like go-ethereum's) reads to decide how to collapse it."
  (flet ((node (hash)
           (multiple-value-bind (encoded present-p)
               (gethash hash (hoodi-replay-witness-nodes witness))
             (unless present-p
               (push (format nil "trie node ~A" (bytes-to-hex hash))
                     *hoodi-replay-gaps*))
             (values encoded present-p))))
    (let ((account-trie (make-persisted-mpt state-root #'node)))
      (make-lazy-state-db
       (lambda (address)
         (multiple-value-bind (record present-p)
             (mpt-get account-trie (keccak-256 (address-bytes address)))
           (if present-p
               (let* ((account (decode-state-account-rlp record))
                      (code-hash (state-account-code-hash account))
                      (code
                        (if (hash32= code-hash +empty-code-hash+)
                            (make-byte-vector 0)
                            (or (gethash (hash32-bytes code-hash)
                                         (hoodi-replay-witness-codes witness))
                                (progn
                                  (push (format nil "code ~A"
                                                (hash32-to-hex code-hash))
                                        *hoodi-replay-gaps*)
                                  (hoodi-replay-corpus-fail
                                   "Code ~A of ~A is not in the corpus"
                                   (hash32-to-hex code-hash)
                                   (address-to-hex address))))))
                      (storage-trie
                        (make-persisted-mpt (state-account-storage-root account)
                                            #'node)))
                 (values account code t nil storage-trie))
               (values nil nil nil))))
       nil
       nil
       :trie account-trie
       :cached-root state-root
       :direct-trie-p t))))

(defun hoodi-replay-block-hashes (block witness)
  "BLOCKHASH history from the witness's ancestor headers, each linked to the
next by hash, starting from BLOCK's parent.  Returns the table and the parent
header."
  (let* ((header (block-header block))
         (by-number (make-hash-table))
         (hashes (make-hash-table))
         (expected (block-header-parent-hash header))
         (parent nil))
    (dolist (ancestor (hoodi-replay-witness-headers witness))
      (setf (gethash (block-header-number ancestor) by-number) ancestor))
    (loop for number downfrom (1- (block-header-number header))
          for ancestor = (gethash number by-number)
          while ancestor
          do (unless (hash32= (block-header-hash ancestor) expected)
               (hoodi-replay-corpus-fail
                "Witness header ~D does not hash to its child's parent hash"
                number))
             (unless parent
               (setf parent ancestor))
             (setf (gethash number hashes) expected
                   expected (block-header-parent-hash ancestor)))
    (unless parent
      (hoodi-replay-corpus-fail "The witness has no parent header"))
    (values hashes parent)))

(defun hoodi-replay-copy-hashes (hashes)
  (let ((copy (make-hash-table)))
    (maphash (lambda (number hash) (setf (gethash number copy) hash)) hashes)
    copy))

;;; The reference's receipts, pre-state and post-state

(defun hoodi-replay-reference-receipts (json)
  (mapcar
   (lambda (receipt)
     (make-receipt
      :type (hoodi-replay-quantity (hoodi-replay-field receipt "type"))
      :status (hoodi-replay-quantity (hoodi-replay-field receipt "status"))
      :cumulative-gas-used
      (hoodi-replay-quantity (hoodi-replay-field receipt "cumulativeGasUsed"))
      :logs
      (mapcar (lambda (log)
                (make-log-entry
                 :address (address-from-hex (hoodi-replay-field log "address"))
                 :topics (mapcar #'hash32-from-hex
                                 (hoodi-replay-array
                                  (hoodi-replay-field log "topics")))
                 :data (hex-to-bytes (hoodi-replay-field log "data"))))
              (hoodi-replay-array (hoodi-replay-field receipt "logs")))))
   (hoodi-replay-array json)))

(defun hoodi-replay-reference-pre-state (prestates)
  "The block's pre-state as the reference's per-transaction prestateTracer
output shows it: the first transaction to show an account or slot shows its
value before the block.  Address key -> (balance nonce code-hash slots)."
  (let ((accounts (make-hash-table :test #'equal)))
    (dolist (trace (hoodi-replay-array prestates))
      (dolist (entry (hoodi-replay-entries (hoodi-replay-field trace "result")
                                           "prestate"))
        (let* ((key (hoodi-replay-address-key (car entry)))
               (fields (cdr entry))
               (known (gethash key accounts)))
          (unless known
            (setf known
                  (list (hoodi-replay-quantity
                         (hoodi-replay-field fields "balance"))
                        (hoodi-replay-quantity
                         (hoodi-replay-field fields "nonce"))
                        (let ((code (hoodi-replay-field fields "code")))
                          (if code
                              (keccak-256-hash (hex-to-bytes code))
                              +empty-code-hash+))
                        (make-hash-table :test #'equal))
                  (gethash key accounts) known))
          (dolist (slot (hoodi-replay-entries (hoodi-replay-field fields
                                                                  "storage")
                                              "prestate storage"))
            (let ((slot-key (hoodi-replay-slot-key (car slot))))
              (unless (nth-value 1 (gethash slot-key (fourth known)))
                (setf (gethash slot-key (fourth known))
                      (hoodi-replay-quantity (cdr slot)))))))))
    accounts))

(defstruct (hoodi-replay-account (:constructor make-hoodi-replay-account))
  (present-p t)
  balance
  nonce
  code-hash
  (storage (make-hash-table :test #'equal))
  ;; Every slot not set since reads zero: the account was deleted.
  cleared-p
  ;; Index of the reference transaction that last wrote each field or slot.
  (writers (make-hash-table :test #'equal)))

(defun hoodi-replay-reference-account (accounts key)
  (or (gethash key accounts)
      (setf (gethash key accounts) (make-hoodi-replay-account))))

(defun hoodi-replay-reference-post-state (diffs)
  "Fold the reference's per-transaction diffMode traces into what it reports
changed by the block's transactions: address key -> HOODI-REPLAY-ACCOUNT,
holding only what some transaction changed.  A slot on a transaction's pre
side and absent from its post side was cleared; an account on the pre side and
absent from the post side was deleted; an account whose post side is a zero
codeHash was touched and does not exist."
  (let ((accounts (make-hash-table :test #'equal)))
    (loop for trace in (hoodi-replay-array diffs)
          for index from 0
          for result = (hoodi-replay-field trace "result")
          for pre = (hoodi-replay-field result "pre")
          for post = (hoodi-replay-field result "post")
          do (let ((post-fields (make-hash-table :test #'equal)))
               (dolist (entry (hoodi-replay-entries post "diff post"))
                 (let* ((key (hoodi-replay-address-key (car entry)))
                        (fields (cdr entry))
                        (account (hoodi-replay-reference-account accounts key))
                        (writers (hoodi-replay-account-writers account))
                        (balance (hoodi-replay-field fields "balance"))
                        (nonce (hoodi-replay-field fields "nonce"))
                        (code (hoodi-replay-field fields "code"))
                        (code-hash (hoodi-replay-field fields "codeHash"))
                        ;; reth lists an account a transaction touched but
                        ;; left nonexistent with only a zero codeHash.
                        (absent-p (and code-hash
                                       (zerop (hoodi-replay-quantity
                                               code-hash)))))
                   (setf (gethash key post-fields) fields
                         (hoodi-replay-account-present-p account) (not absent-p)
                         (gethash "present" writers) index)
                   (when (and code-hash (not absent-p))
                     (setf (hoodi-replay-account-code-hash account)
                           (hash32-from-hex code-hash)
                           (gethash "code" writers) index))
                   (when balance
                     (setf (hoodi-replay-account-balance account)
                           (hoodi-replay-quantity balance)
                           (gethash "balance" writers) index))
                   (when nonce
                     (setf (hoodi-replay-account-nonce account)
                           (hoodi-replay-quantity nonce)
                           (gethash "nonce" writers) index))
                   (when code
                     (setf (hoodi-replay-account-code-hash account)
                           (keccak-256-hash (hex-to-bytes code))
                           (gethash "code" writers) index))
                   (dolist (slot (hoodi-replay-entries
                                  (hoodi-replay-field fields "storage")
                                  "diff post storage"))
                     (let ((slot-key (hoodi-replay-slot-key (car slot))))
                       (setf (gethash slot-key
                                      (hoodi-replay-account-storage account))
                             (hoodi-replay-quantity (cdr slot))
                             (gethash slot-key writers) index)))))
               (dolist (entry (hoodi-replay-entries pre "diff pre"))
                 (let* ((key (hoodi-replay-address-key (car entry)))
                        (account (hoodi-replay-reference-account accounts key))
                        (writers (hoodi-replay-account-writers account)))
                   (multiple-value-bind (fields post-p)
                       (gethash key post-fields)
                     (if (not post-p)
                         (setf (hoodi-replay-account-present-p account) nil
                               (hoodi-replay-account-balance account) 0
                               (hoodi-replay-account-nonce account) 0
                               (hoodi-replay-account-code-hash account)
                               +empty-code-hash+
                               (hoodi-replay-account-cleared-p account) t
                               (hoodi-replay-account-storage account)
                               (make-hash-table :test #'equal)
                               (gethash "present" writers) index)
                         (let ((post-storage
                                 (hoodi-replay-field fields "storage")))
                           (dolist (slot (hoodi-replay-entries
                                          (hoodi-replay-field (cdr entry)
                                                              "storage")
                                          "diff pre storage"))
                             (unless (hoodi-replay-field post-storage
                                                         (car slot))
                               (let ((slot-key
                                       (hoodi-replay-slot-key (car slot))))
                                 (setf (gethash
                                        slot-key
                                        (hoodi-replay-account-storage
                                         account))
                                       0
                                       (gethash slot-key writers)
                                       index)))))))))))
    accounts))

;;; Reading our state

(defun hoodi-replay-read-account (state address-key slot-keys)
  "STATE's view of ADDRESS-KEY as (present-p balance nonce code-hash slots),
SLOTS an alist (slot-key . value) over SLOT-KEYS.  A read the state cannot
serve reads as :UNAVAILABLE."
  (flet ((safely (thunk)
           (handler-case (funcall thunk)
             (error () :unavailable))))
    (let* ((address (address-from-hex address-key))
           (account (safely (lambda () (state-db-get-account state address)))))
      (if (eq account :unavailable)
          (list :unavailable :unavailable :unavailable :unavailable
                (mapcar (lambda (key) (cons key :unavailable)) slot-keys))
          (list (not (null account))
                (if account (state-account-balance account) 0)
                (if account (state-account-nonce account) 0)
                (if account (state-account-code-hash account) +empty-code-hash+)
                (mapcar (lambda (slot-key)
                          (cons slot-key
                                (safely
                                 (lambda ()
                                   (state-db-get-storage
                                    state address
                                    (hash32-from-hex slot-key))))))
                        slot-keys))))))

(defun hoodi-replay-known-slot-keys (state address-key)
  "Slots STATE's object for ADDRESS-KEY has read or written."
  (let ((object (gethash address-key
                         (ethereum-lisp.state::state-db-objects state)))
        (keys '()))
    (when object
      (maphash (lambda (key value)
                 (declare (ignore value))
                 (push key keys))
               (ethereum-lisp.state::state-object-storage object))
      ;; Objects carry ZERO-SLOTS since 72d148aa; the guard keeps the harness
      ;; running on the state layer before it, which its regression control
      ;; (block 3684027) replays.
      (let ((zero-slots
              (and (fboundp 'ethereum-lisp.state::state-object-zero-slots)
                   (funcall 'ethereum-lisp.state::state-object-zero-slots
                            object))))
        (when zero-slots
          (maphash (lambda (key value)
                     (declare (ignore value))
                     (push key keys))
                   zero-slots))))
    keys))

(defun hoodi-replay-touched-keys (state)
  (let ((keys (make-hash-table :test #'equal)))
    (maphash (lambda (key value)
               (declare (ignore value))
               (setf (gethash key keys) t))
             (ethereum-lisp.state::state-db-touched state))
    keys))

(defun hoodi-replay-observe-state (state reference before)
  "Read STATE for every account the REFERENCE changed and every account the
transactions touched (those touched BEFORE them, by the system calls, are left
out unless the reference changed them too): address key -> reading."
  (let ((readings (make-hash-table :test #'equal)))
    (flet ((observe (key)
             (unless (gethash key readings)
               (let* ((account (gethash key reference))
                      (slot-keys
                        (remove-duplicates
                         (append
                          (hoodi-replay-known-slot-keys state key)
                          (and account
                               (loop for slot-key being the hash-keys
                                       of (hoodi-replay-account-storage account)
                                     collect slot-key)))
                         :test #'string=)))
                 (setf (gethash key readings)
                       (hoodi-replay-read-account state key slot-keys))))))
      (maphash (lambda (key account)
                 (declare (ignore account))
                 (observe key))
               reference)
      (maphash (lambda (key value)
                 (declare (ignore value))
                 (unless (gethash key before)
                   (observe key)))
               (ethereum-lisp.state::state-db-touched state)))
    readings))

;;; Comparing

(defun hoodi-replay-text (value)
  (typecase value
    (hash32 (hash32-to-hex value))
    (integer (format nil "0x~(~X~)" value))
    (null "absent")
    ((eql t) "present")
    (t (string-downcase (princ-to-string value)))))

(defun hoodi-replay-state-differences (readings reference pre-state)
  "Differences between READINGS (address key -> reading, see
HOODI-REPLAY-READ-ACCOUNT) and the REFERENCE post-state, taking what the
reference did not change from PRE-STATE.  Each is a plist (:address :field
:ours :reference :writer), sorted by address, then field, then slot."
  (let ((differences '()))
    (dolist (address-key (sort (loop for key being the hash-keys of readings
                                     collect key)
                               #'string<))
      (destructuring-bind (present-p balance nonce code-hash slots)
          (gethash address-key readings)
        (let* ((account (gethash address-key reference))
               (writers (and account (hoodi-replay-account-writers account)))
               (before (hoodi-replay-read-account
                        pre-state address-key (mapcar #'car slots))))
          (destructuring-bind (pre-present-p pre-balance pre-nonce
                               pre-code-hash pre-slots)
              before
            (flet ((compare (field ours changed-p reference-value pre-value
                             writer-key)
                     (let ((expected (if changed-p reference-value pre-value)))
                       (unless (string= (hoodi-replay-text ours)
                                        (hoodi-replay-text expected))
                         (push (list :address address-key
                                     :field field
                                     :ours (hoodi-replay-text ours)
                                     :reference (hoodi-replay-text expected)
                                     :writer (and writers
                                                  (or (gethash writer-key
                                                               writers)
                                                      (gethash "present"
                                                               writers))))
                               differences)))))
              (compare "present" present-p
                       (and account t)
                       (and account (hoodi-replay-account-present-p account))
                       pre-present-p "present")
              (compare "balance" balance
                       (and account (hoodi-replay-account-balance account) t)
                       (and account (hoodi-replay-account-balance account))
                       pre-balance "balance")
              (compare "nonce" nonce
                       (and account (hoodi-replay-account-nonce account) t)
                       (and account (hoodi-replay-account-nonce account))
                       pre-nonce "nonce")
              (compare "code" code-hash
                       (and account (hoodi-replay-account-code-hash account) t)
                       (and account (hoodi-replay-account-code-hash account))
                       pre-code-hash "code")
              (loop for (slot-key . value) in (sort (copy-list slots) #'string<
                                                    :key #'car)
                    do (multiple-value-bind (reference-value set-p)
                           (if account
                               (gethash slot-key
                                        (hoodi-replay-account-storage account))
                               (values nil nil))
                         (compare (concatenate 'string "slot 0x" slot-key)
                                  value
                                  (or set-p
                                      (and account
                                           (hoodi-replay-account-cleared-p
                                            account)))
                                  (if set-p reference-value 0)
                                  (cdr (assoc slot-key pre-slots
                                              :test #'string=))
                                  slot-key))))))))
    (nreverse differences)))

(defun hoodi-replay-prestate-differences (reference-pre pre-state skipped)
  "Where the reference's prestateTracer view differs from PRE-STATE, the
witness-backed state the replay starts from.  SKIPPED address keys are the
pre-block system-call contracts, which the reference shows after those calls."
  (let ((differences '())
        (slots 0))
    (dolist (address-key (sort (loop for key being the hash-keys of reference-pre
                                     collect key)
                               #'string<))
      (unless (member address-key skipped :test #'string=)
        (destructuring-bind (balance nonce code-hash storage)
            (gethash address-key reference-pre)
          (let ((slot-keys (loop for key being the hash-keys of storage
                                 collect key)))
            (incf slots (length slot-keys))
            (destructuring-bind (present-p ours-balance ours-nonce
                                 ours-code-hash ours-slots)
                (hoodi-replay-read-account pre-state address-key slot-keys)
              (declare (ignore present-p))
              (flet ((compare (field ours reference)
                       (unless (string= (hoodi-replay-text ours)
                                        (hoodi-replay-text reference))
                         (push (list :address address-key :field field
                                     :ours (hoodi-replay-text ours)
                                     :reference (hoodi-replay-text reference))
                               differences))))
                (compare "balance" ours-balance balance)
                (compare "nonce" ours-nonce nonce)
                (compare "code" ours-code-hash code-hash)
                (loop for (slot-key . value) in ours-slots
                      do (compare (concatenate 'string "slot 0x" slot-key)
                                  value (gethash slot-key storage)))))))))
    (values (nreverse differences) slots)))

(defun hoodi-replay-receipt-differences (transactions ours reference)
  "Per-transaction differences between our receipts and the reference's, as
plists (:tx :hash :field :ours :reference), in transaction order."
  (let ((differences '())
        (previous-ours 0)
        (previous-reference 0))
    (loop for transaction in transactions
          for index from 0
          for our in ours
          for their in reference
          do (flet ((compare (field our-value their-value)
                      (unless (equal our-value their-value)
                        (push (list :tx index
                                    :hash (hash32-to-hex
                                           (transaction-hash transaction))
                                    :field field
                                    :ours our-value :reference their-value)
                              differences))))
               (compare "status" (receipt-status our) (receipt-status their))
               (compare "gasUsed"
                        (- (receipt-cumulative-gas-used our) previous-ours)
                        (- (receipt-cumulative-gas-used their)
                           previous-reference))
               (compare "logs" (length (receipt-logs our))
                        (length (receipt-logs their)))
               (loop for our-log in (receipt-logs our)
                     for their-log in (receipt-logs their)
                     for log-index from 0
                     do (compare (format nil "log ~D address" log-index)
                                 (address-to-hex (log-entry-address our-log))
                                 (address-to-hex (log-entry-address their-log)))
                        (compare (format nil "log ~D topics" log-index)
                                 (mapcar #'hash32-to-hex
                                         (log-entry-topics our-log))
                                 (mapcar #'hash32-to-hex
                                         (log-entry-topics their-log)))
                        (compare (format nil "log ~D data" log-index)
                                 (bytes-to-hex (log-entry-data our-log))
                                 (bytes-to-hex (log-entry-data their-log))))
               (setf previous-ours (receipt-cumulative-gas-used our)
                     previous-reference (receipt-cumulative-gas-used their))))
    (nreverse differences)))

(defun hoodi-replay-commitment-differences (ours block-header transactions)
  "Header commitments our executed header OURS derived that differ from the
block's own."
  (let ((differences '()))
    (flet ((compare (field our-value their-value)
             (let ((our-text (hoodi-replay-text our-value))
                   (their-text (hoodi-replay-text their-value)))
               (unless (string= our-text their-text)
                 (push (list :field field :ours our-text :reference their-text)
                       differences)))))
      (compare "gasUsed" (block-header-gas-used ours)
               (block-header-gas-used block-header))
      (compare "blobGasUsed" (blob-gas-used transactions)
               (or (block-header-blob-gas-used block-header) 0))
      (compare "logsBloom" (bytes-to-hex (block-header-logs-bloom ours))
               (bytes-to-hex (block-header-logs-bloom block-header)))
      (compare "receiptsRoot" (block-header-receipts-root ours)
               (block-header-receipts-root block-header))
      (compare "requestsHash" (block-header-requests-hash ours)
               (block-header-requests-hash block-header))
      (compare "stateRoot" (block-header-state-root ours)
               (block-header-state-root block-header)))
    (nreverse differences)))

;;; Replaying one block

(defun hoodi-replay-condition-kind (condition)
  (cond (*hoodi-replay-gaps* :witness-gap)
        ((typep condition 'hoodi-replay-corpus-error) :corpus)
        ((typep condition 'ethereum-lisp.validation:state-unavailable-error)
         :witness-gap)
        (t :execution)))

(defun hoodi-replay-without-option (options key)
  (loop for (option value) on options by #'cddr
        unless (eq option key)
          append (list option value)))

(defun hoodi-replay-execution-options (block parent hashes config)
  (append
   (list :expected-chain-id (chain-config-chain-id config)
         :parent-header parent
         :chain-config config
         :block-hashes (hoodi-replay-copy-hashes hashes)
         :apply-block-rewards-p t
         :ommers (block-ommers block))
   (when (block-withdrawals-present-p block)
     (list :withdrawals (block-withdrawals block)))))

(defun hoodi-replay-strict (raw witness parent hashes config)
  "Execute the block exactly as the Engine import does.  Returns :OK, or the
condition's kind and report."
  (let ((*hoodi-replay-gaps* nil)
        (block (block-from-rlp raw)))
    (handler-case
        (progn
          ;; The candidate validator's parent/header/body half
          ;; (BLOCK-IMPORT-VALIDATE-CANDIDATE): base fee, gas limit, the blob
          ;; schedule's excess blob gas, blob counts.  No ommers post-Merge.
          (validate-block-against-config parent block config)
          (apply #'execute-signed-block
                 (hoodi-replay-backed-state
                  witness (block-header-state-root parent))
                 (block-transactions block)
                 :header (block-header block)
                 :expected-block-hash (block-hash block)
                 (hoodi-replay-execution-options block parent hashes config))
          (if *hoodi-replay-gaps*
              (values :witness-gap (first *hoodi-replay-gaps*))
              :ok))
      (error (condition)
        (values (hoodi-replay-condition-kind condition)
                (princ-to-string condition))))))

(defun hoodi-replay-localizing (raw witness parent hashes config reference)
  "Execute the block with its post-execution commitments cleared and our
state read after its transactions.  Returns the executed block, our receipts
and the readings, or NIL and the condition's kind and report."
  (let* ((*hoodi-replay-gaps* nil)
         (block (block-from-rlp raw))
         (header (block-header block))
         (readings nil))
    (setf (block-header-state-root header) nil
          (block-header-receipts-root header) nil
          (block-header-logs-bloom header) nil
          (block-header-gas-used header) 0
          (block-header-requests-hash header) nil)
    (handler-case
        (multiple-value-bind (executed receipts)
            (apply #'ethereum-lisp.execution::execute-block-with-message-applier
                   (hoodi-replay-backed-state
                    witness (block-header-state-root parent))
                   (block-transactions block)
                   (lambda (state transactions &rest options)
                     (let ((before (hoodi-replay-touched-keys state)))
                       (multiple-value-prog1
                           (apply #'apply-signed-message-list
                                  state transactions
                                  :expected-chain-id
                                  (chain-config-chain-id config)
                                  options)
                         (setf readings
                               (hoodi-replay-observe-state
                                state reference before)))))
                   :header header
                   :withdrawals-supplied-p (block-withdrawals-present-p block)
                   ;; Prague requests are derived; an empty side list only
                   ;; satisfies the fork's body shape without the header hash.
                   :requests '()
                   :requests-supplied-p t
                   (hoodi-replay-without-option
                    (hoodi-replay-execution-options block parent hashes config)
                    :expected-chain-id))
          (if *hoodi-replay-gaps*
              (values nil :witness-gap (first *hoodi-replay-gaps*))
              (values executed receipts readings)))
      (error (condition)
        (values nil (hoodi-replay-condition-kind condition)
                (princ-to-string condition))))))

(defun hoodi-replay-difference-text (difference)
  (format nil "~@[tx ~D ~]~@[~A ~]~@[~A ~]~A ours=~A reference=~A~@[ (reference writer tx ~D)~]"
          (getf difference :tx)
          (getf difference :hash)
          (let ((address (getf difference :address)))
            (and address (concatenate 'string "0x" address)))
          (getf difference :field)
          (getf difference :ours)
          (getf difference :reference)
          (getf difference :writer)))

(defun hoodi-replay-first-difference (receipts state commitments prestate)
  "The earliest difference: by transaction index between the first receipt
difference and the state difference the reference wrote first, then a header
commitment, then the pre-state."
  (let* ((receipt (first receipts))
         (state-first (first (sort (copy-list state) #'<
                                   :key (lambda (difference)
                                          (or (getf difference :writer)
                                              most-positive-fixnum)))))
         (receipt-index (and receipt (getf receipt :tx)))
         (state-index (and state-first (getf state-first :writer))))
    (cond ((and receipt state-first state-index (< state-index receipt-index))
           state-first)
          (receipt receipt)
          (state-first state-first)
          (commitments (first commitments))
          (t (first prestate)))))

;;; Cost.  Each block reports the calling thread's CPU time and the bytes
;;; consed by the strict run (the block exactly as the Engine import executes
;;; it: header checks, sender recovery, the EVM, the roots) and by the whole
;;; replay (the corpus reads and both runs), so interpreter work is measured
;;; on real Hoodi traffic by the same test that proves the results unchanged.
;;; The numbers are costs only, no block data.  GET-BYTES-CONSED advances by
;;; allocation region, so a small figure is an upper bound in region units.

(defmacro hoodi-replay-measure ((plist cpu-key bytes-key) &body body)
  "Evaluate BODY, record its thread CPU microseconds and bytes consed under
CPU-KEY and BYTES-KEY of PLIST (a place), and return BODY's values."
  (let ((cpu (gensym "CPU")) (bytes (gensym "BYTES")))
    `(let ((,cpu (ethereum-lisp.telemetry:telemetry-thread-cpu-microseconds))
           (,bytes (sb-ext:get-bytes-consed)))
       (multiple-value-prog1 (progn ,@body)
         (setf (getf ,plist ,bytes-key) (- (sb-ext:get-bytes-consed) ,bytes)
               (getf ,plist ,cpu-key)
               (- (ethereum-lisp.telemetry:telemetry-thread-cpu-microseconds)
                  ,cpu))))))

(defun hoodi-replay-block (directory)
  "Replay the block in DIRECTORY.  Returns a plist: :number :verdict (:match,
:diverges, :comparator, :prestate or :unreplayable), :strict, :first (text of
the first difference), :receipts :commitments :state (differences) and the
counts :transactions :accounts :slots :prestate-slots, and the strict run's
cost, :strict-cpu (thread CPU microseconds) and :strict-bytes."
  (let* ((manifest (hoodi-replay-json directory "manifest.json"))
         (number (hoodi-replay-quantity (hoodi-replay-field manifest "number")))
         (hash (hash32-from-hex (hoodi-replay-field manifest "hash")))
         (result (list :number number)))
    (handler-case
        (let* ((raw (hex-to-bytes (hoodi-replay-json directory "raw-block.json")))
               (block (block-from-rlp raw))
               (header (block-header block))
               (config (ethereum-lisp.genesis::hoodi-chain-config))
               (witness (hoodi-replay-read-witness directory))
               (prestates (hoodi-replay-json directory "prestate.json"))
               (diffs (hoodi-replay-json directory "diff.json"))
               (reference-receipts
                 (hoodi-replay-reference-receipts
                  (hoodi-replay-json directory "receipts.json")))
               (reference (hoodi-replay-reference-post-state diffs))
               (parent-json (hoodi-replay-json directory "parent.json")))
          (hoodi-replay-add-trace-codes witness prestates nil)
          (hoodi-replay-add-trace-codes witness diffs t)
          (setf (getf result :transactions) (length (block-transactions block)))
          ;; Our decoding and header hashing of the raw block.
          (unless (hash32= (block-hash block) hash)
            (return-from hoodi-replay-block
              (list* :verdict :diverges
                     :first (format nil "block hash ours=~A reference=~A"
                                    (hash32-to-hex (block-hash block))
                                    (hash32-to-hex hash))
                     result)))
          (multiple-value-bind (hashes parent)
              (hoodi-replay-block-hashes block witness)
            (unless (and (hash32= (block-header-hash parent)
                                  (hash32-from-hex
                                   (hoodi-replay-field parent-json "hash")))
                         (hash32= (block-header-state-root parent)
                                  (hash32-from-hex
                                   (hoodi-replay-field parent-json
                                                       "stateRoot"))))
              (hoodi-replay-corpus-fail
               "parent.json does not describe the witness's parent header"))
            (unless (hash32= (transaction-receipt-list-root
                              (block-transactions block) reference-receipts)
                             (block-header-receipts-root header))
              (hoodi-replay-corpus-fail
               "The reference's receipts do not rebuild the receipts root"))
            (let ((pre-state (hoodi-replay-backed-state
                              witness (block-header-state-root parent))))
              (multiple-value-bind (prestate-differences prestate-slots)
                  (hoodi-replay-prestate-differences
                   (hoodi-replay-reference-pre-state prestates)
                   pre-state
                   (list (ethereum-lisp.state::address-key
                          ethereum-lisp.execution::+beacon-roots-address+)
                         (ethereum-lisp.state::address-key
                          ethereum-lisp.execution::+history-storage-address+)))
                (setf (getf result :prestate-slots) prestate-slots)
                (multiple-value-bind (strict strict-report)
                    (hoodi-replay-measure (result :strict-cpu :strict-bytes)
                      (hoodi-replay-strict raw witness parent hashes config))
                  (setf (getf result :strict)
                        (if (eq strict :ok) "ok" strict-report))
                  (multiple-value-bind (executed receipts readings)
                      (hoodi-replay-localizing raw witness parent hashes
                                               config reference)
                    (when (null executed)
                      ;; RECEIPTS and READINGS are the kind and the report.
                      (return-from hoodi-replay-block
                        (list* :verdict (if (member receipts
                                                    '(:witness-gap :corpus))
                                            :unreplayable
                                            :diverges)
                               :first (format nil "localizing run: ~A"
                                              readings)
                               result)))
                    (let* ((receipt-differences
                             (hoodi-replay-receipt-differences
                              (block-transactions block) receipts
                              reference-receipts))
                           (commitment-differences
                             (hoodi-replay-commitment-differences
                              (block-header executed) header
                              (block-transactions block)))
                           (state-differences
                             (hoodi-replay-state-differences
                              readings reference pre-state))
                           (first
                             (hoodi-replay-first-difference
                              receipt-differences state-differences
                              commitment-differences prestate-differences)))
                      (setf (getf result :accounts) (hash-table-count readings)
                            (getf result :slots)
                            (loop for reading being the hash-values of readings
                                  sum (length (fifth reading)))
                            (getf result :receipts) receipt-differences
                            (getf result :commitments) commitment-differences
                            (getf result :state) state-differences
                            (getf result :prestate) prestate-differences
                            (getf result :first)
                            (and first (hoodi-replay-difference-text first))
                            (getf result :verdict)
                            (cond
                              ((member strict '(:witness-gap :corpus))
                               :unreplayable)
                              (prestate-differences :prestate)
                              ((and (eq strict :ok)
                                    (or receipt-differences
                                        commitment-differences
                                        state-differences))
                               :comparator)
                              ((eq strict :ok) :match)
                              (t :diverges)))
                      result)))))))
      (error (condition)
        (list* :verdict :unreplayable
               :first (princ-to-string condition)
               result)))))

(defun hoodi-replay-report (result stream)
  (format stream "~&HOODI-REPLAY block=~D verdict=~(~A~) txs=~D accounts=~D ~
slots=~D prestateSlots=~D receiptDiffs=~D stateDiffs=~D ~
commitmentDiffs=~D~@[ strict=~S~]~@[ first=~S~]~%"
          (getf result :number)
          (getf result :verdict)
          (or (getf result :transactions) 0)
          (or (getf result :accounts) 0)
          (or (getf result :slots) 0)
          (or (getf result :prestate-slots) 0)
          (length (getf result :receipts))
          (length (getf result :state))
          (length (getf result :commitments))
          (getf result :strict)
          (getf result :first))
  (dolist (kind '(:commitments :receipts :state :prestate))
    (loop for difference in (getf result kind)
          repeat 8
          do (format stream "~&HOODI-REPLAY   ~(~A~) ~A~%"
                     kind (hoodi-replay-difference-text difference)))))

(defun hoodi-replay-cost-report (result stream)
  (format stream "~&HOODI-REPLAY-COST block=~D strictCpuUs=~D strictBytes=~D ~
blockCpuUs=~D blockBytes=~D~%"
          (getf result :number)
          (or (getf result :strict-cpu) 0)
          (or (getf result :strict-bytes) 0)
          (or (getf result :block-cpu) 0)
          (or (getf result :block-bytes) 0)))

(defun hoodi-replay-cost-summary (results stream)
  "One line of totals, and the median strict run, over RESULTS."
  (flet ((total (key)
           (loop for result in results sum (or (getf result key) 0))))
    (let ((strict (sort (loop for result in results
                              for cpu = (getf result :strict-cpu)
                              when cpu collect cpu)
                        #'<)))
      (format stream "~&HOODI-REPLAY-COST summary: blocks=~D strictCpuMs=~D ~
strictMB=~D medianStrictCpuUs=~D blockCpuMs=~D blockMB=~D~%"
              (length results)
              (round (total :strict-cpu) 1000)
              (round (total :strict-bytes) 1000000)
              (if strict (nth (floor (length strict) 2) strict) 0)
              (round (total :block-cpu) 1000)
              (round (total :block-bytes) 1000000)))))

(defun hoodi-replay-corpus (root &optional selection (stream *standard-output*))
  "Replay every block of the corpus at ROOT (restricted to SELECTION), report
each and its cost on STREAM, and return the results."
  (let ((results '()))
    (dolist (number (hoodi-replay-corpus-blocks root selection))
      (let* ((cost '())
             (result (append
                      (hoodi-replay-measure (cost :block-cpu :block-bytes)
                        (hoodi-replay-block
                         (merge-pathnames (format nil "~D/" number) root)))
                      cost)))
        (hoodi-replay-report result stream)
        (hoodi-replay-cost-report result stream)
        (force-output stream)
        (push result results)))
    (nreverse results)))

(defun hoodi-replay-count (results verdict)
  (count verdict results :key (lambda (result) (getf result :verdict))))

(defun hoodi-replay-replayed (results)
  "Blocks that executed to a verdict about the client."
  (+ (hoodi-replay-count results :match)
     (hoodi-replay-count results :diverges)
     (hoodi-replay-count results :comparator)
     (hoodi-replay-count results :prestate)))

(defun hoodi-replay-gate-failures (results)
  "Why RESULTS fail the gate, or NIL.  A run that replayed no block fails:
selecting nothing is not evidence."
  (append
   (when (zerop (hoodi-replay-replayed results))
     (list "no block was replayed"))
   (loop for result in results
         unless (eq (getf result :verdict) :match)
           collect (format nil "block ~D: ~(~A~)~@[ ~A~]"
                           (getf result :number)
                           (getf result :verdict)
                           (getf result :first)))))

(deftest hoodi-replay-blocks-match-the-reference-client
  (:layer :integration)
  (let ((root (hoodi-replay-corpus-root)))
    (unless root
      (skip-test
       (format nil "Set ~A to a corpus fetched by scripts/fetch-hoodi-replay-corpus.sh to run this test"
               +hoodi-replay-root-env+)))
    (let* ((selection-text (funcall *fixture-root-environment-reader*
                                    +hoodi-replay-blocks-env+))
           (selection (unless (blank-string-p selection-text)
                        (hoodi-replay-parse-selection selection-text)))
           (results (hoodi-replay-corpus root selection))
           (failures (hoodi-replay-gate-failures results)))
      (format t "~&HOODI-REPLAY summary: selected=~D replayed=~D match=~D ~
diverges=~D comparator=~D prestate=~D unreplayable=~D~%"
              (length results) (hoodi-replay-replayed results)
              (hoodi-replay-count results :match)
              (hoodi-replay-count results :diverges)
              (hoodi-replay-count results :comparator)
              (hoodi-replay-count results :prestate)
              (hoodi-replay-count results :unreplayable))
      (hoodi-replay-cost-summary results *standard-output*)
      (when failures
        (error "Hoodi replay: ~D failure~:P~{~%  ~A~}"
               (length failures) failures)))))

;;; Controls that need no corpus: the comparator finds what it must, the gate
;;; refuses a run that replayed nothing, and the selection reads as documented.

(defun hoodi-replay-control-slot (n)
  (format nil "0x~64,'0X" n))

(defun hoodi-replay-control-state (accounts)
  "An in-memory state holding ACCOUNTS ((address balance nonce ((slot . value)
...)) ...), slots as small integers."
  (let ((state (make-state-db)))
    (loop for (address balance nonce storage) in accounts
          do (state-db-set-account state (address-from-hex address)
                                   (make-state-account :balance balance
                                                       :nonce nonce))
             (loop for (slot . value) in storage
                   do (state-db-set-storage
                       state (address-from-hex address)
                       (hash32-from-hex (hoodi-replay-control-slot slot))
                       value)))
    state))

(defun hoodi-replay-control-readings (state addresses slots)
  (let ((readings (make-hash-table :test #'equal)))
    (dolist (address addresses readings)
      (let ((key (hoodi-replay-address-key address)))
        (setf (gethash key readings)
              (hoodi-replay-read-account
               state key
               (mapcar (lambda (n)
                         (hoodi-replay-slot-key (hoodi-replay-control-slot n)))
                       slots)))))))

(deftest hoodi-replay-comparator-finds-each-kind-of-state-difference
  (let* ((a "0x00000000000000000000000000000000000000a1")
         (b "0x00000000000000000000000000000000000000b1")
         (c "0x00000000000000000000000000000000000000c1")
         (d "0x00000000000000000000000000000000000000d1")
         ;; One transaction: A pays 1 wei to B (created), A's slot 1 goes
         ;; 5 -> 7 and its slot 2 is cleared, C is deleted, and D is touched
         ;; but left nonexistent (reth's zero codeHash entry).
         (diffs
           (ethereum-lisp.json:parse-json
            (format nil "[{\"txHash\":\"0x~64,'0X\",\"result\":{~
\"pre\":{\"~A\":{\"balance\":\"0xa\",\"nonce\":1,\"storage\":{\"~A\":\"0x5\",\"~A\":\"0x3\"}},~
\"~A\":{\"balance\":\"0x0\",\"nonce\":1}},~
\"post\":{\"~A\":{\"balance\":\"0x9\",\"nonce\":2,\"storage\":{\"~A\":\"0x7\"}},~
\"~A\":{\"balance\":\"0x1\"},\"~A\":{\"codeHash\":\"0x~64,'0X\"}}}}]"
                    1 a (hoodi-replay-control-slot 1)
                    (hoodi-replay-control-slot 2) c a
                    (hoodi-replay-control-slot 1) b d 0)))
         (reference (hoodi-replay-reference-post-state diffs))
         (pre-state (hoodi-replay-control-state
                     (list (list a 10 1 '((1 . 5) (2 . 3) (3 . 4)))
                           (list c 0 1 '()))))
         (right (list (list a 9 2 '((1 . 7) (3 . 4)))
                      (list b 1 0 '()))))
    (flet ((differences (accounts)
             (hoodi-replay-state-differences
              (hoodi-replay-control-readings
               (hoodi-replay-control-state accounts) (list a b c d) '(1 2 3))
              reference pre-state))
           (fields (differences)
             (mapcar (lambda (difference) (getf difference :field))
                     differences)))
      ;; The positive control: the reference's own post-state reads clean,
      ;; the untouched slot 3 included.
      (is (null (differences right)))
      ;; Each mutation is found, named, and attributed to transaction 0.
      (let ((found (differences (list (list a 9 2 '((1 . 6) (3 . 4)))
                                      (list b 1 0 '())))))
        (is (equal (list (concatenate 'string "slot "
                                      (string-downcase
                                       (hoodi-replay-control-slot 1))))
                   (fields found)))
        (is (equal "0x6" (getf (first found) :ours)))
        (is (equal "0x7" (getf (first found) :reference)))
        (is (eql 0 (getf (first found) :writer))))
      (is (equal (list (concatenate 'string "slot "
                                    (string-downcase
                                     (hoodi-replay-control-slot 2))))
                 (fields (differences
                          (list (list a 9 2 '((1 . 7) (2 . 3) (3 . 4)))
                                (list b 1 0 '()))))))
      (is (equal '("slot 0x0000000000000000000000000000000000000000000000000000000000000003")
                 (fields (differences
                          (list (list a 9 2 '((1 . 7) (3 . 5)))
                                (list b 1 0 '()))))))
      (is (equal '("balance")
                 (fields (differences
                          (list (list a 8 2 '((1 . 7) (3 . 4)))
                                (list b 1 0 '()))))))
      (is (equal '("present" "balance")
                 (fields (differences (list (list a 9 2 '((1 . 7) (3 . 4))))))))
      (is (equal '("present" "nonce")
                 (fields (differences
                          (list (list a 9 2 '((1 . 7) (3 . 4)))
                                (list b 1 0 '())
                                (list c 0 1 '()))))))
      (is (equal '("present" "balance")
                 (fields (differences
                          (list (list a 9 2 '((1 . 7) (3 . 4)))
                                (list b 1 0 '())
                                (list d 5 0 '())))))))))

(deftest hoodi-replay-gate-fails-a-run-that-replayed-nothing
  (is (equal '("no block was replayed") (hoodi-replay-gate-failures '())))
  (let ((gap (list :number 7 :verdict :unreplayable :first "trie node 0x01")))
    (is (equal '("no block was replayed" "block 7: unreplayable trie node 0x01")
               (hoodi-replay-gate-failures (list gap)))))
  (is (null (hoodi-replay-gate-failures (list (list :number 8 :verdict :match)))))
  (is (equal '("block 9: diverges tx 1 gasUsed")
             (hoodi-replay-gate-failures
              (list (list :number 8 :verdict :match)
                    (list :number 9 :verdict :diverges
                          :first "tx 1 gasUsed"))))))

(deftest hoodi-replay-selection-reads-numbers-and-ranges
  (is (equal '(3685380 3685381 3685382 3685491)
             (hoodi-replay-parse-selection "3685380-3685382, 3685491")))
  (is (null (hoodi-replay-parse-selection "")))
  (signals hoodi-replay-corpus-error
    (hoodi-replay-parse-selection "3685380,x")))

(deftest hoodi-replay-cost-lines-carry-only-numbers
  (let ((results (list (list :number 5 :verdict :match
                             :strict-cpu 3000 :strict-bytes 2000000
                             :block-cpu 9000 :block-bytes 7000000)
                       (list :number 6 :verdict :match
                             :strict-cpu 1000 :strict-bytes 1000000
                             :block-cpu 4000 :block-bytes 3000000))))
    (is (equal (format nil "HOODI-REPLAY-COST block=5 strictCpuUs=3000 ~
strictBytes=2000000 blockCpuUs=9000 blockBytes=7000000~%")
               (with-output-to-string (stream)
                 (hoodi-replay-cost-report (first results) stream))))
    (is (equal (format nil "HOODI-REPLAY-COST summary: blocks=2 strictCpuMs=4 ~
strictMB=3 medianStrictCpuUs=3000 blockCpuMs=13 blockMB=10~%")
               (with-output-to-string (stream)
                 (hoodi-replay-cost-summary results stream))))))
