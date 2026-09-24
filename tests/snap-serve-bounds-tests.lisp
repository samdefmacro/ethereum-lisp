(in-package #:ethereum-lisp.test)

;;;; The snap/1 server's work is bounded by the request, not by the state.
;;;;
;;;; Hoodi (b5161312, 2026-09-24): peer-session threads held the node's store
;;;; guard for 20-134 s from the moment the node had head state and advertised
;;;; snap/1, and from 01:50Z one hold never ended while the Lisp heap grew from
;;;; about 0.4 to 3.95 GB and the container was OOM-killed. The server answered
;;;; GetAccountRange and GetStorageRanges through MPT-ENTRY-RANGE, which
;;;; enumerates EVERY leaf of a lazily persisted trie (and sorts them) before
;;;; the origin, limit or byte budget is looked at, and it resolved those nodes
;;;; into the shared, retained node graph of the served state.
;;;;
;;;; These tests serve from a lazy direct state over a persisted account trie,
;;;; the shape the RocksDB provider serves, and count the trie nodes each
;;;; request reads.

(defun snap-serve-bounds-fixture (account-count slot-count)
  "Persist ACCOUNT-COUNT accounts, the last with SLOT-COUNT storage slots.

Returns (VALUES STATE DATABASE ROOT LOADS STORAGE-ACCOUNT-HASH STORAGE-ROOT):
STATE is a lazy direct-trie state over the persisted account trie, and LOADS a
cons whose CAR counts the account-trie nodes read through STATE's loader."
  (let ((memory (make-state-db))
        (database (make-memory-key-value-database))
        (storage-address nil))
    (dotimes (index account-count)
      (let ((address (snap-test-address-from-integer (1+ index))))
        (state-db-set-account memory address
                              (make-state-account :nonce 1
                                                  :balance (1+ index)))
        (setf storage-address address)))
    (dotimes (index slot-count)
      (state-db-set-storage memory storage-address
                            (make-hash32 (snap-test-index-hash (1+ index)))
                            (1+ index)))
    (let ((root (state-db-root memory))
          (storage-root (state-db-get-storage-root memory storage-address))
          (loads (list 0)))
      (dolist (trie (state-db-persistence-tries memory))
        (mpt-persist database trie))
      (let* ((trie (make-persisted-mpt
                    root
                    (lambda (hash)
                      (incf (car loads))
                      (trie-node-store-get database hash))))
             (state (make-lazy-state-db
                     (lambda (address)
                       (declare (ignore address))
                       (values nil nil nil))
                     nil nil
                     :trie trie :cached-root root :direct-trie-p t)))
        (values state database (hash32-bytes root) loads
                (keccak-256 (address-bytes storage-address))
                storage-root)))))

(defun snap-serve-bounds-account-request (root bytes)
  (ethereum-lisp.snap:make-snap-get-account-range
   41 root (make-byte-vector 32)
   (make-byte-vector 32 :initial-element #xff) bytes))

(defun snap-serve-bounds-verifies-p (root response)
  "True when an AccountRange RESPONSE proves its accounts from the zero origin."
  (and (mpt-verify-range-proof
        root
        (ethereum-lisp.snap-sync::snap-sync-account-entries response)
        (ethereum-lisp.snap:snap-account-range-proof response)
        :start (make-byte-vector 32))
       t))

(defun snap-serve-bounds-root-resolved-p (state)
  "True when serving left a resolved node in STATE's own account-trie graph.
Such a resolution is memoized for as long as the state (and every trie that
shares the node) lives."
  (let ((root (mpt-root-node (ethereum-lisp.state::state-db-trie state))))
    (and (ethereum-lisp.trie::hash-node-p root)
         (ethereum-lisp.trie::hash-node-resolved root)
         t)))

(defun snap-serve-bounds-call (backend message-id request)
  "Serve REQUEST, returning (VALUES RESPONSE MILLISECONDS)."
  (let ((started-at (get-internal-real-time)))
    (values (snap-test-call-backend backend message-id request)
            (round (* 1000 (- (get-internal-real-time) started-at))
                   internal-time-units-per-second))))

(defmacro with-snap-serve-seconds ((seconds) &body body)
  "Run BODY with the server's per-request time budget set to SECONDS. PROGV,
so the form reads and does nothing on a server that has no such budget."
  `(progv (list (intern "*SNAP-SYNC-SERVE-SECONDS*" '#:ethereum-lisp.snap-sync))
       (list ,seconds)
     ,@body))

(deftest snap-server-account-range-reads-only-the-nodes-it-returns
  (:layer :integration :module :p2p)
  ;; geth v1.17 ServiceGetAccountRangeQuery iterates its snapshot from Origin
  ;; and stops at the first key at or past Limit, or once the response passes
  ;; Bytes: the work is proportional to the response. A 600-byte request over
  ;; 1,024 accounts must read the proof paths and the few leaves it returns,
  ;; not the whole trie. RED at 886afd05: every node is read (1,000+).
  (multiple-value-bind (state database root loads)
      (snap-serve-bounds-fixture 1024 0)
    (let ((backend (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
                    database state)))
      (setf (car loads) 0)
      (let* ((response (snap-serve-bounds-call
                        backend
                        ethereum-lisp.snap:+snap-message-get-account-range+
                        (snap-serve-bounds-account-request root 600)))
             (accounts (length (ethereum-lisp.snap:snap-account-range-accounts
                                response)))
             (partial-loads (car loads)))
        (format t "~&# bounded account range: ~D accounts, ~D node reads~%"
                accounts partial-loads)
        (is (<= 1 accounts 16))
        (is (<= partial-loads 64))
        (is (snap-serve-bounds-verifies-p root response))
        ;; Served nodes are not memoized into the state's own graph: a peer
        ;; that walks the whole key space over many requests would otherwise
        ;; pin the whole decoded trie in the heap for as long as it lives.
        (is (not (snap-serve-bounds-root-resolved-p state))))
      ;; Positive control for the counter: a request that asks for everything
      ;; reads every leaf and returns every account.
      (setf (car loads) 0)
      (let* ((response (with-snap-serve-seconds (nil)
                         (snap-serve-bounds-call
                          backend
                          ethereum-lisp.snap:+snap-message-get-account-range+
                          (snap-serve-bounds-account-request
                           root (* 2 1024 1024)))))
             (accounts (length (ethereum-lisp.snap:snap-account-range-accounts
                                response))))
        (is (= 1024 accounts))
        (is (>= (car loads) 1024))
        (is (snap-serve-bounds-verifies-p root response))))))

(deftest snap-server-storage-range-reads-only-the-slots-it-returns
  (:layer :integration :module :p2p)
  ;; geth v1.17 ServiceGetStorageRangesQuery iterates one account's storage
  ;; snapshot from Origin and stops at the byte budget, proving the cut. A
  ;; 600-byte request against 1,024 slots must not read the whole storage
  ;; trie. RED at 886afd05: every storage node is read.
  (multiple-value-bind (state database root loads account-hash storage-root)
      (snap-serve-bounds-fixture 4 1024)
    (declare (ignore loads))
    (let ((backend (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
                    database state))
          (reads 0))
      (sb-int:encapsulate 'ethereum-lisp.trie:trie-node-store-get
                          'snap-serve-bounds
                          (lambda (function &rest arguments)
                            (incf reads)
                            (apply function arguments)))
      (unwind-protect
           (let* ((response
                    (snap-serve-bounds-call
                     backend
                     ethereum-lisp.snap:+snap-message-get-storage-ranges+
                     (ethereum-lisp.snap:make-snap-get-storage-ranges
                      42 root (list account-hash)
                      (make-byte-vector 0) (make-byte-vector 0) 600)))
                  (groups (ethereum-lisp.snap:snap-storage-ranges-slots
                           response))
                  (slots (first groups)))
             (format t "~&# bounded storage range: ~D slots, ~D node reads~%"
                     (length slots) reads)
             (is (= 1 (length groups)))
             (is (<= 1 (length slots) 32))
             (is (<= reads 96))
             ;; A cut range carries its proof and verifies as a partial range.
             (is (ethereum-lisp.snap:snap-storage-ranges-proof response))
             (is (mpt-verify-range-proof
                  storage-root
                  (ethereum-lisp.snap-sync::snap-sync-storage-entries slots)
                  (ethereum-lisp.snap:snap-storage-ranges-proof response)
                  :start (make-byte-vector 32))))
        (sb-int:unencapsulate 'ethereum-lisp.trie:trie-node-store-get
                              'snap-serve-bounds)))))

(deftest snap-server-stops-at-its-time-budget-and-proves-the-partial-range
  (:layer :integration :module :p2p)
  ;; One request is one store-guard hold, and every Engine request waits
  ;; behind it. With slow reads (the Hoodi host had 190 MB of page cache left)
  ;; a full-size request must still end within the server's time budget and
  ;; answer the accounts it has, proved: snap/1 allows any prefix of the range
  ;; as long as its proof holds, and the requester continues from the last
  ;; key. geth bounds only TrieNodes by time (maxTrieNodeTimeSpent, 5 s); its
  ;; range handlers read a flat snapshot and cannot run long. RED at 886afd05:
  ;; the request reads all 512 accounts' nodes, about 2.5 s here.
  (multiple-value-bind (state database root)
      (snap-serve-bounds-fixture 512 0)
    (let ((backend (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
                    database state)))
      (sb-int:encapsulate 'ethereum-lisp.trie:trie-node-store-get
                          'snap-serve-bounds
                          (lambda (function &rest arguments)
                            (sleep 0.004)
                            (apply function arguments)))
      (unwind-protect
           (multiple-value-bind (response ms)
               (with-snap-serve-seconds (0.3)
                 (snap-serve-bounds-call
                  backend ethereum-lisp.snap:+snap-message-get-account-range+
                  (snap-serve-bounds-account-request root (* 2 1024 1024))))
             (let ((accounts (length (ethereum-lisp.snap:snap-account-range-accounts
                                      response))))
               (format t "~&# time-bounded account range: ~D accounts in ~D ms~%"
                       accounts ms)
               (is (< ms 1200))
               (is (<= 1 accounts 511))
               (is (snap-serve-bounds-verifies-p root response))))
        (sb-int:unencapsulate 'ethereum-lisp.trie:trie-node-store-get
                              'snap-serve-bounds)))))

(deftest snap-server-bytecodes-stop-at-the-geth-lookup-cap
  (:layer :integration :module :p2p)
  ;; geth v1.17 ServiceGetByteCodesQuery serves at most maxCodeLookups (1024)
  ;; hashes and caps Bytes at softResponseLimit (2 MiB). RED at 886afd05: all
  ;; 1,100 are served.
  (let* ((state (make-state-db))
         (database (make-memory-key-value-database))
         (backend (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
                   database state))
         (code #(1 2 3 4))
         (code-hash (keccak-256 code)))
    (kv-put-chain-record database :code code-hash code)
    (let ((response (snap-test-call-backend
                     backend ethereum-lisp.snap:+snap-message-get-bytecodes+
                     (ethereum-lisp.snap:make-snap-get-bytecodes
                      43 (loop repeat 1100 collect code-hash)
                      (* 64 1024 1024)))))
      (is (= 1024 (length (ethereum-lisp.snap:snap-bytecodes-codes
                           response)))))))

(deftest snap-server-answers-a-proved-prefix-when-asked-to-yield
  (:layer :integration :module :p2p)
  ;; A node serves under its store guard and passes a yield predicate that is
  ;; true while an Engine request waits. The server then stops between items
  ;; and answers what it has: account and storage ranges with the proof of a
  ;; partial range. Controls: a predicate that never fires serves the whole
  ;; range.
  (multiple-value-bind (state database root loads account-hash storage-root)
      (snap-serve-bounds-fixture 64 64)
    (declare (ignore loads))
    (flet ((backend-yielding-after (count)
             (let ((asked 0))
               (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
                database state
                :yield-predicate (lambda () (>= (incf asked) count)))))
           (accounts (response)
             (length (ethereum-lisp.snap:snap-account-range-accounts response)))
           (storage-request ()
             (ethereum-lisp.snap:make-snap-get-storage-ranges
              44 root (list account-hash)
              (make-byte-vector 0) (make-byte-vector 0) (* 2 1024 1024))))
      (let ((response (snap-test-call-backend
                       (backend-yielding-after 3)
                       ethereum-lisp.snap:+snap-message-get-account-range+
                       (snap-serve-bounds-account-request root (* 2 1024 1024)))))
        (is (= 3 (accounts response)))
        (is (snap-serve-bounds-verifies-p root response)))
      (let ((response (snap-test-call-backend
                       (backend-yielding-after most-positive-fixnum)
                       ethereum-lisp.snap:+snap-message-get-account-range+
                       (snap-serve-bounds-account-request root (* 2 1024 1024)))))
        (is (= 64 (accounts response)))
        (is (snap-serve-bounds-verifies-p root response)))
      (let* ((response (snap-test-call-backend
                        (backend-yielding-after 5)
                        ethereum-lisp.snap:+snap-message-get-storage-ranges+
                        (storage-request)))
             (slots (first (ethereum-lisp.snap:snap-storage-ranges-slots
                            response))))
        (is (= 5 (length slots)))
        (is (ethereum-lisp.snap:snap-storage-ranges-proof response))
        (is (mpt-verify-range-proof
             storage-root
             (ethereum-lisp.snap-sync::snap-sync-storage-entries slots)
             (ethereum-lisp.snap:snap-storage-ranges-proof response)
             :start (make-byte-vector 32))))
      (let* ((response (snap-test-call-backend
                        (backend-yielding-after most-positive-fixnum)
                        ethereum-lisp.snap:+snap-message-get-storage-ranges+
                        (storage-request)))
             (slots (first (ethereum-lisp.snap:snap-storage-ranges-slots
                            response))))
        (is (= 64 (length slots)))
        ;; The whole trie, so no proof, as geth answers it.
        (is (null (ethereum-lisp.snap:snap-storage-ranges-proof response)))))))

(defun snap-serve-walk-keys (trie start &optional (limit most-positive-fixnum))
  "The (KEY . VALUE) pairs MPT-MAP-ENTRIES-FROM visits from START, at most
LIMIT, and whether the function ended the walk."
  (let ((pairs '()))
    (let ((stopped
            (mpt-map-entries-from
             trie start
             (lambda (key value)
               (push (cons key value) pairs)
               (>= (length pairs) limit)))))
      (values (nreverse pairs) stopped))))

(deftest snap-serve-trie-walk-matches-the-full-enumeration
  (:layer :unit :module :p2p)
  ;; MPT-MAP-ENTRIES-FROM, which the server walks instead of MPT-ENTRY-RANGE,
  ;; must visit exactly MPT-ENTRY-RANGE's entries in the same order from any
  ;; start: before, at, between and after keys, and shorter than a key; over
  ;; an in-memory trie and the same trie read lazily from a database; and over
  ;; keys of mixed length, where a branch carries a value.
  (let ((trie (make-mpt))
        (database (make-memory-key-value-database))
        (keys '()))
    (dotimes (index 300)
      (let ((key (keccak-256 (snap-test-index-hash index))))
        (push key keys)
        (mpt-put trie key (rlp-encode (1+ index)))))
    (mpt-persist database trie)
    (let* ((lazy (make-persisted-mpt
                  (mpt-root-hash trie)
                  (lambda (hash) (trie-node-store-get database hash))))
           (starts
             (append
              (list nil (make-byte-vector 32)
                    (make-byte-vector 32 :initial-element #xff)
                    (make-byte-vector 1 :initial-element #x80))
              (loop for key in keys
                    repeat 25
                    collect key
                    collect (let ((next (copy-seq key)))
                              (setf (aref next 31)
                                    (min 255 (1+ (aref next 31))))
                              next)
                    collect (subseq key 0 1)
                    collect (subseq key 0 2)))))
      (dolist (start starts)
        (let ((expected (mpt-entry-range trie :start start)))
          (is (equalp expected (snap-serve-walk-keys trie start)))
          (is (equalp expected (snap-serve-walk-keys lazy start)))))
      ;; The function ends the walk, and the walk says so.
      (multiple-value-bind (pairs stopped) (snap-serve-walk-keys lazy nil 5)
        (is (= 5 (length pairs)))
        (is (eq t stopped))
        (is (equalp (subseq (mpt-entry-range trie) 0 5) pairs)))
      (is (null (nth-value 1 (snap-serve-walk-keys lazy nil)))))
    ;; Mixed-length keys: a key that is a prefix of another is a branch value.
    (let ((mixed (make-mpt)))
      (dolist (key '(#(1) #(1 2) #(1 2 3) #(1 3) #(2) #(2 0 0) #(16) #(17 1)))
        (mpt-put mixed (ensure-byte-vector key) (rlp-encode (length key))))
      (dolist (start (list nil #(0) #(1) #(1 1) #(1 2) #(1 2 4) #(1 4)
                           #(2 0) #(3) #(16 0) #(255)))
        (let ((start (and start (ensure-byte-vector start))))
          (is (equalp (mpt-entry-range mixed :start start)
                      (snap-serve-walk-keys mixed start))))))))
