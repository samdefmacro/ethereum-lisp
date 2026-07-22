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
