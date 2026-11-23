#!r6rs
;;; (unique-id): how ids compare and hash.
;;;
;;; uuid=? holds just when two ids have the same 16 octets. uuid<? orders ids
;;; as unsigned bytes from octet 0, which is their order as 128-bit unsigned
;;; integers and the order of their lower-case text, so v7 ids sort by time
;;; (RFC 9562 §6.11). uuid-hash answers a fixnum below 2^23 from the octets
;;; alone: equal ids hash alike, ids that differ in one octet hash apart, and
;;; random ids spread. A hashtable made with uuid-hash and uuid=? keys by id.
;;; An argument that is not an id is an assertion violation naming the
;;; procedure and holding the argument itself.
;;;
;;; Every call into the library goes through try or try-violation, which tag
;;; what happened, so a raise is never mistaken for an answer. Property tests
;;; draw from a seeded linear congruential generator and list the first
;;; failing cases, which must be none; a case that raises is a failure.
(import (rnrs)
        (srfi :64)
        (unique-id)
        (unique-id-testing))

(define runner (test-runner-simple))
(test-runner-current runner)

;; --- helpers ----------------------------------------------------------------

;; try : (-> Any) -> (U (List 'value Any) (List 'assertion-violation Symbol Any)
;;                      (List 'raised Any))
;; What THUNK answered, or the who and irritants of the assertion violation it
;; raised, or whatever else it raised.
(define (try thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e) (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'raised e)))
    (list 'value (thunk))))

;; try-violation : (-> Any) Any -> (U (List 'assertion-violation Symbol Boolean)
;;                                    (List 'value Any) (List 'raised Any))
;; THUNK's outcome as an assertion violation's who and whether its irritants
;; are a one-element list holding OFFENDER itself (eqv?); a value or another
;; raise is tagged as it is.
(define (try-violation thunk offender)
  (guard (e ((and (assertion-violation? e) (who-condition? e) (irritants-condition? e))
             (let ((irritants (condition-irritants e)))
               (list 'assertion-violation
                     (condition-who e)
                     (and (pair? irritants)
                          (null? (cdr irritants))
                          (eqv? (car irritants) offender)))))
            (#t (list 'raised e)))
    (list 'value (thunk))))

;; make-rng : Nat -> (-> Nat)
;; A generator seeded with SEED: state' = (1664525 * state + 1013904223) mod
;; 2^32, and each answer is the state's high byte, 0 to 255.
(define (make-rng seed)
  (let ((state seed))
    (lambda ()
      (set! state (mod (+ (* 1664525 state) 1013904223) 4294967296))
      (div state 16777216))))

;; rand-list : (-> Nat) Nat -> (Listof Nat)
;; N bytes drawn in order from RNG.
(define (rand-list rng n)
  (let loop ((i 0) (acc '()))
    (if (= i n)
        (reverse acc)
        (loop (+ i 1) (cons (rng) acc)))))

;; rand-int : (-> Nat) Nat -> Nat
;; An integer of 8 * N bits drawn from RNG, big-endian.
(define (rand-int rng n)
  (let loop ((i 0) (acc 0))
    (if (= i n)
        acc
        (loop (+ i 1) (+ (* acc 256) (rng))))))

;; repeat : Nat Any -> (Listof Any)
;; A list of N copies of X.
(define (repeat n x)
  (if (= n 0) '() (cons x (repeat (- n 1) x))))

;; list-with : (Listof Any) Nat Any -> (Listof Any)
;; LST with the element at index POS replaced by X.
(define (list-with lst pos x)
  (cond ((null? lst) '())
        ((= pos 0) (cons x (cdr lst)))
        (else (cons (car lst) (list-with (cdr lst) (- pos 1) x)))))

;; id : (Listof Nat) -> Uuid
;; A fresh id of the octets in OCTETS, 16 of them.
(define (id octets)
  (bytevector->uuid (u8-list->bytevector octets)))

;; collect-failures : Nat (Nat -> Any) -> (Listof Any)
;; Runs CHECK on 0 to N-1, in order. CHECK answers #f for a pass and a datum
;; for a failure; a case that raises is the failure (raised I). The answer is
;; the first 5 failures, or '() when every case passed.
(define (collect-failures n check)
  (let loop ((i 0) (found '()) (kept 0))
    (if (= i n)
        (reverse found)
        (let ((f (guard (e (#t (list 'raised i)))
                   (check i))))
          (if (and f (< kept 5))
              (loop (+ i 1) (cons f found) (+ kept 1))
              (loop (+ i 1) found kept))))))

;; hash-ok? : Any -> Boolean
;; Whether H is an exact fixnum from 0 to below 2^23.
(define (hash-ok? h)
  (and (integer? h) (exact? h) (fixnum? h) (<= 0 h) (< h 8388608)))

;; octets-string : (Listof Nat) -> String
;; The octets of OCTETS as hex, three digits each, to key a table of
;; strings. Its case is the Scheme's own, which a key needs only to keep.
(define (octets-string octets)
  (apply string-append
         (let loop ((l octets))
           (if (null? l)
               '()
               (cons (number->string (+ 256 (car l)) 16) (loop (cdr l)))))))

;; A base of 16 octets that are neither 0 nor FF, some above 7F.
(define base-octets
  '(#x21 #x2E #x3B #x48 #x55 #x62 #x6F #x7C #x89 #x96 #xA3 #xB0 #xBD #xCA #xD7 #xE4))

(test-begin "unique-id-order")

;; --- uuid=? -----------------------------------------------------------------

(test-equal "uuid=?: ids made separately from the same octets are equal, both ways"
  '(value (#t #t))
  (try (lambda ()
         (let* ((a (id base-octets))
                (b (id base-octets)))
           (list (uuid=? a b) (uuid=? b a))))))

(test-equal "uuid=?: an id is equal to itself"
  '(value #t)
  (try (lambda ()
         (let ((a (id base-octets)))
           (uuid=? a a)))))

;; Each position, changed by a flipped low bit and by its complement.
(test-equal "uuid=?: ids that differ only in one of the 16 octets are not equal"
  '(value ())
  (try (lambda ()
         (collect-failures
          32
          (lambda (i)
            (let* ((pos (div i 2))
                   (old (list-ref base-octets pos))
                   (new (if (= (mod i 2) 0) (bitwise-xor old 1) (- 255 old)))
                   (a (id base-octets))
                   (b (id (list-with base-octets pos new)))
                   (ab (uuid=? a b))
                   (ba (uuid=? b a)))
              (if (and (eq? ab #f) (eq? ba #f))
                  #f
                  (list 'equal-answered pos new ab ba))))))))

(test-equal "uuid=?: nil-uuid and max-uuid are not equal"
  '(value (#f #f))
  (try (lambda ()
         (list (uuid=? nil-uuid max-uuid) (uuid=? max-uuid nil-uuid)))))

;; --- uuid<? -----------------------------------------------------------------

(test-equal "uuid<?: an id is not before an equal one, either way, or itself"
  '(value (#f #f #f))
  (try (lambda ()
         (let* ((a (id base-octets))
                (b (id base-octets)))
           (list (uuid<? a b) (uuid<? b a) (uuid<? a a))))))

(test-equal "uuid<?: nil-uuid comes before max-uuid, not the other way"
  '(value (#t #f))
  (try (lambda ()
         (list (uuid<? nil-uuid max-uuid) (uuid<? max-uuid nil-uuid)))))

(test-equal "uuid<?: nil-uuid comes before the id whose only nonzero octet is octet 15, 1"
  '(value (#t #f))
  (try (lambda ()
         (let ((low (id (append (repeat 15 0) '(1)))))
           (list (uuid<? nil-uuid low) (uuid<? low nil-uuid))))))

(test-equal "uuid<?: the id that differs from max-uuid only in octet 15 comes before it"
  '(value (#t #f))
  (try (lambda ()
         (let ((almost (id (append (repeat 15 255) '(254)))))
           (list (uuid<? almost max-uuid) (uuid<? max-uuid almost))))))

(test-equal "uuid<?: it is lexicographic, 01 FF FF ... comes before 02 00 00 ..."
  '(value (#t #f))
  (try (lambda ()
         (let ((a (id (cons 1 (repeat 15 255))))
               (b (id (cons 2 (repeat 15 0)))))
           (list (uuid<? a b) (uuid<? b a))))))

(test-equal "uuid<?: it is unsigned in octet 0, 7F ... comes before 80 ..."
  '(value (#t #f))
  (try (lambda ()
         (let ((a (id (cons #x7F (repeat 15 #x33))))
               (b (id (cons #x80 (repeat 15 #x33)))))
           (list (uuid<? a b) (uuid<? b a))))))

(test-equal "uuid<?: it is unsigned in octet 15, ... 7F comes before ... 80"
  '(value (#t #f))
  (try (lambda ()
         (let ((a (id (append (repeat 15 #x33) '(#x7F))))
               (b (id (append (repeat 15 #x33) '(#x80)))))
           (list (uuid<? a b) (uuid<? b a))))))

(test-equal "uuid<?: it is unsigned in each of the 16 octets, 7F before 80 with the rest equal"
  '(value ())
  (try (lambda ()
         (collect-failures
          16
          (lambda (pos)
            (let* ((a (id (list-with (repeat 16 #x33) pos #x7F)))
                   (b (id (list-with (repeat 16 #x33) pos #x80)))
                   (ab (uuid<? a b))
                   (ba (uuid<? b a)))
              (if (and (eq? ab #t) (eq? ba #f))
                  #f
                  (list 'order-answered pos ab ba))))))))

;; --- uuid<? against two models ---------------------------------------------

(test-equal "uuid<?: agrees with the 128-bit integer order, string<? on the text, and uuid=?, seed 1, 2000 pairs sharing a prefix of 0 to 16 octets"
  '(value ())
  (try (lambda ()
         (let ((rng (make-rng 1)))
           (collect-failures
            2000
            (lambda (i)
              (let* ((k (mod (rng) 17))
                     (prefix (rand-list rng k))
                     (tail-a (rand-list rng (- 16 k)))
                     (tail-b (rand-list rng (- 16 k)))
                     (oa (append prefix tail-a))
                     (ob (append prefix tail-b))
                     (a (id oa))
                     (b (id ob))
                     (na (bytevector-uint-ref (u8-list->bytevector oa) 0 (endianness big) 16))
                     (nb (bytevector-uint-ref (u8-list->bytevector ob) 0 (endianness big) 16))
                     (sa (uuid->string a))
                     (sb (uuid->string b))
                     (lt (uuid<? a b))
                     (gt (uuid<? b a))
                     (eq (uuid=? a b))
                     (ok (and (boolean? lt) (boolean? gt) (boolean? eq)
                              (eq? lt (< na nb))
                              (eq? gt (> na nb))
                              (eq? eq (= na nb))
                              (eq? lt (string<? sa sb))
                              (eq? gt (string<? sb sa))
                              (= 1 (+ (if lt 1 0) (if gt 1 0) (if eq 1 0))))))
                (if ok
                    #f
                    (list 'order-disagrees i k oa ob lt gt eq)))))))))

;; --- v7 time order, RFC 9562 §6.11 -------------------------------------------

(test-equal "uuid<?: RFC 9562 §6.11, v7 ids sort by time, seed 7, 2000 pairs, MS2 = MS1 + 1 in half"
  '(value ())
  (try (lambda ()
         (let ((rng (make-rng 7))
               (top (- (expt 2 48) 1)))
           (collect-failures
            2000
            (lambda (i)
              (let* ((ms1 (mod (rand-int rng 6) top))
                     (ms2 (if (even? i)
                              (+ ms1 1)
                              (+ ms1 1 (mod (rand-int rng 6) (- top ms1)))))
                     (extreme (= 0 (mod i 5)))
                     (c1 (if extreme 4095 (mod (rand-int rng 2) 4096)))
                     (c2 (if extreme 0 (mod (rand-int rng 2) 4096)))
                     (r1 (if extreme (repeat 8 255) (rand-list rng 8)))
                     (r2 (if extreme (repeat 8 0) (rand-list rng 8)))
                     (a (make-uuid-v7 ms1 c1 (u8-list->bytevector r1)))
                     (b (make-uuid-v7 ms2 c2 (u8-list->bytevector r2)))
                     (ab (uuid<? a b))
                     (ba (uuid<? b a)))
                (if (and (eq? ab #t) (eq? ba #f))
                    #f
                    (list 'not-time-ordered i ms1 ms2 c1 c2 ab ba)))))))))

(test-equal "uuid<?: RFC 9562 §6.11, v7 ids sort by time across each carry, 2^k - 1 ms before 2^k ms"
  '(value ())
  (try (lambda ()
         (collect-failures
          48
          (lambda (k)
            (let* ((a (make-uuid-v7 (- (expt 2 k) 1) 4095 (u8-list->bytevector (repeat 8 255))))
                   (b (make-uuid-v7 (expt 2 k) 0 (u8-list->bytevector (repeat 8 #x11))))
                   (ab (uuid<? a b))
                   (ba (uuid<? b a)))
              (if (and (eq? ab #t) (eq? ba #f))
                  #f
                  (list 'carry-misordered k ab ba))))))))

;; --- uuid-hash --------------------------------------------------------------

(test-equal "uuid-hash: nil-uuid hashes to a fixnum from 0 to below 2^23"
  '(value #t)
  (try (lambda () (hash-ok? (uuid-hash nil-uuid)))))

(test-equal "uuid-hash: max-uuid hashes to a fixnum from 0 to below 2^23"
  '(value #t)
  (try (lambda () (hash-ok? (uuid-hash max-uuid)))))

(test-equal "uuid-hash: random ids hash to fixnums from 0 to below 2^23, seed 11, 2000 ids"
  '(value ())
  (try (lambda ()
         (let ((rng (make-rng 11)))
           (collect-failures
            2000
            (lambda (i)
              (let* ((octets (rand-list rng 16))
                     (h (uuid-hash (id octets))))
                (if (hash-ok? h)
                    #f
                    (list 'bad-hash i octets h)))))))))

(test-equal "uuid-hash: ids made separately from the same octets hash alike, seed 13, 2000 octet strings"
  '(value ())
  (try (lambda ()
         (let ((rng (make-rng 13)))
           (collect-failures
            2000
            (lambda (i)
              (let* ((octets (rand-list rng 16))
                     (h1 (uuid-hash (id octets)))
                     (h2 (uuid-hash (id octets))))
                (if (and (hash-ok? h1) (= h1 h2))
                    #f
                    (list 'equal-ids-hash-apart i octets h1 h2)))))))))

(test-equal "uuid-hash: an id differing from the base in exactly one octet hashes differently, all 16 octets and 255 values"
  '(value ())
  (try (lambda ()
         (let ((base-hash (uuid-hash (id base-octets))))
           (collect-failures
            4096
            (lambda (i)
              (let* ((pos (div i 256))
                     (v (mod i 256)))
                (if (= v (list-ref base-octets pos))
                    #f
                    (let ((h (uuid-hash (id (list-with base-octets pos v)))))
                      (if (and (hash-ok? base-hash) (hash-ok? h) (not (= h base-hash)))
                          #f
                          (list 'one-octet-same-hash pos v base-hash h)))))))))))

(test-equal "uuid-hash: 1000 distinct random ids, seed 17, get at least 990 distinct hashes"
  '(value (1000 #t))
  (try (lambda ()
         (let ((rng (make-rng 17))
               (seen (make-hashtable string-hash string=?))
               (hashes (make-eqv-hashtable)))
           (let loop ((ids '()) (n 0))
             (if (< n 1000)
                 (let* ((octets (rand-list rng 16))
                        (key (octets-string octets)))
                   (if (hashtable-contains? seen key)
                       (loop ids n)
                       (begin
                         (hashtable-set! seen key #t)
                         (loop (cons octets ids) (+ n 1)))))
                 (begin
                   (for-each (lambda (octets)
                               (hashtable-set! hashes (uuid-hash (id octets)) #t))
                             ids)
                   (list (length ids)
                         (>= (hashtable-size hashes) 990)))))))))

;; --- a hashtable of ids -----------------------------------------------------

(test-equal "hashtable of ids: a value is found by an equal id made separately, and not by a different id"
  '(value (found missing))
  (try (lambda ()
         (let* ((table (make-hashtable uuid-hash uuid=?))
                (key (id base-octets))
                (same (id base-octets))
                (other (id (list-with base-octets 9 #x97))))
           (hashtable-set! table key 'found)
           (list (hashtable-ref table same 'missing)
                 (hashtable-ref table other 'missing))))))

(test-equal "hashtable of ids: two equal ids set two values, and the size is 1 with the last value"
  '(value (1 second))
  (try (lambda ()
         (let* ((table (make-hashtable uuid-hash uuid=?))
                (key (id base-octets))
                (same (id base-octets)))
           (hashtable-set! table key 'first)
           (hashtable-set! table same 'second)
           (list (hashtable-size table)
                 (hashtable-ref table (id base-octets) 'missing))))))

(test-equal "hashtable of ids: 1000 random ids, seed 19, are each found by a fresh equal copy"
  '(value (() 1000))
  (try (lambda ()
         (let* ((rng (make-rng 19))
                (all (make-vector 1000 #f))
                (table (make-hashtable uuid-hash uuid=?)))
           (let fill ((i 0))
             (when (< i 1000)
               (vector-set! all i (rand-list rng 16))
               (hashtable-set! table (id (vector-ref all i)) i)
               (fill (+ i 1))))
           (let* ((failures
                   (collect-failures
                    1000
                    (lambda (i)
                      (let ((found (hashtable-ref table (id (vector-ref all i)) 'missing)))
                        (if (eqv? found i)
                            #f
                            (list 'not-found i found))))))
                  (size (hashtable-size table)))
             (list failures size))))))

;; --- errors -----------------------------------------------------------------

;; A bytevector of 16 bytes is not an id; nor is an id's text, or #f.
(test-equal "uuid=?: a non-id as A is an assertion violation naming uuid=? and A"
  '(assertion-violation uuid=? #t)
  (let ((bad (make-bytevector 16 7)))
    (try-violation (lambda () (uuid=? bad (id base-octets))) bad)))

(test-equal "uuid=?: a non-id as B is an assertion violation naming uuid=? and B"
  '(assertion-violation uuid=? #t)
  (let ((bad "not an id"))
    (try-violation (lambda () (uuid=? (id base-octets) bad)) bad)))

(test-equal "uuid=?: two non-ids are an assertion violation naming uuid=? and A"
  '(assertion-violation uuid=? #t)
  (let ((bad-a (make-bytevector 16 7))
        (bad-b "not an id"))
    (try-violation (lambda () (uuid=? bad-a bad-b)) bad-a)))

(test-equal "uuid<?: a non-id as A is an assertion violation naming uuid<? and A"
  '(assertion-violation uuid<? #t)
  (let ((bad (make-bytevector 16 7)))
    (try-violation (lambda () (uuid<? bad (id base-octets))) bad)))

(test-equal "uuid<?: a non-id as B is an assertion violation naming uuid<? and B"
  '(assertion-violation uuid<? #t)
  (let ((bad "not an id"))
    (try-violation (lambda () (uuid<? (id base-octets) bad)) bad)))

(test-equal "uuid<?: two non-ids are an assertion violation naming uuid<? and A"
  '(assertion-violation uuid<? #t)
  (let ((bad-a (make-bytevector 16 7))
        (bad-b "not an id"))
    (try-violation (lambda () (uuid<? bad-a bad-b)) bad-a)))

(test-equal "uuid-hash: a 16-byte bytevector is an assertion violation naming uuid-hash and it"
  '(assertion-violation uuid-hash #t)
  (let ((bad (make-bytevector 16 7)))
    (try-violation (lambda () (uuid-hash bad)) bad)))

(test-equal "uuid-hash: an id's text is an assertion violation naming uuid-hash and it"
  '(assertion-violation uuid-hash #t)
  (let ((bad "017f22e2-79b0-7cc3-98c4-dc0c0c07398f"))
    (try-violation (lambda () (uuid-hash bad)) bad)))

(test-equal "uuid-hash: #f is an assertion violation naming uuid-hash and it"
  '(assertion-violation uuid-hash #t)
  (try-violation (lambda () (uuid-hash #f)) #f))

(test-end "unique-id-order")

(exit (suite-exit-status runner))
