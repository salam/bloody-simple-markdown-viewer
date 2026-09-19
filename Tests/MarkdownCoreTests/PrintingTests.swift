import AppKit
import PDFKit
import Testing
@testable import MarkdownCore

@MainActor
@Suite("Printing and PDF")
struct PrintingTests {
    private let source = """
    # Printed Report

    Prose with **bold**, `code` and inline math $E = mc^2$.

    | Language | Parser | Speed |
    |:---------|:-------|------:|
    | Swift    | native | fast  |
    | C        | cmark  | fastest |

    ```swift
    let x = 1
    ```

    - [x] done
    - [ ] open
    """

    /// The reason flattened rendering exists: the print path never creates
    /// attachment views, so a live-view table would leave a blank space.
    @Test func flattenedTablesCarryAnImage() {
        let doc = DocumentRenderer(theme: .system, attachmentRendering: .flattened)
            .render(source: source)
        var table: TableTextAttachment?
        doc.attributedString.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: doc.attributedString.length)
        ) { value, _, _ in
            if let found = value as? TableTextAttachment { table = found }
        }
        #expect(table != nil)
        #expect(table?.image != nil, "a flattened table must rasterise, or it prints blank")
        #expect((table?.image?.size.width ?? 0) > 50)
    }

    @Test func interactiveTablesStillUseALiveView() {
        let doc = DocumentRenderer(theme: .system, attachmentRendering: .interactive)
            .render(source: source)
        var table: TableTextAttachment?
        doc.attributedString.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: doc.attributedString.length)
        ) { value, _, _ in
            if let found = value as? TableTextAttachment { table = found }
        }
        #expect(table?.allowsTextAttachmentView == true)
    }

    @Test func flattenedDisplayMathCarriesAnImage() {
        let doc = DocumentRenderer(theme: .system, attachmentRendering: .flattened)
            .render(source: "$$\\sum_{i=1}^{n} i$$")
        var math: MathTextAttachment?
        doc.attributedString.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: doc.attributedString.length)
        ) { value, _, _ in
            if let found = value as? MathTextAttachment { math = found }
        }
        #expect(math != nil)
        #expect(math?.image != nil, "display math must rasterise for print")
    }

    @Test func printThemeUsesInkOnWhite() {
        let theme = DocumentPrinter.printTheme()
        #expect(theme.textColor == .black)
        // Screen reading width must not constrain the printed column.
        #expect(theme.readingWidth > 10_000)
    }

    @Test func buildsAPrintViewSizedToThePage() {
        let info = DocumentPrinter.defaultPrintInfo()
        let view = DocumentPrinter.makeView(source: source, title: "Report",
                                            baseURL: nil, printInfo: info)
        let expectedWidth = info.paperSize.width - info.leftMargin - info.rightMargin
        #expect(abs(view.frame.width - expectedWidth) < 1)
        #expect(view.frame.height > 100, "the document must have laid out")
        #expect(view.backgroundColor == .white)
    }

    /// Renders the print view to PDF and checks real content came out.
    @Test func producesPDFDataContainingTheDocument() {
        let info = DocumentPrinter.defaultPrintInfo()
        let view = DocumentPrinter.makeView(source: source, title: "Report",
                                            baseURL: nil, printInfo: info)
        let data = view.dataWithPDF(inside: view.bounds)
        #expect(data.count > 4000, "PDF looks empty at \(data.count) bytes")

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("markdown-snapshots")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("printed.pdf")
        try? data.write(to: url)

        // The text must be selectable text in the PDF, not a picture of text.
        guard let pdf = PDFDocument(data: data), let text = pdf.string else {
            Issue.record("PDF could not be parsed")
            return
        }
        #expect(text.contains("Printed Report"))
        // PDFKit splits a bold run, so match a prefix rather than the word.
        #expect(text.contains("Languag"), "the table's text is missing from the PDF")
        #expect(text.contains("fastest"))
        #expect(text.contains("let x = 1"), "the code block is missing from the PDF")
        print("PDF: \(url.path) pages=\(pdf.pageCount)")
    }
}

@MainActor
@Suite("Table header sizing")
struct TableHeaderSizingTests {
    /// Headers are drawn bold, so they must be measured bold too. Measuring in
    /// the regular font makes every header cell wrap onto a second line.
    @Test func headerColumnsAreWideEnoughForBoldText() {
        let model = TableModel(header: ["Language", "Parser", "Speed"],
                               alignments: [.left, .left, .right],
                               rows: [["Swift", "native", "fast"]])
        let geometry = TableGeometry(model: model, theme: .system)
        let bold = NSAttributedString(
            string: "Language",
            attributes: [.font: NSFont.boldSystemFont(ofSize: Theme.system.baseFontSize)])
        let needed = ceil(bold.size().width) + TableGeometry.cellPaddingX * 2
        #expect(geometry.columnWidths[0] >= needed)
    }

    @Test func aTableWithBoldHeadersIsNoTallerThanItsRowCount() {
        let model = TableModel(header: ["Language", "Parser", "Speed"],
                               alignments: [.left, .left, .right],
                               rows: [["Swift", "native", "fast"], ["C", "cmark", "fastest"]])
        let geometry = TableGeometry(model: model, theme: .system)
        // Three single-line rows. A wrapped header would make the first taller.
        #expect(geometry.rowHeights.count == 3)
        #expect(geometry.rowHeights[0] <= geometry.rowHeights[1] + 2)
    }
}
