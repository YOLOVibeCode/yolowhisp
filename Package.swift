// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YOLOWhisp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "YOLOWhisp",
            path: "Sources/YOLOWhisp"
        ),
        .testTarget(
            name: "YOLOWhispTests",
            dependencies: ["YOLOWhisp"],
            path: "Tests/YOLOWhispTests"
        ),
    ]
)
