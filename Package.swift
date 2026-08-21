// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftGo",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SwiftActivityCore", targets: ["SwiftActivityCore"]),
        .executable(name: "SwiftGo", targets: ["SwiftActivityApp"]),
        .executable(name: "swift-activity", targets: ["SwiftActivityCLI"]),
        .executable(name: "swift-activity-self-test", targets: ["SwiftActivitySelfTest"])
    ],
    targets: [
        .target(name: "SwiftActivityCore"),
        .executableTarget(name: "SwiftActivityApp", dependencies: ["SwiftActivityCore"]),
        .executableTarget(name: "SwiftActivityCLI", dependencies: ["SwiftActivityCore"]),
        .executableTarget(name: "SwiftActivitySelfTest", dependencies: ["SwiftActivityCore"])
    ]
)
