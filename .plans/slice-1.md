# Slice 1: the core, `(unique-id)`

The contract the library and its suites are built to. RFC 9562's text, fetched from
rfc-editor.org on 2026-11-22, is the source of every vector here; each cites its section
or figure.

## Files

| File | What it holds |
|---|---|
| `src/unique-id.sls` | the library `(unique-id)` |
| `tests/test-unique-id-text.sps` | suite `unique-id-text`: text in and out |
| `tests/test-unique-id.sps` | suite `unique-id`: the record, bytes, nil and max, version, variant and timestamp, `make-uuid-v4` and `make-uuid-v7` |
| `tests/test-unique-id-order.sps` | suite `unique-id-order`: `uuid=?`, `uuid<?`, `uuid-hash`, and v7's time order |

## Exports

In this order:

```
uuid?
bytevector->uuid uuid->bytevector
string->uuid uuid->string
uuid-version uuid-variant uuid-v7-timestamp
uuid=? uuid<? uuid-hash
nil-uuid max-uuid
make-uuid-v4 make-uuid-v7
```

Octets are numbered 0 to 15 and bits 0 to 127, most significant first (RFC 9562 §4).

| Signature | Answers |
|---|---|
| `uuid? : Any -> Boolean` | #t for an id, #f for anything else, a 16-byte bytevector included. |
| `bytevector->uuid : Bytevector -> Uuid` | The id whose octets are BYTES, 16 bytes. The id keeps its own copy: changing BYTES later does not change it. |
| `uuid->bytevector : Uuid -> Bytevector` | The id's 16 octets, octet 0 first, in a fresh bytevector. |
| `string->uuid : String -> (U Uuid #f)` | The id TEXT spells in the canonical form, or #f for any other string. The canonical form is 36 characters: a hyphen at indexes 8, 13, 18 and 23, and at the other 32 an ASCII hex digit, `0`–`9`, `a`–`f` or `A`–`F`, in any mix of case (§4's ABNF). |
| `uuid->string : Uuid -> String` | The canonical form in lower case, in a fresh string. |
| `uuid-version : Uuid -> (U Nat #f)` | For an id of variant `rfc9562`, bits 48–51, the high 4 bits of octet 6: 0 to 15 (§4.2). #f for any other variant, which RFC 9562 gives no version (§4.2's last paragraph, Table 2's title): the nil and max ids among them (§5.9, §5.10). |
| `uuid-variant : Uuid -> Symbol` | From octet 8's high bits (§4.1, Table 1): `ncs` for 0xxx, `rfc9562` for 10xx, `microsoft` for 110x, `future` for 111x. |
| `uuid-v7-timestamp : Uuid -> (U Nat #f)` | For an id of version 7 and variant `rfc9562`, octets 0–5 as a big-endian unsigned integer: milliseconds since 1970-01-01 UTC (§5.7). #f for any other id. |
| `uuid=? : Uuid Uuid -> Boolean` | #t when A and B have the same 16 octets. |
| `uuid<? : Uuid Uuid -> Boolean` | #t when A's octets come before B's, compared as unsigned bytes from octet 0. This is the ids' order as 128-bit unsigned integers, and their lower-case text's order under `string<?` (§6.11). |
| `uuid-hash : Uuid -> Nat` | A nonnegative fixnum below 2^23, from the octets alone (see **Hash**). |
| `nil-uuid : Uuid` | The id whose 128 bits are all 0 (§5.9). |
| `max-uuid : Uuid` | The id whose 128 bits are all 1 (§5.10). |
| `make-uuid-v4 : Bytevector -> Uuid` | BYTES, 16 bytes, with the high 4 bits of octet 6 set to 0100 and the high 2 bits of octet 8 set to 10. The other 122 bits are BYTES' own (§5.4). BYTES is not changed. |
| `make-uuid-v7 : Nat Nat Bytevector -> Uuid` | MS (below 2^48) big-endian in octets 0–5. Then 0111 in the high 4 bits of octet 6, and COUNTER (below 2^12) in the 12 bits after it, octet 6's low 4 bits and octet 7. Then BYTES, 8 bytes, in octets 8–15, with octet 8's high 2 bits set to 10 (§5.7). BYTES is not changed. |

## Errors

- **An argument outside its procedure's domain raises an assertion violation.** Its who
  is the exported procedure's own name, and its irritants are a one-element list holding
  the offending argument itself (`eqv?`).
  - A Uuid argument must satisfy `uuid?`.
  - A String argument must satisfy `string?`.
  - A Bytevector argument must be a bytevector of the stated length: 16 bytes, or 8 for
    `make-uuid-v7`.
  - A Nat argument must be an exact integer from 0 to below its bound.
- **Arguments are checked from first to last**, and the first that fails is the one
  raised.
- **Text is not an argument error.** `string->uuid` answers #f for any string that is
  not canonical. It raises only for a non-string.

## Hash

- Every pair of `uuid=?` ids hashes alike, and `(make-hashtable uuid-hash uuid=?)` keys
  a table by id.
- Ids that differ in exactly one octet have different hashes.
- 1000 distinct random ids get at least 990 distinct hashes.
- **The algorithm**, which the suites hold by the three properties above and do not pin.
  h starts at 0. For each octet b, from 0 to 15:
  - rotate h left by 8 within 23 bits: `((h & #x7FFF) << 8) | (h >> 15)`;
  - then xor in b.

  It uses only `fx` operations on values below 2^23, so it runs on a Scheme with the
  narrowest fixnums R6RS allows.

## The record

- An opaque, sealed R6RS record holding a bytevector of 16 bytes, which never leaves the
  library. Its type, constructor and field accessor are not exported.
- `record?` answers #f for an id.

## Vectors

From RFC 9562's text. A test that uses one names its source in its name.

| Source | Input | Id |
|---|---|---|
| A.3, Figure 20 | `make-uuid-v4` of bytes `919108F752D133205BACF847DB4148A8` | `919108f7-52d1-4320-9bac-f847db4148a8` |
| A.6, Figure 26 | `make-uuid-v7` of `#x017F22E279B0`, `#xCC3`, bytes `18C4DC0C0C07398F` | `017f22e2-79b0-7cc3-98c4-dc0c0c07398f` |

- **A.6:** the timestamp is "0x017F22E279B0 or 1645557742000". `string->uuid` of the
  RFC's own upper-case `017F22E2-79B0-7CC3-98C4-DC0C0C07398F` gives a v7 id with that
  timestamp.
- **A.6's BYTES:** `rand_b` is "0b01, 0x8C4DC0C0C07398F", 62 bits. As 8 bytes with the
  two high bits 00, that is `18C4DC0C0C07398F`. With those two bits 01, 10 or 11
  (`58…`, `98…`, `D8…`), BYTES gives the same id.
- **§4, Figures 1 and 3:** `f81d4fae-7dec-11d0-a765-00a0c91e6bf6` is, as an unsigned
  integer, 329800735698586629295641978511506172918. Its version is 1 and its variant
  `rfc9562`, and its v7 timestamp is #f.
- **§4.2, Figure 5:** `00000000-0000-4000-8000-000000000000`, and the same with `9`, `A`
  and `B` for the `8`, are version 4 with variant `rfc9562`.
- **§5.9 and §5.10:**
  - `nil-uuid` is `00000000-0000-0000-0000-000000000000`, variant `ncs`, so no
    version.
  - `max-uuid` is the RFC's `FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF`, written as
    `ffffffff-ffff-ffff-ffff-ffffffffffff`, variant `future`, so no version.

## Amended after review

- **`uuid-version` answered the version bits of any id**, whatever its variant, and so
  gave 7 for an id that is not v7. It now answers #f outside variant `rfc9562`.

## Out of this slice

- The generator and the system's clock and entropy: slices 2 and 3.
- Any other text form: braces, URNs, no hyphens.
