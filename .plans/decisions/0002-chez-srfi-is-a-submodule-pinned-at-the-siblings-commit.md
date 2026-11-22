# ADR-0002: chez-srfi is a submodule pinned at the siblings' commit

- **Status:** Accepted
- **Date:** 2026-11-22
- **Scope:** the suites' SRFI-64 and `(unique-id system)`'s SRFI-19, on Chez
- **Related:** threading ADR-0002, which this follows; chez-http-server and circuit,
  which pin chez-srfi at the same commit

## Context

The suites need SRFI-64, and the sibling repositories' testing rules are written around
it. `(unique-id system)` needs SRFI-19 for the clock. chez-srfi
(https://github.com/arcfide/chez-srfi) carries both as R6RS, with a compatibility file
per implementation for SRFI-19. It tags no releases. Its files use Akku's
percent-encoded names (`%3a64.sls`), which Chez does not decode. Guile 3 has both SRFIs
built in, under the same R6RS names.

## Decision

1. **chez-srfi is a submodule at `vendor/chez-srfi`, pinned at
   `7879b527f267f067416552fb989135ad1b4ea436`** (`SRFI_PIN` in the Makefile), the commit
   threading, chez-http-server and circuit pin.
2. **`make submodules` clones it, where the network is. `make deps` links every entry
   into `build/scheme-libs/srfi` under its own name and its decoded one, and never
   fetches.** The submodule's tree is left alone.
3. **`make check-pins` holds the gitlink and the checkout at `SRFI_PIN`**, and refuses a
   checkout with local edits. Move the gitlink and `SRFI_PIN` on one commit.
4. **On Guile, both SRFIs are Guile's own.** Nothing puts chez-srfi on Guile's path.
5. **SRFI-19 is the library's one dependency, and `(unique-id system)` its one user**
   (ADR-0001). The Akku package will name chez-srfi when `(unique-id system)` lands.

## Consequences

- **A fresh clone needs `make submodules` once** before `make test`; `make deps` says so
  when the submodule is empty.
- **Chez and Guile run different SRFI-19s.** `(unique-id system)` uses only
  `current-time`, `time-utc`, `time-second` and `time-nanosecond`, which both have.
