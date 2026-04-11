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
  c file "ls-inline.c"

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
// Handle exit statuses
// - Exit 0: Success
// - Exit 1: The filesystem changed underneath ls while it was working, 
//   or something peripheral went wrong. Not really the user's fault.
// - Exit 2: The user asked for something that doesn't exist or can't be accessed, 
//   OR ls was invoked incorrectly. The user needs to fix their command.
// ---------------------------------------------------------------------------
pub extern exit( code : int ) : io ()
  c inline "exit(kk_integer_clamp32(#1, kk_context()))"

fun set-exit-status(current : int, serious : bool) : int
  val code = if serious then 2 else 1
  if current < code then code else current

// ---------------------------------------------------------------------------
// Options — will grow as I add flags like -l, -R, -t, etc.
// ---------------------------------------------------------------------------

pub struct options
  show-all        : bool = False // -a
  almost-all      : bool = False // -A
  ignore-backups  : bool = False // -B
  force-columns   : bool = False // -C
  directories     : bool = False // -d
  fs-type         : bool = False // -F
  no-sort         : bool = False // -f
  slash-dir       : bool = False // -p
  reverse         : bool = False // -r
  sort-none       : bool = False // -U
  one-entry       : bool = False // -1

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
    "  -F, --classify         append indicator (one of /@*=|) to entries",
    "  -f                     same as -a -U",
    "  -p, --slash-dir        append / indicator to directories",
    "  -r, --reverse          reverse order while sorting",
    "  -U, --sort=none        do not sort; list entries in directory order",
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
// Separate flag arguments (starting with '-') from path arguments.
// "--" terminates flag parsing, everything after is a path.
// Long options --help and --version are matched before short-flag expansion.
// ---------------------------------------------------------------------------

pub type parse-result
  Parsed(opts : options, paths : list<string>)
  HelpRequested
  VersionRequested
  InvalidFlag(flag : string)

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
    Cons("--sort=none", rest) ->
      parse-args(rest, opts(sort-none = True), paths)
    // Unrecognised long options
    Cons(arg, _) | arg.starts-with("--").bool ->
      InvalidFlag(arg)
    // Short flags — can be combined like -ar, -ra, etc.
    Cons(arg, rest) | arg.starts-with("-").bool && arg != "-" ->
      val chars = arg.slice.drop(1).string.list
      val bad = chars.filter fn(c)
        match c
          'a' -> False
          'A' -> False
          'r' -> False
          'F' -> False
          'f' -> False
          'p' -> False
          '1' -> False
          'C' -> False
          'B' -> False
          'U' -> False
          _   -> True
      match bad
        Cons(c, _) -> InvalidFlag(string(c))
        Nil ->
          val new-opts = chars.foldl(opts) fn(o, c)
            match c
              'a' -> o(show-all = True, almost-all = False)
              'A' -> o(almost-all = True, show-all = False)
              'r' -> o(reverse = True)
              'F' -> o(fs-type = True)
              // TODO: GNU ls -f also disables -l, -s, --color, and -F.
              // Add those overrides here later
              'f' -> o(show-all = True, sort-none = True)
              'p' -> o(slash-dir = True)
              '1' -> o(one-entry = True, force-columns = False)
              'C' -> o(force-columns = True, one-entry = False)
              'B' -> o(ignore-backups = True)
              'U' -> o(sort-none = True)
              _   -> o
          parse-args(rest, new-opts, paths)
    Cons(arg, rest) -> parse-args(rest, opts, Cons(arg, paths))

// ---------------------------------------------------------------------------
// Sorting
// Koka's standard library doesn't include a list sort.
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
pub fun list-dir-names(dir-path : path, opts : options)
  val entries = match try({list-directory(dir-path)})
    Ok(es) -> es
    Error(exn) ->
      eprintln("ls: cannot open directory '" ++ dir-path.string ++ "': " ++ exn.message)
      return ([], set-exit-status(0, serious = False))
  val names   = entries.map fn(p)
    format-name(p.nodir.string, p.classify, opts)
  val visible = if opts.show-all then
                  val dot    = format-name(".",  FDirectory, opts)
                  val dotdot = format-name("..", FDirectory, opts)
                  Cons(dot, Cons(dotdot, names))
                elif opts.almost-all then names
                else names.filter(fn(n) not(n.is-hidden))
  val filtered = if opts.ignore-backups then visible.filter(fn(n) not(n.is-backup))
                 else visible
  val sorted = if opts.sort-none then filtered
               elif opts.reverse then filtered.sort(fn(a, b) cmp(b, a))
               else filtered.sort(cmp)
  (sorted, 0)

pub fun list-dir(dir-path : path, opts : options, show-header : bool) : _ int
  if show-header then println(dir-path.string ++ ":")
  val (sorted, code) = list-dir-names(dir-path, opts)
  val use-columns = if opts.one-entry then False
                    elif opts.force-columns then True
                    else stdout-is-tty()
  if use-columns then
    val width = terminal-width()
    val lines = render-column-major(sorted, width)
    lines.foreach(fn(line) println(line))
  else
    sorted.foreach(fn(name) println(name))
  code

// ---------------------------------------------------------------------------
// Entry point
// No path arguments -> list current directory (".")
// Otherwise         -> list each given path
// GNU ls with no args simply lists ".", no banners, no decoration.
// ---------------------------------------------------------------------------

val short-usage = "usage: ls [-aABCfFprU1] [--help] [--version] [file ...]"

fun main()
  var status := 0
  match get-args().parse-args
    HelpRequested -> show-help()
    VersionRequested -> show-version()
    InvalidFlag(flag) ->
      eprintln("ls: invalid option -- " ++ flag)
      eprintln(short-usage)
      exit(2)
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
          status := set-exit-status(status, serious = False)  // not serious → exit 1
          False
      val (dirs, files) = existing.partition(fn(t) is-directory(t))
      // Sort and print files first (no header), like GNU ls
      val file-names = files.map(fn(f) format-name(f.path/string, f.classify, opts))
      val sorted-file-names = if opts.sort-none then file-names
                              elif opts.reverse then file-names.sort(fn(a, b) cmp(b, a))
                              else file-names.sort(cmp)
      sorted-file-names.foreach(fn(name) println(name))
      // Sort directories, then list each
      // TODO: GNU ls sorts directory arguments alphabetically before listing.
      // This requires a generic sort or a sort-paths helper since our sort
      // only works on list<string> and dirs is list<path>.
      val sorted-dirs = if opts.sort-none then dirs
                        elif opts.reverse then dirs.reverse
                        else dirs  // already in argument order, which is fine
      val show-header = sorted-dirs.length > 1 || sorted-file-names.length > 0
      sorted-dirs.foreach-indexed fn(i, dir-path)
        if i > 0 || sorted-file-names.length > 0 then println("")
        val code = list-dir(dir-path, opts, show-header)
        if code > status then status := code

  exit(status)

