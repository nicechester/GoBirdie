// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GoBirdieCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "GoBirdieCore",
            targets: ["GoBirdieCore"]
        )
    ],
    targets: [
        .target(
            name: "GoBirdieCore",
            path: "Sources/GoBirdieCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
