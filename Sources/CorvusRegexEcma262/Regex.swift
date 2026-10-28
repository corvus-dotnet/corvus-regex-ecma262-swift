// ECMA-262 (JavaScript) regular expressions for Swift, with the grammar and the answers of RegExp, over the
// corvus-regex-ecma262 C library (the Clang module CCorvusRegexEcma262).
//
// A `String` is matched as its UTF-8, with ranges as `String.Index` (and in UTF-8 bytes beside them); `[UInt16]` text
// is matched as UTF-16, lone surrogates and all, with ranges in code units (as JavaScript, NSString and NSRange count
// them). Without the u or v flag a pattern is matched by UTF-16 code unit, so a match can take half of a character
// beyond the Basic Multilingual Plane: over a String its text holds that half as U+FFFD and its range is the whole
// character's (its UTF-8 range ends or starts at the character's third byte); over [UInt16] it is the lone half.
//
// A String is always UTF-8, so its text goes to the C library's _unchecked functions, which do not read the whole text
// once more on each call to check it.
import CCorvusRegexEcma262

/// Why a call failed.
public struct RegexError: Error, CustomStringConvertible, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// The pattern is not valid in the grammar of its flags (new RegExp would throw a SyntaxError).
        case invalidPattern
        /// A letter that is not one of dgimsuvy, a flag given twice, or u with v.
        case invalidFlags
        /// The pattern is over a limit of size.
        case patternTooLarge
        /// A match reached its limit of time, or of backtracking memory, so it has no answer.
        case matchLimit
        /// A value out of range, such as an offset beyond the text or inside a character.
        case invalidArgument
        /// A bug in the library: it was caught, and the library remains usable.
        case internalError
    }

    public let kind: Kind
    public let message: String

    public var description: String { message }

    static func last(_ status: cre_status) -> RegexError {
        let m = cre_last_error_message()
        let message = m.ptr.map { String(decoding: UnsafeRawBufferPointer(start: $0, count: m.len), as: UTF8.self) } ?? ""
        let kind: Kind
        switch status {
        case cre_status(CRE_INVALID_PATTERN): kind = .invalidPattern
        case cre_status(CRE_INVALID_FLAGS): kind = .invalidFlags
        case cre_status(CRE_PATTERN_TOO_LARGE): kind = .patternTooLarge
        case cre_status(CRE_MATCH_LIMIT): kind = .matchLimit
        case cre_status(CRE_PANIC): kind = .internalError
        default: kind = .invalidArgument
        }
        return RegexError(kind: kind, message: message)
    }
}

@inline(__always)
func check(_ status: cre_status) throws {
    if status != cre_status(CRE_OK) { throw RegexError.last(status) }
}

func chars(_ bytes: UnsafeBufferPointer<UInt8>) -> UnsafePointer<CChar>? {
    UnsafeRawPointer(bytes.baseAddress)?.assumingMemoryBound(to: CChar.self)
}

func string(_ s: cre_str) -> String {
    s.ptr.map { String(decoding: UnsafeRawBufferPointer(start: $0, count: s.len), as: UTF8.self) } ?? ""
}

/// The milliseconds of a limit of time in seconds (at least 1; nil for none, which the C library writes as 0).
func millis(_ timeout: Double?) -> UInt64 {
    guard let timeout else { return 0 }
    let ms = timeout * 1000
    return ms <= 1 ? 1 : UInt64(ms)
}

/// The milliseconds of a timeout in seconds (0, or less, for none; otherwise at least 1).
func timeoutMillis(_ timeout: Double) -> UInt64 {
    if !(timeout > 0) { return 0 }
    let ms = timeout * 1000
    return ms <= 1 ? 1 : (ms >= Double(UInt64.max) ? UInt64.max : UInt64(ms))
}

/// The seconds of a timeout in milliseconds, nil for none.
func seconds(_ millis: UInt64) -> Double? {
    millis == 0 ? nil : Double(millis) / 1000
}

let unset = Int(bitPattern: UInt(CRE_UNSET))

/// The edition of ECMA-262 whose grammar a pattern is read with: today's, the default, or ECMAScript 2020's, which JSON
/// Schema 2020-12 names. The 2020 grammar refuses what later editions added: the d and v flags, modifier groups, a
/// name given to more than one group, and property names that are not in its edition's tables.
public enum Edition: Sendable, Equatable {
    case current
    case es2020

    var code: UInt32 { self == .es2020 ? UInt32(CRE_EDITION_ES2020) : UInt32(CRE_EDITION_CURRENT) }
}

/// The version of Unicode whose tables a pattern is read with (its properties and its case folding), independent of
/// the edition: the default, which is the version of the V8 the answers are held to (17 today), 13, 17, 18, or the
/// latest this package supports (18 today).
public enum UnicodeVersion: Sendable, Equatable {
    case `default`
    case v13
    case v17
    case v18
    case latest

    var code: UInt32 {
        switch self {
        case .default: return UInt32(CRE_UNICODE_DEFAULT)
        case .v13: return UInt32(CRE_UNICODE_13)
        case .v17: return UInt32(CRE_UNICODE_17)
        case .v18: return UInt32(CRE_UNICODE_18)
        case .latest: return UInt32(CRE_UNICODE_LATEST)
        }
    }
}

/// A compiled ECMA-262 regular expression, as `new RegExp(pattern, flags)` compiles it. It is immutable: any number of
/// threads may use one at once.
public final class Regex: @unchecked Sendable {
    let handle: OpaquePointer
    /// The distinct names of the groups, in the order of the first group of each name.
    public let groupNames: [String]
    let global: Bool

    /// Compiles a pattern with the flags `new RegExp(pattern, flags)` takes, any of dgimsuvy. Throws a RegexError:
    /// invalidPattern, invalidFlags or patternTooLarge. `timeout` is the time in seconds each match may take before it
    /// is abandoned with a RegexError of kind matchLimit (0 for none); nil takes `Regex.defaultTimeout`, which is none
    /// unless set. A timeout also caps the backtracking memory of a match; without one a match has no limit of time or
    /// of memory, so give a pattern or a text from outside one. `edition` is the grammar the pattern is read with, and
    /// `unicodeVersion` the version of Unicode whose tables it is read with; under `.es2020` the d and v flags are
    /// invalidFlags. `try?` makes it a constructor that gives nil for a pattern that is not valid, with its timeout.
    public init(_ pattern: String, flags: String = "", timeout: Double? = nil, edition: Edition = .current,
                unicodeVersion: UnicodeVersion = .default) throws {
        var regex: OpaquePointer?
        var pattern = pattern
        var flags = flags
        let ms = timeout.map(timeoutMillis) ?? cre_default_match_timeout()
        try pattern.withUTF8 { p in
            try flags.withUTF8 { f in
                try check(cre_regex_new_with_options(chars(p), p.count, chars(f), f.count, ms, edition.code,
                                                     unicodeVersion.code, &regex))
            }
        }
        let h = regex!
        handle = h
        groupNames = (0..<cre_regex_group_name_count(h)).map { string(cre_regex_group_name(h, $0)) }
        global = string(cre_regex_flags(h)).contains("g")
    }

    deinit { cre_regex_free(handle) }

    /// Whether a pattern is valid with the flags, in the grammar of the edition and under the version of Unicode,
    /// without compiling it.
    public static func isValid(_ pattern: String, flags: String = "", edition: Edition = .current,
                               unicodeVersion: UnicodeVersion = .default) -> Bool {
        var valid = false
        var pattern = pattern
        var flags = flags
        let status = pattern.withUTF8 { p in
            flags.withUTF8 { f in
                cre_regex_is_valid_with_options(chars(p), p.count, chars(f), f.count, edition.code, unicodeVersion.code, &valid)
            }
        }
        return status == cre_status(CRE_OK) && valid
    }

    /// The versions of Unicode a pattern can be read with.
    public static let unicodeVersions = [13, 17, 18]

    /// The version of Unicode `.default` stands for: the version of the V8 the answers are held to.
    public static let defaultUnicodeVersion = 17

    /// The version of Unicode `.latest` stands for: the latest this package supports.
    public static let latestUnicodeVersion = 18

    /// The pattern as it was given.
    public var source: String { string(cre_regex_source(handle)) }

    /// The flags as RegExp.prototype.flags writes them, in the order dgimsuvy.
    public var flags: String { string(cre_regex_flags(handle)) }

    /// The number of capturing groups.
    public var groupCount: Int { cre_regex_group_count(handle) }

    /// The edition whose grammar the pattern was read with.
    public var edition: Edition { cre_regex_edition(handle) == UInt32(CRE_EDITION_ES2020) ? .es2020 : .current }

    /// The version of Unicode whose tables the pattern was read with, resolved: 13, 17 or 18.
    public var unicodeVersion: Int { Int(cre_regex_unicode_version(handle)) }

    /// The time in seconds each match may take before it is abandoned with a RegexError of kind matchLimit, or nil for
    /// no limit.
    public var timeout: Double? { seconds(cre_regex_match_timeout(handle)) }

    /// The timeout in seconds of every Regex made from now on without one of its own, or nil (or 0) for no limit, the
    /// default. It is the process-wide default of .NET's REGEX_DEFAULT_MATCH_TIMEOUT; a program that matches patterns
    /// or texts from outside should set it when it starts. A Regex already made keeps its own.
    public static var defaultTimeout: Double? {
        get { seconds(cre_default_match_timeout()) }
        set { cre_set_default_match_timeout(newValue.map(timeoutMillis) ?? 0) }
    }

    func newCaptures() throws -> OpaquePointer {
        var c: OpaquePointer?
        try check(cre_captures_new(handle, &c))
        return c!
    }

    // ---------------------------------------------------------------------------------------------------------------
    // String

    /// Whether the pattern matches at or after `start` (at `start` alone with the y flag), as RegExp.prototype.test
    /// with lastIndex there. A match that reaches the pattern's timeout throws a RegexError of kind matchLimit; a timeout
    /// in seconds here takes its place for this match.
    public func test(_ text: String, from start: String.Index? = nil, timeout: Double? = nil) throws -> Bool {
        let offset = start.map { text.utf8.distance(from: text.utf8.startIndex, to: $0) } ?? 0
        return try firstMatchUTF8(text, offset: offset, timeout: timeout) != nil
    }

    /// The first match at or after `start`, as exec finds it with lastIndex there, or nil. A match that reaches the
    /// pattern's timeout throws a RegexError of kind matchLimit; a timeout in seconds here takes its place.
    public func firstMatch(in text: String, from start: String.Index? = nil, timeout: Double? = nil) throws -> Match? {
        let offset = start.map { text.utf8.distance(from: text.utf8.startIndex, to: $0) } ?? 0
        return try firstMatchUTF8(text, offset: offset, timeout: timeout)
    }

    func firstMatchUTF8(_ original: String, offset: Int, timeout: Double?) throws -> Match? {
        var text = original
        let captures = try newCaptures()
        defer { cre_captures_free(captures) }
        var found = false
        try text.withUTF8 { t in
            guard offset <= t.count else { return }
            try check(timeout == nil
                ? cre_regex_captures_unchecked(handle, chars(t), t.count, offset, captures, &found)
                : cre_regex_captures_limit_unchecked(handle, chars(t), t.count, offset, millis(timeout), captures, &found))
        }
        return found ? Match(text: original, captures: captures, names: groupNames) : nil
    }

    /// Every match of a global search, as matchAll makes one. After an empty match the search goes on one character
    /// later, and with the y flag each match must start where the one before ended.
    public func matches(in original: String) throws -> [Match] {
        var text = original
        let captures = try newCaptures()
        defer { cre_captures_free(captures) }
        var out: [Match] = []
        try text.withUTF8 { t in
            var it: OpaquePointer?
            try check(cre_regex_captures_iter_unchecked(handle, chars(t), t.count, &it))
            defer { cre_matches_free(it) }
            var found = false
            while true {
                try check(cre_matches_next_captures(it, captures, &found))
                if !found { break }
                out.append(Match(text: original, captures: captures, names: groupNames))
            }
        }
        return out
    }

    /// The number of matches of a global search, without making them.
    public func matchCount(in text: String) throws -> Int {
        var text = text
        return try text.withUTF8 { t in
            var it: OpaquePointer?
            try check(cre_regex_find_iter_unchecked(handle, chars(t), t.count, &it))
            defer { cre_matches_free(it) }
            return try count(it)
        }
    }

    func count(_ it: OpaquePointer?) throws -> Int {
        var n = 0
        var got = 0
        return try withUnsafeTemporaryAllocation(of: cre_match.self, capacity: 256) { batch in
            repeat {
                try check(cre_matches_next_batch(it, batch.baseAddress, 256, &got))
                n += got
            } while got == 256
            return n
        }
    }

    /// The text with the first match replaced, or every match with the g flag, as String.prototype.replace replaces
    /// them. The template's $& is the match, $` the text before it, $' the text after it, $1 to $99 a group, $<name> a
    /// named group, and $$ a dollar sign.
    public func replace(in text: String, with template: String) throws -> String {
        try replaceUTF8(text, template, all: global)
    }

    /// The text with every match replaced, whether or not the g flag is set (String.prototype.replaceAll).
    public func replaceAll(in text: String, with template: String) throws -> String {
        try replaceUTF8(text, template, all: true)
    }

    func replaceUTF8(_ text: String, _ template: String, all: Bool) throws -> String {
        var text = text
        var template = template
        var out = cre_string(ptr: nil, len: 0)
        try text.withUTF8 { t in
            try template.withUTF8 { r in
                try check(all
                    ? cre_regex_replace_all_unchecked(handle, chars(t), t.count, chars(r), r.count, &out)
                    : cre_regex_replace_unchecked(handle, chars(t), t.count, chars(r), r.count, &out))
            }
        }
        defer { cre_string_free(&out) }
        return String(decoding: UnsafeRawBufferPointer(start: out.ptr, count: out.len), as: UTF8.self)
    }

    /// The text with the first match replaced, or every match with the g flag, by what `transform` returns for it.
    public func replace(in text: String, _ transform: (Match) throws -> String) throws -> String {
        try replace(text, all: global, transform)
    }

    /// The text with every match replaced by what `transform` returns for it.
    public func replaceAll(in text: String, _ transform: (Match) throws -> String) throws -> String {
        try replace(text, all: true, transform)
    }

    func replace(_ text: String, all: Bool, _ transform: (Match) throws -> String) throws -> String {
        let found = all ? try matches(in: text) : try firstMatch(in: text).map { [$0] } ?? []
        var out = ""
        var last = text.startIndex
        for m in found {
            out += text[last..<m.range.lowerBound]
            out += try transform(m)
            last = m.range.upperBound
        }
        out += text[last...]
        return out
    }

    /// The text split around the matches, as String.prototype.split(separator, limit) splits it: what each group
    /// captured is spliced in after the piece before it (nil for a group that did not take part), an empty match at
    /// the start or the end splits nothing, and there are at most `limit` pieces.
    public func split(_ text: String, limit: Int? = nil) throws -> [String?] {
        var text = text
        var pieces = cre_pieces(items: nil, len: 0, internal: nil)
        try text.withUTF8 { t in
            try check(cre_regex_split_unchecked(handle, chars(t), t.count, limit.map { UInt32(clamping: $0) } ?? CRE_SPLIT_ALL, &pieces))
        }
        defer { cre_pieces_free(&pieces) }
        return (0..<pieces.len).map { k in
            let p = pieces.items[k]
            return p.ptr.map { String(decoding: UnsafeRawBufferPointer(start: $0, count: p.len), as: UTF8.self) }
        }
    }

    // ---------------------------------------------------------------------------------------------------------------
    // [UInt16]

    /// test over UTF-16 text, `start` in code units.
    public func test(utf16 text: [UInt16], from start: Int = 0, timeout: Double? = nil) throws -> Bool {
        try firstMatch(utf16: text, from: start, timeout: timeout) != nil
    }

    /// The first match over UTF-16 text at or after `start` (in code units), or nil.
    public func firstMatch(utf16 text: [UInt16], from start: Int = 0, timeout: Double? = nil) throws -> UTF16Match? {
        guard start <= text.count else { return nil }
        let captures = try newCaptures()
        defer { cre_captures_free(captures) }
        var found = false
        try text.withUnsafeBufferPointer { t in
            try check(timeout == nil
                ? cre_regex_captures_utf16(handle, t.baseAddress, t.count, start, captures, &found)
                : cre_regex_captures_limit_utf16(handle, t.baseAddress, t.count, start, millis(timeout), captures, &found))
        }
        return found ? UTF16Match(text: text, captures: captures, names: groupNames) : nil
    }

    /// Every match of a global search over UTF-16 text.
    public func matches(utf16 text: [UInt16]) throws -> [UTF16Match] {
        let captures = try newCaptures()
        defer { cre_captures_free(captures) }
        var out: [UTF16Match] = []
        try text.withUnsafeBufferPointer { t in
            var it: OpaquePointer?
            try check(cre_regex_captures_iter_utf16(handle, t.baseAddress, t.count, &it))
            defer { cre_matches_free(it) }
            var found = false
            while true {
                try check(cre_matches_next_captures(it, captures, &found))
                if !found { break }
                out.append(UTF16Match(text: text, captures: captures, names: groupNames))
            }
        }
        return out
    }

    /// The number of matches of a global search over UTF-16 text, without making them.
    public func matchCount(utf16 text: [UInt16]) throws -> Int {
        try text.withUnsafeBufferPointer { t in
            var it: OpaquePointer?
            try check(cre_regex_find_iter_utf16(handle, t.baseAddress, t.count, &it))
            defer { cre_matches_free(it) }
            return try count(it)
        }
    }

    /// replace over UTF-16 text.
    public func replace(utf16 text: [UInt16], with template: [UInt16]) throws -> [UInt16] {
        try replaceUTF16(text, template, all: global)
    }

    /// replaceAll over UTF-16 text.
    public func replaceAll(utf16 text: [UInt16], with template: [UInt16]) throws -> [UInt16] {
        try replaceUTF16(text, template, all: true)
    }

    func replaceUTF16(_ text: [UInt16], _ template: [UInt16], all: Bool) throws -> [UInt16] {
        var out = cre_string16(ptr: nil, len: 0)
        try text.withUnsafeBufferPointer { t in
            try template.withUnsafeBufferPointer { r in
                try check(all
                    ? cre_regex_replace_all_utf16(handle, t.baseAddress, t.count, r.baseAddress, r.count, &out)
                    : cre_regex_replace_utf16(handle, t.baseAddress, t.count, r.baseAddress, r.count, &out))
            }
        }
        defer { cre_string16_free(&out) }
        return Array(UnsafeBufferPointer(start: out.ptr, count: out.len))
    }

    /// split over UTF-16 text.
    public func split(utf16 text: [UInt16], limit: Int? = nil) throws -> [[UInt16]?] {
        var pieces = cre_pieces16(items: nil, len: 0, internal: nil)
        try text.withUnsafeBufferPointer { t in
            try check(cre_regex_split_utf16(handle, t.baseAddress, t.count, limit.map { UInt32(clamping: $0) } ?? CRE_SPLIT_ALL, &pieces))
        }
        defer { cre_pieces16_free(&pieces) }
        return (0..<pieces.len).map { k in
            let p = pieces.items[k]
            return p.ptr.map { Array(UnsafeBufferPointer(start: $0, count: p.len)) }
        }
    }
}

/// The groups of the last match a captures handle read: each group's range (nil for one that did not take part), and
/// the group each name stands for in this match.
func groupsOf(_ captures: OpaquePointer, names: [String]) -> (groups: [Range<Int>?], named: [Int?]) {
    let n = cre_captures_len(captures)
    var groups: [Range<Int>?] = []
    groups.reserveCapacity(n)
    for k in 0..<n {
        var m = cre_match(start: 0, end: 0)
        groups.append(cre_captures_get(captures, k, &m) ? Int(m.start)..<Int(m.end) : nil)
    }
    let named: [Int?] = names.map { name in
        var name = name
        var m = cre_match(start: 0, end: 0)
        let took = name.withUTF8 { cre_captures_name(captures, chars($0), $0.count, &m) }
        return took ? groups.firstIndex(of: Int(m.start)..<Int(m.end)) : nil
    }
    return (groups, named)
}

/// A match over a String: each group by number or name, as a range of the text and as its text.
public struct Match: Sendable {
    /// The text the match was found in.
    public let text: String
    /// Each group's range in UTF-8 bytes (the whole match first), nil for one that did not take part.
    public let utf8Ranges: [Range<Int>?]
    let names: [String]
    let named: [Int?]

    init(text: String, captures: OpaquePointer, names: [String]) {
        self.text = text
        let g = groupsOf(captures, names: names)
        utf8Ranges = g.groups
        self.names = names
        named = g.named
    }

    /// The number of groups, the whole match among them.
    public var count: Int { utf8Ranges.count }

    /// The whole match's range.
    public var range: Range<String.Index> { range(0)! }

    /// The whole match's text.
    public var value: Substring { text[range] }

    /// Group `group`'s range, nil when it did not take part. A range that starts or ends between the halves of a
    /// character (without u or v) is the whole character's.
    public func range(_ group: Int) -> Range<String.Index>? {
        guard group >= 0, group < utf8Ranges.count, let r = utf8Ranges[group] else { return nil }
        return index(r.lowerBound, end: false)..<index(r.upperBound, end: true)
    }

    /// The range of the group of the name, nil when no group of that name took part.
    public func range(_ name: String) -> Range<String.Index>? {
        guard let k = names.firstIndex(of: name), let g = named[k] else { return nil }
        return range(g)
    }

    /// Group `group`'s text, nil when it did not take part.
    public subscript(_ group: Int) -> Substring? { range(group).map { text[$0] } }

    /// The text of the group of the name, nil when no group of that name took part.
    public subscript(_ name: String) -> Substring? { range(name).map { text[$0] } }

    func index(_ offset: Int, end: Bool) -> String.Index {
        let utf8 = text.utf8
        var i = utf8.index(utf8.startIndex, offsetBy: offset)
        guard i < utf8.endIndex, utf8[i] & 0xC0 == 0x80 else { return i }
        // Inside a character (between the halves of one beyond the Basic Multilingual Plane): its start, or past it.
        while i > utf8.startIndex, utf8[i] & 0xC0 == 0x80 { i = utf8.index(before: i) }
        return end ? text.unicodeScalars.index(after: i) : i
    }
}

/// A match over UTF-16 text: each group by number or name, as a range of code units and as its units.
public struct UTF16Match: Sendable {
    /// The text the match was found in.
    public let text: [UInt16]
    /// Each group's range in code units (the whole match first), nil for one that did not take part.
    public let ranges: [Range<Int>?]
    let names: [String]
    let named: [Int?]

    init(text: [UInt16], captures: OpaquePointer, names: [String]) {
        self.text = text
        let g = groupsOf(captures, names: names)
        ranges = g.groups
        self.names = names
        named = g.named
    }

    /// The number of groups, the whole match among them.
    public var count: Int { ranges.count }

    /// The whole match's range.
    public var range: Range<Int> { ranges[0]! }

    /// Group `group`'s range, nil when it did not take part.
    public func range(_ group: Int) -> Range<Int>? {
        guard group >= 0, group < ranges.count else { return nil }
        return ranges[group]
    }

    /// The range of the group of the name, nil when no group of that name took part.
    public func range(_ name: String) -> Range<Int>? {
        guard let k = names.firstIndex(of: name), let g = named[k] else { return nil }
        return ranges[g]
    }

    /// Group `group`'s units, nil when it did not take part.
    public subscript(_ group: Int) -> ArraySlice<UInt16>? { range(group).map { text[$0] } }

    /// The units of the group of the name, nil when no group of that name took part.
    public subscript(_ name: String) -> ArraySlice<UInt16>? { range(name).map { text[$0] } }
}

/// The version of the C library this program runs with, as "major.minor.patch".
public var libraryVersion: String { string(cre_version()) }
