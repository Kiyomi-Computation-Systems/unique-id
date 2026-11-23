# The system library

`(unique-id system)` is where the library touches the world. The core and the
generator read no clock and no randomness; this library does. It gives you the
real clock, the real random bytes, and two things made from them.

```scheme
(import (rnrs) (unique-id) (unique-id generator) (unique-id system))
```

## What is in it

| Name | What it is |
|:--|:--|
| `system-clock` | The Unix time in milliseconds. |
| `system-entropy` | `n` fresh random bytes from `/dev/urandom`. |
| `make-system-uuid-generator` | A new [generator](generators.md) from both. |
| `make-system-uuid-hash` | A new keyed hash, keyed with 8 random bytes. |

For most programs, the generator is all you need:

```scheme
(define g (make-system-uuid-generator))

(uuid->string (generate-v7 g))
;; => e.g. "01a20830-7505-778a-911a-cae5b270a2b3"
```

The result differs every time. Each call of `make-system-uuid-generator` or
`make-system-uuid-hash` answers a new one. The library keeps none of its own, so
make one and keep it.

## The clock

```scheme
(system-clock)
;; => e.g. 1795433735446
```

It answers whole milliseconds since 1970, as an exact integer. It reads
SRFI-19's `time-utc`, which is the Unix time. (SRFI-19's `time-tai` and
`time-monotonic` run 37 seconds ahead of it, and would put wrong times in your
ids.)

## The entropy

```scheme
(system-entropy 8)
;; => e.g. #vu8(209 75 114 216 219 2 64 239)

(bytevector-length (system-entropy 16))
;; => 16

(bytevector-length (system-entropy 0))
;; => 0
```

You get a fresh bytevector of exactly `n` bytes that nobody else holds. `n`
must be an exact nonnegative integer, or it is an assertion violation.

Each call that reads opens `/dev/urandom` for itself, reads, and closes it
before it returns. It does not keep one port open. Three reasons:

- **Forks.** A port that reads ahead holds bytes in a buffer. If the process
  forks, parent and child both hold the same buffer and would hand out the same
  bytes. With a port per call, nothing is buffered across a call, so a forked
  child never repeats its parent's bytes.
- **Threads.** No two threads share a port.
- **No leaks.** No port outlives a call, even if the read raises.

The port is also unbuffered. A buffered one reads thousands of bytes to answer
16.

The price is one `open` and one `close` per call. That is most of the cost of a
system id (see [Costs](#costs)), and it is what makes forks safe.

If `/dev/urandom` ever answers fewer bytes than you asked for, `system-entropy`
raises an error whose irritant is what it got. The kernel does not do this.

## The hash

```scheme
(define hash (make-system-uuid-hash))

(define id (string->uuid "017F22E2-79B0-7CC3-98C4-DC0C0C07398F"))

(= (hash id) (hash id))
;; => #t

(hash id)
;; => e.g. 3931743512
```

It is [`make-uuid-hash`](hashing.md) with a key drawn from `system-entropy`.
Its numbers differ from one process to the next, so never store them. Use it
as a hashtable's hash function for ids a client sends:

```scheme
(define table (make-hashtable hash uuid=?))
```

## Where it runs

`(unique-id system)` needs `/dev/urandom`, so it runs on Linux and macOS. It
imports `(srfi :19)`, for the clock. On Chez that is chez-srfi's. On Guile it
is Guile's own. The core and the generator need neither. If you cannot use the
system library, pass `make-uuid-generator` a clock and entropy of your own.

See [Getting started](getting-started.md) for how to put chez-srfi on Chez's
path.

## Costs

For a sense of scale, measured on Chez 10.4.0, in microseconds:

| What | Time |
|:--|:--|
| `generate-v7` from a system generator | 1.47 |
| `system-entropy` alone | 1.37 |
| `make-uuid-v7` from given bytes | 0.027 |
| `uuid-hash` | 0.06 |
| the keyed hash | 0.43 |

So the port work is most of a system id's cost. That is the price of fork
safety, not something to avoid. Your numbers will differ.

Every export is in the [reference](reference.md#unique-id-system).
