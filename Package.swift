// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MainThreadWatchdog",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MainThreadWatchdog", targets: ["MainThreadWatchdog"]),
    ],
    targets: [
        .target(name: "MainThreadWatchdog", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "MainThreadWatchdogTests", dependencies: ["MainThreadWatchdog"]),
    ]
)
