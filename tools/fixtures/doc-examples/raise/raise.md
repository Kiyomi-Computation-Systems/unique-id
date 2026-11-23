# Raise

```scheme
(import (rnrs))
(define (boom) (assertion-violation 'boom "it broke" 1 "two"))
(boom)
;; => never
(raise 'plain)
;; => never
(+ 1 1)
;; => 3
(+ 1 1)
;; => 2
```
