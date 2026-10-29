# Contributing

This guide is for someone who wants to build the package, run its tests and gates, and open a pull request. It covers
the tools, the build step by step, the gates every change must pass, and how the package is released. The
[design document](design.md) describes what is underneath.

## 1. Tools

| Tool | Needed for | Version |
|---|---|---|
| Swift | Everything | 5.9 or later; Xcode on macOS, or the toolchain or the `swift` image on Linux |
| The C library | Linux: the package links it | The release `Package.swift` names, unpacked from its archive for the platform |
| pkg-config | Linux: finding the C library | Any recent version |
| Git | The repository and the test data | Any recent version |
| Node.js | The test data for other versions of Unicode and for ECMAScript 2020, and the V8 rows of the harness | 24 (the V8 it carries is the oracle) |

- **macOS:** Xcode (or its command line tools); SwiftPM downloads the C library as an XCFramework. `brew install git
  node@24`.
- **Linux:** the Swift toolchain from [swift.org](https://www.swift.org/install/) (or `docker.io/library/swift:6.4`),
  `pkg-config`, and the C library: unpack the archive for the platform from
  [its release](https://github.com/corvus-dotnet/corvus-regex-ecma262-rs/releases) and set
  `PKG_CONFIG_PATH=<unpacked>/lib/pkgconfig` and `LD_LIBRARY_PATH=<unpacked>/lib`.

## 2. Getting the sources

```
git clone https://github.com/corvus-dotnet/corvus-regex-ecma262-swift.git
git clone https://github.com/corvus-dotnet/ecma262-regex-test-data.git   # beside it: the test data
cd corvus-regex-ecma262-swift
```

Keep the directory's name: SwiftPM names a package by its directory, and the tools find this package by it. The test
data is the oracle for the engine; the commands below assume it at `../ecma262-regex-test-data`.

## 3. Building and testing, step by step

Every command runs from the repository root.

1. **The tests.** `swift test -j 4` builds the package and runs the tests.
2. **The getting-started programs.** `swift tools/docs/run-getting-started.swift` builds each program of the page as
   an executable of one package over this one, and runs it.
3. **iOS.** On macOS, `xcodebuild build -scheme CorvusRegexEcma262 -destination 'generic/platform=iOS'`, and again for
   `'generic/platform=iOS Simulator'`.
4. **The test data.** From `tools/dataset`: `swift run -c release dataset ../../../ecma262-regex-test-data/data
   wrong-cases.tsv` must report 0 wrong, 0 refused and 0 at a limit. For the other versions of Unicode and for
   ECMAScript 2020, write the data with its own scripts (`unicode.js apply`, `edition.js apply` in the data
   repository) and run it with `--unicode 13` or `--edition es2020`, as CI does.

## 4. The C library

The package is built on one release of the C library: `Package.swift` names its XCFramework's URL and checksum (the
`.sha256` file attached beside it), and the Dockerfile and CI name the version and each Linux archive's SHA-256. Moving
to a new C library release moves all of them. A fix to the engine's answers is made in
[the C library's repository](https://github.com/corvus-dotnet/corvus-regex-ecma262-rs) and taken here by moving the
release.

## 5. Benchmarks

`tools/bench/run.sh <workloads.json> <texts directory> <out.json>` runs this package, `NSRegularExpression` and V8 over
the Industry workloads; the script lists what it needs and its settings. The published figures are on
[the benchmark page](https://corvus-oss.org/corvus-regex-ecma262-benchmarks/), which runs this repository's harness
image each night beside every other engine; a run on another machine is comparable with itself, never with the page.

## 6. What a pull request needs

- **The gates of section 3** passing on the change as pushed, on Linux and macOS.
- **A fix to the engine's answers in the C library's repository**, with its case in the test data first.
- **A failing test first** for a bug in the package: the test that reproduces it, then the fix.
- **The design document kept current**, describing the package as it is.
- **Documentation comments** on every public declaration, since the API reference on the Swift Package Index is
  generated from them.
- **The getting-started page** kept true: its programs are built and run in CI.

### Conventions

- Swift that builds without warnings, with every public type `Sendable` where it can be.
- A `String`'s UTF-8 goes to the C library as it lies, with no copy and no second check.

## 7. Releases

A release is made by hand, as a GitHub release tagged `v<version>` (SwiftPM reads the version past the `v`). Before it,
a pull request moves the C library's release (section 4). The release publishes the harness image with its tag. A change
to the benchmark harness alone is a harness release (`gh release create harness-<version>.<n> --latest=false`), which
publishes the harness image. The documentation site takes the published documents (the getting-started page, the API
reference, the design document and this guide) from `main`, and they describe the latest release: a change to them alone
needs no release, and a change to the API carries its documents and is released straight after it is merged.

`main` is protected by a ruleset: changes arrive by pull request, and the `CI gate` and `Harness image` checks must be
green on the branch as it will merge.
