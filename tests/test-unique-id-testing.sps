#!r6rs
;;; (unique-id-testing): the shared exit form and the verdict it exits with.
;;;
;;; suite-verdict is asked about runners of the suite's own making, each with
;;; known counts, under SRFI-64's null runner so nothing they run is
;;; reported. This suite cannot vouch for the verdict it exits through, so it
;;; exits 1 on its own failures first, before the shared form.
(import (rnrs)
        (srfi :64)
        (unique-id-testing))

(define runner (test-runner-simple))
(test-runner-current runner)

;; counted : (-> Any) -> Test-Runner
;; A null runner after THUNK's tests ran on it.
(define (counted thunk)
  (let ((r (test-runner-null)))
    (test-with-runner r (thunk))
    r))

;; verdict : Test-Runner -> (U (List (U 0 1) String) (List 'raised Any))
;; suite-verdict's answer for R, or what it raised.
(define (verdict r)
  (guard (e (#t (list 'raised e)))
    (suite-verdict r)))

(define (message pass fail xpass)
  (string-append "suite-exit-status: exit 1 (pass " (number->string pass)
                 ", fail " (number->string fail) ", xpass " (number->string xpass)
                 "): a suite needs a pass, and no fail or xpass\n"))

(test-begin "unique-id-testing")

;; --- suite-exit-form --------------------------------------------------------

;; Built with list: a quoted exit form here would be an early exit to
;; make check-suites, which reads data.
(test-equal "suite-exit-form is the datum every suite ends with"
  (list 'exit (list 'suite-exit-status 'runner))
  suite-exit-form)

;; --- suite-verdict ----------------------------------------------------------

(test-equal "a pass alone: 0, and nothing to write"
  '(0 "")
  (verdict (counted (lambda () (test-assert #t)))))

(test-equal "no test at all: 1"
  (list 1 (message 0 0 0))
  (verdict (counted (lambda () #t))))

(test-equal "a pass and a fail: 1"
  (list 1 (message 1 1 0))
  (verdict (counted (lambda () (test-assert #t) (test-assert #f)))))

(test-equal "a pass and an unexpected pass: 1"
  (list 1 (message 1 0 1))
  (verdict (counted (lambda ()
                      (test-assert #t)
                      (test-expect-fail 1)
                      (test-assert #t)))))

(test-equal "a pass, an expected fail and a skip: 0"
  '(0 "")
  (verdict (counted (lambda ()
                      (test-assert #t)
                      (test-expect-fail 1)
                      (test-assert #f)
                      (test-skip 1)
                      (test-assert #f)))))

(test-equal "256 failures: 1, not a count that wraps to 0"
  (list 1 (message 1 256 0))
  (verdict (counted (lambda ()
                      (test-assert #t)
                      (let loop ((i 0))
                        (when (< i 256)
                          (test-assert #f)
                          (loop (+ i 1))))))))

(test-equal "not a runner: an assertion violation from suite-verdict"
  '(assertion-violation suite-verdict (not-a-runner))
  (guard (e ((and (assertion-violation? e) (who-condition? e) (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'other-raise e)))
    (suite-verdict 'not-a-runner)
    'no-raise))

;; --- suite-exit-status ------------------------------------------------------

;; What it writes is held on Chez, which can rebind the error port, by
;; tools/test-unique-id-checks.sps.
(test-equal "suite-exit-status: 0 for a pass alone"
  0
  (guard (e (#t (list 'raised e)))
    (suite-exit-status (counted (lambda () (test-assert #t))))))

(test-end "unique-id-testing")

(when (or (= (test-runner-pass-count runner) 0)
          (> (test-runner-fail-count runner) 0)
          (> (test-runner-xpass-count runner) 0))
  (exit 1))

(exit (suite-exit-status runner))
