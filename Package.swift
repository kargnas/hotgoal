// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "hot-goal-for-mac",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "hot-goal-for-mac", targets: ["HotGoalForMac"]),
        .executable(name: "hot-goal-for-mac-helper", targets: ["HotGoalForMacHelper"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.8.1"),
    ],
    targets: [
        .target(
            name: "HotGoalForMacCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "HotGoalForMac",
            dependencies: [
                "HotGoalForMacCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [.linkedFramework("ServiceManagement")]
        ),
        .executableTarget(
            name: "HotGoalForMacHelper",
            dependencies: ["HotGoalForMacCore"]
        ),
        .testTarget(name: "HotGoalForMacTests", dependencies: ["HotGoalForMacCore"]),
    ]
)
