#!r6rs
;; Each import is one a suite may not have.
(import (rnrs)
        (srfi :1)
        (only (chezscheme) printf)
        (unique-id nope)
        (rnrs eval)
        (unique-id-checks))
(display 1)
