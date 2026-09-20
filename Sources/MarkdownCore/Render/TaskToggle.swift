import Foundation

/// Ticking a checkbox in the rendered view, written straight back into the source.
///
/// This is the whole of the rendered view's editing model, and deliberately so.
/// Full WYSIWYG would mean mapping arbitrary attributed-string edits back onto
/// Markdown, which is where that kind of editor goes wrong. A checkbox is one
/// bracketed marker on one line: it maps back exactly, and a miss changes
/// nothing at all rather than corrupting the file.
public enum TaskToggle {
    /// What a plain click does. Anything unfinished becomes done; done reverts
    /// to open, never to in-progress, so a click is its own undo.
    public static func ticked(_ state: Checkbox.State) -> Checkbox.State {
        state == .checked ? .unchecked : .checked
    }

    /// What an Option-click does: all three states in a fixed order, for the
    /// documents that use the in-progress marker.
    public static func cycled(_ state: Checkbox.State) -> Checkbox.State {
        switch state {
        case .unchecked: .inProgress
        case .inProgress: .checked
        case .checked: .unchecked
        }
    }

    /// Rewrites the checkbox marker on the source line containing `offset`.
    ///
    /// Returns nil when that line carries no task marker, which is the safe
    /// answer for a stale offset: the caller leaves the document untouched.
    public static func apply(_ state: Checkbox.State,
                             atSourceOffset offset: Int,
                             in source: String) -> String? {
        let bytes = Array(source.utf8)
        guard let line = TaskFilter.sourceLine(at: offset, in: bytes),
              let rewritten = replacingMarker(in: line.text,
                                              with: marker(for: state, matching: source))
        else { return nil }

        var out = Array(bytes[0..<line.range.lowerBound])
        out.append(contentsOf: rewritten.utf8)
        out.append(contentsOf: bytes[line.range.upperBound...])
        return String(decoding: out, as: UTF8.self)
    }

    /// The marker text to write for a state, following whatever this document
    /// already uses. A file written entirely in `[✅]` should not sprout a lone
    /// `[x]` the first time someone unticks and reticks a box.
    public static func marker(for state: Checkbox.State, matching source: String) -> String {
        switch state {
        // GFM requires the space: `[]` is not a task list item.
        case .unchecked: " "
        case .checked: existingMarker(for: .checked, in: source) ?? "x"
        case .inProgress: existingMarker(for: .inProgress, in: source) ?? "~"
        }
    }

    /// The first marker in the document that already means this state, spelled
    /// exactly as it is written there.
    private static func existingMarker(for state: Checkbox.State, in source: String) -> String? {
        for slice in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(slice)
            guard let span = markerSpan(in: line) else { continue }
            let raw = (line as NSString).substring(with: span)
            if Checkbox.state(for: raw) == state, !raw.trimmingCharacters(in: .whitespaces).isEmpty {
                return raw
            }
        }
        return nil
    }

    private static func replacingMarker(in line: String, with marker: String) -> String? {
        guard let span = markerSpan(in: line) else { return nil }
        return (line as NSString).replacingCharacters(in: span, with: marker)
    }

    /// Range of the text between the brackets of a task marker on a list line.
    ///
    /// Requires the bullet: without it, a line that merely opens with a
    /// bracketed word, such as a link reference definition, would be rewritten.
    private static func markerSpan(in line: String) -> NSRange? {
        let ns = line as NSString
        func character(_ index: Int) -> Character? {
            guard index < ns.length, let scalar = UnicodeScalar(ns.character(at: index)) else { return nil }
            return Character(scalar)
        }

        var index = 0
        while let ch = character(index), ch == " " || ch == "\t" { index += 1 }

        guard let bullet = character(index) else { return nil }
        if bullet == "-" || bullet == "*" || bullet == "+" {
            index += 1
        } else if bullet.isNumber {
            while let ch = character(index), ch.isNumber { index += 1 }
            guard let delimiter = character(index), delimiter == "." || delimiter == ")" else { return nil }
            index += 1
        } else {
            return nil
        }

        var sawSpace = false
        while let ch = character(index), ch == " " || ch == "\t" {
            sawSpace = true
            index += 1
        }
        guard sawSpace, character(index) == "[" else { return nil }

        let contentStart = index + 1
        let closing = ns.range(of: "]", options: [],
                               range: NSRange(location: contentStart,
                                              length: ns.length - contentStart))
        guard closing.location != NSNotFound else { return nil }

        let span = NSRange(location: contentStart, length: closing.location - contentStart)
        guard Checkbox.state(for: ns.substring(with: span)) != nil else { return nil }
        return span
    }
}
