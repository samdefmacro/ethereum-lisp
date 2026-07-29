(in-package #:ethereum-lisp.genesis)

;;;; Canonical public-network genesis presets.
;;;;
;;;; Allocation assets are the decoded prealloc constants from pinned geth
;;;; 38271784c2b31926563806da9a2e023b88f5e7a8, core/genesis_alloc.go. Keeping
;;;; the compact RLP avoids parsing megabytes of JSON at node startup.

(defstruct (built-in-genesis-preset
            (:constructor %make-built-in-genesis-preset
                (&key name config expected-hash allocation-path nonce timestamp
                      gas-limit difficulty extra-data)))
  name
  config
  expected-hash
  allocation-path
  (nonce 0 :type (integer 0 *))
  (timestamp 0 :type (integer 0 *))
  (gas-limit +genesis-gas-limit+ :type (integer 0 *))
  (difficulty +genesis-difficulty+ :type (integer 0 *))
  (extra-data (make-byte-vector 0) :type byte-vector))

(defun mainnet-chain-config ()
  (make-chain-config
   :chain-id 1
   :homestead-block 1150000
   :dao-fork-block 1920000
   :dao-fork-support t
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
   :terminal-total-difficulty 58750000000000000000000
   :shanghai-time 1681338455
   :cancun-time 1710338135
   :prague-time 1746612311
   :osaka-time 1764798551
   :bpo1-time 1765290071
   :bpo2-time 1767747671
   :deposit-contract-address
   (address-from-hex "0x00000000219ab540356cbb839cbe05303d7705fa")))

(defun public-testnet-chain-config
    (chain-id terminal-total-difficulty merge-netsplit-block
     shanghai-time cancun-time prague-time osaka-time bpo1-time bpo2-time
     deposit-contract-address &key (muir-glacier-block nil))
  (make-chain-config
   :chain-id chain-id
   :homestead-block 0
   :dao-fork-support t
   :eip150-block 0
   :eip155-block 0
   :eip158-block 0
   :byzantium-block 0
   :constantinople-block 0
   :petersburg-block 0
   :istanbul-block 0
   :muir-glacier-block muir-glacier-block
   :berlin-block 0
   :london-block 0
   :terminal-total-difficulty terminal-total-difficulty
   :merge-netsplit-block merge-netsplit-block
   :shanghai-time shanghai-time
   :cancun-time cancun-time
   :prague-time prague-time
   :osaka-time osaka-time
   :bpo1-time bpo1-time
   :bpo2-time bpo2-time
   :deposit-contract-address (address-from-hex deposit-contract-address)))

(defun sepolia-chain-config ()
  (public-testnet-chain-config
   11155111 17000000000000000 1735371
   1677557088 1706655072 1741159776 1760427360 1761017184 1761607008
   "0x7f02c3e3c98b133055b8b348b2ac625669ed295d"
   :muir-glacier-block 0))

(defun holesky-chain-config ()
  (public-testnet-chain-config
   17000 0 nil
   1696000704 1707305664 1740434112 1759308480 1759800000 1760389824
   "0x4242424242424242424242424242424242424242"))

(defun hoodi-chain-config ()
  (public-testnet-chain-config
   560048 0 0
   0 0 1742999832 1761677592 1762365720 1762955544
   "0x00000000219ab540356cbb839cbe05303d7705fa"
   :muir-glacier-block 0))

(defun genesis-allocation-path (name)
  (asdf:system-relative-pathname
   "ethereum-lisp"
   (format nil "src/protocol/genesis/alloc-data/~(~A~).rlp" name)))

(defun mainnet-genesis-preset ()
  (%make-built-in-genesis-preset
   :name :mainnet
   :config (mainnet-chain-config)
   :expected-hash
   (hash32-from-hex
    "0xd4e56740f876aef8c010b86a40d5f56745a118d0906a34e69aec8c0db1cb8fa3")
   :allocation-path (genesis-allocation-path :mainnet)
   :nonce 66
   :gas-limit 5000
   :difficulty 17179869184
   :extra-data
   (hex-to-bytes
    "0x11bbe8db4e347b4e8c937c1c8370e4b5ed33adb3db69cbdb7a38e1e50b1b82fa")))

(defun sepolia-genesis-preset ()
  (%make-built-in-genesis-preset
   :name :sepolia
   :config (sepolia-chain-config)
   :expected-hash
   (hash32-from-hex
    "0x25a5cc106eea7138acab33231d7160d69cb777ee0c2c553fcddf5138993e6dd9")
   :allocation-path (genesis-allocation-path :sepolia)
   :timestamp 1633267481
   :gas-limit #x1c9c380
   :difficulty #x20000
   :extra-data
   (map 'byte-vector #'char-code "Sepolia, Athens, Attica, Greece!")))

(defun holesky-genesis-preset ()
  (%make-built-in-genesis-preset
   :name :holesky
   :config (holesky-chain-config)
   :expected-hash
   (hash32-from-hex
    "0xb5f7f912443c940f21fd611f12828d75b534364ed9e95ca4e307729a4661bde4")
   :allocation-path (genesis-allocation-path :holesky)
   :nonce #x1234
   :timestamp 1695902100
   :gas-limit #x17d7840
   :difficulty 1))

(defun hoodi-genesis-preset ()
  (%make-built-in-genesis-preset
   :name :hoodi
   :config (hoodi-chain-config)
   :expected-hash
   (hash32-from-hex
    "0xbbe312868b376a3001692a646dd2d7d1e4406380dfd86b98aa8a34d1557c971b")
   :allocation-path (genesis-allocation-path :hoodi)
   :nonce #x1234
   :timestamp 1742212800
   :gas-limit #x2255100
   :difficulty 1))

(defun find-built-in-genesis-preset (name)
  (case (if (stringp name)
            (intern (string-upcase name) :keyword)
            name)
    (:mainnet (mainnet-genesis-preset))
    (:sepolia (sepolia-genesis-preset))
    (:holesky (holesky-genesis-preset))
    (:hoodi (hoodi-genesis-preset))
    (otherwise
     (block-validation-fail "Unknown built-in genesis preset ~A" name))))

(defun read-binary-file (path)
  (with-open-file (stream path :direction :input
                               :element-type '(unsigned-byte 8))
    (let ((bytes (make-byte-vector (file-length stream))))
      (read-sequence bytes stream)
      bytes)))

(defun genesis-integer-to-fixed-bytes (value size)
  (let ((bytes (make-byte-vector size)))
    (loop for index downfrom (1- size) to 0
          do (setf (aref bytes index) (logand value #xff)
                   value (ash value -8)))
    (unless (zerop value)
      (block-validation-fail "Genesis integer exceeds ~D bytes" size))
    bytes))

(defun prealloc-storage-from-rlp-object (value)
  (loop for entry in (rlp-list-items value)
        for fields = (rlp-list-items entry)
        collect
        (cons (make-hash32
               (rlp-bytes-field (first fields) "Genesis storage key"))
              (bytes-to-integer
               (rlp-bytes-field
                (second fields) "Genesis storage value")))))

(defun prealloc-account-from-rlp-object (value)
  (let* ((fields (rlp-list-items value))
         (misc (when (= 3 (length fields))
                 (rlp-list-items (third fields)))))
    (unless (member (length fields) '(2 3))
      (block-validation-fail
       "Genesis preallocation entry must contain two or three fields"))
    (make-genesis-account
     :address
     (make-address
      (genesis-integer-to-fixed-bytes
       (rlp-uint-field (first fields) "Genesis address") 20))
     :balance (rlp-uint-field (second fields) "Genesis balance")
     :nonce (if misc
                (rlp-uint-field (first misc) "Genesis nonce")
                0)
     :code (if misc
               (rlp-bytes-field (second misc) "Genesis code")
               (make-byte-vector 0))
     :storage (if misc
                  (prealloc-storage-from-rlp-object (third misc))
                  nil))))

(defun built-in-genesis-alloc (preset)
  (mapcar #'prealloc-account-from-rlp-object
          (rlp-list-items
           (rlp-decode-one
            (read-binary-file
             (built-in-genesis-preset-allocation-path preset))))))

(defun built-in-genesis-header (preset &key state-root)
  (unless state-root
    (block-validation-fail
     "Built-in genesis header construction requires a computed state root"))
  (let* ((config (built-in-genesis-preset-config preset))
         (timestamp (built-in-genesis-preset-timestamp preset))
         (header
           (make-block-header
            :parent-hash (zero-hash32)
            :ommers-hash +empty-ommers-hash+
            :beneficiary (zero-address)
            :state-root state-root
            :transactions-root +empty-trie-hash+
            :receipts-root +empty-trie-hash+
            :logs-bloom (make-byte-vector 256)
            :difficulty (built-in-genesis-preset-difficulty preset)
            :number 0
            :gas-limit (built-in-genesis-preset-gas-limit preset)
            :gas-used 0
            :timestamp timestamp
            :extra-data (built-in-genesis-preset-extra-data preset)
            :mix-hash (zero-hash32)
            :nonce
            (uint64-to-8-byte-vector
             (built-in-genesis-preset-nonce preset) "Genesis nonce"))))
    (when (chain-config-london-p config 0)
      (setf (block-header-base-fee-per-gas header) +initial-base-fee+))
    (when (chain-config-shanghai-p config 0 timestamp)
      (setf (block-header-withdrawals-root header) (withdrawal-list-root '())))
    (when (chain-config-cancun-p config 0 timestamp)
      (setf (block-header-parent-beacon-root header) (zero-hash32)
            (block-header-excess-blob-gas header) 0
            (block-header-blob-gas-used header) 0))
    (when (chain-config-prague-p config 0 timestamp)
      (setf (block-header-requests-hash header)
            (execution-requests-hash '())))
    header))

(defun built-in-genesis-block (preset &key state-root)
  (genesis-block-from-genesis-header
   (built-in-genesis-header preset :state-root state-root)))
