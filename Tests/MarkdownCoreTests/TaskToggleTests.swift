import AppKit
import Testing
@testable import MarkdownCore

@Suite("TaskToggle")
struct TaskToggleTests {
    private let source = """
    # Project

    - [x] Parse GFM
    - [~] Math and diagrams
    - [ ] Quick Look extension
      - [ ] nested and indented

    Not a task at all.

    1. [ ] ordered and open
    2. [x] ordered and done

    [link-reference]: https://example.com
    """

    /// The offset of the line a piece of text sits on, the way the renderer
    /// reports it.
    private func offset(of text: String) -> Int {
        let range = source.range(of: text)!
        return source.utf8.distance(from: source.utf8.startIndex, to: range.lowerBound.samePosition(in: source.utf8)!)
    }

    // MARK: What a click means

    @Test func aClickTicksAndUnticks() {
        #expect(TaskToggle.ticked(.unchecked) == .checked)
        #expect(TaskToggle.ticked(.inProgress) == .checked)
        // Done reverts to open, so a click is its own undo.
        #expect(TaskToggle.ticked(.checked) == .unchecked)
    }

    @Test func optionClickCyclesAllThree() {
        #expect(TaskToggle.cycled(.unchecked) == .inProgress)
        #expect(TaskToggle.cycled(.inProgress) == .checked)
        #expect(TaskToggle.cycled(.checked) == .unchecked)
    }

    // MARK: Rewriting the source

    @Test func ticksAnOpenBox() {
        let result = TaskToggle.apply(.checked, atSourceOffset: offset(of: "- [ ] Quick Look"), in: source)
        #expect(result?.contains("- [x] Quick Look extension") == true)
        // Nothing else moved.
        #expect(result?.contains("- [x] Parse GFM") == true)
        #expect(result?.contains("- [~] Math and diagrams") == true)
    }

    @Test func unticksADoneBox() {
        let result = TaskToggle.apply(.unchecked, atSourceOffset: offset(of: "- [x] Parse GFM"), in: source)
        #expect(result?.contains("- [ ] Parse GFM") == true)
    }

    @Test func marksInProgress() {
        let result = TaskToggle.apply(.inProgress, atSourceOffset: offset(of: "- [ ] Quick Look"), in: source)
        #expect(result?.contains("- [~] Quick Look extension") == true)
    }

    @Test func keepsIndentationOfNestedItems() {
        let result = TaskToggle.apply(.checked, atSourceOffset: offset(of: "  - [ ] nested"), in: source)
        #expect(result?.contains("  - [x] nested and indented") == true)
    }

    @Test func handlesOrderedLists() {
        let result = TaskToggle.apply(.checked, atSourceOffset: offset(of: "1. [ ] ordered"), in: source)
        #expect(result?.contains("1. [x] ordered and open") == true)
    }

    /// An offset anywhere on the line works, because the renderer reports the
    /// list item's start and a click reports whatever the glyph carries.
    @Test func anyOffsetOnTheLineWorks() {
        let lineStart = offset(of: "- [ ] Quick Look")
        for shift in [0, 3, 8, 15] {
            let result = TaskToggle.apply(.checked, atSourceOffset: lineStart + shift, in: source)
            #expect(result?.contains("- [x] Quick Look extension") == true)
        }
    }

    // MARK: Refusing to touch anything else

    @Test func leavesProseAlone() {
        #expect(TaskToggle.apply(.checked, atSourceOffset: offset(of: "Not a task"), in: source) == nil)
    }

    /// A link reference definition opens with a bracket too. Without the bullet
    /// check it would be rewritten into nonsense.
    @Test func leavesLinkReferenceDefinitionsAlone() {
        #expect(TaskToggle.apply(.checked, atSourceOffset: offset(of: "[link-reference]"), in: source) == nil)
    }

    @Test func leavesHeadingsAlone() {
        #expect(TaskToggle.apply(.checked, atSourceOffset: 0, in: source) == nil)
    }

    @Test func aStaleOffsetChangesNothing() {
        #expect(TaskToggle.apply(.checked, atSourceOffset: 99_999, in: source) == nil)
        #expect(TaskToggle.apply(.checked, atSourceOffset: -5, in: source) == nil)
        #expect(TaskToggle.apply(.checked, atSourceOffset: 0, in: "") == nil)
    }

    // MARK: Following the document's own spelling

    @Test func reusesTheMarkerTheDocumentAlreadyUses() {
        let emoji = """
        - [✅] Already done
        - [ ] Not yet
        """
        let result = TaskToggle.apply(.checked, atSourceOffset: emoji.utf8.count - "- [ ] Not yet".utf8.count,
                                      in: emoji)
        #expect(result?.contains("- [✅] Not yet") == true)
        #expect(result?.contains("[x]") == false)
    }

    @Test func fallsBackToPlainMarkers() {
        #expect(TaskToggle.marker(for: .checked, matching: "- [ ] only open items here") == "x")
        #expect(TaskToggle.marker(for: .inProgress, matching: "- [ ] only open items here") == "~")
        // GFM needs the space: `[]` is not a task list item.
        #expect(TaskToggle.marker(for: .unchecked, matching: "- [x] done") == " ")
    }

    @Test func followsAnInProgressSpelling() {
        let wip = """
        - [WIP] Something started
        - [ ] Something not
        """
        #expect(TaskToggle.marker(for: .inProgress, matching: wip) == "WIP")
    }

    // MARK: Round trip through the renderer

    /// The offsets a click acts on come from the render, so the two have to
    /// agree end to end.
    @Test func offsetsFromTheRendererLandOnTheRightLine() {
        let document = DocumentRenderer(theme: .system).render(source: source)
        let rendered = document.attributedString
        let text = rendered.string as NSString
        let target = text.range(of: "Quick Look extension")
        let offset = rendered.attribute(.sourceOffset, at: target.location, effectiveRange: nil) as? Int

        let result = TaskToggle.apply(.checked, atSourceOffset: offset ?? -1, in: source)
        #expect(result?.contains("- [x] Quick Look extension") == true)
    }

    @Test func tickingTwiceReturnsTheOriginal() {
        let once = TaskToggle.apply(.checked, atSourceOffset: offset(of: "- [ ] Quick Look"), in: source)!
        let twice = TaskToggle.apply(.unchecked, atSourceOffset: offset(of: "- [ ] Quick Look"), in: once)!
        #expect(twice == source)
    }
}
