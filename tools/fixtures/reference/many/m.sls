#!r6rs
;;; (m): Breaches, in the export list's order.
(library (m)
  (export q p)
  (import (rnrs))

  (define (p) 1)

  (define (q) 2))
