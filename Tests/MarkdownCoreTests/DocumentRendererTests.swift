import AppKit
import Testing
@testable import MarkdownCore

@Suite("DocumentRenderer")
struct DocumentRendererTests {
    private func render(_ src: String) -> RenderedDocument {
        DocumentRenderer(theme: .system).render(source: src)
    }

    // MARK: Headings and outline

    @Test func buildsOutlineWithGitHubAnchors() {
        let doc = render("# Hello World\n\ntext\n\n## Sub Section\n")
        #expect(doc.outline.count == 2)
        #expect(doc.outline[0].title == "Hello World")
        #expect(doc.outline[0].anchor == "hello-world")
        #expect(doc.outline[1].level == 2)
        #expect(doc.outline[1].anchor == "sub-section")
    }

    @Test func deduplicatesRepeatedAnchors() {
        let doc = render("# Setup\n\n# Setup\n\n# Setup\n")
        #expect(doc.outline.map(\.anchor) == ["setup", "setup-1", "setup-2"])
    }

    @Test func stripsPunctuationFromAnchors() {
        let doc = render("# What's new, really?\n")
        #expect(doc.outline[0].anchor == "whats-new-really")
    }

    @Test func outlineCharacterOffsetsPointAtHeadings() {
        let doc = render("# One\n\nbody text\n\n## Two\n")
        let s = doc.attributedString.string as NSString
        for entry in doc.outline {
            let at = s.substring(from: entry.characterOffset)
            #expect(at.hasPrefix(entry.title))
        }
    }

    @Test func headingSizesDescend() {
        let doc = render("# Big\n\n###### Small\n")
        let s = doc.attributedString
        let big = s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let smallAt = doc.outline[1].characterOffset
        let small = s.attribute(.font, at: smallAt, effectiveRange: nil) as? NSFont
        #expect((big?.pointSize ?? 0) > (small?.pointSize ?? 0))
    }

    // MARK: Source mapping

    @Test func everyRunCarriesASourceOffset() {
        let doc = render("# Hi\n\nbody\n")
        var missing = 0
        let full = NSRange(location: 0, length: doc.attributedString.length)
        doc.attributedString.enumerateAttribute(.sourceOffset, in: full) { value, _, _ in
            if value == nil { missing += 1 }
        }
        #expect(missing == 0)
    }

    @Test func sourceOffsetsIncreaseThroughTheDocument() {
        let doc = render("# One\n\nfirst\n\n# Two\n\nsecond\n")
        let a = doc.outline[0].sourceOffset
        let b = doc.outline[1].sourceOffset
        #expect(b > a)
    }

    @Test func roundTripsBetweenSourceAndCharacterOffsets() {
        let doc = render("# Alpha\n\ntext here\n\n## Beta\n")
        let entry = doc.outline[1]
        let back = doc.sourceOffset(forCharacterOffset: entry.characterOffset)
        #expect(abs(back - entry.sourceOffset) < 8)
    }

    // MARK: Inlines

    @Test func appliesEmphasisAndStrong() {
        let doc = render("*a* **b**\n")
        let s = doc.attributedString
        let italic = s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let bold = s.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        #expect(italic?.fontDescriptor.symbolicTraits.contains(.italic) == true)
        #expect(bold?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test func rendersStrikethrough() {
        let doc = render("~~gone~~\n")
        let style = doc.attributedString.attribute(.strikethroughStyle, at: 0, effectiveRange: nil)
        #expect(style != nil)
        #expect(doc.attributedString.string.contains("gone"))
    }

    @Test func rendersLinksWithDestination() {
        let doc = render("[Apple](https://apple.com)\n")
        let url = doc.attributedString.attribute(.link, at: 0, effectiveRange: nil) as? URL
        #expect(url?.host == "apple.com")
        #expect(doc.attributedString.string.contains("Apple"))
    }

    @Test func rendersInlineCodeInMonospace() {
        let doc = render("use `let x` here\n")
        let at = (doc.attributedString.string as NSString).range(of: "let x").location
        let font = doc.attributedString.attribute(.font, at: at, effectiveRange: nil) as? NSFont
        #expect(font?.isFixedPitch == true)
    }

    @Test func substitutesEmojiShortcodes() {
        let doc = render("Ship it :rocket: :tada:\n")
        #expect(doc.attributedString.string.contains("🚀"))
        #expect(doc.attributedString.string.contains("🎉"))
    }

    @Test func leavesUnknownShortcodesAlone() {
        let doc = render("a :not_an_emoji: b\n")
        #expect(doc.attributedString.string.contains(":not_an_emoji:"))
    }

    // MARK: Lists

    @Test func rendersNestedUnorderedListsWithDistinctBullets() {
        let doc = render("- a\n  - b\n- c\n")
        let text = doc.attributedString.string
        #expect(text.contains("\u{2022}"))
        #expect(text.contains("\u{25E6}"))
        #expect(text.contains("a") && text.contains("b") && text.contains("c"))
    }

    @Test func rendersOrderedListNumbers() {
        let doc = render("1. first\n2. second\n3. third\n")
        let text = doc.attributedString.string
        #expect(text.contains("1.") && text.contains("2.") && text.contains("3."))
    }

    @Test func respectsOrderedListStartIndex() {
        let doc = render("5. five\n6. six\n")
        #expect(doc.attributedString.string.contains("5."))
        #expect(doc.attributedString.string.contains("6."))
    }

    @Test func rendersTaskListCheckboxes() {
        let doc = render("- [x] done\n- [ ] todo\n")
        let text = doc.attributedString.string
        #expect(text.contains("\u{2611}"))
        #expect(text.contains("\u{2610}"))
        #expect(text.contains("done") && text.contains("todo"))
    }

    @Test func listsCarryADepthAttribute() {
        let doc = render("- item\n")
        #expect(doc.attributedString.attribute(.listDepth, at: 0, effectiveRange: nil) as? Int == 1)
    }

    /// Setting textLists makes TextKit 2 override our indentation, so it must
    /// stay unset however tempting it looks.
    @Test func listsDoNotUseNSTextList() {
        let doc = render("- a\n  - b\n")
        let style = doc.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.textLists.isEmpty == true)
    }

    // MARK: Quotes and alerts

    @Test func detectsAllFiveAlertKinds() {
        for kind in AlertKind.allCases {
            let doc = render("> [!\(kind.rawValue.uppercased())]\n> body text\n")
            let found = doc.attributedString.attribute(.alertKind, at: 0, effectiveRange: nil) as? String
            #expect(found == kind.rawValue)
            #expect(!doc.attributedString.string.contains("[!"))
            #expect(doc.attributedString.string.contains(kind.title))
            #expect(doc.attributedString.string.contains("body text"))
        }
    }

    @Test func plainQuoteHasDepthButNoAlertKind() {
        let doc = render("> quoted\n")
        #expect(doc.attributedString.attribute(.alertKind, at: 0, effectiveRange: nil) == nil)
        #expect(doc.attributedString.attribute(.quoteDepth, at: 0, effectiveRange: nil) as? Int == 1)
    }

    @Test func nestedQuotesIncreaseDepth() {
        let doc = render("> > deep\n")
        let depth = doc.attributedString.attribute(.quoteDepth, at: 0, effectiveRange: nil) as? Int
        #expect(depth == 2)
    }

    // MARK: Code blocks

    @Test func rendersFencedCodeWithHighlighting() {
        let doc = render("```swift\nlet x = 1\n```\n")
        #expect(doc.attributedString.string.contains("let x = 1"))
        let font = doc.attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.isFixedPitch == true)
        #expect(doc.attributedString.attribute(.codeBlock, at: 0, effectiveRange: nil) as? Bool == true)
    }

    @Test func rendersTildeFencesAndIndentedCode() {
        #expect(render("~~~\nplain\n~~~\n").attributedString.string.contains("plain"))
        #expect(render("    indented\n").attributedString.string.contains("indented"))
    }

    @Test func rendersMermaidRatherThanShowingItsSource() {
        let doc = render("```mermaid\ngraph TD\nA-->B\n```\n")
        var found = false
        doc.attributedString.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: doc.attributedString.length)
        ) { value, _, _ in
            if value is MermaidTextAttachment { found = true }
        }
        #expect(found)
    }

    // MARK: Tables

    @Test func emitsAnAttachmentForATable() {
        let doc = render("| a | b |\n|---|---|\n| 1 | 2 |\n")
        var found: TableTextAttachment?
        let full = NSRange(location: 0, length: doc.attributedString.length)
        doc.attributedString.enumerateAttribute(.attachment, in: full) { value, _, _ in
            if let t = value as? TableTextAttachment { found = t }
        }
        #expect(found != nil)
        #expect(found?.model.columnCount == 2)
        #expect(found?.model.rows.count == 1)
    }

    @Test func readsTableColumnAlignment() {
        let doc = render("| l | c | r |\n|:--|:-:|--:|\n| 1 | 2 | 3 |\n")
        var model: TableModel?
        let full = NSRange(location: 0, length: doc.attributedString.length)
        doc.attributedString.enumerateAttribute(.attachment, in: full) { value, _, _ in
            if let t = value as? TableTextAttachment { model = t.model }
        }
        #expect(model?.alignments == [.left, .center, .right])
    }

    // MARK: Frontmatter and structure

    @Test func stripsFrontmatterFromRenderedOutput() {
        let doc = render("---\ntitle: Secret\n---\n\n# Visible\n")
        #expect(doc.frontmatter == "title: Secret")
        #expect(!doc.attributedString.string.contains("title: Secret"))
        #expect(doc.attributedString.string.contains("Visible"))
    }

    @Test func rendersThematicBreak() {
        let doc = render("a\n\n---\n\nb\n")
        #expect(doc.attributedString.string.contains("a"))
        #expect(doc.attributedString.string.contains("b"))
    }

    @Test func showsRawHTMLRatherThanDroppingIt() {
        let doc = render("<details>\n<summary>More</summary>\n</details>\n")
        #expect(doc.attributedString.string.contains("details") || doc.attributedString.string.contains("More"))
    }

    // MARK: Robustness

    @Test func handlesEmptyAndWhitespaceDocuments() {
        #expect(render("").attributedString.length == 0)
        #expect(render("\n\n\n").attributedString.length >= 0)
    }

    @Test func handlesDeeplyNestedStructures() {
        let src = String(repeating: "> ", count: 30) + "deep\n"
        let doc = render(src)
        #expect(doc.attributedString.string.contains("deep"))
    }

    @Test func handlesAMixedRealisticDocument() {
        let src = """
        ---
        title: Test
        ---

        # Report :tada:

        Some **bold** and *italic* and `code` and ~~struck~~ text with a [link](https://x.com).

        > [!WARNING]
        > Be careful here.

        ## Data

        | Name | Count |
        |:-----|------:|
        | a    |     1 |
        | b    |     2 |

        ```python
        def f(x):
            return x * 2  # doubles
        ```

        - [x] shipped
        - [ ] pending
          - nested note

        1. first
        2. second

        ---

        Done.
        """
        let doc = render(src)
        let text = doc.attributedString.string
        #expect(doc.outline.count == 2)
        #expect(text.contains("🎉"))
        #expect(text.contains("WARNING"))
        #expect(text.contains("def f(x):"))
        #expect(text.contains("shipped"))
        #expect(text.contains("Done."))
        #expect(doc.frontmatter == "title: Test")
    }
}

@Suite("Nested quote and alert depth")
struct NestedQuoteTests {
    private func render(_ src: String) -> RenderedDocument {
        DocumentRenderer(theme: .system).render(source: src)
    }

    @Test func tripleNestingReachesDepthThree() {
        let doc = render("> > > deepest\n")
        let at = (doc.attributedString.string as NSString).range(of: "deepest").location
        #expect(doc.attributedString.attribute(.quoteDepth, at: at, effectiveRange: nil) as? Int == 3)
    }

    @Test func outerQuoteDoesNotFlattenInnerAlert() {
        let doc = render("> outer text\n>\n> > [!NOTE]\n> > inner note\n")
        let at = (doc.attributedString.string as NSString).range(of: "inner note").location
        #expect(doc.attributedString.attribute(.alertKind, at: at, effectiveRange: nil) as? String == "note")
        let outerAt = (doc.attributedString.string as NSString).range(of: "outer text").location
        #expect(doc.attributedString.attribute(.alertKind, at: outerAt, effectiveRange: nil) == nil)
    }
}

@Suite("List nesting")
struct ListNestingTests {
    private func render(_ src: String) -> RenderedDocument {
        DocumentRenderer(theme: .system).render(source: src)
    }

    private func headIndent(_ doc: RenderedDocument, forTextContaining needle: String) -> CGFloat {
        let at = (doc.attributedString.string as NSString).range(of: needle).location
        guard at != NSNotFound,
              let style = doc.attributedString.attribute(.paragraphStyle, at: at,
                                                         effectiveRange: nil) as? NSParagraphStyle
        else { return -1 }
        return style.headIndent
    }

    /// An outer list must not flatten the indentation a nested list already set.
    @Test func eachNestingLevelIndentsFurtherThanTheLast() {
        let doc = render("""
        - level one
          - level two
            - level three
        """)
        let one = headIndent(doc, forTextContaining: "level one")
        let two = headIndent(doc, forTextContaining: "level two")
        let three = headIndent(doc, forTextContaining: "level three")
        #expect(one > 0)
        #expect(two > one)
        #expect(three > two)
    }

    @Test func orderedListItemsShareTheSameIndent() {
        let doc = render("1. first\n2. second\n3. third\n")
        let a = headIndent(doc, forTextContaining: "first")
        let b = headIndent(doc, forTextContaining: "second")
        let c = headIndent(doc, forTextContaining: "third")
        #expect(a == b)
        #expect(b == c)
    }

    @Test func markerSitsLeftOfTheText() {
        let doc = render("- item\n")
        let at = (doc.attributedString.string as NSString).range(of: "item").location
        let style = doc.attributedString.attribute(.paragraphStyle, at: at,
                                                   effectiveRange: nil) as? NSParagraphStyle
        #expect((style?.firstLineHeadIndent ?? 0) < (style?.headIndent ?? 0))
    }

    @Test func listsInsideQuotesKeepBothIndents() {
        let doc = render("> - quoted item\n")
        let indent = headIndent(doc, forTextContaining: "quoted item")
        let plain = headIndent(render("- plain item\n"), forTextContaining: "plain item")
        #expect(indent > plain)
    }
}

@Suite("Code block layout")
struct CodeBlockLayoutTests {
    private func render(_ src: String) -> RenderedDocument {
        DocumentRenderer(theme: .system).render(source: src)
    }

    /// Each line of a code block is its own paragraph, so any paragraph
    /// spacing would double-space the code.
    @Test func codeLinesHaveNoParagraphSpacing() {
        let doc = render("```swift\nlet a = 1\nlet b = 2\nlet c = 3\n```\n")
        let at = (doc.attributedString.string as NSString).range(of: "let b").location
        let style = doc.attributedString.attribute(.paragraphStyle, at: at,
                                                   effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.paragraphSpacing == 0)
        #expect(style?.paragraphSpacingBefore == 0)
    }

    @Test func longCodeLinesWrapRatherThanOverflow() {
        let doc = render("```swift\nlet x = \(String(repeating: "a", count: 300))\n```\n")
        let at = (doc.attributedString.string as NSString).range(of: "let x").location
        let style = doc.attributedString.attribute(.paragraphStyle, at: at,
                                                   effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.lineBreakMode == .byCharWrapping)
    }

    @Test func blockKeepsItsPaddingInsideTheBackground() {
        // Spacer lines carry the codeBlock attribute so the drawn band covers them.
        let doc = render("```\nx\n```\n")
        let first = doc.attributedString.attribute(.codeBlock, at: 0, effectiveRange: nil)
        #expect(first as? Bool == true)
    }
}

@MainActor
@Suite("Table attachment sizing")
struct TableAttachmentSizingTests {
    /// TextKit asks for attachment bounds during layout, before the hosted view
    /// exists. A zero answer collapses the table to an invisible speck, which
    /// is exactly what happened before the size was measured up front.
    @Test func reportsARealSizeBeforeItsViewIsLoaded() {
        let model = TableModel(
            header: ["Language", "Parser", "Speed"],
            alignments: [.left, .left, .right],
            rows: [["Swift", "native", "fast"], ["C", "cmark-gfm", "fastest"]]
        )
        let attachment = TableTextAttachment(model: model, theme: .system)
        #expect(attachment.measuredSize.width > 100)
        #expect(attachment.measuredSize.height > 40)
        #expect(attachment.bounds.width == attachment.measuredSize.width)
    }

    @Test func widerTablesMeasureWider() {
        let narrow = TableTextAttachment(
            model: TableModel(header: ["a"], alignments: [.left], rows: [["1"]]),
            theme: .system)
        let wide = TableTextAttachment(
            model: TableModel(header: ["a much longer header", "and another one here"],
                              alignments: [.left, .left],
                              rows: [["value one", "value two"]]),
            theme: .system)
        #expect(wide.measuredSize.width > narrow.measuredSize.width)
    }

    @Test func moreRowsMeasureTaller() {
        let short = TableTextAttachment(
            model: TableModel(header: ["a"], alignments: [.left], rows: [["1"]]),
            theme: .system)
        let tall = TableTextAttachment(
            model: TableModel(header: ["a"], alignments: [.left],
                              rows: [["1"], ["2"], ["3"], ["4"], ["5"]]),
            theme: .system)
        #expect(tall.measuredSize.height > short.measuredSize.height)
    }

    @Test func buildsAViewMatchingTheMeasuredSize() {
        let attachment = TableTextAttachment(
            model: TableModel(header: ["h1", "h2"], alignments: [.left, .left],
                              rows: [["a", "b"]]),
            theme: .system)
        let view = attachment.makeContainerView()
        #expect(view.frame.size == attachment.measuredSize)
    }

    @Test func veryWideTablesAreCappedRatherThanRunningOffThePage() {
        let long = String(repeating: "wide ", count: 60)
        let attachment = TableTextAttachment(
            model: TableModel(header: [long, long, long],
                              alignments: [.left, .left, .left],
                              rows: [[long, long, long]]),
            theme: .system)
        #expect(attachment.measuredSize.width <= 680)
        // Capping makes cells wrap, so the table gets taller instead.
        #expect(attachment.measuredSize.height > 60)
    }

    /// Measuring must not touch AppKit views: rendering runs off the main
    /// thread in tests and would throw if it did.
    @Test func measuringIsPureGeometry() {
        let geometry = TableGeometry(model: TableModel(
            header: ["a", "b"], alignments: [.left, .right], rows: [["1", "2"], ["3", "4"]]),
            theme: .system)
        #expect(geometry.columnWidths.count == 2)
        #expect(geometry.rowHeights.count == 3)
        #expect(geometry.size.height > 0)
    }
}
