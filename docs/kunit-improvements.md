# kunit improvement notes

## Implicit parameter resolution in test bodies

When using `assert/equal` or `assert/contains` inside `test`, `dtest`, or `itest` bodies,
Koka's implicit parameter resolution fails to find `?eq` and `?show` for common types
like `string`, `int`, `list<string>`, and `maybe<string>`.

This is because the test body effect rows (`<pure,kassertion,kscenario>`,
`<div,exn,console,kassertion,kscenario>`, etc.) prevent the compiler from resolving
the implicit parameters automatically.

### Workaround

Use `assert/is-true` with explicit comparisons instead:

```koka
// This fails to compile:
assert/equal("expected", actual-string)
assert/equal(42, actual-int)
assert/contains(string-list, "needle")

// This works:
assert/is-true(actual-string == "expected")
assert/is-true(actual-int == 42)
assert/is-true(string-list.any(fn(s) s == "needle"))
```

### Possible fix: concrete overloads

Add type-specific assertion functions that don't rely on implicit resolution:

```koka
pub fun assert/equal-string(expected: string, actual: string, ?kk-file-line: string): <pure,kassertion> ()
  if expected == actual then pass()
  else fail("assert/equal-string", kk-file-line, expected, actual)

pub fun assert/equal-int(expected: int, actual: int, ?kk-file-line: string): <pure,kassertion> ()
  if expected == actual then pass()
  else fail("assert/equal-int", kk-file-line, expected.show, actual.show)

pub fun assert/contains-string(collection: list<string>, expected: string, ?kk-file-line: string): <pure,kassertion> ()
  if collection.any(fn(s) s == expected) then pass()
  else fail("assert/contains-string", kk-file-line,
    "collection to contain " ++ expected,
    collection.join(", "))
```

This preserves kunit's structured error reporting (file/line, expected vs actual)
while avoiding the implicit resolution issue.

## Test function naming

The current names `test`, `dtest`, and `itest` are cryptic — the prefix doesn't
communicate what kind of test body each one expects.

### Current names and what they mean

| Function | Effect | Handler | Use case |
|----------|--------|---------|----------|
| `test` / `skip` | `<pure,kassertion,kscenario>` | `defaultKUnitHandler` | Pure unit tests |
| `dtest` / `dskip` | `<div,exn,console,kassertion,kscenario>` | `defaultKDivHandler` | Recursive/divergent code (parsers, tree walkers) |
| `itest` / `iskip` | `<io,kassertion,kscenario>` | `defaultKIntegrationHandler` | Side-effectful integration tests |

### Proposed renames

| Current | Proposed | Rationale |
|---------|----------|-----------|
| `test` | `unit` | Clearly communicates "pure unit test" |
| `dtest` | `divergent` | Explicit about what `d` stands for |
| `itest` | `integration` | Matches the handler name already |
| `skip` | `unit-skip` | Pairs with `unit` |
| `dskip` | `divergent-skip` | Pairs with `divergent` |
| `iskip` | `integration-skip` | Pairs with `integration` |

Alternatively, keep a single `test` function and unify the handlers so the effect
row is inferred automatically — but that may require deeper changes to how kunit
handles effect polymorphism.
