# ADR-0003: Builds and tests run on the host's Chez and Guile, and CI builds Chez 10.4.1

- **Status:** Accepted
- **Date:** 2026-11-22
- **Scope:** development tooling and CI. No library change.
- **Related:** threading ADR-0003, which this extends with Guile; its
  `scripts/ci/build-chez.sh`, copied here unchanged

## Context

The library has no native code, so it needs no container: it runs on the host's Chez
10.4.0 and Guile 3.0.11 as it would on later ones. Ubuntu 24.04's `chezscheme` package is
9.5.8, with no arm64 build, so CI builds Chez itself, as threading does. Its `guile-3.0`
package, in universe, is 3.0.9, built for amd64 and arm64.

The host's Guile 3.0.11 carries a SRFI-64 written in 2024, by its source's copyright line.
Guile 3.0.9 predates it. Measured with a 3.0.9 from the host's Guix store, its SRFI-64
behaves like chez-srfi's on raises, and writes `SUITE-NAME.log` to the directory it runs
in.

Guile reads `GUILE_LOAD_PATH` and `GUILE_LOAD_COMPILED_PATH` ahead of its own
directories, and compiled files from `XDG_CACHE_HOME`'s cache even with
`--no-auto-compile`. The host's Guix profile sets both paths.

## Decision

1. **`make` runs the host's Chez and Guile**: `CHEZ` as given, else the first of
   `scheme` and `chez` on `PATH` that answers as Chez Scheme (`scripts/require-chez`);
   `GUILE` as given, else the first of `guile` and `guile-3.0` that answers as Guile 3
   (`scripts/require-guile`). **`make check-chez` and `make check-guile` refuse anything
   else**, naming what it answered, and every target that runs either checks it first.
   No version floor is enforced beyond Guile's major version.
2. **CI runs on Linux, amd64 and arm64**, on pinned Ubuntu 24.04 images. It **builds
   Chez 10.4.1 from its sha256-pinned release tarball** (`scripts/ci/build-chez.sh`),
   cached per OS release, arch and script, and **installs Ubuntu's `guile-3.0`**. The job
   asserts the Chez version and machine type, and the Guile major version, it ends up
   with.
3. **The Guile lane runs Guile with those two paths unset and `XDG_CACHE_HOME` under
   `build/`** (`GUILE_ENV`), **from `build/guile`**, so no outside library, stale
   compiled file or log file reaches the lane or the tree.
4. **There is no development container.**

## Consequences

- **Four Schemes run the suites**: the host's Chez 10.4.0 and Guile 3.0.11, and CI's Chez
  10.4.1 and Guile 3.0.9. README.org names them rather than a floor.
- **The host and CI run different Guile SRFI-64s**, the newer and the older. On CI no
  lane catches a test that expects `#f` from a raise; only the host's Guile does.
  AGENTS.md's testing rules forbid such a test. A suite that passes on one and fails on
  the other has leaned on an edge those rules forbid, or found one they do not yet
  name.
- **CI's Guile is whatever Ubuntu 24.04 ships**, which can move with a point release. A
  pinned Guile would take a build script of its own, like Chez's.
