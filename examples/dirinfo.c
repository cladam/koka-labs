/*
 * dirinfo.c — C23 directory info utility
 *
 * Demonstrates: lstat (inode, size), opendir/readdir (listing).
 * Functional style: pure functions return values, no global state.
 *
 * Build:  cc -std=c23 -Wall -Wextra -o dirinfo examples/dirinfo.c
 * Usage:  ./dirinfo [directory]
 */
#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

// ---------------------------------------------------------------------------
// Types — small structs to return multiple values cleanly
// ---------------------------------------------------------------------------

typedef struct {
    bool    ok;
    ino_t   inode;
    off_t   size;
} stat_result;

typedef struct {
    char    name[256];
    ino_t   inode;        // from readdir's d_ino (free — no extra syscall)
} dir_entry;

typedef struct {
    dir_entry  *entries;
    size_t      count;
    int         error;    // errno on failure, 0 on success
} dir_listing;

// ---------------------------------------------------------------------------
// Pure-ish functions — each does one thing, returns a value
// ---------------------------------------------------------------------------

// Stat a path via lstat (doesn't follow symlinks).
// Returns inode + size, or ok=false on error.
[[nodiscard]]
static stat_result get_stat(const char *path) {
    struct stat st = {};
    if (lstat(path, &st) < 0) {
        return (stat_result){ .ok = false };
    }
    return (stat_result){
        .ok    = true,
        .inode = st.st_ino,
        .size  = st.st_size,
    };
}

// Read a directory into a heap-allocated array of dir_entry.
// Caller owns the returned .entries pointer (free it when done).
// Skips "." and ".." — same as the Koka version.
[[nodiscard]]
static dir_listing read_directory(const char *path) {
    DIR *dp = opendir(path);
    if (dp == nullptr) {
        return (dir_listing){ .error = errno };
    }

    size_t cap = 64;
    size_t len = 0;
    dir_entry *entries = malloc(cap * sizeof *entries);
    if (entries == nullptr) {
        closedir(dp);
        return (dir_listing){ .error = ENOMEM };
    }

    for (struct dirent *de; (de = readdir(dp)) != nullptr; ) {
        // Skip . and ..
        if (de->d_name[0] == '.' &&
            (de->d_name[1] == '\0' ||
             (de->d_name[1] == '.' && de->d_name[2] == '\0'))) {
            continue;
        }

        // Grow if needed
        if (len == cap) {
            cap *= 2;
            dir_entry *tmp = realloc(entries, cap * sizeof *tmp);
            if (tmp == nullptr) {
                free(entries);
                closedir(dp);
                return (dir_listing){ .error = ENOMEM };
            }
            entries = tmp;
        }

        // Copy entry — d_ino comes free from readdir
        snprintf(entries[len].name, sizeof entries[len].name, "%s", de->d_name);
        entries[len].inode = de->d_ino;
        len++;
    }

    closedir(dp);
    return (dir_listing){ .entries = entries, .count = len, .error = 0 };
}

// Build "dir/name" into a caller-provided buffer.
// Returns false if the path would be truncated.
[[nodiscard]]
static bool join_path(char *buf, size_t bufsz,
                      const char *dir, const char *name) {
    int n = snprintf(buf, bufsz, "%s/%s", dir, name);
    return n >= 0 && (size_t)n < bufsz;
}

// ---------------------------------------------------------------------------
// Main — orchestrates the pure functions
// ---------------------------------------------------------------------------

int main(int argc, char *argv[]) {
    const char *dir = argc > 1 ? argv[1] : ".";

    // 1. Read the directory
    dir_listing listing = read_directory(dir);
    if (listing.error != 0) {
        fprintf(stderr, "dirinfo: cannot open '%s': %s\n",
                dir, strerror(listing.error));
        return 1;
    }

    // 2. For each entry, stat for size (inode we already have from readdir)
    printf("%10s  %10s  %s\n", "inode", "size", "name");
    printf("%10s  %10s  %s\n", "-----", "----", "----");

    for (size_t i = 0; i < listing.count; i++) {
        dir_entry *e = &listing.entries[i];
        char full[1024];

        if (!join_path(full, sizeof full, dir, e->name)) {
            fprintf(stderr, "dirinfo: path too long: %s/%s\n", dir, e->name);
            continue;
        }

        stat_result sr = get_stat(full);
        if (sr.ok) {
            printf("%10llu  %10lld  %s\n",
                   (unsigned long long)sr.inode,
                   (long long)sr.size,
                   e->name);
        } else {
            printf("%10llu  %10s  %s\n",
                   (unsigned long long)e->inode,  // fallback: readdir's d_ino
                   "?",
                   e->name);
        }
    }

    free(listing.entries);
    return 0;
}
