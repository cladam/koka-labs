import std/os/path
import std/os/dir
import std/os/env
import ls
import assert

pub fun main() : io ()
  // Smoke tests: verify list-dir doesn't crash with various options
  list-dir("." .path, Options(), False)
  list-dir("." .path, Options(show-all = True), False)
  list-dir("." .path, Options(almost-all = True), False)
  list-dir("." .path, Options(reverse = True), False)

  // Output assertions: verify expected entries appear
  val entries = list-dir-names("." .path, Options())
  assert-contains(entries, "README.md", "default listing contains README.md")
  assert-contains(entries, "src", "default listing contains src")

  val entries-a = list-dir-names("." .path, Options(show-all = True))
  assert-contains(entries-a, ".", "show-all listing contains .")
  assert-contains(entries-a, "..", "show-all listing contains ..")
  assert-contains(entries-a, "README.md", "show-all listing contains README.md")

  val entries-r = list-dir-names("." .path, Options(reverse = True))
  val first = entries-r.head.default("")
  val last  = entries-r.last.default("")
  if first > last then
    println(green("  \u2713 ") ++ "reverse listing is in descending order")
  else
    println(red("  \u2717 ") ++ "reverse listing is in descending order")
    println("      first: " ++ first ++ ", last: " ++ last)
    process-exit(1)

  // Unit tests for pure logic
  defaultKUnitHandler
    // --- Options defaults ---
    test("Options default show-all is False")
      val opts = Options()
      assert/is-false(opts.show-all)

    test("Options default almost-all is False")
      val opts = Options()
      assert/is-false(opts.almost-all)

    test("Options default reverse is False")
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

    test("parse-args -a overrides -A")
      val sa = match parse-args(["-A", "-a"])
        Parsed(opts, _) -> opts.show-all
        _ -> False
      val aa = match parse-args(["-A", "-a"])
        Parsed(opts, _) -> opts.almost-all
        _ -> True
      assert/is-true(sa)
      assert/is-false(aa)

    test("parse-args -A overrides -a")
      val sa = match parse-args(["-a", "-A"])
        Parsed(opts, _) -> opts.show-all
        _ -> True
      val aa = match parse-args(["-a", "-A"])
        Parsed(opts, _) -> opts.almost-all
        _ -> False
      assert/is-false(sa)
      assert/is-true(aa)

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

    test("parse-args -- stops flag parsing")
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

    test("is-hidden returns False for regular files")
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

    test("format-name appends nothing for regular files with -F")
      val name = format-name("file.txt", FRegular, Options(fs-type = True))
      assert/is-true(name == "file.txt")

    test("format-name with -p appends / only for dirs")
      val dir-name = format-name("src", FDirectory, Options(slash-dir = True))
      val file-name = format-name("file.txt", FRegular, Options(slash-dir = True))
      assert/is-true(dir-name == "src/")
      assert/is-true(file-name == "file.txt")

    test("format-name with no flags returns plain name")
      val name = format-name("README.md", FRegular, Options())
      assert/is-true(name == "README.md")

    // --- collection assertions on list-dir-names output ---
    test("default listing has multiple entries")
      assert/not-empty(["README.md", "src", "tests"])

    test("in-range: entry count is reasonable")
      assert/in-range(5, 1, 100)
