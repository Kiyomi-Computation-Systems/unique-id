#!r6rs
;;; (a b): The second library.
(library (a b)
  (export delta eps)
  (import (rnrs))

  ;; delta : Nat (Listof Nat)
  ;;   -> (Pair Nat (Listof Nat))
  ;; The pair of FIRST and REST.
  (define (delta first . rest) (cons first rest))

  ;; eps : (Listof Any) -> Nat
  ;; The length of ALL.
  (define (eps . all) (length all)))
