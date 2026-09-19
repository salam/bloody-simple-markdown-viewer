import AppKit
import MarkdownCore

final class DocumentWindowController: NSWindowController, NSWindowDelegate,
                                      NSTextViewDelegate, NSMenuItemValidation,
                                      NSSearchFieldDelegate {
    private var splitView: NSSplitView!
    private var outlineScrollView: NSScrollView!
    private var outlineTable: NSTableView!
    private(set) var scrollView: MarkdownScrollView!

    // Toolbar controls, retained by the toolbar delegate as it builds them.
    var searchField: NSSearchField?
    var matchCountLabel: NSTextField?
    var findOptionsButton: NSPopUpButton?
    var taskFilterButton: NSPopUpButton?

    private var searchOptions = SearchOptions()
    private var matches: [NSRange] = []
    private var currentMatch: Int?
    private var isOutlineVisible = false
    /// Empty means no filter: the whole document is shown.
    private var taskFilterStates: Set<Checkbox.State> = []
    private var zoomStep = 0

    private var markdownDocument: MarkdownDocument? { document as? MarkdownDocument }
    private var textView: MarkdownTextView { scrollView.markdownTextView }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Controls share the row with the traffic lights and the document tabs,
        // so the window carries no separate chrome band.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unifiedCompact
        // Disallowed by default so macOS never folds a separately-opened file
        // into an existing window; DocumentController tabs batches explicitly.
        window.tabbingMode = .disallowed
        window.tabbingIdentifier = "ch.sala.BloodySimpleMarkdownViewer.document"
        window.setFrameAutosaveName("MarkdownDocumentWindow")
        window.isRestorable = false
        window.minSize = NSSize(width: 480, height: 320)
        self.init(window: window)
        window.delegate = self
        window.toolbar = makeToolbar()
        setUpContent()
    }

    private func setUpContent() {
        scrollView = MarkdownScrollView(theme: .system)
        scrollView.markdownTextView.delegate = self
        // A double-click in the render opens the source at that spot.
        scrollView.markdownTextView.onJumpToSource = { [weak self] sourceOffset in
            self?.revealInSource(sourceOffset: sourceOffset)
        }

        scrollView.markdownTextView.onFileDrop = { [weak self] urls in
            guard let self,
                  let controller = NSDocumentController.shared as? DocumentController else { return }
            // A file dropped on this window becomes a tab of this window.
            controller.openBatch(urls, joining: self.window)
        }

        outlineTable = NSTableView()
        outlineTable.headerView = nil
        outlineTable.rowHeight = 22
        outlineTable.backgroundColor = .clear
        outlineTable.style = .sourceList
        outlineTable.selectionHighlightStyle = .regular
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("heading"))
        column.resizingMask = .autoresizingMask
        outlineTable.addTableColumn(column)
        outlineTable.dataSource = self
        outlineTable.delegate = self
        outlineTable.target = self
        outlineTable.action = #selector(outlineRowClicked(_:))

        outlineScrollView = NSScrollView()
        outlineScrollView.documentView = outlineTable
        outlineScrollView.hasVerticalScroller = true
        outlineScrollView.drawsBackground = false
        outlineScrollView.automaticallyAdjustsContentInsets = false
        outlineScrollView.contentInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(outlineScrollView)
        splitView.addArrangedSubview(scrollView)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)

        guard let contentView = window?.contentView else { return }
        contentView.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        setOutlineVisible(false, animated: false)
    }

    func load(document: MarkdownDocument) {
        refresh()
    }

    /// Re-applies the document to the view in whichever mode is current.
    func refresh() {
        guard let document = markdownDocument else { return }
        document.theme = themeForCurrentZoom()
        if document.isShowingSource {
            textView.displaySource(document.source, theme: document.theme)
            textView.isEditable = true
        } else {
            document.rerender()
            textView.theme = document.theme
            if taskFilterStates.isEmpty {
                textView.display(document.rendered)
            } else {
                // Filtered lines keep their source offsets, so double-clicking
                // one still jumps to the right place in the real document.
                textView.displayFiltered(
                    TaskFilter.filtered(document.rendered,
                                        states: taskFilterStates,
                                        theme: document.theme))
            }
            textView.isEditable = false
        }
        window?.title = document.displayName
        window?.tab.title = document.displayName
        outlineTable.reloadData()
        updateTaskFilterMenu()
        runSearch()
    }

    private func themeForCurrentZoom() -> Theme {
        var theme = Theme.system
        theme.baseFontSize = max(9, min(30, 14 + CGFloat(zoomStep)))
        return theme
    }

    // MARK: Source toggle

    @IBAction func toggleSourceMode(_ sender: Any?) {
        guard let document = markdownDocument else { return }
        // Hold the reading position across the switch, using the source offset
        // every rendered run carries.
        let visible = textView.characterIndexForInsertion(at: scrollView.contentView.bounds.origin)

        if document.isShowingSource {
            document.updateSource(textView.string)
            document.isShowingSource = false
            refresh()
            scrollView.scrollToCharacterOffset(
                document.rendered.characterOffset(forSourceOffset: visible))
        } else {
            let sourceOffset = document.rendered.sourceOffset(forCharacterOffset: visible)
            document.isShowingSource = true
            refresh()
            scrollView.scrollToCharacterOffset(min(sourceOffset, textView.string.utf16.count))
        }
    }

    /// Switches to source mode and puts the caret at a source offset.
    func revealInSource(sourceOffset: Int) {
        guard let document = markdownDocument else { return }
        if !document.isShowingSource {
            document.isShowingSource = true
            refresh()
        }
        let length = (textView.string as NSString).length
        let target = min(max(sourceOffset, 0), length)
        // Select the whole line, so the destination is obvious rather than an
        // invisible caret somewhere in the middle of a paragraph.
        let line = (textView.string as NSString).lineRange(for: NSRange(location: target, length: 0))
        textView.reveal(line)
        window?.makeFirstResponder(textView)
    }

    // MARK: Outline

    @IBAction func toggleOutline(_ sender: Any?) {
        setOutlineVisible(!isOutlineVisible, animated: true)
    }

    private func setOutlineVisible(_ visible: Bool, animated: Bool) {
        isOutlineVisible = visible
        outlineScrollView.isHidden = !visible
        if visible {
            splitView.setPosition(232, ofDividerAt: 0)
            outlineTable.reloadData()
        } else {
            splitView.setPosition(0, ofDividerAt: 0)
        }
        splitView.adjustSubviews()
    }

    @objc private func outlineRowClicked(_ sender: Any?) {
        let row = outlineTable.clickedRow >= 0 ? outlineTable.clickedRow : outlineTable.selectedRow
        guard let document = markdownDocument, row >= 0, row < document.rendered.outline.count else { return }
        let entry = document.rendered.outline[row]
        let target = document.isShowingSource
            ? min(entry.sourceOffset, textView.string.utf16.count)
            : entry.characterOffset
        scrollView.scrollToCharacterOffset(target)
    }

    // MARK: Task filter

    @objc func toggleTaskFilter(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let state = Checkbox.State(rawValue: raw) else { return }
        // Picking a state shows only that state; picking it again clears it.
        taskFilterStates = taskFilterStates == [state] ? [] : [state]
        updateTaskFilterMenu()
        refresh()
    }

    @objc func clearTaskFilter(_ sender: Any?) {
        taskFilterStates = []
        updateTaskFilterMenu()
        refresh()
    }

    private func updateTaskFilterMenu() {
        guard let menu = taskFilterButton?.menu else { return }
        for item in menu.items {
            guard let raw = item.representedObject as? String,
                  let state = Checkbox.State(rawValue: raw) else { continue }
            item.state = taskFilterStates.contains(state) ? .on : .off
            if let document = markdownDocument {
                let count = TaskFilter.taskCount(in: document.rendered, state: state)
                item.title = "Only \(state.title)  (\(count))"
                item.isEnabled = count > 0
            }
        }
        // Make it obvious at a glance that a filter is on.
        taskFilterButton?.contentTintColor = taskFilterStates.isEmpty ? nil : .controlAccentColor
    }

    // MARK: Zoom

    @IBAction func zoomIn(_ sender: Any?) { zoomStep = min(zoomStep + 1, 16); refresh() }
    @IBAction func zoomOut(_ sender: Any?) { zoomStep = max(zoomStep - 1, -5); refresh() }
    @IBAction func resetZoom(_ sender: Any?) { zoomStep = 0; refresh() }

    // MARK: Search

    @IBAction func showFind(_ sender: Any?) {
        guard let field = searchField else { return }
        window?.makeFirstResponder(field)
    }

    @objc func searchFieldChanged(_ sender: Any?) {
        currentMatch = nil
        runSearch()
        if !matches.isEmpty { moveToMatch(forward: true) }
    }

    @IBAction func findNext(_ sender: Any?) { moveToMatch(forward: true) }
    @IBAction func findPrevious(_ sender: Any?) { moveToMatch(forward: false) }

    @objc func toggleFindOption(_ sender: NSMenuItem) {
        switch sender.tag {
        case 1: searchOptions.isRegularExpression.toggle()
        case 2: searchOptions.isCaseSensitive.toggle()
        case 3: searchOptions.matchesWholeWords.toggle()
        default: break
        }
        sender.state = sender.state == .on ? .off : .on
        currentMatch = nil
        runSearch()
    }

    private func runSearch() {
        let query = searchField?.stringValue ?? ""
        guard !query.isEmpty else {
            matches = []
            currentMatch = nil
            textView.clearHighlights()
            matchCountLabel?.stringValue = ""
            return
        }
        do {
            matches = try DocumentSearch.matches(for: query, in: textView.string, options: searchOptions)
            matchCountLabel?.textColor = .secondaryLabelColor
            matchCountLabel?.stringValue = matches.isEmpty
                ? "none"
                : "\((currentMatch ?? 0) + 1) of \(matches.count)"
        } catch SearchError.invalidPattern {
            // Say so rather than silently matching nothing.
            matches = []
            matchCountLabel?.textColor = .systemRed
            matchCountLabel?.stringValue = "bad regex"
        } catch {
            matches = []
            matchCountLabel?.stringValue = ""
        }
        textView.highlight(matches: matches, current: currentMatch)
    }

    private func moveToMatch(forward: Bool) {
        guard !matches.isEmpty else { return }
        let from: Int
        if let current = currentMatch, current < matches.count {
            from = forward ? matches[current].location + 1 : matches[current].location
        } else {
            from = textView.selectedRange().location
        }
        currentMatch = DocumentSearch.indexOfMatch(at: from, in: matches, forward: forward)
        guard let index = currentMatch else { return }
        textView.highlight(matches: matches, current: index)
        textView.reveal(matches[index])
        matchCountLabel?.stringValue = "\(index + 1) of \(matches.count)"
    }

    // MARK: Bookmarks

    @IBAction func addBookmark(_ sender: Any?) {
        guard let document = markdownDocument, let url = document.fileURL else { return }
        let offset = document.isShowingSource
            ? textView.selectedRange().location
            : document.rendered.sourceOffset(
                forCharacterOffset: textView.characterIndexForInsertion(
                    at: scrollView.contentView.bounds.origin))
        BookmarkStore.shared.add(for: url, sourceOffset: offset,
                                 snippet: snippet(around: offset, in: document.source))
    }

    private func snippet(around offset: Int, in source: String) -> String {
        let ns = source as NSString
        let utf16Offset = min(max(offset, 0), max(ns.length - 1, 0))
        guard ns.length > 0 else { return "" }
        let line = ns.lineRange(for: NSRange(location: utf16Offset, length: 0))
        return ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Editing

    func textDidChange(_ notification: Notification) {
        guard let document = markdownDocument, document.isShowingSource else { return }
        document.updateSource(textView.string)
    }

    func windowWillClose(_ notification: Notification) {
        guard let document = markdownDocument, document.isShowingSource else { return }
        document.updateSource(textView.string)
    }

    // MARK: Menu validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleSourceMode(_:)):
            menuItem.title = (markdownDocument?.isShowingSource ?? false)
                ? "Show Rendered Markdown" : "Show Markdown Source"
            return markdownDocument != nil
        case #selector(toggleOutline(_:)):
            menuItem.title = isOutlineVisible ? "Hide Outline" : "Show Outline"
            return markdownDocument?.rendered.outline.isEmpty == false
        case #selector(findNext(_:)), #selector(findPrevious(_:)):
            return !matches.isEmpty
        case #selector(addBookmark(_:)):
            return markdownDocument?.fileURL != nil
        case #selector(toggleTaskFilter(_:)), #selector(clearTaskFilter(_:)):
            return !(markdownDocument.map { TaskFilter.statesPresent(in: $0.rendered).isEmpty } ?? true)
        default:
            return true
        }
    }
}

// MARK: - Outline list

extension DocumentWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        markdownDocument?.rendered.outline.count ?? 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let outline = markdownDocument?.rendered.outline, row < outline.count else { return nil }
        let entry = outline[row]

        let identifier = NSUserInterfaceItemIdentifier("outlineCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
            ?? {
                let created = NSTableCellView()
                created.identifier = identifier
                let label = NSTextField(labelWithString: "")
                label.lineBreakMode = .byTruncatingTail
                label.translatesAutoresizingMaskIntoConstraints = false
                created.addSubview(label)
                created.textField = label
                NSLayoutConstraint.activate([
                    label.centerYAnchor.constraint(equalTo: created.centerYAnchor),
                    label.trailingAnchor.constraint(equalTo: created.trailingAnchor, constant: -8)
                ])
                return created
            }()

        cell.textField?.stringValue = entry.title
        cell.textField?.font = .systemFont(ofSize: entry.level <= 2 ? 12 : 11,
                                           weight: entry.level == 1 ? .semibold : .regular)
        cell.textField?.textColor = entry.level <= 2 ? .labelColor : .secondaryLabelColor

        // Indent by heading level so the outline reads as a hierarchy.
        cell.constraints
            .filter { $0.firstAttribute == .leading }
            .forEach { cell.removeConstraint($0) }
        if let label = cell.textField {
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor,
                                           constant: 10 + CGFloat(entry.level - 1) * 12).isActive = true
        }
        return cell
    }
}
