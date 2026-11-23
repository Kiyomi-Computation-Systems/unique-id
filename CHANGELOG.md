# Changelog

All notable changes to unique-id are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The API may change in any
release before 1.0.

## [Unreleased]

### Added

- `(unique-id)`: ids as opaque records; text and bytes in and out; version, variant and
  v7 timestamp; `uuid=?`, `uuid<?` and `uuid-hash`; `nil-uuid` and `max-uuid`;
  `make-uuid-v4` and `make-uuid-v7` from the bits you supply.
- `(unique-id generator)`: `make-uuid-generator` over a clock and an entropy source
  you give it; `generate-v4`; `generate-v7`, whose ids from one generator always
  increase, unless the clock falls more than 10 seconds behind, which resets it.
- `(unique-id)`: `make-uuid-hash`, a keyed hash, HalfSipHash-2-4, for tables keyed by
  ids that others send.
- `(unique-id system)`: `system-clock`, the Unix time in milliseconds; `system-entropy`,
  bytes from `/dev/urandom`, opened afresh by every call that reads;
  `make-system-uuid-generator`;
  `make-system-uuid-hash`, keyed from `/dev/urandom`.
- `docs/`: guides to ids, generators, the system library, hash tables and errors, a
  getting-started page, a quickstart, and an API reference generated from the
  signature comments in `src/`. `make site` renders them as HTML.
