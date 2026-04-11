# Decoded: GNU `ls` (coreutils)

Summary of [MaiZure's decoded GNU ls](https://www.maizure.org/projects/decoded-gnu-coreutils/ls.html),
a source-code walkthrough of `ls.c` from coreutils 8.3.

## At a Glance

| Metric | Value |
|---|---|
| Lines of code | 5 309 |
| Principal syscalls | `opendir()`, `readdir()` |
| Support syscalls | `closedir()`, `fstat()` |
| Options | 83 (40 short, 43 long) |
| History | Spiritually linked with LISTF from CTSS (1963); added to Shellutils Oct 1992; 653 revisions |

> The `ls` command is the most complex (read: over-engineered) utility in coreutils.

## Architecture Overview

The program follows four phases: **Setup → Parsing → Execution → Output**.

### 1. Setup (~1 000 lines of globals, structs, enums)

Three entry points exist depending on invocation (`ls`, `dir`, or `vdir`), each
setting `ls_mode` to control default options.

**Key structs:**

- `fileinfo` — holds data for a single file entry
- `column_info` — metadata for column layout
- `pending` — linked list of directories still to process
- `ignore_pattern` — file-name patterns to skip
- `bin_str` / `color_ext_type` — colour indicator data

**Key enums:**

- `filetype` — 10 file types
- `format` — 5 output formats
- `sort_type` — 7 sorting categories
- `ignore_mode` — 3 ways to ignore special files
- `Dereference_symlink` — 4 symlink strategies
- `time_types` — 3 time types (modified, created, access)
- `indicator_style` — 4 colour indicator styles

Initialisation sets default flags, quoting style, and reads column/tab sizes
from the environment.

### 2. Parsing

`decode_switches()` (579 lines) is the largest helper. It iterates over every
CLI argument to answer:

- What is the overall output format?
- What specific formats are needed (time, inode, blocks, …)?
- Are colours used?
- How is output sorted and ordered?
- Is the search recursive?
- Does the search follow links?

Many options simply override each other rather than conflicting (e.g. `-l`
overrides `-1`).

**Explicit failure checks:**

- Invalid line or tab size
- Invalid time-style format

**Colour parsing:** `parse_ls_color()` reads the `LS_COLORS` env var using a
state machine, character by character. Each entry (e.g. `di=1:`) has a label,
`=`, an ANSI encoding, and a separator.

### 3. Execution

After parsing, execution proceeds as:

1. Set up colours from `LS_COLORS` / `COLORTERM`
2. Finalise symlink handling; prepare for recursive search if needed
3. Allocate the file table and clear the sort vector
4. Queue the initial directory (user-specified or cwd)

#### Processing directories

For each queued directory:

1. `opendir()` to open the directory
2. Check for cycles (already-visited directories)
3. Clear the file table
4. Print directory name header (if appropriate)
5. Loop `readdir()` until all files processed:
   - Check if file type should be ignored
   - Add file to table via `gobble_file()` (332 lines — the 2nd largest helper)
   - Handle pending signals
6. `closedir()`
7. Sort the file table
8. Extract child directories into the pending list
9. Print via `print_current_files()`

#### `gobble_file()` — adding a file to the table

Depending on the requested format, a subset of:

- Ensure table capacity
- Set file reference and verify quoting needs
- Construct full file name
- `stat()` or `lstat()` (for symlinks)
- Check capabilities and security context / ACL
- Construct link name (if link)
- Compute widths: owner, group, author, security context, major/minor device,
  size, inode
- Return total size in blocks

### 4. Printing output

Output format varies: columns, single list, horizontal wrap, long format, etc.

The deepest call chain for long format:

```
print_current_files()
  └─ print_long_format()
       └─ print_name_with_quoting()
            └─ quote_name()          → fwrite() to stdout
                 └─ print_color_indicator()
                      └─ put_indicator()  → fwrite() (colour escapes)
```

**Failure cases during output:**

- Unable to open directory (permissions, doesn't exist)
- Unable to `stat()` file
- Improper hyperlink formatting
- Error reading directory
- Unable to close directory
- Unable to read a followed symlink

## Helper Functions (selected)

| Function | Purpose |
|---|---|
| `calculate_columns()` | Column count based on screen size |
| `sort_files()` | Sort file table using active `sort_type` |
| `gobble_file()` | Add file to table (332 lines) |
| `decode_switches()` | Parse all CLI switches (579 lines) |
| `parse_ls_color()` | Initialise colour scheme from `LS_COLORS` |
| `print_long_format()` | Output `-l` style lines |
| `print_many_per_line()` | Output `-C` style columns |
| `get_type_indicator()` | Return type indicator char for `-F` |
| `quote_name()` | Quote and write file name |
| `signal_setup()` | Initialise / restore signal handlers |

## References

- [Source code (coreutils 8.3)](http://github.com/MaiZure/coreutils-8.3/tree/master/src/ls.c)
- [Code walkthrough](http://www.maizure.org/projects/decoded-gnu-coreutils/ls_walkthrough.html)
- [GNU manual](https://www.gnu.org/software/coreutils/manual/html_node/ls-invocation.html)
- [POSIX spec](http://pubs.opengroup.org/onlinepubs/9699919799/utilities/ls.html)
- [Linux man page](http://man7.org/linux/man-pages//man1/ls.1.html)
