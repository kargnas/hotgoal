// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "hottarget",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "hottarget", targets: ["HotTarget"]),
        .executable(name: "hottarget-helper", targets: ["HotTargetHelper"]),
        .executable(name: "hot-goal-for-mac", targets: ["HotGoalForMac"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.8.1"),
    ],
    targets: [
        .target(
            name: "HotTargetCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
            ]
        ),
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
            name: "HotTarget",
            dependencies: [
                "HotTargetCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [.linkedFramework("ServiceManagement")]
        ),
        .executableTarget(
            name: "HotTargetHelper",
            dependencies: ["HotTargetCore"]
        ),
        .testTarget(name: "HotTargetTests", dependencies: ["HotTargetCore"]),
    ]
)
