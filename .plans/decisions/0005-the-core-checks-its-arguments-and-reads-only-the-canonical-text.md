# ADR-0005: The core checks its own arguments and reads only the canonical text

- **Status:** Accepted. On 2026-11-22 the owner approved decisions 2 and 3, and kept
  decision 5's unkeyed hash, with a keyed one to come in slice 3. Decisions 1 and 4 were
  chosen with the slice, not asked of the owner
- **Date:** 2026-11-22
- **Scope:** `(unique-id)`'s errors, text, field readers and hash
- **Related:** ADR-0004, which made an id a record; the brief's design, whose signatures
  this keeps but `uuid-version`'s; `.plans/slice-1.md`, the contract the slice was built
  to

## Context

The brief gives the core's signatures, not what each does at its edges: a bad argument,
an id of another variant, text that is nearly canonical.

Measured on the host, Chez 10.4.0 and Guile 3.0.11 and 3.0.9, before this record:

- A record accessor given something else raises an assertion violation. Chez names the
  accessor as its who; Guile 3.0.9 and 3.0.11 attach no who at all. A check that relies
  on the record's own checks names no procedure the caller knows.
- `string->number` with radix 16 takes a sign and a `#x` prefix, and `char-numeric?`
  takes digits outside ASCII. Either would let a group that is not hex pass as hex.
- RFC 9562 defines versions for its own variant alone (§4.2's last paragraph, and Table
  2's title). The nil id is of the NCS variant and the max id of the future one (§5.9,
  §5.10).

The server checks every id a client sends, so text that is not canonical must be refused
with `#f`, never read leniently.

## Decision

1. **Every exported procedure checks its own arguments.** An argument outside its domain
   raises an assertion violation whose who is the procedure's own name and whose
   irritants are a one-element list holding that argument. Arguments are checked first
   to last.
2. **`string->uuid` reads the canonical form alone**: 36 characters, hyphens at 8, 13,
   18 and 23, and ASCII hex digits, in either case, everywhere else. Any other string
   gives `#f`; a non-string raises.
3. **`uuid-version` answers the 4 version bits of an id of variant `rfc9562`, and `#f`
   for any other**, the nil and max ids among them. The brief gave it `Uuid -> Nat`; it
   is `Uuid -> (U Nat #f)`, so that `(eqv? (uuid-version id) 7)` holds of v7 ids alone.
   **`uuid-v7-timestamp` answers for exactly those ids**, and `#f` for any other.
4. **A variant is a symbol**: `ncs`, `rfc9562`, `microsoft` or `future`, the four rows
   of RFC 9562's Table 1.
5. **`uuid-hash` rotates and xors the 16 octets within 23 bits**, using `fx` operations
   alone, so every intermediate value is a fixnum on any R6RS Scheme. The suites hold
   the hash's properties, not its values: equal ids hash alike, a change to one octet
   changes the hash, and 1000 random ids get at least 990 hashes.

## Consequences

- **Every suite asserts a raise's who and irritant**, so a check left to the record
  fails on both lanes.
- **The hash may change in any release** without breaking a suite. A table must not
  store hashes.
- **The hash is unkeyed and linear under xor**: the hash of `a xor b` is the xor of
  theirs. Anyone can make many valid ids that share one hash, so a hashtable keyed by
  ids an adversary chooses, such as ids a client sends, can be flooded. A keyed hash,
  its key from the system's entropy, comes with `(unique-id system)`; `uuid-hash` stays,
  the fast hash for ids the program made itself.
- **A caller that may hold a non-string checks `string?` first**: `string->uuid`
  raises for one, as every procedure does outside its domain.
- **An id of another variant is still an id**: it parses, prints and compares. Only
  `uuid-version` and `uuid-v7-timestamp` ask about its variant.
