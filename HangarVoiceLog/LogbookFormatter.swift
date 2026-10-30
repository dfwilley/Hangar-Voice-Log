import Foundation

/// Turns an entry into draft logbook text and spreadsheet (CSV) rows.
enum LogbookFormatter {

    /// Dates are written out in full, for example "October 30, 2026".
    static func longDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
    }

    /// Tidies spoken text: trims spaces, capitalizes the first letter, ends with a period.
    static func cleanDescription(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Collapse runs of spaces left behind by dictation.
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        guard let first = result.first else { return "" }
        result = first.uppercased() + result.dropFirst()
        if let last = result.last, !".!?".contains(last) {
            result += "."
        }
        return result
    }

    static func draft(for entry: LogEntry, tail: String, timeZone: TimeZone = .current) -> String {
        var lines: [String] = []
        lines.append("\(tail) — \(entry.category.label)")
        lines.append("Date: \(longDate(entry.workDate, timeZone: timeZone))")

        var times: [String] = []
        let tach = entry.tach.trimmingCharacters(in: .whitespaces)
        let hobbs = entry.hobbs.trimmingCharacters(in: .whitespaces)
        if !tach.isEmpty { times.append("Tach: \(tach)") }
        if !hobbs.isEmpty { times.append("Hobbs: \(hobbs)") }
        if !times.isEmpty { lines.append(times.joined(separator: "    ")) }

        lines.append("")
        let description = cleanDescription(entry.details)
        lines.append(description.isEmpty ? "(Describe the work performed.)" : description)
        lines.append("")
        lines.append("Signature: ______________________   Certificate No.: ____________")
        return lines.joined(separator: "\n")
    }

    // MARK: - Spreadsheet export

    static let csvHeader = "Date,Tail,Category,Tach,Hobbs,Description,Photos"

    static func csvField(_ value: String) -> String {
        let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuotes ? "\"\(escaped)\"" : escaped
    }

    static func csv(for entries: [LogEntry], tail: String, timeZone: TimeZone = .current) -> String {
        var rows = [csvHeader]
        for entry in entries.sorted(by: { $0.workDate < $1.workDate }) {
            let fields = [
                longDate(entry.workDate, timeZone: timeZone),
                tail,
                entry.category.label,
                entry.tach.trimmingCharacters(in: .whitespaces),
                entry.hobbs.trimmingCharacters(in: .whitespaces),
                cleanDescription(entry.details),
                String(entry.photoFileNames.count)
            ]
            rows.append(fields.map(csvField).joined(separator: ","))
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }
}
