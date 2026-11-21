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

/// NomadNet 1.5.1: a hub under a custom destination name wants that type (`RRC.py:226-227`).
final class RRC151WantedTypeTests: XCTestCase {

  private final class App: NomadNetworkAppProtocol {
    let reticulum: Reticulum
    let identity = Identity()
    let storagePath: URL? = nil
    let peerDisplayName: String? = nil
    init(storagePath: URL) { reticulum = Reticulum(configuration: .init(storagePath: storagePath)) }
  }

  private func makeApp() -> App {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("rrc151-\(UUID().uuidString)")
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return App(storagePath: directory)
  }

  /// `unwantsDestinationType` answers `true` only for a type the requester wanted.
  private func wanted(_ name: String, by app: App) -> Bool {
    let transport = app.reticulum.transport
    return transport.unwantsDestinationType(name, requester: transport.applicationIdentity.hash)
  }

  func testAHubUnderACustomNameWantsThatType() {
    let app = makeApp()
    let manager = RRCManager(app: app)

    manager.addHub(hash: Data(repeating: 0xAB, count: 16), destName: "custom.hub")

    XCTAssertTrue(wanted("custom.hub", by: app))
  }

  func testAHubUnderTheDefaultNameWantsNothing() {
    let app = makeApp()
    let manager = RRCManager(app: app)

    manager.addHub(hash: Data(repeating: 0xAB, count: 16))
    manager.addHub(hash: Data(repeating: 0xCD, count: 16), destName: RRC.defaultDestName)

    XCTAssertFalse(wanted(RRC.defaultDestName, by: app))
  }
}
