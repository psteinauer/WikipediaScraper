// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WikipediaScraper",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.19"),
    ],
    targets: [
        // Core library — shared by both CLI and GUI
        .target(
            name: "WikipediaScraperCore",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Sources/WikipediaScraperCore"
        ),
        // Command-line tool
        .executableTarget(
            name: "WikipediaScraper",
            dependencies: [
                "WikipediaScraperCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/WikipediaScraper"
        ),
        // macOS SwiftUI app
        .executableTarget(
            name: "WikipediaScraperApp",
            dependencies: ["WikipediaScraperCore"],
            path: "Sources/WikipediaScraperApp",
            exclude: ["Info.plist"],
            resources: [
                .process("Assets.xcassets"),
            ]
        ),
    ]
)
