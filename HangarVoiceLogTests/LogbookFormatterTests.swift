import XCTest
import UIKit
@testable import HangarVoiceLog

final class LogbookFormatterTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    // MARK: Dates and numbers

    func testDatesAreWrittenOut() {
        XCTAssertEqual(LogbookFormatter.longDate(date(2026, 10, 30), timeZone: utc), "October 30, 2026")
        XCTAssertEqual(LogbookFormatter.longDate(isoDay: "2026-08-25"), "August 25, 2026")
        XCTAssertEqual(LogbookFormatter.dayString(date(2026, 8, 5), timeZone: utc), "2026-08-05")
    }

    func testHobbsShowsOneDecimal() {
        XCTAssertEqual(LogbookFormatter.hobbs(13.3), "13.3")
        XCTAssertEqual(LogbookFormatter.hobbs(14), "14.0")
    }

    func testBlanksAreDetected() {
        XCTAssertTrue(LogbookFormatter.hasBlanks("Compression #1 [ ]/80"))
        XCTAssertTrue(LogbookFormatter.hasBlanks("Installed [oil filter P/N]"))
        XCTAssertFalse(LogbookFormatter.hasBlanks("Lubed propeller with 1 oz Aeroshell #6."))
    }

    // MARK: Access import file

    func testImportLineMatchesAccessFormat() {
        var entry = LogEntry()
        entry.workDate = date(2026, 10, 30)
        entry.hobbs = " 14.2 "
        entry.laborHours = "1.0"
        entry.equipmentIds = [122, 124]
        entry.performedById = 1
        entry.recurringId = 3
        entry.text = "Oil and filter change.\tFilled with 6 qts.\r\nGround run - no leaks.\n"

        let line = LogbookFormatter.importLine(for: entry, timeZone: utc)
        let fields = line.components(separatedBy: "\t")

        XCTAssertEqual(fields.count, 8)
        XCTAssertEqual(fields[0], "2026-10-30")
        XCTAssertEqual(fields[1], "14.2")
        XCTAssertEqual(fields[2], "1")
        XCTAssertEqual(fields[3], "122,124")
        XCTAssertEqual(fields[4], "1")
        XCTAssertEqual(fields[5], "3")
        XCTAssertEqual(fields[6], "0")
        XCTAssertEqual(fields[7], "Oil and filter change. Filled with 6 qts.\\nGround run - no leaks.")
    }

    func testImportLineForJobWithoutTemplate() {
        var entry = LogEntry()
        entry.workDate = date(2026, 10, 30)
        entry.hobbs = "15"
        entry.text = "Replaced canopy latch spring."
        let fields = LogbookFormatter.importLine(for: entry, timeZone: utc).components(separatedBy: "\t")
        XCTAssertEqual(fields[1], "15")
        XCTAssertEqual(fields[2], "")
        XCTAssertEqual(fields[3], "")
        XCTAssertEqual(fields[5], "0")
    }

    func testNewImportFileGetsHeader() {
        let text = LogbookFormatter.appendingImportLines(["a\tb"], to: nil)
        XCTAssertEqual(text, LogbookFormatter.importHeader + "\r\na\tb\r\n")
    }

    func testExistingImportFileKeepsLines() {
        let existing = LogbookFormatter.importHeader + "\nfirst\tline\n"
        let text = LogbookFormatter.appendingImportLines(["second\tline"], to: existing)
        XCTAssertEqual(text, LogbookFormatter.importHeader + "\r\nfirst\tline\r\nsecond\tline\r\n")
    }

    // MARK: Data file from Access

    func testDataFileDecodes() throws {
        let json = """
        {
          "schema": 1,
          "generatedAt": "2026-10-30T13:00:00Z",
          "source": "Maintenance Record_be.accdb",
          "lastHobbs": {"value": 13.3, "date": "2026-08-25", "logId": 769},
          "maintainers": [{"id": 1, "name": "Dale Willey, Owner", "ap": false}],
          "jobs": [{"recurringId": 3, "name": "Oil Change", "entry": "Oil and filter change.", "laborHours": 1.0, "equipmentIds": [12]}]
        }
        """
        let data = try HangarData.decode(Data(json.utf8))
        XCTAssertEqual(data.lastHobbs?.value, 13.3)
        XCTAssertEqual(data.jobs.first?.equipmentIds, [12])
        XCTAssertEqual(HangarData.chipName(for: data.jobs[0]), "Oil change")
    }

    func testBuiltInCopyHasStandardJobs() {
        let names = HangarData.builtIn.jobs.map(HangarData.chipName(for:))
        XCTAssertTrue(names.contains("Oil change"))
        XCTAssertTrue(names.contains("Prop lube"))
        XCTAssertTrue(names.contains("Pitot-static check"))
        XCTAssertEqual(HangarData.builtIn.lastHobbs?.value, 13.3)
    }

    func testLastHobbsUsesHighestReading() {
        let access = HangarData.LastHobbs(value: 13.3, date: "2026-08-25", logId: 769)
        var older = LogEntry()
        older.hobbs = "12.0"
        XCTAssertEqual(EntryStore.lastHobbs(access: access, entries: [older])?.value, 13.3)
        XCTAssertEqual(EntryStore.lastHobbs(access: access, entries: [older])?.fromAccess, true)

        var newer = LogEntry()
        newer.hobbs = "15.4"
        let reading = EntryStore.lastHobbs(access: access, entries: [older, newer])
        XCTAssertEqual(reading?.value, 15.4)
        XCTAssertEqual(reading?.fromAccess, false)

        XCTAssertNil(EntryStore.lastHobbs(access: nil, entries: []))
    }

    func testEntryRoundTripsThroughJSON() throws {
        var entry = LogEntry()
        entry.hobbs = "100.0"
        entry.equipmentIds = [5]
        entry.status = .sent
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LogEntry.self, from: encoder.encode(entry))
        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.equipmentIds, [5])
        XCTAssertEqual(decoded.status, .sent)
    }

    func testFontsAreBundled() {
        let names = ["BarlowCondensed-Bold", "Barlow-Regular", "Barlow-SemiBold", "IBMPlexMono-Medium"]
        for name in names {
            XCTAssertNotNil(UIFont(name: name, size: 17), "\(name) did not load")
        }
    }
}
