// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HaikuHAPBridge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "haiku-hap-bridge", targets: ["HaikuHAPBridge"])
    ],
    dependencies: [
        .package(url: "https://github.com/LasCondes/HAP.git", revision: "2af63825c4067929f54e76d5bcfc11a5f52b04ea")
    ],
    targets: [
        .executableTarget(
            name: "HaikuHAPBridge",
            dependencies: [
                .product(name: "HAP", package: "HAP")
            ],
            path: "Sources/HaikuHAPBridge",
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-strict-concurrency=minimal"])
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
