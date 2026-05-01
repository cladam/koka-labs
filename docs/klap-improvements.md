# klap improvements needed for kls

## Summary

Migrating `kls` (GNU ls clone) from hand-rolled argument parsing to klap.
Three features are missing from klap that prevent a clean migration.

---

## Gap 1: Action flags (flag sets value on an option)

**Status:** `arg-action` field exists on `arg-def` but is **never used by the parser**.

GNU ls has many short flags that are syntactic sugar for setting a value on
a shared option. For example, `-S`, `-t`, `-U`, `-X`, `-v` all set the
sort mode, and `-c`, `-u` set the time type. In the current hand-rolled
parser each flag directly mutates the options struct.

### Flags that need this

| Flag | Target option | Value set     |
|------|--------------|---------------|
| `-S` | `sort`       | `size`        |
| `-t` | `sort`       | `time`        |
| `-U` | `sort`       | `none`        |
| `-X` | `sort`       | `extension`   |
| `-v` | `sort`       | `version`     |
| `-c` | `time`       | `ctime`       |
| `-u` | `time`       | `atime`       |
| `-p` | `indicator-style` | `slash`  |
| `-l` | `format`     | `long`        |
| `-1` | `format`     | `one`         |
| `-C` | `format`     | `columns`     |
| `-g` | `format`     | `long`        |
| `-n` | `format`     | `long`        |
| `-o` | `format`     | `long`        |

### Why this matters: last-wins semantics

GNU ls uses **last-wins** override: `ls -1l` uses long format (`-l` last),
while `ls -l1` uses one-per-line (`-1` last). Similarly `ls -St` sorts by
time (`-t` last), `ls -tS` sorts by size (`-S` last).

If action flags use `add-value` (append) on the target option, then
`get-one` (which returns the last value) gives last-wins for free.

### Proposed API

Change `arg-action` from `maybe<string>` to `maybe<(string, string)>`:
- first element: target option name
- second element: value to set

```koka
// In arg.kk
arg-action : maybe<(string, string)> = Nothing

pub fun action( a : arg-def, target : string, val_ : string ) : arg-def
  a(arg-action = Just((target, val_)))
```

Wire it into the parser: when a flag with an action is encountered, call
`m.add-value(target, value)` instead of (or in addition to) `m.set-flag`.

### Usage in kls

```koka
// Hidden options that receive values from action flags
.arg(option("sort").hidden.default-value("name")
      .values(["name","size","time","extension","version","width","none"]))
.arg(option("time").hidden.default-value("mtime")
      .values(["mtime","atime","ctime"]))
.arg(option("format").hidden.default-value("columns"))
.arg(option("indicator-style").hidden.default-value("none")
      .values(["none","slash","file-type","classify"]))

// Action flags that set values on the hidden options
.arg(flag-short("", 'S').no-long.action("sort", "size").help("sort by file size"))
.arg(flag-short("", 't').no-long.action("sort", "time").help("sort by time"))
.arg(flag-short("", 'U').no-long.action("sort", "none").help("do not sort"))
.arg(flag-short("", 'v').no-long.action("sort", "version").help("version sort"))
.arg(flag-short("", 'X').no-long.action("sort", "extension").help("sort by extension"))
.arg(flag-short("", 'c').no-long.action("time", "ctime"))
.arg(flag-short("", 'u').no-long.action("time", "atime"))
.arg(flag-short("", 'l').no-long.action("format", "long"))
.arg(flag-short("", '1').no-long.action("format", "one"))
.arg(flag-short("", 'C').no-long.action("format", "columns"))
.arg(flag-short("", 'p').no-long.action("indicator-style", "slash"))
```

---

## Gap 2: Multi-action flags (one flag sets multiple options)

Some ls flags set multiple options at once:

| Flag | Effects |
|------|---------|
| `-f` | sets `filter=all`, `sort=none`, `format=default` |
| `-g` | sets `format=long`, `no-owner=true` |
| `-n` | sets `format=long`, `numeric-ids=true` |
| `-o` | sets `format=long`, `no-group=true` |

### Proposed API

Allow a list of actions per flag:

```koka
arg-actions : list<(string, string)> = []

pub fun action( a : arg-def, target : string, val_ : string ) : arg-def
  a(arg-actions = Cons((target, val_), a.arg-actions))
```

This way `.action("format", "long").action("no-owner", "true")` chains naturally.

In the parser, when a flag is encountered, iterate over all its actions and
call `m.add-value(target, value)` for each.

### Alternative: post-parse implies

If multi-action feels too complex, these can be handled post-parse:

```koka
val m = app.parse-or-exit(get-args())
// Post-parse: -g implies -l + no-owner
val m2 = if m.get-flag("g") then m.add-value("format", "long") else m
```

This works but loses last-wins ordering (`ls -gl` vs `ls -lg`).

---

## Gap 3: Optional option values

`--classify[=WHEN]` can be used in three ways:
- `--classify` → defaults to "always"
- `--classify=auto` → explicit value
- No flag at all → classify is off

klap currently treats `--classify` (no `=`) as:
- A flag (no value) if defined as `ArgFlag`
- Requiring a next-arg value if defined as `ArgOption`

Neither handles the optional-value case.

### Proposed API

Add an `arg-optional-value` field with a default:

```koka
arg-optional-value : maybe<string> = Nothing  // default when flag used without =

pub fun optional-value( a : arg-def, default : string ) : arg-def
  a(arg-optional-value = Just(default))
```

In the parser, when processing a long option without `=`:
- If `arg-optional-value` is `Just(default)`, use the default value
  (don't consume the next argument)
- Otherwise, require a value as usual

### Usage in kls

```koka
.arg(option("classify")
      .optional-value("always")
      .values(["always","yes","force","auto","tty","never","no","none"])
      .help("append indicator to entries"))
```

---

## What works today (no klap changes needed)

These ls features map cleanly to klap as-is:

| Feature | klap API |
|---------|----------|
| `-a` / `--all` | `flag-short("all", 'a')` |
| `-A` / `--almost-all` | `flag-short("almost-all", 'A')` |
| `-B` / `--ignore-backups` | `flag-short("ignore-backups", 'B')` |
| `-d` / `--directory` | `flag-short("directory", 'd')` |
| `-F` / `--classify` | see Gap 3 (needs optional value) |
| `-G` / `--no-group` | `flag-short("no-group", 'G')` |
| `-i` / `--inode` | `flag-short("inode", 'i')` |
| `-r` / `--reverse` | `flag-short("reverse", 'r')` |
| `-R` / `--recursive` | `flag-short("recursive", 'R')` |
| `--author` | `flag("author")` |
| `--group-directories-first` | `flag("group-directories-first")` |
| `--sort=WORD` | `option("sort").values([...])` |
| `--time=WORD` | `option("time").values([...])` |
| `--indicator-style=WORD` | `option("indicator-style").values([...])` |
| `-I PATTERN` / `--ignore=PATTERN` | `option-short("ignore", 'I').multiple` |
| `--hide=PATTERN` | `option("hide").multiple` |
| `--file-type` | `flag("file-type")` |
| `--numeric-uid-gid` | see Gap 2 (sets format+numeric) |
| Positional `FILE...` | `positional("FILE").multiple` |
| `--help` / `--version` | built-in |
| Combined short flags `-arF` | built-in |
| `--` separator | built-in |

---

## Implementation priority

1. **Action flags** (Gap 1) — highest impact, unblocks most short flags
2. **Optional option values** (Gap 3) — needed for `--classify[=WHEN]`
3. **Multi-action flags** (Gap 2) — nice to have, can workaround post-parse

## Migration note: `-a` / `-A` mutual exclusivity

With action flags, model these as action flags on a hidden `filter` option:
- `-a` → `action("filter", "all")`
- `-A` → `action("filter", "almost-all")`

Then `get-one("filter")` returns whichever was last. No explicit override
groups needed — last-wins falls out naturally from `add-value` + `get-one`.
