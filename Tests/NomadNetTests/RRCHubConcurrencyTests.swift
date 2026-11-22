//===----------------------------------------------------------------------===//
// Copyright (c) 2026 NomadNetSwift contributors.
//
// Licensed under the GNU General Public License, version 3 (GPL-3.0). See
// LICENSE in the repository root for the full license text, and NOTICE for
// attribution of the upstream project this file is derived from.
//
// SPDX-License-Identifier: GPL-3.0-only
//===----------------------------------------------------------------------===//

import ReticulumSwift
import XCTest

@testable import NomadNet

/// The hub writes its state under `lock` on network threads while an app's views read it on the
/// main thread.
///
/// Run under `--sanitize=thread`: a plain run rarely interleaves at the wrong instruction, and
/// ThreadSanitizer reports the race whether or not it does.
final class RRCHubConcurrencyTests: XCTestCase {

  func testPublicStateReadsWhileTheHubWritesIt() {
    let hub = RRCManager(identity: Identity()).addHub(hash: Data(repeating: 0xCD, count: 16))

    DispatchQueue.concurrentPerform(iterations: 400) { i in
      if i.isMultiple(of: 2) {
        hub.addRoom("room\(i)")
        hub.setStatus(.connecting, text: "Connecting \(i)")
      } else {
        _ = hub.rooms.count
        _ = hub.statusText.count
        _ = hub.status
        _ = hub.unreadRooms.count
      }
    }

    XCTAssertEqual(hub.rooms.count, 200)
    XCTAssertEqual(hub.status, .connecting)
  }
}
