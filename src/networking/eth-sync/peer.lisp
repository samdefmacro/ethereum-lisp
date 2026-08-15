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
  eth-version
  shared-capabilities
  snap-offset
  snap-version
  snap-backend
  remote-status
  ;; Installed by the CLI before the session pump starts.  This callback only
  ;; wakes the node-wide coordinator after a validated block/range announcement;
  ;; it carries no target and therefore cannot grant sync authority.
  sync-notification-function
  ;; The peer's devp2p Hello: its client id, advertised capabilities, and the
  ;; TCP port it listens on. Kept because a peer manager reports it and because
  ;; the listen port is what makes a peer dialable back.
  remote-hello
  ;; The chain this peer's requests are answered from; NIL means we answer
  ;; nothing (see serve.lisp).
  serve-backend
  ;; Transaction hashes this peer announced that we have not fetched yet, as a
  ;; set (see gossip.lisp). NIL until the peer announces something.
  announced-hashes
  ;; Hashes this remote peer demonstrably knows, bounded in gossip.lisp. Used to
  ;; avoid reflecting its own transactions straight back to it.
  known-transaction-hashes
  ;; Block hashes announced for top-level draining by the session pump. Kept as
  ;; a FIFO list because ordering by the peer's announcement is useful.
  announced-block-hashes
  (request-counter 0))

(defun eth-peer-set-sync-notification-function (peer function)
  "Install FUNCTION as PEER's validated sync-announcement notification.

FUNCTION must take no arguments.  Install it before the session message loop
starts; an ETH-PEER remains single-thread-owned after that point.  NIL removes
the callback."
  (unless (typep peer 'eth-peer)
    (error "Sync notification requires an eth peer"))
  (unless (or (null function) (functionp function))
    (error "Sync notification callback must be a function or NIL"))
  (setf (eth-peer-sync-notification-function peer) function)
  peer)

(defun eth-peer-notify-sync-announcement (peer)
  (let ((function (eth-peer-sync-notification-function peer)))
    (when function
      (funcall function))))

(defun eth-peer-next-request-id (peer)
  "Return a fresh eth request id for PEER (a per-session ascending counter)."
  (setf (eth-peer-request-counter peer)
        (logand (1+ (eth-peer-request-counter peer)) #xffffffffffffffff)))

(defun eth-peer-remote-public-key (peer)
  "The peer's 64-byte static public key, learned during the RLPx handshake."
  (rlpx-connection-remote-public-key (eth-peer-connection peer)))

(defun eth-peer-remote-client-id (peer)
  "The peer's self-reported client id string, or NIL before the Hello is known."
  (let ((hello (eth-peer-remote-hello peer)))
    (when hello (devp2p-hello-client-id hello))))

(defun eth-peer-remote-capabilities (peer)
  "The capabilities the peer advertised, or NIL before the Hello is known."
  (let ((hello (eth-peer-remote-hello peer)))
    (when hello (devp2p-hello-capabilities hello))))

(defun eth-peer-remote-listen-port (peer)
  "The TCP port the peer says it listens on, or NIL if it advertised none.

A peer that reports 0 is telling us not to dial it back, so that reads as NIL
rather than as port zero."
  (let ((hello (eth-peer-remote-hello peer)))
    (when hello
      (let ((port (devp2p-hello-listen-port hello)))
        (when (and port (plusp port)) port)))))

;;; Message transport: eth message ids ride the wire at OFFSET+id, and the base
;;; protocol's own traffic is handled transparently.

(defun eth-wire-send (connection offset eth-message-id payload)
  "Send an eth message over CONNECTION at the negotiated OFFSET (compressed)."
  (rlpx-connection-write-message connection (+ offset eth-message-id) payload))

(defun eth-wire-read-once (connection offset &optional message-count)
  "Read exactly ONE devp2p message, returning (VALUES KIND ID PAYLOAD).

KIND is :ETH for a subprotocol message, whose ID has the offset already removed,
or :BASE for base-protocol traffic, whose ID is the raw devp2p id — leaving the
caller to answer a Ping and to decide what a Pong means. A Disconnect still
signals RLPX-DISCONNECT, since that ends the session either way.

This exists because ETH-WIRE-READ loops until a subprotocol message arrives, and
a session that is merely being kept alive never produces one. A caller that must
stay responsive between frames — to notice a shutdown, to time out an idle peer,
to send its own keepalive — has to see the Ping and Pong traffic, not block
inside a loop that swallows it."
  (multiple-value-bind (code payload)
      (rlpx-connection-read-message
       connection
       :max-frame-size (1+ +eth-max-message-size+)
       :max-message-size +eth-max-message-size+)
    (cond
      ((= code +devp2p-message-disconnect+)
       (error 'rlpx-disconnect :reason (decode-devp2p-disconnect payload)))
      ((< code offset)
       (when (> (length payload) +devp2p-max-message-size+)
         (error "devp2p base message contains ~D bytes, exceeding the ~D-byte limit"
                (length payload) +devp2p-max-message-size+))
       ;; Ping and Pong are the only base traffic a live session may carry; a
       ;; second Hello is a protocol error, and erroring on it is the behavior
       ;; ETH-WIRE-READ has always had.
       (unless (or (= code +devp2p-message-ping+)
                   (= code +devp2p-message-pong+))
         (error "unexpected base-protocol message id ~D below eth offset ~D"
                code offset))
       (values :base code payload))
      (t
       (let ((local-id (- code offset)))
         (when (and message-count (>= local-id message-count))
           (error "eth message id ~D is outside the negotiated ~D-id range"
                  local-id message-count))
         (values :eth local-id payload))))))

(defun eth-wire-read (connection offset &optional message-count)
  "Read the next eth message from CONNECTION, returning (VALUES ETH-ID PAYLOAD).

Base-protocol traffic is handled inline: a Ping is answered with a Pong and the
read continues, a Pong is ignored, and a Disconnect signals RLPX-DISCONNECT.
Only subprotocol messages are returned to the caller.

Because it loops, this BLOCKS between frames for as long as the peer sends only
keepalives. That is right for a caller waiting on a reply it has already asked
for, and wrong for a long-lived session loop, which should use
ETH-WIRE-READ-ONCE and handle the base traffic itself."
  (loop
    (multiple-value-bind (kind id payload)
        (eth-wire-read-once connection offset message-count)
      (if (eq kind :eth)
          (return (values id payload))
          (when (= id +devp2p-message-ping+)
            (rlpx-send-pong connection))))))

(defun eth-wire-read-negotiated-once (connection shared-capabilities)
  "Read one base, eth, or snap message using the negotiated capability map.

The returned KIND is :BASE, :ETH, or :SNAP and ID is relative to the selected
capability.  Resolution is range checked by the p2p layer, so an id immediately
past snap/1 (or past the selected eth version) is rejected instead of being
misclassified as that capability."
  (multiple-value-bind (code payload)
      (rlpx-connection-read-message
       connection
       :max-frame-size (1+ (max +eth-max-message-size+
                                +snap-max-message-size+))
       :max-message-size (max +eth-max-message-size+ +snap-max-message-size+))
    (when (= code +devp2p-message-disconnect+)
      (error 'rlpx-disconnect :reason (decode-devp2p-disconnect payload)))
    (multiple-value-bind (capability local-id)
        (rlpx-shared-capability-for-message-code shared-capabilities code)
      (cond
        ((null capability)
         (when (> (length payload) +devp2p-max-message-size+)
           (error "devp2p base message contains ~D bytes, exceeding the ~D-byte limit"
                  (length payload) +devp2p-max-message-size+))
         (unless (or (= code +devp2p-message-ping+)
                     (= code +devp2p-message-pong+))
           (error "unexpected devp2p base message id ~D" code))
         (values :base local-id payload))
        ((string= "eth" (rlpx-shared-capability-name capability))
         (values :eth local-id payload))
        ((string= "snap" (rlpx-shared-capability-name capability))
         (values :snap local-id payload))
        (t
         (error "negotiated capability ~S has no session dispatcher"
                (rlpx-shared-capability-name capability)))))))

(defun eth-peer-handle-base-message (peer id)
  (when (= id +devp2p-message-ping+)
    (rlpx-send-pong (eth-peer-connection peer)))
  t)

(defun eth-peer-send-snap (peer snap-message-id payload)
  "Send one snap/1 message, rejecting use when snap was not negotiated."
  (unless (eth-peer-snap-offset peer)
    (error "snap/1 was not negotiated with this peer"))
  (unless (and (integerp snap-message-id)
               (<= 0 snap-message-id)
               (< snap-message-id +snap-message-count+))
    (error "snap/1 message id ~S is outside the negotiated range"
           snap-message-id))
  (rlpx-connection-write-message
   (eth-peer-connection peer)
   (+ (eth-peer-snap-offset peer) snap-message-id)
   payload))

(defun eth-peer-serve-snap-message (peer snap-message-id payload)
  "Serve one snap/1 request and return true; responses return NIL."
  (when (member snap-message-id
                (list +snap-message-get-account-range+
                      +snap-message-get-storage-ranges+
                      +snap-message-get-bytecodes+
                      +snap-message-get-trie-nodes+))
    (let ((backend (eth-peer-snap-backend peer)))
      (unless backend
        (error "peer sent a snap/1 request although no snap server is installed"))
      (multiple-value-bind (response-id response)
          (snap-serve-request backend snap-message-id payload)
        (eth-peer-send-snap peer response-id response)))
    t))

(defun eth-peer-send (peer eth-message-id payload)
  "Send an eth message to PEER."
  (unless (and (integerp eth-message-id)
               (<= 0 eth-message-id)
               (< eth-message-id
                  (devp2p-capability-message-count
                   "eth" (eth-peer-eth-version peer))))
    (error "eth/~D message id ~S is outside the negotiated range"
           (eth-peer-eth-version peer) eth-message-id))
  (eth-wire-send (eth-peer-connection peer) (eth-peer-eth-offset peer)
                 eth-message-id payload))

(defun eth-peer-read (peer)
  "Read the next eth message from PEER, returning (VALUES ETH-ID PAYLOAD)."
  (loop
    (multiple-value-bind (kind id payload) (eth-peer-read-once peer)
      (case kind
        (:eth (return (values id payload)))
        (:snap
         (unless (eth-peer-serve-snap-message peer id payload)
           (error "unsolicited snap/1 response id ~D" id)))
        (:base (eth-peer-handle-base-message peer id))))))

(defun eth-peer-send-block-range-update (peer earliest latest latest-hash)
  "Send an eth/69 BlockRangeUpdate after validating the advertised range."
  (when (< (eth-peer-eth-version peer) +eth-protocol-version-69+)
    (error "BlockRangeUpdate requires eth/69 or later"))
  (eth-validate-block-range earliest latest latest-hash)
  (eth-peer-send
   peer
   +eth-message-block-range-update+
   (encode-eth-block-range-update
    (make-eth-block-range earliest latest latest-hash))))

(defun eth-peer-read-once (peer)
  "Read exactly one message from PEER, returning (VALUES KIND ID PAYLOAD).

See ETH-WIRE-READ-ONCE: this is the read a session loop uses, so that keepalive
traffic reaches the loop instead of being absorbed below it."
  (let ((shared (eth-peer-shared-capabilities peer)))
    (if shared
        (eth-wire-read-negotiated-once (eth-peer-connection peer) shared)
        (eth-wire-read-once (eth-peer-connection peer)
                            (eth-peer-eth-offset peer)
                            (devp2p-capability-message-count
                             "eth" (eth-peer-eth-version peer))))))

(defconstant +snap-max-skipped-messages+ 256
  "Maximum unrelated messages handled while awaiting one snap response.")

(defun eth-peer-snap-request (peer message-id request)
  "Send one typed snap/1 REQUEST and return its decoded matching response."
  (unless (member message-id
                  (list +snap-message-get-account-range+
                        +snap-message-get-storage-ranges+
                        +snap-message-get-bytecodes+
                        +snap-message-get-trie-nodes+))
    (error "snap/1 message id ~D is not a request" message-id))
  (let ((request-id (snap-request-id message-id request))
        (expected-id (1+ message-id)))
    (eth-peer-send-snap peer message-id (encode-snap-message message-id request))
    (dotimes (i +snap-max-skipped-messages+
                (error "no snap/1 response id ~D for request ~D after ~D messages"
                       expected-id request-id +snap-max-skipped-messages+))
      (multiple-value-bind (kind id payload) (eth-peer-read-once peer)
        (case kind
          (:base (eth-peer-handle-base-message peer id))
          (:eth (eth-peer-handle-message peer id payload))
          (:snap
           (if (= id expected-id)
               (let ((response (decode-snap-message id payload)))
                 (when (= request-id (snap-response-id id response))
                   (return response)))
               (unless (eth-peer-serve-snap-message peer id payload)
                 (error "unexpected snap/1 response id ~D while awaiting ~D"
                        id expected-id)))))))))

;;; The eth Status handshake.

(defun eth-build-status (config genesis-hash head-number head-timestamp
                         best-hash total-difficulty
                         &key network-id (genesis-timestamp 0))
  "Assemble our eth Status from the chain CONFIG and the current head.

NETWORK-ID defaults to the config's chain id. The fork id is derived from the
config at (HEAD-NUMBER, HEAD-TIMESTAMP)."
  (let ((best (ensure-byte-vector best-hash)))
    (make-eth-status
     :version +eth-protocol-version+
     :network-id (or network-id (chain-config-chain-id config))
     :total-difficulty total-difficulty
     :best-hash best
     :genesis-hash (ensure-byte-vector genesis-hash)
     :fork-id (chain-config-eth-fork-id config genesis-hash head-number
                                        head-timestamp genesis-timestamp)
     ;; eth/69 carries our served range and head instead of the total
     ;; difficulty; the head hash is the best hash and we serve from genesis.
     :earliest-block 0
     :latest-block head-number
     :latest-block-hash best)))

(defstruct (eth-chain-context
            (:constructor make-eth-chain-context
                (config genesis-hash head-number head-timestamp
                 &optional (genesis-timestamp 0))))
  "The local chain context needed to validate a peer's fork id during the eth
handshake."
  config
  genesis-hash
  head-number
  head-timestamp
  genesis-timestamp)

(defun eth-chain-context-fork-id (chain-context)
  "Our own EIP-2124 fork id for CHAIN-CONTEXT."
  (chain-config-eth-fork-id
   (eth-chain-context-config chain-context)
   (eth-chain-context-genesis-hash chain-context)
   (eth-chain-context-head-number chain-context)
   (eth-chain-context-head-timestamp chain-context)
   (eth-chain-context-genesis-timestamp chain-context)))

(defun eth-chain-context-record-pairs (chain-context)
  "The chain-specific ENR entries a node on this chain should advertise.

Only the `eth` fork-id entry today. Kept beside the predicate that reads other
nodes' entries because the two are one decision seen from both ends: a client
that filters on an entry it does not itself publish is asking of others exactly
what it refuses to supply, and would be filtered straight back out."
  (list (cons "eth" (eth-fork-id-enr-entry
                     (eth-chain-context-fork-id chain-context)))))

(defun eth-chain-context-record-compatible-p (chain-context record-value)
  "True when the `eth` ENR entry RECORD-VALUE belongs to a peer on our chain.

The predicate form of the handshake check, for deciding whether a discovered
node is worth a TCP connection at all. A node with no `eth` entry, or an
unreadable one, is NOT compatible: discv4 is one shared DHT carrying every
chain that uses it, so `I cannot tell' has to mean `not mine' or the filter
admits exactly the nodes it exists to exclude."
  (let ((fork-id (eth-fork-id-from-enr-entry record-value)))
    (and fork-id
         (handler-case
             (progn (validate-peer-fork-id
                     (eth-chain-context-config chain-context)
                     (eth-chain-context-genesis-hash chain-context)
                     (eth-chain-context-head-number chain-context)
                     (eth-chain-context-head-timestamp chain-context)
                     fork-id
                     (eth-chain-context-genesis-timestamp chain-context))
                    t)
           (eth-fork-id-mismatch () nil)))))

(defun eth-validate-peer-status (ours theirs &optional chain-context)
  "Signal an error unless the peer's Status THEIRS is compatible with OURS.

Requires the protocol version, network id, and genesis hash to match; genesis
plus network identify the chain. When CHAIN-CONTEXT is supplied, the peer's fork
id is additionally checked against our chain per EIP-2124. Returns THEIRS on
success."
  (unless (= (eth-status-version ours) (eth-status-version theirs))
    (error "eth version mismatch: ours ~D, peer ~D"
           (eth-status-version ours) (eth-status-version theirs)))
  (unless (= (eth-status-network-id ours) (eth-status-network-id theirs))
    (error "eth network mismatch: ours ~D, peer ~D"
           (eth-status-network-id ours) (eth-status-network-id theirs)))
  (unless (bytes= (eth-status-genesis-hash ours) (eth-status-genesis-hash theirs))
    (error "eth genesis mismatch: peer is on a different chain"))
  (when (>= (eth-status-version theirs) +eth-protocol-version-69+)
    (eth-validate-block-range
     (eth-status-earliest-block theirs)
     (eth-status-latest-block theirs)
     (eth-status-latest-block-hash theirs)))
  (when chain-context
    (validate-peer-fork-id (eth-chain-context-config chain-context)
                           (eth-chain-context-genesis-hash chain-context)
                           (eth-chain-context-head-number chain-context)
                           (eth-chain-context-head-timestamp chain-context)
                           (eth-status-fork-id theirs)
                           (eth-chain-context-genesis-timestamp chain-context)))
  theirs)

(defun eth-validate-block-range (earliest latest latest-hash)
  "Validate an eth/69 served range and return true."
  (unless (and (integerp earliest) (integerp latest)
               (<= 0 earliest latest))
    (error "eth block range is invalid: ~S through ~S" earliest latest))
  (let ((hash (ensure-byte-vector latest-hash)))
    (unless (and (= (length hash) 32)
                 (not (every #'zerop hash)))
      (error "eth block range latest hash must be a non-zero 32-byte hash")))
  t)

(defun eth-peer-handshake (connection eth-offset eth-version our-status
                           &key chain-context serve-backend remote-hello
                                shared-capabilities snap-backend)
  "Exchange eth Status over CONNECTION and return a validated ETH-PEER.

Encodes OUR-STATUS in the negotiated ETH-VERSION's wire format (eth/68 carries
total difficulty; eth/69 carries a block range instead), reads the peer's, and
validates version, network, genesis, and — when CHAIN-CONTEXT is given — the
EIP-2124 fork id before returning the peer. Both sides send before reading, so
there is no deadlock. SERVE-BACKEND, when given, is installed before the peer is
returned, so the peer can never send a request we drop for want of a backend."
  (setf (eth-status-version our-status) eth-version)
  (eth-wire-send connection eth-offset +eth-message-status+
                 (encode-eth-status-for-version our-status eth-version))
  (multiple-value-bind (eth-id payload)
      (if shared-capabilities
          (loop
            (multiple-value-bind (kind id payload)
                (eth-wire-read-negotiated-once connection shared-capabilities)
              (case kind
                (:eth (return (values id payload)))
                (:base
                 (when (= id +devp2p-message-ping+)
                   (rlpx-send-pong connection)))
                (:snap
                 (error "snap/1 traffic arrived before the eth Status handshake")))))
          (eth-wire-read
           connection eth-offset
           (devp2p-capability-message-count "eth" eth-version)))
    (unless (= eth-id +eth-message-status+)
      (error "expected eth Status (0x00) but got eth message id ~D" eth-id))
    (let ((peer-status (decode-eth-status-for-version payload eth-version)))
      (eth-validate-peer-status our-status peer-status chain-context)
      (let ((snap (and shared-capabilities
                       (rlpx-shared-capability-named
                        shared-capabilities "snap"))))
        (%make-eth-peer :connection connection
                        :eth-offset eth-offset
                        :eth-version eth-version
                        :shared-capabilities shared-capabilities
                        :snap-offset (and snap
                                          (rlpx-shared-capability-offset snap))
                        :snap-version (and snap
                                           (rlpx-shared-capability-version snap))
                        :snap-backend snap-backend
                        :remote-status peer-status
                        :remote-hello remote-hello
                        :serve-backend serve-backend)))))

(defun eth-peer-connect (connection hello our-status
                         &key chain-context serve-backend snap-backend)
  "Run the devp2p Hello exchange then the eth Status handshake over CONNECTION.

HELLO is our devp2p Hello, which must advertise the eth capability. The eth
version is whichever the negotiation settled on. CHAIN-CONTEXT, when supplied,
enables the EIP-2124 fork-id compatibility check, and SERVE-BACKEND the serving
of the peer's own requests. Returns the ETH-PEER, or errors if the peer does not
share eth."
  (multiple-value-bind (peer-hello shared) (rlpx-exchange-hello connection hello)
    (let ((eth (rlpx-shared-capability-named shared "eth")))
      (unless eth
        (error "peer does not support the eth capability"))
      (eth-peer-handshake connection
                          (rlpx-shared-capability-offset eth)
                          (rlpx-shared-capability-version eth)
                          our-status
                          :chain-context chain-context
                          :serve-backend serve-backend
                          :remote-hello peer-hello
                          :shared-capabilities shared
                          :snap-backend snap-backend))))
