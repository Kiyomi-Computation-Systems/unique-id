#!r6rs
;;; (x): A signature with no colon.
(library (x)
  (export f)
  (import (rnrs))

  ;; f Nat
  ;; Fine, but the first line has no colon.
  (define f 1))
