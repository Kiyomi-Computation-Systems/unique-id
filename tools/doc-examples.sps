#!r6rs
;;; make check-docs's generator: writes one program per page of the *.md files
;;; in the first directory named, DOCS-DIR, into the second, OUT-DIR, after
;;; removing every *.sps there, and exits 0. A page it refuses gets a program
;;; that writes its complaints to stderr and exits 1, so a lane reports the
;;; page as failed; the generator writes one line per complaint to stderr,
;;; still writes every page it can, and exits 1. Any other number of arguments is a usage error, exit 2.
(import (rnrs)
        (unique-id-doc-examples))

(define err (current-error-port))

(define args (cdr (command-line)))

(unless (= (length args) 2)
  (put-string err "usage: doc-examples.sps DOCS-DIR OUT-DIR\n")
  (exit 2))

(define complaints (write-programs (car args) (cadr args)))

(for-each (lambda (c) (put-string err (string-append c "\n"))) complaints)
(exit (if (null? complaints) 0 1))
