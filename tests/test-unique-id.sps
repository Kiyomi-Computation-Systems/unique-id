#!r6rs
;;; (unique-id): the id record and its bytes, the nil and max ids, version,
;;; variant and v7 timestamp, and the two constructors make-uuid-v4 and
;;; make-uuid-v7.
;;;
;;; Every call into the library runs under a guard that tags what happened:
;;; (value V) with ids turned to text, (violation WHO IRRITANT-OK?) for an
;;; assertion violation, or (raised) for anything else. Ids are compared as
;;; text or as bytes, never with equal?. Text parsing, uuid=?, uuid<?,
;;; uuid-hash and order belong to other suites; string->uuid and uuid->string
;;; only build and check ids here.
(import (rnrs)
        (srfi :64)
        (unique-id)
        (unique-id-testing))

(define runner (test-runner-simple))
(test-runner-current runner)

;; --- helpers ----------------------------------------------------------------

;; norm : Any -> Any
;; V, with an id turned into its canonical text.
(define (norm v)
  (if (uuid? v) (uuid->string v) v))

;; attempt : (-> Any) -> (U (List 'value Any) (List 'raised))
;; (value V) with V normalised when THUNK answers V, (raised) when it raises
;; anything.
(define (attempt thunk)
  (guard (e (#t (list 'raised)))
    (list 'value (norm (thunk)))))

;; attempt-error : (-> (Listof Any)) Any Nat
;;                 -> (U (List 'violation Symbol Boolean) (List 'value Any) (List 'raised))
;; Applies the procedure PROC to the list MAKE-ARGS answers. An assertion
;; violation gives (violation WHO OK?): OK? is #t when its irritants are a
;; one-element list whose element is eqv? to argument number K, counted
;; from 0.
(define (attempt-error make-args proc k)
  (let ((args '()))
    (guard (e ((assertion-violation? e)
               (list 'violation
                     (and (who-condition? e) (condition-who e))
                     (and (irritants-condition? e)
                          (let ((irritants (condition-irritants e)))
                            (and (list? irritants)
                                 (= 1 (length irritants))
                                 (eqv? (car irritants) (list-ref args k)))))))
              (#t (list 'raised)))
      (set! args (make-args))
      (list 'value (norm (apply proc args))))))

;; hex->bytevector : String -> Bytevector
;; The bytes TEXT spells, two hex digits each.
(define (hex->bytevector text)
  (let* ((n (div (string-length text) 2))
         (bv (make-bytevector n 0)))
    (do ((i 0 (+ i 1)))
        ((= i n) bv)
      (bytevector-u8-set! bv i
                          (string->number (substring text (* 2 i) (+ 2 (* 2 i))) 16)))))

;; with-octet : Bytevector Nat Nat -> Bytevector
;; A copy of BV whose octet I is V.
(define (with-octet bv i v)
  (let ((c (bytevector-copy bv)))
    (bytevector-u8-set! c i v)
    c))

;; sample : Bytevector
;; 16 octets, none 0; octet 6 is #xCD and octet 8 is #xFE.
(define sample
  (u8-list->bytevector
   '(#x01 #x23 #x45 #x67 #x89 #xAB #xCD #xEF #xFE #xDC #xBA #x98 #x76 #x54 #x32 #x10)))

;; sample8 : Bytevector
;; 8 octets, none 0.
(define sample8
  (u8-list->bytevector '(#x18 #xC4 #xDC #x0C #x0C #x07 #x39 #x8F)))

;; sample-copy : -> Bytevector
;; A fresh copy of SAMPLE.
(define (sample-copy) (bytevector-copy sample))

;; two48 : Nat
;; 2^48, one more than the largest v7 timestamp.
(define two48 (expt 2 48))

;; octets-of : Bytevector -> (-> Bytevector)
;; A thunk: the octets of the id BV makes.
(define (octets-of bv)
  (lambda () (uuid->bytevector (bytevector->uuid bv))))

;; make-lcg : Nat -> (-> Nat)
;; A seeded generator. Each call steps
;; state' = (1664525 * state + 1013904223) mod 2^32 and answers state' >> 24,
;; an octet.
(define (make-lcg seed)
  (let ((state seed))
    (lambda ()
      (set! state (mod (+ (* 1664525 state) 1013904223) 4294967296))
      (bitwise-arithmetic-shift-right state 24))))

;; draw-octets : (-> Nat) Nat -> (Listof Nat)
;; N octets from NEXT, in the order drawn.
(define (draw-octets next n)
  (let loop ((k 0) (acc '()))
    (if (= k n)
        (reverse acc)
        (let ((o (next)))
          (loop (+ k 1) (cons o acc))))))

;; octets->nat : (Listof Nat) -> Nat
;; The big-endian unsigned integer OCTETS spell.
(define (octets->nat octets)
  (let loop ((rest octets) (n 0))
    (if (null? rest)
        n
        (loop (cdr rest) (+ (* 256 n) (car rest))))))

;; failing-cases : Nat Nat ((-> Nat) -> Any) (Any -> Boolean)
;;                 -> (Listof (List Nat Symbol Any))
;; Runs N cases from the LCG seeded with SEED: GEN draws a case's inputs, and
;; CHECK answers whether they pass. A failing case is (INDEX wrong INPUTS), or
;; (INDEX raised INPUTS) when CHECK raised.
(define (failing-cases seed n gen check)
  (let ((next (make-lcg seed)))
    (let loop ((i 0) (acc '()))
      (if (= i n)
          (reverse acc)
          (let* ((inputs (gen next))
                 (verdict (guard (e (#t 'raised))
                            (if (check inputs) 'ok 'wrong))))
            (loop (+ i 1)
                  (if (eq? verdict 'ok)
                      acc
                      (cons (list i verdict inputs) acc))))))))

(test-begin "unique-id")

;; --- uuid? ------------------------------------------------------------------

(for-each
 (lambda (entry)
   (test-equal (string-append "uuid?: #t for an id from " (car entry))
     '(value #t)
     (attempt (lambda () (uuid? ((cdr entry)))))))
 (list (cons "bytevector->uuid" (lambda () (bytevector->uuid (sample-copy))))
       (cons "string->uuid"
             (lambda () (string->uuid "f81d4fae-7dec-11d0-a765-00a0c91e6bf6")))
       (cons "make-uuid-v4" (lambda () (make-uuid-v4 (sample-copy))))
       (cons "make-uuid-v7" (lambda () (make-uuid-v7 #x017F22E279B0 #xCC3 sample8)))
       (cons "nil-uuid" (lambda () nil-uuid))
       (cons "max-uuid" (lambda () max-uuid))))

(for-each
 (lambda (entry)
   (test-equal (string-append "uuid?: #f for " (car entry))
     '(value #f)
     (attempt (lambda () (uuid? ((cdr entry)))))))
 (list (cons "a 16-byte bytevector" (lambda () (sample-copy)))
       (cons "an id's 36-character text"
             (lambda () "f81d4fae-7dec-11d0-a765-00a0c91e6bf6"))
       (cons "#f" (lambda () #f))
       (cons "a symbol" (lambda () 'uuid))
       (cons "a list of 16 octets" (lambda () (bytevector->u8-list sample)))))

;; --- record? ----------------------------------------------------------------

(test-equal "record?: #f for an id, whose record is opaque"
  '(value #f)
  (attempt (lambda () (record? (bytevector->uuid (sample-copy))))))

;; --- bytevector->uuid and uuid->bytevector ----------------------------------

(test-equal "uuid->bytevector: the octets bytevector->uuid was given"
  (list 'value sample)
  (attempt (octets-of (sample-copy))))

(test-equal "bytevector->uuid: the id keeps its own copy of BYTES"
  (list 'value sample)
  (attempt (lambda ()
             (let* ((bytes (sample-copy))
                    (id (bytevector->uuid bytes)))
               (bytevector-u8-set! bytes 0 #xAA)
               (bytevector-u8-set! bytes 15 #xBB)
               (uuid->bytevector id)))))

(test-equal "uuid->bytevector: changing one answer leaves the next unchanged"
  (list 'value sample)
  (attempt (lambda ()
             (let* ((id (bytevector->uuid (sample-copy)))
                    (first (uuid->bytevector id)))
               (bytevector-u8-set! first 0 #xAA)
               (bytevector-u8-set! first 9 #xBB)
               (uuid->bytevector id)))))

(test-equal "uuid->bytevector: two answers are not eq?"
  '(value #f)
  (attempt (lambda ()
             (let* ((id (bytevector->uuid (sample-copy)))
                    (first (uuid->bytevector id))
                    (second (uuid->bytevector id)))
               (eq? first second)))))

;; --- byte order -------------------------------------------------------------

(test-equal "bytevector->uuid: RFC 9562 §4, Figure 3's integer is Figure 1's text"
  '(value "f81d4fae-7dec-11d0-a765-00a0c91e6bf6")
  (attempt (lambda ()
             (let ((bytes (make-bytevector 16 0)))
               (bytevector-uint-set! bytes 0 329800735698586629295641978511506172918
                                     (endianness big) 16)
               (bytevector->uuid bytes)))))

(test-equal "uuid->bytevector: RFC 9562 §4, Figure 1's octets, octet 0 first"
  (list 'value (hex->bytevector "f81d4fae7dec11d0a76500a0c91e6bf6"))
  (attempt (lambda ()
             (uuid->bytevector
              (string->uuid "f81d4fae-7dec-11d0-a765-00a0c91e6bf6")))))

;; --- bytevector->uuid errors ------------------------------------------------

(for-each
 (lambda (entry)
   (test-equal (string-append "bytevector->uuid: assertion violation for " (car entry))
     '(violation bytevector->uuid #t)
     (attempt-error (lambda () (list ((cdr entry)))) bytevector->uuid 0)))
 (list (cons "0 bytes" (lambda () (make-bytevector 0 7)))
       (cons "15 bytes" (lambda () (make-bytevector 15 7)))
       (cons "17 bytes" (lambda () (make-bytevector 17 7)))
       (cons "a string" (lambda () "0123456789abcdef"))
       (cons "a list of 16 octets" (lambda () (bytevector->u8-list sample)))
       (cons "an id" (lambda () (bytevector->uuid (sample-copy))))))

;; --- non-ids ----------------------------------------------------------------

(for-each
 (lambda (proc-entry)
   (for-each
    (lambda (arg-entry)
      (test-equal (string-append (symbol->string (car proc-entry)) ": assertion violation for "
                                 (car arg-entry))
        (list 'violation (car proc-entry) #t)
        (attempt-error (lambda () (list ((cdr arg-entry)))) (cdr proc-entry) 0)))
    (list (cons "a 16-byte bytevector" (lambda () (sample-copy)))
          (cons "an id's text" (lambda () "f81d4fae-7dec-11d0-a765-00a0c91e6bf6"))
          (cons "#f" (lambda () #f)))))
 (list (cons 'uuid->bytevector uuid->bytevector)
       (cons 'uuid-version uuid-version)
       (cons 'uuid-variant uuid-variant)
       (cons 'uuid-v7-timestamp uuid-v7-timestamp)))

;; --- nil and max ----------------------------------------------------------

(test-equal "nil-uuid: RFC 9562 §5.9, 16 octets of 0"
  (list 'value (make-bytevector 16 0))
  (attempt (lambda () (uuid->bytevector nil-uuid))))

(test-equal "max-uuid: RFC 9562 §5.10, 16 octets of #xFF"
  (list 'value (make-bytevector 16 #xFF))
  (attempt (lambda () (uuid->bytevector max-uuid))))

(test-equal "nil-uuid: RFC 9562 §5.9, variant ncs, so no version"
  '(value #f)
  (attempt (lambda () (uuid-version nil-uuid))))

(test-equal "nil-uuid: RFC 9562 §5.9, variant ncs"
  '(value ncs)
  (attempt (lambda () (uuid-variant nil-uuid))))

(test-equal "max-uuid: RFC 9562 §5.10, variant future, so no version"
  '(value #f)
  (attempt (lambda () (uuid-version max-uuid))))

(test-equal "max-uuid: RFC 9562 §5.10, variant future"
  '(value future)
  (attempt (lambda () (uuid-variant max-uuid))))

(test-equal "nil-uuid: no v7 timestamp"
  '(value #f)
  (attempt (lambda () (uuid-v7-timestamp nil-uuid))))

(test-equal "max-uuid: no v7 timestamp"
  '(value #f)
  (attempt (lambda () (uuid-v7-timestamp max-uuid))))

;; --- uuid-version -----------------------------------------------------------

(test-equal "uuid-version: RFC 9562 §4, Figure 1 is 1"
  '(value 1)
  (attempt (lambda ()
             (uuid-version (string->uuid "f81d4fae-7dec-11d0-a765-00a0c91e6bf6")))))

(for-each
 (lambda (text)
   (test-equal (string-append "uuid-version: RFC 9562 §4.2, Figure 5's " text " is 4")
     '(value 4)
     (attempt (lambda () (uuid-version (string->uuid text))))))
 '("00000000-0000-4000-8000-000000000000"
   "00000000-0000-4000-9000-000000000000"
   "00000000-0000-4000-a000-000000000000"
   "00000000-0000-4000-b000-000000000000"))

(let loop ((n 0))
  (when (< n 16)
    (test-equal (string-append "uuid-version: variant rfc9562 (octet 8 #x80, #x9B, #xBF), octet 6's high nibble "
                               (number->string n) " is " (number->string n))
      (map (lambda (o8) (list 'value n)) '(#x80 #x9B #xBF))
      (map (lambda (o8)
             (attempt (lambda ()
                        (uuid-version
                         (bytevector->uuid
                          (with-octet (with-octet sample 6 (+ (* 16 n) 11)) 8 o8))))))
           '(#x80 #x9B #xBF)))
    (test-equal (string-append "uuid-version: any other variant (octet 8 #x35, #x7F, #xC0, #xD7, #xE0, #xF9), octet 6's high nibble "
                               (number->string n) " gives no version")
      (map (lambda (o8) '(value #f)) '(#x35 #x7F #xC0 #xD7 #xE0 #xF9))
      (map (lambda (o8)
             (attempt (lambda ()
                        (uuid-version
                         (bytevector->uuid
                          (with-octet (with-octet sample 6 (+ (* 16 n) 11)) 8 o8))))))
           '(#x35 #x7F #xC0 #xD7 #xE0 #xF9)))
    (loop (+ n 1))))

;; --- uuid-variant -----------------------------------------------------------

(test-equal "uuid-variant: RFC 9562 §4, Figure 1 is rfc9562"
  '(value rfc9562)
  (attempt (lambda ()
             (uuid-variant (string->uuid "f81d4fae-7dec-11d0-a765-00a0c91e6bf6")))))

(for-each
 (lambda (text)
   (test-equal (string-append "uuid-variant: RFC 9562 §4.2, Figure 5's " text " is rfc9562")
     '(value rfc9562)
     (attempt (lambda () (uuid-variant (string->uuid text))))))
 '("00000000-0000-4000-8000-000000000000"
   "00000000-0000-4000-9000-000000000000"
   "00000000-0000-4000-a000-000000000000"
   "00000000-0000-4000-b000-000000000000"))

;; model-variant : Nat -> Symbol
;; RFC 9562 §4.1, Table 1, read off bits 7, 6 and 5 of octet 8's value B.
(define (model-variant b)
  (cond ((not (bitwise-bit-set? b 7)) 'ncs)
        ((not (bitwise-bit-set? b 6)) 'rfc9562)
        ((not (bitwise-bit-set? b 5)) 'microsoft)
        (else 'future)))

(test-equal "uuid-variant: RFC 9562 §4.1, Table 1, all 256 values of octet 8: failures"
  '()
  (let loop ((b 0) (acc '()))
    (if (= b 256)
        (reverse acc)
        (let ((got (attempt (lambda ()
                              (uuid-variant (bytevector->uuid (with-octet sample 8 b)))))))
          (loop (+ b 1)
                (if (equal? got (list 'value (model-variant b)))
                    acc
                    (cons (list b got) acc)))))))

;; --- uuid-v7-timestamp ------------------------------------------------------

(test-equal "uuid-v7-timestamp: RFC 9562 A.6, Figure 26 made by make-uuid-v7"
  '(value 1645557742000)
  (attempt (lambda ()
             (uuid-v7-timestamp (make-uuid-v7 #x017F22E279B0 #xCC3 sample8)))))

(test-equal "uuid-v7-timestamp: RFC 9562 A.6, the RFC's own upper-case text"
  '(value 1645557742000)
  (attempt (lambda ()
             (uuid-v7-timestamp
              (string->uuid "017F22E2-79B0-7CC3-98C4-DC0C0C07398F")))))

(for-each
 (lambda (entry)
   (test-equal (string-append "uuid-v7-timestamp: version 7, octet 8 " (car entry))
     (cadr entry)
     (attempt (lambda ()
                (uuid-v7-timestamp
                 (bytevector->uuid
                  (with-octet (with-octet sample 6 #x7B) 8 (cddr entry))))))))
 '(("#x7F, just below rfc9562" . ((value #f) . #x7F))
   ("#x80, the first rfc9562" . ((value #x0123456789AB) . #x80))
   ("#xBF, the last rfc9562" . ((value #x0123456789AB) . #xBF))
   ("#xC0, just above rfc9562" . ((value #f) . #xC0))))

(for-each
 (lambda (entry)
   (test-equal (string-append "uuid-v7-timestamp: #f for version 7 with variant " (car entry))
     '(value #f)
     (attempt (lambda ()
                (uuid-v7-timestamp
                 (bytevector->uuid
                  (with-octet (with-octet sample 6 #x7B) 8 (cdr entry))))))))
 '(("ncs" . #x35) ("microsoft" . #xD7) ("future" . #xF9)))

(let loop ((v 0))
  (when (< v 16)
    (unless (= v 7)
      (test-equal (string-append "uuid-v7-timestamp: #f for version " (number->string v)
                                 " with variant rfc9562")
        '(value #f)
        (attempt (lambda ()
                   (uuid-v7-timestamp
                    (bytevector->uuid
                     (with-octet (with-octet sample 6 (+ (* 16 v) 11)) 8 #x9B)))))))
    (loop (+ v 1))))

(test-equal "uuid-v7-timestamp: #f for RFC 9562 §4, Figure 1, a v1 id"
  '(value #f)
  (attempt (lambda ()
             (uuid-v7-timestamp (string->uuid "f81d4fae-7dec-11d0-a765-00a0c91e6bf6")))))

(test-equal "uuid-v7-timestamp: 0 for make-uuid-v7 with MS 0"
  '(value 0)
  (attempt (lambda () (uuid-v7-timestamp (make-uuid-v7 0 #xABC sample8)))))

(test-equal "uuid-v7-timestamp: 2^48-1 for make-uuid-v7 with MS 2^48-1"
  (list 'value (- two48 1))
  (attempt (lambda () (uuid-v7-timestamp (make-uuid-v7 (- two48 1) #xABC sample8)))))

;; --- make-uuid-v4 -----------------------------------------------------------

(test-equal "make-uuid-v4: RFC 9562 A.3, Figure 20"
  '(value "919108f7-52d1-4320-9bac-f847db4148a8")
  (attempt (lambda ()
             (make-uuid-v4 (hex->bytevector "919108F752D133205BACF847DB4148A8")))))

(test-equal "make-uuid-v4: RFC 9562 A.3, Figure 20, BYTES is unchanged"
  (list 'value (hex->bytevector "919108F752D133205BACF847DB4148A8"))
  (attempt (lambda ()
             (let ((bytes (hex->bytevector "919108F752D133205BACF847DB4148A8")))
               (make-uuid-v4 bytes)
               bytes))))

(test-equal "make-uuid-v4: changing BYTES afterwards leaves the id unchanged"
  '(value "919108f7-52d1-4320-9bac-f847db4148a8")
  (attempt (lambda ()
             (let* ((bytes (hex->bytevector "919108F752D133205BACF847DB4148A8"))
                    (id (make-uuid-v4 bytes)))
               (bytevector-u8-set! bytes 0 #x11)
               (bytevector-u8-set! bytes 6 #x22)
               (bytevector-u8-set! bytes 8 #x33)
               id))))

(test-equal "make-uuid-v4: property, seed 20261122, 1500 cases: version 4, variant rfc9562, the other 122 bits BYTES'"
  '()
  (failing-cases
   20261122 1500
   (lambda (next) (draw-octets next 16))
   (lambda (octets)
     (let* ((in (u8-list->bytevector octets))
            (id (make-uuid-v4 in))
            (out (uuid->bytevector id)))
       (and (= 16 (bytevector-length out))
            (= 4 (uuid-version id))
            (eq? 'rfc9562 (uuid-variant id))
            (= (bitwise-and (bytevector-u8-ref out 6) 15)
               (bitwise-and (bytevector-u8-ref in 6) 15))
            (= (bitwise-and (bytevector-u8-ref out 8) 63)
               (bitwise-and (bytevector-u8-ref in 8) 63))
            (let loop ((i 0))
              (cond ((= i 16) #t)
                    ((or (= i 6) (= i 8)) (loop (+ i 1)))
                    ((= (bytevector-u8-ref out i) (bytevector-u8-ref in i))
                     (loop (+ i 1)))
                    (else #f))))))))

;; --- make-uuid-v4 errors ----------------------------------------------------

(for-each
 (lambda (entry)
   (test-equal (string-append "make-uuid-v4: assertion violation for " (car entry))
     '(violation make-uuid-v4 #t)
     (attempt-error (lambda () (list ((cdr entry)))) make-uuid-v4 0)))
 (list (cons "0 bytes" (lambda () (make-bytevector 0 7)))
       (cons "15 bytes" (lambda () (make-bytevector 15 7)))
       (cons "17 bytes" (lambda () (make-bytevector 17 7)))
       (cons "a string" (lambda () "0123456789abcdef"))
       (cons "a list of 16 octets" (lambda () (bytevector->u8-list sample)))
       (cons "an id" (lambda () (bytevector->uuid (sample-copy))))))

;; --- make-uuid-v7 -----------------------------------------------------------

(for-each
 (lambda (entry)
   (test-equal (string-append "make-uuid-v7: RFC 9562 A.6, Figure 26, BYTES " (car entry))
     '(value "017f22e2-79b0-7cc3-98c4-dc0c0c07398f")
     (attempt (lambda ()
                (make-uuid-v7 #x017F22E279B0 #xCC3 (hex->bytevector (cdr entry)))))))
 '(("18C4DC0C0C07398F" . "18C4DC0C0C07398F")
   ("58C4DC0C0C07398F" . "58C4DC0C0C07398F")
   ("98C4DC0C0C07398F" . "98C4DC0C0C07398F")
   ("D8C4DC0C0C07398F" . "D8C4DC0C0C07398F")))

(test-equal "make-uuid-v7: lowest bounds, MS 0, COUNTER 0, BYTES of #x00"
  '(value "00000000-0000-7000-8000-000000000000")
  (attempt (lambda () (make-uuid-v7 0 0 (make-bytevector 8 0)))))

(test-equal "make-uuid-v7: highest bounds, MS 2^48-1, COUNTER 4095, BYTES of #xFF"
  '(value "ffffffff-ffff-7fff-bfff-ffffffffffff")
  (attempt (lambda () (make-uuid-v7 (- two48 1) 4095 (make-bytevector 8 #xFF)))))

(test-equal "make-uuid-v7: RFC 9562 A.6, Figure 26, BYTES is unchanged"
  (list 'value (hex->bytevector "D8C4DC0C0C07398F"))
  (attempt (lambda ()
             (let ((bytes (hex->bytevector "D8C4DC0C0C07398F")))
               (make-uuid-v7 #x017F22E279B0 #xCC3 bytes)
               bytes))))

(test-equal "make-uuid-v7: property, seed 77031, 1500 cases: version 7, variant rfc9562, MS, COUNTER and BYTES in place"
  '()
  (failing-cases
   77031 1500
   (lambda (next)
     (let* ((ms (octets->nat (draw-octets next 6)))
            (counter (bitwise-and #xFFF (octets->nat (draw-octets next 2))))
            (octets (draw-octets next 8)))
       (list ms counter octets)))
   (lambda (inputs)
     (let* ((ms (car inputs))
            (counter (cadr inputs))
            (in (u8-list->bytevector (caddr inputs)))
            (id (make-uuid-v7 ms counter in))
            (out (uuid->bytevector id)))
       (and (= 16 (bytevector-length out))
            (= 7 (uuid-version id))
            (eq? 'rfc9562 (uuid-variant id))
            (eqv? ms (uuid-v7-timestamp id))
            (= ms (bytevector-uint-ref out 0 (endianness big) 6))
            (= counter (+ (* 256 (bitwise-and (bytevector-u8-ref out 6) 15))
                          (bytevector-u8-ref out 7)))
            (= (bitwise-and (bytevector-u8-ref out 8) 63)
               (bitwise-and (bytevector-u8-ref in 0) 63))
            (let loop ((i 9))
              (cond ((= i 16) #t)
                    ((= (bytevector-u8-ref out i) (bytevector-u8-ref in (- i 8)))
                     (loop (+ i 1)))
                    (else #f))))))))

;; --- make-uuid-v7 errors ----------------------------------------------------

;; v7-error : Nat (Listof Any)
;;            -> (U (List 'violation Symbol Boolean) (List 'value Any) (List 'raised))
;; make-uuid-v7's outcome for ARGS, the irritant being argument number K.
(define (v7-error k args)
  (attempt-error (lambda () args) make-uuid-v7 k))

;; good-ms : Nat
;; A valid MS: Figure 26's.
(define good-ms #x017F22E279B0)

;; good-counter : Nat
;; A valid COUNTER: Figure 26's.
(define good-counter #xCC3)

(for-each
 (lambda (entry)
   (test-equal (string-append "make-uuid-v7: assertion violation for MS " (car entry))
     '(violation make-uuid-v7 #t)
     (v7-error 0 (list (cdr entry) good-counter sample8))))
 (list (cons "-1" -1)
       (cons "2^48" two48)
       (cons "1.0" 1.0)
       (cons "1/2" (/ 1 2))
       (cons "the symbol a" 'a)
       (cons "the string \"1\"" "1")))

(for-each
 (lambda (entry)
   (test-equal (string-append "make-uuid-v7: assertion violation for COUNTER " (car entry))
     '(violation make-uuid-v7 #t)
     (v7-error 1 (list good-ms (cdr entry) sample8))))
 (list (cons "-1" -1)
       (cons "4096" 4096)
       (cons "2.0" 2.0)
       (cons "3/2" (/ 3 2))
       (cons "the symbol b" 'b)))

(for-each
 (lambda (entry)
   (test-equal (string-append "make-uuid-v7: assertion violation for BYTES " (car entry))
     '(violation make-uuid-v7 #t)
     (v7-error 2 (list good-ms good-counter (cdr entry)))))
 (list (cons "of 7 bytes" (make-bytevector 7 9))
       (cons "of 9 bytes" (make-bytevector 9 9))
       (cons "of 16 bytes" (make-bytevector 16 9))
       (cons "a string" "abcdefgh")))

(test-equal "make-uuid-v7: MS and BYTES both bad, the irritant is MS"
  '(violation make-uuid-v7 #t)
  (v7-error 0 (list -1 good-counter (make-bytevector 7 9))))

(test-equal "make-uuid-v7: COUNTER and BYTES both bad, the irritant is COUNTER"
  '(violation make-uuid-v7 #t)
  (v7-error 1 (list good-ms 4096 (make-bytevector 7 9))))

(test-equal "make-uuid-v7: MS and COUNTER both bad, the irritant is MS"
  '(violation make-uuid-v7 #t)
  (v7-error 0 (list two48 4096 sample8)))

(test-end "unique-id")

(exit (suite-exit-status runner))
