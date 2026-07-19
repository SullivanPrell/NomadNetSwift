import XCTest
import CryptoKit
@testable import NomadNet
import ReticulumSwift

/// Tests for the RRC hub→client resource-receive path (NomadNet 1.2.8, commits
/// f07a035 / 510d476): accept-by-size, sha256 verification, and routing of MOTD /
/// `/who` / `/list` notices delivered as a resource transfer through the same parser
/// as the packet path.
final class RRCResourceReceiveTests: XCTestCase {

    private func makeHub(rooms: [String] = []) -> (RRCHub, RRCManager) {
        let mgr = RRCManager(identity: Identity())
        let h = mgr.addHub(hash: Data(repeating: 0xCD, count: 16))
        for r in rooms { _ = h.addRoom(r) }
        return (h, mgr)
    }

    /// Deliver a T_RESOURCE_ENVELOPE packet so the hub stores a ResourceExpectation
    /// (mirrors a hub announcing it is about to send a resource).
    private func storeExpectation(_ h: RRCHub, rid: Data, kind: String, size: Int,
                                  room: String? = nil, sha256: Data? = nil,
                                  encoding: String = "utf-8") {
        var bodyPairs: [(CBOR.Value, CBOR.Value)] = [
            (.uint(UInt64(RRC.ResField.id)),       .bytes(rid)),
            (.uint(UInt64(RRC.ResField.kind)),     .text(kind)),
            (.uint(UInt64(RRC.ResField.size)),     .uint(UInt64(size))),
            (.uint(UInt64(RRC.ResField.encoding)), .text(encoding)),
        ]
        if let sha = sha256 { bodyPairs.append((.uint(UInt64(RRC.ResField.sha256)), .bytes(sha))) }
        var pairs: [(CBOR.Value, CBOR.Value)] = [
            (.uint(UInt64(RRC.Key.version)), .uint(UInt64(RRC.version))),
            (.uint(UInt64(RRC.Key.type)),    .uint(UInt64(RRC.MessageType.resourceEnvelope))),
            (.uint(UInt64(RRC.Key.id)),      .bytes(Data((0..<8).map { _ in UInt8.random(in: 0...255) }))),
            (.uint(UInt64(RRC.Key.ts)),      .uint(UInt64(Date().timeIntervalSince1970 * 1000))),
            (.uint(UInt64(RRC.Key.src)),     .bytes(Data(repeating: 0xAB, count: 16))),
        ]
        if let room { pairs.append((.uint(UInt64(RRC.Key.room)), .text(room))) }
        pairs.append((.uint(UInt64(RRC.Key.body)), .map(bodyPairs)))
        h._onPacket(CBOR.encode(.map(pairs)))
    }

    // MARK: - _resourceAdvertised (size cap)

    func testResourceAdvertisedAcceptsWithinCap() {
        let (h, _) = makeHub()
        XCTAssertTrue(h._resourceAdvertised(size: 1000))
        XCTAssertTrue(h._resourceAdvertised(size: RRCHub.defaultMaxAcceptedResourceSize)) // at cap
    }

    func testResourceAdvertisedRejectsOverCap() {
        let (h, _) = makeHub()
        XCTAssertFalse(h._resourceAdvertised(size: RRCHub.defaultMaxAcceptedResourceSize + 1))
    }

    func testResourceAdvertisedRejectsWhenCapDisabled() {
        let (h, mgr) = makeHub()
        mgr.maxAcceptedResourceSize = 0
        XCTAssertFalse(h._resourceAdvertised(size: 1))
    }

    func testResourceAdvertisedHonorsConfiguredCap() {
        let (h, mgr) = makeHub()
        mgr.maxAcceptedResourceSize = 500
        XCTAssertTrue(h._resourceAdvertised(size: 500))
        XCTAssertFalse(h._resourceAdvertised(size: 501))
    }

    // MARK: - _resourceConcluded (routing)

    func testResourceConcludedMOTD() {
        let (h, _) = makeHub()
        let text = "Welcome to the hub, delivered by resource!"
        let payload = Data(text.utf8)
        storeExpectation(h, rid: Data([1]), kind: RRC.ResKind.motd, size: payload.count)
        h._resourceConcluded(payload: payload)
        XCTAssertEqual(h.motd, text)
    }

    func testResourceConcludedWhoNoticeUpdatesMembers() {
        let (h, _) = makeHub(rooms: ["lobby"])
        let text = "members in lobby: alice (abcdef012345), 1234567890abcdef1234567890abcdef"
        let payload = Data(text.utf8)
        storeExpectation(h, rid: Data([2]), kind: RRC.ResKind.notice, size: payload.count, room: "lobby")
        h._resourceConcluded(payload: payload)
        XCTAssertFalse((h.members["lobby"] ?? []).isEmpty,
                       "a /who reply delivered by resource must populate members")
    }

    func testResourceConcludedListNoticeUpdatesRooms() {
        let (h, _) = makeHub()
        let text = "Registered public rooms\nlobby - General chat\ndev"
        let payload = Data(text.utf8)
        storeExpectation(h, rid: Data([3]), kind: RRC.ResKind.notice, size: payload.count)
        h._resourceConcluded(payload: payload)
        XCTAssertNotNil(h.availableRooms["lobby"])
        XCTAssertNotNil(h.availableRooms["dev"])
    }

    func testResourceConcludedPlainNoticeRecorded() {
        let (h, _) = makeHub(rooms: ["lobby"])
        let text = "server maintenance in 5 minutes"
        let payload = Data(text.utf8)
        storeExpectation(h, rid: Data([4]), kind: RRC.ResKind.notice, size: payload.count, room: "lobby")
        h._resourceConcluded(payload: payload)
        XCTAssertTrue(h.getMessages(room: "lobby").contains { $0.kind == "notice" && $0.text == text })
    }

    func testResourceConcludedBlobIgnored() {
        let (h, _) = makeHub()
        let payload = Data(repeating: 0x11, count: 64)
        storeExpectation(h, rid: Data([5]), kind: RRC.ResKind.blob, size: payload.count)
        h._resourceConcluded(payload: payload)
        XCTAssertNil(h.motd)
    }

    // MARK: - matching / integrity

    func testResourceConcludedSizeMismatchIgnored() {
        let (h, _) = makeHub()
        let payload = Data("Welcome!".utf8)
        // Expectation size deliberately wrong → no match → treated as blob → ignored.
        storeExpectation(h, rid: Data([6]), kind: RRC.ResKind.motd, size: payload.count + 99)
        h._resourceConcluded(payload: payload)
        XCTAssertNil(h.motd)
    }

    func testResourceConcludedShaMismatchDropped() {
        let (h, _) = makeHub()
        let payload = Data("Welcome!".utf8)
        let wrongSha = Data(repeating: 0x00, count: 32)
        storeExpectation(h, rid: Data([7]), kind: RRC.ResKind.motd, size: payload.count, sha256: wrongSha)
        h._resourceConcluded(payload: payload)
        XCTAssertNil(h.motd, "a payload whose sha256 does not match the advertisement must be dropped")
    }

    func testResourceConcludedShaMatchAccepted() {
        let (h, _) = makeHub()
        let text = "Verified MOTD"
        let payload = Data(text.utf8)
        let sha = Data(SHA256.hash(data: payload))
        storeExpectation(h, rid: Data([8]), kind: RRC.ResKind.motd, size: payload.count, sha256: sha)
        h._resourceConcluded(payload: payload)
        XCTAssertEqual(h.motd, text)
    }
}
