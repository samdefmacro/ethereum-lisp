(in-package #:ethereum-lisp.nat)

;;;; NAT policy plus NAT-PMP and UPnP IGD protocol clients.

(defstruct (nat-policy (:constructor %make-nat-policy (mode address gateway)))
  mode address gateway)

(defun parse-nat-policy (value)
  "Parse geth-compatible none/any/upnp/pmp[:gateway]/extip:address policy."
  (let ((value (string-downcase value)))
    (cond
      ((string= value "none") (%make-nat-policy :none nil nil))
      ((string= value "any") (%make-nat-policy :any nil nil))
      ((string= value "upnp") (%make-nat-policy :upnp nil nil))
      ((string= value "pmp") (%make-nat-policy :pmp nil nil))
      ((and (> (length value) 4) (string= "pmp:" value :end2 4))
       (%make-nat-policy :pmp nil (subseq value 4)))
      ((and (> (length value) 6) (string= "extip:" value :end2 6))
       (%make-nat-policy :extip (subseq value 6) nil))
      (t (error "unsupported --nat policy ~S" value)))))

(defun nat-u16 (bytes start)
  (logior (ash (aref bytes start) 8) (aref bytes (1+ start))))

(defun nat-u32 (bytes start)
  (logior (ash (aref bytes start) 24)
          (ash (aref bytes (+ start 1)) 16)
          (ash (aref bytes (+ start 2)) 8)
          (aref bytes (+ start 3))))

(defun nat-write-u16 (bytes start value)
  (setf (aref bytes start) (ldb (byte 8 8) value)
        (aref bytes (1+ start)) (ldb (byte 8 0) value)))

(defun nat-write-u32 (bytes start value)
  (dotimes (i 4 bytes)
    (setf (aref bytes (+ start i)) (ldb (byte 8 (* 8 (- 3 i))) value))))

(defun nat-pmp-external-address-request ()
  (make-byte-vector 2))

(defun nat-pmp-map-request (protocol internal-port external-port lifetime)
  (let ((request (make-byte-vector 12))
        (opcode (ecase protocol (:udp 1) (:tcp 2))))
    (setf (aref request 1) opcode)
    (nat-write-u16 request 4 internal-port)
    (nat-write-u16 request 6 external-port)
    (nat-write-u32 request 8 lifetime)
    request))

(defun ensure-nat-pmp-response (bytes opcode length)
  (let ((bytes (ensure-byte-vector bytes)))
    (unless (= (length bytes) length)
      (error "NAT-PMP response has wrong length"))
    (unless (and (zerop (aref bytes 0))
                 (= (aref bytes 1) (logior opcode #x80)))
      (error "NAT-PMP response has wrong version or opcode"))
    (unless (zerop (nat-u16 bytes 2))
      (error "NAT-PMP gateway rejected request with result ~D"
             (nat-u16 bytes 2)))
    bytes))

(defun decode-nat-pmp-external-address-response (bytes)
  (let ((bytes (ensure-nat-pmp-response bytes 0 12)))
    (values
     (format nil "~D.~D.~D.~D"
             (aref bytes 8) (aref bytes 9) (aref bytes 10) (aref bytes 11))
     (nat-u32 bytes 4))))

(defun decode-nat-pmp-map-response (bytes protocol)
  (let* ((opcode (ecase protocol (:udp 1) (:tcp 2)))
         (bytes (ensure-nat-pmp-response bytes opcode 16)))
    (values (nat-u16 bytes 8) (nat-u16 bytes 10)
            (nat-u32 bytes 12) (nat-u32 bytes 4))))

(defun upnp-ssdp-discovery-request ()
  (format nil "M-SEARCH * HTTP/1.1~C~CHOST: 239.255.255.250:1900~C~C~
MAN: \"ssdp:discover\"~C~CMX: 2~C~CST: urn:schemas-upnp-org:~
device:InternetGatewayDevice:1~C~C~C~C"
          #\Return #\Linefeed #\Return #\Linefeed
          #\Return #\Linefeed #\Return #\Linefeed
          #\Return #\Linefeed #\Return #\Linefeed))

(defun nat-http-header (response name)
  (dolist (line (uiop:split-string response :separator '(#\Newline)))
    (let ((colon (position #\: line)))
      (when (and colon (string-equal name (string-trim '(#\Return #\Space)
                                                       (subseq line 0 colon))))
        (return (string-trim '(#\Return #\Space #\Tab)
                             (subseq line (1+ colon))))))))

(defun upnp-discovery-location (response)
  (or (nat-http-header response "location")
      (error "UPnP discovery response has no LOCATION")))

(defun nat-xml-value (xml tag)
  (let* ((open (format nil "<~A>" tag))
         (close (format nil "</~A>" tag))
         (start (search open xml :test #'char-equal))
         (end (and start (search close xml :start2 (+ start (length open))
                                      :test #'char-equal))))
    (and end (subseq xml (+ start (length open)) end))))

(defun upnp-control-url (description)
  (or (nat-xml-value description "controlURL")
      (error "UPnP device description has no controlURL")))

(defun upnp-add-port-mapping-request
    (control-url internal-client internal-port external-port protocol lifetime)
  (let* ((protocol (string-upcase (string protocol)))
         (body
           (format nil "<?xml version=\"1.0\"?>~
<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" ~
s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">~
<s:Body><u:AddPortMapping xmlns:u=\"urn:schemas-upnp-org:service:~
WANIPConnection:1\"><NewRemoteHost></NewRemoteHost>~
<NewExternalPort>~D</NewExternalPort><NewProtocol>~A</NewProtocol>~
<NewInternalPort>~D</NewInternalPort><NewInternalClient>~A</NewInternalClient>~
<NewEnabled>1</NewEnabled><NewPortMappingDescription>ethereum-lisp</NewPortMappingDescription>~
<NewLeaseDuration>~D</NewLeaseDuration></u:AddPortMapping></s:Body></s:Envelope>"
                   external-port protocol internal-port internal-client lifetime)))
    (values
     control-url
     (format nil "POST ~A HTTP/1.1~C~CCONTENT-TYPE: text/xml; charset=\"utf-8\"~
~C~CSOAPACTION: \"urn:schemas-upnp-org:service:WANIPConnection:1#AddPortMapping\"~
~C~CCONTENT-LENGTH: ~D~C~C~C~C~A"
             control-url #\Return #\Linefeed #\Return #\Linefeed
             #\Return #\Linefeed (length body)
             #\Return #\Linefeed #\Return #\Linefeed body))))

(defun nat-resolve-and-map
    (policy port &key udp-exchange http-get http-post internal-address
                      (lifetime 3600))
  "Resolve external address and map TCP/UDP using injected real transports."
  (ecase (nat-policy-mode policy)
    (:none (values nil nil))
    (:extip (values (nat-policy-address policy) nil))
    (:pmp
     (unless udp-exchange (error "NAT-PMP requires a UDP transport"))
     (multiple-value-bind (address epoch)
         (decode-nat-pmp-external-address-response
          (funcall udp-exchange (nat-policy-gateway policy) 5351
                   (nat-pmp-external-address-request)))
       (declare (ignore epoch))
       (dolist (protocol '(:tcp :udp))
         (decode-nat-pmp-map-response
          (funcall udp-exchange (nat-policy-gateway policy) 5351
                   (nat-pmp-map-request protocol port port lifetime))
          protocol))
       (values address t)))
    ((:upnp :any)
     (unless (and udp-exchange http-get http-post internal-address)
       (error "UPnP requires SSDP, HTTP, and internal-address transports"))
     (let* ((discovery
              (funcall udp-exchange "239.255.255.250" 1900
                       (upnp-ssdp-discovery-request)))
            (location (upnp-discovery-location discovery))
            (control (upnp-control-url (funcall http-get location))))
       (dolist (protocol '(:tcp :udp))
         (multiple-value-bind (url request)
             (upnp-add-port-mapping-request
              control internal-address port port protocol lifetime)
           (let ((response (funcall http-post url request)))
             (unless (search " 200 " response)
               (error "UPnP gateway rejected port mapping")))))
       (values nil t)))))
