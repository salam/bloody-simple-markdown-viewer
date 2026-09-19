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

    @Test func emptySelectionSaysSoRatherThanShowingEverything() {
        let text = TaskFilter.filtered(document(), states: []).string
        #expect(!text.contains("Parse GFM"))
        #expect(text.contains("No task states selected"))
    }

    @Test func documentWithNoTasksSaysSo() {
        let plain = DocumentRenderer(theme: .system).render(source: "# Title\n\nJust prose.\n")
        #expect(TaskFilter.statesPresent(in: plain).isEmpty)
        let text = TaskFilter.filtered(plain, states: [.unchecked]).string
        #expect(text.contains("No matching tasks"))
    }

    @Test func keepsTheCheckboxGlyphs() {
        let text = TaskFilter.filtered(document(), states: [.checked, .inProgress, .unchecked]).string
        #expect(text.contains("\u{2611}"))
        #expect(text.contains("\u{25E7}"))
        #expect(text.contains("\u{2610}"))
    }
}
