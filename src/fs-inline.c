/*---------------------------------------------------------------------------
  File-type detection for ls -F flag.
  Uses lstat for symlinks (does not follow the link),
  stat for everything else (follows symlinks).

  This isn't included in Koka's standard library, but was easy enough to write in C and import into Koka. It is used by the ls.kk implementation of the ls -F flag.
---------------------------------------------------------------------------*/
#include <sys/stat.h>

static bool kk_os_is_symlink(kk_string_t path, kk_context_t* ctx) {
  struct stat buf;
  int res = lstat(kk_string_cbuf_borrow(path, NULL, ctx), &buf);
  kk_string_drop(path, ctx);
  return (res == 0 && S_ISLNK(buf.st_mode));
}

static bool kk_os_is_executable(kk_string_t path, kk_context_t* ctx) {
  struct stat buf;
  int res = stat(kk_string_cbuf_borrow(path, NULL, ctx), &buf);
  kk_string_drop(path, ctx);
  return (res == 0 && !S_ISDIR(buf.st_mode) && (buf.st_mode & S_IXUSR));
}

static bool kk_os_is_fifo(kk_string_t path, kk_context_t* ctx) {
  struct stat buf;
  int res = stat(kk_string_cbuf_borrow(path, NULL, ctx), &buf);
  kk_string_drop(path, ctx);
  return (res == 0 && S_ISFIFO(buf.st_mode));
}

static bool kk_os_is_socket(kk_string_t path, kk_context_t* ctx) {
  struct stat buf;
  int res = stat(kk_string_cbuf_borrow(path, NULL, ctx), &buf);
  kk_string_drop(path, ctx);
  return (res == 0 && S_ISSOCK(buf.st_mode));
}
