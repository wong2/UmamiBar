// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UmamiBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "UmamiBar", targets: ["UmamiBar"]),
        .library(name: "UmamiBarCore", targets: ["UmamiBarCore"]),
    ],
    targets: [
        .target(name: "UmamiBarCore"),
        .executableTarget(
            name: "UmamiBar",
            dependencies: ["UmamiBarCore"]
        ),
        .testTarget(
            name: "UmamiBarTests",
            dependencies: ["UmamiBarCore"]
        ),
    ]
)
