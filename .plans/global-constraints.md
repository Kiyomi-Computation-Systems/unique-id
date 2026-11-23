# Global constraints

These rules bind every task brief. Each one cites the decision record in
[decisions/](decisions/) it comes from. If a rule here and its record disagree, the record
wins and this file gets fixed. Rules from a record that is still Proposed are marked
provisional. They bind until that record is accepted or amended.

## Platforms

- **The library runs wherever an R6RS Scheme does**; `(unique-id system)` also needs
  `/dev/urandom`: Linux and macOS. The build and the tests need a POSIX shell and GNU
  make. CI runs on Linux alone (AGENTS.md), on amd64 and arm64 (ADR-0003).

## The library

- **Every file under `src/` is a plain R6RS library**: `STEM.sls` with no other dot, at
  the path its name gives; first line exactly `#!r6rs`, no `#!` after it; one
  `(library NAME (export ...) (import ...) ...)` form with no version on its name;
  importing, through any wrapper, only `(rnrs ...)` but `(rnrs eval)`, and `(unique-id
  ...)` libraries that are themselves under `src/`; **and `(srfi :19)` in `(unique-id
  system)` alone**. Nothing else lives under `src/` but an OS's or an editor's litter.
  `make check-imports` holds it, and `make test` runs it once `src/` exists (ADR-0001).
- **Three libraries**: `(unique-id)`, the pure core, with no clock and no entropy;
  `(unique-id generator)`, which takes both as arguments; `(unique-id system)`, the
  system's clock and `/dev/urandom` (ADR-0001).
- **An id is an opaque, sealed record of 16 bytes.** `uuid=?`, `uuid<?`, `uuid-hash`
  and `make-uuid-hash`'s procedures compare and hash it; `equal?` on ids is no part of the contract (ADR-0004).
- **Every exported procedure checks its own arguments**: one outside its domain raises an
  assertion violation whose who is the procedure's name and whose one irritant is that
  argument. `string->uuid` reads the canonical 36-character form alone, ASCII hex in
  either case, and answers `#f` for any other string (ADR-0005).
- **One generator's v7 ids increase**, but at a reset: RFC 9562 §6.2's Method 1;
  a clock within 10 seconds of the last id's time held to that time, and one further behind followed, a reset; a rollover moving the timestamp on one millisecond past the last.
  A bad clock or entropy answer raises an assertion violation naming the `generate-`
  procedure; running out of timestamp raises with `error`; a call that raises leaves the
  generator as it was (ADR-0006).
- **SRFI-19 is the library's one dependency**: chez-srfi's on Chez, Guile's own on Guile
  (ADR-0002).
- **`make-uuid-hash` answers HalfSipHash-2-4 of an id's 16 octets** under an 8-byte key,
  the reference's 32-bit output read little-endian. Its arithmetic is generic and stays
  below 2^33; `uuid-hash`'s stays below 2^23 in `fx` operations. Its procedure raises
  under its maker's name (ADR-0007).
- **`(unique-id system)` reads `time-utc`, never `time-monotonic` or `time-tai`, and
  opens `/dev/urandom` unbuffered at every call that reads**, closing it whether the read returns or
  raises, so no port outlives a call. It holds no generator or hash of its own
  (ADR-0008).

## Tests and tooling

- **The library suites, `tests/test-*.sps`, run on Chez and on Guile 3.** `tests/` is
  plain R6RS: `STEM.sls` and `STEM.sps` files alone, no `(unique-id ...)` library,
  importing only `(rnrs ...)` but `(rnrs eval)`, `(srfi :64)`, `(srfi :19)`, the library
  and `tests/`' own libraries. `make check-tests` holds it, and `make test` runs it
  (ADR-0001, and ADR-0008 for `(srfi :19)`).
- **Every lane runs each suite under `ulimit -n 64`**, so a leaked port fails on every
  Scheme (ADR-0008).
- **The Guile lane runs with `GUILE_LOAD_PATH` and `GUILE_LOAD_COMPILED_PATH` unset,
  `XDG_CACHE_HOME` under `build/`, from `build/guile`** (ADR-0003).
- **The audits under `tools/` run on Chez alone** and may use `(chezscheme)` (ADR-0001).
  So does the fork suite, which runs `(unique-id system)` in a child program with `src/`
  on the child's path alone; the tools lane's own path leaves `src/` out (ADR-0008).
- **chez-srfi is at `vendor/chez-srfi`, pinned at `SRFI_PIN`,
  `7879b527f267f067416552fb989135ad1b4ea436`.** Move the gitlink and `SRFI_PIN` on one
  commit; `make check-pins` holds them. `make deps` never fetches (ADR-0002).
- **`make` runs the host's Chez and Guile**, `CHEZ` and `GUILE` or the first on `PATH`
  that answers as each, and `make check-chez` and `make check-guile` refuse any other. No
  development container (ADR-0003).
- **CI builds Chez 10.4.1 from its sha256-pinned tarball** (`scripts/ci/build-chez.sh`)
  and installs Ubuntu's `guile-3.0`, and asserts the versions and machine type it ends up
  with (ADR-0003).
