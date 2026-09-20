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

    /// Lines another program changed while this document was open. Reset by
    /// construction, so the highlights last exactly as long as the window does.
    private(set) var changes = ChangeTracker()

    /// The source with snippets pulled in. Equal to `source` for the usual
    /// document, which has none. Printing and PDF export render from this;
    /// everything that addresses a position uses `source`.
    private(set) var expandedSource: String = ""
    /// Files this document pulls in, so a change to one of them is noticed too.
    private(set) var snippetFiles: [URL] = []

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
        // Our own edit adds no highlight, but it does move the lines the
        // existing ones sit on.
        changes.remap(from: source, to: newValue)
        source = newValue
        updateChangeCount(.changeDone)
    }

    func rerender() {
        let resolved = SnippetResolver.expand(source: source, baseURL: fileURL) { url in
            FolderAccess.shared.read(url)
        }
        expandedSource = resolved.text
        snippetFiles = resolved.referenced
        rendered = DocumentRenderer(theme: theme, baseURL: fileURL)
            .render(expanded: resolved.text, original: source, map: resolved.map)
    }

    /// True when this document asks for other files, without reading any of
    /// them. The window checks before deciding whether to ask for the folder.
    var needsSnippetAccess: Bool { SnippetResolver.containsDirectives(source) }

    // MARK: Printing

    /// NSDocument routes Cmd-P here, so printing works from the menu, the
    /// toolbar and the responder chain without any extra wiring.
    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any])
        throws -> NSPrintOperation {
        let info = DocumentPrinter.defaultPrintInfo()
        for (key, value) in printSettings {
            info.dictionary()[key] = value
        }
        // Printed from the expanded text: a snippet is part of the document as
        // far as the page is concerned.
        return DocumentPrinter.operation(source: expandedSource,
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
            DocumentPrinter.writePDF(source: self.expandedSource,
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
            // Record before replacing: the diff is the only thing that knows
            // which lines are new, and after the assignment the old text is
            // gone. Our own writes never reach here, because they leave the
            // file equal to what is already in `source`.
            self.changes.record(from: self.source, to: text)
            self.source = text
            self.rerender()
            for controller in self.windowControllers {
                (controller as? DocumentWindowController)?.refresh()
            }
        }
    }
}
