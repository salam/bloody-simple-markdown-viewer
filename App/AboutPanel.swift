import AppKit

/// The About panel.
///
/// AppKit's standard panel is used rather than a hand-built window, because it
/// already knows the version, the copyright and the icon, and because it is
/// what people expect a Mac app's About box to look like. The one thing it does
/// not do on its own is carry a link, which it will render from a `.link`
/// attribute in the credits.
enum AboutPanel {
    static let homepage = URL(string: "https://matthias.sala.ch")!

    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    static var credits: NSAttributedString {
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center
        centred.lineSpacing = 2

        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: centred
        ]
        var link = body
        link[.link] = homepage
        link[.foregroundColor] = NSColor.linkColor

        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "Made by ", attributes: body))
        text.append(NSAttributedString(string: homepage.host ?? homepage.absoluteString,
                                       attributes: link))
        text.append(NSAttributedString(
            string: "\nbecause looking at a Markdown file should not need a browser engine.",
            attributes: body))
        return text
    }
}
