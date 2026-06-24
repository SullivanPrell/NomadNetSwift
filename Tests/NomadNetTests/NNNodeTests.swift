import XCTest
@testable import NomadNet

// MARK: - NNNode constants

final class NNNodeConstantsTests: XCTestCase {

    /// Python: Node.JOB_INTERVAL = 5
    func testJobInterval() { XCTAssertEqual(NNNode.jobInterval, 5) }

    /// Python: Node.START_ANNOUNCE_DELAY = 6
    func testStartAnnounceDelay() { XCTAssertEqual(NNNode.startAnnounceDelay, 6) }

    /// Python: destination aspects "nomadnetwork", "node" → "nomadnetwork.node"
    func testAspectFilter() { XCTAssertEqual(NNNode.aspectFilter, "nomadnetwork.node") }

    /// Python: "/page/index.mu"
    func testDefaultPagePath() { XCTAssertEqual(NNNode.defaultPagePath, "/page/index.mu") }
}

// MARK: - NNNode creation

final class NNNodeCreationTests: XCTestCase {

    func testNameStored() {
        let node = NNNode(name: "Test Node")
        XCTAssertEqual(node.name, "Test Node")
    }

    /// Python: Node.announce() → self.app_data = self.name.encode("utf-8")
    func testAnnounceDataIsUTF8EncodedName() {
        let node = NNNode(name: "My Node")
        XCTAssertEqual(node.announceData(), "My Node".data(using: .utf8)!)
    }

    func testAnnounceDataForEmptyName() {
        let node = NNNode(name: "")
        XCTAssertEqual(node.announceData(), Data())
    }
}

// MARK: - Page registration (Python: register_pages + register_request_handler)

final class NNNodePageRegistrationTests: XCTestCase {

    func testRegisterPageMakesPathRegistered() {
        let node = NNNode(name: "Test")
        node.registerPage("/page/test.mu") { _ in Data() }
        XCTAssertTrue(node.isPageRegistered("/page/test.mu"))
    }

    func testUnregisteredPathIsNotRegistered() {
        let node = NNNode(name: "Test")
        XCTAssertFalse(node.isPageRegistered("/page/missing.mu"))
    }

    func testRegisteredPagePathsListsPaths() {
        let node = NNNode(name: "Test")
        node.registerPage("/page/a.mu") { _ in nil }
        node.registerPage("/page/b.mu") { _ in nil }
        let paths = node.registeredPagePaths()
        XCTAssertTrue(paths.contains("/page/a.mu"))
        XCTAssertTrue(paths.contains("/page/b.mu"))
    }

    func testRegisterFileStoresHandler() {
        let node = NNNode(name: "Test")
        node.registerFile("/file/doc.pdf") { _ in Data() }
        XCTAssertTrue(node.isFileRegistered("/file/doc.pdf"))
    }

    func testRegisteredFilePathsListsPaths() {
        let node = NNNode(name: "Test")
        node.registerFile("/file/a.pdf") { _ in nil }
        node.registerFile("/file/b.zip") { _ in nil }
        let paths = node.registeredFilePaths()
        XCTAssertTrue(paths.contains("/file/a.pdf"))
        XCTAssertTrue(paths.contains("/file/b.zip"))
    }
}

// MARK: - Request dispatch (Python: serve_page + serve_file)

final class NNNodeRequestDispatchTests: XCTestCase {

    func testHandlePageRequestCallsRegisteredHandler() {
        let node = NNNode(name: "Test")
        let expected = "hello".data(using: .utf8)!
        node.registerPage("/page/hello.mu") { _ in expected }
        let result = node.handlePageRequest(path: "/page/hello.mu", requestData: nil)
        XCTAssertEqual(result, expected)
    }

    func testHandlePageRequestPassesRequestData() {
        let node = NNNode(name: "Test")
        let input = Data([0x01, 0x02])
        var captured: Data?
        node.registerPage("/page/echo.mu") { data in captured = data; return data }
        _ = node.handlePageRequest(path: "/page/echo.mu", requestData: input)
        XCTAssertEqual(captured, input)
    }

    /// Python: If /page/index.mu is not registered, serve DEFAULT_INDEX
    func testDefaultIndexPageServedForUnregisteredIndex() {
        let node = NNNode(name: "Test")
        let result = node.handlePageRequest(path: "/page/index.mu", requestData: nil)
        XCTAssertNotNil(result)
        let text = String(data: result!, encoding: .utf8)!
        XCTAssertTrue(text.contains("index.mu"), "Default index should mention 'index.mu'")
    }

    /// Registered handler takes priority over the default index
    func testRegisteredIndexPageOverridesDefault() {
        let node = NNNode(name: "Test")
        let custom = "custom".data(using: .utf8)!
        node.registerPage("/page/index.mu") { _ in custom }
        let result = node.handlePageRequest(path: "/page/index.mu", requestData: nil)
        XCTAssertEqual(result, custom)
    }

    func testUnregisteredNonIndexPageReturnsNil() {
        let node = NNNode(name: "Test")
        let result = node.handlePageRequest(path: "/page/nonexistent.mu", requestData: nil)
        XCTAssertNil(result)
    }

    func testHandleFileRequestCallsHandler() {
        let node = NNNode(name: "Test")
        let expected = Data([0xFF, 0xFE])
        node.registerFile("/file/data.bin") { _ in expected }
        let result = node.handleFileRequest(path: "/file/data.bin", requestData: nil)
        XCTAssertEqual(result, expected)
    }

    func testUnregisteredFileRequestReturnsNil() {
        let node = NNNode(name: "Test")
        let result = node.handleFileRequest(path: "/file/missing.bin", requestData: nil)
        XCTAssertNil(result)
    }
}

// MARK: - Default page content

final class NNNodeDefaultContentTests: XCTestCase {

    /// Python: DEFAULT_INDEX mentions "index.mu" in the body text
    func testDefaultIndexContentMentionsIndexMu() {
        XCTAssertTrue(NNNode.defaultIndexPage.contains("index.mu"))
    }

    /// Python: DEFAULT_NOTALLOWED mentions permission denial
    func testDefaultNotAllowedContentIsNonEmpty() {
        XCTAssertFalse(NNNode.defaultNotAllowedPage.isEmpty)
    }

    func testDefaultIndexPageIsValidUTF8() {
        XCTAssertNotNil(NNNode.defaultIndexPage.data(using: .utf8))
    }

    func testDefaultNotAllowedPageIsValidUTF8() {
        XCTAssertNotNil(NNNode.defaultNotAllowedPage.data(using: .utf8))
    }
}

// MARK: - Peer lifecycle callbacks (Python: peer_connected / peer_disconnected)

final class NNNodePeerLifecycleTests: XCTestCase {

    func testPeerConnectedCallbackInvoked() {
        let node = NNNode(name: "Test")
        let linkID = Data([0x01, 0x02])
        var received: Data?
        node.onPeerConnected = { id in received = id }
        node.handleLinkEstablished(linkID: linkID)
        XCTAssertEqual(received, linkID)
    }

    func testPeerDisconnectedCallbackInvoked() {
        let node = NNNode(name: "Test")
        let linkID = Data([0x03, 0x04])
        var received: Data?
        node.onPeerDisconnected = { id in received = id }
        node.handleLinkClosed(linkID: linkID)
        XCTAssertEqual(received, linkID)
    }

    func testNoPeerConnectedCallbackNoError() {
        let node = NNNode(name: "Test")
        // Should not crash when no callback is set
        node.handleLinkEstablished(linkID: Data([0x01]))
    }

    func testNoPeerDisconnectedCallbackNoError() {
        let node = NNNode(name: "Test")
        node.handleLinkClosed(linkID: Data([0x01]))
    }
}
