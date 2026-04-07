// ---------------------------------------------------------------------------
// assert.kk — lightweight xUnit-style test framework for Koka
// ---------------------------------------------------------------------------

extern process-exit(code : int) : io ()
  c inline "exit(kk_integer_clamp32(#1,kk_context()))"

// ---------------------------------------------------------------------------
// ANSI helpers
// ---------------------------------------------------------------------------

val ansi-reset  = "\x1B[0m"
val ansi-green  = "\x1B[32m"
val ansi-red    = "\x1B[31m"
val ansi-yellow = "\x1B[33m"
val ansi-bold   = "\x1B[1m"

fun green(s : string)  : string
  ansi-green  ++ s ++ ansi-reset

fun red(s : string)    : string
  ansi-red    ++ s ++ ansi-reset

fun yellow(s : string) : string
  ansi-yellow ++ s ++ ansi-reset

fun bold(s : string)   : string
  ansi-bold   ++ s ++ ansi-reset

// ---------------------------------------------------------------------------
// Effects
// ---------------------------------------------------------------------------

pub effect kassertion
  fun pass() : ()
  fun fail(
    assertion-function-name: string,
    koka-file-line: string,
    expected: string,
    actually: string) : ()
  fun fatal(message:string): ()

pub effect kunit
  fun test(test-name:string, body: () -> <pure,kassertion, kscenario> (), ?kk-module:string) : ()
  fun skip(test-name:string, body: () -> <pure,kassertion, kscenario> (), ?kk-module:string) : ()

pub effect kscenario
  fun scenario(inputs:a, ?show: a -> string) : ()

// ---------------------------------------------------------------------------
// Assertions
// ---------------------------------------------------------------------------

pub fun assert/equal(expected:a, actual:a, ?eq:(a,a) -> pure bool, ?show:a -> pure string, ?kk-file-line:string) : <pure,kassertion> ()
  if eq(expected, actual)
    then pass()
    else fail(
        assertion-function-name = "assert/equal",
        koka-file-line = kk-file-line,
        expected = expected.show,
        actually = actual.show)

pub fun assert/not-equal(expected:a, actual:a, ?eq:(a,a) -> pure bool, ?show:a -> pure string, ?kk-file-line:string) : <pure,kassertion> ()
  if !eq(expected, actual)
    then pass()
    else fail(
        assertion-function-name = "assert/not-equal",
        koka-file-line = kk-file-line,
        expected = "not " ++ expected.show,
        actually = actual.show)

pub fun assert/is-true(actual:bool, ?kk-file-line:string) : <pure,kassertion> ()
  if actual
    then pass()
    else fail(
        assertion-function-name = "assert/is-true",
        koka-file-line = kk-file-line,
        expected = "True",
        actually = "False")

pub fun assert/is-false(actual:bool, ?kk-file-line:string) : <pure,kassertion> ()
  if !actual
    then pass()
    else fail(
        assertion-function-name = "assert/is-false",
        koka-file-line = kk-file-line,
        expected = "False",
        actually = "True")

// ---------------------------------------------------------------------------
// Scenarios
// ---------------------------------------------------------------------------

pub fun scenarios(inputs: () -> list<a>, body: a -> <pure,kassertion> (), ?show: a -> string) : (() -> <pure, kassertion, kscenario> ())
  fn() inputs().list/foreach(fn(i)
    scenario(i)
    body(i)
  )

// ---------------------------------------------------------------------------
// Default handler — tracks counts and exits non-zero on failure
// ---------------------------------------------------------------------------

pub fun defaultKUnitHandler(action: () -> kunit ()) : io ()
  var testname := ""
  var modulename := ""
  var inputsShow := ""
  var passed := 0
  var failed := 0
  var skipped := 0

  with handler
    fun scenario(inputs, show)
      inputsShow := inputs.show

  with handler
    fun pass()
      passed := passed + 1
      println(green("  \u2713 ") ++ modulename ++ " \"" ++ testname ++ "\"" ++ (if inputsShow == "" then "" else " (" ++ inputsShow ++ ")"))
    fun fail(assertion-function-name, koka-file-line, expected, actually)
      failed := failed + 1
      println(red("  \u2717 ") ++ modulename ++ " \"" ++ testname ++ "\"" ++ (if inputsShow == "" then "" else " (" ++ inputsShow ++ ")"))
      println("    " ++ assertion-function-name ++ " at " ++ koka-file-line)
      println("      expected: " ++ expected)
      println("      actually: " ++ actually)
    fun fatal(message)
      failed := failed + 1
      println(red("  ! ") ++ "fatal: " ++ message)

  with handler
    fun test(test-name, body, module-name)
      modulename := module-name
      testname := test-name
      inputsShow := ""
      body()
    fun skip(test-name, body, module-name)
      skipped := skipped + 1
      println(yellow("  - ") ++ module-name ++ " \"" ++ test-name ++ "\" (skipped)")

  action()

  // Summary
  val total = passed + failed + skipped
  println("")
  println(bold("Results: ") ++ green(passed.show ++ " passed") ++ ", " ++ (if failed > 0 then red(failed.show ++ " failed") else "0 failed") ++ ", " ++ (if skipped > 0 then yellow(skipped.show ++ " skipped") else "0 skipped") ++ " (" ++ total.show ++ " total)")

  if failed > 0 then process-exit(1)