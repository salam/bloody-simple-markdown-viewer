import Foundation

public struct SearchOptions: Sendable, Equatable {
    public var isRegularExpression: Bool
    public var isCaseSensitive: Bool
    public var matchesWholeWords: Bool

    public init(isRegularExpression: Bool = false,
                isCaseSensitive: Bool = false,
                matchesWholeWords: Bool = false) {
        self.isRegularExpression = isRegularExpression
        self.isCaseSensitive = isCaseSensitive
        self.matchesWholeWords = matchesWholeWords
    }
}

public enum SearchError: Error, Equatable {
    /// The regular expression could not be compiled. Carries the reason so the
    /// find bar can show it, rather than silently matching nothing.
    case invalidPattern(String)
}

/// Finds matches in whatever text is currently displayed.
///
/// Searching the displayed text rather than always the source keeps highlight
/// ranges exact in both modes, and lets a regular expression in source mode
/// match Markdown syntax itself.
public enum DocumentSearch {
    public static func matches(for query: String,
                               in text: String,
                               options: SearchOptions) throws -> [NSRange] {
        guard !query.isEmpty, !text.isEmpty else { return [] }
        let full = NSRange(location: 0, length: (text as NSString).length)

        var pattern = options.isRegularExpression ? query : NSRegularExpression.escapedPattern(for: query)
        if options.matchesWholeWords {
            pattern = "\\b(?:\(pattern))\\b"
        }

        var regexOptions: NSRegularExpression.Options = []
        if !options.isCaseSensitive { regexOptions.insert(.caseInsensitive) }

        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: regexOptions)
        } catch {
            throw SearchError.invalidPattern((error as NSError).localizedDescription)
        }

        return regex.matches(in: text, options: [], range: full)
            .map(\.range)
            .filter { $0.length > 0 }
    }

    /// Index of the first match at or after an offset, wrapping around the ends.
    ///
    /// Inclusive: this is where a *new* query starts from, so narrowing "fo" to
    /// "foo" stays on the hit under the caret rather than skipping past it.
    public static func indexOfMatch(at offset: Int, in matches: [NSRange], forward: Bool) -> Int? {
        guard !matches.isEmpty else { return nil }
        if forward {
            return matches.firstIndex { $0.location >= offset } ?? 0
        }
        return matches.lastIndex { $0.location < offset } ?? matches.count - 1
    }

    /// Index of the match after the one currently selected, wrapping around.
    ///
    /// Exclusive, and that is the whole point: after jumping to a match the
    /// caret sits exactly on it, so the inclusive rule above hands back the
    /// same match and Find Next never leaves the first hit.
    public static func indexOfMatch(after selection: NSRange,
                                    in matches: [NSRange], forward: Bool) -> Int? {
        guard !matches.isEmpty else { return nil }
        if forward {
            return matches.firstIndex { $0.location > selection.location } ?? 0
        }
        return matches.lastIndex { $0.location < selection.location } ?? matches.count - 1
    }
}
