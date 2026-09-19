import Foundation

/// Recognises the checkbox markers people actually write.
///
/// GitHub Flavored Markdown defines exactly two, `[ ]` and `[x]`, and that is
/// all cmark-gfm will report as a task list item. Everything else, `[✅]`,
/// `[✔️]`, `[OK]`, `[DONE]`, arrives as ordinary text at the start of a list
/// item, or as an unresolved shortcut link reference. Those are detected here
/// and the marker is removed from the visible text.
public enum Checkbox {
    public enum State: String, Equatable, Sendable, CaseIterable {
        case checked
        case unchecked
        /// Started but not finished. Not a GFM concept at all, but people write
        /// it constantly, as `[~]`, `[/]` or `[WIP]`.
        case inProgress

        public var title: String {
            switch self {
            case .checked: "Done"
            case .inProgress: "In Progress"
            case .unchecked: "Open"
            }
        }
    }

    /// Markers meaning done. Compared case-insensitively, with variation
    /// selectors stripped so `✔️` and `✔` are the same thing.
    private static let checkedMarkers: Set<String> = [
        "x", "✅", "✔", "☑", "☒", "✓", "√", "ok", "done", "y", "yes", "true", "*", "+"
    ]

    private static let uncheckedMarkers: Set<String> = [
        "", " ", "-", "_", "?", "todo", "open", "n", "no", "false", "pending"
    ]

    private static let inProgressMarkers: Set<String> = [
        "~", "/", ">", "…", "...", "wip", "doing", "started", "partial", "half",
        "progress", "in progress", "in arbeit", "arbeit", "ongoing", "active"
    ]

    /// Reads a leading `[...]` marker, returning its state and how many UTF-16
    /// units to drop from the text. Returns nil when the item is not a task.
    public static func parseLeadingMarker(in text: String) -> (state: State, consumed: Int)? {
        let ns = text as NSString
        var index = 0
        // Allow leading whitespace before the bracket.
        while index < ns.length, Character(UnicodeScalar(ns.character(at: index))!).isWhitespace {
            index += 1
        }
        guard index < ns.length, ns.character(at: index) == UInt16(UnicodeScalar("[").value) else {
            return nil
        }
        let contentStart = index + 1
        let searchRange = NSRange(location: contentStart, length: ns.length - contentStart)
        let closing = ns.range(of: "]", options: [], range: searchRange)
        guard closing.location != NSNotFound else { return nil }

        let raw = ns.substring(with: NSRange(location: contentStart,
                                             length: closing.location - contentStart))
        guard let state = state(for: raw) else { return nil }

        // Also swallow a single space after the bracket, so the text does not
        // start with a gap.
        var consumed = closing.location + 1
        if consumed < ns.length, ns.character(at: consumed) == UInt16(UnicodeScalar(" ").value) {
            consumed += 1
        }
        return (state, consumed)
    }

    public static func state(for marker: String) -> State? {
        let normalised = marker
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\u{FE0F}", with: "")   // emoji variation selector
            .replacingOccurrences(of: "\u{FE0E}", with: "")   // text variation selector
            .lowercased()
        if checkedMarkers.contains(normalised) { return .checked }
        if inProgressMarkers.contains(normalised) { return .inProgress }
        if uncheckedMarkers.contains(normalised) { return .unchecked }
        return nil
    }

    /// Glyph shown for a state. All three are box-shaped so a mixed list reads
    /// as one column rather than a jumble of shapes.
    public static func glyph(for state: State) -> String {
        switch state {
        case .checked: "\u{2611}"      // ballot box with check
        case .inProgress: "\u{25E7}"   // square, left half filled
        case .unchecked: "\u{2610}"    // empty ballot box
        }
    }
}
