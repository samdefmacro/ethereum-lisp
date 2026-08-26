(defpackage #:ethereum-lisp.cli
  (:use #:cl
        #:ethereum-lisp
        #:ethereum-lisp.telemetry)
  (:import-from #:ethereum-lisp.types
                #:hash32=)
  (:import-from #:ethereum-lisp.chain-store
                #:engine-payload-store-ancestor-p)
  (:import-from #:ethereum-lisp.engine-payloads
                #:engine-target-gas-limit)
  (:import-from #:ethereum-lisp.engine-api
                #:engine-rpc-improve-open-payloads
                #:make-engine-rpc-get-blobs-v3-snapshot-function)
  (:import-from #:ethereum-lisp.eth-wire
                #:eth-pooled-entry-transaction
                #:+eth-protocol-version-69+
                #:+eth-message-new-block-hashes+
                #:make-eth-new-block-hash
                #:encode-eth-new-block-hashes)
  (:import-from #:ethereum-lisp.eth-sync
                #:eth-sync-multi-peer-error
                #:eth-sync-multi-peer-fail
                #:eth-peer-set-sync-notification-function)
  (:import-from #:ethereum-lisp.txpool
                #:engine-payload-store-enable-txpool-database-change-tracking
                #:engine-payload-store-txpool-database-change-tracking-enabled-p
                #:engine-payload-store-clear-txpool-database-dirty-transaction-hashes
                #:engine-payload-store-pending-mining-transactions
                #:engine-payload-store-pending-transactions
                #:engine-payload-store-pending-transaction-count
                #:engine-payload-store-queued-transaction-count
                #:engine-payload-store-basefee-transaction-count
                #:engine-payload-store-blob-transaction-count
                #:engine-payload-store-pooled-transaction
                #:engine-payload-store-pooled-transactions
                #:engine-payload-store-txpool-changes-since
                #:engine-payload-store-remove-expired-txpool-queued-view-transactions
                #:engine-select-mining-transactions)
  ;; The admin RPC namespace reads peering state through a backend of closures
  ;; the node builds; the struct itself belongs to the API layer.
  (:import-from #:ethereum-lisp.public-api
                #:make-admin-backend
                ;; eth_subscribe is answered per connection, so the registry
                ;; lives on the WebSocket session rather than in the router.
                #:make-eth-rpc-subscription-registry
                #:eth-rpc-handle-eth-subscribe
                #:eth-rpc-handle-eth-unsubscribe
                #:eth-rpc-subscription-poll)
  ;; The WebSocket endpoint drives a transport that knows nothing about
  ;; Ethereum: it is handed a request handler and a notification source.
  (:import-from #:ethereum-lisp.websocket
                #:websocket-handshake-response
                #:make-websocket-connection
                #:websocket-pump)
  ;; The WebSocket endpoint answers ordinary methods through the same router
  ;; the HTTP listener uses, so it needs the service's context directly.
  (:import-from #:ethereum-lisp.rpc-http
                #:engine-rpc-http-service-rpc-context)
  (:import-from #:ethereum-lisp.rpc
                ;; The -JSON variant: string in, string out. The -STRING one
                ;; returns a parsed object, which a frame cannot carry.
                #:rpc-handle-request-json)
  (:import-from #:ethereum-lisp.json
                #:json-array-values
                #:json-object-p
                #:json-object-field
                #:+json-false+)
  ;; Gossiped transactions go through the same admission the public RPC uses.
  (:import-from #:ethereum-lisp.txpool.application
                #:make-txpool-admission-policy
                #:txpool-local-transaction-predicate
                #:txpool-admit-transaction)
  (:import-from #:ethereum-lisp.node-store.persistence
                #:make-node-store-persistence-metadata
                #:node-store-persistence-metadata-role
                #:node-store-persistence-metadata-generation
                #:node-store-persistence-metadata-chain-id
                #:node-store-persistence-metadata-genesis-hash
                #:node-store-persistence-metadata-authority-id
                #:node-store-persistence-metadata-base-chain-generation
                #:node-store-read-persistence-metadata
                #:node-store-migrate-chain-schema
                #:make-database-engine-payload-store
                #:database-engine-payload-store-p
                #:database-engine-payload-store-database
                #:make-node-store-peer-sync-progress
                #:node-store-peer-sync-progress-last-number
                #:node-store-peer-sync-progress-last-hash
                #:node-store-read-peer-sync-progress
                #:make-node-store-snap-skeleton-progress
                #:node-store-snap-skeleton-progress-target-hash
                #:node-store-snap-skeleton-progress-target-number
                #:node-store-snap-skeleton-progress-anchor-number
                #:node-store-snap-skeleton-progress-anchor-hash
                #:node-store-snap-skeleton-progress-pivot-number
                #:node-store-snap-skeleton-progress-pivot-hash
                #:node-store-snap-skeleton-progress-last-number
                #:node-store-snap-skeleton-progress-last-hash
                #:node-store-read-snap-skeleton-progress
                #:node-store-delete-snap-skeleton-progress
                #:node-store-populate-snap-skeleton-rebase-batch
                #:node-store-export-snap-skeleton-batch-to-kv
                #:node-store-delete-peer-sync-progress
                #:node-store-export-payload-candidate-to-kv
                #:node-store-export-buffered-candidate-to-kv
                #:node-store-export-invalid-candidate-to-kv
                #:node-store-export-forkchoice-to-kv
                #:node-store-export-to-kv
                #:node-store-export-txpool-records-to-kv
                #:node-store-import-txpool-records-from-kv
                #:node-store-import-txpool-blob-sidecars-from-kv
                #:node-store-import-bounded-invalid-tipsets-from-kv
                #:node-store-import-bounded-remote-blocks-from-kv
                #:node-store-restore-txpool-consistency)
  (:import-from #:ethereum-lisp.validation
                #:block-validation-fail
                #:storage-error
                #:storage-fail)
  (:export
   #:devnet-chain-preset
   #:make-devnet-chain-preset
   #:devnet-chain-preset-name
   #:devnet-chain-preset-genesis-json
   #:devnet-chain-preset-network-id
   #:devnet-chain-preset-bootnodes
   #:*devnet-chain-preset-provider*
   #:devnet-cli-apply-chain-preset
   #:make-devnet-peer-table
   #:devnet-peer-table
   #:devnet-peer-table-count
   #:devnet-peer-table-entry
   #:devnet-peer-table-entries
   #:devnet-peer-table-max-peers
   #:devnet-peer-table-pending
   #:devnet-peer-table-self-id-hex
   #:devnet-peer-table-slot-verdict
   #:devnet-peer-table-reserve-slot
   #:devnet-peer-table-release-slot
   #:devnet-peer-table-inbound-verdict
   #:devnet-peer-score
   #:devnet-peer-note-score
   #:devnet-peer-table-admit
   #:devnet-peer-table-remove
   #:devnet-peer-table-snapshot
   #:devnet-peer-table-count-by-direction
   #:+devnet-dial-cooldown-seconds+
   #:+devnet-dial-backoff-ceiling-seconds+
   #:+devnet-dial-backoff-max-doublings+
   #:+devnet-max-active-dials+
   #:+devnet-dial-ratio+
   #:+devnet-dial-dynamic-candidate-limit+
   #:+devnet-dial-dynamic-forget-failures+
   #:devnet-dial-candidate
   #:make-devnet-dial-candidate
   #:devnet-dial-candidate-id-hex
   #:devnet-dial-candidate-enode
   #:devnet-dial-candidate-kind
   #:devnet-dial-candidate-state
   #:devnet-dial-candidate-failures
   #:devnet-dial-candidate-next-eligible-at
   #:devnet-dial-registry
   #:make-devnet-dial-registry
   #:devnet-dial-registry-candidate
   #:devnet-dial-registry-count
   #:devnet-dial-backoff-seconds
   #:devnet-dial-registry-put-static
   #:devnet-dial-registry-put-bootstrap
   #:devnet-dial-registry-offer-dynamic
   #:devnet-dial-registry-dialing-count
   #:devnet-dial-free-slots
   #:devnet-dial-verdict
   #:devnet-dial-registry-plan
   #:devnet-dial-registry-claim-plan
   #:devnet-dial-registry-mark-dialing
   #:devnet-dial-registry-mark-connected
   #:devnet-dial-registry-mark-done
   #:devnet-dial-registry-expire
   #:devnet-dial-registry-snapshot
   #:devnet-peer-entry
   #:make-devnet-peer-entry
   #:devnet-peer-entry-id-hex
   #:devnet-peer-entry-direction
   #:devnet-peer-entry-remote-host
   #:devnet-peer-entry-remote-port
   #:devnet-peer-entry-eth-version
   #:devnet-peer-entry-client-id
   #:devnet-peer-entry-connected-at
   #:+devnet-default-max-peers+
   #:devnet-node-peer-table
   #:devnet-node-discovery-table
   #:devnet-start-discovery-server-thread
   #:devnet-node-p2p-host
   #:devnet-node-p2p-port
   #:devnet-node-enode
   #:devnet-node-metrics
   #:devnet-node-metrics-enabled-p
   #:devnet-node-metrics-host
   #:devnet-node-metrics-port
   #:devnet-node-metrics-endpoint
   #:devnet-metrics-http-response
   #:devnet-start-metrics-server-thread
   #:devnet-node-ws-enabled-p
   #:devnet-node-ws-host
   #:devnet-node-ws-port
   #:devnet-node-ws-origins
   #:devnet-node-ws-rpc-prefix
   #:devnet-node-ws-endpoint
   #:devnet-ws-parse-handshake
   #:devnet-ws-message-handler
   #:devnet-ws-notification-source
   #:devnet-start-ws-server-thread
   #:devnet-shutdown-controller-add-closeable
   #:devnet-shutdown-controller-remove-closeable
   #:devnet-start-p2p-listener-thread
   #:devnet-start-dial-scheduler-thread
   #:devnet-peer-dial-session
   #:devnet-node-sync-targets
   #:devnet-node-forkchoice-sync-targets
   #:devnet-peer-fill-sync-gaps
   #:devnet-peer-pending-broadcast
   #:devnet-node-claim-sync
   #:devnet-node-release-sync
   #:call-with-devnet-sync-claim
   #:+devnet-broadcast-batch-limit+
   #:+devnet-peer-known-transaction-limit+
   #:devnet-dial-scheduler-pass
   #:+devnet-dial-tick-seconds+
   #:+devnet-session-stream-timeout-seconds+
   #:devnet-node-dial-registry
   #:devnet-join-peer-sessions
   #:devnet-node
   #:devnet-endpoint-config
   #:make-devnet-endpoint-config
   #:devnet-txpool-policy
   #:make-devnet-txpool-policy
   #:make-devnet-node
   #:devnet-node-genesis-path
   #:devnet-node-store
   #:devnet-node-config
   #:devnet-node-genesis-block
   #:devnet-node-service
   #:devnet-node-public-service
   #:devnet-node-telemetry-sink
   #:devnet-node-jwt-secret-path
   #:devnet-node-log-path
   #:devnet-node-database-path
   #:devnet-node-pid-file-path
   #:devnet-node-prune-state-before
   #:devnet-shutdown-controller
   #:make-devnet-shutdown-controller
   #:devnet-shutdown-controller-requested-p
   #:devnet-shutdown-requested-p
   #:devnet-shutdown-request
   #:devnet-node-summary
   #:start-devnet-node-listeners
   #:start-devnet-node
   #:main))
