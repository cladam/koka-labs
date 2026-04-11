## `ls.c` Exit Status Analysis

### How It Works

The global `exit_status` starts at 0 in `main()` and can only escalate upward through the `set_exit_status(bool serious)` function:

- If `serious == true` → sets exit status to **2** (`LS_FAILURE`)
- If `serious == false` and current status is still 0 → sets exit status to **1** (`LS_MINOR_PROBLEM`)
- Once at 2, it stays at 2 — it never goes back down

The key distinction: `serious` is almost always tied to the `command_line_arg` boolean — i.e., **was the failing item something the user explicitly asked for on the command line, or something discovered during traversal?**

---

### Exit 0 — Success

Normal operation. `ls` listed everything it was asked to without any errors. `main()` returns `exit_status` which remains at `EXIT_SUCCESS` (0) if no failure paths were hit.

---

### Exit 1 — Minor Problems (`LS_MINOR_PROBLEM`)

These are **transient or incidental failures** encountered while processing directory contents — things the user didn't explicitly name. Every one of these goes through `file_failure(command_line_arg=false, ...)` or `set_exit_status(false)`:

1. **Cannot stat a file discovered via `readdir`** — The big one. In `gobble_file()`, if `stat`/`lstat` fails on a file found inside a directory (not a command-line argument), you get exit 1. This is the classic race condition: a file existed when `readdir` returned it but was deleted before `stat`. The code even has a comment: *"Failure to stat a command line argument leads to an exit status of 2. For other files, stat failure provokes an exit status of 1."*

2. **Cannot open a subdirectory during `-R` recursion** — `print_dir()` calls `file_failure(command_line_arg, ...)` where `command_line_arg` is `false` for recursively-discovered directories. So `opendir` failing on a subdirectory → exit 1.

3. **Cannot determine device/inode of a subdirectory** — During loop detection in recursive mode, if `fstat`/`stat` fails on a subdirectory that wasn't a command-line arg → exit 1.

4. **`readdir` error while reading a directory** — If `readdir` sets errno to something other than 0 or ENOENT while iterating a subdirectory → exit 1.

5. **Cannot close a directory** — If `closedir` fails on a subdirectory → exit 1.

6. **Cannot canonicalize a path** (for `--hyperlink`) — If `canonicalize_filename_mode` fails on a discovered file → exit 1.

7. **Cannot read a symbolic link** — `get_link_name()` fails via `areadlink_with_size` on a symlink found during traversal → exit 1.

8. **`strcoll` failure during sorting** — In `xstrcoll()`, if `strcoll` sets `errno` (locale-related collation failure), it explicitly calls `set_exit_status(false)` → exit 1. This is the only non-`file_failure` path to exit 1.

---

### Exit 2 — Serious Trouble (`LS_FAILURE`)

These fall into two categories: **fatal errors that exit immediately**, and **runtime errors on command-line arguments**.

#### Immediate exit (via `error(LS_FAILURE, ...)` or `usage(LS_FAILURE)`)

These call `error()` with a non-zero first argument, which terminates the program right away with exit code 2:

1. **Unrecognized option** — `usage(LS_FAILURE)` in the `default` case of the getopt switch.

2. **Invalid `-w` line width** — e.g., `ls -w abc`.

3. **Invalid `-T` tab size** — e.g., `ls -T abc` (via `xnumtoumax(..., LS_FAILURE, ...)`).

4. **Invalid `--time-style` format** — A time style format string with more than one newline.

5. **Unrecognized `--time-style` name** — `x_timestyle_match` is passed `LS_FAILURE` as the error exit code.

6. **`--dired` and `--zero` used together** — Incompatible options.

7. **Memory exhaustion** — `xalloc_die()` is called in three places (hash table init for loop detection, column info allocation, and directory visit tracking). `xalloc_die` exits with `LS_FAILURE` thanks to `initialize_exit_failure(LS_FAILURE)` in `main()`.

#### Non-fatal but serious (via `set_exit_status(true)`)

These happen during runtime but don't abort — `ls` continues and reports what it can:

8. **Cannot stat a command-line argument** — The most common case. If you run `ls nonexistent`, the `stat`/`lstat` in `gobble_file()` fails with `command_line_arg=true` → `file_failure(true, ...)` → exit 2. Note: for command-line args, `gobble_file` also returns 0 immediately, so nothing is printed for that argument.

9. **Cannot open a directory given on the command line** — `print_dir()` calls `file_failure(command_line_arg, ...)` and when `command_line_arg=true`, that's exit 2.

10. **Cannot determine device/inode of a command-line directory** — Same pattern during loop detection.

11. **Recursive loop detected on a command-line directory** — In `print_dir()`, the "not listing already-listed directory" case explicitly calls `set_exit_status(true)` — always serious, regardless of how the directory was encountered.

12. **Cannot canonicalize a command-line path** (with `--hyperlink`).

13. **Cannot read a symbolic link given on the command line**.

14. **`readdir` error on a command-line directory**.

15. **`closedir` failure on a command-line directory**.

---

### The Key Design Insight

The architecture is elegant: almost every runtime failure flows through a single function, `file_failure(bool serious, ...)`, and the `serious` parameter is almost universally just `command_line_arg`. This means the exit code directly reflects **whose fault it is**:

- **Exit 1**: The filesystem changed underneath `ls` while it was working, or something peripheral went wrong. Not really the user's fault.
- **Exit 2**: The user asked for something that doesn't exist or can't be accessed, OR `ls` was invoked incorrectly. The user needs to fix their command.

The only exception to the `serious == command_line_arg` pattern is the recursive loop detection case, which always treats a loop as serious (`true`), and the `xstrcoll` case, which always treats collation failure as minor (`false`).
