// Runs this package over the ECMA-262 regular expression test data (github.com/corvus-dotnet/ecma262-regex-test-data),
// judged by the data's own rule ("How a runner judges an engine" in its README) exactly as the C library's runner
// judges it:
//
//   swift run -c release dataset <data directory> <wrong-cases file> [--files <glob>]
//
// Each record is asked about under each grammar V8 found it valid in: the record's flags with u added (the unicode
// answers), the record's flags alone (the legacy answers) and, in the file that has them, the flags with v added (the
// unicode_sets answers). A text is matched as [UInt16] (positions in code units, as the data gives them) and as a
// String (positions in UTF-8 bytes); a text with a lone surrogate has no String form and is matched as [UInt16] alone.
// Records marked v8_deviation are left out. Any difference from V8 is a wrong answer; a refusal of a valid pattern, an
// acceptance of an invalid one, and a match that reaches its limit are counted apart and listed too. captures.jsonl is
// judged on exec, the global search, the sticky flag, replace and split. A match is given 2 seconds.
// ill-formed-utf8.jsonl holds bytes that are not UTF-8, each one answer over UTF-8 under each grammar the pattern is
// valid in, whose right answer is a refusal: a String cannot hold such bytes, so they are refused where they would
// become one (checked as the standard library decodes UTF-8, stopping at the first error), before the package.
//
// JSONSerialization refuses a lone surrogate, which the data holds, so each lone surrogate escape is read as a code
// point of a block of 2,048 private use code points (the block's first + its offset from U+D800) and turned back into
// its code unit wherever the text is used. The block is chosen for each line from the blocks of Planes 15 and 16: the
// first whose code points the line does not hold, which is known when the line, read with that block, holds as many
// of them as it had lone surrogate escapes. So no character of the data is taken for a lone surrogate (test262's
// texts hold the ends of the private use ranges). The workers are threads, so each keeps the block of its line.
import CorvusRegexEcma262
import Foundation

let limit = 2.0
let replacement = "<$&|$1|$2|$10|$<a>|$$|$`|$'>"

struct Counts {
    var right = 0, wrong = 0, refused = 0, accepted = 0, limited = 0, errors = 0
    mutating func add(_ o: Counts) {
        right += o.right; wrong += o.wrong; refused += o.refused; accepted += o.accepted; limited += o.limited
        errors += o.errors
    }
}

// An escaped backslash, a surrogate pair's escapes, or a lone surrogate's escape.
let surrogateEscape = try! NSRegularExpression(
    pattern: #"\\\\|\\u(d[89ab][0-9a-f]{2})\\u(d[c-f][0-9a-f]{2})|\\u(d[89a-f][0-9a-f]{2})"#, options: [.caseInsensitive])

// The first code point of each block a line's lone surrogates may be read as.
let blocks: [UInt32] = Array(stride(from: 0xF0000, through: 0xFF000, by: 0x800)) + Array(stride(from: 0x100000, through: 0x10F000, by: 0x800))

// The block of the line this thread is judging.
func block() -> UInt32 { Thread.current.threadDictionary["corvus.loneBlock"] as? UInt32 ?? 0xF0000 }

func isLone(_ v: UInt32) -> Bool { let b = block(); return v >= b && v < b + 0x800 }

// The line with each lone surrogate escape written as the escape of a code point of a block, and how many were.
func rewrite(_ line: String, _ block: UInt32) -> (String, Int) {
    let ns = line as NSString
    var out = ""
    var last = 0
    var written = 0
    for m in surrogateEscape.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
        let lone = m.range(at: 3)
        guard lone.location != NSNotFound else { continue }
        out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
        let v = Int(block) + Int(ns.substring(with: lone), radix: 16)! - 0xD800 - 0x10000
        out += String(format: "\\u%04x\\u%04x", 0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF))
        last = m.range.location + m.range.length
        written += 1
    }
    out += ns.substring(from: last)
    return (out, written)
}

// How many code points of a block the strings of a value hold.
func count(in value: Any, _ block: UInt32) -> Int {
    switch value {
    case let s as String: return s.unicodeScalars.reduce(0) { $0 + ($1.value >= block && $1.value < block + 0x800 ? 1 : 0) }
    case let a as [Any]: return a.reduce(0) { $0 + count(in: $1, block) }
    case let d as [String: Any]: return d.reduce(0) { $0 + count(in: $1.key, block) + count(in: $1.value, block) }
    default: return 0
    }
}

// The record of a line, its lone surrogates read as code points of the first block the line does not use.
func read(_ line: String) -> [String: Any] {
    for b in blocks {
        let (text, written) = rewrite(line, b)
        let r = try! JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as! [String: Any]
        if count(in: r, b) == written {
            Thread.current.threadDictionary["corvus.loneBlock"] = b
            return r
        }
    }
    fatalError("every block of Planes 15 and 16 is used by the line")
}

// The UTF-16 code units of a text as read.
func units(_ s: String) -> [UInt16] {
    let b = block()
    var out: [UInt16] = []
    for c in s.unicodeScalars {
        let v = c.value
        if v >= b && v < b + 0x800 {
            out.append(UInt16(0xD800 + v - b))
        } else {
            out.append(contentsOf: String(c).utf16)
        }
    }
    return out
}

func lone(_ s: String) -> Bool { s.unicodeScalars.contains { isLone($0.value) } }

// UTF-8, a lone surrogate as U+FFFD (as String::from_utf16_lossy writes it).
func utf8Lossy(_ s: String) -> String {
    String(String.UnicodeScalarView(s.unicodeScalars.map { isLone($0.value) ? "\u{FFFD}" : $0 }))
}

func escape(_ s: String) -> String {
    units(s).map { $0 >= 0x20 && $0 < 0x7F && $0 != 0x5C ? String(UnicodeScalar(UInt8($0))) : String(format: "\\u%04x", $0) }
        .joined()
}

func shown(_ pattern: String) -> String { escape(utf8Lossy(pattern)) }

// For each UTF-16 code unit index of a text (and its end), the UTF-8 byte offset; the low half of a pair is its
// character's third byte.
func byteOffsets(_ s: String) -> [Int] {
    var at: [Int] = []
    var b = 0
    for c in s.unicodeScalars {
        if c.value > 0xFFFF {
            at.append(b)
            at.append(b + 2)
        } else {
            at.append(b)
        }
        b += String(c).utf8.count
    }
    at.append(b)
    return at
}

enum Compiled {
    case regex(Regex)
    case refused(String, Bool)  // message, is_error
}

func compile(_ pattern: String, _ flags: String) -> Compiled {
    do {
        return .regex(try Regex(utf8Lossy(pattern), flags: flags))
    } catch let e as RegexError {
        switch e.kind {
        case .invalidPattern: return .refused("PARSE: \(e.message)", false)
        case .patternTooLarge: return .refused("TOO-LARGE: \(e.message)", false)
        default: return .refused("ERROR: \(e.message)", true)
        }
    } catch {
        return .refused("ERROR: \(error)", true)
    }
}

func modes(_ r: [String: Any]) -> [(String, String, Bool)] {
    let valid = r["valid"] as? [String: Any] ?? [:]
    var out = [("u", "unicode", valid["unicode"] as? Bool == true), ("", "legacy", valid["legacy"] as? Bool == true)]
    if valid["unicode_sets"] != nil { out.append(("v", "unicode_sets", valid["unicode_sets"] as? Bool == true)) }
    return out
}

func judgeTests(_ name: String, _ r: [String: Any], _ pattern: String, _ c: inout Counts, _ w: inout [String]) {
    let flags = r["flags"] as? String ?? ""
    let headPattern = shown(pattern)
    for (suffix, answer, valid) in modes(r) {
        let modeFlags = flags + suffix
        let head = "\(name)\t/\(headPattern)/\(modeFlags)"
        let re: Regex
        switch compile(pattern, modeFlags) {
        case .refused(let message, let isError):
            if isError { c.errors += 1 }
            if valid {
                c.refused += 1
                w.append("REFUSED\t\(head)\t\(message.split(whereSeparator: \.isNewline).first.map(String.init) ?? "")")
            }
            continue
        case .regex(let compiled): re = compiled
        }
        if !valid {
            c.accepted += 1
            w.append("ACCEPTED-INVALID\t\(head)")
            continue
        }
        for test in r["tests"] as? [[String: Any]] ?? [] {
            guard let expected = test[answer] as? Bool, let text = test["text"] as? String else { continue }
            for enc in ["utf16", "utf8"] {
                if enc == "utf8" && lone(text) { continue }
                do {
                    let got = enc == "utf16" ? try re.test(utf16: units(text), timeout: limit) : try re.test(text, timeout: limit)
                    if got == expected {
                        c.right += 1
                    } else {
                        c.wrong += 1
                        w.append("WRONG\t\(head)\t\(escape(text))\t\(enc)\texpected \(expected)")
                    }
                } catch let e as RegexError where e.kind == .matchLimit {
                    c.limited += 1
                    w.append("LIMIT\t\(head)\t\(escape(text))\t\(enc)\t\(e.message.contains("memory") ? "memory" : "time")")
                } catch {
                    c.errors += 1
                    w.append("ERROR\t\(head)\t\(escape(text))\t\(enc)\t\(error)")
                }
            }
        }
    }
}

// The String of bytes that are UTF-8, or nil: the standard library's decoder, which stops at the first ill-formed
// sequence (an overlong form, an encoded surrogate, a value beyond U+10FFFF, a sequence cut short or a stray byte).
func utf8String(_ bytes: [UInt8]) -> String? {
    var scalars = String.UnicodeScalarView()
    let failed = transcode(bytes.makeIterator(), from: UTF8.self, to: UTF32.self, stoppingOnError: true) {
        scalars.append(Unicode.Scalar($0)!)
    }
    return failed ? nil : String(scalars)
}

func judgeIllFormed(_ r: [String: Any], _ pattern: String, _ c: inout Counts, _ w: inout [String]) {
    let name = "ill-formed-utf8.jsonl"
    let flags = r["flags"] as? String ?? ""
    let headPattern = shown(pattern)
    for (suffix, _, valid) in modes(r) {
        let modeFlags = flags + suffix
        let head = "\(name)\t/\(headPattern)/\(modeFlags)"
        let re: Regex
        switch compile(pattern, modeFlags) {
        case .refused(let message, let isError):
            if isError { c.errors += 1 }
            if valid {
                c.refused += 1
                w.append("REFUSED\t\(head)\t\(message.split(whereSeparator: \.isNewline).first.map(String.init) ?? "")")
            }
            continue
        case .regex(let compiled): re = compiled
        }
        if !valid {
            c.accepted += 1
            w.append("ACCEPTED-INVALID\t\(head)")
            continue
        }
        for test in r["tests"] as? [[String: Any]] ?? [] {
            guard let hex = test["bytes"] as? String else { continue }
            var bytes: [UInt8] = []
            var i = hex.startIndex
            while i < hex.endIndex {
                let j = hex.index(i, offsetBy: 2)
                bytes.append(UInt8(hex[i..<j], radix: 16)!)
                i = j
            }
            guard let text = utf8String(bytes) else {
                c.right += 1
                continue
            }
            // Not reached with the data, whose bytes are never UTF-8; were they, the package would answer.
            c.wrong += 1
            w.append("WRONG\t\(head)\t\(hex)\tutf8\tread as UTF-8 (\((try? re.test(text, timeout: limit)).map(String.init(describing:)) ?? "error")), not refused")
        }
    }
}

// The expected [start, end] of each group (nil for one that did not take part), mapped by map (identity when nil).
func spansOf(_ expected: Any?) -> [[Int]?]? {
    guard let a = expected as? [Any] else { return nil }
    return a.map { ($0 as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue } }
}

func same(_ expected: [[Int]?]?, _ got: [Range<Int>?]?, _ map: [Int]?) -> Bool {
    guard let expected, let got else { return expected == nil && got == nil }
    guard expected.count == got.count else { return false }
    for (e, g) in zip(expected, got) {
        if let e {
            guard let g else { return false }
            let want = map.map { $0[e[0]]..<$0[e[1]] } ?? e[0]..<e[1]
            if want != g { return false }
        } else if g != nil {
            return false
        }
    }
    return true
}

func judgeAll(_ found: [Range<Int>], _ all: [[[Int]?]?], _ map: [Int]?) -> Bool {
    var n = 0
    for m in found {
        // One match more than the data has: wrong, unless the data kept only the first twenty.
        if n >= all.count { return all.count == 20 }
        guard let a = all[n], let e = a[0] else { return false }
        let want = map.map { $0[e[0]]..<$0[e[1]] } ?? e[0]..<e[1]
        if m != want { return false }
        n += 1
    }
    return !((all.count < 20 && n != all.count) || (all.count == 20 && n < 20))
}

func sameSplit(_ expected: Any?, _ got: [[UInt16]?]) -> Bool {
    guard let e = expected as? [Any], e.count == got.count else { return false }
    for (x, g) in zip(e, got) {
        if let s = x as? String {
            guard let g, g == units(s) else { return false }
        } else if g != nil {
            return false
        }
    }
    return true
}

func judgeMode(_ whereText: String, _ a: [String: Any], _ text: String, _ re: Regex, _ g: Regex, _ y: Regex,
               _ c: inout Counts, _ w: inout [String]) throws {
    func check(_ what: String, _ ok: Bool, _ c: inout Counts, _ w: inout [String]) {
        if ok { c.right += 1 } else {
            c.wrong += 1
            w.append("WRONG\tcaptures.jsonl\t\(whereText)\t\(what)")
        }
    }
    let u16 = units(text)
    let hasLone = lone(text)
    let byteAt = hasLone ? nil : byteOffsets(text)
    let exec = spansOf(a["exec"])
    let m: UTF16Match?
    do {
        m = try re.firstMatch(utf16: u16, timeout: limit)
    } catch let e as RegexError where e.kind == .matchLimit {
        c.limited += 1
        w.append("LIMIT\tcaptures.jsonl\t\(whereText)")
        return
    }
    check("exec", same(exec, m?.ranges, nil), &c, &w)
    if !hasLone { check("exec-utf8", same(exec, try re.firstMatch(in: text)?.utf8Ranges, byteAt), &c, &w) }

    let all = (a["all"] as? [Any] ?? []).map { spansOf($0) }
    let found16 = try g.matches(utf16: u16)
    var ok = true
    var n = 0
    for mm in found16 {
        if n >= all.count { ok = ok && all.count == 20; break }
        if !same(all[n], mm.ranges, nil) { ok = false; break }
        n += 1
    }
    if (all.count < 20 && n != all.count) || (all.count == 20 && n < 20) { ok = false }
    check("all", ok && judgeAll(found16.map(\.range), all, nil), &c, &w)
    if !hasLone { check("all-utf8", judgeAll(try g.matches(in: text).map { $0.utf8Ranges[0]! }, all, byteAt), &c, &w) }

    if !text.isEmpty {
        let sticky = spansOf(a["sticky"])
        check("sticky", same(sticky, try y.firstMatch(utf16: u16, from: 1)?.ranges, nil), &c, &w)
        if let byteAt, !hasLone {
            let utf8 = Array(text.utf8)
            if byteAt[1] >= utf8.count || utf8[byteAt[1]] & 0xC0 != 0x80 {
                let from = text.utf8.index(text.utf8.startIndex, offsetBy: byteAt[1])
                check("sticky-utf8", same(sticky, try y.firstMatch(in: text, from: from)?.utf8Ranges, byteAt), &c, &w)
            }
        }
    }

    let replace = a["replace"] as? String
    let replaceAll = a["replaceAll"] as? String
    let template = Array(replacement.utf16)
    check("replace", replace.map { try! re.replace(utf16: u16, with: template) == units($0) } ?? false, &c, &w)
    check("replaceAll", replaceAll.map { try! g.replace(utf16: u16, with: template) == units($0) } ?? false, &c, &w)
    if !hasLone {
        check("replace-utf8", replace.map { try! re.replace(in: text, with: replacement) == utf8Lossy($0) } ?? false, &c, &w)
        check("replaceAll-utf8", replaceAll.map { try! g.replace(in: text, with: replacement) == utf8Lossy($0) } ?? false, &c, &w)
    }
    check("split", sameSplit(a["split"], try re.split(utf16: u16)), &c, &w)
    check("split3", sameSplit(a["split3"], try re.split(utf16: u16, limit: 3)), &c, &w)
}

func judgeCaptures(_ r: [String: Any], _ pattern: String, _ c: inout Counts, _ w: inout [String]) {
    let flags = r["flags"] as? String ?? ""
    let valid = r["valid"] as? [String: Any] ?? [:]
    let headPattern = shown(pattern)
    var cache: [String: Regex?] = [:]
    func make(_ f: String) -> Regex? {
        if let hit = cache[f] { return hit }
        var re: Regex?
        if case .regex(let compiled) = compile(pattern, f) { re = compiled }
        cache[f] = re
        return re
    }
    for test in r["tests"] as? [[String: Any]] ?? [] {
        if test["v8_deviation"] as? Bool == true { continue }
        guard let text = test["text"] as? String else { continue }
        for mode in ["unicode", "legacy"] {
            guard valid[mode] as? Bool == true, let a = test[mode] as? [String: Any] else { continue }
            let modeFlags = flags + (mode == "unicode" ? "u" : "")
            let whereText = "/\(headPattern)/\(modeFlags)\t\(escape(text))"
            guard let re = make(modeFlags), let g = make(modeFlags + "g"), let y = make(modeFlags + "y") else {
                c.refused += 1
                w.append("REFUSED\tcaptures.jsonl\t\(whereText)")
                continue
            }
            do {
                try judgeMode(whereText, a, text, re, g, y, &c, &w)
            } catch {
                c.errors += 1
                w.append("ERROR\tcaptures.jsonl\t\(whereText)\t\(error)")
            }
        }
    }
}

func judgeLines(_ name: String, _ lines: ArraySlice<Substring>) -> (Counts, [String], Int, Int) {
    var c = Counts()
    var w: [String] = []
    var records = 0, skipped = 0
    for line in lines where !line.isEmpty {
        let r = read(String(line))
        if r["v8_deviation"] as? Bool == true { skipped += 1; continue }
        records += 1
        guard let pattern = r["pattern"] as? String else { continue }
        if name == "captures.jsonl" {
            judgeCaptures(r, pattern, &c, &w)
        } else if name == "ill-formed-utf8.jsonl" {
            judgeIllFormed(r, pattern, &c, &w)
        } else {
            judgeTests(name, r, pattern, &c, &w)
        }
    }
    return (c, w, records, skipped)
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: dataset <data directory> <wrong-cases file> [--files glob]\n".data(using: .utf8)!)
    exit(2)
}
let directory = args[1], wrongPath = args[2]
let filesGlob = args.count >= 5 && args[3] == "--files" ? args[4] : "*.jsonl"
let files = try FileManager.default.contentsOfDirectory(atPath: directory)
    .filter { $0.hasSuffix(".jsonl") && fnmatch(filesGlob, $0, 0) == 0 }.sorted()
var total = Counts()
var wrong: [String] = []
var records = 0, skipped = 0
let start = Date()
for name in files {
    let text = try String(contentsOfFile: "\(directory)/\(name)", encoding: .utf8)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    let workers = 4
    let size = (lines.count + workers - 1) / workers
    var parts = [(Counts, [String], Int, Int)](repeating: (Counts(), [], 0, 0), count: workers)
    let lock = NSLock()
    DispatchQueue.concurrentPerform(iterations: workers) { k in
        let slice = lines[min(k * size, lines.count)..<min((k + 1) * size, lines.count)]
        let result = judgeLines(name, slice)
        lock.lock()
        parts[k] = result
        lock.unlock()
    }
    var fileTotal = Counts()
    for (c, w, rec, skip) in parts {
        fileTotal.add(c)
        wrong.append(contentsOf: w)
        records += rec
        skipped += skip
    }
    print(String(format: "%@ right %10d  wrong %6d  refused-valid %4d  accepted-invalid %4d  limit %4d  %6.1fs",
                 name.padding(toLength: 24, withPad: " ", startingAt: 0), fileTotal.right, fileTotal.wrong, fileTotal.refused,
                 fileTotal.accepted, fileTotal.limited, Date().timeIntervalSince(start)))
    fflush(stdout)
    total.add(fileTotal)
}
try wrong.sorted().map { $0 + "\n" }.joined().write(toFile: wrongPath, atomically: true, encoding: .utf8)
print(String(format: "\nrecords %d (skipped %d deviations)  right %d  wrong %d  refused-valid %d  accepted-invalid %d  limit %d  errors %d  in %.1fs",
             records, skipped, total.right, total.wrong, total.refused, total.accepted, total.limited, total.errors,
             Date().timeIntervalSince(start)))
exit(total.wrong + total.refused + total.accepted + total.errors + total.limited == 0 ? 0 : 1)
