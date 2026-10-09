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

/// Micron markup read by code point, against NomadNet 1.4.4.
///
/// Python indexes a `str` by code point, so `MicronParser.py` reads a combining mark, either
/// half of a regional-indicator pair, or a Hangul jamo as a character of its own, and splits a
/// page on `"\n"` alone. `scripts/micron-reference-vectors.py` printed every expected value
/// from NomadNet 1.4.4 on Python 3.14.5 and urwid 4.0.8. Values compare by code point, because
/// `String ==` applies canonical equivalence.
@Suite("Micron code points")
struct MicronCodePointTests {

  /// Markup and the rows NomadNet 1.4.4 builds from it.
  struct Vector: CustomTestStringConvertible {
    let markup: String
    let nodes: [MicronNode]
    let anchors: [String: Int]

    init(_ markup: String, _ nodes: [MicronNode], anchors: [String: Int]) {
      self.markup = markup
      self.nodes = nodes
      self.anchors = anchors
    }

    var testDescription: String { markup.debugDescription }
  }

  /// Markup and the page colors NomadNet 1.4.4's browser reads from it.
  struct PageColorVector: CustomTestStringConvertible {
    let markup: String
    let foreground: MicronColor?
    let background: MicronColor?

    init(_ markup: String, foreground: MicronColor?, background: MicronColor?) {
      self.markup = markup
      self.foreground = foreground
      self.background = background
    }

    var testDescription: String { markup.debugDescription }
  }

  /// A value's description, equal to another only when their code points match.
  struct Exact: Equatable, CustomStringConvertible {
    let description: String

    init(_ value: Any) {
      description = String(reflecting: value)
    }

    static func == (lhs: Exact, rhs: Exact) -> Bool {
      lhs.description.unicodeScalars.elementsEqual(rhs.description.unicodeScalars)
    }
  }

  /// Pages through `markup_to_attrmaps`, which `parsePage` mirrors.
  static let parsePageVectors: [Vector] = [
    Vector(
      "a\r\nb",
      [
        .line([.text("a\r", style: .init())], depth: 0, alignment: .left),
        .line([.text("b", style: .init())], depth: 0, alignment: .left),
      ],
      anchors: [:]),
    Vector(
      "\r\n",
      [
        .line([.text("\r", style: .init())], depth: 0, alignment: .left),
        .emptyLine,
      ],
      anchors: [:]),
    Vector(
      "a\r\n\r\nb",
      [
        .line([.text("a\r", style: .init())], depth: 0, alignment: .left),
        .line([.text("\r", style: .init())], depth: 0, alignment: .left),
        .line([.text("b", style: .init())], depth: 0, alignment: .left),
      ],
      anchors: [:]),
    Vector(
      "-\r\n",
      [
        .horizontalRule(character: "\u{2500}"),
        .emptyLine,
      ],
      anchors: [:]),
    Vector(
      ">T\r\nx",
      [
        .heading(level: 1, spans: [.text("T\r", style: .init())], depth: 1, slug: "t"),
        .line([.text("x", style: .init())], depth: 1, alignment: .left),
      ],
      anchors: ["t": 0]),
    Vector(
      "#c\r\nx",
      [
        .line([.text("x", style: .init())], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`=\r\nx",
      [
        .line([.text("\r", style: .init())], depth: 0, alignment: .left),
        .line([.text("x", style: .init())], depth: 0, alignment: .left),
      ],
      anchors: [:]),
    Vector(
      ">\u{301}Title",
      [
        .heading(level: 1, spans: [.text("\u{301}Title", style: .init())], depth: 1, slug: "title")
      ],
      anchors: ["title": 0]),
    Vector(
      ">>\u{301}x",
      [
        .heading(level: 2, spans: [.text("\u{301}x", style: .init())], depth: 2, slug: "x")
      ],
      anchors: ["x": 0]),
    Vector(
      "#\u{301}\nx",
      [
        .line([.text("x", style: .init())], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "\\\u{301}`!x",
      [
        .line(
          [.text("\u{301}", style: .init()), .text("x", style: .init(bold: true))], depth: 0,
          alignment: .left)
      ],
      anchors: [:]),
    Vector(
      ">H\n<\u{301}x",
      [
        .heading(level: 1, spans: [.text("H", style: .init())], depth: 1, slug: "h"),
        .line([.text("\u{301}x", style: .init())], depth: 0, alignment: .left),
      ],
      anchors: ["h": 0]),
    Vector(
      "`t\u{301}\n|a|b|\n|-|-|\n`t",
      [
        .table(rows: [["|a|b|"], ["|-|-|"]], alignment: nil, maxWidth: nil)
      ],
      anchors: [:]),
    Vector(
      "`tc\u{301}\n|a|\n|1|\n`t",
      [
        .table(rows: [["|a|"], ["|1|"]], alignment: .center, maxWidth: nil)
      ],
      anchors: [:]),
    Vector(
      "`{\u{301}p`5`a|b}",
      [
        .partial(MicronPartial(url: "\u{301}p", refreshInterval: 5.0, fields: ["a", "b"]))
      ],
      anchors: [:]),
    Vector(
      "`{p`5`a}\u{301}",
      [
        .partial(MicronPartial(url: "p", refreshInterval: 5.0, fields: ["a"]))
      ],
      anchors: [:]),
    Vector(
      "`{p`5`\u{301}a}",
      [
        .partial(MicronPartial(url: "p", refreshInterval: 5.0, fields: ["\u{301}a"]))
      ],
      anchors: [:]),
    Vector(
      "`{p`5`a|\u{301}b}",
      [
        .partial(MicronPartial(url: "p", refreshInterval: 5.0, fields: ["a", "\u{301}b"]))
      ],
      anchors: [:]),
    Vector(
      ">`<\u{301}f`v>",
      [
        .line(
          [
            .field(
              MicronField(
                fieldType: .text, name: "\u{301}f", value: "v", label: "", width: 24,
                prechecked: false, style: .init()))
          ], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      ">\u{301}`<f`v>",
      [
        .line(
          [
            .text("\u{301}", style: .init()),
            .field(
              MicronField(
                fieldType: .text, name: "f", value: "v", label: "", width: 24, prechecked: false,
                style: .init())),
          ], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`!\u{301}x",
      [
        .line([.text("\u{301}x", style: .init(bold: true))], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`*\u{301}x",
      [
        .line([.text("\u{301}x", style: .init(italic: true))], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`_\u{301}x",
      [
        .line([.text("\u{301}x", style: .init(underline: true))], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`c\u{301}x",
      [
        .line([.text("\u{301}x", style: .init())], depth: 0, alignment: .center)
      ],
      anchors: [:]),
    Vector(
      "`l\u{301}x",
      [
        .line([.text("\u{301}x", style: .init())], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`r\u{301}x",
      [
        .line([.text("\u{301}x", style: .init())], depth: 0, alignment: .right)
      ],
      anchors: [:]),
    Vector(
      "`a\u{301}x",
      [
        .line([.text("\u{301}x", style: .init())], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`f\u{301}x",
      [
        .line([.text("\u{301}x", style: .init())], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`b\u{301}x",
      [
        .line([.text("\u{301}x", style: .init())], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`!a``\u{301}x",
      [
        .line(
          [.text("a", style: .init(bold: true)), .text("\u{301}x", style: .init())], depth: 0,
          alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`\u{301}x",
      [
        .line([.text("x", style: .init())], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "a\\\u{301}`!b",
      [
        .line(
          [.text("a\u{301}", style: .init()), .text("b", style: .init(bold: true))], depth: 0,
          alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`Ff00\u{301}x",
      [
        .line(
          [.text("\u{301}x", style: .init(fgColor: .rgb3(r: 15, g: 0, b: 0)))], depth: 0,
          alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`F\u{301}00x",
      [
        .line([.text("x", style: .init())], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`FTf00000\u{301}x",
      [
        .line(
          [.text("\u{301}x", style: .init(fgColor: .rgb6(r: 240, g: 0, b: 0)))], depth: 0,
          alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`Bf00\u{301}x",
      [
        .line(
          [.text("\u{301}x", style: .init(bgColor: .rgb3(r: 15, g: 0, b: 0)))], depth: 0,
          alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`:ab\u{5B0}c x",
      [
        .line([.text("\u{5B0}c x", style: .init())], depth: 0, alignment: .left)
      ],
      anchors: ["ab": 0]),
    Vector(
      "`:a\u{24B6}b x",
      [
        .line([.text("\u{24B6}b x", style: .init())], depth: 0, alignment: .left)
      ],
      anchors: ["a": 0]),
    Vector(
      "`:\u{301}a x",
      [
        .line([.text("\u{301}a x", style: .init())], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`:a\u{216B}b x",
      [
        .line([.text(" x", style: .init())], depth: 0, alignment: .left)
      ],
      anchors: ["a\u{216B}b": 0]),
    Vector(
      "`[\u{301}l`u]",
      [
        .line(
          [.link(MicronLink(label: "\u{301}l", url: "u", fields: [], style: .init()))], depth: 0,
          alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`[l`\u{301}u]",
      [
        .line(
          [.link(MicronLink(label: "l", url: "\u{301}u", fields: [], style: .init()))], depth: 0,
          alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`[l`u]\u{301}x",
      [
        .line(
          [
            .link(MicronLink(label: "l", url: "u", fields: [], style: .init())),
            .text("\u{301}x", style: .init()),
          ], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`[l`u`a|\u{301}b]",
      [
        .line(
          [.link(MicronLink(label: "l", url: "u", fields: ["a", "\u{301}b"], style: .init()))],
          depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`<\u{301}n`v>",
      [
        .line(
          [
            .field(
              MicronField(
                fieldType: .text, name: "\u{301}n", value: "v", label: "", width: 24,
                prechecked: false, style: .init()))
          ], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`<n`\u{301}v>",
      [
        .line(
          [
            .field(
              MicronField(
                fieldType: .text, name: "n", value: "\u{301}v", label: "", width: 24,
                prechecked: false, style: .init()))
          ], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`<n`v>\u{301}x",
      [
        .line(
          [
            .field(
              MicronField(
                fieldType: .text, name: "n", value: "v", label: "", width: 24, prechecked: false,
                style: .init())), .text("\u{301}x", style: .init()),
          ], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`<?|\u{301}n|1`l>",
      [
        .line(
          [
            .field(
              MicronField(
                fieldType: .checkbox, name: "\u{301}n", value: "1", label: "l", width: 24,
                prechecked: false, style: .init()))
          ], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`<!\u{301}|n`v>",
      [
        .line(
          [
            .field(
              MicronField(
                fieldType: .masked, name: "n", value: "v", label: "", width: 24, prechecked: false,
                style: .init()))
          ], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`<?\u{301}|n|1`l>",
      [
        .line(
          [
            .field(
              MicronField(
                fieldType: .checkbox, name: "n", value: "1", label: "l", width: 24,
                prechecked: false, style: .init()))
          ], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`<^\u{301}|n|1`l>",
      [
        .line(
          [
            .field(
              MicronField(
                fieldType: .radio, name: "n", value: "1", label: "l", width: 24, prechecked: false,
                style: .init()))
          ], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`F\u{1F1FA}\u{1F1F8}0x",
      [
        .line([.text("x", style: .init())], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`B\u{1100}\u{1161}0x",
      [
        .line([.text("x", style: .init())], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`FT\u{1F1FA}\u{1F1F8}0000x",
      [
        .line([.text("x", style: .init())], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "\u{D4E}`!x",
      [
        .line(
          [.text("\u{D4E}", style: .init()), .text("x", style: .init(bold: true))], depth: 0,
          alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`!\u{FF9E}x",
      [
        .line([.text("\u{FF9E}x", style: .init(bold: true))], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      ">\u{FF9E}T",
      [
        .heading(level: 1, spans: [.text("\u{FF9E}T", style: .init())], depth: 1, slug: "t")
      ],
      anchors: ["t": 0]),
  ]
  /// Pages through the browser, which strips modifiers first (`Browser.py:1846`).
  static let browserVectors: [Vector] = [
    Vector(
      "a\r\nb",
      [
        .line([.text("a", style: .init())], depth: 0, alignment: .left),
        .line([.text("b", style: .init())], depth: 0, alignment: .left),
      ],
      anchors: [:]),
    Vector(
      "`F\u{1F1FA}\u{1F1F8}0x",
      [
        .line([.text("x", style: .init())], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`B\u{1100}\u{1161}0x",
      [
        .line([.text("x", style: .init())], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "\u{D4E}`!x",
      [
        .line(
          [.text("\u{D4E}", style: .init()), .text("x", style: .init(bold: true))], depth: 0,
          alignment: .left)
      ],
      anchors: [:]),
    Vector(
      "`!\u{FF9E}x",
      [
        .line([.text("\u{FF9E}x", style: .init(bold: true))], depth: 0, alignment: .left)
      ],
      anchors: [:]),
    Vector(
      ">\u{FF9E}T",
      [
        .heading(level: 1, spans: [.text("\u{FF9E}T", style: .init())], depth: 1, slug: "t")
      ],
      anchors: ["t": 0]),
  ]
  /// Page color directives, read as `Browser.py:1824-1844` reads them.
  static let pageColorVectors: [PageColorVector] = [
    PageColorVector("\u{D4E}#!fg=f00\n", foreground: .rgb3(r: 15, g: 0, b: 0), background: nil),
    PageColorVector("#!fg=\u{301}ab\n#!fg=0f0\n", foreground: nil, background: nil),
    PageColorVector("#!bg=\u{301}ab\n#!bg=00f\n", foreground: nil, background: nil),
    PageColorVector("#!fg=f00\r\n", foreground: nil, background: nil),
    PageColorVector("#!fg=ab\r\n", foreground: nil, background: nil),
  ]

  @Test("A page parses as NomadNet 1.4.4 parses it, by code point", arguments: parsePageVectors)
  func parsePage(vector: Vector) {
    let page = MicronParser.parsePage(vector.markup)
    #expect(Exact(Self.observable(page)) == Exact(Self.expected(vector)))
  }

  @Test(
    "A page from a node parses as NomadNet 1.4.4's browser parses it, by code point",
    arguments: browserVectors)
  func browserPage(vector: Vector) throws {
    let page = try MicronDividerTests.loadedPage(vector.markup)
    #expect(Exact(Self.observable(page)) == Exact(Self.expected(vector)))
  }

  @Test(
    "The page colors come from the first directive found by code point",
    arguments: pageColorVectors)
  func pageColors(vector: PageColorVector) {
    let page = MicronParser.parsePage(vector.markup)
    #expect(Exact(page.foregroundColor as Any) == Exact(vector.foreground as Any))
    #expect(Exact(page.backgroundColor as Any) == Exact(vector.background as Any))
  }

  /// The rows and anchors of `vector`, in the form `observable(_:)` returns.
  static func expected(_ vector: Vector) -> [String] {
    [String(reflecting: vector.nodes)] + sortedAnchors(vector.anchors)
  }

  /// What NomadNet's widgets carry of `page`.
  ///
  /// The rows omit the `.anchor` markers, and anchors index rows. A Python style has no
  /// alignment (`MicronParser.py:705-706`), and urwid joins adjacent runs of one style.
  static func observable(_ page: MicronPage) -> [String] {
    var rows: [MicronNode] = []
    var rowOfNode: [Int: Int] = [:]
    for (index, node) in page.nodes.enumerated() {
      if case .anchor = node { continue }
      rowOfNode[index] = rows.count
      rows.append(joinedRuns(node))
    }
    var anchors: [String: Int] = [:]
    for (name, index) in page.anchors {
      anchors[name] = rowOfNode[index] ?? -1
    }
    return [String(reflecting: rows)] + sortedAnchors(anchors)
  }

  static func sortedAnchors(_ anchors: [String: Int]) -> [String] {
    anchors.map { String(reflecting: ($0.key, $0.value)) }.sorted {
      $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars)
    }
  }

  static func joinedRuns(_ node: MicronNode) -> MicronNode {
    switch node {
    case .line(let spans, let depth, let alignment):
      return .line(joinedRuns(spans), depth: depth, alignment: alignment)
    case .heading(let level, let spans, let depth, let slug):
      return .heading(level: level, spans: joinedRuns(spans), depth: depth, slug: slug)
    default:
      return node
    }
  }

  static func joinedRuns(_ spans: [MicronSpan]) -> [MicronSpan] {
    var joined: [MicronSpan] = []
    for span in spans.map(withoutAlignment) {
      if case .text(let text, let style) = span,
        case .text(let previous, let previousStyle)? =
          joined.last, style == previousStyle
      {
        joined[joined.count - 1] = .text(previous + text, style: style)
      } else {
        joined.append(span)
      }
    }
    return joined
  }

  static func withoutAlignment(_ span: MicronSpan) -> MicronSpan {
    switch span {
    case .text(let text, var style):
      style.alignment = .left
      return .text(text, style: style)
    case .link(var link):
      link.style.alignment = .left
      return .link(link)
    case .field(var field):
      field.style.alignment = .left
      return .field(field)
    }
  }
}
