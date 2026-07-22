(in-package #:ethereum-lisp.p2p)

;;;; Ethereum Node Records (ENR, EIP-778).
;;;;
;;;; An ENR is a signed, versioned key/value record identifying a node:
;;;;
;;;;   record = rlp([signature, seq, k1, v1, k2, v2, ...])
;;;;
;;;; with the keys in byte order. The signature covers keccak256 of the same list
;;;; without the signature. Under the "v4" identity scheme the record carries a
;;;; 33-byte compressed secp256k1 public key and the signature is a bare r||s
;;;; (64 bytes, no recovery id). Records are capped at 300 bytes.

(defconstant +enr-max-size+ 300)

(defstruct (enr (:constructor %make-enr (signature seq pairs)))
  signature
  seq
  ;; An alist of (key-string . value-bytes) in the record's order.
  pairs)

(defun enr-value (record key)
  "Return the value bytes stored under KEY in RECORD, or NIL when absent."
  (cdr (assoc key (enr-pairs record) :test #'string=)))

(defun enr-public-key (record)
  "Return the 64-byte uncompressed public key of RECORD, or NIL when the
compressed key is absent or invalid."
  (let ((compressed (enr-value record "secp256k1")))
    (and compressed
         (secp256k1-decompress-public-key (ensure-byte-vector compressed)))))

(defun enr-content-rlp (seq pairs)
  "The RLP of [seq, k1, v1, ...] — the record content that is signed."
  (rlp-encode
   (apply #'make-rlp-list
          (list* (integer-to-minimal-bytes seq)
                 (loop for (key . value) in pairs
                       append (list (ascii-to-bytes key)
                                    (ensure-byte-vector value)))))))

(defun enr-sort-pairs (pairs)
  "Sort record PAIRS by key in byte order, as EIP-778 requires."
  (sort (copy-alist pairs)
        (lambda (a b) (and (string< a b) t))
        :key #'car))

(defun encode-enr (private-key seq extra-pairs)
  "Build and sign an ENR under the v4 scheme. EXTRA-PAIRS is an alist of
(key-string . value-bytes) such as (\"ip\" . #(127 0 0 1)); the id and
secp256k1 keys are supplied from PRIVATE-KEY. Signals if the record exceeds
300 bytes."
  (let* ((public-key (secp256k1-private-key-public-key private-key))
         (pairs (enr-sort-pairs
                 (list* (cons "id" (ascii-to-bytes "v4"))
                        (cons "secp256k1"
                              (secp256k1-compress-public-key public-key))
                        extra-pairs)))
         (signature (subseq (secp256k1-sign (keccak-256 (enr-content-rlp seq pairs))
                                            private-key)
                            0 64))
         (record (rlp-encode
                  (apply #'make-rlp-list
                         (list* (ensure-byte-vector signature)
                                (integer-to-minimal-bytes seq)
                                (loop for (key . value) in pairs
                                      append (list (ascii-to-bytes key)
                                                   (ensure-byte-vector value))))))))
    (when (> (length record) +enr-max-size+)
      (error "ENR exceeds ~D bytes" +enr-max-size+))
    record))

(defun decode-enr (bytes)
  "Decode and verify an ENR. Returns an ENR struct, or signals on an oversize
record, an unsupported identity scheme, or a signature that does not verify.

Values keep their raw RLP object (a byte string or a nested list, e.g. the empty
list go-ethereum uses for the snap key), and the signed content is rebuilt from
those raw items so a list-valued entry re-encodes exactly."
  (let ((bytes (ensure-byte-vector bytes)))
    (when (> (length bytes) +enr-max-size+)
      (error "ENR exceeds ~D bytes" +enr-max-size+))
    ;; A record is exactly rlp([signature, seq, ...]) — reject trailing bytes.
    (let* ((items (rlp-list-items (rlp-decode bytes)))
           (signature (ensure-byte-vector (first items)))
           (seq (bytes-to-integer (ensure-byte-vector (second items))))
           ;; content = rlp([seq, k1, v1, ...]) rebuilt from the raw items.
           (content (rlp-encode (apply #'make-rlp-list (rest items))))
           (pairs (loop for (key value) on (cddr items) by #'cddr
                        collect (cons (bytes-to-ascii (ensure-byte-vector key))
                                      value))))
      ;; EIP-778 requires keys byte-sorted and unique.
      (loop for (a b) on pairs
            while b
            when (string>= (car a) (car b))
              do (error "ENR keys must be sorted and unique"))
      (let ((id (cdr (assoc "id" pairs :test #'string=))))
        (unless (and id (string= (bytes-to-ascii (ensure-byte-vector id)) "v4"))
          (error "unsupported ENR identity scheme")))
      (let ((public-key (enr-public-key (%make-enr signature seq pairs))))
        (unless (and public-key
                     (= 64 (length signature))
                     (secp256k1-verify (keccak-256 content)
                                       (bytes-to-integer (subseq signature 0 32))
                                       (bytes-to-integer (subseq signature 32 64))
                                       public-key))
          (error "ENR signature does not verify")))
      (%make-enr signature seq pairs))))
