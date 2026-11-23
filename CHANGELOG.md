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
