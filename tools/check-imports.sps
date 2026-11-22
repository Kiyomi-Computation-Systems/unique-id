#!r6rs
;;; make check-imports: reads every file under the one directory named on the
;;; command line, src/ in make, and names each breach of a rule of
;;; (unique-id-checks)'s import-complaints, on stderr, then exits 1.
;;; Otherwise it says how many libraries it read and exits 0. Any other
;;; number of arguments is a usage error, exit 2.
(import (rnrs)
        (unique-id-checks))

(define err (current-error-port))

(define args (cdr (command-line)))

(unless (= (length args) 1)
  (put-string err "usage: check-imports.sps DIR\n")
  (exit 2))

(define root (car args))

(define complaints (import-complaints root))

(define (where path)
  (if (string=? path ".") root (string-append root "/" path)))

(for-each (lambda (c)
            (put-string err (string-append "check-imports: " (where (car c)) ": "
                                           (caddr c) "\n")))
          complaints)

(when (null? complaints)
  (put-string (current-output-port)
              (string-append "check-imports: every library under " root
                             " is plain R6RS and imports only what it may ("
                             (number->string (length (library-files root))) " checked)\n")))

(exit (if (null? complaints) 0 1))
