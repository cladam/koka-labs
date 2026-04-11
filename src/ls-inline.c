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
