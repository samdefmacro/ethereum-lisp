(in-package #:ethereum-lisp.test)

;;;; Transaction gossip: the four message codecs, the rules about what we will
;;;; and will not pass on, and a full announce-fetch-accept exchange between two
;;;; peers over a real RLPx session.
;;;;
;;;; The pool here is a hash table behind the backend closures, so these tests
;;;; state gossip behavior directly — including a pool that rejects. That a
;;;; gossiped transaction reaches the node's real transaction pool is a separate
;;;; test, in cli-devnet-node-tests.lisp.

(defun eth-gossip-test-transaction (nonce &key (gas-price 2))
  (make-legacy-transaction :nonce nonce :gas-price gas-price :gas-limit 21000
                           :value 3 :data #(1) :v 27 :r 4 :s 5))

(defun eth-gossip-test-typed-transaction (nonce)
  (make-dynamic-fee-transaction :chain-id 1 :nonce nonce :max-fee-per-gas 10
                                :max-priority-fee-per-gas 1 :gas-limit 21000
                                :value 4 :y-parity 1 :r 6 :s 7))

(defun eth-gossip-test-blob-transaction (nonce)
  (let ((commitment
          (make-byte-vector +kzg-commitment-size+ :initial-element 2)))
    (make-blob-transaction
     :chain-id 1 :nonce nonce :max-fee-per-gas 10 :max-priority-fee-per-gas 1
     :gas-limit 21000 :max-fee-per-blob-gas 1
     ;; A blob transaction must have a recipient; it cannot create a contract.
     :to (address-from-hex "0x0000000000000000000000000000000000003001")
     :blob-versioned-hashes
     (list (kzg-commitment-to-versioned-hash commitment))
     :y-parity 0 :r 8 :s 9)))

(defun eth-gossip-transaction-hash-bytes (transaction)
  (hash32-bytes (transaction-hash transaction)))

(defun eth-gossip-test-blob-sidecar ()
  (make-blob-sidecar
   :blobs (list (make-byte-vector +blob-byte-size+ :initial-element 1))
   :commitments
   (list (make-byte-vector +kzg-commitment-size+ :initial-element 2))
   :proofs (list (make-byte-vector +kzg-proof-size+ :initial-element 3))))

(defun eth-gossip-test-backend (&key (transactions '()) reject-p)
  "A backend over hash-table pools. Returns (VALUES BACKEND POOL SIDECARS);
REJECT-P, if given, is a predicate marking transactions the pool turns down."
  (let ((pool (make-hash-table :test #'equalp))
        (sidecars (make-hash-table :test #'equalp))
        (pending-sidecar nil))
    (dolist (transaction transactions)
      (setf (gethash (eth-gossip-transaction-hash-bytes transaction) pool)
            transaction)
      (when (typep transaction 'blob-transaction)
        (setf (gethash (eth-gossip-transaction-hash-bytes transaction)
                       sidecars)
              (eth-gossip-test-blob-sidecar))))
    (values
     (make-eth-serve-backend
      :pooled-transaction (lambda (hash) (gethash hash pool))
      :pooled-transaction-sidecar
      (lambda (transaction)
        (gethash (eth-gossip-transaction-hash-bytes transaction) sidecars))
      :known-transaction-p (lambda (hash) (nth-value 1 (gethash hash pool)))
      :accept-transaction
      (lambda (transaction &optional sidecar)
        (when (and reject-p (funcall reject-p transaction))
          (error "test pool rejected the transaction"))
        (setf (gethash (eth-gossip-transaction-hash-bytes transaction) pool)
              transaction)
        (when (or sidecar pending-sidecar)
          (setf (gethash (eth-gossip-transaction-hash-bytes transaction)
                         sidecars)
                (or sidecar pending-sidecar)
                pending-sidecar nil)))
      :accept-blob-sidecar
      (lambda (sidecar) (setf pending-sidecar sidecar)))
     pool
     sidecars)))

(defun eth-gossip-test-peer (backend)
  "A peer with no connection, for exercising the parts that only touch state."
  (ethereum-lisp.eth-sync::%make-eth-peer :serve-backend backend))

(defun eth-gossip-test-call-with-function-overrides (bindings thunk)
  "Call THUNK with global function BINDINGS, restoring every definition."
  (let ((originals
          (mapcar (lambda (binding)
                    (cons (car binding) (fdefinition (car binding))))
                  bindings)))
    (unwind-protect
         (progn
           (dolist (binding bindings)
             (setf (fdefinition (car binding)) (cdr binding)))
           (funcall thunk))
      (dolist (binding originals)
        (setf (fdefinition (car binding)) (cdr binding))))))

;;; Codecs.

(deftest eth-transactions-message-round-trips
  (:layer :unit :module :p2p)
  (let* ((transactions (list (eth-gossip-test-transaction 1)
                             (eth-gossip-test-typed-transaction 2)))
         (decoded (ethereum-lisp.eth-wire:decode-eth-transactions
                   (ethereum-lisp.eth-wire:encode-eth-transactions transactions))))
    (is (= 2 (length decoded)))
    ;; Both encodings survive: the legacy one rides as a list, the typed one as
    ;; an opaque string, and each comes back byte-identical.
    (loop for sent in transactions
          for got in decoded
          do (is (bytes= (transaction-encoding sent)
                         (transaction-encoding got))))))

(deftest eth-transaction-gossip-item-counts-are-bounded
  (:layer :unit :module :p2p)
  ;; The ordinary round-trip above is the positive control. These hostile
  ;; messages exceed the decoder bounds before transaction/hash materialization.
  (signals rlp-error
    (ethereum-lisp.eth-wire:decode-eth-transactions
     (rlp-encode
      (apply #'make-rlp-list
             (loop repeat
                   (1+ ethereum-lisp.eth-wire:+eth-max-transactions-per-message+)
                   collect (make-byte-vector 0))))))
  (signals error
    (ethereum-lisp.eth-wire:decode-eth-new-pooled-transaction-hashes
     (rlp-encode
      (make-rlp-list
       (make-byte-vector
        (1+ ethereum-lisp.eth-wire:+eth-max-transaction-announcements+))
       (make-rlp-list)
       (make-rlp-list))))))

(deftest eth-gossip-tracks-peer-knowledge-and-large-transactions
  (:layer :unit :module :p2p)
  (multiple-value-bind (backend pool) (eth-gossip-test-backend)
    (declare (ignore pool))
    (let* ((peer (eth-gossip-test-peer backend))
           (small (eth-gossip-test-transaction 1))
           (large
             (make-legacy-transaction
              :nonce 2 :gas-price 2 :gas-limit 100000
              :value 3 :v 27 :r 4 :s 5
              :data (make-array 5000 :element-type '(unsigned-byte 8)
                                :initial-element 1))))
      ;; Receiving a full transaction records that this peer knows it, so the
      ;; next txpool poll cannot reflect it straight back.
      (is (ethereum-lisp.eth-sync:eth-peer-gossip-message
           peer ethereum-lisp.eth-wire:+eth-message-transactions+
           (ethereum-lisp.eth-wire:encode-eth-transactions (list small))))
      (is (ethereum-lisp.eth-sync:eth-peer-knows-transaction-p peer small))
      (is (null
           (ethereum-lisp.eth-sync::eth-peer-sendable-transactions
            peer (list small)
            (lambda (size) (declare (ignore size)) t))))
      ;; A payload above the full-broadcast threshold is left for the hash
      ;; announcement pass in the pump.
      (is (> (length (transaction-encoding large))
             ethereum-lisp.eth-sync:+eth-full-transaction-broadcast-size+))
      (is (null
           (ethereum-lisp.eth-sync::eth-peer-sendable-transactions
            peer (list large)
            (lambda (size)
              (<= size
                  ethereum-lisp.eth-sync:+eth-full-transaction-broadcast-size+)))))
      (is (= 1
             (length
              (ethereum-lisp.eth-sync::eth-peer-sendable-transactions
               peer (list large)
               (lambda (size) (declare (ignore size)) t))))))))

(deftest eth-new-pooled-transaction-hashes-round-trips
  (:layer :unit :module :p2p)
  (let ((transactions (list (eth-gossip-test-transaction 1)
                            (eth-gossip-test-typed-transaction 2))))
    (multiple-value-bind (types sizes hashes)
        (ethereum-lisp.eth-wire:decode-eth-new-pooled-transaction-hashes
         (ethereum-lisp.eth-wire:encode-eth-new-pooled-transaction-hashes
          transactions))
      ;; Three columns of equal length, aligned by position.
      (is (equal '(0 2) types))
      (is (equal (mapcar (lambda (transaction)
                           (length (transaction-encoding transaction)))
                         transactions)
                 sizes))
      (loop for transaction in transactions
            for hash in hashes
            do (is (bytes= (eth-gossip-transaction-hash-bytes transaction) hash))))
    ;; An announcement with no transactions still encodes and decodes.
    (multiple-value-bind (types sizes hashes)
        (ethereum-lisp.eth-wire:decode-eth-new-pooled-transaction-hashes
         (ethereum-lisp.eth-wire:encode-eth-new-pooled-transaction-hashes '()))
      (is (null types))
      (is (null sizes))
      (is (null hashes)))))

(deftest eth-new-pooled-blob-announcement-uses-wrapper-size
  (:layer :unit :module :p2p)
  (let* ((transaction (eth-gossip-test-blob-transaction 3))
         (sidecar (eth-gossip-test-blob-sidecar))
         (entry (make-blob-network-transaction transaction sidecar)))
    (multiple-value-bind (types sizes hashes)
        (ethereum-lisp.eth-wire:decode-eth-new-pooled-transaction-hashes
         (ethereum-lisp.eth-wire:encode-eth-new-pooled-transaction-hashes
          (list entry)))
      (is (equal '(3) types))
      (is (equal
           (list
            (length (blob-pooled-transaction-encoding transaction sidecar)))
           sizes))
      (is (bytes= (eth-gossip-transaction-hash-bytes transaction)
                  (first hashes))))))

(deftest eth-new-pooled-transaction-hashes-rejects-ragged-columns
  (:layer :unit :module :p2p)
  ;; A peer whose columns disagree is malformed. Pairing them up anyway would
  ;; silently attach one transaction's size to another's hash.
  (signals error
    (ethereum-lisp.eth-wire:decode-eth-new-pooled-transaction-hashes
     (rlp-encode
      (make-rlp-list
       (ensure-byte-vector #(0 2))
       (make-rlp-list (integer-to-minimal-bytes 100))
       (make-rlp-list
        (hex-to-bytes
         "0x1111111111111111111111111111111111111111111111111111111111111111")
        (hex-to-bytes
         "0x2222222222222222222222222222222222222222222222222222222222222222")))))))

(deftest eth-gossip-queues-hash-announcements-and-submits-full-blocks
  (:layer :unit :module :p2p)
  (let* ((accepted nil)
         (backend
           (ethereum-lisp.eth-sync:make-eth-serve-backend
            :accept-block (lambda (block) (setf accepted block))))
         (peer (eth-gossip-test-peer backend))
         (block
           (ethereum-lisp.blocks:make-block-from-parts
            :header (make-block-header :number 9 :difficulty 0
                                       :gas-limit 30000000
                                       :extra-data (make-byte-vector 0))))
         (hash (hash32-bytes (block-hash block))))
    (is (ethereum-lisp.eth-sync:eth-peer-gossip-message
         peer ethereum-lisp.eth-wire:+eth-message-new-block-hashes+
         (ethereum-lisp.eth-wire:encode-eth-new-block-hashes
          (list (ethereum-lisp.eth-wire:make-eth-new-block-hash hash 9)))))
    (is (= 1 (ethereum-lisp.eth-sync:eth-peer-announced-block-count peer)))
    (is (ethereum-lisp.eth-sync:eth-peer-gossip-message
         peer ethereum-lisp.eth-wire:+eth-message-new-block+
         (ethereum-lisp.eth-wire:encode-eth-new-block
          (ethereum-lisp.eth-wire:make-eth-new-block block 0))))
    (is (not (null accepted)))
    (is (bytes= (hash32-bytes (block-hash block))
                (hash32-bytes (block-hash accepted))))))

(deftest eth-new-block-gossip-propagates-backend-storage-error
  (:layer :unit :module :p2p)
  (let* ((accept-calls 0)
         (backend
           (ethereum-lisp.eth-sync:make-eth-serve-backend
            :accept-block
            (lambda (block)
              (declare (ignore block))
              (incf accept-calls)
              (ethereum-lisp.validation:storage-fail
               "Injected NewBlock storage failure"))))
         (peer (eth-gossip-test-peer backend))
         (block
           (ethereum-lisp.blocks:make-block-from-parts
            :header (make-block-header :number 9 :difficulty 0
                                       :gas-limit 30000000
                                       :extra-data (make-byte-vector 0)))))
    (signals ethereum-lisp.validation:storage-error
      (ethereum-lisp.eth-sync:eth-peer-gossip-message
       peer ethereum-lisp.eth-wire:+eth-message-new-block+
       (ethereum-lisp.eth-wire:encode-eth-new-block
        (ethereum-lisp.eth-wire:make-eth-new-block block 0))))
    (is (= 1 accept-calls))))

(deftest eth-new-block-hashes-fetch-propagates-backend-storage-error
  (:layer :unit :module :p2p)
  (let* ((accept-calls 0)
         (header-fetches 0)
         (body-fetches 0)
         (header
           (make-block-header
            :number 9 :difficulty 0 :gas-limit 30000000
            :extra-data (make-byte-vector 0)
            :transactions-root (transaction-list-root '())
            :ommers-hash (ommers-hash '())))
         (body
           (ethereum-lisp.eth-wire:make-eth-block-body
            :transactions '() :ommers '()))
         (hash (hash32-bytes (block-header-hash header)))
         (backend
           (ethereum-lisp.eth-sync:make-eth-serve-backend
            :accept-block
            (lambda (block)
              (declare (ignore block))
              (incf accept-calls)
              (ethereum-lisp.validation:storage-fail
               "Injected NewBlockHashes fetch storage failure"))))
         (peer (eth-gossip-test-peer backend)))
    (is (ethereum-lisp.eth-sync:eth-peer-gossip-message
         peer ethereum-lisp.eth-wire:+eth-message-new-block-hashes+
         (ethereum-lisp.eth-wire:encode-eth-new-block-hashes
          (list (ethereum-lisp.eth-wire:make-eth-new-block-hash hash 9)))))
    (eth-gossip-test-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.eth-sync:eth-peer-get-block-headers
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (incf header-fetches)
              (list header)))
      (cons 'ethereum-lisp.eth-sync:eth-peer-get-block-bodies
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (incf body-fetches)
              (list body))))
     (lambda ()
       (signals ethereum-lisp.validation:storage-error
         (ethereum-lisp.eth-sync:eth-peer-fetch-announced-block peer))))
    (is (= 1 header-fetches))
    (is (= 1 body-fetches))
    (is (= 1 accept-calls))
    (is (zerop
         (ethereum-lisp.eth-sync:eth-peer-announced-block-count peer)))))

(deftest eth-gossip-applies-block-range-updates-without-a-serve-backend
  (:layer :unit :module :p2p)
  (let* ((old-hash
           (hex-to-bytes
            "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (new-hash
           (hex-to-bytes
            "0x2222222222222222222222222222222222222222222222222222222222222222"))
         (status
           (ethereum-lisp.eth-wire:make-eth-status
            :version 69 :earliest-block 1 :latest-block 10
            :latest-block-hash old-hash))
         (peer
           (ethereum-lisp.eth-sync::%make-eth-peer
            :eth-version 69 :remote-status status)))
    (is (ethereum-lisp.eth-sync:eth-peer-gossip-message
         peer ethereum-lisp.eth-wire:+eth-message-block-range-update+
         (ethereum-lisp.eth-wire:encode-eth-block-range-update
          (ethereum-lisp.eth-wire:make-eth-block-range 5 20 new-hash))))
    (is (= 5 (ethereum-lisp.eth-wire:eth-status-earliest-block status)))
    (is (= 20 (ethereum-lisp.eth-wire:eth-status-latest-block status)))
    (is (bytes=
         new-hash
         (ethereum-lisp.eth-wire:eth-status-latest-block-hash status)))))

(deftest eth-gossip-notifies-only-fresh-block-and-range-announcements
  (:layer :unit :module :p2p)
  (multiple-value-bind (backend pool) (eth-gossip-test-backend)
    (declare (ignore pool))
    (let* ((old-hash
             (make-byte-vector 32 :initial-element 1))
           (new-hash
             (make-byte-vector 32 :initial-element 2))
           (announced-hash
             (make-byte-vector 32 :initial-element 3))
           (status
             (ethereum-lisp.eth-wire:make-eth-status
              :version 69 :earliest-block 0 :latest-block 10
              :latest-block-hash old-hash))
           (peer
             (ethereum-lisp.eth-sync::%make-eth-peer
              :eth-version 69 :remote-status status :serve-backend backend))
           (notifications 0)
           (range-payload
             (ethereum-lisp.eth-wire:encode-eth-block-range-update
              (ethereum-lisp.eth-wire:make-eth-block-range
               5 20 new-hash)))
           (hash-payload
             (ethereum-lisp.eth-wire:encode-eth-new-block-hashes
              (list
               (ethereum-lisp.eth-wire:make-eth-new-block-hash
                announced-hash 21)))))
      (ethereum-lisp.eth-sync:eth-peer-set-sync-notification-function
       peer (lambda () (incf notifications)))
      ;; A validated range changes the peer availability snapshot before the
      ;; notification callback runs.
      (is (ethereum-lisp.eth-sync:eth-peer-gossip-message
           peer ethereum-lisp.eth-wire:+eth-message-block-range-update+
           range-payload))
      (is (= 1 notifications))
      (is (= 20 (ethereum-lisp.eth-wire:eth-status-latest-block status)))
      ;; Replaying identical untrusted input is coalesced at this boundary.
      (is (ethereum-lisp.eth-sync:eth-peer-gossip-message
           peer ethereum-lisp.eth-wire:+eth-message-block-range-update+
           range-payload))
      (is (= 1 notifications))
      ;; A fresh hash announcement wakes once; its duplicate neither grows the
      ;; bounded block queue nor manufactures another coordinator pass.
      (is (ethereum-lisp.eth-sync:eth-peer-gossip-message
           peer ethereum-lisp.eth-wire:+eth-message-new-block-hashes+
           hash-payload))
      (is (= 2 notifications))
      (is (ethereum-lisp.eth-sync:eth-peer-gossip-message
           peer ethereum-lisp.eth-wire:+eth-message-new-block-hashes+
           hash-payload))
      (is (= 2 notifications))
      (is (= 1
             (ethereum-lisp.eth-sync:eth-peer-announced-block-count peer))))))

(deftest eth-pooled-transaction-messages-round-trip
  (:layer :unit :module :p2p)
  (let ((hashes (list (eth-gossip-transaction-hash-bytes
                       (eth-gossip-test-transaction 1))
                      (eth-gossip-transaction-hash-bytes
                       (eth-gossip-test-transaction 2)))))
    (multiple-value-bind (request-id decoded)
        (ethereum-lisp.eth-wire:decode-eth-get-pooled-transactions
         (ethereum-lisp.eth-wire:encode-eth-get-pooled-transactions 9 hashes))
      (is (= 9 request-id))
      (is (= 2 (length decoded)))
      (is (bytes= (first hashes) (first decoded)))))
  (let ((transactions (list (eth-gossip-test-transaction 1)
                            (eth-gossip-test-typed-transaction 2))))
    (multiple-value-bind (request-id decoded)
        (ethereum-lisp.eth-wire:decode-eth-pooled-transactions
         (ethereum-lisp.eth-wire:encode-eth-pooled-transactions 11 transactions))
      (is (= 11 request-id))
      (is (= 2 (length decoded)))
      (is (bytes= (transaction-encoding (second transactions))
                  (transaction-encoding (second decoded))))))
  (let* ((blob (eth-gossip-test-blob-transaction 3))
         (sidecar (eth-gossip-test-blob-sidecar))
         (entry (cons blob sidecar)))
    (multiple-value-bind (request-id decoded)
        (ethereum-lisp.eth-wire:decode-eth-pooled-transactions
         (ethereum-lisp.eth-wire:encode-eth-pooled-transactions
          12 (list entry)))
      (is (= 12 request-id))
      (is (= 1 (length decoded)))
      (is (bytes=
           (transaction-encoding blob)
           (transaction-encoding
            (ethereum-lisp.eth-wire:eth-pooled-entry-transaction
             (first decoded)))))
      (is (equalp
           (blob-sidecar-blobs sidecar)
           (blob-sidecar-blobs
            (ethereum-lisp.eth-wire:eth-pooled-entry-sidecar
             (first decoded))))))))

;;; What we will and will not pass on.

(deftest eth-gossip-serves-blob-transactions-with-sidecars
  (:layer :unit :module :p2p)
  ;; A bare type-3 transaction is not gossipable, but the pooled envelope with
  ;; its sidecar is announced and served.
  (let ((plain (eth-gossip-test-transaction 1))
        (blob (eth-gossip-test-blob-transaction 2)))
    (is (eth-gossipable-transaction-p plain))
    (is (not (eth-gossipable-transaction-p blob)))
    (is (eth-gossipable-transaction-p
         (cons blob (eth-gossip-test-blob-sidecar))))
    (multiple-value-bind (backend pool)
        (eth-gossip-test-backend :transactions (list plain blob))
      (declare (ignore pool))
      ;; Asked for both by hash, both are served and the blob keeps its sidecar.
      (let ((served (eth-serve-pooled-transactions
                     backend
                     (list (eth-gossip-transaction-hash-bytes blob)
                           (eth-gossip-transaction-hash-bytes plain)))))
        (is (= 2 (length served)))
        (is (typep (ethereum-lisp.eth-wire:eth-pooled-entry-transaction
                    (first served))
                   'blob-transaction))
        (is (typep (ethereum-lisp.eth-wire:eth-pooled-entry-sidecar
                    (first served))
                   'blob-sidecar))
        (is (bytes= (transaction-encoding plain)
                    (transaction-encoding (second served))))))))

(deftest eth-gossip-selects-pooled-blob-proof-format-by-eth-version
  (:layer :unit :module :p2p)
  ;; Hive's eth/69 pooled-transaction request exposed this seam: an RPC wrapper
  ;; stores a legacy proof, while eth/72 needs cell proofs. Selecting only the
  ;; latter made pre-72 requests look as if the transaction did not exist.
  (let* ((transaction (eth-gossip-test-blob-transaction 9))
         (hash (eth-gossip-transaction-hash-bytes transaction))
         (legacy-sidecar (eth-gossip-test-blob-sidecar))
         (cell-sidecar
           (make-blob-sidecar
            :blobs (blob-sidecar-blobs legacy-sidecar)
            :commitments (blob-sidecar-commitments legacy-sidecar)
            :proofs
            (loop repeat +cell-proofs-per-blob+
                  collect (make-byte-vector +kzg-proof-size+))))
         (backend
           (make-eth-serve-backend
            :pooled-transaction
            (lambda (requested)
              (and (bytes= requested hash) transaction))
            :pooled-transaction-sidecar
            (lambda (requested)
              (declare (ignore requested))
              legacy-sidecar)
            :pooled-blob-sidecar
            (lambda (requested)
              (declare (ignore requested))
              cell-sidecar))))
    (flet ((served-sidecar (version)
             (ethereum-lisp.eth-wire:eth-pooled-entry-sidecar
              (first
               (eth-serve-pooled-transactions
                backend (list hash) :version version)))))
      (is (= 1
             (length
              (blob-sidecar-proofs
               (served-sidecar
                ethereum-lisp.eth-wire:+eth-protocol-version-69+)))))
      (is (= +cell-proofs-per-blob+
             (length
              (blob-sidecar-proofs
               (served-sidecar
                ethereum-lisp.eth-wire:+eth-protocol-version-72+))))))))

(deftest eth-gossip-serves-and-verifies-versioned-blob-wrapper
  (:layer :unit :module :p2p)
  (let* ((blob (make-byte-vector +blob-byte-size+))
         (commitment (make-byte-vector +kzg-commitment-size+))
         (proofs
           (loop repeat +cell-proofs-per-blob+
                 collect (make-byte-vector +kzg-proof-size+)))
         (transaction
           (make-blob-transaction
            :chain-id 1
            :to (address-from-hex
                 "0x0000000000000000000000000000000000003001")
            :blob-versioned-hashes
            (list (kzg-commitment-to-versioned-hash commitment))))
         (sidecar
           (make-blob-sidecar :blobs (list blob)
                              :commitments (list commitment)
                              :proofs proofs))
         (stored-sidecar nil)
         (accepted nil)
         (server
           (make-eth-serve-backend
            :pooled-transaction (lambda (hash)
                                  (declare (ignore hash))
                                  transaction)
            :pooled-blob-sidecar (lambda (value)
                                   (declare (ignore value))
                                   sidecar)))
         (client
           (make-eth-serve-backend
            :accept-blob-sidecar
            (lambda (value) (setf stored-sidecar value))
            :accept-transaction
            (lambda (value) (setf accepted value)))))
    (let ((served
            (eth-serve-pooled-transactions
             server (list (eth-gossip-transaction-hash-bytes transaction)))))
      (is (= 1 (length served)))
      (is (typep (first served) 'blob-network-transaction))
      (let ((*kzg-cell-proof-verifier*
              (lambda (verified-blob verified-commitment verified-proofs)
                (and (bytes= blob verified-blob)
                     (bytes= commitment verified-commitment)
                     (= +cell-proofs-per-blob+
                        (length verified-proofs))))))
        (is (= 1 (eth-accept-transactions client served)))
        (setf stored-sidecar nil
              accepted nil)
        (is (= 1 (eth-accept-transactions
                  client (list (cons transaction sidecar)))))))
    (is stored-sidecar)
    (is (eq transaction accepted))))

(deftest eth-72-pooled-blob-with-omitted-payload-does-not-drop-the-peer
  (:layer :unit :module :p2p)
  (let* ((commitment (make-byte-vector +kzg-commitment-size+))
         (transaction
           (make-blob-transaction
            :chain-id 1
            :to (address-from-hex
                 "0x0000000000000000000000000000000000003001")
            :blob-versioned-hashes
            (list (kzg-commitment-to-versioned-hash commitment))))
         (fragment
           (make-blob-sidecar
            :blobs '()
            :commitments (list commitment)
            :proofs
            (loop repeat +cell-proofs-per-blob+
                  collect (make-byte-vector +kzg-proof-size+))))
         (accepted 0)
         (stored 0)
         (backend
           (make-eth-serve-backend
            :accept-transaction
            (lambda (value) (declare (ignore value)) (incf accepted))
            :accept-blob-sidecar
            (lambda (value) (declare (ignore value)) (incf stored))))
         (peer (ethereum-lisp.eth-sync::%make-eth-peer
                :eth-version ethereum-lisp.eth-wire:+eth-protocol-version-72+
                :serve-backend backend))
         (payload
           (ethereum-lisp.eth-wire:encode-eth-pooled-transactions
            77 (list (make-blob-network-transaction transaction fragment)))))
    ;; Geth's eth/72 network encoder sends exactly this shape: commitments and
    ;; 128 cell proofs remain, while the blob list is empty and GetCells carries
    ;; the payload later. It is valid framing, but not yet a poolable sidecar.
    (is (ethereum-lisp.eth-sync:eth-peer-gossip-message
         peer ethereum-lisp.eth-wire:+eth-message-pooled-transactions+ payload))
    (is (zerop accepted))
    (is (zerop stored))
    ;; The same payload is not valid before eth/72's GetCells semantics.
    (setf (ethereum-lisp.eth-sync:eth-peer-eth-version peer)
          ethereum-lisp.eth-wire:+eth-protocol-version-71+)
    (signals block-validation-error
      (ethereum-lisp.eth-sync:eth-peer-gossip-message
       peer ethereum-lisp.eth-wire:+eth-message-pooled-transactions+ payload))))

(deftest eth-gossip-serves-only-the-pooled-transactions-it-has
  (:layer :unit :module :p2p)
  (let* ((held (eth-gossip-test-transaction 1))
         (missing (eth-gossip-test-transaction 2)))
    (multiple-value-bind (backend pool) (eth-gossip-test-backend
                                         :transactions (list held))
      (declare (ignore pool))
      (let ((served (eth-serve-pooled-transactions
                     backend
                     (list (eth-gossip-transaction-hash-bytes missing)
                           (eth-gossip-transaction-hash-bytes held)
                           ;; A malformed hash is skipped, not an error.
                           (ensure-byte-vector #(1 2 3))))))
        (is (= 1 (length served)))
        (is (bytes= (transaction-encoding held)
                    (transaction-encoding (first served))))))))

(deftest eth-gossip-accepts-what-the-pool-takes-and-skips-what-it-rejects
  (:layer :unit :module :p2p)
  ;; Peers relay without pre-filtering for us, so one transaction the pool turns
  ;; down must not cost us the connection or the rest of the batch.
  (let ((good (eth-gossip-test-transaction 1))
        (bad (eth-gossip-test-transaction 2))
        (also-good (eth-gossip-test-transaction 3)))
    (multiple-value-bind (backend pool)
        (eth-gossip-test-backend
         :reject-p (lambda (transaction) (= (transaction-nonce transaction) 2)))
      (is (= 2 (eth-accept-transactions backend (list good bad also-good))))
      (is (= 2 (hash-table-count pool)))
      (is (null (gethash (eth-gossip-transaction-hash-bytes bad) pool))))))

(deftest eth-gossip-fresh-chain-gate-precedes-transaction-decoding
  (:layer :unit :module :p2p)
  ;; Pinned geth checks Backend.AcceptTxs before decoding all three inbound
  ;; transaction message kinds. Malformed payloads therefore prove both the
  ;; gate and its position: any decoder reached below would signal.
  (let* ((gate-calls 0)
         (backend
           (make-eth-serve-backend
            :accept-transactions-p
            (lambda () (incf gate-calls) nil)
            :accept-transaction
            (lambda (transaction)
              (declare (ignore transaction))
              (error "syncing node admitted an inbound transaction"))))
         (peer
           (ethereum-lisp.eth-sync::%make-eth-peer
            :eth-version ethereum-lisp.eth-wire:+eth-protocol-version-72+
            :serve-backend backend))
         (malformed (ensure-byte-vector #(255))))
    (is (eth-peer-gossip-message
         peer ethereum-lisp.eth-wire:+eth-message-transactions+ malformed))
    (is (eth-peer-gossip-message
         peer ethereum-lisp.eth-wire:+eth-message-new-pooled-transaction-hashes+
         malformed))
    (is (eth-peer-gossip-message
         peer ethereum-lisp.eth-wire:+eth-message-pooled-transactions+ malformed))
    (is (= 3 gate-calls))
    (is (zerop (eth-peer-announced-hash-count peer)))))

(deftest eth-gossip-queues-only-announced-hashes-worth-fetching
  (:layer :unit :module :p2p)
  (let* ((held (eth-gossip-test-transaction 1))
         (wanted (eth-gossip-test-transaction 2)))
    (multiple-value-bind (backend pool) (eth-gossip-test-backend
                                         :transactions (list held))
      (declare (ignore pool))
      (let ((peer (eth-gossip-test-peer backend))
            (held-hash (eth-gossip-transaction-hash-bytes held))
            (wanted-hash (eth-gossip-transaction-hash-bytes wanted)))
        ;; One already in the pool, one new, one announced twice, one malformed.
        (is (= 1 (eth-peer-queue-announced-hashes
                  peer backend
                  (list held-hash wanted-hash wanted-hash
                        (ensure-byte-vector #(1 2 3))))))
        (is (= 1 (eth-peer-announced-hash-count peer)))
        ;; Re-announcing what is already queued adds nothing.
        (is (= 0 (eth-peer-queue-announced-hashes peer backend
                                                  (list wanted-hash))))
        ;; Taking them empties the queue, so a peer that never answers does not
        ;; leave us asking for the same hashes forever.
        (let ((taken (eth-peer-take-announced-hashes peer 10)))
          (is (= 1 (length taken)))
          (is (bytes= wanted-hash (first taken))))
        (is (= 0 (eth-peer-announced-hash-count peer)))))))

(deftest eth-gossip-bounds-the-announced-hash-queue
  (:layer :unit :module :p2p)
  ;; A peer announcing faster than we fetch must not grow our memory without
  ;; bound; past the limit the excess is dropped.
  (multiple-value-bind (backend pool) (eth-gossip-test-backend)
    (declare (ignore pool))
    (let* ((peer (eth-gossip-test-peer backend))
           (over (+ +eth-max-announced-transaction-hashes+ 50))
           (hashes (loop for n from 1 to over
                         collect (eth-gossip-transaction-hash-bytes
                                  (eth-gossip-test-transaction n)))))
      (is (= +eth-max-announced-transaction-hashes+
             (eth-peer-queue-announced-hashes peer backend hashes)))
      (is (= +eth-max-announced-transaction-hashes+
             (eth-peer-announced-hash-count peer)))
      (is (= 25 (length (eth-peer-take-announced-hashes peer 25)))))))

;;; A full exchange over a real session.

(deftest eth-gossip-announce-fetch-and-accept-over-a-socket
  (:layer :integration :module :p2p :requires-local-sockets t)
  ;; The whole path: the server announces a transaction by hash, the client
  ;; queues it, asks for it, and puts it in its pool — every message handled by
  ;; the gossip layer on both sides.
  (let* ((config (eth-sync-test-config))
         (server-static
          #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (client-static
          #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (server-static-pub (secp256k1-private-key-public-key server-static))
         (offered (eth-gossip-test-transaction 7))
         (blob (eth-gossip-test-blob-transaction 8))
         (listener (make-instance 'sb-bsd-sockets:inet-socket
                                  :type :stream :protocol :tcp)))
    (multiple-value-bind (server-backend server-pool)
        (eth-gossip-test-backend :transactions (list offered blob))
      (declare (ignore server-pool))
      (multiple-value-bind (client-backend client-pool client-sidecars)
          (eth-gossip-test-backend)
        (flet ((hello (client-id)
                 (make-devp2p-hello
                  :client-id client-id
                  :capabilities (list (make-devp2p-capability "eth" 68))
                  :node-id server-static-pub))
               (status ()
                 (eth-build-status config *eth-sync-test-genesis* 0 0
                                   *eth-sync-test-genesis* 0)))
          (setf (sb-bsd-sockets:sockopt-reuse-address listener) t)
          (unwind-protect
               (progn
                 (sb-bsd-sockets:socket-bind
                  listener (sb-bsd-sockets:make-inet-address "127.0.0.1") 0)
                 (sb-bsd-sockets:socket-listen listener 1)
                 (multiple-value-bind (address port)
                     (sb-bsd-sockets:socket-name listener)
                   (declare (ignore address))
                   (let ((server-error nil)
                         (announced nil))
                     (let ((server-thread
                             (sb-thread:make-thread
                              (lambda ()
                                (handler-case
                                    (let* ((cs (sb-bsd-sockets:socket-accept
                                                listener))
                                           (stream (p2p-binary-socket-stream cs))
                                           (connection (rlpx-accept-stream
                                                        stream server-static))
                                           (peer (eth-peer-connect
                                                  connection (hello "srv")
                                                  (status)
                                                  :serve-backend server-backend)))
                                      ;; The plain transaction and the blob
                                      ;; wrapper are both available to eth/68.
                                      (setf announced
                                            (eth-peer-announce-transactions
                                             peer (list offered blob)))
                                      ;; Answer the client's request for it.
                                      (eth-peer-serve-loop peer :max-messages 1))
                                  (error (condition)
                                    (setf server-error condition))))
                              :name "eth-gossip-test-server")))
                       (let ((client-socket
                               (make-instance 'sb-bsd-sockets:inet-socket
                                              :type :stream :protocol :tcp)))
                         (sb-bsd-sockets:socket-connect
                          client-socket
                          (sb-bsd-sockets:make-inet-address "127.0.0.1") port)
                         (let* ((stream (p2p-binary-socket-stream client-socket))
                                (connection (rlpx-connect-stream
                                             stream client-static
                                             server-static-pub))
                                (peer (eth-peer-connect
                                       connection (hello "cli") (status)
                                       :serve-backend client-backend)))
                           ;; Read the announcement, which only queues hashes.
                           (eth-peer-serve-loop peer :max-messages 1)
                           (is (= 2 (eth-peer-announced-hash-count peer)))
                           (is (zerop (hash-table-count client-pool)))
                           ;; Then ask for both, validate the V1 blob proof, and
                           ;; pool each transaction with the blob sidecar kept.
                           (let ((*kzg-blob-proof-verifier*
                                   (lambda (actual-blob actual-commitment
                                            actual-proof)
                                     (and
                                      (= +blob-byte-size+
                                         (length actual-blob))
                                      (= +kzg-commitment-size+
                                         (length actual-commitment))
                                      (= +kzg-proof-size+
                                         (length actual-proof))))))
                             (is (= 2
                                    (eth-peer-fetch-announced-transactions
                                     peer))))
                           (is (= 0 (eth-peer-announced-hash-count peer)))
                           (is (= 2 (hash-table-count client-pool)))
                           (let ((received (gethash
                                            (eth-gossip-transaction-hash-bytes
                                             offered)
                                            client-pool)))
                             (is (not (null received)))
                             (is (bytes= (transaction-encoding offered)
                                         (transaction-encoding received))))
                           (is (typep
                                (gethash
                                 (eth-gossip-transaction-hash-bytes blob)
                                 client-pool)
                                'blob-transaction))
                           (is (typep
                                (gethash
                                 (eth-gossip-transaction-hash-bytes blob)
                                 client-sidecars)
                                'blob-sidecar)))
                       (sb-thread:join-thread server-thread)
                       (when server-error
                         (error "eth gossip server side failed: ~A" server-error))
                       (is (= 2 announced))))))
            (ignore-errors (sb-bsd-sockets:socket-close listener)))))))))
