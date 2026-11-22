#!r6rs
(library (unique-id)
  (export f)
  (import (rnrs)) #!chezscheme
  (define (f x) '|a b|))
