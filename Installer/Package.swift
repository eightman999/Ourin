// swift-tools-version:5.9
// Ourin 専用インストーラー。Xcode プロジェクトとは独立に SwiftPM でビルドし、
// scripts/build-installer.sh が .app バンドルへ組み立てる。
import PackageDescription

let package = Package(
    name: "OurinInstaller",
    defaultLocalization: "ja",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "OurinInstaller", targets: ["OurinInstaller"]),
    ],
    targets: [
        // UI を持たない処理（SSP 検出・移行・app 差し替え）。テスト対象。
        .target(name: "OurinInstallerCore"),
        .executableTarget(
            name: "OurinInstaller",
            dependencies: ["OurinInstallerCore"]
        ),
        .testTarget(
            name: "OurinInstallerCoreTests",
            dependencies: ["OurinInstallerCore"]
        ),
    ]
)
