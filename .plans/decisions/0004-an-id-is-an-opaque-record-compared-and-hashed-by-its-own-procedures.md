# ADR-0004: An id is an opaque record, compared and hashed by its own procedures

- **Status:** Accepted
- **Date:** 2026-11-22
- **Scope:** `(unique-id)`'s representation and its comparison API
- **Related:** the brief, `.plans/uuid.md`, whose open questions this answers in part

## Context

The brief left open whether an id is a record or a bare 16-byte bytevector. A bytevector
binds straight to a SQLite blob, and `equal?` and `equal-hash` see into it. A record
cannot be confused with any other bytevector, and its 16 bytes are checked once, when it
is made.

`equal?` on records is not portable: measured on the host, two records holding the same
bytes are `equal?` on Guile 3.0.11 and 3.0.9 and not on Chez 10.4.0. So an `equal?`
hashtable of ids finds an id by an equal one on Guile, and not on Chez: code that works
on one Scheme breaks on the other.

The owner chose a record, and an exported hash.

## Decision

1. **An id is an opaque, sealed R6RS record holding 16 bytes.** `bytevector->uuid` makes
   one from a 16-byte bytevector and raises an assertion violation for any other;
   `uuid->bytevector` answers a fresh copy, so no caller can change an id.
2. **`uuid=?` and `uuid<?` compare ids by their bytes**, and **`uuid-hash` answers an
   exact nonnegative integer from the bytes**, so `(make-hashtable uuid-hash uuid=?)`
   keys a table by id. `uuid-hash` answers a fixnum on any R6RS Scheme: below 2^23, since
   R6RS promises a fixnum width of 24 bits, sign included.
3. **`equal?` on ids is no part of the contract**: README.org says to use `uuid=?`.
4. **The package and its libraries are named `unique-id`**: the Akku name `uuid` is
   taken, and `uuid7` would mislead, since v4 is included.

**Amended 2026-11-22**, measured on Guile 3.0.9 and 3.0.11: "no caller can change an id"
holds within R6RS. A Guile program that imports `(guile)` reaches the record's field with
`struct-ref`, and can change an id's octets or put a bytevector of another length there.
Chez's `record-rtd` and `inspect/object` refuse an opaque record. Only code in the same
process can do this, never data a client sends.

## Consequences

- **A SQLite binding costs one call**: `uuid->bytevector` to store, `bytevector->uuid` to
  read.
- **Tests never compare ids with `equal?` or `test-equal`**: they compare
  `uuid->string`, or use `uuid=?`. AGENTS.md says so.
