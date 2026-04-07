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
- [x] `-a` — show entries starting with `.`
- [x] `-r` — reverse sort order
- [x] Combined flags (`-ar`, `-ra`)
- [x] `--` stops flag parsing
- [ ] Multiple path arguments — `ls dir1 dir2`
- [ ] Distinguish files vs directories in arguments
- [ ] Error handling (`ls: cannot access ...`)

### Phase 2 — Output Formats
- [ ] `-1` — one entry per line (currently the only mode)
- [ ] `-l` — long format (permissions, owner, group, size, date, name)
- [ ] `-C` — multi-column (default when stdout is a terminal)
- [ ] `-m` — comma-separated

### Phase 3 — Sorting & Filtering
- [ ] `-t` — sort by modification time
- [ ] `-S` — sort by size
- [ ] `-U` — unsorted (directory order)
- [ ] `-A` — almost all (like `-a` but exclude `.` and `..`)
- [ ] `-I PATTERN` — ignore glob pattern
- [ ] `-B` — ignore backups (`*~`)

### Phase 4 — Indicators & Recursion
- [x] `-F` — append file type indicator (`/`, `*`, `@`, etc.)
- [ ] `-p` — append `/` to directories
- [ ] `-R` — recursive listing
- [ ] `-d` — list directory itself, don't descend

### Phase 5 — Polish
- [ ] `-h` — human-readable sizes
- [ ] `--color` — colorized output
- [ ] `-H` — dereference symlinks on command line
- [ ] `-L` — dereference all symlinks
- [ ] Exit codes matching GNU conventions
