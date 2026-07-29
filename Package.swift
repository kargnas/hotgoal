// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ulfan",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "ulfan", targets: ["ULFan"]),
        .executable(name: "ulfan-helper", targets: ["ULFanHelper"]),
    ],
    targets: [
        .target(
            name: "ULFanCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "ULFan",
            dependencies: ["ULFanCore"],
            linkerSettings: [.linkedFramework("ServiceManagement")]
        ),
        .executableTarget(
            name: "ULFanHelper",
            dependencies: ["ULFanCore"]
        ),
        .testTarget(name: "ULFanTests", dependencies: ["ULFanCore"]),
    ]
)
