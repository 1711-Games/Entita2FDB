// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "Entita2FDB",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "Entita2FDB", targets: ["Entita2FDB"]),
    ],
    dependencies: [
        .package(url: "https://github.com/1711-Games/Entita2.git", from: "1.0.0"),
        .package(url: "https://github.com/kirilltitov/FDBSwift.git", .upToNextMajor(from: "5.0.0-RC-3")),
        .package(url: "https://github.com/1711-Games/LGN-Log.git", .upToNextMinor(from: "0.4.0")),
    ],
    targets: [
        .target(
            name: "Entita2FDB",
            dependencies: [
                .product(name: "Entita2", package: "Entita2"),
                .product(name: "FDB", package: "FDBSwift"),
                .product(name: "LGNLog", package: "LGN-Log"),
            ]
        ),
        .testTarget(name: "Entita2FDBTests", dependencies: ["Entita2FDB"]),
    ]
)
