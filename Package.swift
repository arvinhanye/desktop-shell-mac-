// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DesktopShell",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DesktopShell", targets: ["DesktopShell"])
    ],
    targets: [
        .executableTarget(name: "DesktopShell")
    ],
    swiftLanguageModes: [.v5]
)
