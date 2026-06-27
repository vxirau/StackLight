// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StackLight",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "StackLight", targets: ["StackLight"])
    ],
    targets: [
        .executableTarget(
            name: "StackLight",
            path: "Sources/Stacklight"
        )
    ]
)
