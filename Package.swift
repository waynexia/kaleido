// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kaleido",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "KaleidoCore", targets: ["KaleidoCore"]),
        .executable(name: "Kaleido", targets: ["Kaleido"]),
    ],
    targets: [
        .target(name: "KaleidoCore"),
        .executableTarget(name: "Kaleido", dependencies: ["KaleidoCore"]),
        .testTarget(name: "KaleidoCoreTests", dependencies: ["KaleidoCore"]),
        .testTarget(name: "KaleidoTests", dependencies: ["Kaleido"]),
    ],
    swiftLanguageModes: [.v5]
)
