# Ids

An id is a UUID: a 128-bit label that is, for all practical purposes, unique.
You write it as 36 characters.

```scheme
(import (rnrs) (unique-id))

(define id (string->uuid "017F22E2-79B0-7CC3-98C4-DC0C0C07398F"))
(uuid->string id)
;; => "017f22e2-79b0-7cc3-98c4-dc0c0c07398f"
```

An id is a Scheme value of its own, not a string. To make fresh ids, see
[Generators](generators.md) and [The system library](system.md).

## Which version

This library makes two kinds, as RFC 9562 defines them.

- **Version 4** is 122 random bits. Nothing else is in it. Use it when ids only
  need to be unique and need not say anything.
- **Version 7** is the time in milliseconds first, then random bits. Ids made
  later sort after ids made earlier, so a database index grows at its end.
  Use it as a record key, or when you want creation order.

If unsure, choose 7. It does show roughly when the id was made. If that is a
secret, choose 4.

## Text

`string->uuid` reads the canonical form: 8, 4, 4, 4 and 12 hex digits, joined by
hyphens. Either case works. `uuid->string` writes lower case, in a fresh
string.

```scheme
(uuid->string (string->uuid "919108F7-52D1-4320-9BAC-F847DB4148A8"))
;; => "919108f7-52d1-4320-9bac-f847db4148a8"
```

Anything else, such as braces, a `urn:uuid:` prefix, missing hyphens or spaces
around it, is not an id, so `string->uuid` answers `#f`.

```scheme
(string->uuid "{017f22e2-79b0-7cc3-98c4-dc0c0c07398f}")
;; => #f
(string->uuid "017f22e279b07cc398c4dc0c0c07398f")
;; => #f
```

It does not raise, because bad text is what you expect from a client. Check
the answer. A value that is not a string at all is a bug in your code, and
raises (see [Errors](errors.md)).

## Bytes

An id is 16 bytes. `uuid->bytevector` gives them, and `bytevector->uuid` takes
them. Each makes a copy, so changing one side never changes the other.

```scheme
(uuid->bytevector id)
;; => #vu8(1 127 34 226 121 176 124 195 152 196 220 12 12 7 57 143)

(define bytes (make-bytevector 16 1))
(define copy (bytevector->uuid bytes))
(bytevector-u8-set! bytes 0 99)
(uuid->string copy)
;; => "01010101-0101-0101-0101-010101010101"
```

Bytes of any length but 16 raise; `bytevector->uuid` never answers `#f`. If the
bytes come from outside, check `(= (bytevector-length bytes) 16)` first.

## What an id says

```scheme
(uuid-version id)
;; => 7
(uuid-variant id)
;; => rfc9562
(uuid-v7-timestamp id)
;; => 1645557742000
```

`uuid-version` is 4 or 7 here. `uuid-variant` is the layout: `rfc9562`, else
`ncs`, `microsoft` or `future`. `uuid-v7-timestamp` is the Unix time in
milliseconds the id was made at.

Both answer `#f` when they have nothing to say. A version exists only for the
`rfc9562` layout, and a timestamp only for a v7 id of that layout:

```scheme
(define v4 (string->uuid "919108f7-52d1-4320-9bac-f847db4148a8"))
(list (uuid-version v4) (uuid-v7-timestamp v4))
;; => (4 #f)
```

## Nil and max

`nil-uuid` is all 0 bits and `max-uuid` all 1 bits: the smallest and largest
ids, handy as bounds or "no id yet".

```scheme
(uuid->string nil-uuid)
;; => "00000000-0000-0000-0000-000000000000"
(uuid->string max-uuid)
;; => "ffffffff-ffff-ffff-ffff-ffffffffffff"
```

Neither has a version: the nil id's variant is `ncs` and the max id's is
`future`.

## Making an id from your own bits

`make-uuid-v4` and `make-uuid-v7` read no clock and no random source. They take
every bit they do not fix, so the same input makes the same id: ids for a test.

`make-uuid-v4` takes 16 bytes and overwrites the six bits that say "version 4,
`rfc9562`". `make-uuid-v7` takes the milliseconds (below 2^48), a 12-bit
counter (below 4096) and 8 more bytes.

```scheme
(define tail (u8-list->bytevector '(#x98 #xC4 #xDC #x0C #x0C #x07 #x39 #x8F)))

(uuid->string (make-uuid-v7 1645557742000 #xCC3 tail))
;; => "017f22e2-79b0-7cc3-98c4-dc0c0c07398f"
```

The first two bits of the 8 bytes become `10`. Inputs are never changed. A bad
argument raises.

## Comparing ids

An id is an opaque record. Compare ids with `uuid=?`, never with `equal?`,
which answers `#f` on Chez and `#t` on Guile for two ids with the same bytes.
`uuid<?` orders ids by their 16 bytes, the same order as their lower-case text,
so v7 ids sort by time.

```scheme
(uuid=? id (string->uuid "017f22e2-79b0-7cc3-98c4-dc0c0c07398f"))
;; => #t
(map uuid->string (list-sort uuid<? (list max-uuid id v4 nil-uuid)))
;; => ("00000000-0000-0000-0000-000000000000"
;;     "017f22e2-79b0-7cc3-98c4-dc0c0c07398f"
;;     "919108f7-52d1-4320-9bac-f847db4148a8"
;;     "ffffffff-ffff-ffff-ffff-ffffffffffff")
```

To use ids as hashtable keys, see [Hash tables](hashing.md). Every procedure is
listed in the [API reference](reference.md#unique-id).
