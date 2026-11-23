#!r6rs
;;; (x): A signature that names another export.
(library (x)
  (export f g)
  (import (rnrs))

  ;; g : Nat
  ;; Names g, above f.
  (define f 1)

  ;; g : Nat
  ;; Names itself.
  (define g 2))
