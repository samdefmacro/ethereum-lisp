(in-package #:ethereum-lisp.test)

;;;; eth/68 wire protocol message round-trips.

(deftest eth-status-round-trips
  (let* ((fork-id (ethereum-lisp.eth-wire:make-eth-fork-id
                   (hex-to-bytes "0xfc64ec04") 1150000))
         (status (ethereum-lisp.eth-wire:make-eth-status
                  :network-id 1
                  :total-difficulty #x0100000000000000000000000000000000000000000000000000000000000000
                  :best-hash (hex-to-bytes
                              "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20")
                  :genesis-hash (hex-to-bytes
                                 "0xd4e56740f876aef8c010b86a40d5f56745a118d0906a34e69aec8c0db1cb8fa3")
                  :fork-id fork-id))
         (decoded (ethereum-lisp.eth-wire:decode-eth-status
                   (ethereum-lisp.eth-wire:encode-eth-status status))))
    (is (= 68 (ethereum-lisp.eth-wire:eth-status-version decoded)))
    (is (= 1 (ethereum-lisp.eth-wire:eth-status-network-id decoded)))
    (is (= (ethereum-lisp.eth-wire:eth-status-total-difficulty status)
           (ethereum-lisp.eth-wire:eth-status-total-difficulty decoded)))
    (is (bytes= (ethereum-lisp.eth-wire:eth-status-best-hash status)
                (ethereum-lisp.eth-wire:eth-status-best-hash decoded)))
    (is (bytes= (ethereum-lisp.eth-wire:eth-status-genesis-hash status)
                (ethereum-lisp.eth-wire:eth-status-genesis-hash decoded)))
    (let ((fid (ethereum-lisp.eth-wire:eth-status-fork-id decoded)))
      (is (bytes= (hex-to-bytes "0xfc64ec04")
                  (ethereum-lisp.eth-wire:eth-fork-id-hash fid)))
      (is (= 1150000 (ethereum-lisp.eth-wire:eth-fork-id-next fid))))))

(deftest eth-get-block-headers-round-trips
  ;; By number.
  (let* ((request (ethereum-lisp.eth-wire:make-eth-get-block-headers
                   :request-id 42 :origin-number 1000 :amount 192
                   :skip 0 :reverse nil))
         (decoded (ethereum-lisp.eth-wire:decode-eth-get-block-headers
                   (ethereum-lisp.eth-wire:encode-eth-get-block-headers request))))
    (is (= 42 (ethereum-lisp.eth-wire:eth-get-block-headers-request-id decoded)))
    (is (= 1000 (ethereum-lisp.eth-wire:eth-get-block-headers-origin-number decoded)))
    (is (null (ethereum-lisp.eth-wire:eth-get-block-headers-origin-hash decoded)))
    (is (= 192 (ethereum-lisp.eth-wire:eth-get-block-headers-amount decoded)))
    (is (not (ethereum-lisp.eth-wire:eth-get-block-headers-reverse decoded))))
  ;; By hash, reverse.
  (let* ((hash (hex-to-bytes
                "0xaabbccddeeff00112233445566778899aabbccddeeff00112233445566778899"))
         (request (ethereum-lisp.eth-wire:make-eth-get-block-headers
                   :request-id 7 :origin-hash hash :amount 1 :skip 3 :reverse t))
         (decoded (ethereum-lisp.eth-wire:decode-eth-get-block-headers
                   (ethereum-lisp.eth-wire:encode-eth-get-block-headers request))))
    (is (bytes= hash (ethereum-lisp.eth-wire:eth-get-block-headers-origin-hash decoded)))
    (is (null (ethereum-lisp.eth-wire:eth-get-block-headers-origin-number decoded)))
    (is (= 3 (ethereum-lisp.eth-wire:eth-get-block-headers-skip decoded)))
    (is (ethereum-lisp.eth-wire:eth-get-block-headers-reverse decoded))))

(deftest eth-block-headers-round-trips-real-headers
  (let* ((h1 (make-block-header :number 100 :timestamp 1000 :gas-limit 30000000
                                :base-fee-per-gas 7 :state-root +empty-trie-hash+
                                :parent-hash (zero-hash32)))
         (h2 (make-block-header :number 101 :timestamp 1012 :gas-limit 30000000
                                :base-fee-per-gas 8 :state-root +empty-trie-hash+
                                :parent-hash (block-header-hash h1)))
         (encoded (ethereum-lisp.eth-wire:encode-eth-block-headers 99 (list h1 h2))))
    (multiple-value-bind (request-id headers)
        (ethereum-lisp.eth-wire:decode-eth-block-headers encoded)
      (is (= 99 request-id))
      (is (= 2 (length headers)))
      ;; The decoded headers hash identically to the originals.
      (is (bytes= (hash32-bytes (block-header-hash h1))
                  (hash32-bytes (block-header-hash (first headers)))))
      (is (bytes= (hash32-bytes (block-header-hash h2))
                  (hash32-bytes (block-header-hash (second headers))))))))

(deftest eth-wire-message-ids-are-offset-past-the-base-protocol
  (is (= #x10 (ethereum-lisp.eth-wire:eth-wire-message-id
               ethereum-lisp.eth-wire:+eth-message-status+)))
  (is (= #x13 (ethereum-lisp.eth-wire:eth-wire-message-id
               ethereum-lisp.eth-wire:+eth-message-get-block-headers+)))
  (is (= #x14 (ethereum-lisp.eth-wire:eth-wire-message-id
               ethereum-lisp.eth-wire:+eth-message-block-headers+))))

(deftest eth-block-bodies-round-trip
  ;; GetBlockBodies by hash list.
  (let ((hashes (list (hash32-bytes (zero-hash32))
                      (hex-to-bytes
                       "0x1111111111111111111111111111111111111111111111111111111111111111"))))
    (multiple-value-bind (request-id decoded-hashes)
        (ethereum-lisp.eth-wire:decode-eth-get-block-bodies
         (ethereum-lisp.eth-wire:encode-eth-get-block-bodies 55 hashes))
      (is (= 55 request-id))
      (is (= 2 (length decoded-hashes)))
      (is (bytes= (second hashes) (second decoded-hashes)))))
  ;; BlockBodies: an empty body and a body with a transaction + withdrawal.
  (let* ((tx (make-legacy-transaction :nonce 0 :gas-limit 21000
                                      :to (address-from-hex
                                           "0x0000000000000000000000000000000000000001")
                                      :value 1000))
         (empty-body (ethereum-lisp.eth-wire:make-eth-block-body
                      :transactions '() :ommers '()))
         (full-body (ethereum-lisp.eth-wire:make-eth-block-body
                     :transactions (list tx) :ommers '()
                     :withdrawals (list (make-withdrawal :index 0 :validator-index 1
                                                         :address (address-from-hex
                                                                   "0x0000000000000000000000000000000000000002")
                                                         :amount 42))
                     :withdrawals-present-p t))
         (encoded (ethereum-lisp.eth-wire:encode-eth-block-bodies
                   77 (list empty-body full-body))))
    (multiple-value-bind (request-id bodies)
        (ethereum-lisp.eth-wire:decode-eth-block-bodies encoded)
      (is (= 77 request-id))
      (is (= 2 (length bodies)))
      (is (null (ethereum-lisp.eth-wire:eth-block-body-transactions (first bodies))))
      (let ((decoded-full (second bodies)))
        (is (= 1 (length (ethereum-lisp.eth-wire:eth-block-body-transactions decoded-full))))
        (is (ethereum-lisp.eth-wire:eth-block-body-withdrawals-present-p decoded-full))
        (is (= 1 (length (ethereum-lisp.eth-wire:eth-block-body-withdrawals decoded-full))))
        ;; The decoded transaction encodes identically to the original.
        (is (bytes= (transaction-encoding tx)
                    (transaction-encoding
                     (first (ethereum-lisp.eth-wire:eth-block-body-transactions
                             decoded-full)))))))))

(deftest eth-fork-id-matches-eip-2124-mainnet-vectors
  ;; EIP-2124 mainnet fork-hash vectors, over the mainnet genesis hash.
  (let ((genesis (hex-to-bytes
                  "0xd4e56740f876aef8c010b86a40d5f56745a118d0906a34e69aec8c0db1cb8fa3")))
    ;; CRC32 of the genesis hash alone is the forkhash before Homestead.
    (is (string= "0xfc64ec04"
                 (bytes-to-hex (ethereum-lisp.eth-wire:eth-fork-hash genesis '()))))
    ;; After Homestead (block 1150000).
    (is (string= "0x97c2c34c"
                 (bytes-to-hex (ethereum-lisp.eth-wire:eth-fork-hash genesis '(1150000)))))
    ;; After Homestead + DAO (1920000).
    (is (string= "0x91d1f948"
                 (bytes-to-hex (ethereum-lisp.eth-wire:eth-fork-hash
                                genesis '(1150000 1920000)))))
    ;; compute-eth-fork-id assembles the hash and the next-fork value.
    (let ((fid (ethereum-lisp.eth-wire:compute-eth-fork-id genesis '() 1150000)))
      (is (string= "0xfc64ec04"
                   (bytes-to-hex (ethereum-lisp.eth-wire:eth-fork-id-hash fid))))
      (is (= 1150000 (ethereum-lisp.eth-wire:eth-fork-id-next fid))))))

(deftest crc32-matches-known-vectors
  ;; The IEEE CRC-32 of "123456789" is the standard 0xCBF43926 check value.
  (is (= #xcbf43926 (ethereum-lisp.eth-wire:crc32 (ascii-to-bytes "123456789"))))
  (is (= 0 (ethereum-lisp.eth-wire:crc32 (make-byte-vector 0)))))

(deftest chain-config-fork-id-matches-geth-mainnet-progression
  ;; A mainnet chain-config, checked against go-ethereum's forkid_test.go: the
  ;; fork hash and the next-fork field at a series of chain heights. Block forks
  ;; that share an activation (Constantinople/Petersburg, the Spurious Dragon
  ;; EIPs) must collapse to one fold input, and the time forks must fold after
  ;; every block fork.
  (let ((genesis (hex-to-bytes
                  "0xd4e56740f876aef8c010b86a40d5f56745a118d0906a34e69aec8c0db1cb8fa3"))
        (config (make-chain-config
                 :chain-id 1
                 :homestead-block 1150000
                 :dao-fork-block 1920000
                 :eip150-block 2463000
                 :eip155-block 2675000
                 :eip158-block 2675000
                 :byzantium-block 4370000
                 :constantinople-block 7280000
                 :petersburg-block 7280000
                 :istanbul-block 9069000
                 :muir-glacier-block 9200000
                 :berlin-block 12244000
                 :london-block 12965000
                 :arrow-glacier-block 13773000
                 :gray-glacier-block 15050000
                 :shanghai-time 1681338455
                 :cancun-time 1710338135)))
    (flet ((fork-id-at (number time)
             (let ((fid (ethereum-lisp.eth-wire:chain-config-eth-fork-id
                         config genesis number time)))
               (list (bytes-to-hex (ethereum-lisp.eth-wire:eth-fork-id-hash fid))
                     (ethereum-lisp.eth-wire:eth-fork-id-next fid)))))
      ;; Genesis (Frontier): CRC over the genesis hash alone, next Homestead.
      (is (equal '("0xfc64ec04" 1150000) (fork-id-at 0 0)))
      ;; Homestead, next DAO.
      (is (equal '("0x97c2c34c" 1920000) (fork-id-at 1150000 0)))
      ;; DAO, next Tangerine Whistle.
      (is (equal '("0x91d1f948" 2463000) (fork-id-at 1920000 0)))
      ;; Byzantium, next Constantinople.
      (is (equal '("0xa00bc324" 7280000) (fork-id-at 4370000 0)))
      ;; Constantinople and Petersburg share block 7280000: one fold input.
      (is (equal '("0x668db0af" 9069000) (fork-id-at 7280000 0)))
      ;; London, next Arrow Glacier.
      (is (equal '("0xb715077d" 13773000) (fork-id-at 12965000 0)))
      ;; Gray Glacier, next fork is a timestamp (Shanghai).
      (is (equal '("0xf0afd0e3" 1681338455) (fork-id-at 15050000 0)))
      ;; Shanghai, folded after every block fork, next Cancun.
      (is (equal '("0xdce96c2d" 1710338135) (fork-id-at 20000000 1681338455)))
      ;; Cancun, no further scheduled fork.
      (is (equal '("0x9f3d2254" 0) (fork-id-at 20000000 1710338135))))))

(deftest eth-status-69-matches-geth-live-wire-bytes
  ;; Byte-exact against a real geth v1.17.4 eth/69 Status captured live on the
  ;; testnet box: [version, networkid, genesis, forkid, earliest, latest,
  ;; latestHash]. Total difficulty and best hash are gone in eth/69.
  (let* ((genesis (hex-to-bytes
                   "0xdd4db8010834be306d0386cbddf2fc91d5778b05a410d22e7bbbf2f2629e5822"))
         (status (ethereum-lisp.eth-wire:make-eth-status
                  :version 69 :network-id 1337 :genesis-hash genesis
                  :fork-id (ethereum-lisp.eth-wire:make-eth-fork-id
                            (hex-to-bytes "0xd59b4e01") 0)
                  :earliest-block 0 :latest-block 0 :latest-block-hash genesis))
         (encoded (ethereum-lisp.eth-wire:encode-eth-status-69 status)))
    (is (string=
         "0xf84f45820539a0dd4db8010834be306d0386cbddf2fc91d5778b05a410d22e7bbbf2f2629e5822c684d59b4e01808080a0dd4db8010834be306d0386cbddf2fc91d5778b05a410d22e7bbbf2f2629e5822"
         (bytes-to-hex encoded)))
    ;; Version-dispatched decode round-trips.
    (let ((decoded (ethereum-lisp.eth-wire:decode-eth-status-for-version encoded 69)))
      (is (= 69 (ethereum-lisp.eth-wire:eth-status-version decoded)))
      (is (= 1337 (ethereum-lisp.eth-wire:eth-status-network-id decoded)))
      (is (= 0 (ethereum-lisp.eth-wire:eth-status-latest-block decoded)))
      (is (bytes= genesis (ethereum-lisp.eth-wire:eth-status-genesis-hash decoded)))
      (is (bytes= genesis (ethereum-lisp.eth-wire:eth-status-latest-block-hash decoded)))
      (is (string= "0xd59b4e01"
                   (bytes-to-hex (ethereum-lisp.eth-wire:eth-fork-id-hash
                                  (ethereum-lisp.eth-wire:eth-status-fork-id decoded))))))
    ;; The version dispatcher picks the eth/68 format below 69.
    (is (string= (bytes-to-hex encoded)
                 (bytes-to-hex (ethereum-lisp.eth-wire:encode-eth-status-for-version status 69))))))

(defun eth-wire-mainnet-config ()
  (make-chain-config
   :chain-id 1 :homestead-block 1150000 :dao-fork-block 1920000
   :eip150-block 2463000 :eip155-block 2675000 :eip158-block 2675000
   :byzantium-block 4370000 :constantinople-block 7280000 :petersburg-block 7280000
   :istanbul-block 9069000 :muir-glacier-block 9200000 :berlin-block 12244000
   :london-block 12965000 :arrow-glacier-block 13773000 :gray-glacier-block 15050000
   :shanghai-time 1681338455 :cancun-time 1710338135))

(deftest validate-peer-fork-id-follows-eip-2124-rules
  (let ((genesis (hex-to-bytes
                  "0xd4e56740f876aef8c010b86a40d5f56745a118d0906a34e69aec8c0db1cb8fa3"))
        (config (eth-wire-mainnet-config)))
    (flet ((fid (number time)
             (ethereum-lisp.eth-wire:chain-config-eth-fork-id config genesis number time))
           (valid (number time peer-fid)
             (ethereum-lisp.eth-wire:validate-peer-fork-id config genesis number time peer-fid))
           (raw-fid (hash next)
             (ethereum-lisp.eth-wire:make-eth-fork-id (hex-to-bytes hash) next)))
      ;; Rule 1b — a peer with our exact current fork id connects.
      (is (valid 15050000 0 (fid 15050000 0)))
      ;; Rule 2 — a peer behind us (at DAO) with the correct next fork connects.
      (is (valid 15050000 0 (fid 1920000 0)))
      ;; Rule 3 — a peer ahead of us (at Cancun) connects; we are the stale one.
      (is (valid 15050000 0 (fid 20000000 1710338135)))
      ;; Rule 2 — same past hash but the WRONG next fork is remote-stale.
      (signals ethereum-lisp.eth-wire:eth-fork-id-mismatch
        (valid 15050000 0 (raw-fid "0x91d1f948" 9999999)))
      (handler-case (valid 15050000 0 (raw-fid "0x91d1f948" 9999999))
        (ethereum-lisp.eth-wire:eth-fork-id-mismatch (condition)
          (is (eq :remote-stale
                  (ethereum-lisp.eth-wire:eth-fork-id-mismatch-reason condition)))))
      ;; Rule 4 — an unrecognized fork hash is a different chain.
      (signals ethereum-lisp.eth-wire:eth-fork-id-mismatch
        (valid 15050000 0 (raw-fid "0xdeadbeef" 0)))
      (handler-case (valid 15050000 0 (raw-fid "0xdeadbeef" 0))
        (ethereum-lisp.eth-wire:eth-fork-id-mismatch (condition)
          (is (eq :local-incompatible-or-stale
                  (ethereum-lisp.eth-wire:eth-fork-id-mismatch-reason condition)))))
      ;; Rule 1a — at Cancun, a peer announcing Cancun as its NEXT fork (which we
      ;; have already crossed) means our software is stale.
      (signals ethereum-lisp.eth-wire:eth-fork-id-mismatch
        (valid 20000000 1710338135 (raw-fid "0x9f3d2254" 1710338135)))
      (handler-case (valid 20000000 1710338135 (raw-fid "0x9f3d2254" 1710338135))
        (ethereum-lisp.eth-wire:eth-fork-id-mismatch (condition)
          (is (eq :local-incompatible-or-stale
                  (ethereum-lisp.eth-wire:eth-fork-id-mismatch-reason condition))))))))
