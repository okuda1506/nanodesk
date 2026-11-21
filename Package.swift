// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NanoDesk",
    platforms: [.macOS(.v15)],
    products: [.library(name: "NanoDeskCore", targets: ["NanoDeskCore"])],
    targets: [
        .target(name: "NanoDeskCore"),
        .testTarget(name: "NanoDeskCoreTests", dependencies: ["NanoDeskCore"])
    ]
)
