import AppKit

/// A GFM table, rendered as a real `NSGridView` hosted inside the text.
///
/// This does not use `NSTextTable`. Under TextKit 2 an `NSTextTableBlock`
/// silently fails to lay out: the cells collapse into plain sequential
/// paragraphs with no crash and no warning. Verified by probe. Hosting a view
/// through `NSTextAttachmentViewProvider` does work and, critically, does not
/// knock the text view back to TextKit 1.
/// Not `Sendable`: it holds `NSAttributedString`. Rendering is main-thread work.
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

    public var columnCount: Int {
        max(header.count, rows.map(\.count).max() ?? 0)
    }
}

public final class TableTextAttachment: NSTextAttachment {
    public let model: TableModel
    public let theme: Theme

    public init(model: TableModel, theme: Theme) {
        self.model = model
        self.theme = theme
        super.init(data: nil, ofType: nil)
        // Reserve space until the hosted view reports its real size.
        bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
    }

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
        // Must be set in the initializer path, not later.
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }

    /// Builds the grid. Separated from the provider so it is testable without
    /// a live text view.
    public func makeGridView() -> NSGridView {
        let columns = model.columnCount
        let grid = NSGridView(numberOfColumns: max(columns, 1), rows: 0)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 6
        grid.columnSpacing = 18

        func cellView(_ text: NSAttributedString, bold: Bool, column: Int) -> NSView {
            let field = NSTextField(labelWithAttributedString: text)
            field.lineBreakMode = .byWordWrapping
            field.cell?.wraps = true
            field.maximumNumberOfLines = 0
            if bold {
                let bolded = NSMutableAttributedString(attributedString: text)
                bolded.addAttribute(.font,
                                    value: NSFont.boldSystemFont(ofSize: theme.baseFontSize),
                                    range: NSRange(location: 0, length: bolded.length))
                field.attributedStringValue = bolded
            }
            let alignment = column < model.alignments.count ? model.alignments[column] : .left
            field.alignment = switch alignment {
            case .left: .left
            case .center: .center
            case .right: .right
            }
            return field
        }

        if !model.header.isEmpty {
            let views = (0..<columns).map { col -> NSView in
                cellView(col < model.header.count ? model.header[col] : NSAttributedString(),
                         bold: true, column: col)
            }
            grid.addRow(with: views)
        }

        for row in model.rows {
            let views = (0..<columns).map { col -> NSView in
                cellView(col < row.count ? row[col] : NSAttributedString(), bold: false, column: col)
            }
            grid.addRow(with: views)
        }
        return grid
    }
}

/// Hosts the grid, plus a header rule and a subtle border, inside the text flow.
public final class TableViewProvider: NSTextAttachmentViewProvider {
    public override func loadView() {
        guard let attachment = textAttachment as? TableTextAttachment else {
            view = NSView()
            return
        }
        let grid = attachment.makeGridView()
        let container = TableContainerView(theme: attachment.theme,
                                           hasHeader: !attachment.model.header.isEmpty)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)

        let inset: CGFloat = 10
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset)
        ])
        container.grid = grid
        view = container
    }

    public override func attachmentBounds(for attributes: [NSAttributedString.Key: Any],
                                          location: any NSTextLocation,
                                          textContainer: NSTextContainer?,
                                          proposedLineFragment: CGRect,
                                          position: CGPoint) -> CGRect {
        guard let container = view else { return .zero }
        container.layoutSubtreeIfNeeded()
        let size = container.fittingSize
        return CGRect(x: 0, y: 0,
                      width: max(size.width, 1),
                      height: max(size.height, 1))
    }
}

/// Draws the header rule and outer border behind the grid.
final class TableContainerView: NSView {
    private let theme: Theme
    private let hasHeader: Bool
    weak var grid: NSGridView?

    init(theme: Theme, hasHeader: Bool) {
        self.theme = theme
        self.hasHeader = hasHeader
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        theme.ruleColor.setStroke()
        border.lineWidth = 1
        border.stroke()

        guard hasHeader, let grid, grid.numberOfRows > 1 else { return }
        let headerCell = grid.cell(atColumnIndex: 0, rowIndex: 0)
        let headerFrame = headerCell.contentView?.frame ?? .zero
        let y = (headerFrame.maxY + grid.frame.minY + grid.rowSpacing / 2).rounded()
        let rule = NSBezierPath()
        rule.move(to: NSPoint(x: 1, y: y))
        rule.line(to: NSPoint(x: bounds.width - 1, y: y))
        rule.lineWidth = 1
        theme.ruleColor.setStroke()
        rule.stroke()
    }
}
