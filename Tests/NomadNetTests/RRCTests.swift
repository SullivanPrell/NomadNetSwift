import XCTest
@testable import NomadNet

// MARK: - RRC constants

final class RRCConstantsTests: XCTestCase {

    // ── RRC protocol version ──────────────────────────────────────────────────
    func testRRCVersion()         { XCTAssertEqual(RRC.version,     1) }

    // ── Envelope field keys (Python: K_V, K_T, K_ID, K_TS, K_SRC, ...) ───────
    func testKeyVersion()  { XCTAssertEqual(RRC.Key.version, 0) }
    func testKeyType()     { XCTAssertEqual(RRC.Key.type,    1) }
    func testKeyID()       { XCTAssertEqual(RRC.Key.id,      2) }
    func testKeyTS()       { XCTAssertEqual(RRC.Key.ts,      3) }
    func testKeySrc()      { XCTAssertEqual(RRC.Key.src,     4) }
    func testKeyRoom()     { XCTAssertEqual(RRC.Key.room,    5) }
    func testKeyBody()     { XCTAssertEqual(RRC.Key.body,    6) }
    func testKeyNick()     { XCTAssertEqual(RRC.Key.nick,    7) }

    // ── Message type constants (Python: T_HELLO, T_WELCOME, ...) ─────────────
    func testTHello()      { XCTAssertEqual(RRC.MessageType.hello,    1)  }
    func testTWelcome()    { XCTAssertEqual(RRC.MessageType.welcome,  2)  }

    func testTJoin()       { XCTAssertEqual(RRC.MessageType.join,     10) }
    func testTJoined()     { XCTAssertEqual(RRC.MessageType.joined,   11) }
    func testTPart()       { XCTAssertEqual(RRC.MessageType.part,     12) }
    func testTParted()     { XCTAssertEqual(RRC.MessageType.parted,   13) }

    func testTMsg()        { XCTAssertEqual(RRC.MessageType.msg,      20) }
    func testTNotice()     { XCTAssertEqual(RRC.MessageType.notice,   21) }
    func testTAction()     { XCTAssertEqual(RRC.MessageType.action,   22) }

    func testTPing()       { XCTAssertEqual(RRC.MessageType.ping,     30) }
    func testTPong()       { XCTAssertEqual(RRC.MessageType.pong,     31) }

    func testTError()      { XCTAssertEqual(RRC.MessageType.error,    40) }

    func testTResourceEnvelope() { XCTAssertEqual(RRC.MessageType.resourceEnvelope, 50) }

    // ── HELLO body indices ────────────────────────────────────────────────────
    func testBHelloName()  { XCTAssertEqual(RRC.HelloField.name,  0) }
    func testBHelloVer()   { XCTAssertEqual(RRC.HelloField.ver,   1) }
    func testBHelloCaps()  { XCTAssertEqual(RRC.HelloField.caps,  2) }

    // ── WELCOME body indices ─────────────────────────────────────────────────
    func testBWelcomeHub()    { XCTAssertEqual(RRC.WelcomeField.hub,    0) }
    func testBWelcomeVer()    { XCTAssertEqual(RRC.WelcomeField.ver,    1) }
    func testBWelcomeCaps()   { XCTAssertEqual(RRC.WelcomeField.caps,   2) }
    func testBWelcomeLimits() { XCTAssertEqual(RRC.WelcomeField.limits, 3) }

    // ── Capability indices ────────────────────────────────────────────────────
    func testCapResourceEnvelope() { XCTAssertEqual(RRC.Cap.resourceEnvelope, 0) }
    func testCapAction()           { XCTAssertEqual(RRC.Cap.action,           1) }

    // ── Default limits ────────────────────────────────────────────────────────
    func testDefaultDestName()        { XCTAssertEqual(RRC.defaultDestName,     "rrc.hub")  }
    func testDefaultMaxNickBytes()    { XCTAssertEqual(RRC.defaultMaxNickBytes,    32) }
    func testDefaultMaxRoomBytes()    { XCTAssertEqual(RRC.defaultMaxRoomBytes,    64) }
    func testDefaultMaxMsgBytes()     { XCTAssertEqual(RRC.defaultMaxMsgBytes,    350) }
    func testDefaultMaxRooms()        { XCTAssertEqual(RRC.defaultMaxRooms,        32) }
    func testDefaultRatePerMinute()   { XCTAssertEqual(RRC.defaultRatePerMinute,  240) }
}

// MARK: - RRCEnvelope construction (Python: _make_envelope)

final class RRCEnvelopeTests: XCTestCase {

    private let fakeSrc = Data(repeating: 0xAB, count: 10)

    func testMakeEnvelopeHasVersion() {
        let env = RRC.makeEnvelope(type: RRC.MessageType.msg, src: fakeSrc)
        XCTAssertEqual(env.version, RRC.version)
    }

    func testMakeEnvelopeHasCorrectType() {
        let env = RRC.makeEnvelope(type: RRC.MessageType.join, src: fakeSrc)
        XCTAssertEqual(env.type, RRC.MessageType.join)
    }

    func testMakeEnvelopeHasSrc() {
        let env = RRC.makeEnvelope(type: RRC.MessageType.msg, src: fakeSrc)
        XCTAssertEqual(env.src, fakeSrc)
    }

    func testMakeEnvelopeHasIDOfEightBytes() {
        let env = RRC.makeEnvelope(type: RRC.MessageType.msg, src: fakeSrc)
        XCTAssertEqual(env.id.count, 8)
    }

    func testMakeEnvelopeIDsAreDifferent() {
        let env1 = RRC.makeEnvelope(type: RRC.MessageType.msg, src: fakeSrc)
        let env2 = RRC.makeEnvelope(type: RRC.MessageType.msg, src: fakeSrc)
        XCTAssertNotEqual(env1.id, env2.id)
    }

    func testMakeEnvelopeHasTimestampInMilliseconds() {
        let before = Int64(Date().timeIntervalSince1970 * 1000) - 100
        let env = RRC.makeEnvelope(type: RRC.MessageType.msg, src: fakeSrc)
        let after  = Int64(Date().timeIntervalSince1970 * 1000) + 100
        XCTAssertGreaterThanOrEqual(env.ts, before)
        XCTAssertLessThanOrEqual(env.ts, after)
    }

    func testMakeEnvelopeOptionalRoomNilByDefault() {
        let env = RRC.makeEnvelope(type: RRC.MessageType.msg, src: fakeSrc)
        XCTAssertNil(env.room)
    }

    func testMakeEnvelopeOptionalRoomSet() {
        let env = RRC.makeEnvelope(type: RRC.MessageType.join, src: fakeSrc, room: "lobby")
        XCTAssertEqual(env.room, "lobby")
    }

    func testMakeEnvelopeOptionalBodySet() {
        let env = RRC.makeEnvelope(type: RRC.MessageType.msg, src: fakeSrc, body: "hello world")
        XCTAssertEqual(env.body, "hello world")
    }

    func testMakeEnvelopeOptionalNickSet() {
        let env = RRC.makeEnvelope(type: RRC.MessageType.msg, src: fakeSrc, nick: "alice")
        XCTAssertEqual(env.nick, "alice")
    }

    func testMakeEnvelopeCanProvideExplicitMID() {
        let mid = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        let env = RRC.makeEnvelope(type: RRC.MessageType.msg, src: fakeSrc, mid: mid)
        XCTAssertEqual(env.id, mid)
    }

    func testMakeEnvelopeCanProvideExplicitTimestamp() {
        let ts: Int64 = 1_700_000_000_000
        let env = RRC.makeEnvelope(type: RRC.MessageType.msg, src: fakeSrc, ts: ts)
        XCTAssertEqual(env.ts, ts)
    }
}

// MARK: - RRCMessage

final class RRCMessageTests: XCTestCase {

    func testRRCMessageStoresKind() {
        let msg = RRCMessage(kind: "msg", room: "lobby", src: Data(),
                              nick: "alice", text: "hi", ts: 1234)
        XCTAssertEqual(msg.kind, "msg")
    }

    func testRRCMessageStoresRoom() {
        let msg = RRCMessage(kind: "msg", room: "lobby", src: Data(),
                              nick: "alice", text: "hi", ts: 1234)
        XCTAssertEqual(msg.room, "lobby")
    }

    func testRRCMessageStoresNick() {
        let msg = RRCMessage(kind: "action", room: "dev", src: Data(),
                              nick: "bob", text: "waves", ts: 9999)
        XCTAssertEqual(msg.nick, "bob")
    }

    func testRRCMessageStoresText() {
        let msg = RRCMessage(kind: "msg", room: "lobby", src: Data(),
                              nick: "alice", text: "hello!", ts: 1234)
        XCTAssertEqual(msg.text, "hello!")
    }

    func testRRCMessageStoresSrc() {
        let src = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let msg = RRCMessage(kind: "msg", room: "lobby", src: src,
                              nick: "alice", text: "hi", ts: 1234)
        XCTAssertEqual(msg.src, src)
    }

    func testRRCMessageStoresTimestamp() {
        let ts: Int64 = 1_700_000_000_000
        let msg = RRCMessage(kind: "msg", room: "lobby", src: Data(),
                              nick: "alice", text: "hi", ts: ts)
        XCTAssertEqual(msg.ts, ts)
    }

    func testRRCMessageDefaultMentionIsFalse() {
        let msg = RRCMessage(kind: "msg", room: "lobby", src: Data(),
                              nick: "alice", text: "hi", ts: 0)
        XCTAssertFalse(msg.mention)
    }
}

// MARK: - CBOR encode/decode (used by RRC for wire serialisation)

final class CBORTests: XCTestCase {

    // ── Unsigned integers ────────────────────────────────────────────────────

    func testEncodeSmallUint() {
        // 0-23 encoded as single byte: major type 0 | value
        XCTAssertEqual(CBOR.encode(.uint(0)),   Data([0x00]))
        XCTAssertEqual(CBOR.encode(.uint(1)),   Data([0x01]))
        XCTAssertEqual(CBOR.encode(.uint(23)),  Data([0x17]))
    }

    func testEncodeUint24To255() {
        // 24 → 0x18 0x18; 255 → 0x18 0xFF
        XCTAssertEqual(CBOR.encode(.uint(24)),  Data([0x18, 0x18]))
        XCTAssertEqual(CBOR.encode(.uint(255)), Data([0x18, 0xFF]))
    }

    func testEncodeUint256To65535() {
        // 256 → 0x19 0x01 0x00
        XCTAssertEqual(CBOR.encode(.uint(256)),   Data([0x19, 0x01, 0x00]))
        XCTAssertEqual(CBOR.encode(.uint(65535)), Data([0x19, 0xFF, 0xFF]))
    }

    func testEncodeUint32Bit() {
        // 65536 = 0x00010000 → 0x1a 0x00 0x01 0x00 0x00
        XCTAssertEqual(CBOR.encode(.uint(65536)), Data([0x1A, 0x00, 0x01, 0x00, 0x00]))
    }

    // ── Byte strings ──────────────────────────────────────────────────────────

    func testEncodeEmptyBytes() {
        XCTAssertEqual(CBOR.encode(.bytes(Data())), Data([0x40]))
    }

    func testEncodeByteString() {
        // 2 bytes → 0x42 + bytes
        let bs = Data([0xAB, 0xCD])
        XCTAssertEqual(CBOR.encode(.bytes(bs)), Data([0x42, 0xAB, 0xCD]))
    }

    // ── Text strings ──────────────────────────────────────────────────────────

    func testEncodeEmptyText() {
        XCTAssertEqual(CBOR.encode(.text("")), Data([0x60]))
    }

    func testEncodeTextHello() {
        // "hello" = 5 bytes → 0x65 + UTF-8
        let expected = Data([0x65, 0x68, 0x65, 0x6C, 0x6C, 0x6F])
        XCTAssertEqual(CBOR.encode(.text("hello")), expected)
    }

    // ── Maps ──────────────────────────────────────────────────────────────────

    func testEncodeEmptyMap() {
        XCTAssertEqual(CBOR.encode(.map([])), Data([0xA0]))
    }

    func testEncodeOneEntryMap() {
        // {0: 1} → 0xa1 0x00 0x01
        let m: [(CBOR.Value, CBOR.Value)] = [(.uint(0), .uint(1))]
        XCTAssertEqual(CBOR.encode(.map(m)), Data([0xA1, 0x00, 0x01]))
    }

    // ── Null / bool ───────────────────────────────────────────────────────────

    func testEncodeNull() {
        XCTAssertEqual(CBOR.encode(.null), Data([0xF6]))
    }

    func testEncodeTrue() {
        XCTAssertEqual(CBOR.encode(.bool(true)),  Data([0xF5]))
    }

    func testEncodeFalse() {
        XCTAssertEqual(CBOR.encode(.bool(false)), Data([0xF4]))
    }

    // ── Round-trip decode ─────────────────────────────────────────────────────

    func testDecodeUint() throws {
        let data = CBOR.encode(.uint(42))
        let v = try CBOR.decode(data)
        guard case .uint(let n) = v else { return XCTFail("expected uint") }
        XCTAssertEqual(n, 42)
    }

    func testDecodeByteString() throws {
        let bytes = Data([0xDE, 0xAD])
        let data = CBOR.encode(.bytes(bytes))
        let v = try CBOR.decode(data)
        guard case .bytes(let b) = v else { return XCTFail("expected bytes") }
        XCTAssertEqual(b, bytes)
    }

    func testDecodeTextString() throws {
        let data = CBOR.encode(.text("rrc"))
        let v = try CBOR.decode(data)
        guard case .text(let t) = v else { return XCTFail("expected text") }
        XCTAssertEqual(t, "rrc")
    }

    func testDecodeMap() throws {
        let m: [(CBOR.Value, CBOR.Value)] = [(.uint(1), .text("hello"))]
        let data = CBOR.encode(.map(m))
        let v = try CBOR.decode(data)
        guard case .map(let pairs) = v else { return XCTFail("expected map") }
        XCTAssertEqual(pairs.count, 1)
        guard case .uint(let k) = pairs[0].0 else { return XCTFail("expected uint key") }
        XCTAssertEqual(k, 1)
        guard case .text(let s) = pairs[0].1 else { return XCTFail("expected text value") }
        XCTAssertEqual(s, "hello")
    }

    func testDecodeNull() throws {
        let data = CBOR.encode(.null)
        let v = try CBOR.decode(data)
        guard case .null = v else { return XCTFail("expected null") }
    }

    func testDecodeBool() throws {
        let trueData  = CBOR.encode(.bool(true))
        let falseData = CBOR.encode(.bool(false))
        guard case .bool(true)  = try CBOR.decode(trueData)  else { return XCTFail() }
        guard case .bool(false) = try CBOR.decode(falseData) else { return XCTFail() }
    }
}

// MARK: - RRC wire encode/decode (envelope → CBOR bytes)

final class RRCWireTests: XCTestCase {

    private let fakeSrc = Data(repeating: 0x42, count: 10)

    func testEnvelopeRoundTrip() throws {
        let env = RRC.makeEnvelope(type: RRC.MessageType.msg, src: fakeSrc, room: "lobby", body: "hi", nick: "alice")
        let data = try RRC.encode(env)
        let decoded = try RRC.decode(data)
        XCTAssertEqual(decoded.version, env.version)
        XCTAssertEqual(decoded.type,    env.type)
        XCTAssertEqual(decoded.src,     env.src)
        XCTAssertEqual(decoded.room,    env.room)
        XCTAssertEqual(decoded.body,    env.body)
        XCTAssertEqual(decoded.nick,    env.nick)
        XCTAssertEqual(decoded.id,      env.id)
        XCTAssertEqual(decoded.ts,      env.ts)
    }

    func testEnvelopeWithoutOptionalFields() throws {
        let env = RRC.makeEnvelope(type: RRC.MessageType.ping, src: fakeSrc)
        let data = try RRC.encode(env)
        let decoded = try RRC.decode(data)
        XCTAssertEqual(decoded.type, RRC.MessageType.ping)
        XCTAssertNil(decoded.room)
        XCTAssertNil(decoded.body)
        XCTAssertNil(decoded.nick)
    }
}
