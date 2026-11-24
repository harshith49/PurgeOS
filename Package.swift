// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "PurgeOS", platforms: [.macOS(.v13)], products: [.executable(name: "PurgeOS", targets: ["PurgeOS"])], targets: [.target(name: "PurgeCore"), .executableTarget(name: "PurgeOS", dependencies: ["PurgeCore"]), .executableTarget(name: "SafetyChecks", dependencies: ["PurgeCore"], path: "Tests/SafetyChecks")])
