// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MindFlow",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MindFlowKit"),
        .executableTarget(name: "Bough", dependencies: ["MindFlowKit"], path: "Sources/MindFlow"),
        .executableTarget(name: "MindFlowIconGen", dependencies: ["MindFlowKit"], path: "Tools/IconGen"),
        // XCTest is unavailable without full Xcode; a plain executable keeps checks green under CLT.
        .executableTarget(name: "MindFlowChecks", dependencies: ["MindFlowKit"], path: "Checks"),
    ]
)
