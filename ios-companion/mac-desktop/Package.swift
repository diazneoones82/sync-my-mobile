// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SyncMyMobileMac",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "SyncMyMobileMac", targets: ["SyncMyMobileMac"]),
    ],
    targets: [
        .executableTarget(
            name: "SyncMyMobileMac",
            path: "Sources/SyncMyMobileMac",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
