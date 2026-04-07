# koka-labs

Exploring the [Koka](https://koka-lang.github.io/koka/doc/index.html) language by rebuilding GNU coreutils — starting with `ls`.

The goal is to follow the [GNU coreutils philosophy](https://github.com/coreutils/coreutils/blob/master/src/ls.c), reimplemented piece by piece in Koka's effect-typed, functional style.

## Running

```bash
./exec ls              # build and run ls (debug)
./exec ls /tmp         # with arguments
./exec ls -ar /tmp     # with flags
./exec -O ls           # optimized build
```

## Programs

| Program | Description |
|---------|-------------|
| `ls.kk` | List directory contents |

## ls — Progress

### Phase 1 — Foundation
- [x] Default directory listing (`.` when no args)
- [x] Hide dotfiles by default
- [x] Alphabetical sort
- [x] Show basenames, not full paths
- [x] `-a` — show all entries including `.` and `..`
- [x] `-A` — like `-a`, but exclude `.` and `..`
- [x] `-r` — reverse sort order
- [x] Combined flags (`-ar`, `-ra`)
- [x] `--` stops flag parsing
- [x] Multiple path arguments — `ls dir1 dir2`
- [x] Distinguish files vs directories in arguments
- [x] Error handling (`ls: cannot access ...`)

### Phase 2 — Output Formats
- [x] `-1` — one entry per line
- [ ] `-l` — long format (permissions, owner, group, size, date, name)
- [x] `-C` — multi-column (default when stdout is a terminal)
- [ ] `-m` — comma-separated list
- [ ] `-x` — list entries by lines instead of by columns
- [ ] `--format=WORD` — select format (across, commas, long, single-column, verbose, vertical)

### Phase 3 — Sorting & Filtering
- [ ] `-t` — sort by modification time
- [ ] `-S` — sort by size
- [ ] `-U` — unsorted (directory order)
- [ ] `-v` — natural sort of version numbers within text
- [ ] `-X` — sort alphabetically by entry extension
- [ ] `--sort=WORD` — select sort (none, size, time, version, extension, name, width)
- [ ] `-B` — ignore backups (`*~`)
- [ ] `-I PATTERN` — ignore glob pattern
- [ ] `--hide=PATTERN` — hide matching entries (overridden by `-a`/`-A`)
- [ ] `-f` — do not sort, enable `-aU`

### Phase 4 — Indicators, Recursion & Directories
- [x] `-F` — append file type indicator (`/`, `*`, `@`, etc.)
- [x] `-p` — append `/` to directories
- [ ] `--file-type` — like `-F`, but do not append `*`
- [ ] `--indicator-style=WORD` — none, slash, file-type, classify
- [ ] `-R` — recursive listing
- [ ] `-d` — list directories themselves, not their contents
- [ ] `--group-directories-first` — group directories before files

### Phase 5 — Long Format Enhancements
- [ ] `-g` — like `-l`, but omit owner
- [ ] `-o` — like `-l`, but omit group information
- [ ] `-G, --no-group` — suppress group in long listing
- [ ] `-n, --numeric-uid-gid` — numeric user and group IDs
- [ ] `--author` — print author of each file with `-l`
- [ ] `-i, --inode` — print index number of each file
- [ ] `-s, --size` — print allocated size of each file in blocks
- [ ] `-k, --kibibytes` — default to 1024-byte blocks for `-s`
- [ ] `-h, --human-readable` — sizes like 1K 234M 2G
- [ ] `--si` — like `-h`, but use powers of 1000
- [ ] `--block-size=SIZE` — scale sizes when printing

### Phase 6 — Time Options
- [ ] `-c` — show/sort by ctime (status change time)
- [ ] `-u` — show/sort by access time
- [ ] `--time=WORD` — select timestamp (atime, ctime, mtime, birth)
- [ ] `--time-style=TIME_STYLE` — time/date format with `-l`
- [ ] `--full-time` — like `-l --time-style=full-iso`

### Phase 7 — Symlinks, Quoting & Color
- [ ] `-H` — dereference symlinks on command line
- [ ] `-L` — dereference all symlinks
- [ ] `--color[=WHEN]` — colorized output
- [ ] `--hyperlink[=WHEN]` — hyperlink file names
- [ ] `-N, --literal` — print entry names without quoting
- [ ] `-Q, --quote-name` — enclose entry names in double quotes
- [ ] `-b, --escape` — C-style escapes for nongraphic characters
- [ ] `--quoting-style=WORD` — select quoting style
- [ ] `-q, --hide-control-chars` — print `?` instead of nongraphic characters

### Phase 8 — Remaining & Polish
- [ ] `-w, --width=COLS` — set output width (0 = no limit)
- [ ] `-T, --tabsize=COLS` — assume tab stops at each COLS instead of 8
- [ ] `--zero` — end each output line with NUL, not newline
- [ ] `-Z, --context` — print security context of each file
- [ ] `-D, --dired` — generate output for Emacs dired mode
- [ ] Exit codes matching GNU conventions (0, 1, 2)
