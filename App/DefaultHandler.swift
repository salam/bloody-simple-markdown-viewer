import AppKit
import UniformTypeIdentifiers

/// Offers to become the default Markdown application.
///
/// Always an explicit, user-initiated choice. An app that silently seizes file
/// associations on first launch is behaving badly, regardless of whether the
/// API happens to allow it.
enum DefaultHandler {
    private static let promptedKey = "HasOfferedDefaultHandler"

    static var markdownType: UTType {
        UTType("net.daringfireball.markdown") ?? .plainText
    }

    static var isDefault: Bool {
        guard let current = NSWorkspace.shared.urlForApplication(toOpen: markdownType) else {
            return false
        }
        return current == Bundle.main.bundleURL
    }

    static func offerOnFirstRunIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: promptedKey), !isDefault else { return }
        defaults.set(true, forKey: promptedKey)

        // Let the first window settle before interrupting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let alert = NSAlert()
            alert.messageText = "Open Markdown files with this app?"
            alert.informativeText = """
            Set A Bloody Simple Markdown Viewer as the default application for \
            Markdown files, so double-clicking a .md file opens it here.

            You can change this later in the app menu.
            """
            alert.addButton(withTitle: "Make Default")
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() == .alertFirstButtonReturn {
                makeDefault()
            }
        }
    }

    static func makeDefault() {
        NSWorkspace.shared.setDefaultApplication(
            at: Bundle.main.bundleURL,
            toOpen: markdownType
        ) { error in
            guard let error else { return }
            DispatchQueue.main.async {
                NSAlert(error: error).runModal()
            }
        }
    }
}
