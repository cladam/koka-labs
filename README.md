# koka-labs

Exploring the [Koka](https://koka-lang.github.io/koka/doc/index.html) language by rebuilding GNU coreutils — starting with `ls`.

The goal is to follow the [GNU coreutils philosophy](https://github.com/coreutils/coreutils/blob/master/src/ls.c), reimplemented piece by piece in Koka's effect-typed, functional style.

## Building

```bash
git clone https://github.com/cladam/koka-labs.git
cd koka-labs
```

### Requirements

- macOS / Linux POSIX
- Koka the language installed: `curl -sSL https://github.com/koka-lang/koka/releases/latest/download/install.sh | sudo sh`

## Running

### From source
```bash
./exec ls              # build and run ls (debug)
./exec ls /tmp         # with arguments
./exec ls -ar /tmp     # with flags
./exec -O ls           # optimised build

# Build and produce a binary
koka -O2 src/ls.kk 2>&1 | tee build.log
BINARY=$(grep '^created :' build.log | awk '{print $3}')
cp "$BINARY" koka-ls
chmod +x koka-ls
```

### From built binary
```bash
./koka-ls

# See implemented flags with --help
```

### macOS: downloaded binary

macOS Gatekeeper quarantines binaries downloaded from the internet. After downloading a release, run:

```bash
xattr -d com.apple.quarantine koka-ls
```

---

## Programs

| Program | Description |
|---------|-------------|
| `ls.kk` | List directory contents |

## ls — Progress

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
- [ ] Exit codes (0 success, 1 minor problems, 2 serious trouble)

### Phase 2 — Which files are listed
[GNU §10.1.1](https://www.gnu.org/software/coreutils/manual/html_node/Which-files-are-listed.html)
- [x] `-a, --all` — in directories, do not ignore names starting with `.`
- [x] `-A, --almost-all` — like `-a`, but ignore `.` and `..`
- [ ] `-B, --ignore-backups` — ignore entries ending with `~`
- [ ] `-d, --directory` — list directories themselves, not their contents
- [ ] `-H, --dereference-command-line` — follow symlinks listed on the command line
- [ ] `--dereference-command-line-symlink-to-dir` — follow command-line symlinks that point to directories
- [ ] `--hide=PATTERN` — hide matching entries (overridden by `-a`/`-A`)
- [ ] `-I, --ignore=PATTERN` — do not list entries matching pattern
- [ ] `-L, --dereference` — show information for link target, not the link itself
- [ ] `-R, --recursive` — list subdirectories recursively

### Phase 3 — What information is listed
[GNU §10.1.2](https://www.gnu.org/software/coreutils/manual/html_node/What-information-is-listed.html) ·
[GNU §10.1.5](https://www.gnu.org/software/coreutils/manual/html_node/Formatting-file-timestamps.html)
- [ ] `-l, --format=long` — long format (type, mode, links, owner, group, size, timestamp, name)
- [ ] `-g` — long format, omit owner
- [ ] `-o` — long format, omit group (equivalent to `-l -G`)
- [ ] `-G, --no-group` — suppress group in long listing
- [ ] `-n, --numeric-uid-gid` — long format with numeric user and group IDs
- [ ] `--author` — with `-l`, print author of each file
- [ ] `-i, --inode` — print inode number of each file
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
- [ ] `-S, --sort=size` — sort by file size, largest first
- [ ] `-t, --sort=time` — sort by modification time, newest first
- [ ] `-U, --sort=none` — do not sort; list entries in directory order
- [ ] `-v, --sort=version` — natural sort of version numbers within text
- [ ] `-X, --sort=extension` — sort alphabetically by file extension
- [ ] `--sort=name` — sort by name (default; explicit override)
- [ ] `--sort=width` — sort by printed width of file name
- [ ] `-c, --time=ctime` — use/sort by status change time
- [ ] `-u, --time=atime` — use/sort by access time
- [ ] `--time=WORD` — select timestamp (atime, ctime, mtime, birth)
- [ ] `-f` — do not sort; enable `-a` and `-U`
- [ ] `--group-directories-first` — group directories before files

### Phase 5 — General output formatting
[GNU §10.1.4](https://www.gnu.org/software/coreutils/manual/html_node/General-output-formatting.html)
- [x] `-1` — one file per line
- [x] `-C, --format=vertical` — list in columns, sorted vertically (default for terminal)
- [x] `-F, --classify` — append indicator (`/` dir, `*` exec, `@` symlink, `=` socket, `|` FIFO, `>` door)
- [x] `-p, --indicator-style=slash` — append `/` to directories
- [ ] `-m, --format=commas` — comma-separated list, filling width
- [ ] `-x, --format=across` — like `-C`, but sorted across rather than down columns
- [ ] `--format=WORD` — select format (across, commas, long, single-column, verbose, vertical)
- [ ] `--file-type, --indicator-style=file-type` — like `-F`, but do not append `*`
- [ ] `--indicator-style=WORD` — none, slash, file-type, classify
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
