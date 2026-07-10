(in-package #:ethereum-lisp.test)

(defun devnet-cli-set-node-store-config (node store config)
  (let* ((old-config (ethereum-lisp.cli:devnet-node-config node))
         (old-network-id (ethereum-lisp.cli::devnet-node-network-id node))
         (default-network-id-p
           (= old-network-id (chain-config-chain-id old-config)))
         (effective-network-id
           (if default-network-id-p
               (chain-config-chain-id config)
               old-network-id)))
    (flet ((rebind-service (service)
             (setf (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                    service)
                   (ethereum-lisp.rpc:rpc-context-rebind
                    (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                     service)
                    :store store
                    :config config
                    :network-id effective-network-id))))
      (setf (ethereum-lisp.cli:devnet-node-store node) store
            (ethereum-lisp.cli:devnet-node-config node) config
            (ethereum-lisp.cli::devnet-node-network-id node)
            effective-network-id)
      (rebind-service (ethereum-lisp.cli:devnet-node-service node))
      (rebind-service (ethereum-lisp.cli:devnet-node-public-service node))))
  node)

(defun devnet-cli-engine-forkchoice-v2-request
    (id head &key (safe (zero-hash32)) (finalized (zero-hash32)))
  (let ((request (engine-fixture-forkchoice-request
                  id head :safe safe :finalized finalized)))
    (setf (cdr (assoc "method" request :test #'string=))
          "engine_forkchoiceUpdatedV2")
    request))

(defun devnet-cli-payload-attributes-v2
    (parent-block suggested-fee-recipient)
  (let ((parent-header (block-header parent-block)))
    (list (cons "timestamp"
                (quantity-to-hex
                 (1+ (block-header-timestamp parent-header))))
          (cons "prevRandao" (hash32-to-hex (zero-hash32)))
          (cons "suggestedFeeRecipient"
                (address-to-hex suggested-fee-recipient))
          (cons "withdrawals" '()))))

(defun devnet-cli-payload-attributes-v1
    (parent-block suggested-fee-recipient)
  (let ((parent-header (block-header parent-block)))
    (list (cons "timestamp"
                (quantity-to-hex
                 (1+ (block-header-timestamp parent-header))))
          (cons "prevRandao" (hash32-to-hex (zero-hash32)))
          (cons "suggestedFeeRecipient"
                (address-to-hex suggested-fee-recipient)))))

(defun devnet-cli-pre-shanghai-genesis-object ()
  (let* ((genesis
           (parse-json (devnet-cli-file-string +devnet-cli-genesis-fixture+)))
         (config
           (remove "shanghaiTime"
                   (fixture-object-field genesis "config")
                   :key #'car
                   :test #'string=)))
    (setf (cdr (assoc "format" genesis :test #'string=))
          "ethereum-lisp/pre-shanghai-engine-v1-script-fixture")
    (setf (cdr (assoc "config" genesis :test #'string=)) config)
    genesis))

(defun devnet-cli-engine-new-payload-v1-request (id payload)
  (let ((request (engine-fixture-payload-request id payload)))
    (setf (cdr (assoc "method" request :test #'string=))
          "engine_newPayloadV1")
    request))

(defun devnet-cli-engine-forkchoice-v1-payload-attributes-request
    (id head payload-attributes
     &key (safe (zero-hash32)) (finalized (zero-hash32)))
  (let ((request (engine-fixture-forkchoice-request
                  id head :safe safe :finalized finalized)))
    (setf (cdr (assoc "params" request :test #'string=))
          (list (first (fixture-object-field request "params"))
                payload-attributes))
    request))

(defun devnet-cli-engine-forkchoice-v2-payload-attributes-request
    (id head payload-attributes
     &key (safe (zero-hash32)) (finalized (zero-hash32)))
  (let ((request (devnet-cli-engine-forkchoice-v2-request
                  id head :safe safe :finalized finalized)))
    (setf (cdr (assoc "params" request :test #'string=))
          (list (first (fixture-object-field request "params"))
                payload-attributes))
    request))

(defun make-devnet-cli-one-shot-listener (endpoint)
  (let ((accepted-p nil))
    (make-engine-rpc-http-listener
     :endpoint endpoint
     :accept-function
     (lambda ()
       (unless accepted-p
         (setf accepted-p t)
         (make-engine-rpc-http-connection
          :input-stream
          (make-string-input-stream "GET / HTTP/1.1\r\n\r\n")
          :output-stream (make-string-output-stream)
          :close-function (lambda () nil))))
     :close-function (lambda () nil))))
