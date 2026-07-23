// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ThermalIcon",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "ThermalIcon", targets: ["ThermalIcon"]),
        .executable(name: "ThermalIconFanHelper", targets: ["ThermalIconFanHelper"]),
    ],
    targets: [
        .target(
            name: "ThermalIconCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "ThermalIcon",
            dependencies: ["ThermalIconCore"],
            linkerSettings: [.linkedFramework("ServiceManagement")]
        ),
        .executableTarget(
            name: "ThermalIconFanHelper",
            dependencies: ["ThermalIconCore"]
        ),
        .testTarget(name: "ThermalIconTests", dependencies: ["ThermalIconCore"]),
    ]
)
