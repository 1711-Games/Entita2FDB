// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Entita2FDB",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(name: "Entita2FDB", targets: ["Entita2FDB"]),
    ],
    dependencies: [
        .package(url: "git@github.com:kirilltitov/Entita2.git", .branch("master")),
        .package(url: "https://github.com/kirilltitov/FDBSwift.git", .upToNextMajor(from: "4.0.0"))
    ],
    targets: [
        .target(name: "Entita2FDB", dependencies: ["Entita2", "FDB"]),
        .testTarget(name: "Entita2FDBTests", dependencies: ["Entita2FDB"]),
    ]
)
