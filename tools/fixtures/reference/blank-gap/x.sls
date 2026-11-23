#!r6rs
;;; (x): A blank line between the comment and the definition.
(library (x)
  (export f)
  (import (rnrs))

  ;; f : Nat
  ;; Fine, but a blank line follows.

  (define f 1))
