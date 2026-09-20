import AppKit
import Testing
@testable import MarkdownCore

@Suite("ChangeTracker")
struct ChangeTrackerTests {
    private let original = """
    # Title

    First paragraph.

    ## Section

    Second paragraph.
    """

    private func lines(_ tracker: ChangeTracker, in source: String) -> [String] {
        let all = source.components(separatedBy: "\n")
        return tracker.changedLines.keys.sorted().compactMap { $0 < all.count ? all[$0] : nil }
    }

    @Test func aFreshTrackerHasNothing() {
        #expect(ChangeTracker().isEmpty)
        #expect(ChangeTracker().highlights(in: original).isEmpty)
    }

    @Test func anIdenticalRewriteChangesNothing() {
        var tracker = ChangeTracker()
        tracker.record(from: original, to: original)
        #expect(tracker.isEmpty)
    }

    @Test func marksOnlyTheEditedLine() {
        var tracker = ChangeTracker()
        let edited = original.replacingOccurrences(of: "Second paragraph.", with: "Rewritten by someone else.")
        tracker.record(from: original, to: edited)
        #expect(lines(tracker, in: edited) == ["Rewritten by someone else."])
    }

    @Test func marksInsertedLines() {
        var tracker = ChangeTracker()
        let edited = original.replacingOccurrences(of: "## Section",
                                                   with: "## Section\n\nA brand new line.")
        tracker.record(from: original, to: edited)
        // The blank line already after the heading matches the old one, so what
        // is new is the text and the blank that now follows it.
        #expect(lines(tracker, in: edited) == ["A brand new line.", ""])
    }

    @Test func aDeletionLeavesTheSurvivingLinesAlone() {
        var tracker = ChangeTracker()
        let edited = original.replacingOccurrences(of: "First paragraph.\n\n", with: "")
        tracker.record(from: original, to: edited)
        #expect(tracker.isEmpty, "removing a line changes no remaining line")
    }

    /// The reason marks are held per line rather than per offset: an edit above
    /// an existing highlight must move it, not orphan it.
    @Test func anEarlierMarkFollowsItsLineDown() {
        var tracker = ChangeTracker()
        let first = original.replacingOccurrences(of: "Second paragraph.", with: "Changed once.")
        tracker.record(from: original, to: first, at: Date(timeIntervalSince1970: 0))
        #expect(lines(tracker, in: first) == ["Changed once."])

        // Now someone inserts two lines at the very top.
        let second = "Inserted at the top.\n\n" + first
        tracker.record(from: first, to: second, at: Date(timeIntervalSince1970: 3600))

        let marked = lines(tracker, in: second)
        #expect(marked.contains("Changed once."), "the earlier mark must have moved with its line")
        #expect(marked.contains("Inserted at the top."))
        #expect(tracker.changedLines.count == 3)   // the insert is two lines plus the old mark
    }

    @Test func eachEditKeepsItsOwnTime() {
        var tracker = ChangeTracker()
        let morning = Date(timeIntervalSince1970: 0)
        let later = Date(timeIntervalSince1970: 7200)

        let first = original.replacingOccurrences(of: "First paragraph.", with: "Edit A.")
        tracker.record(from: original, to: first, at: morning)
        let second = first.replacingOccurrences(of: "Second paragraph.", with: "Edit B.")
        tracker.record(from: first, to: second, at: later)

        let highlights = tracker.highlights(in: second)
        #expect(highlights.count == 2)
        #expect(Set(highlights.map(\.time)) == [morning, later])
    }

    // MARK: Byte ranges

    @Test func highlightRangesCoverExactlyTheChangedLine() {
        var tracker = ChangeTracker()
        let edited = original.replacingOccurrences(of: "Second paragraph.", with: "Rewritten.")
        tracker.record(from: original, to: edited)

        let highlights = tracker.highlights(in: edited)
        #expect(highlights.count == 1)
        let bytes = Array(edited.utf8)
        let text = String(decoding: bytes[highlights[0].range], as: UTF8.self)
        #expect(text == "Rewritten.")
    }

    /// Byte ranges, not UTF-16 ranges, like every other source position here.
    @Test func rangesAreByteOffsetsInANonASCIIDocument() {
        var tracker = ChangeTracker()
        let before = "# Überschrift — eins\n\nEin Absatz mit «Zitat».\n\nLetzte Zeile\n"
        let after = before.replacingOccurrences(of: "Letzte Zeile", with: "Geänderte Zeile")
        tracker.record(from: before, to: after)

        let highlights = tracker.highlights(in: after)
        #expect(highlights.count == 1)
        let bytes = Array(after.utf8)
        #expect(String(decoding: bytes[highlights[0].range], as: UTF8.self) == "Geänderte Zeile")
        #expect(highlights[0].range.lowerBound != (after as NSString).range(of: "Geänderte").location,
                "the fixture must actually distinguish bytes from UTF-16")
    }

    @Test func adjacentLinesFromOneEditMergeIntoOneRange() {
        var tracker = ChangeTracker()
        let edited = original.replacingOccurrences(of: "Second paragraph.",
                                                   with: "One.\nTwo.\nThree.")
        tracker.record(from: original, to: edited)
        let highlights = tracker.highlights(in: edited)
        #expect(highlights.count == 1, "three consecutive lines from one save are one block")
        let bytes = Array(edited.utf8)
        #expect(String(decoding: bytes[highlights[0].range], as: UTF8.self) == "One.\nTwo.\nThree.")
    }

    // MARK: Colour

    @Test func theSameMinuteGivesTheSameColour() {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 9; parts.day = 20; parts.hour = 14; parts.minute = 33
        let a = Calendar.current.date(from: parts)!
        parts.second = 47
        let b = Calendar.current.date(from: parts)!
        #expect(ChangeTracker.hue(for: a) == ChangeTracker.hue(for: b))
        #expect(ChangeTracker.label(for: a) == "14:33")
    }

    @Test func consecutiveMinutesAreVisiblyApart() {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 9; parts.day = 20; parts.hour = 14; parts.minute = 33
        let a = Calendar.current.date(from: parts)!
        parts.minute = 34
        let b = Calendar.current.date(from: parts)!
        let distance = abs(ChangeTracker.hue(for: a) - ChangeTracker.hue(for: b))
        #expect(min(distance, 1 - distance) > 0.2, "a minute apart must not look like the same edit")
    }

    // MARK: Bounds

    @Test func aWholesaleRewriteIsBoundedRatherThanQuadratic() {
        var tracker = ChangeTracker()
        let before = (0..<4_000).map { "line \($0)" }.joined(separator: "\n")
        let after = (0..<4_000).map { "different \($0)" }.joined(separator: "\n")
        let started = Date()
        tracker.record(from: before, to: after)
        #expect(Date().timeIntervalSince(started) < 2, "the diff must not attempt a 16M-cell table")
        #expect(tracker.changedLines.count == 4_000)
    }

    @Test func handlesEmptyDocuments() {
        var tracker = ChangeTracker()
        tracker.record(from: "", to: "now it has content\n")
        #expect(!tracker.isEmpty)
        tracker.record(from: "now it has content\n", to: "")
        #expect(tracker.highlights(in: "").isEmpty || tracker.changedLines.count <= 1)
    }

    // MARK: Marking up the rendered text

    private func rendered(_ source: String, _ tracker: ChangeTracker) -> NSMutableAttributedString {
        let document = DocumentRenderer(theme: .system).render(source: source)
        let text = NSMutableAttributedString(attributedString: document.attributedString)
        tracker.markRuns(in: text, source: source)
        return text
    }

    private func marked(_ text: NSAttributedString) -> [String] {
        var found: [String] = []
        text.enumerateAttribute(.changedAt, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard value != nil else { return }
            found.append((text.string as NSString).substring(with: range)
                .trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return found.filter { !$0.isEmpty }
    }

    @Test func marksTheChangedParagraphAndNothingElse() {
        let before = "# Title\n\nUntouched paragraph.\n\nOriginal text.\n"
        let after = before.replacingOccurrences(of: "Original text.", with: "Replaced text.")
        var tracker = ChangeTracker()
        tracker.record(from: before, to: after)

        let text = rendered(after, tracker)
        #expect(marked(text).contains { $0.contains("Replaced text.") })
        #expect(!marked(text).contains { $0.contains("Untouched paragraph.") })
    }

    /// A fenced block reports its fence as the source offset of every one of
    /// its lines, so matching a run's start offset alone leaves a change inside
    /// one the single place in the document that never lights up.
    @Test func marksACodeBlockWhoseContentChanged() {
        let before = "Intro.\n\n```swift\nlet x = 1\n```\n\nOutro.\n"
        let after = before.replacingOccurrences(of: "let x = 1", with: "let x = 1\nprint(x)")
        var tracker = ChangeTracker()
        tracker.record(from: before, to: after)

        let text = rendered(after, tracker)
        #expect(marked(text).contains { $0.contains("print(x)") },
                "a change inside a fence must tint the block")
        #expect(!marked(text).contains { $0.contains("Outro.") })
    }

    @Test func marksNothingWhenTheTrackerIsEmpty() {
        let text = rendered("# Title\n\nBody.\n", ChangeTracker())
        #expect(marked(text).isEmpty)
    }

    /// Source mode has no attributes to read, so the byte ranges map straight
    /// onto the text — through the UTF-16 conversion, not around it.
    @Test func marksSourceModeThroughTheOffsetConversion() {
        let before = "# Überschrift — eins\n\nErste Zeile.\n\nZweite Zeile.\n"
        let after = before.replacingOccurrences(of: "Zweite Zeile.", with: "Geänderte Zeile.")
        var tracker = ChangeTracker()
        tracker.record(from: before, to: after)

        let text = NSMutableAttributedString(string: after)
        tracker.markSourceRuns(in: text, source: after)
        #expect(marked(text) == ["Geänderte Zeile."])
    }

    // MARK: Edits made here

    /// Ticking a checkbox or typing in source mode is not an external change,
    /// but it still moves the lines an external change is marked on.
    @Test func ourOwnEditMovesMarksWithoutAddingAny() {
        var tracker = ChangeTracker()
        let external = original.replacingOccurrences(of: "Second paragraph.", with: "Changed elsewhere.")
        tracker.record(from: original, to: external, at: Date(timeIntervalSince1970: 0))
        #expect(tracker.changedLines.count == 1)

        let mine = "A line I typed myself.\n\n" + external
        tracker.remap(from: external, to: mine)

        #expect(tracker.changedLines.count == 1, "my own typing must not add a highlight")
        #expect(lines(tracker, in: mine) == ["Changed elsewhere."], "the old mark must have moved")
    }

    @Test func remappingAnEmptyTrackerStaysEmpty() {
        var tracker = ChangeTracker()
        tracker.remap(from: original, to: original + "\nmore\n")
        #expect(tracker.isEmpty)
    }
}
