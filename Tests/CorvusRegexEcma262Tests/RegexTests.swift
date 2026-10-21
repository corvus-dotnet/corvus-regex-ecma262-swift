// The package's tests: each member over String and [UInt16] text, against the answers V8 gives.
import CorvusRegexEcma262
import XCTest

final class RegexTests: XCTestCase {
    func u16(_ s: String) -> [UInt16] { Array(s.utf16) }

    func testCompiling() throws {
        let r = try Regex(#"(?<year>\d{4})-(?<month>\d{2})"#, flags: "gu")
        XCTAssertEqual(r.source, #"(?<year>\d{4})-(?<month>\d{2})"#)
        XCTAssertEqual(r.flags, "gu")
        XCTAssertEqual(r.groupCount, 2)
        XCTAssertEqual(r.groupNames, ["year", "month"])
        XCTAssertEqual(try Regex("a", flags: "yig").flags, "giy")
        XCTAssertTrue(Regex.isValid("a+", flags: "u"))
        XCTAssertFalse(Regex.isValid("a{2,1}", flags: "u"))
        // Annex B reads {2,1 as text without u.
        XCTAssertTrue(Regex.isValid("a{2,1"))
    }

    func testErrors() {
        func kind(_ f: () throws -> Void) -> RegexError.Kind? {
            do { try f() } catch let e as RegexError { return e.kind } catch { return nil }
            return nil
        }
        XCTAssertEqual(kind { _ = try Regex("(") }, .invalidPattern)
        XCTAssertEqual(kind { _ = try Regex(#"\p{Nope}"#, flags: "u") }, .invalidPattern)
        XCTAssertEqual(kind { _ = try Regex("a", flags: "uv") }, .invalidFlags)
        XCTAssertEqual(kind { _ = try Regex(String(repeating: "(", count: 1001) + String(repeating: ")", count: 1001)) }, .patternTooLarge)
    }

    func testFirstMatch() throws {
        let r = try Regex("o+")
        XCTAssertTrue(try r.test("foo"))
        XCTAssertFalse(try r.test("bar"))
        let text = "a foo, a boo"
        let m = try XCTUnwrap(try r.firstMatch(in: text, from: text.utf8.index(text.startIndex, offsetBy: 3)))
        XCTAssertEqual(m.value, "oo")
        XCTAssertEqual(m.utf8Ranges[0], 3..<5)
        XCTAssertNil(try r.firstMatch(in: "a foo", from: "a foo".endIndex))
        // The y flag: a match starts where the search starts.
        let sticky = try Regex("o", flags: "y")
        XCTAssertTrue(try sticky.test("foo", from: "foo".index(after: "foo".startIndex)))
        XCTAssertFalse(try sticky.test("foo"))
        // Ranges are String.Index; UTF-8 ranges beside them.
        let cafe = try XCTUnwrap(try Regex("ok").firstMatch(in: "café ok"))
        XCTAssertEqual(cafe.utf8Ranges[0], 6..<8)
        XCTAssertEqual("café ok"[cafe.range], "ok")
    }

    func testHalfCharacters() throws {
        // Without u a character beyond the Basic Multilingual Plane is two code units, and . takes one: the UTF-8
        // range ends at the character's third byte, and the String range is the whole character's.
        let m = try XCTUnwrap(try Regex("^.").firstMatch(in: "😀x"))
        XCTAssertEqual(m.utf8Ranges[0], 0..<2)
        XCTAssertEqual(m.value, "😀")
        XCTAssertEqual(try XCTUnwrap(try Regex("^.", flags: "u").firstMatch(in: "😀x")).utf8Ranges[0], 0..<4)
    }

    func testUTF16() throws {
        let r = try Regex("o+")
        let m = try XCTUnwrap(try r.firstMatch(utf16: u16("a foo")))
        XCTAssertEqual(m.range, 3..<5)
        let lone: [UInt16] = [0x61, 0xD800, 0x62]
        XCTAssertTrue(try Regex("^...$").test(utf16: lone))
        XCTAssertTrue(try Regex("^...$", flags: "u").test(utf16: lone))
        XCTAssertEqual(try Regex(#"\ud800"#).firstMatch(utf16: lone)?.range, 1..<2)
        XCTAssertTrue(try Regex("^..$").test(utf16: u16("😀")))
        XCTAssertTrue(try Regex("^.$", flags: "u").test(utf16: u16("😀")))
    }

    func testGroups() throws {
        let r = try Regex(#"(?<year>\d{4})-(?<month>\d{2})(-(\d{2}))?"#, flags: "u")
        let m = try XCTUnwrap(try r.firstMatch(in: "due 2026-10, then"))
        XCTAssertEqual(m.count, 5)
        XCTAssertEqual(m[0], "2026-10")
        XCTAssertEqual(m["year"], "2026")
        XCTAssertEqual(m[2], "10")
        XCTAssertNil(m[3])
        XCTAssertNil(m["nope"])
        XCTAssertNil(m[9])
        XCTAssertEqual(try Regex("(?<d>a)|(?<d>b)", flags: "u").firstMatch(in: "b")?["d"], "b")
        let m16 = try XCTUnwrap(try r.firstMatch(utf16: u16("on 2027-01-31")))
        XCTAssertEqual(m16["month"].map(Array.init), u16("01"))
        XCTAssertEqual(m16.range(4), 11..<13)
    }

    func testMatches() throws {
        let r = try Regex(#"\d+"#, flags: "g")
        XCTAssertEqual(try r.matches(in: "1 22 333 4444").map { String($0.value) }, ["1", "22", "333", "4444"])
        XCTAssertEqual(try Regex("a", flags: "g").matchCount(in: String(repeating: "a ", count: 1000)), 1000)
        XCTAssertEqual(try Regex("a", flags: "g").matchCount(utf16: u16(String(repeating: "a ", count: 1000))), 1000)
        XCTAssertEqual(try Regex("", flags: "gu").matches(in: "😀").count, 2)
        XCTAssertEqual(try Regex("", flags: "g").matches(utf16: u16("😀")).count, 3)
        XCTAssertEqual(try Regex("a", flags: "gy").matches(in: "aab").count, 2)
        XCTAssertEqual(try Regex("a", flags: "gy").matches(in: "baa").count, 0)
        XCTAssertEqual(try r.matches(utf16: u16("x1y22z333")).map(\.range), [1..<2, 3..<5, 6..<9])
    }

    func testReplace() throws {
        let date = try Regex(#"(?<y>\d{4})-(?<m>\d{2})"#, flags: "g")
        XCTAssertEqual(try date.replace(in: "2026-10, 2027-01", with: "$<m>/$1"), "10/2026, 01/2027")
        let first = try Regex(#"\d+"#)
        XCTAssertEqual(try first.replace(in: "1 2 3", with: "[$&]"), "[1] 2 3")
        XCTAssertEqual(try first.replaceAll(in: "1 2 3", with: "[$&]"), "[1] [2] [3]")
        XCTAssertEqual(try first.replace(in: "a1b", with: "<$`|$'|$$>"), "a<a|b|$>b")
        XCTAssertEqual(try first.replaceAll(in: "1 2 3") { String(Int($0.value)! * 2) }, "2 4 6")
        XCTAssertEqual(try first.replace(utf16: u16("a1b"), with: u16("<$&>")), u16("a<1>b"))
        XCTAssertEqual(try Regex("^.").replace(in: "😀", with: "x"), "x\u{FFFD}")
    }

    func testSplit() throws {
        let comma = try Regex(#"\s*(;)\s*"#)
        XCTAssertEqual(try comma.split("a ; b;c"), ["a", ";", "b", ";", "c"])
        XCTAssertEqual(try comma.split("a;b;c", limit: 2), ["a", ";"])
        XCTAssertEqual(try Regex("(x)?,").split("a,b"), ["a", nil, "b"])
        XCTAssertEqual(try comma.split(utf16: u16("a;b")), [u16("a"), u16(";"), u16("b")])
    }

    func testLimits() throws {
        let slow = try Regex(#"^(a+)+\1$"#)
        let text = String(repeating: "a", count: 64) + "!"
        XCTAssertThrowsError(try slow.test(text, timeout: 0.005)) { XCTAssertEqual(($0 as? RegexError)?.kind, .matchLimit) }
        XCTAssertFalse(try Regex(#"^(a+)+$"#).test(text, timeout: 1))
    }

    // The README's example, as it is written there.
    func testReadme() throws {
        let date = try Regex(#"(?<year>\d{4})-(?<month>\d{2})"#, flags: "gu")
        XCTAssertTrue(try date.test("due 2026-10"))
        let m = try XCTUnwrap(try date.firstMatch(in: "due 2026-10"))
        XCTAssertEqual(m["year"], "2026")
        XCTAssertEqual(m.utf8Ranges[0], 4..<11)
        XCTAssertEqual(try date.matches(in: "2026-10, 2027-01").map(\.value), ["2026-10", "2027-01"])
        XCTAssertEqual(try date.replace(in: "2026-10, 2027-01", with: "$<month>/$1"), "10/2026, 01/2027")
        XCTAssertEqual(try date.replace(in: "2026-10") { String($0["month"]!) }, "10")
        XCTAssertEqual(try Regex(#"\s*(;)\s*"#).split("a ; b;c"), ["a", ";", "b", ";", "c"])
    }

    func testVersion() {
        XCTAssertEqual(libraryVersion.split(separator: ".").count, 3)
    }
}
