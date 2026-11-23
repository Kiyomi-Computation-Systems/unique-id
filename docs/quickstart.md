# Quickstart

The examples build on each other: run them in order, after this import:

```scheme
(import (rnrs) (unique-id) (unique-id generator) (unique-id system))
```

Results marked `e.g.` are random and differ every time.

## 1. Make an id

Make one generator, keep it, and ask it for ids.

```scheme
(define gen (make-system-uuid-generator))

(uuid->string (generate-v7 gen))
;; => e.g. "01a20830-652b-73a4-a9b9-22687141744e"

(uuid-version (generate-v4 gen))
;; => 4
```

A version 7 id starts with the time, so it sorts by when it was made. A
version 4 id is random all through. A generator's version 7 ids increase, so
keep the generator: do not make one per id.

## 2. Turn an id into text and back

```scheme
(define id (string->uuid "017F22E2-79B0-7CC3-98C4-DC0C0C07398F"))

(uuid->string id)
;; => "017f22e2-79b0-7cc3-98c4-dc0c0c07398f"
```

`string->uuid` reads the 36-character form in either case. `uuid->string`
writes lower case. Any other text answers `#f`:

```scheme
(string->uuid "{017f22e2-79b0-7cc3-98c4-dc0c0c07398f}")
;; => #f

(string->uuid "urn:uuid:017f22e2-79b0-7cc3-98c4-dc0c0c07398f")
;; => #f
```

Something that is not a string at all raises. See [Errors](errors.md).

## 3. Turn an id into bytes, or make one from bytes

```scheme
(uuid->bytevector id)
;; => #vu8(1 127 34 226 121 176 124 195 152 196 220 12 12 7 57 143)

(uuid->string (make-uuid-v4 (make-bytevector 16 #x91)))
;; => "91919191-9191-4191-9191-919191919191"
```

An id is 16 bytes, and both directions copy. The `4` in the text is the
version. The variant is the first digit after the next hyphen: one of 8, 9, a
or b. The maker sets both over your bytes. [Ids](ids.md) has the rest.

## 4. Compare and sort

Use `uuid=?` for equality and `uuid<?` for order. Do not use `equal?`: Chez
answers `#f` for two ids with the same bytes, Guile `#t`.

```scheme
(define other (make-uuid-v4 (make-bytevector 16 #x91)))

(uuid=? id (string->uuid "017f22e2-79b0-7cc3-98c4-dc0c0c07398f"))
;; => #t

(uuid<? id other)
;; => #t

(map uuid->string (list-sort uuid<? (list other id nil-uuid max-uuid)))
;; => ("00000000-0000-0000-0000-000000000000"
;;     "017f22e2-79b0-7cc3-98c4-dc0c0c07398f"
;;     "91919191-9191-4191-9191-919191919191"
;;     "ffffffff-ffff-ffff-ffff-ffffffffffff")
```

The order is the order of the 16 bytes, which is also the order of the
lower-case text. `nil-uuid` is all zero bits and `max-uuid` all ones.

## 5. Key a hashtable by ids

```scheme
(define nodes (make-hashtable uuid-hash uuid=?))

(hashtable-set! nodes id 'root)

(hashtable-ref nodes (string->uuid "017F22E2-79B0-7CC3-98C4-DC0C0C07398F") #f)
;; => root

(hashtable-ref nodes other #f)
;; => #f
```

The second id is a different object with the same bytes, and the table finds it.
`uuid-hash` is for ids you made or trust.

## 6. Hash ids that a client sends

`uuid-hash` has no secret, so someone who chooses the ids can make them all
land in one bucket. For ids from outside, use a keyed hash:

```scheme
(define seen (make-hashtable (make-system-uuid-hash) uuid=?))

(hashtable-set! seen id #t)

(hashtable-contains? seen id)
;; => #t
```

The key is random, so never store the hashes. [Hash tables](hashing.md) shows
how to give the key yourself.

## 7. Read what an id says

```scheme
(uuid-version id)
;; => 7

(uuid-v7-timestamp id)
;; => 1645557742000
```

The timestamp is milliseconds since 1970. Both answer `#f` for an id that has
no such thing to say: see [Ids](ids.md) for `uuid-variant` and the nil id.

## Where next

The guides explain each part: [Ids](ids.md), [Generators](generators.md),
[The system library](system.md), [Hash tables](hashing.md) and
[Errors](errors.md). The [API reference](reference.md) lists every export.
