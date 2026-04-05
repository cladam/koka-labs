// ---------------------------------------------------------------------------
// ls.kk — list directory contents
//
// A simplified clone of GNU ls, written in Koka.
// Author: Claes Adamsson
// License: MIT
// ---------------------------------------------------------------------------
module ls

import std/os/path
import std/os/dir
import std/os/env

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

// ---------------------------------------------------------------------------
// Options — will grow as we add flags like -l, -R, -t, etc.
// ---------------------------------------------------------------------------

struct options
  show-all : bool = False // -a
  reverse  : bool = False // -r
  fs-type  : bool = False // -F

// ---------------------------------------------------------------------------
// File classification — for -F flag
// GNU ls -F appends: / (dir), @ (symlink), * (exec), = (socket),
// | (FIFO), % (whiteout). Symlink is checked first via lstat so that
// a symlink to a directory shows '@' rather than '/'.
// Whiteout is not detected (macOS-specific UFS concept, rare in practice).
// ---------------------------------------------------------------------------

fun classify-suffix(p : path) : fsys string
  val s = p.string
  if is-symlink(s)    then "@"
  elif is-directory(p) then "/"
  elif is-executable(s) then "*"
  elif is-socket(s)    then "="
  elif is-fifo(s)      then "|"
  else ""

// ---------------------------------------------------------------------------
// Argument parsing
// GNU ls supports combined short flags like -ar, -ra, etc.
// We separate flag arguments (starting with '-') from path arguments.
// "--" terminates flag parsing, everything after is a path.
// ---------------------------------------------------------------------------

fun parse-args(args : list<string>, opts : options = Options(), paths : list<string> = []) : (options, list<string>)
  match args
    Nil -> (opts, paths.reverse)
    Cons("--", rest) -> (opts, paths.reverse ++ rest)
    Cons(arg, rest) | arg.starts-with("-").bool && arg != "-" ->
      val new-opts = arg.slice.drop(1).string.list.foldl(opts) fn(o, c)
        match c
          'a' -> o(show-all = True)
          'r' -> o(reverse = True)
          'F' -> o(fs-type = True)
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

fun is-hidden(name : string) : bool
  match name.head-char
    Just('.') -> True
    _         -> False

// ---------------------------------------------------------------------------
// Listing
// list-directory returns full paths; we display only the basename, matching
// how GNU ls shows just the name within the listed directory.
// ---------------------------------------------------------------------------

fun list-dir(dir-path : path, opts : options)
  val entries = list-directory(dir-path)
  val names   = entries.map fn(p)
    val name = p.nodir.string
    if opts.fs-type then name ++ classify-suffix(p) else name
  val visible = if opts.show-all then names
                else names.filter(fn(n) !n.is-hidden)
  val sorted  = if opts.reverse then visible.sort(fn(a, b) cmp(b, a))
                else visible.sort(cmp)
  sorted.foreach(fn(name) println(name))

// ---------------------------------------------------------------------------
// Entry point
// No path arguments -> list current directory (".")
// Otherwise         -> list each given path
// GNU ls with no args simply lists ".", no banners, no decoration.
// ---------------------------------------------------------------------------

fun main()
  val (opts, paths) = get-args().parse-args
  val targets       = match paths
    Nil -> [".".path]
    _   -> paths.map(fn(p) p.path)
  targets.foreach fn(dir-path)
    list-dir(dir-path, opts)
