import AppKit
import MarkdownCore

/// One Markdown file.
///
/// Holds the source as the single source of truth and re-renders on demand.
/// There is deliberately no autosave: silently rewriting someone's file from
/// something billed as a viewer is a bad default.
final class MarkdownDocument: NSDocument {
    private(set) var source: String = ""
    private(set) var rendered: RenderedDocument = .empty
    var theme: Theme = .system

    /// True when the window is showing editable source rather than rendered output.
    var isShowingSource = false

    override class var autosavesInPlace: Bool { false }

    override func makeWindowControllers() {
        let controller = DocumentWindowController()
        addWindowController(controller)
        controller.load(document: self)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError)
        }
        source = text
        rerender()
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let data = source.data(using: .utf8) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError)
        }
        return data
    }

    /// Called by the window controller when the user edits in source mode.
    func updateSource(_ newValue: String) {
        guard newValue != source else { return }
        source = newValue
        updateChangeCount(.changeDone)
    }

    func rerender() {
        rendered = DocumentRenderer(theme: theme, baseURL: fileURL).render(source: source)
    }

    // MARK: Printing

    /// NSDocument routes Cmd-P here, so printing works from the menu, the
    /// toolbar and the responder chain without any extra wiring.
    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any])
        throws -> NSPrintOperation {
        let info = DocumentPrinter.defaultPrintInfo()
        for (key, value) in printSettings {
            info.dictionary()[key] = value
        }
        return DocumentPrinter.operation(source: source,
                                         title: displayName ?? "Document",
                                         baseURL: fileURL,
                                         printInfo: info)
    }

    /// Exports the rendered document as a PDF.
    @IBAction func exportAsPDF(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (displayName as NSString?)?
            .deletingPathExtension.appending(".pdf") ?? "Document.pdf"
        panel.canCreateDirectories = true
        panel.message = "Export the rendered Markdown as a PDF."

        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            DocumentPrinter.writePDF(source: self.source,
                                     title: self.displayName ?? "Document",
                                     baseURL: self.fileURL,
                                     to: url)
        }
        if let window = windowControllers.first?.window {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            complete(panel.runModal())
        }
    }

    /// Reload after the file changed on disk underneath us.
    override func presentedItemDidChange() {
        guard let url = fileURL, !isDocumentEdited else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let text = try? String(contentsOf: url, encoding: .utf8), text != self.source else { return }
            self.source = text
            self.rerender()
            for controller in self.windowControllers {
                (controller as? DocumentWindowController)?.refresh()
            }
        }
    }
}
