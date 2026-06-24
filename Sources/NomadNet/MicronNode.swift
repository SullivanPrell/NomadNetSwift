/// AST node types produced by `MicronParser`.
///
/// The Micron markup language is used by NomadNet pages (`.mu` files).
/// Each node corresponds to a logical element in the rendered document.

// MARK: - Color

/// A Micron colour value.
///
/// Colours are specified in one of three formats matching the Python parser:
/// - `.default`  — inherit / terminal default
/// - `.rgb3(r,g,b)` — 3-nibble hex (each component 0–F)
/// - `.rgb6(...)` — 6-digit hex (e.g. "ff8800")
/// - `.grey(percent)` — greyscale, "g" + 2-digit decimal percentage (0–99)
public enum MicronColor: Equatable {
    /// Terminal / inherited default colour.
    case `default`
    /// Three-nibble RGB hex colour (one hex digit per channel, 0–F).
    case rgb3(r: UInt8, g: UInt8, b: UInt8)
    /// Six-digit full RGB hex colour (two hex digits per channel, 00–FF).
    case rgb6(r: UInt8, g: UInt8, b: UInt8)
    /// Greyscale expressed as an integer percentage (0–99), prefixed by "g" in Micron.
    case grey(percent: UInt8)
}

// MARK: - Alignment

/// Horizontal alignment of a line or element.
public enum MicronAlignment: Equatable {
    case left
    case center
    case right
}

// MARK: - Style

/// The rendering style active at a point in the document.
///
/// Mirrors the Python `state` dict keys that influence text appearance.
public struct MicronStyle: Equatable {
    public var bold: Bool
    public var underline: Bool
    public var italic: Bool
    public var strikethrough: Bool
    public var blink: Bool
    public var fgColor: MicronColor
    public var bgColor: MicronColor
    public var alignment: MicronAlignment

    public static let `default` = MicronStyle(
        bold: false,
        underline: false,
        italic: false,
        strikethrough: false,
        blink: false,
        fgColor: .default,
        bgColor: .default,
        alignment: .left
    )

    public init(
        bold: Bool = false,
        underline: Bool = false,
        italic: Bool = false,
        strikethrough: Bool = false,
        blink: Bool = false,
        fgColor: MicronColor = .default,
        bgColor: MicronColor = .default,
        alignment: MicronAlignment = .left
    ) {
        self.bold = bold
        self.underline = underline
        self.italic = italic
        self.strikethrough = strikethrough
        self.blink = blink
        self.fgColor = fgColor
        self.bgColor = bgColor
        self.alignment = alignment
    }
}

// MARK: - Form field types

/// The type of an interactive form field embedded in a Micron page.
public enum MicronFieldType: Equatable {
    /// Single-line or multi-line text input.
    case text
    /// Password-masked text input.
    case masked
    /// Boolean checkbox.
    case checkbox
    /// Single-selection radio button (grouped by name).
    case radio
}

/// An interactive form field embedded inside a line.
public struct MicronField: Equatable {
    public var fieldType: MicronFieldType
    public var name: String
    /// Pre-filled / default text for a text field; selected value for checkbox/radio.
    public var value: String
    /// Display label for checkbox and radio buttons.
    public var label: String
    /// Preferred display width (columns) for text fields.
    public var width: Int
    /// Whether a checkbox/radio is pre-checked.
    public var prechecked: Bool
    public var style: MicronStyle

    public init(
        fieldType: MicronFieldType,
        name: String,
        value: String = "",
        label: String = "",
        width: Int = 24,
        prechecked: Bool = false,
        style: MicronStyle = .default
    ) {
        self.fieldType = fieldType
        self.name = name
        self.value = value
        self.label = label
        self.width = width
        self.prechecked = prechecked
        self.style = style
    }
}

// MARK: - Link

/// A navigable link embedded in a line.
public struct MicronLink: Equatable {
    /// Display text. If empty in markup the URL is used as label.
    public var label: String
    /// Navigation target (NomadNet node hash + path, or a relative path).
    public var url: String
    /// Optional form field values to attach to the request.
    public var fields: [String]
    public var style: MicronStyle

    public init(label: String, url: String, fields: [String] = [], style: MicronStyle = .default) {
        self.label = label
        self.url = url
        self.fields = fields
        self.style = style
    }
}

// MARK: - Partial

/// A partial (transclusion / embedded sub-page).
///
/// In the Python implementation these are loaded asynchronously and rendered in place.
public struct MicronPartial: Equatable {
    public var url: String
    public var refreshInterval: Double?
    public var fields: [String]

    public init(url: String, refreshInterval: Double? = nil, fields: [String] = []) {
        self.url = url
        self.refreshInterval = refreshInterval
        self.fields = fields
    }
}

// MARK: - Inline span

/// A span of text or interactive element within a line, carrying its own style.
public enum MicronSpan: Equatable {
    /// Plain text with a style applied.
    case text(String, style: MicronStyle)
    /// A navigable link.
    case link(MicronLink)
    /// An interactive form field.
    case field(MicronField)
}

// MARK: - Top-level nodes

/// A top-level AST node emitted by `MicronParser`.
public enum MicronNode: Equatable {
    /// An empty line (renders as a blank row).
    case emptyLine

    /// A line of inline spans at normal (depth-0) or indented (depth > 0) nesting.
    ///
    /// - Parameters:
    ///   - spans: Inline content.
    ///   - depth: Section nesting depth (0 = no indent).
    ///   - alignment: Horizontal alignment.
    case line([MicronSpan], depth: Int, alignment: MicronAlignment)

    /// A heading line (produced by one or more leading `>` characters).
    ///
    /// - Parameters:
    ///   - level: Heading level (1, 2, or 3+).
    ///   - spans: Inline content after the `>` prefix(es).
    ///   - depth: Section nesting depth when the heading was encountered.
    ///   - slug: URL-friendly anchor slug derived from the heading text.
    case heading(level: Int, spans: [MicronSpan], depth: Int, slug: String)

    /// A horizontal divider (produced by a line starting with `-`).
    ///
    /// - Parameter character: The fill character (default `─` U+2500).
    case horizontalRule(character: Character)

    /// A table rendered from pipe-separated rows buffered between `` `t `` markers.
    ///
    /// After the Python implementation delegates actual table layout to
    /// `MarkdownToMicron.format_table_raw`, each formatted row is re-parsed;
    /// here we store the raw row strings for downstream renderers.
    case table(rows: [[String]], alignment: MicronAlignment?, maxWidth: Int?)

    /// A transclusion / embedded sub-page.
    case partial(MicronPartial)

    /// An anchor declaration (`` `:<name> ``) — zero-width position marker.
    case anchor(name: String)
}
