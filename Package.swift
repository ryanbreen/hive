// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Hive",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Hive", targets: ["Hive"])
    ],
    targets: [
        .executableTarget(
            name: "Hive",
            path: "Sources/Hive"
        )
    ]
)
