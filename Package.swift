// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "whooshing.nexus",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .watchOS(.v6),
        .tvOS(.v13),
    ],
    products: [
        .library( name: "Nexus", targets: ["Nexus"] )
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor", from: "4.122.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.10.0"),
        .package(url: "https://github.com/apple/swift-system", from: "1.7.5"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.6.0"),
        .package(url: "https://github.com/Flight-School/AnyCodable", from: "0.6.0"),
        .package(url: "https://github.com/whooshing-workshop/whooshing.toolbox-basic.git", from: "1.6.2")
    ],
    targets: [
        .target(
            name: "Nexus",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "AnyCodable", package: "AnyCodable"),
                .product(name: "Cryptos", package: "whooshing.toolbox-basic"),
                .product(name: "LoggingAdvanced", package: "whooshing.toolbox-basic"),
                .product(name: "NIOAdvanced", package: "whooshing.toolbox-basic"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "OrderedCollections", package: "swift-collections")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "nexus-Tests",
            dependencies: [
                .target(name: "Nexus"),
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
    ]
)
