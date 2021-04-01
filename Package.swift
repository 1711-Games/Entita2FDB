// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "Entita2FDB",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(name: "Entita2FDB", targets: ["Entita2FDB"]),
    ],
    dependencies: [
        .package(url: "https://github.com/1711-Games/Entita2.git", .branch("async-await") /*.upToNextMinor(from: "0.1.0")*/),
        .package(url: "https://github.com/kirilltitov/FDBSwift.git", .branch("async-await") /*.upToNextMajor(from: "4.0.0")*/),
    ],
    targets: [
        .target(
            name: "Entita2FDB",
            dependencies: [
                .product(name: "Entita2", package: "Entita2"),
                .product(name: "FDB", package: "FDBSwift"),
            ]
        ),
        .testTarget(name: "Entita2FDBTests", dependencies: ["Entita2FDB"]),
    ]
)
