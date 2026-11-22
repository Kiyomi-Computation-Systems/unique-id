#!r6rs
;; (unique-id chez) is no file here: on a path with another directory that
;; holds it, Chez would load that one.
(library (unique-id)
  (export f)
  (import (rnrs) (only (unique-id chez) helper))
  (define (f x) (helper x)))
