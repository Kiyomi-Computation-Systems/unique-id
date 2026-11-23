#!r6rs
;;; (unique-id): make-uuid-hash, the keyed hash. HalfSipHash-2-4 of an id's 16
;;; octets under an 8-byte key, by the reference's own vectors and by
;;; properties drawn from seeded generators.
;;;
;;; Every call into the library runs under a guard that tags what happened:
;;; (value V), (violation WHO OK?) for an assertion violation, (error WHO OK?)
;;; for an `error`, (raised X) for anything else raised, and (raised-condition)
;;; for any other condition. OK? is #t when the one irritant is eqv? to the one
;;; expected. Each test's expected value is such an outcome, so a library that
;;; raises the wrong thing, or nothing, fails it. Ids are compared as bytes or
;;; text, never with equal?.
(import (rnrs)
        (srfi :64)
        (unique-id)
        (unique-id-testing))

(define runner (test-runner-simple))
(test-runner-current runner)

;; --- helpers ----------------------------------------------------------------

;; Types of this file:
;;   Condition  an R6RS condition.
;;   Outcome    what a tagged call did: (List 'value Any), (List 'violation
;;              (U Symbol #f) Boolean), (List 'error (U Symbol #f) Boolean),
;;              (List 'raised Any) or (List 'raised-condition).

;; who-of : Condition -> (U Symbol #f)
;; The who of the condition E, or #f when it has none.
(define (who-of e)
  (and (who-condition? e) (condition-who e)))

;; irritant-ok? : Condition Any -> Boolean
;; #t when the irritants of E are a list of one element, eqv? to IRRITANT.
(define (irritant-ok? e irritant)
  (and (irritants-condition? e)
       (let ((irritants (condition-irritants e)))
         (and (list? irritants)
              (= 1 (length irritants))
              (eqv? (car irritants) irritant)))))

;; classify : (-> Any) Any -> Outcome
;; What THUNK did, tagged. The tags are all distinct, and none is a bare #f.
(define (classify thunk irritant)
  (guard (e ((assertion-violation? e)
             (list 'violation (who-of e) (irritant-ok? e irritant)))
            ((error? e)
             (list 'error (who-of e) (irritant-ok? e irritant)))
            ((condition? e) (list 'raised-condition))
            (#t (list 'raised e)))
    (list 'value (thunk))))

;; hex->bytevector : String -> Bytevector
;; The bytes TEXT spells, two hex digits each.
(define (hex->bytevector text)
  (let* ((n (div (string-length text) 2))
         (bv (make-bytevector n 0)))
    (do ((i 0 (+ i 1)))
        ((= i n) bv)
      (bytevector-u8-set! bv i
                          (string->number (substring text (* 2 i) (+ 2 (* 2 i))) 16)))))

;; make-lcg : Nat -> (-> Nat)
;; A seeded generator. Each call steps
;; state' = (1664525 * state + 1013904223) mod 2^32 and answers state' >> 24,
;; an octet.
(define (make-lcg seed)
  (let ((state seed))
    (lambda ()
      (set! state (mod (+ (* 1664525 state) 1013904223) 4294967296))
      (bitwise-arithmetic-shift-right state 24))))

;; draw-bytes : (-> Nat) Nat -> Bytevector
;; N octets from NEXT, in the order drawn.
(define (draw-bytes next n)
  (let ((bv (make-bytevector n 0)))
    (do ((i 0 (+ i 1)))
        ((= i n) bv)
      (bytevector-u8-set! bv i (next)))))

;; count-distinct : (Listof Nat) -> Nat
;; How many different numbers LIST holds.
(define (count-distinct list)
  (let ((table (make-eqv-hashtable)))
    (for-each (lambda (n) (hashtable-set! table n #t)) list)
    (hashtable-size table)))

;; bytes-copy : Bytevector -> Bytevector
;; A fresh copy of BV.
(define (bytes-copy bv)
  (let ((copy (make-bytevector (bytevector-length bv) 0)))
    (bytevector-copy! bv 0 copy 0 (bytevector-length bv))
    copy))

;; hash-of : String String -> Outcome
;; The outcome of hashing the id spelled by hex ID-HEX, under the key spelled
;; by hex KEY-HEX.
(define (hash-of key-hex id-hex)
  (classify (lambda ()
              ((make-uuid-hash (hex->bytevector key-hex))
               (bytevector->uuid (hex->bytevector id-hex))))
            #f))

;; Keys and ids used more than once.
(define ref-key "0001020304050607")
(define a6-id "017f22e279b07cc398c4dc0c0c07398f")
(define zero-id "00000000000000000000000000000000")

;; vectors : (Listof (List String String Nat))
;; The (KEY-HEX ID-HEX ANSWER) of every vector this suite checks, the first
;; from vectors.h and the others from halfsiphash.c.
(define vectors
  (list
   (list ref-key "000102030405060708090a0b0c0d0e0f" #x84ACB5D9)
   (list ref-key zero-id #x805566E3)
   (list ref-key "ffffffffffffffffffffffffffffffff" #xB1F9F81A)
   (list "ffffffffffffffff" "ffffffffffffffffffffffffffffffff" #x8E3AA694)
   (list "0000000000000000" zero-id #xE29C7B3E)
   (list ref-key a6-id #xCB9E911D)
   (list ref-key "919108f752d143209bacf847db4148a8" #xE601E061)
   (list "fcc318c4dc0c0c07" a6-id #xB181D3F3)
   (list "0100000000000000" zero-id #x041D64AF)
   (list "0000000001000000" zero-id #xC9F60692)
   (list ref-key "00000000000000000000000000000080" #xCC5B07CE)
   (list ref-key "80000000000000000000000000000000" #x54198BA2)))

;; --- tests ------------------------------------------------------------------

(test-begin "unique-id-keyed-hash")

(test-equal "make-uuid-hash: vectors.h, vectors_hsip32 entry 16, key 0001020304050607, id 000102..0f"
  '(value #x84ACB5D9)
  (hash-of ref-key "000102030405060708090a0b0c0d0e0f"))

(test-equal "make-uuid-hash: halfsiphash.c, key 0001020304050607, the zero id"
  '(value #x805566E3)
  (hash-of ref-key zero-id))

(test-equal "make-uuid-hash: halfsiphash.c, key 0001020304050607, the all-ones id"
  '(value #xB1F9F81A)
  (hash-of ref-key "ffffffffffffffffffffffffffffffff"))

(test-equal "make-uuid-hash: halfsiphash.c, key ff..ff, the all-ones id"
  '(value #x8E3AA694)
  (hash-of "ffffffffffffffff" "ffffffffffffffffffffffffffffffff"))

(test-equal "make-uuid-hash: halfsiphash.c, the zero key, the zero id"
  '(value #xE29C7B3E)
  (hash-of "0000000000000000" zero-id))

(test-equal "make-uuid-hash: halfsiphash.c, key 0001020304050607, the A.6 id"
  '(value #xCB9E911D)
  (hash-of ref-key a6-id))

(test-equal "make-uuid-hash: halfsiphash.c, key 0001020304050607, the A.3 id"
  '(value #xE601E061)
  (hash-of ref-key "919108f752d143209bacf847db4148a8"))

(test-equal "make-uuid-hash: halfsiphash.c, key fcc318c4dc0c0c07, the A.6 id"
  '(value #xB181D3F3)
  (hash-of "fcc318c4dc0c0c07" a6-id))

(test-equal "make-uuid-hash: halfsiphash.c, key 0100000000000000 (k0 alone), the zero id"
  '(value #x041D64AF)
  (hash-of "0100000000000000" zero-id))

(test-equal "make-uuid-hash: halfsiphash.c, key 0000000001000000 (k1 alone), the zero id"
  '(value #xC9F60692)
  (hash-of "0000000001000000" zero-id))

(test-equal "make-uuid-hash: halfsiphash.c, key 0001020304050607, the id with only octet 15 = 80"
  '(value #xCC5B07CE)
  (hash-of ref-key "00000000000000000000000000000080"))

(test-equal "make-uuid-hash: halfsiphash.c, key 0001020304050607, the id with only octet 0 = 80"
  '(value #x54198BA2)
  (hash-of ref-key "80000000000000000000000000000000"))

(test-equal "make-uuid-hash: KEY is read at the call: zeroed before the first hash, the zero id still answers the vectors.h key's #x805566E3, not the zero key's (halfsiphash.c)"
  '(value #x805566E3)
  (classify (lambda ()
              (let* ((key (hex->bytevector ref-key))
                     (hash (make-uuid-hash key)))
                (do ((i 0 (+ i 1)))
                    ((= i 8))
                  (bytevector-u8-set! key i 0))
                (hash nil-uuid)))
            #f))

(test-equal "make-uuid-hash: procedures made from equal keys, by two calls from two bytevectors, answer alike for every vector (vectors.h and halfsiphash.c)"
  (list 'value (map (lambda (v) (list (caddr v) (caddr v))) vectors))
  (classify (lambda ()
              (map (lambda (v)
                     (let* ((h1 (make-uuid-hash (hex->bytevector (car v))))
                            (h2 (make-uuid-hash (hex->bytevector (car v))))
                            (id (bytevector->uuid (hex->bytevector (cadr v)))))
                       (list (h1 id) (h2 id))))
                   vectors))
            #f))

(test-equal "make-uuid-hash: range, seed 4242, 1000 ids: all exact in 0..2^32-1, one at least 2^31, at least 999 distinct"
  '(value (#t #t #t))
  (classify (lambda ()
              (let* ((next (make-lcg 4242))
                     (hash (make-uuid-hash (hex->bytevector ref-key)))
                     (answers (let loop ((i 0) (acc '()))
                                (if (= i 1000)
                                    (reverse acc)
                                    (let* ((id (bytevector->uuid (draw-bytes next 16)))
                                           (a (hash id)))
                                      (loop (+ i 1) (cons a acc)))))))
                (list (for-all (lambda (a)
                                 (and (integer? a) (exact? a) (<= 0 a #xFFFFFFFF)))
                               answers)
                      (exists (lambda (a) (>= a #x80000000)) answers)
                      (>= (count-distinct answers) 999))))
            #f))

(test-equal "make-uuid-hash: one bit, vectors.h key, the A.6 id: each of its 128 single-bit flips answers differently from #xCB9E911D"
  '(value (#xCB9E911D 128))
  (classify (lambda ()
              (let* ((hash (make-uuid-hash (hex->bytevector ref-key)))
                     (base (hex->bytevector a6-id))
                     (base-answer (hash (bytevector->uuid base)))
                     (differing
                      (let loop ((bit 0) (n 0))
                        (if (= bit 128)
                            n
                            (let ((flipped (bytes-copy base))
                                  (octet (div bit 8)))
                              (bytevector-u8-set!
                               flipped octet
                               (bitwise-xor (bytevector-u8-ref base octet)
                                            (bitwise-arithmetic-shift-left 1 (mod bit 8))))
                              (loop (+ bit 1)
                                    (if (= (hash (bytevector->uuid flipped)) base-answer)
                                        n
                                        (+ n 1))))))))
                (list base-answer differing)))
            #f))

(test-equal "make-uuid-hash: keys, seed 8080, 16 keys: 16 distinct answers for the A.6 id"
  '(value 16)
  (classify (lambda ()
              (let* ((next (make-lcg 8080))
                     (id (bytevector->uuid (hex->bytevector a6-id)))
                     (answers (let loop ((i 0) (acc '()))
                                (if (= i 16)
                                    (reverse acc)
                                    (let ((key (draw-bytes next 8)))
                                      (loop (+ i 1)
                                            (cons ((make-uuid-hash key) id) acc)))))))
                (count-distinct answers)))
            #f))

;; Flooding. The 1024 ids are built at run time from uuid-hash, in this one
;; test's expression. The construction leans on uuid-hash being linear under
;; xor, and on the hash of nil-uuid being 0: if uuid-hash changes, this test
;; must change with it.
;; For each i below 10, the id with octet i = 1 and octets 13, 14 and 15 set to
;; the bytes of its uuid-hash s (s < 2^23) has uuid-hash 0. The ten are
;; linearly independent, and the A.6 id xor each subset of them is one of 1024
;; ids with one uuid-hash.
(test-equal "make-uuid-hash: flooding, vectors.h key: 1024 ids of one uuid-hash take at least 1000 answers"
  '(value (1024 #t #t #t))
  (classify
   (lambda ()
     (let* ((hash (make-uuid-hash (hex->bytevector ref-key)))
            (ten (map (lambda (i)
                        (let* ((bv (make-bytevector 16 0))
                               (_ (bytevector-u8-set! bv i 1))
                               (s (uuid-hash (bytevector->uuid bv))))
                          (bytevector-u8-set! bv 13 (bitwise-arithmetic-shift-right s 16))
                          (bytevector-u8-set! bv 14 (bitwise-and (bitwise-arithmetic-shift-right s 8) 255))
                          (bytevector-u8-set! bv 15 (bitwise-and s 255))
                          bv))
                      '(0 1 2 3 4 5 6 7 8 9)))
            (base (hex->bytevector a6-id))
            (ids (map (lambda (subset)
                        (let ((bv (bytes-copy base)))
                          (do ((j 0 (+ j 1)))
                              ((= j 10) bv)
                            (when (bitwise-bit-set? subset j)
                              (let ((t (list-ref ten j)))
                                (do ((k 0 (+ k 1)))
                                    ((= k 16))
                                  (bytevector-u8-set!
                                   bv k (bitwise-xor (bytevector-u8-ref bv k)
                                                     (bytevector-u8-ref t k)))))))))
                      (let loop ((n 1023) (acc '()))
                        (if (< n 0) acc (loop (- n 1) (cons n acc))))))
            (texts (map (lambda (bv) (uuid->string (bytevector->uuid bv))) ids))
            (distinct-texts (let ((table (make-hashtable string-hash string=?)))
                              (for-each (lambda (t) (hashtable-set! table t #t)) texts)
                              (hashtable-size table)))
            (ten-zero? (for-all (lambda (bv) (= 0 (uuid-hash (bytevector->uuid bv)))) ten))
            (hashes (map (lambda (bv) (uuid-hash (bytevector->uuid bv))) ids))
            (one-hash? (= 1 (count-distinct hashes)))
            (answers (map (lambda (bv) (hash (bytevector->uuid bv))) ids)))
       (list distinct-texts ten-zero? one-hash? (>= (count-distinct answers) 1000))))
   #f))

(test-equal "make-uuid-hash: hashtable, seed 6006, 1000 ids: each found by a fresh copy (vectors.h key)"
  '(value 1000)
  (classify (lambda ()
              (let* ((next (make-lcg 6006))
                     (table (make-hashtable (make-uuid-hash (hex->bytevector ref-key)) uuid=?))
                     (all (let loop ((i 0) (acc '()))
                            (if (= i 1000)
                                (reverse acc)
                                (loop (+ i 1) (cons (draw-bytes next 16) acc))))))
                (let fill ((rest all) (i 0))
                  (unless (null? rest)
                    (hashtable-set! table (bytevector->uuid (car rest)) i)
                    (fill (cdr rest) (+ i 1))))
                (let find ((rest all) (i 0) (found 0))
                  (if (null? rest)
                      found
                      (find (cdr rest) (+ i 1)
                            (if (eqv? i (hashtable-ref table
                                                       (bytevector->uuid (bytes-copy (car rest)))
                                                       #f))
                                (+ found 1)
                                found))))))
            #f))

;; Errors.

;; key-error : Any -> Outcome
;; The outcome of (make-uuid-hash KEY).
(define (key-error key)
  (classify (lambda () (make-uuid-hash key)) key))

(test-equal "make-uuid-hash: a string key is an assertion violation naming make-uuid-hash, the string the irritant"
  '(violation make-uuid-hash #t)
  (let ((key "01234567")) (classify (lambda () (make-uuid-hash key)) key)))

(test-equal "make-uuid-hash: a vector key is an assertion violation naming make-uuid-hash, the vector the irritant"
  '(violation make-uuid-hash #t)
  (let ((key (vector 0 1 2 3 4 5 6 7))) (classify (lambda () (make-uuid-hash key)) key)))

(test-equal "make-uuid-hash: the symbol key is an assertion violation naming make-uuid-hash, the symbol the irritant"
  '(violation make-uuid-hash #t)
  (key-error 'key))

(test-equal "make-uuid-hash: a 7-byte key is an assertion violation naming make-uuid-hash, the key the irritant"
  '(violation make-uuid-hash #t)
  (key-error (make-bytevector 7 1)))

(test-equal "make-uuid-hash: a 9-byte key is an assertion violation naming make-uuid-hash, the key the irritant"
  '(violation make-uuid-hash #t)
  (key-error (make-bytevector 9 1)))

(test-equal "make-uuid-hash: a 0-byte key is an assertion violation naming make-uuid-hash, the key the irritant"
  '(violation make-uuid-hash #t)
  (key-error (make-bytevector 0 1)))

;; arg-error : Any -> Outcome
;; The outcome of calling a procedure made by make-uuid-hash on ARG.
(define (arg-error arg)
  (classify (lambda () ((make-uuid-hash (hex->bytevector ref-key)) arg)) arg))

(test-equal "make-uuid-hash: HASH given a 16-byte bytevector is an assertion violation naming make-uuid-hash, the bytevector the irritant"
  '(violation make-uuid-hash #t)
  (arg-error (make-bytevector 16 1)))

(test-equal "make-uuid-hash: HASH given a string is an assertion violation naming make-uuid-hash, the string the irritant"
  '(violation make-uuid-hash #t)
  (arg-error "not an id"))

(test-equal "make-uuid-hash: HASH given #f is an assertion violation naming make-uuid-hash, #f the irritant"
  '(violation make-uuid-hash #t)
  (arg-error #f))

(test-end "unique-id-keyed-hash")

(exit (suite-exit-status runner))
