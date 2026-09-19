import AppKit
import Testing
@testable import MarkdownCore

@Suite("Theme")
struct ThemeTests {
    @Test func headingFontsDescendInSize() {
        let t = Theme.system
        let sizes = (1...6).map { t.headingFont(level: $0).pointSize }
        #expect(sizes == sizes.sorted(by: >))
        #expect(sizes[0] > t.bodyFont.pointSize)
    }

    @Test func headingLevelIsClamped() {
        let t = Theme.system
        #expect(t.headingFont(level: 0).pointSize == t.headingFont(level: 1).pointSize)
        #expect(t.headingFont(level: 99).pointSize == t.headingFont(level: 6).pointSize)
    }

    @Test func alertTintsAreDistinct() {
        let t = Theme.system
        let tints = AlertKind.allCases.map { t.alertTint(for: $0) }
        #expect(Set(tints).count == AlertKind.allCases.count)
    }

    @Test func monoFontIsFixedPitch() {
        #expect(Theme.system.monoFont.isFixedPitch)
    }
}
