import AppKit
import MarkdownCore

/// Shown in place of the document when a task filter matches nothing.
///
/// Deliberately built as chrome rather than as a line of body text: system UI
/// font, window background, a real button. A sentence rendered in the document's
/// own typography reads like something the file actually contains, which is
/// exactly the wrong impression when the file contains nothing of the sort.
final class TaskFilterEmptyView: NSView {
    var onShowEverything: (() -> Void)?

    private let detailLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Opaque, because it stands in for the document rather than floating over it.
    override var isOpaque: Bool { true }

    /// Filled here rather than through a layer so the colour re-resolves when
    /// the window switches between light and dark.
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }

    /// Describes the filter that came up empty, and the mode it applies to.
    func update(states: Set<Checkbox.State>, showingSource: Bool) {
        let names = Checkbox.State.allCases
            .filter { states.contains($0) }
            .map { $0.title.lowercased() }
        let subject: String
        switch names.count {
        case 0: subject = "tasks"
        case 1: subject = "tasks marked \(names[0])"
        default: subject = "tasks marked " + names.dropLast().joined(separator: ", ")
            + " or " + names[names.count - 1]
        }
        detailLabel.stringValue = showingSource
            ? "The source of this document has no \(subject)."
            : "This document has no \(subject)."
    }

    private func build() {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "checklist.unchecked",
                             accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 34, weight: .regular)
        icon.contentTintColor = .tertiaryLabelColor

        let title = NSTextField(labelWithString: "No matching tasks in this document")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.alignment = .center

        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .tertiaryLabelColor
        detailLabel.alignment = .center

        let button = NSButton(title: "Show Everything", target: self,
                              action: #selector(showEverything(_:)))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"

        let stack = NSStackView(views: [icon, title, detailLabel, button])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(18, after: detailLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
        ])

        setAccessibilityRole(.group)
        setAccessibilityLabel("No matching tasks")
    }

    @objc private func showEverything(_ sender: Any?) {
        onShowEverything?()
    }
}
