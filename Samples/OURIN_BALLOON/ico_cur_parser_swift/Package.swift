
// swift-tools-version:5.7
import PackageDescription
let package = Package(
    name: "OurinICO",
    platforms: [.macOS(.v10_15)],
    products: [.library(name: "OurinICO", targets: ["OurinICO"]), .executable(name: "ourin-ico-demo", targets: ["Demo"])],
    targets: [
        .target(name: "OurinICO", path: "Sources/OurinICO"),
        .executableTarget(name: "Demo", dependencies: ["OurinICO"], path: "Sources/Demo"),
    ]
)
