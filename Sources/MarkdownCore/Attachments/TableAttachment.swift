import AppKit

/// A GFM table, drawn directly rather than composed from controls.
///
/// This does not use `NSTextTable`. Under TextKit 2 an `NSTextTableBlock`
/// silently fails to lay out: cells collapse into plain sequential paragraphs,
/// with no crash and no warning. Verified by probe.
///
/// It also does not use `NSGridView`. Sizing has to happen before the hosted
/// view exists, because TextKit asks for attachment bounds during layout and a
/// zero answer collapses the table to an invisible speck. Building views to
/// measure would also drag AppKit onto whatever thread is rendering. Geometry
/// is therefore computed arithmetically from the text, and the view draws to
/// exactly that geometry.
public struct TableModel {
    public enum Alignment: Sendable { case left, center, right }

    public let header: [NSAttributedString]
    public let alignments: [Alignment]
    public let rows: [[NSAttributedString]]

    public init(header: [NSAttributedString], alignments: [Alignment], rows: [[NSAttributedString]]) {
        self.header = header
        self.alignments = alignments
        self.rows = rows
    }

    /// Convenience for tests and plain-text tables.
    public init(header: [String], alignments: [Alignment], rows: [[String]], theme: Theme = .system) {
        let attrs: [NSAttributedString.Key: Any] = [.font: theme.bodyFont, .foregroundColor: theme.textColor]
        self.header = header.map { NSAttributedString(string: $0, attributes: attrs) }
        self.alignments = alignments
        self.rows = rows.map { $0.map { NSAttributedString(string: $0, attributes: attrs) } }
    }

    public var columnCount: Int { max(header.count, rows.map(\.count).max() ?? 0) }

    func alignment(forColumn column: Int) -> Alignment {
        column < alignments.count ? alignments[column] : .left
    }

    /// All rows including the header, as a uniform grid with gaps padded.
    func allRows() -> [[NSAttributedString]] {
        let columns = columnCount
        func pad(_ row: [NSAttributedString]) -> [NSAttributedString] {
            (0..<columns).map { $0 < row.count ? row[$0] : NSAttributedString() }
        }
        return (header.isEmpty ? [] : [pad(header)]) + rows.map(pad)
    }

    var hasHeader: Bool { !header.isEmpty }
}

/// Column widths, row heights and overall size, derived from the text alone.
public struct TableGeometry {
    public static let cellPaddingX: CGFloat = 12
    public static let cellPaddingY: CGFloat = 7
    public static let outerInset: CGFloat = 1
    static let maxTableWidth: CGFloat = 660
    static let minColumnWidth: CGFloat = 44

    public let columnWidths: [CGFloat]
    public let rowHeights: [CGFloat]
    public let size: CGSize

    public init(model: TableModel) {
        let rows = model.allRows()
        let columns = model.columnCount
        guard columns > 0, !rows.isEmpty else {
            columnWidths = []
            rowHeights = []
            size = CGSize(width: 1, height: 1)
            return
        }

        // Ideal width of each column, from the widest cell in it.
        var widths = (0..<columns).map { column -> CGFloat in
            rows.reduce(CGFloat(0)) { widest, row in
                max(widest, ceil(row[column].size().width))
            } + TableGeometry.cellPaddingX * 2
        }

        // Shrink proportionally if the natural width is unreasonable, letting
        // the longest cells wrap rather than running off the page.
        let natural = widths.reduce(0, +)
        if natural > TableGeometry.maxTableWidth {
            let scale = TableGeometry.maxTableWidth / natural
            widths = widths.map { max(TableGeometry.minColumnWidth, floor($0 * scale)) }
        }
        columnWidths = widths

        // Row heights, measured at the final column widths so wrapped text fits.
        rowHeights = rows.map { row -> CGFloat in
            var tallest: CGFloat = 0
            for (column, cell) in row.enumerated() where column < widths.count {
                let available = widths[column] - TableGeometry.cellPaddingX * 2
                guard available > 0, cell.length > 0 else { continue }
                let box = cell.boundingRect(
                    with: CGSize(width: available, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                )
                tallest = max(tallest, ceil(box.height))
            }
            return max(tallest, 17) + TableGeometry.cellPaddingY * 2
        }

        size = CGSize(
            width: widths.reduce(0, +) + TableGeometry.outerInset * 2,
            height: rowHeights.reduce(0, +) + TableGeometry.outerInset * 2
        )
    }

    func originX(ofColumn column: Int) -> CGFloat {
        TableGeometry.outerInset + columnWidths[0..<column].reduce(0, +)
    }

    func originY(ofRow row: Int) -> CGFloat {
        TableGeometry.outerInset + rowHeights[0..<row].reduce(0, +)
    }
}

public final class TableTextAttachment: NSTextAttachment {
    public let model: TableModel
    public let theme: Theme
    public let geometry: TableGeometry

    public var measuredSize: CGSize { geometry.size }

    public init(model: TableModel, theme: Theme) {
        self.model = model
        self.theme = theme
        self.geometry = TableGeometry(model: model)
        super.init(data: nil, ofType: nil)
        bounds = CGRect(origin: .zero, size: geometry.size)
        // Without this the layout system never asks for a view provider.
        allowsTextAttachmentView = true
        // An attachment with no image draws a generic document icon, which
        // ends up painted on top of the hosted view. A fully transparent
        // one-pixel image suppresses it at no meaningful cost.
        image = Self.transparentPlaceholder
    }

    private static let transparentPlaceholder: NSImage = {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        return image
    }()

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func viewProvider(for parentView: NSView?,
                                      location: any NSTextLocation,
                                      textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        let provider = TableViewProvider(
            textAttachment: self,
            parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager,
            location: location
        )
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }

    public func makeContainerView() -> NSView {
        let view = TableView(model: model, theme: theme, geometry: geometry)
        view.frame = CGRect(origin: .zero, size: geometry.size)
        return view
    }
}

public final class TableViewProvider: NSTextAttachmentViewProvider {
    public override func loadView() {
        guard let attachment = textAttachment as? TableTextAttachment else {
            view = NSView()
            return
        }
        view = attachment.makeContainerView()
    }

    public override func attachmentBounds(for attributes: [NSAttributedString.Key: Any],
                                          location: any NSTextLocation,
                                          textContainer: NSTextContainer?,
                                          proposedLineFragment: CGRect,
                                          position: CGPoint) -> CGRect {
        guard let attachment = textAttachment as? TableTextAttachment else { return .zero }
        return CGRect(origin: .zero, size: attachment.measuredSize)
    }
}

/// Draws the table to the geometry measured for it.
public final class TableView: NSView {
    private let model: TableModel
    private let theme: Theme
    private let geometry: TableGeometry

    init(model: TableModel, theme: Theme, geometry: TableGeometry) {
        self.model = model
        self.theme = theme
        self.geometry = geometry
        super.init(frame: CGRect(origin: .zero, size: geometry.size))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }
    public override var intrinsicContentSize: NSSize { geometry.size }

    public override func draw(_ dirtyRect: NSRect) {
        let rows = model.allRows()
        guard !rows.isEmpty, !geometry.columnWidths.isEmpty else { return }

        // Header band.
        if model.hasHeader, let headerHeight = geometry.rowHeights.first {
            let band = NSRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
            theme.codeBackground.setFill()
            band.fill()
        }

        // Row separators.
        theme.ruleColor.setStroke()
        for row in 1..<rows.count {
            let y = geometry.originY(ofRow: row).rounded() + 0.5
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 0, y: y))
            line.line(to: NSPoint(x: bounds.width, y: y))
            line.lineWidth = model.hasHeader && row == 1 ? 1.5 : 0.5
            line.stroke()
        }

        // Cell text.
        for (rowIndex, row) in rows.enumerated() {
            let rowY = geometry.originY(ofRow: rowIndex)
            let rowHeight = geometry.rowHeights[rowIndex]
            for (column, cell) in row.enumerated() where column < geometry.columnWidths.count {
                guard cell.length > 0 else { continue }
                let columnX = geometry.originX(ofColumn: column)
                let width = geometry.columnWidths[column] - TableGeometry.cellPaddingX * 2
                guard width > 0 else { continue }

                let styled = NSMutableAttributedString(attributedString: cell)
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = switch model.alignment(forColumn: column) {
                case .left: .left
                case .center: .center
                case .right: .right
                }
                paragraph.lineBreakMode = .byWordWrapping
                let full = NSRange(location: 0, length: styled.length)
                styled.addAttribute(.paragraphStyle, value: paragraph, range: full)
                if model.hasHeader && rowIndex == 0 {
                    styled.addAttribute(.font,
                                        value: NSFont.boldSystemFont(ofSize: theme.baseFontSize),
                                        range: full)
                }

                let box = styled.boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                )
                let textY = rowY + (rowHeight - box.height) / 2
                styled.draw(with: CGRect(x: columnX + TableGeometry.cellPaddingX,
                                         y: textY,
                                         width: width,
                                         height: box.height),
                            options: [.usesLineFragmentOrigin, .usesFontLeading])
            }
        }

        // Outer border last, so it sits over the bands.
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        theme.ruleColor.setStroke()
        border.lineWidth = 1
        border.stroke()
    }
}
