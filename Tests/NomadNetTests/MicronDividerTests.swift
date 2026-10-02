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

/// The fill character of a Micron divider, against NomadNet 1.4.4.
///
/// NomadNet 1.4.4 keeps a divider's fill character only when urwid renders it in one terminal
/// cell, and otherwise draws `─` (`MicronParser.py:603-613`). Each expected fill was read from
/// NomadNet 1.4.4's parser on urwid 4.0.8 and wcwidth 0.8.2.
@Suite("Micron divider fill character")
struct MicronDividerTests {

  /// Divider lines through `markup_to_attrmaps`, which `parsePage` mirrors.
  static let parsePageVectors: [(markup: String, fill: String)] = [
    ("-", "\u{2500}"),
    ("-=", "="),
    ("-\u{01}", "\u{2500}"),
    ("-\u{7F}", "\u{2500}"),
    ("-\u{85}", "\u{2500}"),
    ("-\u{A0}", "\u{A0}"),
    ("-\u{AD}", "\u{AD}"),
    ("-\u{E9}", "\u{E9}"),
    ("-e\u{301}", "\u{2500}"),
    ("-\u{301}", "\u{2500}"),
    ("-\u{200B}", "\u{2500}"),
    ("-\u{200B}=", "="),
    ("-\u{2028}", "\u{2500}"),
    ("-\u{6F22}", "\u{2500}"),
    ("-\u{1F600}", "\u{2500}"),
    ("-\u{1100}", "\u{2500}"),
    ("-\u{1160}", "\u{2500}"),
    ("-\u{2550}", "\u{2550}"),
    ("-\u{2022}", "\u{2022}"),
    ("-\u{2605}", "\u{2605}"),
    ("-ab", "\u{2500}"),
    ("-\u{FF01}", "\u{2500}"),
    ("-\u{3000}", "\u{2500}"),
    ("-\u{20000}", "\u{2500}"),
    ("-\u{E0001}", "\u{2500}"),
    ("-\u{FE0F}", "\u{2500}"),
    ("-\u{1F1FA}\u{1F1F8}", "\u{2500}"),
    ("-\u{202E}=", "="),
    ("-=\u{FEFF}", "="),
  ]

  /// Divider pages through the browser, which strips modifiers first (`Browser.py:1846`).
  static let browserVectors: [(markup: String, fill: String)] = [
    ("-=", "="),
    ("-\u{A0}", "\u{2500}"),
    ("-\u{AD}", "\u{2500}"),
    ("-\u{E9}", "\u{E9}"),
    ("-e\u{301}", "e"),
    ("-\u{6F22}", "\u{2500}"),
  ]

  @Test(
    "A divider keeps a fill that renders in one cell, and draws ─ otherwise",
    arguments: parsePageVectors)
  func parsePageFill(markup: String, fill: String) throws {
    let nodes = MicronParser.parsePage(markup).nodes
    try #require(nodes.count == 1)
    guard case .horizontalRule(let character) = nodes[0] else {
      Issue.record("Expected a divider for \(markup.debugDescription), got \(nodes[0])")
      return
    }
    #expect(Self.scalars(String(character)) == Self.scalars(fill))
  }

  @Test(
    "A page from a node draws the divider its stripped markup describes",
    arguments: browserVectors)
  func browserFill(markup: String, fill: String) throws {
    let page = try Self.loadedPage(markup)
    try #require(page.nodes.count == 1)
    guard case .horizontalRule(let character) = page.nodes[0] else {
      Issue.record("Expected a divider for \(markup.debugDescription), got \(page.nodes[0])")
      return
    }
    #expect(Self.scalars(String(character)) == Self.scalars(fill))
  }

  @Test("A code point is one cell wide exactly when wcwidth reports 1")
  func cellWidthMatchesWcwidth() {
    let single: [UInt32] = [0x20, 0x41, 0xA0, 0xAD, 0xE9, 0x2022, 0x2500, 0x2605]
    let other: [UInt32] = [
      0x01, 0x1F, 0x7F, 0x85, 0x9F, 0x301, 0x1100, 0x1160, 0x200B, 0x2028, 0x3000, 0x6F22,
      0xFE0F, 0xFF01, 0x1F1FA, 0x1F600, 0x20000, 0xE0001,
    ]
    for value in single {
      #expect(MicronCellWidth.isSingleCell(Unicode.Scalar(value)!), "U+\(String(value, radix: 16))")
    }
    for value in other {
      #expect(
        !MicronCellWidth.isSingleCell(Unicode.Scalar(value)!), "U+\(String(value, radix: 16))")
    }
  }

  static func scalars(_ text: String) -> [UInt32] {
    text.unicodeScalars.map(\.value)
  }

  /// Loads `markup` through `NomadNetBrowser.handleResponse`, as a page a node sent.
  static func loadedPage(_ markup: String) throws -> MicronPage {
    let browser = NomadNetBrowser()
    let url = try #require(NomadNetURL.parse("abc123def456789012abcdef01234567"))
    browser.handleResponse(Data(markup.utf8), url: url)
    return try #require(browser.currentPage)
  }
}
