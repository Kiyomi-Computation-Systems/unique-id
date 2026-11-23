#!r6rs
;;; (x): A signature with no type.
(library (x)
  (export f)
  (import (rnrs))

  ;; f : 
  ;; Fine, but the type is empty.
  (define f 1))
