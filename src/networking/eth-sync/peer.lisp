(in-package #:ethereum-lisp.eth-sync)

;;;; Driving the eth wire protocol over a live RLPx connection.
;;;;
;;;; Once the devp2p Hello exchange has negotiated a shared eth capability at
;;;; some message-id offset, the two peers exchange an eth Status to confirm
;;;; they are on the same chain. After that the connection carries eth requests
;;;; and responses, with base-protocol Ping/Pong keepalives answered inline so a
;;;; long-lived session stays up.

(defstruct (eth-peer (:constructor %make-eth-peer))
  connection
  eth-offset
  remote-status
  (request-counter 0))

(defun eth-peer-next-request-id (peer)
  "Return a fresh eth request id for PEER (a per-session ascending counter)."
  (setf (eth-peer-request-counter peer)
        (logand (1+ (eth-peer-request-counter peer)) #xffffffffffffffff)))

(defun eth-peer-remote-public-key (peer)
  "The peer's 64-byte static public key, learned during the RLPx handshake."
  (rlpx-connection-remote-public-key (eth-peer-connection peer)))

;;; Message transport: eth message ids ride the wire at OFFSET+id, and the base
;;; protocol's own traffic is handled transparently.

(defun eth-wire-send (connection offset eth-message-id payload)
  "Send an eth message over CONNECTION at the negotiated OFFSET (compressed)."
  (rlpx-connection-write-message connection (+ offset eth-message-id) payload))

(defun eth-wire-read (connection offset)
  "Read the next eth message from CONNECTION, returning (VALUES ETH-ID PAYLOAD).

Base-protocol traffic is handled inline: a Ping is answered with a Pong and the
read continues, a Pong is ignored, and a Disconnect signals RLPX-DISCONNECT.
Only subprotocol messages are returned to the caller."
  (loop
    (multiple-value-bind (code payload)
        (rlpx-connection-read-message connection)
      (cond
        ((= code +devp2p-message-ping+) (rlpx-send-pong connection))
        ((= code +devp2p-message-pong+) nil)
        ((= code +devp2p-message-disconnect+)
         (error 'rlpx-disconnect :reason (decode-devp2p-disconnect payload)))
        ((< code offset)
         (error "unexpected base-protocol message id ~D below eth offset ~D"
                code offset))
        (t (return (values (- code offset) payload)))))))

(defun eth-peer-send (peer eth-message-id payload)
  "Send an eth message to PEER."
  (eth-wire-send (eth-peer-connection peer) (eth-peer-eth-offset peer)
                 eth-message-id payload))

(defun eth-peer-read (peer)
  "Read the next eth message from PEER, returning (VALUES ETH-ID PAYLOAD)."
  (eth-wire-read (eth-peer-connection peer) (eth-peer-eth-offset peer)))

;;; The eth Status handshake.

(defun eth-build-status (config genesis-hash head-number head-timestamp
                         best-hash total-difficulty
                         &key network-id (genesis-timestamp 0))
  "Assemble our eth Status from the chain CONFIG and the current head.

NETWORK-ID defaults to the config's chain id. The fork id is derived from the
config at (HEAD-NUMBER, HEAD-TIMESTAMP)."
  (make-eth-status
   :version +eth-protocol-version+
   :network-id (or network-id (chain-config-chain-id config))
   :total-difficulty total-difficulty
   :best-hash (ensure-byte-vector best-hash)
   :genesis-hash (ensure-byte-vector genesis-hash)
   :fork-id (chain-config-eth-fork-id config genesis-hash head-number
                                      head-timestamp genesis-timestamp)))

(defun eth-validate-peer-status (ours theirs)
  "Signal an error unless the peer's Status THEIRS is compatible with OURS.

Requires the protocol version, network id, and genesis hash to match; genesis
plus network identify the chain. A fuller EIP-2124 fork-id compatibility check
is left to a later pass. Returns THEIRS on success."
  (unless (= (eth-status-version ours) (eth-status-version theirs))
    (error "eth version mismatch: ours ~D, peer ~D"
           (eth-status-version ours) (eth-status-version theirs)))
  (unless (= (eth-status-network-id ours) (eth-status-network-id theirs))
    (error "eth network mismatch: ours ~D, peer ~D"
           (eth-status-network-id ours) (eth-status-network-id theirs)))
  (unless (bytes= (eth-status-genesis-hash ours) (eth-status-genesis-hash theirs))
    (error "eth genesis mismatch: peer is on a different chain"))
  theirs)

(defun eth-peer-handshake (connection eth-offset our-status)
  "Exchange eth Status over CONNECTION and return a validated ETH-PEER.

Sends OUR-STATUS, reads the peer's, and validates version, network, and genesis
before returning the peer. Both sides send before reading, so there is no
deadlock."
  (eth-wire-send connection eth-offset +eth-message-status+
                 (encode-eth-status our-status))
  (multiple-value-bind (eth-id payload) (eth-wire-read connection eth-offset)
    (unless (= eth-id +eth-message-status+)
      (error "expected eth Status (0x00) but got eth message id ~D" eth-id))
    (let ((peer-status (decode-eth-status payload)))
      (eth-validate-peer-status our-status peer-status)
      (%make-eth-peer :connection connection
                      :eth-offset eth-offset
                      :remote-status peer-status))))

(defun eth-peer-connect (connection hello our-status)
  "Run the devp2p Hello exchange then the eth Status handshake over CONNECTION.

HELLO is our devp2p Hello, which must advertise the eth capability. Returns the
ETH-PEER, or errors if the peer does not share eth."
  (multiple-value-bind (peer-hello shared) (rlpx-exchange-hello connection hello)
    (declare (ignore peer-hello))
    (let ((eth (rlpx-shared-capability-named shared "eth")))
      (unless eth
        (error "peer does not support the eth capability"))
      (eth-peer-handshake connection (rlpx-shared-capability-offset eth)
                          our-status))))
