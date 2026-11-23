#!r6rs
;;; (unique-id generator): Version 4 and version 7 ids from a clock and an
;;; entropy source, whose version 7 ids increase while the clock stays within
;;; 10 seconds of the last one.
;;;
;;;   make-uuid-generator  uuid-generator?   a generator over CLOCK and ENTROPY
;;;   generate-v4                            a random id
;;;   generate-v7                            an id greater than the last v7
;;;                                          id, but after a reset
;;;
;;; A generator keeps the last v7 id's millisecond and its 12-bit counter, and
;;; belongs to its caller: it is not safe to share between threads. Its order
;;; holds among one generator's ids, not across generators or restarts, and
;;; breaks at each fall of the clock more than 10 seconds behind the last id:
;;; the generator then starts over from the clock.
;;; Plain R6RS, importing (rnrs) and (unique-id).
(library (unique-id generator)
  (export make-uuid-generator uuid-generator? generate-v4 generate-v7)
  (import (rnrs) (unique-id))

  ;; A generator: CLOCK, ENTROPY, and the last v7 id's millisecond and counter,
  ;; both #f until the first v7 id. The record is sealed and opaque, and its
  ;; type, constructor and accessors are not exported. It is generative.
  (define-record-type (generator make-generator generator?)
    (fields (immutable clock generator-clock)
            (immutable entropy generator-entropy)
            (mutable last-ms generator-last-ms generator-last-ms-set!)
            (mutable last-counter generator-last-counter
                     generator-last-counter-set!))
    (sealed #t)
    (opaque #t))

  ;; make-uuid-generator : (-> Nat) (Nat -> Bytevector) -> Generator
  ;; A fresh generator over CLOCK and ENTROPY; it calls neither. CLOCK answers
  ;; the Unix time in milliseconds, leap seconds excluded.
  ;; ENTROPY, given N, answers N random bytes. An assertion violation unless
  ;; both are procedures, naming the first that is not.
  (define (make-uuid-generator clock entropy)
    (unless (procedure? clock)
      (assertion-violation 'make-uuid-generator "not a procedure" clock))
    (unless (procedure? entropy)
      (assertion-violation 'make-uuid-generator "not a procedure" entropy))
    (make-generator clock entropy #f #f))

  ;; rollback-allowance : Nat
  ;; How far, in milliseconds, the clock may fall behind the last v7 id before
  ;; the generator starts over from it: 10 seconds, enough for a time daemon's
  ;; correction or a leap second.
  (define rollback-allowance 10000)

  ;; uuid-generator? : Any -> Boolean
  ;; #t for a generator, #f for anything else.
  (define (uuid-generator? x) (generator? x))

  ;; check-generator : Symbol Any -> Void
  ;; Returns when X is a generator, else an assertion violation naming WHO,
  ;; with X as its one irritant.
  (define (check-generator who x)
    (unless (generator? x)
      (assertion-violation who "not a generator" x)))

  ;; ask-entropy : Symbol Generator Nat -> Bytevector
  ;; Calls ENTROPY of G once with N. Answers its answer, unchanged, when that
  ;; is a bytevector of N bytes, else an assertion violation naming WHO, with
  ;; the answer as its one irritant. A raise from ENTROPY passes through.
  (define (ask-entropy who g n)
    (let ((bytes ((generator-entropy g) n)))
      (unless (and (bytevector? bytes) (= (bytevector-length bytes) n))
        (assertion-violation who "not a bytevector of the length asked" bytes))
      bytes))

  ;; generate-v4 : Generator -> Uuid
  ;; The v4 id of the 16 bytes that (ENTROPY 16) answers, through make-uuid-v4.
  ;; It never calls CLOCK and leaves the v7 state alone. An assertion violation
  ;; when G is not a generator, or when ENTROPY does not answer 16 bytes.
  (define (generate-v4 g)
    (check-generator 'generate-v4 g)
    (make-uuid-v4 (ask-entropy 'generate-v4 g 16)))

  ;; generate-v7 : Generator -> Uuid
  ;; A v7 id greater, under uuid<?, than the last v7 id G answered, unless
  ;; CLOCK has fallen more than 10 seconds behind that id's millisecond; then
  ;; the id takes CLOCK's answer, and is less.
  ;; When CLOCK's answer is past the last millisecond, or that far behind it,
  ;; the id takes it, with the 12-bit counter seeded from the first two of
  ;; (ENTROPY 10)'s bytes, top bit cleared. Else it keeps the last millisecond,
  ;; with the counter one more and (ENTROPY 8); and when that counter is full,
  ;; it takes the last millisecond plus 1, reseeded from (ENTROPY 10). The
  ;; id's last 8 bytes are ENTROPY's. An assertion violation when G is not a
  ;; generator, when CLOCK does not answer an exact integer from 0 to below
  ;; 2^48, or when ENTROPY does not answer the bytes asked. An `error` when the
  ;; counter is full at millisecond 2^48 - 1. A call that raises leaves G as it
  ;; was. CLOCK and ENTROPY must not call G: G's state is read before ENTROPY
  ;; is called, so an id ENTROPY made through G has its millisecond and
  ;; counter repeated by the id G then answers, which may sort below it.
  (define (generate-v7 g)
    (check-generator 'generate-v7 g)
    (let ((now ((generator-clock g))))
      ;; integer? comes before exact?, which raises on a non-number. The
      ;; arithmetic from here on is generic: NOW reaches 2^48, past the 24-bit
      ;; fixnum range R6RS promises.
      (unless (and (integer? now) (exact? now) (<= 0 now) (< now (expt 2 48)))
        (assertion-violation 'generate-v7 "not a millisecond time" now))
      (let ((last-ms (generator-last-ms g))
            (last-counter (generator-last-counter g)))
        (cond
          ((or (not last-ms) (> now last-ms))
           (finish-fresh g now))
          ((< now (- last-ms rollback-allowance))
           ;; The clock has fallen too far behind to follow: start over from it.
           (finish-fresh g now))
          ((< last-counter 4095)
           ;; Same tick, or the clock stepped back by up to 10 seconds: keep
           ;; the last millisecond.
           (let ((counter (+ last-counter 1)))
             (finish g last-ms counter (ask-entropy 'generate-v7 g 8))))
          ((= last-ms (- (expt 2 48) 1))
           (error 'generate-v7 "out of timestamps" last-ms))
          (else
           ;; Rollover: run ahead of the clock by one millisecond.
           (finish-fresh g (+ last-ms 1)))))))

  ;; finish-fresh : Generator Nat -> Uuid
  ;; The v7 id at millisecond MS with a counter seeded from (ENTROPY 10): the
  ;; first two bytes, big-endian, AND #x7FF, so the counter's top bit is
  ;; clear. The other 8 bytes are its last 8, in a fresh bytevector.
  (define (finish-fresh g ms)
    (let* ((bytes (ask-entropy 'generate-v7 g 10))
           (seed (bitwise-and (bytevector-uint-ref bytes 0 (endianness big) 2)
                              #x7FF))
           (rest (make-bytevector 8 0)))
      (bytevector-copy! bytes 2 rest 0 8)
      (finish g ms seed rest)))

  ;; finish : Generator Nat Nat Bytevector -> Uuid
  ;; The v7 id of MS, COUNTER and the 8 BYTES. Only after it is made does G
  ;; take MS and COUNTER as its last, so a raise leaves G as it was.
  (define (finish g ms counter bytes)
    (let ((id (make-uuid-v7 ms counter bytes)))
      (generator-last-ms-set! g ms)
      (generator-last-counter-set! g counter)
      id)))
