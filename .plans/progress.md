# Progress ledger

Where unique-id stands. Read it with [global-constraints.md](global-constraints.md)
before starting slice work. When a slice merges, update **Now** and add a close-out under
**Close-outs**, newest first.

## Now

- **Slice 2, the generator, `(unique-id generator)`, is merged**, squashed from
  [PR #3](https://github.com/Kiyomi-Computation-Systems/unique-id/pull/3) on 2026-11-22;
  its close-out is below.
- **The design** is the brief, [uuid.md](uuid.md). The owner answered its open questions
  on 2026-11-22; its **Answers** section records them, and ADR-0001 to ADR-0004 the
  decisions they led to; later answers are recorded there too.
- **Next: slice 3**, the system, `(unique-id system)`, with the keyed hash.

## Slices

1. **The core, `(unique-id)`**: the record; text in and out; bytes in and out; version,
   variant and v7 timestamp; `uuid=?`, `uuid<?` and `uuid-hash`; the nil and max ids;
   `make-uuid-v4` and `make-uuid-v7`. RFC 9562's Appendix A vectors, copied from the
   RFC's text; round trips; every malformed text refused; a property test of the version
   and variant bits.
2. **The generator, `(unique-id generator)`**: `make-uuid-generator`, `generate-v4`,
   `generate-v7`, with RFC 9562 §6.2 Method 1's counter. A scripted clock that repeats,
   steps back and overflows the counter gives strictly increasing ids; one more than 10 seconds behind resets it.
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

- **On CI, no lane catches a test that expects `#f` from a raise**: chez-srfi and Guile
  3.0.9 both pass it. AGENTS.md forbids such tests. Only the host's Guile 3.0.11 catches
  one (ADR-0003).
- **Nothing checks that the Guile lane searches `src/` before `tests/`.** The Makefile's
  order was wrong for two slices, and a builder found it, not a check. A tools test that
  plants a shadow library and asserts it loses would hold it.
- **Two `run-check` behaviours are untested**: that it runs `$CHEZ` rather than whatever
  `scheme` is on `PATH`, and that the child's stdin is `/dev/null`.
- **Nothing has run on macOS**, which the Makefile and the scripts aim to support. The
  fork suite is the likeliest to break there: it loads libc by name to find `fork`.

## Close-outs

### Slice 2, the generator: PR #3, 2026-11-22

- **What merged:**
  - **The library:** `src/unique-id/generator.sls`, `(unique-id generator)`. It exports
    `make-uuid-generator`, `uuid-generator?`, `generate-v4` and `generate-v7`, built to
    the contract in [slice-2.md](slice-2.md).
  - **The suites:**
    - generator, 93 tests: exact calls and answers from A.6 and A.3, bad answers,
      rollover, reset and running out;
    - monotonic, 10 seeded runs of scripted clocks.
  - **Records:** ADR-0006. Also the brief's later answers, README.org, CHANGELOG.md, an
    AGENTS.md trap, the global constraints, and the Makefile's Guile `-L` order.
- **The owner's choices:**
  - The keyed hash goes in slice 3.
  - A clock more than 10 seconds behind the last id resets the generator, chosen over
    counting on and over refusing.
  - The reset was kept after it was shown to depart from §6.2's SHOULD, as LiosK's
    uuidv7 does.
- **Chosen with the slice:**
  - Method 1, seeded from 11 random bits.
  - One entropy call per id.
  - A bad clock or entropy answer raises an assertion violation, and running out
    raises with `error`.
  - A raise leaves the generator unchanged.
  - Order holds within one generator only.
- **How it was built:**
  - A read-only review of the contract, on Opus, came before any building, which the
    slice 1 reflection asked for.
  - Then three Sonnet builders worked in parallel, from one contract: the library and
    the two suites. A mutation run on Sonnet and an adversarial review on Opus followed,
    and two Sonnet fixers.
  - The reset was its own round: tests first, the library after, mutants, and a focused
    Opus review.
- **Verified:**
  - `make test` on Chez 10.4.0 and Guile 3.0.11, and the Guile lane on Guile 3.0.9.
  - CI on amd64 and arm64, with Chez 10.4.1 and Guile 3.0.9.
  - All 46 mutants of the generator are killed on all three Schemes, each by a counted
    test failure, as were the 13 mutants the reviews built, each when it was made.
- **The contract review**, before building, found:
  - which calls happen on a path that raises was unspecified;
  - the rollover vector could not tell LAST-MS + 1 from NOW + 1, which answers
    decreasing ids;
  - the four table vectors shared their last 8 bytes;
  - nothing tested the 2^48 edge.

  All of these were fixed before any builder started.
- **The slice review** found no fault in the library's behaviour. It found five
  untested paths, each with a surviving mutant, and doc and signature slips:
  - a full counter, then the clock moving on;
  - a bad entropy answer at a new tick after a first id;
  - the generator's opacity;
  - a bad NOW on an exhausted generator;
  - v4 answers indistinguishable from strings.
- **The reset review** found:
  - two wrong libraries passing both suites: state changed by a raise on the reset
    path, and the edge unpinned on the rollover path;
  - the departure from §6.2's SHOULD, which the recommendation to the owner had missed;
  - about a dozen untrue claims, among them "always increase", "breaks once", "10
    seconds ahead" (it is 10.001) and the rate that resets without a clock fault.
- **Caught in hand-backs:**
  - **Guile's `-L` order.** Guile searches `-L` directories in the order given, so the
    scaffold's Guile lane searched `tests/` before `src/`, though its comment said the
    opposite. A shadow library planted in `tests/` replaced the core for all 150 of
    its tests. `make check-tests` had always refused such a file. The Makefile now puts
    `src/` first.
  - A builder's stub runs on Guile had loaded the real library through that order. It
    was told, and reran them.
- **Traps recorded in AGENTS.md:** Guile's `-L` order. To test a stand-in library, put
  its directory first on both Schemes.
- **Also learned:**
  - SRFI-19's `time-monotonic` runs 37 s ahead of `time-utc` on both Schemes.
  - A clock held exactly 10 s behind cannot stay held past a rollover: the rollover
    puts it 10.001 s behind.
  - A stray `git stash` and `git stash pop` in one command did no harm, but is no
    way to work.

### Slice 1, the core: PR #2, 2026-11-22

- **What merged:**
  - **The library:** `src/unique-id.sls`, `(unique-id)`, with 15 exports, built to the
    contract in [slice-1.md](slice-1.md).
  - **The suites:** text (49 tests), core (150) and order (33). RFC 9562's vectors are
    copied from its text, and the property tests are seeded.
  - **Records:** ADR-0005, and an amendment to ADR-0004. Also README.org, CHANGELOG.md,
    and new traps in AGENTS.md.
- **The owner's choices:**
  - `uuid-version : Uuid -> (U Nat #f)`, #f outside variant `rfc9562`, where the brief
    had `Uuid -> Nat`.
  - `string->uuid` raises for a non-string.
  - A keyed hash comes in slice 3, and `uuid-hash` stays.
- **Chosen with the slice:**
  - Every export checks its own arguments: who is its name, the one irritant is the bad
    argument, checked first to last.
  - Variants are symbols.
  - The hash rotates and xors within 23 bits.
  - The record is generative.
- **How it was built:**
  - Four Sonnet agents in parallel, from one contract: the library and the three
    suites. Each suite had to fail every test against a stub that only raises.
  - Then a Sonnet mutation run and a read-only adversarial review on Opus.
  - Two Sonnet agents fixed what they found.
- **Verified:**
  - `make test` on Chez 10.4.0 and Guile 3.0.11, and the Guile lane on Guile 3.0.9.
  - CI on amd64 and arm64, with Chez 10.4.1 and Guile 3.0.9.
  - All 76 mutants of the library are killed on all three Schemes, each by a counted
    test failure.
- **Caught in hand-backs:**
  - The library's record had a fixed `nongenerative` uid. Any program could define the
    type again, make 3-byte ids, and change `nil-uuid`'s own octets, on both Schemes.
    The record is now generative.
  - A builder claimed `record?` needs `(rnrs records inspection)`. It does not:
    `(rnrs)` has it on both Schemes.
  - A suite dropped its `string-set!` freshness test, reading `(rnrs mutable-strings)`
    as forbidden. It is allowed, and the test is back. It kills a caching
    `uuid->string`.
- **The review:** 9 findings, each reproduced.
  - **Test gaps.** Untested were the characters next to the hex ranges (`/`, `@`, `` ` ``),
    the variant boundaries (the mutation run's 3 survivors), and exact non-integers
    such as `1/2`. All are now tested, and each kills mutants made for it.
  - **`uuid-version` answered 7 for ids that are not v7.** It is now #f outside the
    RFC's variant.
  - **`uuid-hash` is unkeyed and linear under xor**, so ids that share a hash cost
    nothing. README.org warns, and slice 3 adds a keyed hash.
  - **Guile's `struct-ref` reaches an id's octets.** ADR-0004 now says "within R6RS".
  - **The rest:** comment and signature slips, and an ADR claim about Guile's who.
- **Traps recorded in AGENTS.md:**
  - `string-set!` and `string-fill!` are in `(rnrs mutable-strings)`, and `quotient`,
    `remainder` and `modulo` in `(rnrs r5rs)`: none is in `(rnrs)`.
  - `number->string` in radix 16 is upper case on Chez and lower case on Guile.
  - A fixed `nongenerative` uid opens a record type to any program.
- **Also learned:**
  - On Guile, a record accessor's raise carries no who condition at all.
  - The Guile lane runs uncompiled, so its timings are not Guile's speed: `uuid-hash`
    took 7 µs there and 2 µs compiled.

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
