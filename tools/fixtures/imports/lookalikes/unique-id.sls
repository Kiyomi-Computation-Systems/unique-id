#!r6rs
;; Names that start like rnrs and unique-id, but are neither.
(library (unique-id)
  (export f)
  (import (rnrs) (only (unique-id-testing) describe) (rnrs-extra))
  (define (f x) (describe x)))
