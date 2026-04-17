# The Recursive (`-R` / `--recursive`) Machinery in `ls.c`

Recursion in `ls` is **not** implemented via actual C recursion (no function
calls itself). Instead it uses an **iterative work-queue** pattern with a
singly-linked list of pending directories. There are five key pieces.

---

## 1. The `pending` struct (line 377–386)

This is the work-queue node. Each entry holds:

- `name` — the directory path to list (or `NULL` for a "marker" entry used
  for loop-detection cleanup)
- `realname` — the symlink's real name, if the directory was reached through
  a symbolic link
- `command_line_arg` — whether this directory was given directly on the
  command line (this controls exit-status severity: `true` => exit 2 on
  failure, `false` => exit 1)
- `next` — pointer to the next pending entry

The global `pending_dirs` is the head of this linked list. It acts as a
**stack** (LIFO) — new entries are prepended to the front.

---

## 2. `queue_directory()` (line 2936–2945)

This is the function that adds a directory to the work queue. It simply
`xmalloc`s a new `struct pending`, copies the name and realname strings,
records whether it was a command-line argument, and pushes it onto the
front of `pending_dirs`.

It is called from three places:

1. **`main()`** — when no files are given on the command line, it queues `"."`.
2. **`extract_dirs_from_files()`** — the key recursive step; queues
   subdirectories found inside a directory that was just listed.
3. **`extract_dirs_from_files()` again** — inserts a `NULL`-named marker
   entry for loop-detection bookkeeping (see section 5 below).

Because `queue_directory` prepends (stack push), and
`extract_dirs_from_files` iterates the sorted file list in **reverse**
order, the directories end up being processed in the correct (sorted)
forward order.

---

## 3. `extract_dirs_from_files()` (line 3678–3726)

This is the heart of the recursive discovery. It is called after a
directory's contents have been read and sorted. It scans the file list
for subdirectories and queues them for later processing.

Here is what it does step by step:

1. **Insert a marker entry** — If loop detection is active and we have a
   parent dirname, it first calls `queue_directory(NULL, dirname, false)`.
   This marker has `name == NULL`. When the main loop later dequeues this
   marker, it knows the parent directory is fully processed and can be
   removed from the active-directory set (see section 5).

2. **Queue subdirectories in reverse order** — It iterates `sorted_file[]`
   from the end to the beginning. For each entry that `is_directory()`
   returns true for (and that isn't `.` or `..`), it calls
   `queue_directory()` with the full path (dirname + filename). Because
   the list is a stack and we iterate in reverse, the first directory
   alphabetically ends up on top and gets processed first.

3. **Compact the file table** — After queuing, it removes all
   `arg_directory` entries from the `sorted_file[]` array, compacting
   the remaining entries. This is so the directory names themselves are
   not printed in the current listing — they'll be printed as headers
   when their contents are listed later.

The `ignore_dot_and_dot_dot` flag is `true` whenever `dirname != NULL`
(i.e., always except for the initial command-line processing pass). This
prevents infinite recursion into `.` and `..`.

---

## 4. `print_dir()` (line 2952–3114)

This function does the actual work of listing one directory. It is called
from the main loop for each pending directory entry. Here is its flow:

1. **Open the directory** with `opendir()`. On failure, report an error
   and return (exit status depends on `command_line_arg`).

2. **Loop detection** (only when `-R` is active, i.e., `LOOP_DETECT` is
   true):
   - `stat` the directory to get its device and inode numbers.
   - Call `visit_dir(dev, ino)` which tries to insert the dev/ino pair
     into the `active_dir_set` hash table.
   - If it was **already present**, we have found a filesystem loop
     (e.g., a symlink cycle). Print a warning, set exit status to 2
     (always serious), and return without listing.
   - If insertion succeeded, push the dev/ino onto the `dev_ino_obstack`
     stack for later cleanup.

3. **Print the directory header** — If recursive mode is on, or if
   multiple directories are being listed, print the directory name
   followed by a colon (e.g., `./subdir:`).

4. **Read all entries** — Loop over `readdir()`, calling `gobble_file()`
   for each non-ignored entry. Note that `gobble_file` is called with
   `command_line_arg = false` here, meaning any stat failures on
   individual files inside the directory produce exit status 1 (minor),
   not 2.

5. **Close the directory** — Call `closedir()`, report error if it fails.

6. **Sort** the collected file entries.

7. **Recurse** — If `recursive` is true, call
   `extract_dirs_from_files(name, false)`. This queues all subdirectories
   found in this directory onto the pending list. Note `command_line_arg`
   is `false` here, so all recursively-discovered directories are treated
   as non-command-line arguments.

8. **Print** — Optionally print a "total NNN" line (for `-l`), then call
   `print_current_files()` to output the listing.

---

## 5. The main loop (line 1790–1819 in `main()`)

After initial setup and processing of command-line arguments, `main()`
enters the core loop:

```
while (pending_dirs)
{
    thispend = pending_dirs;
    pending_dirs = pending_dirs->next;

    if (LOOP_DETECT)
    {
        if (thispend->name == NULL)
        {
            // This is a marker entry.
            // Pop the dev/ino from the obstack and remove it
            // from active_dir_set. This directory is done.
            struct dev_ino di = dev_ino_pop ();
            struct dev_ino *found = hash_remove (active_dir_set, &di);
            dev_ino_free (found);
            free_pending_ent (thispend);
            continue;
        }
    }

    print_dir (thispend->name, thispend->realname,
               thispend->command_line_arg);

    free_pending_ent (thispend);
    print_dir_name = true;
}
```

This is a simple work-queue drain:

- Pop the front entry off `pending_dirs`.
- If it is a **marker entry** (`name == NULL`), handle loop-detection
  cleanup: pop the corresponding dev/ino off the obstack and remove it
  from the hash set. This means "we are done with that parent directory,
  it is no longer 'active'."
- Otherwise, call `print_dir()` to list the directory. Inside
  `print_dir()`, if `-R` is active, `extract_dirs_from_files()` will
  push new entries (and a new marker) onto `pending_dirs`.
- Free the pending entry.
- Repeat until the queue is empty.

---

## 6. Loop Detection — How It All Fits Together

When `-R` is active, `main()` creates a hash table (`active_dir_set`)
keyed by `(device, inode)` pairs, and an obstack (`dev_ino_obstack`)
that acts as a stack of those pairs.

The lifecycle of a directory in the loop detector:

1. `print_dir()` is called for directory X.
2. `visit_dir(X.dev, X.ino)` inserts X into `active_dir_set`. If it was
   already there, we have a loop — abort with exit 2.
3. `dev_ino_push(X.dev, X.ino)` pushes X onto the obstack.
4. X's contents are read and sorted.
5. `extract_dirs_from_files()` first pushes a **marker** (name=NULL,
   realname=X) onto `pending_dirs`, then pushes X's subdirectories.
6. The main loop processes X's subdirectories (which may themselves
   recurse).
7. Eventually the main loop reaches the marker entry for X.
8. `dev_ino_pop()` retrieves X's dev/ino from the obstack.
9. `hash_remove(active_dir_set, ...)` removes X from the active set.
10. X is no longer considered "active" — if we encounter the same dev/ino
    again via a different path, it won't be flagged as a loop.

The marker entries and the obstack together implement a **depth-tracking
mechanism**: directories are pushed when entered and popped when all
their descendants have been fully processed. This correctly handles the
case where the same directory is legitimately reachable via two different
(non-cyclic) paths — it won't be in the active set when encountered the
second time, because the first traversal will have already completed and
removed it.

The classic loop scenario this detects:

```
mkdir loop; cd loop; ln -s ../loop sub; ls -RL
```

Here, `sub` points back to `loop`. When `ls -RL` descends into `sub`,
it finds the same dev/ino as `loop` (which is still in the active set
because we're still inside it). `visit_dir()` returns `true` (match
found), and `print_dir()` prints:

```
ls: ./sub: not listing already-listed directory
```

and sets exit status to 2 (always treated as serious, regardless of
whether the looping directory was a command-line argument).

---

## Summary: The Recursive Flow

```
main()
  |
  |-- queue initial directories (from argv or ".")
  |
  `-- while (pending_dirs):
        |
        |-- [if marker] -> pop dev/ino from active set, continue
        |
        `-- print_dir(name):
              |
              |-- opendir(name)
              |-- [if -R] visit_dir() -> add to active set (or detect loop)
              |-- [if -R] dev_ino_push()
              |-- readdir loop -> gobble_file() for each entry
              |-- closedir()
              |-- sort_files()
              |-- [if -R] extract_dirs_from_files():
              |     |-- queue marker (NULL, name)
              |     `-- queue each subdirectory
              `-- print_current_files()
```

Key design properties:

- **Iterative, not recursive** — Uses a linked-list work queue instead
  of call-stack recursion. This means `ls -R` on a very deep directory
  tree won't overflow the C stack.
- **Depth-first** — Because `queue_directory` prepends (stack/LIFO),
  subdirectories are processed before sibling directories at the same
  level, giving depth-first traversal.
- **Sorted within each level** — `extract_dirs_from_files` iterates in
  reverse sorted order and prepends, so subdirectories within a single
  parent are visited in forward sorted order.
- **Loop-safe** — The `active_dir_set` hash table tracks directories
  currently on the "call stack" (ancestors of the current directory).
  Marker entries in the pending queue ensure directories are removed
  from the active set at exactly the right time.
- **Memory-efficient** — Only the pending queue and the active-dir hash
  table persist across directories. Each directory's file table
  (`cwd_file`) is cleared and reused for the next directory.