(in-package #:ethereum-lisp.eth-sync)

;;;; The block-download driver (initial block download).
;;;;
;;;; Given a peer, download blocks forward from a starting number: request
;;;; headers in batches, fetch the matching bodies, assemble each block, and
;;;; hand it to an import callback in order. Keeping the import behind a callback
;;;; leaves this layer independent of the chain store — the node supplies a
;;;; callback that executes and commits each block.

(defconstant +eth-sync-default-batch-size+ 192
  "How many block headers to request at once during download.")

(defun eth-sync-validate-header-batch (headers origin-number previous-header)
  "Reject a header reply that does not answer the requested contiguous range."
  (loop with parent = previous-header
        for header in headers
        for expected from origin-number
        do (unless (= expected (block-header-number header))
             (error "peer returned header ~D where block ~D was requested"
                    (block-header-number header) expected))
           (when parent
             (unless (hash32= (block-header-parent-hash header)
                              (block-header-hash parent))
               (error "peer returned a non-contiguous header at block ~D"
                      expected)))
           (setf parent header))
  t)

(defun eth-sync-validate-body (header body)
  "Reject a body whose commitments do not match HEADER before import."
  (ethereum-lisp.execution:validate-block-body-commitments-before-execution
   (eth-block-body-transactions body)
   header
   :ommers (eth-block-body-ommers body)
   :withdrawals (eth-block-body-withdrawals body)
   :withdrawals-supplied-p
   (eth-block-body-withdrawals-present-p body))
  t)

(defun eth-sync-assemble-block (header body)
  "Assemble a block from a downloaded HEADER and its BODY.

Uses make-block-from-parts, which trusts the header's committed roots rather
than recomputing them, since the header was received rather than built here."
  (make-block-from-parts
   :header header
   :transactions (eth-block-body-transactions body)
   :ommers (eth-block-body-ommers body)
   :withdrawals (eth-block-body-withdrawals body)
   :withdrawals-present-p (eth-block-body-withdrawals-present-p body)))

(defun eth-sync-download-blocks
    (peer import-block
     &key (start-number 1)
          (batch-size +eth-sync-default-batch-size+)
          (max-blocks nil)
          (progress nil))
  "Download blocks forward from START-NUMBER, importing each in order.

Requests headers from PEER in batches, fetches their bodies, assembles each
block, and calls IMPORT-BLOCK on it. IMPORT-BLOCK receives one assembled block
and is expected to execute and commit it; an error it signals propagates and
stops the download. PROGRESS, if given, is called with each block after import.
Stops when the peer returns no further headers, or after MAX-BLOCKS blocks.
Returns the number of blocks imported."
  (let ((next start-number)
        (imported 0)
        (previous-header nil))
    (loop
      (let ((amount (if max-blocks
                        (min batch-size (- max-blocks imported))
                        batch-size)))
        (when (<= amount 0)
          (return imported))
        (let ((headers (eth-peer-get-block-headers
                        peer :origin-number next :amount amount)))
          (when (null headers)
            (return imported))
          (eth-sync-validate-header-batch headers next previous-header)
          (let* ((hashes (mapcar (lambda (h) (hash32-bytes (block-header-hash h)))
                                 headers))
                 (bodies (eth-peer-get-block-bodies peer hashes)))
            (unless (= (length bodies) (length headers))
              (error "peer returned ~D bodies for ~D headers"
                     (length bodies) (length headers)))
            (loop for header in headers
                  for body in bodies
                  do (eth-sync-validate-body header body)
                     (let ((block (eth-sync-assemble-block header body)))
                       (funcall import-block block)
                       (incf imported)
                       (when progress (funcall progress block))))
            (setf previous-header (car (last headers)))
            (setf next (+ next (length headers)))
            ;; A short batch means the peer has no more blocks past its tip.
            (when (< (length headers) amount)
              (return imported))))))))
