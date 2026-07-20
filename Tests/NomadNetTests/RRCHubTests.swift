import XCTest
@testable import NomadNet
import ReticulumSwift

// MARK: - Test helpers

private func makeSrc(_ byte: UInt8 = 0xAB, count: Int = 16) -> Data { Data(repeating: byte, count: count) }

private func makeManager(identity: Identity? = nil) -> RRCManager {
    RRCManager(identity: identity ?? Identity())
}

private func makeHub(identity: Identity? = nil, rooms: [String] = []) -> RRCHub {
    let id = identity ?? Identity()
    let mgr = makeManager(identity: id)
    let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
    for r in rooms { _ = h.addRoom(r) }
    return h
}

// Build a raw CBOR packet as the hub would receive it from the network.
private func makePkt(
    type: Int,
    src: Data = makeSrc(),
    room: String? = nil,
    body: CBOR.Value? = nil,
    nick: String? = nil,
    mid: Data = Data((0..<8).map { _ in UInt8.random(in: 0...255) }),
    ts: Int64? = nil
) -> Data {
    let tsVal = ts ?? Int64(Date().timeIntervalSince1970 * 1000)
    var pairs: [(CBOR.Value, CBOR.Value)] = [
        (.uint(UInt64(RRC.Key.version)), .uint(UInt64(RRC.version))),
        (.uint(UInt64(RRC.Key.type)),    .uint(UInt64(type))),
        (.uint(UInt64(RRC.Key.id)),      .bytes(mid)),
        (.uint(UInt64(RRC.Key.ts)),      .uint(UInt64(bitPattern: tsVal))),
        (.uint(UInt64(RRC.Key.src)),     .bytes(src)),
    ]
    if let r = room { pairs.append((.uint(UInt64(RRC.Key.room)), .text(r))) }
    if let b = body { pairs.append((.uint(UInt64(RRC.Key.body)), b)) }
    if let n = nick { pairs.append((.uint(UInt64(RRC.Key.nick)), .text(n))) }
    return CBOR.encode(.map(pairs))
}

private func makeWelcomePkt(
    src: Data = makeSrc(),
    hubName: String = "TestHub",
    hubVer: String = "1.0",
    maxNick: Int = 32,
    maxRoom: Int = 64,
    maxMsg: Int = 350,
    maxRooms: Int = 32,
    rate: Int = 240
) -> Data {
    let limits: CBOR.Value = .map([
        (.uint(UInt64(RRC.LimitField.maxNickBytes)),           .uint(UInt64(maxNick))),
        (.uint(UInt64(RRC.LimitField.maxRoomNameBytes)),       .uint(UInt64(maxRoom))),
        (.uint(UInt64(RRC.LimitField.maxMsgBodyBytes)),        .uint(UInt64(maxMsg))),
        (.uint(UInt64(RRC.LimitField.maxRoomsPerSession)),     .uint(UInt64(maxRooms))),
        (.uint(UInt64(RRC.LimitField.rateLimitMsgsPerMinute)), .uint(UInt64(rate))),
    ])
    let body: CBOR.Value = .map([
        (.uint(UInt64(RRC.WelcomeField.hub)),    .text(hubName)),
        (.uint(UInt64(RRC.WelcomeField.ver)),    .text(hubVer)),
        (.uint(UInt64(RRC.WelcomeField.caps)),   .map([])),
        (.uint(UInt64(RRC.WelcomeField.limits)), limits),
    ])
    return makePkt(type: RRC.MessageType.welcome, src: src, body: body)
}

private func makeJoinedPkt(src: Data = makeSrc(), room: String, members: [Data], nick: String? = nil) -> Data {
    let bodyArr: CBOR.Value = .array(members.map { .bytes($0) })
    return makePkt(type: RRC.MessageType.joined, src: src, room: room, body: bodyArr, nick: nick)
}

private func makePartedPkt(src: Data = makeSrc(), room: String, members: [Data], nick: String? = nil) -> Data {
    let bodyArr: CBOR.Value = .array(members.map { .bytes($0) })
    return makePkt(type: RRC.MessageType.parted, src: src, room: room, body: bodyArr, nick: nick)
}

// Decode a sent CBOR map into a keyed dict.
private func decodeSentEnv(_ data: Data) throws -> [Int: CBOR.Value] {
    let v = try CBOR.decode(data)
    guard case .map(let pairs) = v else { throw NSError(domain: "test", code: 1) }
    var d: [Int: CBOR.Value] = [:]
    for (k, val) in pairs {
        if case .uint(let u) = k { d[Int(u)] = val }
    }
    return d
}

// MARK: - RRC new constants

final class RRCNewConstantsTests: XCTestCase {
    // LimitField (Python L_MAX_*)
    func testLimitFieldMaxNickBytes()           { XCTAssertEqual(RRC.LimitField.maxNickBytes,            0) }
    func testLimitFieldMaxRoomNameBytes()        { XCTAssertEqual(RRC.LimitField.maxRoomNameBytes,        1) }
    func testLimitFieldMaxMsgBodyBytes()         { XCTAssertEqual(RRC.LimitField.maxMsgBodyBytes,         2) }
    func testLimitFieldMaxRoomsPerSession()      { XCTAssertEqual(RRC.LimitField.maxRoomsPerSession,      3) }
    func testLimitFieldRateLimitMsgsPerMinute()  { XCTAssertEqual(RRC.LimitField.rateLimitMsgsPerMinute,  4) }

    // ResField (Python B_RES_*)
    func testResFieldID()       { XCTAssertEqual(RRC.ResField.id,       0) }
    func testResFieldKind()     { XCTAssertEqual(RRC.ResField.kind,     1) }
    func testResFieldSize()     { XCTAssertEqual(RRC.ResField.size,     2) }
    func testResFieldSha256()   { XCTAssertEqual(RRC.ResField.sha256,   3) }
    func testResFieldEncoding() { XCTAssertEqual(RRC.ResField.encoding, 4) }

    // ResKind (Python RES_KIND_*)
    func testResKindNotice() { XCTAssertEqual(RRC.ResKind.notice, "notice") }
    func testResKindMotd()   { XCTAssertEqual(RRC.ResKind.motd,   "motd")   }
    func testResKindBlob()   { XCTAssertEqual(RRC.ResKind.blob,   "blob")   }

    // HistKey (Python H_KIND, H_SRC, …)
    func testHistKeyKind()    { XCTAssertEqual(RRC.HistKey.kind,    "k")  }
    func testHistKeySrc()     { XCTAssertEqual(RRC.HistKey.src,     "s")  }
    func testHistKeyNick()    { XCTAssertEqual(RRC.HistKey.nick,    "n")  }
    func testHistKeyText()    { XCTAssertEqual(RRC.HistKey.text,    "t")  }
    func testHistKeyTs()      { XCTAssertEqual(RRC.HistKey.ts,      "ts") }
    func testHistKeyMention() { XCTAssertEqual(RRC.HistKey.mention, "m")  }
}

// MARK: - CBOR.decodeAll

final class CBORDecodeAllTests: XCTestCase {
    func testDecodeAllEmpty() throws {
        let r = try CBOR.decodeAll(Data())
        XCTAssertTrue(r.isEmpty)
    }

    func testDecodeAllSingleItem() throws {
        let data = CBOR.encode(.uint(42))
        let r = try CBOR.decodeAll(data)
        XCTAssertEqual(r.count, 1)
        guard case .uint(let n) = r[0] else { return XCTFail() }
        XCTAssertEqual(n, 42)
    }

    func testDecodeAllMultipleItems() throws {
        var data = Data()
        data.append(CBOR.encode(.uint(1)))
        data.append(CBOR.encode(.text("hello")))
        data.append(CBOR.encode(.bool(true)))
        let r = try CBOR.decodeAll(data)
        XCTAssertEqual(r.count, 3)
        guard case .uint(1) = r[0] else { return XCTFail("expected uint(1)") }
        guard case .text("hello") = r[1] else { return XCTFail("expected text") }
        guard case .bool(true) = r[2] else { return XCTFail("expected bool") }
    }

    func testDecodeAllMapsRoundTrip() throws {
        let m1: [(CBOR.Value, CBOR.Value)] = [(.uint(1), .text("a"))]
        let m2: [(CBOR.Value, CBOR.Value)] = [(.uint(2), .bytes(Data([0xAB])))]
        var data = Data()
        data.append(CBOR.encode(.map(m1)))
        data.append(CBOR.encode(.map(m2)))
        let r = try CBOR.decodeAll(data)
        XCTAssertEqual(r.count, 2)
        guard case .map(let pairs1) = r[0] else { return XCTFail() }
        XCTAssertEqual(pairs1.count, 1)
        guard case .map(let pairs2) = r[1] else { return XCTFail() }
        XCTAssertEqual(pairs2.count, 1)
    }
}

// MARK: - RRCHub init / state

final class RRCHubInitTests: XCTestCase {
    func testInitialStatusDisconnected() {
        let h = makeHub()
        XCTAssertEqual(h.status, .disconnected)
    }

    // Regression for bug 007: `connect()` acquired the hub's non-recursive NSLock
    // and, while holding it, called `_setStatus`, which re-acquired the SAME lock →
    // self-deadlock. `connect()` never returned, so no real link was ever opened.
    // Every prior RRC test drove the hub via the `_sendHook`/`_onPacket` seam and
    // never exercised the real connect() path, so the deadlock went uncaught.
    // Run connect() off-thread with a timeout: pre-fix this hangs and the
    // expectation is never fulfilled (clean failure, not a wedged suite).
    func testConnectReturnsAndDoesNotDeadlock() {
        let h = makeHub()
        XCTAssertEqual(h.status, .disconnected)
        let returned = expectation(description: "connect() returns without deadlocking")
        DispatchQueue.global().async {
            h.connect()          // pre-fix: deadlocks here forever
            returned.fulfill()
        }
        wait(for: [returned], timeout: 5)
        // connect() sets .connecting under the lock; the worker (no transport in a
        // bare manager) then advances to .failed. Either proves the state machine ran.
        XCTAssertTrue(h.status == .connecting || h.status == .failed,
                      "connect() should advance past .disconnected, got \(h.status)")
    }

    func testInitialWelcomedFalse() {
        XCTAssertFalse(makeHub().welcomed)
    }

    func testInitialRoomsEmpty() {
        XCTAssertTrue(makeHub().rooms.isEmpty)
    }

    func testInitialHubNameNil() {
        XCTAssertNil(makeHub().hubName)
    }

    func testInitialMotdNil() {
        XCTAssertNil(makeHub().motd)
    }

    func testDefaultMaxNickBytes() {
        XCTAssertEqual(makeHub().maxNickBytes, RRC.defaultMaxNickBytes)
    }

    func testDefaultMaxMsgBodyBytes() {
        XCTAssertEqual(makeHub().maxMsgBodyBytes, RRC.defaultMaxMsgBytes)
    }

    func testHubHashStored() {
        let hash = Data(repeating: 0xEF, count: 16)
        let mgr = makeManager()
        let h = mgr.addHub(hash: hash)
        XCTAssertEqual(h.hubHash, hash)
    }

    func testDestNameDefault() {
        XCTAssertEqual(makeHub().destName, RRC.defaultDestName)
    }
}

// MARK: - normalizeRoom

final class RRCHubNormalizeRoomTests: XCTestCase {
    func testNormalizeRoomLowercases() throws {
        let h = makeHub()
        XCTAssertEqual(try h.normalizeRoom("Lobby"), "lobby")
    }

    func testNormalizeRoomTrimsWhitespace() throws {
        let h = makeHub()
        XCTAssertEqual(try h.normalizeRoom("  dev  "), "dev")
    }

    func testNormalizeRoomEmptyThrows() {
        let h = makeHub()
        XCTAssertThrowsError(try h.normalizeRoom(""))
    }

    func testNormalizeRoomWhitespaceOnlyThrows() {
        let h = makeHub()
        XCTAssertThrowsError(try h.normalizeRoom("   "))
    }
}

// MARK: - Room management

final class RRCHubRoomManagementTests: XCTestCase {
    func testAddRoomAddsToRoomsSet() {
        let h = makeHub()
        _ = h.addRoom("lobby")
        XCTAssertTrue(h.rooms.contains("lobby"))
    }

    func testAddRoomCreatesMessageBuffer() {
        let h = makeHub()
        _ = h.addRoom("lobby")
        XCTAssertNotNil(h.getMessages(room: "lobby"))
    }

    func testAddRoomNormalizes() {
        let h = makeHub()
        _ = h.addRoom("LOBBY")
        XCTAssertTrue(h.rooms.contains("lobby"))
    }

    func testRemoveRoomRemovesFromRoomsSet() {
        let h = makeHub(rooms: ["lobby"])
        h.removeRoom("lobby")
        XCTAssertFalse(h.rooms.contains("lobby"))
    }

    func testRemoveRoomClearsMessages() {
        let h = makeHub(rooms: ["lobby"])
        h.removeRoom("lobby")
        XCTAssertTrue(h.getMessages(room: "lobby").isEmpty)
    }

    func testClearMessagesEmptiesBuffer() {
        let h = makeHub(rooms: ["lobby"])
        // Feed a message
        h._onPacket(makePkt(type: RRC.MessageType.msg, src: makeSrc(), room: "lobby", body: .text("hi")))
        XCTAssertFalse(h.getMessages(room: "lobby").isEmpty)
        h.clearMessages("lobby")
        XCTAssertTrue(h.getMessages(room: "lobby").isEmpty)
    }

    func testGetMembersEmptyByDefault() {
        let h = makeHub(rooms: ["lobby"])
        XCTAssertTrue(h.getMembers(room: "lobby").isEmpty)
    }

    func testMarkReadClearsUnreadRoom() {
        let h = makeHub(rooms: ["lobby"])
        h._onPacket(makePkt(type: RRC.MessageType.msg, src: makeSrc(), room: "lobby", body: .text("hi")))
        h.markRead("lobby")
        XCTAssertFalse(h.unreadRooms.contains("lobby"))
    }
}

// MARK: - displayNameFor / nick

final class RRCHubNickTests: XCTestCase {
    func testDisplayNameForUnknownReturnsHexPrefix() {
        let h = makeHub()
        let hash = Data(repeating: 0xAB, count: 8)
        let name = h.displayNameFor(hash)
        XCTAssertEqual(name, hash.hex.prefix(12).lowercased())
    }

    func testDisplayNameForKnownNickReturnsNick() {
        let h = makeHub(rooms: ["lobby"])
        let hash = Data(repeating: 0x11, count: 8)
        h._onPacket(makePkt(type: RRC.MessageType.msg, src: hash, room: "lobby",
                            body: .text("hey"), nick: "alice"))
        XCTAssertEqual(h.displayNameFor(hash), "alice")
    }

    func testGetEffectiveNickFromOverride() {
        let h = makeHub()
        h.nickOverride = "testNick"
        XCTAssertEqual(h.getEffectiveNick(), "testNick")
    }

    func testGetEffectiveNickFromManager() {
        let mgr = RRCManager(identity: Identity(), nickname: "globalNick")
        let h = mgr.addHub(hash: Data(repeating: 0xFF, count: 16))
        XCTAssertEqual(h.getEffectiveNick(), "globalNick")
    }

    func testNickOverrideTakesPriorityOverManager() {
        let mgr = RRCManager(identity: Identity(), nickname: "globalNick")
        let h = mgr.addHub(hash: Data(repeating: 0xFF, count: 16))
        h.nickOverride = "myNick"
        XCTAssertEqual(h.getEffectiveNick(), "myNick")
    }

    func testSetNickOverrideNilOnEmpty() {
        let h = makeHub()
        h.nickOverride = "alice"
        h.setNickOverride("")
        XCTAssertNil(h.nickOverride)
    }

    func testSetNickOverrideNilOnNil() {
        let h = makeHub()
        h.nickOverride = "alice"
        h.setNickOverride(nil)
        XCTAssertNil(h.nickOverride)
    }
}

// MARK: - sendHello CBOR structure

final class RRCHubSendHelloTests: XCTestCase {
    func testSendHelloContainsHelloType() throws {
        let h = makeHub()
        var sent: Data? = nil
        h._sendHook = { sent = $0 }
        h._sendHello()
        let env = try decodeSentEnv(XCTUnwrap(sent))
        guard case .uint(let t) = env[RRC.Key.type] else { return XCTFail("no type") }
        XCTAssertEqual(Int(t), RRC.MessageType.hello)
    }

    func testSendHelloContainsSrc() throws {
        let id = Identity()
        let h = makeHub(identity: id)
        var sent: Data? = nil
        h._sendHook = { sent = $0 }
        h._sendHello()
        let env = try decodeSentEnv(XCTUnwrap(sent))
        guard case .bytes(let src) = env[RRC.Key.src] else { return XCTFail("no src") }
        XCTAssertEqual(src, id.hash)
    }

    func testSendHelloContainsVersion() throws {
        let h = makeHub()
        var sent: Data? = nil
        h._sendHook = { sent = $0 }
        h._sendHello()
        let env = try decodeSentEnv(XCTUnwrap(sent))
        guard case .uint(let v) = env[RRC.Key.version] else { return XCTFail("no version") }
        XCTAssertEqual(Int(v), RRC.version)
    }

    func testSendHelloBodyIsMap() throws {
        let h = makeHub()
        var sent: Data? = nil
        h._sendHook = { sent = $0 }
        h._sendHello()
        let env = try decodeSentEnv(XCTUnwrap(sent))
        guard case .map(_) = env[RRC.Key.body] else { return XCTFail("body should be a map") }
    }

    func testSendHelloBodyContainsName() throws {
        let h = makeHub()
        var sent: Data? = nil
        h._sendHook = { sent = $0 }
        h._sendHello()
        let env = try decodeSentEnv(XCTUnwrap(sent))
        guard case .map(let bodyPairs) = env[RRC.Key.body] else { return XCTFail() }
        var bodyDict: [Int: CBOR.Value] = [:]
        for (k, v) in bodyPairs { if case .uint(let u) = k { bodyDict[Int(u)] = v } }
        guard case .text(let name) = bodyDict[RRC.HelloField.name] else { return XCTFail("no name") }
        XCTAssertEqual(name, "nomadnet")
    }

    func testSendHelloBodyContainsCaps() throws {
        let h = makeHub()
        var sent: Data? = nil
        h._sendHook = { sent = $0 }
        h._sendHello()
        let env = try decodeSentEnv(XCTUnwrap(sent))
        guard case .map(let bodyPairs) = env[RRC.Key.body] else { return XCTFail() }
        var bodyDict: [Int: CBOR.Value] = [:]
        for (k, v) in bodyPairs { if case .uint(let u) = k { bodyDict[Int(u)] = v } }
        guard case .map(_) = bodyDict[RRC.HelloField.caps] else { return XCTFail("no caps map") }
    }

    func testSendHelloIncludesNickWhenSet() throws {
        let h = makeHub()
        h.nickOverride = "alice"
        var sent: Data? = nil
        h._sendHook = { sent = $0 }
        h._sendHello()
        let env = try decodeSentEnv(XCTUnwrap(sent))
        guard case .text(let n) = env[RRC.Key.nick] else { return XCTFail("no nick") }
        XCTAssertEqual(n, "alice")
    }

    func testSendHelloOmitsNickWhenNil() throws {
        let h = makeHub()
        var sent: Data? = nil
        h._sendHook = { sent = $0 }
        h._sendHello()
        let env = try decodeSentEnv(XCTUnwrap(sent))
        XCTAssertNil(env[RRC.Key.nick])
    }
}

// MARK: - _onPacket: T_WELCOME

final class RRCHubWelcomeTests: XCTestCase {
    func testOnWelcomeSetsWelcomed() {
        let h = makeHub()
        h._onPacket(makeWelcomePkt())
        XCTAssertTrue(h.welcomed)
    }

    func testOnWelcomeSetsStatusConnected() {
        let h = makeHub()
        h._onPacket(makeWelcomePkt())
        XCTAssertEqual(h.status, .connected)
    }

    func testOnWelcomeSetsHubName() {
        let h = makeHub()
        h._onPacket(makeWelcomePkt(hubName: "MyHub"))
        XCTAssertEqual(h.hubName, "MyHub")
    }

    func testOnWelcomeSetsHubVersion() {
        let h = makeHub()
        h._onPacket(makeWelcomePkt(hubVer: "2.0"))
        XCTAssertEqual(h.hubVersion, "2.0")
    }

    func testOnWelcomeUpdatesMaxMsgBodyBytes() {
        let h = makeHub()
        h._onPacket(makeWelcomePkt(maxMsg: 512))
        XCTAssertEqual(h.maxMsgBodyBytes, 512)
    }

    func testOnWelcomeUpdatesMaxNickBytes() {
        let h = makeHub()
        h._onPacket(makeWelcomePkt(maxNick: 16))
        XCTAssertEqual(h.maxNickBytes, 16)
    }

    func testOnWelcomeResetsReconnectAttempts() {
        let h = makeHub()
        h._reconnectAttempts = 3
        h._onPacket(makeWelcomePkt())
        XCTAssertEqual(h._reconnectAttempts, 0)
    }
}

// MARK: - _onPacket: T_JOINED / T_PARTED

final class RRCHubJoinPartTests: XCTestCase {
    func testOnJoinedAddsToRoomsSet() {
        let id = Identity()
        let mgr = makeManager(identity: id)
        let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
        // Simulate our own join: put room in pendingJoins
        h._pendingJoins.insert("lobby")
        h._onPacket(makeJoinedPkt(src: id.hash, room: "lobby", members: [id.hash]))
        XCTAssertTrue(h.rooms.contains("lobby"))
    }

    func testOnJoinedRecordsMembersInSet() {
        let id = Identity()
        let mgr = makeManager(identity: id)
        let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
        let peerHash = Data(repeating: 0x77, count: 16)
        h._pendingJoins.insert("lobby")
        h._onPacket(makeJoinedPkt(src: id.hash, room: "lobby", members: [id.hash, peerHash]))
        let members = h.getMembers(room: "lobby")
        XCTAssertTrue(members.contains(peerHash))
    }

    func testOnJoinedForeignPeerRecordsSystemMessage() {
        let id = Identity()
        let mgr = makeManager(identity: id)
        let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
        _ = h.addRoom("lobby")
        let peer = Data(repeating: 0x77, count: 16)
        h._onPacket(makeJoinedPkt(src: peer, room: "lobby", members: [peer]))
        let msgs = h.getMessages(room: "lobby")
        XCTAssertTrue(msgs.contains { $0.kind == "system" && $0.text.contains("joined") })
    }

    func testOnJoinedLearnsPeerNick() {
        let id = Identity()
        let mgr = makeManager(identity: id)
        let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
        _ = h.addRoom("lobby")
        let peer = Data(repeating: 0x55, count: 16)
        h._onPacket(makeJoinedPkt(src: peer, room: "lobby", members: [peer], nick: "bob"))
        XCTAssertEqual(h.displayNameFor(peer), "bob")
    }

    func testOnPartedRemovesMemberFromRoom() {
        let id = Identity()
        let mgr = makeManager(identity: id)
        let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
        _ = h.addRoom("lobby")
        let peer = Data(repeating: 0x55, count: 16)
        // First join
        h._onPacket(makeJoinedPkt(src: peer, room: "lobby", members: [peer]))
        // Then part
        h._onPacket(makePartedPkt(src: peer, room: "lobby", members: [peer]))
        XCTAssertFalse(h.getMembers(room: "lobby").contains(peer))
    }

    func testOnPartedForeignPeerRecordsSystemMessage() {
        let id = Identity()
        let mgr = makeManager(identity: id)
        let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
        _ = h.addRoom("lobby")
        let peer = Data(repeating: 0x55, count: 16)
        h._onPacket(makePartedPkt(src: peer, room: "lobby", members: [peer]))
        let msgs = h.getMessages(room: "lobby")
        XCTAssertTrue(msgs.contains { $0.kind == "system" && $0.text.contains("left") })
    }
}

// MARK: - _onPacket: T_MSG / T_ACTION / T_NOTICE / T_ERROR

final class RRCHubMessageHandlerTests: XCTestCase {
    func testOnMsgRecordsMessage() {
        let h = makeHub(rooms: ["lobby"])
        h._onPacket(makePkt(type: RRC.MessageType.msg, src: makeSrc(), room: "lobby", body: .text("hello")))
        let msgs = h.getMessages(room: "lobby")
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs[0].kind, "msg")
        XCTAssertEqual(msgs[0].text, "hello")
    }

    func testOnMsgStoresNick() {
        let h = makeHub(rooms: ["lobby"])
        h._onPacket(makePkt(type: RRC.MessageType.msg, src: makeSrc(), room: "lobby",
                            body: .text("hi"), nick: "alice"))
        let msgs = h.getMessages(room: "lobby")
        XCTAssertEqual(msgs.first?.nick, "alice")
    }

    func testOnMsgMarksUnreadForInactiveRoom() {
        let mgr = makeManager()
        let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
        _ = h.addRoom("lobby")
        _ = h.addRoom("dev")
        mgr.setActive(hub: h, room: "dev")  // active on dev, msg arrives in lobby
        h._onPacket(makePkt(type: RRC.MessageType.msg, src: makeSrc(), room: "lobby", body: .text("ping")))
        XCTAssertTrue(h.unreadRooms.contains("lobby"))
    }

    func testOnMsgDoesNotMarkUnreadForActiveRoom() {
        let mgr = makeManager()
        let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
        _ = h.addRoom("lobby")
        mgr.setActive(hub: h, room: "lobby")
        h._onPacket(makePkt(type: RRC.MessageType.msg, src: makeSrc(), room: "lobby", body: .text("hi")))
        XCTAssertFalse(h.unreadRooms.contains("lobby"))
    }

    func testOnMsgLearnsSenderNick() {
        let h = makeHub(rooms: ["lobby"])
        let src = Data(repeating: 0x11, count: 16)
        h._onPacket(makePkt(type: RRC.MessageType.msg, src: src, room: "lobby",
                            body: .text("hi"), nick: "carol"))
        XCTAssertEqual(h.displayNameFor(src), "carol")
    }

    func testOnMsgDeduplicatesOwnMessage() {
        let id = Identity()
        let mgr = makeManager(identity: id)
        let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
        _ = h.addRoom("lobby")
        let mid = Data(repeating: 0xAA, count: 8)
        h._sentIDs.append(mid)  // simulate already having sent this mid
        h._onPacket(makePkt(type: RRC.MessageType.msg, src: id.hash, room: "lobby",
                            body: .text("echo"), mid: mid))
        XCTAssertTrue(h.getMessages(room: "lobby").isEmpty)
    }

    func testOnActionRecordsAction() {
        let h = makeHub(rooms: ["lobby"])
        h._onPacket(makePkt(type: RRC.MessageType.action, src: makeSrc(), room: "lobby",
                            body: .text("waves")))
        let msgs = h.getMessages(room: "lobby")
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs[0].kind, "action")
    }

    func testOnNoticeRecordsNotice() {
        let h = makeHub(rooms: ["lobby"])
        h._onPacket(makePkt(type: RRC.MessageType.notice, src: makeSrc(), room: "lobby",
                            body: .text("server restarting")))
        let msgs = h.getMessages(room: "lobby")
        XCTAssertTrue(msgs.contains { $0.kind == "notice" })
    }

    func testOnNoticeMOTDSetMotd() {
        let h = makeHub()
        // A NOTICE with no room and string body → MOTD
        h._onPacket(makePkt(type: RRC.MessageType.notice, src: makeSrc(), body: .text("Welcome!")))
        XCTAssertEqual(h.motd, "Welcome!")
    }

    func testOnErrorRecordsError() {
        let h = makeHub(rooms: ["lobby"])
        h._onPacket(makePkt(type: RRC.MessageType.error, src: makeSrc(), room: "lobby",
                            body: .text("rate limit exceeded")))
        let msgs = h.getMessages(room: "lobby")
        XCTAssertTrue(msgs.contains { $0.kind == "error" })
    }
}

// MARK: - _onPacket: T_PING / T_PONG

final class RRCHubPingPongTests: XCTestCase {
    func testOnPingRespondsWithPong() throws {
        let h = makeHub()
        var sent: Data? = nil
        h._sendHook = { sent = $0 }
        let pingBody = Data(repeating: 0x42, count: 8)
        h._onPacket(makePkt(type: RRC.MessageType.ping, src: makeSrc(), body: .bytes(pingBody)))
        let env = try decodeSentEnv(XCTUnwrap(sent))
        guard case .uint(let t) = env[RRC.Key.type] else { return XCTFail("no type") }
        XCTAssertEqual(Int(t), RRC.MessageType.pong)
    }

    func testOnPongRecordsRTT() {
        let h = makeHub(rooms: ["lobby"])
        let mid = Data((0..<8).map { _ in UInt8.random(in: 0...255) })
        let sentAt = Int64(Date().timeIntervalSince1970 * 1000) - 50
        h._pendingPings[mid] = (sentAt, "lobby")
        h._onPacket(makePkt(type: RRC.MessageType.pong, src: makeSrc(), body: .bytes(mid)))
        // Pong should record a system message with RTT
        let msgs = h.getMessages(room: "lobby")
        XCTAssertTrue(msgs.contains { $0.kind == "system" && $0.text.lowercased().contains("pong") })
    }
}

// MARK: - sendJoin / sendPart / sendMessage / sendAction outbound CBOR

final class RRCHubOutboundTests: XCTestCase {
    func testJoinRoomCBORType() throws {
        let h = makeHub()
        var sent: Data? = nil
        h._sendHook = { sent = $0 }
        try h.joinRoom("lobby")
        let env = try decodeSentEnv(XCTUnwrap(sent))
        guard case .uint(let t) = env[RRC.Key.type] else { return XCTFail() }
        XCTAssertEqual(Int(t), RRC.MessageType.join)
    }

    func testJoinRoomCBORRoom() throws {
        let h = makeHub()
        var sent: Data? = nil
        h._sendHook = { sent = $0 }
        try h.joinRoom("DEV")  // should normalize
        let env = try decodeSentEnv(XCTUnwrap(sent))
        guard case .text(let r) = env[RRC.Key.room] else { return XCTFail() }
        XCTAssertEqual(r, "dev")
    }

    func testPartRoomCBORType() throws {
        let h = makeHub(rooms: ["lobby"])
        var sent: Data? = nil
        h._sendHook = { sent = $0 }
        h.partRoom("lobby")
        let env = try decodeSentEnv(XCTUnwrap(sent))
        guard case .uint(let t) = env[RRC.Key.type] else { return XCTFail() }
        XCTAssertEqual(Int(t), RRC.MessageType.part)
    }

    func testSendMessageCBORType() throws {
        let h = makeHub(rooms: ["lobby"])
        var sent: Data? = nil
        h._sendHook = { sent = $0 }
        _ = try h.sendMessage(room: "lobby", text: "hello")
        let env = try decodeSentEnv(XCTUnwrap(sent))
        guard case .uint(let t) = env[RRC.Key.type] else { return XCTFail() }
        XCTAssertEqual(Int(t), RRC.MessageType.msg)
    }

    func testSendMessageCBORBody() throws {
        let h = makeHub(rooms: ["lobby"])
        var sent: Data? = nil
        h._sendHook = { sent = $0 }
        _ = try h.sendMessage(room: "lobby", text: "world")
        let env = try decodeSentEnv(XCTUnwrap(sent))
        guard case .text(let b) = env[RRC.Key.body] else { return XCTFail() }
        XCTAssertEqual(b, "world")
    }

    func testSendMessageRecordsLocalMessage() throws {
        let h = makeHub(rooms: ["lobby"])
        h._sendHook = { _ in }
        _ = try h.sendMessage(room: "lobby", text: "yo")
        let msgs = h.getMessages(room: "lobby")
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs[0].text, "yo")
    }

    func testSendMessageTooLongThrows() {
        let h = makeHub(rooms: ["lobby"])
        h._sendHook = { _ in }
        let longText = String(repeating: "x", count: h.maxMsgBodyBytes + 1)
        XCTAssertThrowsError(try h.sendMessage(room: "lobby", text: longText))
    }

    func testSendActionCBORType() throws {
        let h = makeHub(rooms: ["lobby"])
        var sent: Data? = nil
        h._sendHook = { sent = $0 }
        _ = try h.sendAction(room: "lobby", text: "waves")
        let env = try decodeSentEnv(XCTUnwrap(sent))
        guard case .uint(let t) = env[RRC.Key.type] else { return XCTFail() }
        XCTAssertEqual(Int(t), RRC.MessageType.action)
    }

    func testSendPingReturnsEightByteID() throws {
        let h = makeHub()
        h._sendHook = { _ in }
        let mid = try h.sendPing()
        XCTAssertEqual(mid.count, 8)
    }

    func testSendPingStoresPendingPing() throws {
        let h = makeHub()
        h._sendHook = { _ in }
        let mid = try h.sendPing()
        XCTAssertNotNil(h._pendingPings[mid])
    }

    func testSendCommandCBORType() throws {
        let h = makeHub()
        h._sendHook = { _ in }
        try h.sendCommand(text: "/list")
        // No assertion needed — just verify it doesn't throw
    }

    func testSendCommandNonSlashThrows() {
        let h = makeHub()
        h._sendHook = { _ in }
        XCTAssertThrowsError(try h.sendCommand(text: "list"))
    }
}

// MARK: - parseWhoNotice / parseRoomListNotice

final class RRCHubParseNoticeTests: XCTestCase {
    func testParseWhoNoticeBasic() {
        let text = "members in lobby: alice (abcdef012345), 1234567890abcdef1234567890abcdef"
        let r = RRCHub.parseWhoNotice(text)
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.room, "lobby")
        XCTAssertEqual(r?.entries.count, 2)
        XCTAssertEqual(r?.entries.first?.nick, "alice")
    }

    func testParseWhoNoticeEmpty() {
        let text = "members in lobby: (none)"
        let r = RRCHub.parseWhoNotice(text)
        XCTAssertNotNil(r)
        XCTAssertTrue(r?.entries.isEmpty ?? false)
    }

    func testParseWhoNoticeReturnsNilForUnrelated() {
        XCTAssertNil(RRCHub.parseWhoNotice("just a regular notice"))
    }

    func testParseRoomListNoticeBasic() {
        let text = """
        Registered public rooms
        lobby - General chat
        dev
        """
        let r = RRCHub.parseRoomListNotice(text)
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.count, 2)
        XCTAssertNotNil(r?["lobby"])
        XCTAssertNotNil(r?["dev"])
    }

    func testParseRoomListNoticeNoRooms() {
        let r = RRCHub.parseRoomListNotice("No public rooms registered")
        XCTAssertNotNil(r)
        XCTAssertTrue(r?.isEmpty ?? false)
    }

    func testParseRoomListNoticeReturnsNilForUnrelated() {
        XCTAssertNil(RRCHub.parseRoomListNotice("just a regular message"))
    }
}

// MARK: - History entry encode/decode

final class RRCHubHistoryEntryTests: XCTestCase {
    func testEntryForRoundTrip() {
        let h = makeHub()
        let src = Data(repeating: 0xAB, count: 8)
        let msg = RRCMessage(kind: "msg", room: "lobby", src: src,
                             nick: "alice", text: "hello", ts: 1_700_000_000_000)
        let entry = h._entryFor(msg)
        let recovered = RRCHub._msgFromEntry(room: "lobby", entry: entry)
        XCTAssertNotNil(recovered)
        XCTAssertEqual(recovered?.kind,  "msg")
        XCTAssertEqual(recovered?.text,  "hello")
        XCTAssertEqual(recovered?.nick,  "alice")
        XCTAssertEqual(recovered?.src,   src)
        XCTAssertEqual(recovered?.ts,    1_700_000_000_000)
    }

    func testEntryForPreservesMention() {
        let h = makeHub()
        var msg = RRCMessage(kind: "msg", room: "lobby", src: Data(),
                             nick: nil, text: "yo", ts: 0)
        msg.mention = true
        let recovered = RRCHub._msgFromEntry(room: "lobby", entry: h._entryFor(msg))
        XCTAssertTrue(recovered?.mention ?? false)
    }

    func testMsgFromEntryNilOnInvalidEntry() {
        XCTAssertNil(RRCHub._msgFromEntry(room: "lobby", entry: [:]))
    }

    func testPersistableRoomAllowsNormalRooms() {
        XCTAssertTrue(RRCHub._persistableRoom("lobby"))
    }

    func testPersistableRoomRejectsEmpty() {
        XCTAssertFalse(RRCHub._persistableRoom(""))
    }

    func testPersistableRoomRejectsStar() {
        XCTAssertFalse(RRCHub._persistableRoom("*"))
    }
}

// MARK: - History file persistence

final class RRCHubHistoryPersistenceTests: XCTestCase {
    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rrc_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    func testAppendAndLoadHistory() throws {
        let mgr = RRCManager(identity: Identity(), storagePath: tmpDir)
        let h = mgr.addHub(hash: Data(repeating: 0xAB, count: 16))
        _ = h.addRoom("lobby")

        let src = Data(repeating: 0x11, count: 8)
        let msg = RRCMessage(kind: "msg", room: "lobby", src: src, nick: "alice", text: "test", ts: 1000)
        h._appendHistory(room: "lobby", msg: msg)

        // Load into a fresh hub
        let mgr2 = RRCManager(identity: Identity(), storagePath: tmpDir)
        mgr2._hubs = mgr._hubs  // share hub list for path resolution
        let h2 = mgr2.addHub(hash: Data(repeating: 0xAB, count: 16))
        _ = h2.addRoom("lobby")
        h2._loadHistory()

        let msgs = h2.getMessages(room: "lobby")
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs[0].text, "test")
    }

    func testDeleteHistoryClearsFile() throws {
        let mgr = RRCManager(identity: Identity(), storagePath: tmpDir)
        let h = mgr.addHub(hash: Data(repeating: 0xAB, count: 16))
        _ = h.addRoom("lobby")
        let msg = RRCMessage(kind: "msg", room: "lobby", src: Data(), nick: nil, text: "hi", ts: 0)
        h._appendHistory(room: "lobby", msg: msg)

        let path = mgr._historyPath(hub: h, room: "lobby")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))

        h._deleteHistory(room: "lobby")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
    }
}

// MARK: - RRCManager

final class RRCManagerTests: XCTestCase {
    func testAddHubCreatesHub() {
        let mgr = makeManager()
        let h = mgr.addHub(hash: Data(repeating: 0xAB, count: 16))
        XCTAssertEqual(mgr.hubs.count, 1)
        XCTAssertEqual(h.hubHash, Data(repeating: 0xAB, count: 16))
    }

    func testAddHubDeduplicates() {
        let mgr = makeManager()
        let h1 = mgr.addHub(hash: Data(repeating: 0xAB, count: 16))
        let h2 = mgr.addHub(hash: Data(repeating: 0xAB, count: 16))
        XCTAssertTrue(h1 === h2)
        XCTAssertEqual(mgr.hubs.count, 1)
    }

    func testRemoveHub() {
        let mgr = makeManager()
        let h = mgr.addHub(hash: Data(repeating: 0xAB, count: 16))
        mgr.removeHub(h)
        XCTAssertTrue(mgr.hubs.isEmpty)
    }

    func testFindHubByHash() {
        let mgr = makeManager()
        let hash = Data(repeating: 0xCC, count: 16)
        let h = mgr.addHub(hash: hash)
        XCTAssertTrue(mgr.findHub(hash: hash) === h)
    }

    func testFindHubNilForUnknownHash() {
        let mgr = makeManager()
        XCTAssertNil(mgr.findHub(hash: Data(repeating: 0xFF, count: 16)))
    }

    func testHasUnreadFalseByDefault() {
        let mgr = makeManager()
        _ = mgr.addHub(hash: Data(repeating: 0xAB, count: 16))
        XCTAssertFalse(mgr.hasUnread)
    }

    func testHasUnreadTrueWhenRoomUnread() {
        let mgr = makeManager()
        let h = mgr.addHub(hash: Data(repeating: 0xAB, count: 16))
        _ = h.addRoom("lobby")
        h._onPacket(makePkt(type: RRC.MessageType.msg, src: makeSrc(), room: "lobby", body: .text("ping")))
        XCTAssertTrue(mgr.hasUnread)
    }

    func testSetActiveMarkReadOnHub() {
        let mgr = makeManager()
        let h = mgr.addHub(hash: Data(repeating: 0xAB, count: 16))
        _ = h.addRoom("lobby")
        h._onPacket(makePkt(type: RRC.MessageType.msg, src: makeSrc(), room: "lobby", body: .text("hi")))
        XCTAssertTrue(h.unreadRooms.contains("lobby"))
        mgr.setActive(hub: h, room: "lobby")
        XCTAssertFalse(h.unreadRooms.contains("lobby"))
    }

    func testActiveRoomForHub() {
        let mgr = makeManager()
        let h = mgr.addHub(hash: Data(repeating: 0xAB, count: 16))
        mgr.setActive(hub: h, room: "dev")
        XCTAssertEqual(mgr.activeRoomFor(hub: h), "dev")
    }

    func testActiveRoomForOtherHubIsNil() {
        let mgr = makeManager()
        let h1 = mgr.addHub(hash: Data(repeating: 0x01, count: 16))
        let h2 = mgr.addHub(hash: Data(repeating: 0x02, count: 16))
        mgr.setActive(hub: h1, room: "lobby")
        XCTAssertNil(mgr.activeRoomFor(hub: h2))
    }

    func testOnWelcomeRejoinsSavedRooms() throws {
        let mgr = makeManager()
        let h = mgr.addHub(hash: Data(repeating: 0xAB, count: 16))
        _ = h.addRoom("lobby")
        _ = h.addRoom("dev")
        var joinsSent: [String] = []
        h._sendHook = { data in
            if let env = try? decodeSentEnv(data),
               let tv = env[RRC.Key.type], case .uint(let t) = tv, Int(t) == RRC.MessageType.join,
               let rv = env[RRC.Key.room], case .text(let r) = rv {
                joinsSent.append(r)
            }
        }
        mgr._onWelcome(hub: h)
        XCTAssertTrue(joinsSent.contains("lobby"))
        XCTAssertTrue(joinsSent.contains("dev"))
    }
}

// MARK: - RRCManager persistence (save/load)

final class RRCManagerPersistenceTests: XCTestCase {
    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rrcmgr_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    func testSaveAndLoadHubs() throws {
        let mgr1 = RRCManager(identity: Identity(), storagePath: tmpDir)
        let hash = Data(repeating: 0xBB, count: 16)
        let h = mgr1.addHub(hash: hash)
        _ = h.addRoom("lobby")
        h.autoReconnect = true
        h.nickOverride = "testNick"
        mgr1.save()

        let mgr2 = RRCManager(identity: Identity(), storagePath: tmpDir)
        mgr2.load()
        XCTAssertEqual(mgr2.hubs.count, 1)
        let h2 = mgr2.hubs[0]
        XCTAssertEqual(h2.hubHash, hash)
        XCTAssertTrue(h2.rooms.contains("lobby"))
        XCTAssertTrue(h2.autoReconnect)
        XCTAssertEqual(h2.nickOverride, "testNick")
    }

    func testSaveAndLoadDestName() throws {
        let mgr1 = RRCManager(identity: Identity(), storagePath: tmpDir)
        let hash = Data(repeating: 0xCC, count: 16)
        _ = mgr1.addHub(hash: hash, destName: "custom.hub")
        mgr1.save()

        let mgr2 = RRCManager(identity: Identity(), storagePath: tmpDir)
        mgr2.load()
        XCTAssertEqual(mgr2.hubs[0].destName, "custom.hub")
    }

    func testLoadIsIdempotent() throws {
        let mgr1 = RRCManager(identity: Identity(), storagePath: tmpDir)
        let hash = Data(repeating: 0xDD, count: 16)
        _ = mgr1.addHub(hash: hash)
        mgr1.save()

        let mgr2 = RRCManager(identity: Identity(), storagePath: tmpDir)
        mgr2.load()
        mgr2.load()  // second load should be a no-op
        XCTAssertEqual(mgr2.hubs.count, 1)
    }
}

// MARK: - RRCHub history behaviour (Phase 22)
// Tests for _perRoomCap, _filterHistory, _ephemeralNoticesTimeout, _cleanHistory,
// per-room cap trimming in _recordMessage/_recordSystem, and _loadHistory filter+cap.

final class RRCHubHistoryBehaviorTests: XCTestCase {

    // ------------------------------------------------------------------ _perRoomCap

    func testPerRoomCapNilByDefault() {
        // No manager override → cap is nil (no limit)
        let h = makeHub()
        XCTAssertNil(h._perRoomCap())
    }

    func testPerRoomCapFromManagerOverride() {
        let mgr = makeManager()
        let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
        mgr._rrcHistoryPerRoomCapOverride = 5
        XCTAssertEqual(h._perRoomCap(), 5)
    }

    func testPerRoomCapZeroMeansNil() {
        let mgr = makeManager()
        let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
        mgr._rrcHistoryPerRoomCapOverride = 0
        XCTAssertNil(h._perRoomCap())
    }

    func testPerRoomCapNegativeMeansNil() {
        let mgr = makeManager()
        let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
        mgr._rrcHistoryPerRoomCapOverride = -1
        XCTAssertNil(h._perRoomCap())
    }

    // ----------------------------------------------------------------- _filterHistory

    func testFilterHistoryDefaultsTrue() {
        let h = makeHub()
        XCTAssertTrue(h._filterHistory())
    }

    func testFilterHistoryOverrideFalse() {
        let mgr = makeManager()
        let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
        mgr._rrcFilterLoadedHistoryOverride = false
        XCTAssertFalse(h._filterHistory())
    }

    // -------------------------------------------------- _ephemeralNoticesTimeout

    func testEphemeralNoticesTimeoutDefaultIs600() {
        let h = makeHub()
        XCTAssertEqual(h._ephemeralNoticesTimeout(), 600.0)
    }

    func testEphemeralNoticesTimeoutOverride() {
        let mgr = makeManager()
        let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
        mgr._rrcEphemeralNoticesTimeoutOverride = 300.0
        XCTAssertEqual(h._ephemeralNoticesTimeout(), 300.0)
    }

    // ----------------------------------------- _recordMessage cap trimming

    func testRecordMessageCapTruncatesBuffer() {
        let mgr = makeManager()
        let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
        mgr._rrcHistoryPerRoomCapOverride = 3
        _ = h.addRoom("test")
        for i in 0..<5 {
            let ts = Int64(Date().timeIntervalSince1970 * 1000) + Int64(i)
            let msg = RRCMessage(kind: "msg", room: "test", src: makeSrc(UInt8(i)),
                                  nick: "n\(i)", text: "msg\(i)", ts: ts)
            h._recordMessage(msg)
        }
        let msgs = h.getMessages(room: "test")
        XCTAssertEqual(msgs.count, 3, "buffer should be capped at 3")
        // Most recent 3: msg2, msg3, msg4
        XCTAssertEqual(msgs[0].text, "msg2")
        XCTAssertEqual(msgs[2].text, "msg4")
    }

    func testRecordSystemCapTruncatesBuffer() {
        let mgr = makeManager()
        let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
        mgr._rrcHistoryPerRoomCapOverride = 2
        _ = h.addRoom("sys")
        for i in 0..<4 { h._recordSystem(room: "sys", text: "s\(i)") }
        XCTAssertEqual(h.getMessages(room: "sys").count, 2)
    }

    // -------------------------------------- _loadHistory filter + cap

    func testLoadHistoryFiltersSystemMessages() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rrc_lh_filter_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Writer: append 1 "msg" + 1 "system" entry via _appendHistory
        let wMgr = RRCManager(identity: Identity(), storagePath: dir)
        let wHub = wMgr.addHub(hash: Data(repeating: 0xAB, count: 16))
        _ = wHub.addRoom("gr")
        let baseTs = Int64(Date().timeIntervalSince1970 * 1000)
        wHub._appendHistory(room: "gr",
            msg: RRCMessage(kind: "msg",    room: "gr", src: nil, nick: nil, text: "hello",  ts: baseTs))
        wHub._appendHistory(room: "gr",
            msg: RRCMessage(kind: "system", room: "gr", src: nil, nick: nil, text: "joined", ts: baseTs + 1))

        // Reader: filter = true (default) — system messages should be dropped
        let rMgr = RRCManager(identity: Identity(), storagePath: dir)
        let rHub = rMgr.addHub(hash: Data(repeating: 0xAB, count: 16))
        _ = rHub.addRoom("gr")
        rHub._loadHistory()

        let msgs = rHub.getMessages(room: "gr")
        XCTAssertEqual(msgs.count, 1, "system message should be filtered on load")
        XCTAssertEqual(msgs.first?.text, "hello")
    }

    func testLoadHistoryDoesNotFilterWhenFalse() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rrc_lh_nofilter_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Writer: append 1 "msg" + 1 "system" + 1 "notice" entry
        let wMgr = RRCManager(identity: Identity(), storagePath: dir)
        let wHub = wMgr.addHub(hash: Data(repeating: 0xAB, count: 16))
        _ = wHub.addRoom("gr")
        let baseTs = Int64(Date().timeIntervalSince1970 * 1000)
        for (i, kind) in ["msg", "system", "notice"].enumerated() {
            wHub._appendHistory(room: "gr",
                msg: RRCMessage(kind: kind, room: "gr", src: nil, nick: nil,
                                 text: kind + "_text", ts: baseTs + Int64(i)))
        }

        // Reader: filter = false → all 3 entries should load
        let rMgr = RRCManager(identity: Identity(), storagePath: dir)
        rMgr._rrcFilterLoadedHistoryOverride = false
        let rHub = rMgr.addHub(hash: Data(repeating: 0xAB, count: 16))
        _ = rHub.addRoom("gr")
        rHub._loadHistory()

        XCTAssertEqual(rHub.getMessages(room: "gr").count, 3,
                       "all 3 kinds should load when filter=false")
    }

    func testLoadHistoryAppliesPerRoomCap() throws {
        // Use UUID-named temp dir (same pattern as other persistence tests)
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rrc_lh_cap_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Writer manager: append 5 messages to the history file via the known-good _appendHistory
        let wMgr = RRCManager(identity: Identity(), storagePath: dir)
        let wHub = wMgr.addHub(hash: Data(repeating: 0xAB, count: 16))
        _ = wHub.addRoom("cap")
        let baseTs = Int64(Date().timeIntervalSince1970 * 1000)
        for i in 0..<5 {
            let msg = RRCMessage(kind: "msg", room: "cap", src: nil, nick: nil,
                                  text: "m\(i)", ts: baseTs + Int64(i * 100))
            wHub._appendHistory(room: "cap", msg: msg)
        }

        // Reader manager: load with cap=2 and no filter → keep last 2 entries
        let rMgr = RRCManager(identity: Identity(), storagePath: dir)
        rMgr._rrcHistoryPerRoomCapOverride = 2
        rMgr._rrcFilterLoadedHistoryOverride = false
        let rHub = rMgr.addHub(hash: Data(repeating: 0xAB, count: 16))
        _ = rHub.addRoom("cap")
        rHub._loadHistory()

        let msgs = rHub.getMessages(room: "cap")
        XCTAssertEqual(msgs.count, 2, "only the 2 most recent should be kept")
        guard msgs.count == 2 else { return }
        XCTAssertEqual(msgs[0].text, "m3")
        XCTAssertEqual(msgs[1].text, "m4")
    }

    /// Regression test for Python NomadNet RRC commit bec78cf:
    /// "RRC: filter and *then* apply the history cap".
    /// If a room has 3 msgs + 2 system entries and cap=2, after filtering
    /// 3 real messages remain; cap should keep the last 2 of those, not 2
    /// of the 5 pre-filter entries.
    func testLoadHistoryFiltersBeforeApplyingCap() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rrc_lh_filtercap_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let wMgr = RRCManager(identity: Identity(), storagePath: dir)
        let wHub = wMgr.addHub(hash: Data(repeating: 0xAC, count: 16))
        _ = wHub.addRoom("fc")
        let baseTs = Int64(Date().timeIntervalSince1970 * 1000)
        // Write: msg0, system, msg1, system, msg2
        let entries: [(String, String)] = [("msg", "m0"), ("system", "s1"),
                                            ("msg", "m1"), ("system", "s2"),
                                            ("msg", "m2")]
        for (i, (kind, text)) in entries.enumerated() {
            wHub._appendHistory(room: "fc",
                msg: RRCMessage(kind: kind, room: "fc", src: nil, nick: nil,
                                text: text, ts: baseTs + Int64(i)))
        }

        // Load with filter=true (drops system) and cap=2 → should keep msg1, msg2
        let rMgr = RRCManager(identity: Identity(), storagePath: dir)
        rMgr._rrcFilterLoadedHistoryOverride = true
        rMgr._rrcHistoryPerRoomCapOverride  = 2
        let rHub = rMgr.addHub(hash: Data(repeating: 0xAC, count: 16))
        _ = rHub.addRoom("fc")
        rHub._loadHistory()

        let msgs = rHub.getMessages(room: "fc")
        XCTAssertEqual(msgs.count, 2, "cap applied after filter: expect 2 msgs")
        XCTAssertEqual(msgs.first?.text, "m1")
        XCTAssertEqual(msgs.last?.text,  "m2")
    }

    // ------------------------------------------------- _cleanHistory

    func testCleanHistoryRemovesOldEphemeralMessages() {
        let mgr = makeManager()
        let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
        mgr._rrcEphemeralNoticesTimeoutOverride = 1.0  // 1-second lifetime
        _ = h.addRoom("cr")
        // Inject a system message with a timestamp 10 seconds in the past
        let oldTs = Int64((Date().timeIntervalSince1970 - 10.0) * 1000)
        h._testInjectMessage(room: "cr",
                             msg: RRCMessage(kind: "system", room: "cr",
                                             src: nil, nick: nil, text: "old", ts: oldTs))
        h._testResetHistoryClean()
        h._cleanHistory()
        XCTAssertTrue(h.getMessages(room: "cr").isEmpty,
                      "old system message should have been cleaned")
    }

    func testCleanHistoryKeepsRecentEphemeralMessages() {
        let mgr = makeManager()
        let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
        mgr._rrcEphemeralNoticesTimeoutOverride = 600.0
        _ = h.addRoom("kr")
        let recentTs = Int64(Date().timeIntervalSince1970 * 1000)
        h._testInjectMessage(room: "kr",
                             msg: RRCMessage(kind: "system", room: "kr",
                                             src: nil, nick: nil, text: "new", ts: recentTs))
        h._testResetHistoryClean()
        h._cleanHistory()
        XCTAssertEqual(h.getMessages(room: "kr").count, 1,
                       "recent system message should not be cleaned")
    }

    func testCleanHistoryDoesNotCleanNonEphemeralMessages() {
        let mgr = makeManager()
        let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
        mgr._rrcEphemeralNoticesTimeoutOverride = 0.001  // very short — everything old gets swept
        _ = h.addRoom("ne")
        // A "msg" kind message with a very old timestamp — should NOT be swept
        let oldTs = Int64((Date().timeIntervalSince1970 - 9999.0) * 1000)
        h._testInjectMessage(room: "ne",
                             msg: RRCMessage(kind: "msg", room: "ne",
                                             src: nil, nick: nil, text: "keep", ts: oldTs))
        h._testResetHistoryClean()
        h._cleanHistory()
        XCTAssertEqual(h.getMessages(room: "ne").count, 1,
                       "non-ephemeral 'msg' kind must never be removed by _cleanHistory")
    }

    func testCleanHistoryRespectsCooldown() {
        let mgr = makeManager()
        let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
        mgr._rrcEphemeralNoticesTimeoutOverride = 0.001  // so old messages are swept
        _ = h.addRoom("cool")
        let oldTs = Int64((Date().timeIntervalSince1970 - 10.0) * 1000)

        // First call: _lastHistoryClean = .distantPast → runs, sweeps "x", updates clock
        h._testInjectMessage(room: "cool",
                             msg: RRCMessage(kind: "system", room: "cool",
                                             src: nil, nick: nil, text: "x", ts: oldTs))
        h._cleanHistory()

        // Inject "x2" (also old) immediately after — clock just updated, cooldown not expired
        h._testInjectMessage(room: "cool",
                             msg: RRCMessage(kind: "system", room: "cool",
                                             src: nil, nick: nil, text: "x2", ts: oldTs))
        h._cleanHistory()  // second call: < 5s since last → skipped

        XCTAssertEqual(h.getMessages(room: "cool").count, 1,
                       "cooldown prevents immediate re-sweep; x2 should still be present")
    }

    // ------------------------------------------ class-level constants

    func testCleanHistoryIntervalConstant() {
        XCTAssertEqual(RRCHub.cleanHistoryInterval, 5.0)
    }

    func testSysNoticeTimeoutConstant() {
        XCTAssertEqual(RRCHub.sysNoticeTimeout, 600.0)
    }
}
