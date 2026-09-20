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

    /// Draws a view into a bitmap through an explicit context.
    ///
    /// Not `cacheDisplay(in:to:)`: that needs a window-backed context, and in a
    /// headless `swift test` run it returns a blank canvas with no error, so
    /// the snapshot silently measures nothing.
    private static func render(_ view: NSView) -> NSBitmapImageRep? {
        let size = view.bounds.size
        guard size.width >= 1, size.height >= 1,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(size.width.rounded()),
                                         pixelsHigh: Int(size.height.rounded()),
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        // Opaque white first. A fresh bitmap is transparent, and the table
        // draws in black at varying alpha, so every pixel would come back with
        // identical RGB and the snapshot would read as blank.
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        if view.isFlipped {
            // The view draws y-down; a bitmap context is y-up.
            let flip = NSAffineTransform()
            flip.translateX(by: 0, yBy: size.height)
            flip.scaleX(by: 1, yBy: -1)
            flip.concat()
        }
        view.draw(view.bounds)
        context.flushGraphics()
        return rep
    }

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
        guard let rep = Self.render(view) else {
            Issue.record("no bitmap")
            return
        }
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
