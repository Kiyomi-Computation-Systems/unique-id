#!r6rs
(library (unique-id-testing)
  (export g)
  (import (rnrs) (srfi :64))
  (define (g x) x))
