# Progress ledger

Where unique-id stands. Read it with [global-constraints.md](global-constraints.md)
before starting slice work. When a slice merges, update **Now** and add a close-out under
**Close-outs**, newest first.

## Now

- **The scaffold is on the branch `scaffold`**, not yet merged. A read-only adversarial
  review, on Opus, found 10 defects. Each was reproduced, and each is fixed on the
  branch; the close-out will list them.
- **CI passes on the PR**, on amd64 and arm64: Chez 10.4.1 built from source, Ubuntu's
  Guile 3.0.9, every lane run.
- **The design** is the brief, [uuid.md](uuid.md). The owner answered its open questions
  on 2026-11-22; its **Answers** section records them, and ADR-0001 to ADR-0004 the
  decisions they led to.
- **Next: slice 1**, the core, `(unique-id)`.

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

## Open

- **On CI, no lane catches a test that expects `#f` from a raise**: chez-srfi and Guile
  3.0.9 both pass it. AGENTS.md forbids such tests. Only the host's Guile 3.0.11 catches
  one (ADR-0003).
- **`Akku.manifest` has not been read by `akku`**, which is not installed on the
  development host, and names no dependency yet. Slice 3 settles both.
- **Two `run-check` behaviours are untested**: that it runs `$CHEZ` rather than whatever
  `scheme` is on `PATH`, and that the child's stdin is `/dev/null`.
- **Nothing has run on macOS**, which the Makefile and the scripts aim to support.

## Close-outs

None yet.
