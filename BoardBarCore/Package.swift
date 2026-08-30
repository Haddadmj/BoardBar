// swift-tools-version: 6.0
import PackageDescription

// Pure logic lives here — URL parsing, GraphQL decoding, staleness math — so it
// can be tested with `swift test` in about a second and without a provisioning
// profile. The app target depends on this package; nothing in here imports
// SwiftUI or AppKit.
let package = Package(
    name: "BoardBarCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "BoardBarCore", targets: ["BoardBarCore"])],
    targets: [
        .target(name: "BoardBarCore"),
        .testTarget(name: "BoardBarCoreTests", dependencies: ["BoardBarCore"]),
    ]
)
