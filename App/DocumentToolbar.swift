import AppKit
import MarkdownCore
import UniformTypeIdentifiers

extension NSToolbarItem.Identifier {
    static let sourceToggle = NSToolbarItem.Identifier("ch.sala.bsmv.sourceToggle")
    static let outlineToggle = NSToolbarItem.Identifier("ch.sala.bsmv.outlineToggle")
    static let bookmark = NSToolbarItem.Identifier("ch.sala.bsmv.bookmark")
    static let export = NSToolbarItem.Identifier("ch.sala.bsmv.export")
    static let share = NSToolbarItem.Identifier("ch.sala.bsmv.share")
    static let taskFilter = NSToolbarItem.Identifier("ch.sala.bsmv.taskFilter")
    static let search = NSToolbarItem.Identifier("ch.sala.bsmv.search")
    static let matchCount = NSToolbarItem.Identifier("ch.sala.bsmv.matchCount")
    static let findOptions = NSToolbarItem.Identifier("ch.sala.bsmv.findOptions")
}

/// Builds the window's toolbar.
///
/// The toolbar uses the unified compact style with the window title hidden, so
/// its controls sit in the same row as the close, minimise and zoom buttons and
/// the document tabs. That removes a whole band of chrome and leaves the
/// maximum vertical space for the document, which is the point of the app.
extension DocumentWindowController: NSToolbarDelegate {

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "ch.sala.bsmv.document")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        return toolbar
    }

    /// Export is deliberately not here. Sharing covers the common case in one
    /// click, and PDF export stays one drag away in Customise Toolbar for
    /// anyone who wants it, as well as in the File menu.
    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sourceToggle, .outlineToggle, .taskFilter, .flexibleSpace,
         .matchCount, .search, .findOptions, .bookmark, .share]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sourceToggle, .outlineToggle, .taskFilter, .bookmark, .share, .export,
         .search, .matchCount, .findOptions,
         .flexibleSpace, .space, .sidebarTrackingSeparator]
    }

    public func toolbar(_ toolbar: NSToolbar,
                        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                        willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case .sourceToggle:
            return button(identifier, symbol: "chevron.left.forwardslash.chevron.right",
                          label: "Source", tooltip: "Toggle between rendered Markdown and source",
                          action: #selector(toggleSourceMode(_:)))

        case .outlineToggle:
            return button(identifier, symbol: "list.bullet.indent",
                          label: "Outline", tooltip: "Show or hide the document outline",
                          action: #selector(toggleOutline(_:)))

        case .bookmark:
            let item = NSToolbarItem(itemIdentifier: identifier)
            let button = NSPopUpButton(frame: .zero, pullsDown: true)
            button.bezelStyle = .toolbar
            button.imagePosition = .imageOnly
            // A pull-down button draws its first menu item's image, so the menu
            // cannot start empty: `menuNeedsUpdate` only fires when the menu is
            // about to open, which left a bare chevron in the toolbar until
            // someone clicked the thing they could not see.
            let menu = NSMenu()
            menu.delegate = self
            let icon = NSMenuItem()
            icon.image = NSImage(systemSymbolName: "bookmark", accessibilityDescription: "Bookmarks")
            menu.addItem(icon)
            button.menu = menu
            bookmarkButton = button
            item.view = button
            item.label = "Bookmarks"
            item.toolTip = "Bookmarks in this document"
            return item

        case .taskFilter:
            let item = NSToolbarItem(itemIdentifier: identifier)
            let button = NSPopUpButton(frame: .zero, pullsDown: true)
            button.bezelStyle = .toolbar
            button.imagePosition = .imageOnly
            let menu = NSMenu()
            let icon = NSMenuItem()
            icon.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Tasks")
            menu.addItem(icon)
            let all = NSMenuItem(title: "Show Everything",
                                 action: #selector(clearTaskFilter(_:)), keyEquivalent: "")
            all.target = self
            menu.addItem(all)
            menu.addItem(.separator())
            for state in Checkbox.State.allCases {
                let entry = NSMenuItem(title: "Only \(state.title)",
                                       action: #selector(toggleTaskFilter(_:)), keyEquivalent: "")
                entry.representedObject = state.rawValue
                entry.target = self
                menu.addItem(entry)
            }
            button.menu = menu
            taskFilterButton = button
            item.view = button
            item.label = "Tasks"
            item.toolTip = "Show only task items"
            return item

        case .export:
            // Was a pull-down whose menu was built and then never assigned, so
            // it drew as an empty chevron and did nothing at all. One button,
            // one action.
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.image = Self.pdfIcon
            item.label = "Export PDF"
            item.paletteLabel = "Export as PDF"
            item.toolTip = "Export the rendered document as a PDF"
            item.target = nil          // routed to the document via the responder chain
            item.action = #selector(MarkdownDocument.exportAsPDF(_:))
            item.isBordered = true
            return item

        case .share:
            let item = NSToolbarItem(itemIdentifier: identifier)
            let button = NSButton(image: NSImage(systemSymbolName: "square.and.arrow.up",
                                                 accessibilityDescription: "Share")!,
                                  target: self, action: #selector(shareDocument(_:)))
            button.bezelStyle = .toolbar
            button.imagePosition = .imageOnly
            // Kept as a view because the share sheet is a popover and needs
            // something on screen to point at.
            shareButton = button
            item.view = button
            item.label = "Share"
            item.paletteLabel = "Share"
            item.toolTip = "Share this document"
            return item

        case .search:
            let item = NSToolbarItem(itemIdentifier: identifier)
            let field = NSSearchField()
            field.placeholderString = "Find"
            field.sendsWholeSearchString = false
            field.sendsSearchStringImmediately = true
            field.target = self
            field.action = #selector(searchFieldChanged(_:))
            field.delegate = self
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
            searchField = field
            item.view = field
            item.label = "Find"
            item.toolTip = "Find in document"
            item.visibilityPriority = .high
            return item

        case .matchCount:
            let item = NSToolbarItem(itemIdentifier: identifier)
            let label = NSTextField(labelWithString: "")
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 62).isActive = true
            matchCountLabel = label
            item.view = label
            item.label = "Matches"
            return item

        case .findOptions:
            let item = NSToolbarItem(itemIdentifier: identifier)
            let button = NSPopUpButton(frame: .zero, pullsDown: true)
            button.bezelStyle = .toolbar
            button.imagePosition = .imageOnly
            let menu = NSMenu()
            let title = NSMenuItem()
            title.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: nil)
            menu.addItem(title)
            for (tag, name) in [(1, "Regular Expression"), (2, "Match Case"), (3, "Whole Words")] {
                let entry = NSMenuItem(title: name, action: #selector(toggleFindOption(_:)),
                                       keyEquivalent: "")
                entry.tag = tag
                entry.target = self
                menu.addItem(entry)
            }
            button.menu = menu
            findOptionsButton = button
            item.view = button
            item.label = "Options"
            item.toolTip = "Search options"
            return item

        default:
            return nil
        }
    }

    /// The system's own icon for the PDF type. No SF Symbol reads as "PDF",
    /// and this is the picture people already associate with one.
    private static let pdfIcon: NSImage = {
        let icon = NSWorkspace.shared.icon(for: .pdf)
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }()

    private func button(_ identifier: NSToolbarItem.Identifier, symbol: String,
                        label: String, tooltip: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.label = label
        item.paletteLabel = label
        item.toolTip = tooltip
        item.target = self
        item.action = action
        item.isBordered = true
        return item
    }
}
