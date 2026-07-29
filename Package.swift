// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ulfan",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "hottarget", targets: ["HotTarget"]),
        .executable(name: "ulfan-helper", targets: ["ULFanHelper"]),
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
            name: "ULFanHelper",
            dependencies: ["HotTargetCore"]
        ),
        .testTarget(name: "HotTargetTests", dependencies: ["HotTargetCore"]),
    ]
)
