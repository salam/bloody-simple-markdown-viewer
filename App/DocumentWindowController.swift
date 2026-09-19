import AppKit
import MarkdownCore

final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, NSMenuItemValidation {
    private var scrollView: MarkdownScrollView!
    private var markdownDocument: MarkdownDocument? { document as? MarkdownDocument }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = false
        window.tabbingMode = .preferred
        // A shared identifier is what lets windows be merged into one tab group.
        window.tabbingIdentifier = "ch.sala.BloodySimpleMarkdownViewer.document"
        window.setFrameAutosaveName("MarkdownDocumentWindow")
        window.minSize = NSSize(width: 420, height: 320)
        self.init(window: window)
        window.delegate = self
        setUpContent()
    }

    private func setUpContent() {
        scrollView = MarkdownScrollView(theme: .system)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.markdownTextView.delegate = self

        // A file dropped on this window becomes a tab of this window.
        scrollView.markdownTextView.onFileDrop = { urls in
            guard let controller = NSDocumentController.shared as? DocumentController else { return }
            controller.openBatch(urls, joining: self.window)
        }

        guard let contentView = window?.contentView else { return }
        contentView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    func load(document: MarkdownDocument) {
        refresh()
        window?.title = document.displayName
    }

    /// Re-applies the document to the view in whichever mode is current.
    func refresh() {
        guard let document = markdownDocument else { return }
        let textView = scrollView.markdownTextView
        if document.isShowingSource {
            textView.displaySource(document.source, theme: document.theme)
            textView.isEditable = true
        } else {
            document.rerender()
            textView.display(document.rendered)
            textView.isEditable = false
        }
        window?.title = document.displayName
        invalidateRestorableState()
    }

    // MARK: Source toggle

    @IBAction func toggleSourceMode(_ sender: Any?) {
        guard let document = markdownDocument else { return }
        let textView = scrollView.markdownTextView

        // Hold the reading position across the switch, using the source offset
        // that every rendered run carries.
        let visibleCharacter = textView.characterIndexForInsertion(
            at: scrollView.contentView.bounds.origin
        )
        if document.isShowingSource {
            document.updateSource(textView.string)
            document.isShowingSource = false
            refresh()
            let target = document.rendered.characterOffset(forSourceOffset: visibleCharacter)
            scrollView.scrollToCharacterOffset(target)
        } else {
            let sourceOffset = document.rendered.sourceOffset(forCharacterOffset: visibleCharacter)
            document.isShowingSource = true
            refresh()
            scrollView.scrollToCharacterOffset(min(sourceOffset, textView.string.utf16.count))
        }
    }

    // MARK: Editing

    func textDidChange(_ notification: Notification) {
        guard let document = markdownDocument, document.isShowingSource else { return }
        document.updateSource(scrollView.markdownTextView.string)
    }

    func windowWillClose(_ notification: Notification) {
        guard let document = markdownDocument, document.isShowingSource else { return }
        document.updateSource(scrollView.markdownTextView.string)
    }

    // MARK: Menu validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSourceMode(_:)) {
            menuItem.title = (markdownDocument?.isShowingSource ?? false)
                ? "Show Rendered Markdown"
                : "Show Markdown Source"
            return markdownDocument != nil
        }
        return true
    }
}
