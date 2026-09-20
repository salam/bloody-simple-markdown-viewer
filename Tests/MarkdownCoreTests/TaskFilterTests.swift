import AppKit
import Testing
@testable import MarkdownCore

@Suite("TaskFilter")
struct TaskFilterTests {
    private let source = """
    # Project

    Some prose that is not a task at all.

    ## Shipping

    - [x] Parse GFM
    - [x] Render tables
    - [~] Math and diagrams
    - [ ] Quick Look extension
    - [ ] Notarised release

    Another paragraph of prose.

    - a plain list item, not a task
    - another plain one

    ## Later

    - [WIP] Bookmarks polish
    - [DONE] Syntax highlighting
    """

    private func document() -> RenderedDocument {
        DocumentRenderer(theme: .system).render(source: source)
    }

    @Test func findsEveryStatePresent() {
        let states = TaskFilter.statesPresent(in: document())
        #expect(Set(states) == Set([.checked, .inProgress, .unchecked]))
    }

    @Test func countsTasksByState() {
        let doc = document()
        #expect(TaskFilter.taskCount(in: doc, state: .checked) == 3)      // 2 [x] plus [DONE]
        #expect(TaskFilter.taskCount(in: doc, state: .inProgress) == 2)   // [~] plus [WIP]
        #expect(TaskFilter.taskCount(in: doc, state: .unchecked) == 2)
    }

    @Test func showsOnlyOpenTasks() {
        let filtered = TaskFilter.filtered(document(), states: [.unchecked])
        let text = filtered.string
        #expect(text.contains("Quick Look extension"))
        #expect(text.contains("Notarised release"))
        #expect(!text.contains("Parse GFM"))
        #expect(!text.contains("Math and diagrams"))
        // Prose and plain list items are excluded entirely.
        #expect(!text.contains("prose"))
        #expect(!text.contains("plain list item"))
    }

    @Test func showsOnlyInProgressTasks() {
        let text = TaskFilter.filtered(document(), states: [.inProgress]).string
        #expect(text.contains("Math and diagrams"))
        #expect(text.contains("Bookmarks polish"))
        #expect(!text.contains("Parse GFM"))
    }

    @Test func combinesSeveralStates() {
        let text = TaskFilter.filtered(document(), states: [.inProgress, .unchecked]).string
        #expect(text.contains("Math and diagrams"))
        #expect(text.contains("Quick Look extension"))
        #expect(!text.contains("Parse GFM"))
    }

    @Test func keepsSourceOffsetsSoJumpingStillWorks() {
        let filtered = TaskFilter.filtered(document(), states: [.unchecked])
        var offsets: [Int] = []
        filtered.enumerateAttribute(.sourceOffset,
                                    in: NSRange(location: 0, length: filtered.length)) { value, _, _ in
            if let offset = value as? Int { offsets.append(offset) }
        }
        #expect(!offsets.isEmpty)
        #expect(offsets.allSatisfy { $0 > 0 })
    }

    @Test func emptySelectionYieldsNothingRatherThanEverything() {
        #expect(TaskFilter.matchCount(in: document(), states: []) == 0)
        #expect(TaskFilter.filtered(document(), states: []).length == 0)
    }

    /// The "no matching tasks" message is chrome drawn by the window, not a
    /// line of the document, so the filter itself must come back empty.
    @Test func documentWithNoTasksYieldsNothing() {
        let plain = DocumentRenderer(theme: .system).render(source: "# Title\n\nJust prose.\n")
        #expect(TaskFilter.statesPresent(in: plain).isEmpty)
        #expect(TaskFilter.matchCount(in: plain, states: [.unchecked]) == 0)
        #expect(TaskFilter.filtered(plain, states: [.unchecked]).length == 0)
    }

    @Test func countsMatchesAcrossSeveralStates() {
        let doc = document()
        #expect(TaskFilter.matchCount(in: doc, states: [.checked]) == 3)
        #expect(TaskFilter.matchCount(in: doc, states: [.inProgress, .unchecked]) == 4)
        #expect(TaskFilter.matchCount(in: doc, states: Set(Checkbox.State.allCases)) == 7)
    }

    // MARK: Filtering the source

    @Test func filteredSourceKeepsTheLinesVerbatim() {
        let text = TaskFilter.filteredSource(document(), states: [.unchecked]).string
        #expect(text.contains("- [ ] Quick Look extension"))
        #expect(text.contains("- [ ] Notarised release"))
        #expect(!text.contains("Parse GFM"))
        #expect(!text.contains("prose"))
    }

    /// Markers the renderer normalises to a glyph must survive as written.
    @Test func filteredSourceKeepsUnusualMarkers() {
        let text = TaskFilter.filteredSource(document(), states: [.checked]).string
        #expect(text.contains("- [DONE] Syntax highlighting"))
        #expect(text.contains("- [x] Parse GFM"))
    }

    @Test func filteredSourceKeepsSourceOffsets() {
        let filtered = TaskFilter.filteredSource(document(), states: [.inProgress])
        // Offsets are UTF-8 byte offsets, so check them against the bytes.
        let bytes = Array(source.utf8)
        var checked = 0
        filtered.enumerateAttribute(.sourceOffset,
                                    in: NSRange(location: 0, length: filtered.length)) { value, _, _ in
            guard let offset = value as? Int else { return }
            // Each offset is the first byte of the line it came from.
            #expect(offset == 0 || bytes[offset - 1] == 0x0A)
            checked += 1
        }
        #expect(checked == 2)
    }

    @Test func filteredSourceIsEmptyWhenNothingMatches() {
        let plain = DocumentRenderer(theme: .system).render(source: "# Title\n\nJust prose.\n")
        #expect(TaskFilter.filteredSource(plain, states: [.checked]).length == 0)
    }

    @Test func keepsTheCheckboxGlyphs() {
        let text = TaskFilter.filtered(document(), states: [.checked, .inProgress, .unchecked]).string
        #expect(text.contains("\u{2611}"))
        #expect(text.contains("\u{25E7}"))
        #expect(text.contains("\u{2610}"))
    }

    // MARK: Items, for callers outside the view

    @Test func listsItemsWithTheirTextAndState() {
        let items = TaskFilter.items(in: document())
        #expect(items.count == 7)
        #expect(items.map(\.text).first == "Parse GFM")
        // The glyph and its tab are gone; the text is what a script wants.
        #expect(!items.contains { $0.text.contains("\u{2611}") || $0.text.contains("\t") })
    }

    /// The odd spellings resolve to a state, which is the point of reading
    /// these off the render rather than off the source.
    @Test func itemsNormaliseUnusualMarkers() {
        let items = TaskFilter.items(in: document())
        let byText = Dictionary(uniqueKeysWithValues: items.map { ($0.text, $0.state) })
        #expect(byText["Syntax highlighting"] == .checked)      // [DONE]
        #expect(byText["Bookmarks polish"] == .inProgress)      // [WIP]
        #expect(byText["Quick Look extension"] == .unchecked)
    }

    @Test func itemsCanBeNarrowedToOneState() {
        #expect(TaskFilter.items(in: document(), states: [.inProgress]).map(\.text)
            == ["Math and diagrams", "Bookmarks polish"])
    }

    /// Offsets are what a caller ticks a box with, so they have to land on the
    /// item's own line.
    @Test func itemOffsetsLandOnTheirSourceLine() {
        for item in TaskFilter.items(in: document()) {
            let line = SourceOffset.line(atByte: item.sourceOffset, in: source)
            #expect(line.contains(item.text), "offset for “\(item.text)” landed on “\(line)”")
        }
    }
}
