#!r6rs
;;; (o): Exports listed in an order unlike their definitions.
(library (o)
  (export c a b)
  (import (rnrs))

  ;; a : Nat
  ;; The first defined.
  (define a 1)

  ;; b : Nat
  ;; The second defined.
  (define b 2)

  ;; c : Nat
  ;; The third defined.
  (define c 3))
