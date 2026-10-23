// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Blockbottle",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Blockbottle", targets: ["Blockbottle"]),
        .library(name: "BlockbottleCore", targets: ["BlockbottleCore"]),
    ],
    targets: [
        .target(name: "BlockbottleCore"),
        .executableTarget(name: "Blockbottle", dependencies: ["BlockbottleCore"]),
        .testTarget(name: "BlockbottleCoreTests", dependencies: ["BlockbottleCore"]),
    ]
)
