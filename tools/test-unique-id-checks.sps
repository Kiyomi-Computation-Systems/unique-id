#!r6rs
;;; (unique-id-checks)'s describe and run-check, and what (unique-id-testing)'s
;;; suite-exit-status writes, which only Chez, of the two lanes, can capture.
;;;
;;; suite-exit-status is asked about runners of the suite's own making, each
;;; with known counts, under SRFI-64's null runner so nothing they run is
;;; reported. This suite cannot vouch for the verdict it exits through, so it
;;; exits 1 on its own failures first, before the shared form.
(import (rnrs)
        (srfi :64)
        (unique-id-testing)
        (unique-id-checks)
        (only (chezscheme) directory-list foreign-entry? foreign-procedure getenv
              load-shared-object parameterize putenv)
        ;; (rnrs)'s current-error-port takes no argument; Chez's is the
        ;; parameter behind it, which parameterize can rebind.
        (prefix (only (chezscheme) current-error-port) chez:))

(define runner (test-runner-simple))
(test-runner-current runner)

;; counted : (-> Any) -> Test-Runner
;; A null runner after THUNK's tests ran on it.
(define (counted thunk)
  (let ((r (test-runner-null)))
    (test-with-runner r (thunk))
    r))

;; written-status : Test-Runner -> (U (List Integer String) (List 'raised String))
;; suite-exit-status's answer for R, and all it wrote to the error port.
(define (written-status r)
  (guard (e (#t (list 'raised (describe e))))
    (let-values (((port take) (open-string-output-port)))
      (let ((status (parameterize ((chez:current-error-port port))
                      (suite-exit-status r))))
        (list status (take))))))

(test-begin "unique-id-checks")

;; --- suite-exit-status ------------------------------------------------------

(test-equal "suite-exit-status: a pass alone exits 0 and writes nothing"
  '(0 "")
  (written-status (counted (lambda () (test-assert #t)))))

(test-equal "suite-exit-status: a fail exits 1 and writes suite-verdict's line"
  (list 1 (string-append "suite-exit-status: exit 1 (pass 1, fail 1, xpass 0):"
                         " a suite needs a pass, and no fail or xpass\n"))
  (written-status (counted (lambda () (test-assert #t) (test-assert #f)))))

;; --- describe ---------------------------------------------------------------

(test-equal "describe: anything but a condition as write writes it"
  "(a \"b\" #\\c)"
  (describe '(a "b" #\c)))

(test-equal "describe: a condition as Chez displays it"
  "Exception in f: boom with irritant 42"
  (describe (condition (make-who-condition 'f)
                       (make-message-condition "boom")
                       (make-irritants-condition '(42)))))

;; --- run-check --------------------------------------------------------------

(test-equal "run-check: the exit status, stdout and stderr; each argument one word, unexpanded"
  '(3 "[a b][it's][][$HOME][\"q\"][back\\slash]" "to stderr\n")
  (guard (e (#t (list 'raised (describe e))))
    (run-check "tools/fixtures/programs/out-err-exit.sps"
               '("a b" "it's" "" "$HOME" "\"q\"" "back\\slash"))))

;; Whatever the capture files are named, the directory holds after a call
;; just what it held before.
(test-equal "run-check: leaves no capture file behind"
  '(same)
  (guard (e (#t (list 'raised (describe e))))
    (run-check "tools/fixtures/programs/out-err-exit.sps" '())
    (let* ((before (list-sort string<? (directory-list "build/run-check")))
           (ignored (run-check "tools/fixtures/programs/out-err-exit.sps" '()))
           (after (list-sort string<? (directory-list "build/run-check"))))
      (if (equal? before after) '(same) (list 'before before 'after after)))))

;; --- run-check: $CHEZ and stdin ---------------------------------------------

;; Chez 10 finds no "open", "dup" or "dup2" until libc is loaded;
;; foreign-procedure looks each entry up where it is evaluated, so this comes
;; first.
(for-each (lambda (name)
            (unless (foreign-entry? "dup2")
              (guard (e (#t #f)) (load-shared-object name))))
          '("libc.so.6" "libc.so" "libc.dylib"))

;; open : String Integer -> Integer
;; A new descriptor for the file at PATH opened with FLAGS, -1 on failure.
(define c-open (foreign-procedure "open" (string int) int))

;; dup : Integer -> Integer
;; A new descriptor for the file descriptor FD, -1 on failure.
(define c-dup (foreign-procedure "dup" (int) int))

;; dup2 : Integer Integer -> Integer
;; Makes descriptor NEW another name for OLD; answers NEW, -1 on failure.
(define c-dup2 (foreign-procedure "dup2" (int int) int))

;; close : Integer -> Integer
;; Closes descriptor FD.
(define c-close (foreign-procedure "close" (int) int))

;; with-env : String String (-> Any) -> Any
;; THUNK's answer, with environment variable NAME set to VALUE for the call
;; and put back after, even when THUNK raises.
(define (with-env name value thunk)
  (let ((old (getenv name)))
    (dynamic-wind
      (lambda () (putenv name value))
      thunk
      (lambda () (putenv name (or old ""))))))

;; with-stdin-file : String (-> Any) -> Any
;; THUNK's answer, with descriptor 0 a read-only descriptor of the file at
;; PATH for the call, and the original descriptor 0 put back after, even
;; when THUNK raises.
(define (with-stdin-file path thunk)
  (let ((saved #f))
    (dynamic-wind
      (lambda ()
        (let ((fd (c-open path 0)))
          (when (< fd 0) (error 'with-stdin-file "cannot open" path))
          (set! saved (c-dup 0))
          (c-dup2 fd 0)
          (c-close fd)))
      thunk
      (lambda ()
        (when (and saved (>= saved 0))
          (c-dup2 saved 0)
          (c-close saved))))))

(define stand-in "tools/fixtures/run-check/stand-in-chez")

;; tool-libdirs : String
;; TOOL_LIBDIRS, or "" when it is unset, so an expected value never raises:
;; run-check then raises inside the test, which names it.
(define tool-libdirs (or (getenv "TOOL_LIBDIRS") ""))

(test-equal "run-check: runs $CHEZ, not the scheme on the path, with its libdirs, program and arguments"
  (list 0
        (string-append "stand-in chez\n--libdirs\n" tool-libdirs
                       "\n--program\nsome/program.sps\nan arg\nb\n")
        "stand-in stderr\n")
  (guard (e (#t (list 'raised (describe e))))
    (with-env "CHEZ" stand-in
      (lambda () (run-check "some/program.sps" '("an arg" "b"))))))

(test-equal "run-check: the child's stdin is /dev/null, though the suite's own holds bytes"
  (list 0
        (string-append "stand-in chez\n--libdirs\n" tool-libdirs
                       "\n--program\nsome/program.sps\n")
        "stand-in stderr\n")
  (guard (e (#t (list 'raised (describe e))))
    (with-env "CHEZ" stand-in
      (lambda ()
        (with-stdin-file "tools/fixtures/run-check/stdin-bytes.txt"
          (lambda () (run-check "some/program.sps" '())))))))

(test-end "unique-id-checks")

(when (or (= (test-runner-pass-count runner) 0)
          (> (test-runner-fail-count runner) 0)
          (> (test-runner-xpass-count runner) 0))
  (exit 1))

(exit (suite-exit-status runner))
