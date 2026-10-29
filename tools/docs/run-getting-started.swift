// Builds and runs each program of the getting-started page the documentation site publishes (docs/getting-started.md),
// so that the page shows only code that works: swift tools/docs/run-getting-started.swift, from the repository.
//
// Each block of Swift on the page that is more than an import is the main.swift of an executable of one package,
// which depends on this repository's package; the package is built once, then each executable is run. A program that
// does not build, or stops (a failed precondition), fails the script.

import Foundation

let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let page = try String(contentsOf: repository.appendingPathComponent("docs/getting-started.md"), encoding: .utf8)

var blocks: [String] = []
var current: [String]? = nil
for line in page.components(separatedBy: "\n") {
    if current == nil, line == "```swift" {
        current = []
    } else if current != nil, line == "```" {
        let code = current!.joined(separator: "\n")
        // A block that is only the import, such as Setup's, is not a program.
        if code.trimmingCharacters(in: .whitespacesAndNewlines) != "import CorvusRegexEcma262" {
            blocks.append(code)
        }
        current = nil
    } else if current != nil {
        current!.append(line)
    }
}
guard blocks.count >= 5 else {
    fatalError("the page has \(blocks.count) programs")
}

let work = FileManager.default.temporaryDirectory.appendingPathComponent("getting-started-\(ProcessInfo.processInfo.processIdentifier)")
defer { try? FileManager.default.removeItem(at: work) }
var targets: [String] = []
for (n, code) in blocks.enumerated() {
    let name = "Example\(n + 1)"
    let directory = work.appendingPathComponent("Sources/\(name)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try code.write(to: directory.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
    targets.append("        .executableTarget(name: \"\(name)\", dependencies: [.product(name: \"CorvusRegexEcma262\", package: \"\(repository.lastPathComponent)\")]),")
}
let manifest = """
    // swift-tools-version:5.9
    import PackageDescription

    let package = Package(
        name: "GettingStarted",
        platforms: [.macOS(.v10_15), .iOS(.v13)],
        dependencies: [.package(path: "\(repository.path)")],
        targets: [
    \(targets.joined(separator: "\n"))
        ]
    )

    """
try manifest.write(to: work.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

@discardableResult
func run(_ arguments: [String]) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.currentDirectoryURL = work
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

guard try run(["swift", "build", "-j", "4"]) == 0 else {
    fatalError("the getting-started programs did not build")
}
var failed: [String] = []
for n in 1...blocks.count {
    if try run(["swift", "run", "--skip-build", "Example\(n)"]) != 0 {
        failed.append("Example\(n)")
    } else {
        print("Example\(n): ok")
    }
}
guard failed.isEmpty else {
    fatalError("the getting-started programs that failed: \(failed.joined(separator: ", "))")
}
print("\(blocks.count) getting-started programs built and ran.")
