# CorvusRegexEcma262 for Swift: design

An outline of the package as it is: what it offers, how it is built and why, and how it is tested and measured. The
[getting-started page](getting-started.md) shows how to use it.

## 1. What it is

A Swift package of regular expressions with ECMA-262's grammar and answers (ECMAScript 2025), over `String` and
`[UInt16]`. It is a binding to the corvus-regex-ecma262 C library, built from the Rust crate, whose engine it uses as
it is.

**Why ECMA-262.** JSON Schema, OpenAPI and many wire formats specify their patterns as ECMAScript regular
expressions. `NSRegularExpression` (ICU) and Swift's `Regex` have their own grammars and their own meaning for `^`,
`$`, `\d`, `\w`, `\s`, `.` and case folding, and Swift's `Regex` matches by grapheme cluster, so a translation to them
can never be exact. An engine that reads ECMA-262 directly, held to V8's answers over a large data set (section 6),
needs no translation.

## 2. Public surface

**Names.** A final class `Regex` in the module `CorvusRegexEcma262`, with `test`, `firstMatch(in:)`, `matches(in:)`,
`matchCount(in:)`, `replace(in:with:)` (or a closure), `replaceAll` and `split`, the methods of a `RegExp` named as
Swift names methods, each taking the position as `from:` where JavaScript keeps `lastIndex`. Each has a `utf16:` form.
A `Match` holds its groups as `Substring`s and as ranges (`Range<String.Index>`, and UTF-8 offsets beside them); a
`UTF16Match` as `ArraySlice<UInt16>` and `Range<Int>`.

**Flags.** ECMA-262's, as a string, and nothing else.

**Edition and Unicode version.** By default a pattern is read with today's grammar (`edition: .current`) and V8's
version of Unicode (`unicodeVersion: .default`, 17 today). Either is overridden when the pattern is compiled,
independently: `.es2020` is the grammar JSON Schema 2020-12 names, and the versions are `.v13`, `.v17`, `.v18` and
`.latest`. Both are resolved when the pattern is compiled.

**Errors.** Each failure throws a `RegexError`, whose `kind` is `.invalidPattern`, `.invalidFlags`, `.patternTooLarge`
or `.matchLimit` and whose `message` says why. `try?` is the form that gives `nil` in place of an error, and takes a
timeout as the initialiser does.

**ECMA-262 algorithms.** `replace` substitutes as `GetSubstitution` does, replacing every match only with `g`, or
calls a closure with each `Match`; `replaceAll` always replaces every match. `split` follows
`RegExp.prototype[Symbol.split]`, with `nil` for a group that did not take part.

**Input.** A `String` is matched as its UTF-8, in place. A `String` is always valid Unicode, so there is nothing to
refuse. `[UInt16]` text is UTF-16 code units, lone surrogates and all, with ranges in code units, as JavaScript,
`NSString` and `NSRange` count them. Nothing is transcoded.

**Limits.** The C library's: a match timeout in seconds per pattern or for every pattern (`Regex.defaultTimeout`),
with a `timeout:` of its own on `test` and `firstMatch`; the size limits; and no stack overflow.

## 3. Engine

The engine is the Rust crate's, which
[its design](https://github.com/corvus-dotnet/corvus-regex-ecma262-rs/blob/main/docs/design.md) describes, reached
through the C library ([its design](https://github.com/corvus-dotnet/corvus-regex-ecma262-rs/blob/main/docs/design-c.md)).
The package's work is between Swift and the C library:

- **Handles.** A `Regex` owns the C library's compiled pattern and frees it when it is released; it is immutable and
  `Sendable`, so any number of threads use one at once.
- **Text.** A `String`'s contiguous UTF-8 goes to the C library's `_unchecked` functions as it lies, since a `String`
  is always UTF-8 and needs no second check; `[UInt16]` goes as its code units.
- **Without u or v.** A match can take half of a character beyond the Basic Multilingual Plane. Over a `String` its
  range is the whole character's, since a `String.Index` cannot fall inside one, and its UTF-8 range ends at the
  character's third byte; over `[UInt16]` it is the lone half, as in JavaScript.
- **Errors.** A status other than `CRE_OK` is thrown as a `RegexError` with the C library's message.

## 4. The C library

On macOS and iOS, SwiftPM downloads the C library as the XCFramework its release attaches, named in `Package.swift` by
its URL and checksum. On Linux the package's `Linux/CCorvusRegexEcma262` module finds the C library installed on the
system through its pkg-config file. The version and each archive's hash are named in `Package.swift`, the Dockerfile
and CI.

## 5. Targets and layout

macOS 10.15, iOS 13 and later, and Linux (x64 and arm64), with Swift 5.9 and later.

- `Sources/CorvusRegexEcma262`: the Swift API; `Linux/`: the C library's module on Linux; `Tests/`: the tests.
- `tools/dataset`: the test-data runner; `tools/docs`: the getting-started runner; `tools/bench`: the benchmark harness.

The tools name this package by its path, and SwiftPM names a package by its directory, so they need the repository in
a directory named `corvus-regex-ecma262-swift`.

## 6. Testing

**The ECMA-262 test data.** [`ecma262-regex-test-data`](https://github.com/corvus-dotnet/ecma262-regex-test-data)
holds V8's answers: validity under each grammar, `test` answers, the positions of `exec`, the global search, `y`,
`replace` and `split`, and every `exec` call of test262. `tools/dataset` runs all of it over `[UInt16]` and `String`
on Linux on every change, with none wrong, refused or at a limit, and as the data's own scripts write it for Unicode 13
and 18 and for ECMAScript 2020.

**Other tests.** XCTest over every method and both kinds of text, and the getting-started page's programs, on Linux
(x64 and arm64) and macOS; the package is built for iOS and the iOS simulator.

## 7. Benchmarks

The harness image, `ghcr.io/corvus-dotnet/corvus-regex-ecma262-swift`, runs the Industry workloads of
`dotnet/performance` over this package (UTF-8 and UTF-16), `NSRegularExpression` and V8. The published figures are on
[the benchmark page](https://corvus-oss.org/corvus-regex-ecma262-benchmarks/), which runs every engine's image each
night; this repository publishes none of its own.

Three rows are not like for like with an engine that is not ECMA-262's, as the price of its rules under u: `.*` (`.`
excludes CR, so the CRLF text has more matches), `Sher[a-z]+|Hol[a-z]+` under i (the search must also find the long s
and the Kelvin sign), and `[a-q][^u-z]{13}x` (a supplementary character is two units, so the distance to the `x` is
not fixed).

## 8. Differences a Swift user will meet

- Matching is by code point with `u` or `v` and by UTF-16 code unit without, as JavaScript's, never by grapheme
  cluster.
- `^` and `$` are the start and end of the text unless the `m` flag is set.
- The grammar is ECMA-262's: no regex literals or builders, and no `(?i)` prefix.

The [getting-started page](getting-started.md) has the full list.
