# API reference

Everything the three libraries export, one entry each.

This page is generated from the signature comments in `src/` by `make reference`, so edit those, not this page.

```scheme
(import (rnrs) (unique-id) (unique-id generator) (unique-id system))
```

## How to read an entry

Each entry shows the call shape, then the signature, then what the procedure answers. A value has a signature alone.

Names in capitals in the text are the call's arguments, as TEXT is `text`, or the values the text names, as CLOCK is a generator's clock.

| Type | Means |
|:--|:--|
| `Uuid` | an id |
| `Generator` | what `make-uuid-generator` answers |
| `Nat` | an exact nonnegative integer |
| `Boolean` | `#t` or `#f` |
| `String` | a string |
| `Symbol` | a symbol |
| `Bytevector` | a bytevector |
| `Any` | any value |
| `#f` | the value `#f` |
| `(U A B)` | either an `A` or a `B` |
| `(A B -> C)` | a procedure of an `A` and a `B` that answers a `C` |
| `(-> A)` | a procedure of no arguments that answers an `A` |

A signature that starts with `->`, as `system-clock : -> Nat`, is a procedure of no arguments too.

## Errors

An argument outside its domain raises an assertion violation whose who is the procedure's name and whose one irritant is that argument. See [Errors](errors.md).
