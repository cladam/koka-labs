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

extern stat-error(p : string) : fsys string
  c "kk_os_stat_error"

extern eprint(msg : string) : fsys ()
  c "kk_os_eprint"

fun eprintln(msg : string) : fsys ()
  eprint(msg ++ "\n")

// ---------------------------------------------------------------------------
// Options — will grow as I add flags like -l, -R, -t, etc.
// ---------------------------------------------------------------------------

struct options
  show-all : bool = False // -a
  reverse  : bool = False // -r
  fs-type  : bool = False // -F
  slash-dir: bool = False // -p

// ---------------------------------------------------------------------------
// File classification for -F flag
// GNU ls -F appends: / (dir), @ (symlink), * (exec), = (socket),
// | (FIFO), % (whiteout). Symlink is checked first via lstat so that
// a symlink to a directory shows '@' rather than '/'.
// Whiteout is not detected (macOS-specific UFS concept, rare in practice).
// ---------------------------------------------------------------------------

// Create a type for pattern matching
type file-kind
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
  "  -a             do not ignore entries starting with .",
  "  -r             reverse order while sorting",
  "  -F             append indicator (one of /@ *=|) to entries",
  "  -p             append / indicator to directories",
  "      --help     show this help and exit",
  "      --version  show version and exit"
].join("\n")

fun show-help() : io ()
  println(usage)

fun show-version() : io ()
  val program = "ls - simple directory listing ala ls"
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

type parse-result
  Parsed(opts : options, paths : list<string>)
  HelpRequested
  VersionRequested

fun parse-args(args : list<string>, opts : options = Options(), paths : list<string> = []) : parse-result
  match args
    Nil -> Parsed(opts, paths.reverse)
    Cons("--", rest) -> Parsed(opts, paths.reverse ++ rest)
    Cons("--help", _) -> HelpRequested
    Cons("--version", _) -> VersionRequested
    Cons(arg, rest) | arg.starts-with("-").bool && arg != "-" ->
      val new-opts = arg.slice.drop(1).string.list.foldl(opts) fn(o, c)
        match c
          'a' -> o(show-all = True)
          'r' -> o(reverse = True)
          'F' -> o(fs-type = True)
          'p' -> o(slash-dir = True)
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

// Format a single entry name with optional -F / -p suffix
fun format-name(name : string, kind : file-kind, opts : options) : string
  if opts.fs-type then name ++ kind.suffix
  elif opts.slash-dir then match kind
    FDirectory -> name ++ "/"
    _          -> name
  else name

// ---------------------------------------------------------------------------
// Listing
// list-directory returns full paths; we display only the basename, matching
// how GNU ls shows just the name within the listed directory.
// ---------------------------------------------------------------------------

fun list-dir(dir-path : path, opts : options, show-header : bool)
  if show-header then println(dir-path.string ++ ":")
  val entries = list-directory(dir-path)
  val names   = entries.map fn(p)
    format-name(p.nodir.string, p.classify, opts)
  val visible = if opts.show-all then names
                else names.filter(fn(n) !n.is-hidden)
  val sorted  = if opts.reverse then visible.sort(fn(a, b) cmp(b, a))
                else visible.sort(cmp)
  // Render in columns like GNU ls (column-major)
  val width = terminal-width()
  val lines = render-column-major(sorted, width)
  lines.foreach(fn(line) println(line))

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
