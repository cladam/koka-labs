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

  // Unit tests for pure logic
  defaultKUnitHandler
    test("Options default show-all is False")
      val opts = Options()
      is-false(opts.show-all)

    test("Options default almost-all is False")
      val opts = Options()
      is-false(opts.almost-all)

    test("Options default reverse is False")
      val opts = Options()
      is-false(opts.reverse)

    test("Options show-all can be set to True")
      val opts = Options(show-all = True)
      is-true(opts.show-all)
