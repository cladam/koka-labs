// ls - list directory contents
// Following the GNU coreutils ls philosophy, piece by piece.

import std/os/path
import std/os/dir
import std/os/env

// ---------------------------------------------------------------------------
// Options — will grow as we add flags like -l, -R, -t, etc.
// ---------------------------------------------------------------------------

struct options
  show-all : bool = False
  reverse  : bool = False

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
  val names   = entries.map(fn(p) p.nodir.string)
  val visible = if opts.show-all then names
                else names.filter(fn(n) !n.is-hidden)
  val sorted  = visible.sort(cmp)
  sorted.foreach(fn(name) println(name))

// ---------------------------------------------------------------------------
// Entry point
// No arguments  -> list current directory (".")
// One argument   -> list that path
// GNU ls with no args simply lists ".", no banners, no decoration.
// ---------------------------------------------------------------------------

fun main()
  val opts = Options()
  val args = get-args()
  val dir-path = match args
    Cons(a, _) -> a.path
    Nil        -> ".".path
  list-dir(dir-path, opts)
