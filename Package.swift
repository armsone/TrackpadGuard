// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TrackpadGuard",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TrackpadGuard", targets: ["TrackpadGuard"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4")
    ],
    targets: [
        .target(name: "TrackpadGuardCore"),
        .executableTarget(
            name: "TrackpadGuard",
            dependencies: [
                "TrackpadGuardCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "TrackpadGuardCoreTests",
            dependencies: ["TrackpadGuardCore"]
        ),
        .testTarget(
            name: "TrackpadGuardTests",
            dependencies: ["TrackpadGuard"]
        )
    ]
)
