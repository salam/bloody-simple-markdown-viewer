import Testing
@testable import MarkdownCore

@Suite("Frontmatter")
struct FrontmatterTests {
    @Test func splitsYAML() {
        let r = Frontmatter.split("---\ntitle: Hi\n---\n# Heading\n")
        #expect(r.frontmatter == "title: Hi")
        #expect(r.body == "# Heading\n")
        #expect(r.bodyLineOffset == 3)
    }

    @Test func splitsTOML() {
        let r = Frontmatter.split("+++\ntitle = \"Hi\"\n+++\ntext\n")
        #expect(r.frontmatter == "title = \"Hi\"")
        #expect(r.body == "text\n")
    }

    @Test func leavesThematicBreakAlone() {
        let r = Frontmatter.split("# Heading\n\n---\n\ntext\n")
        #expect(r.frontmatter == nil)
        #expect(r.body == "# Heading\n\n---\n\ntext\n")
        #expect(r.bodyLineOffset == 0)
    }

    @Test func unterminatedFenceIsNotFrontmatter() {
        let r = Frontmatter.split("---\ntitle: Hi\nno closing fence\n")
        #expect(r.frontmatter == nil)
    }
}
