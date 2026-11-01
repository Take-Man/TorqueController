// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TorqueController",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TorqueEngine", targets: ["TorqueEngine"]),
        .executable(name: "torque-cli", targets: ["TorqueCLI"]),
        .executable(name: "TorqueController", targets: ["TorqueController"]),
    ],
    targets: [
        .target(name: "TorqueEngine"),
        .executableTarget(name: "TorqueCLI", dependencies: ["TorqueEngine"]),
        .executableTarget(name: "TorqueController", dependencies: ["TorqueEngine"]),
        .testTarget(name: "TorqueEngineTests", dependencies: ["TorqueEngine"]),
        .testTarget(name: "TorqueControllerTests", dependencies: ["TorqueController"]),
    ]
)
