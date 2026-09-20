// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MarkdownCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MarkdownCore", targets: ["MarkdownCore"]),
        .executable(name: "mdv", targets: ["mdv"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", branch: "main"),
        .package(url: "https://github.com/PhraseHQ/SwaTex.git", exact: "0.5.0"),
        .package(url: "https://github.com/Australware/swift-mermaid.git", exact: "0.3.0")
    ],
    targets: [
        .target(
            name: "MarkdownCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "SwaTex", package: "SwaTex"),
                .product(name: "SwaTexRender", package: "SwaTex"),
                .product(name: "Mermaid", package: "swift-mermaid")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "mdv",
            dependencies: ["MarkdownCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MarkdownCoreTests",
            dependencies: ["MarkdownCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
