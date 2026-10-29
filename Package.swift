// swift-tools-version:5.9
import PackageDescription

// The corvus-regex-ecma262 C library, as the Clang module CCorvusRegexEcma262: on Apple platforms the XCFramework
// attached to the C library's release; elsewhere the C library installed on the system, found through its pkg-config
// file (corvus-regex-ecma262.pc, in the release's archive for the platform).
#if canImport(Darwin)
let cLibrary: Target = .binaryTarget(
    name: "CCorvusRegexEcma262",
    url: "https://github.com/corvus-dotnet/corvus-regex-ecma262-rs/releases/download/v0.2.5/CorvusRegexEcma262.xcframework.zip",
    checksum: "6512b9cac79f77e17fb4dfbe1afe3c41c19827942692d851f2db1a361e4eb4b4"
)
#else
let cLibrary: Target = .systemLibrary(
    name: "CCorvusRegexEcma262",
    path: "Linux/CCorvusRegexEcma262",
    pkgConfig: "corvus-regex-ecma262"
)
#endif

let package = Package(
    name: "CorvusRegexEcma262",
    platforms: [.macOS(.v10_15), .iOS(.v13)],
    products: [
        .library(name: "CorvusRegexEcma262", targets: ["CorvusRegexEcma262"]),
    ],
    targets: [
        cLibrary,
        .target(name: "CorvusRegexEcma262", dependencies: ["CCorvusRegexEcma262"]),
        .testTarget(name: "CorvusRegexEcma262Tests", dependencies: ["CorvusRegexEcma262"]),
    ]
)
