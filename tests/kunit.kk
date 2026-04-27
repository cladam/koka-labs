/*
 * kunit.kk — lightweight xUnit-style test framework for Koka
 * Inspired by KUnit - https://github.com/koka-community/kunit Thanks!
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

pub extern process-exit(code : int) : io ()
  c inline "exit(kk_integer_clamp32(#1,kk_context()))"

// ---------------------------------------------------------------------------
// ANSI helpers
// ---------------------------------------------------------------------------

val ansi-reset  = "\x1B[0m"
val ansi-green  = "\x1B[32m"
val ansi-red    = "\x1B[31m"
val ansi-yellow = "\x1B[33m"
val ansi-bold   = "\x1B[1m"

pub fun green(s : string)  : string
  ansi-green  ++ s ++ ansi-reset

pub fun red(s : string)    : string
  ansi-red    ++ s ++ ansi-reset

fun yellow(s : string) : string
  ansi-yellow ++ s ++ ansi-reset

pub fun bold(s : string)   : string
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

// Divergent unit tests — for test bodies that involve recursive functions
// (e.g. parsers, tree walkers) which carry the `div` effect but do not
// perform I/O. Prefer this over kintegration when the code under test is
// pure apart from potential non-termination.
// Note: also allows `exn` and `console` since recursive Koka code often
// introduces these effects transitively.
pub effect kdiv
  fun dtest(test-name:string, body: () -> <div,exn,console,kassertion, kscenario> (), ?kk-module:string) : ()
  fun dskip(test-name:string, body: () -> <div,exn,console,kassertion, kscenario> (), ?kk-module:string) : ()

pub effect kintegration
  fun itest(test-name:string, body: () -> <io,kassertion, kscenario> (), ?kk-module:string) : ()
  fun iskip(test-name:string, body: () -> <io,kassertion, kscenario> (), ?kk-module:string) : ()

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
// Collection assertions
// ---------------------------------------------------------------------------

pub fun assert/contains(collection:list<a>, expected:a, ?eq:(a,a) -> pure bool, ?show:a -> pure string, ?kk-file-line:string) : <pure,kassertion> ()
  if collection.any(fn(item) eq(item, expected))
    then pass()
    else fail(
        assertion-function-name = "assert/contains",
        koka-file-line = kk-file-line,
        expected = "collection to contain " ++ expected.show,
        actually = collection.map(show).join(", "))

pub fun assert/not-contains(collection:list<a>, expected:a, ?eq:(a,a) -> pure bool, ?show:a -> pure string, ?kk-file-line:string) : <pure,kassertion> ()
  if !collection.any(fn(item) eq(item, expected))
    then pass()
    else fail(
        assertion-function-name = "assert/not-contains",
        koka-file-line = kk-file-line,
        expected = "collection to not contain " ++ expected.show,
        actually = collection.map(show).join(", "))

pub fun assert/empty(collection:list<a>, ?show:a -> pure string, ?kk-file-line:string) : <pure,kassertion> ()
  match collection
    Nil -> pass()
    _   -> fail(
        assertion-function-name = "assert/empty",
        koka-file-line = kk-file-line,
        expected = "empty collection",
        actually = collection.map(show).join(", "))

pub fun assert/not-empty(collection:list<a>, ?kk-file-line:string) : <pure,kassertion> ()
  match collection
    Nil -> fail(
        assertion-function-name = "assert/not-empty",
        koka-file-line = kk-file-line,
        expected = "non-empty collection",
        actually = "[]")
    _   -> pass()

// ---------------------------------------------------------------------------
// Numeric assertions
// ---------------------------------------------------------------------------

pub fun assert/in-range(actual:a, low:a, high:a, ?cmp:(a,a) -> pure order, ?show:a -> pure string, ?kk-file-line:string) : <pure,kassertion> ()
  if cmp(actual, low) != Lt && cmp(actual, high) != Gt
    then pass()
    else fail(
        assertion-function-name = "assert/in-range",
        koka-file-line = kk-file-line,
        expected = show(low) ++ " .. " ++ show(high),
        actually = actual.show)

pub fun assert/not-in-range(actual:a, low:a, high:a, ?cmp:(a,a) -> pure order, ?show:a -> pure string, ?kk-file-line:string) : <pure,kassertion> ()
  if cmp(actual, low) == Lt || cmp(actual, high) == Gt
    then pass()
    else fail(
        assertion-function-name = "assert/not-in-range",
        koka-file-line = kk-file-line,
        expected = "not in " ++ show(low) ++ " .. " ++ show(high),
        actually = actual.show)

// ---------------------------------------------------------------------------
// Scenarios
// ---------------------------------------------------------------------------

pub fun scenarios(inputs: () -> list<a>, body: a -> <pure,kassertion> (), ?show: a -> string) : (() -> <pure, kassertion, kscenario> ())
  fn() inputs().list/foreach(fn(i)
    scenario(i)
    body(i)
  )

// ---------------------------------------------------------------------------
// Standalone IO assertions (for tests that need side effects)
// ---------------------------------------------------------------------------

pub fun assert-contains(entries : list<string>, name : string, msg : string) : io ()
  if entries.any(fn(e) e == name) then
    println(green("  \u2713 ") ++ msg)
  else
    println(red("  \u2717 ") ++ msg)
    println("      expected to find: " ++ name)
    println("      entries: " ++ entries.show)
    process-exit(1)

pub fun assert-not-contains(entries : list<string>, name : string, msg : string) : io ()
  if entries.all(fn(e) e != name) then
    println(green("  \u2713 ") ++ msg)
  else
    println(red("  \u2717 ") ++ msg)
    println("      expected NOT to find: " ++ name)
    println("      entries: " ++ entries.show)
    process-exit(1)

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
  var test-failed := False
  var fail-details := ""

  with handler
    fun scenario(inputs, show)
      inputsShow := inputs.show

  with handler
    fun pass()
      ()
    fun fail(assertion-function-name, koka-file-line, expected, actually)
      test-failed := True
      fail-details := fail-details ++ "    " ++ assertion-function-name ++ " at " ++ koka-file-line ++ "\n      expected: " ++ expected ++ "\n      actually: " ++ actually ++ "\n"
    fun fatal(message)
      test-failed := True
      fail-details := fail-details ++ "    fatal: " ++ message ++ "\n"

  with handler
    fun test(test-name, body, module-name)
      modulename := module-name
      testname := test-name
      inputsShow := ""
      test-failed := False
      fail-details := ""
      body()
      val suffix = if inputsShow == "" then "" else " (" ++ inputsShow ++ ")"
      if test-failed then
        failed := failed + 1
        println(red("  \u2717 ") ++ modulename ++ " \"" ++ testname ++ "\"" ++ suffix)
        print(fail-details)
      else
        passed := passed + 1
        println(green("  \u2713 ") ++ modulename ++ " \"" ++ testname ++ "\"" ++ suffix)
    fun skip(test-name, body, module-name)
      skipped := skipped + 1
      println(yellow("  - ") ++ module-name ++ " \"" ++ test-name ++ "\" (skipped)")

  action()

  // Summary
  val total = passed + failed + skipped
  println("")
  println(bold("Results: ") ++ green(passed.show ++ " passed") ++ ", " ++ (if failed > 0 then red(failed.show ++ " failed") else "0 failed") ++ ", " ++ (if skipped > 0 then yellow(skipped.show ++ " skipped") else "0 skipped") ++ " (" ++ total.show ++ " total)")

  if failed > 0 then process-exit(1)

// ---------------------------------------------------------------------------
// Divergent handler — like defaultKUnitHandler but allows div in test bodies.
// Use for recursive code (parsers, tree walkers) that is otherwise pure.
// ---------------------------------------------------------------------------

pub fun defaultKDivHandler(action: () -> kdiv ()) : io ()
  var testname := ""
  var modulename := ""
  var inputsShow := ""
  var passed := 0
  var failed := 0
  var skipped := 0
  var test-failed := False
  var fail-details := ""

  with handler
    fun scenario(inputs, show)
      inputsShow := inputs.show

  with handler
    fun pass()
      ()
    fun fail(assertion-function-name, koka-file-line, expected, actually)
      test-failed := True
      fail-details := fail-details ++ "    " ++ assertion-function-name ++ " at " ++ koka-file-line ++ "\n      expected: " ++ expected ++ "\n      actually: " ++ actually ++ "\n"
    fun fatal(message)
      test-failed := True
      fail-details := fail-details ++ "    fatal: " ++ message ++ "\n"

  with handler
    fun dtest(test-name, body, module-name)
      modulename := module-name
      testname := test-name
      inputsShow := ""
      test-failed := False
      fail-details := ""
      body()
      val suffix = if inputsShow == "" then "" else " (" ++ inputsShow ++ ")"
      if test-failed then
        failed := failed + 1
        println(red("  \u2717 ") ++ modulename ++ " \"" ++ testname ++ "\"" ++ suffix)
        print(fail-details)
      else
        passed := passed + 1
        println(green("  \u2713 ") ++ modulename ++ " \"" ++ testname ++ "\"" ++ suffix)
    fun dskip(test-name, body, module-name)
      skipped := skipped + 1
      println(yellow("  - ") ++ module-name ++ " \"" ++ test-name ++ "\" (skipped)")

  action()

  // Summary
  val total = passed + failed + skipped
  println("")
  println(bold("Results: ") ++ green(passed.show ++ " passed") ++ ", " ++ (if failed > 0 then red(failed.show ++ " failed") else "0 failed") ++ ", " ++ (if skipped > 0 then yellow(skipped.show ++ " skipped") else "0 skipped") ++ " (" ++ total.show ++ " total)")

  if failed > 0 then process-exit(1)

// ---------------------------------------------------------------------------
// Integration handler — like defaultKUnitHandler but allows IO in test bodies
// ---------------------------------------------------------------------------

pub fun defaultKIntegrationHandler(action: () -> <io,kintegration> ()) : io ()
  var testname := ""
  var modulename := ""
  var inputsShow := ""
  var passed := 0
  var failed := 0
  var skipped := 0
  var test-failed := False
  var fail-details := ""

  with handler
    fun scenario(inputs, show)
      inputsShow := inputs.show

  with handler
    fun pass()
      ()
    fun fail(assertion-function-name, koka-file-line, expected, actually)
      test-failed := True
      fail-details := fail-details ++ "    " ++ assertion-function-name ++ " at " ++ koka-file-line ++ "\n      expected: " ++ expected ++ "\n      actually: " ++ actually ++ "\n"
    fun fatal(message)
      test-failed := True
      fail-details := fail-details ++ "    fatal: " ++ message ++ "\n"

  with handler
    fun itest(test-name, body, module-name)
      modulename := module-name
      testname := test-name
      inputsShow := ""
      test-failed := False
      fail-details := ""
      body()
      val suffix = if inputsShow == "" then "" else " (" ++ inputsShow ++ ")"
      if test-failed then
        failed := failed + 1
        println(red("  \u2717 ") ++ modulename ++ " \"" ++ testname ++ "\"" ++ suffix)
        print(fail-details)
      else
        passed := passed + 1
        println(green("  \u2713 ") ++ modulename ++ " \"" ++ testname ++ "\"" ++ suffix)
    fun iskip(test-name, body, module-name)
      skipped := skipped + 1
      println(yellow("  - ") ++ module-name ++ " \"" ++ test-name ++ "\" (skipped)")

  action()

  // Summary
  val total = passed + failed + skipped
  println("")
  println(bold("Results: ") ++ green(passed.show ++ " passed") ++ ", " ++ (if failed > 0 then red(failed.show ++ " failed") else "0 failed") ++ ", " ++ (if skipped > 0 then yellow(skipped.show ++ " skipped") else "0 skipped") ++ " (" ++ total.show ++ " total)")

  if failed > 0 then process-exit(1)