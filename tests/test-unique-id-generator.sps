#!r6rs
;;; (unique-id generator): what a generator asks of its clock and its entropy
;;; source, and what it answers, by fixed vectors.
;;;
;;; The clock and the entropy source are scripted stand-ins that share one
;;; log. The log holds `clock` for each call to the clock and N for each call
;;; to the entropy source asking for N bytes, in the order the calls came. A
;;; stand-in asked more times than it was scripted for logs `clock-overrun` or
;;; `entropy-overrun`, so the log shows it. Every call into the library runs
;;; under a guard that tags what happened: (value V), with an id in V turned to
;;; (id TEXT) so that it never equals a string, (violation WHO OK?) for an assertion violation, (error WHO OK?) for an
;;; `error`, (raised X) for anything else a stand-in raised, and
;;; (raised-condition) for any other condition. OK? is #t when the one
;;; irritant is eqv? to the one expected. Ids are compared as text, never with
;;; equal?. The monotonic order of ids belongs to another suite.
(import (rnrs)
        (srfi :64)
        (unique-id)
        (unique-id generator)
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
;;   Step       (List Outcome (Listof Any)): the outcome of one call and the log
;;              of that call.
;;   Script     what a stand-in answers: either a vector of answers, one per
;;              call, or a procedure of the call number and the arguments of
;;              the call that answers.
;;   World      a vector of the clock stand-in, the entropy stand-in, the
;;              generator over them and a drain procedure.
;;   Scenario   what a scenario answers: its steps in a list, or (escaped).

;; norm : Any -> Any
;; V, with an id turned into (id TEXT), TEXT being its canonical text.
(define (norm v)
  (if (uuid? v) (list 'id (uuid->string v)) v))

;; vid : String -> (List 'value (List 'id String))
;; The outcome of a call that answers the id whose canonical text is TEXT.
(define (vid text)
  (list 'value (list 'id text)))

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

;; attempt : (-> Any) -> (U (List 'value Any) (List 'raised))
;; (value V) with V normalised when THUNK answers V, (raised) when it raises
;; anything.
(define (attempt thunk)
  (guard (e (#t (list 'raised)))
    (list 'value (norm (thunk)))))

;; guarded : (-> Any) -> Any
;; What THUNK answers, or (escaped) when it raises. A scenario runs under it,
;; so a raise outside the tagged calls cannot end the suite.
(define (guarded thunk)
  (guard (e (#t (list 'escaped)))
    (thunk)))

;; hex->bytevector : String -> Bytevector
;; The bytes TEXT spells, two hex digits each.
(define (hex->bytevector text)
  (let* ((n (div (string-length text) 2))
         (bv (make-bytevector n 0)))
    (do ((i 0 (+ i 1)))
        ((= i n) bv)
      (bytevector-u8-set! bv i
                          (string->number (substring text (* 2 i) (+ 2 (* 2 i))) 16)))))

;; hex-digits : String
;; The 16 digits, in lower case.
(define hex-digits "0123456789abcdef")

;; hex3 : Nat -> String
;; The 3 lower case hex digits of N, below 4096.
(define (hex3 n)
  (string (string-ref hex-digits (div n 256))
          (string-ref hex-digits (mod (div n 16) 16))
          (string-ref hex-digits (mod n 16))))

;; repeat : Nat Any -> (Listof Any)
;; A list of N copies of X.
(define (repeat n x)
  (let loop ((k 0) (acc '()))
    (if (= k n) acc (loop (+ k 1) (cons x acc)))))

;; raise-marker : Any
;; The first of a pair that a script answers to make the stand-in raise the
;; second.
(define raise-marker (list 'raise))

;; raising : Any -> Any
;; A script entry: the stand-in raises V.
(define (raising v) (cons raise-marker v))

;; play : Script Nat (Listof Any) (-> Any) -> Any
;; The answer number I of SCRIPT. A vector answers its element I, and calls
;; ON-OVERRUN past its end, answering the symbol overrun. A procedure answers
;; what it gives for I and ARGS. An entry made by `raising` raises instead.
(define (play script i args on-overrun)
  (let ((entry (cond ((procedure? script) (apply script i args))
                     ((< i (vector-length script)) (vector-ref script i))
                     (else (on-overrun) 'overrun))))
    (if (and (pair? entry) (eq? (car entry) raise-marker))
        (raise (cdr entry))
        entry)))

;; new-world : Script Script -> World
;; A generator over a scripted clock and entropy source, with their shared log.
;; The World is (vector CLOCK ENTROPY GENERATOR DRAIN), DRAIN being a
;; (-> (Listof Any)) that answers the log so far, in order, and empties it.
(define (new-world clock-script entropy-script)
  (let* ((events '())
         (note! (lambda (x) (set! events (cons x events))))
         (clock-calls 0)
         (entropy-calls 0)
         (clock (lambda ()
                  (let ((i clock-calls))
                    (set! clock-calls (+ clock-calls 1))
                    (note! 'clock)
                    (play clock-script i '()
                          (lambda () (note! 'clock-overrun))))))
         (entropy (lambda (n)
                    (let ((i entropy-calls))
                      (set! entropy-calls (+ entropy-calls 1))
                      (note! n)
                      (play entropy-script i (list n)
                            (lambda () (note! 'entropy-overrun))))))
         (drain (lambda ()
                  (let ((log (reverse events)))
                    (set! events '())
                    log))))
    (vector clock entropy (make-uuid-generator clock entropy) drain)))

;; world-clock : World -> (-> Nat)
;; The clock stand-in of W.
(define (world-clock w) (vector-ref w 0))

;; world-entropy : World -> (Nat -> Bytevector)
;; The entropy stand-in of W.
(define (world-entropy w) (vector-ref w 1))

;; world-generator : World -> Generator
;; The generator of W.
(define (world-generator w) (vector-ref w 2))

;; drain : World -> (Listof Any)
;; The calls the stand-ins of W have seen since the last drain, in order.
(define (drain w) ((vector-ref w 3)))

;; step7 : World Any -> (List Any (Listof Any))
;; One generate-v7 on W: what it did, classified with IRRITANT as the expected
;; irritant, then the log of that call.
(define (step7 w irritant)
  (let* ((result (classify (lambda () (generate-v7 (world-generator w))) irritant))
         (log (drain w)))
    (list result log)))

;; step4 : World Any -> (List Any (Listof Any))
;; One generate-v4 on W, as step7.
(define (step4 w irritant)
  (let* ((result (classify (lambda () (generate-v4 (world-generator w))) irritant))
         (log (drain w)))
    (list result log)))

;; run-steps : World Nat Any -> (Listof (List Any (Listof Any)))
;; N calls of step7 on W, in order.
(define (run-steps w n irritant)
  (let loop ((k 0) (acc '()))
    (if (= k n)
        (reverse acc)
        (let* ((s (step7 w irritant)))
          (loop (+ k 1) (cons s acc))))))

;; step-mismatches : (Listof Step) Nat Nat (Nat -> String) (Listof Any)
;;                   -> (Listof (List Nat Step Step))
;; For each step I of STEPS from FROM to TO, not counting TO, those that are
;; not the step of the id (ID-OF I) with the log LOG, as (call-number actual
;; expected), call numbers counted from 1.
(define (step-mismatches steps from to id-of log)
  (let ((v (list->vector steps)))
    (let loop ((i from) (acc '()))
      (if (= i to)
          (reverse acc)
          (let* ((actual (vector-ref v i))
                 (expected (list (vid (id-of i)) log)))
            (loop (+ i 1)
                  (if (equal? actual expected)
                      acc
                      (cons (list (+ i 1) actual expected) acc))))))))

;; --- vectors ----------------------------------------------------------------

;; t-a6 : Nat
;; RFC 9562 A.6's timestamp.
(define t-a6 #x017F22E279B0)

;; two48 : Nat
;; 2^48, the first millisecond count that is too large.
(define two48 (expt 2 48))

;; Answers of the entropy source, each a procedure that builds a fresh
;; bytevector, so that no stand-in is handed an object that another test could
;; see changed. The first two bytes of a 10-byte answer are the seed of the
;; counter: #xFCC3 AND #x7FF is #x4C3.
;; b10-a, b8-a, b8-b, b10-b, b16-a3, roll10-first, roll8 : (-> Bytevector)
(define (b10-a) (hex->bytevector "FCC318C4DC0C0C07398F"))
(define (b8-a) (hex->bytevector "5BACF847DB4148A8"))
(define (b8-b) (hex->bytevector "919108F752D13320"))
(define (b10-b) (hex->bytevector "0123D8C4DC0C0C07398F"))
(define (b16-a3) (hex->bytevector "919108F752D133205BACF847DB4148A8"))
(define (roll10-first) (hex->bytevector "07FF18C4DC0C0C07398F"))
(define (roll8) (hex->bytevector "18C4DC0C0C07398F"))

;; Ids those answers make.
;; id-4c3, id-4c4, id-a3 : String
(define id-4c3 "017f22e2-79b0-74c3-98c4-dc0c0c07398f")
(define id-4c4 "017f22e2-79b0-74c4-9bac-f847db4148a8")
(define id-a3 "919108f7-52d1-4320-9bac-f847db4148a8")

;; Steps a scenario expects.
;; step-4c3, step-4c4, step-bad-now, step-a3 : Step
(define step-4c3 (list (vid id-4c3) '(clock 10)))
(define step-4c4 (list (vid id-4c4) '(clock 8)))
(define step-bad-now '((violation generate-v7 #t) (clock)))
(define step-a3 (list (vid id-a3) '(16)))

;; step-4c3-at-0 : Step
;; The step of a new tick at millisecond 0, with A.3's 10 bytes.
(define step-4c3-at-0
  (list (vid "00000000-0000-74c3-98c4-dc0c0c07398f") '(clock 10)))

;; roll-id : Nat -> String
;; The id at 79b0 with counter C, and the rollover table's rand_b.
(define (roll-id c)
  (string-append "017f22e2-79b0-7" (hex3 c) "-98c4-dc0c0c07398f"))

;; top-id : Nat -> String
;; The id at the timestamp #xFFFFFFFFFFFE with counter C, and the same rand_b.
(define (top-id c)
  (string-append "ffffffff-fffe-7" (hex3 c) "-98c4-dc0c0c07398f"))

;; last-id : Nat -> String
;; The id at the timestamp #xFFFFFFFFFFFF with counter C, and the same rand_b.
(define (last-id c)
  (string-append "ffffffff-ffff-7" (hex3 c) "-98c4-dc0c0c07398f"))

;; good-entropy : (Nat -> Bytevector)
;; An entropy source that answers N zero bytes.
(define good-entropy (lambda (n) (make-bytevector n 0)))

;; good-clock : (-> Nat)
;; A clock that answers 0.
(define good-clock (lambda () 0))

;; bad-string : String
;; One string object, so that an irritant can be eqv? to it.
(define bad-string (string #\x))

(test-begin "unique-id-generator")

;; --- construction -----------------------------------------------------------

(test-equal "make-uuid-generator: calls neither the clock nor the entropy source"
  '(#t ())
  (guarded
   (lambda ()
     (let* ((w (new-world (vector) (vector)))
            (made (uuid-generator? (world-generator w))))
       (list made (drain w))))))

(test-equal "make-uuid-generator: the generator is opaque, record? answers #f"
  '(value #f)
  (attempt (lambda ()
             (record? (make-uuid-generator good-clock good-entropy)))))

(test-equal "uuid-generator?: #t for a generator"
  '(value #t)
  (attempt (lambda ()
             (uuid-generator? (make-uuid-generator good-clock good-entropy)))))

(for-each
 (lambda (entry)
   (test-equal (string-append "uuid-generator?: #f for " (car entry))
     '(value #f)
     (attempt (lambda () (uuid-generator? ((cdr entry)))))))
 (list (cons "a procedure" (lambda () (lambda () 1)))
       (cons "a list" (lambda () (list 1 2)))
       (cons "an id" (lambda () (bytevector->uuid (b16-a3))))
       (cons "the symbol generator" (lambda () 'generator))))

(for-each
 (lambda (entry)
   ;; entry: (label clock entropy irritant)
   (let ((label (car entry))
         (clock (cadr entry))
         (entropy (caddr entry))
         (irritant (cadddr entry)))
     (test-equal (string-append "make-uuid-generator: assertion violation, " label)
       '(violation make-uuid-generator #t)
       (classify (lambda () (make-uuid-generator clock entropy)) irritant))))
 (list (list "CLOCK 5, the irritant is CLOCK" 5 good-entropy 5)
       (list "CLOCK #f, the irritant is CLOCK" #f good-entropy #f)
       (list "CLOCK a list, the irritant is CLOCK" '() good-entropy '())
       (list "ENTROPY 5, the irritant is ENTROPY" good-clock 5 5)
       (list "ENTROPY a string, the irritant is ENTROPY" good-clock bad-string bad-string)
       (list "ENTROPY the symbol e, the irritant is ENTROPY" good-clock 'e 'e)
       (list "CLOCK 5 and ENTROPY a string, the irritant is CLOCK" 5 bad-string 5)
       (list "CLOCK the symbol c and ENTROPY 7, the irritant is CLOCK" 'c 7 'c)))

;; --- the basic table: A.6's timestamp, A.3's bytes --------------------------

;; basic-call : Nat -> (U Step (List 'escaped))
;; Calls 1 to K of the basic table on a new generator: the step of call K.
(define (basic-call k)
  (guarded
   (lambda ()
     (let* ((w (new-world (vector t-a6 t-a6 (- t-a6 1) (+ t-a6 1))
                          (vector (b10-a) (b8-a) (b8-b) (b10-b))))
            (steps (run-steps w k #f)))
       (list-ref steps (- k 1))))))

(test-equal "generate-v7, A.6 and A.3 table call 1: new tick, asks 10"
  (list (vid "017f22e2-79b0-74c3-98c4-dc0c0c07398f") '(clock 10))
  (basic-call 1))

(test-equal "generate-v7, A.6 and A.3 table call 2: same tick, asks 8"
  (list (vid "017f22e2-79b0-74c4-9bac-f847db4148a8") '(clock 8))
  (basic-call 2))

(test-equal "generate-v7, A.6 and A.3 table call 3: clock stepped back, asks 8"
  (list (vid "017f22e2-79b0-74c5-9191-08f752d13320") '(clock 8))
  (basic-call 3))

(test-equal "generate-v7, A.6 and A.3 table call 4: next tick, asks 10"
  (list (vid "017f22e2-79b1-7123-98c4-dc0c0c07398f") '(clock 10))
  (basic-call 4))

;; --- the rollover on a stepped-back clock ------------------------------

;; rollover-steps : (-> (Listof Step))
;; Calls 1 to 2050: the clock answers t-a6 for calls 1 to 2049 and one
;; millisecond less for call 2050.
(define (rollover-steps)
  (let ((w (new-world (lambda (i) (if (< i 2049) t-a6 (- t-a6 1)))
                      (lambda (i n)
                        (cond ((= i 0) (roll10-first))
                              ((= n 8) (roll8))
                              (else (b10-a)))))))
    (run-steps w 2050 #f)))

(test-equal "generate-v7, 6.2 rollover: asks 10, then 8 2048 times, then 10"
  (append '(clock 10)
          (apply append (repeat 2048 '(clock 8)))
          '(clock 10))
  (guarded
   (lambda ()
     (apply append (map cadr (rollover-steps))))))

(test-equal "generate-v7, 6.2 rollover: call 1, call 2049 and call 2050 ids"
  (list (vid (roll-id #x7FF))
        (vid (roll-id #xFFF))
        (vid "017f22e2-79b1-74c3-98c4-dc0c0c07398f"))
  (guarded
   (lambda ()
     (let ((v (list->vector (rollover-steps))))
       (list (car (vector-ref v 0))
             (car (vector-ref v 2048))
             (car (vector-ref v 2049)))))))

(test-equal "generate-v7, 6.2 rollover: calls 2 to 2049 count from 800 to FFF, none out"
  '(2050 ())
  (guarded
   (lambda ()
     (let ((steps (rollover-steps)))
       (list (length steps)
             (step-mismatches steps 1 2049
                              (lambda (i) (roll-id (+ #x800 (- i 1))))
                              '(clock 8)))))))

(test-equal "generate-v7, 6.2 rollover: a bad answer to the rollover's ENTROPY leaves the state"
  (list (list (vid (roll-id #xFFF)) '(clock 8))
        '((violation generate-v7 #t) (clock 10))
        (list (vid "017f22e2-79b1-74c3-98c4-dc0c0c07398f") '(clock 10)))
  (guarded
   (lambda ()
     (let* ((bad (make-bytevector 8 1))
            (w (new-world (lambda (i) (if (< i 2049) t-a6 (- t-a6 1)))
                          (lambda (i n)
                            (cond ((= i 0) (roll10-first))
                                  ((= i 2049) bad)
                                  ((= n 8) (roll8))
                                  (else (b10-a))))))
            (before (run-steps w 2049 #f))
            (s-bad (step7 w bad))
            (s-good (step7 w #f)))
       (list (list-ref before 2048) s-bad s-good)))))

;; --- a full counter, then the clock moves on --------------------------------

(test-equal "generate-v7, A.6: a full counter, then a new tick: the tick wins whatever the counter"
  (list (vid "017f22e2-79b5-74c3-98c4-dc0c0c07398f") '(clock 10))
  (guarded
   (lambda ()
     (let* ((w (new-world (lambda (i) (if (< i 2049) t-a6 #x017F22E279B5))
                          (lambda (i n)
                            (cond ((= i 0) (roll10-first))
                                  ((= n 8) (roll8))
                                  (else (b10-a))))))
            (before (run-steps w 2049 #f))
            (s (step7 w #f)))
       s))))

;; --- a clock more than 10 seconds behind resets ----------------------------

;; t-reset : Nat
;; A.6's timestamp as a decimal count, 1645557742000.
(define t-reset 1645557742000)

;; reset-call : Nat -> (U Step (List 'escaped))
;; Calls 1 to K of the reset table on a new generator: the step of call K.
(define (reset-call k)
  (guarded
   (lambda ()
     (let* ((w (new-world (vector t-reset (- t-reset 10000)
                                  (- t-reset 10001) (- t-reset 10001))
                          (vector (b10-a) (b8-a) (b10-b) (b8-b))))
            (steps (run-steps w k #f)))
       (list-ref steps (- k 1))))))

(test-equal "generate-v7, A.6 reset table call 1: new tick, asks 10"
  (list (vid "017f22e2-79b0-74c3-98c4-dc0c0c07398f") '(clock 10))
  (reset-call 1))

(test-equal "generate-v7, A.6 reset table call 2: exactly 10 s behind does not reset, asks 8"
  (list (vid "017f22e2-79b0-74c4-9bac-f847db4148a8") '(clock 8))
  (reset-call 2))

(test-equal "generate-v7, A.6 reset table call 3: 10.001 s behind resets, asks 10"
  (list (vid "017f22e2-529f-7123-98c4-dc0c0c07398f") '(clock 10))
  (reset-call 3))

(test-equal "generate-v7, A.6 reset table call 4: counts on from the reset, asks 8"
  (list (vid "017f22e2-529f-7124-9191-08f752d13320") '(clock 8))
  (reset-call 4))

(test-equal "generate-v7, A.6 recovery from the top: a clock far below #xFFFFFFFFFFFF resets, asks 10"
  (list (list (vid "ffffffff-ffff-74c3-98c4-dc0c0c07398f") '(clock 10))
        (list (vid "017f22e2-79b0-74c3-98c4-dc0c0c07398f") '(clock 10)))
  (guarded
   (lambda ()
     (let* ((w (new-world (vector #xFFFFFFFFFFFF t-reset) (vector (b10-a) (b10-a))))
            (s1 (step7 w #f))
            (s2 (step7 w #f)))
       (list s1 s2)))))

;; full-world : Nat Nat -> World
;; A world whose clock answers AT for calls 1 to 2049 and LATER for call 2050.
;; Its entropy source answers roll10-first for call 1, roll8 to 8 and b10-a to
;; every other 10.
(define (full-world at later)
  (new-world (lambda (i) (if (< i 2049) at later))
             (lambda (i n)
               (cond ((= i 0) (roll10-first))
                     ((= n 8) (roll8))
                     (else (b10-a))))))

(test-equal "generate-v7, A.6: an exhausted generator at the top resets, rather than raise"
  (list (vid "017f22e2-79b0-74c3-98c4-dc0c0c07398f") '(clock 10))
  (guarded
   (lambda ()
     (let* ((w (full-world #xFFFFFFFFFFFF t-reset))
            (before (run-steps w 2049 #f))
            (s (step7 w #f)))
       s))))

(test-equal "generate-v7, A.6: a full counter and a clock 10.001 s behind resets, it asks 10"
  (list (vid "017f22e2-529f-74c3-98c4-dc0c0c07398f") '(clock 10))
  (guarded
   (lambda ()
     (let* ((w (full-world t-a6 (- t-a6 10001)))
            (before (run-steps w 2049 #f))
            (s (step7 w #f)))
       s))))

(test-equal "generate-v7, 6.2: a full counter and a clock exactly 10 s behind rolls over, it does not reset"
  (list (vid "017f22e2-79b1-74c3-98c4-dc0c0c07398f") '(clock 10))
  (guarded
   (lambda ()
     (let* ((w (full-world t-a6 (- t-a6 10000)))
            (before (run-steps w 2049 #f))
            (s (step7 w #f)))
       s))))

;; reset-raise-scenario : Any Any -> Scenario
;; The steps, in a list of three, of: a first id at counter #x4C3; then a call
;; 10.001 s behind, a reset, whose entropy source answers ENTRY, with IRRITANT
;; the one expected; then a call 5 s behind the first id.
(define (reset-raise-scenario entry irritant)
  (guarded
   (lambda ()
     (let* ((w (new-world (vector t-reset (- t-reset 10001) (- t-reset 5000))
                          (vector (b10-a) entry (b8-a))))
            (s1 (step7 w #f))
            (s2 (step7 w irritant))
            (s3 (step7 w #f)))
       (list s1 s2 s3)))))

(test-equal "generate-v7, A.6: a bad answer to the reset's ENTROPY leaves the state, the next call counts on"
  (list step-4c3 '((violation generate-v7 #t) (clock 10)) step-4c4)
  (let ((bad (make-bytevector 3 1)))
    (reset-raise-scenario bad bad)))

(test-equal "generate-v7, A.6: a raise from the reset's ENTROPY leaves the state, the next call counts on"
  (list step-4c3 '((raised boom) (clock 10)) step-4c4)
  (reset-raise-scenario (raising 'boom) #f))

;; --- running out of timestamp: 6.1 error handling ---------------------------

;; runout-world : Nat -> World
;; A world whose clock answers TOP always, and whose entropy source answers
;; roll10-first to 10 and roll8 to 8.
(define (runout-world top)
  (new-world (lambda (i) top)
             (lambda (i n) (if (= n 10) (roll10-first) (roll8)))))

(test-equal "generate-v7, 6.1 running out below the top: call 1 and call 2049 ids"
  (list (list (vid (top-id #x7FF)) '(clock 10))
        (list (vid (top-id #xFFF)) '(clock 8)))
  (guarded
   (lambda ()
     (let ((v (list->vector (run-steps (runout-world #xFFFFFFFFFFFE) 2049 #f))))
       (list (vector-ref v 0) (vector-ref v 2048))))))

(test-equal "generate-v7, 6.1 running out below the top: call 2050 rolls over to the last timestamp"
  (list (vid "ffffffff-ffff-77ff-98c4-dc0c0c07398f") '(clock 10))
  (guarded
   (lambda ()
     (list-ref (run-steps (runout-world #xFFFFFFFFFFFE) 2050 #f) 2049))))

(test-equal "generate-v7, 6.1 running out below the top: calls 2051 to 4098 count from 800 to FFF"
  '(4098 ())
  (guarded
   (lambda ()
     (let ((steps (run-steps (runout-world #xFFFFFFFFFFFE) 4098 #f)))
       (list (length steps)
             (step-mismatches steps 2050 4098
                              (lambda (i) (last-id (+ #x800 (- i 2050))))
                              '(clock 8)))))))

(test-equal "generate-v7, 6.1 running out below the top: call 4099 raises an error and asks ENTROPY nothing"
  '((error generate-v7 #t) (clock))
  (guarded
   (lambda ()
     (list-ref (run-steps (runout-world #xFFFFFFFFFFFE) 4099 281474976710655)
               4098))))

(test-equal "generate-v7, 6.1 running out below the top: a further call raises the same"
  '((error generate-v7 #t) (clock))
  (guarded
   (lambda ()
     (list-ref (run-steps (runout-world #xFFFFFFFFFFFE) 4100 281474976710655)
               4099))))

(test-equal "generate-v7, 6.1 running out at the top: call 1 and call 2049 ids"
  (list (list (vid (last-id #x7FF)) '(clock 10))
        (list (vid (last-id #xFFF)) '(clock 8)))
  (guarded
   (lambda ()
     (let ((v (list->vector (run-steps (runout-world #xFFFFFFFFFFFF) 2049 #f))))
       (list (vector-ref v 0) (vector-ref v 2048))))))

(test-equal "generate-v7, 6.1 running out at the top: call 2050 raises an error and asks ENTROPY nothing"
  '((error generate-v7 #t) (clock))
  (guarded
   (lambda ()
     (list-ref (run-steps (runout-world #xFFFFFFFFFFFF) 2050 281474976710655)
               2049))))

(test-equal "generate-v7, 6.1 running out at the top: a further call raises the same"
  '((error generate-v7 #t) (clock))
  (guarded
   (lambda ()
     (list-ref (run-steps (runout-world #xFFFFFFFFFFFF) 2051 281474976710655)
               2050))))

;; A bad NOW is checked before running out.

(test-equal "generate-v7, 6.1: a bad CLOCK answer on an exhausted generator is an assertion violation, and asks ENTROPY nothing"
  '((violation generate-v7 #t) (clock))
  (guarded
   (lambda ()
     (let ((w (new-world (lambda (i) (if (< i 2049) #xFFFFFFFFFFFF -1))
                         (lambda (i n) (if (= n 10) (roll10-first) (roll8))))))
       (list-ref (run-steps w 2050 -1) 2049)))))

;; --- v4, A.3 ----------------------------------------------------------------

(test-equal "generate-v4, A.3: the id of A.3's bytes, asking 16 and never the clock"
  (list (vid id-a3) '(16))
  (guarded
   (lambda ()
     (step4 (new-world (vector) (vector (b16-a3))) #f))))

(test-equal "generate-v4 between generate-v7s, A.3 and A.6: ids, the last counter the first plus 1"
  (list (vid id-4c3) (vid id-a3) (vid id-4c4))
  (guarded
   (lambda ()
     (let* ((w (new-world (vector t-a6 t-a6) (vector (b10-a) (b16-a3) (b8-a))))
            (s1 (step7 w #f))
            (s2 (step4 w #f))
            (s3 (step7 w #f)))
       (list (car s1) (car s2) (car s3))))))

(test-equal "generate-v4 between generate-v7s, A.3 and A.6: asks 10, 16, 8 and the clock only for v7"
  '(clock 10 16 clock 8)
  (guarded
   (lambda ()
     (let* ((w (new-world (vector t-a6 t-a6) (vector (b10-a) (b16-a3) (b8-a))))
            (s1 (step7 w #f))
            (s2 (step4 w #f))
            (s3 (step7 w #f)))
       (append (cadr s1) (cadr s2) (cadr s3))))))

;; --- bad answers of the clock ------------------------------------------

;; clock-scenario : Any Boolean -> Scenario
;; The steps, in a list of three, of: with FIRST?, a first id, else (none);
;; then a call whose clock answers BAD; then a call at t-a6.
(define (clock-scenario bad first?)
  (guarded
   (lambda ()
     (let* ((w (new-world (if first? (vector t-a6 bad t-a6) (vector bad t-a6))
                          (if first? (vector (b10-a) (b8-a)) (vector (b10-a)))))
            (s1 (if first? (step7 w #f) '(none)))
            (s2 (step7 w bad))
            (s3 (step7 w #f)))
       (list s1 s2 s3)))))

(for-each
 (lambda (entry)
   (let ((label (car entry))
         (bad (cdr entry)))
     (test-equal (string-append "generate-v7, A.6: CLOCK answers " label
                                " on a new generator, refused, the state is as it was")
       (list '(none) step-bad-now step-4c3)
       (clock-scenario bad #f))
     (test-equal (string-append "generate-v7, A.6: CLOCK answers " label
                                " after a first id, refused, the counter goes on from the first")
       (list step-4c3 step-bad-now step-4c4)
       (clock-scenario bad #t))))
 (list (cons "2^48" two48)
       (cons "-1" -1)
       (cons "1/2" (/ 1 2))
       (cons "an inexact integer" 1645557742000.)
       (cons "the symbol tick" 'tick)))

(test-equal "generate-v7: CLOCK answers 0 on a new generator, accepted"
  (list (list (vid "00000000-0000-74c3-98c4-dc0c0c07398f") '(clock 10)))
  (guarded
   (lambda ()
     (let* ((w (new-world (vector 0) (vector (b10-a))))
            (s (step7 w #f)))
       (list s)))))

(test-equal "generate-v7: CLOCK answers 2^48 - 1 on a new generator, accepted"
  (list (list (vid "ffffffff-ffff-74c3-98c4-dc0c0c07398f") '(clock 10)))
  (guarded
   (lambda ()
     (let* ((w (new-world (vector (- two48 1)) (vector (b10-a))))
            (s (step7 w #f)))
       (list s)))))

(test-equal "generate-v7, A.6: CLOCK answers 0 after a first id, accepted as a reset, it asks 10"
  (list step-4c3 step-4c3-at-0)
  (guarded
   (lambda ()
     (let* ((w (new-world (vector t-a6 0) (vector (b10-a) (b10-a))))
            (s1 (step7 w #f))
            (s2 (step7 w #f)))
       (list s1 s2)))))

(test-equal "generate-v7, A.6: CLOCK answers 2^48 - 1 after a first id, accepted as a new tick"
  (list step-4c3
        (list (vid "ffffffff-ffff-74c3-98c4-dc0c0c07398f") '(clock 10)))
  (guarded
   (lambda ()
     (let* ((w (new-world (vector t-a6 (- two48 1)) (vector (b10-a) (b10-a))))
            (s1 (step7 w #f))
            (s2 (step7 w #f)))
       (list s1 s2)))))

;; --- a bad answer of the entropy source at a new tick ---------------------

(test-equal "generate-v7, A.6: a bad answer, then a raise, at a new tick leave the state, the good call is a new tick"
  (list step-4c3
        '((violation generate-v7 #t) (clock 10))
        '((raised boom) (clock 10))
        (list (vid "017f22e2-79b1-74c3-98c4-dc0c0c07398f") '(clock 10)))
  (guarded
   (lambda ()
     (let* ((bad (make-bytevector 8 1))
            (w (new-world (vector t-a6 #x017F22E279B1 #x017F22E279B1 #x017F22E279B1)
                          (vector (b10-a) bad (raising 'boom) (b10-a))))
            (s1 (step7 w #f))
            (s2 (step7 w bad))
            (s3 (step7 w #f))
            (s4 (step7 w #f)))
       (list s1 s2 s3 s4)))))

;; --- bad answers of the entropy source ---------------------------------

;; entropy-scenario : (-> Any) Boolean -> Scenario
;; The steps, in a list of three, of: with FIRST?, a first id at counter #x4C3,
;; else (none); then a call whose entropy source answers what MAKE-BAD makes;
;; then a good call at the same tick.
(define (entropy-scenario make-bad first?)
  (guarded
   (lambda ()
     (let* ((bad (make-bad))
            (w (new-world (if first? (vector t-a6 t-a6 t-a6) (vector t-a6 t-a6))
                          (if first? (vector (b10-a) bad (b8-a)) (vector bad (b10-a)))))
            (s1 (if first? (step7 w #f) '(none)))
            (s2 (step7 w bad))
            (s3 (step7 w #f)))
       (list s1 s2 s3)))))

(for-each
 (lambda (entry)
   (test-equal (string-append "generate-v7, A.6: ENTROPY answers " (car entry)
                              " to a request for 10 on a new generator, refused, the state is as it was")
     (list '(none) '((violation generate-v7 #t) (clock 10)) step-4c3)
     (entropy-scenario (cdr entry) #f)))
 (list (cons "a string" (lambda () "not bytes"))
       (cons "#f" (lambda () #f))
       (cons "8 bytes" (lambda () (make-bytevector 8 1)))
       (cons "9 bytes" (lambda () (make-bytevector 9 1)))
       (cons "11 bytes" (lambda () (make-bytevector 11 1)))))

(for-each
 (lambda (entry)
   (test-equal (string-append "generate-v7, A.6: ENTROPY answers " (car entry)
                              " to a request for 8 after a first id, refused, the counter goes on from the first")
     (list step-4c3 '((violation generate-v7 #t) (clock 8)) step-4c4)
     (entropy-scenario (cdr entry) #t)))
 (list (cons "a string" (lambda () "not bytes"))
       (cons "#f" (lambda () #f))
       (cons "7 bytes" (lambda () (make-bytevector 7 1)))
       (cons "9 bytes" (lambda () (make-bytevector 9 1)))
       (cons "10 bytes" (lambda () (make-bytevector 10 1)))))

;; v4-entropy-scenario : (-> Any) -> (U (List Step Step) (List 'escaped))
;; The steps of a generate-v4 whose entropy source answers what MAKE-BAD makes,
;; then of one that answers A.3's bytes.
(define (v4-entropy-scenario make-bad)
  (guarded
   (lambda ()
     (let* ((bad (make-bad))
            (w (new-world (vector) (vector bad (b16-a3))))
            (s1 (step4 w bad))
            (s2 (step4 w #f)))
       (list s1 s2)))))

(for-each
 (lambda (entry)
   (test-equal (string-append "generate-v4, A.3: ENTROPY answers " (car entry)
                              ", refused, the next good call answers A.3's id")
     (list '((violation generate-v4 #t) (16)) step-a3)
     (v4-entropy-scenario (cdr entry))))
 (list (cons "a string" (lambda () "not bytes"))
       (cons "15 bytes" (lambda () (make-bytevector 15 1)))
       (cons "17 bytes" (lambda () (make-bytevector 17 1)))
       (cons "8 bytes" (lambda () (make-bytevector 8 1)))))

;; --- raises pass through ----------------------------------------------------

(test-equal "generate-v7, A.6: a raise from the clock on a new generator passes through, nothing else is called"
  (list '((raised boom) (clock)) step-4c3)
  (guarded
   (lambda ()
     (let* ((w (new-world (vector (raising 'boom) t-a6) (vector (b10-a))))
            (s1 (step7 w #f))
            (s2 (step7 w #f)))
       (list s1 s2)))))

(test-equal "generate-v7, A.6: a raise from the clock after a first id passes through, the state is as it was"
  (list step-4c3 '((raised boom) (clock)) step-4c4)
  (guarded
   (lambda ()
     (let* ((w (new-world (vector t-a6 (raising 'boom) t-a6) (vector (b10-a) (b8-a))))
            (s1 (step7 w #f))
            (s2 (step7 w #f))
            (s3 (step7 w #f)))
       (list s1 s2 s3)))))

(test-equal "generate-v7, A.6: a raise from the entropy source on a new generator passes through"
  (list '((raised boom) (clock 10)) step-4c3)
  (guarded
   (lambda ()
     (let* ((w (new-world (vector t-a6 t-a6) (vector (raising 'boom) (b10-a))))
            (s1 (step7 w #f))
            (s2 (step7 w #f)))
       (list s1 s2)))))

(test-equal "generate-v7, A.6: a raise from the entropy source after a first id passes through, the state is as it was"
  (list step-4c3 '((raised boom) (clock 8)) step-4c4)
  (guarded
   (lambda ()
     (let* ((w (new-world (vector t-a6 t-a6 t-a6)
                          (vector (b10-a) (raising 'boom) (b8-a))))
            (s1 (step7 w #f))
            (s2 (step7 w #f))
            (s3 (step7 w #f)))
       (list s1 s2 s3)))))

(test-equal "generate-v4, A.3: a raise from the entropy source passes through, nothing else is called"
  (list '((raised boom) (16)) step-a3)
  (guarded
   (lambda ()
     (let* ((w (new-world (vector) (vector (raising 'boom) (b16-a3))))
            (s1 (step4 w #f))
            (s2 (step4 w #f)))
       (list s1 s2)))))

;; --- an argument that is no generator ---------------------------------------

(for-each
 (lambda (who-entry)
   (for-each
    (lambda (arg-entry)
      (test-equal (string-append (symbol->string (car who-entry)) ": assertion violation for "
                                 (car arg-entry) ", and nothing is called")
        (list (list 'violation (car who-entry) #t) '())
        (guarded
         (lambda ()
           (let* ((w (new-world (vector t-a6) (vector (b10-a) (b16-a3))))
                  (arg ((cdr arg-entry) w))
                  (result (classify (lambda () ((cdr who-entry) arg)) arg))
                  (log (drain w)))
             (list result log))))))
    (list (cons "the clock procedure" (lambda (w) (world-clock w)))
          (cons "the entropy procedure" (lambda (w) (world-entropy w)))
          (cons "#f" (lambda (w) #f))
          (cons "an id" (lambda (w) (bytevector->uuid (b16-a3)))))))
 (list (cons 'generate-v4 generate-v4)
       (cons 'generate-v7 generate-v7)))

;; --- ENTROPY's answer is the caller's ---------------------------------------

(test-equal "generate-v7, A.6: the entropy answers are unchanged after the calls"
  '(#t #t)
  (guarded
   (lambda ()
     (let* ((a10 (hex->bytevector "FCC318C4DC0C0C07398F"))
            (a8 (hex->bytevector "5BACF847DB4148A8"))
            (w (new-world (vector t-a6 t-a6) (vector a10 a8))))
       (generate-v7 (world-generator w))
       (generate-v7 (world-generator w))
       (list (bytevector=? a10 (hex->bytevector "FCC318C4DC0C0C07398F"))
             (bytevector=? a8 (hex->bytevector "5BACF847DB4148A8")))))))

(test-equal "generate-v4, A.3: the entropy answer is unchanged after the call"
  '(#t)
  (guarded
   (lambda ()
     (let* ((a16 (hex->bytevector "919108F752D133205BACF847DB4148A8"))
            (w (new-world (vector) (vector a16))))
       (generate-v4 (world-generator w))
       (list (bytevector=? a16
                           (hex->bytevector "919108F752D133205BACF847DB4148A8")))))))

(test-equal "generate-v7, A.6: changing the entropy answers afterwards changes no id"
  (list id-4c3 id-4c4 id-4c3 id-4c4)
  (guarded
   (lambda ()
     (let* ((a10 (b10-a))
            (a8 (b8-a))
            (w (new-world (vector t-a6 t-a6) (vector a10 a8)))
            (g (world-generator w))
            (u1 (generate-v7 g))
            (u2 (generate-v7 g))
            (t1 (uuid->string u1))
            (t2 (uuid->string u2)))
       (bytevector-fill! a10 255)
       (bytevector-fill! a8 255)
       (list t1 t2 (uuid->string u1) (uuid->string u2))))))

(test-equal "generate-v7, A.6: changing an entropy answer afterwards changes no later id"
  (list step-4c3 step-4c4)
  (guarded
   (lambda ()
     (let* ((a10 (b10-a))
            (w (new-world (vector t-a6 t-a6) (vector a10 (b8-a))))
            (s1 (step7 w #f)))
       (bytevector-fill! a10 255)
       (let* ((s2 (step7 w #f)))
         (list s1 s2))))))

(test-equal "generate-v4, A.3: changing the entropy answer afterwards changes no id"
  (list id-a3 id-a3)
  (guarded
   (lambda ()
     (let* ((a16 (b16-a3))
            (w (new-world (vector) (vector a16)))
            (u (generate-v4 (world-generator w)))
            (before (uuid->string u)))
       (bytevector-fill! a16 255)
       (list before (uuid->string u))))))

(test-end "unique-id-generator")

(exit (suite-exit-status runner))
