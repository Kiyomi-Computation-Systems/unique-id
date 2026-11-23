# Unchecked raise

```scheme
(import (rnrs))
(+ 1 1)
;; => 2
(raise 'stop)
(+ 2 2)
;; => 4
```
