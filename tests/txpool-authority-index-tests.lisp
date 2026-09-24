(in-package #:ethereum-lisp.test)

;;;; EIP-7702 authority reservations and full-pool eviction.
;;;;
;;;; Oracles: EIP-7702 and go-ethereum v1.17 core/txpool/legacypool.
;;;; validateAuth keeps at most one in-flight transaction for an account that
;;;; is delegated or named by a pending authorization, and refuses a set-code
;;;; transaction whose authority already has one; the pool answers "is this
;;;; address a pending authority?" from an index (txLookup auths), never by
;;;; re-recovering every pooled authorization. priceHeap.cmp orders eviction by
;;;; the effective tip at the base fee, then the fee cap, then the tip cap.

(defun txpool-s6-signature-values (hash private-key)
  "R, S and y-parity of PRIVATE-KEY's signature over the hash32 HASH."
  (let ((signature (secp256k1-sign (hash32-bytes hash) private-key)))
    (values (bytes-to-integer (subseq signature 0 32))
            (bytes-to-integer (subseq signature 32 64))
            (aref signature 64))))

(defun txpool-s6-authorization (authority-key &key (chain-id 1337) (nonce 0))
  "An EIP-7702 authorization signed by AUTHORITY-KEY, delegating to 0x..7702."
  (let* ((target (address-from-hex "0x0000000000000000000000000000000000007702"))
         (unsigned (make-set-code-authorization
                    :chain-id chain-id :address target :nonce nonce)))
    (multiple-value-bind (r s y-parity)
        (txpool-s6-signature-values
         (set-code-authorization-signing-hash unsigned) authority-key)
      (make-set-code-authorization :chain-id chain-id :address target
                                   :nonce nonce :y-parity y-parity :r r :s s))))

(defun txpool-s6-set-code-transaction
    (private-key authorizations &key (nonce 0) (chain-id 1337))
  (let ((fields (list :chain-id chain-id :nonce nonce
                      :max-priority-fee-per-gas 2 :max-fee-per-gas 1000
                      :gas-limit 100000
                      :to (address-from-hex
                           "0x0000000000000000000000000000000000003001")
                      :authorization-list authorizations)))
    (multiple-value-bind (r s y-parity)
        (txpool-s6-signature-values
         (set-code-transaction-signing-hash
          (apply #'make-set-code-transaction fields))
         private-key)
      (apply #'make-set-code-transaction :y-parity y-parity :r r :s s fields))))

(defun txpool-s6-dynamic-fee-transaction
    (private-key &key (nonce 0) (tip 2) (fee-cap 1000) (chain-id 1337))
  (let ((fields (list :chain-id chain-id :nonce nonce
                      :max-priority-fee-per-gas tip :max-fee-per-gas fee-cap
                      :gas-limit 21000
                      :to (address-from-hex
                           "0x0000000000000000000000000000000000003001"))))
    (multiple-value-bind (r s y-parity)
        (txpool-s6-signature-values
         (dynamic-fee-transaction-signing-hash
          (apply #'make-dynamic-fee-transaction fields))
         private-key)
      (apply #'make-dynamic-fee-transaction :y-parity y-parity :r r :s s
             fields))))

(defun txpool-s6-admit (transaction store config &optional policy)
  "Admit TRANSACTION; the rejection message, or NIL when it was admitted."
  (handler-case
      (progn
        (ethereum-lisp.txpool.application:txpool-admit-transaction
         transaction store config
         (or policy
             (ethereum-lisp.txpool.application:make-txpool-admission-policy))
         :admitted-at 1)
        nil)
    (block-validation-error (condition)
      (princ-to-string condition))))

(defun txpool-s6-call-counting-recoveries (thunk)
  "Call THUNK; return how many EIP-7702 authorities it recovered."
  (let* ((name 'ethereum-lisp.transactions:set-code-authorization-authority)
         (original (fdefinition name))
         (calls 0))
    (unwind-protect
         (progn
           (setf (fdefinition name)
                 (lambda (authorization)
                   (incf calls)
                   (funcall original authorization)))
           (funcall thunk))
      (setf (fdefinition name) original))
    calls))

(deftest txpool-7702-admission-recovers-no-pooled-authorization
  (:layer :unit :module :txpool)
  ;; Every admission asked whether its sender was a pending authority by
  ;; recovering every authorization of every pooled set-code transaction.
  (let* ((senders '(31 32 33 34 35 36 37 38))
         (authorities '(41 42 43 44 45 46 47 48))
         (newcomer 39))
    (multiple-value-bind (store config)
        (txpool-s6-store (cons newcomer senders))
      (loop for sender in senders
            for authority in authorities
            do (is (null (txpool-s6-admit
                          (txpool-s6-set-code-transaction
                           sender (list (txpool-s6-authorization authority)))
                          store config))))
      (is (= 8 (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
                store)))
      (let ((recoveries
              (txpool-s6-call-counting-recoveries
               (lambda ()
                 (is (null (txpool-s6-admit
                            (txpool-s6-dynamic-fee-transaction newcomer)
                            store config)))))))
        (is (= 9 (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
                  store)))
        (is (zerop recoveries)))
      ;; Positive control for the counter: a set-code admission recovers its
      ;; own authorization.
      (is (plusp (txpool-s6-call-counting-recoveries
                  (lambda ()
                    (txpool-s6-admit
                     (txpool-s6-set-code-transaction
                      newcomer (list (txpool-s6-authorization 49)) :nonce 1)
                     store config))))))))

(deftest txpool-7702-pending-authorization-reserves-its-authority-until-it-leaves
  (:layer :unit :module :txpool)
  (let ((delegator 51) (authority 52) (bystander 53))
    (multiple-value-bind (store config)
        (txpool-s6-store (list delegator authority bystander))
      (let ((set-code (txpool-s6-set-code-transaction
                       delegator (list (txpool-s6-authorization authority)))))
        (is (null (txpool-s6-admit set-code store config)))
        ;; The authority is reserved: its own transaction is refused ...
        (is (search "reserved by a pending set-code authorization"
                    (txpool-s6-admit (txpool-s6-dynamic-fee-transaction authority)
                                     store config)))
        ;; ... while an unrelated sender is not (control).
        (is (null (txpool-s6-admit (txpool-s6-dynamic-fee-transaction bystander)
                                   store config)))
        ;; A set-code transaction naming an authority that has an in-flight
        ;; transaction is refused.
        (is (search "authority already has an in-flight transaction"
                    (txpool-s6-admit
                     (txpool-s6-set-code-transaction
                      delegator (list (txpool-s6-authorization bystander))
                      :nonce 1)
                     store config)))
        ;; Once the set-code transaction is included, the reservation goes
        ;; with it.
        (ethereum-lisp.txpool:engine-payload-store-remove-included-block-transactions
         store (make-block :header (make-block-header :number 1)
                           :transactions (list set-code)))
        (is (null (txpool-s6-admit (txpool-s6-dynamic-fee-transaction authority)
                                   store config)))))))

(deftest txpool-full-pool-evicts-by-effective-tip-at-the-child-base-fee
  (:layer :unit :module :txpool)
  ;; Head base fee 100 at exactly the gas target, so the child base fee is 100.
  ;; A offers a tip of 90 but its fee cap leaves room for 1; B pays 5.
  (multiple-value-bind (store config)
      (txpool-s6-store '(61 62 63 64) :base-fee 100 :gas-used 15000000)
    (let ((policy (ethereum-lisp.txpool.application:make-txpool-admission-policy
                   :global-slot-limit 2))
          (a (txpool-s6-dynamic-fee-transaction 61 :tip 90 :fee-cap 101))
          (b (txpool-s6-dynamic-fee-transaction 62 :tip 5 :fee-cap 10000))
          (c (txpool-s6-dynamic-fee-transaction 63 :tip 3 :fee-cap 10000))
          (d (txpool-s6-dynamic-fee-transaction 64 :tip 1 :fee-cap 10000)))
      (is (null (txpool-s6-admit a store config policy)))
      (is (null (txpool-s6-admit b store config policy)))
      ;; C (3) outbids A (1), the cheapest by what a block would earn.
      (is (null (txpool-s6-admit c store config policy)))
      (is (null (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
                 store (transaction-hash a))))
      (is (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
           store (transaction-hash b)))
      ;; Control: D (1) does not outbid the cheapest left (C, 3).
      (is (search "underpriced" (txpool-s6-admit d store config policy)))
      (is (= 2 (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
                store))))))
