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
import std/os/process
import src/ls
import kunit

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// GNU ls binary — on macOS via Homebrew it's `gls`
val gnu-ls = "gls"

// Run GNU ls with flags and a directory, return trimmed stdout
fun run-gnu-ls(flags : string, dir : string) : io string
  val cmd = gnu-ls ++ " " ++ flags ++ " " ++ dir
  match run-system-read(cmd)
    Ok(output) -> output.trim
    Error(exn) -> exn.message

// Run koka-ls via bio effect capture, return trimmed output
fun run-koka-ls(dir : path, opts : options) : _ string
  fun go() : _ (int, string)
    with bio
    with status
    list-dir(dir, opts, False)
  val (_, output) = go()
  output.trim

// ---------------------------------------------------------------------------
// Comparison tests
// ---------------------------------------------------------------------------

pub fun main() : io ()
  println(bold("Comparing koka-ls output to " ++ gnu-ls ++ "..."))
  println("")

  defaultKIntegrationHandler
    itest("default listing matches GNU ls -1")
      val gnu    = run-gnu-ls("-1", ".")
      val koka   = run-koka-ls(".".path, Options(one-entry = True))
      assert/is-true(gnu == koka)

    itest("-a matches GNU ls -1a")
      val gnu    = run-gnu-ls("-1a", ".")
      val koka   = run-koka-ls(".".path, Options(show-all = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-A matches GNU ls -1A")
      val gnu    = run-gnu-ls("-1A", ".")
      val koka   = run-koka-ls(".".path, Options(almost-all = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-r matches GNU ls -1r")
      val gnu    = run-gnu-ls("-1r", ".")
      val koka   = run-koka-ls(".".path, Options(reverse = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-F matches GNU ls -1F")
      val gnu    = run-gnu-ls("-1F", ".")
      val koka   = run-koka-ls(".".path, Options(fs-type = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-p matches GNU ls -1p")
      val gnu    = run-gnu-ls("-1p", ".")
      val koka   = run-koka-ls(".".path, Options(slash-dir = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-B matches GNU ls -1B")
      val gnu    = run-gnu-ls("-1B", ".")
      val koka   = run-koka-ls(".".path, Options(ignore-backups = True, one-entry = True))
      assert/is-true(gnu == koka)

    itest("-U unsorted has same entries as GNU ls -1U")
      // GNU ls -U is directory order which may differ, so compare as sets
      val gnu    = run-gnu-ls("-1U", ".").split("\n").sort(string/cmp)
      val koka   = run-koka-ls(".".path, Options(sort-none = True, one-entry = True)).split("\n").sort(string/cmp)
      assert/is-true(gnu == koka)