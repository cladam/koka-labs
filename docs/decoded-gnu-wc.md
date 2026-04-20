### Architecture Overview

**1. Command-line options** (lines 70–135, 780–870)

| Short | Long | Flag |
|-------|------|------|
| `-c` | `--bytes` | `print_bytes` |
| `-m` | `--chars` | `print_chars` |
| `-l` | `--lines` | `print_lines` |
| `-w` | `--words` | `print_words` |
| `-L` | `--max-line-length` | `print_linelength` |
| | `--files0-from=F` | NUL-delimited file list |
| | `--total=WHEN` | `auto\|always\|only\|never` |
| | `--debug` | show SIMD info |

Default (no flags) = `lines + words + bytes`.

**2. Four counting modes** — the core `wc()` function (wc.c) selects a strategy based on what's requested:

| Mode | Condition | Strategy |
|------|-----------|----------|
| **Bytes only** | `count_bytes && !count_chars && !print_lines && !count_complicated` | `lseek`/`fstat` shortcut, falls back to raw `read()` loop |
| **Lines (± bytes)** | `!count_chars && !count_complicated` | Delegates to `wc_lines()` — with optional AVX2/AVX512/NEON SIMD acceleration |
| **Multibyte full count** | `MB_CUR_MAX > 1` | `mbrtoc32` loop with word/char/linelength tracking |
| **Single-byte full count** | else | Simple byte-at-a-time loop with `wc_isprint`/`wc_isspace` lookup tables |

**3. SIMD line counting** (wc.c, wc.h)

`wc_lines()` has a fallback C implementation that toggles between a naive per-byte `'\n'` check and `rawmemchr` based on average line length (threshold: 15 bytes/line). The SIMD variants (AVX2, AVX512, NEON) are in separate translation units declared in wc.h.

**4. Output formatting** (wc.c)

`write_counts()` prints counts in a fixed order: lines → words → chars → bytes → linelength, each right-justified to `number_width` (computed from `fstat` sizes of all input files).

**5. File handling** (wc.c)

`wc_file()` opens the file (or uses stdin for `-`/null), calls `wc()`, and closes.

**6. Totals tracking** — global `uintmax_t` accumulators with overflow detection via `ckd_add`.

---

### Key design decisions relevant to a Koka port

1. **Effect-based I/O**: The C code mixes buffered `read()` calls with `lseek`/`fstat`. In Koka, you'd model file reading as an effect, and the byte-only fast path (fstat/lseek) as an optimization handler.

2. **Word definition**: A word is a maximal run of non-whitespace. The `in_word` boolean flip-flops, counting word *starts*. This is a simple state machine — a great fit for a fold over a byte/char stream.

3. **Multibyte vs single-byte**: The C code branches on `MB_CUR_MAX`. In Koka you'd likely always work with UTF-8 strings, but could optimize the ASCII-only path.

4. **SIMD line counting**: Not portable to Koka directly. The C fallback in `wc_lines()` is what you'd implement. Koka's inline-C facility (like your `ls-inline.c`) could wrap SIMD if needed later.

5. **`--total` mode**: An enum with 4 variants — maps directly to a Koka `type total-mode`.

6. **The `fstat` shortcut for byte counting**: When only `-c` is requested, wc avoids reading the file entirely if it can determine size from metadata. This is a meaningful optimization worth preserving.
