#!r6rs
;;; make check-tests: reads every file under the tests directory named first
;;; on the command line, tests/ in make, given the library directory named
;;; second, src/ in make, and names each breach of a rule of
;;; (unique-id-checks)'s suite-tree-complaints, on stderr, then exits 1.
;;; Otherwise it says how many files it read and exits 0. Any other number of
;;; arguments is a usage error, exit 2.
(import (rnrs)
        (unique-id-checks))

(define err (current-error-port))

(define args (cdr (command-line)))

(unless (= (length args) 2)
  (put-string err "usage: check-tests.sps TESTS SRC\n")
  (exit 2))

(define root (car args))

(define complaints (suite-tree-complaints root (cadr args)))

(define (where path)
  (if (string=? path ".") root (string-append root "/" path)))

(for-each (lambda (c)
            (put-string err (string-append "check-tests: " (where (car c)) ": "
                                           (caddr c) "\n")))
          complaints)

(when (null? complaints)
  (put-string (current-output-port)
              (string-append "check-tests: every file under " root
                             " is plain R6RS and imports only what it may ("
                             (number->string (length (suite-tree-files root))) " checked)\n")))

(exit (if (null? complaints) 0 1))
