import std/os/path
import std/os/dir
import std/os/env
import ls

pub fun main() : io ()
  // Test simple listing with default options (no flags)
  println("=== Default listing ===")
  list-dir("." .path, Options(), False)

  println("\n=== With -a (show all) ===")
  list-dir("." .path, Options(show-all = True), False)

  println("\n=== With -A (almost all) ===")
  list-dir("." .path, Options(almost-all = True), False)

  println("\n=== With -r (reverse) ===")
  list-dir("." .path, Options(reverse = True), False)
