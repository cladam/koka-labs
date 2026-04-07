// ---------------------------------------------------------------------------
// columns.kk — multi-column layout engine
//
// Implements the GNU ls column layout algorithm:
// Given N entries with display widths and a terminal width, find the
// maximum number of columns that fits, then render entries in
// column-major (-C) or row-major (-x) order.
//
// See docs/gnu-ls-columns.md for a full dissection of the algorithm.
// ---------------------------------------------------------------------------
module columns

extern import
  c file "columns-inline.c"

// ---------------------------------------------------------------------------
// C FFI — terminal width detection via ioctl / COLUMNS / fallback 80
// ---------------------------------------------------------------------------

pub extern terminal-width() : io int
  c "kk_os_terminal_width"

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

val min-column-width = 3  // 1 char name + 2 char separator
val separator-width  = 2  // two spaces between columns
val default-tabsize  = 8  // default tab stop width, matches GNU ls

// ---------------------------------------------------------------------------
// Layout result
// ---------------------------------------------------------------------------

// A computed layout: how many columns, and the width of each column.
// Column widths for non-last columns include the 2-char separator.
struct layout
  cols      : int
  col-widths : list<int>

// ---------------------------------------------------------------------------
// calculate-columns
//
// Brute-force simulation: try every possible column count from 1 to
// max-cols, simulate where each entry would land, track per-column
// maximum widths, and pick the highest column count whose total width
// fits within the terminal.
//
// by-columns: true for column-major (-C), false for row-major (-x)
// ---------------------------------------------------------------------------

// Ceiling division
fun cdiv(a : int, b : int) : int
  (a + b - 1) / b

// A mutable layout hypothesis for one column count
struct hypothesis
  valid     : bool
  total-width : int
  widths    : list<int>  // per-column max widths

// Update a hypothesis for a single entry
fun update-hypothesis(h : hypothesis, col : int, real-width : int) : hypothesis
  val old-width = h.widths.iat(col).default(min-column-width)
  if real-width > old-width then
    val new-total = h.total-width + (real-width - old-width)
    Hypothesis(
      valid = h.valid && new-total < 0, // placeholder, checked by caller
      total-width = new-total,
      widths = h.widths.set(col, real-width)
    )
  else h

// Set element at index in a list (0-based)
fun set(xs : list<int>, idx : int, value : int) : list<int>
  xs.map-indexed fn(i, x)
    if i == idx then value else x

// Get element at index in a list (0-based)
fun iat(xs : list<int>, idx : int) : maybe<int>
  match xs
    Nil -> Nothing
    Cons(x, rest) -> if idx == 0 then Just(x) else rest.iat(idx - 1)

fun calculate-columns(entry-widths : list<int>, line-width : int, by-columns : bool) : layout
  val n = entry-widths.length
  if n == 0 then return Layout(1, [line-width])

  val max-cols-by-width = cdiv(line-width, min-column-width)
  val max-cols = min(max-cols-by-width, n)

  // Initialize hypotheses: for k columns, each column starts at min-column-width
  val init-hypotheses = list(1, max-cols).map fn(k)
    Hypothesis(
      valid = True,
      total-width = k * min-column-width,
      widths = list(1, k).map(fn(_) min-column-width)
    )

  // Process each file through all hypotheses
  val final-hypotheses = entry-widths.foldl-indexed(init-hypotheses) fn(filesno, hyps, width)
    hyps.map-indexed fn(hi, h)
      if !h.valid then h
      else
        val k = hi + 1  // number of columns for this hypothesis
        val col = if by-columns then
            val rows = cdiv(n, k)
            filesno / rows
          else
            filesno % k
        // Last column has no separator
        val real-width = width + (if col == k - 1 then 0 else separator-width)
        val old-width = h.widths.iat(col).default(min-column-width)
        if real-width > old-width then
          val new-total = h.total-width + (real-width - old-width)
          Hypothesis(
            valid = new-total < line-width,
            total-width = new-total,
            widths = h.widths.set(col, real-width)
          )
        else h

  // Pick highest valid column count (walk from max-cols down to 1)
  val result = final-hypotheses.reverse.foldl(Nothing) fn(found, h)
    match found
      Just(_) -> found
      Nothing -> if h.valid then Just(h) else Nothing

  match result
    Just(h) -> Layout(h.widths.length, h.widths)
    Nothing -> Layout(1, [line-width])

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

// Tab-aware indentation from position `from` to position `to`.
// Uses tab characters when they would skip past at least one tab stop,
// otherwise uses spaces. Matches GNU ls indent() behavior.
fun indent(from0 : int, to : int, tabsize : int) : div string
  var pos := from0
  var result := ""
  while { pos < to }
    if tabsize > 0 && (to / tabsize) > ((pos + 1) / tabsize) then
      result := result ++ "\t"
      pos := pos + tabsize - (pos % tabsize)
    else
      result := result ++ " "
      pos := pos + 1
  result

// Render entries in column-major order (-C, default)
// Returns a list of lines to print
pub fun render-column-major(entries : list<string>, line-width : int, tabsize : int = default-tabsize) : div list<string>
  val n = entries.length
  if n == 0 then return []

  val entry-widths = entries.map(fn(e) e.count)
  val lay = calculate-columns(entry-widths, line-width, by-columns = True)
  val cols = lay.cols
  val rows = cdiv(n, cols)

  // Convert entries list to a function for random access
  val arr = entries.vector

  list(0, rows - 1).map fn(row)
    var pos := 0
    val parts = list(0, cols - 1).filter-map fn(col)
      val filesno = col * rows + row
      if filesno >= n then Nothing
      else
        val entry = arr.at(filesno).default("")
        val name-width = entry.count
        val col-width = lay.col-widths.iat(col).default(0)
        // Last column (or last entry in row) doesn't need padding
        if col == cols - 1 || col * rows + row + rows >= n then
          Just(entry)
        else
          val gap = indent(pos + name-width, pos + col-width, tabsize)
          pos := pos + col-width
          Just(entry ++ gap)
    parts.join("")

// Render entries in row-major order (-x)
// Returns a list of lines to print
pub fun render-row-major(entries : list<string>, line-width : int, tabsize : int = default-tabsize) : div list<string>
  val n = entries.length
  if n == 0 then return []

  val entry-widths = entries.map(fn(e) e.count)
  val lay = calculate-columns(entry-widths, line-width, by-columns = False)
  val cols = lay.cols

  val arr = entries.vector

  list(0, n - 1).foldl(([], [], 0)) fn((lines, current-line, pos), filesno)
    val col = filesno % cols
    val entry = arr.at(filesno).default("")
    val name-width = entry.count
    val col-width = lay.col-widths.iat(col).default(0)
    if col == 0 && filesno > 0 then
      // New row
      val padded = if col == cols - 1 || filesno == n - 1 then entry
                   else entry ++ indent(name-width, col-width, tabsize)
      val new-pos = col-width
      (Cons(current-line.reverse.join(""), lines), [padded], new-pos)
    else
      val padded = if col == cols - 1 || filesno == n - 1 then entry
                   else entry ++ indent(pos + name-width, pos + col-width, tabsize)
      val new-pos = pos + col-width
      (lines, Cons(padded, current-line), new-pos)
  .fst-with-last2

// Helper to flush the last line
fun fst-with-last2(triple : (list<string>, list<string>, int)) : list<string>
  val (lines, current, _) = triple
  val last-line = current.reverse.join("")
  Cons(last-line, lines).reverse

// Safe vector access
fun vat(v : vector<string>, idx : int) : exn maybe<string>
  if idx >= 0 && idx < v.length then Just(v[idx])
  else Nothing

// Indexed foldl
fun foldl-indexed(xs : list<a>, init : b, f : (int, b, a) -> b) : b
  var idx := 0
  xs.foldl(init) fn(acc, x)
    val result = f(idx, acc, x)
    idx := idx + 1
    result
