import src/ls
import kunit-ng

fun main()
  run-suites
    suite("src/ls", src/ls/tests)
