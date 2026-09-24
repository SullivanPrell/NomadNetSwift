//===----------------------------------------------------------------------===//
// Copyright (c) 2026 NomadNetSwift contributors.
//
// Licensed under the GNU General Public License, version 3 (GPL-3.0). See
// LICENSE in the repository root for the full license text, and NOTICE for
// attribution of the upstream project this file is derived from.
//
// SPDX-License-Identifier: GPL-3.0-only
//===----------------------------------------------------------------------===//

// swift-format-ignore-file: AlwaysUseLowerCamelCase, NoLeadingUnderscores

import Foundation

// Spellings public in 1.2.0, kept so 1.x stays source-compatible. Remove in 2.0.0.

extension RRCHub {
  /// Deprecated spelling of ``onPacket(_:)``.
  @available(*, deprecated, renamed: "onPacket(_:)")
  public func _onPacket(_ data: Data) { onPacket(data) }

  /// Deprecated spelling of ``msgFromEntry(room:entry:)``.
  @available(*, deprecated, renamed: "msgFromEntry(room:entry:)")
  public static func _msgFromEntry(room: String, entry: [String: CBOR.Value]) -> RRCMessage? {
    msgFromEntry(room: room, entry: entry)
  }

  /// Deprecated spelling of ``persistableRoom(_:)``.
  @available(*, deprecated, renamed: "persistableRoom(_:)")
  public static func _persistableRoom(_ room: String) -> Bool { persistableRoom(room) }
}
