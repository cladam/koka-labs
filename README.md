# koka-labs

Exploring the [Koka](https://koka-lang.github.io/koka/doc/index.html) language by rebuilding GNU ls.

The goal is to follow the [GNU coreutils philosophy](https://github.com/coreutils/coreutils/blob/master/src/ls.c), reimplemented piece by piece in Koka's effect-typed, functional style.

## Building

```bash
git clone https://github.com/cladam/koka-labs.git
cd koka-labs
```

### Requirements

- macOS / Linux POSIX
- coreutils installed
- Koka the language installed: `curl -sSL https://github.com/koka-lang/koka/releases/latest/download/install.sh | sudo sh`

## Running

### From source
```bash
# use the bash script to run kls
./exec-ls ls              # build and run ls (debug)
./exec-ls ls /tmp         # with arguments
./exec-ls ls -ar /tmp     # with flags

###

# Build and produce a binary
koka src/ls.kk -o kls
chmod +x kls
```

> **Note:** Optimised builds (`koka -O1`/`-O2`) currently segfault due to a Koka compiler bug in `kk_cctx_copy` when stacking effect handlers. Use debug builds for now.

### From built binary
```bash
./kls
# See implemented flags with --help
```

### macOS: downloaded binary

macOS Gatekeeper quarantines binaries downloaded from the internet. After downloading a release, run:

```bash
xattr -d com.apple.quarantine koka-ls
```

### Testing

I am testing kls with both integration and unit tests, see [tests/test-ls.kk](tests/test-ls.kk).
Integration tests use the `bio` effect to capture `list-dir` output into a string buffer instead of printing to stdout, making output assertions straightforward.

Run all tests with the helper script:
```bash
./test-ls
```

The testing framework is [kunit](https://github.com/cladam/kunit), managed as a git submodule under `lib/kunit/`.

---

## Programs

| Program | Description |
|---------|-------------|
| `ls.kk` | List directory contents |

## ls — Progress

### Phase 0 - Infrastructure

- [x] Create a testing framework based on XUnit
- [x] Create a CI workflow and publish binaries

### Phase 1 — Foundation
- [x] Default directory listing (`.` when no args)
- [x] Hide dotfiles by default
- [x] Alphabetical sort (default)
- [x] Show basenames, not full paths
- [x] Combined short flags (`-ar`, `-ra`)
- [x] `--` stops flag parsing
- [x] Multiple path arguments — `ls dir1 dir2`
- [x] Distinguish files vs directories in arguments
- [x] Error handling (`ls: cannot access ...`)
- [x] Exit codes (0 success, 1 minor problems, 2 serious trouble)

### Phase 2 — Which files are listed

[GNU §10.1.1](https://www.gnu.org/software/coreutils/manual/html_node/Which-files-are-listed.html)
- [x] `-a, --all` — in directories, do not ignore names starting with `.`
- [x] `-A, --almost-all` — like `-a`, but ignore `.` and `..`
- [x] `-B, --ignore-backups` — ignore entries ending with `~`
- [x] `-d, --directory` — list directories themselves, not their contents
- [ ] `-H, --dereference-command-line` — follow symlinks listed on the command line
- [ ] `--dereference-command-line-symlink-to-dir` — follow command-line symlinks that point to directories
- [x] `--hide=PATTERN` — hide matching entries (overridden by `-a`/`-A`)
- [x] `-I, --ignore=PATTERN` — do not list entries matching pattern
- [ ] `-L, --dereference` — show information for link target, not the link itself
- [x] `-R, --recursive` — list subdirectories recursively

### Phase 3 — What information is listed

[GNU §10.1.2](https://www.gnu.org/software/coreutils/manual/html_node/What-information-is-listed.html) ·
[GNU §10.1.5](https://www.gnu.org/software/coreutils/manual/html_node/Formatting-file-timestamps.html)
- [x] `-l, --format=long` — long format (type, mode, links, owner, group, size, timestamp, name)
- [x] `-g` — long format, omit owner
- [x] `-o` — long format, omit group (equivalent to `-l -G`)
- [x] `-G, --no-group` — suppress group in long listing
- [x] `-n, --numeric-uid-gid` — long format with numeric user and group IDs
- [x] `--author` — with `-l`, print author of each file
- [x] `-i, --inode` — print inode number of each file
- [ ] `-s, --size` — print allocated size of each file in blocks
- [ ] `-h, --human-readable` — print sizes like 1K 234M 2G (powers of 1024)
- [ ] `--si` — like `-h`, but use powers of 1000
- [ ] `--block-size=SIZE` — scale sizes by SIZE when printing
- [ ] `--full-time` — long format with `--time-style=full-iso`
- [ ] `--time-style=STYLE` — time/date format with `-l` (full-iso, long-iso, iso, locale, +FORMAT)
- [ ] `-Z, --context` — print security context of each file
- [ ] `-D, --dired` — generate output for Emacs dired mode

### Phase 4 — Sorting the output

[GNU §10.1.3](https://www.gnu.org/software/coreutils/manual/html_node/Sorting-the-output.html)
- [x] `-r, --reverse` — reverse whatever the sorting method is
- [x] `-S, --sort=size` — sort by file size, largest first
- [x] `-t, --sort=time` — sort by modification time, newest first
- [x] `-U, --sort=none` — do not sort; list entries in directory order
- [x] `-v, --sort=version` — natural sort of version numbers within text
- [x] `-X, --sort=extension` — sort alphabetically by file extension
- [x] `--sort=name` — sort by name (default; explicit override)
- [x] `--sort=width` — sort by printed width of file name
- [x] `-c, --time=ctime` — use/sort by status change time
- [x] `-u, --time=atime` — use/sort by access time
- [x] `--time=WORD` — select timestamp (atime, ctime, mtime, birth)
- [x] `-f` — do not sort; enable `-a` and `-U`
- [x] `--group-directories-first` — group directories before files

### Phase 5 — General output formatting

[GNU §10.1.4](https://www.gnu.org/software/coreutils/manual/html_node/General-output-formatting.html)
- [x] `-1` — one file per line
- [x] `-C, --format=vertical` — list in columns, sorted vertically (default for terminal)
- [x] `-F, --classify` — append indicator (`/` dir, `*` exec, `@` symlink, `=` socket, `|` FIFO, `>` door)
- [x] `-p, --indicator-style=slash` — append `/` to directories
- [ ] `-m, --format=commas` — comma-separated list, filling width
- [ ] `-x, --format=across` — like `-C`, but sorted across rather than down columns
- [ ] `--format=WORD` — select format (across, commas, long, single-column, verbose, vertical)
- [x] `--file-type, --indicator-style=file-type` — like `-F`, but do not append `*`
- [x] `--indicator-style=WORD` — none, slash, file-type, classify
- [ ] `-k, --kibibytes` — default to 1024-byte blocks for `-s` and per-directory totals
- [ ] `--color[=WHEN]` — colorize output (none, auto, always)
- [ ] `--hyperlink[=WHEN]` — hyperlink file names (none, auto, always)
- [ ] `-T, --tabsize=COLS` — assume tab stops at each COLS instead of 8
- [ ] `-w, --width=COLS` — set output width (0 = no limit)
- [ ] `--zero` — end each line with NUL, not newline (implies `-1`, `--color=none`, `-N`)

### Phase 6 — Formatting the file names

[GNU §10.1.6](https://www.gnu.org/software/coreutils/manual/html_node/Formatting-the-file-names.html)
- [ ] `-b, --escape` — C-style backslash escapes for nongraphic characters
- [ ] `-N, --literal` — print entry names without quoting
- [ ] `-q, --hide-control-chars` — print `?` instead of nongraphic characters
- [ ] `-Q, --quote-name` — enclose entry names in double quotes
- [ ] `--quoting-style=WORD` — literal, shell, shell-always, shell-escape, shell-escape-always, c, escape, clocale, locale
- [ ] `--show-control-chars` — print nongraphic characters as-is (default for non-terminal)
