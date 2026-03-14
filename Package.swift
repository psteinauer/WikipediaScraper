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
        .executableTarget(
            name: "WikipediaScraper",
            dependencies: [
                .product(name: "ArgumentParser",  package: "swift-argument-parser"),
                .product(name: "ZIPFoundation",   package: "ZIPFoundation"),
            ],
            path: "Sources/WikipediaScraper"
        ),
    ]
)
