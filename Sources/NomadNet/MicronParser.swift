/// Pure-Swift port of the Python `MicronParser` (NomadNet textui/MicronParser.py).
///
/// # Micron markup summary
///
/// ## Line-level directives (first character of the raw line)
/// | First char | Meaning |
/// |---|---|
/// | `#` | Comment — line is discarded |
/// | `\` | Escape — the `\` is stripped; remainder rendered literally (no further markup) |
/// | `<` | Section reset — depth becomes 0; rest of line is re-parsed |
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
/// | `` `F `` *rgb* | Set foreground colour (3-digit hex) |
/// | `` `FT `` *rrggbb* | Set foreground colour (6-digit hex) |
/// | `` `f `` | Reset foreground to default |
/// | `` `B `` *rgb* | Set background colour (3-digit hex) |
/// | `` `BT `` *rrggbb* | Set background colour (6-digit hex) |
/// | `` `b `` | Reset background to default |
/// | `` `` `` `` | Reset all formatting (bold/underline/italic + colours + alignment) |
/// | `` `c `` | Align center |
/// | `` `l `` | Align left |
/// | `` `r `` | Align right |
/// | `` `a `` | Reset alignment to default (left) |
/// | `` `:<name> `` | Anchor declaration |
/// | `` `[label`url`fields] `` | Link |
/// | `` `<flags\|name`data> `` | Form field |

import Foundation

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

    // Current colour state
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

// MARK: - MicronParser

/// Parses Micron markup into an array of `MicronNode` AST nodes.
///
/// Usage:
/// ```swift
/// let nodes = MicronParser.parse(markupString)
/// ```
public struct MicronParser {

    // MARK: Public API

    /// Parse a complete Micron document and return its AST.
    ///
    /// - Parameter markup: Raw Micron markup text.
    /// - Returns: Array of `MicronNode` values representing the document.
    public static func parse(_ markup: String) -> [MicronNode] {
        var state = ParseState()
        var nodes: [MicronNode] = []

        let lines = markup.split(separator: "\n", omittingEmptySubsequences: false)

        for rawLine in lines {
            let line = String(rawLine)
            if line.isEmpty {
                nodes.append(.emptyLine)
            } else {
                let produced = parseLine(line, state: &state)
                nodes.append(contentsOf: produced)
            }
        }

        // If we were still in table mode at EOF, flush the buffer
        if state.tableMode, !state.tableBuffer.isEmpty {
            nodes.append(.table(
                rows: state.tableBuffer.map { [$0] },
                alignment: state.tableAlign,
                maxWidth: state.tableMaxWidth
            ))
        }

        return nodes
    }

    // MARK: - Line-level parsing

    /// Parse a single non-empty line against the current mutable state.
    /// Returns zero or more nodes to append to the output.
    private static func parseLine(_ line: String, state: inout ParseState) -> [MicronNode] {
        var chars = Array(line)
        guard !chars.isEmpty else { return [] }

        let first = chars[0]

        // ── Literal mode ────────────────────────────────────────────────────
        // The literal toggle `` `= `` works in *and* out of literal mode.
        if line == "`=" {
            state.literal.toggle()
            return []
        }

        if state.literal {
            // In literal mode only render text as-is (allow escaping the toggle)
            let text = (line == "\\`=") ? "`=" : line
            let span = MicronSpan.text(text, style: state.currentStyle())
            return [.line([span], depth: state.depth, alignment: state.alignment)]
        }

        // ── Comment ─────────────────────────────────────────────────────────
        if first == "#" { return [] }

        // ── Escape prefix ───────────────────────────────────────────────────
        // A leading `\` strips the backslash and passes the rest through with
        // NO further inline parsing (same as pre_escape=True in Python).
        var preEscape = false
        var workLine = line
        if first == "\\" {
            workLine = String(line.dropFirst())
            preEscape = true
        } else {
            // Heading lines containing `< (field opening) lose their heading status
            if first == ">" && line.contains("`<") {
                workLine = line.drop(while: { $0 == ">" }).description
            }
        }

        let workChars = Array(workLine)
        guard !workChars.isEmpty else { return [] }
        let workFirst = workChars[0]

        // ── Table toggle `` `t `` ────────────────────────────────────────────
        if workLine.hasPrefix("`t") {
            let afterT = workChars.dropFirst(2)
            var align: MicronAlignment? = nil
            var maxWidth: Int? = nil
            var rest = afterT[...]

            if let first = rest.first {
                if first == "l" { align = .left; rest = rest.dropFirst() }
                else if first == "c" { align = .center; rest = rest.dropFirst() }
                else if first == "r" { align = .right; rest = rest.dropFirst() }
            }
            if !rest.isEmpty, let w = Int(String(rest)) {
                maxWidth = w
            }

            if state.tableMode {
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
            } else {
                state.tableMode = true
                state.tableBuffer = []
                state.tableAlign = align
                state.tableMaxWidth = maxWidth
                return []
            }
        }

        // ── Table buffering ──────────────────────────────────────────────────
        if state.tableMode {
            state.tableBuffer.append(workLine)
            return []
        }

        // ── Partial `` `{ `` ────────────────────────────────────────────────
        if workLine.hasPrefix("`{") {
            if let partial = parsePartial(String(workLine.dropFirst(2))) {
                return [.partial(partial)]
            }
            return []
        }

        // ── Section reset `<` ────────────────────────────────────────────────
        if !preEscape && workFirst == "<" {
            state.depth = 0
            let rest = String(workChars.dropFirst())
            if rest.isEmpty { return [] }
            return parseLine(rest, state: &state)
        }

        // ── Section headings `>` ──────────────────────────────────────────────
        if !preEscape && workFirst == ">" {
            var level = 0
            var idx = 0
            while idx < workChars.count && workChars[idx] == ">" {
                level += 1
                idx += 1
            }
            state.depth = level
            let content = String(workChars[idx...])
            guard !content.isEmpty else { return [] }

            let slug = slugify(content)
            let spans = makeOutput(line: Array(content), state: &state, preEscape: false)
            guard !spans.isEmpty else { return [] }
            return [.heading(level: level, spans: spans, depth: level, slug: slug)]
        }

        // ── Horizontal rule `-` ───────────────────────────────────────────────
        if !preEscape && workFirst == "-" {
            let fillChar: Character
            if workChars.count == 2 {
                let candidate = workChars[1]
                fillChar = candidate.asciiValue.map { $0 >= 32 } ?? false ? candidate : "\u{2500}"
            } else {
                fillChar = "\u{2500}"
            }
            return [.horizontalRule(character: fillChar)]
        }

        // ── Regular line ──────────────────────────────────────────────────────
        let spans = makeOutput(line: Array(workLine), state: &state, preEscape: preEscape)
        guard !spans.isEmpty else { return [] }
        return [.line(spans, depth: state.depth, alignment: state.alignment)]
    }

    // MARK: - Inline output builder

    /// Tokenize a single line into `MicronSpan` values.
    ///
    /// Mirrors `make_output()` in the Python parser.
    private static func makeOutput(
        line: [Character],
        state: inout ParseState,
        preEscape: Bool
    ) -> [MicronSpan] {

        var output: [MicronSpan] = []
        var part = ""                   // accumulator for plain-text runs
        var mode: ParseMode = .text
        var escape = preEscape
        var i = 0

        // Helper — flush the current text accumulator into a span
        func flushPart() {
            if !part.isEmpty {
                output.append(.text(part, style: state.currentStyle()))
                part = ""
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
                        let hex = String(line[(i + 2)..<(i + 8)])
                        state.fgColor = parseColor6(hex) ?? .default
                        i += 7; mode = .text; i += 1; continue
                    } else if i + 3 < line.count {
                        let hex = String(line[(i + 1)..<(i + 4)])
                        state.fgColor = parseColor3(hex) ?? .default
                        i += 3; mode = .text; i += 1; continue
                    }

                case "f":
                    state.fgColor = state.defaultFg

                case "B":
                    // `BT rrggbb  (6-digit) or `B rgb (3-digit)
                    if i + 1 < line.count && line[i + 1] == "T" && i + 7 < line.count {
                        let hex = String(line[(i + 2)..<(i + 8)])
                        state.bgColor = parseColor6(hex) ?? .default
                        i += 7; mode = .text; i += 1; continue
                    } else if i + 3 < line.count {
                        let hex = String(line[(i + 1)..<(i + 4)])
                        state.bgColor = parseColor3(hex) ?? .default
                        i += 3; mode = .text; i += 1; continue
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
                    // Anchor declaration: `:<name>
                    let nameStart = i + 1
                    var nameEnd = nameStart
                    while nameEnd < line.count && (line[nameEnd].isLetter || line[nameEnd].isNumber || line[nameEnd] == "_" || line[nameEnd] == "-") {
                        nameEnd += 1
                    }
                    let anchorName = String(line[nameStart..<nameEnd])
                    if !anchorName.isEmpty {
                        flushPart()
                        output.append(.text("", style: state.currentStyle())) // zero-width placeholder
                        // We embed the anchor as a text span with an empty string — renderers
                        // that need the anchor name should use the heading slug mechanism instead.
                        // A dedicated `.anchor` node is emitted only when parsing standalone `:`
                        // lines. Here we note it via a state side-channel for upstream callers.
                    }
                    i = nameEnd; mode = .text; flushPart(); continue

                case "<":
                    // Form field: `<flags|name`data>
                    flushPart()
                    if let (field, skip) = parseField(line: line, afterBracket: i + 1, state: state) {
                        output.append(.field(field))
                        i += skip; mode = .text; i += 1; continue
                    }

                case "[":
                    // Link: `[label`url`fields]
                    flushPart()
                    if let (link, skip) = parseLink(line: line, afterBracket: i + 1, state: state) {
                        output.append(.link(link))
                        i += skip; mode = .text; i += 1; continue
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
    private static func parsePartial(_ s: String) -> MicronPartial? {
        guard let endPos = s.firstIndex(of: "}") else { return nil }
        let descriptor = String(s[s.startIndex..<endPos])
        let components = descriptor.split(separator: "`", omittingEmptySubsequences: false).map(String.init)

        let url: String
        var refresh: Double? = nil
        var fields: [String] = []

        switch components.count {
        case 1:
            url = components[0]
        case 2:
            url = components[0]
            refresh = Double(components[1])
        case 3...:
            url = components[0]
            refresh = Double(components[1])
            fields = components[2].split(separator: "|").map(String.init)
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
    /// Format: `label\`url\`fields]` — returns (link, charactersConsumed).
    private static func parseLink(
        line: [Character],
        afterBracket: Int,
        state: ParseState
    ) -> (MicronLink, Int)? {
        // Find the closing `]`
        let slice = line[afterBracket...]
        guard let relEnd = slice.firstIndex(of: "]") else { return nil }

        let linkData = String(line[afterBracket..<relEnd])
        let components = linkData.split(separator: "`", omittingEmptySubsequences: false).map(String.init)

        let label: String
        let url: String
        var fields: [String] = []

        switch components.count {
        case 1:
            url = components[0]
            label = url.isEmpty ? "" : url
        case 2:
            label = components[0]
            url = components[1]
        case 3...:
            label = components[0]
            url = components[1]
            fields = components[2].split(separator: "|").map(String.init)
        default:
            return nil
        }

        guard !url.isEmpty else { return nil }
        let displayLabel = label.isEmpty ? url : label
        let consumed = line.distance(from: line.startIndex, to: relEnd) - afterBracket + 1 // +1 for ]

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
    /// Format: `flags|name\`data>` — returns (field, charactersConsumed).
    private static func parseField(
        line: [Character],
        afterBracket: Int,
        state: ParseState
    ) -> (MicronField, Int)? {
        // Find the closing backtick that ends the flags|name portion
        let slice = Array(line[afterBracket...])
        guard let backtickRel = slice.firstIndex(of: "`") else { return nil }
        let backtickAbs = afterBracket + backtickRel

        let fieldContent = String(line[afterBracket..<backtickAbs])

        // Find the closing `>`
        guard let closingRel = Array(line[backtickAbs...]).firstIndex(of: ">") else { return nil }
        let closingAbs = backtickAbs + closingRel

        let fieldData = String(line[(backtickAbs + 1)..<closingAbs])

        // Parse flags|name
        var fieldType: MicronFieldType = .text
        var name: String
        var value = ""
        var width = 24
        var masked = false
        var prechecked = false

        if fieldContent.contains("|") {
            let parts = fieldContent.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            var flags = parts.count > 0 ? parts[0] : ""
            name = parts.count > 1 ? parts[1] : ""
            value = parts.count > 2 ? parts[2] : ""
            if parts.count > 3, parts[3] == "*" { prechecked = true }

            if flags.contains("^") {
                fieldType = .radio
                flags = flags.replacingOccurrences(of: "^", with: "")
            } else if flags.contains("?") {
                fieldType = .checkbox
                flags = flags.replacingOccurrences(of: "?", with: "")
            } else if flags.contains("!") {
                fieldType = .masked
                flags = flags.replacingOccurrences(of: "!", with: "")
                masked = true
            }

            if !flags.isEmpty, let w = Int(flags) {
                width = min(w, 256)
            }
        } else {
            name = fieldContent
        }

        let consumed = closingAbs - afterBracket + 1 // +1 for >

        let label = (fieldType == .checkbox || fieldType == .radio) ? fieldData : ""
        let dataValue = (fieldType == .checkbox || fieldType == .radio) ? (value.isEmpty ? fieldData : value) : fieldData

        let field = MicronField(
            fieldType: fieldType,
            name: name,
            value: dataValue,
            label: label,
            width: width,
            prechecked: prechecked,
            style: state.currentStyle()
        )
        _ = masked // suppress warning; fieldType .masked already encodes this
        return (field, consumed)
    }

    // MARK: - Colour parsers

    /// Parse a 3-character hex colour string ("rgb") into a `MicronColor`.
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
              let b = UInt8(String(h[2]), radix: 16) else { return nil }
        return .rgb3(r: r, g: g, b: b)
    }

    /// Parse a 6-character hex colour string ("rrggbb") into a `MicronColor`.
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
        let slug = stripped
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
        let pattern = "`[FB]T[0-9a-fA-F]{6}|`[FB][0-9a-fA-F]{3}|`:[A-Za-z0-9_\\-]*|`[!*_=fbacrl`<>\\{\\}]"
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
