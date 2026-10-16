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

/// RRC integers outside the range of `Int`.
///
/// Python's `cbor2` reads any unsigned integer into an unbounded `int`, so a hub can send one as
/// a key, a type, a limit or a size.
@Suite("RRC integers outside Int's range")
struct RRCIntegerRangeTests {

  static let huge = CBOR.Value.uint(UInt64.max)

  static func key(_ value: Int) -> CBOR.Value { .uint(UInt64(value)) }

  static func envelope(
    type: CBOR.Value, body: CBOR.Value? = nil, extra: [(CBOR.Value, CBOR.Value)] = []
  ) -> Data {
    var pairs: [(CBOR.Value, CBOR.Value)] = [
      (key(RRC.Key.version), .uint(UInt64(RRC.version))),
      (key(RRC.Key.type), type),
      (key(RRC.Key.id), .bytes(Data(repeating: 0x01, count: 8))),
      (key(RRC.Key.ts), .uint(1_700_000_000_000)),
      (key(RRC.Key.src), .bytes(Data(repeating: 0xAB, count: 16))),
    ]
    if let body { pairs.append((key(RRC.Key.body), body)) }
    return CBOR.encode(.map(pairs + extra))
  }

  @Test("an envelope key past Int.max is skipped")
  func envelopeKey() throws {
    let data = Self.envelope(type: Self.key(RRC.MessageType.pong), extra: [(Self.huge, .uint(1))])
    #expect(try RRC.decode(data).type == RRC.MessageType.pong)
  }

  @Test("an envelope type past Int.max is refused")
  func envelopeType() {
    #expect(throws: (any Error).self) { try RRC.decode(Self.envelope(type: Self.huge)) }
  }

  @Test("a hub ignores integers past Int.max and keeps reading the welcome")
  func hubPackets() {
    let manager = RRCManager(identity: Identity())
    defer { withExtendedLifetime(manager) {} }
    let hub = manager.addHub(hash: Data(repeating: 0xCD, count: 16))
    hub.onPacket(Self.envelope(type: Self.huge))
    hub.onPacket(
      Self.envelope(type: Self.key(RRC.MessageType.pong), extra: [(Self.huge, .uint(1))]))
    hub.onPacket(
      Self.envelope(
        type: Self.key(RRC.MessageType.resourceEnvelope),
        body: .map([
          (Self.huge, .uint(1)),
          (Self.key(RRC.ResField.id), .bytes(Data(repeating: 0x02, count: 8))),
          (Self.key(RRC.ResField.kind), .text("blob")),
          (Self.key(RRC.ResField.size), Self.huge),
        ])))
    hub.onPacket(
      Self.envelope(
        type: Self.key(RRC.MessageType.welcome),
        body: .map([
          (Self.huge, .uint(1)),
          (Self.key(RRC.WelcomeField.hub), .text("hub")),
          (Self.key(RRC.WelcomeField.caps), .map([(Self.huge, .bool(true))])),
          (
            Self.key(RRC.WelcomeField.limits),
            .map([
              (Self.huge, .uint(1)), (Self.key(RRC.LimitField.maxNickBytes), Self.huge),
            ])
          ),
        ])))

    #expect(hub.hubName == "hub")
    #expect(hub.hubCaps.isEmpty)
    #expect(hub.maxNickBytes == RRC.defaultMaxNickBytes)
  }
}
