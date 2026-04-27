/*
 * compare-ls.kk - compare koka-ls output to GNU ls
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

import std/os/path
import std/os/env
import std/os/process
import src/ls
import kunit

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// GNU ls binary — on macOS via Homebrew it's `gls`
fun get-gnu-ls() : io string
  match get-args()
    Cons(bin, _) -> bin
    _            -> "gls"  // fallback default

// Run GNU ls with flags and a directory, return trimmed stdout
fun run-gnu-ls(flags : string, dir : string) : io string
  val bin = get-gnu-ls()
  val cmd = bin ++ " " ++ flags ++ " " ++ dir
  match run-system-read(cmd)
    Ok(output) -> output.trim
    Error(exn) -> exn.message

// Run koka-ls via bio effect capture, return trimmed output
fun run-koka-ls(dir : path, opts : options) : _ string
  fun go() : _ (int, string)
    with bio
    with status
    list-dir(dir, opts, opts.recurse)
  val (_, output) = go()
  output.trim

// ---------------------------------------------------------------------------
// Comparison tests
// ---------------------------------------------------------------------------

pub fun main() : io ()
  println(bold("Comparing koka-ls output to GNU ls..."))
  println("")

  defaultKIntegrationHandler
    itest("default listing (-1) matches GNU ls -1")
      val gnu    = run-gnu-ls("-1", ".")
      val koka   = run-koka-ls(".".path, Options(one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1a matches GNU ls -1a")
      val gnu    = run-gnu-ls("-1a", ".")
      val koka   = run-koka-ls(".".path, Options(show-all = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1A matches GNU ls -1A")
      val gnu    = run-gnu-ls("-1A", ".")
      val koka   = run-koka-ls(".".path, Options(almost-all = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1r matches GNU ls -1r")
      val gnu    = run-gnu-ls("-1r", ".")
      val koka   = run-koka-ls(".".path, Options(reverse = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1F matches GNU ls -1F")
      val gnu    = run-gnu-ls("-1F", ".")
      val koka   = run-koka-ls("." .path, Options(classify = ClassifyAlways, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1 --classify=always matches GNU ls -1 --classify=always")
      val gnu    = run-gnu-ls("-1 --classify=always", ".")
      val koka   = run-koka-ls(".".path, Options(classify = ClassifyAlways, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1 --classify=never matches GNU ls -1 --classify=never")
      val gnu    = run-gnu-ls("-1 --classify=never", ".")
      val koka   = run-koka-ls(".".path, Options(classify = ClassifyNever, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1p matches GNU ls -1p")
      val gnu    = run-gnu-ls("-1p", ".")
      val koka   = run-koka-ls("." .path, Options(indicator = IndicatorSlash, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1B matches GNU ls -1B")
      val gnu    = run-gnu-ls("-1B", ".")
      val koka   = run-koka-ls(".".path, Options(ignore-backups = True, one-entry = True))
      assert/is-true(gnu == koka)

    // compare --ignore
    itest("-1 --ignore='*.md' matches GNU ls")
      val gnu  = run-gnu-ls("-1 --ignore='*.md'", ".")
      val koka = run-koka-ls(".".path, Options(ignore-patterns = ["*.md"], one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1 --ignore='*.md' --ignore='test*' matches GNU ls")
      val gnu  = run-gnu-ls("-1 --ignore='*.md' --ignore='test*'", ".")
      val koka = run-koka-ls(".".path, Options(ignore-patterns = ["*.md", "test*"], one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1a --ignore='*.md' still ignores with -a")
      val gnu  = run-gnu-ls("-1a --ignore='*.md'", ".")
      val koka = run-koka-ls(".".path, Options(show-all = True, ignore-patterns = ["*.md"], one-entry = True))
      assert/is-true(gnu == koka)

    // compare --hide
    itest("-1 --hide='*.md' matches GNU ls")
      val gnu  = run-gnu-ls("-1 --hide='*.md'", ".")
      val koka = run-koka-ls(".".path, Options(hide-patterns = ["*.md"], one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1a --hide='*.md' shows .md files (hide overridden by -a)")
      val gnu  = run-gnu-ls("-1a --hide='*.md'", ".")
      val koka = run-koka-ls(".".path, Options(show-all = True, hide-patterns = ["*.md"], one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1A --hide='*.md' shows .md files (hide overridden by -A)")
      val gnu  = run-gnu-ls("-1A --hide='*.md'", ".")
      val koka = run-koka-ls(".".path, Options(almost-all = True, hide-patterns = ["*.md"], one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1R matches GNU ls -1R")
      val gnu    = run-gnu-ls("-1R", ".")
      val koka   = run-koka-ls("." .path, Options(recurse = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1U unsorted has same entries as GNU ls -1U")
      // GNU ls -U is directory order which may differ, so compare as sets
      val gnu    = run-gnu-ls("-1U", ".").split("\n").sortBy(string/cmp)
      val koka   = run-koka-ls("." .path, Options(sort-by = SortNone, one-entry = True)).split("\n").sortBy(string/cmp)
      assert/is-true(gnu == koka)

    // --- inode comparison tests ---
    itest("-1i matches GNU ls -1i")
      val gnu    = run-gnu-ls("-1i", ".")
      val koka   = run-koka-ls(".".path, Options(print-inode = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1ia matches GNU ls -1ia")
      val gnu    = run-gnu-ls("-1ia", ".")
      val koka   = run-koka-ls(".".path, Options(print-inode = True, show-all = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1iA matches GNU ls -1iA")
      val gnu    = run-gnu-ls("-1iA", ".")
      val koka   = run-koka-ls(".".path, Options(print-inode = True, almost-all = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1ir matches GNU ls -1ir")
      val gnu    = run-gnu-ls("-1ir", ".")
      val koka   = run-koka-ls(".".path, Options(print-inode = True, reverse = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1iF matches GNU ls -1iF")
      val gnu    = run-gnu-ls("-1iF", ".")
      val koka   = run-koka-ls(".".path, Options(print-inode = True, classify = ClassifyAlways, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1i on subdirectory matches GNU ls -1i")
      val gnu    = run-gnu-ls("-1i", "src")
      val koka   = run-koka-ls("src".path, Options(print-inode = True, one-entry = True))
      assert/is-true(gnu == koka)

    // --- --file-type and --indicator-style comparison tests ---
    itest("-1 --file-type matches GNU ls -1 --file-type")
      val gnu    = run-gnu-ls("-1 --file-type", ".")
      val koka   = run-koka-ls(".".path, Options(indicator = IndicatorFileType, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1 --indicator-style=slash matches GNU ls")
      val gnu    = run-gnu-ls("-1 --indicator-style=slash", ".")
      val koka   = run-koka-ls(".".path, Options(indicator = IndicatorSlash, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1 --indicator-style=file-type matches GNU ls")
      val gnu    = run-gnu-ls("-1 --indicator-style=file-type", ".")
      val koka   = run-koka-ls(".".path, Options(indicator = IndicatorFileType, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1 --indicator-style=classify matches GNU ls")
      val gnu    = run-gnu-ls("-1 --indicator-style=classify", ".")
      val koka   = run-koka-ls(".".path, Options(indicator = IndicatorClassify, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1 --indicator-style=none matches GNU ls")
      val gnu    = run-gnu-ls("-1 --indicator-style=none", ".")
      val koka   = run-koka-ls(".".path, Options(indicator = IndicatorNone, one-entry = True))
      assert/is-true(gnu == koka)

    // --- size sort comparison tests ---
    itest("-1S matches GNU ls -1S")
      val gnu    = run-gnu-ls("-1S", ".")
      val koka   = run-koka-ls(".".path, Options(sort-by = SortSize, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1Sr matches GNU ls -1Sr")
      val gnu    = run-gnu-ls("-1Sr", ".")
      val koka   = run-koka-ls(".".path, Options(sort-by = SortSize, reverse = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1S on subdirectory matches GNU ls -1S")
      val gnu    = run-gnu-ls("-1S", "src")
      val koka   = run-koka-ls("src".path, Options(sort-by = SortSize, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1SF matches GNU ls -1SF")
      val gnu    = run-gnu-ls("-1SF", ".")
      val koka   = run-koka-ls(".".path, Options(sort-by = SortSize, classify = ClassifyAlways, one-entry = True))
      assert/is-true(gnu == koka)

    // --- time sort comparison tests ---
    itest("-1t matches GNU ls -1t")
      val gnu    = run-gnu-ls("-1t", ".")
      val koka   = run-koka-ls(".".path, Options(sort-by = SortTime, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1tr matches GNU ls -1tr")
      val gnu    = run-gnu-ls("-1tr", ".")
      val koka   = run-koka-ls(".".path, Options(sort-by = SortTime, reverse = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1t on subdirectory matches GNU ls -1t")
      val gnu    = run-gnu-ls("-1t", "src")
      val koka   = run-koka-ls("src".path, Options(sort-by = SortTime, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1tc (sort by ctime) matches GNU ls -1tc")
      val gnu    = run-gnu-ls("-1tc", ".")
      val koka   = run-koka-ls(".".path, Options(sort-by = SortTime, time-type = TimeCtime, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1tu (sort by atime) matches GNU ls -1tu")
      val gnu    = run-gnu-ls("-1tu", ".")
      val koka   = run-koka-ls(".".path, Options(sort-by = SortTime, time-type = TimeAtime, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1t --time=ctime matches GNU ls")
      val gnu    = run-gnu-ls("-1t --time=ctime", ".")
      val koka   = run-koka-ls(".".path, Options(sort-by = SortTime, time-type = TimeCtime, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1X matches GNU ls -1X")
      val gnu    = run-gnu-ls("-1X", ".")
      val koka   = run-koka-ls(".".path, Options(sort-by = SortExtension, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1Xr matches GNU ls -1Xr")
      val gnu    = run-gnu-ls("-1Xr", ".")
      val koka   = run-koka-ls(".".path, Options(sort-by = SortExtension, reverse = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1X on subdirectory matches GNU ls -1X")
      val gnu    = run-gnu-ls("-1X", "src")
      val koka   = run-koka-ls("src".path, Options(sort-by = SortExtension, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1 --sort=width matches GNU ls -1 --sort=width")
      val gnu    = run-gnu-ls("-1 --sort=width", ".")
      val koka   = run-koka-ls(".".path, Options(sort-by = SortWidth, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1r --sort=width matches GNU ls -1r --sort=width")
      val gnu    = run-gnu-ls("-1r --sort=width", ".")
      val koka   = run-koka-ls(".".path, Options(sort-by = SortWidth, reverse = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1 --sort=width on src matches GNU ls")
      val gnu    = run-gnu-ls("-1 --sort=width", "src")
      val koka   = run-koka-ls("src".path, Options(sort-by = SortWidth, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1 --group-directories-first matches GNU ls")
      val gnu    = run-gnu-ls("-1 --group-directories-first", ".")
      val koka   = run-koka-ls(".".path, Options(group-dirs = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1r --group-directories-first matches GNU ls")
      val gnu    = run-gnu-ls("-1r --group-directories-first", ".")
      val koka   = run-koka-ls(".".path, Options(group-dirs = True, reverse = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1S --group-directories-first matches GNU ls")
      val gnu    = run-gnu-ls("-1S --group-directories-first", ".")
      val koka   = run-koka-ls(".".path, Options(sort-by = SortSize, group-dirs = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1v matches GNU ls -1v")
      val gnu    = run-gnu-ls("-1v", ".")
      val koka   = run-koka-ls(".".path, Options(sort-by = SortVersion, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1vr matches GNU ls -1vr")
      val gnu    = run-gnu-ls("-1vr", ".")
      val koka   = run-koka-ls(".".path, Options(sort-by = SortVersion, reverse = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1v on src matches GNU ls -1v")
      val gnu    = run-gnu-ls("-1v", "src")
      val koka   = run-koka-ls("src".path, Options(sort-by = SortVersion, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-1va matches GNU ls -1va")
      val gnu    = run-gnu-ls("-1va", ".")
      val koka   = run-koka-ls(".".path, Options(sort-by = SortVersion, show-all = True, one-entry = True))
      assert/is-true(gnu == koka)

    // --- long-format (-l) comparison tests ---
    itest("-l matches GNU ls -l")
      val gnu    = run-gnu-ls("-l", ".")
      val koka   = run-koka-ls(".".path, Options(long-format = True))
      assert/is-true(gnu == koka)

    itest("-la matches GNU ls -la")
      val gnu    = run-gnu-ls("-la", ".")
      val koka   = run-koka-ls(".".path, Options(long-format = True, show-all = True))
      assert/is-true(gnu == koka)

    itest("-lA matches GNU ls -lA")
      val gnu    = run-gnu-ls("-lA", ".")
      val koka   = run-koka-ls(".".path, Options(long-format = True, almost-all = True))
      assert/is-true(gnu == koka)

    itest("-lr matches GNU ls -lr")
      val gnu    = run-gnu-ls("-lr", ".")
      val koka   = run-koka-ls(".".path, Options(long-format = True, reverse = True))
      assert/is-true(gnu == koka)

    itest("-li matches GNU ls -li")
      val gnu    = run-gnu-ls("-li", ".")
      val koka   = run-koka-ls(".".path, Options(long-format = True, print-inode = True))
      assert/is-true(gnu == koka)

    itest("-l on src matches GNU ls -l")
      val gnu    = run-gnu-ls("-l", "src")
      val koka   = run-koka-ls("src".path, Options(long-format = True))
      assert/is-true(gnu == koka)

    itest("-l on tests matches GNU ls -l")
      val gnu    = run-gnu-ls("-l", "tests")
      val koka   = run-koka-ls("tests".path, Options(long-format = True))
      assert/is-true(gnu == koka)

    itest("-lS matches GNU ls -lS")
      val gnu    = run-gnu-ls("-lS", ".")
      val koka   = run-koka-ls(".".path, Options(long-format = True, sort-by = SortSize))
      assert/is-true(gnu == koka)

    itest("-lt matches GNU ls -lt")
      val gnu    = run-gnu-ls("-lt", ".")
      val koka   = run-koka-ls(".".path, Options(long-format = True, sort-by = SortTime))
      assert/is-true(gnu == koka)

    itest("-lF matches GNU ls -lF")
      val gnu    = run-gnu-ls("-lF", ".")
      val koka   = run-koka-ls(".".path, Options(long-format = True, classify = ClassifyAlways))
      assert/is-true(gnu == koka)

    // --- no-group (-G) comparison tests ---
    itest("-G matches GNU ls -lG")
      val gnu = run-gnu-ls("-lG", ".")
      val koka = run-koka-ls(".".path, Options(long-format = True, no-group = True))
      assert/is-true(gnu == koka)

    // --- no-owner (-g) comparison tests ---
    itest("-G matches GNU ls -lg")
      val gnu = run-gnu-ls("-lg", ".")
      val koka = run-koka-ls(".".path, Options(long-format = True, no-owner = True))
      assert/is-true(gnu == koka)

    // --- no-group (-o) comparison tests (same as -lG) ---
    itest("-o matches GNU ls -o")
      val gnu = run-gnu-ls("-o", ".")
      val koka = run-koka-ls(".".path, Options(long-format = True, no-group = True))
      assert/is-true(gnu == koka)

    // --- numeric uid/gid (-n) comparison tests ---
    itest("-n matches GNU ls -n")
      val gnu    = run-gnu-ls("-n", ".")
      val koka   = run-koka-ls(".".path, Options(long-format = True, numeric-ids = True))
      assert/is-true(gnu == koka)

    itest("-na matches GNU ls -na")
      val gnu    = run-gnu-ls("-na", ".")
      val koka   = run-koka-ls(".".path, Options(long-format = True, numeric-ids = True, show-all = True))
      assert/is-true(gnu == koka)