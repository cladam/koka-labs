/*
 * vercmp.c — version-aware file name comparison in C23
 *
 * Re-implementation of gnulib's filevercmp algorithm, the same one used by
 * GNU ls -v and sort -V.  This is also what koka-ls uses via C FFI.
 *
 * The algorithm has three layers:
 *
 *   1. Special priority:
 *      empty < "." < ".." < dotfiles < everything else
 *
 *   2. Extension stripping (two-pass):
 *      Remove a suffix matching (\.[A-Za-z~][A-Za-z0-9~]*)*$
 *      Compare without it; if equal, re-compare with full strings.
 *      This makes "hello-8.txt" sort before "hello-8.2.txt".
 *
 *   3. Debian verrevcmp (the core):
 *      Walk both strings left-to-right, alternating:
 *        a) Non-digit run: compare byte-by-byte with custom ordering:
 *              ~  <  end-of-string  <  letters  <  other bytes
 *        b) Digit run: skip leading zeros, compare numerically
 *           (longer digit string = bigger number, then by digit value)
 *
 * Build:  gcc -std=c2x -Wall -Wextra -pedantic -o vercmp tests/vercmp.c
 * Usage:  ./vercmp                      # run built-in test suite
 *         ./vercmp "a1" "a10"           # compare two strings
 */
#include <ctype.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ---------------------------------------------------------------------------
// Layer 3: Custom byte ordering for non-digit comparison
// ---------------------------------------------------------------------------
//
// The Debian spec says, in non-digit runs:
//   - tilde (~) sorts before everything, even end-of-string
//   - end-of-string sorts before all real bytes except tilde
//   - letters sort before non-letters (by ASCII value)
//   - non-letter, non-digit bytes sort after letters (offset by 256)
//
// Digits get order 0 here because they're handled separately.

static int order(const char *s, size_t pos, size_t len) {
    if (pos == len) return -1;                    // end-of-string
    unsigned char c = (unsigned char)s[pos];
    if (isdigit(c))  return 0;                    // handled in digit phase
    if (isalpha(c))  return c;                    // letters: 65–122
    if (c == '~')    return -2;                   // tilde: before everything
    return (int)c + 256;                          // other: after letters
}

// ---------------------------------------------------------------------------
// Layer 3: Debian verrevcmp — the core comparison loop
// ---------------------------------------------------------------------------
//
// Alternates between two phases:
//
// Phase A — Non-digit run:
//   Compare byte-by-byte using order().  Both positions advance in lockstep.
//   When both positions reach a digit (or end), move to Phase B.
//
// Phase B — Digit run:
//   Skip leading zeros.  Compare digit-by-digit, tracking the first
//   difference.  Whichever string has more remaining digits is larger.
//   If same length, use the first digit difference.

static int verrevcmp(const char *s1, size_t n1, const char *s2, size_t n2) {
    size_t p1 = 0, p2 = 0;
    while (p1 < n1 || p2 < n2) {
        // Phase A: non-digit bytes
        while ((p1 < n1 && !isdigit((unsigned char)s1[p1]))
            || (p2 < n2 && !isdigit((unsigned char)s2[p2]))) {
            int c1 = order(s1, p1, n1);
            int c2 = order(s2, p2, n2);
            if (c1 != c2) return c1 - c2;
            p1++;
            p2++;
        }
        // Phase B: digit run — skip leading zeros
        while (p1 < n1 && s1[p1] == '0') p1++;
        while (p2 < n2 && s2[p2] == '0') p2++;
        // Compare digit-by-digit, noting first difference
        int first_diff = 0;
        while (p1 < n1 && p2 < n2
            && isdigit((unsigned char)s1[p1])
            && isdigit((unsigned char)s2[p2])) {
            if (!first_diff)
                first_diff = s1[p1] - s2[p2];
            p1++;
            p2++;
        }
        // More remaining digits → larger number
        if (p1 < n1 && isdigit((unsigned char)s1[p1])) return 1;
        if (p2 < n2 && isdigit((unsigned char)s2[p2])) return -1;
        if (first_diff) return first_diff;
    }
    return 0;
}

// ---------------------------------------------------------------------------
// Layer 2: Extension stripping — find where the suffix begins
// ---------------------------------------------------------------------------
//
// A suffix is the longest tail matching: (\.[A-Za-z~][A-Za-z0-9~]*)*$
// But the suffix must not consume the entire non-empty string.
//
// Examples:
//   "hello-8.txt"           → prefix "hello-8",  suffix ".txt"
//   "hello-8.2.txt"         → prefix "hello-8.2", suffix ".txt"
//   "foo.tar.gz"            → prefix "foo",       suffix ".tar.gz"
//   "hello-8.0.12.tar.gz"   → prefix "hello-8.0.12", suffix ".tar.gz"
//   "hello-8.2"             → prefix "hello-8.2", suffix "" (dot not followed by letter)

static size_t file_prefixlen(const char *s, size_t len) {
    size_t prefixlen = 0;
    for (size_t i = 0; ; ) {
        if (i == len) return prefixlen;
        i++;
        prefixlen = i;  // everything before a suffix candidate is prefix
        // Try to match (\.[A-Za-z~][A-Za-z0-9~]*)* from position i
        while (i + 1 < len && s[i] == '.'
            && (isalpha((unsigned char)s[i + 1]) || s[i + 1] == '~')) {
            for (i += 2; i < len && (isalnum((unsigned char)s[i]) || s[i] == '~'); i++)
                continue;
        }
    }
}

// ---------------------------------------------------------------------------
// Layer 1: Top-level filevercmp — special priorities + two-pass
// ---------------------------------------------------------------------------

static int filevercmp(const char *a, size_t alen, const char *b, size_t blen) {
    // Empty strings sort first
    if (!alen) return blen ? -1 : 0;
    if (!blen) return 1;

    // Special priority for leading '.'
    if (a[0] == '.') {
        if (b[0] != '.') return -1;
        // "." sorts before everything
        if (alen == 1) return (blen == 1) ? 0 : -1;
        if (blen == 1) return 1;
        // ".." sorts next
        if (a[1] == '.' && alen == 2) return (b[1] == '.' && blen == 2) ? 0 : -1;
        if (b[1] == '.' && blen == 2) return 1;
    } else if (b[0] == '.') {
        return 1;
    }

    // Two-pass: first without suffix, then with
    size_t apfx = file_prefixlen(a, alen);
    size_t bpfx = file_prefixlen(b, blen);
    bool one_pass = (apfx == alen && bpfx == blen);

    int result = verrevcmp(a, apfx, b, bpfx);
    if (result || one_pass) return result;
    return verrevcmp(a, alen, b, blen);
}

// Convenience: compare NUL-terminated strings
static int filevercmp_str(const char *a, const char *b) {
    return filevercmp(a, strlen(a), b, strlen(b));
}

// ---------------------------------------------------------------------------
// qsort comparator — for sorting an array of strings by version
// ---------------------------------------------------------------------------

static int cmp_version(const void *a, const void *b) {
    const char *sa = *(const char **)a;
    const char *sb = *(const char **)b;
    return filevercmp_str(sa, sb);
}

// ---------------------------------------------------------------------------
// Test harness
// ---------------------------------------------------------------------------

static int tests_run    = 0;
static int tests_passed = 0;

static void check(const char *label, const char *a, const char *b, int expected_sign) {
    tests_run++;
    int result = filevercmp_str(a, b);
    int actual_sign = (result < 0) ? -1 : (result > 0) ? 1 : 0;
    bool ok = (actual_sign == expected_sign);
    if (ok) {
        tests_passed++;
    } else {
        const char *sign_str[] = { "<", "==", ">" };
        printf("  FAIL: %s\n", label);
        printf("        \"%s\" vs \"%s\"\n", a, b);
        printf("        expected %s, got %s (raw %d)\n",
               sign_str[expected_sign + 1], sign_str[actual_sign + 1], result);
    }
}

static void run_tests(void) {
    printf("Running filevercmp tests...\n\n");

    // --- Basic numeric ordering ---
    check("a1 < a2",              "a1",    "a2",    -1);
    check("a2 < a10",             "a2",    "a10",   -1);
    check("a1 < a13",             "a1",    "a13",   -1);
    check("a13 < a120",           "a13",   "a120",  -1);
    check("a1 == a1",             "a1",    "a1",     0);

    // --- Leading zeros: numerically equal (filevercmp skips leading zeros) ---
    check("00 == 0",              "00",    "0",      0);
    check("01 < 010 (different zero count)",
                                  "01",    "010",   -1);
    check("09 > 0 (9 > 0)",       "09",    "0",      1);
    check("000 == 00",            "000",   "00",     0);

    // --- Empty string and dots ---
    check("empty < .",            "",      ".",     -1);
    check(". < ..",               ".",     "..",    -1);
    check(".. < .hidden",         "..",    ".hidden", -1);
    check(".hidden < visible",    ".hidden", "visible", -1);
    check("empty == empty",       "",      "",       0);

    // --- Letters sort before non-letters (in non-digit runs) ---
    check("az < a%",              "az",    "a%",    -1);
    check("foo7a < foo07 (letter before dot)",
                                  "foo7a.7z", "foo07.7z", -1);

    // --- Tilde sorts before everything (within verrevcmp) ---
    // Note: empty string has top-level priority in filevercmp,
    // so empty < ~ at the filevercmp level.
    check("~ > empty (special priority)", "~", "",    1);
    check("1~ < 1",               "1~",    "1",     -1);
    check("1~ < 1%",              "1~",    "1%",    -1);

    // --- Extension stripping ---
    check("hello-8.txt < hello-8.2.txt",
                                  "hello-8.txt", "hello-8.2.txt", -1);
    check("hello-8.2.txt < hello-8.10.txt",
                                  "hello-8.2.txt", "hello-8.10.txt", -1);

    // --- Real-world versioned files ---
    check("gcc-10.fc9.tar.gz < gcc-10.8.12.fc9.tar.bz2",
                                  "gcc_10.fc9.tar.gz", "gcc_10.8.12.7rc2.fc9.tar.bz2", -1);
    check("file-1.0 < file-1.1",   "file-1.0", "file-1.1", -1);
    check("file-1.9 < file-1.10",  "file-1.9", "file-1.10", -1);
    check("lib-2.0.so < lib-2.1.so", "lib-2.0.so", "lib-2.1.so", -1);

    // --- Mixed ---
    check("jan1 < jan2",          "jan1",  "jan2",  -1);
    check("jan2 < jan10",         "jan2",  "jan10", -1);

    printf("\nResults: %d/%d passed\n", tests_passed, tests_run);
}

// ---------------------------------------------------------------------------
// Demo: sort a list of file names by version
// ---------------------------------------------------------------------------

static void run_demo(void) {
    const char *files[] = {
        "file-1.10.txt",
        "file-1.2.txt",
        "file-1.1.txt",
        ".hidden",
        "file-1.0.txt",
        "..",
        ".",
        "README.md",
        "file-1.9.txt",
        "file-1.20.txt",
    };
    size_t n = sizeof files / sizeof files[0];

    printf("\nVersion sort demo:\n\n");
    printf("  %-20s  →  %-20s\n", "unsorted", "version-sorted");
    printf("  %-20s     %-20s\n", "--------", "--------------");

    // Copy so we can sort without affecting the original display
    const char *sorted[sizeof files / sizeof files[0]];
    memcpy(sorted, files, sizeof files);
    qsort(sorted, n, sizeof sorted[0], cmp_version);

    for (size_t i = 0; i < n; i++) {
        printf("  %-20s  →  %-20s\n",
               i < n ? files[i] : "",
               i < n ? sorted[i] : "");
    }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

int main(int argc, char *argv[]) {
    if (argc == 3) {
        // Compare two strings from the command line
        int r = filevercmp_str(argv[1], argv[2]);
        const char *op = (r < 0) ? "<" : (r > 0) ? ">" : "==";
        printf("\"%s\" %s \"%s\"  (raw: %d)\n", argv[1], op, argv[2], r);
        return 0;
    }

    if (argc != 1) {
        fprintf(stderr, "Usage: %s [string1 string2]\n", argv[0]);
        return 1;
    }

    run_tests();
    run_demo();
    return tests_passed == tests_run ? 0 : 1;
}
