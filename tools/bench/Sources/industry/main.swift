// The Industry benchmark from Swift: each workload counted by each engine, in nanoseconds per count, under the
// interleaved protocol every harness of the central benchmark page follows (docs/benchmarks/README.md in
// corvus-regex-ecma262-rs), a port of the C harness's driver (tools/c/industry.c there):
//
//   industry <workloads.json> [--engines corvus-utf8,corvus-utf16,foundation,swift,v8] [--v8 <industry.mjs>]
//            [--rounds 3] [--seconds 0.7] [--passes 7] [--spread 0.05] [--filter <substring of the id>] [--out <json>]
//
// The workloads are the outer loop, each workload's rounds next and the engines innermost, their order turned by one
// each round, so that a workload's rounds are seconds apart, as its engines are. Each figure is a child process of its
// own (`industry --one`, or `node industry.mjs --one` for V8), which warms for two fifths of its seconds, then times
// `passes` passes of as many counts as fit the rest and reports their median. A workload's figure for an engine is the
// median of its rounds, with the fastest and the slowest round as its spread; a figure whose spread, (slowest -
// fastest) / median, is over --spread is listed in the run's facts (spread_over) and on stderr. A figure that does not
// finish in 30 s is stopped and recorded as giving no result within 30 s, and is not run in the workload's later
// rounds.
//
// The engines, each counting the matches of a global search as a Swift program counts them:
// - corvus-utf8 and corvus-utf16: this package with the workload's flags and u, over the text as a String and as
//   [UInt16], with Regex.matchCount;
// - foundation: Foundation's NSRegularExpression (ICU), which does not claim ECMA-262, given the pattern as it is with
//   the flags i, m and s, with numberOfMatches;
// - swift: the standard library's Regex, which does not claim ECMA-262, given the pattern as it is with the flags i, m
//   and s, counting matches(of:);
// - v8: Node's RegExp (--v8), with gu added.
//
// The texts are those of the reference run, in CORVUS_REGEX_TEXTS (or ~/.local/share/corvus-regex-benchmarks); the
// run unzips each once into a directory of its own (CORVUS_REGEX_PLAIN), which the children read. POSIX only: the
// benchmark runs on Linux, in the image.
import CorvusRegexEcma262
import Foundation

let notECMA262: Set<String> = ["foundation", "swift"]
let labels = ["corvus-utf8": "corvus-regex-ecma262 UTF-8", "corvus-utf16": "corvus-regex-ecma262 UTF-16",
              "foundation": "NSRegularExpression", "swift": "Swift Regex", "v8": "V8"]

func shell(_ command: String) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", command]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
    return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
}

func loadText(_ file: String) -> String {
    let plainName = file.hasSuffix(".gz") ? String(file.dropLast(3)) : file
    if let plain = ProcessInfo.processInfo.environment["CORVUS_REGEX_PLAIN"],
       let s = try? String(contentsOfFile: "\(plain)/\(plainName)", encoding: .utf8) {
        return s
    }
    let dir = ProcessInfo.processInfo.environment["CORVUS_REGEX_TEXTS"]
        ?? "\(NSHomeDirectory())/.local/share/corvus-regex-benchmarks"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", "gzip -dc '\(dir)/\(file)'"]
    let pipe = Pipe()
    p.standardOutput = pipe
    try! p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    var s = String(decoding: data, as: UTF8.self)
    if s.hasPrefix("\u{FEFF}") { s.removeFirst() }
    return s
}

func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

// Warms, then times passes: the median, the fastest and the slowest pass in nanoseconds per count, the count, and the
// counts timed.
func measure(_ seconds: Double, _ passes: Int, _ count: () throws -> Int) throws -> (Double, Double, Double, Int, Int) {
    let expected = try count()
    let warmEnd = now() + UInt64(seconds * 0.4 * 1e9)
    var reps = 0
    while now() < warmEnd {
        if try count() != expected { throw NSError(domain: "the count changed", code: 1) }
        reps += 1
    }
    let perPass = max(1, Int((Double(reps) * 0.6 / Double(passes)).rounded()))
    var times: [Double] = []
    for _ in 0..<passes {
        let t0 = now()
        for _ in 0..<perPass { _ = try count() }
        times.append(Double(now() - t0) / Double(perPass))
    }
    times.sort()
    return (times[passes / 2], times[0], times[passes - 1], expected, perPass * passes)
}

func one(_ path: String, _ index: Int, _ engine: String, _ seconds: Double, _ passes: Int) -> [String: Any] {
    let workloads = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [[String: Any]]
    guard index < workloads.count else { return ["error": "no workload \(index)"] }
    let w = workloads[index]
    let pattern = w["pattern"] as! String, flags = w["flags"] as! String
    let text = loadText(w["file"] as! String)
    do {
        let count: () throws -> Int
        switch engine {
        case "corvus-utf8", "corvus-utf16":
            let re = try CorvusRegexEcma262.Regex(pattern, flags: flags.contains("u") || flags.contains("v") ? flags : flags + "u")
            if engine == "corvus-utf8" {
                count = { try re.matchCount(in: text) }
            } else {
                let units = Array(text.utf16)
                count = { try re.matchCount(utf16: units) }
            }
        case "foundation":
            var options: NSRegularExpression.Options = []
            if flags.contains("i") { options.insert(.caseInsensitive) }
            if flags.contains("m") { options.insert(.anchorsMatchLines) }
            if flags.contains("s") { options.insert(.dotMatchesLineSeparators) }
            let re = try NSRegularExpression(pattern: pattern, options: options)
            let range = NSRange(location: 0, length: (text as NSString).length)
            count = { re.numberOfMatches(in: text, range: range) }
        case "swift":
            if #available(macOS 13, *) {
                var re = try _StringProcessing.Regex<AnyRegexOutput>(pattern)
                if flags.contains("i") { re = re.ignoresCase() }
                if flags.contains("m") { re = re.anchorsMatchLineEndings() }
                if flags.contains("s") { re = re.dotMatchesNewlines() }
                let compiled = re
                count = { text.matches(of: compiled).count }
            } else {
                return ["error": "Swift Regex needs macOS 13"]
            }
        default:
            return ["error": "unknown engine \(engine)"]
        }
        let (median, low, high, expected, reps) = try measure(seconds, passes, count)
        return ["median": (median * 10).rounded() / 10, "min": (low * 10).rounded() / 10, "max": (high * 10).rounded() / 10,
                "count": expected, "reps": reps]
    } catch {
        return ["error": "\(error)"]
    }
}

// A figure stopped at the limit, which the page shows as giving no result within 30 s.
let stopped: [String: Any] = ["error": "did not produce a result within 30 s", "limit": 30]

func isStopped(_ line: [String: Any]?) -> Bool { (line?["limit"] as? Int) == 30 }

// One figure in a child process: the child's line of JSON, or one with the error.
func figure(_ v8: String?, _ path: String, _ index: Int, _ spec: String, _ seconds: String, _ passes: String) -> [String: Any] {
    let parts = spec.split(separator: "@", maxSplits: 1).map(String.init)
    let engine = parts[0]
    let p = Process()
    if engine == "v8" {
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["node", v8 ?? "", "--one", path, String(index), seconds, passes]
    } else {
        p.executableURL = URL(fileURLWithPath: parts.count > 1 ? parts[1] : CommandLine.arguments[0])
        p.arguments = ["--one", path, String(index), engine, seconds, passes]
    }
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return ["error": "\(error)"] }
    // The child's output, read on another thread so that the wait can time out; the semaphore orders the write
    // before the read.
    final class Output: @unchecked Sendable { var data = Data() }
    let output = Output()
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        output.data = pipe.fileHandleForReading.readDataToEndOfFile()
        done.signal()
    }
    if done.wait(timeout: .now() + 30) == .timedOut {
        p.terminate()
        kill(p.processIdentifier, SIGKILL)
        return stopped
    }
    p.waitUntilExit()
    guard let line = String(decoding: output.data, as: UTF8.self).split(separator: "\n").last,
          let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
        return ["error": "the process ended without figures"]
    }
    return object
}

func field(_ path: String, _ prefix: String) -> String {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }
    for line in text.split(separator: "\n") where line.hasPrefix(prefix) {
        return line.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }
    return ""
}

let args = CommandLine.arguments
if args.count > 1 && args[1] == "--one" {
    let result = one(args[2], Int(args[3])!, args[4], Double(args[5])!, Int(args[6])!)
    print(String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self))
    exit(0)
}
let path = args[1]
var opts = ["rounds": "3", "seconds": "0.7", "passes": "7", "spread": "0.05"]
var i = 2
while i + 1 < args.count {
    opts[String(args[i].drop(while: { $0 == "-" }))] = args[i + 1]
    i += 2
}
let engines = opts["engines"].map { $0.split(separator: ",").map(String.init) }
    ?? ["corvus-utf8", "corvus-utf16", "foundation", "swift"] + (opts["v8"] != nil ? ["v8"] : [])
let rounds = Int(opts["rounds"]!)!
let limit = Double(opts["spread"]!)!
let workloads = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [[String: Any]]
let chosen = workloads.indices.filter { opts["filter"] == nil || (workloads[$0]["id"] as! String).contains(opts["filter"]!) }

// The texts unzipped once, for every child.
let plain = NSTemporaryDirectory() + "corvus-regex-texts-swift-\(getpid())"
try FileManager.default.createDirectory(atPath: plain, withIntermediateDirectories: true)
for w in workloads {
    let file = w["file"] as! String
    let target = "\(plain)/\(file.hasSuffix(".gz") ? String(file.dropLast(3)) : file)"
    if !FileManager.default.fileExists(atPath: target) { try loadText(file).write(toFile: target, atomically: true, encoding: .utf8) }
}
setenv("CORVUS_REGEX_PLAIN", plain, 1)

var figures: [String: [Int: (each: [Double], line: [String: Any])]] = [:]
var v8Engine = ""
for (c, k) in chosen.enumerated() {
    for round in 0..<rounds {
        for turn in 0..<engines.count {
            let e = engines[(turn + round) % engines.count]
            // A figure stopped at the limit in an earlier round is not run again.
            if isStopped(figures[e]?[k]?.line) { continue }
            let line = figure(opts["v8"], path, k, e, opts["seconds"]!, opts["passes"]!)
            var fig = figures[e, default: [:]][k] ?? (each: [], line: line)
            fig.line = line
            if let m = line["median"] as? Double { fig.each.append(m) } else {
                FileHandle.standardError.write("\(e) \(workloads[k]["id"]!) \(line)\n".data(using: .utf8)!)
            }
            figures[e, default: [:]][k] = fig
            if e == "v8", let name = line["engine"] as? String { v8Engine = name }
        }
    }
    FileHandle.standardError.write("workload \(c + 1) of \(chosen.count) done\n".data(using: .utf8)!)
}
try? FileManager.default.removeItem(atPath: plain)

var over: [String] = [], differ: [String] = []
var results: [String: [String: Any]] = [:]
for e in engines {
    var rows: [String: Any] = [:]
    for k in chosen {
        let wid = workloads[k]["id"] as! String
        let fig = figures[e]?[k] ?? (each: [], line: [:])
        if fig.each.count < rounds {
            // A round with no figure (an error, a limit) makes the figure an error.
            rows[wid] = fig.line["error"] != nil ? fig.line : ["error": "a round gave no figure"]
            continue
        }
        let sorted = fig.each.sorted()
        let n = sorted.count
        let m = n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2
        let spread = m > 0 ? (sorted[n - 1] - sorted[0]) / m : 0
        if spread > limit {
            over.append(String(format: "%@ %@ %.1f%%", e, wid, spread * 100))
            FileHandle.standardError.write(String(format: "SPREAD %@ %@ %.1f%%\n", e, wid, spread * 100).data(using: .utf8)!)
        }
        let count = fig.line["count"] as? Int
        var entry: [String: Any] = ["median": (m * 10).rounded() / 10, "min": sorted[0], "max": sorted[n - 1],
                                    "count": count as Any, "rounds": n, "spread": (spread * 10000).rounded() / 10000, "each": fig.each]
        // Without V8 in the run (V8=0), its count as the workloads carry it (v8Count, from the central run).
        let oracle = figures["v8"] != nil ? figures["v8"]?[k]?.line["count"] as? Int : workloads[k]["v8Count"] as? Int
        if let oracle, let count, count != oracle, e != "v8" {
            differ.append("\(e) \(wid) \(count) vs V8 \(oracle)")
            FileHandle.standardError.write("COUNT  \(e) \(wid) \(count) against V8's \(oracle)\n".data(using: .utf8)!)
            if notECMA262.contains(e) {
                entry["differs"] = "\(labels[e]!) \(count), V8 \(oracle)"
            } else {
                entry = ["error": "counted \(count) where V8 counts \(oracle)"]
            }
        }
        rows[wid] = entry
    }
    results[e] = rows
}
let facts: [String: String] = [
    "cpu": field("/proc/cpuinfo", "model name"),
    "cores": String(ProcessInfo.processInfo.activeProcessorCount),
    "affinity": field("/proc/self/status", "Cpus_allowed_list"),
    "os": shell("uname -sr"),
    "load": shell("cut -d' ' -f1 /proc/loadavg"),
    "swift": shell("swift --version 2>&1 | head -1"),
    "commit": ProcessInfo.processInfo.environment["CORVUS_COMMIT"].flatMap { $0.isEmpty ? nil : $0 } ?? shell("git rev-parse HEAD"),
    "date": ISO8601DateFormatter().string(from: Date()),
    "seconds": opts["seconds"]!, "passes": opts["passes"]!,
    "runner": ProcessInfo.processInfo.environment["RUNNER_NAME"] ?? "",
    "runner_os": ProcessInfo.processInfo.environment["RUNNER_OS"] ?? "",
    "image": [ProcessInfo.processInfo.environment["ImageOS"], ProcessInfo.processInfo.environment["ImageVersion"]].compactMap { $0 }.joined(separator: " "),
    "corvus-regex-ecma262": libraryVersion,
    "rounds": String(rounds), "protocol": "interleaved", "spread_limit": String(limit),
    "spread_over": over.joined(separator: "; "), "counts_differ": differ.joined(separator: "; "), "v8": v8Engine,
]
let data = try JSONSerialization.data(withJSONObject: ["facts": facts, "end": ISO8601DateFormatter().string(from: Date()), "results": results])
if let out = opts["out"] { try data.write(to: URL(fileURLWithPath: out)) } else { print(String(decoding: data, as: UTF8.self)) }
