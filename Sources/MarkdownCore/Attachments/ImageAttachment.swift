import AppKit

/// An inline image. Local files load immediately; remote URLs load off the main
/// thread and invalidate only their own range when they arrive.
public final class ImageTextAttachment: NSTextAttachment {
    public let url: URL
    public let altText: String
    private let theme: Theme
    private var loaded = false

    /// Images wider than this are scaled down to fit the reading column.
    private let maxWidth: CGFloat = 680

    public init(url: URL, theme: Theme, altText: String) {
        self.url = url
        self.theme = theme
        self.altText = altText
        super.init(data: nil, ofType: nil)
        loadIfLocal()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func loadIfLocal() {
        guard url.isFileURL, let image = NSImage(contentsOf: url) else {
            // Remote or missing: show the alt text until or unless it loads.
            bounds = .zero
            return
        }
        apply(image)
    }

    private func apply(_ image: NSImage) {
        self.image = image
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = min(1, maxWidth / size.width)
        bounds = CGRect(x: 0, y: 0,
                        width: (size.width * scale).rounded(),
                        height: (size.height * scale).rounded())
        loaded = true
    }

    /// Fetches a remote image. Call from the main thread; the completion also
    /// arrives on the main thread so the caller can invalidate layout.
    public func loadRemote(completion: @escaping () -> Void) {
        guard !loaded, !url.isFileURL else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self.apply(image)
                completion()
            }
        }.resume()
    }
}
