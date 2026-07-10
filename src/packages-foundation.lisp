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
   #:bytes-to-ascii))

(defpackage #:ethereum-lisp.hex
  (:use #:cl #:ethereum-lisp.bytes)
  (:export
   #:bytes-to-hex
   #:hex-to-bytes
   #:quantity-to-hex
   #:hex-to-quantity))

(defpackage #:ethereum-lisp.database
  (:use #:cl #:ethereum-lisp.bytes #:ethereum-lisp.hex)
  (:export
   #:key-value-database
   #:memory-key-value-database
   #:file-key-value-database
   #:make-memory-key-value-database
   #:make-file-key-value-database
   #:kv-get
   #:kv-put
   #:kv-delete
   #:kv-write-batch
   #:make-kv-write-batch
   #:kv-batch-put
   #:kv-batch-delete
   #:kv-apply-batch
   #:kv-iterator
   #:kv-chain-record-key
   #:kv-put-chain-record
   #:kv-get-chain-record
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
   #:kv-chain-checkpoints))

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
   #:stream-telemetry-sink
   #:make-stream-telemetry-sink
   #:stream-telemetry-sink-stream
   #:telemetry-events
   #:telemetry-emit
   #:telemetry-log
   #:telemetry-metric))

(defpackage #:ethereum-lisp.validation
  (:use #:cl #:ethereum-lisp.bytes)
  (:export
   #:block-validation-error
   #:block-validation-error-message
   #:block-validation-fail
   #:ensure-uint256
   #:optional-bytes))

(defpackage #:ethereum-lisp.rlp
  (:use #:cl #:ethereum-lisp.bytes)
  (:export
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
   #:zero-hash32))

(defpackage #:ethereum-lisp.crypto
  (:use #:cl #:ethereum-lisp.bytes #:ethereum-lisp.hex #:ethereum-lisp.types)
  (:export
   #:keccak-256
   #:keccak-256-hash
   #:keccak-256-hex
   #:sha256
   #:sha256-hash
   #:sha256-hex
   #:ripemd160
   #:ripemd160-hex
   #:secp256k1-private-key-address
   #:secp256k1-recover-public-key
   #:secp256k1-recover-address
   #:secp256k1-valid-signature-values-p
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
        #:ethereum-lisp.trie.encoding)
  (:export
   #:mpt
   #:make-mpt
   #:mpt-put
   #:mpt-delete
   #:mpt-get
   #:mpt-entry-pairs
   #:mpt-entry-range
   #:mpt-get-proof
   #:mpt-verify-proof
   #:mpt-root-hash
   #:mpt-root-hex
   #:mpt-root-node))
