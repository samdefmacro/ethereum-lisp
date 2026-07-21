(in-package #:ethereum-lisp.types)

;;;; Unix-epoch clock.
;;;;
;;;; Common Lisp universal time counts from 1900-01-01, while every value
;;;; Ethereum exchanges with the outside world — block timestamps, JWT `iat`
;;;; claims, fork activation times — counts from 1970-01-01. Mixing the two
;;;; silently shifts a value by ~2.2 billion seconds, so conversions go through
;;;; here rather than being open-coded.

(defconstant +unix-epoch-universal-time+ 2208988800
  "Universal time of 1970-01-01T00:00:00Z, the Unix epoch.")

(defun universal-time-to-unix-time (universal-time)
  "Convert UNIVERSAL-TIME to seconds since the Unix epoch."
  (check-type universal-time integer)
  (- universal-time +unix-epoch-universal-time+))

(defun unix-time-to-universal-time (unix-time)
  "Convert UNIX-TIME to a Common Lisp universal time."
  (check-type unix-time integer)
  (+ unix-time +unix-epoch-universal-time+))

(defun unix-time ()
  "Return the current time in seconds since the Unix epoch."
  (universal-time-to-unix-time (get-universal-time)))
