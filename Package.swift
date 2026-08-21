// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kite",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "KiteCore", targets: ["KiteCore"]),
        .executable(name: "Kite", targets: ["KiteApp"]),
        .executable(name: "kite-cli", targets: ["KiteCLI"]),
        .executable(name: "kite-self-test", targets: ["KiteSelfTest"])
    ],
    targets: [
        .target(name: "KiteCore"),
        .executableTarget(name: "KiteApp", dependencies: ["KiteCore"]),
        .executableTarget(name: "KiteCLI", dependencies: ["KiteCore"]),
        .executableTarget(name: "KiteSelfTest", dependencies: ["KiteCore"])
    ]
)
