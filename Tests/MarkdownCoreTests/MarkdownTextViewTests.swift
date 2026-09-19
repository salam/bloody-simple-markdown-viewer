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
}
