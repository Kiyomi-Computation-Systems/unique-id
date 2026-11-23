# Progress ledger

Where unique-id stands. Read it with [global-constraints.md](global-constraints.md)
before starting slice work. When a slice merges, update **Now** and add a close-out under
**Close-outs**, newest first.

## Now

- **The scaffold is merged**, squashed from
  [PR #1](https://github.com/Kiyomi-Computation-Systems/unique-id/pull/1) on 2026-11-22;
  its close-out is below.
- **The design** is the brief, [uuid.md](uuid.md). The owner answered its open questions
  on 2026-11-22; its **Answers** section records them, and ADR-0001 to ADR-0004 the
  decisions they led to.
- **Slice 1, the core, `(unique-id)`, is built on branch `core`**, to the contract in
  [slice-1.md](slice-1.md), and reviewed; not yet merged. ADR-0005 records its edge
  decisions, which the owner accepted. `make test` passes on Chez 10.4.0, Guile 3.0.11 and
  Guile 3.0.9, and all 76 mutants of the library are killed on each.

## Slices

1. **The core, `(unique-id)`**: the record; text in and out; bytes in and out; version,
   variant and v7 timestamp; `uuid=?`, `uuid<?` and `uuid-hash`; the nil and max ids;
   `make-uuid-v4` and `make-uuid-v7`. RFC 9562's Appendix A vectors, copied from the
   RFC's text; round trips; every malformed text refused; a property test of the version
   and variant bits.
2. **The generator, `(unique-id generator)`**: `make-uuid-generator`, `generate-v4`,
   `generate-v7`, with RFC 9562 §6.2 Method 1's counter. A scripted clock that repeats,
   steps back and overflows the counter gives strictly increasing ids.
3. **The system, `(unique-id system)`**: the clock through SRFI-19, bytes from
   `/dev/urandom`, and a generator made of them, whose ids parse back and differ.
   `Akku.manifest` names chez-srfi; `akku` reads it.
   - **A keyed hash**, for tables keyed by ids a client sends, which `uuid-hash` leaves
     open to flooding (ADR-0005). It has two parts:
     - In the core, `make-uuid-hash : Bytevector -> (Uuid -> Nat)`, which takes the key
       as an argument.
     - In `(unique-id system)`, one keyed from `/dev/urandom`.

     HalfSipHash-2-4 is the candidate, checked against the SipHash reference's own
     vectors. Measured on a prototype, it is about 7× `uuid-hash`'s cost on Chez,
     0.47 µs a hash, and 2× on compiled Guile. Its arithmetic stays below 2^33, so
     AGENTS.md's below-2^23 rule for hashing needs amending with it. `uuid-hash` stays.

## Open

- **`uuid-hash` can be flooded until slice 3.** It is unkeyed and linear under xor, so
  anyone can make many valid ids that share a hash. README.org warns against keying a
  table by client ids with it; slice 3 adds a keyed hash.
- **On CI, no lane catches a test that expects `#f` from a raise**: chez-srfi and Guile
  3.0.9 both pass it. AGENTS.md forbids such tests. Only the host's Guile 3.0.11 catches
  one (ADR-0003).
- **`Akku.manifest` has not been read by `akku`**, which is not installed on the
  development host, and names no dependency yet. Slice 3 settles both.
- **Two `run-check` behaviours are untested**: that it runs `$CHEZ` rather than whatever
  `scheme` is on `PATH`, and that the child's stdin is `/dev/null`.
- **Nothing has run on macOS**, which the Makefile and the scripts aim to support.

## Close-outs

### The scaffold: PR #1, 2026-11-22

- **What merged:**
  - **Build and pin:** the Makefile, with `help`, `check-help`, `submodules`,
    `check-pins`, `check-chez`, `check-guile`, `deps`, `dev`, `dev-guile`, `run`, `test`,
    `test-chez`, `test-guile`, `test-tools`, `check-suites`, `check-imports`,
    `check-tests` and `clean`. `scripts/require-chez`, `scripts/require-guile`,
    `scripts/guile-prelude.scm`, and `scripts/ci/build-chez.sh` from threading.
    chez-srfi pinned at `7879b52`.
  - **Test harness:** `(unique-id-testing)`, plain R6RS, for both lanes;
    `(unique-id-checks)`, Chez's, for the audits. Three audit programs, one library-lane
    suite, four audit suites and their fixtures.
  - **CI and docs:** CI, AGENTS.md with its rule for signatures in comments, README.org,
    CHANGELOG.md, Akku.manifest.
  - **Plans:** ADR-0001 to ADR-0004, the global constraints, and the owner's answers in
    the brief.
- **The owner's choices:** the name `unique-id`; an id is a record, and `uuid-hash` is
  exported; the suites run on Chez and on Guile; the package goes to Akku later.
- **Chosen with the scaffold:** three libraries, `(srfi :19)` in `(unique-id system)`
  alone; the audits in `tools/` on Chez alone; Ubuntu's Guile in CI.
- **Verified:**
  - `make test` passes on Chez 10.4.0 and Guile 3.0.11 locally, and the Guile lane on a
    Guile 3.0.9 from the Guix store.
  - CI's first run built Chez 10.4.1 on both images (`ta6le` and `tarm64le`), ran
    Ubuntu's Guile 3.0.9, and passed every lane on each.
  - 27 mutants of the harness and the audits are all killed.
- **The review:** a read-only adversarial review, on Opus, found 10 defects, each
  reproduced and fixed before merge.
  - `tests/` was unaudited: a `.guile.sls` beside the testing library let a failing
    suite pass on Guile. `make check-tests` now holds `tests/`.
  - The Guile lane read `GUILE_LOAD_PATH`, `GUILE_LOAD_COMPILED_PATH` and the user's
    compiled cache, and Guile 3.0.9 wrote log files into the tree. The lane now runs
    with `GUILE_ENV`, from `build/guile`.
  - The rest were false claims: the SRFI-64 rules stated for one Guile, a fixnum bound
    a bit too wide, an `equal?` hashtable claim, the prelude's reach, three comments,
    the brief's rendering, and minor breaches of the signature rule.
  - Its fix for the prelude, keeping `warn`, brings back the core warnings on both
    Guiles; the comments were corrected instead.
- **Traps recorded in AGENTS.md:**
  - chez-srfi and Guile 3.0.9 turn a raise in the actual expression into `#f`; Guile
    3.0.11 counts it a failure.
  - `equal?` on records: `#f` on Chez, `#t` on Guile. Tests never compare ids with it.
  - A suite's top level on Guile sees Guile's own names, such as `string-map`.
  - Guile prefers `STEM.guile.sls` to `STEM.sls`.
- **Also learned:**
  - `bytevector`, `bytevector-append` and `read-bytevector` are R7RS, not R6RS.
  - Ubuntu 24.04's `guile-3.0` is 3.0.9, in universe, built for arm64 too.
  - Guile reads compiled files from its cache even with `--no-auto-compile`.
