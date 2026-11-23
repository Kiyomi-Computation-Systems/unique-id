#!r6rs
;;; (unique-id)'s text: string->uuid and uuid->string.
;;;
;;; string->uuid takes the 36-character canonical form, in any case, and
;;; answers #f for every other string. Each position is held on its own: every
;;; hex digit at every digit index, every refused character at every index,
;;; every length, and a hyphen moved. uuid->string answers lower case in a
;;; fresh string. Ids come from string->uuid and bytevector->uuid, and from
;;; the library's nil-uuid and max-uuid.
;;;
;;; Every call into the library goes through a helper that tags what happened,
;;; so a raise is a value to compare, never a dead suite and never a #f that
;;; passes. Ids are compared by their octets or their text, never with equal?.
(import (rnrs)
        ;; string-set!, for the freshness test, is not in (rnrs).
        (rnrs mutable-strings)
        (srfi :64)
        (unique-id)
        (unique-id-testing))

(define runner (test-runner-simple))
(test-runner-current runner)

;; --- what happened ----------------------------------------------------------

;; value-of : (-> Any) -> (U (List 'value Any) (List 'raised Any))
;; The tagged answer of THUNK, or the tagged object it raised.
(define (value-of thunk)
  (guard (e (#t (list 'raised e)))
    (list 'value (thunk))))

;; parse : String -> (U (List 'id (Listof Nat)) (List 'no-id) (List 'raised Any))
;; What string->uuid makes of TEXT: the id's 16 octets, no id, or the raise.
(define (parse text)
  (guard (e (#t (list 'raised e)))
    (let ((id (string->uuid text)))
      (if id
          (list 'id (bytevector->u8-list (uuid->bytevector id)))
          (list 'no-id)))))

;; round-text : String -> (U (List 'value (U String Symbol)) (List 'raised Any))
;; The text of the id TEXT spells, or the symbol no-id for none, tagged.
(define (round-text text)
  (value-of (lambda ()
              (let ((id (string->uuid text)))
                (if id (uuid->string id) 'no-id)))))

;; id-text : (Listof Nat) -> (U (List 'value String) (List 'raised Any))
;; uuid->string of the id bytevector->uuid makes of OCTETS.
(define (id-text octets)
  (value-of (lambda ()
              (uuid->string (bytevector->uuid (u8-list->bytevector octets))))))

;; irritants-ok? : Any Any -> Boolean
;; Whether IRRITANTS is a list of one element, eqv? to ARG.
(define (irritants-ok? irritants arg)
  (and (pair? irritants) (null? (cdr irritants)) (eqv? (car irritants) arg)))

;; violation : (Any -> Any) (-> Any)
;;             -> (U (List 'assertion-violation Any Boolean) (List 'returned) (List 'raised Any))
;; Calls PROC on the argument MAKE-ARG makes. An assertion violation answers its
;; who and whether its irritants are the argument alone; anything else raised
;; answers 'raised, and no raise 'returned.
(define (violation proc make-arg)
  (guard (e (#t (list 'raised e)))
    (let ((arg (make-arg)))
      (guard (e ((and (assertion-violation? e) (who-condition? e) (irritants-condition? e))
                 (list 'assertion-violation
                       (condition-who e)
                       (irritants-ok? (condition-irritants e) arg)))
                (#t (list 'raised e)))
        (proc arg)
        (list 'returned)))))

;; --- what the suite computes ------------------------------------------------

;; nibble-of : Char -> Nat
;; The value of the ASCII hex digit C.
(define (nibble-of c)
  (let ((n (char->integer c)))
    (cond ((and (>= n 48) (<= n 57)) (- n 48))
          ((and (>= n 97) (<= n 102)) (- n 87))
          ((and (>= n 65) (<= n 70)) (- n 55))
          (else (assertion-violation 'nibble-of "not a hex digit" c)))))

;; digits->octets : (Listof Char) -> (Listof Nat)
;; The octets of an even number of hex digit characters.
(define (digits->octets chars)
  (if (null? chars)
      '()
      (cons (+ (* 16 (nibble-of (car chars))) (nibble-of (cadr chars)))
            (digits->octets (cddr chars)))))

;; text->octets : String -> (Listof Nat)
;; The octets of a canonical text, in either case.
(define (text->octets text)
  (digits->octets (filter (lambda (c) (not (char=? c #\-))) (string->list text))))

;; hex2 : Nat -> String
;; The two lower-case hex digits of the octet B.
(define (hex2 b)
  (string (string-ref "0123456789abcdef" (div b 16))
          (string-ref "0123456789abcdef" (mod b 16))))

;; octets->text : (Listof Nat) -> String
;; The canonical lower-case text of 16 OCTETS.
(define (octets->text octets)
  (let ((h (apply string-append (map hex2 octets))))
    (string-append (substring h 0 8) "-" (substring h 8 12) "-" (substring h 12 16)
                   "-" (substring h 16 20) "-" (substring h 20 32))))

;; iota* : Nat -> (Listof Nat)
;; 0 up to below N.
(define (iota* n)
  (let loop ((i (- n 1)) (acc '()))
    (if (< i 0) acc (loop (- i 1) (cons i acc)))))

;; repeat : Nat Any -> (Listof Any)
;; A list of N copies of X.
(define (repeat n x)
  (map (lambda (i) x) (iota* n)))

;; pattern-octets : Nat -> (Listof Nat)
;; 16 octets whose octet i is (i * 17 + K) mod 256.
(define (pattern-octets k)
  (map (lambda (i) (mod (+ (* i 17) k) 256)) (iota* 16)))

;; set-nibble : (Listof Nat) Nat Nat -> (Listof Nat)
;; OCTETS with digit K (0 to 31, high nibble first) replaced by the nibble N.
(define (set-nibble octets k n)
  (let loop ((os octets) (j 0))
    (cond ((null? os) '())
          ((= j (div k 2))
           (cons (if (even? k)
                     (+ (* 16 n) (mod (car os) 16))
                     (+ (* 16 (div (car os) 16)) n))
                 (cdr os)))
          (else (cons (car os) (loop (cdr os) (+ j 1)))))))

;; replace-at : String Nat Char -> String
;; TEXT with the character at I replaced by C.
(define (replace-at text i c)
  (list->string
   (map (lambda (x j) (if (= j i) c x)) (string->list text) (iota* (string-length text)))))

;; digit-index->text-index : Nat -> Nat
;; Where hex digit K (0 to 31) sits in the 36-character text.
(define (digit-index->text-index k)
  (cond ((< k 8) k)
        ((< k 12) (+ k 1))
        ((< k 16) (+ k 2))
        ((< k 20) (+ k 3))
        (else (+ k 4))))

;; failures-of : (Listof Any) (Any -> Any) -> (Listof Any)
;; The non-#f answers of CHECK over ITEMS, in order. CHECK answers #f for a
;; pass.
(define (failures-of items check)
  (let loop ((xs items) (acc '()))
    (if (null? xs)
        (reverse acc)
        (let ((f (check (car xs))))
          (loop (cdr xs) (if f (cons f acc) acc))))))

;; cross : (Listof Any) (Listof Any) -> (Listof (List Any Any))
;; Every pair of an element of AS with an element of BS.
(define (cross as bs)
  (apply append (map (lambda (a) (map (lambda (b) (list a b)) bs)) as)))

;; padding : Nat -> String
;; N hex digit characters.
(define (padding n)
  (list->string
   (map (lambda (i) (string-ref "0123456789abcdef" (mod i 16))) (iota* n))))

;; --- data -------------------------------------------------------------------

;; A text of no default value: no octet is 0, and its digits mix case once
;; upcased.
(define base-text "3d7e5a91-c2f4-4b68-a1d0-8e6f2b49c735")
(define base-octets (text->octets base-text))

(define hyphen-indexes '(8 13 18 23))

(define hex-chars (string->list "0123456789abcdefABCDEF"))

;; Characters that are no hex digit, to put where one belongs.
;; Every character from code point 0 to 255 but the 22 hex digits, and three
;; above: an Arabic-Indic digit, a full-width digit and a full-width letter.
(define bad-digit-chars
  (append (filter (lambda (c) (not (memv c hex-chars)))
                  (map integer->char (iota* 256)))
          (map integer->char '(#x663 #xFF11 #xFF21))))

;; Characters that are no hyphen, to put where one belongs.
;; Every character from code point 0 to 255 but the hyphen, and two look-alikes:
;; U+2010 hyphen and U+2212 minus sign.
(define bad-hyphen-chars
  (append (filter (lambda (c) (not (char=? c #\-)))
                  (map integer->char (iota* 256)))
          (map integer->char '(#x2010 #x2212))))

(define a6-upper "017F22E2-79B0-7CC3-98C4-DC0C0C07398F")
(define a6-lower "017f22e2-79b0-7cc3-98c4-dc0c0c07398f")
(define a3-text "919108f7-52d1-4320-9bac-f847db4148a8")
(define figure1-text "f81d4fae-7dec-11d0-a765-00a0c91e6bf6")
(define figure5-texts
  '("00000000-0000-4000-8000-000000000000"
    "00000000-0000-4000-9000-000000000000"
    "00000000-0000-4000-A000-000000000000"
    "00000000-0000-4000-B000-000000000000"))
(define nil-text "00000000-0000-0000-0000-000000000000")
(define max-upper "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")
(define max-lower "ffffffff-ffff-ffff-ffff-ffffffffffff")

(define base-upper (string-upcase base-text))
;; Letters alternate between lower and upper case by index.
(define base-mixed
  (list->string
   (map (lambda (c i) (if (even? i) (char-upcase c) (char-downcase c)))
        (string->list base-text)
        (iota* 36))))

(define rfc-texts
  (append (list a6-upper a6-lower a3-text figure1-text nil-text max-upper max-lower)
          figure5-texts))
(define case-texts (list base-text base-upper base-mixed))

(test-begin "unique-id-text")

;; --- 1. The RFC's texts -----------------------------------------------------

(test-equal "string->uuid: RFC 9562 A.6, Figure 26, upper case"
  (list 'id (text->octets a6-lower))
  (parse a6-upper))

(test-equal "uuid->string: RFC 9562 A.6, Figure 26, the upper-case text prints in lower case"
  (list 'value a6-lower)
  (round-text a6-upper))

(test-equal "uuid-v7-timestamp: RFC 9562 A.6, Figure 26, 0x017F22E279B0 or 1645557742000"
  (list 'value 1645557742000)
  (value-of (lambda () (uuid-v7-timestamp (string->uuid a6-upper)))))

(test-equal "string->uuid: RFC 9562 A.3, Figure 20"
  (list 'id (text->octets a3-text))
  (parse a3-text))

(test-equal "uuid->string: RFC 9562 A.3, Figure 20, prints back"
  (list 'value a3-text)
  (round-text a3-text))

(test-equal "string->uuid: RFC 9562 section 4, Figure 1"
  (list 'id (text->octets figure1-text))
  (parse figure1-text))

(test-equal "string->uuid: RFC 9562 section 4, Figures 1 and 3, as a big-endian integer"
  (list 'value 329800735698586629295641978511506172918)
  (value-of (lambda ()
              (bytevector-uint-ref (uuid->bytevector (string->uuid figure1-text))
                                   0 (endianness big) 16))))

(for-each
 (lambda (text)
   (test-equal (string-append "string->uuid: RFC 9562 section 4.2, Figure 5, " text)
     (list 'id (text->octets text))
     (parse text))
   (test-equal (string-append "uuid->string: RFC 9562 section 4.2, Figure 5, " text
                              " prints in lower case")
     (list 'value (string-downcase text))
     (round-text text)))
 figure5-texts)

(test-equal "uuid->string: RFC 9562 section 5.9, nil-uuid"
  (list 'value nil-text)
  (value-of (lambda () (uuid->string nil-uuid))))

(test-equal "string->uuid: RFC 9562 section 5.9, the nil text is nil-uuid"
  (list 'value #t)
  (value-of (lambda () (uuid=? (string->uuid nil-text) nil-uuid))))

(test-equal "uuid->string: RFC 9562 section 5.10, max-uuid prints in lower case"
  (list 'value max-lower)
  (value-of (lambda () (uuid->string max-uuid))))

(test-equal "string->uuid: RFC 9562 section 5.10, the upper-case text is max-uuid"
  (list 'value #t)
  (value-of (lambda () (uuid=? (string->uuid max-upper) max-uuid))))

;; --- 2. Case ----------------------------------------------------------------

(test-equal "string->uuid: all lower case"
  (list 'id base-octets)
  (parse base-text))

(test-equal "string->uuid: all upper case, the same octets"
  (list 'id base-octets)
  (parse base-upper))

(test-equal "string->uuid: mixed case, the same octets"
  (list 'id base-octets)
  (parse base-mixed))

;; --- 3. Every hex digit in every position -----------------------------------

(test-equal "string->uuid: every hex digit at every digit index, 32 by 22 cases, none failing"
  '()
  (failures-of
   (cross (iota* 32) hex-chars)
   (lambda (case)
     (let* ((k (car case))
            (c (cadr case))
            (expected (list 'id (set-nibble base-octets k (nibble-of c))))
            (actual (parse (replace-at base-text (digit-index->text-index k) c))))
       (if (equal? actual expected)
           #f
           (list k (char->integer c) actual))))))

;; --- 4. Every refusal by position -------------------------------------------

;; refusal-failures : (Listof Nat) (Listof Char) -> (Listof (List Nat Nat Any))
;; The failures of string->uuid to refuse base-text with the character at an
;; index of INDEXES replaced by a character of CHARS: each is the index, the
;; character's code point and what parse answered.
(define (refusal-failures indexes chars)
  (failures-of
   (cross indexes chars)
   (lambda (case)
     (let* ((i (car case))
            (c (cadr case))
            (actual (parse (replace-at base-text i c))))
       (if (equal? actual (list 'no-id))
           #f
           (list i (char->integer c) actual))))))

(test-equal "string->uuid: no id for a non-digit at any digit index, none failing"
  '()
  (refusal-failures
   (filter (lambda (i) (not (memv i hyphen-indexes))) (iota* 36))
   bad-digit-chars))

(test-equal "string->uuid: no id for a non-hyphen at any hyphen index, none failing"
  '()
  (refusal-failures hyphen-indexes bad-hyphen-chars))

;; --- 5. Lengths -------------------------------------------------------------

(test-equal "string->uuid: no id for any length 0 to 72 but 36, none failing"
  '()
  (failures-of
   (filter (lambda (n) (not (= n 36))) (iota* 73))
   (lambda (n)
     (let ((texts
            (if (< n 36)
                (list (list 'prefix (substring base-text 0 n))
                      (list 'suffix (substring base-text (- 36 n) 36)))
                (list (list 'appended (string-append base-text (padding (- n 36))))
                      (list 'prepended (string-append (padding (- n 36)) base-text))))))
       (let ((bad (failures-of
                   texts
                   (lambda (kind+text)
                     (let ((actual (parse (cadr kind+text))))
                       (if (equal? actual (list 'no-id))
                           #f
                           (list (car kind+text) actual)))))))
         (if (null? bad) #f (list n bad)))))))

;; strip-hyphens : String -> String
;; TEXT without its hyphens.
(define (strip-hyphens text)
  (list->string (filter (lambda (c) (not (char=? c #\-))) (string->list text))))

(test-equal "string->uuid: no id for 32 digits with no hyphen"
  (list 'no-id)
  (parse (strip-hyphens base-text)))

(test-equal "string->uuid: no id for a text in braces"
  (list 'no-id)
  (parse (string-append "{" base-text "}")))

(test-equal "string->uuid: no id for a urn:uuid: prefix"
  (list 'no-id)
  (parse (string-append "urn:uuid:" base-text)))

(test-equal "string->uuid: no id for a leading space"
  (list 'no-id)
  (parse (string-append " " base-text)))

(test-equal "string->uuid: no id for a trailing space"
  (list 'no-id)
  (parse (string-append base-text " ")))

(test-equal "string->uuid: no id for two valid texts run together"
  (list 'no-id)
  (parse (string-append base-text a3-text)))

;; --- 6. Hyphens moved -------------------------------------------------------

(test-equal "string->uuid: no id for a hyphen swapped with a neighbour, none failing"
  '()
  (failures-of
   (cross hyphen-indexes '(-1 1))
   (lambda (case)
     (let* ((h (car case))
            (j (+ h (cadr case)))
            (s (list->string
                (map (lambda (x i)
                       (cond ((= i h) (string-ref base-text j))
                             ((= i j) (string-ref base-text h))
                             (else x)))
                     (string->list base-text)
                     (iota* 36))))
            (actual (parse s)))
       (if (equal? actual (list 'no-id))
           #f
           (list h j actual))))))

;; --- 7. A non-string given to string->uuid ----------------------------------

;; string->uuid-violation : (-> Any)
;;     -> (U (List 'assertion-violation Any Boolean) (List 'returned) (List 'raised Any))
;; What violation makes of string->uuid called on the value MAKE-ARG makes.
(define (string->uuid-violation make-arg)
  (violation string->uuid make-arg))

(test-equal "string->uuid: a symbol is an assertion violation"
  (list 'assertion-violation 'string->uuid #t)
  (string->uuid-violation (lambda () 'abc)))

(test-equal "string->uuid: a char is an assertion violation"
  (list 'assertion-violation 'string->uuid #t)
  (string->uuid-violation (lambda () #\a)))

(test-equal "string->uuid: #f is an assertion violation"
  (list 'assertion-violation 'string->uuid #t)
  (string->uuid-violation (lambda () #f)))

(test-equal "string->uuid: a 36-byte bytevector is an assertion violation"
  (list 'assertion-violation 'string->uuid #t)
  (string->uuid-violation (lambda () (make-bytevector 36 48))))

(test-equal "string->uuid: a list of 36 chars is an assertion violation"
  (list 'assertion-violation 'string->uuid #t)
  (string->uuid-violation (lambda () (string->list base-text))))

(test-equal "string->uuid: an id is an assertion violation"
  (list 'assertion-violation 'string->uuid #t)
  (string->uuid-violation
   (lambda () (bytevector->uuid (u8-list->bytevector base-octets)))))

;; --- 8. uuid->string --------------------------------------------------------

(test-equal "uuid->string: the id of 16 octets all v, v from 0 to 255, none failing"
  '()
  (failures-of
   (iota* 256)
   (lambda (v)
     (let ((actual (id-text (repeat 16 v)))
           (expected (list 'value (octets->text (repeat 16 v)))))
       (if (equal? actual expected) #f (list v actual))))))

(test-equal "uuid->string: the ids of octet i = (i * 17 + k) mod 256, k from 0 to 15, none failing"
  '()
  (failures-of
   (iota* 16)
   (lambda (k)
     (let ((actual (id-text (pattern-octets k)))
           (expected (list 'value (octets->text (pattern-octets k)))))
       (if (equal? actual expected) #f (list k actual))))))

(test-equal "uuid->string: two answers for one id are not eq?"
  (list 'value #f)
  (value-of
   (lambda ()
     (let* ((id (bytevector->uuid (u8-list->bytevector (pattern-octets 3))))
            (first (uuid->string id))
            (second (uuid->string id)))
       (eq? first second)))))

(test-equal "uuid->string: changing one answer leaves the next unchanged"
  (list 'value "03142536-4758-697a-8b9c-adbecfe0f102")
  (value-of
   (lambda ()
     (let* ((id (bytevector->uuid (u8-list->bytevector (pattern-octets 3))))
            (first (uuid->string id)))
       (string-set! first 0 #\x)
       (uuid->string id)))))

;; --- 9. A non-id given to uuid->string --------------------------------------

;; uuid->string-violation : (-> Any)
;;     -> (U (List 'assertion-violation Any Boolean) (List 'returned) (List 'raised Any))
;; What violation makes of uuid->string called on the value MAKE-ARG makes.
(define (uuid->string-violation make-arg)
  (violation uuid->string make-arg))

(test-equal "uuid->string: a 16-byte bytevector is an assertion violation"
  (list 'assertion-violation 'uuid->string #t)
  (uuid->string-violation (lambda () (u8-list->bytevector base-octets))))

(test-equal "uuid->string: the text of an id is an assertion violation"
  (list 'assertion-violation 'uuid->string #t)
  (uuid->string-violation (lambda () base-text)))

(test-equal "uuid->string: #f is an assertion violation"
  (list 'assertion-violation 'uuid->string #t)
  (uuid->string-violation (lambda () #f)))

;; --- 10. Round trips --------------------------------------------------------

(test-equal "text, id, text: lower-cases the RFC and case texts, none failing"
  '()
  (failures-of
   (append rfc-texts case-texts)
   (lambda (text)
     (let ((actual (round-text text))
           (expected (list 'value (string-downcase text))))
       (if (equal? actual expected) #f (list text actual))))))

;; bytes-round : (Listof Nat) -> (U (List 'value (Listof Nat)) (List 'raised Any))
;; The octets of the id that text from the id of OCTETS spells.
(define (bytes-round octets)
  (value-of
   (lambda ()
     (let* ((id (bytevector->uuid (u8-list->bytevector octets)))
            (text (uuid->string id))
            (id2 (string->uuid text)))
       (bytevector->u8-list (uuid->bytevector id2))))))

;; bytes-round-failures : (Listof (Listof Nat)) -> (Listof (List (Listof Nat) Any))
;; The members of PATTERNS, 16 octets each, that bytes-round does not answer
;; as themselves, each with what it answered.
(define (bytes-round-failures patterns)
  (failures-of
   patterns
   (lambda (octets)
     (let ((actual (bytes-round octets)))
       (if (equal? actual (list 'value octets)) #f (list octets actual))))))

(test-equal "bytes, id, text, id, bytes: 16 octets all v, v from 0 to 255, none failing"
  '()
  (bytes-round-failures (map (lambda (v) (repeat 16 v)) (iota* 256))))

(test-equal "bytes, id, text, id, bytes: octet i = (i * 17 + k) mod 256, k from 0 to 15, none failing"
  '()
  (bytes-round-failures (map pattern-octets (iota* 16))))

(test-end "unique-id-text")

(exit (suite-exit-status runner))
