import AppKit
import Testing
@testable import MarkdownCore

@Suite("Mermaid")
struct MermaidTests {
    // MARK: The crash guards

    /// A diagram header with no nodes yields a scene of infinite size, and the
    /// library converts that to an Int before its own zero-check. A streamed
    /// LLM response passes through this state on the way to a real diagram, so
    /// it is the common case, not an edge case.
    @Test func headerWithNoNodesDoesNotCrash() {
        for source in ["graph TD", "flowchart TD", "stateDiagram-v2", "graph TD\n  %% a comment"] {
            #expect(throws: MermaidRenderer.Failure.self) {
                _ = try MermaidRenderer.scene(from: source, darkMode: false)
            }
        }
    }

    /// A subgraph nested inside another of the same name overflows the stack
    /// inside the library, where it cannot be caught. It must be refused first.
    @Test func selfNestedSubgraphIsRefusedBeforeRendering() {
        let source = """
        graph TD
            subgraph S1
                subgraph S1
                    X --> Y
                end
            end
        """
        #expect(MermaidRenderer.unsafeReason(in: source) != nil)
        #expect(throws: MermaidRenderer.Failure.self) {
            _ = try MermaidRenderer.scene(from: source, darkMode: false)
        }
    }

    @Test func distinctlyNamedNestedSubgraphsAreAllowed() {
        let source = """
        graph TD
            subgraph Outer
                subgraph Inner
                    X --> Y
                end
            end
        """
        #expect(MermaidRenderer.unsafeReason(in: source) == nil)
    }

    @Test func siblingSubgraphsReusingANameAreAllowed() {
        // Sequential, not nested: the stack unwinds at `end`.
        let source = """
        graph TD
            subgraph A
                X --> Y
            end
            subgraph A
                P --> Q
            end
        """
        #expect(MermaidRenderer.unsafeReason(in: source) == nil)
    }

    @Test func recognisesTitledSubgraphSyntax() {
        let source = """
        graph TD
            subgraph S1[Outer Title]
                subgraph S1["Inner Title"]
                    X --> Y
                end
            end
        """
        #expect(MermaidRenderer.unsafeReason(in: source) != nil)
    }

    // MARK: Rendering

    @Test func rendersAFlowchart() throws {
        let scene = try MermaidRenderer.scene(from: """
        graph TD
            A[Start] --> B{Working?}
            B -->|Yes| C[Ship it]
            B -->|No| D[Debug]
        """, darkMode: false)
        #expect(scene.size.width > 50)
        #expect(scene.size.height > 50)
        #expect(!scene.elements.isEmpty)
    }

    @Test func rendersTheCommonDiagramTypes() {
        let diagrams = [
            "sequenceDiagram\n    U->>A: Click\n    A-->>U: Result",
            "stateDiagram-v2\n    [*] --> Idle\n    Idle --> Busy: go",
            "classDiagram\n    class Doc {\n      +parse()\n    }",
            "erDiagram\n    USER ||--o{ ORDER : places",
            "pie title Langs\n    \"Swift\" : 70\n    \"C\" : 30"
        ]
        for source in diagrams {
            #expect(throws: Never.self) {
                _ = try MermaidRenderer.scene(from: source, darkMode: false)
            }
        }
    }

    /// Unsupported types must report themselves so the host can show the source.
    @Test func unsupportedTypesReportThemselves() {
        let gantt = """
        gantt
            title Schedule
            dateFormat YYYY-MM-DD
            section One
            Design :a1, 2026-01-01, 30d
        """
        do {
            _ = try MermaidRenderer.scene(from: gantt, darkMode: false)
            Issue.record("gantt unexpectedly rendered")
        } catch let failure as MermaidRenderer.Failure {
            if case .unsupportedType = failure {} else {
                Issue.record("expected unsupportedType, got \(failure)")
            }
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func emptySourceIsRejected() {
        #expect(throws: MermaidRenderer.Failure.self) {
            _ = try MermaidRenderer.scene(from: "   \n  ", darkMode: false)
        }
    }

    // MARK: Integration with the document

    @Test @MainActor func documentEmbedsARenderedDiagram() {
        let doc = DocumentRenderer(theme: .system).render(source: """
        ```mermaid
        graph LR
            A[One] --> B[Two]
        ```
        """)
        var diagram: MermaidTextAttachment?
        doc.attributedString.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: doc.attributedString.length)
        ) { value, _, _ in
            if let found = value as? MermaidTextAttachment { diagram = found }
        }
        #expect(diagram != nil)
        #expect(diagram?.failed == false)
        #expect((diagram?.bounds.width ?? 0) > 30)
    }

    @Test @MainActor func unsupportedDiagramFallsBackToItsSource() {
        let doc = DocumentRenderer(theme: .system).render(source: """
        ```mermaid
        gantt
            title Schedule
            section One
            Design :a1, 2026-01-01, 30d
        ```
        """)
        // Nothing may be silently lost.
        #expect(doc.attributedString.string.contains("gantt"))
        #expect(doc.attributedString.string.contains("Design"))
    }

    @Test @MainActor func partialDiagramFromStreamingFallsBackSafely() {
        let doc = DocumentRenderer(theme: .system).render(source: "```mermaid\ngraph TD\n```\n")
        #expect(doc.attributedString.string.contains("graph TD"))
    }

    @Test @MainActor func flattenedDiagramCarriesAnImageForPrinting() {
        let doc = DocumentRenderer(theme: .system, attachmentRendering: .flattened)
            .render(source: "```mermaid\ngraph LR\n  A --> B\n```\n")
        var diagram: MermaidTextAttachment?
        doc.attributedString.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: doc.attributedString.length)
        ) { value, _, _ in
            if let found = value as? MermaidTextAttachment { diagram = found }
        }
        #expect(diagram?.image != nil, "a flattened diagram must rasterise or it prints blank")
    }
}
