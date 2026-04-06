/*---------------------------------------------------------------------------
  File-type detection for ls -F flag.
  Uses lstat for symlinks (does not follow the link),
  stat for everything else (follows symlinks).

  This isn't included in Koka's standard library, but was easy enough to
  write in C and import into Koka. It is used by the ls.kk implementation
  of the ls -F flag.

  Note: kk_stat_t and kk_posix_stat are static in kklib/src/os.c and not
  exported through kklib.h, so we define our own equivalents here.
---------------------------------------------------------------------------*/
#include <sys/types.h>
#include <sys/stat.h>

static bool kk_os_is_symlink(kk_string_t path, kk_context_t* ctx) {
  struct stat st = { 0 };
  int err = 0;
  kk_with_string_as_qutf8_borrow(path, cpath, ctx) {
    if (lstat(cpath, &st) < 0) err = errno;
  }
  kk_string_drop(path, ctx);
  if (err != 0) return false;
  return ((st.st_mode & S_IFLNK) != 0);
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
  return ((st.st_mode & S_IFIFO) != 0);
}

static bool kk_os_is_socket(kk_string_t path, kk_context_t* ctx) {
  struct stat st = { 0 };
  int err = 0;
  kk_with_string_as_qutf8_borrow(path, cpath, ctx) {
    if (stat(cpath, &st) < 0) err = errno;
  }
  kk_string_drop(path, ctx);
  if (err != 0) return false;
  return ((st.st_mode & S_IFSOCK) != 0);
}

