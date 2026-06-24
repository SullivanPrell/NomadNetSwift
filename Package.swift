// swift-tools-version:5.9
import PackageDescription
import Foundation

// ReticulumSwift dependency.
//
// Consumers get the published release from GitHub. For developing the whole
// stack from sibling checkouts (ReticulumSwift next to this repo), set
// RETICULUM_LOCAL_DEPS=1 to use the local path instead:
//
//   RETICULUM_LOCAL_DEPS=1 swift test
//
let useLocalDeps = ProcessInfo.processInfo.environment["RETICULUM_LOCAL_DEPS"] != nil
let reticulumDependency: Package.Dependency = useLocalDeps
    ? .package(path: "../ReticulumSwift")
    : .package(url: "https://github.com/SullivanPrell/ReticulumSwift.git", from: "1.0.0")

let package = Package(
    name: "NomadNetSwift",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "NomadNet", targets: ["NomadNet"]),
    ],
    dependencies: [
        reticulumDependency,
    ],
    targets: [
        .target(
            name: "NomadNet",
            dependencies: [
                .product(name: "ReticulumSwift", package: "ReticulumSwift"),
            ]
        ),
        .testTarget(
            name: "NomadNetTests",
            dependencies: [
                "NomadNet",
                .product(name: "ReticulumSwift", package: "ReticulumSwift"),
            ]
        ),
    ]
)
