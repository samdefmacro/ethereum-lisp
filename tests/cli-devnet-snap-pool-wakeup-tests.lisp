(in-package #:ethereum-lisp.test)

;;;; The SNAP dependency pool's waiters, and the range generation's stop.
;;;;
;;;; docs/evidence/sec5-snap-range-silence.txt: the fresh-datadir Hoodi run at
;;;; a18b84e2 went silent for hours after three storage peers refused the aged
;;;; pivot in one second.  Each refusal woke ONE pool waiter (condition-notify)
;;;; while it made its peer ineligible for every waiter; the woken waiters
;;;; found the last busy peers and slept again, the last refusal left no
;;;; eligible peer and no request in flight, and the remaining StorageRanges
;;;; lanes slept forever.  The range coordinator, unwinding the stale-pivot
;;;; yield, joined those lanes without a bound and without a log line, so the
;;;; node neither rebased nor refreshed its sources while new peers connected.

(defun snap-pool-wakeup-node ()
  (ethereum-lisp.cli:make-devnet-node
   :genesis-json *eth-sync-paris-genesis-json*
   :port 0 :public-port 0))

(defun snap-pool-wakeup-entry (name)
  (ethereum-lisp.cli::make-devnet-peer-entry
   :id-hex name
   :request-queue (ethereum-lisp.cli::make-devnet-peer-request-queue)))

(defun snap-pool-wakeup-waiter (pool response-id started)
  "Start one thread that waits in POOL's acquire for RESPONSE-ID.

It signals STARTED just before it asks, and returns the acquire's values as a
list, or (:CONDITION condition) when the acquire signalled."
  (sb-thread:make-thread
   (lambda ()
     (handler-case
         (progn
           (sb-thread:signal-semaphore started)
           (multiple-value-list
            (ethereum-lisp.cli::devnet-snap-source-pool-acquire
             pool response-id)))
       (serious-condition (condition)
         (list :condition condition))))
   :name "snap-pool-wakeup-waiter"))

(defun snap-pool-wakeup-caller (pool response-id started)
  "Start one thread that runs a pooled StorageRanges call through POOL."
  (sb-thread:make-thread
   (lambda ()
     (handler-case
         (progn
           (sb-thread:signal-semaphore started)
           (list :value
                 (ethereum-lisp.cli::devnet-snap-source-pool-call
                  pool response-id
                  #'ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
                  :request "storage ranges")))
       (serious-condition (condition)
         (list :condition condition))))
   :name "snap-pool-wakeup-caller"))

(defun snap-pool-wakeup-wait-started (started count)
  "Wait for COUNT threads to reach their acquire, then let them block there."
  (loop repeat count
        do (sb-thread:wait-on-semaphore started :timeout 5))
  (sleep 0.2))

(defun snap-pool-wakeup-join (thread seconds)
  (sb-thread:join-thread thread :timeout seconds :default :blocked))

(defun snap-pool-wakeup-unstick (pool live-cell threads)
  "Hand every still-blocked thread a fresh idle peer and join it.

Cleanup only: on the pre-fix pool a stranded waiter would otherwise outlive
the test.  Registering a source broadcasts to every waiter."
  (dolist (thread threads)
    (when (sb-thread:thread-alive-p thread)
      (let ((rescue (snap-pool-wakeup-entry "rescue-peer")))
        (setf (car live-cell) (append (car live-cell) (list rescue)))
        (ethereum-lisp.cli::devnet-snap-source-pool-register
         pool rescue (devnet-snap-test-source)))
      (ignore-errors (sb-thread:join-thread thread :timeout 10)))))

(deftest devnet-snap-source-pool-wakes-every-waiter-when-its-last-peer-is-retired
  (:layer :unit :module :p2p)
  ;; Three dependency lanes wait for the one eligible peer, which is busy.
  ;; Its request then fails with state unavailable: the pool retires the peer
  ;; for this pivot, and no eligible peer is left.  Every waiter must learn
  ;; that at once and return (NIL NIL), the pool's no-candidate answer.  RED
  ;; at 7cef5a67: the retirement woke one waiter (condition-notify); the
  ;; other two slept until something else touched the pool, which on Hoodi
  ;; was never.
  #+sbcl
  (let* ((node (snap-pool-wakeup-node))
         (entry (snap-pool-wakeup-entry "last-eligible-peer"))
         (pivot (make-hash32 (make-byte-vector 32 :initial-element 91)))
         (pool (ethereum-lisp.cli::make-devnet-snap-source-pool node pivot))
         (storage-id ethereum-lisp.snap:+snap-message-storage-ranges+)
         (live (list (list entry)))
         (started (sb-thread:make-semaphore :count 0))
         (waiters '()))
    (ethereum-lisp.cli::devnet-snap-source-pool-register
     pool entry (devnet-snap-test-source))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (seen-node &key snap-only-p)
              (declare (ignore seen-node snap-only-p))
              (car live))))
     (lambda ()
       (unwind-protect
            (progn
              ;; The busy slot: this thread's own reservation.
              (is (eq entry
                      (ethereum-lisp.cli::devnet-snap-source-pool-acquire
                       pool storage-id)))
              (setf waiters
                    (loop repeat 3
                          collect (snap-pool-wakeup-waiter
                                   pool storage-id started)))
              (snap-pool-wakeup-wait-started started 3)
              ;; Positive control: they really wait for the busy peer.
              (is (every (lambda (waiter)
                           (eq :blocked (snap-pool-wakeup-join waiter 0.1)))
                         waiters))
              (ethereum-lisp.cli::devnet-snap-source-pool-fail-and-release
               pool entry storage-id :state-unavailable-p t)
              (let ((outcomes
                      (mapcar (lambda (waiter)
                                (snap-pool-wakeup-join waiter 5))
                              waiters)))
                (is (= 3 (count '(nil nil) outcomes :test #'equal)))
                (is (zerop (count :blocked outcomes)))))
         (snap-pool-wakeup-unstick pool live waiters)))))
  #-sbcl
  (is t))

(deftest devnet-snap-source-pool-waiter-admits-a-peer-that-connects-while-it-waits
  (:layer :unit :module :p2p)
  ;; A lane waits because every eligible peer is busy.  A new SNAP peer then
  ;; connects.  The dialer's range coordinator would register it on its next
  ;; refresh, but that coordinator may itself be waiting for this lane, so
  ;; the waiter must re-read the live set within a bounded interval.  RED at
  ;; 7cef5a67: the waiter slept until a release on the busy peer (on Hoodi,
  ;; 26 peers connected after the stall and none was used).
  #+sbcl
  (let* ((node (snap-pool-wakeup-node))
         (busy (snap-pool-wakeup-entry "busy-peer"))
         (newcomer (snap-pool-wakeup-entry "newly-connected-peer"))
         (pool (ethereum-lisp.cli::make-devnet-snap-source-pool node))
         (storage-id ethereum-lisp.snap:+snap-message-storage-ranges+)
         (live (list (list busy)))
         (started (sb-thread:make-semaphore :count 0))
         (waiter nil))
    (ethereum-lisp.cli::devnet-snap-source-pool-register
     pool busy (devnet-snap-test-source))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (seen-node &key snap-only-p)
              (declare (ignore seen-node snap-only-p))
              (car live))))
     (lambda ()
       (unwind-protect
            (progn
              (is (eq busy
                      (ethereum-lisp.cli::devnet-snap-source-pool-acquire
                       pool storage-id)))
              (setf waiter (snap-pool-wakeup-waiter pool storage-id started))
              (snap-pool-wakeup-wait-started started 1)
              (is (eq :blocked (snap-pool-wakeup-join waiter 0.1)))
              ;; The peer table changes; nobody registers or releases.
              (setf (car live) (list busy newcomer))
              (let ((outcome (snap-pool-wakeup-join waiter 5)))
                (is (not (eq :blocked outcome)))
                (when (consp outcome)
                  (is (eq newcomer (first outcome)))
                  (is (second outcome))
                  (ethereum-lisp.cli::devnet-snap-source-pool-release
                   pool newcomer storage-id))))
         (when (and waiter (sb-thread:thread-alive-p waiter))
           (ethereum-lisp.cli::devnet-snap-source-pool-release
            pool busy storage-id)
           (ignore-errors (sb-thread:join-thread waiter :timeout 10)))))))
  #-sbcl
  (is t))

(deftest devnet-snap-source-pool-stale-pivot-releases-every-waiter
  (:layer :unit :module :p2p)
  ;; Once one pooled request proves the CL-authorized target has moved past
  ;; this pivot, every lane of the generation is futile: each must get the
  ;; same scheduling result (SNAP-SYNC-HEAL-YIELDED) at once, without another
  ;; request, instead of waiting for a peer that serves a pruned root.  RED at
  ;; 7cef5a67: the lane waiting for the busy peer stayed asleep.
  #+sbcl
  (let* ((node (snap-pool-wakeup-node))
         (busy (snap-pool-wakeup-entry "busy-peer"))
         (pruned (snap-pool-wakeup-entry "pruned-peer"))
         (pivot (make-hash32 (make-byte-vector 32 :initial-element 92)))
         (pool (ethereum-lisp.cli::make-devnet-snap-source-pool node pivot))
         (storage-id ethereum-lisp.snap:+snap-message-storage-ranges+)
         (live (list (list busy pruned)))
         (gate (sb-thread:make-semaphore :count 0))
         (started (sb-thread:make-semaphore :count 0))
         (pruned-requests 0)
         (busy-requests 0)
         (stale-checks 0)
         (caller nil)
         (late-caller nil)
         (waiter nil))
    (ethereum-lisp.cli::devnet-snap-source-pool-register
     pool busy
     (devnet-snap-test-source
      :storage-ranges (lambda (request)
                        (incf busy-requests)
                        request)))
    (ethereum-lisp.cli::devnet-snap-source-pool-register
     pool pruned
     (devnet-snap-test-source
      :storage-ranges
      (lambda (request)
        (declare (ignore request))
        (incf pruned-requests)
        (sb-thread:wait-on-semaphore gate :timeout 10)
        (ethereum-lisp.snap-sync:snap-sync-state-unavailable
         "storage-range"))))
    (setf (ethereum-lisp.cli::devnet-snap-source-pool-stale-function pool)
          (lambda () (incf stale-checks) t))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (seen-node &key snap-only-p)
              (declare (ignore seen-node snap-only-p))
              (car live))))
     (lambda ()
       (unwind-protect
            (progn
              (is (eq busy
                      (ethereum-lisp.cli::devnet-snap-source-pool-acquire
                       pool storage-id)))
              ;; The caller takes the only idle peer and blocks in its request.
              (setf caller (snap-pool-wakeup-caller pool storage-id started))
              (snap-pool-wakeup-wait-started started 1)
              (setf waiter (snap-pool-wakeup-waiter pool storage-id started))
              (snap-pool-wakeup-wait-started started 1)
              (is (eq :blocked (snap-pool-wakeup-join waiter 0.1)))
              (sb-thread:signal-semaphore gate)
              (let ((called (snap-pool-wakeup-join caller 5))
                    (waited (snap-pool-wakeup-join waiter 5)))
                (is (consp called))
                (when (consp called)
                  (is (eq :condition (first called)))
                  (is (typep (second called)
                             'ethereum-lisp.snap-sync:snap-sync-heal-yielded)))
                (is (not (eq :blocked waited)))
                ;; The acquire itself answers "no candidate"; the pooled call
                ;; turns that into the latched scheduling result.
                (is (equal '(nil nil) waited)))
              ;; Any later lane gets the result without a request.
              (setf late-caller
                    (snap-pool-wakeup-caller pool storage-id started))
              (let ((late (snap-pool-wakeup-join late-caller 5)))
                (is (consp late))
                (when (consp late)
                  (is (typep (second late)
                             'ethereum-lisp.snap-sync:snap-sync-heal-yielded))))
              (is (= 1 pruned-requests))
              (is (zerop busy-requests))
              (is (= 1 stale-checks)))
         (sb-thread:signal-semaphore gate 4)
         (when caller
           (snap-pool-wakeup-unstick pool live (list caller)))
         (when waiter
           (snap-pool-wakeup-unstick pool live (list waiter)))
         (when late-caller
           (snap-pool-wakeup-unstick pool live (list late-caller)))))))
  #-sbcl
  (is t))
