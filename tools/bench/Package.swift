// swift-tools-version:5.9
// The Industry benchmark harness for this package (see Sources/industry/main.swift).
import PackageDescription

let package = Package(
    name: "industry",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(name: "industry", dependencies: [.product(name: "CorvusRegexEcma262", package: "corvus-regex-ecma262-swift")]),
    ]
)
