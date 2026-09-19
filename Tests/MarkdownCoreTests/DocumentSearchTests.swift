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
}
