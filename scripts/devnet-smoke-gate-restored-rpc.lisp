(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-devnet-smoke-gate-restored-rpc-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun load-devnet-smoke-gate-restored-rpc-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-devnet-smoke-gate-restored-rpc-root*)))

(dolist (relative-path
         '("scripts/devnet-smoke-gate-restored-public-rpc.lisp"
           "scripts/devnet-smoke-gate-restored-engine-rpc.lisp"
           "scripts/devnet-smoke-gate-restored-cache-rpc.lisp"
           "scripts/devnet-smoke-gate-transaction-runtime.lisp"
           "scripts/devnet-smoke-gate-restored-txpool-rpc.lisp"
           "scripts/devnet-smoke-gate-restored-side-reorg-rpc.lisp"))
  (load-devnet-smoke-gate-restored-rpc-file relative-path))
