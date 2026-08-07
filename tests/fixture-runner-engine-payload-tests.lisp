(in-package #:ethereum-lisp.test)

;;;; Cancun-and-later Engine payload conformance, and invalid-payload refusal.
;;;;
;;;; The V2 replay path builds the child block itself and then submits what it
;;;; built. That works while a payload is self-contained, and stops working at
;;;; Cancun: newPayloadV3 carries the blob versioned hashes and the parent
;;;; beacon block root outside the payload, newPayloadV4 adds the execution
;;;; requests, and a harness that reconstructs the call cannot exercise the
;;;; argument checking those parameters exist for. So these tests submit the
;;;; fixture's own parameters, unmodified, through the real Engine method.
;;;;
;;;; That also makes the invalid half expressible for the first time. A vector
;;;; the node must REFUSE has no derived expectation -- there is no state root
;;;; or receipts root, because the block was never executed -- so the only thing
;;;; to assert is the refusal, and asserting it requires handing the node the
;;;; payload as-is rather than one this harness rebuilt.
;;;;
;;;; The parent has to hash to exactly the genesis hash the fixture states.
;;;; Anything else and the node answers SYNCING, which is neither acceptance nor
;;;; refusal, and every assertion below would pass without judging the payload.
;;;; Checking the reconstruction against the fixture's own hash is therefore
;;;; both a precondition and a header-encoding conformance check in its own
;;;; right.

(defun eest-engine-payload-store (case)
  "Return (VALUES store genesis-block) seeded with CASE's genesis and pre-state."
  (let* ((genesis
           (make-block :header (fixture-required-field case "genesisHeader")))
         (state
           (engine-fixture-parent-state (fixture-required-field case "parent")))
         (store (make-engine-payload-memory-store)))
    (engine-payload-store-put-block store genesis :state-available-p t)
    (commit-state-db-to-chain-store store (block-hash genesis) state)
    (values store genesis)))

(defun eest-engine-payload-request (id case)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method"
              (format nil "engine_newPayloadV~A"
                      (fixture-required-field case "newPayloadVersion")))
        (cons "params" (fixture-required-field case "params"))))

(defun eest-engine-payload-submit (case)
  "Submit CASE through the real Engine method and return what came back.

Returns (VALUES response store), so callers can also inspect what the node did
to its own view -- refusing a payload in the response while publishing its state
would still be a consensus failure."
  (multiple-value-bind (store genesis) (eest-engine-payload-store case)
    (let ((genesis-hash (hash32-to-hex (block-hash genesis))))
      (unless (string= genesis-hash (fixture-required-field case "genesisHash"))
        (error "EEST engine case ~A rebuilt genesis hashes to ~A, but the ~
                fixture says ~A, so the payload's parent would not resolve"
               (fixture-required-field case "name")
               genesis-hash
               (fixture-required-field case "genesisHash"))))
    (values (engine-rpc-handle-request
             (eest-engine-payload-request 401 case)
             store
             (engine-fixture-chain-config case)
             :import-function #'execute-and-commit-engine-payload)
            store)))

(defun eest-engine-payload-response-error (response)
  (cdr (assoc "error" response :test #'string=)))

(defun eest-engine-payload-response-result (response)
  (cdr (assoc "result" response :test #'string=)))

(defun eest-engine-payload-block-hash (case)
  (fixture-required-field
   (fixture-required-field case "payload")
   "blockHash"))

(defun eest-engine-payload-error-code (value)
  "EEST writes an Engine errorCode as a number; accept a hex string too."
  (etypecase value
    (integer value)
    (string (hex-to-quantity value))))

(defun assert-eest-engine-payload-accepted (case)
  "Assert the node ACCEPTED CASE's payload and adopted it."
  (multiple-value-bind (response store) (eest-engine-payload-submit case)
    (let ((error-object (eest-engine-payload-response-error response))
          (result (eest-engine-payload-response-result response))
          (block-hash (eest-engine-payload-block-hash case)))
      (when error-object
        (error "EEST engine case ~A expected VALID but newPayloadV~A returned ~
                a JSON-RPC error: ~S"
               (fixture-required-field case "name")
               (fixture-required-field case "newPayloadVersion")
               error-object))
      (let ((status (fixture-object-field result "status")))
        (unless (equal "VALID" status)
          (error "EEST engine case ~A expected VALID, got ~A (validationError: ~
                  ~S)"
                 (fixture-required-field case "name")
                 status
                 (fixture-object-field result "validationError"))))
      (is (equal "VALID" (fixture-object-field result "status")))
      (is (equal block-hash (fixture-object-field result "latestValidHash")))
      (is (chain-store-state-available-p store (hash32-from-hex block-hash))))))

(defun assert-eest-engine-payload-refused (case)
  "Assert the node REFUSED CASE's payload for the reason the fixture states.

Two kinds of refusal, and the fixture says which. An errorCode is a JSON-RPC
error the Engine method itself must return, and that one is compared exactly.
A validationError is an EEST spec exception name -- `BlockException.INVALID_
GASLIMIT' and friends -- which no client reproduces verbatim and Hive does not
compare either; what is checkable, and what is asserted, is that the node
refused THROUGH THE ENGINE PROTOCOL with a stated reason. A Lisp condition
escaping, a VALID status, or an INVALID with no reason all fail here, so this is
not `execution threw something'.

The last assertion is the one that makes the refusal mean anything: a rejected
payload must leave no state published, because a node that answers INVALID and
still exposes the block's state has not rejected it."
  (multiple-value-bind (response store) (eest-engine-payload-submit case)
    (let* ((expect (fixture-required-field case "expect"))
           (expected-code (fixture-object-field expect "errorCode"))
           (error-object (eest-engine-payload-response-error response))
           (result (eest-engine-payload-response-result response))
           (block-hash (eest-engine-payload-block-hash case)))
      (if expected-code
          (progn
            (unless error-object
              (error "EEST engine case ~A expected JSON-RPC error ~A, got ~S"
                     (fixture-required-field case "name")
                     expected-code
                     result))
            (is (eql (eest-engine-payload-error-code expected-code)
                     (fixture-object-field error-object "code"))))
          (progn
            (when error-object
              (error "EEST engine case ~A expected an INVALID payload status, ~
                      got a JSON-RPC error: ~S"
                     (fixture-required-field case "name")
                     error-object))
            (let ((status (fixture-object-field result "status"))
                  (validation-error
                    (fixture-object-field result "validationError")))
              (unless (equal "INVALID" status)
                (error "EEST engine case ~A must be refused as ~S but the node ~
                        answered ~A"
                       (fixture-required-field case "name")
                       (fixture-object-field expect "validationError")
                       status))
              (is (equal "INVALID" status))
              (is (not (blank-string-p validation-error))))))
      (is (not (chain-store-state-available-p
                store
                (hash32-from-hex block-hash)))))))

(defun phase-a-eest-blockchain-late-replay-selectors (cases)
  (remove-if-not
   (lambda (case)
     (member (eest-blockchain-replay-materialization-kind case)
             '("engineNewPayloadV3" "engineNewPayloadV4")
             :test #'string=))
   cases))

(deftest optional-phase-a-eest-engine-late-payload-replay-executes
  ;; Cancun and Prague payloads, submitted as newPayloadV3/V4 with their blob
  ;; versioned hashes, parent beacon root and execution requests intact. Empty
  ;; under the default Shanghai gate -- widening
  ;; ETHEREUM_LISP_PHASE_A_BLOCKCHAIN_REPLAY_FORKS is what selects them -- and
  ;; the count manifest is what reports the emptiness rather than hiding it.
  (let ((cases (phase-a-eest-blockchain-late-replay-selectors
                (load-optional-phase-a-eest-blockchain-replay-cases))))
    (dolist (source-case cases)
      (assert-eest-engine-payload-accepted
       (materialize-eest-blockchain-engine-newpayload-late-case source-case)))))

(deftest optional-phase-a-eest-engine-payload-rejection-executes
  (dolist (source-case (load-optional-phase-a-eest-blockchain-rejection-cases))
    (assert-eest-engine-payload-refused
     (materialize-eest-blockchain-engine-rejection-case source-case))))
