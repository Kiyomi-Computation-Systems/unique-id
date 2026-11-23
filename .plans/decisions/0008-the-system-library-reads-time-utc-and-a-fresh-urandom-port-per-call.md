# ADR-0008: The system library reads `time-utc`, and opens `/dev/urandom` afresh at every call

- **Status:** Accepted. Chosen with the slice, and accepted by the owner on 2026-11-23.
- **Date:** 2026-11-22
- **Scope:** `(unique-id system)`, `make check-tests`, the fork suite under `tools/`, the
  Makefile's lanes, and `Akku.manifest`
- **Related:** ADR-0001, whose rule 4 this amends; ADR-0002, which names the SRFI-19
  names the library uses; ADR-0006, whose generator this feeds; ADR-0007, whose keyed
  hash this keys; `.plans/slice-3.md`, the contract

## Context

`(rnrs)` has no clock and no entropy. The brief asks for a default generator that reads
the time through SRFI-19 and bytes from `/dev/urandom`, with no FFI.

Measured on the host, Chez 10.4.0 with chez-srfi at the pin, and Guile 3.0.11, before
this record:

- SRFI-19's `time-monotonic` and `time-tai` run 37 s ahead of `time-utc` on both. The
  generator's clock is the Unix time, leap seconds excluded (RFC 9562 §5.7).
- **A buffered port repeats itself across a fork.** A buffered `/dev/urandom` port, read
  once, then read by a parent and its forked child, gave both the same 16 bytes, on
  Guile through `primitive-fork` and on Chez through `(foreign-procedure "fork" () int)`.
  A port opened unbuffered at each read gave different bytes. RFC 9562 §6.9 asks that
  a CSPRNG be "properly reseeded upon state changes, such as process forks".
- `(buffer-mode none)` is honoured on both: each `get-bytevector-n` is one `read` of the
  bytes asked. A buffered port reads 8192 bytes on Chez and 4096 on Guile at its first
  read.
- Opening an unbuffered port, reading 16 bytes and closing it costs 1.6 µs on Chez and
  6.0 µs on uncompiled Guile; a buffered port, 17.7 µs and 15.2 µs; one shared
  unbuffered port, 0.33 µs and 0.49 µs.
- A port that is never closed fails 5000 calls on Chez under a descriptor limit of
  1024, but on both Guiles only under 64: Guile closes the ports its collector finds.
  The host allows 1048576, under which all three pass.

ADR-0001 kept `(srfi :19)` out of `tests/`, so a suite had no second clock to check
`system-clock` against, and kept the library out of `tools/`, whose suites run on Chez
and may fork.

## Decision

1. **`system-clock` answers `time-utc` in milliseconds**: its second times 1000, plus
   its nanosecond div 1000000. Never `time-monotonic` or `time-tai`.
2. **`system-entropy` opens `/dev/urandom` unbuffered at every call**, reads the bytes
   asked with one `get-bytevector-n`, and closes the port whether the read returns or
   raises. No port outlives a call, so a forked child never reads its parent's bytes,
   and no two threads share a port. A count of 0 answers an empty bytevector without
   opening the file, which saves an open and a close. A short read raises with
   `error`.
3. **The library makes generators and hashes, and holds none.**
   `make-system-uuid-generator` and `make-system-uuid-hash` answer a new one at each
   call. A generator belongs to its caller, so a shared one would break that.
4. **A file under `tests/` may import `(srfi :19)`**, amending ADR-0001's rule 4, as it
   may `(srfi :64)`: both lanes have it. `(unique-id system)` stays the one library
   under `src/` that imports it.
5. **A fork suite under `tools/`, on Chez alone**, amending ADR-0001's rule 5. It runs
   `tools/fork-probe.sps` as a child program with `src/` on the child's path, which
   forks through Chez's foreign-procedure interface and asserts that parent and child
   draw different entropy and ids. The tools lane's own path still leaves `src/` out.
6. **Every lane runs each suite under `ulimit -n 64`**, so a port left open fails on
   every Scheme, not on Chez alone.
7. **`Akku.manifest` names chez-srfi** as a dependency, from the version whose commit is
   the submodule's pin, `0.0.0-akku.181.7879b52`, up. Akku 1.1.0 locks the range today
   at `0.0.0-akku.291.5219353`.

## Consequences

- **Entropy costs an open, a read and a close per id** on Chez, about 1.3 µs, and more
  calls on Guile, which also asks the file's status and position: more than the
  generator's own work, and safe across forks and threads.
- **A fork copies a generator's state.** When both processes' next v7 ids fall in its
  last millisecond, or the clock is behind it, they share their millisecond and
  counter, and differ in their 62 random bits. At a new tick each draws its own seed.
- **A consumer of the Akku package may run a newer chez-srfi** than the suites ran
  against: the range's floor is the pin.
- **The fork suite holds the per-call port on Chez alone**, and on Linux. It refuses a
  buffered port kept open, but not an unbuffered one kept open, nor a buffered one
  opened per call: both are fork-safe, and no test sees either.
- **A suite may hold at most 64 descriptors open at once**, its own and its Scheme's.
