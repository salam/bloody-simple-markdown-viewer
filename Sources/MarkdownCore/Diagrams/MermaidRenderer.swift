import CoreGraphics
import Foundation
import Mermaid

/// Renders Mermaid diagrams, with guards for three defects found by testing the
/// library directly rather than reading its README.
///
/// 1. **A diagram header with no nodes traps.** `graph TD` on its own yields a
///    scene whose size is negative infinity, and `cgImage` converts that to an
///    `Int` before its own zero-check, which crashes. This matters far more
///    than it sounds: a streamed LLM response passes through exactly that state
///    on its way to a complete diagram.
/// 2. **A subgraph nested inside another of the same name overflows the
///    stack.** That happens inside the library's own `render`, where it cannot
///    be caught, so it has to be prevented before calling in.
/// 3. **Layout is only deterministic single-threaded.** Vendored global
///    counters make concurrent renders disagree on geometry about 6% of the
///    time, so every render is serialised onto one queue.
public enum MermaidRenderer {
    public enum Failure: Error, Equatable {
        /// The library does not implement this diagram type, for example gantt
        /// or mindmap. The host shows the source instead.
        case unsupportedType(String)
        case invalidSyntax(String)
        /// Rejected before rendering because it would have crashed the process.
        case wouldCrash(String)
        case empty
    }

    /// All rendering happens here. See defect 3 above.
    private static let queue = DispatchQueue(label: "ch.sala.bsmv.mermaid")

    public static func scene(from source: String, darkMode: Bool) throws -> MermaidScene {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.empty }

        if let reason = unsafeReason(in: trimmed) {
            throw Failure.wouldCrash(reason)
        }

        return try queue.sync {
            let scene: MermaidScene
            do {
                scene = try Mermaid.render(trimmed, theme: darkMode ? .dark : .default)
            } catch let error as MermaidError {
                switch error {
                case .unsupportedDiagramType(let type):
                    throw Failure.unsupportedType(type)
                case .parse(let message, let line):
                    throw Failure.invalidSyntax("line \(line): \(message)")
                case .layout(let message):
                    throw Failure.invalidSyntax(message)
                @unknown default:
                    throw Failure.invalidSyntax("\(error)")
                }
            } catch {
                throw Failure.invalidSyntax("\(error)")
            }

            // Defect 1: check before anything converts these to integers.
            let size = scene.size
            guard size.width.isFinite, size.height.isFinite,
                  size.width > 0, size.height > 0 else {
                throw Failure.empty
            }
            return scene
        }
    }

    /// Detects the one input known to take the process down.
    ///
    /// A subgraph whose identifier repeats inside itself makes the library
    /// recurse on its own parent chain until the stack dies. That happens
    /// inside `render`, and a Swift stack overflow cannot be caught, so the
    /// only option is to refuse beforehand. This is a cheap token scan, not a
    /// reimplementation of the parser.
    static func unsafeReason(in source: String) -> String? {
        var stack: [String] = []
        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "end" {
                if !stack.isEmpty { stack.removeLast() }
                continue
            }
            guard line.lowercased().hasPrefix("subgraph") else { continue }
            let name = subgraphIdentifier(from: line)
            guard !name.isEmpty else { stack.append(""); continue }
            if stack.contains(name) {
                return "a subgraph named \"\(name)\" is nested inside itself"
            }
            stack.append(name)
        }
        return nil
    }

    private static func subgraphIdentifier(from line: String) -> String {
        var rest = String(line.dropFirst("subgraph".count)).trimmingCharacters(in: .whitespaces)
        // `subgraph id[Title]` and `subgraph id ["Title"]` both name `id`.
        if let bracket = rest.firstIndex(of: "[") {
            rest = String(rest[rest.startIndex..<bracket])
        }
        return rest.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
}
