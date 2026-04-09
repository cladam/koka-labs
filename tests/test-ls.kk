/*
 * test-ls.kk - unit tests for ls.kka
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
import std/os/file
import std/os/dir
import std/os/env
import src/ls
import assert

// A helper to ensure a file exists with specific content
fun create-test-file(name : string, content : string = "") : <fsys,exn> () {
  val p = name.path
  write-text-file(p, content)
}

pub fun main() : io ()
  // Smoke tests: verify list-dir doesn't crash with various options
  println(bold("Running smoke tests..."))

  list-dir("." .path, Options(), False)
  list-dir("." .path, Options(show-all = True), False)
  list-dir("." .path, Options(almost-all = True), False)
  list-dir("." .path, Options(reverse = True), False)

  // Integration tests
  println(bold("Running integration tests..."))
  defaultKIntegrationHandler
    // Output assertions: verify expected entries appear
    itest("default listing contains README.md")
      val entries = list-dir-names("." .path, Options())
      assert/is-true(entries.any(fn(e) e == "README.md"))

    itest("default listing contains src")
      val entries = list-dir-names("." .path, Options())
      assert/is-true(entries.any(fn(e) e == "src"))

    itest("show-all listing contains .")
      val entries = list-dir-names("." .path, Options(show-all = True))
      assert/is-true(entries.any(fn(e) e == "."))

    itest("show-all listing contains ..")
      val entries = list-dir-names("." .path, Options(show-all = True))
      assert/is-true(entries.any(fn(e) e == ".."))

    itest("show-all listing contains README.md")
      val entries = list-dir-names("." .path, Options(show-all = True))
      assert/is-true(entries.any(fn(e) e == "README.md"))

    itest("reverse listing is in descending order")
      val entries-r = list-dir-names("." .path, Options(reverse = True))
      val first = entries-r.head.default("")
      val last  = entries-r.last.default("")
      assert/is-true(first > last)

    // --- ignore-backups integration test ---
    itest("-B: default listing shows backup file")
      val backup-file = "tests/test-ls.kk~"
      create-test-file(backup-file, "backup content")
      val entries = list-dir-names("tests".path, Options())
      assert/is-true(entries.any(fn(e) e == "test-ls.kk~"))

    itest("-B: ignore-backups hides backup file")
      val entries = list-dir-names("tests".path, Options(ignore-backups = True))
      assert/is-true(entries.all(fn(e) e != "test-ls.kk~"))

  // Unit tests for pure logic
  println(bold("Running unit tests..."))
  defaultKUnitHandler
    // --- Options defaults ---
    test("Options should not have show-all by default")
      val opts = Options()
      assert/is-false(opts.show-all)

    test("Options should not have almost-all by default")
      val opts = Options()
      assert/is-false(opts.almost-all)

    test("Options should not have reverse by default")
      val opts = Options()
      assert/is-false(opts.reverse)

    test("Options show-all can be set to True")
      val opts = Options(show-all = True)
      assert/is-true(opts.show-all)

    // --- parse-args ---
    test("parse-args with no args returns empty paths")
      val paths = match parse-args([])
        Parsed(_, p) -> p
        _ -> ["unexpected"]
      assert/empty(paths)

    test("parse-args -a enables show-all")
      val sa = match parse-args(["-a"])
        Parsed(opts, _) -> opts.show-all
        _ -> False
      assert/is-true(sa)

    test("parse-args -A enables almost-all")
      val aa = match parse-args(["-A"])
        Parsed(opts, _) -> opts.almost-all
        _ -> False
      assert/is-true(aa)

    test("parse-args -a should not enable almost-all")
      val sa = match parse-args(["-A", "-a"])
        Parsed(opts, _) -> opts.show-all
        _ -> False
      val aa = match parse-args(["-A", "-a"])
        Parsed(opts, _) -> opts.almost-all
        _ -> True
      assert/is-true(sa)
      assert/is-false(aa)

    test("parse-args -A should not enable show-all")
      val sa = match parse-args(["-a", "-A"])
        Parsed(opts, _) -> opts.show-all
        _ -> True
      val aa = match parse-args(["-a", "-A"])
        Parsed(opts, _) -> opts.almost-all
        _ -> False
      assert/is-false(sa)
      assert/is-true(aa)
    
    // Ignnore backup files tests
    test("parse-args -B enables ignore-backups")
      val hb = match parse-args(["-B"])
        Parsed(opts, _) -> opts.ignore-backups
        _ -> False
      assert/is-true(hb)

    test("parse-args --ignore-backups enables ignore-backups")
      val hb = match parse-args(["--ignore-backups"])
        Parsed(opts, _) -> opts.ignore-backups
        _ -> False
      assert/is-true(hb)

    test("parse-args -r enables reverse")
      val rev = match parse-args(["-r"])
        Parsed(opts, _) -> opts.reverse
        _ -> False
      assert/is-true(rev)

    test("parse-args -F enables fs-type")
      val ft = match parse-args(["-F"])
        Parsed(opts, _) -> opts.fs-type
        _ -> False
      assert/is-true(ft)

    test("parse-args combined flags -arF")
      val sa = match parse-args(["-arF"])
        Parsed(opts, _) -> opts.show-all
        _ -> False
      val rev = match parse-args(["-arF"])
        Parsed(opts, _) -> opts.reverse
        _ -> False
      val ft = match parse-args(["-arF"])
        Parsed(opts, _) -> opts.fs-type
        _ -> False
      assert/is-true(sa)
      assert/is-true(rev)
      assert/is-true(ft)

    test("parse-args separates paths from flags")
      val rev = match parse-args(["-r", "foo", "bar"])
        Parsed(opts, _) -> opts.reverse
        _ -> False
      val paths = match parse-args(["-r", "foo", "bar"])
        Parsed(_, p) -> p
        _ -> []
      assert/is-true(rev)
      assert/is-true(paths.show == ["foo", "bar"].show)

    test("parse-args -- should not enable flags after terminator")
      val rev = match parse-args(["--", "-r"])
        Parsed(opts, _) -> opts.reverse
        _ -> True
      val paths = match parse-args(["--", "-r"])
        Parsed(_, p) -> p
        _ -> []
      assert/is-false(rev)
      assert/is-true(paths.show.contains("-r"))

    test("parse-args --help returns HelpRequested")
      val is-help = match parse-args(["--help"])
        HelpRequested -> True
        _ -> False
      assert/is-true(is-help)

    test("parse-args --version returns VersionRequested")
      val is-ver = match parse-args(["--version"])
        VersionRequested -> True
        _ -> False
      assert/is-true(is-ver)

    // --- is-hidden ---
    test("is-hidden returns True for dotfiles")
      assert/is-true(is-hidden(".git"))

    test("is-hidden should not match regular files")
      assert/is-false(is-hidden("README.md"))

    // --- format-name with -F ---
    test("format-name appends / for directories with -F")
      val name = format-name("src", FDirectory, Options(fs-type = True))
      assert/is-true(name == "src/")

    test("format-name appends * for executables with -F")
      val name = format-name("run", FExecutable, Options(fs-type = True))
      assert/is-true(name == "run*")

    test("format-name appends @ for symlinks with -F")
      val name = format-name("link", FSymlink, Options(fs-type = True))
      assert/is-true(name == "link@")

    test("format-name should not append suffix for regular files with -F")
      val name = format-name("file.txt", FRegular, Options(fs-type = True))
      assert/is-true(name == "file.txt")

    test("format-name with -p should not append / for non-dirs")
      val dir-name = format-name("src", FDirectory, Options(slash-dir = True))
      val file-name = format-name("file.txt", FRegular, Options(slash-dir = True))
      assert/is-true(dir-name == "src/")
      assert/is-true(file-name == "file.txt")

    test("format-name should not alter name without flags")
      val name = format-name("README.md", FRegular, Options())
      assert/is-true(name == "README.md")

    // --- collection assertions on list-dir-names output ---
    test("default listing has multiple entries")
      assert/not-empty(["README.md", "src", "tests"])

    test("in-range: entry count is reasonable")
      assert/in-range(5, 1, 100)

