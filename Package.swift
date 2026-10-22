// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Belfer",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Belfer", targets: ["Belfer"])],
    targets: [
        .executableTarget(name: "Belfer", path: "Belfer", exclude: ["Assets.xcassets"]),
        .testTarget(name: "BelferTests", dependencies: ["Belfer"], path: "Tests/BelferTests")
    ]
)
