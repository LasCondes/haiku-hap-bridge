// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HaikuHAPBridge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "haiku-hap-bridge", targets: ["HaikuHAPBridge"])
    ],
    dependencies: [
        .package(url: "https://github.com/LasCondes/HAP.git", revision: "e66f58e5a299bf5d4bcc09ec6f4830776e8b8732")
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
