#!r6rs
;;; (x): One export has no comment.
(library (x)
  (export f g)
  (import (rnrs))

  ;; f : Nat
  ;; Fine.
  (define f 1)

  ;;; A note directly above g, which is not a comment on it.
  (define (g) 2))
