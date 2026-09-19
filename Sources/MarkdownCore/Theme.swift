import AppKit

/// The five GitHub alert kinds, as of the 2023-12-14 launch.
public enum AlertKind: String, CaseIterable, Sendable {
    case note, tip, important, warning, caution

    public var title: String { rawValue.uppercased() }

    /// SF Symbol shown beside the title.
    public var symbolName: String {
        switch self {
        case .note: "info.circle.fill"
        case .tip: "lightbulb.fill"
        case .important: "exclamationmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .caution: "exclamationmark.octagon.fill"
        }
    }
}

/// How attachments are produced.
///
/// On screen, tables and display math host live views so they stay crisp at any
/// zoom. Printing goes through a different path that does not instantiate
/// attachment views at all, so those would silently vanish from the page.
/// Flattened mode rasterises them into the attachment's image instead, which
/// prints and exports correctly.
public enum AttachmentRendering: Sendable {
    case interactive
    case flattened
}

/// Typography and colour for the rendered document.
///
/// Every colour is a dynamic `NSColor`, so dark mode requires no second theme
/// and no re-render; AppKit resolves them against the current appearance.
public struct Theme: Sendable {
    public var baseFontSize: CGFloat
    public var readingWidth: CGFloat
    public var textColor: NSColor
    public var secondaryTextColor: NSColor
    public var linkColor: NSColor
    public var codeBackground: NSColor
    public var quoteBarColor: NSColor
    public var ruleColor: NSColor
    /// Whether the document is drawn on a dark background.
    ///
    /// Held explicitly rather than inferred from a dynamic colour: resolving
    /// `.labelColor` outside a drawing context gives whichever appearance
    /// happens to be current, which is not necessarily the window's. Diagrams
    /// pick their palette from this.
    public var isDarkBackground: Bool

    public static var system: Theme {
        var theme = Theme.base
        theme.isDarkBackground = Theme.systemPrefersDark
        return theme
    }

    public static var systemPrefersDark: Bool {
        NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    static let base = Theme(
        baseFontSize: 14,
        readingWidth: 720,
        textColor: .labelColor,
        secondaryTextColor: .secondaryLabelColor,
        linkColor: .linkColor,
        codeBackground: .quaternarySystemFill,
        quoteBarColor: .tertiaryLabelColor,
        ruleColor: .separatorColor,
        isDarkBackground: false
    )

    public var bodyFont: NSFont { .systemFont(ofSize: baseFontSize) }

    public var monoFont: NSFont {
        .monospacedSystemFont(ofSize: baseFontSize - 1, weight: .regular)
    }

    /// Heading sizes descend from h1 to h6, with h6 settling just under body size.
    public func headingFont(level: Int) -> NSFont {
        let scale: [CGFloat] = [1.9, 1.55, 1.3, 1.15, 1.02, 0.95]
        let clamped = min(max(level, 1), 6)
        let weight: NSFont.Weight = clamped <= 2 ? .bold : .semibold
        return .systemFont(ofSize: (baseFontSize * scale[clamped - 1]).rounded(), weight: weight)
    }

    public func alertTint(for kind: AlertKind) -> NSColor {
        switch kind {
        case .note: .systemBlue
        case .tip: .systemGreen
        case .important: .systemPurple
        case .warning: .systemYellow
        case .caution: .systemRed
        }
    }

    // Syntax highlighting palette, semantic so it adapts to appearance.
    public var codeKeywordColor: NSColor { .systemPink }
    public var codeTypeColor: NSColor { .systemTeal }
    public var codeStringColor: NSColor { .systemRed }
    public var codeCommentColor: NSColor { .secondaryLabelColor }
    public var codeNumberColor: NSColor { .systemOrange }
    public var codePlainColor: NSColor { textColor }
}
