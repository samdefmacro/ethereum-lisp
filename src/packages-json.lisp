(defpackage #:ethereum-lisp.json
  (:use #:cl
        #:ethereum-lisp.hex
        #:ethereum-lisp.types
        #:ethereum-lisp.validation)
  (:export
   #:parse-json
   #:json-encode
   #:json-object-p
   #:json-empty-array-p
   #:json-array-p
   #:json-array-values
   #:json-object-field
   #:json-object-field-present-p
   #:json-object-field-any
   #:json-object-entries
   #:json-hex-quantity-string-p
   #:parse-json-quantity
   #:parse-json-quantity-field
   #:json-empty-object
   #:json-empty-object-p
   #:make-json-empty-object
   #:+json-empty-object+))

(defpackage #:ethereum-lisp.json-rpc
  (:use #:cl
        #:ethereum-lisp.hex
        #:ethereum-lisp.types
        #:ethereum-lisp.validation
        #:ethereum-lisp.json)
  (:export
   #:json-rpc-response
   #:json-rpc-error-object
   #:json-rpc-invalid-request-response
   #:json-rpc-parse-error-response
   #:json-rpc-version-valid-p
   #:json-rpc-notification-p
   #:json-rpc-request-id-valid-p
   #:json-rpc-request-valid-p
   #:json-rpc-required-field
   #:json-rpc-optional-quantity-field
   #:json-rpc-required-quantity-field
   #:json-rpc-hash32
   #:json-rpc-address
   #:json-rpc-bytes
   #:json-rpc-required-hash32-field
   #:json-rpc-optional-hash32-value
   #:json-rpc-required-address-field
   #:json-rpc-required-bytes-field
   #:json-rpc-optional-bytes-field
   #:json-rpc-byte-list
   #:json-rpc-hash32-list
   #:json-rpc-required-param
   #:json-rpc-quantity-param))
