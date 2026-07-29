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
    ],
    targets: [
        .target(
            name: "HotTargetCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "HotTarget",
            dependencies: ["HotTargetCore"],
            linkerSettings: [.linkedFramework("ServiceManagement")]
        ),
        .executableTarget(
            name: "HotTargetHelper",
            dependencies: ["HotTargetCore"]
        ),
        .testTarget(name: "HotTargetTests", dependencies: ["HotTargetCore"]),
    ]
)
