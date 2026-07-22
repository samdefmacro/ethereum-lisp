(in-package #:ethereum-lisp.eth-wire)

;;;; EIP-2124 fork identifier.
;;;;
;;;; Peers exchange a fork id in the eth Status handshake to check they are on
;;;; the same chain and agree on which forks have happened. The id is a 4-byte
;;;; CRC32 over the genesis hash and every fork point that has already passed,
;;;; plus the block or timestamp of the next upcoming fork.

(defparameter +crc32-table+
  (let ((table (make-array 256 :element-type '(unsigned-byte 32))))
    (dotimes (n 256 table)
      (let ((c n))
        (dotimes (k 8)
          (setf c (if (logtest c 1)
                      (logxor #xedb88320 (ash c -1))
                      (ash c -1))))
        (setf (aref table n) c))))
  "IEEE 802.3 CRC-32 lookup table, reflected, polynomial 0xEDB88320.")

(defun crc32 (bytes)
  "Return the IEEE CRC-32 of BYTES as an (unsigned-byte 32)."
  (let ((crc #xffffffff))
    (loop for byte across (ensure-byte-vector bytes)
          do (setf crc (logxor (ash crc -8)
                               (aref +crc32-table+
                                     (logand (logxor crc byte) #xff)))))
    (logand (logxor crc #xffffffff) #xffffffff)))

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
