#!r6rs
;;; (x): An export no definition holds.
(library (x)
  (export f g)
  (import (rnrs))

  ;; f : Nat
  ;; Not defined.

  ;; g : Nat
  ;; Fine.
  (define g 2))
