import AppKit
import MarkdownCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let documentController: DocumentController

    init(documentController: DocumentController) {
        self.documentController = documentController
        super.init()
    }

    /// Files opened together arrive here as one batch, whether from Finder,
    /// `open a.md b.md`, or a drop on the Dock icon. A batch becomes one
    /// window with tabs; a separate open becomes a separate window.
    /// Kept for completeness. In a document-based app NSDocumentController
    /// handles the odoc Apple Event itself and this is never called, which is
    /// why the window and tab rule lives in DocumentController instead.
    func application(_ application: NSApplication, open urls: [URL]) {
        documentController.openBatch(urls, joining: nil)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DefaultHandler.offerOnFirstRunIfNeeded()
    }
}

// MARK: - Application-level commands

extension AppDelegate {
    @IBAction func makeDefaultMarkdownApp(_ sender: Any?) {
        DefaultHandler.makeDefault()
    }

    @IBAction func openProjectPage(_ sender: Any?) {
        guard let url = URL(string: "https://github.com/salam/bloody-simple-markdown-viewer") else { return }
        NSWorkspace.shared.open(url)
    }

    @IBAction func showSyntaxGuide(_ sender: Any?) {
        guard let url = URL(string: "https://github.github.com/gfm/") else { return }
        NSWorkspace.shared.open(url)
    }
}
