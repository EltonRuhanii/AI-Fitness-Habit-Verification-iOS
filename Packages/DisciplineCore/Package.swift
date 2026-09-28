// swift-tools-version: 5.9
import PackageDescription

// DisciplineCore holds all platform-independent domain logic (models, streak and
// day-resolution rules, AI verification policy, repetition state machines, research
// export). It depends only on Foundation so it can be unit-tested on any platform.
let package = Package(
    name: "DisciplineCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DisciplineCore", targets: ["DisciplineCore"])
    ],
    targets: [
        .target(name: "DisciplineCore"),
        .testTarget(name: "DisciplineCoreTests", dependencies: ["DisciplineCore"])
    ]
)
