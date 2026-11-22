#!r6rs
;; (srfi :19) outside (unique-id system).
(library (unique-id)
  (export f)
  (import (rnrs) (only (srfi :19) current-time))
  (define (f) (current-time)))
