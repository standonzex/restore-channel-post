// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChannelRecoveryKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "ChannelRecoveryKit", type: .static, targets: ["ChannelRecoveryKit"]),
        .executable(name: "RecoveryKitChecks", targets: ["RecoveryKitChecks"])
    ],
    targets: [
        .target(name: "ChannelRecoveryKit"),
        .executableTarget(name: "RecoveryKitChecks", dependencies: ["ChannelRecoveryKit"], path: "Checks")
    ]
)
