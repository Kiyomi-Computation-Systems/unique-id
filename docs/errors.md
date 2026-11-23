# Errors

Two things can go wrong: the input is bad, or your code is. The library tells
them apart. Text from outside answers `#f`. Bytes from outside raise, so check
that they are 16 long before `bytevector->uuid`. A mistake in your own code
raises.

```scheme
(import (rnrs) (unique-id) (unique-id generator) (unique-id system))
```

## What answers #f

- `string->uuid` of a string that is not an id.
- `uuid-version` of an id with no version: the nil and max ids, and any id that
  is not of the `rfc9562` variant.
- `uuid-v7-timestamp` of any id that is not a v7 id.

## What raises

Every export checks its arguments. A bad one raises an assertion violation. Bad
text is not a bad argument: `(string->uuid "nope")` answers `#f`, but
`(string->uuid 42)` raises.

The condition has a who, the name of the procedure, and one irritant, the bad
argument. Catch it with `guard` and read them with `condition-who` and
`condition-irritants`.

```scheme
(define (caught thunk)
  (guard (e ((assertion-violation? e)
             (list (condition-who e) (condition-irritants e))))
    (thunk)
    'no-raise))

(caught (lambda () (string->uuid 42)))
;; => (string->uuid (42))
(caught (lambda () (uuid->string "text")))
;; => (uuid->string ("text"))
(caught (lambda () (bytevector->uuid (make-bytevector 15 0))))
;; => (bytevector->uuid (#vu8(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)))
(caught (lambda () (make-uuid-v7 0 4096 (make-bytevector 8 0))))
;; => (make-uuid-v7 (4096))
```

The `'no-raise` matters: `guard` answers its body's value when nothing raises,
so give that case a value you can tell apart. `make-uuid-v7` raises for the
first bad argument, in order. Read the who and the irritant, not the printed
condition, which differs between Chez and Guile.

## The keyed hash

The procedure `make-uuid-hash` answers is checked too. Given anything but an
id, its who is `make-uuid-hash`, not the name you bound it to. So is the who of
a key that is not 8 bytes.

```scheme
(define hash (make-uuid-hash (make-bytevector 8 0)))

(caught (lambda () (hash 'x)))
;; => (make-uuid-hash (x))
```

`make-system-uuid-hash`'s procedure raises the same way.

## Generators

A [generator](generators.md) checks its clock and entropy source when it uses
them.

```scheme
(define (const-entropy n) (make-bytevector n 0))

(caught (lambda () (make-uuid-generator 5 const-entropy)))
;; => (make-uuid-generator (5))
```

A clock must answer an exact integer from 0 to below 2^48. An entropy source,
asked for N bytes, must answer a bytevector of N bytes. Anything else raises an
assertion violation named for the `generate-` procedure that asked, with the
bad answer as the irritant, as here for a clock:

```scheme
(define bad-clock (make-uuid-generator (lambda () "noon") const-entropy))
(caught (lambda () (generate-v7 bad-clock)))
;; => (generate-v7 ("noon"))
```

If the clock or the entropy source itself raises, the raise passes through
unchanged.

```scheme
(define boom
  (make-uuid-generator (lambda () (raise 'clock-broke)) const-entropy))
(guard (e (#t (list 'raised e)))
  (generate-v7 boom))
;; => (raised clock-broke)
```

A call that raises leaves the generator as it was. Here the entropy source
fails once, and the next id carries on (its counter is 1, after 0):

```scheme
(define ok #t)
(define flaky
  (make-uuid-generator
   (lambda () 1000)
   (lambda (n) (if ok (make-bytevector n 0) (raise 'no-entropy)))))

(uuid->string (generate-v7 flaky))
;; => "00000000-03e8-7000-8000-000000000000"
(set! ok #f)
(guard (e (#t (list 'raised e)))
  (generate-v7 flaky))
;; => (raised no-entropy)
(set! ok #t)
(uuid->string (generate-v7 flaky))
;; => "00000000-03e8-7001-8000-000000000000"
```

## Running out

At the last millisecond, 2^48 - 1, with its counter full, `generate-v7` raises
with `error`, not an assertion violation, because nothing is wrong with the
arguments. Its who is `generate-v7` and its one irritant is that millisecond.
[Generators](generators.md) says when this can happen.

```scheme
(define end (make-uuid-generator (lambda () (- (expt 2 48) 1)) const-entropy))
(define (take n) (do ((i 0 (+ i 1))) ((= i n)) (generate-v7 end)))

(take 4096)
(guard (e ((error? e)
           (list (assertion-violation? e)
                 (condition-who e)
                 (condition-irritants e))))
  (generate-v7 end))
;; => (#f generate-v7 (281474976710655))
```

## The system library

`system-entropy` raises an assertion violation for a count that is not an exact
nonnegative integer, and an `error` if `/dev/urandom` answers short. See
[The system library](system.md).

Every procedure's contract is in the [API reference](reference.md).
