/*
 * wordsort.c — sort words using decorate-sort-undecorate in C23
 *
 * Demonstrates the same pattern used in ls.kk for -S / -t sorting:
 *   1. Decorate:   attach a sort key to each element
 *   2. Sort:       compare by key, with a tiebreaker
 *   3. Undecorate: strip the key, keep the result
 *
 * Build:  gcc -std=c2x -Wall -Wextra -o wordsort tests/wordsort.c
 * Usage:  ./wordsort
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ---------------------------------------------------------------------------
// Step 1: Decorate — a word paired with its sort key (length)
// ---------------------------------------------------------------------------

typedef struct {
    const char *word;   // the original word (like e.fst in Koka)
    size_t      len;    // the sort key    (like e.thd — the "size")
} decorated;

// ---------------------------------------------------------------------------
// Step 2: Sort — compare by key, tiebreak by name
//
// In Koka this is:
//   match cmp(b.thd, a.thd) { Eq -> cmp(a.fst, b.fst); c -> c }
//
// In C we write a qsort comparator that does the same thing:
//   - Primary:   longer words first  (descending length)
//   - Tiebreak:  alphabetical        (ascending name)
// ---------------------------------------------------------------------------

static int cmp_decorated(const void *a, const void *b) {
    const decorated *da = a;
    const decorated *db = b;

    // Primary: descending by length  (like cmp(b.thd, a.thd))
    if (db->len != da->len) {
        return (db->len > da->len) ? 1 : -1;
    }

    // Tiebreak: ascending by name    (like cmp(a.fst, b.fst))
    return strcmp(da->word, db->word);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

int main(void) {
    const char *phrase = "koka-ls is a clone of GNU ls in Koka";

    printf("Input:  \"%s\"\n\n", phrase);

    // --- Tokenize into words ---
    // (strtok mutates, so work on a copy)
    char buf[256];
    snprintf(buf, sizeof buf, "%s", phrase);

    const char *words[64];
    size_t count = 0;
    for (char *tok = strtok(buf, " "); tok != nullptr; tok = strtok(nullptr, " ")) {
        words[count++] = tok;
    }

    // --- Step 1: Decorate — attach the sort key (word length) ---
    decorated items[64];
    for (size_t i = 0; i < count; i++) {
        items[i] = (decorated){
            .word = words[i],
            .len  = strlen(words[i]),   // like get-size(path) in Koka
        };
    }

    // --- Step 2: Sort by key with tiebreaker ---
    qsort(items, count, sizeof items[0], cmp_decorated);

    // --- Step 3: Undecorate — just print the words, drop the key ---
    printf("Sorted: ");
    for (size_t i = 0; i < count; i++) {
        printf("%s%s", items[i].word, (i + 1 < count) ? " " : "");
    }
    printf("\n\n");

    // --- Show the decoration for educational purposes ---
    printf("%-12s  %s\n", "word", "length");
    printf("%-12s  %s\n", "----", "------");
    for (size_t i = 0; i < count; i++) {
        printf("%-12s  %zu\n", items[i].word, items[i].len);
    }

    return 0;
}
