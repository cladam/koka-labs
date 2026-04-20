/*
 * ls-inline.c - File type detection for ls -F flag.
 * Copyright (C) 2026 Claes Adamsson <claes.adamsson@gmail.com>
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE 
 * SOFTWARE.
*/


/*
  Uses lstat for symlinks (does not follow the link),
  stat for everything else (follows symlinks).

  This isn't included in Koka's standard library, but was easy enough to
  write in C and import into Koka. It is used by the ls.kk implementation
  of the ls -F flag.

  Note: kk_stat_t and kk_posix_stat are static in kklib/src/os.c and not
  exported through kklib.h, so we define our own equivalents here.
*/
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fnmatch.h>

static bool kk_os_is_symlink(kk_string_t path, kk_context_t* ctx) {
  struct stat st = { 0 };
  int err = 0;
  kk_with_string_as_qutf8_borrow(path, cpath, ctx) {
    if (lstat(cpath, &st) < 0) err = errno;
  }
  kk_string_drop(path, ctx);
  if (err != 0) return false;
  return ((st.st_mode & S_IFMT) == S_IFLNK);
}

static bool kk_os_is_executable(kk_string_t path, kk_context_t* ctx) {
  struct stat st = { 0 };
  int err = 0;
  kk_with_string_as_qutf8_borrow(path, cpath, ctx) {
    if (stat(cpath, &st) < 0) err = errno;
  }
  kk_string_drop(path, ctx);
  if (err != 0) return false;
  return ((st.st_mode & S_IFDIR) == 0 && (st.st_mode & S_IXUSR) != 0);
}

static bool kk_os_is_fifo(kk_string_t path, kk_context_t* ctx) {
  struct stat st = { 0 };
  int err = 0;
  kk_with_string_as_qutf8_borrow(path, cpath, ctx) {
    if (stat(cpath, &st) < 0) err = errno;
  }
  kk_string_drop(path, ctx);
  if (err != 0) return false;
  return ((st.st_mode & S_IFMT) == S_IFIFO);
}

static bool kk_os_is_socket(kk_string_t path, kk_context_t* ctx) {
  struct stat st = { 0 };
  int err = 0;
  kk_with_string_as_qutf8_borrow(path, cpath, ctx) {
    if (stat(cpath, &st) < 0) err = errno;
  }
  kk_string_drop(path, ctx);
  if (err != 0) return false;
  return ((st.st_mode & S_IFMT) == S_IFSOCK);
}

static kk_string_t kk_os_stat_error(kk_string_t path, kk_context_t* ctx) {
  struct stat st = { 0 };
  int err = 0;
  kk_with_string_as_qutf8_borrow(path, cpath, ctx) {
    if (lstat(cpath, &st) < 0) err = errno;
  }
  kk_string_drop(path, ctx);
  if (err != 0) return kk_string_alloc_from_qutf8(strerror(err), ctx);
  return kk_string_empty();
}

static kk_unit_t kk_os_eprint(kk_string_t msg, kk_context_t* ctx) {
  kk_with_string_as_qutf8_borrow(msg, cmsg, ctx) {
    fputs(cmsg, stderr);
  }
  kk_string_drop(msg, ctx);
  return kk_Unit;
}

// Checks if stdout is a terminal
static bool kk_os_isatty_stdout(kk_context_t* ctx) {
  return isatty(STDOUT_FILENO) != 0;
}

static bool kk_os_fnmatch(kk_string_t pattern, kk_string_t name, kk_context_t* ctx) {
  bool result = false;
  kk_with_string_as_qutf8_borrow(pattern, cpat, ctx) {
    kk_with_string_as_qutf8_borrow(name, cname, ctx) {
      result = (fnmatch(cpat, cname, 0) == 0);
    }
  }
  kk_string_drop(pattern, ctx);
  kk_string_drop(name, ctx);
  return result;
}

/*
  readdir-raw: Read a directory and return all entries (excluding . and ..)
  as a single string in the format "inode\tname\ninode\tname\n...".
  This lets Koka get both the name and d_ino from readdir without
  needing to construct complex Koka data structures from C.
  Returns empty string on error.
*/
#include <dirent.h>

static kk_string_t kk_os_readdir_raw(kk_string_t dirpath, kk_context_t* ctx) {
  DIR* dp = NULL;
  kk_with_string_as_qutf8_borrow(dirpath, cpath, ctx) {
    dp = opendir(cpath);
  }
  kk_string_drop(dirpath, ctx);
  if (dp == NULL) return kk_string_empty();

  // Dynamic buffer
  size_t cap = 4096;
  size_t len = 0;
  char* buf = (char*)kk_malloc(cap, ctx);
  if (buf == NULL) { closedir(dp); return kk_string_empty(); }

  struct dirent* de;
  while ((de = readdir(dp)) != NULL) {
    // Skip . and ..
    if (de->d_name[0] == '.' && (de->d_name[1] == '\0' ||
        (de->d_name[1] == '.' && de->d_name[2] == '\0'))) continue;

    // Format: "inode\tname\n"
    char line[4096];
    int n = snprintf(line, sizeof(line), "%llu\t%s\n",
                     (unsigned long long)de->d_ino, de->d_name);
    if (n < 0 || (size_t)n >= sizeof(line)) continue;

    // Grow buffer if needed
    while (len + (size_t)n + 1 > cap) {
      cap *= 2;
      buf = (char*)kk_realloc(buf, cap, ctx);
      if (buf == NULL) { closedir(dp); return kk_string_empty(); }
    }
    memcpy(buf + len, line, (size_t)n);
    len += (size_t)n;
  }
  closedir(dp);

  buf[len] = '\0';
  kk_string_t result = kk_string_alloc_from_qutf8(buf, ctx);
  kk_free(buf, ctx);
  return result;
}

/*
  get-size: Get the file size in bytes via lstat.
  Returns 0 on error. Uses lstat so symlinks return their own size.
*/
static kk_integer_t kk_os_get_size(kk_string_t path, kk_context_t* ctx) {
  struct stat st = { 0 };
  int err = 0;
  kk_with_string_as_qutf8_borrow(path, cpath, ctx) {
    if (lstat(cpath, &st) < 0) err = errno;
  }
  kk_string_drop(path, ctx);
  if (err != 0) return kk_integer_from_int(0, ctx);
  return kk_integer_from_int64((int64_t)st.st_size, ctx);
}

/*
  get-mtime/get-atime/get-ctime: Get file timestamps as nanoseconds since epoch.
  Returns seconds * 1_000_000_000 + nanoseconds for full sub-second precision.
  GNU ls uses nanoseconds for sorting, so we need this to match its ordering.
  Returns 0 on error. Uses lstat so symlinks return their own metadata.
  macOS uses st_mtimespec; Linux uses st_mtim.
*/
#ifdef __APPLE__
  #define KK_ST_MTIME_SEC(st)  ((st).st_mtimespec.tv_sec)
  #define KK_ST_MTIME_NSEC(st) ((st).st_mtimespec.tv_nsec)
  #define KK_ST_ATIME_SEC(st)  ((st).st_atimespec.tv_sec)
  #define KK_ST_ATIME_NSEC(st) ((st).st_atimespec.tv_nsec)
  #define KK_ST_CTIME_SEC(st)  ((st).st_ctimespec.tv_sec)
  #define KK_ST_CTIME_NSEC(st) ((st).st_ctimespec.tv_nsec)
#else
  #define KK_ST_MTIME_SEC(st)  ((st).st_mtim.tv_sec)
  #define KK_ST_MTIME_NSEC(st) ((st).st_mtim.tv_nsec)
  #define KK_ST_ATIME_SEC(st)  ((st).st_atim.tv_sec)
  #define KK_ST_ATIME_NSEC(st) ((st).st_atim.tv_nsec)
  #define KK_ST_CTIME_SEC(st)  ((st).st_ctim.tv_sec)
  #define KK_ST_CTIME_NSEC(st) ((st).st_ctim.tv_nsec)
#endif

// Combine seconds and nanoseconds into a single Koka integer:
// sec * 1_000_000_000 + nsec
// Koka integers are arbitrary precision, so no overflow risk.
static kk_integer_t kk_time_to_ns(time_t sec, long nsec, kk_context_t* ctx) {
  kk_integer_t ksec  = kk_integer_from_int64((int64_t)sec, ctx);
  kk_integer_t kbil  = kk_integer_from_int64(1000000000LL, ctx);
  kk_integer_t knsec = kk_integer_from_int64((int64_t)nsec, ctx);
  kk_integer_t prod  = kk_integer_mul(ksec, kbil, ctx);
  return kk_integer_add(prod, knsec, ctx);
}

static kk_integer_t kk_os_get_mtime(kk_string_t path, kk_context_t* ctx) {
  struct stat st = { 0 };
  int err = 0;
  kk_with_string_as_qutf8_borrow(path, cpath, ctx) {
    if (lstat(cpath, &st) < 0) err = errno;
  }
  kk_string_drop(path, ctx);
  if (err != 0) return kk_integer_from_int(0, ctx);
  return kk_time_to_ns(KK_ST_MTIME_SEC(st), KK_ST_MTIME_NSEC(st), ctx);
}

static kk_integer_t kk_os_get_atime(kk_string_t path, kk_context_t* ctx) {
  struct stat st = { 0 };
  int err = 0;
  kk_with_string_as_qutf8_borrow(path, cpath, ctx) {
    if (lstat(cpath, &st) < 0) err = errno;
  }
  kk_string_drop(path, ctx);
  if (err != 0) return kk_integer_from_int(0, ctx);
  return kk_time_to_ns(KK_ST_ATIME_SEC(st), KK_ST_ATIME_NSEC(st), ctx);
}

static kk_integer_t kk_os_get_ctime(kk_string_t path, kk_context_t* ctx) {
  struct stat st = { 0 };
  int err = 0;
  kk_with_string_as_qutf8_borrow(path, cpath, ctx) {
    if (lstat(cpath, &st) < 0) err = errno;
  }
  kk_string_drop(path, ctx);
  if (err != 0) return kk_integer_from_int(0, ctx);
  return kk_time_to_ns(KK_ST_CTIME_SEC(st), KK_ST_CTIME_NSEC(st), ctx);
}

/*
  get-inode: Get the inode number of a file via lstat.
  Returns 0 on error. Uses lstat so symlinks return their own inode.
*/
static kk_integer_t kk_os_get_inode(kk_string_t path, kk_context_t* ctx) {
  struct stat st = { 0 };
  int err = 0;
  kk_with_string_as_qutf8_borrow(path, cpath, ctx) {
    if (lstat(cpath, &st) < 0) err = errno;
  }
  kk_string_drop(path, ctx);
  if (err != 0) return kk_integer_from_int(0, ctx);
  return kk_integer_from_int64((int64_t)st.st_ino, ctx);
}

// ---------------------------------------------------------------------------
// stat-info: All file metadata in a single lstat call (for ls -l).
//
// Returns a tab-separated string so Koka can parse it without needing
// to construct complex C→Koka data structures:
//   mode \t nlink \t owner \t uid \t group \t gid \t size \t mtime_sec \t mtime_nsec \t blocks
//
// mode is the 10-char "drwxr-xr-x" string.
// owner/group are looked up via getpwuid/getgrgid; empty if unknown.
// Returns empty string on error.
// ---------------------------------------------------------------------------
#include <pwd.h>
#include <grp.h>

// Format mode bits into the classic "-rwxrwxrwx" string (10 chars + NUL).
static void kk_format_mode(mode_t mode, char *buf) {
  switch (mode & S_IFMT) {
    case S_IFDIR:  buf[0] = 'd'; break;
    case S_IFLNK:  buf[0] = 'l'; break;
    case S_IFCHR:  buf[0] = 'c'; break;
    case S_IFBLK:  buf[0] = 'b'; break;
    case S_IFIFO:  buf[0] = 'p'; break;
    case S_IFSOCK: buf[0] = 's'; break;
    default:       buf[0] = '-'; break;
  }
  buf[1] = (mode & S_IRUSR) ? 'r' : '-';
  buf[2] = (mode & S_IWUSR) ? 'w' : '-';
  buf[3] = (mode & S_ISUID) ? ((mode & S_IXUSR) ? 's' : 'S')
                             : ((mode & S_IXUSR) ? 'x' : '-');
  buf[4] = (mode & S_IRGRP) ? 'r' : '-';
  buf[5] = (mode & S_IWGRP) ? 'w' : '-';
  buf[6] = (mode & S_ISGID) ? ((mode & S_IXGRP) ? 's' : 'S')
                             : ((mode & S_IXGRP) ? 'x' : '-');
  buf[7] = (mode & S_IROTH) ? 'r' : '-';
  buf[8] = (mode & S_IWOTH) ? 'w' : '-';
  buf[9] = (mode & S_ISVTX) ? ((mode & S_IXOTH) ? 't' : 'T')
                             : ((mode & S_IXOTH) ? 'x' : '-');
  buf[10] = '\0';
}

static kk_string_t kk_os_stat_info(kk_string_t path, kk_context_t* ctx) {
  struct stat st = { 0 };
  int err = 0;
  kk_with_string_as_qutf8_borrow(path, cpath, ctx) {
    if (lstat(cpath, &st) < 0) err = errno;
  }
  kk_string_drop(path, ctx);
  if (err != 0) return kk_string_empty();

  char modebuf[12];
  kk_format_mode(st.st_mode, modebuf);

  struct passwd *pw = getpwuid(st.st_uid);
  const char *owner = pw ? pw->pw_name : "";

  struct group *gr = getgrgid(st.st_gid);
  const char *group = gr ? gr->gr_name : "";

  char buf[1024];
  snprintf(buf, sizeof(buf), "%s\t%llu\t%s\t%u\t%s\t%u\t%lld\t%lld\t%ld\t%lld",
    modebuf,
    (unsigned long long)st.st_nlink,
    owner,
    (unsigned)st.st_uid,
    group,
    (unsigned)st.st_gid,
    (long long)st.st_size,
    (long long)KK_ST_MTIME_SEC(st),
    (long)KK_ST_MTIME_NSEC(st),
    (long long)st.st_blocks);
  return kk_string_alloc_from_qutf8(buf, ctx);
}

// ---------------------------------------------------------------------------
// filevercmp — version-aware file name comparison (GNU ls -v)
//
// Re-implemented from gnulib's filevercmp.c (LGPL-3.0-or-later).
// Original authors: Ian Jackson, Anthony Towns, FSF.
// Adapted for Koka FFI: no gnulib deps, uses only standard C.
//
// Algorithm (from the GNU coreutils docs):
//  1. Empty string, ".", ".." sort first; dotfiles before non-dotfiles.
//  2. File extension suffix is stripped; compare without it first.
//  3. Core comparison alternates non-digit and digit runs:
//     - Non-digit: byte-by-byte with custom order:
//         ~ < end-of-string < letters < other bytes
//     - Digit: skip leading zeros, compare numerically.
//  4. If equal without suffix, re-compare with full strings.
// ---------------------------------------------------------------------------
#include <ctype.h>

// Return the length of the prefix before the file extension suffix.
// Suffix matches (\.[A-Za-z~][A-Za-z0-9~]*)*$ (longest, non-whole-string).
static size_t fvc_prefixlen(const char *s, size_t len) {
  size_t prefixlen = 0;
  for (size_t i = 0; ; ) {
    if (i == len)
      return prefixlen;
    i++;
    prefixlen = i;
    while (i + 1 < len && s[i] == '.'
           && (isalpha((unsigned char)s[i+1]) || s[i+1] == '~'))
      for (i += 2; i < len && (isalnum((unsigned char)s[i]) || s[i] == '~'); i++)
        continue;
  }
}

// Custom byte ordering for version sort non-digit comparison.
static int fvc_order(const char *s, size_t pos, size_t len) {
  if (pos == len)
    return -1;                          // end-of-string
  unsigned char c = (unsigned char)s[pos];
  if (isdigit(c))
    return 0;                           // digits handled separately
  else if (isalpha(c))
    return c;                           // letters sort by ASCII value
  else if (c == '~')
    return -2;                          // tilde sorts before everything
  else
    return (int)c + 256;               // other bytes sort after letters
}

// Core Debian verrevcmp: compare two byte arrays by version rules.
static int fvc_verrevcmp(const char *s1, size_t n1, const char *s2, size_t n2) {
  size_t p1 = 0, p2 = 0;
  while (p1 < n1 || p2 < n2) {
    int first_diff = 0;
    // Compare non-digit parts
    while ((p1 < n1 && !isdigit((unsigned char)s1[p1]))
        || (p2 < n2 && !isdigit((unsigned char)s2[p2]))) {
      int c1 = fvc_order(s1, p1, n1);
      int c2 = fvc_order(s2, p2, n2);
      if (c1 != c2)
        return c1 - c2;
      p1++; p2++;
    }
    // Skip leading zeros
    while (p1 < n1 && s1[p1] == '0') p1++;
    while (p2 < n2 && s2[p2] == '0') p2++;
    // Compare digit parts numerically
    while (p1 < n1 && p2 < n2
        && isdigit((unsigned char)s1[p1]) && isdigit((unsigned char)s2[p2])) {
      if (!first_diff)
        first_diff = s1[p1] - s2[p2];
      p1++; p2++;
    }
    if (p1 < n1 && isdigit((unsigned char)s1[p1])) return 1;   // s1 has more digits
    if (p2 < n2 && isdigit((unsigned char)s2[p2])) return -1;  // s2 has more digits
    if (first_diff) return first_diff;
  }
  return 0;
}

// Full filevercmp: handles empty, dot, dotdot, dotfiles, extension stripping.
static int kk_filevercmp(const char *a, size_t alen, const char *b, size_t blen) {
  // Empty strings sort first
  if (!alen) return blen ? -1 : 0;
  if (!blen) return 1;

  // Special cases for leading '.'
  if (a[0] == '.') {
    if (b[0] != '.') return -1;
    // "." sorts first
    if (alen == 1) return (blen == 1) ? 0 : -1;
    if (blen == 1) return 1;
    // ".." sorts second
    if (a[1] == '.' && alen == 2) return (b[1] == '.' && blen == 2) ? 0 : -1;
    if (b[1] == '.' && blen == 2) return 1;
  } else if (b[0] == '.') {
    return 1;
  }

  // Strip file extension suffixes
  size_t apfx = fvc_prefixlen(a, alen);
  size_t bpfx = fvc_prefixlen(b, blen);

  // If both suffixes are empty, one pass suffices
  int one_pass = (apfx == alen && bpfx == blen);

  int result = fvc_verrevcmp(a, apfx, b, bpfx);
  if (result || one_pass) return result;
  // Suffixes differ: re-compare with full strings
  return fvc_verrevcmp(a, alen, b, blen);
}

// Koka FFI wrapper: compare two Koka strings using filevercmp.
static kk_integer_t kk_os_filevercmp(kk_string_t sa, kk_string_t sb, kk_context_t* ctx) {
  int result = 0;
  kk_with_string_as_qutf8_borrow(sa, ca, ctx) {
    kk_with_string_as_qutf8_borrow(sb, cb, ctx) {
      size_t alen = strlen(ca);
      size_t blen = strlen(cb);
      result = kk_filevercmp(ca, alen, cb, blen);
    }
  }
  kk_string_drop(sa, ctx);
  kk_string_drop(sb, ctx);
  // Normalize to -1/0/1
  return kk_integer_from_int(result < 0 ? -1 : result > 0 ? 1 : 0, ctx);
}