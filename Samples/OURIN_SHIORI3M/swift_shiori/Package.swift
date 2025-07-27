// swift-tools-version:5.7
import PackageDescription
let package = Package(
    name: "OurinSwiftSHIORI",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(name: "OurinSwiftSHIORI", type: .dynamic, targets: ["OurinSwiftSHIORI"])
    ],
    targets: [
        .target(name: "OurinSwiftSHIORI", path: "Sources")
    ]
)
