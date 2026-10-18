// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HabitGate", platforms: [.macOS(.v13)],
    products: [.executable(name: "HabitGate", targets: ["HabitGate"]),
               .executable(name: "HabitGateBridge", targets: ["HabitGateBridge"])],
    targets: [.target(name: "GateCore"),
              .executableTarget(name: "HabitGate", dependencies: ["GateCore"]),
              .executableTarget(name: "HabitGateBridge", dependencies: ["GateCore"]),
              .testTarget(name: "GateCoreTests", dependencies: ["GateCore"]),
              .testTarget(name: "HabitGateTests", dependencies: ["HabitGate"])])
