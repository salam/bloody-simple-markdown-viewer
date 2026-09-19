import AppKit

/// A text view laid out for paper rather than a window.
///
/// Printing does not go through the on-screen viewport, so this builds its own
/// text stack sized to the printable width, and takes a document rendered with
/// flattened attachments so tables and display math actually appear on the page
/// instead of silently vanishing.
public final class PrintableDocumentView: NSTextView {
    private let headerText: String

    public init(document: RenderedDocument, title: String, pageWidth: CGFloat) {
        headerText = title

        let container = NSTextContainer(size: CGSize(width: pageWidth,
                                                     height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        layoutManager.textContainer = container
        contentStorage.addTextLayoutManager(layoutManager)

        super.init(frame: NSRect(x: 0, y: 0, width: pageWidth, height: 1), textContainer: container)

        isEditable = false
        isSelectable = false
        drawsBackground = true
        // Paper is white whatever the screen appearance happens to be.
        backgroundColor = .white
        appearance = NSAppearance(named: .aqua)
        textContainerInset = .zero
        isVerticallyResizable = true
        isHorizontallyResizable = false

        textStorage?.setAttributedString(document.attributedString)
        sizeToFitPage(width: pageWidth)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func sizeToFitPage(width: CGFloat) {
        guard let layoutManager = textLayoutManager else { return }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let used = layoutManager.usageBoundsForTextContainer
        frame = NSRect(x: 0, y: 0, width: width, height: max(used.height + 8, 1))
    }

    public override var isFlipped: Bool { true }

    /// Draws the running head and page number into the page margins.
    public override func drawPageBorder(with borderSize: NSSize) {
        guard let operation = NSPrintOperation.current else { return }
        let info = operation.printInfo
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.gray
        ]

        let left = info.leftMargin
        let right = borderSize.width - info.rightMargin

        let head = NSAttributedString(string: headerText, attributes: attributes)
        head.draw(at: NSPoint(x: left, y: max(info.topMargin - 22, 8)))

        let page = NSAttributedString(string: "\(operation.currentPage)", attributes: attributes)
        page.draw(at: NSPoint(x: right - page.size().width,
                              y: borderSize.height - info.bottomMargin + 10))

        NSColor.gray.withAlphaComponent(0.3).setStroke()
        let rule = NSBezierPath()
        let ruleY = max(info.topMargin - 6, 20).rounded() + 0.5
        rule.move(to: NSPoint(x: left, y: ruleY))
        rule.line(to: NSPoint(x: right, y: ruleY))
        rule.lineWidth = 0.5
        rule.stroke()
    }
}

/// Builds print operations and PDF exports for a document.
public enum DocumentPrinter {
    /// Ink on white paper, at a size that reads well in print.
    public static func printTheme() -> Theme {
        var theme = Theme.system
        theme.textColor = .black
        theme.secondaryTextColor = .darkGray
        theme.linkColor = .blue
        theme.codeBackground = NSColor(white: 0.95, alpha: 1)
        theme.ruleColor = NSColor(white: 0.75, alpha: 1)
        theme.quoteBarColor = NSColor(white: 0.6, alpha: 1)
        theme.baseFontSize = 11
        theme.readingWidth = .greatestFiniteMagnitude
        return theme
    }

    /// Print settings shaped for reading: portrait, generous margins.
    public static func defaultPrintInfo() -> NSPrintInfo {
        let base = NSPrintInfo.shared
        let info = NSPrintInfo(dictionary: base.dictionary() as? [NSPrintInfo.AttributeKey: Any] ?? [:])
        info.orientation = .portrait
        info.topMargin = 56
        info.bottomMargin = 56
        info.leftMargin = 54
        info.rightMargin = 54
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        return info
    }

    /// Renders the source for paper and returns a ready print operation.
    ///
    /// The document is re-rendered with flattened attachments, because the
    /// on-screen version hosts live views which the print path never creates.
    public static func makeView(source: String, title: String,
                                baseURL: URL?, printInfo: NSPrintInfo) -> PrintableDocumentView {
        let rendered = DocumentRenderer(theme: printTheme(), baseURL: baseURL,
                                        attachmentRendering: .flattened).render(source: source)
        let pageWidth = max(printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin, 100)
        return PrintableDocumentView(document: rendered, title: title, pageWidth: pageWidth)
    }

    public static func operation(source: String, title: String, baseURL: URL?,
                                 printInfo: NSPrintInfo) -> NSPrintOperation {
        let view = makeView(source: source, title: title, baseURL: baseURL, printInfo: printInfo)
        let operation = NSPrintOperation(view: view, printInfo: printInfo)
        operation.jobTitle = title
        return operation
    }

    /// Writes the document straight to a PDF file, with no print panel.
    public static func writePDF(source: String, title: String,
                                baseURL: URL?, to url: URL) {
        let info = defaultPrintInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let operation = operation(source: source, title: title, baseURL: baseURL, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.run()
    }
}
