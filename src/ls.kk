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

extern fnmatch(pattern: string, name: string): bool
  c "kk_os_fnmatch"

extern readdir-raw(dir : string) : fsys string
  c "kk_os_readdir_raw"

extern get-inode(p : string) : fsys int
  c "kk_os_get_inode"

extern get-size(p : string) : fsys int
  c "kk_os_get_size"

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
extern process-exit(code: int) : io()
  c inline "exit(kk_integer_clamp32(#1, kk_context()))"

fun set-exit-status(current: int, serious: bool) : int
  val code = if serious then 2 else 1
  if current < code then code else current

// ---------------------------------------------------------------------------
//  Show non-linear control by exiting a computation. (exception monad)
// ---------------------------------------------------------------------------
pub effect exit
  ctl exit( exitcode : int ) : a

pub fun status( action : () -> <exit|e> a ) : e int
  with final ctl exit(code) code // use `final` since we never resume
  action()
  0

// ---------------------------------------------------------------------------
//  Basic I/O
//  Shows output state (writer monad)
// ---------------------------------------------------------------------------

//  echoln would be println but routed through the bio effect instead of the console. 
//  It's the same interface but now the implementation is pluggable:
//  Production: with fun write(fd, s) print(s) → prints to real stdout (same as println)
//  Testing: with bio → captures to a string buffer 
//
//  It's an interesting concept. I found the pattern in the unix.kk sample.
pub effect bio
  fun write( fd : filedesc, s : string ) : ()

pub alias filedesc = int
pub val stdout = 0

pub fun echo( s : string ) : bio ()
  write(stdout,s)

pub fun echoln( s : string ) : bio ()
  write(stdout, s ++ "\n")

pub fun bio( action : () -> <bio|e> a) : e (a,string)
  var buf := ""
  with return(x) (x,buf)
  with fun write(fd,s) buf := buf ++ s
  action()

// ---------------------------------------------------------------------------
// Options — will grow as I add flags like -l, -R, -t, etc.
// ---------------------------------------------------------------------------

pub type sort-key
  SortName       // default: alphabetical
  SortSize       // -S: largest first
  SortNone       // -U: directory order

pub type indicator-style
  IndicatorNone
  IndicatorSlash     // -p: only / for directories
  IndicatorFileType  // --file-type: like classify but no * for executables
  IndicatorClassify  // -F: full indicators */=>@|

pub type classify-when
  ClassifyAlways
  ClassifyAuto
  ClassifyNever

fun parse-classify-when(s : string) : maybe<classify-when>
  match s
    "always" -> Just(ClassifyAlways)
    "yes"    -> Just(ClassifyAlways)
    "force"  -> Just(ClassifyAlways)
    "auto"   -> Just(ClassifyAuto)
    "tty"    -> Just(ClassifyAuto)
    "never"  -> Just(ClassifyNever)
    "no"     -> Just(ClassifyNever)
    "none"   -> Just(ClassifyNever)
    _        -> Nothing

fun parse-indicator-style(s : string) : maybe<indicator-style>
  match s
    "none"      -> Just(IndicatorNone)
    "slash"     -> Just(IndicatorSlash)
    "file-type" -> Just(IndicatorFileType)
    "classify"  -> Just(IndicatorClassify)
    _           -> Nothing

fun parse-sort-key(s : string) : maybe<sort-key>
  match s
    "none"      -> Just(SortNone)
    "name"      -> Just(SortName)
    "size"      -> Just(SortSize)
    _           -> Nothing

pub struct options
  show-all        : bool = False // -a
  almost-all      : bool = False // -A
  ignore-backups  : bool = False // -B
  force-columns   : bool = False // -C
  dir-only        : bool = False // -d
  classify        : classify-when   = ClassifyNever // -F, --classify[=WHEN]
  indicator       : indicator-style = IndicatorNone // --indicator-style, -p, --file-type
  no-sort         : bool = False // -f
  hide-patterns   : list<string> = [] // --hide
  ignore-patterns : list<string> = [] // -I
  reverse         : bool = False // -r
  print-inode     : bool = False // -i
  recurse         : bool = False // -R
  sort-by         : sort-key = SortName // --sort=WORD, -S, -U
  one-entry       : bool = False // -1

// ---------------------------------------------------------------------------
// Directory entry — name + inode from readdir
// ---------------------------------------------------------------------------

pub struct dir-entry
  entry-name  : string
  entry-ino   : int      // d_ino from readdir, 0 if unknown

// Parse the raw "inode\tname\n" format from readdir-raw into a list of dir-entry
pub fun parse-readdir(s : string) : list<dir-entry>
  s.lines.filter(fn(l) !l.is-empty).map fn(line)
    match line.split("\t")
      Cons(ino-str, Cons(name, _)) ->
        Dir-entry(name, ino-str.parse-int.default(0))
      _ -> Dir-entry(line, 0)

// Read a directory using readdir, returning dir-entry list with d_ino
pub fun read-dir-entries(dir-path : path) : fsys list<dir-entry>
  val s = readdir-raw(dir-path.string)
  parse-readdir(s)

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

// Like suffix but does not append * for executables (--file-type)
fun file-type-suffix(kind : file-kind) : string
  match kind
    FDirectory  -> "/"
    FSymlink    -> "@"
    FExecutable -> ""
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
    "  -a, --all                    do not ignore entries starting with .(includes . and ..)",
    "  -A, --almost-all             like -a, but do not list . and ..",
    "  -B, --ignore-backups         do not list implied entries ending with ~",
    "  -C                           list entries by columns",
    "  -d, --directory              list directories themselves, not their contents",
    "  -F, --classify[=WHEN]        append indicator (one of */=>@|) to entries WHEN",
    "  -f                           same as -a -U",
    "  --file-type                  like -F, except do not append '*'",
    "  --hide=PATTERN               do not list implied entries matching shell PATTERN",
    "                               (overridden by -a or -A)",
    "  --indicator-style=WORD       none, slash (-p), file-type, classify (-F)",
    "  -I, --ignore=PATTERN         do not list entries matching shell PATTERN",
    "  -i, --inode                  print the index number of each file",
    "  -p, --indicator-style=slash  append / indicator to directories",
    "  -r, --reverse                reverse order while sorting",
    "  -R, --recursive              list subdirectories recursively",
    "  -S                           sort by file size, largest first",
    "      --sort=WORD              sort by WORD: none (-U), name, size (-S)",
    "  -U                           do not sort; list entries in directory order",
    "  -1                           list one file per line",
    "      --help                   show this help and exit",
    "      --version                show version and exit"
].join("\n")

fun show-help() : bio ()
  echoln(usage)

fun show-version() : bio ()
  val program = "koka-ls - directory listing (GNU ls clone in Koka)"
  echoln(program-name  ++ "@" ++ version)
  echoln("Program: " ++ program)
  echoln("Author: " ++ author)
  echoln("Repository: " ++ repository)

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
      parse-args(rest, opts(classify = ClassifyAlways), paths)
    Cons(arg, rest) | arg.starts-with("--classify=").bool ->
      val when-str = arg.slice.drop(11).string
      match parse-classify-when(when-str)
        Just(cw) -> parse-args(rest, opts(classify = cw), paths)
        Nothing  -> InvalidFlag("--classify=" ++ when-str)
    Cons("--directory", rest) ->
      parse-args(rest, opts(dir-only = True), paths)
    Cons("--sort=none", rest) ->
      parse-args(rest, opts(sort-by = SortNone), paths)
    Cons(arg, rest) | arg.starts-with("--sort=").bool ->
      val sort-str = arg.slice.drop(7).string
      match parse-sort-key(sort-str)
        Just(sk) -> parse-args(rest, opts(sort-by = sk), paths)
        Nothing  -> InvalidFlag("--sort=" ++ sort-str)
    Cons("--recursive", rest) ->
      parse-args(rest, opts(recurse = True), paths)
    Cons("--file-type", rest) ->
      parse-args(rest, opts(indicator = IndicatorFileType), paths)
    Cons(arg, rest) | arg.starts-with("--indicator-style=").bool ->
      val style-str = arg.slice.drop(18).string
      match parse-indicator-style(style-str)
        Just(sty) -> parse-args(rest, opts(indicator = sty), paths)
        Nothing   -> InvalidFlag("--indicator-style=" ++ style-str)
    Cons("--inode", rest) ->
      parse-args(rest, opts(print-inode = True), paths)
    Cons(arg, rest) | arg.starts-with("--hide=").bool ->
      val pat = arg.slice.drop(7).string
      parse-args(rest, opts(hide-patterns = Cons(pat, opts.hide-patterns)), paths)
    Cons(arg, rest) | arg.starts-with("--ignore=").bool ->
      val pat = arg.slice.drop(9).string
      parse-args(rest, opts(ignore-patterns = Cons(pat, opts.ignore-patterns)), paths)
    // Unrecognised long options
    Cons(arg, _) | arg.starts-with("--").bool ->
      InvalidFlag(arg)
    // Short flags — can be combined like -ar, -ra, etc.
    Cons(arg, rest) | arg.starts-with("-").bool && arg != "-" ->
      val chars = arg.slice.drop(1).string.list
      val has-I = chars.any(fn(c) c == 'I')
      val bad = chars.filter fn(c)
        match c
          'a' -> False
          'A' -> False
          'B' -> False
          'C' -> False
          'd' -> False
          'f' -> False
          'F' -> False
          'i' -> False
          'I' -> False
          'p' -> False
          'r' -> False
          'R' -> False
          'S' -> False
          'U' -> False
          '1' -> False
          _   -> True
      match bad
        Cons(c, _) -> InvalidFlag(string(c))
        Nil ->
          val new-opts = chars.filter(fn(c) c != 'I').foldl(opts) fn(o, c)
            match c
              'a' -> o(show-all = True, almost-all = False)
              'A' -> o(almost-all = True, show-all = False)
              'B' -> o(ignore-backups = True)
              'C' -> o(force-columns = True, one-entry = False)
              'd' -> o(dir-only = True)
              // TODO: GNU ls -f also disables -l, -s, --color, and -F.
              // Add those overrides here later
              'f' -> o(show-all = True, sort-by = SortNone)
              // -F shouldn't follow symlinks
              'F' -> o(classify = ClassifyAlways)
              'i' -> o(print-inode = True)
              'p' -> o(indicator = IndicatorSlash)
              'r' -> o(reverse = True)
              'R' -> o(recurse = True)
              'S' -> o(sort-by = SortSize)
              'U' -> o(sort-by = SortNone)
              '1' -> o(one-entry = True, force-columns = False)
              _   -> o
          if has-I then
            match rest
              Cons(pat, rest2) ->
                parse-args(rest2, new-opts(ignore-patterns = Cons(pat, new-opts.ignore-patterns)), paths)
              Nil -> InvalidFlag("-I (missing pattern)")
          else
            parse-args(rest, new-opts, paths)
    Cons(arg, rest) -> parse-args(rest, opts, Cons(arg, paths))

// ---------------------------------------------------------------------------
// Sorting — simple insertion sort, fine for directory listings.
// ---------------------------------------------------------------------------

fun insertby(x : a, xs : list<a>, cmp : (a, a) -> order) : list<a>
  match xs
    Nil -> [x]
    Cons(y, ys) -> match cmp(x, y)
      Gt -> Cons(y, insertby(x, ys, cmp))
      _  -> Cons(x, xs)

pub fun sortby(xs : list<a>, cmp : (a, a) -> order) : list<a>
  match xs
    Nil -> Nil
    Cons(x, rest) -> insertby(x, rest.sortby(cmp), cmp)

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

// Format a single entry name with optional indicator suffix
// Priority: --classify / -F  >  --indicator-style / --file-type / -p
pub fun format-name(name : string, kind : file-kind, opts : options, is-tty : bool = True) : string
  val do-classify = match opts.classify
    ClassifyAlways -> True
    ClassifyAuto   -> is-tty
    ClassifyNever  -> False
  val sfx = if do-classify then kind.suffix
            else match opts.indicator
              IndicatorClassify  -> kind.suffix
              IndicatorFileType  -> kind.file-type-suffix
              IndicatorSlash     -> match kind { FDirectory -> "/"; _ -> "" }
              IndicatorNone      -> ""
  if sfx.is-empty || name.ends-with(sfx).bool then name else name ++ sfx

pub fun matches-any(name: string, patterns: list<string>): bool
  patterns.any(fn(p) fnmatch(p, name))

fun is-dot-dir(name : string) : bool
  name == "." || name == ".."

// ---------------------------------------------------------------------------
// Listing
// list-directory returns full paths; only display the basename, matching
// how GNU ls shows just the name within the listed directory.
// ---------------------------------------------------------------------------
pub fun list-dir-names(dir-path : path, opts : options, is-tty : bool = True)
  val raw-entries = match try({read-dir-entries(dir-path)})
    Ok(es) -> es
    Error(exn) ->
      eprintln("ls: cannot open directory '" ++ dir-path.string ++ "': " ++ exn.message)
      return ([], set-exit-status(0, serious = False))
  // Map to (display-name, inode, raw-name) tuples; classify on full path
  val entries = raw-entries.map fn(de)
    val full = (dir-path / de.entry-name.path)
    (format-name(de.entry-name, full.classify, opts, is-tty), de.entry-ino, de.entry-name)
  val visible = if opts.show-all then
                  val dot    = (format-name(".",  FDirectory, opts, is-tty), get-inode(dir-path.string), ".")
                  val dotdot-path = (dir-path / "..".path).string
                  val dotdot = (format-name("..", FDirectory, opts, is-tty), get-inode(dotdot-path), "..")
                  Cons(dot, Cons(dotdot, entries))
                elif opts.almost-all then entries
                else entries.filter(fn(e) not(e.fst.is-hidden))
  val filtered = if opts.ignore-backups then visible.filter(fn(e) not(e.fst.is-backup))
                 else visible
  val unhidden = match opts.hide-patterns
    Nil -> filtered
    _pats | opts.show-all || opts.almost-all -> filtered
    pats -> filtered.filter(fn(e) not(e.fst.matches-any(pats)))
  val ignored  = match opts.ignore-patterns
    Nil -> unhidden
    pats -> unhidden.filter(fn(e) not(e.fst.matches-any(pats)))
  val sorted = match opts.sort-by
    SortNone -> ignored.map(fn(e) (e.fst, e.snd))
    SortName ->
      val s = if opts.reverse then ignored.sortby(fn(a, b) cmp(b.fst, a.fst))
              else ignored.sortby(fn(a, b) cmp(a.fst, b.fst))
      s.map(fn(e) (e.fst, e.snd))
    SortSize ->
      val with-size = ignored.map fn(e)
        val sz = get-size((dir-path / e.thd.path).string)
        (e.fst, e.snd, sz)
      val s = if opts.reverse then with-size.sortby fn(a, b)
                match cmp(a.thd, b.thd) { Eq -> cmp(b.fst, a.fst); c -> c }
              else with-size.sortby fn(a, b)
                match cmp(b.thd, a.thd) { Eq -> cmp(a.fst, b.fst); c -> c }
      s.map(fn(e) (e.fst, e.snd))
  (sorted, 0)

// Format inode for display, right-justified to given width
pub fun format-inode(ino : int, width : int) : string
  val s = ino.show
  val pad = width - s.count
  (if pad > 0 then " ".repeat(pad) else "") ++ s

// Compute the maximum inode display width
pub fun inode-width(entries : list<(string, int)>) : int
  entries.foldl(0) fn(mx, e)
    val w = e.snd.show.count
    if w > mx then w else mx

// Format entries for display, prepending inode if needed
pub fun format-entries(entries : list<(string, int)>, opts : options) : list<string>
  if opts.print-inode then
    val iw = inode-width(entries)
    entries.map(fn(e) format-inode(e.snd, iw) ++ " " ++ e.fst)
  else
    entries.map(fn(e) e.fst)

pub fun list-dir(dir-path : path, opts : options, show-header : bool, display-path : string = dir-path.string) : _ int
  if show-header then echoln(display-path ++ ":")
  val tty = stdout-is-tty()
  val (sorted, code) = list-dir-names(dir-path, opts, tty)
  val display = format-entries(sorted, opts)
  val use-columns = if opts.one-entry then False
                    elif opts.force-columns then True
                    else tty
  if use-columns then
    val width = terminal-width()
    val lines = render-column-major(display, width)
    lines.foreach(fn(line) echoln(line))
  else
    display.foreach(fn(name) echoln(name))
  // Recurse into subdirectories for -R
  if opts.recurse && !opts.dir-only then
    val raw-entries = match try({read-dir-entries(dir-path)})
      Ok(es) -> es
      Error(_) -> []
    val dirs = raw-entries.filter(fn(de) is-directory(dir-path / de.entry-name.path) && !de.entry-name.is-dot-dir)
    val visible-dirs = if opts.show-all || opts.almost-all then dirs
                       else dirs.filter(fn(de) not(de.entry-name.is-hidden))
    val sorted-dirs = match opts.sort-by
      SortNone -> visible-dirs
      SortName ->
        if opts.reverse then visible-dirs.sortby(fn(a, b) cmp(b.entry-name, a.entry-name))
        else visible-dirs.sortby(fn(a, b) cmp(a.entry-name, b.entry-name))
      SortSize ->
        val with-size = visible-dirs.map(fn(de) (de, get-size((dir-path / de.entry-name.path).string)))
        val s = if opts.reverse then with-size.sortby fn(a, b)
                  match cmp(a.snd, b.snd) { Eq -> cmp(b.fst.entry-name, a.fst.entry-name); c -> c }
                else with-size.sortby fn(a, b)
                  match cmp(b.snd, a.snd) { Eq -> cmp(a.fst.entry-name, b.fst.entry-name); c -> c }
        s.map(fn(e) e.fst)
    sorted-dirs.foldl(code) fn(acc, de)
      echoln("")
      val sub-path = (dir-path.string ++ "/" ++ de.entry-name).path
      val sub-display = display-path ++ "/" ++ de.entry-name
      val sub-code = list-dir(sub-path, opts, True, sub-display)
      if sub-code > acc then sub-code else acc
  else code

// ---------------------------------------------------------------------------
// Entry point
// No path arguments -> list current directory (".")
// Otherwise         -> list each given path
// GNU ls with no args simply lists ".", no banners, no decoration.
// ---------------------------------------------------------------------------

val short-usage = "usage: ls [-aABCfFdiIprRSU1] [--help] [--version] [file ...]"

fun main()
  val code = status
    with fun write(fd, s) print(s)    // bio handler: route to real stdout
    var exit-code := 0
    match get-args().parse-args
      HelpRequested -> show-help()
      VersionRequested -> show-version()
      InvalidFlag(flag) ->
        eprintln("ls: invalid option -- " ++ flag)
        eprintln(short-usage)
        exit(2)
      Parsed(opts, paths) ->
        // Keep original argument strings alongside path objects so that
        // display preserves what the user (or shell glob) provided,
        // e.g. the trailing '/' from */.
        val targets : list<(string, path)> = match paths
          Nil -> [(".", ".".path)]
          _   -> paths.map(fn(p) (p, p.path))
        // Report inaccessible paths to stderr, like GNU ls
        val existing = targets.filter fn(t)
          val err = stat-error((t.snd).string)
          if err.is-empty then True
          else
            eprintln("ls: cannot access '" ++ t.fst ++ "': " ++ err)
            exit-code := set-exit-status(exit-code, serious = False)  // not serious → exit 1
            False
        val (dirs, files) = if opts.dir-only then ([], existing)
                            else existing.partition(fn(t) is-directory(t.snd))
        // Sort and print files first (no header), like GNU ls
        val tty = stdout-is-tty()
        val file-entries = files.map fn(t)
          val name = format-name(t.fst, (t.snd).classify, opts, tty)
          val ino = if opts.print-inode then get-inode((t.snd).string) else 0
          (name, ino, (t.snd).string)
        val sorted-file-entries = match opts.sort-by
          SortNone -> file-entries.map(fn(e) (e.fst, e.snd))
          SortName ->
            val s = if opts.reverse then file-entries.sortBy(fn(a, b) cmp(b.fst, a.fst))
                    else file-entries.sortBy(fn(a, b) cmp(a.fst, b.fst))
            s.map(fn(e) (e.fst, e.snd))
          SortSize ->
            val with-size = file-entries.map(fn(e) (e.fst, e.snd, get-size(e.thd)))
            val s = if opts.reverse then with-size.sortby fn(a, b)
                      match cmp(a.thd, b.thd) { Eq -> cmp(b.fst, a.fst); c -> c }
                    else with-size.sortby fn(a, b)
                      match cmp(b.thd, a.thd) { Eq -> cmp(a.fst, b.fst); c -> c }
            s.map(fn(e) (e.fst, e.snd))
        val sorted-file-names = format-entries(sorted-file-entries, opts)
        val use-columns = if opts.one-entry then False
                          elif opts.force-columns then True
                          else tty
        if use-columns then
          val width = terminal-width()
          val lines = render-column-major(sorted-file-names, width)
          lines.foreach(fn(line) echoln(line))
        else
          sorted-file-names.foreach(fn(name) echoln(name))
        // Sort directories, then list each
        val sorted-dirs = match opts.sort-by
          SortNone -> dirs
          SortSize ->
            val with-size = dirs.map(fn(t) (t, get-size((t.snd).string)))
            val s = if opts.reverse then with-size.sortby(fn(a, b) cmp(a.snd, b.snd))
                    else with-size.sortby(fn(a, b) cmp(b.snd, a.snd))
            s.map(fn(e) e.fst)
          _ ->
            if opts.reverse then dirs.reverse
            else dirs  // already in argument order, which is fine
        val show-header = sorted-dirs.length > 1 || sorted-file-names.length > 0
        sorted-dirs.foreach-indexed fn(i, dir-entry)
          if i > 0 || sorted-file-names.length > 0 then echoln("")
          val dir-code = list-dir(dir-entry.snd, opts, show-header)
          if dir-code > exit-code then exit-code := dir-code
    if exit-code > 0 then exit(exit-code)
  process-exit(code)
