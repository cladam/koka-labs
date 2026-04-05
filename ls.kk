// list files
import std/os/path
import std/os/dir
import std/os/env
import std/os/flags

// The main entry point.
// The effects <console, fsys, env> tell the compiler exactly what this program can do.
fun main() {
  // Get command line arguments
  val args = get-args()

  // Use the first argument as path, or default to current directory "."
  val dir-path = args.head.unjust.path

  println("Listing contents of: " ++ dir-path.string)
  println("---------------------------------------")

  // list-directory returns a list of filenames
  // we use .foreach and the dot-selection you liked!
  list-directory(dir-path).foreach fn(name) {
    println(name)
  }
}
