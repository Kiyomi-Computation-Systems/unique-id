# API reference

Everything the three libraries export, one entry each.

This page is generated from the signature comments in `src/` by `make reference`, so edit those, not this page.

```scheme
(import (rnrs) (unique-id) (unique-id generator) (unique-id system))
```

## How to read an entry

Each entry shows the call shape, then the signature, then what the procedure answers. A value has a signature alone.

Names in capitals in the text are the call's arguments, as TEXT is `text`, or the values the text names, as CLOCK is a generator's clock.

| Type | Means |
|:--|:--|
| `Uuid` | an id |
| `Generator` | what `make-uuid-generator` answers |
| `Nat` | an exact nonnegative integer |
| `Boolean` | `#t` or `#f` |
| `String` | a string |
| `Symbol` | a symbol |
| `Bytevector` | a bytevector |
| `Any` | any value |
| `#f` | the value `#f` |
| `(U A B)` | either an `A` or a `B` |
| `(A B -> C)` | a procedure of an `A` and a `B` that answers a `C` |
| `(-> A)` | a procedure of no arguments that answers an `A` |

A signature that starts with `->`, as `system-clock : -> Nat`, is a procedure of no arguments too.

## Errors

An argument outside its domain raises an assertion violation whose who is the procedure's name and whose one irritant is that argument. See [Errors](errors.md).

## (unique-id)

UUIDs, versions 4 and 7, as RFC 9562 defines them.

An id is an opaque, sealed record of 16 octets. The library reads no clock and no entropy: every bit it does not fix is an argument. Octets are numbered 0 to 15 and bits 0 to 127, most significant first. Plain R6RS, importing (rnrs) alone.

### `uuid?`

```text
(uuid? x)
uuid? : Any -> Boolean
```

#t for an id, #f for anything else, a 16-byte bytevector included.

### `bytevector->uuid`

```text
(bytevector->uuid bytes)
bytevector->uuid : Bytevector -> Uuid
```

The id whose octets are BYTES, 16 bytes. The id keeps its own copy: changing BYTES later does not change it. Else an assertion violation.

### `uuid->bytevector`

```text
(uuid->bytevector id)
uuid->bytevector : Uuid -> Bytevector
```

The id's 16 octets, octet 0 first, in a fresh bytevector. Else an assertion violation.

### `string->uuid`

```text
(string->uuid text)
string->uuid : String -> (U Uuid #f)
```

The id TEXT spells in the canonical 36-character form, in either case, or #f when TEXT is any other string. An assertion violation when TEXT is not a string.

### `uuid->string`

```text
(uuid->string id)
uuid->string : Uuid -> String
```

The canonical form in lower case, in a fresh string. Else an assertion violation.

### `uuid-version`

```text
(uuid-version id)
uuid-version : Uuid -> (U Nat #f)
```

For an id of variant `rfc9562`, bits 48-51, the high 4 bits of octet 6: 0 to 15. #f for an id of any other variant, the nil and max ids among them: RFC 9562 defines versions for its own variant alone. Else an assertion violation.

### `uuid-variant`

```text
(uuid-variant id)
uuid-variant : Uuid -> Symbol
```

From octet 8's high bits: `ncs` for 0xxx, `rfc9562` for 10xx, `microsoft` for 110x, `future` for 111x. Else an assertion violation.

### `uuid-v7-timestamp`

```text
(uuid-v7-timestamp id)
uuid-v7-timestamp : Uuid -> (U Nat #f)
```

For an id of version 7 and variant `rfc9562`, octets 0-5 as a big-endian unsigned integer: milliseconds since 1970-01-01 UTC. #f for any other id. Else an assertion violation.

### `uuid=?`

```text
(uuid=? a b)
uuid=? : Uuid Uuid -> Boolean
```

#t when A and B have the same 16 octets. Else an assertion violation.

### `uuid<?`

```text
(uuid<? a b)
uuid<? : Uuid Uuid -> Boolean
```

#t when A's octets come before B's, compared as unsigned bytes from octet 0. This is the ids' order as 128-bit unsigned integers, and their lower-case text's order under string<?. Else an assertion violation.

### `uuid-hash`

```text
(uuid-hash id)
uuid-hash : Uuid -> Nat
```

A nonnegative fixnum below 2^23, from the octets alone, for (make-hashtable uuid-hash uuid=?). Ids that differ in one octet hash apart. Else an assertion violation.

### `make-uuid-hash`

```text
(make-uuid-hash key)
make-uuid-hash : Bytevector -> (Uuid -> Nat)
```

A procedure HASH such that (HASH ID) is HalfSipHash-2-4 of ID's 16 octets under KEY, 8 bytes: a number from 0 to 2^32 - 1. KEY is read at this call, so changing it later changes no hash, and procedures made from equal keys answer alike. Use it where an attacker may choose the ids, with a secret KEY. HASH, given anything but an id, raises an assertion violation whose who is make-uuid-hash. Else an assertion violation for a KEY that is not 8 bytes.

### `nil-uuid`

```text
nil-uuid : Uuid
```

The id whose 128 bits are all 0.

### `max-uuid`

```text
max-uuid : Uuid
```

The id whose 128 bits are all 1.

### `make-uuid-v4`

```text
(make-uuid-v4 bytes)
make-uuid-v4 : Bytevector -> Uuid
```

BYTES, 16 bytes, with the high 4 bits of octet 6 set to 0100 and the high 2 bits of octet 8 set to 10. The other 122 bits are BYTES' own. BYTES is not changed. Else an assertion violation.

### `make-uuid-v7`

```text
(make-uuid-v7 ms counter bytes)
make-uuid-v7 : Nat Nat Bytevector -> Uuid
```

MS (below 2^48) big-endian in octets 0-5. Then 0111 in the high 4 bits of octet 6, and COUNTER (below 2^12) in the 12 bits after it, octet 6's low 4 bits and octet 7. Then BYTES, 8 bytes, in octets 8-15, with octet 8's high 2 bits set to 10. BYTES is not changed. Else an assertion violation, the first argument that fails being the one raised.

## (unique-id generator)

Version 4 and version 7 ids from a clock and an entropy source, whose version 7 ids increase while the clock stays within 10 seconds of the last one.

A generator keeps the last v7 id's millisecond and its 12-bit counter, and belongs to its caller: it is not safe to share between threads. Its order holds among one generator's ids, not across generators or restarts, and breaks at each fall of the clock more than 10 seconds behind the last id: the generator then starts over from the clock. Plain R6RS, importing (rnrs) and (unique-id).

### `make-uuid-generator`

```text
(make-uuid-generator clock entropy)
make-uuid-generator : (-> Nat) (Nat -> Bytevector) -> Generator
```

A fresh generator over CLOCK and ENTROPY; it calls neither. CLOCK answers the Unix time in milliseconds, leap seconds excluded. ENTROPY, given N, answers N random bytes. An assertion violation unless both are procedures, naming the first that is not.

### `uuid-generator?`

```text
(uuid-generator? x)
uuid-generator? : Any -> Boolean
```

#t for a generator, #f for anything else.

### `generate-v4`

```text
(generate-v4 g)
generate-v4 : Generator -> Uuid
```

The v4 id of the 16 bytes that (ENTROPY 16) answers, through make-uuid-v4. It never calls CLOCK and leaves the v7 state alone. An assertion violation when G is not a generator, or when ENTROPY does not answer 16 bytes.

### `generate-v7`

```text
(generate-v7 g)
generate-v7 : Generator -> Uuid
```

A v7 id greater, under uuid<?, than the last v7 id G answered, unless CLOCK has fallen more than 10 seconds behind that id's millisecond; then the id takes CLOCK's answer, and is less. When CLOCK's answer is past the last millisecond, or that far behind it, the id takes it, with the 12-bit counter seeded from the first two of (ENTROPY 10)'s bytes, top bit cleared. Else it keeps the last millisecond, with the counter one more and (ENTROPY 8); and when that counter is full, it takes the last millisecond plus 1, reseeded from (ENTROPY 10). The id's last 8 bytes are ENTROPY's. An assertion violation when G is not a generator, when CLOCK does not answer an exact integer from 0 to below 2^48, or when ENTROPY does not answer the bytes asked. An `error` when the counter is full at millisecond 2^48 - 1. A call that raises leaves G as it was. CLOCK and ENTROPY must not call G: G's state is read before ENTROPY is called, so an id ENTROPY made through G has its millisecond and counter repeated by the id G then answers, which may sort below it.

## (unique-id system)

The system's clock and entropy, and what is made of them.

Each call of system-entropy that reads opens its own /dev/urandom port and closes it before it returns, so no port outlives a call: a forked child never rereads bytes its parent's port had buffered, and no two threads share a port. The port is unbuffered, because a buffered one reads thousands of bytes to answer 16. The clock reads SRFI-19's time-utc, which is the Unix time: time-monotonic and time-tai run 37 seconds ahead of it. Needs /dev/urandom: Linux and macOS. Plain R6RS, importing (rnrs), SRFI-19 and the two libraries of this package.

### `system-clock`

```text
(system-clock)
system-clock : -> Nat
```

The Unix time in milliseconds: the second of SRFI-19's time-utc times 1000, plus its nanosecond div 1000000.

### `system-entropy`

```text
(system-entropy n)
system-entropy : Nat -> Bytevector
```

A fresh bytevector of N random bytes from /dev/urandom, which no one else holds. N not an exact nonnegative integer is an assertion violation. When the read answers anything but N bytes, an error whose irritant is that answer.

### `make-system-uuid-generator`

```text
(make-system-uuid-generator)
make-system-uuid-generator : -> Generator
```

A new generator over system-clock and system-entropy.

### `make-system-uuid-hash`

```text
(make-system-uuid-hash)
make-system-uuid-hash : -> (Uuid -> Nat)
```

make-uuid-hash under a new 8-byte key from system-entropy. Its procedure raises as make-uuid-hash's does, with who make-uuid-hash.
