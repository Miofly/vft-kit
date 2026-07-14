// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "cc-helper",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CCHelperCore"),
        .executableTarget(
            name: "cc-helper",
            dependencies: ["CCHelperCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CCHelperCoreTests",
            dependencies: ["CCHelperCore"]
        )
    ]
)
