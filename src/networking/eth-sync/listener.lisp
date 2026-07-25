(in-package #:ethereum-lisp.eth-sync)

;;;; Listening for inbound RLPx connections.
;;;;
;;;; Dialing peers makes us a client of the network; accepting connections is
;;;; what makes us a member of it. A node nobody can reach is invisible to
;;;; discovery, contributes nothing back, and can only ever learn from peers it
;;;; happened to dial first.
;;;;
;;;; The HTTP listener next door cannot be reused for this. It hands back a
;;;; character stream in UTF-8 where RLPx needs raw octets, it discards the
;;;; peer's address, which a peer manager needs, and its accept blocks
;;;; indefinitely, which is the one thing an accept loop that must notice
;;;; shutdown cannot do. The shape below is borrowed from it; the mechanism is
;;;; not.
;;;;
;;;; ACCEPT IS READINESS-GATED, NOT BLOCKING. Waiting on the descriptor with a
;;;; timeout before calling accept is the whole correctness mechanism of this
;;;; file: it is what lets the accept loop return to its caller regularly enough
;;;; to see a shutdown request, without depending on closing the socket from
;;;; another thread to break it out. The close path still shuts the socket down
;;;; as well, but only as a second line of defence.

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets))

(defstruct (eth-sync-listener
            (:constructor %make-eth-sync-listener (socket host port close-lock)))
  "A bound, listening TCP socket for inbound RLPx connections.

Unlike the HTTP listener the socket itself stays reachable, because the accept
gate needs its file descriptor."
  socket
  host
  port
  close-lock
  (closed-p nil))

(defun eth-sync-socket-endpoint-host (host)
  "The address to ADVERTISE for a socket bound to HOST.

A wildcard bind is not an address anyone can dial, so it is reported as
loopback rather than published as 0.0.0.0."
  (if (string= host "0.0.0.0")
      "127.0.0.1"
      host))

(defun make-eth-sync-socket-listener (&key (host "0.0.0.0") (port 0) (backlog 16))
  "Bind and listen for inbound RLPx connections, returning an ETH-SYNC-LISTENER.

PORT 0 binds an ephemeral port; the real one is read back from the socket, so a
caller always knows what to advertise before any peer connects."
  #-sbcl
  (declare (ignore host port backlog))
  #-sbcl
  (error "An RLPx listener requires SBCL sb-bsd-sockets")
  #+sbcl
  (let ((socket (make-instance 'sb-bsd-sockets:inet-socket
                               :type :stream :protocol :tcp)))
    (setf (sb-bsd-sockets:sockopt-reuse-address socket) t)
    (handler-case
        (progn
          (sb-bsd-sockets:socket-bind
           socket (sb-bsd-sockets:make-inet-address host) port)
          (sb-bsd-sockets:socket-listen socket backlog)
          (multiple-value-bind (address bound-port) (sb-bsd-sockets:socket-name socket)
            (declare (ignore address))
            (%make-eth-sync-listener
             socket host bound-port
             (sb-thread:make-mutex :name "ethereum-lisp-p2p-listener-close"))))
      (error (condition)
        (ignore-errors (sb-bsd-sockets:socket-close socket))
        (error condition)))))

(defun eth-sync-listener-endpoint-host (listener)
  "The dialable address of LISTENER, never a wildcard."
  (eth-sync-socket-endpoint-host (eth-sync-listener-host listener)))

(defun eth-sync-listener-accept (listener &key (timeout-seconds 1))
  "Accept one inbound connection, returning (VALUES SOCKET HOST PORT), or NIL.

Waits at most TIMEOUT-SECONDS for a connection and returns NIL if none arrives,
so the caller regains control on a schedule it chooses rather than whenever the
network happens to oblige. Returns NIL at once once the listener is closed."
  #-sbcl
  (declare (ignore listener timeout-seconds))
  #-sbcl
  nil
  #+sbcl
  (unless (eth-sync-listener-closed-p listener)
    (let ((socket (eth-sync-listener-socket listener)))
      (when (sb-sys:wait-until-fd-usable
             (sb-bsd-sockets:socket-file-descriptor socket) :input timeout-seconds nil)
        ;; Closed while we waited: the descriptor is readable but accepting it
        ;; would race the close.
        (unless (eth-sync-listener-closed-p listener)
          (multiple-value-bind (accepted address port)
              (sb-bsd-sockets:socket-accept socket)
            (when accepted
              ;; DISCV4-IP-STRING renders 4- and 16-byte addresses and returns
              ;; NIL for anything else, so an address we cannot render becomes
              ;; the unspecified one rather than NIL leaking into a peer record.
              (values accepted
                      (or (and address (discv4-ip-string address)) "0.0.0.0")
                      port))))))))

(defun eth-sync-listener-close (listener)
  "Close LISTENER. Idempotent, and safe to call from another thread.

The shutdown before the close is belt and braces: accept is readiness-gated, so
a blocked accept is not what this has to break."
  #-sbcl
  (declare (ignore listener))
  #-sbcl
  nil
  #+sbcl
  (sb-thread:with-mutex ((eth-sync-listener-close-lock listener))
    (unless (eth-sync-listener-closed-p listener)
      (setf (eth-sync-listener-closed-p listener) t)
      (let ((socket (eth-sync-listener-socket listener)))
        (ignore-errors (sb-bsd-sockets:socket-shutdown socket :direction :io))
        (ignore-errors (sb-bsd-sockets:socket-close socket)))))
  t)
