#!r6rs
;;; make reference: writes the page for the libraries under the first
;;; directory named, SRC-DIR, to stdout, after the head file named second, and
;;; exits 0. When an export has no valid signature comment it writes nothing
;;; to stdout, one line per breach to stderr, and exits 1. Any other number of
;;; arguments is a usage error, exit 2.
(import (rnrs)
        (unique-id-reference))

(define err (current-error-port))

(define args (cdr (command-line)))

(unless (= (length args) 2)
  (put-string err "usage: reference.sps SRC-DIR HEAD-FILE\n")
  (exit 2))

(define src-dir (car args))

(define breaches (reference-breaches src-dir))

(cond
  ((null? breaches)
   (let ((out (transcoded-port (standard-output-port)
                               (make-transcoder (utf-8-codec) (eol-style lf)))))
     (put-string out (reference-page src-dir (file-text (cadr args))))
     (flush-output-port out)
     (exit 0)))
  (else
   (for-each (lambda (b) (put-string err (string-append (breach-line b) "\n"))) breaches)
   (exit 1)))
