import Foundation

/// Text formatting rules shared by the screens and the Access import file.
enum LogbookFormatter {

    /// Dates written out in full, for example "October 30, 2026".
    static func longDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
    }

    /// "2026-08-25" → "August 25, 2026"
    static func longDate(isoDay: String) -> String {
        guard let date = dayDate(isoDay) else { return isoDay }
        return longDate(date, timeZone: TimeZone(identifier: "UTC")!)
    }

    static func dayString(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func dayDate(_ isoDay: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: isoDay)
    }

    /// One decimal place, as the Hobbs meter reads.
    static func hobbs(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    /// True if the text still has a blank to fill in, like "[ ]" or "[oil filter P/N]".
    static func hasBlanks(_ text: String) -> Bool {
        text.range(of: #"\[[^\]]*\]"#, options: .regularExpression) != nil
    }

    // MARK: Access import file

    static let importFileName = "Claude Logbook Import.txt"
    static let importHeader = "Date\tHobbs\tTimeRequired\tEquipmentIDs\tPerformedByIDs\tRecurringID\tSBID\tEntry"

    /// One tab-delimited line for ImportClaudeLogbookEntries.
    static func importLine(for entry: LogEntry, timeZone: TimeZone = .current) -> String {
        let text = entry.text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: "\\n")
        let hobbs = number(entry.hobbs).map { trimNumber($0) } ?? ""
        let labor = number(entry.laborHours).map { trimNumber($0) } ?? ""
        let fields = [
            dayString(entry.workDate, timeZone: timeZone),
            hobbs,
            labor,
            entry.equipmentIds.map(String.init).joined(separator: ","),
            String(entry.performedById),
            String(entry.recurringId),
            "0",
            text
        ]
        return fields.joined(separator: "\t")
    }

    /// The import file's new contents after adding lines: header first if the
    /// file is new, existing lines kept, CRLF line endings for Windows.
    static func appendingImportLines(_ lines: [String], to existing: String?) -> String {
        var body = (existing ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if body.hasPrefix("\u{FEFF}") { body.removeFirst() }
        var rows = body.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if rows.first != importHeader {
            rows.insert(importHeader, at: 0)
        }
        rows.append(contentsOf: lines)
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    private static func trimNumber(_ value: Double) -> String {
        let text = String(format: "%.2f", value)
        var trimmed = text
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed
    }
}
