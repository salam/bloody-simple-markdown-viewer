import AppKit

/// The document view.
///
/// Created with `usingTextLayoutManager: true` and kept on TextKit 2 for the
/// life of the view. Reading `layoutManager` anywhere, even once, silently and
/// permanently drops it to TextKit 1 and forfeits lazy viewport layout, which
/// is what lets a 16 MB file open in about 130 ms. A debug observer below
/// catches any code that does this by accident.
public final class MarkdownTextView: NSTextView {
    public var theme: Theme = .system
    /// Called when Markdown files are dropped onto this view. The host opens
    /// them as tabs of the window that received the drop.
    public var onFileDrop: (([URL]) -> Void)?

    private static let acceptedExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtext", "mdx", "qmd", "rmd", "txt"
    ]

    public convenience init() {
        self.init(frame: .zero)
    }

    public override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonSetup()
    }

    public override init(frame frameRect: NSRect) {
        // The only initializer that guarantees TextKit 2.
        let container = NSTextContainer(size: CGSize(width: frameRect.width,
                                                     height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        layoutManager.textContainer = container
        contentStorage.addTextLayoutManager(layoutManager)
        super.init(frame: frameRect, textContainer: container)
        commonSetup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func commonSetup() {
        isEditable = false
        isSelectable = true
        isRichText = true
        allowsUndo = true
        usesFindBar = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        textContainerInset = CGSize(width: 32, height: 28)
        linkTextAttributes = [
            .foregroundColor: theme.linkColor,
            .cursor: NSCursor.pointingHand
        ]
        registerForDraggedTypes([.fileURL])

        #if DEBUG
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didFallBackToTextKit1),
            name: NSTextView.willSwitchToNSLayoutManagerNotification,
            object: self
        )
        #endif
    }

    @objc private func didFallBackToTextKit1() {
        assertionFailure("""
        Fell back to TextKit 1. Something read NSTextView.layoutManager, which is a \
        one-way switch that disables lazy viewport layout. Find the caller and use the \
        textLayoutManager APIs instead.
        """)
    }

    // MARK: Content

    public func display(_ document: RenderedDocument) {
        textStorage?.setAttributedString(document.attributedString)
        refreshViewport()
    }

    /// Forces a viewport layout pass.
    ///
    /// Attachment views, such as tables, are created by the viewport layout
    /// controller. Without this the table stays invisible until something else
    /// provokes a pass, so it would appear only after the first scroll or a
    /// Select All.
    public func refreshViewport() {
        guard let layoutManager = textLayoutManager else {
            needsDisplay = true
            return
        }
        layoutManager.textViewportLayoutController.layoutViewport()
        needsLayout = true
        needsDisplay = true
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The first real layout pass can only happen once there is a window.
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.refreshViewport()
        }
    }

    public func displaySource(_ source: String, theme: Theme) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: theme.monoFont,
            .foregroundColor: theme.textColor,
            .paragraphStyle: {
                let style = NSMutableParagraphStyle()
                style.lineHeightMultiple = 1.3
                return style
            }()
        ]
        textStorage?.setAttributedString(NSAttributedString(string: source, attributes: attrs))
        refreshViewport()
    }

    // MARK: Search highlighting

    private var highlightedMatches: [NSRange] = []

    /// Highlights search matches without touching the text storage.
    ///
    /// TextKit 2 rendering attributes are display-only, so highlighting costs
    /// nothing in the document and leaves undo, editing and the saved file
    /// completely unaffected.
    public func highlight(matches: [NSRange], current: Int?) {
        guard let layoutManager = textLayoutManager else { return }
        layoutManager.setRenderingAttributes([:], for: layoutManager.documentRange)
        highlightedMatches = matches

        for (index, range) in matches.enumerated() {
            guard let textRange = self.textRange(from: range) else { continue }
            let isCurrent = index == current
            layoutManager.setRenderingAttributes([
                .backgroundColor: isCurrent
                    ? NSColor.systemYellow.withAlphaComponent(0.85)
                    : NSColor.systemYellow.withAlphaComponent(0.32),
                .foregroundColor: isCurrent ? NSColor.black : theme.textColor
            ], for: textRange)
        }
        needsDisplay = true
    }

    public func clearHighlights() {
        guard let layoutManager = textLayoutManager else { return }
        layoutManager.setRenderingAttributes([:], for: layoutManager.documentRange)
        highlightedMatches = []
        needsDisplay = true
    }

    /// Converts a text-storage range into the TextKit 2 range type.
    public func textRange(from range: NSRange) -> NSTextRange? {
        guard let contentManager = textLayoutManager?.textContentManager,
              let start = contentManager.location(contentManager.documentRange.location,
                                                  offsetBy: range.location),
              let end = contentManager.location(start, offsetBy: range.length) else { return nil }
        return NSTextRange(location: start, end: end)
    }

    /// Scrolls a range into view and selects it.
    public func reveal(_ range: NSRange) {
        guard range.location != NSNotFound else { return }
        setSelectedRange(range)
        scrollRangeToVisible(range)
        needsDisplay = true
    }

    // MARK: Quote bars and alert tints

    /// Drawn in `drawBackground`, not `draw`. The text view fills its own
    /// background during `draw`, which would paint straight over anything
    /// drawn before calling super.
    public override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawQuoteDecorations(in: rect)
    }

    /// Draws the left bar and tinted background for block quotes and alerts.
    /// Done here rather than by inserting glyphs so the decoration reflows with
    /// the text and costs nothing in the attributed string.
    private func drawQuoteDecorations(in dirtyRect: NSRect) {
        guard let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let storage = textStorage, storage.length > 0 else { return }

        let inset = textContainerInset
        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location,
            options: [.ensuresLayout, .estimatesSize]
        ) { fragment in
            let frame = fragment.layoutFragmentFrame
            let rect = NSRect(x: frame.minX + inset.width,
                              y: frame.minY + inset.height,
                              width: frame.width,
                              height: frame.height)
            guard rect.intersects(dirtyRect) else {
                return rect.minY < dirtyRect.maxY
            }
            guard let range = fragment.rangeInElement.nsRange(in: contentManager),
                  range.length > 0, range.location < storage.length else { return true }

            let probe = min(range.location, storage.length - 1)
            let columnWidth = self.textContainer?.size.width ?? rect.width

            // Code blocks: one filled band per line fragment. Adjacent bands
            // touch, so a multi-line block reads as a single continuous block
            // without the gaps a per-run background attribute leaves behind.
            if storage.attribute(.codeBlock, at: probe, effectiveRange: nil) != nil {
                let band = NSRect(x: inset.width, y: rect.minY,
                                  width: columnWidth, height: rect.height)
                self.theme.codeBackground.setFill()
                band.fill()
            }

            guard let depth = storage.attribute(.quoteDepth, at: probe, effectiveRange: nil) as? Int,
                  depth > 0 else { return true }

            let kind = (storage.attribute(.alertKind, at: probe, effectiveRange: nil) as? String)
                .flatMap(AlertKind.init(rawValue:))
            let tint = kind.map { theme.alertTint(for: $0) } ?? theme.quoteBarColor

            for level in 1...depth {
                let x = inset.width + CGFloat(level - 1) * 18 + 4
                if kind != nil && level == depth {
                    // Span the whole reading column, not just the measured text
                    // width, so the tint reads as a block rather than a ragged edge.
                    let fill = NSRect(x: x, y: rect.minY,
                                      width: inset.width + columnWidth - x, height: rect.height)
                    tint.withAlphaComponent(0.07).setFill()
                    fill.fill()
                }
                let bar = NSRect(x: x, y: rect.minY, width: 3, height: rect.height)
                (level == depth ? tint : theme.quoteBarColor).withAlphaComponent(
                    level == depth ? 0.85 : 0.35
                ).setFill()
                NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
            }
            return true
        }
    }

    // MARK: Dragging

    public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        markdownURLs(from: sender).isEmpty ? [] : .copy
    }

    public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        markdownURLs(from: sender).isEmpty ? [] : .copy
    }

    public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = markdownURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onFileDrop?(urls)
        return true
    }

    private func markdownURLs(from sender: any NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let objects = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: options
        ) as? [URL] else { return [] }
        return objects.filter { Self.acceptedExtensions.contains($0.pathExtension.lowercased()) }
    }
}

extension NSTextRange {
    /// Converts a TextKit 2 range into the `NSRange` the text storage uses.
    func nsRange(in contentManager: NSTextContentManager) -> NSRange? {
        let start = contentManager.offset(from: contentManager.documentRange.location, to: location)
        let length = contentManager.offset(from: location, to: endLocation)
        guard start != NSNotFound, length != NSNotFound else { return nil }
        return NSRange(location: start, length: length)
    }
}
