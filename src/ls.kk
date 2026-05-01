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
import klap

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

extern get-mtime(p : string) : fsys int
  c "kk_os_get_mtime"

extern get-atime(p : string) : fsys int
  c "kk_os_get_atime"

extern get-ctime(p : string) : fsys int
  c "kk_os_get_ctime"

pub extern filevercmp(a : string, b : string) : int
  c "kk_os_filevercmp"

extern stat-info-raw(p : string) : fsys string
  c "kk_os_stat_info"

pub extern readlink-path(p : string) : fsys string
  c "kk_os_readlink_path"

pub extern format-timestamp(sec : int) : fsys string
  c "kk_os_format_timestamp"

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
  SortTime       // -t: newest first
  SortNone       // -U: directory order
  SortExtension  // -X: by extension
  SortWidth      // --sort=width: by name length
  SortVersion    // -v: version sort (natural numeric ordering)

pub type time-kind
  TimeMtime      // default: modification time
  TimeAtime      // -u: access time
  TimeCtime      // -c: status change time

pub type indicator-style
  IndicatorNone
  IndicatorSlash     // -p: only / for directories
  IndicatorFileType  // --file-type: like classify but no * for executables
  IndicatorClassify  // -F: full indicators */=>@|

pub type classify-when
  ClassifyAlways
  ClassifyAuto
  ClassifyNever

pub struct options
  show-all        : bool = False // -a
  almost-all      : bool = False // -A
  ignore-backups  : bool = False // -B
  force-columns   : bool = False // -C
  dir-only        : bool = False // -d
  classify        : classify-when   = ClassifyNever // -F, --classify[=WHEN]
  indicator       : indicator-style = IndicatorNone // --indicator-style, -p, --file-type
  no-sort         : bool = False // -f
  long-format     : bool = False // -l
  hide-patterns   : list<string> = [] // --hide
  ignore-patterns : list<string> = [] // -I
  reverse         : bool = False // -r
  no-group        : bool = False // -G, --no-group, -o
  no-owner        : bool = False // -g
  numeric-ids     : bool = False // -n, --numeric-uid-gid
  show-author     : bool = False // --author
  print-inode     : bool = False // -i
  recurse         : bool = False // -R
  sort-by         : sort-key = SortName // --sort=WORD, -S, -t, -U -X
  time-type       : time-kind = TimeMtime // --time=WORD, -c, -u
  group-dirs      : bool = False // --group-directories-first
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
// File metadata — single-stat result for -l (long format)
// Parsed from the tab-separated string returned by stat-info-raw:
//   mode \t nlink \t owner \t uid \t group \t gid \t size \t mtime_sec \t mtime_nsec \t blocks
// ---------------------------------------------------------------------------

pub struct file-info
  fi-mode      : string  // e.g. "-rwxr-xr-x"
  fi-nlink     : int
  fi-owner     : string  // user name from getpwuid
  fi-uid       : int
  fi-group     : string  // group name from getgrgid
  fi-gid       : int
  fi-size      : int
  fi-mtime-sec : int     // seconds since epoch
  fi-mtime-nsec: int
  fi-blocks    : int     // 512-byte blocks allocated

pub fun parse-stat-info(s : string) : maybe<file-info>
  match s.split("\t")
    [mode, nlink, owner, uid, group, gid, size, mtime-s, mtime-ns, blocks] ->
      Just(File-info(
        mode,
        nlink.parse-int.default(0),
        owner,
        uid.parse-int.default(0),
        group,
        gid.parse-int.default(0),
        size.parse-int.default(0),
        mtime-s.parse-int.default(0),
        mtime-ns.parse-int.default(0),
        blocks.parse-int.default(0)
      ))
    _ -> Nothing

pub fun get-file-info(p : string) : fsys maybe<file-info>
  val s = stat-info-raw(p)
  if s.is-empty then Nothing
  else parse-stat-info(s)

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
    "Usage: kls [OPTION]... [FILE]...",
    "List information about the FILEs (the current directory by default).",
    "Sort entries alphabetically if none of -cftuvSUX nor --sort is specified.",
    "",
    "  -a, --all                  do not ignore entries starting with .",
    "  -A, --almost-all           like -a, but do not list . and ..",
    "      --author               with -l, print the author of each file",
    "  -B, --ignore-backups       do not list implied entries ending with ~",
    "  -C                         list entries by columns",
    "  -d, --directory            list directories themselves, not their contents",
    "  -F, --classify[=WHEN]      append indicator (one of */=>@|) to entries WHEN",
    "  -f                         same as -a -U",
    "  -g                         like -l, but do not list owner",    
    "  -G, --no-group             in a long listing, don't print group names",
    "      --file-type            like -F, except do not append '*'",
    "      --hide=PATTERN         do not list implied entries matching shell PATTERN",
    "                             (overridden by -a or -A)",
    "      --indicator-style=WORD",
    "                             none, slash (-p), file-type, classify (-F)",
    "  -I, --ignore=PATTERN       do not list entries matching shell PATTERN",
    "  -i, --inode                print the index number of each file",
    "  -l                         use a long listing format",
    "  -n, --numeric-uid-gid      like -l, but list numeric user and group IDs",
    "  -o                         like -l, but do not list group information",
    "  -p, --indicator-style=slash",
    "                             append / indicator to directories",
    "  -r, --reverse              reverse order while sorting",
    "  -R, --recursive            list subdirectories recursively",
    "  -S                         sort by file size, largest first",
    "      --sort=WORD            sort by WORD: none (-U), name, size (-S),",
    "                             time (-t), extension (-X), version (-v), width",
    "  -v                         natural sort of (version) numbers within text",
    "      --group-directories-first",
    "                             group directories before files",
    "  -t                         sort by time, newest first; see --time",
    "      --time=WORD            select which timestamp to use with -t:",
    "                             mtime (default), atime (-u), ctime (-c)",
    "  -c                         with -t: sort by ctime (status change time)",
    "  -u                         with -t: sort by atime (access time)",
    "  -U                         do not sort; list entries in directory order",
    "  -X                         sort alphabetically by entry extension",
    "  -1                         list one file per line",
    "      --help                 show this help and exit",
    "      --version              show version and exit"
].join("\n")

fun show-help() : bio ()
  echoln(usage)

fun show-version() : bio ()
  val program = "kls - directory listing (GNU ls clone in Koka)"
  echoln(program-name  ++ "@" ++ version)
  echoln("Program: " ++ program)
  echoln("Author: " ++ author)
  echoln("Repository: " ++ repository)

// ---------------------------------------------------------------------------
// CLI definition using klap
// ---------------------------------------------------------------------------

val kls-command = command("kls")
  .version(version)
  .about("List information about the FILEs (the current directory by default).\nSort entries alphabetically if none of -cftuvSUX nor --sort is specified.")
  .usage("Usage: kls [OPTION]... [FILE]...")
  .author(author)
  // Simple boolean flags
  .arg(flag-short("all", 'a').help("do not ignore entries starting with .")
        .action("filter", "all"))
  .arg(flag-short("almost-all", 'A').help("like -a, but do not list . and ..")
        .action("filter", "almost-all"))
  .arg(flag-short("ignore-backups", 'B').help("do not list implied entries ending with ~"))
  .arg(flag-short("directory", 'd').help("list directories themselves, not their contents"))
  .arg(flag-short("no-group", 'G').help("in a long listing, don't print group names"))
  .arg(flag-short("inode", 'i').help("print the index number of each file"))
  .arg(flag-short("reverse", 'r').help("reverse order while sorting"))
  .arg(flag-short("recursive", 'R').help("list subdirectories recursively"))
  .arg(flag("author").help("with -l, print the author of each file"))
  .arg(flag("group-directories-first").help("group directories before files"))
  .arg(flag("file-type").help("like -F, except do not append '*'")
        .action("indicator-style", "file-type"))
  // Options with values
  .arg(option("sort").value-name("WORD")
        .values(["none", "name", "size", "time", "extension", "width", "version"])
        .default-value("name")
        .help("sort by WORD: none (-U), name, size (-S), time (-t), extension (-X), version (-v), width"))
  .arg(option("time").value-name("WORD")
        .values(["mtime", "modification", "atime", "access", "use", "ctime", "status"])
        .default-value("mtime")
        .help("select which timestamp to use: mtime (default), atime (-u), ctime (-c)"))
  .arg(option("classify")
        .optional-value("always")
        .values(["always", "yes", "force", "auto", "tty", "never", "no", "none"])
        .help("append indicator (one of */=>@|) to entries"))
  .arg(option("indicator-style").value-name("WORD")
        .values(["none", "slash", "file-type", "classify"])
        .default-value("none")
        .help("none, slash (-p), file-type, classify (-F)"))
  .arg(option-short("ignore", 'I').value-name("PATTERN").multiple
        .help("do not list entries matching shell PATTERN"))
  .arg(option("hide").value-name("PATTERN").multiple
        .help("do not list implied entries matching shell PATTERN"))
  // Hidden options for action flag targets
  .arg(option("format").hidden.default-value("default"))
  .arg(option("filter").hidden.default-value("default"))
  // Short-only action flags that set values on hidden options
  .arg(flag-short("", 'S').no-long.action("sort", "size").hidden.help("sort by file size, largest first"))
  .arg(flag-short("", 't').no-long.action("sort", "time").hidden.help("sort by time, newest first"))
  .arg(flag-short("", 'U').no-long.action("sort", "none").hidden.help("do not sort; list in directory order"))
  .arg(flag-short("", 'v').no-long.action("sort", "version").hidden.help("natural sort of (version) numbers within text"))
  .arg(flag-short("", 'X').no-long.action("sort", "extension").hidden.help("sort alphabetically by entry extension"))
  .arg(flag-short("", 'c').no-long.action("time", "ctime").hidden.help("with -t: sort by ctime"))
  .arg(flag-short("", 'u').no-long.action("time", "atime").hidden.help("with -t: sort by atime"))
  .arg(flag-short("", 'l').no-long.action("format", "long").hidden.help("use a long listing format"))
  .arg(flag-short("", '1').no-long.action("format", "one").hidden.help("list one file per line"))
  .arg(flag-short("", 'C').no-long.action("format", "columns").hidden.help("list entries by columns"))
  .arg(flag-short("", 'p').no-long.action("indicator-style", "slash").hidden.help("append / indicator to directories"))
  // -F as action on classify
  .arg(flag-short("", 'F').no-long.action("classify", "always").hidden.help("append indicator to entries"))
  // Multi-action flags: -g, -n, -o, -f
  .arg(flag-short("", 'g').no-long.action("format", "long").action("filter", "no-owner").hidden)
  .arg(flag-short("", 'n').no-long.action("format", "long").action("numeric-uid-gid", "true").hidden)
  .arg(flag-short("", 'o').no-long.action("format", "long").action("filter", "no-group").hidden)
  .arg(flag-short("", 'f').no-long.action("filter", "all").action("sort", "none").action("format", "default").hidden)
  .arg(flag("numeric-uid-gid").long("numeric-uid-gid")
        .action("format", "long").action("numeric-uid-gid", "true")
        .help("like -l, but list numeric user and group IDs"))
  // Positional
  .arg(positional("FILE").multiple)

// ---------------------------------------------------------------------------
// Convert klap arg-matches to options struct
// ---------------------------------------------------------------------------

fun parse-sort-key(s : string) : sort-key
  match s
    "none"      -> SortNone
    "size"      -> SortSize
    "time"      -> SortTime
    "extension" -> SortExtension
    "width"     -> SortWidth
    "version"   -> SortVersion
    _           -> SortName

fun parse-time-kind(s : string) : time-kind
  match s
    "atime"         -> TimeAtime
    "access"        -> TimeAtime
    "use"           -> TimeAtime
    "ctime"         -> TimeCtime
    "status"        -> TimeCtime
    _               -> TimeMtime

fun parse-classify-when(s : string) : classify-when
  match s
    "always" -> ClassifyAlways
    "yes"    -> ClassifyAlways
    "force"  -> ClassifyAlways
    "auto"   -> ClassifyAuto
    "tty"    -> ClassifyAuto
    "never"  -> ClassifyNever
    "no"     -> ClassifyNever
    "none"   -> ClassifyNever
    _        -> ClassifyNever

fun parse-indicator-style(s : string) : indicator-style
  match s
    "slash"     -> IndicatorSlash
    "file-type" -> IndicatorFileType
    "classify"  -> IndicatorClassify
    _           -> IndicatorNone

pub fun matches-to-options(m : arg-matches) : options
  val format-str = m.get-one-or("format", "default")
  val filter-str = m.get-one-or("filter", "default")
  val long-format = format-str == "long"
  val one-entry = format-str == "one"
  val force-columns = format-str == "columns"
  val show-all = filter-str == "all"
  val almost-all = filter-str == "almost-all"
  val no-owner = filter-str == "no-owner" || m.get-flag("g")
  val no-group-from-filter = filter-str == "no-group"
  val numeric-ids = m.get-one-or("numeric-uid-gid", "false") == "true"
  val classify-str = m.get-one("classify")
  val classify-val = match classify-str
    Just(s) -> parse-classify-when(s)
    Nothing -> ClassifyNever
  Options(
    show-all = show-all,
    almost-all = almost-all,
    ignore-backups = m.get-flag("ignore-backups"),
    force-columns = force-columns,
    dir-only = m.get-flag("directory"),
    classify = classify-val,
    indicator = parse-indicator-style(m.get-one-or("indicator-style", "none")),
    long-format = long-format,
    hide-patterns = m.get-many("hide"),
    ignore-patterns = m.get-many("ignore"),
    reverse = m.get-flag("reverse"),
    no-group = m.get-flag("no-group") || no-group-from-filter,
    no-owner = no-owner,
    numeric-ids = numeric-ids,
    show-author = m.get-flag("author"),
    print-inode = m.get-flag("inode"),
    recurse = m.get-flag("recursive"),
    sort-by = parse-sort-key(m.get-one-or("sort", "name")),
    time-type = parse-time-kind(m.get-one-or("time", "mtime")),
    group-dirs = m.get-flag("group-directories-first"),
    one-entry = one-entry
  )

// ---------------------------------------------------------------------------
// Backward-compatible parse-args — used by tests
// ---------------------------------------------------------------------------

pub type parse-result
  Parsed(opts : options, paths : list<string>)
  HelpRequested
  VersionRequested
  InvalidFlag(flag : string)

pub fun parse-args(args : list<string>) : div parse-result
  match try-klap({ kls-command.parse(args) })
    Right(m) -> Parsed(matches-to-options(m), m.get-positionals)
    Left("__help__") -> HelpRequested
    Left("__version__") -> VersionRequested
    Left(msg) -> InvalidFlag(msg)

// ---------------------------------------------------------------------------
// Sorting — simple insertion sort, fine for directory listings.
// ---------------------------------------------------------------------------

// Get the timestamp for a file based on the time-kind option
fun get-timestamp(p : string, tk : time-kind) : fsys int
  match tk
    TimeMtime -> get-mtime(p)
    TimeAtime -> get-atime(p)
    TimeCtime -> get-ctime(p)

// Get the extension of a filename for -X sorting.
// GNU ls uses strrchr(name, '.') — the part from the last '.' onward.
// Files with no '.' have an empty extension and sort first.
pub fun get-extension(name : string) : string
  val chars = name.list
  val rev = chars.reverse
  match rev.index-of(fn(c) c == '.')
    -1 -> ""   // no dot → empty extension
    n  -> rev.take(n + 1).reverse.string  // includes the dot

// Compare two names by extension, with name tiebreaker.
// This matches GNU ls cmp_extension: compare from the last '.',
// then fall back to full name comparison.
fun cmp-extension(a : string, b : string) : order
  val ea = get-extension(a)
  val eb = get-extension(b)
  match cmp(ea, eb)
    Eq -> cmp(a, b)
    c  -> c

// Compare two names by version (GNU ls -v), using filevercmp via C FFI.
fun cmp-version(a : string, b : string) : order
  val r = filevercmp(a, b)
  if r < 0 then Lt elif r > 0 then Gt else Eq

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
  // Decorate–sort–undecorate: each branch keeps the original 3-tuple so
  // --group-directories-first can partition by raw name after sorting.
  val sorted3 = match opts.sort-by
    SortNone -> ignored
    SortName ->
      if opts.reverse then ignored.sortby(fn(a, b) cmp(b.fst, a.fst))
      else ignored.sortby(fn(a, b) cmp(a.fst, b.fst))
    SortSize ->
      val decorated = ignored.map(fn(e) (e, get-size((dir-path / e.thd.path).string)))
      val s = if opts.reverse then decorated.sortby fn(a, b)
                match cmp(a.snd, b.snd) { Eq -> cmp(b.fst.fst, a.fst.fst); c -> c }
              else decorated.sortby fn(a, b)
                match cmp(b.snd, a.snd) { Eq -> cmp(a.fst.fst, b.fst.fst); c -> c }
      s.map(fn(e) e.fst)
    SortTime ->
      val decorated = ignored.map(fn(e) (e, get-timestamp((dir-path / e.thd.path).string, opts.time-type)))
      val s = if opts.reverse then decorated.sortby fn(a, b)
                match cmp(a.snd, b.snd) { Eq -> cmp(b.fst.fst, a.fst.fst); c -> c }
              else decorated.sortby fn(a, b)
                match cmp(b.snd, a.snd) { Eq -> cmp(a.fst.fst, b.fst.fst); c -> c }
      s.map(fn(e) e.fst)
    SortExtension ->
      if opts.reverse then ignored.sortby(fn(a, b) cmp-extension(b.fst, a.fst))
      else ignored.sortby(fn(a, b) cmp-extension(a.fst, b.fst))
    SortVersion ->
      if opts.reverse then ignored.sortby(fn(a, b) cmp-version(b.fst, a.fst))
      else ignored.sortby(fn(a, b) cmp-version(a.fst, b.fst))
    SortWidth ->
      val decorated = ignored.map(fn(e) (e, e.fst.count))
      val s = if opts.reverse then decorated.sortby fn(a, b)
                match cmp(b.snd, a.snd) { Eq -> cmp(b.fst.fst, a.fst.fst); c -> c }
              else decorated.sortby fn(a, b)
                match cmp(a.snd, b.snd) { Eq -> cmp(a.fst.fst, b.fst.fst); c -> c }
      s.map(fn(e) e.fst)
  // --group-directories-first: partition dirs before files, preserving sort
  val sorted = if opts.group-dirs then
      val (grp-dirs, grp-files) = sorted3.partition(fn(e) is-directory(dir-path / e.thd.path))
      grp-dirs ++ grp-files
    else
      sorted3
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

// Right-justify a string to the given width
fun rjust(s : string, w : int) : string
  val pad = w - s.count
  (if pad > 0 then " ".repeat(pad) else "") ++ s

// Left-justify a string to the given width
fun ljust(s : string, w : int) : string
  val pad = w - s.count
  s ++ (if pad > 0 then " ".repeat(pad) else "")

// Format and print long-format (-l) listing
// entries: (display-name, inode, full-path-for-stat)
pub fun format-long-listing(entries : list<(string, int, string)>, opts : options, show-total : bool = True) : _ ()
  val infos = entries.map fn(e)
    (e, get-file-info(e.thd))
  // Print "total BLOCKS" line (512-byte blocks displayed as 1K blocks)
  if show-total then
    val total-raw = infos.foldl(0) fn(acc, x)
      match x.snd
        Just(fi) -> acc + fi.fi-blocks
        Nothing  -> acc
    echoln("total " ++ (total-raw / 2).show)
  // Compute column widths for alignment
  val nw = infos.foldl(0) fn(mx, x)
    match x.snd
      Just(fi) -> max(mx, fi.fi-nlink.show.count)
      Nothing  -> mx
  val ow = infos.foldl(0) fn(mx, x)
    match x.snd
      Just(fi) -> max(mx, (if opts.numeric-ids then fi.fi-uid.show else fi.fi-owner).count)
      Nothing  -> mx
  val aw = if opts.show-author then
      infos.foldl(0) fn(mx, x)
        match x.snd
          Just(fi) -> max(mx, fi.fi-owner.count)
          Nothing  -> mx
    else 0
  val gw = infos.foldl(0) fn(mx, x)
    match x.snd
      Just(fi) -> max(mx, (if opts.numeric-ids then fi.fi-gid.show else fi.fi-group).count)
      Nothing  -> mx
  val sw = infos.foldl(0) fn(mx, x)
    match x.snd
      Just(fi) -> max(mx, fi.fi-size.show.count)
      Nothing  -> mx
  val iw = if opts.print-inode then
      infos.foldl(0) fn(mx, x)
        max(mx, x.fst.snd.show.count)
    else 0
  // Render each line
  infos.foreach fn(x)
    val (name, ino, fpath) = x.fst
    match x.snd
      Just(fi) ->
        val ip = if opts.print-inode then rjust(ino.show, iw) ++ " " else ""
        val sl = if fi.fi-mode.head-char.default(' ') == 'l' then
            val target = readlink-path(fpath)
            if target.is-empty then "" else " -> " ++ target
          else ""
        val ts = format-timestamp(fi.fi-mtime-sec)
        val owner-str = if opts.numeric-ids then fi.fi-uid.show else fi.fi-owner
        val group-str = if opts.numeric-ids then fi.fi-gid.show else fi.fi-group
        val op = if opts.no-owner then "" else ljust(owner-str, ow) ++ " "
        val gp = if opts.no-group then "" else ljust(group-str, gw) ++ " "
        val ap = if opts.show-author then ljust(fi.fi-owner, aw) ++ " " else ""
        echoln(ip ++ fi.fi-mode ++ " " ++ rjust(fi.fi-nlink.show, nw) ++ " " ++
               op ++ gp ++ ap ++
               rjust(fi.fi-size.show, sw) ++ " " ++ ts ++ " " ++ name ++ sl)
      Nothing ->
        echoln("? " ++ name)

pub fun list-dir(dir-path : path, opts : options, show-header : bool, display-path : string = dir-path.string) : _ int
  if show-header then echoln(display-path ++ ":")
  val tty = stdout-is-tty()
  val (sorted, code) = list-dir-names(dir-path, opts, tty)
  if opts.long-format then
    val full-entries = sorted.map(fn(e) (e.fst, e.snd, (dir-path / e.thd.path).string))
    format-long-listing(full-entries, opts)
  else
    val display = format-entries(sorted.map(fn(e) (e.fst, e.snd)), opts)
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
      SortTime ->
        val with-time = visible-dirs.map(fn(de) (de, get-timestamp((dir-path / de.entry-name.path).string, opts.time-type)))
        val s = if opts.reverse then with-time.sortby fn(a, b)
                  match cmp(a.snd, b.snd) { Eq -> cmp(b.fst.entry-name, a.fst.entry-name); c -> c }
                else with-time.sortby fn(a, b)
                  match cmp(b.snd, a.snd) { Eq -> cmp(a.fst.entry-name, b.fst.entry-name); c -> c }
        s.map(fn(e) e.fst)
      SortExtension ->
        if opts.reverse then visible-dirs.sortby(fn(a, b) cmp-extension(b.entry-name, a.entry-name))
        else visible-dirs.sortby(fn(a, b) cmp-extension(a.entry-name, b.entry-name))
      SortVersion ->
        if opts.reverse then visible-dirs.sortby(fn(a, b) cmp-version(b.entry-name, a.entry-name))
        else visible-dirs.sortby(fn(a, b) cmp-version(a.entry-name, b.entry-name))
      SortWidth ->
        val decorated = visible-dirs.map(fn(de) (de, de.entry-name.count))
        val s = if opts.reverse then decorated.sortby fn(a, b)
                  match cmp(b.snd, a.snd) { Eq -> cmp(b.fst.entry-name, a.fst.entry-name); c -> c }
                else decorated.sortby fn(a, b)
                  match cmp(a.snd, b.snd) { Eq -> cmp(a.fst.entry-name, b.fst.entry-name); c -> c }
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

val short-usage = "Try 'kls --help' for more information."

fun main()
  val code = status
    with fun write(fd, s) print(s)    // bio handler: route to real stdout
    var exit-code := 0
    val m = match try-klap({ kls-command.parse(get-args()) })
      Right(matches) -> matches
      Left("__help__") ->
        show-help()
        exit(0)
      Left("__version__") ->
        show-version()
        exit(0)
      Left(msg) ->
        eprintln("kls: " ++ msg)
        eprintln(short-usage)
        exit(2)
    val opts = matches-to-options(m)
    val paths = m.get-positionals()
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
        eprintln("kls: cannot access '" ++ t.fst ++ "': " ++ err)
        exit-code := set-exit-status(exit-code, serious = False)
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
      SortNone -> file-entries
      SortName ->
        if opts.reverse then file-entries.sortBy(fn(a, b) cmp(b.fst, a.fst))
        else file-entries.sortBy(fn(a, b) cmp(a.fst, b.fst))
      SortSize ->
        val decorated = file-entries.map(fn(e) (e, get-size(e.thd)))
        val s = if opts.reverse then decorated.sortby fn(a, b)
                  match cmp(a.snd, b.snd) { Eq -> cmp(b.fst.fst, a.fst.fst); c -> c }
                else decorated.sortby fn(a, b)
                  match cmp(b.snd, a.snd) { Eq -> cmp(a.fst.fst, b.fst.fst); c -> c }
        s.map(fn(e) e.fst)
      SortTime ->
        val decorated = file-entries.map(fn(e) (e, get-timestamp(e.thd, opts.time-type)))
        val s = if opts.reverse then decorated.sortby fn(a, b)
                  match cmp(a.snd, b.snd) { Eq -> cmp(b.fst.fst, a.fst.fst); c -> c }
                else decorated.sortby fn(a, b)
                  match cmp(b.snd, a.snd) { Eq -> cmp(a.fst.fst, b.fst.fst); c -> c }
        s.map(fn(e) e.fst)
      SortExtension ->
        if opts.reverse then file-entries.sortby(fn(a, b) cmp-extension(b.fst, a.fst))
        else file-entries.sortby(fn(a, b) cmp-extension(a.fst, b.fst))
      SortVersion ->
        if opts.reverse then file-entries.sortby(fn(a, b) cmp-version(b.fst, a.fst))
        else file-entries.sortby(fn(a, b) cmp-version(a.fst, b.fst))
      SortWidth ->
        val decorated = file-entries.map(fn(e) (e, e.fst.count))
        val s = if opts.reverse then decorated.sortby fn(a, b)
                  match cmp(b.snd, a.snd) { Eq -> cmp(b.fst.fst, a.fst.fst); c -> c }
                else decorated.sortby fn(a, b)
                  match cmp(a.snd, b.snd) { Eq -> cmp(a.fst.fst, b.fst.fst); c -> c }
        s.map(fn(e) e.fst)
    val has-files = sorted-file-entries.length > 0
    if opts.long-format then
      if has-files then
        format-long-listing(sorted-file-entries, opts, False)
    else
      val sorted-file-names = format-entries(sorted-file-entries.map(fn(e) (e.fst, e.snd)), opts)
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
      SortTime ->
        val with-time = dirs.map(fn(t) (t, get-timestamp((t.snd).string, opts.time-type)))
        val s = if opts.reverse then with-time.sortby(fn(a, b) cmp(a.snd, b.snd))
                else with-time.sortby(fn(a, b) cmp(b.snd, a.snd))
        s.map(fn(e) e.fst)
      SortExtension ->
        if opts.reverse then dirs.sortby(fn(a, b) cmp-extension(b.fst, a.fst))
        else dirs.sortby(fn(a, b) cmp-extension(a.fst, b.fst))
      SortVersion ->
        if opts.reverse then dirs.sortby(fn(a, b) cmp-version(b.fst, a.fst))
        else dirs.sortby(fn(a, b) cmp-version(a.fst, b.fst))
      SortWidth ->
        val decorated = dirs.map(fn(t) (t, t.fst.count))
        val s = if opts.reverse then decorated.sortby fn(a, b)
                  match cmp(b.snd, a.snd) { Eq -> cmp(b.fst.fst, a.fst.fst); c -> c }
                else decorated.sortby fn(a, b)
                  match cmp(a.snd, b.snd) { Eq -> cmp(a.fst.fst, b.fst.fst); c -> c }
        s.map(fn(e) e.fst)
      _ ->
        if opts.reverse then dirs.reverse
        else dirs
    val show-header = sorted-dirs.length > 1 || has-files
    sorted-dirs.foreach-indexed fn(i, dir-entry)
      if i > 0 || has-files then echoln("")
      val dir-code = list-dir(dir-entry.snd, opts, show-header)
      if dir-code > exit-code then exit-code := dir-code
    if exit-code > 0 then exit(exit-code)
  process-exit(code)
