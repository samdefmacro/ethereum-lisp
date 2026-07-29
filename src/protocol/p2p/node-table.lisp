(in-package #:ethereum-lisp.p2p)

;;;; The Kademlia routing table: who we know, organised by distance.
;;;;
;;;; Discovery needs to answer two questions. "Who is near this target?" is what
;;;; a peer asks us with FindNode, and answering it is what makes us useful to
;;;; the network rather than merely present in it. "Who should I talk to next?"
;;;; is what our own crawl asks. A flat set answers neither well: it grows
;;;; without bound, and the nodes it keeps are whichever happened to arrive
;;;; first rather than the ones that make the network navigable.
;;;;
;;;; Nodes are filed into buckets by LOG DISTANCE — the position of the highest
;;;; differing bit between two node ids' hashes, so bucket 255 holds the half of
;;;; the network furthest away and bucket 0 the nearest possible neighbour. Each
;;;; bucket holds at most K entries. That shape is what makes a lookup converge
;;;; in a logarithmic number of hops: every step at least halves the remaining
;;;; distance.
;;;;
;;;; NOTHING HERE LOCKS OR READS A CLOCK. NOW is always an argument, exactly as
;;;; in the peer table and the dial scheduler, so every decision is checkable as
;;;; a table and a caller composes several under one acquisition.
;;;;
;;;; A NODE IS ONLY USEFUL ONCE IT HAS ANSWERED US. A discv4 endpoint proof is
;;;; what stops the table being filled with addresses that were merely claimed
;;;; by somebody else, so an entry is not offered to a peer asking FindNode
;;;; until it has been bonded.

(defconstant +discv4-bucket-size+ 16
  "How many nodes one bucket holds (Kademlia's k). Our policy.")

(defconstant +discv4-bucket-count+ 256
  "One bucket per possible log distance over a 256-bit id space.")

(defconstant +discv4-bond-lifetime-seconds+ 43200
  "How long an endpoint proof stays good: 12 hours. Our policy. Re-proving on
every exchange would double the traffic of every lookup.")

(defstruct (discv4-table-entry
            (:constructor make-discv4-table-entry
                (&key node-id host udp-port tcp-port (bonded-at nil)
                      pending-ping-hash
                      (added-at 0) (last-seen-at 0) (failures 0))))
  "One known node. BONDED-AT is when it last proved it owns its endpoint; NIL
means it has only ever been mentioned to us by somebody else."
  node-id
  host
  udp-port
  tcp-port
  bonded-at
  pending-ping-hash
  added-at
  last-seen-at
  failures)

(defstruct (discv4-node-table
            (:constructor %make-discv4-node-table (self-id buckets)))
  "Known nodes, bucketed by log distance from our own id."
  self-id
  buckets)

(defun make-discv4-node-table (self-id)
  (%make-discv4-node-table
   (ensure-byte-vector self-id)
   (make-array +discv4-bucket-count+ :initial-element '())))

(defun discv4-log-distance (id-a id-b)
  "The bucket index for two node ids: the position of their highest differing
hash bit, or NIL when the ids are identical.

This is the whole reason a lookup converges. Two ids differing in their top bit
are in the furthest bucket and share nothing; two differing only in the last are
adjacent."
  (let ((distance (discv4-node-distance id-a id-b)))
    (if (zerop distance)
        nil
        (1- (integer-length distance)))))

(defun discv4-table-bucket-index (table node-id)
  (discv4-log-distance (discv4-node-table-self-id table) node-id))

(defun discv4-table-entry (table node-id)
  (let ((index (discv4-table-bucket-index table node-id)))
    (when index
      (find node-id (aref (discv4-node-table-buckets table) index)
            :key #'discv4-table-entry-node-id :test #'bytes=))))

(defun discv4-table-count (table &key bonded-only)
  (let ((count 0))
    (dotimes (index +discv4-bucket-count+ count)
      (dolist (entry (aref (discv4-node-table-buckets table) index))
        (when (or (not bonded-only) (discv4-table-entry-bonded-at entry))
          (incf count))))))

(defun discv4-table-bonded-p (table node-id now)
  "Whether NODE-ID has proved its endpoint recently enough to be trusted."
  (let ((entry (discv4-table-entry table node-id)))
    (and entry
         (discv4-table-entry-bonded-at entry)
         (< (- now (discv4-table-entry-bonded-at entry))
            +discv4-bond-lifetime-seconds+))))

(defun discv4-table-put (table node-id host udp-port tcp-port now
                         &key bonded)
  "Record a node, returning its entry, or NIL if the bucket was full.

An existing entry is refreshed and moved to the front, so a bucket is ordered
most-recently-seen first. A FULL bucket REFUSES the newcomer rather than
evicting anyone: a node that has been answering us for hours is worth more than
one we just heard of, and this is what stops a flood of fresh addresses from
displacing everything we know."
  (let ((index (discv4-table-bucket-index table node-id)))
    (when index
      (let* ((bucket (aref (discv4-node-table-buckets table) index))
             (existing (find node-id bucket
                             :key #'discv4-table-entry-node-id :test #'bytes=)))
        (cond
          (existing
           (setf (discv4-table-entry-host existing) host)
           (setf (discv4-table-entry-udp-port existing) udp-port)
           (setf (discv4-table-entry-tcp-port existing) tcp-port)
           (setf (discv4-table-entry-last-seen-at existing) now)
           (when bonded
             (setf (discv4-table-entry-bonded-at existing) now)
             (setf (discv4-table-entry-failures existing) 0))
           (setf (aref (discv4-node-table-buckets table) index)
                 (cons existing (remove existing bucket)))
           existing)
          ((< (length bucket) +discv4-bucket-size+)
           (let ((entry (make-discv4-table-entry
                         :node-id (ensure-byte-vector node-id)
                         :host host :udp-port udp-port :tcp-port tcp-port
                         :bonded-at (when bonded now)
                         :added-at now :last-seen-at now)))
             (setf (aref (discv4-node-table-buckets table) index)
                   (cons entry bucket))
             entry))
          (t nil))))))

(defun discv4-table-note-failure (table node-id)
  "Count a node that did not answer, and drop it once it has stopped answering
often enough. Returns T if it was dropped."
  (let ((entry (discv4-table-entry table node-id))
        (index (discv4-table-bucket-index table node-id)))
    (when entry
      (incf (discv4-table-entry-failures entry))
      (when (>= (discv4-table-entry-failures entry) 4)
        (setf (aref (discv4-node-table-buckets table) index)
              (remove entry (aref (discv4-node-table-buckets table) index)))
        t))))

(defun discv4-table-note-ping (table node-id ping-hash)
  "Remember the exact Ping NODE-ID must answer before it can become bonded."
  (let ((entry (discv4-table-entry table node-id)))
    (when entry
      (setf (discv4-table-entry-pending-ping-hash entry)
            (ensure-byte-vector ping-hash))
      entry)))

(defun discv4-table-accept-pong
    (table node-id host udp-port ping-hash now)
  "Bond NODE-ID only when PING-HASH answers our outstanding endpoint probe."
  (let ((entry (discv4-table-entry table node-id)))
    (when (and entry
               (string= host (discv4-table-entry-host entry))
               (= udp-port (discv4-table-entry-udp-port entry))
               (discv4-table-entry-pending-ping-hash entry)
               (bytes= ping-hash
                       (discv4-table-entry-pending-ping-hash entry)))
      (setf (discv4-table-entry-bonded-at entry) now
            (discv4-table-entry-last-seen-at entry) now
            (discv4-table-entry-failures entry) 0
            (discv4-table-entry-pending-ping-hash entry) nil)
      entry)))

(defun discv4-table-remove (table node-id)
  (let ((index (discv4-table-bucket-index table node-id))
        (entry (discv4-table-entry table node-id)))
    (when (and index entry)
      (setf (aref (discv4-node-table-buckets table) index)
            (remove entry (aref (discv4-node-table-buckets table) index)))
      entry)))

(defun discv4-table-entries (table &key bonded-only)
  (let ((entries '()))
    (dotimes (index +discv4-bucket-count+ entries)
      (dolist (entry (aref (discv4-node-table-buckets table) index))
        (when (or (not bonded-only) (discv4-table-entry-bonded-at entry))
          (push entry entries))))))

(defun discv4-table-closest (table target-id &key (limit +discv4-bucket-size+)
                                                  (bonded-only t) now)
  "The nodes nearest TARGET-ID, nearest first.

BONDED-ONLY by default, because this answers a stranger's FindNode: passing on
an address that has never proved itself would make us a party to whatever it was
claimed for."
  (let ((entries (sort (remove-if-not
                        (lambda (entry)
                          (or (not bonded-only)
                              (null now)
                              (discv4-table-bonded-p
                               table (discv4-table-entry-node-id entry) now)))
                        (discv4-table-entries table
                                             :bonded-only bonded-only))
                       #'<
                       :key (lambda (entry)
                              (discv4-node-distance
                               (discv4-table-entry-node-id entry) target-id)))))
    (subseq entries 0 (min (length entries) limit))))
