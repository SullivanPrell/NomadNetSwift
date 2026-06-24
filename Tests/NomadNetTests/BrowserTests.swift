import XCTest
import ReticulumSwift
@testable import NomadNet

// MARK: - NomadNetURL tests

final class NomadNetURLTests: XCTestCase {

    // The Python Browser uses a colon separator: "<32-hex-chars>:<path>"
    // e.g. "abc123def456789012abcdef01234567:/page/index.mu"
    // 16 bytes = 32 hex chars (RNS.Reticulum.TRUNCATED_HASHLENGTH // 8 * 2 = 128 // 8 * 2)

    private let validHash  = "abc123def456789012abcdef01234567"   // 32 hex chars = 16 bytes
    private let validHash2 = "0102030405060708090a0b0c0d0e0f10"   // 16 bytes in hex

    // MARK: - Parsing: valid URLs

    func testParseHashOnly() {
        // Just a destination hash → default path /page/index.mu
        let url = NomadNetURL.parse(validHash)
        XCTAssertNotNil(url)
        XCTAssertEqual(url!.destinationHash, Data([0xab, 0xc1, 0x23, 0xde, 0xf4, 0x56, 0x78, 0x90, 0x12, 0xab, 0xcd, 0xef, 0x01, 0x23, 0x45, 0x67]))
        XCTAssertEqual(url!.path, "/page/index.mu")
    }

    func testParseHashWithColonPath() {
        // Standard NomadNet URL: hash:path
        let url = NomadNetURL.parse("\(validHash):/some/path")
        XCTAssertNotNil(url)
        XCTAssertEqual(url!.path, "/some/path")
    }

    func testParseHashWithEmptyPathUsesDefault() {
        // hash: with empty path → default
        let url = NomadNetURL.parse("\(validHash):")
        XCTAssertNotNil(url)
        XCTAssertEqual(url!.path, "/page/index.mu")
    }

    func testParseHashWithIndexPath() {
        let url = NomadNetURL.parse("\(validHash):/page/index.mu")
        XCTAssertNotNil(url)
        XCTAssertEqual(url!.path, "/page/index.mu")
    }

    func testDestinationHashIsCorrectBytes() {
        let url = NomadNetURL.parse(validHash2)
        XCTAssertNotNil(url)
        XCTAssertEqual(url!.destinationHash, Data([0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,0x10]))
    }

    func testHashLengthIs16Bytes() {
        let url = NomadNetURL.parse(validHash)
        XCTAssertNotNil(url)
        XCTAssertEqual(url!.destinationHash.count, 16)
    }

    // MARK: - Parsing: invalid URLs

    func testParseEmptyStringReturnsNil() {
        XCTAssertNil(NomadNetURL.parse(""))
    }

    func testParseTooShortHashReturnsNil() {
        // 20 chars — too short for a 16-byte (32-hex) hash
        XCTAssertNil(NomadNetURL.parse("abc123def456789012ab"))
    }

    func testParseTooLongHashReturnsNil() {
        // 34 chars — too long for a 16-byte (32-hex) hash
        XCTAssertNil(NomadNetURL.parse("abc123def456789012abcdef012345670a"))
    }

    func testParseNonHexHashReturnsNil() {
        // 32 chars but contains non-hex characters
        XCTAssertNil(NomadNetURL.parse("gggggggggggggggggggggggggggggggg"))
    }

    func testParseLongPathIsHandledGracefully() {
        // Long path should parse fine (no crash)
        let longPath = String(repeating: "x", count: 200)
        let url = NomadNetURL.parse("\(validHash):/\(longPath)")
        XCTAssertNotNil(url)
        XCTAssertEqual(url!.path, "/\(longPath)")
    }

    func testParseVeryLongHashComponentReturnsNil() {
        // 40 hex chars = 20 bytes — wrong length (need exactly 16 bytes / 32 hex chars)
        let longHash = String(repeating: "a", count: 40)
        XCTAssertNil(NomadNetURL.parse(longHash))
    }

    // MARK: - toString round-trip

    func testToStringRoundTripHashOnly() {
        let url = NomadNetURL.parse(validHash)!
        // toString always emits hash:path
        XCTAssertEqual(url.toString(), "\(validHash):/page/index.mu")
    }

    func testToStringRoundTripWithPath() {
        let url = NomadNetURL.parse("\(validHash):/some/path")!
        XCTAssertEqual(url.toString(), "\(validHash):/some/path")
    }

    // MARK: - Equatability

    func testEqualURLs() {
        let a = NomadNetURL.parse(validHash)!
        let b = NomadNetURL.parse(validHash)!
        XCTAssertEqual(a, b)
    }

    func testDifferentPathNotEqual() {
        let a = NomadNetURL.parse("\(validHash):/page/a.mu")!
        let b = NomadNetURL.parse("\(validHash):/page/b.mu")!
        XCTAssertNotEqual(a, b)
    }

    // MARK: - URL variables (var_<name>)

    // The Python browser parses link targets like
    //   "<hash>:<path>`a=1|b=2"
    // into request_data["var_a"] = "1", request_data["var_b"] = "2".
    // (Browser.retrieve_url, ~line 884; Browser.handle_link, ~line 224.)
    // Segments after the backtick that contain a single "=" become URL
    // variables; the path component is unaffected.

    func testParseURLWithoutVariablesHasEmptyDict() {
        let url = NomadNetURL.parse(validHash)!
        XCTAssertTrue(url.variables.isEmpty)
    }

    func testParseURLWithSingleVariable() {
        let url = NomadNetURL.parse("\(validHash):/page/index.mu`name=alice")!
        XCTAssertEqual(url.path, "/page/index.mu")
        XCTAssertEqual(url.variables, ["name": "alice"])
    }

    func testParseURLWithMultipleVariables() {
        let url = NomadNetURL.parse("\(validHash):/page/index.mu`a=1|b=2")!
        XCTAssertEqual(url.path, "/page/index.mu")
        XCTAssertEqual(url.variables, ["a": "1", "b": "2"])
    }

    func testParseURLVariableValueCanBeEmpty() {
        // "key=" → var "key" with empty value (Python: split gives ["key", ""])
        let url = NomadNetURL.parse("\(validHash):/page/index.mu`key=")!
        XCTAssertEqual(url.variables, ["key": ""])
    }

    func testParseURLNonVariableSegmentIgnored() {
        // A segment without "=" is a form-field reference, not a URL variable.
        let url = NomadNetURL.parse("\(validHash):/page/index.mu`fieldname|a=1")!
        XCTAssertEqual(url.variables, ["a": "1"])
    }

    func testParseURLMalformedVariableIgnored() {
        // "a=b=c" splits into 3 parts → ignored (Python checks len(c) == 2).
        let url = NomadNetURL.parse("\(validHash):/page/index.mu`a=b=c|x=9")!
        XCTAssertEqual(url.variables, ["x": "9"])
    }

    func testParseHashOnlyWithVariables() {
        // Variables work even with the default path.
        let url = NomadNetURL.parse("\(validHash)`token=abc")!
        XCTAssertEqual(url.path, "/page/index.mu")
        XCTAssertEqual(url.variables, ["token": "abc"])
    }

    func testToStringRoundTripWithVariables() {
        let original = NomadNetURL.parse("\(validHash):/page/index.mu`a=1|b=2")!
        let reparsed = NomadNetURL.parse(original.toString())!
        XCTAssertEqual(reparsed.path, "/page/index.mu")
        XCTAssertEqual(reparsed.variables, ["a": "1", "b": "2"])
    }

    func testURLsWithDifferentVariablesNotEqual() {
        let a = NomadNetURL.parse("\(validHash):/page/index.mu`a=1")!
        let b = NomadNetURL.parse("\(validHash):/page/index.mu`a=2")!
        XCTAssertNotEqual(a, b)
    }
}

// MARK: - PageHistory tests

final class PageHistoryTests: XCTestCase {

    private let hashA = "abc123def456789012abcdef01234567"
    private let hashB = "0102030405060708090a0b0c0d0e0f10"
    private let hashC = "0a0b0c0d0e0f10111213141516171819"

    private func makeURL(_ hash: String, path: String = "/page/index.mu") -> NomadNetURL {
        NomadNetURL.parse("\(hash):\(path)")!
    }

    // MARK: - Initial state

    func testInitialHistoryIsEmpty() {
        let h = PageHistory()
        XCTAssertNil(h.current)
        XCTAssertFalse(h.canGoBack)
        XCTAssertFalse(h.canGoForward)
    }

    // MARK: - Push

    func testPushMakesCurrentNonNil() {
        let h = PageHistory()
        h.push(makeURL(hashA))
        XCTAssertNotNil(h.current)
        XCTAssertEqual(h.current, makeURL(hashA))
    }

    func testPushTwoCurrent() {
        let h = PageHistory()
        h.push(makeURL(hashA))
        h.push(makeURL(hashB))
        XCTAssertEqual(h.current, makeURL(hashB))
    }

    func testPushThreeEntriesCanGoBack() {
        let h = PageHistory()
        h.push(makeURL(hashA))
        h.push(makeURL(hashB))
        h.push(makeURL(hashC))
        XCTAssertTrue(h.canGoBack)
        XCTAssertFalse(h.canGoForward)
    }

    // MARK: - Back navigation

    func testBackReturnsCorrectURL() {
        let h = PageHistory()
        h.push(makeURL(hashA))
        h.push(makeURL(hashB))
        let prev = h.back()
        XCTAssertEqual(prev, makeURL(hashA))
        XCTAssertEqual(h.current, makeURL(hashA))
    }

    func testBackAtBeginningReturnsNil() {
        let h = PageHistory()
        h.push(makeURL(hashA))
        let result = h.back()
        XCTAssertNil(result)
        XCTAssertEqual(h.current, makeURL(hashA))  // stays at beginning
    }

    func testBackWhenEmptyReturnsNil() {
        let h = PageHistory()
        XCTAssertNil(h.back())
    }

    func testMultipleBacksStayAtBeginning() {
        let h = PageHistory()
        h.push(makeURL(hashA))
        h.push(makeURL(hashB))
        _ = h.back()    // → A
        _ = h.back()    // already at beginning → nil
        _ = h.back()    // still at beginning → nil
        XCTAssertEqual(h.current, makeURL(hashA))
    }

    // MARK: - Forward navigation

    func testForwardAfterBackReturnsNext() {
        let h = PageHistory()
        h.push(makeURL(hashA))
        h.push(makeURL(hashB))
        _ = h.back()              // → A
        let fwd = h.forward()    // → B
        XCTAssertEqual(fwd, makeURL(hashB))
        XCTAssertEqual(h.current, makeURL(hashB))
    }

    func testForwardAtEndReturnsNil() {
        let h = PageHistory()
        h.push(makeURL(hashA))
        h.push(makeURL(hashB))
        let result = h.forward()
        XCTAssertNil(result)
        XCTAssertEqual(h.current, makeURL(hashB))  // stays at end
    }

    func testForwardWhenEmptyReturnsNil() {
        let h = PageHistory()
        XCTAssertNil(h.forward())
    }

    func testCanGoBackAndForward() {
        let h = PageHistory()
        h.push(makeURL(hashA))
        h.push(makeURL(hashB))
        h.push(makeURL(hashC))
        _ = h.back()             // position: B
        XCTAssertTrue(h.canGoBack)
        XCTAssertTrue(h.canGoForward)
    }

    // MARK: - Push truncates forward history

    func testPushAfterBackTruncatesForwardHistory() {
        let h = PageHistory()
        h.push(makeURL(hashA))
        h.push(makeURL(hashB))
        _ = h.back()             // → A
        h.push(makeURL(hashC))   // should truncate B from forward
        XCTAssertFalse(h.canGoForward)
        XCTAssertEqual(h.current, makeURL(hashC))
    }

    // MARK: - Position tracking

    func testPositionStartsAtMinusOne() {
        let h = PageHistory()
        XCTAssertEqual(h.position, -1)
    }

    func testPositionAfterOnePush() {
        let h = PageHistory()
        h.push(makeURL(hashA))
        XCTAssertEqual(h.position, 0)
    }

    func testPositionAfterTwoPushes() {
        let h = PageHistory()
        h.push(makeURL(hashA))
        h.push(makeURL(hashB))
        XCTAssertEqual(h.position, 1)
    }

    func testPositionAfterBack() {
        let h = PageHistory()
        h.push(makeURL(hashA))
        h.push(makeURL(hashB))
        _ = h.back()
        XCTAssertEqual(h.position, 0)
    }

    // MARK: - Entry count

    func testEntriesCountMatchesPushes() {
        let h = PageHistory()
        h.push(makeURL(hashA))
        h.push(makeURL(hashB))
        h.push(makeURL(hashC))
        XCTAssertEqual(h.entries.count, 3)
    }
}

// MARK: - PageRequest tests

final class PageRequestTests: XCTestCase {

    private let validHash = "abc123def456789012abcdef01234567"

    func testPageRequestHoldsURL() {
        let url = NomadNetURL.parse(validHash)!
        let req = PageRequest(url: url)
        XCTAssertEqual(req.url, url)
    }

    func testPageRequestDefaultFieldsEmpty() {
        let url = NomadNetURL.parse(validHash)!
        let req = PageRequest(url: url)
        XCTAssertTrue(req.fields.isEmpty)
    }

    func testPageRequestWithFields() {
        let url = NomadNetURL.parse(validHash)!
        let req = PageRequest(url: url, fields: ["name": "alice", "msg": "hello"])
        XCTAssertEqual(req.fields["name"], "alice")
        XCTAssertEqual(req.fields["msg"], "hello")
    }

    func testPageRequestHasTimestamp() {
        let before = Date()
        let url = NomadNetURL.parse(validHash)!
        let req = PageRequest(url: url)
        let after = Date()
        XCTAssertTrue(req.timestamp >= before)
        XCTAssertTrue(req.timestamp <= after)
    }
}

// MARK: - Field encoding tests

final class FieldEncodingTests: XCTestCase {

    // The Python browser sends request_data as a dict with keys:
    //   "field_<name>" for form field values
    //   "var_<name>"   for URL variable values
    // The dict is passed as the `data` parameter to link.request().
    // In Swift, we encode this as msgpack.

    func testEncodeEmptyFieldsIsNil() {
        // Empty fields → nil data (no request body)
        let data = NomadNetBrowser.encodeFields([:])
        XCTAssertNil(data)
    }

    func testEncodeSingleFieldProducesData() {
        let data = NomadNetBrowser.encodeFields(["name": "alice"])
        XCTAssertNotNil(data)
    }

    func testEncodeFieldsRoundTrips() {
        // Encode then decode back through MsgPack to verify correctness
        let fields = ["name": "alice", "msg": "hello"]
        let data = NomadNetBrowser.encodeFields(fields)
        XCTAssertNotNil(data)

        // Decode and verify all keys have "field_" prefix
        if let data {
            let decoded = try? MsgPack.decode(data)
            guard case .map(let pairs) = decoded else {
                XCTFail("Expected map value")
                return
            }
            let dict = Dictionary(uniqueKeysWithValues: pairs.compactMap { (k, v) -> (String, String)? in
                guard case .string(let key) = k, case .string(let val) = v else { return nil }
                return (key, val)
            })
            XCTAssertEqual(dict["field_name"], "alice")
            XCTAssertEqual(dict["field_msg"], "hello")
        }
    }

    func testEncodeMultipleFieldsHasFieldPrefix() {
        let data = NomadNetBrowser.encodeFields(["username": "bob"])
        XCTAssertNotNil(data)
        if let data {
            let decoded = try? MsgPack.decode(data)
            guard case .map(let pairs) = decoded else {
                XCTFail("Expected map value")
                return
            }
            let keys = pairs.compactMap { k, _ -> String? in
                guard case .string(let key) = k else { return nil }
                return key
            }
            XCTAssertTrue(keys.contains("field_username"))
        }
    }

    // MARK: - encode(fields:variables:)

    // The combined encoder emits "field_<name>" for form fields and
    // "var_<name>" for URL variables — matching Python's request_data dict.

    private func decodeStringMap(_ data: Data?) -> [String: String]? {
        guard let data, let decoded = try? MsgPack.decode(data),
              case .map(let pairs) = decoded else { return nil }
        return Dictionary(uniqueKeysWithValues: pairs.compactMap { (k, v) -> (String, String)? in
            guard case .string(let key) = k, case .string(let val) = v else { return nil }
            return (key, val)
        })
    }

    func testEncodeEmptyFieldsAndVariablesIsNil() {
        XCTAssertNil(NomadNetBrowser.encode(fields: [:], variables: [:]))
    }

    func testEncodeVariablesOnlyHasVarPrefix() {
        let dict = decodeStringMap(NomadNetBrowser.encode(fields: [:], variables: ["a": "1"]))
        XCTAssertEqual(dict?["var_a"], "1")
    }

    func testEncodeBothFieldsAndVariables() {
        let dict = decodeStringMap(NomadNetBrowser.encode(
            fields: ["name": "alice"],
            variables: ["city": "NYC"]
        ))
        XCTAssertEqual(dict?["field_name"], "alice")
        XCTAssertEqual(dict?["var_city"], "NYC")
        XCTAssertEqual(dict?.count, 2)
    }

    func testEncodeFieldsConvenienceMatchesCombined() {
        // encodeFields(x) must equal encode(fields: x, variables: [:])
        let viaConvenience = NomadNetBrowser.encodeFields(["msg": "hi"])
        let viaCombined = NomadNetBrowser.encode(fields: ["msg": "hi"], variables: [:])
        XCTAssertEqual(viaConvenience, viaCombined)
    }
}

// MARK: - Content detection tests

final class ContentDetectionTests: XCTestCase {

    func testMicronContentIsPageContent() {
        // Valid UTF-8 text (Micron markup) → treated as page content
        let micron = ">Hello NomadNet\n\nThis is a page."
        let data = micron.data(using: .utf8)!
        XCTAssertTrue(NomadNetBrowser.isPageContent(data: data))
    }

    func testEmptyDataIsPageContent() {
        // Empty response — treat as page content (blank page)
        XCTAssertTrue(NomadNetBrowser.isPageContent(data: Data()))
    }

    func testPlainTextIsPageContent() {
        let text = "Plain text page without markup"
        let data = text.data(using: .utf8)!
        XCTAssertTrue(NomadNetBrowser.isPageContent(data: data))
    }

    func testBinaryDataWithHighBytesIsNotPageContent() {
        // Data that is not valid UTF-8 → binary, not page content
        var bytes = Data([0x00, 0x01, 0xFF, 0xFE, 0x80, 0x81])
        // Make it clearly non-UTF-8 with invalid continuation bytes
        bytes.append(contentsOf: [0xC0, 0x80])  // overlong encoding
        XCTAssertFalse(NomadNetBrowser.isPageContent(data: bytes))
    }

    func testMicronWithBgHeaderIsPageContent() {
        // A page that starts with the #!bg= directive
        let page = "#!bg=000\n>Title\n\nContent"
        let data = page.data(using: .utf8)!
        XCTAssertTrue(NomadNetBrowser.isPageContent(data: data))
    }
}

// MARK: - NomadNetBrowser state tests (no network)

final class NomadNetBrowserStateTests: XCTestCase {

    private let validHash = "abc123def456789012abcdef01234567"

    func testBrowserInitialHistoryEmpty() {
        let browser = NomadNetBrowser()
        XCTAssertNil(browser.history.current)
    }

    func testBrowserGoBackWhenEmptyDoesNothing() {
        let browser = NomadNetBrowser()
        // Should not crash
        browser.goBack()
        XCTAssertNil(browser.history.current)
    }

    func testBrowserGoForwardWhenEmptyDoesNothing() {
        let browser = NomadNetBrowser()
        browser.goForward()
        XCTAssertNil(browser.history.current)
    }

    func testBrowserDefaultTimeoutIs10() {
        let browser = NomadNetBrowser()
        XCTAssertEqual(browser.timeout, 10.0, accuracy: 0.001)
    }

    func testBrowserDefaultPathConstant() {
        XCTAssertEqual(NomadNetBrowser.defaultPath, "/page/index.mu")
    }
}
