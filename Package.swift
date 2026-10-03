// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "TalkTimer",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "TalkTimerCore", targets: ["TalkTimerCore"]),
    .executable(name: "TalkTimer", targets: ["TalkTimerApp"])
  ],
  targets: [
    .target(name: "TalkTimerCore"),
    .executableTarget(name: "TalkTimerApp", dependencies: ["TalkTimerCore"]),
    .testTarget(name: "TalkTimerCoreTests", dependencies: ["TalkTimerCore"]),
    .testTarget(name: "TalkTimerAppTests", dependencies: ["TalkTimerApp", "TalkTimerCore"])
  ]
)
