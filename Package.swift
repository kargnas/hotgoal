// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "hot-goal",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "hot-goal", targets: ["HotGoal"]),
        .executable(name: "hot-goal-helper", targets: ["HotGoalHelper"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.8.1"),
    ],
    targets: [
        .target(
            name: "HotGoalCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "HotGoal",
            dependencies: [
                "HotGoalCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [.linkedFramework("ServiceManagement")]
        ),
        .executableTarget(
            name: "HotGoalHelper",
            dependencies: ["HotGoalCore"]
        ),
        .testTarget(name: "HotGoalTests", dependencies: ["HotGoalCore"]),
    ]
)
