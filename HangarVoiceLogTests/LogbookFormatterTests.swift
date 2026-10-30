import XCTest
@testable import HangarVoiceLog

final class LogbookFormatterTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func testLongDateIsWrittenOut() {
        XCTAssertEqual(LogbookFormatter.longDate(date(2026, 10, 30), timeZone: utc), "October 30, 2026")
    }

    func testCleanDescription() {
        XCTAssertEqual(LogbookFormatter.cleanDescription("  changed oil and  filter "), "Changed oil and filter.")
        XCTAssertEqual(LogbookFormatter.cleanDescription("Torqued wheel nuts!"), "Torqued wheel nuts!")
        XCTAssertEqual(LogbookFormatter.cleanDescription("   "), "")
    }

    func testDraftIncludesTailDateTachAndSignatureLine() {
        var entry = LogEntry()
        entry.workDate = date(2026, 10, 30)
        entry.tach = " 512.3 "
        entry.category = .maintenance
        entry.details = "changed oil and filter, no metal found"

        let draft = LogbookFormatter.draft(for: entry, tail: "N721NE", timeZone: utc)

        XCTAssertTrue(draft.hasPrefix("N721NE — Maintenance\nDate: October 30, 2026\nTach: 512.3\n"))
        XCTAssertTrue(draft.contains("Changed oil and filter, no metal found."))
        XCTAssertFalse(draft.contains("Hobbs"))
        XCTAssertTrue(draft.contains("Signature:"))
    }

    func testDraftWithEmptyDescriptionShowsPrompt() {
        let draft = LogbookFormatter.draft(for: LogEntry(), tail: "N721NE", timeZone: utc)
        XCTAssertTrue(draft.contains("(Describe the work performed.)"))
    }

    func testCSVQuotesCommasQuotesAndLineBreaks() {
        XCTAssertEqual(LogbookFormatter.csvField("plain"), "plain")
        XCTAssertEqual(LogbookFormatter.csvField("a, b"), "\"a, b\"")
        XCTAssertEqual(LogbookFormatter.csvField("said \"ok\""), "\"said \"\"ok\"\"\"")
        XCTAssertEqual(LogbookFormatter.csvField("line1\nline2"), "\"line1\nline2\"")
    }

    func testCSVRowsAreOldestFirst() {
        var newer = LogEntry()
        newer.workDate = date(2026, 10, 30)
        newer.details = "second"
        var older = LogEntry()
        older.workDate = date(2026, 9, 1)
        older.details = "first, with comma"
        older.photoFileNames = ["a.jpg", "b.jpg"]

        let lines = LogbookFormatter.csv(for: [newer, older], tail: "N721NE", timeZone: utc)
            .components(separatedBy: "\r\n")

        XCTAssertEqual(lines[0], LogbookFormatter.csvHeader)
        XCTAssertEqual(lines[1], "\"September 1, 2026\",N721NE,Maintenance,,,\"First, with comma.\",2")
        XCTAssertEqual(lines[2], "\"October 30, 2026\",N721NE,Maintenance,,,Second.,0")
    }

    func testEntryRoundTripsThroughJSON() throws {
        var entry = LogEntry()
        entry.tach = "100.0"
        entry.audioFileName = "voice.m4a"
        entry.photoFileNames = ["p.jpg"]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LogEntry.self, from: encoder.encode(entry))
        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.tach, "100.0")
        XCTAssertEqual(decoded.photoFileNames, ["p.jpg"])
    }
}
