// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "OurinSSTPServer",
    platforms: [.macOS(.v10_15)],
    products: [
        .executable(name: "ourin-sstp", targets: ["OurinSSTPServer"]),
    ],
    targets: [
        .executableTarget(
            name: "OurinSSTPServer",
            path: "Sources"
        )
    ]
)
