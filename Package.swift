// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ThermalIcon",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "ThermalIcon", targets: ["ThermalIcon"]),
    ],
    targets: [
        .executableTarget(name: "ThermalIcon"),
        .testTarget(name: "ThermalIconTests", dependencies: ["ThermalIcon"]),
    ]
)
