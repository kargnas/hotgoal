// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "hotgoal",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "hotgoal", targets: ["HotGoal"]),
        .executable(name: "hotgoal-helper", targets: ["HotGoalHelper"]),
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
