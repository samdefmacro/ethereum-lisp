(in-package #:ethereum-lisp.test)

;;; Control-plane brokers are bash scripts that run on the developer host and
;;; drive a remote server over ssh.  They are never run against a real host
;;; from the test suite; their self-tests stub ssh, scp, docker, git, free and
;;; df, and exercise argument parsing and every refusal branch with a paired
;;; positive control.  This file only launches those self-tests inside the
;;; project container and requires a non-zero check count.

(deftest hoodi-hive-gate-selftest-covers-refusals
  (:layer :integration :module :control-plane :launches-processes t)
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "bash"
             (namestring
              (repository-relative-pathname "scripts/hoodi-hive-gate-selftest.sh")))
       :directory *repository-root*
       :output :string
       :error-output :string
       :ignore-error-status t)
    (unless (= 0 status)
      (format *error-output* "~&~A~&~A~&" stdout stderr))
    (is (= 0 status))
    (is (search "hoodi-hive-gate selftest:" stdout))
    (is (search ", 0 failed" stdout))
    (is (null (search "not ok" stdout)))
    ;; A self-test that ran nothing must not pass: the refusal matrix alone
    ;; is more than forty checks.
    (let* ((marker "hoodi-hive-gate selftest: ")
           (start (search marker stdout))
           (count (and start
                       (parse-integer stdout
                                      :start (+ start (length marker))
                                      :junk-allowed t))))
      (is (and count (>= count 40))))))
