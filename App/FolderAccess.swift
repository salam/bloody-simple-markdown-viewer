import AppKit

/// Folders the reader has let this app read.
///
/// The app is sandboxed. Opening a document grants access to that one file, so
/// a snippet living in a sibling file is unreadable no matter how ordinary the
/// path looks. The only way through is to ask, so the reader is asked once per
/// folder and the answer is kept as a security-scoped bookmark.
///
/// Declining is remembered for the session, so a document full of snippets in a
/// folder you said no to does not ask again on every re-render.
@MainActor
final class FolderAccess {
    static let shared = FolderAccess()

    private static let defaultsKey = "ch.sala.bsmv.folderGrants"

    /// Bookmark data by folder path.
    private var grants: [String: Data]
    /// Folders resolved and opened this run. Access has to stay open for as
    /// long as we might read, and closing it is the app quitting.
    private var open: Set<URL> = []
    /// Folders the reader has already declined, so we ask at most once.
    private var declined: Set<String> = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        grants = defaults.dictionary(forKey: Self.defaultsKey) as? [String: Data] ?? [:]
    }

    /// Reads a file, if it is inside a folder we are allowed to read.
    ///
    /// Returns nil rather than throwing: a snippet that cannot be read is a
    /// warning in the document, not a failure of the document.
    func read(_ url: URL) -> String? {
        guard ensureOpen(url.deletingLastPathComponent()) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Asks for a document's folder, if it needs snippets and has not been
    /// granted yet. Call once per window, from the main thread.
    func requestAccessIfNeeded(forDocumentAt url: URL, in window: NSWindow?) {
        let folder = url.deletingLastPathComponent().standardizedFileURL
        guard !ensureOpen(folder), !declined.contains(folder.path) else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.prompt = "Grant Access"
        panel.message = """
        This document pulls in other files from “\(folder.lastPathComponent)”. \
        Grant access to that folder so they can be shown. This is asked once per folder.
        """

        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            guard response == .OK, let granted = panel.url else {
                self.declined.insert(folder.path)
                return
            }
            self.store(granted.standardizedFileURL)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(panel.runModal())
        }
    }

    /// True when this folder, or one above it, is already granted and open.
    private func ensureOpen(_ folder: URL) -> Bool {
        let standardised = folder.standardizedFileURL
        if open.contains(where: { standardised.path == $0.path
            || standardised.path.hasPrefix($0.path + "/") }) { return true }

        // Walk up: a grant on a parent covers everything under it.
        var candidate = standardised
        while true {
            if let data = grants[candidate.path], resolve(data, expecting: candidate) { return true }
            let parent = candidate.deletingLastPathComponent().standardizedFileURL
            if parent.path == candidate.path { return false }
            candidate = parent
        }
    }

    private func resolve(_ data: Data, expecting folder: URL) -> Bool {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [.withSecurityScope],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return false }
        open.insert(url.standardizedFileURL)
        // A stale bookmark still resolved, so refresh it while we hold access.
        if stale { store(url.standardizedFileURL) }
        return true
    }

    private func store(_ folder: URL) {
        guard let data = try? folder.bookmarkData(options: .withSecurityScope,
                                                  includingResourceValuesForKeys: nil,
                                                  relativeTo: nil) else { return }
        grants[folder.path] = data
        defaults.set(grants, forKey: Self.defaultsKey)
        if folder.startAccessingSecurityScopedResource() {
            open.insert(folder)
        }
    }
}
