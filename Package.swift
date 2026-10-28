// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RunGuard",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "RunGuard", targets: ["RunGuardApp"]),
        .executable(name: "runguard", targets: ["runguard"])
    ],
    targets: [
        .target(name: "RunGuardCore", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "RunGuardApp", dependencies: ["RunGuardCore"]),
        .executableTarget(name: "runguard", dependencies: ["RunGuardCore"])
    ],
    swiftLanguageModes: [.v5]
)
