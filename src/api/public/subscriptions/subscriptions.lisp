(in-package #:ethereum-lisp.public-api)

;;;; eth_subscribe / eth_unsubscribe.
;;;;
;;;; A subscription belongs to ONE connection and dies with it. That is not a
;;;; simplification, it is the specified behaviour: the id is meaningless to any
;;;; other connection, and there is no way to reattach after a reconnect. So the
;;;; registry lives on the session rather than on the node, and closing a socket
;;;; is all the cleanup there is.
;;;;
;;;; THE FEED IS POLLED, NOT PUSHED. Nothing in the node offers a change stream
;;;; to hook -- the same problem the transaction gossip ran into, solved the
;;;; same way. Each connection keeps a cursor (the head it last reported, the
;;;; pending hashes it has already announced) and each pass reports the
;;;; difference. It costs one head comparison per connection per pass when
;;;; nothing has happened, which is the common case.

(defconstant +eth-rpc-subscription-id-bytes+ 16
  "How many random bytes a subscription id carries. geth uses 16; a client that
logs or indexes ids will not care, but matching the width costs nothing.")

(defconstant +eth-rpc-subscription-head-catchup-limit+ 128
  "How far back a newHeads cursor will walk to find the head it last reported.

Our policy, and a bound rather than a target. A connection that has been idle
across more blocks than this, or that is looking at a reorged-away branch, gets
the current head alone rather than a walk that might not terminate anywhere
useful.")

(defstruct (eth-rpc-subscription
            (:constructor %make-eth-rpc-subscription
                (id kind addresses topic-filters include-transactions-p)))
  "One live subscription. KIND is :NEW-HEADS, :LOGS or :NEW-PENDING-TRANSACTIONS."
  id
  kind
  addresses
  topic-filters
  include-transactions-p)

(defstruct (eth-rpc-subscription-registry
            (:constructor make-eth-rpc-subscription-registry ()))
  "The subscriptions of ONE connection, plus its cursor into the chain.

LAST-HEAD-HASH and KNOWN-PENDING are the cursor. They are per-connection because
two clients may be at different points, and a shared cursor would mean whichever
polled first consumed the notification for both."
  (subscriptions '())
  (last-head-hash nil)
  (known-pending nil))

(defun eth-rpc-subscription-count (registry)
  (length (eth-rpc-subscription-registry-subscriptions registry)))

(defun eth-rpc-new-subscription-id ()
  (bytes-to-hex (secure-random-bytes +eth-rpc-subscription-id-bytes+)))

(defun eth-rpc-subscription-kind-from-name (name)
  (cond
    ((string= name "newHeads") :new-heads)
    ((string= name "logs") :logs)
    ((string= name "newPendingTransactions") :new-pending-transactions)
    ;; Deliberately not supported, and named rather than lumped in with a
    ;; typo: syncing is a real geth subscription we simply do not offer, and a
    ;; client asking for it deserves to be told that rather than left guessing.
    ((string= name "syncing")
     (invalid-parameters-fail "eth_subscribe syncing is not supported"))
    (t (invalid-parameters-fail
        "eth_subscribe does not support the ~A subscription" name))))

(defun eth-rpc-handle-eth-subscribe (params registry)
  "Register a subscription and return its id.

The logs filter is parsed HERE rather than at notification time, so a malformed
filter is an error on the subscribe call -- where the client can see it -- and
not a silent absence of notifications later."
  (unless (and (listp params) (plusp (length params)))
    (invalid-parameters-fail "eth_subscribe requires a subscription name"))
  (let* ((name (first params))
         (kind (progn
                 (unless (stringp name)
                   (invalid-parameters-fail
                    "eth_subscribe subscription name must be a string"))
                 (eth-rpc-subscription-kind-from-name name)))
         (options (second params))
         (addresses nil)
         (topic-filters nil)
         (include-transactions-p nil))
    (case kind
      (:logs
       (when options
         (unless (json-object-p options)
           (invalid-parameters-fail "eth_subscribe logs filter must be an object"))
         (setf addresses (eth-rpc-log-filter-addresses options "eth_subscribe")
               topic-filters (eth-rpc-log-filter-topics options "eth_subscribe"))))
      (:new-pending-transactions
       ;; geth's second argument: true means send whole transactions instead of
       ;; just their hashes.
       (setf include-transactions-p (and options (not (eq options :false)) t))))
    (let ((subscription (%make-eth-rpc-subscription
                         (eth-rpc-new-subscription-id)
                         kind addresses topic-filters include-transactions-p)))
      (push subscription (eth-rpc-subscription-registry-subscriptions registry))
      (eth-rpc-subscription-id subscription))))

(defun eth-rpc-handle-eth-unsubscribe (params registry)
  "Drop a subscription, returning whether it existed.

An unknown id is FALSE rather than an error, which is what geth does: a client
tearing down after a reconnect should not have to distinguish `already gone`
from `never existed`."
  (unless (and (listp params) (= 1 (length params)))
    (invalid-parameters-fail "eth_unsubscribe requires exactly one id"))
  (let* ((id (first params))
         (before (eth-rpc-subscription-registry-subscriptions registry)))
    (unless (stringp id)
      (invalid-parameters-fail "eth_unsubscribe id must be a string"))
    (setf (eth-rpc-subscription-registry-subscriptions registry)
          (remove id before :key #'eth-rpc-subscription-id :test #'string-equal))
    (/= (length before)
        (length (eth-rpc-subscription-registry-subscriptions registry)))))

(defun eth-rpc-subscription-notification-json (id result)
  "One eth_subscription notification, as a JSON string.

A notification, so no id at the envelope level -- the subscription id lives in
params, and a client that replied to it would be replying to nothing."
  (json-encode
   (list (cons "jsonrpc" "2.0")
         (cons "method" "eth_subscription")
         (cons "params"
               (list (cons "subscription" id)
                     (cons "result" result))))))

(defun eth-rpc-subscription-new-heads (store registry)
  "Return new and removed blocks since the cursor moved.

The first value is the replacement branch oldest first. The second is the
orphaned branch from the former head backwards. If no common ancestor can be
found within the bounded walk, only the current head is reported and no removed
claim is fabricated."
  (let* ((head (chain-store-head-block store))
         (cursor (eth-rpc-subscription-registry-last-head-hash registry)))
    (when head
      (let ((head-hash (block-hash head)))
        (cond
          ((and cursor (hash32= cursor head-hash)) (values nil nil))
          ((null cursor)
           ;; First pass: adopt the head without reporting it. A client that
           ;; subscribes at block N wants N+1 onwards, not a replay of N.
           (setf (eth-rpc-subscription-registry-last-head-hash registry) head-hash)
           (values nil nil))
          (t
           (let ((old-chain '())
                 (old-hashes (make-hash-table :test 'equalp))
                 (walk (chain-store-known-block store cursor)))
             (loop repeat +eth-rpc-subscription-head-catchup-limit+
                   while walk
                   do (push walk old-chain)
                      (setf (gethash (engine-payload-store-key
                                     (block-hash walk))
                                    old-hashes)
                            t
                            walk
                            (chain-store-known-block
                             store
                             (block-header-parent-hash
                              (block-header walk)))))
             (setf old-chain (nreverse old-chain))
             (let ((new-blocks '())
                   (common-hash nil)
                   (walk head))
               (loop repeat +eth-rpc-subscription-head-catchup-limit+
                     while walk
                     for key = (engine-payload-store-key (block-hash walk))
                     do (if (gethash key old-hashes)
                            (progn
                              (setf common-hash key)
                              (return))
                            (progn
                              (push walk new-blocks)
                              (setf walk
                                    (chain-store-known-block
                                     store
                                     (block-header-parent-hash
                                      (block-header walk)))))))
             (setf (eth-rpc-subscription-registry-last-head-hash registry)
                   head-hash)
               (if common-hash
                   (values
                    new-blocks
                    (loop for block in old-chain
                          until (string=
                                 common-hash
                                 (engine-payload-store-key (block-hash block)))
                          collect block))
                   (values (list head) nil))))))))))

(defun eth-rpc-subscription-pending-hashes (store registry)
  "The pooled transactions this connection has not been told about yet.

Poll and diff, for the same reason the gossip broadcaster does it: consuming a
change feed would mean building one, and the pool has none that can be read
without disturbing the journal."
  (let ((known (or (eth-rpc-subscription-registry-known-pending registry)
                   (setf (eth-rpc-subscription-registry-known-pending registry)
                         (make-hash-table :test #'equal))))
        (fresh '()))
    (let ((current (make-hash-table :test #'equal)))
      (dolist (transaction (engine-payload-store-pending-transactions store))
        (let ((key (hash32-to-hex (transaction-hash transaction))))
          (setf (gethash key current) transaction)
          (unless (gethash key known)
            (push transaction fresh))))
      ;; Forget what has left the pool, so a transaction that is dropped and
      ;; later re-admitted is announced again -- and so the table cannot grow
      ;; without bound on a long-lived connection.
      (maphash (lambda (key value)
                 (declare (ignore value))
                 (unless (gethash key current) (remhash key known)))
               known)
      (dolist (transaction fresh)
        (setf (gethash (hash32-to-hex (transaction-hash transaction)) known) t)))
    (nreverse fresh)))

(defun eth-rpc-subscription-poll (store registry &key config)
  "Everything this connection should be sent now, as a list of JSON strings.

Returns NIL when nothing has changed, which is the common case and costs one
head comparison."
  (declare (ignore config))
  (let ((subscriptions (eth-rpc-subscription-registry-subscriptions registry))
        (messages '()))
    (when subscriptions
      (let ((wants-chain-p
              (some (lambda (s) (member (eth-rpc-subscription-kind s)
                                        '(:new-heads :logs)))
                    subscriptions)))
        (multiple-value-bind (new-blocks removed-blocks)
            (when wants-chain-p
              (eth-rpc-subscription-new-heads store registry))
          (let ((pending
                  (when (some (lambda (s)
                                (eq :new-pending-transactions
                                    (eth-rpc-subscription-kind s)))
                              subscriptions)
                    (eth-rpc-subscription-pending-hashes store registry))))
            (dolist (subscription subscriptions)
              (let ((id (eth-rpc-subscription-id subscription)))
                (ecase (eth-rpc-subscription-kind subscription)
              (:new-heads
               (dolist (block new-blocks)
                 (push (eth-rpc-subscription-notification-json
                        id (eth-rpc-header-object (block-header block)))
                       messages)))
              (:logs
               (dolist (block removed-blocks)
                 (dolist (log (eth-rpc-block-logs-object
                               block
                               (eth-rpc-subscription-addresses subscription)
                               (eth-rpc-subscription-topic-filters
                                subscription)
                               :removed-p t))
                   (push (eth-rpc-subscription-notification-json id log)
                         messages)))
               (dolist (block new-blocks)
                 (dolist (log (eth-rpc-block-logs-object
                               block
                               (eth-rpc-subscription-addresses subscription)
                               (eth-rpc-subscription-topic-filters
                                subscription)))
                   (push (eth-rpc-subscription-notification-json id log)
                         messages))))
              (:new-pending-transactions
               (dolist (transaction pending)
                 (push (eth-rpc-subscription-notification-json
                        id
                        (if (eth-rpc-subscription-include-transactions-p
                             subscription)
                            ;; No block and no index: a pending transaction is
                            ;; in none, and the object renders those as null,
                            ;; which is what a client expects here.
                            (eth-rpc-transaction-object transaction nil nil)
                            (hash32-to-hex (transaction-hash transaction))))
                       messages)))))))))
    (nreverse messages))))
