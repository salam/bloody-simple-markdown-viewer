import AppKit
import MarkdownCore

/// Implements the window and tab rule.
///
/// AppKit has no built-in notion of "these files were opened together". The
/// system-wide "prefer tabs" preference groups by window creation time, which
/// cannot express the rule we want, so the batching is done explicitly here.
final class DocumentController: NSDocumentController {

    /// Opens a batch of URLs. The first opens a window; the rest join it as
    /// tabs. Passing a `joining` window puts all of them into that window
    /// instead, which is what a drop onto an open window does.
    func openBatch(_ urls: [URL], joining host: NSWindow?) {
        guard !urls.isEmpty else { return }
        open(Array(urls), joining: host)
    }

    private func open(_ remaining: [URL], joining host: NSWindow?) {
        guard let url = remaining.first else { return }
        let rest = Array(remaining.dropFirst())

        openDocument(withContentsOf: url, display: false) { [weak self] document, alreadyOpen, error in
            guard let self else { return }

            if let error {
                self.presentError(error)
                self.open(rest, joining: host)
                return
            }
            guard let document = document as? MarkdownDocument else {
                self.open(rest, joining: host)
                return
            }

            // Reopening a document that is already showing just brings it forward.
            if alreadyOpen, let existing = document.windowControllers.first?.window {
                existing.makeKeyAndOrderFront(nil)
                self.open(rest, joining: host ?? existing)
                return
            }

            if document.windowControllers.isEmpty {
                document.makeWindowControllers()
            }
            guard let window = document.windowControllers.first?.window else {
                self.open(rest, joining: host)
                return
            }

            if let host, host !== window {
                // Windows are created with tabbing disallowed so the system
                // never groups separate opens. Enable it for the moment it
                // takes to join this batch, then put it back.
                let hostMode = host.tabbingMode
                host.tabbingMode = .preferred
                window.tabbingMode = .preferred
                host.addTabbedWindow(window, ordered: .above)
                host.tabbingMode = hostMode
                window.tabbingMode = .disallowed
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: false)

            // Everything after the first in a batch joins the window we just made.
            self.open(rest, joining: host ?? window)
        }
    }
}
