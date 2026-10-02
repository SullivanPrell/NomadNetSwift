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
import Testing

@testable import NomadNet

/// The characters a page loses before it renders, against NomadNet 1.4.4.
///
/// The browser renders `markup_to_attrmaps(strip_modifiers(markup))` (`Browser.py:1846`), and
/// `markup_to_attrmaps` strips `STRIP_CONTROL_RE` from what it receives (`MicronParser.py:107`).
/// Each expected value was read from NomadNet 1.4.4.
@Suite("Page sanitizing")
struct PageSanitizingTests {

  /// A rendered row: a text line's characters, an empty row, or a divider's fill.
  ///
  /// Rows compare by code point, so a composed accent doesn't equal a decomposed one.
  enum Row: Equatable {
    case text(String)
    case divider(String)

    static func == (lhs: Row, rhs: Row) -> Bool {
      switch (lhs, rhs) {
      case (.text(let left), .text(let right)), (.divider(let left), .divider(let right)):
        return Array(left.unicodeScalars) == Array(right.unicodeScalars)
      default:
        return false
      }
    }
  }

  @Test(
    "strip_modifiers removes controls, marks, and modifiers, then trims Python whitespace",
    arguments: [
      ("a\u{01}b", "ab"),
      ("a\u{7F}b\u{85}c", "abc"),
      ("a\u{200B}b", "ab"),
      ("x\u{202E}y", "xy"),
      ("\u{FEFF}page", "page"),
      ("a\u{FFF0}b", "ab"),
      ("e\u{301}", "e"),
      ("line\n", "line"),
      ("\n\nline\n\n", "line"),
      (" \u{A0}line\u{3000} ", "line"),
      ("a\r\nb\rc", "a\nb\nc"),
      ("\tline\t", "line"),
      ("-\u{AD}", "-"),
      ("\u{2028}a\u{2029}", "a"),
      ("a\u{00}b", "ab"),
      ("\u{1C}line\u{1F}", "line"),
      ("one\n\ntwo\n", "one\n\ntwo"),
      ("\u{1F44D}\u{1F3FD}", "\u{1F44D}"),
      ("\u{2764}\u{FE0F}", "\u{2764}"),
    ])
  func stripModifiersMatchesTheReference(input: String, expected: String) throws {
    let stripped = try #require(NomadNetUtil.stripModifiers(input))
    #expect(Array(stripped.unicodeScalars) == Array(expected.unicodeScalars))
  }

  @Test(
    "parsePage strips control and zero-width characters, and keeps marks",
    arguments: [
      ("a\u{200B}b", [Row.text("ab")]),
      ("x\u{202E}y", [Row.text("xy")]),
      ("e\u{301}x", [Row.text("e\u{301}x")]),
      ("\u{FEFF}Hello", [Row.text("Hello")]),
      ("one\n\ntwo\n", [Row.text("one"), Row.text(""), Row.text("two"), Row.text("")]),
    ])
  func parsePageStripsControls(markup: String, expected: [Row]) {
    #expect(Self.rows(MicronParser.parsePage(markup)) == expected)
  }

  @Test(
    "A page from a node renders its stripped markup",
    arguments: [
      ("e\u{301}x", [Row.text("ex")]),
      ("one\n\ntwo\n", [Row.text("one"), Row.text(""), Row.text("two")]),
      ("text\n-e\u{301}\n", [Row.text("text"), Row.divider("e")]),
    ])
  func browserRendersStrippedMarkup(markup: String, expected: [Row]) throws {
    #expect(Self.rows(try MicronDividerTests.loadedPage(markup)) == expected)
  }

  @Test("A page color on the last line still applies after the page is trimmed")
  func pageColorsComeFromTheRawMarkup() throws {
    let page = try MicronDividerTests.loadedPage("Hello\n#!fg=ddd\n")
    #expect(page.foregroundColor == .rgb3(r: 13, g: 13, b: 13))
  }

  static func rows(_ page: MicronPage) -> [Row] {
    page.nodes.compactMap { node in
      switch node {
      case .emptyLine:
        return .text("")
      case .line(let spans, _, _):
        return .text(
          spans.map { span in
            if case .text(let text, _) = span { return text }
            return ""
          }.joined())
      case .horizontalRule(let character):
        return .divider(String(character))
      default:
        return nil
      }
    }
  }
}
