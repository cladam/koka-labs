# GNU `ls` Column Layout — Complete Dissection

This document dissects how GNU coreutils `ls` implements its column-based
output layouts (`-C` and `-x` flags). Useful for porting `ls` to another
language (e.g., Koka).

All line references are to `src/ls.c` in the coreutils source tree.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Format Modes](#2-format-modes)
3. [Key Global State](#3-key-global-state)
4. [Data Structures](#4-data-structures)
5. [File Width Calculation](#5-file-width-calculation)
6. [The Core Algorithm: calculate_columns](#6-the-core-algorithm-calculate_columns)
7. [Rendering: print_many_per_line (column-major / -C)](#7-rendering-print_many_per_line--column-major---c)
8. [Rendering: print_horizontal (row-major / -x)](#8-rendering-print_horizontal--row-major---x)
9. [Rendering: print_with_separator (comma / fallback)](#9-rendering-print_with_separator--comma--fallback)
10. [The indent Function](#10-the-indent-function)
11. [Worked Example](#11-worked-example)
12. [Summary for Porting](#12-summary-for-porting)

---

## 1. Overview

The column layout answers one question:

> Given N files with varying display widths and a fixed terminal width,
> what is the maximum number of columns we can use, and how wide should
> each column be?

The answer is found through **brute-force simulation**: try every possible
column count from 1 to max_cols, simulate where each file would land,
track per-column maximum widths, and pick the highest column count whose
total width still fits within the terminal.

Two fill orders:

- **Column-major** (`-C`, `many_per_line`): files fill DOWN column 0, then
  DOWN column 1, etc. This is the default when stdout is a terminal.
- **Row-major** (`-x`, `horizontal`): files fill LEFT-TO-RIGHT across row 0,
  then row 1, etc.

Both use the **same** `calculate_columns()` function; they differ only in
how they map file index to (row, column).

---

## 2. Format Modes (L429-436)

```c
enum format {
    long_format,      /* -l */
    one_per_line,     /* -1 */
    many_per_line,    /* -C  (column-major, default to tty) */
    horizontal,       /* -x  (row-major) */
    with_commas       /* -m */
};
```

The dispatch in `print_current_files()` (L4063-4103):

- `many_per_line` -> if line_length known: `print_many_per_line()`, else fallback
- `horizontal` -> if line_length known: `print_horizontal()`, else fallback
- Both fall back to `print_with_separator(' ')` when `line_length == 0`
- `with_commas` -> always uses `print_with_separator(',')`
- `one_per_line` and `long_format` don't use column logic at all

---

## 3. Key Global State

| Variable        | Type                   | Description                                                    |
|-----------------|------------------------|----------------------------------------------------------------|
| `line_length`   | `size_t`               | Terminal width in columns. Set by `-w` or ioctl. 0 = unlimited |
| `tabsize`       | `size_t`               | Chars per tab stop (`-T`). 0 = no tabs. Default 8              |
| `cwd_file`      | `struct fileinfo *`    | Array of all files in current directory                        |
| `cwd_n_used`    | `idx_t`                | Number of files in `cwd_file`                                  |
| `sorted_file`   | `struct fileinfo **`   | Pointers into `cwd_file`, in sorted order                      |
| `column_info`   | `struct column_info *` | Array of layout hypotheses (one per possible column count)     |
| `max_idx`       | `size_t`               | Maximum possible columns for this terminal width               |

`max_idx` is computed in `decode_switches()` (L2304-2308):

```c
max_idx = line_length / MIN_COLUMN_WIDTH;            // MIN_COLUMN_WIDTH = 3
max_idx += line_length % MIN_COLUMN_WIDTH != 0;      // round up
```

Where `MIN_COLUMN_WIDTH = 3` (1 char for name + 2 chars for separator).
So terminal width 80 gives `max_idx = 27`.

---

## 4. Data Structures

### `struct fileinfo` (relevant fields, L202-242)

```c
struct fileinfo {
    char *name;              /* The file name */
    char *linkname;          /* Symlink target, or NULL */
    struct stat stat;        /* File metadata */
    enum filetype filetype;  /* File type enum */
    int quoted;              /* Whether name needs quoting (-1 = unknown) */
    size_t width;            /* Cached screen width of displayed name */
};
```

The `width` field is lazily cached. It stores the display width of the
quoted file name. It is populated by `update_current_files_info()` (L4004-4017)
before sorting, but only when column output is active:

```c
static void update_current_files_info(void) {
    if (sort_type == sort_width
        || (line_length && (format == many_per_line || format == horizontal)))
    {
        for (idx_t i = 0; i < cwd_n_used; i++) {
            struct fileinfo *f = sorted_file[i];
            f->width = fileinfo_name_width(f);
        }
    }
}
```

### `struct column_info` (L983-988)

```c
struct column_info {
    bool valid_len;    /* Is this column count still feasible? */
    size_t line_len;   /* Sum of all column widths in this layout */
    size_t *col_arr;   /* Array of per-column widths (max width seen in each col) */
};
```

`column_info` is an array indexed from 0 to `max_cols - 1`.
`column_info[i]` represents a hypothetical layout with **`i + 1`** columns.

- `col_arr` has `i + 1` entries -- one width per column
- `line_len` is the sum of all `col_arr` entries
- `valid_len` starts `true` and becomes `false` once `line_len >= line_length`

The `col_arr` arrays are allocated as a **triangle**: `column_info[0]` gets
1 element, `column_info[1]` gets 2, ..., `column_info[n-1]` gets n. Total
allocation is `n*(n+1)/2` size_t values.

---

## 5. File Width Calculation

### `length_of_file_name_and_frills()` (L5052-5083)

This computes the display width of a file entry including optional "frills"
(inode number, block size, security context, type indicator):

```c
static size_t length_of_file_name_and_frills(const struct fileinfo *f) {
    size_t len = 0;

    if (print_inode)
        len += 1 + (format == with_commas
                    ? strlen(umaxtostr(f->stat.st_ino, buf))
                    : inode_number_width);

    if (print_block_size)
        len += 1 + (format == with_commas
                    ? strlen(human_readable(...))
                    : block_size_width);

    if (print_scontext)
        len += 1 + (format == with_commas ? strlen(f->scontext) : scontext_width);

    len += fileinfo_name_width(f);   /* quoted name width */

    if (indicator_style != none) {
        char c = get_type_indicator(f->stat_ok, f->stat.st_mode, f->filetype);
        len += (c != 0);             /* 1 for '/', '*', '@', etc. */
    }

    return len;
}
```

Key points:

- In column modes (non-comma), **fixed-width** fields are used for inode,
  block size, and security context (pre-computed global max widths). This
  ensures columns align properly.
- In comma mode, **variable-width** (actual) values are used since there
  are no columns to align.
- The `+1` before each frill width accounts for the leading space separator.

### `fileinfo_name_width()` (L3866-3872)

```c
static size_t fileinfo_name_width(struct fileinfo const *f) {
    return f->width
           ? f->width
           : quote_name_width(f->name, filename_quoting_options, f->quoted);
}
```

`quote_name_width()` computes the **screen width** of the name after
applying the chosen quoting style. This properly accounts for multibyte
characters (using `mbswidth`), so screen width != byte length.

---

## 6. The Core Algorithm: `calculate_columns` (L5288-5334)

This is the heart of the layout logic. It takes one boolean parameter:
`by_columns` -- `true` for column-major (`-C`), `false` for row-major (`-x`).

### Step 1: Determine `max_cols`

```c
idx_t max_cols = 0 < max_idx && max_idx < cwd_n_used ? max_idx : cwd_n_used;
```

You can never have more columns than files, and you can never have more
columns than the terminal width allows (`max_idx`). Take the smaller.

### Step 2: Initialize via `init_column_info(max_cols)` (L5245-5283)

```c
static void init_column_info(idx_t max_cols) {
    /* ... allocation logic (triangle of col_arr arrays) ... */

    for (idx_t i = 0; i < max_cols; ++i) {
        column_info[i].valid_len = true;
        column_info[i].line_len = (i + 1) * MIN_COLUMN_WIDTH;  // 3 per column
        for (idx_t j = 0; j <= i; ++j)
            column_info[i].col_arr[j] = MIN_COLUMN_WIDTH;      // 3 each
    }
}
```

Every layout hypothesis starts with each column set to `MIN_COLUMN_WIDTH` (3).
So the initial `line_len` for a k-column layout is `3 * k`.

The allocation uses a triangle structure: for `max_cols` hypotheses, you need
`1 + 2 + ... + max_cols = max_cols*(max_cols+1)/2` size_t values total. This
is allocated in one block and parceled out.

### Step 3: Simulate all layouts (the main loop)

For each file, and for each still-valid column count, determine which
column the file would land in, and update that column's width if needed:

```c
for (idx_t filesno = 0; filesno < cwd_n_used; ++filesno) {
    struct fileinfo const *f = sorted_file[filesno];
    size_t name_length = length_of_file_name_and_frills(f);

    for (idx_t i = 0; i < max_cols; ++i) {
        if (column_info[i].valid_len) {

            // Which column does file 'filesno' land in for an (i+1)-column layout?
            idx_t idx = (by_columns
                         ? filesno / ((cwd_n_used + i) / (i + 1))   // column-major
                         : filesno % (i + 1));                       // row-major

            // The last column doesn't need a 2-char separator after it
            size_t real_length = name_length + (idx == i ? 0 : 2);

            // If this file is wider than the current column max, update
            if (column_info[i].col_arr[idx] < real_length) {
                column_info[i].line_len += (real_length - column_info[i].col_arr[idx]);
                column_info[i].col_arr[idx] = real_length;
                column_info[i].valid_len = (column_info[i].line_len < line_length);
            }
        }
    }
}
```

#### The column-major index formula explained

For `by_columns = true`, the formula is:

    idx = filesno / ((cwd_n_used + i) / (i + 1))

Here `i + 1` is the number of columns being tested. The expression
`(cwd_n_used + i) / (i + 1)` is integer ceiling division for
`ceil(cwd_n_used / (i + 1))`, which gives the number of **rows**.
Then `filesno / rows` gives the **column index**.

Example: 10 files, 3 columns:
- rows = ceil(10/3) = 4
- Files 0..3 -> column 0   (0/4=0, 1/4=0, 2/4=0, 3/4=0)
- Files 4..7 -> column 1   (4/4=1, 5/4=1, 6/4=1, 7/4=1)
- Files 8..9 -> column 2   (8/4=2, 9/4=2)

For `by_columns = false` (row-major), it is simply:

    idx = filesno % (i + 1)

File 0 -> col 0, file 1 -> col 1, file 2 -> col 2, file 3 -> col 0, etc.

#### The separator logic

`real_length = name_length + (idx == i ? 0 : 2)` means:

- Non-last columns include a **2-character separator** (two spaces) in
  their width budget.
- The last column (rightmost) does NOT include any separator -- it just
  needs to fit the name.

#### Invalidation as pruning

Once a layout's total `line_len >= line_length`, it is marked invalid
(`valid_len = false`) and skipped for all remaining files. This is a
crucial **optimization**: wide files quickly eliminate high column counts,
so the inner loop gets cheaper as it goes. Correctness is preserved
because columns only ever grow -- once a layout is too wide, no future
file can shrink it.

### Step 4: Pick the best layout

```c
idx_t cols;
for (cols = max_cols; 1 < cols; --cols) {
    if (column_info[cols - 1].valid_len)
        break;
}
return cols;
```

Walk from the highest column count down to 1, and return the first
layout that is still valid. This **maximizes** the number of columns.
Worst case (everything too wide) returns 1.

The chosen column count `cols` also means `column_info[cols - 1]` has
the per-column widths in `col_arr` ready to use for rendering.

---

## 7. Rendering: `print_many_per_line` -- Column-Major / `-C` (L5085-5118)

This is the default `ls` output when stdout is a terminal.

```c
static void print_many_per_line(void) {
    idx_t cols = calculate_columns(true);           // by_columns = true
    struct column_info const *line_fmt = &column_info[cols - 1];

    // Number of rows (rightmost columns may have one fewer entry)
    idx_t rows = cwd_n_used / cols + (cwd_n_used % cols != 0);

    for (idx_t row = 0; row < rows; row++) {
        size_t col = 0;
        idx_t filesno = row;        // start at this row in column 0
        size_t pos = 0;

        while (true) {
            struct fileinfo const *f = sorted_file[filesno];
            size_t name_length = length_of_file_name_and_frills(f);
            size_t max_name_length = line_fmt->col_arr[col++];
            print_file_name_and_frills(f, pos);

            if (cwd_n_used - rows <= filesno)    // no more columns for this row
                break;
            filesno += rows;                     // jump to same row, next column

            indent(pos + name_length, pos + max_name_length);
            pos += max_name_length;
        }
        putchar(eolbyte);
    }
}
```

The traversal is column-major: to move from column C to column C+1 on
the same row, add `rows` to `filesno`. Files are laid out like:

    Col 0    Col 1    Col 2
    file[0]  file[4]  file[8]
    file[1]  file[5]  file[9]
    file[2]  file[6]
    file[3]  file[7]

The condition `cwd_n_used - rows <= filesno` detects when there are no
more columns in this row (handles the "short" rightmost column).

The `indent()` call fills the gap between the end of the printed name
and the start of the next column, using tabs or spaces.

---

## 8. Rendering: `print_horizontal` -- Row-Major / `-x` (L5120-5156)

```c
static void print_horizontal(void) {
    size_t pos = 0;
    idx_t cols = calculate_columns(false);          // by_columns = false
    struct column_info const *line_fmt = &column_info[cols - 1];
    struct fileinfo const *f = sorted_file[0];
    size_t name_length = length_of_file_name_and_frills(f);
    size_t max_name_length = line_fmt->col_arr[0];

    print_file_name_and_frills(f, 0);               // print first entry

    for (idx_t filesno = 1; filesno < cwd_n_used; filesno++) {
        idx_t col = filesno % cols;

        if (col == 0) {
            putchar(eolbyte);                        // new line
            pos = 0;
        } else {
            indent(pos + name_length, pos + max_name_length);
            pos += max_name_length;
        }

        f = sorted_file[filesno];
        print_file_name_and_frills(f, pos);
        name_length = length_of_file_name_and_frills(f);
        max_name_length = line_fmt->col_arr[col];
    }
    putchar(eolbyte);
}
```

Files are laid out like:

    Col 0    Col 1    Col 2
    file[0]  file[1]  file[2]
    file[3]  file[4]  file[5]
    file[6]  file[7]  file[8]
    file[9]

Simply uses `filesno % cols` to determine when to wrap to a new line.

---

## 9. Rendering: `print_with_separator` -- Comma / Fallback (L5160-5195)

Used for `-m` (comma mode) and as a fallback when `line_length` is unknown.
This is a simple greedy line-wrapping algorithm with no column alignment.

It outputs: name, separator char (comma or space), then either a space
(stay on same line) or newline (wrap), depending on whether the next
entry fits.

---

## 10. The `indent` Function (L5200-5216)

Moves the cursor from position `from` to position `to`, using tabs when
possible for efficiency:

```c
static void indent(size_t from, size_t to) {
    while (from < to) {
        if (tabsize != 0 && to / tabsize > (from + 1) / tabsize) {
            putchar('\t');
            from += tabsize - from % tabsize;
        } else {
            putchar(' ');
            from++;
        }
    }
}
```

Uses tabs when they would skip past at least one tab stop. When
`tabsize == 0`, only spaces are used.

---

## 11. Worked Example

Suppose we have 7 files with these display widths and terminal width = 30:

    file_a    (6)
    file_bb   (7)
    file_ccc  (8)
    file_d    (6)
    file_ee   (7)
    file_fff  (8)
    file_g    (6)

max_idx = 30 / 3 = 10, but cwd_n_used = 7, so max_cols = 7.

**Testing 4 columns (column_info[3], by_columns=true):**
- rows = ceil(7/4) = 2
- File 0 (w=6) -> col 0 (0/2=0), needs separator -> real_length = 6+2 = 8
- File 1 (w=7) -> col 0 (1/2=0), real = 7+2 = 9 -> col 0 grows to 9
- File 2 (w=8) -> col 1 (2/2=1), real = 8+2 = 10 -> col 1 = 10
- File 3 (w=6) -> col 1 (3/2=1), real = 6+2 = 8 -> col 1 stays 10
- File 4 (w=7) -> col 2 (4/2=2), real = 7+2 = 9 -> col 2 = 9
- File 5 (w=8) -> col 2 (5/2=2), real = 8+2 = 10 -> col 2 = 10
- File 6 (w=6) -> col 3 (6/2=3), last col -> real = 6+0 = 6

line_len = 9 + 10 + 10 + 6 = 35 >= 30 -> INVALID

**Testing 3 columns (column_info[2], by_columns=true):**
- rows = ceil(7/3) = 3
- File 0 (w=6) -> col 0 (0/3=0), real = 8 -> col 0 = 8
- File 1 (w=7) -> col 0 (1/3=0), real = 9 -> col 0 = 9
- File 2 (w=8) -> col 0 (2/3=0), real = 10 -> col 0 = 10
- File 3 (w=6) -> col 1 (3/3=1), real = 8 -> col 1 = 8
- File 4 (w=7) -> col 1 (4/3=1), real = 9 -> col 1 = 9
- File 5 (w=8) -> col 1 (5/3=1), real = 10 -> col 1 = 10
- File 6 (w=6) -> col 2 (6/3=2), last col -> real = 6

line_len = 10 + 10 + 6 = 26 < 30 -> VALID!

Result: 3 columns, widths [10, 10, 6], rendered as:

    file_a    file_d    file_g
    file_bb   file_ee
    file_ccc  file_fff

The 2-char gap is embedded in the column widths (non-last columns).

---

## 12. Summary for Porting

To port this to Koka, you need:

### Data you need

1. A list of file entries with their computed **display widths** (screen columns, not bytes)
2. The terminal width (`line_length`)
3. A minimum column width constant (3)

### The algorithm (pseudocode)

    function calculate_columns(files, line_length, by_columns):
        n = length(files)
        max_cols = min(line_length / 3 + (if line_length % 3 != 0 then 1 else 0), n)

        // Initialize: for each possible column count k (1..max_cols),
        // track per-column widths and total width
        for k in 1..max_cols:
            layout[k].valid = true
            layout[k].total_width = k * 3
            layout[k].col_widths = array of k elements, each = 3

        // Simulate placing each file
        for filesno in 0..n-1:
            width = display_width(files[filesno])
            for k in 1..max_cols:
                if layout[k].valid:
                    if by_columns:
                        rows = ceil(n / k)
                        col = filesno / rows
                    else:
                        col = filesno % k

                    // Last column has no separator; others add 2
                    real_width = width + (if col == k-1 then 0 else 2)

                    if real_width > layout[k].col_widths[col]:
                        layout[k].total_width += real_width - layout[k].col_widths[col]
                        layout[k].col_widths[col] = real_width
                        layout[k].valid = (layout[k].total_width < line_length)

        // Pick highest valid column count
        for k from max_cols down to 1:
            if layout[k].valid:
                return (k, layout[k].col_widths)
        return (1, [line_length])

    function render_column_major(files, cols, col_widths):
        n = length(files)
        rows = ceil(n / cols)
        for row in 0..rows-1:
            filesno = row
            col = 0
            while filesno < n:
                print files[filesno] padded to col_widths[col]
                filesno += rows
                col += 1
            print newline

    function render_row_major(files, cols, col_widths):
        n = length(files)
        for filesno in 0..n-1:
            col = filesno % cols
            if col == 0 and filesno > 0:
                print newline
            print files[filesno] padded to col_widths[col]
        print newline

### Key subtleties to get right

1. **Column widths include the 2-char separator** for all columns except
   the last. The last column's width is just the file name width.

2. **The column-major index formula** uses ceiling division:
   `rows = ceil(n / k)` then `col = filesno / rows`. This naturally
   handles uneven distributions (rightmost column may be short).

3. **Tab-based indentation**: GNU ls uses tabs (default 8-space tab stops)
   when the gap between the current position and the target position spans
   a tab stop. This is purely an output optimization.

4. **Width calculation must account for multibyte/wide characters**.
   Screen width != byte length. Use wcwidth/wcswidth equivalents.

5. **Quoting affects width**. A file named `my file` displayed as
   `'my file'` is 9 columns wide, not 7.

6. **Invalidation is an optimization, not a correctness requirement**.
   Once a layout is too wide, it stays too wide (columns only grow).
   You could skip the `valid_len` check and just check at the end.

7. **The 2-char separator** is always exactly 2 spaces (or tabs that
   cover that distance). It is NOT variable.