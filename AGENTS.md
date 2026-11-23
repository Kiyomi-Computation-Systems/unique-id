# AGENTS.md

## Project guidelines

### What this is

* UUIDs for R6RS Scheme, versions 4 (random) and 7 (ordered by time), as RFC 9562
  defines them. Built for Techo, whose clients make v7 ids offline and whose server makes
  ids and checks every id a client sends. The brief, and the owner's answers to it, are
  `.plans/uuid.md`.
* Three libraries (ADR-0001):
  * `(unique-id)`, the core: text and bytes in and out; version, variant and v7
    timestamp; `uuid=?`, `uuid<?` and `uuid-hash`; the nil and max ids; and
    `make-uuid-v4` and `make-uuid-v7`, which take every bit they do not fix as
    arguments.
  * `(unique-id generator)`: a generator, given a clock and an entropy source, whose v7
    ids increase, but when the clock falls more than 10 seconds behind.
  * `(unique-id system)`: the system's clock, through SRFI-19, bytes from
    `/dev/urandom`, and a generator made of the two.
* An id is an opaque, sealed record of 16 bytes (ADR-0004). `uuid=?` compares ids and
  `uuid-hash` hashes them; `equal?` on ids is no part of the contract.

### Architecture & portability

* **Functional core, imperative shell.** `(unique-id)` reads no clock and no entropy:
  whatever varies is an argument, so every test of it is a fixed vector. The shell is
  `(unique-id generator)`, which keeps state, and `(unique-id system)`, which reads the
  world.
* Every file under `src/` is **plain R6RS**: a `.sls` library whose first line is
  `#!r6rs`, with no `#!` after it, importing only `(rnrs ...)` but `(rnrs eval)`,
  `(unique-id ...)` libraries that are themselves under `src/`, and, in `(unique-id
  system)` alone, `(srfi :19)` (ADR-0001). `make check-imports` holds it, and `make test`
  runs it once `src/` exists. It passes over an OS's or an editor's litter: dot files,
  `#autosave#` and `backup~`.
* **The library suites run on Chez and on Guile 3** (ADR-0001). Chez is the development
  Scheme, but nothing in `src/` or `tests/` may depend on either: no Chez or Guile
  procedures, no reader syntax of either, no file named `.chezscheme.sls` or `.ss`, which
  Chez loads in place of the `.sls`, nor `.guile.sls`, which Guile does. `make
  check-tests` holds `tests/` to it: STEM.sls and STEM.sps alone, importing only
  `(rnrs ...)` but `(rnrs eval)`, `(srfi :64)`, the library and `tests/`' own
  libraries.
* R6RS leaves some behaviour to the implementation. Prefer the form every implementation
  agrees on, and when the code relies on an R6RS guarantee that is easy to get wrong, say
  which in a comment. Known edges:
  * `equal?` on records: Chez answers `#f` for two ids with the same bytes, Guile `#t`.
  * Fixnums: R6RS promises a fixnum width of only 24 bits, sign included, so a
    nonnegative fixnum is below 2^23 everywhere. Hashing arithmetic stays below it.
  * Names R7RS has are not all R6RS: `bytevector`, `bytevector-append`,
    `read-bytevector` and `string-map` are not. Check the R6RS library before using
    one.
  * `(rnrs)` leaves some R6RS names out: `string-set!` and `string-fill!` are in
    `(rnrs mutable-strings)`, and `quotient`, `remainder` and `modulo` in `(rnrs r5rs)`.
    Use `div` and `mod`.
  * `number->string` in radix 16 answers upper case on Chez, lower case on Guile.
  * A record type with a fixed `nongenerative` uid can be defined again by any program,
    which then makes and opens such records. An id's record is generative.
* The library runs wherever an R6RS Scheme does; `(unique-id system)` also needs
  `/dev/urandom`: Linux and macOS. The build and the tests need a POSIX shell and GNU
  make: Linux and macOS, on amd64 and arm64.
* **DO NOT** set up macOS CI runners: Linux only!

### Signatures in comments

* **Every exported procedure has a comment directly above its definition**: a Typed
  Racket style signature on the first line, then what it answers, in a sentence or two.
  An exported value gets its type the same way.

  ```scheme
  ;; string->uuid : String -> (U Uuid #f)
  ;; The id TEXT spells in the canonical 36-character form, in either case,
  ;; or #f when TEXT is anything else.
  (define (string->uuid text) ...)

  ;; nil-uuid : Uuid
  ;; The id whose 128 bits are all 0.
  (define nil-uuid ...)
  ```

* **The vocabulary**: `Uuid`, `Generator`, `Nat` (an exact nonnegative integer),
  `Integer`, `Boolean`, `String`, `Symbol`, `Char`, `Bytevector`, `Any`, and `Sexp` for
  a datum as `read` answers it; `Void` for what a procedure called for its effect
  answers; `(U A B)` for either; `(Listof A)`, `(List A B)` and
  `(Pair A B)`; `(A B -> C)` for a procedure and `(-> A)` for one of no arguments;
  `(Values A B)` for several values. Name a test runner `Test-Runner` and a library
  name `Library-Name`. A file may name a type of its own, such as `Complaint`, when a
  comment in it says what the type is.
* **What a type cannot say goes in the prose**: a bytevector's length ("16 random
  bytes"), a number's range ("a 12-bit counter"), what is raised and when ("else an
  assertion violation"), and whether an answer is fresh ("a fresh copy").
* Name an argument in capitals when the prose refers to it: TEXT, BYTES.
* An internal procedure gets a signature too when its name does not make its types
  plain. The test-only libraries, `(unique-id-testing)` and `(unique-id-checks)`, follow
  the same rules as `src/`.
* An exported macro, if one is ever added, documents its grammar and what it expands to
  instead.
* A signature describes the code as it is. Change it in the same commit as the code.

### Dependencies

* `(unique-id)` and `(unique-id generator)` have none. `(unique-id system)` imports
  `(srfi :19)`: chez-srfi's on Chez, Guile's own on Guile (ADR-0002).
* The suites use SRFI-64: chez-srfi's on Chez, Guile's own on Guile.
* chez-srfi (https://github.com/arcfide/chez-srfi) is a submodule under `vendor/`,
  pinned at `SRFI_PIN`, the commit threading, chez-http-server and circuit pin
  (ADR-0002). `make submodules` clones it, where the network is; `make deps` links it
  into `build/scheme-libs` and never fetches. `make check-pins` holds the gitlink and
  the checkout at `SRFI_PIN`: move both on one commit.
* Builds and tests run on the host's Chez, found as `scheme` or `chez` on `PATH` or named
  by `CHEZ`, and the host's Guile 3, found as `guile` or `guile-3.0` or named by `GUILE`
  (ADR-0003). There is no development container.
* The package will be published on Akku. `Akku.manifest` names chez-srfi once
  `(unique-id system)` exists.

### Layout, process & libraries

* `src/` holds the library. `tests/` holds the library suites and `(unique-id-testing)`,
  all plain R6RS, which both lanes run. `tools/` holds the audits, `make
  check-imports`, `make check-suites` and `make check-tests`, with
  `(unique-id-checks)`, their suites and fixtures, which run on Chez alone and may use
  Chez's own procedures, through `(only (chezscheme) ...)`.
* Plans live in `/.plans`, decision records in `/.plans/decisions`.
* The ledger is `/.plans/progress.md`: where the project stands, the next slice, and a
  close-out for each merged slice. `/.plans/global-constraints.md` holds the decision
  records' hard rules and binds every task brief. Read both before starting slice work.
  `/.superpowers/` is git-ignored plugin scratch, not the ledger.
* Code comments, `README.org` and `/docs` describe the code as it is: never cite a plan,
  slice, decision record, review, date, or PR or issue number. State the fact or the
  reason itself, in the present tense. History belongs in `/.plans`, the ledger,
  `CHANGELOG.md` and git.
* Add entries to `CHANGELOG.md` for each release.
* `/docs` is for user facing documentation only.
* Documentation should be very concise, focused, to the point, ELI5 style.
* `Makefile` should have a `help` command which lists all of its commands;
  `make check-help` holds it to `.PHONY`.
* Libraries are R6RS `.sls`; libraries and programs contain their own code — no shared
  include bodies.

### Testing & mutation discipline

* Use TDD / test-driven development.
* A test that passes whether the code is right or wrong is worse than no test.
* A test is not finished when it passes. It is finished when you have watched it fail.
* Prefer a check to a comment.
* **Do not** write tests that rely on reading code comments: a test asserts what the code
  does, never what a comment says.
* **Test vectors come from RFC 9562's own text**, never from memory. Name the section a
  vector comes from in its test's name.
* **A property test draws its inputs from a seeded generator** written in the suite, so a
  failure reproduces. Name the seed and the number of cases in the test.
* **Hold the shell's effects with scripted stand-ins**: a clock that answers a list of
  times, an entropy source that answers given bytes and records how many it was asked
  for. Assert what was asked as well as what came back.
* Run mutants on copies under `build/`, each suite under a timeout and a memory cap, on
  both lanes:

  ```sh
  (ulimit -v 4194304 && timeout 60 "$CHEZ" --libdirs src:tests:build/scheme-libs --program tests/test-x.sps)
  (ulimit -v 4194304 && timeout 60 env -u GUILE_LOAD_PATH -u GUILE_LOAD_COMPILED_PATH XDG_CACHE_HOME="$PWD/build/guile-cache" "$GUILE" --r6rs --no-auto-compile -L "$PWD/src" -L "$PWD/tests" -l scripts/guile-prelude.scm tests/test-x.sps)
  ```

  With `&&`, a shell that refuses the cap runs nothing rather than running the suite
  uncapped.

**Tests**

* `guard` returns the body's value when nothing raises, and `0` is truthy. Assert *what
  was raised* against an expected value, with a distinct sentinel for the no-raise case.
* **The SRFI-64s part on raises.** chez-srfi's and Guile 3.0.9's, CI's, behave alike;
  Guile 3.0.11's, the host's, differs. Write every test so it holds on all of them:
  * chez-srfi and Guile 3.0.9 turn a raise in the *actual* expression into `#f`; Guile
    3.0.11 counts it a failure. Never expect `#f` from something that can raise: on
    Chez, and on CI's Guile, the test passes whatever raised. Only the host's Guile
    would catch it.
  * chez-srfi and Guile 3.0.9 do not catch a raise in the *expected* expression, nor in
    a suite's top-level definitions: the suite dies and no test is named. Guile 3.0.11
    counts the first a failure. Compute anything that can raise under a `guard`.
* **Never compare ids with `equal?` or `test-equal`**: `equal?` on records answers
  differently on the two lanes. Compare `uuid->string` or `uuid->bytevector`, or assert
  `uuid=?`.
* Every `tests/test-*.sps` and `tools/test-*.sps` must end with `(exit
  (suite-exit-status runner))`: SRFI-64 sets no exit status. Anything after that line
  never runs, and `make check-suites` checks it is there. It reads suites as data, so a
  quoted exit form anywhere before the last line counts as an early exit: build such a
  list with `list`.
* An exit status is taken modulo 256, so `(exit 256)` exits 0. Exit with 0 or 1, never a
  count.
* A suite cannot vouch for the verdict it exits through. A suite that tests
  `suite-exit-status` must also exit 1 on its own failures, before the shared form.
* Neither Scheme fixes the order a call's arguments are evaluated in: Chez chooses it as
  it compiles each call, and `map` calls its procedure in no fixed order. A `let`'s
  inits are arguments too. No assertion may depend on any order: use `for-each` for
  effects, and `let*` when one init must follow another.
* An assertion passes whenever *another* rule can produce its expected value. Assert
  whole outputs, not substrings, and build a test's base from non-default values.
* SRFI-64 keeps one result per runner. Never run a test inside another test's actual
  expression: the outer verdict is reported under the inner test's name. To test the
  harness itself, run tests on a runner of their own, made with `test-runner-null` and
  `test-with-runner`.
* R6RS cannot rebind a port, so what code writes is tested on Chez alone, in `tools/`.
  There, `(rnrs)`'s `current-output-port` and `current-error-port` take no argument:
  `parameterize` Chez's own, imported with `(prefix (only (chezscheme)
  current-error-port) chez:)`.
* On Guile, a suite's `(import (rnrs))` replaces core bindings, and Guile warns of each.
  `scripts/guile-prelude.scm` stops the warnings, and with them Guile's warning for two
  imported libraries that export one name, which Chez refuses outright. Run suites
  through `make`, or with `GUILE_ENV` and `GUILE_FLAGS` from the Makefile: they keep
  `GUILE_LOAD_PATH` and the user's compiled-file cache out.
* Guile searches `-L` directories in the order given, the first winning, as Chez does
  `--libdirs`. To test a stand-in library, put its directory first on both.
* Guile 3.0.9's SRFI-64 writes `SUITE-NAME.log` to the directory it runs in, so the
  Guile lane runs from `build/guile`, and gives each suite its absolute path.
* On Guile, a suite's top level also sees Guile's own core bindings, `string-map` for
  one, though it never imported them. The Chez lane is what refuses a suite that uses
  one: a suite passes only when both lanes pass.

## Closing ritual

We run this when we're done and ready to merge the PR.

**Important**: ALWAYS ask before running this.

1. Squash merge the PR.
2. Catch up local `main`.
3. Clean up branches. Delete the merged branch locally and on the remote.
4. Reflect.
