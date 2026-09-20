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

    /// Called when the reader double-clicks the rendered document, with the
    /// UTF-8 source offset under the pointer. The host switches to source mode
    /// and reveals that position.
    public var onJumpToSource: ((Int) -> Void)?

    /// Called when the reader clicks a checkbox in the rendered document, with
    /// the UTF-8 source offset of its list item and the state it should become.
    /// The host rewrites the marker in the source and re-renders.
    public var onToggleTask: ((Int, Checkbox.State) -> Void)?

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
        hideCopyButton()
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
        // Which checkboxes are laid out has just changed, and cursor rects are
        // only recomputed on request.
        window?.invalidateCursorRects(for: self)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The first real layout pass can only happen once there is a window.
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.refreshViewport()
        }
    }

    /// Shows a derived view of the document, such as the task filter's output.
    public func displayFiltered(_ text: NSAttributedString) {
        textStorage?.setAttributedString(text)
        hideCopyButton()
        refreshViewport()
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
        hideCopyButton()
        refreshViewport()
    }

    // MARK: Jumping to source

    /// A double-click in the rendered view jumps to the matching place in the
    /// source.
    ///
    /// This deliberately takes precedence over following a link. A single click
    /// still opens the link, so both gestures stay available, and intercepting
    /// before `super` is what stops AppKit from opening the URL on the second
    /// click of a double-click.
    public override func mouseDown(with event: NSEvent) {
        // A checkbox is a control, so it answers on the way down and swallows
        // the event. Letting it through would start a text selection drag from
        // inside the thing that was just clicked.
        if !isEditable, event.clickCount == 1,
           let hit = checkbox(at: convert(event.locationInWindow, from: nil)) {
            let next = event.modifierFlags.contains(.option)
                ? TaskToggle.cycled(hit.state)
                : TaskToggle.ticked(hit.state)
            onToggleTask?(hit.sourceOffset, next)
            return
        }

        guard event.clickCount == 2, !isEditable, let onJumpToSource else {
            super.mouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        guard let storage = textStorage, storage.length > 0 else {
            super.mouseDown(with: event)
            return
        }
        let probe = min(max(index, 0), storage.length - 1)
        let offset = storage.attribute(.sourceOffset, at: probe, effectiveRange: nil) as? Int ?? 0
        onJumpToSource(offset)
    }

    /// Only a single click follows a link; a double-click is a jump to source.
    public override func clicked(onLink link: Any, at charIndex: Int) {
        guard NSApp.currentEvent?.clickCount ?? 1 == 1 else { return }
        super.clicked(onLink: link, at: charIndex)
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

    // MARK: Checkboxes

    /// Frame of a storage range in view coordinates, or nil when it is not laid
    /// out. Public so tests can assert on where things actually landed rather
    /// than on what the attributed string claims.
    public func boundingRect(for range: NSRange) -> NSRect? {
        guard let layoutManager = textLayoutManager,
              let textRange = self.textRange(from: range) else { return nil }
        var union: NSRect?
        layoutManager.enumerateTextSegments(in: textRange, type: .standard,
                                            options: [.rangeNotRequired]) { _, frame, _, _ in
            union = union.map { $0.union(frame) } ?? frame
            return true
        }
        guard var rect = union else { return nil }
        rect.origin.x += textContainerInset.width
        rect.origin.y += textContainerInset.height
        return rect
    }

    /// The checkbox under a point, if the point is on the glyph itself.
    ///
    /// Only the glyph is a control. The rest of the line stays ordinary
    /// selectable text, so dragging across a checklist still selects it.
    public func checkbox(at point: NSPoint) -> (sourceOffset: Int, state: Checkbox.State)? {
        guard !isEditable, let storage = textStorage, storage.length > 0 else { return nil }
        let index = min(max(characterIndexForInsertion(at: point), 0), storage.length - 1)
        let paragraph = (storage.string as NSString)
            .paragraphRange(for: NSRange(location: index, length: 0))
        guard let hit = checkboxGlyph(atParagraphStart: paragraph.location, in: storage),
              hit.rect.insetBy(dx: -4, dy: -2).contains(point) else { return nil }
        return (hit.sourceOffset, hit.state)
    }

    /// Reads the checkbox a paragraph opens with.
    ///
    /// The glyph comparison is load-bearing: continuation paragraphs indented
    /// under a task item inherit its `taskState`, so the attribute alone would
    /// turn the first character of every such paragraph into a checkbox.
    private func checkboxGlyph(atParagraphStart location: Int, in storage: NSTextStorage)
        -> (rect: NSRect, sourceOffset: Int, state: Checkbox.State)? {
        guard location < storage.length,
              let raw = storage.attribute(.taskState, at: location, effectiveRange: nil) as? String,
              let state = Checkbox.State(rawValue: raw),
              let offset = storage.attribute(.sourceOffset, at: location, effectiveRange: nil) as? Int
        else { return nil }
        let glyphRange = NSRange(location: location, length: 1)
        guard (storage.string as NSString).substring(with: glyphRange) == Checkbox.glyph(for: state),
              let rect = boundingRect(for: glyphRange) else { return nil }
        return (rect, offset, state)
    }

    /// A pointing hand over every checkbox, so it reads as something to click.
    public override func resetCursorRects() {
        super.resetCursorRects()
        guard onToggleTask != nil, !isEditable else { return }
        forEachVisibleCheckbox { rect, _, _ in
            addCursorRect(rect.insetBy(dx: -2, dy: -1), cursor: .pointingHand)
        }
    }

    private func forEachVisibleCheckbox(_ body: (NSRect, Int, Checkbox.State) -> Void) {
        guard let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let storage = textStorage, storage.length > 0 else { return }
        let target = visibleRect
        let inset = textContainerInset
        // Starts at the viewport, not at the document start. Enumerating from
        // the start with `.ensuresLayout` would lay out everything above the
        // viewport, and cursor rects are recomputed often enough that a 16 MB
        // file scrolled to its end would pay for the whole document each time.
        let start = layoutManager.textViewportLayoutController.viewportRange?.location
            ?? layoutManager.documentRange.location
        layoutManager.enumerateTextLayoutFragments(
            from: start,
            options: [.ensuresLayout, .estimatesSize]
        ) { fragment in
            let frame = fragment.layoutFragmentFrame
            let rect = NSRect(x: frame.minX + inset.width, y: frame.minY + inset.height,
                              width: frame.width, height: frame.height)
            guard rect.intersects(target) else { return rect.minY < target.maxY }
            guard let range = fragment.rangeInElement.nsRange(in: contentManager),
                  range.length > 0,
                  let hit = self.checkboxGlyph(atParagraphStart: range.location, in: storage)
            else { return true }
            body(hit.rect, hit.sourceOffset, hit.state)
            return true
        }
    }

    // MARK: Copying code blocks

    /// The block the copy button currently belongs to, with the band it sits
    /// in. Cached because it is consulted on every mouse move, and recomputing
    /// the band means walking the block's layout segments.
    private var hoveredCodeBlock: (range: NSRange, band: NSRect)?
    private var hoverTracking: NSTrackingArea?
    private var copyResetWork: DispatchWorkItem?

    /// Where a copied block goes. Injectable so tests do not clobber whatever
    /// the person running them had on their clipboard.
    var pasteboard: NSPasteboard = .general

    private(set) lazy var copyButton: NSButton = {
        let button = NSButton(title: "Copy", target: self, action: #selector(copyHoveredCodeBlock(_:)))
        button.bezelStyle = .roundRect
        button.controlSize = .small
        button.font = .systemFont(ofSize: 10, weight: .medium)
        button.imagePosition = .imageLeading
        button.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        button.setAccessibilityLabel("Copy code block")
        button.isHidden = true
        return button
    }()

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        // `.inVisibleRect` keeps the area in step with scrolling on its own, so
        // the rect passed here is ignored.
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited,
                                            .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTracking = area
    }

    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateCopyButton(at: convert(event.locationInWindow, from: nil))
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hideCopyButton()
    }

    /// Moves the copy button to whichever code block the pointer is over, or
    /// takes it away. Internal so tests can drive it without synthesising a
    /// mouse-moved event.
    func updateCopyButton(at point: NSPoint) {
        guard !isEditable, let storage = textStorage, storage.length > 0 else {
            hideCopyButton()
            return
        }
        // Still inside the block the button already belongs to: nothing to do.
        if let hovered = hoveredCodeBlock, !copyButton.isHidden, hovered.band.contains(point) {
            return
        }
        guard let block = codeBlock(at: point, in: storage) else {
            hideCopyButton()
            return
        }

        hoveredCodeBlock = block
        resetCopyButton()
        let size = copyButton.frame.size
        // Clamped to the viewport so the button stays reachable on a block that
        // is taller than the window.
        let top = max(block.band.minY, visibleRect.minY) + 6
        copyButton.frame = NSRect(x: block.band.maxX - size.width - 10,
                                  y: min(top, block.band.maxY - size.height - 4),
                                  width: size.width, height: size.height)
        if copyButton.superview == nil { addSubview(copyButton) }
        copyButton.isHidden = false
    }

    /// The code block containing a point, and the band drawn behind it.
    ///
    /// The band, not the text extent, is the hover target: it is what the
    /// reader sees as the block, and short lines would otherwise leave dead
    /// space to the right of the very corner the button sits in.
    private func codeBlock(at point: NSPoint, in storage: NSTextStorage) -> (range: NSRange, band: NSRect)? {
        let index = min(max(characterIndexForInsertion(at: point), 0), storage.length - 1)
        guard storage.attribute(.codeBlock, at: index, effectiveRange: nil) != nil else { return nil }

        // Bounded rather than searched over the whole document: this runs on
        // every mouse move, and a block longer than the window is already an
        // outlier. A partial range only shifts where the button sits.
        let window = NSRange(location: max(0, index - 100_000),
                             length: min(storage.length, index + 100_000) - max(0, index - 100_000))
        var range = NSRange(location: 0, length: 0)
        guard storage.attribute(.codeBlock, at: index, longestEffectiveRange: &range, in: window) != nil,
              let rect = boundingRect(for: range) else { return nil }

        let column = textContainer?.size.width ?? rect.width
        let band = NSRect(x: textContainerInset.width, y: rect.minY, width: column, height: rect.height)
        return band.contains(point) ? (range, band) : nil
    }

    @objc func copyHoveredCodeBlock(_ sender: Any?) {
        guard let block = hoveredCodeBlock, let storage = textStorage,
              NSMaxRange(block.range) <= storage.length else { return }
        // The block's range includes the thin spacer newlines that give the
        // drawn band its padding; they are not part of the code.
        let code = (storage.string as NSString).substring(with: block.range)
            .trimmingCharacters(in: .newlines)
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)

        copyResetWork?.cancel()
        copyButton.title = "Copied"
        copyButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        copyButton.sizeToFit()
        let work = DispatchWorkItem { [weak self] in self?.resetCopyButton() }
        copyResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func resetCopyButton() {
        copyResetWork?.cancel()
        copyResetWork = nil
        copyButton.title = "Copy"
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.sizeToFit()
    }

    private func hideCopyButton() {
        hoveredCodeBlock = nil
        copyResetWork?.cancel()
        copyResetWork = nil
        guard copyButton.superview != nil else { return }
        copyButton.isHidden = true
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
