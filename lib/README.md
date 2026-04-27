# Dependencies

Koka does not yet have a package manager. External libraries are managed as
git submodules under `lib/` and made available to the compiler with the `-i` flag.

## Current dependencies

| Library | Description | Repository |
|---------|-------------|------------|
| [klap](klap/) | CLI argument parsing | [cladam/klap](https://github.com/cladam/klap) |
| [kunit](kunit/) | Lightweight xUnit-style test framework | [cladam/kunit](https://github.com/cladam/kunit) |

## Adding a dependency

```sh
git submodule add https://github.com/<owner>/<repo>.git lib/<name>
```

Then compile with `-ilib/<name>`:

```sh
koka -ilib/klap src/ls.kk
```

Multiple libraries are passed as separate `-i` flags:

```sh
koka -ilib/klap -ilib/kunit src/ls.kk
```

## Updating dependencies

Update all submodules to their latest remote commits:

```sh
git submodule update --remote
```

Or update a single dependency:

```sh
git submodule update --remote lib/klap
```

## Cloning the project

When cloning koka-labs for the first time, initialise submodules:

```sh
git clone --recursive https://github.com/cladam/koka-labs.git
```

Or if already cloned:

```sh
git submodule update --init --recursive
```
