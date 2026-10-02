//===----------------------------------------------------------------------===//
// Copyright (c) 2026 NomadNetSwift contributors.
//
// Licensed under the GNU General Public License, version 3 (GPL-3.0). See
// LICENSE in the repository root for the full license text, and NOTICE for
// attribution of the upstream project this file is derived from.
//
// SPDX-License-Identifier: GPL-3.0-only
//===----------------------------------------------------------------------===//

import Foundation

// MARK: - NomadNetUtil

/// Text processing utilities for NomadNet display, rendering, and name sanitization.
///
/// Corresponds to `nomadnet/util.py`.
public enum NomadNetUtil {

  // MARK:–strip_modifiers

  /// Characters that are known to render incorrectly in many fonts and should be
  /// replaced with a space.
  ///
  /// Matches Python `invalid_rendering`.
  private static let invalidRendering: [Character] = ["🕵️", "☝"]

  /// Strip Unicode modifiers, emoji skin tones, variation selectors, and control
  /// characters.
  ///
  /// Normalizes CRLF and CR to LF, removes the characters `STRIP_CONTROL_RE` matches, and
  /// trims whitespace as `str.strip()` does (`util.py:92-126`).
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

    // Additional regular expression passes matching Python's post-processing
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

    return trimPythonWhitespace(stripControl(t))
  }

  /// Removes the control, zero-width, and bidi characters that Python's `STRIP_CONTROL_RE`
  /// matches (`util.py:62-73`).
  static func stripControl(_ text: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in text.unicodeScalars where !isStrippedControl(scalar.value) {
      scalars.append(scalar)
    }
    return String(scalars)
  }

  /// Whether `STRIP_CONTROL_RE` matches the code point `value`.
  static func isStrippedControl(_ value: UInt32) -> Bool {
    switch value {
    case 0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F, 0x7F...0x9F, 0x200B...0x200F, 0x202A...0x202E,
      0x2060...0x206F, 0xFEFF, 0xFFF0...0xFFF8:
      return true
    default:
      return false
    }
  }

  /// Removes leading and trailing whitespace as Python's `str.strip()` does, where
  /// whitespace is every code point that `str.isspace()` accepts.
  static func trimPythonWhitespace(_ text: String) -> String {
    let scalars = text.unicodeScalars
    guard let first = scalars.firstIndex(where: { !isPythonWhitespace($0.value) }),
      let last = scalars.lastIndex(where: { !isPythonWhitespace($0.value) })
    else { return "" }
    return String(scalars[first...last])
  }

  /// Whether Python's `str.isspace()` accepts the code point `value`.
  static func isPythonWhitespace(_ value: UInt32) -> Bool {
    switch value {
    case 0x09...0x0D, 0x1C...0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F,
      0x205F, 0x3000:
      return true
    default:
      return false
    }
  }

  // MARK:–sanitize_name

  /// Unicode blocks to strip from names.
  ///
  /// Corresponds to Python `STRIP_BLOCKS_RE`.
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
      "\u{2600}-\u{26FF}",  // Misc Symbols
      "\u{2700}-\u{27BF}",  // Dingbats
      "\u{FE00}-\u{FE0F}",  // Variation Selectors
      "\u{1F3FB}-\u{1F3FF}",  // Emoji modifiers
    ]
    return "[" + ranges.joined() + "]+"
  }()

  /// Surrogates and private-use areas.
  ///
  /// Corresponds to Python `STRIP_PRIVATE_RE`.
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
        scalars.append(" ")
      // Line / paragraph separators → plain space
      case .lineSeparator, .paragraphSeparator:
        scalars.append(" ")
      // Spacing combining mark (Mc, for example, Indic vowel signs) → keep
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
    result = result.replacingOccurrences(
      of: NomadNetUtil.stripBlocksPattern, with: "", options: opts)
    result = stripControl(result)
    result = result.replacingOccurrences(
      of: NomadNetUtil.stripPrivatePattern, with: "", options: opts)

    // Collapse multiple whitespace characters, strip leading/trailing
    result = result.replacingOccurrences(of: "\\s+", with: " ", options: opts)
    result = result.trimmingCharacters(in: .whitespaces)

    return result
  }

  // MARK:–strip_micron

  /// Remove all Micron formatting markup from `text` (backtick-prefix tags).
  ///
  /// Strips color/background codes, style tags (`!`, `*`, `_`, `=`),
  /// fg/bg reset tags, and navigation tags.
  ///
  /// Corresponds to Python `strip_micron(text)`.
  public static func stripMicron(_ text: String) -> String {
    let opts = String.CompareOptions.regularExpression
    var t = text
    t = t.replacingOccurrences(of: "`[FB][0-9a-fA-F]{3}", with: "", options: opts)
    t = t.replacingOccurrences(of: "`[FB]T[0-9a-fA-F]{6}", with: "", options: opts)
    t = t.replacingOccurrences(of: "`[!*_=]", with: "", options: opts)
    t = t.replacingOccurrences(of: "`f`b", with: "", options: opts)
    t = t.replacingOccurrences(of: "`f", with: "", options: opts)
    t = t.replacingOccurrences(of: "`b", with: "", options: opts)
    t = t.replacingOccurrences(of: "`<", with: "", options: opts)
    t = t.replacingOccurrences(of: "`>", with: "", options: opts)
    t = t.replacingOccurrences(of: "`\\{", with: "", options: opts)
    return t
  }

  // MARK:–strip_escaped_micron

  /// Remove all escaped Micron markup from `text` (pilcrow ¦ prefix tags).
  ///
  /// Corresponds to Python `strip_escaped_micron(text)`.
  public static func stripEscapedMicron(_ text: String) -> String {
    let opts = String.CompareOptions.regularExpression
    var t = text
    t = t.replacingOccurrences(of: "¦[FB][0-9a-fA-F]{3}", with: "", options: opts)
    t = t.replacingOccurrences(of: "¦[FB]T[0-9a-fA-F]{6}", with: "", options: opts)
    t = t.replacingOccurrences(of: "¦[!*_=]", with: "", options: opts)
    t = t.replacingOccurrences(of: "¦f`b", with: "", options: opts)
    t = t.replacingOccurrences(of: "¦f", with: "", options: opts)
    t = t.replacingOccurrences(of: "¦b", with: "", options: opts)
    t = t.replacingOccurrences(of: "¦<", with: "", options: opts)
    t = t.replacingOccurrences(of: "¦>", with: "", options: opts)
    t = t.replacingOccurrences(of: "¦\\{", with: "", options: opts)
    return t
  }

  // MARK:–unescape_micron

  /// Converts escaped Micron tags back to active ones.
  ///
  /// Corresponds to Python `unescape_micron(text)`.
  public static func unescapeMicron(_ text: String) -> String {
    let opts = String.CompareOptions.regularExpression
    var t = text
    t = t.replacingOccurrences(of: "¦([FB][0-9a-fA-F]{3})", with: "`$1", options: opts)
    t = t.replacingOccurrences(of: "¦([FB]T[0-9a-fA-F]{6})", with: "`$1", options: opts)
    t = t.replacingOccurrences(of: "¦([!*_=])", with: "`$1", options: opts)
    t = t.replacingOccurrences(of: "¦(f`b)", with: "`$1", options: opts)
    t = t.replacingOccurrences(of: "¦(f)", with: "`$1", options: opts)
    t = t.replacingOccurrences(of: "¦(b)", with: "`$1", options: opts)
    t = t.replacingOccurrences(of: "¦(<)", with: "`$1", options: opts)
    t = t.replacingOccurrences(of: "¦(>)", with: "`$1", options: opts)
    t = t.replacingOccurrences(of: "¦(\\{)", with: "`$1", options: opts)
    return t
  }

  // MARK:–strip_non_formatting_tags

  /// Remove Micron navigation/layout tags (`<`, `>`, `` `{ ``, `` `r ``,
  /// `` `c ``, `` `l ``) while preserving color/style formatting tags.
  ///
  /// Corresponds to Python `strip_non_formatting_tags(text)`.
  public static func stripNonFormattingTags(_ text: String) -> String {
    let opts = String.CompareOptions.regularExpression
    var t = text
    t = t.replacingOccurrences(of: "`<", with: "", options: opts)
    t = t.replacingOccurrences(of: "`>", with: "", options: opts)
    t = t.replacingOccurrences(of: "`\\{", with: "", options: opts)
    t = t.replacingOccurrences(of: "`r", with: "", options: opts)
    t = t.replacingOccurrences(of: "`c", with: "", options: opts)
    t = t.replacingOccurrences(of: "`l", with: "", options: opts)
    return t
  }
}
