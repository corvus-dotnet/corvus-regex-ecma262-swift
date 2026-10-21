// swift-tools-version:5.9
// The ECMA-262 test-data runner for this package: `swift run -c release dataset <data directory> <wrong-cases file>`.
import PackageDescription

let package = Package(
    name: "dataset",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(name: "dataset", dependencies: [.product(name: "CorvusRegexEcma262", package: "corvus-regex-ecma262-swift")]),
    ]
)
