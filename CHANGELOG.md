# Changelog

All notable changes to unique-id are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The API may change in any
release before 1.0.

## [Unreleased]

### Added

- CONTRIBUTING.md, which says how to set up, which checks a pull request must pass,
  what to do when changing a comment in `src/`, an example or a page in `docs/`, the
  chez-srfi pin or the Makefile, and the house rules for code, tests and pull
  requests. SECURITY.md says how to report a vulnerability privately. `.github/`
  gains a pull-request template and bug and feature issue templates. README.org
  links CONTRIBUTING.md and SECURITY.md.
- `make check-help` also fails when CONTRIBUTING.md, the pull-request template or the
  bug report quotes a `make` target the Makefile lacks.

## [0.1.0] - 2026-11-23

The first release.

### Added

- `(unique-id)`: ids as opaque records, and `uuid?`; text and bytes in and out;
  version, variant and v7 timestamp; `uuid=?`, `uuid<?` and `uuid-hash`;
  `make-uuid-hash`, a keyed hash, HalfSipHash-2-4, for tables keyed by ids that
  others send; `nil-uuid` and `max-uuid`; `make-uuid-v4` and `make-uuid-v7` from the
  bits you supply.
- `(unique-id generator)`: `make-uuid-generator` over a clock and an entropy source
  you give it, and `uuid-generator?`; `generate-v4`; `generate-v7`, whose ids from one
  generator increase, unless the clock is more than 10 seconds behind the last id,
  which resets it. The clock can fall that far, or millions of ids a second can run
  the ids that far ahead of it.
- `(unique-id system)`: `system-clock`, the Unix time in milliseconds; `system-entropy`,
  bytes from `/dev/urandom`, opened afresh by every call that reads;
  `make-system-uuid-generator`; `make-system-uuid-hash`, keyed from `/dev/urandom`.
- Documentation: guides to ids, generators, the system library, hash tables and
  errors, a getting-started page, a quickstart, and an API reference generated from
  the signature comments in `src/`, at
  https://kiyomi-computation-systems.github.io/unique-id/.

[Unreleased]: https://github.com/Kiyomi-Computation-Systems/unique-id/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Kiyomi-Computation-Systems/unique-id/releases/tag/v0.1.0
