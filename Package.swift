// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HaikuHAPBridge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "haiku-hap-bridge", targets: ["HaikuHAPBridge"])
    ],
    dependencies: [
        .package(url: "https://github.com/Bouke/HAP.git", branch: "master")
    ],
    targets: [
        .executableTarget(
            name: "HaikuHAPBridge",
            dependencies: [
                .product(name: "HAP", package: "HAP")
            ],
            path: "Sources/HaikuHAPBridge"
        )
    ]
)
