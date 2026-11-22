#!r6rs
;;; (unique-id-testing): what every suite shares.
;;;
;;;   suite-exit-form    the last datum of every suite
;;;   suite-verdict      the exit status a runner earned, and the line that
;;;                      explains a 1
;;;   suite-exit-status  that status, after writing that line
;;;
;;; Test-only and plain R6RS, so the suites under tests/ run on Chez and on
;;; Guile: it imports (rnrs) and (srfi :64) alone. Its suites are
;;; tests/test-unique-id-testing.sps and, for what suite-exit-status writes,
;;; tools/test-unique-id-checks.sps.
(library (unique-id-testing)
  (export suite-exit-form suite-verdict suite-exit-status)
  (import (rnrs)
          (srfi :64))

  ;; suite-exit-form : Sexp
  ;; The last datum of every tests/test-*.sps and tools/test-*.sps, exactly:
  ;; make check-suites reads each suite as data and compares its last datum
  ;; with this one. `runner` is the suite's own binding for the runner it
  ;; makes current.
  (define suite-exit-form '(exit (suite-exit-status runner)))

  ;; suite-verdict : Test-Runner -> (List (U 0 1) String)
  ;; 0 and "" when RUNNER saw a pass, and no failure and no unexpected pass.
  ;; Otherwise 1, and a line naming the runner's counts. Expected failures
  ;; and skips count neither way. The status is 0 or 1, never a count: exit
  ;; statuses wrap at 256, so 256 failures would exit 0. An assertion
  ;; violation when RUNNER is not a SRFI-64 test runner.
  (define (suite-verdict runner)
    (unless (test-runner? runner)
      (assertion-violation 'suite-verdict "not a SRFI-64 test runner" runner))
    (let ((pass (test-runner-pass-count runner))
          (fail (test-runner-fail-count runner))
          (xpass (test-runner-xpass-count runner)))
      (if (and (> pass 0) (= fail 0) (= xpass 0))
          (list 0 "")
          (list 1 (string-append "suite-exit-status: exit 1 (pass " (number->string pass)
                                 ", fail " (number->string fail)
                                 ", xpass " (number->string xpass)
                                 "): a suite needs a pass, and no fail or xpass\n")))))

  ;; suite-exit-status : Test-Runner -> (U 0 1)
  ;; suite-verdict's status for RUNNER, after its line, if any, on the error
  ;; port, and its assertion violation for anything but a runner. SRFI-64
  ;; sets no exit status of its own.
  (define (suite-exit-status runner)
    (let ((verdict (suite-verdict runner))
          (err (current-error-port)))
      (unless (string=? (cadr verdict) "")
        ;; The runner's own summary, on stdout, comes first.
        (flush-output-port (current-output-port))
        (put-string err (cadr verdict))
        (flush-output-port err))
      (car verdict))))
