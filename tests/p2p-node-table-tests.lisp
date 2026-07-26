(in-package #:ethereum-lisp.test)

;;;; The discovery routing table and the replies built from it. All pure: no
;;;; socket, no thread, and `now` is an integer the test chooses.

(defun node-table-test-id (n)
  (node-id-from-private-key (+ 1000 n)))

(deftest discv4-log-distance-buckets-by-highest-differing-bit
  (:layer :unit :module :p2p)
  (let ((a (node-table-test-id 1))
        (b (node-table-test-id 2)))
    ;; A node has no distance from itself, so it files into no bucket -- which
    ;; is what keeps us out of our own routing table.
    (is (null (discv4-log-distance a a)))
    (let ((distance (discv4-log-distance a b)))
      (is (integerp distance))
      (is (<= 0 distance 255))
      ;; Distance is symmetric, as an XOR metric must be.
      (is (= distance (discv4-log-distance b a))))))

(deftest discv4-table-records-and-expires-endpoint-proofs
  (:layer :unit :module :p2p)
  (let* ((table (make-discv4-node-table (node-table-test-id 0)))
         (peer (node-table-test-id 1)))
    (is (discv4-table-put table peer "127.0.0.1" 30303 30304 100 :bonded t))
    (is (= 1 (discv4-table-count table)))
    (is (discv4-table-bonded-p table peer 100))
    ;; A proof does not last forever; the node has to answer again eventually.
    (is (discv4-table-bonded-p table peer (+ 100 +discv4-bond-lifetime-seconds+ -1)))
    (is (not (discv4-table-bonded-p table peer
                                    (+ 100 +discv4-bond-lifetime-seconds+ 1))))
    ;; Re-seeing it refreshes the proof and the endpoint.
    (discv4-table-put table peer "10.0.0.9" 40404 40405 100000 :bonded t)
    (is (discv4-table-bonded-p table peer 100000))
    (is (= 1 (discv4-table-count table)))
    (let ((entry (discv4-table-entry table peer)))
      (is (string= "10.0.0.9" (discv4-table-entry-host entry)))
      (is (= 40404 (discv4-table-entry-udp-port entry))))
    ;; A node merely mentioned to us is remembered but never bonded.
    (let ((hearsay (node-table-test-id 2)))
      (is (discv4-table-put table hearsay "10.0.0.2" 1 2 100))
      (is (not (discv4-table-bonded-p table hearsay 100))))
    ;; A node that stops answering is eventually dropped.
    (dotimes (i 3) (is (not (discv4-table-note-failure table peer))))
    (is (discv4-table-note-failure table peer))
    (is (null (discv4-table-entry table peer)))))

(deftest discv4-table-keeps-known-nodes-over-newcomers
  (:layer :unit :module :p2p)
  ;; A full bucket refuses a newcomer rather than evicting an incumbent. A node
  ;; that has been answering for hours is worth more than one just heard of,
  ;; and this is what stops a flood of fresh addresses displacing the table.
  (let* ((self (node-table-test-id 0))
         (table (make-discv4-node-table self))
         (bucket-peers '()))
    ;; Collect enough ids that share one bucket to fill it.
    (loop for n from 1 below 4000
          while (< (length bucket-peers) (1+ +discv4-bucket-size+))
          do (let ((id (node-table-test-id n)))
               (when (eql 255 (discv4-log-distance self id))
                 (push id bucket-peers))))
    (is (> (length bucket-peers) +discv4-bucket-size+))
    (let ((incumbents (subseq bucket-peers 0 +discv4-bucket-size+))
          (newcomer (nth +discv4-bucket-size+ bucket-peers)))
      (dolist (id incumbents)
        (is (discv4-table-put table id "127.0.0.1" 30303 30303 100 :bonded t)))
      (is (= +discv4-bucket-size+ (discv4-table-count table)))
      ;; The bucket is full: the newcomer is refused, nobody is evicted.
      (is (null (discv4-table-put table newcomer "127.0.0.1" 1 1 200 :bonded t)))
      (is (= +discv4-bucket-size+ (discv4-table-count table)))
      (is (discv4-table-entry table (first incumbents)))
      ;; Room reappears when an incumbent goes.
      (discv4-table-remove table (first incumbents))
      (is (discv4-table-put table newcomer "127.0.0.1" 1 1 300 :bonded t)))))

(deftest discv4-table-closest-offers-only-proven-nodes
  (:layer :unit :module :p2p)
  ;; This answers a stranger's FindNode. Passing on an address that never proved
  ;; itself would make us a party to whatever it was claimed for.
  (let* ((table (make-discv4-node-table (node-table-test-id 0)))
         (target (node-table-test-id 500)))
    (dotimes (n 8)
      (discv4-table-put table (node-table-test-id (+ 1 n)) "127.0.0.1"
                        30303 30303 100 :bonded t))
    (dotimes (n 4)
      (discv4-table-put table (node-table-test-id (+ 100 n)) "10.0.0.1"
                        30303 30303 100))
    (is (= 12 (discv4-table-count table)))
    (is (= 8 (discv4-table-count table :bonded-only t)))
    (let ((closest (discv4-table-closest table target)))
      (is (= 8 (length closest)))
      (is (every #'discv4-table-entry-bonded-at closest))
      ;; Nearest first, so a lookup actually converges.
      (let ((distances (mapcar (lambda (entry)
                                 (ethereum-lisp.p2p:discv4-node-distance
                                  (discv4-table-entry-node-id entry) target))
                               closest)))
        (is (equal distances (sort (copy-list distances) #'<)))))
    ;; And the limit is honoured.
    (is (= 3 (length (discv4-table-closest table target :limit 3))))))

(deftest discv4-serves-ping-and-refuses-unbonded-queries
  (:layer :unit :module :p2p)
  (let* ((our-key #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (their-key #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (their-id (node-id-from-private-key their-key))
         (table (make-discv4-node-table (node-id-from-private-key our-key)))
         (endpoint (ethereum-lisp.p2p:discv4-endpoint-for-host "127.0.0.1" 30303 30303))
         (ping (ethereum-lisp.p2p:encode-discv4-packet
                their-key ethereum-lisp.p2p:+discv4-packet-ping+
                (ethereum-lisp.p2p:encode-discv4-ping
                 (ethereum-lisp.p2p:make-discv4-ping :from endpoint :to endpoint
                                   :expiration (ethereum-lisp.p2p:discv4-expiration))))))
    ;; A FindNode from a stranger is REFUSED. Answering it would make us an
    ;; amplifier: the reply is far larger than the forged request that asks for
    ;; it, and its source address can be anyone's.
    (let ((find-node (ethereum-lisp.p2p:encode-discv4-packet
                      their-key ethereum-lisp.p2p:+discv4-packet-find-node+
                      (ethereum-lisp.p2p:encode-discv4-find-node
                       (ethereum-lisp.p2p:make-discv4-find-node
                        :target their-id
                        :expiration (ethereum-lisp.p2p:discv4-expiration))))))
      (multiple-value-bind (type data sender) (ethereum-lisp.p2p:decode-discv4-packet find-node)
        (declare (ignore type))
        (is (null (discv4-serve-find-node our-key table data sender 100)))))
    ;; A Ping is answered, and proves the sender's endpoint.
    (multiple-value-bind (type data sender) (ethereum-lisp.p2p:decode-discv4-packet ping)
      (declare (ignore type))
      (let ((pong (discv4-serve-ping our-key table ping data sender
                                     "127.0.0.1" 100)))
        (is (not (null pong)))
        (multiple-value-bind (pong-type pong-data) (ethereum-lisp.p2p:decode-discv4-packet pong)
          (is (= ethereum-lisp.p2p:+discv4-packet-pong+ pong-type))
          ;; The Pong echoes the hash of THAT ping, which is what stops a replay
          ;; of an old one being accepted as an answer.
          (is (bytes= (subseq ping 0 32)
                      (ethereum-lisp.p2p:discv4-pong-ping-hash (ethereum-lisp.p2p:decode-discv4-pong pong-data)))))))
    (is (discv4-table-bonded-p table their-id 100))
    ;; Now bonded, the same FindNode is answered -- with our other known nodes.
    (dotimes (n 6)
      (discv4-table-put table (node-table-test-id n) "127.0.0.1" 30303 30303
                        100 :bonded t))
    (let ((find-node (ethereum-lisp.p2p:encode-discv4-packet
                      their-key ethereum-lisp.p2p:+discv4-packet-find-node+
                      (ethereum-lisp.p2p:encode-discv4-find-node
                       (ethereum-lisp.p2p:make-discv4-find-node :target (node-table-test-id 1)
                                              :expiration (ethereum-lisp.p2p:discv4-expiration))))))
      (multiple-value-bind (type data sender) (ethereum-lisp.p2p:decode-discv4-packet find-node)
        (declare (ignore type))
        (let ((packets (discv4-serve-find-node our-key table data sender 100)))
          (is (not (null packets)))
          ;; Split across datagrams: a full bucket does not fit in one.
          (is (every (lambda (packet) (<= (length packet)
                                          ethereum-lisp.p2p:+discv4-max-packet-size+))
                     packets))
          (let ((total (reduce #'+ packets :key
                               (lambda (packet)
                                 (multiple-value-bind (type data)
                                     (ethereum-lisp.p2p:decode-discv4-packet packet)
                                   (declare (ignore type))
                                   (length (ethereum-lisp.p2p:discv4-neighbors-nodes
                                            (ethereum-lisp.p2p:decode-discv4-neighbors data))))))))
            (is (= 7 total))))))
    ;; An ENRRequest from the same bonded peer is answered with a real record.
    (let ((request (ethereum-lisp.p2p:encode-discv4-packet
                    their-key ethereum-lisp.p2p:+discv4-packet-enr-request+
                    (ethereum-lisp.p2p:encode-discv4-enr-request
                     (ethereum-lisp.p2p:make-discv4-enr-request
                      :expiration (ethereum-lisp.p2p:discv4-expiration))))))
      (multiple-value-bind (type data sender) (ethereum-lisp.p2p:decode-discv4-packet request)
        (declare (ignore type))
        (let ((response (discv4-serve-enr-request our-key table data sender
                                                  request 100)))
          (is (not (null response)))
          (multiple-value-bind (response-type response-data)
              (ethereum-lisp.p2p:decode-discv4-packet response)
            (is (= ethereum-lisp.p2p:+discv4-packet-enr-response+ response-type))
            (let ((record (ethereum-lisp.p2p:discv4-enr-response-record
                           (ethereum-lisp.p2p:decode-discv4-enr-response response-data))))
              ;; It verifies, and it is ours.
              (is (bytes= (node-id-from-private-key our-key)
                          (ethereum-lisp.p2p:enr-public-key (ethereum-lisp.p2p:decode-enr record)))))))))))

(deftest devnet-discovery-server-answers-a-real-client
  (:layer :integration :module :p2p :requires-local-sockets t)
  ;; The node is findable now, not merely able to find. A real discv4 client
  ;; pings it over loopback UDP, gets a Pong, and its FindNode is then answered
  ;; with a node the server knows -- the whole discovery handshake.
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0 :public-port 0
                :p2p-host "127.0.0.1" :p2p-port 0 :max-peers 4))
         (controller (ethereum-lisp.cli::make-devnet-shutdown-controller))
         (client-key #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (server-error nil)
         (probe (ethereum-lisp.p2p:discv4-make-socket :host "127.0.0.1" :port 0))
         (port nil)
         (thread nil))
    ;; Claim a real ephemeral UDP port for the responder to bind.
    (let ((bound (ethereum-lisp.p2p:discv4-make-socket :host "127.0.0.1" :port 0)))
      (setf port (nth-value 1 (sb-bsd-sockets:socket-name bound)))
      (ignore-errors (sb-bsd-sockets:socket-close bound)))
    (setf (ethereum-lisp.cli::devnet-node-p2p-port node) port)
    (unwind-protect
         (let ((endpoint (ethereum-lisp.p2p:discv4-endpoint-for-host
                          "127.0.0.1" port port)))
           (setf thread (ethereum-lisp.cli:devnet-start-discovery-server-thread
                         node controller
                         (lambda (condition) (setf server-error condition))))
           (is (not (null thread)))
           ;; Ping, and expect a Pong echoing our packet's hash.
           (let ((ping (ethereum-lisp.p2p:encode-discv4-packet
                        client-key ethereum-lisp.p2p:+discv4-packet-ping+
                        (ethereum-lisp.p2p:encode-discv4-ping
                         (ethereum-lisp.p2p:make-discv4-ping
                          :from endpoint :to endpoint
                          :expiration (ethereum-lisp.p2p:discv4-expiration))))))
             (ethereum-lisp.p2p:discv4-send-to probe ping "127.0.0.1" port)
             (let ((reply (ethereum-lisp.p2p:discv4-receive probe 10)))
               (is (not (null reply)))
               (multiple-value-bind (type data sender)
                   (ethereum-lisp.p2p:decode-discv4-packet reply)
                 (is (= ethereum-lisp.p2p:+discv4-packet-pong+ type))
                 ;; It really is the node answering, with our ping's hash.
                 (is (bytes= (node-id-from-private-key
                              (ethereum-lisp.cli::devnet-node-node-key node))
                             sender))
                 (is (bytes= (subseq ping 0 32)
                             (ethereum-lisp.p2p:discv4-pong-ping-hash
                              (ethereum-lisp.p2p:decode-discv4-pong data)))))))
           ;; Give the responder a node to hand out, then ask for it. Being
           ;; bonded by the Ping above is what makes this answerable at all.
           (ethereum-lisp.cli::call-with-devnet-peer-table
            node
            (lambda ()
              (discv4-table-put (ethereum-lisp.cli:devnet-node-discovery-table node)
                                (node-table-test-id 42) "10.1.2.3" 30303 30303
                                (unix-time) :bonded t)))
           (let ((find-node (ethereum-lisp.p2p:encode-discv4-packet
                             client-key ethereum-lisp.p2p:+discv4-packet-find-node+
                             (ethereum-lisp.p2p:encode-discv4-find-node
                              (ethereum-lisp.p2p:make-discv4-find-node
                               :target (node-table-test-id 42)
                               :expiration (ethereum-lisp.p2p:discv4-expiration))))))
             (ethereum-lisp.p2p:discv4-send-to probe find-node "127.0.0.1" port)
             (let ((reply (ethereum-lisp.p2p:discv4-receive probe 10)))
               (is (not (null reply)))
               (multiple-value-bind (type data)
                   (ethereum-lisp.p2p:decode-discv4-packet reply)
                 (is (= ethereum-lisp.p2p:+discv4-packet-neighbors+ type))
                 (let* ((nodes (ethereum-lisp.p2p:discv4-neighbors-nodes
                                (ethereum-lisp.p2p:decode-discv4-neighbors data)))
                        (target (find (node-table-test-id 42) nodes
                                      :key #'ethereum-lisp.p2p:discv4-node-node-id
                                      :test #'bytes=)))
                   ;; The client itself is in the table too, having just bonded
                   ;; by pinging us -- so assert the target is among the
                   ;; neighbours rather than that it is the only one.
                   (is (plusp (length nodes)))
                   (is (not (null target)))
                   (is (string= "10.1.2.3"
                                (ethereum-lisp.p2p:discv4-ip-string
                                 (ethereum-lisp.p2p:discv4-node-ip target)))))))))
      (ethereum-lisp.cli:devnet-shutdown-request controller)
      (when thread
        (is (not (eq :timeout (sb-thread:join-thread thread :timeout 15
                                                            :default :timeout)))))
      (is (null server-error))
      (ignore-errors (sb-bsd-sockets:socket-close probe)))))
