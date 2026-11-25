//===----------------------------------------------------------------------===//
// Copyright (c) 2026 NomadNetSwift contributors.
//
// Licensed under the GNU General Public License, version 3 (GPL-3.0). See
// LICENSE in the repository root for the full license text, and NOTICE for
// attribution of the upstream project this file is derived from.
//
// SPDX-License-Identifier: GPL-3.0-only
//===----------------------------------------------------------------------===//

import XCTest

@testable import NomadNet

/// Micron features from NomadNet 1.3.0 and 1.4.0 (`MicronParser.py`).
final class MicronFeatureParityTests: XCTestCase {

  private func spans(_ markup: String) -> [MicronSpan] {
    guard case .line(let s, _, _) = MicronParser.parsePage(markup).nodes.first else { return [] }
    return s
  }

  private func field(_ markup: String) -> MicronField? {
    for case .field(let f) in spans(markup) { return f }
    return nil
  }

  // MARK: Collapsible headings (`MicronParser.py:488-494`, `:590-594`)

  func testCollapsedHeadingIsAHeadingMarkedCollapsed() {
    let page = MicronParser.parsePage("`->Intro\nbody")
    guard case .heading(let level, let s, _, _) = page.nodes.first else {
      return XCTFail("\(page.nodes)")
    }
    XCTAssertEqual(level, 1)
    XCTAssertEqual(s, [.text("Intro", style: .default)])
    XCTAssertEqual(page.collapsibles, [0: true])
  }

  func testOpenHeadingIsMarkedOpenAtItsRow() {
    let page = MicronParser.parsePage("text\n`+>>Deep")
    XCTAssertEqual(page.collapsibles, [1: false])
  }

  func testPlainHeadingIsNotCollapsible() {
    XCTAssertEqual(MicronParser.parsePage(">Plain").collapsibles, [:])
  }

  // MARK: `#!fold` (`MicronParser.py:508-513`, default `:42`)

  func testFoldGlyphsDefault() {
    let page = MicronParser.parsePage("`+>A")
    XCTAssertEqual(page.foldOpenGlyph, "▾")
    XCTAssertEqual(page.foldClosedGlyph, "▸")
  }

  func testFoldDirectiveSetsBothGlyphs() {
    let page = MicronParser.parsePage("#!fold - +\n`+>A")
    XCTAssertEqual(page.foldOpenGlyph, "-")
    XCTAssertEqual(page.foldClosedGlyph, "+")
    XCTAssertEqual(page.nodes.count, 1)
  }

  func testFoldDirectiveWithOneGlyphUsesItTwice() {
    let page = MicronParser.parsePage("#!fold *")
    XCTAssertEqual(page.foldOpenGlyph, "*")
    XCTAssertEqual(page.foldClosedGlyph, "*")
  }

  // MARK: Inline images (`MicronParser.py:221-283`)

  func testImageWithProperties() {
    let nodes = MicronParser.parsePage("`( A cat `w=40`h=10`a=c` /file/cat.png )").nodes
    XCTAssertEqual(
      nodes,
      [
        .image(
          MicronImage(
            altText: "A cat", url: "/file/cat.png", width: "40", height: "10",
            alignment: .center),
          depth: 0)
      ])
  }

  func testImageWithoutABacktickIsDropped() {
    XCTAssertEqual(MicronParser.parsePage("`(just text)").nodes, [])
    XCTAssertEqual(MicronParser.parsePage("`(no close").nodes, [])
  }

  func testImageKeepsSectionDepth() {
    let nodes = MicronParser.parsePage(">>Sec\n`(alt`/i.png)").nodes
    XCTAssertEqual(nodes.last, .image(MicronImage(altText: "alt", url: "/i.png"), depth: 2))
  }

  // MARK: Multi-row fields (`MicronParser.py:984-994`)

  func testFieldWidthByRows() {
    let f = field("`<30x5|msg`hi>")
    XCTAssertEqual(f?.width, 30)
    XCTAssertEqual(f?.rows, 5)
    XCTAssertEqual(f?.value, "hi")
  }

  func testFieldRowsClampAndBadWidthKeepsDefault() {
    let f = field("`<x999|msg`>")
    XCTAssertEqual(f?.width, 24)
    XCTAssertEqual(f?.rows, 256)
    XCTAssertEqual(field("`<12|msg`>")?.rows, 1)
  }

  // MARK: Links (`MicronParser.py:1056-1074`)

  func testLinkWithFourPartsIsConsumedWithoutALink() {
    XCTAssertEqual(spans("`[a`b`c`d]tail"), [.text("tail", style: .default)])
  }

  func testLinkWithEmptyURLIsConsumed() {
    XCTAssertEqual(spans("`[label`]tail"), [.text("tail", style: .default)])
  }
}
