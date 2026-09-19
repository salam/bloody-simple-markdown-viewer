// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MarkdownCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MarkdownCore", targets: ["MarkdownCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", branch: "main")
    ],
    targets: [
        .target(
            name: "MarkdownCore",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MarkdownCoreTests",
            dependencies: ["MarkdownCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
