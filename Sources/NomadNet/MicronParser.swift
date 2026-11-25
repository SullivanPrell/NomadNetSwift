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

  // `#!fold` glyphs, and a collapsible heading's initial state waiting for its row
  // (MicronParser.py "fold_glyphs", "_collapsible_pending").
  var foldGlyphs: (open: String, closed: String) = ("▾", "▸")
  var collapsiblePending: Bool? = nil

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

  /// Whether each collapsible heading starts collapsed, by its index into `nodes`.
  ///
  /// `` `-> `` starts collapsed and `` `+> `` open. Python: `attrmaps.collapsibles`.
  /// A collapsed heading hides the rows after it up to the next heading at its depth or
  /// shallower.
  public let collapsibles: [Int: Bool]

  /// Glyph shown before an open collapsible heading (`#!fold`, default `▾`).
  public let foldOpenGlyph: String

  /// Glyph shown before a collapsed heading (`#!fold`, default `▸`).
  public let foldClosedGlyph: String

  /// Creates a page from its parsed nodes.
  public init(
    nodes: [MicronNode],
    anchors: [String: Int] = [:],
    foregroundColor: MicronColor? = nil,
    backgroundColor: MicronColor? = nil,
    collapsibles: [Int: Bool] = [:],
    foldOpenGlyph: String = "▾",
    foldClosedGlyph: String = "▸"
  ) {
    self.nodes = nodes
    self.anchors = anchors
    self.foregroundColor = foregroundColor
    self.backgroundColor = backgroundColor
    self.collapsibles = collapsibles
    self.foldOpenGlyph = foldOpenGlyph
    self.foldClosedGlyph = foldClosedGlyph
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
    var collapsibles: [Int: Bool] = [:]

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

      if let collapsed = state.collapsiblePending {
        collapsibles[nodes.count] = collapsed
        state.collapsiblePending = nil
      }
      nodes.append(contentsOf: produced)
    }

    // A table still open at the end of the page is dropped: Python renders a table only when
    // the closing `t arrives (MicronParser.py:131-159, :516-531).
    // Anchors still pending at EOF are dropped, as in Python (they are
    // never bound at MicronParser.py:126-131 and stay absent from the map).

    return MicronPage(
      nodes: nodes,
      anchors: anchors,
      foregroundColor: pageFg,
      backgroundColor: pageBg,
      collapsibles: collapsibles,
      foldOpenGlyph: state.foldGlyphs.open,
      foldClosedGlyph: state.foldGlyphs.closed
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
    case 3: return parseColor3(value)
    case 6: return parseColor6(value)
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
    guard var first = line.first else { return [] }
    var line = line

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

    // ── Collapsible heading `` `+> `` / `` `-> `` (MicronParser.py:488-494) ──
    var collapsed: Bool? = nil
    if line.count > 2, line[0] == "`", line[1] == "+" || line[1] == "-", line[2] == ">" {
      collapsed = line[1] == "-"
      line.removeFirst(2)
      first = ">"
    }

    // ── A line with a field loses its heading status, before the escape and comment checks
    // (MicronParser.py:497-500) ──
    if first == ">" && firstIndex(of: Array("`<".unicodeScalars), in: line) != nil {
      line.removeFirst(line.prefix(while: { $0 == ">" }).count)
      first = line[0]
    }

    // ── Comment, and the `#!fold` directive (MicronParser.py:508-513) ──────
    if first == "#" {
      let parts = String(codePoints: line).split(whereSeparator: \.isWhitespace).map(String.init)
      if parts.first == "#!fold", parts.count >= 2 {
        state.foldGlyphs = (parts[1], parts.count >= 3 ? parts[2] : parts[1])
      }
      return []
    }

    // ── Escape prefix ───────────────────────────────────────────────────
    // A leading `\` strips the backslash and passes the rest through with
    // NO further inline parsing (same as pre_escape=True in Python).
    var preEscape = false
    var workLine = line[...]
    if first == "\\" {
      workLine = line.dropFirst()
      preEscape = true
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
      if !rest.isEmpty, let w = NomadNetUtil.pythonInt(rest) {
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
      // render_table returns nothing for fewer than two rows (MicronParser.py:291-292).
      let produced: [MicronNode] =
        state.tableBuffer.count < 2
        ? []
        : [
          .table(
            rows: state.tableBuffer.map { [$0] },
            alignment: state.tableAlign,
            maxWidth: state.tableMaxWidth)
        ]
      state.tableMode = false
      state.tableBuffer = []
      state.tableAlign = nil
      state.tableMaxWidth = nil
      return produced
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

    // ── Image `` `( `` ─────────────────────────────────────────────────────
    if work.starts(with: "`(".unicodeScalars) {
      guard let image = parseImage(Array(work.dropFirst(2))) else { return [] }
      return [.image(image, depth: state.depth)]
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

      // The heading is made with the heading theme's style, then the style the page had comes
      // back (MicronParser.py:572-578). The theme sets no bold, underline or italic, and its
      // colors belong to the renderer.
      let latched = (
        state.bold, state.underline, state.italic, state.fgColor, state.bgColor
      )
      state.bold = false
      state.underline = false
      state.italic = false
      state.fgColor = .default
      state.bgColor = .default
      let spans = makeOutput(line: content, state: &state, preEscape: false)
      (state.bold, state.underline, state.italic, state.fgColor, state.bgColor) = latched
      // Heading slugs auto-register as anchors (MicronParser.py:308-310);
      // the slug stays pending even when the heading renders no output.
      let slug = slugify(String(codePoints: content))
      if !slug.isEmpty { state.pendingAnchors.append((name: slug, headingSlug: true)) }
      guard !spans.isEmpty else { return [] }
      if let collapsed { state.collapsiblePending = collapsed }
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
            state.fgColor = parseColor6(line[(i + 2)..<(i + 8)]) ?? .default
            i += 7
            mode = .text
            i += 1
            continue
          } else if i + 3 < line.count {
            state.fgColor = parseColor3(line[(i + 1)..<(i + 4)]) ?? .default
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
            state.bgColor = parseColor6(line[(i + 2)..<(i + 8)]) ?? .default
            i += 7
            mode = .text
            i += 1
            continue
          } else if i + 3 < line.count {
            state.bgColor = parseColor3(line[(i + 1)..<(i + 4)]) ?? .default
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
            if let link { output.append(.link(link)) }
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

    let url = String(codePoints: components[0])
    var refresh: Double? = nil
    var fieldsComponent: ArraySlice<Unicode.Scalar> = []

    // Python raises on a refresh that float() rejects, and the whole partial goes with it
    // (MicronParser.py:188-192, :219). More than three components leave no URL (:194-197).
    switch components.count {
    case 1:
      break
    case 2:
      guard let value = NomadNetUtil.pythonFloat(components[1]) else { return nil }
      refresh = value
    case 3:
      guard let value = NomadNetUtil.pythonFloat(components[1]) else { return nil }
      refresh = value
      fieldsComponent = components[2]
    default:
      return nil
    }

    guard !url.isEmpty else { return nil }
    // Minimum refresh of 1 second (matches Python)
    if let r = refresh, r < 1 { refresh = nil }

    return MicronPartial(url: url, refreshInterval: refresh, fields: fieldList(fieldsComponent))
  }

  /// Parse an image after the opening `` `( ``: `alt\`key=value\`…\`url)`.
  ///
  /// Python: `parse_image` (MicronParser.py:221-283), which drops a line with no `)` past
  /// its start or with no backtick.
  private static func parseImage(_ s: [Unicode.Scalar]) -> MicronImage? {
    guard let end = s.lastIndex(of: ")"), end > 0 else { return nil }
    let fields = split(s[..<end], on: "`").map {
      String(codePoints: $0).trimmingCharacters(in: .whitespaces)
    }
    guard fields.count >= 2 else { return nil }
    var image = MicronImage(altText: fields[0], url: fields[fields.count - 1])
    for prop in fields.dropFirst().dropLast() {
      guard let eq = prop.firstIndex(of: "=") else { continue }
      let key = prop[..<eq].trimmingCharacters(in: .whitespaces)
      let value = prop[prop.index(after: eq)...].trimmingCharacters(in: .whitespaces)
      switch key {
      case "w": image.width = value
      case "h": image.height = value
      case "a":
        image.alignment =
          [
            "c": .center, "center": .center, "l": .left, "left": .left, "r": .right,
            "right": .right,
          ][
            value]
      default: break
      }
    }
    return image
  }

  /// Parse a link after the opening `[`.
  ///
  /// Format: `label\`url\`fields]`—returns (link, charactersConsumed). The link is `nil`
  /// when the markup has an empty URL or more than three parts, which Python consumes
  /// without output (MicronParser.py:1056-1074).
  private static func parseLink(
    line: [Unicode.Scalar],
    afterBracket: Int,
    state: ParseState
  ) -> (MicronLink?, Int)? {
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
    case 3:
      label = String(codePoints: components[0])
      url = String(codePoints: components[1])
      fields = fieldList(components[2])
    default:
      label = ""
      url = ""
    }

    let consumed = end - afterBracket + 1  // +1 for ]
    guard !url.isEmpty else { return (nil, consumed) }
    let displayLabel = label.isEmpty ? url : label

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
    var rows = 1
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

      // `WxR`: width, then rows of a multi-line field, read with int() and stored only on a
      // text field (MicronParser.py:984-995).
      if !flags.isEmpty, fieldType == .text || fieldType == .masked {
        let x = flags.firstIndex(of: "x") ?? flags.endIndex  // str.partition("x")
        if let w = NomadNetUtil.pythonInt(flags[..<x]) { width = min(w, 256) }
        if x < flags.endIndex, let r = NomadNetUtil.pythonInt(flags[(x + 1)...]) {
          rows = max(1, min(r, 256))
        }
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
      rows: rows,
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
    s.isEmpty ? [] : split(s, on: "|").map { String(codePoints: $0) }
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
    parseColor3(Array(hex.unicodeScalars)[...])
  }

  /// Parse 3 code points ("rgb" or "gNN") as Python's `high_color` reads them, one code point at
  /// a time (MicronParser.py:796-845).
  static func parseColor3(_ code: ArraySlice<Unicode.Scalar>) -> MicronColor? {
    let c = Array(code)
    guard c.count == 3 else { return nil }
    if c[0] == "g" {
      guard let tens = NomadNetUtil.pythonDecimalDigit(c[1]),
        let ones = NomadNetUtil.pythonDecimalDigit(c[2])
      else { return nil }
      return .grey(percent: UInt8(tens * 10 + ones))
    }
    guard let r = NomadNetUtil.pythonHexDigit(c[0]),
      let g = NomadNetUtil.pythonHexDigit(c[1]),
      let b = NomadNetUtil.pythonHexDigit(c[2])
    else { return nil }
    return .rgb3(r: UInt8(r), g: UInt8(g), b: UInt8(b))
  }

  /// Parse a 6-character hex color string ("rrggbb") into a `MicronColor`.
  static func parseColor6(_ hex: String) -> MicronColor? {
    parseColor6(Array(hex.unicodeScalars)[...])
  }

  /// Parse 6 code points ("rrggbb") one code point at a time (MicronParser.py:796-845).
  static func parseColor6(_ code: ArraySlice<Unicode.Scalar>) -> MicronColor? {
    let c = Array(code)
    guard c.count == 6 else { return nil }
    let digits = c.compactMap { NomadNetUtil.pythonHexDigit($0) }
    guard digits.count == 6 else { return nil }
    return .rgb6(
      r: UInt8(digits[0] * 16 + digits[1]),
      g: UInt8(digits[2] * 16 + digits[3]),
      b: UInt8(digits[4] * 16 + digits[5]))
  }

  // MARK: - Slug generation

  /// Produce a URL-safe slug from heading text, stripping Micron formatting codes.
  ///
  /// Mirrors `slugify_micron()` in the Python parser.
  public static func slugify(_ text: String) -> String {
    // re.sub(r"[^A-Za-z0-9]+", "-", stripped).strip("-").lower() (MicronParser.py:90-94):
    // only ASCII letters and digits survive, and the lowercasing comes last.
    var slug = String.UnicodeScalarView()
    var gap = false
    for scalar in stripMicronCodes(text).unicodeScalars {
      switch scalar.value {
      case 0x30...0x39, 0x61...0x7A:
        if gap, !slug.isEmpty { slug.append("-") }
        gap = false
        slug.append(scalar)
      case 0x41...0x5A:
        if gap, !slug.isEmpty { slug.append("-") }
        gap = false
        slug.append(Unicode.Scalar(UInt8(scalar.value + 0x20)))
      default:
        gap = true
      }
    }
    return String(slug)
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
      "`[FB]T[0-9a-fA-F]{6}|`[FB][0-9a-fA-F]{3}|`:[A-Za-z0-9_\\-]*|`[!*_=fbacrl`<>\\{]"
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
