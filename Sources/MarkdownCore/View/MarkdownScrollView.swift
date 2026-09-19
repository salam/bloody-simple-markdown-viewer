import AppKit

/// Scrolling container for the document view, with the reading-width constraint
/// that keeps long lines comfortable on a wide window.
public final class MarkdownScrollView: NSScrollView {
    public let markdownTextView: MarkdownTextView

    public init(theme: Theme = .system) {
        markdownTextView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        markdownTextView.theme = theme
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        drawsBackground = true
        backgroundColor = .textBackgroundColor

        markdownTextView.minSize = CGSize(width: 0, height: 0)
        markdownTextView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude,
                                          height: CGFloat.greatestFiniteMagnitude)
        markdownTextView.isVerticallyResizable = true
        markdownTextView.isHorizontallyResizable = false
        markdownTextView.autoresizingMask = [.width]
        documentView = markdownTextView
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func layout() {
        super.layout()
        applyReadingWidth()
    }

    /// Caps the text column and centres it, so a maximised window does not
    /// produce unreadably long lines.
    private func applyReadingWidth() {
        let available = contentSize.width
        let theme = markdownTextView.theme
        let target = min(available, theme.readingWidth)
        let sideInset = max(32, (available - target) / 2)
        let current = markdownTextView.textContainerInset
        if abs(current.width - sideInset) > 0.5 {
            markdownTextView.textContainerInset = CGSize(width: sideInset, height: current.height)
        }
        markdownTextView.frame.size.width = available
        markdownTextView.textContainer?.size = CGSize(
            width: max(available - sideInset * 2, 100),
            height: .greatestFiniteMagnitude
        )
    }

    /// Scroll so a given character offset sits near the top of the viewport.
    public func scrollToCharacterOffset(_ offset: Int) {
        guard let layoutManager = markdownTextView.textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let location = contentManager.location(contentManager.documentRange.location,
                                                     offsetBy: offset) else { return }
        layoutManager.ensureLayout(for: NSTextRange(location: location))
        guard let fragment = layoutManager.textLayoutFragment(for: location) else { return }
        let y = fragment.layoutFragmentFrame.minY
        contentView.scroll(to: NSPoint(x: 0, y: max(0, y - 12)))
        reflectScrolledClipView(contentView)
    }
}
