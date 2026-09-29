(in-package #:ethereum-lisp.test)

;;;; Silent waits and walks of the SNAP range phase
;;;; (docs/evidence/sec5-snap-range-silence.txt).
;;;;
;;;; At a18b84e2 the range coordinator unwound a stale-pivot yield and joined
;;;; its lanes with no bound and no log line; one lane never returned and the
;;;; node was silent for hours.  A stopping generation now reports while it
;;;; waits, a long storage-root closure walk reports while it reads, and a
;;;; closure that finished before a pivot rebase is not paid for again.

#+sbcl
(deftest snap-generation-join-reports-a-lane-that-has-not-returned
  (:layer :unit :module :p2p)
  (let ((release (sb-thread:make-semaphore :count 0))
        (reports '()))
    (let* ((fast (sb-thread:make-thread (lambda () :fast)
                                        :name "snap-test-fast-lane"))
           (slow (sb-thread:make-thread
                  (lambda ()
                    (sb-thread:wait-on-semaphore release :timeout 20)
                    :slow)
                  :name "snap-test-slow-lane"))
           (ethereum-lisp.snap-sync::*snap-sync-generation-stop-report-seconds*
             0.1))
      (unwind-protect
           (ethereum-lisp.snap-sync::snap-sync-join-generation-threads
            (list fast slow)
            (lambda (profile)
              (push profile reports)
              ;; The report is what an operator would read; after it, let the
              ;; lane finish.
              (unless (ethereum-lisp.snap-sync:snap-sync-generation-stop-profile-joined-p
                       profile)
                (sb-thread:signal-semaphore release))))
        (sb-thread:signal-semaphore release 4)
        (ignore-errors (sb-thread:join-thread slow :timeout 20))))
    (setf reports (nreverse reports))
    (is (>= (length reports) 2))
    (let ((first (first reports))
          (last (car (last reports))))
      (is (not (ethereum-lisp.snap-sync:snap-sync-generation-stop-profile-joined-p
                first)))
      (is (= 1 (ethereum-lisp.snap-sync:snap-sync-generation-stop-profile-live-threads
                first)))
      (is (ethereum-lisp.snap-sync:snap-sync-generation-stop-profile-joined-p last))
      (is (zerop (ethereum-lisp.snap-sync:snap-sync-generation-stop-profile-live-threads
                  last)))
      (is (<= (ethereum-lisp.snap-sync:snap-sync-generation-stop-profile-elapsed-ms
               first)
              (ethereum-lisp.snap-sync:snap-sync-generation-stop-profile-elapsed-ms
               last)))))
  ;; Control: a generation whose lanes all return promptly reports nothing.
  (let ((reports 0))
    (ethereum-lisp.snap-sync::snap-sync-join-generation-threads
     (list (sb-thread:make-thread (lambda () 1) :name "snap-test-lane-a")
           (sb-thread:make-thread (lambda () 2) :name "snap-test-lane-b"))
     (lambda (profile) (declare (ignore profile)) (incf reports)))
    (is (zerop reports)))
  ;; A lane that died on an unhandled condition still surfaces at the join.
  (let ((dead (sb-thread:make-thread
               (lambda ()
                 (sb-thread:abort-thread))
               :name "snap-test-aborted-lane")))
    (signals error
      (ethereum-lisp.snap-sync::snap-sync-join-generation-threads
       (list dead) nil))))

#+sbcl
(deftest snap-state-import-multi-reports-a-stopping-generation-that-waits-for-a-lane
  (:layer :integration :module :p2p)
  ;; The shipped import: one StorageRanges lane proves the pivot stale while
  ;; another lane is still inside its request.  The coordinator must say it is
  ;; waiting, through ON-GENERATION-STOP, and say again when the join ends.
  ;; At 7cef5a67 there was no such report: the join was the silent hours on
  ;; Hoodi.
  (let* ((source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-memory-key-value-database))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000063"))
         (lock (sb-thread:make-mutex :name "snap-test-silence"))
         (storage-calls 0)
         (blocker-p nil)
         (entered (sb-thread:make-semaphore :count 0))
         (release (sb-thread:make-semaphore :count 0))
         (reports '()))
    ;; Two byte-capped contracts, so two global StorageRanges jobs and two
    ;; lanes can be open at once.
    (dolist (contract
             (list address
                   (address-from-hex
                    "0x0000000000000000000000000000000000000064")))
      (loop for byte from 1 to 64
            do (state-db-set-storage
                source-state contract
                (make-hash32 (make-byte-vector 32 :initial-element byte))
                (+ 6300 byte))))
    (let* ((root (state-db-root source-state))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (base-source (snap-test-source backend))
           (real-storage
             (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
              base-source)))
      (flet ((storage (request)
               (let ((role
                       (sb-thread:with-mutex (lock)
                         (incf storage-calls)
                         (cond
                           ((= 1 storage-calls) :serve)
                           ((not blocker-p) (setf blocker-p t) :block)
                           (t :yield)))))
                 (ecase role
                   (:serve (funcall real-storage request))
                   (:block
                    ;; The lane still inside its request when the pivot turns
                    ;; stale; only the stop report lets it go.
                    (sb-thread:signal-semaphore entered)
                    (sb-thread:wait-on-semaphore release :timeout 20)
                    (error 'ethereum-lisp.snap-sync:snap-sync-heal-yielded))
                   (:yield
                    (sb-thread:wait-on-semaphore entered :timeout 5)
                    (error 'ethereum-lisp.snap-sync:snap-sync-heal-yielded))))))
        (let ((sources
                (loop repeat 2
                      collect
                      (ethereum-lisp.snap-sync:make-snap-sync-source
                       :account-range
                       (ethereum-lisp.snap-sync:snap-sync-source-account-range
                        base-source)
                       :storage-ranges #'storage
                       :bytecodes
                       (ethereum-lisp.snap-sync:snap-sync-source-bytecodes
                        base-source)
                       :trie-nodes
                       (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
                        base-source))))
              (ethereum-lisp.snap-sync::*snap-sync-generation-stop-report-seconds*
                0.2))
          (unwind-protect
               (signals ethereum-lisp.snap-sync:snap-sync-heal-yielded
                 (ethereum-lisp.snap-sync:snap-sync-import-state-multi
                  target-database sources
                  :pivot-hash (make-hash32 (snap-test-index-hash 1430))
                  :pivot-number 910 :state-root root
                  :target-hash (make-hash32 (snap-test-index-hash 1431))
                  :chain-id 560048
                  :genesis-hash (make-hash32 (snap-test-index-hash 1432))
                  :authority-id (make-hash32 (snap-test-index-hash 1433))
                  :byte-limit 350
                  :on-generation-stop
                  (lambda (profile)
                    (push profile reports)
                    (sb-thread:signal-semaphore release))))
            (sb-thread:signal-semaphore release 8)))))
    (setf reports (nreverse reports))
    (is blocker-p)
    (is (>= (length reports) 2))
    (when reports
      (is (not (ethereum-lisp.snap-sync:snap-sync-generation-stop-profile-joined-p
                (first reports))))
      (is (plusp (ethereum-lisp.snap-sync:snap-sync-generation-stop-profile-live-threads
                  (first reports))))
      (is (ethereum-lisp.snap-sync:snap-sync-generation-stop-profile-joined-p
           (car (last reports)))))))

(deftest snap-storage-root-closure-walk-reports-progress-while-it-reads
  (:layer :unit :module :p2p)
  ;; A closure walk is bounded, but on a compacting store it read for 43 s on
  ;; Hoodi with nothing logged.  With the interval at zero every multi-get
  ;; reports; at the default a fast walk reports nothing.
  (multiple-value-bind (target storage-root)
      (snap-closure-read-wide-store 5000)
    (let ((reports '()))
      (multiple-value-bind (visited reason calls levels nodes)
          (let ((ethereum-lisp.snap-sync::*snap-sync-storage-closure-progress-seconds*
                  0))
            (ethereum-lisp.snap-sync::snap-sync-storage-root-closure-walk
             target storage-root
             :progress (lambda (progress) (push progress reports))))
        (declare (ignore visited))
        (setf reports (nreverse reports))
        (is (eq :closed reason))
        (is (= calls (length reports)))
        (is (loop for (a b) on reports
                  while b
                  always (<= (ethereum-lisp.snap-sync:snap-sync-storage-closure-progress-nodes-visited
                              a)
                             (ethereum-lisp.snap-sync:snap-sync-storage-closure-progress-nodes-visited
                              b))))
        (let ((last (car (last reports))))
          (is (= calls
                 (ethereum-lisp.snap-sync:snap-sync-storage-closure-progress-multi-gets
                  last)))
          (is (= levels
                 (ethereum-lisp.snap-sync:snap-sync-storage-closure-progress-levels
                  last)))
          (is (<= (ethereum-lisp.snap-sync:snap-sync-storage-closure-progress-nodes-visited
                   last)
                  nodes)))))
    (let ((reports 0))
      (ethereum-lisp.snap-sync::snap-sync-storage-root-closure-walk
       target storage-root
       :progress (lambda (progress) (declare (ignore progress)) (incf reports)))
      (is (zerop reports)))))

(deftest snap-storage-root-closure-survives-a-pivot-rebase
  (:layer :integration :module :p2p)
  ;; Brief (3): a closure that finished while the pivot went stale must not
  ;; be paid for again.  Generation one fills and closes a partitioned root
  ;; under state root R1.  Generation two, rebased to R2, meets the same
  ;; content-addressed root: its cursor set is keyed without the state root,
  ;; so it is complete, and the closure answers :ALREADY-CLOSED without a
  ;; walk, a request, or a marker.
  (let* ((state (make-state-db))
         (address (snap-density-address 3)))
    (state-db-set-account state address (make-state-account :nonce 1 :balance 1))
    (loop for slot from 1 to 600
          do (state-db-set-storage state address (snap-density-slot 3 slot)
                                   (+ 71000 slot)))
    (multiple-value-bind (target account-hash storage-root state-root)
        (snap-marker-partitioned-store state address 4000)
      (flet ((generation (root)
               (let ((runtime
                       (ethereum-lisp.snap-sync::make-snap-sync-multi-runtime
                        nil 0 nil))
                     (profiles '()))
                 (setf (ethereum-lisp.snap-sync::snap-sync-multi-runtime-storage-profile-callback
                        runtime)
                       (lambda (profile) (push profile profiles)))
                 ;; No storage lane is started: a request would find none.
                 (values
                  (ethereum-lisp.snap-sync::snap-sync-multi-fill-storage-root
                   runtime target root account-hash storage-root)
                  (remove-if-not
                   (lambda (profile)
                     (typep profile
                            'ethereum-lisp.snap-sync:snap-sync-storage-closure-profile))
                   profiles)))))
        (is (plusp (hash-table-count (snap-marker-markers target))))
        (multiple-value-bind (completed-p profiles) (generation state-root)
          (is completed-p)
          (is (= 1 (length profiles)))
          (is (eq :closed
                  (ethereum-lisp.snap-sync:snap-sync-storage-closure-profile-outcome
                   (first profiles))))
          (is (plusp
               (ethereum-lisp.snap-sync:snap-sync-storage-closure-profile-nodes-visited
                (first profiles)))))
        (is (zerop (hash-table-count (snap-marker-markers target))))
        (let ((rebased (make-hash32 (keccak-256 (rlp-encode "rebased root")))))
          (is (not (hash32= rebased state-root)))
          (multiple-value-bind (completed-p profiles) (generation rebased)
            (is completed-p)
            (is (= 1 (length profiles)))
            (is (eq :already-closed
                    (ethereum-lisp.snap-sync:snap-sync-storage-closure-profile-outcome
                     (first profiles))))
            (is (zerop
                 (ethereum-lisp.snap-sync:snap-sync-storage-closure-profile-nodes-visited
                  (first profiles))))))
        (is (zerop (hash-table-count (snap-marker-markers target))))))))

(deftest snap-storage-root-closure-of-a-paged-import-walks-only-its-unproved-top
  (:layer :integration :module :p2p)
  ;; The brief's hypothesis for the a18b84e2 silence was an O(trie) closure
  ;; walk at completion.  Measured control: a 20,000-slot contract imported
  ;; in byte-capped StorageRanges pages publishes range-derived :STORAGE
  ;; proofs as it goes, so the closure walks only the nodes above them and
  ;; the page seams, a small fraction of the trie.  The walk's hard bound is
  ;; *SNAP-SYNC-STORAGE-ROOT-CLOSURE-MAX-NODES*.
  (let* ((state (make-state-db))
         (address (snap-density-address 4)))
    (state-db-set-account state address (make-state-account :nonce 1 :balance 1))
    (loop for slot from 1 to 20000
          do (state-db-set-storage state address (snap-density-slot 4 slot)
                                   (+ 72000 slot)))
    (multiple-value-bind (target account-hash storage-root state-root)
        (snap-marker-partitioned-store state address 64000)
      (let ((reachable
              (hash-table-count
               (snap-marker-reachable target (hash32-bytes storage-root)))))
        (multiple-value-bind (outcome profile)
            (ethereum-lisp.snap-sync::snap-sync-publish-storage-root-closure
             target state-root account-hash storage-root)
          (let ((visited
                  (ethereum-lisp.snap-sync:snap-sync-storage-closure-profile-nodes-visited
                   profile)))
            (format *standard-output*
                    "~&; paged closure: trie nodes=~D visited=~D multi-gets=~D levels=~D ~
elapsed-ms=~D~%"
                    reachable visited
                    (ethereum-lisp.snap-sync:snap-sync-storage-closure-profile-multi-gets
                     profile)
                    (ethereum-lisp.snap-sync:snap-sync-storage-closure-profile-levels
                     profile)
                    (ethereum-lisp.snap-sync:snap-sync-storage-closure-profile-elapsed-ms
                     profile))
            (is (eq :closed outcome))
            (is (> reachable 20000))
            (is (plusp visited))
            (is (< (* 4 visited) reachable))))))))
