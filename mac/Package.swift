// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macwinkvm",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "KVMCore"),
        .target(name: "KVMRuntime", dependencies: ["KVMCore"]),
        .executableTarget(name: "macwinkvm-cli", dependencies: ["KVMRuntime"]),
        .executableTarget(name: "macwinkvm", dependencies: ["KVMRuntime"]),
        .testTarget(name: "KVMCoreTests", dependencies: ["KVMCore"]),
    ]
)
