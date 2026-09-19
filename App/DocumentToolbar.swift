import AppKit
import MarkdownCore

extension NSToolbarItem.Identifier {
    static let sourceToggle = NSToolbarItem.Identifier("ch.sala.bsmv.sourceToggle")
    static let outlineToggle = NSToolbarItem.Identifier("ch.sala.bsmv.outlineToggle")
    static let bookmark = NSToolbarItem.Identifier("ch.sala.bsmv.bookmark")
    static let export = NSToolbarItem.Identifier("ch.sala.bsmv.export")
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

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sourceToggle, .outlineToggle, .taskFilter, .flexibleSpace,
         .matchCount, .search, .findOptions, .bookmark, .export]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sourceToggle, .outlineToggle, .taskFilter, .bookmark, .export, .search, .matchCount, .findOptions,
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
            button.menu = NSMenu()
            button.menu?.delegate = self
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
            let item = NSToolbarItem(itemIdentifier: identifier)
            let button = NSPopUpButton(frame: .zero, pullsDown: true)
            button.bezelStyle = .toolbar
            button.imagePosition = .imageOnly
            let menu = NSMenu()
            let icon = NSMenuItem()
            icon.image = NSImage(systemSymbolName: "square.and.arrow.up",
                                 accessibilityDescription: "Export")
            menu.addItem(icon)
            let pdf = NSMenuItem(title: "Export as PDF…",
                                 action: #selector(MarkdownDocument.exportAsPDF(_:)),
                                 keyEquivalent: "")
            menu.addItem(pdf)
            let print = NSMenuItem(title: "Print…",
                                   action: #selector(NSView.printView(_:)), keyEquivalent: "")
            menu.addItem(print)
            item.view = button
            item.label = "Export"
            item.toolTip = "Export as PDF or print"
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
