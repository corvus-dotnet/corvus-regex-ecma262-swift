# corvus-regex-ecma262 for Swift

Regular expressions with the grammar and the answers of ECMA-262, the `RegExp` of JavaScript, for Swift: the
[corvus-regex-ecma262](https://github.com/corvus-dotnet/corvus-regex-ecma262-rs) C library as a Swift package, for
macOS 10.15 and iOS 13 and later (through the XCFramework the C library's release attaches) and Linux (through the C
library's release archive for the platform).

- Every flag: `d`, `g`, `i`, `m`, `s`, `u`, `v` and `y`, with the grammar of each. Without `u` or `v` a pattern is
  read by the Annex B grammar and matched by UTF-16 code unit, as ECMA-262 matches it; with them, by code point. The
  `v` flag has nested classes, the difference and the intersection of classes, strings in a class and the properties
  of strings.
- ECMAScript 2025: lookbehind, named groups (and a name shared between alternatives), modifier groups such as
  `(?i:...)`, and every Unicode property ECMA-262 lists, from Unicode 17 tables the library carries.
- `String` text, matched over its UTF-8 in place, and `[UInt16]` text, matched as JavaScript holds a string, lone
  surrogates and all. A pattern answers as it does in a browser or Node, which `NSRegularExpression` and Swift's
  `Regex` do not: `^` and `$`, `.`, `\d`, `\w`, `\b`, case folding, `\p{...}` and the rest read as JavaScript reads
  them.
- A pattern without a backreference is matched in time proportional to its size times the text, and a pattern can be
  given a match timeout, as a `Regex` of .NET can, which every method honours and which caps the backtracking memory
  too, so with a timeout neither a pattern nor a text from outside can make a program hang.

**Compliance.** Over the [ECMA-262 test data](https://github.com/corvus-dotnet/ecma262-regex-test-data) (what V8 says
about its patterns and texts, test262's patterns and `exec` calls, the global search, `replace` and `split` among them,
and texts of bytes that are not UTF-8, which it refuses), through this package over `[UInt16]` and `String`, it gives
every answer right and none wrong, refuses no valid pattern, accepts no invalid one and reaches no limit. CI runs
the whole data on Linux, and the data as its own scripts write it for Unicode 13 and 18 and for the grammar of
ECMAScript 2020.

## Install

Add the package to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/corvus-dotnet/corvus-regex-ecma262-swift", from: "0.2.5"),
],
targets: [
    .target(name: "MyApp", dependencies: [.product(name: "CorvusRegexEcma262", package: "corvus-regex-ecma262-swift")]),
]
```

On macOS and iOS that is all: SwiftPM downloads the XCFramework. On Linux, install the C library first: unpack the
archive for the platform (`corvus-regex-ecma262-<version>-x86_64-unknown-linux-gnu.tar.gz` or the `aarch64` one) from
the [C library's release](https://github.com/corvus-dotnet/corvus-regex-ecma262-rs/releases), and make its pkg-config
file and its shared library visible:

```
export PKG_CONFIG_PATH=<unpacked>/lib/pkgconfig LD_LIBRARY_PATH=<unpacked>/lib
```

## Getting started

```swift
import CorvusRegexEcma262

// The flags are those of new RegExp(pattern, flags).
let date = try Regex(#"(?<year>\d{4})-(?<month>\d{2})"#, flags: "gu")

try date.test("due 2026-10")                                  // true
let m = try date.firstMatch(in: "due 2026-10")!
m["year"]                                                     // "2026"
m.utf8Ranges[0]                                               // 4..<11

// Every match of a global search, as matchAll makes it.
try date.matches(in: "2026-10, 2027-01").map(\.value)         // ["2026-10", "2027-01"]

// replace replaces every match with the g flag, and the first without it; a closure may give each replacement.
try date.replace(in: "2026-10, 2027-01", with: "$<month>/$1") // "10/2026, 01/2027"
try date.replace(in: "2026-10") { String($0["month"]!) }      // "10"

// split splices in what the groups captured; a group that did not take part is nil.
try Regex(#"\s*(;)\s*"#).split("a ; b;c")                     // ["a", ";", "b", ";", "c"]
```

## The API

| | |
|---|---|
| `Regex(pattern, flags: "", timeout: nil, edition: .current, unicodeVersion: .default)` | Compiles a pattern as `new RegExp(pattern, flags)` does. `timeout` is the match timeout in seconds (0 for none; `nil` for the default). `edition` and `unicodeVersion` are below. |
| `Regex.defaultTimeout` | The timeout of every pattern compiled without one: `nil` (no limit) unless set. |
| `Regex.isValid(pattern, flags: "", edition: .current, unicodeVersion: .default)` | Whether a pattern is valid, without compiling it. |
| `test(text, from:, timeout:)` | `RegExp.prototype.test` with `lastIndex` at `from` (at `from` alone with `y`). |
| `firstMatch(in: text, from:, timeout:)` | The first match at or after `from`, as `exec` finds it: a `Match`, or `nil`. |
| `matches(in: text)` | A global search as `matchAll` makes it: every `Match`. |
| `matchCount(in: text)` | The number of matches of a global search, without making them. |
| `replace(in: text, with: template)`, `replace(in: text) { m in ... }` | `String.prototype.replace`: the first match, or every match with `g`. |
| `replaceAll(in: text, with: template)`, `replaceAll(in: text) { m in ... }` | `String.prototype.replaceAll`: every match. |
| `split(text, limit:)` | `String.prototype.split`: the pieces, `nil` for a group that did not take part. |
| `source`, `flags`, `timeout`, `edition`, `unicodeVersion`, `groupCount`, `groupNames` | What the pattern is. |
| `Regex.unicodeVersions`, `Regex.defaultUnicodeVersion`, `Regex.latestUnicodeVersion` | The versions of Unicode the package carries, `[13, 17, 18]`, the default (17) and the latest (18). |
| `libraryVersion` | The C library's version. |

Each member has a `utf16:` form over `[UInt16]` (`test(utf16:)`, `firstMatch(utf16:)`, `matches(utf16:)` and so on),
whose positions are code-unit offsets and whose match is a `UTF16Match`. Timeouts are in seconds.

A `Match` has `value` and `range` (the whole match, a `Substring` and a `Range<String.Index>`), `m[group]` and
`range(group)` by number or by name (nil for a group that did not take part), `count` (the groups and the match) and
`utf8Ranges` (each group's UTF-8 offsets). A `UTF16Match` has the same over `ArraySlice<UInt16>` and `Range<Int>`.

**Positions.** Without `u` or `v` a pattern is matched by UTF-16 code unit, so a match can take half of a character
beyond the Basic Multilingual Plane. Over `String` its `range` is the whole character's (a `String.Index` cannot fall
inside one) and its UTF-8 range ends at the character's third byte; over `[UInt16]` it is the lone half, as in
JavaScript. A replacement that splits a character puts U+FFFD for the half left behind.

**Errors.** Each is a `RegexError`, whose `kind` is `.invalidPattern`, `.invalidFlags`, `.patternTooLarge` or
`.matchLimit` (a match that reached its timeout or its cap on backtracking memory), and whose `message` says why.

**Timeouts.** A pattern has a match timeout, as a `Regex` of .NET has: `Regex(pattern, flags: "u", timeout: 1)`, or for
every pattern compiled after it `Regex.defaultTimeout = 1`. Every method that matches gives each of its matches the
timeout and throws a `.matchLimit` error at it; `test` and `firstMatch` take a `timeout:` of their own in its place.
Without a timeout (the default) a match has no limit of time or of memory, so a program that matches a pattern or a
text it did not write should set one. There is no separate form that gives nil for an invalid pattern: `try?` is
that form, and it takes a timeout as the constructor does, so a validator needs no default timeout.

**The edition and the version of Unicode.** Two settings, each independent of the other, are settled when a pattern is
compiled and cost a match nothing:

- `edition: .es2020` reads the pattern with the grammar of ECMAScript 2020, which JSON Schema 2020-12 names. It refuses
  what later editions added, and nothing else: the `d` and `v` flags (`.invalidFlags`), modifier groups such as
  `(?i:...)`, a group name used by two groups, and a property name or value that is not in that edition's tables, such
  as `\p{Script=Yezidi}` (each `.invalidPattern`). A pattern it accepts has the same answers as in today's grammar.
  `.current`, the default, is today's grammar.
- `unicodeVersion:` is the version of Unicode whose tables the pattern is read with: the members of each `\p{...}`,
  the characters of a group name, and case folding. It is `.default` (the version of the V8 the answers are held to, 17
  today), `.v13`, `.v17`, `.v18` or `.latest` (18 today). A `Regex`'s `unicodeVersion` gives the version it resolved to.

```swift
let schemaPattern = try? Regex(#"^\p{L}+$"#, flags: "u", timeout: 1, edition: .es2020, unicodeVersion: .v13)
```

**Threads.** A `Regex` is immutable and `Sendable`, and may be used from any number of threads.

## Benchmarks

The Industry workloads of dotnet/performance, this package against `NSRegularExpression`, Swift's `Regex` and V8, are
on the central page, [corvus-oss.org/corvus-regex-ecma262-benchmarks](https://corvus-oss.org/corvus-regex-ecma262-benchmarks/),
measured nightly on one runner with the engines of every other source.

## Repository

- `Sources/CorvusRegexEcma262`: the Swift API; `Linux/`: the C library's module on Linux; `Tests/`: the tests.
- `tools/dataset`: the test-data runner (`swift run -c release dataset <data> wrong.tsv`, from that directory).
- `tools/bench`: the benchmark harness and the script the image runs; `Dockerfile`: the image the central page runs.

The tools name this package by its path, and SwiftPM names a package by its directory, so they need the repository in
a directory named `corvus-regex-ecma262-swift` (a clone's default).

## Releasing

A release is a GitHub release tagged `v<version>` (SwiftPM reads the version past the `v`). Before it, set the
XCFramework's URL and checksum in `Package.swift` to those of the C library release it is built on (the checksum is
the `.sha256` file attached beside the XCFramework), and the version and each archive's SHA-256 in the Dockerfile and
in CI. The release publishes the harness image with the release's tag.

## Licence

Apache-2.0. See [LICENSE](LICENSE).
