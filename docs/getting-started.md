# Getting started with Swift

## Introduction

`CorvusRegexEcma262` is a Swift package whose patterns answer as ECMAScript does. Where `NSRegularExpression` (ICU) and
Swift's `Regex` have their own grammars and their own meaning for `^`, `$`, `\d`, `\w`, `\s`, `.`, case folding and
Unicode properties, this package has ECMA-262's, so a pattern written for JavaScript, or taken from a JSON Schema,
matches the same texts here as it does there. It is the corvus-regex-ecma262 C library, built from the Rust crate and
held to V8's answers on the ECMA-262 test data.

This guide covers:

- **Setup**: the package, and the C library it needs on Linux.
- **Patterns and flags**: the flags are ECMA-262's letters, and what each one does.
- **The edition and the version of Unicode**: the grammar of ECMAScript 2020, and the Unicode tables a pattern reads.
- **Matching**: `test`, `firstMatch`, `matches`, `matchCount`, `replace` and `split`.
- **Timeouts**: the limit of time and of memory a match may take.
- **UTF-8 and UTF-16**: a `String` matched over its UTF-8 in place, and `[UInt16]` as JavaScript holds a string.
- **Differences from NSRegularExpression and Regex**: what to expect when they meet.

## Setup

Add the package to `Package.swift`:

```
dependencies: [
    .package(url: "https://github.com/corvus-dotnet/corvus-regex-ecma262-swift", from: "0.2.3"),
],
targets: [
    .target(name: "MyApp", dependencies: [.product(name: "CorvusRegexEcma262", package: "corvus-regex-ecma262-swift")]),
]
```

It runs on macOS 10.15 and iOS 13 and later, where SwiftPM downloads the C library as an XCFramework, and on Linux
(x64 and arm64), where the C library is installed first: unpack the archive for the platform from the
[C library's release](https://github.com/corvus-dotnet/corvus-regex-ecma262-rs/releases), and make its pkg-config file
and its shared library visible with `PKG_CONFIG_PATH=<unpacked>/lib/pkgconfig` and `LD_LIBRARY_PATH=<unpacked>/lib`.

```swift
import CorvusRegexEcma262
```

## Patterns and flags

A pattern is written as it would be in JavaScript, and the flags are the letters `RegExp` takes, as a string:

| Flag | Meaning |
|---|---|
| `d` | Accepted for completeness; indices are always kept. |
| `g` | `replace` replaces every match; without it, the first, as `String.prototype.replace` does. |
| `i` | Canonicalize of the mode in force: simple case folding with `u` or `v`, `toUpperCase` without. Never the locale. |
| `m` | `^` and `$` at line terminators. |
| `s` | The dot matches line terminators. |
| `u` | The `u` flag grammar; matched by code point. |
| `v` | Set notation and properties of strings; matched by code point. `u` and `v` together is an error, as in ECMA-262. |
| `y` | A match only at the start position. |

```swift
import CorvusRegexEcma262

let a = try Regex(#"\p{Script=Greek}+"#, flags: "u")
let b = try Regex(#"[[a-z]--[aeiou]]+"#, flags: "v")
let c = try Regex(#"^(?<year>\d{4})-(?<month>\d{2})$"#, flags: "u")

let greek = try a.test("αβγ")
let noVowels = try b.test("rhythm")
precondition(greek && noVowels)
precondition(c.groupNames == ["year", "month"])
```

With no flag the pattern is read with the Annex B grammar and matched by UTF-16 code unit, which is what ECMA-262 does
with no flag. JSON Schema's reading, the `u` flag first and Annex B when that refuses, is two compiles, each with the
match timeout, so no default timeout is needed; `try?` is the form that gives `nil` in place of an error:

```swift
import CorvusRegexEcma262

func schemaPattern(_ pattern: String) throws -> Regex {
    if let unicode = try? Regex(pattern, flags: "u", timeout: 1) {
        return unicode
    }
    return try Regex(pattern, timeout: 1)
}

let unicode = try schemaPattern(#"^\p{L}+$"#)
let annexB = try schemaPattern(#"\-"#)  // an identity escape, which only Annex B allows
precondition(unicode.flags == "u" && annexB.flags == "")
```

A pattern that is not valid throws a `RegexError` whose `kind` is `.invalidPattern` and whose `message` says why;
invalid flags are `.invalidFlags`. Every pattern has deterministic limits of size, and `.patternTooLarge` says when one
is passed.

```swift
import CorvusRegexEcma262

do {
    _ = try Regex("a{2,1}", flags: "u")
    preconditionFailure("a pattern that is not valid was compiled")
} catch let e as RegexError {
    precondition(e.kind == .invalidPattern && !e.message.isEmpty)
}
precondition(!Regex.isValid("a", flags: "uv"))
```

## The edition and the version of Unicode

JSON Schema 2020-12 names the grammar of ECMAScript 2020. `edition: .es2020` refuses what later editions added, and
nothing else: the `d` and `v` flags, modifier groups such as `(?i:...)`, a group name used by two groups, and a
property name or value that is not in the 2020 tables (such as `\p{Script=Yezidi}`). A pattern it accepts has the same
answers as in today's grammar.

The version of Unicode is chosen apart from the edition: `unicodeVersion:` is `.v13`, `.v17`, `.v18`, `.latest` (18
today) or `.default`, the version of the V8 the answers are held to (17 today). It decides the members of each
`\p{...}`, the characters of a group name and the case folding of the `i` flag. A `Regex`'s `unicodeVersion` reports
the version it was compiled with. Both are read when the pattern is compiled, so a match costs the same whichever is
chosen.

```swift
import CorvusRegexEcma262

// ECMAScript 2020 as its edition was published, with the Unicode of its year.
let greek = try Regex(#"^\p{Script=Greek}+$"#, flags: "u", timeout: 1, edition: .es2020, unicodeVersion: .v13)
let matched = try greek.test("αβγ")
precondition(matched && greek.unicodeVersion == 13)

// Vithkuqi is in Unicode 14 and later, so not in Unicode 13.
precondition(!Regex.isValid(#"\p{Script=Vithkuqi}"#, flags: "u", unicodeVersion: .v13))
```

## Matching

The methods are those of a `RegExp`, with the position as `from:` where JavaScript keeps `lastIndex`. A `Match` holds
its groups by number and by name, as `Substring`s of the text and as ranges:

```swift
import CorvusRegexEcma262

let date = try Regex(#"(?<year>\d{4})-(?<month>\d{2})"#, flags: "gu")
let text = "due 2026-10, then 2027-01"

let found = try date.test(text)
precondition(found)
let m = try date.firstMatch(in: text)!
precondition(m.value == "2026-10" && m.utf8Ranges[0] == 4..<11)
precondition(m["year"] == "2026" && m[2] == "10")

// Every match of a global search, as matchAll makes it.
let all = try date.matches(in: text).map(\.value)
let count = try date.matchCount(in: text)
precondition(all == ["2026-10", "2027-01"] && count == 2)

// replace replaces every match with the g flag, and the first without it, with every $ form of ECMA-262, or a closure.
let templated = try date.replace(in: text, with: "$<month>/$1")
let computed = try date.replace(in: text) { String($0["year"]!) }
precondition(templated == "due 10/2026, then 01/2027" && computed == "due 2026, then 2027")

// split puts what the groups captured between the pieces; a group that did not take part is nil.
let pieces = try Regex(#"\s*(;)\s*"#).split("a ; b;c")
precondition(pieces == ["a", ";", "b", ";", "c"])
```

`firstMatch(in:from:)` is `exec` with `lastIndex` set, and `y` anchors it there. `test` and `matchCount` make no
`Match`. A `Regex` is immutable and `Sendable`, and may be used from any number of threads.

## Timeouts

A match has no limit by default. A `Regex` made with a `timeout:` (in seconds) abandons a match that reaches it, or
that reaches the cap on backtracking memory the timeout brings, with a `RegexError` whose `kind` is `.matchLimit`,
whatever the pattern:

```swift
import CorvusRegexEcma262

let slow = try Regex(#"^(?:(a+)\1*)+$"#, timeout: 0.1)
precondition(slow.timeout == 0.1)
do {
    _ = try slow.test(String(repeating: "a", count: 60) + "b")
    preconditionFailure("the match did not stop at its timeout")
} catch let e as RegexError {
    precondition(e.kind == .matchLimit)
}
```

A `Regex` made without a timeout takes `Regex.defaultTimeout`, which is `nil` (no limit) unless set. A program that
matches patterns or texts from outside should set one, for example with `Regex.defaultTimeout = 1` when it starts.
`test` and `firstMatch` take a `timeout:` of their own for one match.

A pattern without a backreference is matched in time linear in the text, and no pattern can overflow the stack, so the
timeout is what bounds the others.

## UTF-8 and UTF-16

A `String` is matched over its UTF-8 in place, with no transcoding: a `Match`'s `range` is a `Range<String.Index>`, and
its `utf8Ranges` are byte offsets. A `String` is always valid Unicode, so there is nothing to refuse; bytes become a
`String` through Foundation's `String(bytes:encoding:)`, which gives `nil` for bytes that are not UTF-8, where
`String(decoding:as:)` would read them as U+FFFD. Each method has a `utf16:` form over `[UInt16]`, lone surrogates and
all, whose match is a `UTF16Match` with positions in code units.

```swift
import CorvusRegexEcma262
import Foundation

let dotB = try Regex(".b", flags: "u")
let m8 = try dotB.firstMatch(in: "a😀b")!
let m16 = try dotB.firstMatch(utf16: Array("a😀b".utf16))!
precondition(m8.utf8Ranges[0] == 1..<6)  // bytes of UTF-8
precondition(m16.range == 1..<4)         // UTF-16 code units

precondition(String(bytes: [0xFF] as [UInt8], encoding: .utf8) == nil)
```

Under the `u` and `v` flags a character is a code point in both encodings, so a class, a dot or a quantifier takes a
four-byte sequence as one character. With no flag ECMA-262 matches by UTF-16 code unit, so a match can take half of a
character beyond the Basic Multilingual Plane: over a `String` its `range` is the whole character's (a `String.Index`
cannot fall inside one) and its UTF-8 range ends at the character's third byte; over `[UInt16]` it is the lone half,
as in JavaScript.

## Differences from NSRegularExpression and Regex

The methods follow `RegExp`; the meaning follows ECMA-262. The differences a user coming from `NSRegularExpression` or
Swift's `Regex` will meet:

- **The grammar.** No `(?i)` inline option (ECMA-262 has `(?i:...)` groups), no atomic groups, no possessive
  quantifiers, no `\A` or `\z`, no conditionals, and no regex literals or builders. The flags are a separate string.
- **Anchors and the dot.** `^` and `$` are the start and end of the text unless the `m` flag is set, and `.` excludes
  LF, CR, U+2028 and U+2029 unless the `s` flag is set.
- **The character classes.** `\d` is `[0-9]` and `\w` the 63 ASCII word characters, where both make them Unicode; `\s`
  is ECMAScript's white space and line terminators.
- **Characters.** Swift's `Regex` matches by grapheme cluster; this matches by code point with `u` or `v`, and by
  UTF-16 code unit without, as JavaScript does.
- **Replacement.** A template writes a group as `$1` or `$<name>`, and `$&`, `` $` `` and `$'` are the match and the
  text before and after it; `replace` replaces every match only with the `g` flag, and `replaceAll` always does.
- **Split.** `split` is JavaScript's, which puts what the groups captured between the pieces.
- **Timeouts.** Neither has a limit on a match's time. Here a pattern without a backreference is matched in time linear
  in the text, and a timeout bounds the others.
