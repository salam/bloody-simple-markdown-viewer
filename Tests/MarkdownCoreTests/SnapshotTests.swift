import AppKit
import Testing
@testable import MarkdownCore

/// Minimal NSTextLocation so the view provider can be requested without a
/// live text layout manager.
private final class NSTextLocation_Stub: NSObject, NSTextLocation {
    func compare(_ location: any NSTextLocation) -> ComparisonResult { .orderedSame }
}

@MainActor
@Suite("Table rendering")
struct TableRenderingSnapshotTests {
    static let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("markdown-snapshots")

    private static func write(_ rep: NSBitmapImageRep, named name: String) {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: outputDirectory.appendingPathComponent("\(name).png"))
        }
    }

    private static let sampleModel = TableModel(
        header: ["Language", "Parser", "Speed"],
        alignments: [.left, .left, .right],
        rows: [["Swift", "native", "fast"],
               ["C", "cmark-gfm", "fastest"],
               ["JavaScript", "none", "n/a"]]
    )

    /// Draws the table view on its own, with no TextKit involved, so a failure
    /// here is unambiguously in the drawing code.
    @Test func tableViewDrawsItsContent() {
        let attachment = TableTextAttachment(model: Self.sampleModel, theme: .system)
        let view = attachment.makeContainerView()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            Issue.record("no bitmap")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        Self.write(rep, named: "table-view")

        // The drawn table must differ from a blank canvas across many rows.
        var inkedRows = 0
        for y in stride(from: 2, to: rep.pixelsHigh - 2, by: 3) {
            var distinct = Set<String>()
            for x in stride(from: 2, to: rep.pixelsWide - 2, by: 3) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                distinct.insert(String(format: "%.1f,%.1f,%.1f",
                                       c.redComponent, c.greenComponent, c.blueComponent))
            }
            if distinct.count > 1 { inkedRows += 1 }
        }
        #expect(inkedRows > 10, "table drew \(inkedRows) inked rows; expected a filled grid")
        #expect(rep.pixelsWide > 200)
    }

    /// Everything needed for TextKit to host the table, checked without
    /// relying on a real window.
    ///
    /// Provider instantiation itself cannot be tested here: the viewport
    /// layout controller only creates attachment views for a window backed by
    /// a real window-server session, which a headless test process does not
    /// have. Offscreen, the attachment always falls back to its placeholder.
    /// The live app is the check for that.
    @Test func attachmentIsConfiguredForViewHosting() {
        let attachment = TableTextAttachment(model: Self.sampleModel, theme: .system)
        #expect(attachment.allowsTextAttachmentView,
                "without this the layout system never asks for a view provider")
        #expect(attachment.bounds.size == attachment.measuredSize)

        // A transparent image, so the generic document icon is not painted
        // over the hosted view.
        #expect(attachment.image != nil)
        #expect(attachment.image?.size == NSSize(width: 1, height: 1))

        let provider = attachment.viewProvider(
            for: nil,
            location: NSTextLocation_Stub(),
            textContainer: nil
        )
        #expect(provider is TableViewProvider)
        #expect(provider?.tracksTextAttachmentViewBounds == true)
    }

    @Test func attachmentProvidesAViewProvider() {
        let attachment = TableTextAttachment(model: Self.sampleModel, theme: .system)
        let view = attachment.makeContainerView()
        #expect(view is TableView)
        #expect(view.frame.size == attachment.measuredSize)
    }
}
