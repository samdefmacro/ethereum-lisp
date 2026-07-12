(defun smoke-gate-main
    (&key
       (args (smoke-gate-arguments))
       (environment-lookup #'uiop:getenv)
       (output *standard-output*)
       (error-output *error-output*)
       (load-tests-p t))
  (let ((*smoke-gate-environment-lookup* environment-lookup)
        (*standard-output* output)
        (*error-output* error-output))
    (let* ((args (smoke-gate-normalize-option-args args))
         (help-p (smoke-gate-help-p args)))
    (if help-p
        (smoke-gate-print-help)
        (let* ((pinned-p (smoke-gate-pinned-v5.4.0-p args))
               (devnet-p (smoke-gate-devnet-p args))
               (drift-map-p (smoke-gate-drift-map-p args))
               (json-p (smoke-gate-json-p args))
               (root-argument (smoke-gate-argument-root args)))
          (when load-tests-p
            (load (merge-pathnames "tests/load-tests.lisp"
                                   *ethereum-lisp-smoke-gate-root*)))
          (let* ((suite-root (smoke-gate-suite-root root-argument pinned-p))
                 (report (smoke-gate-report
                          suite-root
                          pinned-p
                          :devnet-p devnet-p
                          :drift-map-p drift-map-p)))
            (if json-p
                (format t "~&~A~%" (smoke-gate-json-encode report))
                (smoke-gate-print-text report))
            report))))))

(when *smoke-gate-run-main-p*
  (smoke-gate-main))
