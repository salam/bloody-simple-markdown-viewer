import AppKit
import MarkdownCore

/// Implements the window and tab rule.
///
/// Files opened together share one window with tabs; files opened separately
/// get separate windows.
///
/// The app delegate's `application(_:open:)` is *not* the hook for this. In a
/// document-based app `NSDocumentController` installs its own Apple Event
/// handler for `odoc` and opens each file directly, so that delegate method is
/// never called. Overriding the open here is the only point that actually sees
/// the files.
///
/// AppKit gives no "these arrived together" signal either, so opens are
/// coalesced by arrival time: Finder, `open a.md b.md` and a Dock drop all
/// deliver their files in one burst, whereas a later double-click arrives well
/// after. `batchInterval` is the dividing line.
final class DocumentController: NSDocumentController {
    /// A window that the next opens must join, set when files are dropped onto
    /// a specific window.
    private var forcedHost: NSWindow?
    /// The window the current burst of opens is collecting into.
    private var burstHost: NSWindow?
    private var burstExpiry: TimeInterval = 0
    private static let batchInterval: TimeInterval = 1.5

    /// Opens URLs, optionally forcing them into an existing window.
    /// A drop onto a window passes that window; everything else passes nil.
    func openBatch(_ urls: [URL], joining host: NSWindow?) {
        guard !urls.isEmpty else { return }
        forcedHost = host
        for url in urls {
            openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
        forcedHost = nil
    }

    override func openDocument(withContentsOf url: URL,
                               display displayDocument: Bool,
                               completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void) {
        let host = forcedHost
        // Always false: the window is placed here, after deciding whether it
        // is a tab or a window of its own.
        super.openDocument(withContentsOf: url, display: false) { [weak self] document, alreadyOpen, error in
            self?.place(document, alreadyOpen: alreadyOpen, forcedHost: host)
            completionHandler(document, alreadyOpen, error)
        }
    }

    private func place(_ document: NSDocument?, alreadyOpen: Bool, forcedHost host: NSWindow?) {
        guard let document = document as? MarkdownDocument else { return }
        if document.windowControllers.isEmpty {
            document.makeWindowControllers()
        }
        guard let window = document.windowControllers.first?.window else { return }

        // Reopening something already on screen just brings it forward.
        if alreadyOpen {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: false)
            return
        }

        let now = Date.timeIntervalSinceReferenceDate
        let target: NSWindow?
        if let host, host !== window, host.isVisible {
            target = host
        } else if now < burstExpiry, let burst = burstHost, burst !== window, burst.isVisible {
            target = burst
        } else {
            target = nil
        }

        if let target {
            join(window, to: target)
        } else {
            burstHost = window
        }

        burstExpiry = now + Self.batchInterval
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
    }

    /// Windows are created with tabbing disallowed so macOS never folds a
    /// separately-opened file into an existing window. Tabbing is enabled just
    /// long enough to join this one, then put back.
    private func join(_ window: NSWindow, to host: NSWindow) {
        let hostMode = host.tabbingMode
        host.tabbingMode = .preferred
        window.tabbingMode = .preferred
        host.addTabbedWindow(window, ordered: .above)
        host.tabbingMode = hostMode
        window.tabbingMode = .disallowed
    }
}
