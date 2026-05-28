// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YOLOWhisp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "YOLOWhisp",
            path: "Sources/YOLOWhisp",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "YOLOWhispTests",
            dependencies: ["YOLOWhisp"],
            path: "Tests/YOLOWhispTests"
        ),
    ]
)
