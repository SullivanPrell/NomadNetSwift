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

private func notice(_ text: String, room: String? = nil) -> Data {
  var pairs: [(CBOR.Value, CBOR.Value)] = [
    (.uint(UInt64(RRC.Key.version)), .uint(UInt64(RRC.version))),
    (.uint(UInt64(RRC.Key.type)), .uint(UInt64(RRC.MessageType.notice))),
    (.uint(UInt64(RRC.Key.id)), .bytes(Data(repeating: 1, count: 8))),
    (.uint(UInt64(RRC.Key.ts)), .uint(0)),
    (.uint(UInt64(RRC.Key.src)), .bytes(Data(repeating: 0xAB, count: 16))),
    (.uint(UInt64(RRC.Key.body)), .text(text)),
  ]
  if let room { pairs.append((.uint(UInt64(RRC.Key.room)), .text(room))) }
  return CBOR.encode(.map(pairs))
}

private func envelope(type: Int, src: Data, room: String?, body: CBOR.Value, nick: String? = nil)
  -> Data
{
  var pairs: [(CBOR.Value, CBOR.Value)] = [
    (.uint(UInt64(RRC.Key.version)), .uint(UInt64(RRC.version))),
    (.uint(UInt64(RRC.Key.type)), .uint(UInt64(type))),
    (.uint(UInt64(RRC.Key.id)), .bytes(Data((0..<8).map { _ in UInt8.random(in: 0...255) }))),
    (.uint(UInt64(RRC.Key.ts)), .uint(0)),
    (.uint(UInt64(RRC.Key.src)), .bytes(src)),
    (.uint(UInt64(RRC.Key.body)), body),
  ]
  if let room { pairs.append((.uint(UInt64(RRC.Key.room)), .text(room))) }
  if let nick { pairs.append((.uint(UInt64(RRC.Key.nick)), .text(nick))) }
  return CBOR.encode(.map(pairs))
}

private func makeHub(rooms: [String] = [], storagePath: URL? = nil) -> RRCHub {
  let mgr = RRCManager(identity: Identity(), storagePath: storagePath)
  let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
  for r in rooms { _ = h.addRoom(r) }
  return h
}

/// The link lifecycle: teardown fires `onClosed` synchronously, which takes the hub lock.
final class RRCLinkLifecycleTests: XCTestCase {

  private final class App: NomadNetworkAppProtocol {
    let reticulum: Reticulum
    let identity = Identity()
    let storagePath: URL? = nil
    let peerDisplayName: String? = nil
    init(storagePath: URL) { reticulum = Reticulum(configuration: .init(storagePath: storagePath)) }
  }

  /// A hub holding a pending link to a random destination, wired as `connectWorker` wires it.
  private func hubWithPendingLink() throws -> (RRCHub, Link) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("rrc-link-\(UUID().uuidString)")
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    let app = App(storagePath: directory)
    addTeardownBlock { _ = app }  // RRCManager holds its app weakly
    let hubIdentity = Identity()
    let dest = try Destination(
      identity: hubIdentity, direction: .out, kind: .single, appName: "rrc", aspects: ["hub"])
    let hub = RRCManager(app: app).addHub(hash: dest.hash)
    let link = try Link.initiate(destination: dest, transport: app.reticulum.transport)
    hub.adoptLink(link)
    return (hub, link)
  }

  /// On WELCOME timeout the link is torn down (`RRC.py` hello_loop).
  ///
  /// Swift tore it down while holding the hub lock, and `onClosed` then waited on that lock
  /// forever.
  func testWelcomeTimeoutTearsDownWithoutDeadlock() throws {
    let (hub, link) = try hubWithPendingLink()
    let done = expectation(description: "welcome timeout returns")
    Thread.detachNewThread {
      hub.welcomeTimedOut()
      done.fulfill()
    }
    guard XCTWaiter().wait(for: [done], timeout: 5) == .completed else {
      return XCTFail("welcomeTimedOut deadlocked on the hub lock")
    }
    XCTAssertEqual(link.status, .closed)
    XCTAssertEqual(hub.status, .disconnected)
  }

  /// `RRC.py:449-454`: a failed identify tears the link down and sends no HELLO.
  func testFailedIdentifyTearsDownTheLink() throws {
    let (hub, link) = try hubWithPendingLink()
    var sent = 0
    hub.sendHook = { _ in sent += 1 }
    hub.onEstablished()  // identify throws: the link is not active
    XCTAssertEqual(link.status, .closed)
    Thread.sleep(forTimeInterval: 0.2)
    XCTAssertEqual(sent, 0)
  }

  /// `RRC.py:417`: the hub destination is built from `dest_name`, not a fixed `rrc.hub`.
  func testCustomDestNameBuildsThatDestination() throws {
    let identity = Identity()
    let hash = Destination.hash(fromFullName: "custom.chat.hub", identity: identity)
    let hub = RRCManager(identity: Identity()).addHub(hash: hash, destName: "custom.chat.hub")
    XCTAssertEqual(try hub.hubDestination(identity: identity).hash, hash)
  }

  /// `RRC.py:224`: the default name is `RNS.prettyhexrep(hub_hash)`.
  func testDefaultNameIsPrettyHexRep() {
    let hash = Data(repeating: 0xCD, count: 16)
    let hub = RRCManager(identity: Identity()).addHub(hash: hash)
    XCTAssertEqual(hub.name, RNSUtilities.prettyhexrep(hash))
  }
}

/// `strip_modifiers` on hub text: `RRC.py:206`, `:890`, `:1006`, `:1263`, `:1402`.
final class RRCStripModifiersTests: XCTestCase {
  private let rlo = "\u{202E}"

  func testMessageTextIsStripped() {
    let h = makeHub(rooms: ["lobby"])
    h.onPacket(
      envelope(
        type: RRC.MessageType.msg, src: Data(repeating: 1, count: 16), room: "lobby",
        body: .text("\(rlo)olleh")))
    XCTAssertEqual(h.getMessages(room: "lobby").map(\.text), ["olleh"])
  }

  func testHubNameIsStripped() {
    let h = makeHub()
    h.onPacket(
      envelope(
        type: RRC.MessageType.welcome, src: Data(repeating: 1, count: 16), room: nil,
        body: .map([(.uint(UInt64(RRC.WelcomeField.hub)), .text("\(rlo)buh"))])))
    XCTAssertEqual(h.hubName, "buh")
  }

  func testMotdIsStripped() {
    let h = makeHub()
    h.onPacket(notice("\(rlo)dtom"))
    XCTAssertEqual(h.motd, "dtom")
  }

  func testRoomListIsStripped() {
    let h = makeHub()
    h.onPacket(notice("Registered public rooms:\n  lob\(rlo)by - top\(rlo)ic"))
    XCTAssertEqual(h.availableRooms.count, 1)
    XCTAssertEqual(h.availableRooms["lobby"], .some("topic"))
  }
}

/// NomadNet 1.4.3 (commit 652a625): `/list` and `/who` replies on low-MTU links.
final class RRCLowMTUNoticeTests: XCTestCase {
  private let full = String(repeating: "ab", count: 32)  // 64 hex

  func testWhoAcceptsSixtyFourHexAndDropsThirtyTwo() {
    let r = RRCHub.parseWhoNotice(
      "members in lobby: alice (abcdef012345), \(full), \(String(repeating: "cd", count: 16))")
    XCTAssertEqual(r?.entries.map(\.hex), ["abcdef012345", full])
  }

  func testListFragmentsJoinTheRoomList() {
    let h = makeHub()
    h.onPacket(notice("Registered public rooms:"))
    h.onPacket(notice("  lobby - General chat"))
    h.onPacket(notice("  dev"))
    XCTAssertEqual(h.availableRooms["lobby"], .some("General chat"))
    XCTAssertEqual(h.availableRooms["dev"], .some(nil))
    XCTAssertNil(h.motd)
    XCTAssertTrue(h.notices.isEmpty)
  }

  func testFragmentOutsideTheWindowIsAMotd() {
    let h = makeHub()
    h.onPacket(notice("  lobby - General chat"))
    XCTAssertEqual(h.motd, "lobby - General chat")  // strip_modifiers ends in .strip()
    XCTAssertTrue(h.availableRooms.isEmpty)
  }

  func testWhoReplyIsNotTheMotd() {
    let h = makeHub()
    h.onPacket(notice("members in lobby: (none)"))
    XCTAssertNil(h.motd)
    XCTAssertTrue(h.notices.isEmpty)
  }

  func testPrefixMemberIsShownThenPromoted() throws {
    let h = makeHub(rooms: ["lobby"])
    let prefix = Data([0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45])
    h.onPacket(notice("members in lobby: alice (abcdef012345)", room: "lobby"))
    XCTAssertEqual(h.getMembers(room: "lobby"), [prefix])
    XCTAssertEqual(h.displayNameFor(prefix), "alice")

    let src = prefix + Data(repeating: 0x77, count: 10)
    h.onPacket(
      envelope(type: RRC.MessageType.msg, src: src, room: "lobby", body: .text("hi"), nick: "al"))
    XCTAssertEqual(h.getMembers(room: "lobby"), [src])
    XCTAssertEqual(h.displayNameFor(src), "al")
  }

  func testJoinedFanoutPromotesAndKeepsThePrefixNick() {
    let h = makeHub(rooms: ["lobby"])
    let prefix = Data([0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45])
    h.onPacket(notice("members in lobby: alice (abcdef012345)", room: "lobby"))
    let full = prefix + Data(repeating: 0x77, count: 10)
    h.onPacket(
      envelope(
        type: RRC.MessageType.joined, src: Data(repeating: 1, count: 16), room: "lobby",
        body: .array([.bytes(full), .bytes(Data(repeating: 2, count: 16))])))
    XCTAssertFalse(h.getMembers(room: "lobby").contains(prefix))
    XCTAssertEqual(h.displayNameFor(full), "alice")
  }

  func testPartedDropsThePrefixMember() {
    let h = makeHub(rooms: ["lobby"])
    let prefix = Data([0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45])
    h.onPacket(notice("members in lobby: alice (abcdef012345)", room: "lobby"))
    h.onPacket(
      envelope(
        type: RRC.MessageType.joined, src: Data(repeating: 1, count: 16), room: "lobby",
        body: .array([.bytes(Data(repeating: 3, count: 16))])))
    h.onPacket(
      envelope(
        type: RRC.MessageType.parted, src: Data(repeating: 1, count: 16), room: "lobby",
        body: .array([.bytes(prefix + Data(repeating: 0x77, count: 10))])))
    XCTAssertFalse(h.getMembers(room: "lobby").contains(prefix))
  }
}

/// `RRC.py:776-799`: a truncated history file keeps every record before the bad one.
final class RRCHistoryTruncationTests: XCTestCase {
  func testTruncatedTailKeepsTheValidPrefix() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("rrc-hist-\(UUID().uuidString)")
    addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
    let h = makeHub(rooms: ["lobby"], storagePath: dir)
    for text in ["one", "two"] {
      h.appendHistory(
        room: "lobby",
        msg: RRCMessage(kind: "msg", room: "lobby", src: nil, nick: nil, text: text, ts: 1))
    }
    let path = h.manager!.historyPath(hub: h, room: "lobby")
    let third = CBOR.encode(
      .map([(.text("k"), .text("msg")), (.text("t"), .text("three")), (.text("ts"), .uint(1))]))
    let handle = try FileHandle(forWritingTo: path)
    try handle.seekToEnd()
    try handle.write(contentsOf: third.prefix(third.count / 2))
    try handle.close()

    h.loadHistory()
    XCTAssertEqual(h.getMessages(room: "lobby").map(\.text), ["one", "two"])
  }
}
