#!r6rs
;;; (x): Signatures and no prose.
(library (x)
  (export f g h)
  (import (rnrs))

  ;; f : Nat
  (define f 1)

  ;; g : Nat
  ;;
  ;; Prose, but after a blank line.
  (define g 2)

  ;; h : Nat
  ;; Fine.
  (define h 3))
