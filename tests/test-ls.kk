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
import kunit

// A helper to ensure a file exists with specific content
fun create-test-file(name : string, content : string = "") : <fsys,exn> () {
  val p = name.path
  write-text-file(p, content)
}

pub fun main() : io ()
  // Smoke tests: verify list-dir doesn't crash with various options
  println(bold("Running smoke tests..."))

  with fun write(fd, s) print(s)    // bio handler: route to real stdout
  list-dir("." .path, Options(), False)
  list-dir("." .path, Options(show-all = True), False)
  list-dir("." .path, Options(almost-all = True), False)
  list-dir("." .path, Options(reverse = True), False)

  // Use bio effect to capture list-dir output into a string
  fun captured-list-dir(dir : path, opts : options)
    with bio
    with status
    list-dir(dir, opts, False)

  // Integration tests
  println("") // Empty line for better output
  println(bold("Running integration tests..."))
  defaultKIntegrationHandler
    itest("bio: captured output contains README.md")
      val (code, output) = captured-list-dir(".".path, Options(one-entry = True))
      assert/is-true(code == 0)
      assert/is-true(output.contains("README.md"))

    itest("bio: captured output contains src")
      val (code, output) = captured-list-dir(".".path, Options(one-entry = True))
      assert/is-true(code == 0)
      assert/is-true(output.contains("src"))
    // Output assertions: verify expected entries appear
    itest("default listing contains README.md")
      val (entries, _) = list-dir-names("." .path, Options())
      assert/is-true(entries.any(fn(e) e.fst == "README.md"))

    itest("default listing contains src")
      val (entries, _) = list-dir-names("." .path, Options())
      assert/is-true(entries.any(fn(e) e.fst == "src"))

    itest("show-all listing contains .")
      val (entries, _) = list-dir-names("." .path, Options(show-all = True))
      assert/is-true(entries.any(fn(e) e.fst == "."))

    itest("show-all listing contains ..")
      val (entries, _) = list-dir-names("." .path, Options(show-all = True))
      assert/is-true(entries.any(fn(e) e.fst == ".."))

    itest("show-all listing contains README.md")
      val (entries, _) = list-dir-names("." .path, Options(show-all = True))
      assert/is-true(entries.any(fn(e) e.fst == "README.md"))

    itest("reverse listing is in descending order")
      val (entries-r, _) = list-dir-names("." .path, Options(reverse = True))
      val first = entries-r.head.default(("", 0, "")).fst
      val last  = entries-r.last.default(("", 0, "")).fst
      assert/is-true(first > last)

    // --- recursive integration tests ---
    itest("-R: recursive listing includes subdirectory header")
      val (code, output) = captured-list-dir(".".path, Options(one-entry = True, recurse = True))
      assert/is-true(code == 0)
      assert/is-true(output.contains("src:"))

    itest("-R: recursive listing includes files from subdirectories")
      val (code, output) = captured-list-dir(".".path, Options(one-entry = True, recurse = True))
      assert/is-true(code == 0)
      assert/is-true(output.contains("ls.kk"))

    itest("-R: recursive listing does not recurse into . or ..")
      val (code, output) = captured-list-dir(".".path, Options(one-entry = True, recurse = True))
      assert/is-true(code == 0)
      assert/is-false(output.contains("./.:" ))
      assert/is-false(output.contains("./..:" ))

    // --- ignore-backups integration test ---
    itest("-B: default listing shows backup file")
      val backup-file = "tests/test-ls.kk~"
      create-test-file(backup-file, "backup content")
      val (entries, _) = list-dir-names("tests".path, Options())
      assert/is-true(entries.any(fn(e) e.fst == "test-ls.kk~"))

    itest("-B: ignore-backups hides backup file")
      val (entries, _) = list-dir-names("tests".path, Options(ignore-backups = True))
      assert/is-true(entries.all(fn(e) e.fst != "test-ls.kk~"))

    // --- inode integration tests ---
    itest("-i: list-dir-names returns non-zero inodes")
      val (entries, _) = list-dir-names(".".path, Options(print-inode = True))
      // All inodes from readdir should be > 0
      assert/is-true(entries.all(fn(e) e.snd > 0))

    itest("-i: inodes are consistent across calls")
      val (entries1, _) = list-dir-names(".".path, Options(print-inode = True))
      val (entries2, _) = list-dir-names(".".path, Options(print-inode = True))
      val ino1 = entries1.filter(fn(e) e.fst == "README.md").head.default(("", 0, "")).snd
      val ino2 = entries2.filter(fn(e) e.fst == "README.md").head.default(("", 0, "")).snd
      assert/is-true(ino1 > 0)
      assert/is-true(ino1 == ino2)

    itest("-i: captured output contains inode numbers")
      val (code, output) = captured-list-dir(".".path, Options(one-entry = True, print-inode = True))
      assert/is-true(code == 0)
      // Each line should start with spaces/digits (the inode), then a space, then the name
      val has-readme = output.lines.any fn(line)
        line.contains("README.md") && line.trim.head-char.default(' ').is-digit
      assert/is-true(has-readme)

    itest("-i with -a: . and .. have inodes")
      val (entries, _) = list-dir-names(".".path, Options(show-all = True, print-inode = True))
      val dot-ino = entries.filter(fn(e) e.fst == ".").head.default(("", 0, "")).snd
      val dotdot-ino = entries.filter(fn(e) e.fst == "..").head.default(("", 0, "")).snd
      assert/is-true(dot-ino > 0)
      assert/is-true(dotdot-ino > 0)

    itest("-i: read-dir-entries returns entries with inodes")
      val entries = read-dir-entries(".".path)
      assert/not-empty(entries)
      // At least one entry should have a non-zero inode
      assert/is-true(entries.any(fn(e) e.entry-ino > 0))

  // Unit tests for pure logic
  println("") // Empty line for better output
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

    test("parse-args -d enables dir-only")
      val do = match parse-args(["-d"])
        Parsed(opts, _) -> opts.dir-only
        _ -> False
      assert/is-true(do)

    test("parse-args --directory enables dir-only")
      val do = match parse-args(["--directory"])
        Parsed(opts, _) -> opts.dir-only
        _ -> False
      assert/is-true(do)

    test("parse-args -r enables reverse")
      val rev = match parse-args(["-r"])
        Parsed(opts, _) -> opts.reverse
        _ -> False
      assert/is-true(rev)

    test("parse-args -R enables recursive")
      val rec = match parse-args(["-R"])
        Parsed(opts, _) -> opts.recurse
        _ -> False
      assert/is-true(rec)

    test("parse-args --recursive enables recursive")
      val rec = match parse-args(["--recursive"])
        Parsed(opts, _) -> opts.recurse
        _ -> False
      assert/is-true(rec)

    test("Options should not have recursive by default")
      val opts = Options()
      assert/is-false(opts.recurse)

    test("parse-args -U enables sort-none")
      val ns = match parse-args(["-U"])
        Parsed(opts, _) -> opts.sort-by.is-sortNone
        _ -> False
      assert/is-true(ns)

    test("parse-args -t enables sort-time")
      val st = match parse-args(["-t"])
        Parsed(opts, _) -> opts.sort-by.is-sortTime
        _ -> False
      assert/is-true(st)

    test("parse-args -c sets time-type to ctime")
      val ct = match parse-args(["-c"])
        Parsed(opts, _) -> opts.time-type.is-timeCtime
        _ -> False
      assert/is-true(ct)

    test("parse-args -u sets time-type to atime")
      val at = match parse-args(["-u"])
        Parsed(opts, _) -> opts.time-type.is-timeAtime
        _ -> False
      assert/is-true(at)

    test("parse-args --sort=time enables sort-time")
      val st = match parse-args(["--sort=time"])
        Parsed(opts, _) -> opts.sort-by.is-sortTime
        _ -> False
      assert/is-true(st)

    test("parse-args --time=atime sets time-type")
      val at = match parse-args(["--time=atime"])
        Parsed(opts, _) -> opts.time-type.is-timeAtime
        _ -> False
      assert/is-true(at)

    test("parse-args --time=ctime sets time-type")
      val ct = match parse-args(["--time=ctime"])
        Parsed(opts, _) -> opts.time-type.is-timeCtime
        _ -> False
      assert/is-true(ct)

    test("parse-args --time=bogus returns InvalidFlag")
      val invalid = match parse-args(["--time=bogus"])
        InvalidFlag(_) -> True
        _ -> False
      assert/is-true(invalid)

    test("parse-args -X enables sort-extension")
      val sx = match parse-args(["-X"])
        Parsed(opts, _) -> opts.sort-by.is-sortExtension
        _ -> False
      assert/is-true(sx)

    test("parse-args --sort=extension enables sort-extension")
      val sx = match parse-args(["--sort=extension"])
        Parsed(opts, _) -> opts.sort-by.is-sortExtension
        _ -> False
      assert/is-true(sx)

    test("get-extension of README.md is .md")
      assert/is-true(get-extension("README.md") == ".md")

    test("get-extension of Makefile is empty")
      assert/is-true(get-extension("Makefile") == "")

    test("get-extension of archive.tar.gz is .gz")
      assert/is-true(get-extension("archive.tar.gz") == ".gz")

    test("get-extension of .gitignore is .gitignore")
      assert/is-true(get-extension(".gitignore") == ".gitignore")

    test("parse-args -F enables classify")
      val ft = match parse-args(["-F"])
        Parsed(opts, _) -> opts.classify.is-classifyAlways
        _ -> False
      assert/is-true(ft)

    test("parse-args -I without pattern returns InvalidFlag")
      val invalid = match parse-args(["-I"])
        InvalidFlag(_) -> True
        _ -> False
      assert/is-true(invalid)

    test("parse-args -I with pattern stores it in ignore-patterns")
      val pats = match parse-args(["-I", "*.txt"])
        Parsed(opts, _) -> opts.ignore-patterns
        _ -> []
      assert/is-true(pats.show == ["*.txt"].show)

    test("parse-args --ignore=PATTERN stores pattern")
      val pats = match parse-args(["--ignore=*.md"])
        Parsed(opts, _) -> opts.ignore-patterns
        _ -> []
      assert/is-true(pats.show == ["*.md"].show)

    test("parse-args --hide=PATTERN stores pattern")
      val pats = match parse-args(["--hide=*.log"])
        Parsed(opts, _) -> opts.hide-patterns
        _ -> []
      assert/is-true(pats.show == ["*.log"].show)

    test("parse-args combined flags -arF")
      val sa = match parse-args(["-arF"])
        Parsed(opts, _) -> opts.show-all
        _ -> False
      val rev = match parse-args(["-arF"])
        Parsed(opts, _) -> opts.reverse
        _ -> False
      val ft = match parse-args(["-arF"])
        Parsed(opts, _) -> opts.classify.is-classifyAlways
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

    // Invalid flag
    test("parse-args -j should trigger InvalidFlag")
      val invalid = match parse-args(["-j"]) // -j isn't being used in GNU ls
        InvalidFlag(_) -> True
        _ -> False
      assert/is-true(invalid)

    test("parse-args --bogus is just bogus")
      val invalid = match parse-args(["--bogus"]) // no bogus
        InvalidFlag(_) -> True
        _ -> False
      assert/is-true(invalid)

    // --- is-hidden ---
    test("is-hidden returns True for dotfiles")
      assert/is-true(is-hidden(".git"))

    test("is-hidden should not match regular files")
      assert/is-false(is-hidden("README.md"))

    // --- format-name with -F ---
    test("format-name appends / for directories with -F")
      val name = format-name("src", FDirectory, Options(classify = ClassifyAlways))
      assert/is-true(name == "src/")

    test("format-name appends * for executables with -F")
      val name = format-name("run", FExecutable, Options(classify = ClassifyAlways))
      assert/is-true(name == "run*")

    test("format-name appends @ for symlinks with -F")
      val name = format-name("link", FSymlink, Options(classify = ClassifyAlways))
      assert/is-true(name == "link@")

    test("format-name should not append suffix for regular files with -F")
      val name = format-name("file.txt", FRegular, Options(classify = ClassifyAlways))
      assert/is-true(name == "file.txt")

    test("format-name with -p should not append / for non-dirs")
      val dir-name = format-name("src", FDirectory, Options(indicator = IndicatorSlash))
      val file-name = format-name("file.txt", FRegular, Options(indicator = IndicatorSlash))
      assert/is-true(dir-name == "src/")
      assert/is-true(file-name == "file.txt")

    test("format-name should not alter name without flags")
      val name = format-name("README.md", FRegular, Options())
      assert/is-true(name == "README.md")

    // --- format-name with --file-type ---
    test("format-name --file-type appends / for directories")
      val name = format-name("src", FDirectory, Options(indicator = IndicatorFileType))
      assert/is-true(name == "src/")

    test("format-name --file-type does not append * for executables")
      val name = format-name("run", FExecutable, Options(indicator = IndicatorFileType))
      assert/is-true(name == "run")

    test("format-name --file-type appends @ for symlinks")
      val name = format-name("link", FSymlink, Options(indicator = IndicatorFileType))
      assert/is-true(name == "link@")

    test("format-name --file-type appends = for sockets")
      val name = format-name("sock", FSocket, Options(indicator = IndicatorFileType))
      assert/is-true(name == "sock=")

    test("format-name --file-type appends | for fifos")
      val name = format-name("pipe", FFifo, Options(indicator = IndicatorFileType))
      assert/is-true(name == "pipe|")

    // --- format-name with --indicator-style=classify ---
    test("format-name --indicator-style=classify acts like -F")
      val name = format-name("run", FExecutable, Options(indicator = IndicatorClassify))
      assert/is-true(name == "run*")

    // --- parse-args: --file-type and --indicator-style ---
    test("parse-args --file-type sets indicator to IndicatorFileType")
      val ind = match parse-args(["--file-type"])
        Parsed(opts, _) -> opts.indicator.is-indicatorFileType
        _ -> False
      assert/is-true(ind)

    test("parse-args --indicator-style=slash sets indicator to IndicatorSlash")
      val ind = match parse-args(["--indicator-style=slash"])
        Parsed(opts, _) -> opts.indicator.is-indicatorSlash
        _ -> False
      assert/is-true(ind)

    test("parse-args --indicator-style=file-type sets indicator")
      val ind = match parse-args(["--indicator-style=file-type"])
        Parsed(opts, _) -> opts.indicator.is-indicatorFileType
        _ -> False
      assert/is-true(ind)

    test("parse-args --indicator-style=classify sets indicator")
      val ind = match parse-args(["--indicator-style=classify"])
        Parsed(opts, _) -> opts.indicator.is-indicatorClassify
        _ -> False
      assert/is-true(ind)

    test("parse-args --indicator-style=none sets indicator")
      val ind = match parse-args(["--indicator-style=none"])
        Parsed(opts, _) -> opts.indicator.is-indicatorNone
        _ -> False
      assert/is-true(ind)

    test("parse-args --indicator-style=bogus returns InvalidFlag")
      val invalid = match parse-args(["--indicator-style=bogus"])
        InvalidFlag(_) -> True
        _ -> False
      assert/is-true(invalid)

    test("parse-args -p sets indicator to IndicatorSlash")
      val ind = match parse-args(["-p"])
        Parsed(opts, _) -> opts.indicator.is-indicatorSlash
        _ -> False
      assert/is-true(ind)

    // --- collection assertions on list-dir-names output ---
    test("default listing has multiple entries")
      assert/not-empty(["README.md", "src", "tests"])

    test("in-range: entry count is reasonable")
      assert/in-range(5, 1, 100)

    // --- parse-args: -i / --inode ---
    test("parse-args -i enables print-inode")
      val pi = match parse-args(["-i"])
        Parsed(opts, _) -> opts.print-inode
        _ -> False
      assert/is-true(pi)

    test("parse-args --inode enables print-inode")
      val pi = match parse-args(["--inode"])
        Parsed(opts, _) -> opts.print-inode
        _ -> False
      assert/is-true(pi)

    test("parse-args -i combined with other flags")
      val result = parse-args(["-1i"])
      match result
        Parsed(opts, _) ->
          assert/is-true(opts.print-inode)
          assert/is-true(opts.one-entry)
        _ -> assert/is-true(False)

    test("Options should not have print-inode by default")
      val opts = Options()
      assert/is-false(opts.print-inode)

    // --- format-inode ---
    test("format-inode right-justifies to given width")
      val s = format-inode(42, 6)
      assert/is-true(s == "    42")

    test("format-inode with exact width has no padding")
      val s = format-inode(12345, 5)
      assert/is-true(s == "12345")

    test("format-inode with large inode")
      val s = format-inode(167835661, 9)
      assert/is-true(s == "167835661")

    // --- inode-width ---
    test("inode-width returns max display width")
      val entries = [("a", 1), ("b", 999), ("c", 42)]
      val w = inode-width(entries)
      assert/is-true(w == 3)

    test("inode-width of empty list is 0")
      val entries : list<(string, int)> = []
      val w = inode-width(entries)
      assert/is-true(w == 0)

    // --- format-entries ---
    test("format-entries without -i returns plain names")
      val entries = [("README.md", 123), ("src", 456)]
      val result = format-entries(entries, Options())
      assert/is-true(result == ["README.md", "src"])

    test("format-entries with -i prepends inode")
      val entries = [("README.md", 42), ("src", 999)]
      val result = format-entries(entries, Options(print-inode = True))
      assert/is-true(result == [" 42 README.md", "999 src"])

    // --- parse-readdir ---
    test("parse-readdir parses inode-tab-name format")
      val input = "123\tfile1\n456\tfile2\n"
      val entries = parse-readdir(input)
      match entries
        Cons(e1, Cons(e2, Nil)) ->
          assert/is-true(e1.entry-name == "file1")
          assert/is-true(e1.entry-ino == 123)
          assert/is-true(e2.entry-name == "file2")
          assert/is-true(e2.entry-ino == 456)
        _ -> assert/is-true(False)

    test("parse-readdir handles empty string")
      val entries = parse-readdir("")
      assert/is-true(entries.is-nil)

    // --- parse-args: --sort=width ---
    test("parse-args --sort=width enables sort-width")
      val sw = match parse-args(["--sort=width"])
        Parsed(opts, _) -> opts.sort-by.is-sortWidth
        _ -> False
      assert/is-true(sw)

    // --- parse-args: --group-directories-first ---
    test("parse-args --group-directories-first enables group-dirs")
      val gd = match parse-args(["--group-directories-first"])
        Parsed(opts, _) -> opts.group-dirs
        _ -> False
      assert/is-true(gd)

    test("Options should not have group-dirs by default")
      val opts = Options()
      assert/is-false(opts.group-dirs)

    // --- parse-args: -v / --sort=version ---
    test("parse-args -v enables sort-version")
      val sv = match parse-args(["-v"])
        Parsed(opts, _) -> opts.sort-by.is-sortVersion
        _ -> False
      assert/is-true(sv)

    test("parse-args --sort=version enables sort-version")
      val sv = match parse-args(["--sort=version"])
        Parsed(opts, _) -> opts.sort-by.is-sortVersion
        _ -> False
      assert/is-true(sv)

    // --- filevercmp unit tests ---
    test("filevercmp: a1 < a2")
      assert/is-true(filevercmp("a1", "a2") < 0)

    test("filevercmp: a2 < a10")
      assert/is-true(filevercmp("a2", "a10") < 0)

    test("filevercmp: a1 < a13 < a120")
      assert/is-true(filevercmp("a1", "a13") < 0)
      assert/is-true(filevercmp("a13", "a120") < 0)

    test("filevercmp: equal strings")
      assert/is-true(filevercmp("hello", "hello") == 0)

    test("filevercmp: dotfiles before non-dotfiles")
      assert/is-true(filevercmp(".hidden", "visible") < 0)

    test("filevercmp: dot sorts first")
      assert/is-true(filevercmp(".", "..") < 0)
      assert/is-true(filevercmp("..", ".hidden") < 0)

    test("filevercmp: extension handling")
      assert/is-true(filevercmp("hello-8.txt", "hello-8.2.txt") < 0)

    // --- parse-stat-info unit tests ---
    test("parse-stat-info parses valid tab-separated input")
      val input = "-rw-r--r--\t1\tuser\t501\tstaff\t20\t1234\t1000000\t0\t8"
      match parse-stat-info(input)
        Just(fi) ->
          assert/is-true(fi.fi-mode == "-rw-r--r--")
          assert/is-true(fi.fi-nlink == 1)
          assert/is-true(fi.fi-owner == "user")
          assert/is-true(fi.fi-uid == 501)
          assert/is-true(fi.fi-group == "staff")
          assert/is-true(fi.fi-gid == 20)
          assert/is-true(fi.fi-size == 1234)
          assert/is-true(fi.fi-mtime-sec == 1000000)
          assert/is-true(fi.fi-mtime-nsec == 0)
          assert/is-true(fi.fi-blocks == 8)
        Nothing -> assert/is-true(False)

    test("parse-stat-info returns Nothing for empty string")
      assert/is-true(parse-stat-info("").is-nothing)

    test("parse-stat-info returns Nothing for malformed input")
      assert/is-true(parse-stat-info("just\ttwo").is-nothing)

    // --- parse-args: -l ---
    test("parse-args -l enables long-format")
      match parse-args(["-l"])
        Parsed(opts, _) -> assert/is-true(opts.long-format)
        _ -> assert/is-true(False)

    test("Options should not have long-format by default")
      val opts = Options()
      assert/is-false(opts.long-format)

    test("-l disables one-entry and force-columns")
      match parse-args(["-1", "-l"])
        Parsed(opts, _) ->
          assert/is-true(opts.long-format)
          assert/is-false(opts.one-entry)
        _ -> assert/is-true(False)

    test("-1 disables long-format")
      match parse-args(["-l", "-1"])
        Parsed(opts, _) ->
          assert/is-false(opts.long-format)
          assert/is-true(opts.one-entry)
        _ -> assert/is-true(False)

    test("-C disables long-format")
      match parse-args(["-l", "-C"])
        Parsed(opts, _) ->
          assert/is-false(opts.long-format)
          assert/is-true(opts.force-columns)
        _ -> assert/is-true(False)

    test("-l can combine with other flags")
      match parse-args(["-la"])
        Parsed(opts, _) ->
          assert/is-true(opts.long-format)
          assert/is-true(opts.show-all)
        _ -> assert/is-true(False)

    // --- parse-args: -G ---
    test("parse-args -G enables no-group")
      match parse-args(["-G"])
        Parsed(opts, _) ->
          assert/is-true(opts.no-group)
        _ -> assert/is-true(False)

    test("parse-args --no-group enables no-group")
      match parse-args(["--no-group"])
        Parsed(opts, _) ->
          assert/is-true(opts.no-group)
        _ -> assert/is-true(False)

    // -- parse-args: -g for no owner ---
    test("parse-args -g enables no-owner")
      match parse-args(["-g"])
        Parsed(opts, _) ->
          assert/is-true(opts.no-owner)
        _ -> assert/is-true(False)

    test("parse-args -o enables no-group")
      match parse-args(["-o"])
        Parsed(opts, _) ->
          assert/is-true(opts.no-group)
          assert/is-true(opts.long-format)
        _ -> assert/is-true(False)

    // --- parse-args: -n for numeric uid/gid ---
    test("parse-args -n enables numeric-ids and long-format")
      match parse-args(["-n"])
        Parsed(opts, _) ->
          assert/is-true(opts.numeric-ids)
          assert/is-true(opts.long-format)
        _ -> assert/is-true(False)

    test("parse-args --numeric-uid-gid enables numeric-ids and long-format")
      match parse-args(["--numeric-uid-gid"])
        Parsed(opts, _) ->
          assert/is-true(opts.numeric-ids)
          assert/is-true(opts.long-format)
        _ -> assert/is-true(False)

    test("parse-args -n disables one-entry and force-columns")
      match parse-args(["-1n"])
        Parsed(opts, _) ->
          assert/is-true(opts.numeric-ids)
          assert/is-true(opts.long-format)
          assert/is-false(opts.one-entry)
          assert/is-false(opts.force-columns)
        _ -> assert/is-true(False)

  // --- file-info integration tests ---
  println("")
  println(bold("Running file-info integration tests..."))
  defaultKIntegrationHandler
    itest("get-file-info returns Just for existing file")
      assert/is-true(get-file-info("README.md").is-just)

    itest("get-file-info returns Nothing for nonexistent file")
      assert/is-true(get-file-info("nonexistent-xyz").is-nothing)

    itest("file-info: regular file mode starts with -")
      match get-file-info("README.md")
        Just(fi) -> assert/is-true(fi.fi-mode.head-char.default(' ') == '-')
        Nothing  -> assert/is-true(False)

    itest("file-info: directory mode starts with d")
      match get-file-info("src")
        Just(fi) -> assert/is-true(fi.fi-mode.head-char.default(' ') == 'd')
        Nothing  -> assert/is-true(False)

    itest("file-info: nlink is positive")
      match get-file-info("README.md")
        Just(fi) -> assert/is-true(fi.fi-nlink > 0)
        Nothing  -> assert/is-true(False)

    itest("file-info: owner is non-empty")
      match get-file-info("README.md")
        Just(fi) -> assert/is-true(fi.fi-owner.count > 0)
        Nothing  -> assert/is-true(False)

    itest("file-info: group is non-empty")
      match get-file-info("README.md")
        Just(fi) -> assert/is-true(fi.fi-group.count > 0)
        Nothing  -> assert/is-true(False)

    itest("file-info: size is positive for non-empty file")
      match get-file-info("README.md")
        Just(fi) -> assert/is-true(fi.fi-size > 0)
        Nothing  -> assert/is-true(False)

    itest("file-info: mtime is positive")
      match get-file-info("README.md")
        Just(fi) -> assert/is-true(fi.fi-mtime-sec > 0)
        Nothing  -> assert/is-true(False)

    itest("readlink-path returns empty for regular file")
      assert/is-true(readlink-path("README.md").is-empty)

    itest("readlink-path returns target for symlink")
      assert/is-true(readlink-path("tests/README.md") == "../README.md")

    itest("readlink-path returns empty for nonexistent file")
      assert/is-true(readlink-path("nonexistent-xyz").is-empty)

    itest("format-timestamp: recent file shows month and time")
      // Use mtime from a real file — should be recent
      match get-file-info("README.md")
        Just(fi) ->
          val ts = format-timestamp(fi.fi-mtime-sec)
          // Should contain a month abbreviation (3 letters) and a colon (HH:MM)
          assert/is-true(ts.count > 0)
          assert/is-true(ts.contains(":"))
        Nothing -> assert/is-true(False)

    itest("format-timestamp: old date shows year instead of time")
      // Jan 1, 2020 00:00:00 UTC = 1577836800
      val ts = format-timestamp(1577836800)
      assert/is-true(ts.contains("2020"))
      assert/is-false(ts.contains(":"))

    // --- long-format (-l) integration tests ---
    itest("-l: output contains total line")
      val (code, output) = captured-list-dir(".".path, Options(long-format = True))
      assert/is-true(code == 0)
      assert/is-true(output.starts-with("total ").bool)

    itest("-l: output contains mode string")
      val (code, output) = captured-list-dir(".".path, Options(long-format = True))
      assert/is-true(code == 0)
      // src directory should show drwx
      assert/is-true(output.contains("drwx"))

    itest("-l: output contains owner and group")
      val (code, output) = captured-list-dir(".".path, Options(long-format = True))
      assert/is-true(code == 0)
      // Should contain at least the current user's name
      match get-file-info("README.md")
        Just(fi) -> assert/is-true(output.contains(fi.fi-owner))
        Nothing  -> assert/is-true(False)

    itest("-l: symlink shows -> target")
      val (code, output) = captured-list-dir("tests".path, Options(long-format = True))
      assert/is-true(code == 0)
      assert/is-true(output.contains("-> ../README.md"))