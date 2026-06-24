import XCTest
@testable import NomadNet

// MARK: - DirectoryEntry creation

final class DirectoryEntryCreationTests: XCTestCase {

    private let validHash = Data(repeating: 0x01, count: 10)   // 10 bytes = truncated hash

    func testEntryStoresSourceHash() {
        let e = DirectoryEntry(sourceHash: validHash, displayName: "Alice")
        XCTAssertEqual(e.sourceHash, validHash)
    }

    func testEntryStoresDisplayName() {
        let e = DirectoryEntry(sourceHash: validHash, displayName: "Alice")
        XCTAssertEqual(e.displayName, "Alice")
    }

    func testEntryDefaultTrustLevelIsUnknown() {
        let e = DirectoryEntry(sourceHash: validHash, displayName: "Bob")
        XCTAssertEqual(e.trustLevel, DirectoryEntry.TrustLevel.unknown)
    }

    func testEntryDefaultHostsNodeIsFalse() {
        let e = DirectoryEntry(sourceHash: validHash, displayName: nil)
        XCTAssertFalse(e.hostsNode)
    }

    func testEntryDefaultPreferredDeliveryIsDirect() {
        let e = DirectoryEntry(sourceHash: validHash, displayName: nil)
        XCTAssertEqual(e.preferredDelivery, DirectoryEntry.Delivery.direct)
    }

    func testEntryDefaultIdentifyIsFalse() {
        let e = DirectoryEntry(sourceHash: validHash, displayName: nil)
        XCTAssertFalse(e.identify)
    }

    func testEntryStoresTrustLevel() {
        let e = DirectoryEntry(sourceHash: validHash, displayName: "Eve",
                               trustLevel: .trusted)
        XCTAssertEqual(e.trustLevel, .trusted)
    }

    func testEntryStoresHostsNode() {
        let e = DirectoryEntry(sourceHash: validHash, displayName: nil, hostsNode: true)
        XCTAssertTrue(e.hostsNode)
    }

    func testEntryStoresSortRank() {
        let e = DirectoryEntry(sourceHash: validHash, displayName: nil, sortRank: 5)
        XCTAssertEqual(e.sortRank, 5)
    }

    func testEntryStoresNotes() {
        let e = DirectoryEntry(sourceHash: validHash, displayName: nil, notes: "Test note")
        XCTAssertEqual(e.notes, "Test note")
    }

    func testEntryDefaultNotesIsEmptyString() {
        let e = DirectoryEntry(sourceHash: validHash, displayName: nil)
        XCTAssertEqual(e.notes, "")
    }
}

// MARK: - DirectoryEntry trust level constants

final class DirectoryEntryTrustLevelTests: XCTestCase {

    /// Python: WARNING = 0x00, UNTRUSTED = 0x01, UNKNOWN = 0x02, TRUSTED = 0xFF
    func testWarningValue()   { XCTAssertEqual(DirectoryEntry.TrustLevel.warning.rawValue,   0x00) }
    func testUntrustedValue() { XCTAssertEqual(DirectoryEntry.TrustLevel.untrusted.rawValue, 0x01) }
    func testUnknownValue()   { XCTAssertEqual(DirectoryEntry.TrustLevel.unknown.rawValue,   0x02) }
    func testTrustedValue()   { XCTAssertEqual(DirectoryEntry.TrustLevel.trusted.rawValue,   0xFF) }

    /// Python: DIRECT = 0x01, PROPAGATED = 0x02
    func testDirectDelivery()     { XCTAssertEqual(DirectoryEntry.Delivery.direct.rawValue,     0x01) }
    func testPropagatedDelivery() { XCTAssertEqual(DirectoryEntry.Delivery.propagated.rawValue, 0x02) }
}

// MARK: - NNDirectory constants

final class NNDirectoryConstantsTests: XCTestCase {

    /// Python: Directory.ANNOUNCE_STREAM_MAXLENGTH = 256
    func testAnnounceStreamMaxLength() {
        XCTAssertEqual(NNDirectory.announceStreamMaxLength, 256)
    }

    func testAspectFilter() {
        XCTAssertEqual(NNDirectory.aspectFilter, "nomadnetwork.node")
    }
}

// MARK: - NNDirectory remember / forget / find

final class NNDirectoryEntryManagementTests: XCTestCase {

    private let hash1 = Data(repeating: 0x01, count: 10)
    private let hash2 = Data(repeating: 0x02, count: 10)

    func testRememberStoresEntry() {
        let dir = NNDirectory()
        let e = DirectoryEntry(sourceHash: hash1, displayName: "Alice")
        dir.remember(e)
        XCTAssertNotNil(dir.find(hash1))
    }

    func testFindReturnsStoredEntry() {
        let dir = NNDirectory()
        let e = DirectoryEntry(sourceHash: hash1, displayName: "Alice")
        dir.remember(e)
        let found = dir.find(hash1)
        XCTAssertEqual(found?.displayName, "Alice")
    }

    func testFindReturnsNilForUnknownHash() {
        let dir = NNDirectory()
        XCTAssertNil(dir.find(hash1))
    }

    func testForgetRemovesEntry() {
        let dir = NNDirectory()
        dir.remember(DirectoryEntry(sourceHash: hash1, displayName: "Alice"))
        dir.forget(hash1)
        XCTAssertNil(dir.find(hash1))
    }

    func testForgetUnknownHashIsNoOp() {
        let dir = NNDirectory()
        // Should not crash
        dir.forget(hash1)
    }

    func testRememberOverwritesExistingEntry() {
        let dir = NNDirectory()
        dir.remember(DirectoryEntry(sourceHash: hash1, displayName: "Alice"))
        dir.remember(DirectoryEntry(sourceHash: hash1, displayName: "Alice Updated"))
        XCTAssertEqual(dir.find(hash1)?.displayName, "Alice Updated")
    }
}

// MARK: - NNDirectory trust level queries

final class NNDirectoryTrustTests: XCTestCase {

    private let hash1 = Data(repeating: 0x01, count: 10)
    private let hash2 = Data(repeating: 0x02, count: 10)

    func testTrustLevelForKnownEntry() {
        let dir = NNDirectory()
        dir.remember(DirectoryEntry(sourceHash: hash1, displayName: "Alice", trustLevel: .trusted))
        XCTAssertEqual(dir.trustLevel(hash1), .trusted)
    }

    func testTrustLevelForUnknownEntryIsUnknown() {
        let dir = NNDirectory()
        XCTAssertEqual(dir.trustLevel(hash2), .unknown)
    }

    func testDisplayNameForKnownEntry() {
        let dir = NNDirectory()
        dir.remember(DirectoryEntry(sourceHash: hash1, displayName: "Alice"))
        XCTAssertEqual(dir.displayName(hash1), "Alice")
    }

    func testDisplayNameForUnknownEntryIsNil() {
        let dir = NNDirectory()
        XCTAssertNil(dir.displayName(hash2))
    }
}

// MARK: - NNDirectory known nodes

final class NNDirectoryKnownNodesTests: XCTestCase {

    private func h(_ n: UInt8) -> Data { Data(repeating: n, count: 10) }

    func testKnownNodesReturnsOnlyHostingEntries() {
        let dir = NNDirectory()
        dir.remember(DirectoryEntry(sourceHash: h(1), displayName: "Node1",
                                    trustLevel: .trusted, hostsNode: true))
        dir.remember(DirectoryEntry(sourceHash: h(2), displayName: "Peer",
                                    hostsNode: false))
        let nodes = dir.knownNodes()
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].displayName, "Node1")
    }

    func testNumberOfKnownNodes() {
        let dir = NNDirectory()
        dir.remember(DirectoryEntry(sourceHash: h(1), displayName: "N1", hostsNode: true))
        dir.remember(DirectoryEntry(sourceHash: h(2), displayName: "N2", hostsNode: true))
        dir.remember(DirectoryEntry(sourceHash: h(3), displayName: "P1", hostsNode: false))
        XCTAssertEqual(dir.numberOfKnownNodes(), 2)
    }

    func testKnownNodesSortedByTrustThenName() {
        let dir = NNDirectory()
        dir.remember(DirectoryEntry(sourceHash: h(1), displayName: "Zeta",
                                    trustLevel: .trusted, hostsNode: true))
        dir.remember(DirectoryEntry(sourceHash: h(2), displayName: "Alpha",
                                    trustLevel: .trusted, hostsNode: true))
        dir.remember(DirectoryEntry(sourceHash: h(3), displayName: "Unknown Node",
                                    trustLevel: .unknown, hostsNode: true))
        let nodes = dir.knownNodes()
        // Trusted nodes before unknown; within same trust level, sorted by name
        XCTAssertEqual(nodes[0].trustLevel, .trusted)
        XCTAssertEqual(nodes[1].trustLevel, .trusted)
        XCTAssertEqual(nodes[2].trustLevel, .unknown)
        XCTAssertEqual(nodes[0].displayName, "Alpha")
        XCTAssertEqual(nodes[1].displayName, "Zeta")
    }
}

// MARK: - NNDirectory announce stream

final class NNDirectoryAnnounceStreamTests: XCTestCase {

    private let hash1 = Data(repeating: 0x01, count: 10)
    private let appData = "TestNode".data(using: .utf8)!

    func testNodeAnnounceAppearsInStream() {
        let dir = NNDirectory()
        dir.nodeAnnounceReceived(sourceHash: hash1, appData: appData, associatedPeer: nil)
        XCTAssertEqual(dir.nodeAnnounces.count, 1)
    }

    func testPeerAnnounceAppearsInStream() {
        let dir = NNDirectory()
        dir.peerAnnounceReceived(sourceHash: hash1, appData: appData)
        XCTAssertEqual(dir.peerAnnounces.count, 1)
    }

    func testNodeAnnounceStreamMaxLengthEnforced() {
        let dir = NNDirectory()
        for i in 0..<300 {
            let h = Data(repeating: UInt8(i & 0xFF), count: 10)
            dir.nodeAnnounceReceived(sourceHash: h, appData: appData, associatedPeer: nil)
        }
        XCTAssertLessThanOrEqual(dir.nodeAnnounces.count, NNDirectory.announceStreamMaxLength)
    }

    func testPeerAnnounceStreamMaxLengthEnforced() {
        let dir = NNDirectory()
        for i in 0..<300 {
            let h = Data(repeating: UInt8(i & 0xFF), count: 10)
            dir.peerAnnounceReceived(sourceHash: h, appData: appData)
        }
        XCTAssertLessThanOrEqual(dir.peerAnnounces.count, NNDirectory.announceStreamMaxLength)
    }

    func testAnnounceStreamIncludesAllTypes() {
        let dir = NNDirectory()
        dir.nodeAnnounceReceived(sourceHash: hash1, appData: appData, associatedPeer: nil)
        dir.peerAnnounceReceived(sourceHash: hash1, appData: appData)
        XCTAssertEqual(dir.announceStream.count, 2)
    }

    func testNodeAnnounceHasCorrectKind() {
        let dir = NNDirectory()
        dir.nodeAnnounceReceived(sourceHash: hash1, appData: appData, associatedPeer: nil)
        XCTAssertEqual(dir.nodeAnnounces[0].kind, "node")
    }

    func testPeerAnnounceHasCorrectKind() {
        let dir = NNDirectory()
        dir.peerAnnounceReceived(sourceHash: hash1, appData: appData)
        XCTAssertEqual(dir.peerAnnounces[0].kind, "peer")
    }
}

// MARK: - NNDirectory disk persistence (save / load)

final class NNDirectoryPersistenceTests: XCTestCase {

    private let hash1 = Data(repeating: 0x01, count: 10)

    func testSaveAndLoadRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nndir_test_\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }

        let dir1 = NNDirectory()
        dir1.remember(DirectoryEntry(sourceHash: hash1, displayName: "Alice",
                                     trustLevel: .trusted, hostsNode: true))
        try dir1.save(to: url)

        let dir2 = NNDirectory()
        try dir2.load(from: url)
        let found = dir2.find(hash1)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.displayName, "Alice")
        XCTAssertEqual(found?.trustLevel,  .trusted)
        XCTAssertTrue(found?.hostsNode ?? false)
    }

    func testLoadFromNonExistentFileIsNoOp() throws {
        let url = URL(fileURLWithPath: "/tmp/does_not_exist_\(UUID().uuidString).bin")
        let dir = NNDirectory()
        // Should not throw
        XCTAssertNoThrow(try dir.load(from: url))
        XCTAssertTrue(dir.directoryEntries.isEmpty)
    }
}
