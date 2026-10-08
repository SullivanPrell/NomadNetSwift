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
import ReticulumSwift
import Testing

@testable import NomadNet

/// CBOR nesting depth, against the vendored decoder NomadNet 1.4.4 reads RRC packets with.
///
/// `nomadnet/vendor/cbor.py` raises once nesting passes `_MAX_DEPTH = 100` (`cbor.py:226`,
/// `:311-312`), and `RRC._on_packet` drops a packet that fails to decode (`RRC.py:965-969`).
@Suite("CBOR nesting depth")
struct CBORDepthTests {

  /// One level of nesting: a one-item array, or a one-pair map whose key is null.
  static let levels: [[UInt8]] = [[0x81], [0xA1, 0xF6]]

  /// `depth` levels around a null.
  static func nested(_ level: [UInt8], depth: Int) -> Data {
    Data(Array([[UInt8]](repeating: level, count: depth).joined()) + [0xF6])
  }

  /// The number of levels above the innermost value.
  static func depth(of value: CBOR.Value) -> Int {
    switch value {
    case .array(let items): return 1 + depth(of: items[0])
    case .map(let pairs): return 1 + depth(of: pairs[0].1)
    default: return 0
    }
  }

  @Test("100,000 nested levels throw instead of overflowing the stack", arguments: levels)
  func deepNestingThrows(level: [UInt8]) {
    let error = #expect(throws: CBOR.CBORError.self) {
      try CBOR.decode(Self.nested(level, depth: 100_000))
    }
    guard case .nestingTooDeep = error else {
      Issue.record("expected nestingTooDeep, got \(String(describing: error))")
      return
    }
  }

  @Test("decodeAll throws on a deep item after a valid one", arguments: levels)
  func decodeAllDeepNestingThrows(level: [UInt8]) {
    let data = CBOR.encode(.uint(1)) + Self.nested(level, depth: 100_000)
    let error = #expect(throws: CBOR.CBORError.self) { try CBOR.decodeAll(data) }
    guard case .nestingTooDeep = error else {
      Issue.record("expected nestingTooDeep, got \(String(describing: error))")
      return
    }
  }

  @Test("101 levels throw", arguments: levels)
  func oneLevelPastTheLimitThrows(level: [UInt8]) {
    let error = #expect(throws: CBOR.CBORError.self) {
      try CBOR.decode(Self.nested(level, depth: 101))
    }
    guard case .nestingTooDeep = error else {
      Issue.record("expected nestingTooDeep, got \(String(describing: error))")
      return
    }
  }

  @Test("10 and 100 levels decode", arguments: levels, [10, 100])
  func nestingWithinTheLimitDecodes(level: [UInt8], depth: Int) throws {
    let value = try CBOR.decode(Self.nested(level, depth: depth))
    #expect(Self.depth(of: value) == depth)
  }

  @Test("An RRC hub drops a deeply nested packet")
  func hubDropsDeepPacket() {
    let hub = RRCManager(identity: Identity()).addHub(hash: Data(repeating: 0xCD, count: 16))
    hub.onPacket(Self.nested([0x81], depth: 100_000))
    #expect(!hub.welcomed)
  }

  @Test("An RRC hub reads a welcome nested three levels deep")
  func hubReadsNestedWelcome() {
    let hub = RRCManager(identity: Identity()).addHub(hash: Data(repeating: 0xCD, count: 16))
    let limits: CBOR.Value = .map([
      (.uint(UInt64(RRC.LimitField.maxMsgBodyBytes)), .uint(UInt64(512)))
    ])
    let body: CBOR.Value = .map([
      (.uint(UInt64(RRC.WelcomeField.hub)), .text("NestedHub")),
      (.uint(UInt64(RRC.WelcomeField.caps)), .map([])),
      (.uint(UInt64(RRC.WelcomeField.limits)), limits),
    ])
    let packet = CBOR.encode(
      .map([
        (.uint(UInt64(RRC.Key.version)), .uint(UInt64(RRC.version))),
        (.uint(UInt64(RRC.Key.type)), .uint(UInt64(RRC.MessageType.welcome))),
        (.uint(UInt64(RRC.Key.id)), .bytes(Data(repeating: 0x01, count: 8))),
        (.uint(UInt64(RRC.Key.ts)), .uint(UInt64(1_700_000_000_000))),
        (.uint(UInt64(RRC.Key.src)), .bytes(Data(repeating: 0xAB, count: 16))),
        (.uint(UInt64(RRC.Key.body)), body),
      ]))
    hub.onPacket(packet)
    #expect(hub.welcomed)
    #expect(hub.hubName == "NestedHub")
  }
}
