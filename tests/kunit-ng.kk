/*
 * kunit-ng.kk — test framework for Koka with in-file unit test support
 * Based on kunit.kk — lightweight xUnit-style test framework for Koka
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
 *
 * --- In-file unit testing ---
 *
 * Each module defines a `tests` function next to its production code:
 *
 *   // In src/foo.kk
 *   fun some-private-helper() ...
 *
 *   pub fun tests() : kunit ()
 *     test("private helper works")
 *       assert/equal(42, some-private-helper())
 *
 * A test runner composes suites from multiple modules:
 *
 *   // In tests/run-all.kk
 *   import src/foo
 *   import src/bar
 *   import kunit-ng
 *
 *   fun main()
 *     run-suites
 *       suite("foo", src/foo/tests)
 *       suite("bar", src/bar/tests)
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

pub effect kscenario
  fun scenario(inputs:a, ?show: a -> string) : ()

// ---------------------------------------------------------------------------
// Result types — structured test outcomes for composability
// ---------------------------------------------------------------------------

pub type test-outcome
  TPassed
  TFailed(details: string)
  TSkipped

pub struct test-result
  suite-name: string
  test-name: string
  module-name: string
  outcome: test-outcome

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
// Collecting handler — run unit tests and return structured results
// ---------------------------------------------------------------------------

fun collect-tests(sname: string, action: () -> kunit ()) : io list<test-result>
  var results := Nil
  var inputsShow := ""
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
      inputsShow := ""
      test-failed := False
      fail-details := ""
      body()
      val suffix = if inputsShow == "" then "" else " (" ++ inputsShow ++ ")"
      val outcome = if test-failed then TFailed(fail-details) else TPassed
      results := Cons(Test-result(sname, test-name ++ suffix, module-name, outcome), results)
    fun skip(test-name, body, module-name)
      results := Cons(Test-result(sname, test-name, module-name, TSkipped), results)

  action()
  results.reverse

// ---------------------------------------------------------------------------
// Suite effect — compose tests from multiple modules
// ---------------------------------------------------------------------------

pub effect ksuite
  fun suite(name: string, action: () -> kunit ()) : ()

// ---------------------------------------------------------------------------
// Reporter — prints structured results and exits non-zero on failure
// ---------------------------------------------------------------------------

fun report-results(results: list<test-result>) : io ()
  var current-suite := ""
  var passed := 0
  var failed := 0
  var skipped := 0

  results.foreach fn(r)
    // Print suite header when entering a new suite
    if r.suite-name != "" && r.suite-name != current-suite then
      current-suite := r.suite-name
      println("")
      println(bold("\u25CF " ++ r.suite-name))
    match r.outcome
      TPassed ->
        passed := passed + 1
        println(green("  \u2713 ") ++ r.module-name ++ " \"" ++ r.test-name ++ "\"")
      TFailed(details) ->
        failed := failed + 1
        println(red("  \u2717 ") ++ r.module-name ++ " \"" ++ r.test-name ++ "\"")
        print(details)
      TSkipped ->
        skipped := skipped + 1
        println(yellow("  - ") ++ r.module-name ++ " \"" ++ r.test-name ++ "\" (skipped)")

  // Summary
  val total = passed + failed + skipped
  println("")
  println(bold("Results: ") ++ green(passed.show ++ " passed") ++ ", " ++ (if failed > 0 then red(failed.show ++ " failed") else "0 failed") ++ ", " ++ (if skipped > 0 then yellow(skipped.show ++ " skipped") else "0 skipped") ++ " (" ++ total.show ++ " total)")

  if failed > 0 then process-exit(1)

// ---------------------------------------------------------------------------
// Suite runner — handles ksuite effect, collects all results, reports once
//
// Usage:
//   run-suites
//     suite("foo", src/foo/tests)
//     suite("bar", src/bar/tests)
// ---------------------------------------------------------------------------

pub fun run-suites(action: () -> <io,ksuite> ()) : io ()
  var all-results := Nil
  with handler
    fun suite(name, body)
      val results = collect-tests(name, body)
      all-results := all-results ++ results
  action()
  report-results(all-results)

// ---------------------------------------------------------------------------
// Single-suite shortcut — run tests from one module directly
//
// Usage:
//   run-tests
//     test("something works")
//       assert/equal(1, 1)
// ---------------------------------------------------------------------------

pub fun run-tests(action: () -> kunit ()) : io ()
  collect-tests("", action).report-results
