// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PatchClientPolicyChecks",
    products: [.library(name: "PatchClientCore", targets: ["PatchClientCore"])],
    targets: [
        .target(name: "TelegramApi"),
        .target(name: "PatchClientCore", dependencies: ["TelegramApi"]),
        .testTarget(name: "PatchClientCoreTests", dependencies: ["PatchClientCore", "TelegramApi"])
    ]
)
