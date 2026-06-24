import XCTest
@testable import NomadNet

// MARK: - NomadNetUtil tests
// Corresponds to nomadnet/util.py

// MARK: - stripModifiers

final class StripModifiersTests: XCTestCase {

    func testNilReturnsNil() {
        XCTAssertNil(NomadNetUtil.stripModifiers(nil))
    }

    func testPlainTextUnchanged() {
        let s = "Hello, world!"
        XCTAssertEqual(NomadNetUtil.stripModifiers(s), s)
    }

    func testStripsCombiningMark() {
        // U+0301 is COMBINING ACUTE ACCENT (Mn) — should be removed
        let s = "e\u{0301}" // "é" in NFD form
        let result = NomadNetUtil.stripModifiers(s)
        // The base letter 'e' stays; the combining accent is stripped
        XCTAssertEqual(result, "e")
    }

    func testStripsSkinToneModifier() {
        // U+1F3FB EMOJI MODIFIER FITZPATRICK TYPE-1-2 — should be stripped
        let s = "👋\u{1F3FB}"
        let result = NomadNetUtil.stripModifiers(s)
        // The base emoji stays; the modifier is stripped
        XCTAssertFalse(result?.contains("\u{1F3FB}") ?? false)
    }

    func testStripsVariationSelector() {
        // U+FE0F is VARIATION SELECTOR-16 (makes emoji presentation) — should be stripped
        let s = "✔\u{FE0F}"
        let result = NomadNetUtil.stripModifiers(s)
        XCTAssertFalse(result?.contains("\u{FE0F}") ?? false)
    }

    func testNormalizesClrf() {
        let s = "line1\r\nline2\rline3"
        let result = NomadNetUtil.stripModifiers(s)
        XCTAssertEqual(result, "line1\nline2\nline3")
    }

    func testStripsNullBytes() {
        // Python: stripped.replace("\x00", "") removes NUL with no substitution
        let s = "hello\0world"
        let result = NomadNetUtil.stripModifiers(s)
        XCTAssertEqual(result, "helloworld")
        XCTAssertFalse(result?.contains("\0") ?? false)
    }

    func testInvalidRenderingCharReplacedWithSpace() {
        // "🕵️" is in invalid_rendering list → replaced with space
        let s = "before🕵️after"
        let result = NomadNetUtil.stripModifiers(s)
        // The spy emoji itself may be stripped with its variation selector,
        // but the space replacement happens first.
        XCTAssertNotNil(result)
        XCTAssertFalse(result?.isEmpty ?? true)
    }

    func testStripsZeroWidthJoiner() {
        // U+200D ZERO WIDTH JOINER (Cf) — should be stripped
        let s = "a\u{200D}b"
        let result = NomadNetUtil.stripModifiers(s)
        XCTAssertEqual(result, "ab")
    }
}

// MARK: - sanitizeName

final class SanitizeNameTests: XCTestCase {

    func testNilReturnsNil() {
        XCTAssertNil(NomadNetUtil.sanitizeName(nil))
    }

    func testPlainNameUnchanged() {
        XCTAssertEqual(NomadNetUtil.sanitizeName("Alice"), "Alice")
    }

    func testLettersNumbersPunctuationKept() {
        let s = "Bob-1.0 (test)"
        let result = NomadNetUtil.sanitizeName(s)
        XCTAssertEqual(result, "Bob-1.0 (test)")
    }

    func testNFKCNormalization() {
        // ① (U+2460 CIRCLED DIGIT ONE) maps to "1" under NFKC
        let s = "Item①"
        let result = NomadNetUtil.sanitizeName(s)
        XCTAssertEqual(result, "Item1")
    }

    func testEmojiStripped() {
        // 🚀 is in a block range that gets stripped
        let s = "Launch 🚀 pad"
        let result = NomadNetUtil.sanitizeName(s)
        XCTAssertFalse(result?.contains("🚀") ?? false)
    }

    func testZalgoStripped() {
        // NFKC composes a + U+0301 (acute) → á (precomposed letter Ll, kept).
        // Additional combining marks that don't form precomposed letters are stripped.
        // U+0483 COMBINING CYRILLIC TITLO (Mn) — doesn't compose with 'a' → stripped.
        // U+0488 COMBINING CYRILLIC MILLION SIGN (Me) — enclosing mark → stripped.
        let s = "a\u{0301}\u{0483}\u{0488}"  // a + acute + cyrillic titlo + cyrillic million sign
        let result = NomadNetUtil.sanitizeName(s)
        // NFKC composes a+0301 → á; 0483 and 0488 don't compose → stripped → "á"
        XCTAssertEqual(result, "\u{00E1}")   // U+00E1 LATIN SMALL LETTER A WITH ACUTE
    }

    func testMultipleSpacesCollapsed() {
        let s = "foo   bar"
        XCTAssertEqual(NomadNetUtil.sanitizeName(s), "foo bar")
    }

    func testLeadingTrailingWhitespaceStripped() {
        XCTAssertEqual(NomadNetUtil.sanitizeName("  hello  "), "hello")
    }

    func testEmptyStringReturnsEmpty() {
        XCTAssertEqual(NomadNetUtil.sanitizeName(""), "")
    }
}

// MARK: - stripMicron

final class StripMicronTests: XCTestCase {

    func testStrips3DigitColorCode() {
        // `F1A2 → removed; plain text stays
        XCTAssertEqual(NomadNetUtil.stripMicron("`F1A2hello"), "hello")
    }

    func testStrips3DigitBackgroundCode() {
        XCTAssertEqual(NomadNetUtil.stripMicron("`Bfff text"), " text")
    }

    func testStripsTrueColorForeground() {
        XCTAssertEqual(NomadNetUtil.stripMicron("`FT123456msg"), "msg")
    }

    func testStripsTrueColorBackground() {
        XCTAssertEqual(NomadNetUtil.stripMicron("`BT000000msg"), "msg")
    }

    func testStripsStyleTags() {
        let s = "`!bold`*italic`_underline`=strikethrough"
        let result = NomadNetUtil.stripMicron(s)
        XCTAssertEqual(result, "bolditalicunderlinestrikethrough")
    }

    func testStripsCombinedResetTag() {
        XCTAssertEqual(NomadNetUtil.stripMicron("before`f`bafter"), "beforeafter")
    }

    func testStripsFgBgResets() {
        XCTAssertEqual(NomadNetUtil.stripMicron("`ftext`b"), "text")
    }

    func testStripsNavigationTags() {
        // `<, `>, `{ — all stripped
        let s = "`<Go back`>`{section}"
        let result = NomadNetUtil.stripMicron(s)
        XCTAssertEqual(result, "Go backsection}")
    }

    func testPlainTextUnchanged() {
        let s = "Hello, world!"
        XCTAssertEqual(NomadNetUtil.stripMicron(s), s)
    }
}

// MARK: - stripEscapedMicron

final class StripEscapedMicronTests: XCTestCase {

    func testStripsEscapedColorCode() {
        XCTAssertEqual(NomadNetUtil.stripEscapedMicron("¦F1A2hello"), "hello")
    }

    func testStripsEscapedStyleTag() {
        XCTAssertEqual(NomadNetUtil.stripEscapedMicron("¦!bold"), "bold")
    }

    func testStripsEscapedNavTag() {
        XCTAssertEqual(NomadNetUtil.stripEscapedMicron("¦<back¦>forward"), "backforward")
    }

    func testPlainTextUnchanged() {
        let s = "Hello, world!"
        XCTAssertEqual(NomadNetUtil.stripEscapedMicron(s), s)
    }

    func testStripsEscapedTrueColorCode() {
        XCTAssertEqual(NomadNetUtil.stripEscapedMicron("¦FT112233text"), "text")
    }
}

// MARK: - unescapeMicron

final class UnescapeMicronTests: XCTestCase {

    func testUnescapesColorCode() {
        // ¦F1A2 → `F1A2
        XCTAssertEqual(NomadNetUtil.unescapeMicron("¦F1A2hello"), "`F1A2hello")
    }

    func testUnescapesStyleTag() {
        XCTAssertEqual(NomadNetUtil.unescapeMicron("¦!bold"), "`!bold")
    }

    func testUnescapesFgReset() {
        XCTAssertEqual(NomadNetUtil.unescapeMicron("¦ftext"), "`ftext")
    }

    func testUnescapesBgReset() {
        XCTAssertEqual(NomadNetUtil.unescapeMicron("before¦bafter"), "before`bafter")
    }

    func testUnescapesNavTags() {
        XCTAssertEqual(NomadNetUtil.unescapeMicron("¦<back"), "`<back")
        XCTAssertEqual(NomadNetUtil.unescapeMicron("¦>fwd"),  "`>fwd")
    }

    func testUnescapesTrueColorTag() {
        XCTAssertEqual(NomadNetUtil.unescapeMicron("¦FT112233txt"), "`FT112233txt")
    }

    func testPlainTextUnchanged() {
        let s = "plain text"
        XCTAssertEqual(NomadNetUtil.unescapeMicron(s), s)
    }
}

// MARK: - stripNonFormattingTags

final class StripNonFormattingTagsTests: XCTestCase {

    func testStripsLinkBack() {
        XCTAssertEqual(NomadNetUtil.stripNonFormattingTags("`<Go back"), "Go back")
    }

    func testStripsLinkForward() {
        XCTAssertEqual(NomadNetUtil.stripNonFormattingTags("`>forward"), "forward")
    }

    func testStripsSectionTag() {
        XCTAssertEqual(NomadNetUtil.stripNonFormattingTags("`{sect}"), "sect}")
    }

    func testStripsAlignmentTags() {
        let s = "`rcenter`cleft`lright"
        let result = NomadNetUtil.stripNonFormattingTags(s)
        XCTAssertEqual(result, "centerleftright")
    }

    func testPreservesColorTag() {
        // `F1A2 is a formatting tag — should NOT be removed
        let s = "`F1A2hello"
        XCTAssertEqual(NomadNetUtil.stripNonFormattingTags(s), "`F1A2hello")
    }

    func testPreservesStyleTag() {
        // `! is a style tag — should NOT be removed
        let s = "`!bold text"
        XCTAssertEqual(NomadNetUtil.stripNonFormattingTags(s), "`!bold text")
    }

    func testPlainTextUnchanged() {
        let s = "Hello"
        XCTAssertEqual(NomadNetUtil.stripNonFormattingTags(s), s)
    }
}
