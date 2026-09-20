import AppKit
import Testing
@testable import MarkdownCore

@MainActor
@Suite("MarkdownTextView")
struct MarkdownTextViewTests {
    @Test func isCreatedOnTextKit2() {
        let view = MarkdownTextView()
        #expect(view.textLayoutManager != nil)
    }

    /// The whole architecture rests on this. A table is the construct most
    /// likely to drag the view back to TextKit 1, because NSTextTable does.
    @Test func staysOnTextKit2AfterDisplayingATable() {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let doc = DocumentRenderer(theme: .system).render(
            source: "| a | b |\n|---|---|\n| 1 | 2 |\n"
        )
        view.display(doc)
        view.layoutSubtreeIfNeeded()
        #expect(view.textLayoutManager != nil)
    }

    @Test func staysOnTextKit2AfterAFullDocument() {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let src = """
        # Title

        Text with **bold**, a [link](https://x.com) and `code`.

        > [!NOTE]
        > An alert.

        | a | b |
        |---|---|
        | 1 | 2 |

        ```swift
        let x = 1
        ```

        - [x] done
        - [ ] todo
        """
        view.display(DocumentRenderer(theme: .system).render(source: src))
        view.layoutSubtreeIfNeeded()
        #expect(view.textLayoutManager != nil)
    }

    @Test func acceptsMarkdownFileDrags() {
        let view = MarkdownTextView()
        #expect(view.registeredDraggedTypes.contains(.fileURL))
    }

    @Test func isReadOnlyByDefault() {
        let view = MarkdownTextView()
        #expect(view.isEditable == false)
        #expect(view.isSelectable == true)
    }

    @Test func canShowRawSource() {
        let view = MarkdownTextView()
        view.displaySource("# Raw **source**", theme: .system)
        #expect(view.string == "# Raw **source**")
    }

    @Test func scrollViewKeepsTextViewOnTextKit2() {
        let scroll = MarkdownScrollView(theme: .system)
        scroll.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        scroll.markdownTextView.display(
            DocumentRenderer(theme: .system).render(source: "# Hello\n\nbody\n")
        )
        scroll.layout()
        #expect(scroll.markdownTextView.textLayoutManager != nil)
    }

    @Test func readingWidthCapsTheTextColumn() {
        let scroll = MarkdownScrollView(theme: .system)
        scroll.frame = NSRect(x: 0, y: 0, width: 2000, height: 600)
        scroll.layout()
        let inset = scroll.markdownTextView.textContainerInset.width
        // On a very wide window the column is centred, not stretched.
        #expect(inset > 100)
    }

    // MARK: Ticking checkboxes

    private func taskView() -> MarkdownTextView {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.onToggleTask = { _, _ in }
        view.display(DocumentRenderer(theme: .system).render(source: """
        - [ ] open item
        - [x] done item

          A continuation paragraph indented under the item above.
        """))
        view.layoutSubtreeIfNeeded()
        return view
    }

    /// Measured against the glyph's real laid-out frame rather than against the
    /// attributed string, because where TextKit puts a glyph and where the
    /// string says it should go have parted company here before.
    @Test func aClickOnTheGlyphFindsTheCheckbox() {
        let view = taskView()
        let storage = view.textStorage!
        let first = (storage.string as NSString).range(of: "\u{2610}")
        let rect = view.boundingRect(for: first)
        #expect(rect != nil)

        let hit = view.checkbox(at: NSPoint(x: rect!.midX, y: rect!.midY))
        #expect(hit?.state == .unchecked)
        #expect(hit?.sourceOffset == 0)
    }

    @Test func aClickOnTheTextIsNotACheckbox() {
        let view = taskView()
        let storage = view.textStorage!
        let word = (storage.string as NSString).range(of: "open item")
        let rect = view.boundingRect(for: word)
        #expect(rect != nil)
        // The line still selects like text; only the glyph is a control.
        #expect(view.checkbox(at: NSPoint(x: rect!.midX, y: rect!.midY)) == nil)
    }

    /// Paragraphs indented under a task item inherit its `taskState`, so the
    /// attribute alone would make their first character a checkbox.
    @Test func aClickOnAContinuationParagraphIsNotACheckbox() {
        let view = taskView()
        let storage = view.textStorage!
        let word = (storage.string as NSString).range(of: "A continuation")
        let rect = view.boundingRect(for: word)
        #expect(rect != nil)
        #expect(view.checkbox(at: NSPoint(x: rect!.minX + 2, y: rect!.midY)) == nil)
    }

    /// The whole chain a click travels: laid-out glyph, hit test, source
    /// rewrite. Each half is tested on its own; this is the one that would
    /// catch the two halves disagreeing about what an offset means.
    @Test func clickingAGlyphRewritesTheRightSourceLine() {
        let source = """
        - [ ] first
        - [ ] second
        - [ ] third
        """
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.onToggleTask = { _, _ in }
        view.display(DocumentRenderer(theme: .system).render(source: source))
        view.layoutSubtreeIfNeeded()

        // Click the middle box, which is the one an off-by-one would miss.
        let text = view.textStorage!.string as NSString
        let line = text.range(of: "second")
        let glyph = NSRange(location: text.paragraphRange(for: line).location, length: 1)
        let rect = view.boundingRect(for: glyph)!
        let hit = view.checkbox(at: NSPoint(x: rect.midX, y: rect.midY))
        #expect(hit != nil)

        let updated = TaskToggle.apply(TaskToggle.ticked(hit!.state),
                                       atSourceOffset: hit!.sourceOffset, in: source)
        #expect(updated == """
        - [ ] first
        - [x] second
        - [ ] third
        """)
    }

    /// The filter rebuilds every paragraph with a flat indent, so the glyph
    /// lands somewhere new and the hit test has to follow it there.
    @Test func checkboxesAreClickableInTheFilteredView() {
        let source = """
        - [x] done
        -   - nested noise
        - [ ] still open
        """
        let document = DocumentRenderer(theme: .system).render(source: source)
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.onToggleTask = { _, _ in }
        view.displayFiltered(TaskFilter.filtered(document, states: [.unchecked], theme: .system))
        view.layoutSubtreeIfNeeded()

        let glyph = (view.textStorage!.string as NSString).range(of: "\u{2610}")
        let rect = view.boundingRect(for: glyph)!
        let hit = view.checkbox(at: NSPoint(x: rect.midX, y: rect.midY))
        #expect(hit?.state == .unchecked)

        let updated = TaskToggle.apply(.checked, atSourceOffset: hit?.sourceOffset ?? -1, in: source)
        #expect(updated?.contains("- [x] still open") == true)
    }

    @Test func aCheckboxIsNotClickableWhileEditingSource() {
        let view = taskView()
        let rect = view.boundingRect(for: (view.textStorage!.string as NSString).range(of: "\u{2610}"))!
        view.isEditable = true
        #expect(view.checkbox(at: NSPoint(x: rect.midX, y: rect.midY)) == nil)
    }

    // MARK: Copying code blocks

    private func codeView() -> MarkdownTextView {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.display(DocumentRenderer(theme: .system).render(source: """
        Some prose first.

        ```swift
        let x = 1
        print(x)
        ```
        """))
        view.layoutSubtreeIfNeeded()
        return view
    }

    @Test func hoveringACodeBlockOffersACopyButton() {
        let view = codeView()
        let code = (view.textStorage!.string as NSString).range(of: "let x = 1")
        let rect = view.boundingRect(for: code)!

        view.updateCopyButton(at: NSPoint(x: rect.midX, y: rect.midY))
        #expect(view.copyButton.isHidden == false)
        // Top-right corner of the block, not of the window.
        #expect(view.copyButton.frame.maxX <= view.bounds.maxX)
        #expect(view.copyButton.frame.minY < rect.maxY)
    }

    @Test func hoveringProseTakesTheButtonAway() {
        let view = codeView()
        let code = (view.textStorage!.string as NSString).range(of: "let x = 1")
        view.updateCopyButton(at: NSPoint(x: view.boundingRect(for: code)!.midX,
                                          y: view.boundingRect(for: code)!.midY))
        #expect(view.copyButton.isHidden == false)

        let prose = (view.textStorage!.string as NSString).range(of: "Some prose first")
        let rect = view.boundingRect(for: prose)!
        view.updateCopyButton(at: NSPoint(x: rect.midX, y: rect.midY))
        #expect(view.copyButton.isHidden == true)
    }

    @Test func copyingPutsTheWholeBlockOnThePasteboard() {
        let view = codeView()
        let board = NSPasteboard(name: NSPasteboard.Name("ch.sala.bsmv.tests"))
        view.pasteboard = board

        let code = (view.textStorage!.string as NSString).range(of: "let x = 1")
        let rect = view.boundingRect(for: code)!
        view.updateCopyButton(at: NSPoint(x: rect.midX, y: rect.midY))
        view.copyHoveredCodeBlock(nil)

        let copied = board.string(forType: .string)
        #expect(copied == "let x = 1\nprint(x)")
        board.releaseGlobally()
    }

    @Test func thereIsNoCopyButtonInSourceMode() {
        let view = codeView()
        let code = (view.textStorage!.string as NSString).range(of: "let x = 1")
        let rect = view.boundingRect(for: code)!
        view.updateCopyButton(at: NSPoint(x: rect.midX, y: rect.midY))
        #expect(view.copyButton.isHidden == false)

        // Source mode is a plain text editor: the fences are right there to
        // select, and a button floating over an editable field is in the way.
        view.displaySource("```swift\nlet x = 1\n```\n", theme: .system)
        view.isEditable = true
        view.layoutSubtreeIfNeeded()
        #expect(view.copyButton.isHidden == true)
        view.updateCopyButton(at: NSPoint(x: rect.midX, y: rect.midY))
        #expect(view.copyButton.isHidden == true)
    }
}
