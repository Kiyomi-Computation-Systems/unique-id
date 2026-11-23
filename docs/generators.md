# Generators

A generator makes ids for you. It is a clock plus a source of random bytes, and
you hand it both. It adds one promise: the v7 ids it makes increase, unless the
clock falls more than 10 seconds behind.

Each example works after this import:

```scheme
(import (rnrs) (unique-id) (unique-id generator) (unique-id system))
```

## The normal case

`(unique-id system)` builds a generator over the real clock and `/dev/urandom`.
Make one, keep it, and ask it for ids.

```scheme
(define g (make-system-uuid-generator))

(uuid->string (generate-v7 g))
;; => e.g. "01a20830-7505-778a-911a-cae5b270a2b3"

(uuid->string (generate-v4 g))
;; => e.g. "84479ce3-f29b-42c7-a506-47d691fdf5c3"
```

The results differ every time. [The system library](system.md) says what that
generator is made of. Below is what a generator promises.

## Make your own

`(make-uuid-generator clock entropy)` takes two procedures:

- `clock` is a procedure of no arguments. It answers the Unix time in
  milliseconds, as an exact integer from 0 to below 2^48.
- `entropy` is a procedure of one argument, `n`. It answers a bytevector of
  exactly `n` random bytes.

`make-uuid-generator` calls neither; passing them in is what lets a test give
fixed ones (see [Test your own code](#test-your-own-code)). `generate-v4` asks
`entropy` for 16 bytes and never reads the clock.

## Why v7 ids increase

A v7 id starts with a millisecond timestamp, so ids made later sort later. But
two ids made in the same millisecond would tie. So a generator also keeps a
12-bit counter beside the timestamp.

Here is a clock stuck at one millisecond, and entropy that is all `#xAB`:

```scheme
(define g (make-uuid-generator (lambda () 1645557742000)
                               (lambda (n) (make-bytevector n #xAB))))

(uuid->string (generate-v7 g))   ;; => "017f22e2-79b0-73ab-abab-abababababab"
(uuid->string (generate-v7 g))   ;; => "017f22e2-79b0-73ac-abab-abababababab"
(uuid->string (generate-v7 g))   ;; => "017f22e2-79b0-73ad-abab-abababababab"
```

The time stayed put, so the counter went up by one: `3ab`, `3ac`, `3ad`. A
millisecond's first counter is seeded from random bits (here `#xABAB`, cut to
11 bits, so there is room to count).

When the counter is full, the generator moves the timestamp one millisecond
ahead and seeds a new counter. It runs ahead of the clock rather than let two
ids tie:

```scheme
(define g (make-uuid-generator (lambda () 1645557742000)
                               (lambda (n) (make-bytevector n 0))))
(define ids (make-vector 4097))
(do ((i 0 (+ i 1))) ((= i 4097)) (vector-set! ids i (generate-v7 g)))

;; The counter starts at 0, so ids 0 to 4095 fill the millisecond.
(uuid->string (vector-ref ids 4095))
;; => "017f22e2-79b0-7fff-8000-000000000000"
(uuid->string (vector-ref ids 4096))
;; => "017f22e2-79b1-7000-8000-000000000000"
```

The clock never moved, but the 4097th id is a millisecond ahead of it.

## A clock that steps back

Clocks go backwards: a time daemon corrects them, or a leap second lands. The
generator copes in two ways, split at 10 seconds.

- **Up to 10 seconds behind.** It keeps the last id's millisecond and counts
  on. The ids still increase.
- **More than 10 seconds behind.** It believes the clock and starts over from
  it. That id is smaller than the one before: the one time ids do not increase.

```scheme
(define (scripted-clock times)   ; answers each time once, then the last
  (lambda ()
    (let ((t (car times)))
      (when (pair? (cdr times)) (set! times (cdr times)))
      t)))

(define g (make-uuid-generator
           (scripted-clock '(1645557742000 1645557737000 1645557712000))
           (lambda (n) (make-bytevector n 0))))

(uuid->string (generate-v7 g))   ;; => "017f22e2-79b0-7000-8000-000000000000"
(uuid->string (generate-v7 g))   ;; => "017f22e2-79b0-7001-8000-000000000000"
(uuid->string (generate-v7 g))   ;; => "017f22e2-0480-7000-8000-000000000000"
```

The second call saw a clock 5 seconds behind and kept the old millisecond. The
third saw one 30 behind, and the id went back.

## Running out

The last millisecond, 2^48 - 1, is in the year 10889. With the counter full
there, `generate-v7` raises an error, message `out of timestamps`, while the
clock is within 10 seconds of it. A clock further behind resets the generator
instead. A call that raises leaves the generator as it was.

## One generator, kept

The promise holds for one generator. Two generators, or one process and the
next, know nothing of each other, and their ids can land in any order. So make
one generator and keep it; a fresh one has no memory of the last id. A
generator keeps state with no lock: give each thread its own.

## Test your own code

In a test, give the generator a clock and entropy that answer what you choose.
Entropy that records what it was asked lets you assert that too:

```scheme
(define asked '())
(define (entropy n)
  (set! asked (cons n asked))
  (make-bytevector n 0))

(define gen (make-uuid-generator (lambda () 1645557742000) entropy))
(define id (generate-v7 gen))

(uuid->string id)        ;; => "017f22e2-79b0-7000-8000-000000000000"
(uuid-v7-timestamp id)   ;; => 1645557742000
asked                    ;; => (10)
```

The id is the same on every run. The first id of a millisecond asks for 10
bytes (two seed the counter); later ones ask for 8.

A bad clock or entropy answer raises; see [Errors](errors.md). Every export is
in the [reference](reference.md#unique-id-generator).
