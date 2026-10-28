// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RunGuard",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "RunGuardApp", targets: ["RunGuardApp"]),
        .executable(name: "runguard-cli", targets: ["runguard"]),
        .executable(name: "RunGuardHelper", targets: ["RunGuardHelper"])
    ],
    targets: [
        .target(name: "RunGuardCore", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "RunGuardApp", dependencies: ["RunGuardCore"]),
        .executableTarget(name: "runguard", dependencies: ["RunGuardCore"]),
        .executableTarget(name: "RunGuardHelper")
    ],
    swiftLanguageModes: [.v5]
)
