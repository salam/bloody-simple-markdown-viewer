import AppKit
import MarkdownCore

final class DocumentWindowController: NSWindowController, NSWindowDelegate,
                                      NSTextViewDelegate, NSMenuItemValidation,
                                      NSSearchFieldDelegate, NSMenuDelegate {
    private var splitView: NSSplitView!
    private var outlineScrollView: NSScrollView!
    private var outlineTable: NSTableView!
    private(set) var scrollView: MarkdownScrollView!
    private var emptyStateView: TaskFilterEmptyView!
    private var emptyStateTop: NSLayoutConstraint!

    // Toolbar controls, retained by the toolbar delegate as it builds them.
    var searchField: NSSearchField?
    var matchCountLabel: NSTextField?
    var findOptionsButton: NSPopUpButton?
    var taskFilterButton: NSPopUpButton?
    var bookmarkButton: NSPopUpButton?
    var shareButton: NSButton?

    private var searchOptions = SearchOptions()
    private var matches: [NSRange] = []
    private var currentMatch: Int?
    /// What the search field held last time it fired, so Return on an unchanged
    /// query can be told apart from a query that actually changed.
    private var lastQuery: String?
    private var isOutlineVisible = false
    /// Empty means no filter: the whole document is shown.
    private var taskFilterStates: Set<Checkbox.State> = []
    private var zoomStep = 0
    private var bookmarkFlashWork: DispatchWorkItem?

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

        // Ticking a checkbox is the rendered view's whole editing model.
        scrollView.markdownTextView.onToggleTask = { [weak self] sourceOffset, state in
            self?.toggleTask(atSourceOffset: sourceOffset, to: state)
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

        emptyStateView = TaskFilterEmptyView()
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.isHidden = true
        emptyStateView.onShowEverything = { [weak self] in self?.clearTaskFilter(nil) }
        contentView.addSubview(emptyStateView)
        // Covers the document, not the sidebar, so the outline stays usable.
        emptyStateTop = emptyStateView.topAnchor.constraint(equalTo: scrollView.topAnchor)
        NSLayoutConstraint.activate([
            emptyStateView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            emptyStateTop,
            emptyStateView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor)
        ])

        setOutlineVisible(false, animated: false)
    }

    func load(document: MarkdownDocument) {
        // Asked once per folder, and only for a document that actually pulls
        // other files in. The sandbox grants this app the one file it was
        // opened with and nothing beside it.
        if document.needsSnippetAccess, let url = document.fileURL {
            FolderAccess.shared.requestAccessIfNeeded(forDocumentAt: url, in: window)
        }
        refresh()
        appearanceObserver = window?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    private var appearanceObserver: NSKeyValueObservation?

    /// Re-applies the document to the view in whichever mode is current.
    func refresh() {
        guard let document = markdownDocument else { return }
        document.theme = themeForCurrentZoom()
        textView.theme = document.theme

        let filtering = !taskFilterStates.isEmpty
        // Source mode has no use for the render, except that the task filter
        // reads its states off it, so it does need one then.
        if filtering || !document.isShowingSource { document.rerender() }
        let matches = filtering
            ? TaskFilter.matchCount(in: document.rendered, states: taskFilterStates)
            : 0

        switch (document.isShowingSource, filtering) {
        case (true, false):
            textView.displaySource(document.source, theme: document.theme)
        case (true, true):
            textView.displayFiltered(
                TaskFilter.filteredSource(document.rendered,
                                          states: taskFilterStates,
                                          theme: document.theme))
        case (false, true):
            // Filtered lines keep their source offsets, so double-clicking
            // one still jumps to the right place in the real document.
            textView.displayFiltered(
                TaskFilter.filtered(document.rendered,
                                    states: taskFilterStates,
                                    theme: document.theme))
        case (false, false):
            textView.display(document.rendered)
        }
        textView.isEditable = isSourceEditable
        applyChangeHighlights(document)
        setEmptyStateVisible(filtering && matches == 0)

        window?.title = document.displayName
        window?.tab.title = document.displayName
        outlineTable.reloadData()
        updateTaskFilterMenu()
        runSearch()
    }

    /// Tints the lines another program changed while this document was open.
    ///
    /// Applied after the text is in place rather than during rendering, so it
    /// survives every mode: the marks are keyed to source lines and the runs on
    /// screen carry the source offsets to match them against.
    private func applyChangeHighlights(_ document: MarkdownDocument) {
        guard !document.changes.isEmpty, let storage = textView.textStorage else { return }
        storage.beginEditing()
        if document.isShowingSource, taskFilterStates.isEmpty {
            document.changes.markSourceRuns(in: storage, source: document.source)
        } else {
            document.changes.markRuns(in: storage, source: document.source)
        }
        storage.endEditing()
        textView.refreshViewport()
    }

    /// The source view is editable only when it shows the whole file. A
    /// filtered source view is a subset of the document; writing it back would
    /// delete every line the filter hid.
    private var isSourceEditable: Bool {
        (markdownDocument?.isShowingSource ?? false) && taskFilterStates.isEmpty
    }

    private func setEmptyStateVisible(_ visible: Bool) {
        emptyStateView.isHidden = !visible
        guard visible, let document = markdownDocument else { return }
        // The scroll view insets itself below the titlebar; match that, or the
        // message sits half a toolbar above the centre of what is on screen.
        emptyStateTop.constant = scrollView.contentInsets.top
        emptyStateView.update(states: taskFilterStates,
                              showingSource: document.isShowingSource)
    }

    private func themeForCurrentZoom() -> Theme {
        var theme = Theme.system
        theme.baseFontSize = max(9, min(30, 14 + CGFloat(zoomStep)))
        // Resolve against this window rather than the app, so a window forced
        // to one appearance still renders diagrams to match.
        if let appearance = window?.effectiveAppearance {
            theme.isDarkBackground = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
        return theme
    }

    /// Diagrams bake in their palette, so switching light and dark has to
    /// re-render rather than just recolour.
    func windowDidChangeBackingProperties(_ notification: Notification) {
        refresh()
    }

    // MARK: Source toggle

    @IBAction func toggleSourceMode(_ sender: Any?) {
        guard let document = markdownDocument else { return }
        // Hold the reading position across the switch, using the source offset
        // every rendered run carries.
        let visible = textView.characterIndexForInsertion(at: scrollView.contentView.bounds.origin)

        if document.isShowingSource {
            if isSourceEditable { document.updateSource(textView.string) }
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
        // Jumping to source means the real line in the real file, so a filter
        // hiding most of it has to come off first.
        let wasFiltered = !taskFilterStates.isEmpty
        taskFilterStates = []
        if !document.isShowingSource || wasFiltered {
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
                // Left selectable at zero on purpose: picking a state with no
                // matches is how you find out there are none, and the empty
                // state says so and offers the way back.
                item.title = "Only \(state.title)  (\(count))"
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
        let query = searchField?.stringValue ?? ""
        // The field sends this on every keystroke and again on Return. Only a
        // changed query restarts the search: Return on an unchanged one means
        // "next", and restarting would land on the hit the caret is already
        // sitting on and never leave it.
        guard query != lastQuery else {
            moveToMatch(forward: true)
            return
        }
        lastQuery = query
        currentMatch = nil
        runSearch()
        guard !matches.isEmpty else { return }
        currentMatch = DocumentSearch.indexOfMatch(at: textView.selectedRange().location,
                                                   in: matches, forward: true)
        revealCurrentMatch()
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
        lastQuery = nil
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

    /// Moves to the next or previous match, measured from what is selected now
    /// rather than from a remembered index, which the search field used to
    /// clear out from under it on every Return.
    private func moveToMatch(forward: Bool) {
        guard !matches.isEmpty else { return }
        currentMatch = DocumentSearch.indexOfMatch(after: textView.selectedRange(),
                                                   in: matches, forward: forward)
        revealCurrentMatch()
    }

    private func revealCurrentMatch() {
        guard let index = currentMatch, index < matches.count else { return }
        textView.highlight(matches: matches, current: index)
        textView.reveal(matches[index])
        matchCountLabel?.stringValue = "\(index + 1) of \(matches.count)"
    }

    // MARK: Sharing

    /// Hands the file to the system share sheet.
    ///
    /// Shares the document itself rather than a rendering of it, which is what
    /// every other document app does and what the recipient can edit. PDF is
    /// its own command.
    @IBAction func shareDocument(_ sender: Any?) {
        guard let document = markdownDocument, let url = document.fileURL else { return }
        // Save first, or the recipient gets the version on disk rather than the
        // one on screen.
        if document.isDocumentEdited {
            document.save(withDelegate: nil, didSave: nil, contextInfo: nil)
        }
        // The sheet is a popover and needs something on screen to point at.
        // The toolbar button when it is there, the document when it is not.
        let anchor: NSView = (sender as? NSView) ?? shareButton ?? scrollView
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    // MARK: Bookmarks

    @IBAction func addBookmark(_ sender: Any?) {
        guard let document = markdownDocument, let url = document.fileURL else { return }
        let offset = bookmarkTarget(in: document)
        let added = BookmarkStore.shared.add(
            for: url,
            sourceOffset: offset,
            snippet: SourceOffset.line(atByte: offset, in: document.source))
        // The same keystroke adds and removes, and neither changed anything
        // visible before, so the whole feature read as broken.
        updateBookmarkButton(flashing: added ? "bookmark.fill" : "bookmark.slash")
    }

    /// Where a new mark goes: the selection if the reader made one, otherwise
    /// the line at the top of the viewport, which is where they are reading.
    ///
    /// Answers in UTF-8 bytes, the unit `Bookmark.sourceOffset` is stored in.
    private func bookmarkTarget(in document: MarkdownDocument) -> Int {
        let selection = textView.selectedRange()
        let characterOffset = selection.length > 0
            ? selection.location
            : textView.characterIndexForInsertion(at: scrollView.contentView.bounds.origin)

        // Unfiltered source mode indexes the source itself, in UTF-16.
        if document.isShowingSource, taskFilterStates.isEmpty {
            return SourceOffset.byte(forUTF16: characterOffset, in: document.source)
        }
        // Every other view is derived, so ask the text actually on screen which
        // source byte it came from. Looking the index up in the unfiltered
        // render would be wrong the moment a filter is on.
        guard let storage = textView.textStorage, storage.length > 0 else { return 0 }
        let probe = min(max(characterOffset, 0), storage.length - 1)
        return storage.attribute(.sourceOffset, at: probe, effectiveRange: nil) as? Int ?? 0
    }

    /// Reflects the document's bookmark state on the toolbar button.
    ///
    /// A pull-down `NSPopUpButton` draws its first menu item's image, so that
    /// is where the icon lives. `flashing` shows a different symbol briefly, to
    /// distinguish a mark being placed from one being taken away.
    private func updateBookmarkButton(flashing symbol: String? = nil) {
        guard let button = bookmarkButton else { return }
        let count = markdownDocument?.fileURL
            .map { BookmarkStore.shared.bookmarks(for: $0).count } ?? 0
        button.menu?.items.first?.image = NSImage(
            systemSymbolName: symbol ?? (count > 0 ? "bookmark.fill" : "bookmark"),
            accessibilityDescription: "Bookmarks")
        button.contentTintColor = (symbol != nil || count > 0) ? .controlAccentColor : nil
        button.toolTip = count == 0
            ? "Bookmarks in this document"
            : "\(count) bookmark\(count == 1 ? "" : "s") in this document"

        guard symbol != nil else { return }
        bookmarkFlashWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.updateBookmarkButton() }
        bookmarkFlashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }


    /// Rebuilds the bookmark menu when it is about to open, so the list is
    /// always current without observing the store.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === bookmarkButton?.menu else { return }
        menu.removeAllItems()

        let icon = NSMenuItem()
        icon.image = NSImage(systemSymbolName: bookmarkSymbol, accessibilityDescription: "Bookmarks")
        menu.addItem(icon)

        let add = NSMenuItem(title: "Add Bookmark Here",
                             action: #selector(addBookmark(_:)), keyEquivalent: "d")
        add.target = self
        menu.addItem(add)

        guard let document = markdownDocument, let url = document.fileURL else { return }
        let bookmarks = BookmarkStore.shared.bookmarks(for: url)
        guard !bookmarks.isEmpty else {
            menu.addItem(.separator())
            let empty = NSMenuItem(title: "No bookmarks yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        menu.addItem(.separator())
        for bookmark in bookmarks {
            let title = bookmark.snippet.isEmpty
                ? "Position \(bookmark.sourceOffset)"
                : String(bookmark.snippet.prefix(60))
            let entry = NSMenuItem(title: title, action: #selector(goToBookmark(_:)), keyEquivalent: "")
            entry.representedObject = bookmark.id.uuidString
            entry.target = self
            entry.image = NSImage(systemSymbolName: "bookmark.fill", accessibilityDescription: nil)
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Remove All Bookmarks",
                               action: #selector(removeAllBookmarks(_:)), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    @objc func goToBookmark(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String,
              let document = markdownDocument, let url = document.fileURL,
              let bookmark = BookmarkStore.shared.bookmarks(for: url)
                  .first(where: { $0.id.uuidString == identifier }) else { return }

        // Re-locate by content: the file may have been edited since the mark
        // was made, which would leave the stored offset pointing at the wrong
        // line.
        let offset = BookmarkStore.shared.resolvedOffset(for: bookmark, in: document.source)
        if document.isShowingSource {
            // The offset is a source byte offset; NSString counts UTF-16.
            let ns = textView.string as NSString
            let utf16 = min(SourceOffset.utf16(forByte: offset, in: document.source), ns.length)
            textView.reveal(ns.lineRange(for: NSRange(location: utf16, length: 0)))
        } else {
            scrollView.scrollToCharacterOffset(
                document.rendered.characterOffset(forSourceOffset: offset))
        }
    }

    @objc func removeAllBookmarks(_ sender: Any?) {
        guard let url = markdownDocument?.fileURL else { return }
        for bookmark in BookmarkStore.shared.bookmarks(for: url) {
            BookmarkStore.shared.remove(bookmark, for: url)
        }
        updateBookmarkButton()
    }

    /// The symbol the toolbar button shows for the current document.
    var bookmarkSymbol: String {
        let count = markdownDocument?.fileURL
            .map { BookmarkStore.shared.bookmarks(for: $0).count } ?? 0
        return count > 0 ? "bookmark.fill" : "bookmark"
    }

    // MARK: Editing

    func textDidChange(_ notification: Notification) {
        guard let document = markdownDocument, isSourceEditable else { return }
        document.updateSource(textView.string)
    }

    func windowWillClose(_ notification: Notification) {
        guard let document = markdownDocument, isSourceEditable else { return }
        document.updateSource(textView.string)
    }

    // MARK: Ticking checkboxes

    /// Rewrites one checkbox marker in the source and re-renders.
    ///
    /// The rendered view is not an editor, so this is the one edit it can make.
    /// It goes through the source rather than the attributed string, which is
    /// why it cannot disturb anything else in the file.
    private func toggleTask(atSourceOffset offset: Int, to state: Checkbox.State) {
        guard let document = markdownDocument,
              let updated = TaskToggle.apply(state, atSourceOffset: offset,
                                             in: document.source) else { return }
        document.undoManager?.setActionName("Tick Checkbox")
        setSource(updated)
    }

    private func setSource(_ source: String) {
        guard let document = markdownDocument, source != document.source else { return }
        let previous = document.source
        document.undoManager?.registerUndo(withTarget: self) { $0.setSource(previous) }
        document.updateSource(source)
        refreshPreservingScroll()
    }

    /// Re-renders and leaves the reader where they were. Ticking a box rebuilds
    /// the whole attributed string, which otherwise throws the view to the top.
    private func refreshPreservingScroll() {
        let origin = scrollView.contentView.bounds.origin
        refresh()
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
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
        case #selector(shareDocument(_:)):
            return markdownDocument?.fileURL != nil
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
