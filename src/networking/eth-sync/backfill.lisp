(in-package #:ethereum-lisp.eth-sync)

;;;; Filling a gap in the chain, backwards.
;;;;
;;;; A consensus client hands us a block whose parent we do not have. We cannot
;;;; execute it -- there is no state to execute it against -- so it is buffered
;;;; and the client is told SYNCING. Something then has to go and fetch what is
;;;; missing, and that is this file.
;;;;
;;;; THE DIRECTION IS THE WHOLE POINT. Forward download works from a number we
;;;; already have; here we know only a HASH, somewhere ahead of us, and nothing
;;;; about the numbers in between -- the chain may have reorged, so the block at
;;;; our head's number plus one is not necessarily an ancestor of the target. So
;;;; the walk runs BACKWARDS from the target, following parent hashes, until it
;;;; reaches a block we already hold. Only then is the direction reversed and
;;;; the blocks executed oldest-first, because execution needs its parent's
;;;; state and so has exactly one possible order.
;;;;
;;;; A HASH-ORIGIN REVERSE REQUEST IS NOT A NUMBER RANGE. Asking a peer for
;;;; headers by hash means we get that peer's own branch, which is what we want:
;;;; the target came from the consensus client, and the branch that leads to it
;;;; is the branch we must import.

(defconstant +eth-backfill-batch-size+ 192
  "How many headers one backward request asks for. Our policy.")

(defconstant +eth-backfill-max-headers+ 100000
  "How far back a single gap-fill will walk before giving up. Our policy, and a
bound rather than a target: a gap this large means we are not merely behind, and
grinding backwards forever would be worse than reporting that.")

(define-condition eth-sync-backfill-peer-error (simple-error) ()
  (:documentation
   "A peer-specific backfill refusal or malformed backfill response."))

(defun eth-sync-backfill-peer-fail (control &rest arguments)
  "Signal a peer-scoped backfill failure that another target may recover from."
  (error 'eth-sync-backfill-peer-error
         :format-control control
         :format-arguments arguments))

(defun eth-sync-collect-backfill-headers
    (peer target-hash known-hash-p
     &key (batch-size +eth-backfill-batch-size+)
          (max-headers +eth-backfill-max-headers+))
  "Walk back from TARGET-HASH until KNOWN-HASH-P accepts a parent, returning the
headers OLDEST FIRST.

KNOWN-HASH-P is called with a parent hash as raw bytes and answers whether we
already hold that block. Returns NIL when the target is one we already have.

Signals when the walk exceeds MAX-HEADERS, or when the peer stops answering
before we reach common ground: an incomplete run of headers is worse than none,
because executing a chain whose base we cannot verify is exactly the thing the
backwards walk exists to prevent."
  (when (funcall known-hash-p target-hash)
    (return-from eth-sync-collect-backfill-headers nil))
  (unless (and (plusp batch-size) (plusp max-headers))
    (error "backfill bounds must be positive"))
  (let ((collected '())
        (next-hash target-hash)
        (next-number nil)
        (count 0))
    (loop
      (let ((headers (eth-peer-get-block-headers
                      peer :origin-hash next-hash :amount batch-size
                           :reverse t)))
        (when (null headers)
          (eth-sync-backfill-peer-fail
           "peer stopped answering ~D headers into a backfill toward ~A"
           count (bytes-to-hex next-hash)))
        (unless (and (listp headers) (<= (length headers) batch-size))
          (eth-sync-backfill-peer-fail
           "peer exceeded the requested backfill header batch size"))
        ;; The peer answers newest-first; keep that order while walking and
        ;; reverse once at the end. Validate the entire hash-linked reverse
        ;; response before accepting any body: a hash-origin request does not
        ;; authorize the peer to substitute an unrelated or repeated branch.
        (dolist (header headers)
          (unless (block-header-p header)
            (eth-sync-backfill-peer-fail
             "peer returned a non-header during backfill"))
          (unless (bytes= next-hash
                          (hash32-bytes (block-header-hash header)))
            (eth-sync-backfill-peer-fail
             "peer backfill header does not match the requested hash"))
          (when (and next-number
                     (/= next-number (block-header-number header)))
            (eth-sync-backfill-peer-fail
             "peer backfill headers are not consecutive"))
          (when (>= count max-headers)
            (eth-sync-backfill-peer-fail
             "backfill toward ~A exceeded ~D headers without reaching a ~
              block we hold"
             (bytes-to-hex target-hash) max-headers))
          (push header collected)
          (incf count)
          (let ((parent (hash32-bytes (block-header-parent-hash header))))
            (when (funcall known-hash-p parent)
              (return-from eth-sync-collect-backfill-headers collected))
            (when (zerop (block-header-number header))
              (eth-sync-backfill-peer-fail
               "peer backfill reached genesis without common ground"))
            (setf next-hash parent
                  next-number (1- (block-header-number header)))))
        (when (>= count max-headers)
          (eth-sync-backfill-peer-fail
           "backfill toward ~A exceeded ~D headers without reaching a ~
            block we hold"
           (bytes-to-hex target-hash) max-headers))))))

(defun eth-sync-import-headers-with-bodies
    (peer headers import-block &key (batch-size +eth-backfill-batch-size+)
                                    progress)
  "Fetch the bodies for HEADERS and import each block in order.

HEADERS must be oldest first, because a block can only be executed once its
parent has been. Returns how many were imported."
  (let ((imported 0))
    (loop while headers
          do (let* ((batch (subseq headers 0 (min (length headers) batch-size)))
                    (hashes (mapcar (lambda (header)
                                      (hash32-bytes (block-header-hash header)))
                                    batch))
                    (bodies (eth-peer-get-block-bodies peer hashes)))
               (unless (listp bodies)
                 (eth-sync-backfill-peer-fail
                  "peer returned a non-list body response during backfill"))
               (unless (= (length bodies) (length batch))
                 (eth-sync-backfill-peer-fail
                  "peer returned ~D bodies for ~D headers during backfill"
                  (length bodies) (length batch)))
               (loop for header in batch
                     for body in bodies
                     do (unless (typep body 'eth-block-body)
                          (eth-sync-backfill-peer-fail
                           "peer returned a non-body during backfill"))
                        ;; This is the peer-owned bundle boundary.  Translate
                        ;; only its deterministic commitment failure; assembly
                        ;; and IMPORT-BLOCK remain outside the handler so local
                        ;; storage, capability, and program failures propagate.
                        (handler-case
                            (eth-sync-validate-body header body)
                          (ethereum-lisp.validation:block-validation-error
                              (condition)
                            (eth-sync-backfill-peer-fail
                             "peer returned a body with invalid commitments: ~A"
                             (ethereum-lisp.validation:block-validation-error-message
                              condition))))
                        (let ((block (eth-sync-assemble-block header body)))
                          (funcall import-block block)
                          (incf imported)
                          (when progress (funcall progress block))))
               (setf headers (nthcdr (length batch) headers))))
    imported))

(defun eth-sync-fill-gap (peer target-hash known-hash-p import-block
                          &key (batch-size +eth-backfill-batch-size+)
                               (max-headers +eth-backfill-max-headers+)
                               progress)
  "Fetch and import everything between what we hold and TARGET-HASH.

This is the whole gap-fill: walk back to common ground, then execute forward.
Returns how many blocks were imported, which is 0 when the target is already
ours."
  (let ((headers (eth-sync-collect-backfill-headers
                  peer target-hash known-hash-p
                  :batch-size batch-size :max-headers max-headers)))
    (if (null headers)
        0
        (eth-sync-import-headers-with-bodies peer headers import-block
                                             :batch-size batch-size
                                             :progress progress))))
