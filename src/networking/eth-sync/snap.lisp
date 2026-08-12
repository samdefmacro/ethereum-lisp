(in-package #:ethereum-lisp.eth-sync)

;;;; Live snap/1 client adapter over the negotiated capability.

(defun eth-peer-snap-sync-source (peer)
  "Return a snap importer source backed by PEER's multiplexed snap/1 stream."
  (unless (and (eth-peer-snap-offset peer)
               (= +snap-protocol-version+ (eth-peer-snap-version peer)))
    (error "peer did not negotiate snap/1"))
  (ethereum-lisp.snap-sync:make-snap-sync-source
   :account-range
   (lambda (request)
     (eth-peer-snap-request peer +snap-message-get-account-range+ request))
   :storage-ranges
   (lambda (request)
     (eth-peer-snap-request peer +snap-message-get-storage-ranges+ request))
   :bytecodes
   (lambda (request)
     (eth-peer-snap-request peer +snap-message-get-bytecodes+ request))
   :trie-nodes
   (lambda (request)
     (eth-peer-snap-request peer +snap-message-get-trie-nodes+ request))))
