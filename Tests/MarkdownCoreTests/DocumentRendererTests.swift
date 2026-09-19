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

    @Test func listsCarryTextListParagraphStyle() {
        let doc = render("- item\n")
        let style = doc.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.textLists.isEmpty == false)
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

    @Test func keepsMathAndMermaidSourceVisibleForNow() {
        // Phase 5 renders these properly; until then nothing may be lost.
        #expect(render("```mermaid\ngraph TD\nA-->B\n```\n").attributedString.string.contains("graph TD"))
        #expect(render("```math\nE = mc^2\n```\n").attributedString.string.contains("E = mc^2"))
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
