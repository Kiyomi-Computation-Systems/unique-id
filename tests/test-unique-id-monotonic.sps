#!r6rs
;;; (unique-id generator): a generator's v7 ids increase, except when the clock
;;; falls more than 10 seconds behind the last id.
;;;
;;; Each run drives generate-v7 over a scripted clock and an entropy source
;;; that draws from a seeded linear congruential generator, and checks every
;;; id it answers against the last id the same generator answered:
;;;
;;;   - When the clock is more than 10000 ms below the last id's timestamp,
;;;     the id is a reset: its timestamp is the clock's answer.
;;;   - Otherwise the id is greater, under uuid<?.
;;;   - Every id's timestamp is from the clock's answer to 10001 ms past it,
;;;     and is the clock's answer whenever that exceeds every earlier
;;;     timestamp since the last reset.
;;;   - Every id is version 7, of variant rfc9562.
;;;   - The clock is called once per id, and the entropy source once, for 8
;;;     or 10 bytes.
;;;
;;; The runs are a held clock; a clock that steps back and holds; one that
;;; steps back exactly 10000 ms and holds; one that steps back 10001 ms; one
;;; that steps back 10001 ms from a full counter; one that jumps forward; a
;;; random walk of the clock; a held clock at 2^48 - 2; and two generators
;;; over one clock.
;;;
;;; Every call into the library is guarded, so a raise is recorded as a
;;; failure and ends its run. A run answers its first failures, which must be
;;; none.
(import (rnrs)
        (srfi :64)
        (unique-id)
        (unique-id generator)
        (unique-id-testing))

(define runner (test-runner-simple))
(test-runner-current runner)

;; --- helpers ----------------------------------------------------------------

;; try : (-> Any) -> (U (List 'value Any) (List 'raised Any))
;; What THUNK answered, or whatever it raised.
(define (try thunk)
  (guard (e (#t (list 'raised e)))
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

;; index-list : Nat -> (Listof Nat)
;; 0 up to N - 1.
(define (index-list n)
  (let loop ((i (- n 1)) (acc '()))
    (if (< i 0) acc (loop (- i 1) (cons i acc)))))

;; field : (Listof (Pair Symbol Any)) Symbol -> Any
;; What a run answered under KEY.
(define (field result key)
  (cdr (assq key result)))

;; list-min : (Listof Nat) -> (U Nat #f)
;; The least of L, or #f when L is empty.
(define (list-min l)
  (and (pair? l)
       (let loop ((m (car l)) (rest (cdr l)))
         (cond ((null? rest) m)
               ((< (car rest) m) (loop (car rest) (cdr rest)))
               (else (loop m (cdr rest)))))))

;; list-max : (Listof Nat) -> (U Nat #f)
;; The greatest of L, or #f when L is empty.
(define (list-max l)
  (and (pair? l)
       (let loop ((m (car l)) (rest (cdr l)))
         (cond ((null? rest) m)
               ((> (car rest) m) (loop (car rest) (cdr rest)))
               (else (loop m (cdr rest)))))))

;; list-last : (Listof Nat) -> (U Nat #f)
;; The last of L, or #f when L is empty.
(define (list-last l)
  (and (pair? l)
       (if (null? (cdr l)) (car l) (list-last (cdr l)))))

;; list-reverse-tail : (Listof Nat) -> (Listof Nat)
;; L without its last element.
(define (list-reverse-tail l)
  (if (or (null? l) (null? (cdr l)))
      '()
      (cons (car l) (list-reverse-tail (cdr l)))))

;; safe-tail : (Listof Any) Nat -> (Listof Any)
;; L without its first K elements, or '() when L is shorter.
(define (safe-tail l k)
  (cond ((null? l) '())
        ((= k 0) l)
        (else (safe-tail (cdr l) (- k 1)))))

;; Walk : a vector of Nat, the clock's answers in call order.
;; Picks : a vector of Nat, the generator each call goes to.

;; make-walk : Nat Nat Nat -> Walk
;; N clock answers drawn from SEED, the first START. After each answer, the
;; next steps back 1 to 50 ms (1 in 16), moves forward 1 to 5 ms (12 in 16),
;; or repeats it (3 in 16), so the clock drifts forward.
(define (make-walk seed start n)
  (let ((rng (make-rng seed))
        (walk (make-vector n start)))
    (let loop ((i 1) (now start))
      (if (>= i n)
          walk
          (let* ((r (mod (rng) 16))
                 (next (cond ((= r 0) (- now (+ 1 (mod (rng) 50))))
                             ((<= r 12) (+ now 1 (mod (rng) 5)))
                             (else now))))
            (vector-set! walk i next)
            (loop (+ i 1) next))))))

;; make-picks : Nat Nat Nat -> Picks
;; N picks, each 0 to K - 1, drawn from SEED.
(define (make-picks seed n k)
  (let ((rng (make-rng seed))
        (picks (make-vector n 0)))
    (let loop ((i 0))
      (if (= i n)
          picks
          (begin
            (vector-set! picks i (mod (rng) k))
            (loop (+ i 1)))))))

;; run-script : (Listof Nat) Nat (Nat -> Nat) (Nat -> Nat) (U Nat #f) Nat
;;              -> (Listof (Pair Symbol Any))
;; Makes one generator per seed in ENTROPY-SEEDS, over one clock that answers
;; (SCRIPT I) on call I, and calls generate-v7 up to N times, call I on the
;; generator (PICK I). The entropy source of each draws from its seed and
;; answers a fresh bytevector of the length asked. Every id is checked against
;; the generator's own earlier ids. A call is a reset when its NOW is more than
;; 10000 below the timestamp of the generator's last id; the id then must carry
;; NOW, and need not exceed the last id, and the timestamps it is held against
;; start again from it. When STOP-TS is a number, the run ends
;; EXTRA calls after the first id whose timestamp is at least STOP-TS. A call
;; that raises, or a generator that cannot be made, ends the run as a failure.
;; The answer holds, under these keys:
;;   failures  the first 5 failures, each (I NOW GENERATOR TAGS ID LAST-ID TS
;;             MAX-TS), or (raised I NOW GENERATOR); '() when every id passed
;;   calls     how many calls were made
;;   stamps    each id's timestamp, in call order
;;   ticks     the calls whose NOW exceeded every earlier timestamp
;;   behinds   the calls whose NOW was below an earlier timestamp
;;   resets    the calls that were resets, in call order
;;   counts    each generator's number of ids
;;   lasts     each generator's last timestamp, or #f
(define (run-script entropy-seeds n script pick stop-ts extra)
  (let* ((k (length entropy-seeds))
         (current 0)
         (clock-count 0)
         (clock (lambda ()
                  (set! clock-count (+ clock-count 1))
                  current))
         (ent-count (make-vector k 0))
         (ent-size (make-vector k #f))
         (lasts (make-vector k #f))
         (last-ts (make-vector k #f))
         (maxs (make-vector k -1))
         (counts (make-vector k 0))
         (reset-calls '())
         (make-entropy
          (lambda (idx seed)
            (let ((rng (make-rng seed)))
              (lambda (len)
                (vector-set! ent-count idx (+ 1 (vector-ref ent-count idx)))
                (vector-set! ent-size idx len)
                (u8-list->bytevector (rand-list rng len))))))
         (gens (guard (e (#t #f))
                 (list->vector
                  (map (lambda (idx seed)
                         (make-uuid-generator clock (make-entropy idx seed)))
                       (index-list k)
                       entropy-seeds))))
         (finish
          (lambda (found calls stamps ticks behinds)
            (list (cons 'failures (reverse found))
                  (cons 'calls calls)
                  (cons 'stamps (reverse stamps))
                  (cons 'ticks ticks)
                  (cons 'behinds behinds)
                  (cons 'resets (reverse reset-calls))
                  (cons 'counts (vector->list counts))
                  (cons 'lasts (vector->list last-ts))))))
    (if (not gens)
        (finish (list (list 'make-raised)) 0 '() 0 0)
        (let loop ((i 0) (found '()) (kept 0) (stamps '()) (ticks 0)
                   (behinds 0) (hit #f))
          (if (or (= i n) (and hit (= i (+ hit 1 extra))))
              (finish found i stamps ticks behinds)
              (let* ((now (script i))
                     (g (pick i))
                     (out (begin
                            (set! current now)
                            (guard (e (#t (list 'raised)))
                              (let* ((id (generate-v7 (vector-ref gens g)))
                                     (ts (uuid-v7-timestamp id))
                                     (last (vector-ref lasts g))
                                     (max-ts (vector-ref maxs g))
                                     (reset? (and last
                                                  (< now (- (vector-ref last-ts g) 10000))))
                                     (ordered (or (not last) reset?
                                                  (eq? #t (uuid<? last id))))
                                     (ver (uuid-version id))
                                     (var (uuid-variant id))
                                     (id-text (uuid->string id))
                                     (last-text (and last (uuid->string last)))
                                     (tags
                                      (append
                                       (if ordered '() '(not-greater))
                                       (if (and (integer? ts) (exact? ts) (>= ts now))
                                           '()
                                           '(below-now))
                                       (if (or (<= now max-ts) (eqv? ts now))
                                           '()
                                           '(not-now))
                                       (if (or (not reset?) (eqv? ts now))
                                           '()
                                           '(reset-ts))
                                       (if (<= ts (+ now 10001))
                                           '()
                                           '(too-far-ahead))
                                       (if (eqv? ver 7) '() '(version))
                                       (if (eq? var 'rfc9562) '() '(variant))
                                       (if (= clock-count (+ i 1))
                                           '()
                                           '(clock-calls))
                                       (if (and (= (vector-ref ent-count g)
                                                   (+ 1 (vector-ref counts g)))
                                                (memv (vector-ref ent-size g) '(8 10)))
                                           '()
                                           '(entropy-calls)))))
                                (vector-set! lasts g id)
                                (vector-set! last-ts g ts)
                                (vector-set! maxs g (if reset? ts (max max-ts ts)))
                                (if reset? (set! reset-calls (cons i reset-calls)))
                                (vector-set! counts g (+ 1 (vector-ref counts g)))
                                (list 'ok tags id-text last-text ts max-ts))))))
                (if (eq? (car out) 'raised)
                    (finish (cons (list 'raised i now g) found) (+ i 1) stamps ticks behinds)
                    (let* ((tags (list-ref out 1))
                           (ts (list-ref out 4))
                           (max-ts (list-ref out 5))
                           (seen (> (vector-ref counts g) 1))
                           (bad (pair? tags)))
                      (loop (+ i 1)
                            (if (and bad (< kept 5))
                                (cons (list i now g tags (list-ref out 2) (list-ref out 3)
                                            ts max-ts)
                                      found)
                                found)
                            (if (and bad (< kept 5)) (+ kept 1) kept)
                            (cons ts stamps)
                            (if (and seen (> now max-ts)) (+ ticks 1) ticks)
                            (if (and seen (< now max-ts)) (+ behinds 1) behinds)
                            (if (and stop-ts (not hit) (>= ts stop-ts)) i hit))))))))))

;; first-counter : Nat -> Nat
;; The counter the first id of a generator gets when its entropy source is
;; seeded with SEED: the first two bytes it answers, big-endian, AND #x7FF.
(define (first-counter seed)
  (let* ((rng (make-rng seed))
         (b0 (rng))
         (b1 (rng)))
    (bitwise-and (+ (* 256 b0) b1) #x7FF)))

;; held-ms : Nat
;; The clock's answer in the runs that start from a real-looking time,
;; 2022-02-22 19:22:22 UTC.
(define held-ms #x017F22E279B0)

;; top-ms : Nat
;; The greatest timestamp an id holds, 2^48 - 1.
(define top-ms (- (expt 2 48) 1))

(test-begin "unique-id-monotonic")

;; --- a held clock ------------------------------------------------------------

(test-equal "generate-v7: RFC 9562 §6.2, a held clock, entropy seed 101, 6000 ids, rolls over and every id passes"
  '(value (() 6000 #t #t))
  (try (lambda ()
         (let* ((r (run-script '(101) 6000 (lambda (i) held-ms) (lambda (i) 0) #f 0))
                (stamps (field r 'stamps)))
           (list (field r 'failures)
                 (field r 'calls)
                 (eqv? (car stamps) held-ms)
                 (> (list-last stamps) held-ms))))))

;; --- a clock that steps back and holds ---------------------------------------

;; 100 calls at held-ms + I, then held at 1000 ms below the last of them for
;; 6000 calls.
(test-equal "generate-v7: RFC 9562 §6.2, a clock that steps back 1000 ms and holds, entropy seed 102, 100 ids then 6000, rolls over while held back and never goes below the last timestamp"
  '(value (() 6100 #t #t))
  (try (lambda ()
         (let* ((before (+ held-ms 99))
                (r (run-script '(102) 6100
                               (lambda (i) (if (< i 100) (+ held-ms i) (- before 1000)))
                               (lambda (i) 0) #f 0))
                (after (safe-tail (field r 'stamps) 100))
                (low (list-min after)))
           (list (field r 'failures)
                 (field r 'calls)
                 (and low (>= low before))
                 (and (pair? after) (> (list-last after) before)))))))

;; --- a clock that steps back 10000 ms and 10001 ms ---------------------------

;; 100 calls at held-ms + I, then held at 10000 ms below the last of them, until
;; the first id past it, which is the rollover: the furthest back a clock can go
;; without a reset. The id after that would reset, as the last timestamp is then
;; 10001 ms ahead of the clock. Each of the first 100 calls is a new tick, with
;; a fresh counter, so the rollover comes between 1 and 4096 calls after them.
(test-equal "generate-v7: RFC 9562 §6.2, a clock that steps back exactly 10000 ms and holds, entropy seed 110, 100 ids then held until it rolls over, never resets and rolls over to the last timestamp plus 1"
  '(value (() #t () #t #t))
  (try (lambda ()
         (let* ((before (+ held-ms 99))
                (r (run-script '(110) 6100
                               (lambda (i) (if (< i 100) (+ held-ms i) (- before 10000)))
                               (lambda (i) 0) (+ before 1) 0))
                (calls (field r 'calls))
                (stamps (field r 'stamps))
                (after (safe-tail stamps 100)))
           (list (field r 'failures)
                 (and (> calls 100) (<= calls 4196))
                 (field r 'resets)
                 (and (= (length after) (- calls 100))
                      (eqv? (list-min after) before)
                      (eqv? (list-max (list-reverse-tail after)) before))
                 (eqv? (list-last stamps) (+ before 1)))))))

;; The same, held at 10001 ms below: the call after the 100th resets, once.
(test-equal "generate-v7: a clock that steps back 10001 ms and holds, entropy seed 111, 100 ids then 6000, resets once to the stepped-back time, then rolls over while held and increases"
  '(value (() 6100 (100) #t #t #t))
  (try (lambda ()
         (let* ((before (+ held-ms 99))
                (back (- before 10001))
                (r (run-script '(111) 6100
                               (lambda (i) (if (< i 100) (+ held-ms i) back))
                               (lambda (i) 0) #f 0))
                (after (safe-tail (field r 'stamps) 100)))
           (list (field r 'failures)
                 (field r 'calls)
                 (field r 'resets)
                 (and (pair? after) (eqv? (car after) back))
                 (and (pair? after) (>= (list-min after) back))
                 (and (pair? after) (> (list-last after) back)))))))

;; The same from a full counter: the clock holds until the counter is full, then
;; steps back 10001 ms and holds. The call at the step resets, and does not roll
;; over to the last timestamp plus 1.
(test-equal "generate-v7: a clock that holds until the counter is full, then steps back 10001 ms and holds, entropy seed 112, 3000 calls after the step, resets once to the stepped-back time and increases"
  '(value (() #t #t #t #t #t))
  (try (lambda ()
         (let* ((back (- held-ms 10001))
                (jump (- 4096 (first-counter 112)))
                (r (run-script '(112) (+ jump 3000)
                               (lambda (i) (if (< i jump) held-ms back))
                               (lambda (i) 0) #f 0))
                (after (safe-tail (field r 'stamps) jump)))
           (list (field r 'failures)
                 (eqv? (field r 'calls) (+ jump 3000))
                 (equal? (field r 'resets) (list jump))
                 (and (pair? after) (eqv? (car after) back))
                 (and (pair? after) (>= (list-min after) back))
                 (and (pair? after) (> (list-last after) back)))))))

;; --- a clock that jumps forward ----------------------------------------------

(test-equal "generate-v7: RFC 9562 §6.2, a clock that holds until the counter is full and then jumps forward 10^12 ms, entropy seed 103, the first id after the jump carries the new time and the run rolls over"
  '(value (() #t #t #t #t))
  (try (lambda ()
         (let* ((jumped (+ held-ms 1000000000000))
                ;; The counter starts at (first-counter 103) and rises by 1
                ;; per call, so it is full, 4095, after call 4095 - start;
                ;; the jump is the next call.
                (jump (- 4096 (first-counter 103)))
                (r (run-script '(103) (+ jump 5000)
                               (lambda (i) (if (< i jump) held-ms jumped))
                               (lambda (i) 0) #f 0))
                (before (let loop ((l (field r 'stamps)) (k jump) (acc '()))
                          (if (or (null? l) (= k 0)) acc (loop (cdr l) (- k 1) (cons (car l) acc)))))
                (after (safe-tail (field r 'stamps) jump)))
           (list (field r 'failures)
                 (and (>= jump 2049) (= (length before) jump)
                      (eqv? (list-min before) held-ms)
                      (eqv? (list-max before) held-ms))
                 (eqv? (field r 'calls) (+ jump 5000))
                 (and (pair? after) (eqv? (car after) jumped))
                 (and (pair? after) (> (list-last after) jumped)))))))

;; --- a random walk -----------------------------------------------------------

(test-equal "generate-v7: RFC 9562 §6.2, a random walk of the clock that repeats, steps back up to 50 ms and moves forward up to 5 ms, walk seed 4, entropy seed 104, 20000 calls, covers new ticks and stepped-back calls"
  '(value (() 20000 () #t #t))
  (try (lambda ()
         (let* ((walk (make-walk 4 held-ms 20000))
                (r (run-script '(104) 20000 (lambda (i) (vector-ref walk i))
                               (lambda (i) 0) #f 0)))
           (list (field r 'failures)
                 (field r 'calls)
                 (field r 'resets)
                 (>= (field r 'ticks) 1000)
                 (>= (field r 'behinds) 100))))))

;; --- the end of time ---------------------------------------------------------

(test-equal "generate-v7: RFC 9562 §6.2, a held clock at 2^48 - 2, entropy seed 105, rolls over to 2^48 - 1 and the run stops 100 ids after it, 4096 - counter + 101 calls, before the generator runs out"
  '(value (() #t #t #t #t))
  (try (lambda ()
         (let* ((start (- top-ms 1))
                (r (run-script '(105) 20000 (lambda (i) start) (lambda (i) 0) top-ms 100))
                (stamps (field r 'stamps))
                (calls (field r 'calls)))
           (list (field r 'failures)
                 (and (pair? stamps) (eqv? (car stamps) start))
                 (eqv? (list-last stamps) top-ms)
                 (eqv? (list-max stamps) top-ms)
                 ;; The first id's counter is full after 4096 - c ids at
                 ;; 2^48 - 2; the next is the first at 2^48 - 1; 100 follow.
                 (eqv? calls (+ (- 4096 (first-counter 105)) 101)))))))

;; --- two generators over one clock -------------------------------------------

(test-equal "generate-v7: RFC 9562 §6.2, two generators over one held clock, entropy seeds 106 and 107, pick seed 6, 12000 interleaved calls, each rolls over and increases on its own"
  '(value (() 12000 #t #t))
  (try (lambda ()
         (let* ((picks (make-picks 6 12000 2))
                (r (run-script '(106 107) 12000 (lambda (i) held-ms)
                               (lambda (i) (vector-ref picks i)) #f 0))
                (counts (field r 'counts))
                (lasts (field r 'lasts)))
           (list (field r 'failures)
                 (field r 'calls)
                 (and (= (length counts) 2)
                      (>= (list-min counts) 5000)
                      (= (+ (car counts) (cadr counts)) 12000))
                 (and (= (length lasts) 2)
                      (> (list-min lasts) held-ms)))))))

(test-equal "generate-v7: RFC 9562 §6.2, two generators over one random walk, walk seed 7, entropy seeds 108 and 109, pick seed 8, 20000 interleaved calls, each increases on its own"
  '(value (() 20000 () #t #t))
  (try (lambda ()
         (let* ((walk (make-walk 7 held-ms 20000))
                (picks (make-picks 8 20000 2))
                (r (run-script '(108 109) 20000 (lambda (i) (vector-ref walk i))
                               (lambda (i) (vector-ref picks i)) #f 0))
                (counts (field r 'counts)))
           (list (field r 'failures)
                 (field r 'calls)
                 (field r 'resets)
                 (and (= (length counts) 2) (>= (list-min counts) 9000))
                 (>= (field r 'behinds) 100))))))

(test-end "unique-id-monotonic")

(exit (suite-exit-status runner))
