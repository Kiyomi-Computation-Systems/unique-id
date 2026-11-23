# Strings

```scheme
(import (rnrs))
(string #\a #\space #\space #\space #\b)
;; => "a b"
(number->string 3735928559 16)
;; => e.g. "deadbeef"
(string-append "ab" "cd" "ef" "01")
;; => e.g. "012345678"
(string #\A)
;; => e.g. "a"
(list 1234 "ab")
;; => e.g. (1 "cd")
```
