# ADR-0007: The keyed hash is HalfSipHash-2-4 of an id's octets

- **Status:** Accepted. The owner asked for a keyed hash in slice 3 on 2026-11-22, and
  kept `uuid-hash`. The algorithm and its interface were chosen with the slice, and the
  owner accepted them on 2026-11-23.
- **Date:** 2026-11-22
- **Scope:** `(unique-id)`'s `make-uuid-hash`, and `(unique-id system)`'s
  `make-system-uuid-hash`
- **Related:** ADR-0005, whose decision 5 left `uuid-hash` unkeyed and linear;
  `.plans/slice-3.md`, the contract

## Context

Techo's server keys tables by ids its clients send. `uuid-hash` is unkeyed and linear
under xor, so anyone can make many valid ids that share one hash, and fill one bucket of
such a table (ADR-0005). A hash whose key the client does not know closes that.

The candidates:

- **SipHash-2-4**, the usual keyed hash for tables. It works in 64-bit words, which pass
  the fixnum range of a 64-bit Scheme, 61 bits on Chez and 62 on Guile: most of its
  sums and shifts would make bignums.
- **HalfSipHash-2-4**, the same design in 32-bit words, with a 64-bit key and a 32-bit
  or 64-bit output. Its reference says that with c ≥ 2 and d ≥ 4 it "is expected to
  provide the maximum PRF security for any function with the same key and output size".
- **`uuid-hash` with a key xor'd in.** Still linear: ids that share a hash still share
  it.

A prototype of HalfSipHash-2-4 over an id's 16 octets cost about 7 times `uuid-hash` on
Chez, 0.47 µs a hash, and 2 times on compiled Guile. The hash as built costs 0.43 µs on
Chez 10.4.0, against `uuid-hash`'s 0.063 µs.

## Decision

1. **`make-uuid-hash : Bytevector -> (Uuid -> Nat)`**, in the core, takes an 8-byte KEY
   and answers a procedure, HASH, that answers HalfSipHash-2-4's 32-bit output for an
   id's 16 octets under KEY: an exact integer from 0 to 2^32 − 1. The core stays pure:
   the key is an argument.
2. **The reference is the authority.** HASH answers what the reference's
   `halfsiphash.c` answers for the same 16 bytes and key, its 4 output bytes read
   little-endian. The suites check the reference's own vector for a 16-byte input, and
   more computed by its own code.
3. **Errors follow ADR-0005.** KEY is checked when `make-uuid-hash` is called. HASH
   checks its argument is an id, and raises under its maker's name, `make-uuid-hash`:
   it has none of its own.
4. **KEY is read at the call**, into two 32-bit words, so changing KEY later changes no
   hash.
5. **The arithmetic is generic, and stays below 2^33.** A 32-bit word passes the 24-bit
   fixnum width R6RS promises, so `fx` operations would not be portable. Masking each
   sum, and rotating the low bits up rather than shifting all of them, keeps every value
   a fixnum on 64-bit Chez and Guile. This amends AGENTS.md's rule that hashing stays below
   2^23, which still holds for `uuid-hash`.
6. **`uuid-hash` stays**, the fast hash for ids the program made itself.

## Consequences

- **A table keyed by client ids uses `(make-system-uuid-hash)`**, whose key comes from
  `/dev/urandom` (ADR-0008), or `make-uuid-hash` with a key of the caller's.
- **The output is 32 bits.** Among n ids, about n²/2^33 pairs share a hash by chance:
  one pair among 92,000 ids. That costs a table a little, never correctness.
- **The key is 64 bits.** HalfSipHash's security is that of its key and output size,
  less than SipHash's 128-bit key. It is meant to keep a table's buckets even, not to
  authenticate.
- **On a 32-bit Scheme the words are bignums**, and HASH is slower, but still right.
- **The keyed-hash suite's flooding test leans on `uuid-hash` being linear.** It builds
  1024 ids that share a `uuid-hash` from that linearity, at run time, and asserts that
  HASH spreads them. If `uuid-hash` changes, that one test changes with it: the one
  exception to ADR-0005's "the hash may change in any release without breaking a
  suite".
