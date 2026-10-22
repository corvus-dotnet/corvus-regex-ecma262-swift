// swift-tools-version:5.9
import PackageDescription

// The corvus-regex-ecma262 C library, as the Clang module CCorvusRegexEcma262: on Apple platforms the XCFramework
// attached to the C library's release; elsewhere the C library installed on the system, found through its pkg-config
// file (corvus-regex-ecma262.pc, in the release's archive for the platform).
#if canImport(Darwin)
let cLibrary: Target = .binaryTarget(
    name: "CCorvusRegexEcma262",
    url: "https://github.com/corvus-dotnet/corvus-regex-ecma262-rs/releases/download/v0.2.0/CorvusRegexEcma262.xcframework.zip",
    checksum: "fcf3e5cde346833ed5e4c5a7faa4b8b9d6a6e5cc1a338127cae99b2988abe691"
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
