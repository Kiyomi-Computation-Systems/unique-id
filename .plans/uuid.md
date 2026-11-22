# Brief: a UUID library for R6RS (v4 and v7)

Date: 2026-11-22
Status: draft for a separate project
For: Techo, which needs time-ordered ids that clients generate

## Why

- Techo's node ids are UUIDv7: clients make them offline, a create can be retried, and
  ids sort by time.
- The server makes ids too, for accounts and keys, and must check every id a client
  sends.

## What exists

| Library | Why it does not fit |
|---|---|
| Akku `uuid` 1.0.0-beta.0 (Weinholt) | Versions 1 to 5 only; read in its `uuid.sls` on 2026-11-22. Depends on `industria`, `hashing`, `struct-pack`. |
| `r6rs-ulid` (ktakashi) | ULID is another format. Its README says it has no good random seed on Chez. |

**The Akku name `uuid` is taken.** The package and its library need another name. This
is the owner's call; `uuid7` misleads, since v4 is included.

## Scope

**In**

- Parse and format the canonical text form: 36 characters, lower case out, either case
  in.
- Convert to and from a 16-byte bytevector.
- Make version 4 and version 7 ids.
- Read an id's version and variant, and a v7 id's timestamp.
- Compare: equal, less-than. A v7 id's byte order is its time order.
- The nil and max ids.

**Out**

- Versions 1, 2, 3, 5, 6 and 8.
- Other text forms: braces, URNs, no hyphens.
- Thread safety. A generator belongs to its caller.

## Design

Functional core, imperative shell, as Techo's `AGENTS.md` asks.

**Core: pure `(rnrs)`, no clock, no entropy**

```scheme
;; string->uuid : String -> (U Uuid #f)
;; uuid->string : Uuid -> String
;; bytevector->uuid : Bytevector -> Uuid        ; 16 bytes, else an assertion violation
;; uuid->bytevector : Uuid -> Bytevector        ; a fresh copy
;; uuid-version : Uuid -> Nat
;; uuid-variant : Uuid -> Symbol
;; uuid-v7-timestamp : Uuid -> (U Nat #f)       ; milliseconds since 1970, #f if not v7
;; uuid=? uuid<? : Uuid Uuid -> Boolean
;; make-uuid-v4 : Bytevector -> Uuid            ; 16 random bytes
;; make-uuid-v7 : Nat Nat Bytevector -> Uuid    ; milliseconds, 12-bit counter, 8 random bytes
```

- `make-uuid-v4` and `make-uuid-v7` set the version and variant bits themselves and
  take everything else as arguments, so every test is a fixed vector.

**Shell: a generator**

```scheme
;; make-uuid-generator : (-> Nat) (Nat -> Bytevector) -> Generator   ; clock, entropy
;; generate-v4 : Generator -> Uuid
;; generate-v7 : Generator -> Uuid
```

- The clock and the entropy source are arguments. A default generator reads the time
  through SRFI-19, from chez-srfi, and bytes from `/dev/urandom`, with no FFI. `(rnrs)`
  has no clock of its own.
- **v7 ids from one generator always increase.** RFC 9562 §6.2, Method 1: the 12 bits
  after the version are a counter.
  - A new millisecond starts the counter at a random value with its top bit clear.
  - The same millisecond adds one.
  - A counter that overflows moves the timestamp on one millisecond.
  - A clock that steps back is ignored: the generator keeps its last timestamp.

## Tests

- RFC 9562's test vectors for v4 and v7 (Appendix A). Copy them from the RFC's text,
  not from memory.
- Round trips: text, bytes, text.
- Every malformed text is refused with `#f`: wrong length, wrong hyphens, a non-hex
  digit.
- Monotonic: a scripted clock that repeats, steps back and overflows the counter gives
  strictly increasing ids.
- The version and variant bits hold for every random input (a property test).
- A default generator's ids parse back, and differ.

## Portability

- The core is plain R6RS. Run its suite on Chez, and on Guile in R6RS mode if that is
  cheap, as `threading` does.
- The default generator needs `/dev/urandom`: Linux and macOS.

## Open

- The package's name.
- Whether an id is a record or a bare 16-byte bytevector. A record is safer; a
  bytevector binds straight to a SQLite blob.
- Whether to publish on Akku at once.

## Answers

The owner answered on 2026-11-22.

- **The name is `unique-id`**, for the package and its libraries (ADR-0004).
- **An id is a record**, and `uuid-hash` is exported, so a hashtable can key on ids
  (ADR-0004).
- **The suites run on Chez and on Guile** (ADR-0001). `threading`, contrary to
  Portability above, runs its suites on Chez alone; the Guile lane is new here.
- **The package will be published on Akku**, not at once.

Decided with the scaffold, not asked of the owner:

- **The library is three libraries** (ADR-0001): `(unique-id)`, the core;
  `(unique-id generator)`, the generator, given a clock and entropy; `(unique-id
  system)`, the default clock and `/dev/urandom`, and the one importer of SRFI-19.
