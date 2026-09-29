(in-package #:ethereum-lisp.test)

;;;; A block whose execution failed internally: how often it is tried again,
;;;; and where the failure is logged.
;;;;
;;;; A BLOCK-EXECUTION-INTERNAL-ERROR is a defect in this node, not a verdict
;;;; (docs/evidence/sec5-evm-edge-audit.txt). The sync coordinator contains it
;;;; and executes the block again later; these tests pin how much later, and
;;;; that every ingress that executes a block logs the failure. The record is
;;;; docs/evidence/sec5-robustness-followups.txt.

(deftest devnet-execution-retry-wait-doubles-to-its-cap-and-ends-for-a-new-target
  (:layer :unit :module :p2p)
  (is (equal '(2 4 8 16 32 64 128 256 300 300)
             (loop for failures from 1 to 10
                   collect (ethereum-lisp.cli::devnet-execution-retry-delay-seconds
                            failures))))
  (let* ((table (make-hash-table :test #'equal))
         (hash (make-hash32 (make-byte-vector 32 :initial-element 7)))
         (target (make-hash32 (make-byte-vector 32 :initial-element 8)))
         (other-target (make-hash32 (make-byte-vector 32 :initial-element 9)))
         (entry (ethereum-lisp.cli::devnet-execution-retry-note-failure
                 table hash 12 target 100)))
    (is (= 1 (ethereum-lisp.cli::devnet-execution-retry-failures entry)))
    (is (= 102 (ethereum-lisp.cli::devnet-execution-retry-next-at entry)))
    ;; The wait holds for the target it was seen under, until it ends.
    (is (eq entry (ethereum-lisp.cli::devnet-execution-retry-waiting
                   table target 101)))
    (is (null (ethereum-lisp.cli::devnet-execution-retry-waiting
               table target 102)))
    ;; A new target, or none, retries at once.
    (is (null (ethereum-lisp.cli::devnet-execution-retry-waiting
               table other-target 101)))
    (is (null (ethereum-lisp.cli::devnet-execution-retry-waiting
               table nil 101)))
    ;; A failure under the new target keeps doubling: it is the same block.
    (ethereum-lisp.cli::devnet-execution-retry-note-failure
     table hash 12 other-target 102)
    (is (= 2 (ethereum-lisp.cli::devnet-execution-retry-failures entry)))
    (is (= 100 (ethereum-lisp.cli::devnet-execution-retry-first-at entry)))
    (is (= 102 (ethereum-lisp.cli::devnet-execution-retry-last-at entry)))
    (is (= 106 (ethereum-lisp.cli::devnet-execution-retry-next-at entry)))
    (is (eq entry (ethereum-lisp.cli::devnet-execution-retry-waiting
                   table other-target 105)))
    (is (null (ethereum-lisp.cli::devnet-execution-retry-waiting
               table target 105)))
    ;; Only execution clears the entry, and with it the count.
    (is (null (ethereum-lisp.cli::devnet-execution-retry-remove-executed
               table (constantly nil))))
    (is (= 1 (hash-table-count table)))
    (is (equal (list entry)
               (ethereum-lisp.cli::devnet-execution-retry-remove-executed
                table (lambda (seen) (hash32= seen hash)))))
    (is (zerop (hash-table-count table))))
  ;; The table is bounded: the entry that failed longest ago leaves first.
  (let ((table (make-hash-table :test #'equal)))
    (loop for index from 1 to ethereum-lisp.cli::+devnet-execution-retry-max-entries+
          do (ethereum-lisp.cli::devnet-execution-retry-note-failure
              table (make-hash32 (make-byte-vector 32 :initial-element index))
              index nil (+ 1000 index)))
    (ethereum-lisp.cli::devnet-execution-retry-note-failure
     table (make-hash32 (make-byte-vector 32 :initial-element 200)) 200 nil 5000)
    (is (= ethereum-lisp.cli::+devnet-execution-retry-max-entries+
           (hash-table-count table)))
    (is (null (gethash (hash32-to-hex
                        (make-hash32 (make-byte-vector 32 :initial-element 1)))
                       table)))
    (is (gethash (hash32-to-hex
                  (make-hash32 (make-byte-vector 32 :initial-element 2)))
                 table))))

(defun internal-error-log-field (event name)
  (second (member name (rest event) :test #'equal)))

(deftest devnet-sync-coordinator-waits-before-executing-a-failed-block-again
  (:layer :unit :module :p2p)
  ;; sec5-evm-edge-audit.txt, Not verified: a persistent internal failure was
  ;; retried on every coordinator pass -- every second and on every peer
  ;; announcement -- re-downloading and re-executing the block with an :error
  ;; line each time. RED at c677bdf0: the second, immediate pass ran the sync
  ;; work again.
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0 :public-port 0))
         (config (ethereum-lisp.cli::devnet-node-config node))
         (block (first (eth-sync-produce-empty-blocks
                        (ethereum-lisp.cli::devnet-node-genesis-block node)
                        config 1)))
         (hash (block-hash block))
         (first-target (make-hash32 (make-byte-vector 32 :initial-element 3)))
         (second-target (make-hash32 (make-byte-vector 32 :initial-element 4)))
         (target (list first-target))
         (failing-p t)
         (calls 0)
         (logs '()))
    (flet ((pass (&rest arguments)
             (apply #'ethereum-lisp.cli::devnet-node-sync-coordinator-pass
                    node arguments))
           (events (name)
             (reverse (remove name logs :key #'first :test-not #'string=))))
      (devnet-peer-sync-call-with-function-overrides
       (list
        (cons 'ethereum-lisp.cli::devnet-node-multi-sync-pass
              (lambda (seen-node)
                (declare (ignore seen-node))
                (incf calls)
                (if failing-p
                    (error 'block-execution-internal-error
                           :block-number 1 :block-hash hash
                           :cause (make-condition
                                   'type-error :datum (expt 2 256)
                                   :expected-type
                                   '(mod 4611686018427387901)))
                    1)))
        (cons 'ethereum-lisp.cli::devnet-node-forkchoice-sync-targets
              (lambda (seen-node)
                (declare (ignore seen-node))
                (list (car target))))
        (cons 'ethereum-lisp.cli::devnet-peer-manager-log
              (lambda (seen-node name &rest fields)
                (declare (ignore seen-node))
                (push (cons name fields) logs))))
       (lambda ()
         ;; Two passes back to back, on the wall clock: the second waits.
         (is (null (pass)))
         (is (= 1 calls))
         (is (null (pass)))
         (is (= 1 calls))
         ;; On a controlled clock from here on. The first failure's two
         ;; seconds are over by now + 2, the second failure's four at + 6.
         (let ((now (+ (unix-time) 2)))
           (is (null (pass :now now)))
           (is (= 2 calls))
           (is (null (pass :now (+ now 3))))
           (is (= 2 calls))
           (is (null (pass :now (+ now 4))))
           (is (= 3 calls))
           ;; A new CL target is tried at once, and the doubling goes on.
           (setf (car target) second-target)
           (is (null (pass :now (+ now 5))))
           (is (= 4 calls))
           (is (null (pass :now (+ now 6))))
           (is (= 4 calls))
           ;; Every attempt was logged with the running count.
           (let ((failures (events "peer.sync.execution_internal_error")))
             (is (= 4 (length failures)))
             (is (equal '(1 2 3 4)
                        (mapcar (lambda (event)
                                  (internal-error-log-field event "failures"))
                                failures)))
             (is (equal '(2 4 8 16)
                        (mapcar (lambda (event)
                                  (internal-error-log-field
                                   event "retryInSeconds"))
                                failures)))
             (is (eql (internal-error-log-field (first failures) "firstAt")
                      (internal-error-log-field (fourth failures) "firstAt")))
             (is (eql (+ now 5)
                      (internal-error-log-field (fourth failures) "lastAt"))))
           ;; The block executes (Engine newPayload, say): the entry goes, the
           ;; recovery is logged, and the sync runs on the very next pass.
           (setf failing-p nil)
           (ethereum-lisp.cli::devnet-peer-sync-import-block node block)
           (is (chain-store-state-available-p
                (ethereum-lisp.cli::devnet-node-store node) hash))
           (is (eql 1 (pass :now (+ now 7))))
           (is (= 5 calls))
           (let ((recovered (events "peer.sync.execution_recovered")))
             (is (= 1 (length recovered)))
             (is (eql 4 (internal-error-log-field (first recovered) "failures")))
             ;; Three passes waited: the immediate one, + 3 and + 6.
             (is (eql 3 (internal-error-log-field (first recovered)
                                                 "deferredPasses"))))
           (is (zerop (hash-table-count
                       (ethereum-lisp.cli::devnet-node-execution-retries
                        node))))))))))
