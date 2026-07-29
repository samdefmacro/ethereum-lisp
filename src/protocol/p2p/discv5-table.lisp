(in-package #:ethereum-lisp.discv5)

;;;; Discovery v5.1 Kademlia table and authenticated message service.
;;;;
;;;; Entries retain signed ENRs and observed UDP endpoints. Records learned
;;;; through NODES are unvalidated until an authenticated handshake arrives
;;;; from their claimed node ID at that endpoint. Only validated entries are
;;;; served, preventing reflection through unverified third-party addresses.

(defconstant +discv5-bucket-size+ 16)

(defstruct (discv5-routing-entry
            (:constructor make-discv5-routing-entry
                (&key node-id record host port validated-p last-seen-at)))
  node-id
  record
  host
  port
  validated-p
  last-seen-at)

(defstruct (discv5-routing-table
            (:constructor %make-discv5-routing-table
                (self-id self-record buckets)))
  self-id
  self-record
  buckets)

(defun make-discv5-routing-table (self-record)
  (let* ((record (decode-enr self-record))
         (id (discv5-node-id (enr-public-key record))))
    (%make-discv5-routing-table
     id (ensure-byte-vector self-record)
     (make-array 256 :initial-element nil))))

(defun discv5-log-distance (left right)
  "Return the discv5 log2 distance in [1, 256], or zero for identical IDs."
  (let ((distance
          (logxor (bytes-to-integer (ensure-byte-vector left))
                  (bytes-to-integer (ensure-byte-vector right)))))
    (integer-length distance)))

(defun discv5-routing-bucket (table node-id)
  (let ((distance
          (discv5-log-distance
           (discv5-routing-table-self-id table) node-id)))
    (and (plusp distance) (1- distance))))

(defun discv5-routing-table-entry (table node-id)
  (let ((bucket (discv5-routing-bucket table node-id)))
    (and bucket
         (find node-id (aref (discv5-routing-table-buckets table) bucket)
               :key #'discv5-routing-entry-node-id :test #'equalp))))

(defun discv5-routing-table-count (table &key validated-only)
  (loop for bucket across (discv5-routing-table-buckets table)
        sum (count-if (lambda (entry)
                        (or (not validated-only)
                            (discv5-routing-entry-validated-p entry)))
                      bucket)))

(defun discv5-private-ip-p (ip)
  (let ((ip (ensure-byte-vector ip)))
    (cond
      ((= 4 (length ip))
       (let ((a (aref ip 0)) (b (aref ip 1)))
         (or (= a 10) (= a 127)
             (and (= a 169) (= b 254))
             (and (= a 172) (<= 16 b 31))
             (and (= a 192) (= b 168)))))
      ((= 16 (length ip))
       ;; ::1, fc00::/7 and fe80::/10.
       (or (and (every #'zerop (subseq ip 0 15)) (= 1 (aref ip 15)))
           (= #xfc (logand #xfe (aref ip 0)))
           (and (= #xfe (aref ip 0)) (= #x80 (logand #xc0 (aref ip 1))))))
      (t nil))))

(defun discv5-valid-endpoint-p (ip port)
  "Whether IP/PORT is a syntactically usable unicast UDP endpoint."
  (let ((ip (ensure-byte-vector ip)))
    (and (member (length ip) '(4 16))
         (integerp port) (<= 1 port 65535)
         (not (every #'zerop ip))
         (if (= 4 (length ip))
             (< (aref ip 0) 224)
             (/= #xff (aref ip 0))))))

(defun discv5-valid-relay-endpoint-p (ip port requester-ip)
  "Validate a relayed endpoint. Public requesters never receive private nodes."
  (and (discv5-valid-endpoint-p ip port)
       (or (null requester-ip)
           (discv5-private-ip-p requester-ip)
           (not (discv5-private-ip-p ip)))))

(defun discv5-record-endpoint (record)
  (let* ((ip4 (enr-value record "ip"))
         (ip6 (enr-value record "ip6"))
         (ip (or ip4 ip6))
         (port-value (if ip4 (enr-value record "udp")
                         (enr-value record "udp6")))
         (port (and port-value
                    (bytes-to-integer (ensure-byte-vector port-value)))))
    (values ip port)))

(defun discv5-routing-table-put-record
    (table record-bytes &key host port validated-p (now 0))
  "Verify and insert an ENR. Older/equal records never replace newer content.

HOST and PORT are the observed UDP endpoint for authenticated records. Without
them the advertised ENR endpoint is retained and the entry remains unvalidated."
  (let* ((record-bytes (ensure-byte-vector record-bytes))
         (record (decode-enr record-bytes))
         (node-id (discv5-node-id (enr-public-key record)))
         (bucket-index (discv5-routing-bucket table node-id)))
    (when bucket-index
      (multiple-value-bind (advertised-ip advertised-port)
          (discv5-record-endpoint record)
        (let ((endpoint-ip (or host advertised-ip))
              (endpoint-port (or port advertised-port)))
          (unless (and endpoint-ip
                       (discv5-valid-endpoint-p endpoint-ip endpoint-port))
            (error "discv5 ENR has no usable UDP endpoint"))
          (let* ((bucket
                   (aref (discv5-routing-table-buckets table) bucket-index))
                 (existing
                   (find node-id bucket
                         :key #'discv5-routing-entry-node-id :test #'equalp)))
            (cond
              (existing
               (let ((old-seq (enr-seq
                               (decode-enr
                                (discv5-routing-entry-record existing)))))
                 (when (> (enr-seq record) old-seq)
                   (setf (discv5-routing-entry-record existing) record-bytes))
                 (when validated-p
                   (setf (discv5-routing-entry-host existing) endpoint-ip
                         (discv5-routing-entry-port existing) endpoint-port
                         (discv5-routing-entry-validated-p existing) t))
                 (setf (discv5-routing-entry-last-seen-at existing) now)
                 (setf (aref (discv5-routing-table-buckets table) bucket-index)
                       (cons existing (remove existing bucket)))
                 existing))
              ((< (length bucket) +discv5-bucket-size+)
               (let ((entry
                       (make-discv5-routing-entry
                        :node-id node-id :record record-bytes
                        :host endpoint-ip :port endpoint-port
                        :validated-p (and validated-p t)
                        :last-seen-at now)))
                 (push entry
                       (aref (discv5-routing-table-buckets table) bucket-index))
                 entry))
              (t nil))))))))

(defun discv5-routing-table-bootstrap (table records &key (now 0))
  "Load trusted seed ENRs as candidates. A handshake must still validate each
observed endpoint before it can be returned in NODES."
  (loop for record in records
        for entry = (handler-case
                        (discv5-routing-table-put-record table record :now now)
                      (error () nil))
        when entry collect entry))

(defun discv5-routing-table-at-distances
    (table distances &key (limit +discv5-bucket-size+) requester-ip)
  "Return validated ENRs from the requested buckets. Distance zero means self."
  (let ((records '()))
    (when (member 0 distances)
      (push (discv5-routing-table-self-record table) records))
    (dolist (distance distances)
      (when (<= 1 distance 256)
        (dolist (entry
                 (aref (discv5-routing-table-buckets table) (1- distance)))
          (when (and (discv5-routing-entry-validated-p entry)
                     (discv5-valid-relay-endpoint-p
                      (discv5-routing-entry-host entry)
                      (discv5-routing-entry-port entry)
                      requester-ip))
            (push (discv5-routing-entry-record entry) records)))))
    (let ((ordered (nreverse records)))
      (subseq ordered 0 (min limit (length ordered))))))

(defun discv5-accept-nodes
    (table response responder-id requested-distances &key requester-ip (now 0))
  "Validate NODES records against the FINDNODE distances before admission."
  (unless (<= 1 (discv5-nodes-total response) 255)
    (error "discv5 NODES total is outside [1, 255]"))
  (let ((accepted '()))
    (dolist (record-bytes (discv5-nodes-records response))
      (handler-case
          (let* ((record (decode-enr record-bytes))
                 (node-id (discv5-node-id (enr-public-key record)))
                 (distance (discv5-log-distance responder-id node-id)))
            (unless (member distance requested-distances)
              (error "discv5 NODES record is outside requested distances"))
            (multiple-value-bind (ip port) (discv5-record-endpoint record)
              (unless (discv5-valid-relay-endpoint-p ip port requester-ip)
                (error "discv5 NODES record endpoint is not relayable"))
              (let ((entry
                      (discv5-routing-table-put-record
                       table record-bytes :now now)))
                (when entry (push entry accepted)))))
        ;; One hostile record does not discard other valid records in a packet.
        (error () nil)))
    (nreverse accepted)))

(defun discv5-record-sequence-for (table node-id)
  (let ((entry (discv5-routing-table-entry table node-id)))
    (and entry
         (enr-seq (decode-enr (discv5-routing-entry-record entry))))))

(defun discv5-nodes-message-batches (request-id records)
  ;; Keep ample room for the largest handshake-independent packet header and
  ;; GCM tag. The wire encoder remains the final 1280-byte guard.
  (let ((batches '())
        (current '())
        (size 0))
    (dolist (record records)
      (when (and current (> (+ size (length record)) 1100))
        (push (nreverse current) batches)
        (setf current nil size 0))
      (push record current)
      (incf size (length record)))
    (when current (push (nreverse current) batches))
    (let* ((batches (or (nreverse batches) (list nil)))
           (total (length batches)))
      (mapcar (lambda (batch)
                (make-discv5-nodes
                 :request-id request-id :total total :records batch))
              batches))))

(defun discv5-serve-message
    (table message source-id source-ip source-port
     &key requested-distances (now 0))
  "Serve one authenticated core message.

Returns response messages and REMOTE-ENR-STALE-P. The latter tells the driver to
request distance zero when PING/PONG advertises a newer remote ENR sequence."
  (etypecase message
    (discv5-ping
     (values
      (list
       (make-discv5-pong
        :request-id (discv5-ping-request-id message)
        :enr-seq (enr-seq
                  (decode-enr (discv5-routing-table-self-record table)))
        :recipient-ip source-ip
        :recipient-port source-port))
      (> (discv5-ping-enr-seq message)
         (or (discv5-record-sequence-for table source-id) -1))))
    (discv5-pong
     (values nil
             (> (discv5-pong-enr-seq message)
                (or (discv5-record-sequence-for table source-id) -1))))
    (discv5-findnode
     (values
      (discv5-nodes-message-batches
       (discv5-findnode-request-id message)
       (discv5-routing-table-at-distances
        table (discv5-findnode-distances message)
        :requester-ip source-ip))
      nil))
    (discv5-nodes
     (unless requested-distances
       (error "discv5 NODES requires the corresponding requested distances"))
     (discv5-accept-nodes
      table message source-id requested-distances
      :requester-ip source-ip :now now)
     (values nil nil))))
