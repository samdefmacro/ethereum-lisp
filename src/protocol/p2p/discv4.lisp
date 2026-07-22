(in-package #:ethereum-lisp.p2p)

;;;; Node Discovery Protocol v4 (discv4).
;;;;
;;;; discv4 runs over UDP and lets a node find peers to dial. Every packet is
;;;;
;;;;   packet = hash(32) || signature(65) || packet-type(1) || packet-data
;;;;
;;;; where signature = secp256k1 sign of keccak256(type || data), and
;;;; hash = keccak256(signature || type || data). The sender's node id is the
;;;; public key recovered from the signature, so packets are self-authenticating.
;;;; This file is the packet codec; the UDP transport and discovery driver ride
;;;; on top of it.

(defconstant +discv4-version+ 4)
(defconstant +discv4-max-packet-size+ 1280
  "discv4 datagrams must fit in a single unfragmented UDP packet.")

(defconstant +discv4-packet-ping+ #x01)
(defconstant +discv4-packet-pong+ #x02)
(defconstant +discv4-packet-find-node+ #x03)
(defconstant +discv4-packet-neighbors+ #x04)
(defconstant +discv4-packet-enr-request+ #x05)
(defconstant +discv4-packet-enr-response+ #x06)

(defconstant +discv4-packet-header-size+ 98
  "hash(32) + signature(65) + type(1) before the packet data.")

(defun discv4-type-octet (type)
  (let ((octet (make-byte-vector 1)))
    (setf (aref octet 0) type)
    octet))

(defun encode-discv4-packet (private-key type data)
  "Sign and frame a discv4 packet of TYPE carrying DATA (already-RLP bytes).

Returns hash || signature || type || data, signed with PRIVATE-KEY."
  (let* ((type-and-data (concat-bytes (discv4-type-octet type)
                                      (ensure-byte-vector data)))
         (signature (secp256k1-sign (keccak-256 type-and-data) private-key))
         (signed (concat-bytes signature type-and-data))
         (hash (keccak-256 signed))
         (packet (concat-bytes hash signed)))
    (when (> (length packet) +discv4-max-packet-size+)
      (error "discv4 packet of ~D bytes exceeds the ~D-byte limit"
             (length packet) +discv4-max-packet-size+))
    packet))

(defun decode-discv4-packet (packet)
  "Verify and split a discv4 PACKET.

Returns (VALUES TYPE DATA SENDER-NODE-ID), where SENDER-NODE-ID is the 64-byte
public key recovered from the signature and DATA is the raw RLP body. Signals on
an oversize, truncated, or badly-hashed packet, or a signature that recovers no
key."
  (let ((packet (ensure-byte-vector packet)))
    (when (> (length packet) +discv4-max-packet-size+)
      (error "discv4 packet exceeds the ~D-byte limit" +discv4-max-packet-size+))
    (when (<= (length packet) +discv4-packet-header-size+)
      (error "discv4 packet is too short to carry a body"))
    (let ((hash (subseq packet 0 32))
          (signature (subseq packet 32 97))
          (signed (subseq packet 32))
          (type-and-data (subseq packet 97))
          (type (aref packet 97))
          (data (subseq packet 98)))
      (unless (bytes= hash (keccak-256 signed))
        (error "discv4 packet hash does not match its contents"))
      (let ((sender (secp256k1-recover-public-key
                     (keccak-256 type-and-data)
                     (aref signature 64)
                     (bytes-to-integer (subseq signature 0 32))
                     (bytes-to-integer (subseq signature 32 64)))))
        (unless sender
          (error "discv4 packet signature does not recover a node id"))
        (values type data sender)))))

;;; Endpoints: [ip, udp-port, tcp-port]. IP is 4 or 16 raw bytes; ports are
;;; minimal big-endian integers (a zero port encodes as the empty string).

(defstruct (discv4-endpoint (:constructor make-discv4-endpoint (ip udp-port tcp-port)))
  ip
  udp-port
  tcp-port)

(defun discv4-endpoint-rlp-object (endpoint)
  (make-rlp-list (ensure-byte-vector (discv4-endpoint-ip endpoint))
                 (integer-to-minimal-bytes (discv4-endpoint-udp-port endpoint))
                 (integer-to-minimal-bytes (discv4-endpoint-tcp-port endpoint))))

(defun discv4-endpoint-from-rlp-object (value)
  (let ((items (rlp-list-items value)))
    (make-discv4-endpoint
     (ensure-byte-vector (first items))
     (bytes-to-integer (ensure-byte-vector (second items)))
     (bytes-to-integer (ensure-byte-vector (third items))))))

;;; Ping (0x01): [version, from, to, expiration, ...].

(defstruct (discv4-ping
            (:constructor make-discv4-ping
                (&key (version +discv4-version+) from to expiration)))
  version
  from
  to
  expiration)

(defun encode-discv4-ping (ping)
  (rlp-encode
   (make-rlp-list
    (integer-to-minimal-bytes (discv4-ping-version ping))
    (discv4-endpoint-rlp-object (discv4-ping-from ping))
    (discv4-endpoint-rlp-object (discv4-ping-to ping))
    (integer-to-minimal-bytes (discv4-ping-expiration ping)))))

(defun decode-discv4-ping (data)
  (let ((items (rlp-list-items (rlp-decode (ensure-byte-vector data)
                                           :allow-trailing t))))
    (make-discv4-ping
     :version (bytes-to-integer (ensure-byte-vector (first items)))
     :from (discv4-endpoint-from-rlp-object (second items))
     :to (discv4-endpoint-from-rlp-object (third items))
     :expiration (bytes-to-integer (ensure-byte-vector (fourth items))))))

;;; Pong (0x02): [to, ping-hash, expiration, ...]. PING-HASH is the 32-byte hash
;;; of the Ping packet being answered, which is the endpoint proof.

(defstruct (discv4-pong (:constructor make-discv4-pong (&key to ping-hash expiration)))
  to
  ping-hash
  expiration)

(defun encode-discv4-pong (pong)
  (rlp-encode
   (make-rlp-list
    (discv4-endpoint-rlp-object (discv4-pong-to pong))
    (ensure-byte-vector (discv4-pong-ping-hash pong))
    (integer-to-minimal-bytes (discv4-pong-expiration pong)))))

(defun decode-discv4-pong (data)
  (let ((items (rlp-list-items (rlp-decode (ensure-byte-vector data)
                                           :allow-trailing t))))
    (make-discv4-pong
     :to (discv4-endpoint-from-rlp-object (first items))
     :ping-hash (ensure-byte-vector (second items))
     :expiration (bytes-to-integer (ensure-byte-vector (third items))))))

;;; FindNode (0x03): [target, expiration]. TARGET is a 64-byte public key; the
;;; recipient answers with the neighbors closest to it.

(defstruct (discv4-find-node (:constructor make-discv4-find-node (&key target expiration)))
  target
  expiration)

(defun encode-discv4-find-node (find-node)
  (rlp-encode
   (make-rlp-list
    (ensure-byte-vector (discv4-find-node-target find-node))
    (integer-to-minimal-bytes (discv4-find-node-expiration find-node)))))

(defun decode-discv4-find-node (data)
  (let ((items (rlp-list-items (rlp-decode (ensure-byte-vector data)
                                           :allow-trailing t))))
    (make-discv4-find-node
     :target (ensure-byte-vector (first items))
     :expiration (bytes-to-integer (ensure-byte-vector (second items))))))

;;; Neighbors (0x04): [[[ip, udp, tcp, node-id]...], expiration]. A full reply
;;; may be split across several packets since 16 nodes exceed the size limit.

(defstruct (discv4-node (:constructor make-discv4-node (ip udp-port tcp-port node-id)))
  ip
  udp-port
  tcp-port
  node-id)

(defun discv4-node-rlp-object (node)
  (make-rlp-list (ensure-byte-vector (discv4-node-ip node))
                 (integer-to-minimal-bytes (discv4-node-udp-port node))
                 (integer-to-minimal-bytes (discv4-node-tcp-port node))
                 (ensure-byte-vector (discv4-node-node-id node))))

(defun discv4-node-from-rlp-object (value)
  (let ((items (rlp-list-items value)))
    (make-discv4-node
     (ensure-byte-vector (first items))
     (bytes-to-integer (ensure-byte-vector (second items)))
     (bytes-to-integer (ensure-byte-vector (third items)))
     (ensure-byte-vector (fourth items)))))

(defstruct (discv4-neighbors (:constructor make-discv4-neighbors (&key nodes expiration)))
  nodes
  expiration)

(defun encode-discv4-neighbors (neighbors)
  (rlp-encode
   (make-rlp-list
    (apply #'make-rlp-list
           (mapcar #'discv4-node-rlp-object (discv4-neighbors-nodes neighbors)))
    (integer-to-minimal-bytes (discv4-neighbors-expiration neighbors)))))

(defun decode-discv4-neighbors (data)
  (let ((items (rlp-list-items (rlp-decode (ensure-byte-vector data)
                                           :allow-trailing t))))
    (make-discv4-neighbors
     :nodes (mapcar #'discv4-node-from-rlp-object (rlp-list-items (first items)))
     :expiration (bytes-to-integer (ensure-byte-vector (second items))))))
