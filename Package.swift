// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "WatchlyCore", platforms: [.macOS(.v13), .tvOS(.v16)], products: [
    .library(name: "WatchlyCore", targets: ["WatchlyCore"])
], targets: [
    .target(name: "WatchlyCore", path: "Sources/Core"),
    .testTarget(name: "WatchlyCoreTests", dependencies: ["WatchlyCore"], path: "Tests")
])
