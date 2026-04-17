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
      val koka   = run-koka-ls(".".path, Options(slash-dir = True, one-entry = True))
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
      val gnu    = run-gnu-ls("-1U", ".").split("\n").sort(string/cmp)
      val koka   = run-koka-ls(".".path, Options(sort-none = True, one-entry = True)).split("\n").sort(string/cmp)
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