//===----------------------------------------------------------------------===//
// Copyright (c) 2026 NomadNetSwift contributors.
//
// Licensed under the GNU General Public License, version 3 (GPL-3.0). See
// LICENSE in the repository root for the full license text, and NOTICE for
// attribution of the upstream project this file is derived from.
//
// SPDX-License-Identifier: GPL-3.0-only
//===----------------------------------------------------------------------===//

/// Pure-Swift port of the Python `MicronParser` (NomadNet textui/MicronParser.py).
///
/// # Micron markup summary
///
/// ## Line-level directives (first character of the raw line)
/// | First char | Meaning |
/// |---|---|
/// | `#` | Comment—line is discarded |
/// | `\` | Escape—the `\` is stripped; remainder rendered literally (no further markup) |
/// | `<` | Section reset—depth becomes 0; rest of line is re-parsed |
/// | `>`, `>>`, `>>>` | Heading level 1/2/3 |
/// | `-` or `-x` | Horizontal rule (optional char after `-`, default `─`) |
/// | `` `= `` | Toggle literal mode |
/// | `` `t `` | Toggle table mode (buffers rows until second `` `t ``) |
/// | `` `{ `` | Partial (transclusion) |
///
/// ## Inline formatting (`` ` `` introduces the next command character)
/// | Sequence | Meaning |
/// |---|---|
/// | `` `! `` | Toggle bold |
/// | `` `_ `` | Toggle underline |
/// | `` `* `` | Toggle italic |
/// | `` `F `` *rgb* | Set foreground color (3-digit hex) |
/// | `` `FT `` *rrggbb* | Set foreground color (6-digit hex) |
/// | `` `f `` | Reset foreground to default |
/// | `` `B `` *rgb* | Set background color (3-digit hex) |
/// | `` `BT `` *rrggbb* | Set background color (6-digit hex) |
/// | `` `b `` | Reset background to default |
/// | `` `` `` `` | Reset all formatting (bold/underline/italic + colors + alignment) |
/// | `` `c `` | Align center |
/// | `` `l `` | Align left |
/// | `` `r `` | Align right |
/// | `` `a `` | Reset alignment to default (left) |
/// | `` `:<name> `` | Anchor declaration |
/// | `` `[label`url`fields] `` | Link |
/// | `` `<flags\|name`data> `` | Form field |

import Foundation

extension String {
  /// Creates a string from `codePoints` without normalizing them.
  fileprivate init<S: Sequence>(codePoints: S) where S.Element == Unicode.Scalar {
    var view = String.UnicodeScalarView()
    view.append(contentsOf: codePoints)
    self.init(view)
  }
}

// MARK: - Parser state

/// Mutable parsing state threaded through the document parse.
private struct ParseState {
  // Literal / table modes
  var literal: Bool = false
  var tableMode: Bool = false
  var tableBuffer: [String] = []
  var tableAlign: MicronAlignment? = nil
  var tableMaxWidth: Int? = nil

  // Section nesting
  var depth: Int = 0

  // Current color state
  var fgColor: MicronColor = .default
  var bgColor: MicronColor = .default
  var defaultFg: MicronColor = .default
  var defaultBg: MicronColor = .default

  // Current text formatting
  var bold: Bool = false
  var underline: Bool = false
  var italic: Bool = false
  var strikethrough: Bool = false
  var blink: Bool = false

  // Alignment
  var alignment: MicronAlignment = .left
  var defaultAlignment: MicronAlignment = .left

  // Radio button groups (name → existing group tag)
  var radioGroups: [String: Int] = [:]

  // Anchor names declared but not yet bound to a produced row
  // (MicronParser.py "pending_anchors", bound at :126-131).
  // `headingSlug` entries come from MicronParser.py:308-310 and bind to the
  // heading row itself, so no separate `.anchor` marker node is emitted.
  var pendingAnchors: [(name: String, headingSlug: Bool)] = []

  func currentStyle() -> MicronStyle {
    MicronStyle(
      bold: bold,
      underline: underline,
      italic: italic,
      strikethrough: strikethrough,
      blink: blink,
      fgColor: fgColor,
      bgColor: bgColor,
      alignment: alignment
    )
  }

  mutating func resetFormatting() {
    bold = false
    underline = false
    italic = false
    fgColor = defaultFg
    bgColor = defaultBg
    alignment = defaultAlignment
  }
}

// MARK: - MicronPage

/// The complete result of parsing a Micron page.
///
/// Carries everything the Python browser derives from a page besides the
/// widget tree: the `#!fg=` / `#!bg=` page colors (Browser.py:1824-1844) and
/// the anchors map bound by `markup_to_attrmaps` (MicronParser.py:126-131,
/// exposed at :142). Returned as one value so no consumer can drop them.
public struct MicronPage: Equatable {
  /// The parsed document AST.
  public let nodes: [MicronNode]

  /// Anchor name → index into `nodes` of the row the anchor is bound to
  /// (the Python `anchors[name] = row_index` mapping).
  ///
  /// Rows bound by an
  /// explicit `` `:name `` declaration are immediately preceded by a
  /// zero-width `.anchor` marker node; heading slugs bind to the
  /// `.heading` node itself, which carries the slug.
  public let anchors: [String: Int]

  /// Page-wide default foreground from a `#!fg=` directive, if present and valid.
  public let foregroundColor: MicronColor?

  /// Page-wide default background from a `#!bg=` directive, if present and valid.
  public let backgroundColor: MicronColor?

  /// Creates a page from its parsed nodes.
  public init(
    nodes: [MicronNode],
    anchors: [String: Int] = [:],
    foregroundColor: MicronColor? = nil,
    backgroundColor: MicronColor? = nil
  ) {
    self.nodes = nodes
    self.anchors = anchors
    self.foregroundColor = foregroundColor
    self.backgroundColor = backgroundColor
  }
}

// MARK: - MicronParser

/// Parses Micron markup into an array of `MicronNode` AST nodes.
///
/// Usage:
/// ```swift
/// let page = MicronParser.parsePage(markupString)
/// ```
public struct MicronParser {

  // MARK: Public API

  /// Parse a complete Micron document, including page-level metadata.
  ///
  /// - Parameter markup: Raw Micron markup text.
  /// - Returns: A `MicronPage` carrying the AST, the anchors map, and any
  ///   `#!fg=` / `#!bg=` page colors.
  public static func parsePage(_ markup: String) -> MicronPage {
    parsePage(markup, colorsFrom: markup)
  }

  /// Parses `markup`, taking the page colors from `source`.
  ///
  /// The browser reads `#!fg=` and `#!bg=` from the markup a node sent, and renders that
  /// markup after `strip_modifiers` (`Browser.py:1824-1846`), so the two can differ.
  static func parsePage(_ markup: String, colorsFrom source: String) -> MicronPage {
    // The page colors seed default_state (MicronParser.py:121), so plain text inherits them
    // and `f/`b reset to them.
    let pageFg = pageColorDirective("#!fg=", in: source)
    let pageBg = pageColorDirective("#!bg=", in: source)

    var state = ParseState()
    if let fg = pageFg {
      state.fgColor = fg
      state.defaultFg = fg
    }
    if let bg = pageBg {
      state.bgColor = bg
      state.defaultBg = bg
    }

    var nodes: [MicronNode] = []
    var anchors: [String: Int] = [:]

    // markup_to_attrmaps strips control and zero-width characters, then splits on the "\n"
    // code point (MicronParser.py:107, :117), so a "\r\n" ending leaves "\r" on the line.
    let lines = NomadNetUtil.stripControl(markup).unicodeScalars.split(
      separator: "\n", omittingEmptySubsequences: false)

    for rawLine in lines {
      let line = Array(rawLine)
      let produced: [MicronNode]
      if line.isEmpty {
        // Python renders empty lines as urwid.Text("")—a produced
        // row, so pending anchors bind to it (MicronParser.py:120-131).
        produced = [.emptyLine]
      } else {
        produced = parseLine(line, state: &state)
      }
      guard !produced.isEmpty else { continue }

      // Pending anchors bind to the next produced row; first declaration
      // wins (MicronParser.py:126-131). For explicit `:name declarations
      // a zero-width `.anchor` marker is emitted ahead of the bound row
      // as an in-tree scroll target; heading slugs bind to the `.heading`
      // node itself, which already carries the slug.
      if !state.pendingAnchors.isEmpty {
        var markerNames: [String] = []
        var bindNames: [String] = []
        for entry in state.pendingAnchors
        where !entry.name.isEmpty && anchors[entry.name] == nil && !bindNames.contains(entry.name) {
          bindNames.append(entry.name)
          if !entry.headingSlug { markerNames.append(entry.name) }
        }
        for name in markerNames { nodes.append(.anchor(name: name)) }
        let rowIndex = nodes.count
        for name in bindNames { anchors[name] = rowIndex }
        state.pendingAnchors = []
      }

      nodes.append(contentsOf: produced)
    }

    // If still in table mode at EOF, flush the buffer
    if state.tableMode, !state.tableBuffer.isEmpty {
      nodes.append(
        .table(
          rows: state.tableBuffer.map { [$0] },
          alignment: state.tableAlign,
          maxWidth: state.tableMaxWidth
        ))
    }
    // Anchors still pending at EOF are dropped, as in Python (they are
    // never bound at MicronParser.py:126-131 and stay absent from the map).

    return MicronPage(
      nodes: nodes,
      anchors: anchors,
      foregroundColor: pageFg,
      backgroundColor: pageBg
    )
  }

  /// Parse a complete Micron document and return its AST only.
  ///
  /// - Parameter markup: Raw Micron markup text.
  /// - Returns: Array of `MicronNode` values representing the document.
  @available(
    *, deprecated, message: "Use parsePage(_:) — parse(_:) discards page colors and anchors"
  )
  public static func parse(_ markup: String) -> [MicronNode] {
    parsePage(markup).nodes
  }

  // MARK: - Page color directives

  /// Extract a page-level color directive value (`#!fg=` / `#!bg=`).
  ///
  /// Mirrors Browser.py:1824-1844: Python takes the first occurrence anywhere
  /// in the document, reads the value up to the next `"\n"` code point, and
  /// accepts only a value of exactly 3 or 6 code points. Python ignores a
  /// directive on the final line without a trailing newline, because
  /// find("\n") returns -1, which fails both length checks.
  static func pageColorDirective(_ directive: String, in markup: String) -> MicronColor? {
    let scalars = Array(markup.unicodeScalars)
    guard let found = firstIndex(of: Array(directive.unicodeScalars), in: scalars),
      let newline = find("\n", in: scalars, from: found + directive.unicodeScalars.count)
    else { return nil }
    let value = scalars[(found + directive.unicodeScalars.count)..<newline]
    switch value.count {
    case 3: return parseColor3(String(codePoints: value))
    case 6: return parseColor6(String(codePoints: value))
    default: return nil
    }
  }

  // MARK: - Line-level parsing

  /// Parse a single non-empty line against the current mutable state.
  ///
  /// The line is a sequence of code points, as Python indexes a `str`, so a combining mark is
  /// a character of its own rather than part of the one before it.
  ///
  /// Returns zero or more nodes to append to the output.
  private static func parseLine(_ line: [Unicode.Scalar], state: inout ParseState) -> [MicronNode] {
    guard let first = line.first else { return [] }

    // ── Literal mode ────────────────────────────────────────────────────
    // The literal toggle `` `= `` works in *and* out of literal mode.
    if line.elementsEqual("`=".unicodeScalars) {
      state.literal.toggle()
      return []
    }

    if state.literal {
      // In literal mode only render text as-is (allow escaping the toggle)
      let text = line.elementsEqual("\\`=".unicodeScalars) ? "`=" : String(codePoints: line)
      let span = MicronSpan.text(text, style: state.currentStyle())
      return [.line([span], depth: state.depth, alignment: state.alignment)]
    }

    // ── Comment ─────────────────────────────────────────────────────────
    if first == "#" { return [] }

    // ── Escape prefix ───────────────────────────────────────────────────
    // A leading `\` strips the backslash and passes the rest through with
    // NO further inline parsing (same as pre_escape=True in Python).
    var preEscape = false
    var workLine = line[...]
    if first == "\\" {
      workLine = line.dropFirst()
      preEscape = true
    } else if first == ">" && firstIndex(of: Array("`<".unicodeScalars), in: line) != nil {
      // Heading lines containing `< (field opening) lose their heading status
      workLine = line.drop(while: { $0 == ">" })
    }

    let work = Array(workLine)
    guard let workFirst = work.first else { return [] }

    // ── Table toggle `` `t `` ────────────────────────────────────────────
    if work.starts(with: "`t".unicodeScalars) {
      var align: MicronAlignment? = nil
      var maxWidth: Int? = nil
      var rest = work.dropFirst(2)

      switch rest.first {
      case "l":
        align = .left
        rest = rest.dropFirst()
      case "c":
        align = .center
        rest = rest.dropFirst()
      case "r":
        align = .right
        rest = rest.dropFirst()
      default:
        break
      }
      if !rest.isEmpty, let w = Int(String(codePoints: rest)) {
        maxWidth = w
      }

      guard state.tableMode else {
        state.tableMode = true
        state.tableBuffer = []
        state.tableAlign = align
        state.tableMaxWidth = maxWidth
        return []
      }
      // Second `t  → flush buffer
      let rows = state.tableBuffer.map { [$0] }
      let node = MicronNode.table(
        rows: rows,
        alignment: state.tableAlign,
        maxWidth: state.tableMaxWidth
      )
      state.tableMode = false
      state.tableBuffer = []
      state.tableAlign = nil
      state.tableMaxWidth = nil
      return [node]
    }

    // ── Table buffering ──────────────────────────────────────────────────
    if state.tableMode {
      state.tableBuffer.append(String(codePoints: work))
      return []
    }

    // ── Partial `` `{ `` ────────────────────────────────────────────────
    if work.starts(with: "`{".unicodeScalars) {
      if let partial = parsePartial(Array(work.dropFirst(2))) {
        return [.partial(partial)]
      }
      return []
    }

    // ── Section reset `<` ────────────────────────────────────────────────
    if !preEscape && workFirst == "<" {
      state.depth = 0
      return parseLine(Array(work.dropFirst()), state: &state)
    }

    // ── Section headings `>` ──────────────────────────────────────────────
    if !preEscape && workFirst == ">" {
      let level = work.prefix(while: { $0 == ">" }).count
      state.depth = level
      let content = Array(work.dropFirst(level))
      guard !content.isEmpty else { return [] }

      let spans = makeOutput(line: content, state: &state, preEscape: false)
      // Heading slugs auto-register as anchors (MicronParser.py:308-310);
      // the slug stays pending even when the heading renders no output.
      let slug = slugify(String(codePoints: content))
      if !slug.isEmpty { state.pendingAnchors.append((name: slug, headingSlug: true)) }
      guard !spans.isEmpty else { return [] }
      return [.heading(level: level, spans: spans, depth: level, slug: slug)]
    }

    // ── Horizontal rule `-` ───────────────────────────────────────────────
    if !preEscape && workFirst == "-" {
      // A two-code-point line keeps its fill when urwid draws it in one cell
      // (MicronParser.py:603-613).
      let fillChar: Character
      if work.count == 2 && MicronCellWidth.isSingleCell(work[1]) {
        fillChar = Character(work[1])
      } else {
        fillChar = "\u{2500}"
      }
      return [.horizontalRule(character: fillChar)]
    }

    // ── Regular line ──────────────────────────────────────────────────────
    let spans = makeOutput(line: work, state: &state, preEscape: preEscape)
    guard !spans.isEmpty else { return [] }
    return [.line(spans, depth: state.depth, alignment: state.alignment)]
  }

  // MARK: - Inline output builder

  /// Tokenize a single line into `MicronSpan` values.
  ///
  /// Mirrors `make_output()` in the Python parser, which reads the line one code point at a
  /// time (MicronParser.py:883-884).
  private static func makeOutput(
    line: [Unicode.Scalar],
    state: inout ParseState,
    preEscape: Bool
  ) -> [MicronSpan] {

    var output: [MicronSpan] = []
    var part = String.UnicodeScalarView()  // accumulator for plain-text runs
    var mode: ParseMode = .text
    var escape = preEscape
    var i = 0

    // Helper—flush the current text accumulator into a span
    func flushPart() {
      if !part.isEmpty {
        output.append(.text(String(part), style: state.currentStyle()))
        part = String.UnicodeScalarView()
      }
    }

    while i < line.count {
      let c = line[i]

      switch mode {
      case .formatting:
        // ── Formatting command characters ────────────────────────────
        switch c {
        case "_":
          state.underline.toggle()

        case "!":
          state.bold.toggle()

        case "*":
          state.italic.toggle()

        case "F":
          // `FT rrggbb  (6-digit) or `F rgb (3-digit)
          if i + 1 < line.count && line[i + 1] == "T" && i + 7 < line.count {
            let hex = String(codePoints: line[(i + 2)..<(i + 8)])
            state.fgColor = parseColor6(hex) ?? .default
            i += 7
            mode = .text
            i += 1
            continue
          } else if i + 3 < line.count {
            let hex = String(codePoints: line[(i + 1)..<(i + 4)])
            state.fgColor = parseColor3(hex) ?? .default
            i += 3
            mode = .text
            i += 1
            continue
          }

        case "f":
          state.fgColor = state.defaultFg

        case "B":
          // `BT rrggbb  (6-digit) or `B rgb (3-digit)
          if i + 1 < line.count && line[i + 1] == "T" && i + 7 < line.count {
            let hex = String(codePoints: line[(i + 2)..<(i + 8)])
            state.bgColor = parseColor6(hex) ?? .default
            i += 7
            mode = .text
            i += 1
            continue
          } else if i + 3 < line.count {
            let hex = String(codePoints: line[(i + 1)..<(i + 4)])
            state.bgColor = parseColor3(hex) ?? .default
            i += 3
            mode = .text
            i += 1
            continue
          }

        case "b":
          state.bgColor = state.defaultBg

        case "`":
          // Reset all formatting
          state.resetFormatting()

        case "c":
          state.alignment = .center

        case "l":
          state.alignment = .left

        case "r":
          state.alignment = .right

        case "a":
          state.alignment = state.defaultAlignment

        case ":":
          // Anchor declaration `:<name>, terminated by any character
          // outside [A-Za-z0-9_-] (MicronParser.py:657-667). Zero-width:
          // contributes no output; parsePage binds the pending name to
          // this line's row (MicronParser.py:126-131).
          let nameStart = i + 1
          var nameEnd = nameStart
          while nameEnd < line.count
            && (NomadNetUtil.isPythonAlnum(line[nameEnd]) || line[nameEnd] == "_"
              || line[nameEnd] == "-")
          {
            nameEnd += 1
          }
          let anchorName = String(codePoints: line[nameStart..<nameEnd])
          if !anchorName.isEmpty {
            state.pendingAnchors.append((name: anchorName, headingSlug: false))
          }
          i = nameEnd
          mode = .text
          continue

        case "<":
          // Form field: `<flags|name`data>
          flushPart()
          if let (field, skip) = parseField(line: line, afterBracket: i + 1, state: state) {
            output.append(.field(field))
            i += skip
            mode = .text
            i += 1
            continue
          }

        case "[":
          // Link: `[label`url`fields]
          flushPart()
          if let (link, skip) = parseLink(line: line, afterBracket: i + 1, state: state) {
            output.append(.link(link))
            i += skip
            mode = .text
            i += 1
            continue
          }

        default:
          break
        }

        mode = .text
        flushPart()

      case .text:
        if c == "\\" {
          if escape {
            part.append(c)
            escape = false
          } else {
            escape = true
          }
        } else if c == "`" {
          if escape {
            part.append(c)
            escape = false
          } else {
            flushPart()
            mode = .formatting
          }
        } else {
          part.append(c)
          escape = false
        }
      }

      i += 1
    }

    flushPart()
    return output
  }

  // MARK: - Sub-parsers

  /// Parse a partial descriptor after the opening `` `{ ``.
  ///
  /// Format: `url\`refresh\`fields}`
  private static func parsePartial(_ s: [Unicode.Scalar]) -> MicronPartial? {
    guard let endPos = s.firstIndex(of: "}") else { return nil }
    let components = split(s[..<endPos], on: "`")

    let url: String
    var refresh: Double? = nil
    var fields: [String] = []

    switch components.count {
    case 1:
      url = String(codePoints: components[0])
    case 2:
      url = String(codePoints: components[0])
      refresh = Double(String(codePoints: components[1]))
    case 3...:
      url = String(codePoints: components[0])
      refresh = Double(String(codePoints: components[1]))
      fields = fieldList(components[2])
    default:
      return nil
    }

    guard !url.isEmpty else { return nil }
    // Minimum refresh of 1 second (matches Python)
    if let r = refresh, r < 1 { refresh = nil }

    return MicronPartial(url: url, refreshInterval: refresh, fields: fields)
  }

  /// Parse a link after the opening `[`.
  ///
  /// Format: `label\`url\`fields]`—returns (link, charactersConsumed).
  private static func parseLink(
    line: [Unicode.Scalar],
    afterBracket: Int,
    state: ParseState
  ) -> (MicronLink, Int)? {
    // Find the closing `]`
    guard let end = find("]", in: line, from: afterBracket) else { return nil }

    let components = split(line[afterBracket..<end], on: "`")

    let label: String
    let url: String
    var fields: [String] = []

    switch components.count {
    case 1:
      url = String(codePoints: components[0])
      label = url.isEmpty ? "" : url
    case 2:
      label = String(codePoints: components[0])
      url = String(codePoints: components[1])
    case 3...:
      label = String(codePoints: components[0])
      url = String(codePoints: components[1])
      fields = fieldList(components[2])
    default:
      return nil
    }

    guard !url.isEmpty else { return nil }
    let displayLabel = label.isEmpty ? url : label
    let consumed = end - afterBracket + 1  // +1 for ]

    let link = MicronLink(
      label: displayLabel,
      url: url,
      fields: fields,
      style: state.currentStyle()
    )
    return (link, consumed)
  }

  /// Parse a form field after the opening `<`.
  ///
  /// Format: `flags|name\`data>`—returns (field, charactersConsumed).
  private static func parseField(
    line: [Unicode.Scalar],
    afterBracket: Int,
    state: ParseState
  ) -> (MicronField, Int)? {
    // Find the closing backtick that ends the flags|name portion
    guard let backtickAbs = find("`", in: line, from: afterBracket) else { return nil }

    let fieldContent = line[afterBracket..<backtickAbs]

    // Find the closing `>`
    guard let closingAbs = find(">", in: line, from: backtickAbs) else { return nil }

    let fieldData = String(codePoints: line[(backtickAbs + 1)..<closingAbs])

    // Parse flags|name
    var fieldType: MicronFieldType = .text
    var name: String
    var value = ""
    var width = 24
    var masked = false
    var prechecked = false

    if fieldContent.contains("|") {
      let parts = split(fieldContent, on: "|")
      var flags = parts.count > 0 ? Array(parts[0]) : []
      name = parts.count > 1 ? String(codePoints: parts[1]) : ""
      value = parts.count > 2 ? String(codePoints: parts[2]) : ""
      if parts.count > 3, parts[3].elementsEqual("*".unicodeScalars) { prechecked = true }

      if flags.contains("^") {
        fieldType = .radio
        flags.removeAll { $0 == "^" }
      } else if flags.contains("?") {
        fieldType = .checkbox
        flags.removeAll { $0 == "?" }
      } else if flags.contains("!") {
        fieldType = .masked
        flags.removeAll { $0 == "!" }
        masked = true
      }

      if !flags.isEmpty, let w = Int(String(codePoints: flags)) {
        width = min(w, 256)
      }
    } else {
      name = String(codePoints: fieldContent)
    }

    let consumed = closingAbs - afterBracket + 1  // +1 for >

    let label = (fieldType == .checkbox || fieldType == .radio) ? fieldData : ""
    let dataValue =
      (fieldType == .checkbox || fieldType == .radio)
      ? (value.isEmpty ? fieldData : value) : fieldData

    let field = MicronField(
      fieldType: fieldType,
      name: name,
      value: dataValue,
      label: label,
      width: width,
      prechecked: prechecked,
      style: state.currentStyle()
    )
    _ = masked  // suppress warning; fieldType .masked already encodes this
    return (field, consumed)
  }

  /// Splits `s` at every `separator`, keeping empty components, as Python's `str.split`.
  private static func split(_ s: ArraySlice<Unicode.Scalar>, on separator: Unicode.Scalar)
    -> [ArraySlice<Unicode.Scalar>]
  {
    s.split(separator: separator, omittingEmptySubsequences: false)
  }

  /// The non-empty `|`-separated names in a link's or partial's field list.
  private static func fieldList(_ s: ArraySlice<Unicode.Scalar>) -> [String] {
    s.split(separator: "|").map { String(codePoints: $0) }
  }

  /// The index of the first `scalar` in `line` at or after `start`, as Python's `str.find`.
  private static func find(_ scalar: Unicode.Scalar, in line: [Unicode.Scalar], from start: Int)
    -> Int?
  {
    guard start < line.count else { return nil }
    return line[start...].firstIndex(of: scalar)
  }

  /// The index of the first occurrence of `needle` in `line`, as Python's `str.find`.
  private static func firstIndex(of needle: [Unicode.Scalar], in line: [Unicode.Scalar]) -> Int? {
    guard !needle.isEmpty, needle.count <= line.count else { return nil }
    return (0...(line.count - needle.count)).first {
      line[$0..<($0 + needle.count)].elementsEqual(needle)
    }
  }

  // MARK: - Color parsers

  /// Parse a 3-character hex color string ("rgb") into a `MicronColor`.
  static func parseColor3(_ hex: String) -> MicronColor? {
    let h = Array(hex)
    guard h.count == 3 else { return nil }
    if h[0] == "g" {
      // Greyscale: "g" + 2-digit decimal
      guard let pct = UInt8(String(h[1...2])) else { return nil }
      return .grey(percent: pct)
    }
    guard let r = UInt8(String(h[0]), radix: 16),
      let g = UInt8(String(h[1]), radix: 16),
      let b = UInt8(String(h[2]), radix: 16)
    else { return nil }
    return .rgb3(r: r, g: g, b: b)
  }

  /// Parse a 6-character hex color string ("rrggbb") into a `MicronColor`.
  static func parseColor6(_ hex: String) -> MicronColor? {
    guard hex.count == 6 else { return nil }
    let s = hex
    let idx = s.startIndex
    guard let r = UInt8(s[idx..<s.index(idx, offsetBy: 2)], radix: 16),
      let g = UInt8(s[s.index(idx, offsetBy: 2)..<s.index(idx, offsetBy: 4)], radix: 16),
      let b = UInt8(s[s.index(idx, offsetBy: 4)..<s.index(idx, offsetBy: 6)], radix: 16)
    else { return nil }
    return .rgb6(r: r, g: g, b: b)
  }

  // MARK: - Slug generation

  /// Produce a URL-safe slug from heading text, stripping Micron formatting codes.
  ///
  /// Mirrors `slugify_micron()` in the Python parser.
  public static func slugify(_ text: String) -> String {
    // Strip formatting codes (backtick sequences)
    let stripped = stripMicronCodes(text)
    // Replace non-alphanumeric runs with hyphens
    let slug =
      stripped
      .lowercased()
      .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return slug
  }

  /// Strip Micron inline formatting codes from a string (for plain-text uses like slugs).
  public static func stripMicronCodes(_ text: String) -> String {
    // Matches the Python `_MICRON_STRIP_RE`:
    //   `FT[0-9a-fA-F]{6}
    //   `F[0-9a-fA-F]{3}
    //   `BT[0-9a-fA-F]{6}
    //   `B[0-9a-fA-F]{3}
    //   `:[A-Za-z0-9_\-]*
    //   `[!*_=fbacrl`<>{]
    let pattern =
      "`[FB]T[0-9a-fA-F]{6}|`[FB][0-9a-fA-F]{3}|`:[A-Za-z0-9_\\-]*|`[!*_=fbacrl`<>\\{\\}]"
    guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
    let range = NSRange(text.startIndex..., in: text)
    return re.stringByReplacingMatches(in: text, range: range, withTemplate: "")
  }

  // MARK: - Mode enum (private)

  private enum ParseMode {
    case text
    case formatting
  }
}
