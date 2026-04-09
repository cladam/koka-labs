/*
 * ls.kk — directory listing (GNU ls clone in Koka)
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
module ls

import std/os/path
import std/os/dir
import std/os/env
import version
import columns

// Import my C code
extern import
  c file "fs-inline.c"

// ---------------------------------------------------------------------------
// C FFI — file-type detection via stat/lstat (POSIX)
// ---------------------------------------------------------------------------

extern is-symlink(p : string) : fsys bool
  c "kk_os_is_symlink"

extern is-executable(p : string) : fsys bool
  c "kk_os_is_executable"

extern is-fifo(p : string) : fsys bool
  c "kk_os_is_fifo"

extern is-socket(p : string) : fsys bool
  c "kk_os_is_socket"

extern stdout-is-tty() : fsys bool
  c "kk_os_isatty_stdout"

extern stat-error(p : string) : fsys string
  c "kk_os_stat_error"

extern eprint(msg : string) : fsys ()
  c "kk_os_eprint"

fun eprintln(msg : string) : fsys ()
  eprint(msg ++ "\n")

// ---------------------------------------------------------------------------
// Options — will grow as I add flags like -l, -R, -t, etc.
// ---------------------------------------------------------------------------

pub struct options
  show-all    : bool = False // -a (includes . and ..)
  almost-all  : bool = False // -A (dotfiles, but not . and ..)
  reverse     : bool = False // -r
  fs-type   : bool = False // -F
  slash-dir : bool = False // -p
  one-entry : bool = False // -1
  force-columns : bool = False // -C
  ignore-backups : bool = False // -B

// ---------------------------------------------------------------------------
// File classification for -F flag
// GNU ls -F appends: / (dir), @ (symlink), * (exec), = (socket),
// | (FIFO), % (whiteout). Symlink is checked first via lstat so that
// a symlink to a directory shows '@' rather than '/'.
// Whiteout is not detected (macOS-specific UFS concept, rare in practice).
// ---------------------------------------------------------------------------

// Create a type for pattern matching
pub type file-kind
  FDirectory
  FRegular
  FSymlink
  FExecutable
  FSocket
  FFifo

fun classify(p : path) : fsys file-kind
  val s = p.string
  if is-symlink(s)      then FSymlink
  elif is-directory(p)  then FDirectory
  elif is-executable(s) then FExecutable
  elif is-socket(s)     then FSocket
  elif is-fifo(s)       then FFifo
  else FRegular

fun suffix(kind : file-kind) : string
  match kind
    FDirectory  -> "/"
    FSymlink    -> "@"
    FExecutable -> "*"
    FSocket     -> "="
    FFifo       -> "|"
    FRegular    -> ""

// Alternatively, combine classify and suffix into one function, not so elegant
fun classify-suffix(p : path) : fsys string
  val s = p.string
  if is-symlink(s)      then "@"
  elif is-directory(p)  then "/"
  elif is-executable(s) then "*"
  elif is-socket(s)     then "="
  elif is-fifo(s)       then "|"
  else ""

// ---------------------------------------------------------------------------
// Help & version
// ---------------------------------------------------------------------------

val usage = [
    "Usage: ls [OPTION]... [FILE]...",
    "List information about the FILEs (the current directory by default).",
    "",
    "  -a, --all              do not ignore entries starting with .(includes . and ..)",
    "  -A, --almost-all       like -a, but do not list . and ..",
    "  -B, --ignore-backups   do not list implied entries ending with ~",
    "  -C                     list entries by columns",
    "  -r, --reverse          reverse order while sorting",
    "  -F, --classify         append indicator (one of /@*=|) to entries",
    "  -p, --slash-dir        append / indicator to directories",
    "  -1                     list one file per line",
    "      --help             show this help and exit",
    "      --version          show version and exit"
].join("\n")

fun show-help() : io ()
  println(usage)

fun show-version() : io ()
  val program = "koka-ls - directory listing (GNU ls clone in Koka)"
  println(program-name  ++ "@" ++ version)
  println("Program: " ++ program)
  println("Author: " ++ author)
  println("Repository: " ++ repository)

// ---------------------------------------------------------------------------
// Argument parsing
// GNU ls supports combined short flags like -ar, -ra, etc.
// We separate flag arguments (starting with '-') from path arguments.
// "--" terminates flag parsing, everything after is a path.
// Long options --help and --version are matched before short-flag expansion.
// ---------------------------------------------------------------------------

pub type parse-result
  Parsed(opts : options, paths : list<string>)
  HelpRequested
  VersionRequested

pub fun parse-args(args : list<string>, opts : options = Options(), paths : list<string> = []) : parse-result
  match args
    Nil -> Parsed(opts, paths.reverse)
    Cons("--", rest) -> Parsed(opts, paths.reverse ++ rest)
    Cons("--help", _) -> HelpRequested
    Cons("--version", _) -> VersionRequested
    // Long options — one match per --flag
    Cons("--all", rest) ->
      parse-args(rest, opts(show-all = True, almost-all = False), paths)
    Cons("--almost-all", rest) ->
      parse-args(rest, opts(almost-all = True, show-all = False), paths)
    Cons("--ignore-backups", rest) ->
      parse-args(rest, opts(ignore-backups = True), paths)
    Cons("--reverse", rest) ->
      parse-args(rest, opts(reverse = True), paths)
    Cons("--classify", rest) ->
      parse-args(rest, opts(fs-type = True), paths)
    // Impure...
    //Cons(arg, rest) | arg.starts-with("--").bool ->
    //  eprintln("ls: unrecognised option '" ++ arg ++ "'")
    //  parse-args(rest, opts, paths)
    // Short flags — can be combined like -ar, -ra, etc.
    Cons(arg, rest) | arg.starts-with("-").bool && arg != "-" ->
      val new-opts = arg.slice.drop(1).string.list.foldl(opts) fn(o, c)
        match c
          'a' -> o(show-all = True, almost-all = False)
          'A' -> o(almost-all = True, show-all = False)
          'r' -> o(reverse = True)
          'F' -> o(fs-type = True)
          'p' -> o(slash-dir = True)
          '1' -> o(one-entry = True, force-columns = False)
          'C' -> o(force-columns = True, one-entry = False)
          'B' -> o(ignore-backups = True)
          _   -> o
      parse-args(rest, new-opts, paths)
    Cons(arg, rest) -> parse-args(rest, opts, Cons(arg, paths))

// ---------------------------------------------------------------------------
// Sorting
// Koka's standard library doesn't include a list sort, so we provide our own.
// Simple insertion sort — fine for directory listings.
// ---------------------------------------------------------------------------

fun insert(x : string, xs : list<string>, cmp : (string, string) -> order) : list<string>
  match xs
    Nil -> [x]
    Cons(y, ys) -> match cmp(x, y)
      Gt -> Cons(y, insert(x, ys, cmp))
      _  -> Cons(x, xs)

fun sort(xs : list<string>, cmp : (string, string) -> order) : list<string>
  match xs
    Nil -> Nil
    Cons(x, rest) -> insert(x, rest.sort(cmp), cmp)

// ---------------------------------------------------------------------------
// Filtering
// GNU ls hides entries starting with '.' by default (IGNORE_DEFAULT mode).
// With -a, all entries are shown.
// ---------------------------------------------------------------------------

pub fun is-hidden(name : string) : bool
  match name.head-char
    Just('.') -> True
    _         -> False

pub fun is-backup(name : string) : bool
  name.ends-with("~").bool

// Format a single entry name with optional -F / -p suffix
pub fun format-name(name : string, kind : file-kind, opts : options) : string
  if opts.fs-type then name ++ kind.suffix
  elif opts.slash-dir then match kind
    FDirectory -> name ++ "/"
    _          -> name
  // Swallow -C for columns as it is default, but -1 overrides it, so we don't need to check that here
  else name

// ---------------------------------------------------------------------------
// Listing
// list-directory returns full paths; we display only the basename, matching
// how GNU ls shows just the name within the listed directory.
// ---------------------------------------------------------------------------

pub fun list-dir-names(dir-path : path, opts : options) : <fsys,exn> list<string>
  val entries = list-directory(dir-path)
  val names   = entries.map fn(p)
    format-name(p.nodir.string, p.classify, opts)
  // -a: show everything including . and ..
  // -A: show dotfiles but exclude . and ..
  // default: hide all dotfiles
  val visible = if opts.show-all then
                  val dot    = format-name(".",  FDirectory, opts)
                  val dotdot = format-name("..", FDirectory, opts)
                  Cons(dot, Cons(dotdot, names))
                elif opts.almost-all then names
                else names.filter(fn(n) !n.is-hidden)
  val filtered = if opts.ignore-backups then visible.filter(fn(n) !n.is-backup)
                 else visible
  if opts.reverse then filtered.sort(fn(a, b) cmp(b, a))
  else filtered.sort(cmp)

pub fun list-dir(dir-path : path, opts : options, show-header : bool)
  if show-header then println(dir-path.string ++ ":")
  val sorted = list-dir-names(dir-path, opts)
  // Render output: -1 forces one-per-line, -C forces columns,
  // otherwise columns if stdout is a tty, one-per-line if piped.
  val use-columns = if opts.one-entry then False
                    elif opts.force-columns then True
                    else stdout-is-tty()
  if use-columns then
    val width = terminal-width()
    val lines = render-column-major(sorted, width)
    lines.foreach(fn(line) println(line))
  else
    sorted.foreach(fn(name) println(name))

// ---------------------------------------------------------------------------
// Entry point
// No path arguments -> list current directory (".")
// Otherwise         -> list each given path
// GNU ls with no args simply lists ".", no banners, no decoration.
// ---------------------------------------------------------------------------

fun main()
  match get-args().parse-args
    HelpRequested -> show-help()
    VersionRequested -> show-version()
    Parsed(opts, paths) ->
      val targets = match paths
        Nil -> [".".path]
        _   -> paths.map(fn(p) p.path)
      // Report inaccessible paths to stderr, like GNU ls
      val existing = targets.filter fn(t)
        val err = stat-error(t.string)
        if err.is-empty then True
        else
          eprintln("ls: cannot access '" ++ t.string ++ "': " ++ err)
          False
      val (dirs, files) = existing.partition(fn(t) is-directory(t))
      // Print files first (no header), like GNU ls
      files.foreach fn(f)
        println(format-name(f.string, f.classify, opts))
      // Then directories, with headers if multiple targets
      val show-header = dirs.length > 1 || files.length > 0
      dirs.foreach-indexed fn(i, dir-path)
        if i > 0 || files.length > 0 then println("")
        list-dir(dir-path, opts, show-header)
