import Foundation

enum EntryCategory: String, Codable, CaseIterable, Identifiable {
    case maintenance
    case inspection
    case repair
    case alteration
    case squawk
    case note

    var id: String { rawValue }

    var label: String {
        switch self {
        case .maintenance: return "Maintenance"
        case .inspection: return "Inspection"
        case .repair: return "Repair"
        case .alteration: return "Alteration"
        case .squawk: return "Squawk"
        case .note: return "Note"
        }
    }
}

struct LogEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var created = Date()
    var workDate = Date()
    var tach = ""
    var hobbs = ""
    var category: EntryCategory = .maintenance
    /// The words describing the work. Starts as the voice transcript and can be edited.
    var details = ""
    var audioFileName: String?
    var photoFileNames: [String] = []

    var summaryLine: String {
        let firstLine = details
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return firstLine.isEmpty ? "(no description yet)" : firstLine
    }
}
