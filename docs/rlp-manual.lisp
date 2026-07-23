;;;; docs/rlp-manual.lisp
;;;;
;;;; MGL-PAX documentation for ethereum-lisp.rlp with mechanically checked
;;;; transcripts: every ```cl-transcript example is re-executed and compared
;;;; by scripts/docs-check.lisp, so these examples cannot rot — they are
;;;; verification artifacts (and in-context teaching corpus for agents), not
;;;; prose. Authoring rules:
;;;;   - package-qualify every symbol inside transcript forms
;;;;   - `=>` (readable values) and `..` (output) are strictly compared;
;;;;     `==>` text is NOT compared, so prefer `=>`/`..`
;;;;   - wrap MACROEXPAND examples in COPY-TREE (transcription enables
;;;;     *PRINT-CIRCLE*; backquote sharing would print as #1# labels)

(defpackage #:ethereum-lisp-docs
  (:use #:cl #:mgl-pax)
  (:export #:@rlp-manual))

(in-package #:ethereum-lisp-docs)

(defsection @rlp-manual (:title "ethereum-lisp.rlp: Recursive Length Prefix"
                         :export nil)
  "RLP is Ethereum's canonical serialization. `ETHEREUM-LISP.RLP:RLP-ENCODE`
accepts non-negative integers (minimal big-endian bytes; zero is the empty
byte string), ASCII strings, byte vectors, plain lists, and `RLP-LIST`
structs. The classic vectors:

```cl-transcript
(ethereum-lisp.hex:bytes-to-hex (ethereum-lisp.rlp:rlp-encode \"dog\"))
=> \"0x83646f67\"

(ethereum-lisp.hex:bytes-to-hex
 (ethereum-lisp.rlp:rlp-encode (list \"cat\" \"dog\")))
=> \"0xc88363617483646f67\"

(ethereum-lisp.hex:bytes-to-hex (ethereum-lisp.rlp:rlp-encode 1024))
=> \"0x820400\"

(ethereum-lisp.hex:bytes-to-hex (ethereum-lisp.rlp:rlp-encode 0))
=> \"0x80\"
```

`ETHEREUM-LISP.RLP:RLP-DECODE` returns two values: the decoded item and the
next input position. Byte payloads come back as byte vectors; RLP lists come
back as `RLP-LIST` structs whose items are read with
`ETHEREUM-LISP.RLP:RLP-LIST-ITEMS`:

```cl-transcript
(ethereum-lisp.rlp:rlp-decode
 (ethereum-lisp.hex:hex-to-bytes \"0x83646f67\"))
=> #(100 111 103)
=> 4

(mapcar #'ethereum-lisp.bytes:bytes-to-ascii
        (ethereum-lisp.rlp:rlp-list-items
         (ethereum-lisp.rlp:rlp-decode
          (ethereum-lisp.hex:hex-to-bytes \"0xc88363617483646f67\"))))
=> (\"cat\" \"dog\")
```

Malformed input signals `ETHEREUM-LISP.RLP:RLP-ERROR`:

```cl-transcript
(handler-case
    (ethereum-lisp.rlp:rlp-decode (ethereum-lisp.hex:hex-to-bytes \"0x\"))
  (ethereum-lisp.rlp:rlp-error () :rejected))
=> :REJECTED
```"
  (ethereum-lisp.rlp:rlp-encode function)
  (ethereum-lisp.rlp:rlp-decode function)
  (ethereum-lisp.rlp:rlp-decode-one function)
  (ethereum-lisp.rlp:rlp-list-items function)
  (ethereum-lisp.rlp:rlp-error condition))

(defsection @docs-check-selftest (:title "Transcript-checker self-test"
                                  :export nil)
  "This section records a deliberately WRONG value. scripts/docs-check.lisp
documents it EXPECTING a consistency error; if it ever passes, transcript
checking is silently off and the docs-check run fails. Do not fix the
example.

```cl-transcript
(+ 1 2)
=> 4
```")
