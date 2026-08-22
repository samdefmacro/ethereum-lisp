(defpackage #:ethereum-lisp.bytes
  (:use #:cl)
  (:export
   #:byte-vector
   #:byte-vector-p
   #:make-byte-vector
   #:ensure-byte-vector
   #:bytes=
   #:concat-bytes
   #:integer-to-minimal-bytes
   #:bytes-to-integer
   #:ascii-to-bytes
   #:bytes-to-ascii
   #:crc32))

(defpackage #:ethereum-lisp.hex
  (:use #:cl #:ethereum-lisp.bytes)
  (:export
   #:bytes-to-hex
   #:hex-to-bytes
   #:quantity-to-hex
   #:hex-to-quantity))

(defpackage #:ethereum-lisp.strings
  (:use #:cl)
  (:export
   #:string-prefix-p))

(defpackage #:ethereum-lisp.snappy
  (:use #:cl #:ethereum-lisp.bytes)
  (:export
   #:snappy-compress
   #:snappy-decompress
   #:+snappy-max-decoded-length+))

(defpackage #:ethereum-lisp.database
  (:use #:cl #:ethereum-lisp.bytes #:ethereum-lisp.hex)
  (:export
   #:key-value-database
   #:memory-key-value-database
   #:file-key-value-database
   #:rocksdb-key-value-database
   #:make-memory-key-value-database
   #:make-file-key-value-database
   #:make-rocksdb-key-value-database
   #:close-rocksdb-key-value-database
   #:rocksdb-available-p
   #:kv-database-reopen-required-p
   #:kv-log-corruption-error
   #:kv-log-corruption-error-path
   #:kv-log-corruption-error-detail
   #:kv-get
   #:kv-get-many
   #:kv-put
   #:kv-delete
   #:kv-write-batch
   #:make-kv-write-batch
   #:kv-batch-put
   #:kv-batch-delete
   #:kv-apply-batch
   #:kv-iterator
   #:kv-chain-record-key
   #:kv-chain-record-key-kind
   #:kv-chain-record-key-identifier
   #:kv-chain-record-kind-start-key
   #:kv-chain-record-kind-end-key
   #:+kv-chain-schema-version+
   #:kv-chain-record-uint64-bytes
   #:kv-chain-record-uint64-identifier
   #:kv-chain-height-hash-identifier
   #:kv-chain-height-hash-identifier-values
   #:kv-put-chain-record
   #:kv-get-chain-record
   #:kv-get-chain-records
   #:kv-delete-chain-record
   #:kv-batch-put-chain-record
   #:kv-batch-delete-chain-record
   #:kv-chain-records
   #:kv-chain-record-entries
   #:kv-put-chain-canonical-hash
   #:kv-get-chain-canonical-hash
   #:kv-delete-chain-canonical-hash
   #:kv-batch-put-chain-canonical-hash
   #:kv-batch-delete-chain-canonical-hash
   #:kv-chain-canonical-hashes
   #:kv-put-chain-checkpoint
   #:kv-get-chain-checkpoint
   #:kv-delete-chain-checkpoint
   #:kv-batch-put-chain-checkpoint
   #:kv-batch-delete-chain-checkpoint
   #:kv-chain-checkpoints
   #:kv-put-chain-schema-version
   #:kv-batch-put-chain-schema-version
   #:kv-get-chain-schema-version))

(defpackage #:ethereum-lisp.telemetry
  (:use #:cl)
  (:export
   #:*telemetry-sink*
   #:telemetry-event
   #:make-telemetry-event
   #:telemetry-event-kind
   #:telemetry-event-name
   #:telemetry-event-value
   #:telemetry-event-fields
   #:memory-telemetry-sink
   #:make-memory-telemetry-sink
   #:counting-telemetry-sink
   #:counting-telemetry-sink-p
   #:make-counting-telemetry-sink
   #:counting-telemetry-sink-delegate
   #:counting-telemetry-sink-snapshot
   #:stream-telemetry-sink
   #:make-stream-telemetry-sink
   #:stream-telemetry-sink-stream
   #:telemetry-events
   #:telemetry-emit
   #:telemetry-log
   #:telemetry-metric
   #:telemetry-prometheus-escape
   #:telemetry-prometheus-text))

(defpackage #:ethereum-lisp.validation
  (:use #:cl #:ethereum-lisp.bytes)
  (:export
   #:ethereum-lisp-error
   #:ethereum-lisp-error-message
   #:data-decoding-error
   #:invalid-parameters-error
   #:consensus-validation-error
   #:configuration-error
   #:storage-error
   #:state-unavailable-error
   #:data-decoding-fail
   #:invalid-parameters-fail
   #:consensus-validation-fail
   #:configuration-fail
   #:storage-fail
   #:state-unavailable-fail
   #:block-validation-error
   #:block-validation-error-message
   #:block-validation-fail
   #:ensure-uint256
   #:optional-bytes
   #:rlp-uint-field
   #:rlp-bytes-field
   #:rlp-list-field
   #:rlp-sized-bytes-field
   #:rlp-hash32-field
   #:rlp-address-field
   #:validate-byte-sequence-field
   #:byte-vector-lexicographic<
   #:uint32-value-p
   #:uint64-value-p))

(defpackage #:ethereum-lisp.rlp
  (:use #:cl #:ethereum-lisp.bytes)
  (:export
   #:+rlp-max-depth+
   #:rlp-error
   #:rlp-list
   #:rlp-list-p
   #:rlp-list-items
   #:make-rlp-list
   #:rlp-encode
   #:rlp-decode
   #:rlp-decode-one))

(defpackage #:ethereum-lisp.types
  (:use #:cl #:ethereum-lisp.bytes #:ethereum-lisp.hex)
  (:export
   #:+uint256-max+
   #:uint256-p
   #:address
   #:address-p
   #:address-bytes
   #:make-address
   #:address-from-hex
   #:address-to-hex
   #:zero-address
   #:hash32
   #:hash32-p
   #:hash32-bytes
   #:make-hash32
   #:hash32-from-hex
   #:hash32-to-hex
   #:hash32=
   #:zero-hash32
   #:+unix-epoch-universal-time+
   #:universal-time-to-unix-time
   #:unix-time-to-universal-time
   #:unix-time))

(defpackage #:ethereum-lisp.crypto
  (:use #:cl #:ethereum-lisp.bytes #:ethereum-lisp.hex #:ethereum-lisp.types)
  (:export
   #:keccak-256
   #:make-keccak-256
   #:keccak-256-update
   #:keccak-256-digest
   #:keccak-256-hash
   #:keccak-256-hex
   #:keccak-512
   #:sha256
   #:sha256-hash
   #:sha256-hex
   #:ripemd160
   #:ripemd160-hex
   #:secp256k1-private-key-address
   #:secp256k1-private-key-public-key
   #:secp256k1-recover-public-key
   #:secp256k1-recover-address
   #:secp256k1-valid-signature-values-p
   #:secp256r1-verify
   #:aes-ctr
   #:make-aes-ctr-stream
   #:aes-ctr-stream-apply
   #:aes-encrypt-ecb-block
   #:hmac-sha256
   #:constant-time-bytes=
   #:secp256k1-ecdh
   #:secp256k1-public-key-point
   #:secp256k1-compress-public-key
   #:secp256k1-decompress-public-key
   #:secp256k1-verify
   #:secp256k1-sign
   #:secp256k1-random-private-key
   #:secure-random-bytes
   #:+kzg-commitment-size+
   #:+kzg-commitment-version+
   #:kzg-commitment-to-versioned-hash
   #:+empty-code-hash+
   #:+empty-trie-hash+))

(defpackage #:ethereum-lisp.trie.encoding
  (:use #:cl #:ethereum-lisp.bytes)
  (:export
   #:+terminator-nibble+
   #:has-terminator-p
   #:keybytes-to-nibbles
   #:nibbles-to-keybytes
   #:hex-prefix-encode
   #:hex-prefix-decode
   #:common-prefix-length))

(defpackage #:ethereum-lisp.trie
  (:use #:cl
        #:ethereum-lisp.bytes
        #:ethereum-lisp.hex
        #:ethereum-lisp.types
        #:ethereum-lisp.rlp
        #:ethereum-lisp.crypto
        #:ethereum-lisp.database
        #:ethereum-lisp.trie.encoding)
  (:export
   #:mpt
   #:make-mpt
   #:copy-mpt
   #:copy-mpt-root
   #:make-persisted-mpt
   #:mpt-put
   #:mpt-put-proven-absent
   #:mpt-delete
   #:mpt-get
   #:mpt-entry-pairs
   #:mpt-entry-range
   #:mpt-get-proof
   #:mpt-verify-proof
   #:mpt-root-hash
   #:mpt-root-hex
   #:mpt-root-node
   #:mpt-persist
   #:mpt-dirty-node-records
   #:mpt-populate-dirty-batch
   #:mpt-mark-nodes-persisted
   #:trie-node-store-get
   #:mpt-get-node-by-compact-path
   #:make-mpt-iterator
   #:mpt-get-range-proof
   #:mpt-verify-range-proof))
