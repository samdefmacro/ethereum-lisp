(in-package #:ethereum-lisp.test)

;;; Control-plane brokers are bash scripts that run on the developer host and
;;; drive a remote server over ssh.  They are never run against a real host
;;; from the test suite; their self-tests stub ssh, scp, docker, git, free and
;;; df, and exercise argument parsing and every refusal branch with a paired
;;; positive control.  This file only launches those self-tests inside the
;;; project container and requires a non-zero check count.

(defun %control-plane-selftest-check-count (script marker)
  "Run the bash self-test SCRIPT and return its exit status, stdout, and the
check count it printed after MARKER (NIL when it printed none)."
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "bash" (namestring (repository-relative-pathname script)))
       :directory *repository-root*
       :output :string
       :error-output :string
       :ignore-error-status t)
    (unless (= 0 status)
      (format *error-output* "~&~A~&~A~&" stdout stderr))
    (let ((start (search marker stdout)))
      ;; Keep the check count in the runner's record even when green.
      (when start
        (format *error-output* "~&# ~A~&"
                (subseq stdout start (or (position #\Newline stdout :start start)
                                         (length stdout)))))
      (values status
              stdout
              (and start
                   (parse-integer stdout
                                  :start (+ start (length marker))
                                  :junk-allowed t))))))

(deftest hoodi-hive-gate-selftest-covers-refusals
  (:layer :integration :module :control-plane :launches-processes t)
  (multiple-value-bind (status stdout count)
      (%control-plane-selftest-check-count
       "scripts/hoodi-hive-gate-selftest.sh" "hoodi-hive-gate selftest: ")
    (is (= 0 status))
    (is (search ", 0 failed" stdout))
    (is (null (search "not ok" stdout)))
    ;; A self-test that ran nothing must not pass: the refusal matrix alone
    ;; is more than forty checks.
    (is (and count (>= count 40)))))

(deftest hoodi-live-gate-selftest-summarises-engine-telemetry
  (:layer :integration :module :control-plane :launches-processes t)
  (multiple-value-bind (status stdout count)
      (%control-plane-selftest-check-count
       "scripts/hoodi-live-gate-selftest.sh" "hoodi-live-gate selftest: ")
    (is (= 0 status))
    (is (search ", 0 failed" stdout))
    (is (null (search "not ok" stdout)))
    ;; The logs summary alone checks more than twenty lines; 37 in all.
    (is (and count (>= count 35)))))
