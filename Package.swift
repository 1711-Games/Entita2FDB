// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "Entita2FDB",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(name: "Entita2FDB", targets: ["Entita2FDB"]),
    ],
    dependencies: [
        .package(url: "https://github.com/1711-Games/Entita2.git", .upToNextMinor(from: "0.1.0")),
        .package(url: "https://github.com/kirilltitov/FDBSwift.git", .upToNextMajor(from: "4.0.0")),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.19.0"),
    ],
    targets: [
        .target(
            name: "Entita2FDB",
            dependencies: [
                .product(name: "Entita2", package: "Entita2"),
                .product(name: "FDB", package: "FDBSwift"),
                .product(name: "NIO", package: "swift-nio"),
            ]
        ),
        .testTarget(name: "Entita2FDBTests", dependencies: ["Entita2FDB"]),
    ]
)
