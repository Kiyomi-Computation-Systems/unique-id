#!r6rs
;;; (unique-id system): the system's clock, entropy, generator and hash.
;;;
;;; The library reads the real clock and /dev/urandom, so no assertion
;;; compares random bytes with fixed ones. Each test states a property that a
;;; wrong library fails with certainty, or that a right one fails with a
;;; chance given in the test's name. A test of many cases runs them all inside
;;; one actual expression and answers a summary that differs by test:
;;; (value ()) or (value 0) when no case failed, (value #t) or a list of #t
;;; when every case held, else what failed. Every call into the library runs
;;; under a guard inside a test's actual expression; the only calls outside a
;;; guard are of this file's own helpers on fixed arguments.
;;;
;;; A guard tags what happened: (value V); (violation WHO OK?) for an
;;; assertion violation; (error WHO OK?) for an `error`; (raised X) for
;;; anything else raised; (raised-condition) for any other condition. OK? is
;;; #t when the one irritant is eqv? to the one expected. Ids are compared as
;;; text or with uuid=?, never with equal?.
(import (rnrs)
        (srfi :64)
        (only (srfi :19) current-time time-utc time-second time-nanosecond)
        (unique-id)
        (unique-id generator)
        (unique-id system)
        (unique-id-testing))

(define runner (test-runner-simple))
(test-runner-current runner)

;; --- helpers ----------------------------------------------------------------

;; Types of this file:
;;   Condition  an R6RS condition.
;;   Outcome    what a tagged call did: (List 'value Any), (List 'violation
;;              (U Symbol #f) Boolean), (List 'error (U Symbol #f) Boolean),
;;              (List 'raised Any) or (List 'raised-condition). An id inside a
;;              value is (List 'id String).

;; norm : Any -> Any
;; V, with an id turned into (id TEXT), TEXT being its canonical text.
(define (norm v)
  (if (uuid? v) (list 'id (uuid->string v)) v))

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
    (list 'value (norm (thunk)))))

;; attempt : (-> Any) -> Outcome
;; (value V) when THUNK answers V, else (raised E), whatever was raised. A
;; many-case test runs under it, so a raise inside it fails the test.
(define (attempt thunk)
  (guard (e (#t (list 'raised e)))
    (list 'value (norm (thunk)))))

;; make-rng : Nat -> (-> Nat)
;; A generator seeded with SEED: state' = (1664525 * state + 1013904223) mod
;; 2^32, and each answer is the state's high byte, 0 to 255.
(define (make-rng seed)
  (let ((state seed))
    (lambda ()
      (set! state (mod (+ (* 1664525 state) 1013904223) 4294967296))
      (div state 16777216))))

;; rng-id : (-> Nat) -> Uuid
;; The id of 16 bytes drawn in order from RNG.
(define (rng-id rng)
  (let ((bv (make-bytevector 16 0)))
    (do ((i 0 (+ i 1)))
        ((= i 16) (bytevector->uuid bv))
      (bytevector-u8-set! bv i (rng)))))

;; rng-ids : Nat Nat -> (Listof Uuid)
;; N ids from a generator seeded with SEED, in order.
(define (rng-ids seed n)
  (let ((rng (make-rng seed)))
    (let loop ((k 0) (acc '()))
      (if (= k n)
          (reverse acc)
          (let ((u (rng-id rng)))
            (loop (+ k 1) (cons u acc)))))))

;; copy-id : Uuid -> Uuid
;; A fresh id with the octets of U.
(define (copy-id u)
  (bytevector->uuid (uuid->bytevector u)))

;; hex->bytevector : String -> Bytevector
;; The bytes TEXT spells, two hex digits each.
(define (hex->bytevector text)
  (let* ((n (div (string-length text) 2))
         (bv (make-bytevector n 0)))
    (do ((i 0 (+ i 1)))
        ((= i n) bv)
      (bytevector-u8-set! bv i
                          (string->number (substring text (* 2 i) (+ 2 (* 2 i))) 16)))))

;; ms-of-time : -> Nat
;; The Unix time in milliseconds, read from SRFI-19's time-utc: its second
;; times 1000, plus its nanosecond div 1000000.
(define (ms-of-time)
  (let ((t (current-time time-utc)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

;; two48 : Nat
;; 2^48.
(define two48 (expt 2 48))

;; two32 : Nat
;; 2^32.
(define two32 (expt 2 32))


;; bytes-of-calls : Nat Nat -> (Listof Bytevector)
;; The answers of COUNT calls of (system-entropy N), in order.
(define (bytes-of-calls count n)
  (let loop ((k 0) (acc '()))
    (if (= k count)
        (reverse acc)
        (let ((b (system-entropy n)))
          (loop (+ k 1) (cons b acc))))))

;; missing-values : (Listof Bytevector) -> (Listof Nat)
;; The byte values from 0 to 255 that no bytevector of BVS holds.
(define (missing-values bvs)
  (let ((seen (make-vector 256 #f)))
    (for-each (lambda (bv)
                (do ((i 0 (+ i 1)))
                    ((= i (bytevector-length bv)))
                  (vector-set! seen (bytevector-u8-ref bv i) #t)))
              bvs)
    (let loop ((v 255) (acc '()))
      (if (< v 0)
          acc
          (loop (- v 1) (if (vector-ref seen v) acc (cons v acc)))))))

;; pairwise-distinct? : (Listof Bytevector) -> Boolean
;; #t when no two bytevectors of BVS hold the same bytes.
(define (pairwise-distinct? bvs)
  (let loop ((rest bvs))
    (or (null? rest)
        (and (not (exists (lambda (b) (bytevector=? (car rest) b)) (cdr rest)))
             (loop (cdr rest))))))

;; text-distinct? : (Listof String) -> Boolean
;; #t when no two strings of TEXTS are equal.
(define (text-distinct? texts)
  (let ((table (make-hashtable string-hash string=?)))
    (for-each (lambda (s) (hashtable-set! table s #t)) texts)
    (= (hashtable-size table) (length texts))))

;; --- system-clock -----------------------------------------------------------

(test-begin "unique-id-system")

(test-equal "system-clock: an exact integer from 2026-11-22T00:00Z to below 2^48"
  '(value (#t #t #t))
  (attempt
   (lambda ()
     (let ((ms (system-clock)))
       (list (and (integer? ms) (exact? ms))
             (>= ms 1795305600000)
             (< ms two48))))))

(test-equal "system-clock: 100 readings lie between time-utc's before and after"
  '(value ())
  (attempt
   (lambda ()
     (let loop ((i 0) (bad '()))
       (if (= i 100)
           (reverse bad)
           (let* ((before (ms-of-time))
                  (ms (system-clock))
                  (after (ms-of-time)))
             (loop (+ i 1)
                   (if (and (integer? ms) (exact? ms) (<= before ms after))
                       bad
                       (cons (list i before ms after) bad)))))))))

;; --- system-entropy ---------------------------------------------------------

(test-equal "system-entropy: N of 0, 1, 8, 10, 16 and 100000 answer N bytes"
  '(value ())
  (attempt
   (lambda ()
     (let loop ((ns '(0 1 8 10 16 100000)) (bad '()))
       (if (null? ns)
           (reverse bad)
           (let ((b (system-entropy (car ns))))
             (loop (cdr ns)
                   (if (and (bytevector? b)
                            (= (bytevector-length b) (car ns)))
                       bad
                       (cons (car ns) bad)))))))))

(test-equal "system-entropy: 64 answers of 16 bytes are pairwise distinct (fails with chance 2^-117)"
  '(value #t)
  (attempt
   (lambda ()
     (let ((bvs (bytes-of-calls 64 16)))
       (and (for-all (lambda (b) (and (bytevector? b) (= 16 (bytevector-length b)))) bvs)
            (pairwise-distinct? bvs))))))

(test-equal "system-entropy: each of 16 positions over 64 calls of 16 bytes takes 2 values (fails with chance 2^-500)"
  '(value ())
  (attempt
   (lambda ()
     (let ((bvs (bytes-of-calls 64 16)))
       (let loop ((pos 0) (bad '()))
         (if (= pos 16)
             (reverse bad)
             (let ((seen (make-vector 256 #f)))
               (for-each (lambda (b) (vector-set! seen (bytevector-u8-ref b pos) #t))
                         bvs)
               (loop (+ pos 1)
                     (if (>= (length (filter (lambda (x) x) (vector->list seen))) 2)
                         bad
                         (cons pos bad))))))))))

(test-equal "system-entropy: each half of 131072 bytes from one call holds every byte value (fails with chance 2^-361)"
  '(value (() ()))
  (attempt
   (lambda ()
     (let ((b (system-entropy 131072)))
       (if (and (bytevector? b) (= 131072 (bytevector-length b)))
           (let ((first (make-bytevector 65536 0))
                 (second (make-bytevector 65536 0)))
             (bytevector-copy! b 0 first 0 65536)
             (bytevector-copy! b 65536 second 0 65536)
             (list (missing-values (list first)) (missing-values (list second))))
           'wrong-length)))))

(test-equal "system-entropy: 65536 bytes from one call hold every byte value (fails with chance 2^-362)"
  '(value ())
  (attempt
   (lambda ()
     (let ((b (system-entropy 65536)))
       (if (and (bytevector? b) (= 65536 (bytevector-length b)))
           (missing-values (list b))
           'wrong-length)))))

(test-equal "system-entropy: 65536 bytes from 4096 calls of 16 hold every byte value (fails with chance 2^-362)"
  '(value ())
  (attempt
   (lambda ()
     (let ((bvs (bytes-of-calls 4096 16)))
       (if (for-all (lambda (b) (and (bytevector? b) (= 16 (bytevector-length b)))) bvs)
           (missing-values bvs)
           'wrong-length)))))

(test-equal "system-entropy: 5000 calls in a row each answer 16 bytes, under the cap of 64 descriptors"
  '(value 0)
  (attempt
   (lambda ()
     (let loop ((i 0) (bad 0))
       (if (= i 5000)
           bad
           (let ((b (system-entropy 16)))
             (loop (+ i 1)
                   (if (and (bytevector? b) (= 16 (bytevector-length b)))
                       bad
                       (+ bad 1)))))))))

(define-syntax entropy-error-test
  (syntax-rules ()
    ((_ name n)
     (test-equal name
       '(violation system-entropy #t)
       (classify (lambda () (system-entropy n)) n)))))

(entropy-error-test "system-entropy: -1 is an assertion violation naming it, with -1 as irritant" -1)
(entropy-error-test "system-entropy: 1/2 is an assertion violation naming it, with 1/2 as irritant" 1/2)
(entropy-error-test "system-entropy: 1.0 is an assertion violation naming it, with 1.0 as irritant" 1.0)
(entropy-error-test "system-entropy: #f is an assertion violation naming it, with #f as irritant" #f)
(entropy-error-test "system-entropy: the symbol n is an assertion violation naming it, with n as irritant" 'n)

;; --- make-system-uuid-generator ---------------------------------------------

(test-equal "make-system-uuid-generator: answers a generator, and two calls answer two"
  '(value (#t #t #f))
  (attempt
   (lambda ()
     (let* ((g1 (make-system-uuid-generator))
            (g2 (make-system-uuid-generator)))
       (list (uuid-generator? g1) (uuid-generator? g2) (eq? g1 g2))))))

(test-equal "make-system-uuid-generator: 5000 v7 ids increase, are version 7 of variant rfc9562, read back, and carry the clock's time"
  '(value ())
  (attempt
   (lambda ()
     (let* ((g (make-system-uuid-generator))
            (before (ms-of-time))
            (ids (let loop ((i 0) (acc '()))
                   (if (= i 5000)
                       (reverse acc)
                       (let ((u (generate-v7 g)))
                         (loop (+ i 1) (cons u acc))))))
            (after (ms-of-time)))
       (let loop ((rest ids) (prev #f) (i 0) (bad '()))
         (if (null? rest)
             (reverse bad)
             (let* ((u (car rest))
                    (ok (and (uuid? u)
                             (or (not prev) (uuid<? prev u))
                             (eqv? 7 (uuid-version u))
                             (eq? 'rfc9562 (uuid-variant u))
                             (let ((back (string->uuid (uuid->string u))))
                               (and back (uuid=? back u)))
                             (let ((ts (uuid-v7-timestamp u)))
                               (and (>= ts before)
                                    ;; A new tick's counter seed is at most
                                    ;; 2047, so a millisecond holds at least
                                    ;; 2049 ids before it rolls over; 5000
                                    ;; ids roll over at most twice past the
                                    ;; clock.
                                    (<= ts (+ after 2)))))))
               (loop (cdr rest) u (+ i 1) (if ok bad (cons i bad))))))))))

(test-equal "make-system-uuid-generator: a fresh generator's first v7 id carries a time between time-utc's before and after"
  '(value #t)
  (attempt
   (lambda ()
     (let* ((g (make-system-uuid-generator))
            (before (ms-of-time))
            (u (generate-v7 g))
            (after (ms-of-time))
            (ts (uuid-v7-timestamp u)))
       (<= before ts after)))))

(test-equal "make-system-uuid-generator: 1000 v4 ids are version 4 and pairwise distinct (fails with chance 2^-103)"
  '(value (#t #t))
  (attempt
   (lambda ()
     (let* ((g (make-system-uuid-generator))
            (ids (let loop ((i 0) (acc '()))
                   (if (= i 1000)
                       (reverse acc)
                       (let ((u (generate-v4 g)))
                         (loop (+ i 1) (cons u acc)))))))
       (list (for-all (lambda (u) (and (uuid? u) (eqv? 4 (uuid-version u)))) ids)
             (text-distinct? (map uuid->string ids)))))))

(test-equal "make-system-uuid-generator: two generators' first v7 ids differ (fails with chance 2^-73)"
  '(value #t)
  (attempt
   (lambda ()
     (let* ((g1 (make-system-uuid-generator))
            (g2 (make-system-uuid-generator))
            (u1 (generate-v7 g1))
            (u2 (generate-v7 g2)))
       (not (uuid=? u1 u2))))))

;; --- make-system-uuid-hash --------------------------------------------------

(test-equal "make-system-uuid-hash: each answer for 1000 ids of seed 20260101 is an exact integer from 0 to 2^32 - 1"
  '(value 0)
  (attempt
   (lambda ()
     (let ((hash (make-system-uuid-hash)))
       (let loop ((rest (rng-ids 20260101 1000)) (bad 0))
         (if (null? rest)
             bad
             (let ((h (hash (car rest))))
               (loop (cdr rest)
                     (if (and (integer? h) (exact? h) (<= 0 h) (< h two32))
                         bad
                         (+ bad 1))))))))))

(test-equal "make-system-uuid-hash: two procedures differ on one of 8 ids, A.6, A.3, nil, max and 4 of seed 20260102 (fails with chance 2^-64)"
  '(value #t)
  (attempt
   (lambda ()
     (let* ((h1 (make-system-uuid-hash))
            (h2 (make-system-uuid-hash))
            ;; The ids of RFC 9562 A.6 (v7) and A.3 (v4).
            (id-a6 (bytevector->uuid
                    (hex->bytevector "017f22e279b07cc398c4dc0c0c07398f")))
            (id-a3 (bytevector->uuid
                    (hex->bytevector "919108f752d143209bacf847db4148a8")))
            (ids (append (list id-a6 id-a3 nil-uuid max-uuid)
                         (rng-ids 20260102 4))))
       (exists (lambda (u) (not (= (h1 u) (h2 u)))) ids)))))

(test-equal "make-system-uuid-hash: a hashtable keyed by it finds 1000 ids of seed 20260103 by fresh copies"
  '(value ())
  (attempt
   (lambda ()
     (let* ((table (make-hashtable (make-system-uuid-hash) uuid=?))
            (ids (rng-ids 20260103 1000)))
       (let fill ((rest ids) (i 0))
         (unless (null? rest)
           (hashtable-set! table (car rest) i)
           (fill (cdr rest) (+ i 1))))
       (let loop ((rest ids) (i 0) (bad '()))
         (if (null? rest)
             (reverse bad)
             (loop (cdr rest) (+ i 1)
                   (if (eqv? i (hashtable-ref table (copy-id (car rest)) 'missing))
                       bad
                       (cons i bad)))))))))

(let ((bv (hex->bytevector "000102030405060708090a0b0c0d0e0f")))
  (test-equal "make-system-uuid-hash: its procedure given a 16-byte bytevector raises, naming make-uuid-hash, with the bytevector"
    '(violation make-uuid-hash #t)
    (classify (lambda () ((make-system-uuid-hash) bv)) bv)))

(test-end "unique-id-system")

(exit (suite-exit-status runner))
