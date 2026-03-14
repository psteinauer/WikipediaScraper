// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WikipediaScraper",
    platforms: [.macOS(.v13), .iOS(.v16)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.19"),
    ],
    targets: [
        // Core library — shared by CLI, macOS app, and iPadOS app
        .target(
            name: "WikipediaScraperCore",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Sources/WikipediaScraperCore"
        ),

        // Shared SwiftUI views and editable model types (compiles on macOS + iOS)
        .target(
            name: "WikipediaScraperSharedUI",
            dependencies: ["WikipediaScraperCore"],
            path: "Sources/WikipediaScraperSharedUI"
        ),

        // Command-line tool (macOS only)
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
            dependencies: ["WikipediaScraperCore", "WikipediaScraperSharedUI"],
            path: "Sources/WikipediaScraperApp",
            exclude: ["Info.plist"],
            resources: [
                .process("Assets.xcassets"),
            ]
        ),

        // iPadOS SwiftUI app
        .executableTarget(
            name: "WikipediaScraperIPad",
            dependencies: ["WikipediaScraperCore", "WikipediaScraperSharedUI"],
            path: "Sources/WikipediaScraperIPad",
            exclude: ["Info.plist"],
            resources: [
                .process("Assets.xcassets"),
            ]
        ),
    ]
)
