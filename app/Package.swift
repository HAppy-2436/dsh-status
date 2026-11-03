// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DSHStatusBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DSHStatusBar", targets: ["DSHStatusBar"])
    ],
    targets: [
        .executableTarget(
            name: "DSHStatusBar",
            path: "Sources/DSHStatusBar"
        )
    ]
)
