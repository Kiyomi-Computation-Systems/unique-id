# ADR-0001: The library is plain R6RS, and its suites run on Chez and Guile

- **Status:** Accepted
- **Date:** 2026-11-22
- **Scope:** `src/`, `tests/`, `tools/` and the test lanes
- **Related:** threading ADR-0001, whose import audit this one's is copied from, and
  which runs its suites on Chez alone

## Context

The library makes and reads UUIDs for Techo, on Chez, and should serve any R6RS Scheme.
Chez is the development Scheme. Guile 3 is on the development host too. threading chose
Chez alone for its suites, because each implementation brings its own SRFI-64, its own
library path rules and its own reading of the edges R6RS leaves open. Here the owner
chose both, to catch those edges rather than avoid them.

Measured on the host, Chez 10.4.0 and Guile 3.0.11, before this record:

- Guile's `--r6rs` loads `STEM.guile.sls` before `STEM.sls`, as Chez loads
  `STEM.chezscheme.sls` and `STEM.ss` before it.
- The SRFI-64s part on raises. chez-srfi's turns a raise in the actual expression into
  `#f`, and lets a raise in the expected expression escape; Guile 3.0.11's records both
  as failures. Guile 3.0.9's, measured from a copy in the host's Guix store, behaves like
  chez-srfi's, and writes a log file to the directory it runs in.
- `equal?` on two records holding the same bytes answers `#f` on Chez and `#t` on Guile.
- A suite's `(import (rnrs))` makes Guile warn of each core binding it replaces, and a
  suite's top level on Guile still sees Guile's other core bindings, such as
  `string-map`, which is not R6RS.

`(rnrs)` has no clock, so the default generator needs one from outside: SRFI-19, which
chez-srfi carries for Chez and Guile carries itself.

## Decision

1. **Every file under `src/` is a plain R6RS library**: named `STEM.sls` with no other
   dot, at the path its library name gives; first line exactly `#!r6rs`, and no `#!`
   after it; one `(library NAME (export ...) (import ...) ...)` form, its name carrying
   no version; importing, through any wrapper, only `(rnrs ...)` but `(rnrs eval)`, and
   `(unique-id ...)` libraries that are themselves under `src/`. **One exception:
   `(unique-id system)` may also import `(srfi :19)`**, for the clock. Nothing else lives
   under `src/` but an OS's or an editor's litter.
2. **The library is three libraries**: `(unique-id)`, the pure core; `(unique-id
   generator)`, which takes its clock and entropy as arguments; `(unique-id system)`, the
   system clock and `/dev/urandom`. A caller who brings a clock needs no SRFI.
3. **`make check-imports` holds rules 1 and 2's imports** (`tools/check-imports.sps`,
   through `(unique-id-checks)`), and **`make test` runs it once `src/` exists**.
   **`make check-tests` holds rule 4's** (`tools/check-tests.sps`), and `make test`
   always runs it.
4. **The library suites, `tests/test-*.sps`, run on Chez and on Guile 3**, each lane with
   its own SRFI-64. `tests/` is plain R6RS too: it holds only `STEM.sls` and `STEM.sps`
   files, no `(unique-id ...)` library, and they import `(rnrs ...)` but `(rnrs eval)`,
   `(srfi :64)`, the library and `tests/`' own libraries alone. Each lane checks the other:
   a suite that imports anything Chez-only fails on Guile, and one that uses a name
   Guile's top level leaks fails on Chez.
5. **The audits, `tools/`, run on Chez alone**, and may use Chez's own procedures. They
   read files and run child processes, which R6RS cannot do portably, and they test
   tooling, not the library.

**Amended 2026-11-22, by ADR-0008:** rule 4 lets a file under `tests/` import `(srfi
:19)` too, which both lanes have, so the system suite can read `time-utc` beside
`system-clock`. Rule 5's `tools/` also holds the fork suite, on Chez alone, which runs
`(unique-id system)` in a child program with `src/` on the child's path: no plain R6RS
suite can fork.

## Consequences

- **A suite must hold on both SRFI-64s.** AGENTS.md's testing rules are written so they
  do: never expect `#f` from something that can raise, compute anything that can raise
  under a `guard`, and never compare ids with `equal?`.
- **What a suite writes to a port is tested on Chez alone**, in `tools/`: R6RS gives no
  way to rebind the error port.
- **A behaviour neither Scheme shows can still reach `src/`**, through what R6RS leaves
  open, such as the order a call's arguments are evaluated in. Two lanes see more of it
  than one, not all of it.
