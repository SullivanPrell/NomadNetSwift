import Foundation

// MARK: - NomadNetUtil

/// Text processing utilities for NomadNet display, rendering, and name sanitization.
///
/// Corresponds to `nomadnet/util.py`.
public enum NomadNetUtil {

    // MARK: – strip_modifiers

    /// Characters that are known to render incorrectly in many fonts and should be
    /// replaced with a space. Matches Python `invalid_rendering`.
    private static let invalidRendering: [Character] = ["🕵️", "☝"]

    /// Strip Unicode modifiers, emoji skin tones, variation selectors, and control
    /// characters. Normalizes CRLF to LF and removes NUL bytes.
    ///
    /// - Returns: `nil` if `text` is `nil`, otherwise the cleaned string.
    ///
    /// Corresponds to Python `strip_modifiers(text)`.
    public static func stripModifiers(_ text: String?) -> String? {
        guard var t = text else { return nil }

        // Replace known bad-rendering chars with a space
        for c in invalidRendering { t = t.replacingOccurrences(of: String(c), with: " ") }

        // Category-based pass: strip combining marks (M*) and format chars (Cf),
        // keep everything else. Matches Python's process_characters() loop.
        var scalars: [Unicode.Scalar] = []
        for scalar in t.unicodeScalars {
            let cat = scalar.properties.generalCategory
            switch cat {
            // Marks (Mn, Mc, Me) → strip
            case .nonspacingMark, .spacingMark, .enclosingMark:
                break
            // Format characters (Cf) → strip
            case .format:
                break
            // ZWJ (U+200D) and ZWNJ (U+200C) are Cf but listed explicitly in Python
            // (already handled above since Cf is stripped)
            default:
                scalars.append(scalar)
            }
        }
        t = String(String.UnicodeScalarView(scalars))

        // Additional regex passes matching Python's post-processing
        let opts = String.CompareOptions.regularExpression

        // Variation Selectors (U+FE00–U+FE0F)
        t = t.replacingOccurrences(of: "[\u{FE00}-\u{FE0F}]", with: "", options: opts)
        // Variation Selectors Supplement (U+E0100–U+E01EF)
        t = t.replacingOccurrences(of: "[\u{E0100}-\u{E01EF}]", with: "", options: opts)
        // Emoji modifier fitzpatrick (skin tones, U+1F3FB–U+1F3FF)
        t = t.replacingOccurrences(of: "[\u{1F3FB}-\u{1F3FF}]", with: "", options: opts)
        // ZWJ / ZWNJ (already stripped in the scalar pass above as Cf, but kept for clarity)
        t = t.replacingOccurrences(of: "[\u{200D}\u{200C}]", with: "", options: opts)

        // Normalize CRLF → LF, then CR → LF
        t = t.replacingOccurrences(of: "\r\n", with: "\n")
        t = t.replacingOccurrences(of: "\r", with: "\n")

        // Remove NUL bytes
        t = t.replacingOccurrences(of: "\0", with: "")

        return t.trimmingCharacters(in: .whitespaces)
    }

    // MARK: – sanitize_name

    /// Unicode blocks to strip from names. Corresponds to Python `STRIP_BLOCKS_RE`.
    private static let stripBlocksPattern: String = {
        // Emoji and symbol ranges that are not in the L/N/P categories
        let ranges = [
            "\u{1F600}-\u{1F64F}",  // Emoticons
            "\u{1F300}-\u{1F5FF}",  // Misc Symbols & Pictographs
            "\u{1F680}-\u{1F6FF}",  // Transport & Map
            "\u{1F700}-\u{1F77F}",  // Alchemical
            "\u{1F780}-\u{1F7FF}",  // Geometric Shapes Extended
            "\u{1F800}-\u{1F8FF}",  // Supplemental Arrows-C
            "\u{1F900}-\u{1F9FF}",  // Supplemental Symbols
            "\u{1FA00}-\u{1FA6F}",  // Chess
            "\u{1FA70}-\u{1FAFF}",  // Symbols Extended-A
            "\u{1F1E0}-\u{1F1FF}",  // Flags / regional indicators
            "\u{2600}-\u{26FF}",    // Misc Symbols
            "\u{2700}-\u{27BF}",    // Dingbats
            "\u{FE00}-\u{FE0F}",    // Variation Selectors
            "\u{1F3FB}-\u{1F3FF}",  // Emoji modifiers
        ]
        return "[" + ranges.joined() + "]+"
    }()

    /// Control characters and zero-width characters. Corresponds to Python `STRIP_CONTROL_RE`.
    private static let stripControlPattern =
        "[\u{00}-\u{08}\u{0B}\u{0C}\u{0E}-\u{1F}\u{7F}-\u{9F}" +
        "\u{200B}-\u{200F}\u{202A}-\u{202E}\u{2060}-\u{206F}\u{FEFF}\u{FFF0}-\u{FFF8}]+"

    /// Surrogates and private-use areas. Corresponds to Python `STRIP_PRIVATE_RE`.
    private static let stripPrivatePattern =
        "[\u{E000}-\u{F8FF}\u{FE10}-\u{FE2F}]+"

    /// Sanitize a display name by applying NFKC normalization, stripping symbols,
    /// emoji, control characters, and Zalgo-style combining marks, then collapsing
    /// whitespace.
    ///
    /// - Returns: `nil` if `name` is `nil`, otherwise the sanitized name (may be empty).
    ///
    /// Corresponds to Python `sanitize_name(name)`.
    public static func sanitizeName(_ name: String?) -> String? {
        guard let n = name else { return nil }

        // NFKC normalization (compatibility decomposition + canonical composition)
        // Same as Python's unicodedata.normalize('NFKC', name)
        var result = n.precomposedStringWithCompatibilityMapping

        // Category-based filter
        var scalars: [Unicode.Scalar] = []
        for scalar in result.unicodeScalars {
            let cat = scalar.properties.generalCategory
            switch cat {
            // Letters (Lu, Ll, Lt, Lm, Lo) → keep
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter,
                 .modifierLetter, .otherLetter:
                scalars.append(scalar)
            // Numbers (Nd, Nl, No) → keep
            case .decimalNumber, .letterNumber, .otherNumber:
                scalars.append(scalar)
            // Punctuation (Pc, Pd, Ps, Pe, Pi, Pf, Po) → keep
            case .connectorPunctuation, .dashPunctuation, .openPunctuation,
                 .closePunctuation, .initialPunctuation, .finalPunctuation,
                 .otherPunctuation:
                scalars.append(scalar)
            // Space separator → normalize to plain space
            case .spaceSeparator:
                scalars.append(Unicode.Scalar(0x20)!)
            // Line / paragraph separators → plain space
            case .lineSeparator, .paragraphSeparator:
                scalars.append(Unicode.Scalar(0x20)!)
            // Spacing combining mark (Mc, e.g. Indic vowel signs) → keep
            case .spacingMark:
                scalars.append(scalar)
            // Everything else: marks, symbols, format chars, controls → strip
            default:
                break
            }
        }
        result = String(String.UnicodeScalarView(scalars))

        // Block-based stripping for anything categories missed
        let opts = String.CompareOptions.regularExpression
        result = result.replacingOccurrences(of: NomadNetUtil.stripBlocksPattern,   with: "", options: opts)
        result = result.replacingOccurrences(of: NomadNetUtil.stripControlPattern,  with: "", options: opts)
        result = result.replacingOccurrences(of: NomadNetUtil.stripPrivatePattern,  with: "", options: opts)

        // Collapse multiple whitespace characters, strip leading/trailing
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: opts)
        result = result.trimmingCharacters(in: .whitespaces)

        return result
    }

    // MARK: – strip_micron

    /// Remove all Micron formatting markup from `text` (backtick-prefix tags).
    ///
    /// Strips colour/background codes, style tags (`!`, `*`, `_`, `=`),
    /// fg/bg reset tags, and navigation tags.
    ///
    /// Corresponds to Python `strip_micron(text)`.
    public static func stripMicron(_ text: String) -> String {
        let opts = String.CompareOptions.regularExpression
        var t = text
        t = t.replacingOccurrences(of: "`[FB][0-9a-fA-F]{3}",   with: "", options: opts)
        t = t.replacingOccurrences(of: "`[FB]T[0-9a-fA-F]{6}", with: "", options: opts)
        t = t.replacingOccurrences(of: "`[!*_=]",               with: "", options: opts)
        t = t.replacingOccurrences(of: "`f`b",                  with: "", options: opts)
        t = t.replacingOccurrences(of: "`f",                    with: "", options: opts)
        t = t.replacingOccurrences(of: "`b",                    with: "", options: opts)
        t = t.replacingOccurrences(of: "`<",                    with: "", options: opts)
        t = t.replacingOccurrences(of: "`>",                    with: "", options: opts)
        t = t.replacingOccurrences(of: "`\\{",                  with: "", options: opts)
        return t
    }

    // MARK: – strip_escaped_micron

    /// Remove all escaped Micron markup from `text` (pilcrow ¦ prefix tags).
    ///
    /// Corresponds to Python `strip_escaped_micron(text)`.
    public static func stripEscapedMicron(_ text: String) -> String {
        let opts = String.CompareOptions.regularExpression
        var t = text
        t = t.replacingOccurrences(of: "¦[FB][0-9a-fA-F]{3}",   with: "", options: opts)
        t = t.replacingOccurrences(of: "¦[FB]T[0-9a-fA-F]{6}", with: "", options: opts)
        t = t.replacingOccurrences(of: "¦[!*_=]",               with: "", options: opts)
        t = t.replacingOccurrences(of: "¦f`b",                  with: "", options: opts)
        t = t.replacingOccurrences(of: "¦f",                    with: "", options: opts)
        t = t.replacingOccurrences(of: "¦b",                    with: "", options: opts)
        t = t.replacingOccurrences(of: "¦<",                    with: "", options: opts)
        t = t.replacingOccurrences(of: "¦>",                    with: "", options: opts)
        t = t.replacingOccurrences(of: "¦\\{",                  with: "", options: opts)
        return t
    }

    // MARK: – unescape_micron

    /// Convert escaped (¦-prefixed) Micron tags back to active (`-prefixed) tags.
    ///
    /// Corresponds to Python `unescape_micron(text)`.
    public static func unescapeMicron(_ text: String) -> String {
        let opts = String.CompareOptions.regularExpression
        var t = text
        t = t.replacingOccurrences(of: "¦([FB][0-9a-fA-F]{3})",   with: "`$1", options: opts)
        t = t.replacingOccurrences(of: "¦([FB]T[0-9a-fA-F]{6})", with: "`$1", options: opts)
        t = t.replacingOccurrences(of: "¦([!*_=])",               with: "`$1", options: opts)
        t = t.replacingOccurrences(of: "¦(f`b)",                  with: "`$1", options: opts)
        t = t.replacingOccurrences(of: "¦(f)",                    with: "`$1", options: opts)
        t = t.replacingOccurrences(of: "¦(b)",                    with: "`$1", options: opts)
        t = t.replacingOccurrences(of: "¦(<)",                    with: "`$1", options: opts)
        t = t.replacingOccurrences(of: "¦(>)",                    with: "`$1", options: opts)
        t = t.replacingOccurrences(of: "¦(\\{)",                  with: "`$1", options: opts)
        return t
    }

    // MARK: – strip_non_formatting_tags

    /// Remove Micron navigation/layout tags (`<`, `>`, `` `{ ``, `` `r ``,
    /// `` `c ``, `` `l ``) while preserving colour/style formatting tags.
    ///
    /// Corresponds to Python `strip_non_formatting_tags(text)`.
    public static func stripNonFormattingTags(_ text: String) -> String {
        let opts = String.CompareOptions.regularExpression
        var t = text
        t = t.replacingOccurrences(of: "`<",    with: "", options: opts)
        t = t.replacingOccurrences(of: "`>",    with: "", options: opts)
        t = t.replacingOccurrences(of: "`\\{",  with: "", options: opts)
        t = t.replacingOccurrences(of: "`r",    with: "", options: opts)
        t = t.replacingOccurrences(of: "`c",    with: "", options: opts)
        t = t.replacingOccurrences(of: "`l",    with: "", options: opts)
        return t
    }
}
