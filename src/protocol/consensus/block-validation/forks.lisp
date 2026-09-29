(in-package #:ethereum-lisp.consensus)

;;;; Fork-specific block header field presence and merge transition checks.

(defparameter +dao-fork-extra-data+
  (ethereum-lisp.hex:hex-to-bytes
   "0x64616f2d686172642d666f726b"))
(defconstant +dao-fork-extra-range+ 10)

(defun validate-block-dao-extra-data (header config)
  (let ((fork-block (chain-config-dao-fork-block config)))
    (when (and fork-block
               (<= fork-block (block-header-number header))
               (< (block-header-number header)
                  (+ fork-block +dao-fork-extra-range+)))
      (let ((matches-p
              (bytes= (ensure-byte-vector (block-header-extra-data header))
                      +dao-fork-extra-data+)))
        (if (chain-config-dao-fork-support config)
            (unless matches-p
              (block-validation-fail
               "DAO-supporting header is missing dao-hard-fork extra data"))
            (when matches-p
              (block-validation-fail
               "DAO-opposing header contains dao-hard-fork extra data"))))))
  t)

(defun block-header-cancun-fields-present-p (header)
  (or (block-header-blob-gas-used header)
      (block-header-excess-blob-gas header)))

(defun validate-block-cancun-fields
    (header &key (cancun-enabled-p
                  (block-header-cancun-fields-present-p header)))
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

(defun block-header-merge-rules-p
    (config parent-header header &key parent-total-difficulty)
  "Whether HEADER, the child of PARENT-HEADER, is held to proof-of-stake rules.

Where CHAIN-CONFIG-MERGE-BY-TOTAL-DIFFICULTY-P is false the configuration
answers. Otherwise the answer is EIP-3675's, read from
PARENT-TOTAL-DIFFICULTY, the parent's cumulative difficulty from genesis:

- below the TTD the child is proof-of-work, and a zero-difficulty child is
  refused;
- at or above it the parent must be the terminal block -- itself a
  proof-of-stake block, or a proof-of-work block whose own parent was still
  below the TTD -- and the child is proof-of-stake, so a positive difficulty
  is refused by the proof-of-stake field rules.

Without the parent's total difficulty (a chain entered at a snap or checkpoint
pivot), a proof-of-stake parent is enough: every descendant of a
proof-of-stake block is one, which is go-ethereum v1.17.6's beacon
VerifyHeader rule. A proof-of-work parent then cannot be shown terminal, so a
zero-difficulty child is refused rather than accepted unverified, and a
positive-difficulty child keeps the proof-of-work rules."
  (let ((number (block-header-number header)))
    (unless (chain-config-merge-by-total-difficulty-p config number)
      (return-from block-header-merge-rules-p
        (chain-config-post-merge-p config number)))
    (let ((terminal-total-difficulty
            (chain-config-terminal-total-difficulty config))
          (proof-of-stake-header-p
            (zerop (block-header-difficulty header))))
      (cond
        (parent-total-difficulty
         (cond
           ((< parent-total-difficulty terminal-total-difficulty)
            (when proof-of-stake-header-p
              (block-validation-fail
               "Proof-of-stake header before the terminal total difficulty: parent total difficulty ~D, terminal ~D"
               parent-total-difficulty terminal-total-difficulty))
            nil)
           ((and (plusp (block-header-difficulty parent-header))
                 (>= (- parent-total-difficulty
                        (block-header-difficulty parent-header))
                     terminal-total-difficulty))
            (block-validation-fail
             "Parent is a proof-of-work block past the terminal block: its own parent's total difficulty ~D reached the terminal ~D"
             (- parent-total-difficulty
                (block-header-difficulty parent-header))
             terminal-total-difficulty))
           (t t)))
        ((block-header-post-merge-p parent-header) t)
        (proof-of-stake-header-p
         (block-validation-fail
          "Proof-of-stake header over a proof-of-work parent whose total difficulty is unknown: the terminal block cannot be verified"))
        (t nil)))))

(defun block-header-post-merge-block-p (config header)
  "Whether HEADER, a block already admitted under CONFIG, is proof-of-stake.

Admission held HEADER to the rules BLOCK-HEADER-MERGE-RULES-P chose, so where
total difficulty decides the Merge its own zero difficulty says which side it
is on; elsewhere the configuration does."
  (let ((number (block-header-number header)))
    (if (chain-config-merge-by-total-difficulty-p config number)
        (block-header-post-merge-p header)
        (chain-config-post-merge-p config number))))

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
