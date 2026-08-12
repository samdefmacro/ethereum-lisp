(in-package #:ethereum-lisp.genesis)

;;;; Canonical public-network genesis presets.
;;;;
;;;; Allocation assets are the decoded prealloc constants from pinned geth
;;;; 38271784c2b31926563806da9a2e023b88f5e7a8, core/genesis_alloc.go. Keeping
;;;; the compact RLP avoids parsing megabytes of JSON at node startup.

(defstruct (built-in-genesis-preset
            (:constructor %make-built-in-genesis-preset
                (&key name config expected-hash allocation-path nonce timestamp
                      gas-limit difficulty extra-data bootnodes)))
  name
  config
  expected-hash
  allocation-path
  (nonce 0 :type (integer 0 *))
  (timestamp 0 :type (integer 0 *))
  (gas-limit +genesis-gas-limit+ :type (integer 0 *))
  (difficulty +genesis-difficulty+ :type (integer 0 *))
  (extra-data (make-byte-vector 0) :type byte-vector)
  (bootnodes '() :type list))

;; Canonical execution-layer discovery-v4 bootnodes from go-ethereum
;; 38271784c2b31926563806da9a2e023b88f5e7a8, params/bootnodes.go. Keep these
;; with the genesis presets: a public-network preset that cannot bootstrap is
;; not a complete network configuration.
(defparameter +mainnet-bootnodes+
  '("enode://d860a01f9722d78051619d1e2351aba3f43f943f6f00718d1b9baa4101932a1f5011f16bb2b1bb35db20d6fe28fa0bf09636d26a87d31de9ec6203eeedb1f666@18.138.108.67:30303"
    "enode://22a8232c3abc76a16ae9d6c3b164f98775fe226f0917b0ca871128a74a8e9630b458460865bab457221f1d448dd9791d24c4e5d88786180ac185df813a68d4de@3.209.45.79:30303"
    "enode://2b252ab6a1d0f971d9722cb839a42cb81db019ba44c08754628ab4a823487071b5695317c8ccd085219c3a03af063495b2f1da8d18218da2d6a82981b45e6ffc@65.108.70.101:30303"
    "enode://4aeb4ab6c14b23e2c4cfdce879c04b0748a20d8e9b59e25ded2a08143e265c6c25936e74cbc8e641e3312ca288673d91f2f93f8e277de3cfa444ecdaaf982052@157.90.35.166:30303"))

(defparameter +sepolia-bootnodes+
  '("enode://4e5e92199ee224a01932a377160aa432f31d0b351f84ab413a8e0a42f4f36476f8fb1cbe914af0d9aef0d51665c214cf653c651c4bbd9d5550a934f241f1682b@138.197.51.181:30303"
    "enode://143e11fb766781d22d92a2e33f8f104cddae4411a122295ed1fdb6638de96a6ce65f5b7c964ba3763bba27961738fef7d3ecc739268f3e5e771fb4c87b6234ba@146.190.1.103:30303"
    "enode://8b61dc2d06c3f96fddcbebb0efb29d60d3598650275dc469c22229d3e5620369b0d3dedafd929835fe7f489618f19f456fe7c0df572bf2d914a9f4e006f783a9@170.64.250.88:30303"
    "enode://10d62eff032205fcef19497f35ca8477bea0eadfff6d769a147e895d8b2b8f8ae6341630c645c30f5df6e67547c03494ced3d9c5764e8622a26587b083b028e8@139.59.49.206:30303"
    "enode://9e9492e2e8836114cc75f5b929784f4f46c324ad01daf87d956f98b3b6c5fcba95524d6e5cf9861dc96a2c8a171ea7105bb554a197455058de185fa870970c7c@138.68.123.152:30303"))

(defparameter +holesky-bootnodes+
  '("enode://ac906289e4b7f12df423d654c5a962b6ebe5b3a74cc9e06292a85221f9a64a6f1cfdd6b714ed6dacef51578f92b34c60ee91e9ede9c7f8fadc4d347326d95e2b@146.190.13.128:30303"
    "enode://a3435a0155a3e837c02f5e7f5662a2f1fbc25b48e4dc232016e1c51b544cb5b4510ef633ea3278c0e970fa8ad8141e2d4d0f9f95456c537ff05fdf9b31c15072@178.128.136.233:30303"))

(defparameter +hoodi-bootnodes+
  '("enode://2112dd3839dd752813d4df7f40936f06829fc54c0e051a93967c26e5f5d27d99d886b57b4ffcc3c475e930ec9e79c56ef1dbb7d86ca5ee83a9d2ccf36e5c240c@134.209.138.84:30303"
    "enode://60203fcb3524e07c5df60a14ae1c9c5b24023ea5d47463dfae051d2c9f3219f309657537576090ca0ae641f73d419f53d8e8000d7a464319d4784acd7d2abc41@209.38.124.160:30303"
    "enode://8ae4a48101b2299597341263da0deb47cc38aa4d3ef4b7430b897d49bfa10eb1ccfe1655679b1ed46928ef177fbf21b86837bd724400196c508427a6f41602cd@134.199.184.23:30303"))

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
   :bootnodes (copy-list +mainnet-bootnodes+)
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
   :bootnodes (copy-list +sepolia-bootnodes+)
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
   :difficulty 1
   :bootnodes (copy-list +holesky-bootnodes+)))

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
   :difficulty 1
   :bootnodes (copy-list +hoodi-bootnodes+)))

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
