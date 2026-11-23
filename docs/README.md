# unique-id

UUIDs for R6RS Scheme: version 4, random, and version 7, ordered by time, as
[RFC 9562](https://www.rfc-editor.org/rfc/rfc9562) defines them. An id is a
small opaque value you make, print, read, compare and use as a hashtable key.

## A taste

```scheme
(import (rnrs) (unique-id) (unique-id generator) (unique-id system))

(define id (string->uuid "017F22E2-79B0-7CC3-98C4-DC0C0C07398F"))

(uuid->string id)
;; => "017f22e2-79b0-7cc3-98c4-dc0c0c07398f"

(uuid-v7-timestamp id)
;; => 1645557742000

(define gen (make-system-uuid-generator))

(define a (generate-v7 gen))
(define b (generate-v7 gen))

(uuid<? a b)
;; => #t
```

The id is RFC 9562's own example. Its first 48 bits are a time, in
milliseconds since 1970. A generator's version 7 ids increase, so each sorts
after the last, unless the clock falls more than 10 seconds behind. See
[Generators](generators.md).

## Ideas to keep in mind

- **An id is opaque.** You get one from a maker, from text, or from bytes, and
  you ask it questions. You do not reach into it.
- **Compare with `uuid=?`, never `equal?`.** Schemes answer `equal?` on
  records differently. Key a hashtable with `(make-hashtable uuid-hash uuid=?)`.
- **Bad text answers `#f`.** `string->uuid` reads one form, 36 characters, in
  either case. Anything else is `#f`.
- **Make one generator and keep it.** A generator's version 7 ids increase.
  Two generators' ids do not sort against each other.
- **Ids that clients send need the keyed hash.** `uuid-hash` has no secret, so
  anyone can make ids that collide. See [Hash tables](hashing.md).

## What is in it

| Library | Use it when you want to… |
|:--|:--|
| `(unique-id)` | read, write, compare, hash and take apart ids, or make one from bits you give it |
| `(unique-id generator)` | make ids from a clock and a random source that you give it, so tests get fixed ids |
| `(unique-id system)` | make ids from the real clock and `/dev/urandom` |

`(unique-id)` reads no clock and no randomness. Everything that varies is an
argument, so its results are the same every time.

## What it is not

- **Not every UUID version.** Only versions 4 and 7. There are no versions 1,
  3, 5, 6 or 8. It can read and compare an id of any version.
- **Not every text form.** No `urn:uuid:` prefix and no braces.
- **Not shared between threads.** A generator is not safe to use from two
  threads at once. Give each thread its own.
- **Not a store.** A generator does not keep the last timestamp across a
  restart, so ids from before and after one are not ordered against each other.

## Where it runs

The libraries are plain R6RS. `(unique-id)` imports `(rnrs)` alone, and
`(unique-id generator)` adds `(unique-id)`. `(unique-id system)` also imports
`(srfi :19)` and needs `/dev/urandom`, so Linux or macOS. CI runs the suites
on Linux, amd64 and arm64, with Chez Scheme and Guile 3; macOS has passed them
by hand, on arm64.

## Status

Nothing is released on Akku yet. Use it from a checkout:
[Getting started](getting-started.md) shows how.

## Read next

- [Getting started](getting-started.md): get the checkout, test it, run a file.
- [Quickstart](quickstart.md): small examples, one task each.
- [Ids](ids.md): what an id is, which version to choose, and how to read one.
- [Generators](generators.md): why version 7 ids increase, and how to test them.
- [The system library](system.md): the real clock and `/dev/urandom`.
- [Hash tables](hashing.md): `uuid-hash` and the keyed hash.
- [Errors](errors.md): what raises and what answers `#f`.
- [API reference](reference.md): every export, one entry each.
