(in-package #:ethereum-lisp.eth-wire)

;;;; EIP-2124 fork identifier.
;;;;
;;;; Peers exchange a fork id in the eth Status handshake to check they are on
;;;; the same chain and agree on which forks have happened. The id is a 4-byte
;;;; CRC32 over the genesis hash and every fork point that has already passed,
;;;; plus the block or timestamp of the next upcoming fork.

(defun eth-fixed-big-endian (value size)
  "Encode VALUE as SIZE big-endian bytes."
  (let ((out (make-byte-vector size)))
    (dotimes (i size out)
      (setf (aref out (- size 1 i)) (logand (ash value (* -8 i)) #xff)))))

(defun eth-fork-hash (genesis-hash passed-forks)
  "Return the 4-byte EIP-2124 fork hash.

PASSED-FORKS is the list of fork points (block numbers or timestamps) that have
already activated, each folded in as a big-endian 64-bit integer after the
genesis hash. CRC-32 is a streaming checksum, so hashing the concatenation
equals the incremental fold reference implementations use."
  (let ((input (ensure-byte-vector genesis-hash)))
    (dolist (fork passed-forks)
      (setf input (concat-bytes input (eth-fixed-big-endian fork 8))))
    (eth-fixed-big-endian (crc32 input) 4)))

(defun compute-eth-fork-id (genesis-hash passed-forks next-fork)
  "Build the fork id from the GENESIS-HASH, the PASSED-FORKS, and NEXT-FORK.

NEXT-FORK is the block or timestamp of the next upcoming fork, or 0 when none is
scheduled."
  (make-eth-fork-id (eth-fork-hash genesis-hash passed-forks) next-fork))

(defun chain-config-eth-fork-id
    (config genesis-hash head-number head-timestamp
     &optional (genesis-timestamp 0))
  "Derive the EIP-2124 fork id for CONFIG at the chain head.

Folds in every block fork already active at HEAD-NUMBER, then every time fork
already active at HEAD-TIMESTAMP, and records the next scheduled fork: the next
upcoming block fork if one remains, otherwise the next upcoming time fork,
otherwise 0. GENESIS-TIMESTAMP identifies time forks that coincide with genesis
so they are excluded from the fold."
  (let* ((block-forks
           (ethereum-lisp.chain-config:chain-config-block-fork-schedule config))
         (time-forks
           (ethereum-lisp.chain-config:chain-config-time-fork-schedule
            config genesis-timestamp))
         (passed (append (remove-if-not (lambda (v) (<= v head-number)) block-forks)
                         (remove-if-not (lambda (v) (<= v head-timestamp))
                                        time-forks)))
         (next (or (find-if (lambda (v) (> v head-number)) block-forks)
                   (find-if (lambda (v) (> v head-timestamp)) time-forks)
                   0)))
    (compute-eth-fork-id genesis-hash passed next)))

;;; The fork id as a node record carries it, rather than as the eth handshake
;;; does. This is what lets a node be judged before it is dialed.

(defun eth-fork-id-enr-entry (fork-id)
  "The `eth` ENR entry value advertising FORK-ID, as an RLP object.

The inverse of ETH-FORK-ID-FROM-ENR-ENTRY, and the reason a record needs one at
all: a node that serves records without this key is filtered out by everyone who
reads them, so not advertising it is the same bug as not reading it, pointed the
other way. The tail go-ethereum leaves room for is simply absent -- we have
nothing to put in it, and a reader ignores it either way."
  (make-rlp-list (eth-fork-id-rlp-object fork-id)))

(defun eth-fork-id-from-enr-entry (value)
  "The fork id in the `eth` entry of an ENR, or NIL when VALUE is not one.

The entry is `[[fork_hash, fork_next], ...]` and NOT `[fork_hash, fork_next]`:
go-ethereum stores a struct whose first field is the fork id and whose remaining
fields are an RLP tail held open for later use, and a struct encodes as a list.
So the nesting is load-bearing -- read one level too shallow and the whole inner
list is taken for the four-byte fork hash, which then matches nothing. The tail
is ignored deliberately; being ignorable is its entire purpose.

Returns NIL rather than signalling on anything malformed. This decodes a
datagram from an unauthenticated stranger, and the only question a caller asks
is whether to dial the node -- which an undecodable record answers by itself."
  (ignore-errors
   (when (rlp-list-p value)
     (let ((inner (first (rlp-list-items value))))
       (when (and (rlp-list-p inner)
                  (= 2 (length (rlp-list-items inner))))
         (let ((fork-id (eth-fork-id-from-rlp-object inner)))
           (when (= 4 (length (ensure-byte-vector (eth-fork-id-hash fork-id))))
             fork-id)))))))

;;; EIP-2124 validation: check a peer's advertised fork id against our chain.

(define-condition eth-fork-id-mismatch (error)
  ((reason :initarg :reason :reader eth-fork-id-mismatch-reason))
  (:report (lambda (condition stream)
             (format stream "eth fork-id incompatible: ~A"
                     (eth-fork-id-mismatch-reason condition))))
  (:documentation "Signalled when a peer's fork id is incompatible with ours.
REASON is :remote-stale (the peer is on our chain but running out-of-date
software) or :local-incompatible-or-stale (we must upgrade, or the chains
differ)."))

(defparameter +fork-id-timestamp-threshold+ 1438269973
  "The mainnet genesis timestamp, used only to decide whether a peer's announced
next-fork is a block number or a timestamp when our own next fork is still a
block fork (matching go-ethereum's timestampThreshold).")

(defparameter +fork-id-uint64-max+ (1- (expt 2 64))
  "Sentinel appended past the last fork so the not-yet-passed search terminates.")

(defun chain-config-fork-hash-series (config genesis-hash genesis-timestamp)
  "Return (VALUES SUMS FORKS+ NBLOCK): the fork hashes we would advertise as our
head crosses each fork, the fork points with a terminating sentinel, and the
count of block-number forks.

SUMS[k] is the fork hash after the first K forks have folded in; SUMS and FORKS+
are index-aligned, so while our head sits before FORKS+[i] our advertised hash is
SUMS[i] and our next fork is FORKS+[i]."
  (let* ((block-forks
           (ethereum-lisp.chain-config:chain-config-block-fork-schedule config))
         (time-forks
           (ethereum-lisp.chain-config:chain-config-time-fork-schedule
            config genesis-timestamp))
         (forks (append block-forks time-forks))
         (sums (make-array (1+ (length forks))))
         (passed '())
         (k 0))
    (setf (aref sums 0) (eth-fork-hash genesis-hash '()))
    (dolist (fork forks)
      (setf passed (append passed (list fork)))
      (setf (aref sums (incf k)) (eth-fork-hash genesis-hash passed)))
    (values sums
            (coerce (append forks (list +fork-id-uint64-max+)) 'vector)
            (length block-forks))))

(defun validate-peer-fork-id (config genesis-hash head-number head-timestamp
                              peer-fork-id &optional (genesis-timestamp 0))
  "EIP-2124 validation of PEER-FORK-ID against our chain at (HEAD-NUMBER,
HEAD-TIMESTAMP). Returns PEER-FORK-ID on success; signals ETH-FORK-ID-MISMATCH
otherwise.

Accepts when the peer's fork hash equals our current hash (and the peer has not
announced a fork we already passed), equals a past hash of ours with the correct
following fork (peer is behind but on our chain), or equals a future hash of ours
(we are behind). Everything else is rejected."
  (multiple-value-bind (sums forks+ nblock)
      (chain-config-fork-hash-series config genesis-hash genesis-timestamp)
    (let ((peer-hash (ensure-byte-vector (eth-fork-id-hash peer-fork-id)))
          (peer-next (eth-fork-id-next peer-fork-id)))
      (dotimes (i (length forks+) peer-fork-id)
        (let ((fork (aref forks+ i))
              (head (if (>= i nblock) head-timestamp head-number)))
          (when (< head fork)
            ;; I is our first not-yet-passed fork; SUMS[i] is our current hash.
            (cond
              ;; Rule 1: the peer's hash is our current hash.
              ((bytes= (aref sums i) peer-hash)
               (when (and (> peer-next 0)
                          (or (>= head peer-next)
                              (and (> peer-next +fork-id-timestamp-threshold+)
                                   (>= head-timestamp peer-next))))
                 ;; 1a: the peer announced a fork we have already crossed.
                 (error 'eth-fork-id-mismatch
                        :reason :local-incompatible-or-stale))
               (return-from validate-peer-fork-id peer-fork-id))
              (t
               ;; Rule 2: the peer's hash is one of our past hashes (subset).
               (loop for j from 0 below i do
                 (when (bytes= (aref sums j) peer-hash)
                   (if (= (aref forks+ j) peer-next)
                       (return-from validate-peer-fork-id peer-fork-id)
                       (error 'eth-fork-id-mismatch :reason :remote-stale))))
               ;; Rule 3: the peer's hash is one of our future hashes (superset).
               (loop for j from (1+ i) below (length sums) do
                 (when (bytes= (aref sums j) peer-hash)
                   (return-from validate-peer-fork-id peer-fork-id)))
               ;; Rule 4: no match at all.
               (error 'eth-fork-id-mismatch
                      :reason :local-incompatible-or-stale)))))))))
