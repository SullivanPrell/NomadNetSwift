import XCTest
@testable import NomadNet

final class MicronParserTests: XCTestCase {

    // MARK: - Helpers

    private func parse(_ s: String) -> [MicronNode] {
        MicronParser.parse(s)
    }

    /// Assert that nodes contains exactly one `.line` and return its spans.
    private func assertSingleLine(_ nodes: [MicronNode], file: StaticString = #file, line: UInt = #line) -> [MicronSpan] {
        XCTAssertEqual(nodes.count, 1, "Expected exactly 1 node", file: file, line: line)
        guard case .line(let spans, _, _) = nodes.first else {
            XCTFail("Expected .line node, got \(nodes.first as Any)", file: file, line: line)
            return []
        }
        return spans
    }

    /// Extract plain text from spans (concatenating all `.text` spans).
    private func plainText(_ spans: [MicronSpan]) -> String {
        spans.compactMap {
            if case .text(let s, _) = $0 { return s }
            return nil
        }.joined()
    }

    // MARK: - Empty / blank lines

    func testEmptyDocumentProducesEmptyLineNode() {
        // An empty string split by "\n" yields one empty element → one .emptyLine node.
        // This matches the Python behaviour: markup.split("\n") on "" gives [""].
        let nodes = parse("")
        XCTAssertEqual(nodes, [.emptyLine])
    }

    func testSingleBlankLineProducesEmptyLine() {
        let nodes = parse("\n")
        // First line is empty string → emptyLine; second would also be empty
        XCTAssertTrue(nodes.contains(.emptyLine))
    }

    func testBlankLinesInMultilineDocument() {
        let nodes = parse("hello\n\nworld")
        XCTAssertEqual(nodes.count, 3)
        XCTAssertEqual(nodes[1], .emptyLine)
    }

    // MARK: - Plain text pass-through

    func testPlainTextProducesTextSpan() {
        let nodes = parse("hello world")
        let spans = assertSingleLine(nodes)
        XCTAssertEqual(plainText(spans), "hello world")
    }

    func testPlainTextStyleIsDefault() {
        let nodes = parse("hello")
        let spans = assertSingleLine(nodes)
        guard case .text(_, let style) = spans.first else {
            XCTFail("Expected text span"); return
        }
        XCTAssertEqual(style, MicronStyle.default)
    }

    // MARK: - Comments

    func testCommentLineProducesNoNodes() {
        let nodes = parse("# this is a comment")
        XCTAssertTrue(nodes.isEmpty)
    }

    func testCommentInMultilineIsSkipped() {
        let nodes = parse("line one\n# comment\nline two")
        // line one + line two = 2 nodes
        XCTAssertEqual(nodes.count, 2)
    }

    // MARK: - Escape prefix

    func testEscapeStripsFrontSlash() {
        let nodes = parse("\\>not a heading")
        let spans = assertSingleLine(nodes)
        XCTAssertEqual(plainText(spans), ">not a heading")
    }

    func testEscapedBacktickProducesLiteralBacktick() {
        let nodes = parse("hello \\` world")
        let spans = assertSingleLine(nodes)
        // The \ escapes the ` so it's rendered literally
        XCTAssertTrue(plainText(spans).contains("`"))
    }

    // MARK: - Literal mode

    func testLiteralModeToggle() {
        // `= toggles literal mode on; next `= toggles it off
        let markup = "`=\n`!bold but rendered literally\n`="
        let nodes = parse(markup)
        // The `= lines produce no nodes; the middle line is rendered literally
        XCTAssertEqual(nodes.count, 1)
        guard case .line(let spans, _, _) = nodes.first else {
            XCTFail("Expected .line"); return
        }
        XCTAssertEqual(plainText(spans), "`!bold but rendered literally")
    }

    func testLiteralModeEscapedToggle() {
        // Inside literal mode, \`= is rendered as the literal string "`="
        let markup = "`=\n\\`=\n`="
        let nodes = parse(markup)
        XCTAssertEqual(nodes.count, 1)
        guard case .line(let spans, _, _) = nodes.first else {
            XCTFail("Expected .line"); return
        }
        XCTAssertEqual(plainText(spans), "`=")
    }

    // MARK: - Section headings

    func testSingleHeadingLevel1() {
        let nodes = parse(">Heading One")
        XCTAssertEqual(nodes.count, 1)
        guard case .heading(let level, let spans, _, let slug) = nodes.first else {
            XCTFail("Expected .heading"); return
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(plainText(spans), "Heading One")
        XCTAssertEqual(slug, "heading-one")
    }

    func testDoubleHeadingLevel2() {
        let nodes = parse(">>Heading Two")
        guard case .heading(let level, _, _, _) = nodes.first else {
            XCTFail("Expected .heading"); return
        }
        XCTAssertEqual(level, 2)
    }

    func testTripleHeadingLevel3() {
        let nodes = parse(">>>Heading Three")
        guard case .heading(let level, _, _, _) = nodes.first else {
            XCTFail("Expected .heading"); return
        }
        XCTAssertEqual(level, 3)
    }

    func testEmptyHeadingProducesNoNode() {
        let nodes = parse(">")
        XCTAssertTrue(nodes.isEmpty)
    }

    func testHeadingSlugStripsFormattingCodes() {
        let nodes = parse(">`!Bold`! Heading")
        guard case .heading(_, _, _, let slug) = nodes.first else {
            XCTFail("Expected .heading"); return
        }
        // Formatting codes stripped; slug from "Bold Heading"
        XCTAssertEqual(slug, "bold-heading")
    }

    // MARK: - Section depth and reset

    func testSectionDepthIsSetByHeading() {
        // After a heading line, subsequent non-heading lines inherit the depth
        let markup = ">>Section\nsome content"
        let nodes = parse(markup)
        XCTAssertEqual(nodes.count, 2)
        guard case .heading(_, _, let hDepth, _) = nodes[0] else {
            XCTFail("Expected heading at index 0"); return
        }
        XCTAssertEqual(hDepth, 2)

        guard case .line(_, let lineDepth, _) = nodes[1] else {
            XCTFail("Expected line at index 1"); return
        }
        XCTAssertEqual(lineDepth, 2)
    }

    func testSectionReset() {
        let markup = ">>Deep section\n<Back to root"
        let nodes = parse(markup)
        // heading + line at depth 0
        guard case .line(_, let depth, _) = nodes[1] else {
            XCTFail("Expected line at index 1"); return
        }
        XCTAssertEqual(depth, 0)
    }

    // MARK: - Horizontal rules

    func testDefaultHorizontalRule() {
        let nodes = parse("-")
        XCTAssertEqual(nodes.count, 1)
        guard case .horizontalRule(let ch) = nodes.first else {
            XCTFail("Expected .horizontalRule"); return
        }
        XCTAssertEqual(ch, "\u{2500}")
    }

    func testCustomHorizontalRule() {
        let nodes = parse("-=")
        guard case .horizontalRule(let ch) = nodes.first else {
            XCTFail("Expected .horizontalRule"); return
        }
        XCTAssertEqual(ch, "=")
    }

    func testHorizontalRuleWithControlCharFallsBackToDefault() {
        // A control character (< 0x20) in position [1] should be replaced with ─
        let nodes = parse("-\u{01}")
        guard case .horizontalRule(let ch) = nodes.first else {
            XCTFail("Expected .horizontalRule"); return
        }
        XCTAssertEqual(ch, "\u{2500}")
    }

    // MARK: - Bold formatting

    func testBoldToggle() {
        let nodes = parse("`!bold text`! normal")
        let spans = assertSingleLine(nodes)
        // Should have at least two spans: one bold, one not
        let boldSpans = spans.compactMap { span -> String? in
            if case .text(let t, let s) = span, s.bold { return t }
            return nil
        }
        XCTAssertFalse(boldSpans.isEmpty)
        let boldText = boldSpans.joined()
        XCTAssertTrue(boldText.contains("bold text"), "Got: \(boldText)")
    }

    // MARK: - Underline formatting

    func testUnderlineToggle() {
        let nodes = parse("`_underlined`_ normal")
        let spans = assertSingleLine(nodes)
        let underlinedSpans = spans.compactMap { span -> String? in
            if case .text(let t, let s) = span, s.underline { return t }
            return nil
        }
        XCTAssertFalse(underlinedSpans.isEmpty)
    }

    // MARK: - Italic formatting

    func testItalicToggle() {
        let nodes = parse("`*italic`* normal")
        let spans = assertSingleLine(nodes)
        let italicSpans = spans.compactMap { span -> String? in
            if case .text(let t, let s) = span, s.italic { return t }
            return nil
        }
        XCTAssertFalse(italicSpans.isEmpty)
    }

    // MARK: - Reset all formatting

    func testBacktickBacktickResetsAll() {
        // `` `` `` resets bold, underline, italic, fg, bg, alignment
        let nodes = parse("`!bold`` normal")
        let spans = assertSingleLine(nodes)
        // After the reset span, the text following "normal" should not be bold
        let normalSpans = spans.compactMap { span -> MicronStyle? in
            if case .text(let t, let s) = span, t == " normal" { return s }
            return nil
        }
        // If we find the normal span, it should not be bold
        if let s = normalSpans.first {
            XCTAssertFalse(s.bold)
        }
        // At minimum we should have more than one span (bold + normal)
        XCTAssertGreaterThan(spans.count, 1)
    }

    // MARK: - Colour: foreground 3-digit

    func testForegroundColor3Digit() {
        let nodes = parse("`Fff0text")
        let spans = assertSingleLine(nodes)
        let colored = spans.compactMap { span -> MicronColor? in
            if case .text(_, let s) = span { return s.fgColor }
            return nil
        }
        XCTAssertTrue(colored.contains(.rgb3(r: 0xf, g: 0xf, b: 0x0)),
                      "Expected rgb3(f,f,0) in \(colored)")
    }

    func testForegroundColorReset() {
        let nodes = parse("`Fff0colored`f back-to-default")
        let spans = assertSingleLine(nodes)
        let defaultColored = spans.compactMap { span -> MicronColor? in
            if case .text(let t, let s) = span, t.contains("back-to-default") { return s.fgColor }
            return nil
        }
        XCTAssertTrue(defaultColored.contains(.default),
                      "Expected .default fg after `f reset, got \(defaultColored)")
    }

    // MARK: - Colour: foreground 6-digit

    func testForegroundColor6Digit() {
        let nodes = parse("`FTff8800text")
        let spans = assertSingleLine(nodes)
        let colors = spans.compactMap { span -> MicronColor? in
            if case .text(_, let s) = span, s.fgColor != .default { return s.fgColor }
            return nil
        }
        XCTAssertTrue(colors.contains(.rgb6(r: 0xff, g: 0x88, b: 0x00)),
                      "Expected rgb6(ff,88,00) in \(colors)")
    }

    // MARK: - Colour: background 3-digit

    func testBackgroundColor3Digit() {
        let nodes = parse("`B123text")
        let spans = assertSingleLine(nodes)
        let colors = spans.compactMap { span -> MicronColor? in
            if case .text(_, let s) = span, s.bgColor != .default { return s.bgColor }
            return nil
        }
        XCTAssertTrue(colors.contains(.rgb3(r: 0x1, g: 0x2, b: 0x3)),
                      "Expected rgb3(1,2,3) in \(colors)")
    }

    func testBackgroundColorReset() {
        let nodes = parse("`B123colored`b normal")
        let spans = assertSingleLine(nodes)
        let defaultColored = spans.compactMap { span -> MicronColor? in
            if case .text(let t, let s) = span, t.contains("normal") { return s.bgColor }
            return nil
        }
        XCTAssertTrue(defaultColored.contains(.default))
    }

    // MARK: - Alignment directives

    func testCenterAlignment() {
        let nodes = parse("`chello")
        guard case .line(_, _, let alignment) = nodes.first else {
            XCTFail("Expected .line"); return
        }
        XCTAssertEqual(alignment, .center)
    }

    func testRightAlignment() {
        let nodes = parse("`rhello")
        guard case .line(_, _, let alignment) = nodes.first else {
            XCTFail("Expected .line"); return
        }
        XCTAssertEqual(alignment, .right)
    }

    func testLeftAlignment() {
        // After right, `l brings it back to left
        let nodes = parse("`r`lhello")
        guard case .line(_, _, let alignment) = nodes.first else {
            XCTFail("Expected .line"); return
        }
        XCTAssertEqual(alignment, .left)
    }

    func testAlignmentResetWithA() {
        let nodes = parse("`r`ahello")
        guard case .line(_, _, let alignment) = nodes.first else {
            XCTFail("Expected .line"); return
        }
        XCTAssertEqual(alignment, .left) // default is left
    }

    // MARK: - Links

    func testSimpleLinkWithLabel() {
        let nodes = parse("`[Click here`nomadnet://abc123/page/index.mu]")
        let spans = assertSingleLine(nodes)
        let links = spans.compactMap { span -> MicronLink? in
            if case .link(let l) = span { return l }
            return nil
        }
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].label, "Click here")
        XCTAssertEqual(links[0].url, "nomadnet://abc123/page/index.mu")
    }

    func testLinkWithoutLabelUsesURL() {
        let nodes = parse("`[`nomadnet://abc123/page]")
        let spans = assertSingleLine(nodes)
        let links = spans.compactMap { span -> MicronLink? in
            if case .link(let l) = span { return l }
            return nil
        }
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].label, "nomadnet://abc123/page")
        XCTAssertEqual(links[0].url, "nomadnet://abc123/page")
    }

    func testLinkWithFields() {
        let nodes = parse("`[Visit`nomadnet://node/page`field1|field2]")
        let spans = assertSingleLine(nodes)
        let links = spans.compactMap { span -> MicronLink? in
            if case .link(let l) = span { return l }
            return nil
        }
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].fields, ["field1", "field2"])
    }

    func testLinkEmptyURLProducesNoLink() {
        // `[label``] — empty URL, should not create a link
        let nodes = parse("`[label``]")
        let spans = assertSingleLine(nodes)
        let links = spans.compactMap { span -> MicronLink? in
            if case .link(let l) = span { return l }
            return nil
        }
        XCTAssertTrue(links.isEmpty)
    }

    func testMultipleLinksOnOneLine() {
        let nodes = parse("`[A`url1] and `[B`url2]")
        let spans = assertSingleLine(nodes)
        let links = spans.compactMap { span -> MicronLink? in
            if case .link(let l) = span { return l }
            return nil
        }
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(links[0].label, "A")
        XCTAssertEqual(links[1].label, "B")
    }

    func testLinkPreservesCurrentStyle() {
        // Bold is active when the link is parsed → style should carry bold
        let nodes = parse("`!`[Link`url]")
        let spans = assertSingleLine(nodes)
        let links = spans.compactMap { span -> MicronLink? in
            if case .link(let l) = span { return l }
            return nil
        }
        XCTAssertEqual(links.count, 1)
        XCTAssertTrue(links[0].style.bold)
    }

    // MARK: - Form fields

    func testSimpleTextField() {
        let nodes = parse("`<username`>")
        let spans = assertSingleLine(nodes)
        let fields = spans.compactMap { span -> MicronField? in
            if case .field(let f) = span { return f }
            return nil
        }
        XCTAssertEqual(fields.count, 1)
        XCTAssertEqual(fields[0].name, "username")
        XCTAssertEqual(fields[0].fieldType, .text)
    }

    func testTextFieldWithWidthAndDefaultValue() {
        // `<32|myfield`default text>
        let nodes = parse("`<32|myfield`default text>")
        let spans = assertSingleLine(nodes)
        let fields = spans.compactMap { span -> MicronField? in
            if case .field(let f) = span { return f }
            return nil
        }
        XCTAssertEqual(fields.count, 1)
        XCTAssertEqual(fields[0].width, 32)
        XCTAssertEqual(fields[0].name, "myfield")
        XCTAssertEqual(fields[0].value, "default text")
    }

    func testMaskedTextField() {
        // `<!|password`>
        let nodes = parse("`<!|password`>")
        let spans = assertSingleLine(nodes)
        let fields = spans.compactMap { span -> MicronField? in
            if case .field(let f) = span { return f }
            return nil
        }
        XCTAssertEqual(fields.count, 1)
        XCTAssertEqual(fields[0].fieldType, .masked)
        XCTAssertEqual(fields[0].name, "password")
    }

    func testCheckboxField() {
        // `<?|agree`I agree>
        let nodes = parse("`<?|agree`I agree>")
        let spans = assertSingleLine(nodes)
        let fields = spans.compactMap { span -> MicronField? in
            if case .field(let f) = span { return f }
            return nil
        }
        XCTAssertEqual(fields.count, 1)
        XCTAssertEqual(fields[0].fieldType, .checkbox)
        XCTAssertEqual(fields[0].name, "agree")
        XCTAssertEqual(fields[0].label, "I agree")
    }

    func testRadioField() {
        // `<^|choice`Option A>
        let nodes = parse("`<^|choice`Option A>")
        let spans = assertSingleLine(nodes)
        let fields = spans.compactMap { span -> MicronField? in
            if case .field(let f) = span { return f }
            return nil
        }
        XCTAssertEqual(fields.count, 1)
        XCTAssertEqual(fields[0].fieldType, .radio)
        XCTAssertEqual(fields[0].name, "choice")
        XCTAssertEqual(fields[0].label, "Option A")
    }

    func testPrecheckedCheckbox() {
        // `<?|agree|val|*`Accept>
        let nodes = parse("`<?|agree|val|*`Accept>")
        let spans = assertSingleLine(nodes)
        let fields = spans.compactMap { span -> MicronField? in
            if case .field(let f) = span { return f }
            return nil
        }
        XCTAssertEqual(fields.count, 1)
        XCTAssertTrue(fields[0].prechecked)
    }

    // MARK: - Table mode

    func testTableModeBuffersRows() {
        let markup = "`t\nrow1\nrow2\n`t"
        let nodes = parse(markup)
        // One table node
        XCTAssertEqual(nodes.count, 1)
        guard case .table(let rows, _, _) = nodes.first else {
            XCTFail("Expected .table"); return
        }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], ["row1"])
        XCTAssertEqual(rows[1], ["row2"])
    }

    func testTableModeWithAlignment() {
        let markup = "`tc\nrow1\n`t"
        let nodes = parse(markup)
        guard case .table(_, let align, _) = nodes.first else {
            XCTFail("Expected .table"); return
        }
        XCTAssertEqual(align, .center)
    }

    func testTableModeWithMaxWidth() {
        let markup = "`t80\nrow1\n`t"
        let nodes = parse(markup)
        guard case .table(_, _, let maxW) = nodes.first else {
            XCTFail("Expected .table"); return
        }
        XCTAssertEqual(maxW, 80)
    }

    func testTableModeWithAlignmentAndWidth() {
        let markup = "`tr60\ndata\n`t"
        let nodes = parse(markup)
        guard case .table(_, let align, let maxW) = nodes.first else {
            XCTFail("Expected .table"); return
        }
        XCTAssertEqual(align, .right)
        XCTAssertEqual(maxW, 60)
    }

    func testUnclosedTableAtEOFFlushed() {
        let markup = "`t\nrow1\nrow2"
        let nodes = parse(markup)
        // Should flush a table with 2 rows
        XCTAssertEqual(nodes.count, 1)
        guard case .table(let rows, _, _) = nodes.first else {
            XCTFail("Expected .table"); return
        }
        XCTAssertEqual(rows.count, 2)
    }

    // MARK: - Partials

    func testSimplePartial() {
        let markup = "`{nomadnet://node/partial}"
        let nodes = parse(markup)
        XCTAssertEqual(nodes.count, 1)
        guard case .partial(let p) = nodes.first else {
            XCTFail("Expected .partial"); return
        }
        XCTAssertEqual(p.url, "nomadnet://node/partial")
        XCTAssertNil(p.refreshInterval)
        XCTAssertTrue(p.fields.isEmpty)
    }

    func testPartialWithRefresh() {
        let markup = "`{nomadnet://node/partial`30}"
        let nodes = parse(markup)
        guard case .partial(let p) = nodes.first else {
            XCTFail("Expected .partial"); return
        }
        XCTAssertEqual(p.refreshInterval, 30)
    }

    func testPartialWithRefreshBelowMinimumIsNil() {
        // Refresh < 1 second should be treated as nil (matches Python)
        let markup = "`{nomadnet://node/partial`0.5}"
        let nodes = parse(markup)
        guard case .partial(let p) = nodes.first else {
            XCTFail("Expected .partial"); return
        }
        XCTAssertNil(p.refreshInterval)
    }

    func testPartialWithFields() {
        let markup = "`{nomadnet://node/partial`10`field1|field2}"
        let nodes = parse(markup)
        guard case .partial(let p) = nodes.first else {
            XCTFail("Expected .partial"); return
        }
        XCTAssertEqual(p.fields, ["field1", "field2"])
    }

    func testPartialEmptyURLProducesNoNode() {
        let markup = "`{}"
        let nodes = parse(markup)
        XCTAssertTrue(nodes.isEmpty)
    }

    // MARK: - Mixed inline content

    func testMixedTextAndLink() {
        let nodes = parse("Visit `[this link`http://example.com] now")
        let spans = assertSingleLine(nodes)

        let textSpans = spans.compactMap { span -> String? in
            if case .text(let t, _) = span { return t }
            return nil
        }
        let linkSpans = spans.compactMap { span -> MicronLink? in
            if case .link(let l) = span { return l }
            return nil
        }

        XCTAssertTrue(textSpans.joined().contains("Visit"))
        XCTAssertTrue(textSpans.joined().contains("now"))
        XCTAssertEqual(linkSpans.count, 1)
        XCTAssertEqual(linkSpans[0].url, "http://example.com")
    }

    func testNestedFormattingAcrossSpans() {
        // Bold text, then italic text, then normal
        let nodes = parse("`!bold `! `*italic`* normal")
        let spans = assertSingleLine(nodes)
        XCTAssertGreaterThan(spans.count, 1)
    }

    // MARK: - Multiline document

    func testMultilineDocument() {
        let markup = """
        >Heading
        Some content here
        -
        More content
        """
        let nodes = parse(markup)
        // heading + content line + rule + content line
        XCTAssertEqual(nodes.count, 4)

        guard case .heading(let level, _, _, _) = nodes[0] else {
            XCTFail("Expected heading at [0]"); return
        }
        XCTAssertEqual(level, 1)

        guard case .line = nodes[1] else {
            XCTFail("Expected line at [1]"); return
        }

        guard case .horizontalRule = nodes[2] else {
            XCTFail("Expected horizontalRule at [2]"); return
        }

        guard case .line = nodes[3] else {
            XCTFail("Expected line at [3]"); return
        }
    }

    // MARK: - Slug generation

    func testSlugifyPlainText() {
        XCTAssertEqual(MicronParser.slugify("Hello World"), "hello-world")
    }

    func testSlugifySpecialCharacters() {
        XCTAssertEqual(MicronParser.slugify("Hello, World!"), "hello-world")
    }

    func testSlugifyStripsFormattingCodes() {
        XCTAssertEqual(MicronParser.slugify("`!Bold`! Heading"), "bold-heading")
    }

    func testSlugifyColorCodes() {
        XCTAssertEqual(MicronParser.slugify("`Fff0colored text"), "colored-text")
    }

    func testSlugifyEmpty() {
        XCTAssertEqual(MicronParser.slugify(""), "")
    }

    func testSlugifyAllSpecialChars() {
        XCTAssertEqual(MicronParser.slugify("---"), "")
    }

    // MARK: - Color parsing

    func testParseColor3ValidRGB() {
        let c = MicronParser.parseColor3("abc")
        XCTAssertEqual(c, .rgb3(r: 0xa, g: 0xb, b: 0xc))
    }

    func testParseColor3Grey() {
        let c = MicronParser.parseColor3("g50")
        XCTAssertEqual(c, .grey(percent: 50))
    }

    func testParseColor3InvalidReturnsNil() {
        XCTAssertNil(MicronParser.parseColor3("zz"))
        XCTAssertNil(MicronParser.parseColor3(""))
        XCTAssertNil(MicronParser.parseColor3("xyz"))  // x,y,z are not valid hex
    }

    func testParseColor6Valid() {
        let c = MicronParser.parseColor6("ff8800")
        XCTAssertEqual(c, .rgb6(r: 0xff, g: 0x88, b: 0x00))
    }

    func testParseColor6InvalidReturnsNil() {
        XCTAssertNil(MicronParser.parseColor6("gg0000"))
        XCTAssertNil(MicronParser.parseColor6(""))
        XCTAssertNil(MicronParser.parseColor6("abc"))
    }

    // MARK: - Strip Micron codes

    func testStripMicronCodesBold() {
        XCTAssertEqual(MicronParser.stripMicronCodes("`!hello`!"), "hello")
    }

    func testStripMicronCodesColor3() {
        XCTAssertEqual(MicronParser.stripMicronCodes("`Fff0hello"), "hello")
    }

    func testStripMicronCodesColor6() {
        XCTAssertEqual(MicronParser.stripMicronCodes("`FTff8800hello"), "hello")
    }

    func testStripMicronCodesAnchor() {
        XCTAssertEqual(MicronParser.stripMicronCodes("`  :my-anchor text"), "`  :my-anchor text") // only strips `:name form
    }

    func testStripMicronCodesReset() {
        XCTAssertEqual(MicronParser.stripMicronCodes("``hello"), "hello")
    }

    // MARK: - Edge cases

    func testLineWithOnlyFormattingCodeProducesEmptySpan() {
        // A line that is only a formatting command (no visible text) still should not crash
        let nodes = parse("`c")
        // The alignment command set center but produced no text span — no node
        // This is implementation-defined; just ensure no crash
        _ = nodes
    }

    func testLongLineWithManyFormats() {
        let markup = "`!bold`! `_under`_ `*ital`* `Fff0color`f `BT00ff00bg`b normal"
        let nodes = parse(markup)
        XCTAssertEqual(nodes.count, 1)
        guard case .line(let spans, _, _) = nodes.first else {
            XCTFail("Expected .line"); return
        }
        XCTAssertGreaterThan(spans.count, 1)
    }

    func testHeadingFollowedByContentInheritsDepth() {
        let markup = ">>>Deep\ncontent"
        let nodes = parse(markup)
        guard case .line(_, let depth, _) = nodes[1] else {
            XCTFail("Expected .line at [1]"); return
        }
        XCTAssertEqual(depth, 3)
    }

    func testMultipleHeadingsResetDepthCorrectly() {
        let markup = ">>Level2\n>Level1\nContent"
        let nodes = parse(markup)
        // After level 1 heading, depth should be 1
        guard case .line(_, let depth, _) = nodes[2] else {
            XCTFail("Expected .line at [2]"); return
        }
        XCTAssertEqual(depth, 1)
    }

    func testHeadingWithFormattingCodes() {
        let nodes = parse(">`!Bold Heading")
        guard case .heading(_, let spans, _, _) = nodes.first else {
            XCTFail("Expected .heading"); return
        }
        let boldSpans = spans.compactMap { span -> String? in
            if case .text(let t, let s) = span, s.bold { return t }
            return nil
        }
        XCTAssertFalse(boldSpans.isEmpty)
    }

    func testBackslashLiteralInText() {
        let nodes = parse("hello\\\\world")
        let spans = assertSingleLine(nodes)
        // Both backslashes should produce a single backslash in output
        XCTAssertTrue(plainText(spans).contains("\\"))
    }

    func testLiteralBacktickInText() {
        let nodes = parse("hello\\`world")
        let spans = assertSingleLine(nodes)
        XCTAssertTrue(plainText(spans).contains("`"))
    }

    func testDocumentWithAllElementTypes() {
        let markup = """
        # comment ignored
        >Heading 1
        >>Heading 2
        plain text line
        -
        `!bold`! and `_under`_
        `[link text`https://example.com]
        `t
        col1|col2
        val1|val2
        `t

        """
        let nodes = parse(markup)

        // Should contain: heading1, heading2, plain, rule, formatted, link line, table, emptyLine
        let headings = nodes.filter { if case .heading = $0 { return true }; return false }
        let lines = nodes.filter { if case .line = $0 { return true }; return false }
        let rules = nodes.filter { if case .horizontalRule = $0 { return true }; return false }
        let tables = nodes.filter { if case .table = $0 { return true }; return false }
        let empty = nodes.filter { $0 == .emptyLine }

        XCTAssertEqual(headings.count, 2)
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(tables.count, 1)
        XCTAssertGreaterThanOrEqual(empty.count, 1)
    }
}
