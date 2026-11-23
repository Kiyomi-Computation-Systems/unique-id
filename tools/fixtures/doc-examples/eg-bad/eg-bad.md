# Wrong shape

```scheme
(import (rnrs))
(string-append "01a2" "-" "77")
;; => e.g. "ffff-12"
(string-append "ab")
;; => e.g. 12
(list 1 2)
;; => e.g. (1 2 3)
```
