(defparameter *ethereum-lisp-script-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun ethereum-lisp-script-arguments ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (rest args)))
    args)
  #-sbcl
  nil)

(defun ethereum-lisp-script-load-file (relative-path)
  (load (merge-pathnames relative-path *ethereum-lisp-script-root*)))

(require :asdf)

(dolist (relative-path
         '("src/packages.lisp"
           "src/bytes.lisp"
           "src/hex.lisp"
           "src/database.lisp"
           "src/telemetry.lisp"
           "src/types.lisp"
           "src/rlp.lisp"
           "src/crypto.lisp"
           "src/trie-encoding.lisp"
           "src/trie.lisp"
           "src/chain-config.lisp"
           "src/genesis.lisp"
           "src/core-constants.lisp"
           "src/accounts.lisp"
           "src/transactions.lisp"
           "src/receipts.lisp"
           "src/txpool-types.lisp"
           "src/blocks.lisp"
           "src/consensus-validation.lisp"
           "src/block-access-list.lisp"
           "src/genesis-block.lisp"
           "src/kzg.lisp"
           "src/engine-payloads.lisp"
           "src/chain-store-types.lisp"
           "src/chain-store-memory.lisp"
           "src/txpool.lisp"
           "src/chain-store-persistence.lisp"
           "src/block-validation.lisp"
           "src/engine-payload-status.lisp"
           "src/engine-rpc-protocol.lisp"
           "src/engine-rpc.lisp"
           "src/public-rpc.lisp"
           "src/engine-rpc-http.lisp"
           "src/state.lisp"
           "src/evm.lisp"
           "src/execution.lisp"
           "src/cli.lisp"))
  (ethereum-lisp-script-load-file relative-path))

(let ((exit-code (ethereum-lisp.cli:main (ethereum-lisp-script-arguments))))
  #+sbcl
  (sb-ext:exit :code exit-code)
  #-sbcl
  (uiop:quit exit-code))
