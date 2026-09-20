import Foundation
import Testing
@testable import MarkdownCore

@Suite("DocumentSearch")
struct DocumentSearchTests {
    private let text = "The quick brown fox.\nThe Quick brown dog.\nQuicksilver is quick."

    @Test func findsLiteralMatchesCaseInsensitivelyByDefault() throws {
        #expect(try DocumentSearch.matches(for: "quick", in: text, options: SearchOptions()).count == 4)
    }

    @Test func respectsCaseSensitivity() throws {
        let matches = try DocumentSearch.matches(
            for: "Quick", in: text, options: SearchOptions(isCaseSensitive: true))
        #expect(matches.count == 2)
    }

    @Test func matchesWholeWordsOnly() throws {
        let matches = try DocumentSearch.matches(
            for: "quick", in: text, options: SearchOptions(matchesWholeWords: true))
        #expect(matches.count == 3)   // "Quicksilver" excluded
    }

    @Test func treatsLiteralQueriesAsLiteral() throws {
        #expect(try DocumentSearch.matches(for: "b.o", in: text, options: SearchOptions()).isEmpty)
    }

    @Test func runsRegularExpressions() throws {
        let matches = try DocumentSearch.matches(
            for: "b.own", in: text, options: SearchOptions(isRegularExpression: true))
        #expect(matches.count == 2)
    }

    @Test func regexCanMatchMarkdownSyntax() throws {
        let source = "# One\n\n## Two\n\n### Three\n"
        let matches = try DocumentSearch.matches(
            for: "(?m)^#{2,3} ", in: source, options: SearchOptions(isRegularExpression: true))
        #expect(matches.count == 2)
    }

    @Test func reportsInvalidPatternsRatherThanMatchingNothing() {
        #expect(throws: SearchError.self) {
            try DocumentSearch.matches(
                for: "[unclosed", in: text, options: SearchOptions(isRegularExpression: true))
        }
    }

    @Test func emptyQueryFindsNothing() throws {
        #expect(try DocumentSearch.matches(for: "", in: text, options: SearchOptions()).isEmpty)
    }

    @Test func zeroWidthMatchesAreDiscarded() throws {
        let matches = try DocumentSearch.matches(
            for: "x*", in: "abc", options: SearchOptions(isRegularExpression: true))
        #expect(matches.isEmpty)
    }

    @Test func findsNextAndPreviousWithWraparound() throws {
        let matches = try DocumentSearch.matches(for: "quick", in: text, options: SearchOptions())
        #expect(DocumentSearch.indexOfMatch(at: 0, in: matches, forward: true) == 0)
        #expect(DocumentSearch.indexOfMatch(at: matches[0].location + 1, in: matches, forward: true) == 1)
        #expect(DocumentSearch.indexOfMatch(at: 10_000, in: matches, forward: true) == 0)
        #expect(DocumentSearch.indexOfMatch(at: 0, in: matches, forward: false) == matches.count - 1)
    }

    @Test func handlesMultibyteText() throws {
        let unicode = "café 🎉 café"
        let matches = try DocumentSearch.matches(for: "café", in: unicode, options: SearchOptions())
        #expect(matches.count == 2)
        for match in matches { #expect((unicode as NSString).substring(with: match) == "café") }
    }

    // MARK: Moving between matches

    private let matches = [NSRange(location: 10, length: 4),
                           NSRange(location: 200, length: 4),
                           NSRange(location: 900, length: 4),
                           NSRange(location: 2000, length: 4)]

    /// The bug this was written for. After jumping to a match the caret sits on
    /// it, so asking again from the caret with the inclusive rule returns the
    /// same match: Return in the search field never left the first hit.
    @Test func repeatedFindNextVisitsEveryMatchInTurn() {
        var selection = NSRange(location: 0, length: 0)
        var visited: [Int] = []
        for _ in 0..<6 {
            guard let index = DocumentSearch.indexOfMatch(after: selection, in: matches,
                                                          forward: true) else { break }
            visited.append(index)
            selection = matches[index]          // what revealing a match does
        }
        #expect(visited == [0, 1, 2, 3, 0, 1], "Find Next must advance and then wrap")
    }

    @Test func repeatedFindPreviousWalksBackwards() {
        var selection = matches[3]
        var visited: [Int] = []
        for _ in 0..<5 {
            guard let index = DocumentSearch.indexOfMatch(after: selection, in: matches,
                                                          forward: false) else { break }
            visited.append(index)
            selection = matches[index]
        }
        #expect(visited == [2, 1, 0, 3, 2])
    }

    /// A new query starts inclusively, so narrowing the search term does not
    /// skip the hit the caret is already on.
    @Test func aNewQueryStaysOnTheMatchUnderTheCaret() {
        #expect(DocumentSearch.indexOfMatch(at: 200, in: matches, forward: true) == 1)
        #expect(DocumentSearch.indexOfMatch(after: NSRange(location: 200, length: 4),
                                            in: matches, forward: true) == 2)
    }

    @Test func movingWithNoMatchesDoesNothing() {
        #expect(DocumentSearch.indexOfMatch(after: NSRange(location: 0, length: 0),
                                            in: [], forward: true) == nil)
    }
}
