// swift-tools-version:5.7
import PackageDescription
let package = Package(
    name: "OurinShioriHost",
    platforms: [.macOS(.v10_15)],
    products: [.executable(name: "ourin-shiori-host", targets: ["OurinShioriHost"])],
    targets: [.executableTarget(name: "OurinShioriHost", path: "Sources")]
)
