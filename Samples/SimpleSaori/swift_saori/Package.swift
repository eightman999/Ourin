// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SimpleSaoriSwift",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "simple_saori_swift", type: .dynamic, targets: ["simple_saori_swift"])
    ],
    targets: [
        .target(name: "simple_saori_swift", path: "Sources")
    ]
)

