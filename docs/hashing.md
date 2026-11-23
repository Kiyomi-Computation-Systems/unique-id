# Hash tables

A hashtable finds a key fast by turning it into a number, its hash. Ids are
records, so a table needs to be told how to hash and compare them.

```scheme
(import (rnrs) (unique-id) (unique-id system))

(define seen (make-hashtable uuid-hash uuid=?))
(define id (string->uuid "017F22E2-79B0-7CC3-98C4-DC0C0C07398F"))

(hashtable-set! seen id 'first)

(hashtable-ref seen (string->uuid "017f22e2-79b0-7cc3-98c4-dc0c0c07398f") #f)
;; => first
(hashtable-ref seen (string->uuid "919108f7-52d1-4320-9bac-f847db4148a8") #f)
;; => #f
```

Two separate ids with the same bytes find the same entry. Do not use
`equal-hash` and `equal?` for ids: they disagree between Chez and Guile.

## `uuid-hash`

`uuid-hash` answers a number below 2^23 from the id's 16 bytes. It is fast, and
ids that differ in one byte get different hashes. Its numbers are the same on
every Scheme.

```scheme
(map uuid-hash
     (list id (string->uuid "919108f7-52d1-4320-9bac-f847db4148a8") nil-uuid))
;; => (978794 3522291 0)
```

It has no secret in it, so anyone can compute it. And anyone who chooses ids
can choose ids that all land on the same number. A table full of such ids
degrades from "find in an instant" to "walk a long list", and a server can be
slowed to a crawl that way. This is called flooding.

So use `uuid-hash` for ids you made yourself, or otherwise trust.

## A keyed hash for ids a client sends

If a client sends ids and your server puts them in a table, use
`make-uuid-hash`. It takes a secret key of 8 bytes and answers a hash
procedure. Without the key, nobody can tell which ids will collide. The hashes
are 32-bit numbers (HalfSipHash-2-4).

```scheme
(define key (u8-list->bytevector '(0 1 2 3 4 5 6 7)))
(define hash (make-uuid-hash key))

(hash id)
;; => 3416166685

(define table (make-hashtable hash uuid=?))
(hashtable-set! table id 'x)
(hashtable-ref table id #f)
;; => x
```

The key is read when you call `make-uuid-hash`, so changing the bytevector
afterwards changes nothing. Two procedures made from equal keys answer alike. A
key of any length but 8 raises.

A fixed key like this one is only for tests. For a real key, use random bytes.

## A random key

`make-system-uuid-hash` makes the key for you, from `/dev/urandom`. Each call
makes a new hash with a new key.

```scheme
(define hash (make-system-uuid-hash))

(hash id)
;; => e.g. 2508975842
```

Run it again and you get another number. Within one hash, the same id always
gets the same number.

```scheme
(= (hash id) (hash id))
;; => #t
```

Because the key is new every time, never store these hashes, send them, or
compare them across processes. Store the ids, and hash again after you load.

## Which one

- Ids you made, or can trust: `uuid-hash`. It is the fastest.
- Ids a client sends: `make-system-uuid-hash`, once, and keep the procedure.
- A hash you must be able to repeat, as in a test: `make-uuid-hash` with a key
  you pick.

## More

Making a hash with `make-system-uuid-hash` reads `/dev/urandom` once, so make
it once and keep it. What each hash costs is under Costs on
[The system library](system.md). A hash given anything but an id raises an
assertion violation whose who is `make-uuid-hash`; see [Errors](errors.md). The
procedures are in the API reference: [`(unique-id)`](reference.md#unique-id)
and [`(unique-id system)`](reference.md#unique-id-system).
