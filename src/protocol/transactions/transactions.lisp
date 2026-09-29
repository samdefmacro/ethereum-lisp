(in-package #:ethereum-lisp.transactions)

;;;; Transaction validation, pricing, encoding, and sender recovery.

(defun chain-rules-transaction-type-supported-p (rules transaction)
  "Return whether RULES activate the envelope type used by TRANSACTION."
  (case (transaction-type transaction)
    (0 t)
    (1 (chain-rules-berlin-p rules))
    (2 (chain-rules-london-p rules))
    (3 (chain-rules-cancun-p rules))
    (4 (chain-rules-prague-p rules))
    (otherwise nil)))

(defun validate-transaction-type-for-config
    (transaction config block-number timestamp)
  (let* ((rules (chain-config-rules config block-number timestamp))
         (type (transaction-type transaction)))
    (when (chain-rules-transaction-type-supported-p rules transaction)
      (return-from validate-transaction-type-for-config t))
    (cond
      ((= type 1)
       (block-validation-fail "Access-list transaction before Berlin"))
      ((= type 2)
       (block-validation-fail "Dynamic-fee transaction before London"))
      ((= type 3)
       (block-validation-fail "Blob transaction before Cancun"))
      ((= type 4)
       (block-validation-fail "Set-code transaction before Prague"))
      (t
       (block-validation-fail "Unsupported transaction type"))))
  t)

(define-transaction-reader transaction-max-priority-fee-per-gas
  (legacy-transaction (legacy-transaction-gas-price transaction))
  (access-list-transaction (access-list-transaction-gas-price transaction))
  (dynamic-fee-transaction
   (dynamic-fee-transaction-max-priority-fee-per-gas transaction))
  (blob-transaction
   (blob-transaction-max-priority-fee-per-gas transaction))
  (set-code-transaction
   (set-code-transaction-max-priority-fee-per-gas transaction)))

(define-transaction-reader transaction-max-fee-per-gas
  (legacy-transaction (legacy-transaction-gas-price transaction))
  (access-list-transaction (access-list-transaction-gas-price transaction))
  (dynamic-fee-transaction
   (dynamic-fee-transaction-max-fee-per-gas transaction))
  (blob-transaction
   (blob-transaction-max-fee-per-gas transaction))
  (set-code-transaction
   (set-code-transaction-max-fee-per-gas transaction)))

(defun validate-1559-transaction-fees (transaction base-fee)
  (let ((max-priority-fee (transaction-max-priority-fee-per-gas transaction))
        (max-fee (transaction-max-fee-per-gas transaction)))
    (unless (uint256-p max-priority-fee)
      (block-validation-fail "Max priority fee must be uint256"))
    (unless (uint256-p max-fee)
      (block-validation-fail "Max fee per gas must be uint256"))
    (when (< max-fee max-priority-fee)
      (block-validation-fail "Max priority fee exceeds max fee"))
    (when (< max-fee base-fee)
      (block-validation-fail "Max fee per gas below base fee"))
    t))

(defun transaction-effective-gas-price
    (transaction &key (base-fee 0) (eip1559-enabled-p t))
  (if (not eip1559-enabled-p)
      (transaction-max-priority-fee-per-gas transaction)
      (progn
        (validate-1559-transaction-fees transaction base-fee)
        (if (or (typep transaction 'legacy-transaction)
                (typep transaction 'access-list-transaction))
            (transaction-max-fee-per-gas transaction)
            (+ base-fee
               (min (transaction-max-priority-fee-per-gas transaction)
                    (- (transaction-max-fee-per-gas transaction)
                       base-fee)))))))

(defun transaction-priority-fee-per-gas
    (transaction &key (base-fee 0) (eip1559-enabled-p t))
  (if (not eip1559-enabled-p)
      (transaction-max-priority-fee-per-gas transaction)
      (max 0 (- (transaction-effective-gas-price transaction
                                                 :base-fee base-fee)
                base-fee))))

(define-transaction-reader transaction-canonical-encoding
  (legacy-transaction (legacy-transaction-rlp transaction))
  (access-list-transaction (access-list-transaction-encoding transaction))
  (dynamic-fee-transaction (dynamic-fee-transaction-encoding transaction))
  (blob-transaction (blob-transaction-encoding transaction))
  (set-code-transaction (set-code-transaction-encoding transaction)))

(define-transaction-reader transaction-computation-cache
  (legacy-transaction
   (legacy-transaction-computation-cache transaction))
  (access-list-transaction
   (access-list-transaction-computation-cache transaction))
  (dynamic-fee-transaction
   (dynamic-fee-transaction-computation-cache transaction))
  (blob-transaction
   (blob-transaction-computation-cache transaction))
  (set-code-transaction
   (set-code-transaction-computation-cache transaction)))

(defun transaction-cached-encoding (transaction)
  "TRANSACTION's canonical encoding, computed once per object (see
TRANSACTION-COMPUTATION-CACHE).  The vector belongs to the cache: callers in
this module only read it."
  (let ((cache (transaction-computation-cache transaction)))
    (or (transaction-computation-cache-encoding cache)
        (setf (transaction-computation-cache-encoding cache)
              (transaction-canonical-encoding transaction)))))

(defun transaction-encoding (transaction)
  "TRANSACTION's canonical encoding: the typed envelope, or the RLP list of a
legacy transaction.  A fresh vector the caller owns, copied from the one the
object computes once."
  (copy-seq (transaction-cached-encoding transaction)))

(defun transaction-from-encoding (bytes)
  (let ((bytes (ensure-byte-vector bytes)))
    (when (zerop (length bytes))
      (block-validation-fail "Transaction encoding is empty"))
    (if (> (aref bytes 0) #x7f)
        (legacy-transaction-from-rlp bytes)
        (case (aref bytes 0)
          (1 (access-list-transaction-from-rlp (subseq bytes 1)))
          (2 (dynamic-fee-transaction-from-rlp (subseq bytes 1)))
          (3 (blob-transaction-from-rlp (subseq bytes 1)))
          (4 (set-code-transaction-from-rlp (subseq bytes 1)))
          (otherwise
           (block-validation-fail
            "Typed transaction decoding is not implemented yet"))))))

(defun pooled-transaction-from-encoding (bytes)
  "Decode a transaction accepted from a pool-facing wire surface.

The second value is a blob sidecar for an EIP-4844 network wrapper, or NIL for
canonical transaction encodings."
  (let ((bytes (ensure-byte-vector bytes)))
    (if (and (plusp (length bytes))
             (= 3 (aref bytes 0)))
        (handler-case
            (blob-pooled-transaction-from-encoding bytes)
          (block-validation-error ()
            (values (transaction-from-encoding bytes) nil)))
        (values (transaction-from-encoding bytes) nil))))

(defun transaction-hash (transaction)
  "Keccak-256 of TRANSACTION's canonical encoding, computed once per object."
  (let ((cache (transaction-computation-cache transaction)))
    (or (transaction-computation-cache-hash cache)
        (setf (transaction-computation-cache-hash cache)
              (keccak-256-hash (transaction-cached-encoding transaction))))))

(defun typed-transaction-sender
    (chain-id y-parity r s signing-hash &key expected-chain-id)
  (when (and (or (not expected-chain-id)
                 (= expected-chain-id chain-id))
             (secp256k1-valid-signature-values-p y-parity r s :low-s-p t))
    (secp256k1-recover-address (hash32-bytes signing-hash) y-parity r s)))

(defun access-list-transaction-sender (transaction &key expected-chain-id)
  "Recover the sender address from an EIP-2930 transaction signature."
  (typed-transaction-sender
   (access-list-transaction-chain-id transaction)
   (access-list-transaction-y-parity transaction)
   (access-list-transaction-r transaction)
   (access-list-transaction-s transaction)
   (access-list-transaction-signing-hash transaction)
   :expected-chain-id expected-chain-id))

(defun dynamic-fee-transaction-sender (transaction &key expected-chain-id)
  "Recover the sender address from an EIP-1559 transaction signature."
  (typed-transaction-sender
   (dynamic-fee-transaction-chain-id transaction)
   (dynamic-fee-transaction-y-parity transaction)
   (dynamic-fee-transaction-r transaction)
   (dynamic-fee-transaction-s transaction)
   (dynamic-fee-transaction-signing-hash transaction)
   :expected-chain-id expected-chain-id))

(defun blob-transaction-sender (transaction &key expected-chain-id)
  "Recover the sender address from an EIP-4844 transaction signature."
  (typed-transaction-sender
   (blob-transaction-chain-id transaction)
   (blob-transaction-y-parity transaction)
   (blob-transaction-r transaction)
   (blob-transaction-s transaction)
   (blob-transaction-signing-hash transaction)
   :expected-chain-id expected-chain-id))

(defun set-code-transaction-sender (transaction &key expected-chain-id)
  "Recover the sender address from an EIP-7702 set-code transaction signature."
  (typed-transaction-sender
   (set-code-transaction-chain-id transaction)
   (set-code-transaction-y-parity transaction)
   (set-code-transaction-r transaction)
   (set-code-transaction-s transaction)
   (set-code-transaction-signing-hash transaction)
   :expected-chain-id expected-chain-id))

(defgeneric transaction-sender (transaction &key expected-chain-id)
  (:documentation
   "The address TRANSACTION's signature recovers to, or NIL when it recovers
to none or EXPECTED-CHAIN-ID excludes it.

The recovery is cached on the transaction object, which cannot change
(TRANSACTION-COMPUTATION-CACHE).  The chain-id gate is the one the per-type
function applies (LEGACY-TRANSACTION-SENDER and friends), but it is evaluated
before the cache on every call, so callers asking with and without a chain id
share one recovery."))

(defun transaction-recovered-sender (transaction recover)
  "TRANSACTION's cached ungated sender, calling RECOVER on it at most once per
object."
  (let* ((cache (transaction-computation-cache transaction))
         (sender (transaction-computation-cache-sender cache)))
    (if (eq sender :unrecovered)
        (setf (transaction-computation-cache-sender cache)
              (funcall recover transaction))
        sender)))

(defun legacy-transaction-frontier-sender (transaction)
  "The address a legacy TRANSACTION's signature recovers to without the EIP-2
low-s bound (FrontierSigner), or NIL; recovered at most once per object.  No
chain-id gate applies: only an unprotected signature is asked."
  (let* ((cache (legacy-transaction-computation-cache transaction))
         (sender (transaction-computation-cache-frontier-sender cache)))
    (if (eq sender :unrecovered)
        (setf (transaction-computation-cache-frontier-sender cache)
              (legacy-transaction-sender transaction :homestead-p nil))
        sender)))

(defun legacy-transaction-sender-chain-id-admits-p
    (transaction expected-chain-id)
  "LEGACY-TRANSACTION-SENDER's chain-id gate: an unprotected (pre-EIP-155)
signature names no chain and passes every expected chain id."
  (or (null expected-chain-id)
      (not (legacy-transaction-protected-p transaction))
      (let ((chain-id (legacy-transaction-chain-id transaction)))
        (and chain-id (= expected-chain-id chain-id)))))

(defmacro define-transaction-sender-method
    (type recover &key chain-id admits-p)
  "Define TRANSACTION-SENDER for TYPE over the ungated RECOVER function.
The gate is ADMITS-P, a function of the transaction and the expected chain
id, or else equality with the typed CHAIN-ID reader, as in
TYPED-TRANSACTION-SENDER."
  `(defmethod transaction-sender ((transaction ,type) &key expected-chain-id)
     (when ,(if admits-p
                `(,admits-p transaction expected-chain-id)
                `(or (null expected-chain-id)
                     (= expected-chain-id (,chain-id transaction))))
       (transaction-recovered-sender transaction #',recover))))

(define-transaction-sender-method
  legacy-transaction legacy-transaction-sender
  :admits-p legacy-transaction-sender-chain-id-admits-p)
(define-transaction-sender-method
  access-list-transaction access-list-transaction-sender
  :chain-id access-list-transaction-chain-id)
(define-transaction-sender-method
  dynamic-fee-transaction dynamic-fee-transaction-sender
  :chain-id dynamic-fee-transaction-chain-id)
(define-transaction-sender-method
  blob-transaction blob-transaction-sender
  :chain-id blob-transaction-chain-id)
(define-transaction-sender-method
  set-code-transaction set-code-transaction-sender
  :chain-id set-code-transaction-chain-id)

(defun transaction-sender-for-rules (transaction rules &key expected-chain-id)
  "The address TRANSACTION's signature recovers to under the signer RULES
select, or NIL.

go-ethereum v1.17.6 core/types/transaction_signing.go MakeSigner picks the
signer by fork, EIP-155 first. From EIP-155 a legacy signature is recovered
as TRANSACTION-SENDER does (EIP155Signer, HomesteadSigner for an unprotected
V). Before it, HomesteadSigner.Sender and FrontierSigner.Sender hand the raw
V to recoverPlain, which accepts only 27 and 28, so a chain-id-protected
signature recovers to nothing. Before Homestead, FrontierSigner.Sender calls
recoverPlain with homestead false: the EIP-2 bound on s does not apply, and an
s above secp256k1n/2 recovers. NIL RULES are the latest fork."
  (cond
    ((or (null rules)
         (not (typep transaction 'legacy-transaction))
         (chain-rules-eip155-active-p rules))
     (transaction-sender transaction :expected-chain-id expected-chain-id))
    ((legacy-transaction-protected-p transaction) nil)
    ((chain-rules-homestead-active-p rules)
     (transaction-sender transaction :expected-chain-id expected-chain-id))
    (t
     ;; The shared recovery applies the low-s bound; only a signature it
     ;; refuses is recovered without it, once, into its own slot.  The
     ;; signature is unprotected here, so EXPECTED-CHAIN-ID gates nothing.
     (or (transaction-sender transaction :expected-chain-id expected-chain-id)
         (legacy-transaction-frontier-sender transaction)))))
